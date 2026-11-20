import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/jarvis_service.dart';
import 'avatar_perf.dart';
import 'avatar_runtime.dart';
import 'avatar_settings_screen.dart';
import 'core/avatar_scene.dart';
import 'core/avatar_settings.dart';
import 'core/avatar_state_machine.dart';
import 'core/render_list.dart';
import 'serpent_guardian_painter.dart';

/// Serpent Guardian avatar — real-time procedural prototype.
///
/// Everything is rendered live every frame from 3D rigs (no video, no
/// sprite sheet). The humanoid and serpent geometry are PROCEDURAL
/// PLACEHOLDERS that exercise the engine until the approved rigged glTF
/// assets exist; the label on screen says so.
class SerpentGuardianView extends StatefulWidget {
  const SerpentGuardianView({
    super.key,
    this.phaseSource,
    this.phaseReader,
    this.soundReader,
    this.avatarId = serpentGuardianId,
    this.skipIntro = false,
    this.showPlaceholderLabel = true,
  });

  final Listenable? phaseSource;
  final JarvisPhase Function()? phaseReader;
  final double Function()? soundReader;
  final String avatarId;
  final bool skipIntro;
  final bool showPlaceholderLabel;

  @override
  State<SerpentGuardianView> createState() => SerpentGuardianViewState();
}

class SerpentGuardianViewState extends State<SerpentGuardianView> with SingleTickerProviderStateMixin {
  late final AvatarScene scene;
  late final Ticker _ticker;
  final _repaint = _Repaint();
  final perf = AvatarPerfMonitor();
  late final ValueNotifier<AvatarSettings> _settings;
  ui.Image? _sprite;
  Duration _last = Duration.zero;
  Duration _sincePaint = Duration.zero;
  AvatarState _lastState = AvatarState.intro;
  RenderList? _lastList;

  AvatarState get state => scene.machine.state;

  @override
  void initState() {
    super.initState();
    _settings = AvatarSettingsStore.listenable(widget.avatarId);
    scene = AvatarScene(settings: _settings.value, skipIntro: widget.skipIntro);
    scene.machine.onTransition = _onTransition;
    _settings.addListener(_onSettings);
    AvatarSettingsStore.load(widget.avatarId);
    avatarSpeechBus.addListener(_onSpeech);
    avatarCommandBus.addListener(_onCommand);
    _sprite = buildGlowSprite();
    _ticker = createTicker(_tick)..start();
    perf.attach();
    if (!widget.skipIntro && _settings.value.introSound) AvatarSound.play('intro');
  }

  void _onSettings() => scene.applySettings(_settings.value);

  void _onSpeech() {
    final cue = avatarSpeechBus.value;
    if (cue == null) return;
    scene.speak(cue.text, rate: cue.rate);
  }

  void _onCommand() {
    switch (avatarCommandBus.value) {
      case 'replay_intro':
        replayIntro();
      case 'close':
        close();
    }
  }

  void _onTransition(AvatarState from, AvatarState to) {
    if (to == AvatarState.intro && _settings.value.introSound) AvatarSound.play('intro');
    if (to == AvatarState.closing && _settings.value.outroSound) AvatarSound.play('outro');
  }

  /// Plays INTRO → MATERIALIZING again.
  void replayIntro() => scene.machine.replayIntro();

  /// Dissolves the avatar (CLOSING).
  void close() => scene.machine.request(AvatarState.closing);

  String _phaseName() {
    try {
      final p = widget.phaseReader?.call() ?? JarvisService.instance.phase;
      return p.name;
    } catch (_) {
      return 'idle';
    }
  }

  double _sound() {
    try {
      final v = widget.soundReader?.call() ?? JarvisService.instance.soundLevel;
      return v.isFinite ? v.clamp(0.0, 1.0).toDouble() : 0;
    } catch (_) {
      return 0;
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    final seconds = dt.inMicroseconds / 1e6;
    scene.update(seconds, phase: _phaseName(), micLevel: _sound());
    perf.onTick(elapsed);
    if (scene.machine.state != _lastState) {
      _lastState = scene.machine.state;
      if (mounted && _settings.value.showDebugStats) setState(() {});
    }
    // Battery mode: paint at most ~30 fps.
    _sincePaint += dt;
    final minFrame = Duration(microseconds: 1000000 ~/ scene.budget.targetFps - 2000);
    if (_sincePaint >= minFrame) {
      _sincePaint = Duration.zero;
      _repaint.ping();
    }
  }

  void _onBuilt(RenderList list, Duration cpu) {
    _lastList = list;
    perf.onFrameBuilt(cpu, list.triangleCount, list.particleCount);
  }

  @override
  void dispose() {
    _ticker.dispose();
    perf.detach();
    _settings.removeListener(_onSettings);
    avatarSpeechBus.removeListener(_onSpeech);
    avatarCommandBus.removeListener(_onCommand);
    _repaint.dispose();
    _sprite?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('serpent-guardian-view'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AvatarSettingsScreen(avatarId: widget.avatarId))),
      onDoubleTap: replayIntro,
      child: Stack(fit: StackFit.expand, children: [
        RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('serpent-guardian-canvas'),
            painter: SerpentGuardianPainter(scene: scene, sprite: () => _sprite, onBuilt: _onBuilt, repaint: _repaint),
            child: const SizedBox.expand(),
          ),
        ),
        if (widget.showPlaceholderLabel)
          const Positioned(
            left: 10,
            bottom: 6,
            child: IgnorePointer(
              child: Text('PROCEDURAL PLACEHOLDER · engine test · not the final model',
                  key: ValueKey('serpent-placeholder-label'),
                  style: TextStyle(color: Color(0x99B8FFE9), fontSize: 9, letterSpacing: 0.6)),
            ),
          ),
        ValueListenableBuilder<AvatarSettings>(
          valueListenable: _settings,
          builder: (context, s, _) => s.showDebugStats
              ? Positioned(top: 6, left: 8, child: IgnorePointer(child: _Stats(view: this)))
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _Stats extends StatefulWidget {
  const _Stats({required this.view});
  final SerpentGuardianViewState view;
  @override
  State<_Stats> createState() => _StatsState();
}

class _StatsState extends State<_Stats> {
  late final Ticker _t;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    _t = Ticker((_) {
      if (++_n % 30 == 0 && mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final s = v.perf.snapshot();
    final l = v._lastList;
    return Text(
      'STATE ${v.state.name.toUpperCase()}\n'
      'fps ${s.fps.toStringAsFixed(0)} · cpu ${s.cpuP50Ms.toStringAsFixed(1)}/${s.cpuP95Ms.toStringAsFixed(1)} ms\n'
      'raster p95 ${s.rasterP95Ms.toStringAsFixed(1)} ms\n'
      'tris ${l?.triangleCount ?? 0} · particles ${l?.particleCount ?? 0} · bolts ${v.scene.boltCount}\n'
      'mode ${v.scene.settings.performance.name}${kDebugMode ? ' · DEBUG BUILD' : ''}',
      style: const TextStyle(color: Color(0xCCB8FFE9), fontSize: 10, fontFamily: 'monospace'),
    );
  }
}
