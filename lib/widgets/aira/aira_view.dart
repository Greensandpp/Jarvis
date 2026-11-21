// ignore: deprecated_member_use
import '../../brain/visual_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'aira_models.dart';
import 'aira_painter.dart';

/// Live animated AIRA core. Owns a ticker that is automatically muted when the
/// widget is off-screen (TickerMode) or the app is backgrounded (Flutter stops
/// scheduling frames), so no animation runs while invisible.
class AiraCoreView extends StatefulWidget {
  const AiraCoreView({
    super.key,
    required this.model,
    required this.state,
    this.quality = AiraQuality.balanced,
    this.reduceMotion = false,
    this.brightness = 1,
    this.speed = 1,
    this.soundLevel,
    this.compact = false,
    this.interactive = true,
  });

  final AiraModel model;
  final AiraVisualState state;
  final AiraQuality quality;
  final bool reduceMotion;
  final double brightness;
  final double speed;
  final double Function()? soundLevel;
  final bool compact;
  final bool interactive;

  @override
  State<AiraCoreView> createState() => AiraCoreViewState();
}

class AiraCoreViewState extends State<AiraCoreView>
    with SingleTickerProviderStateMixin {
  final AiraFrame frame = AiraFrame();
  late final Ticker _ticker;
  late AiraCorePainter _painter;
  Duration _last = Duration.zero;
  Duration _lastPaint = Duration.zero;
  double _frameEma = 0;
  double _slowFor = 0;
  double _adaptive = 1;
  double _dragYaw = 0, _dragPitch = 0;

  /// Frames actually pushed to the painter (exposed for tests / diagnostics).
  int paintedFrames = 0;
  double get adaptiveDetail => _adaptive;

  @override
  void initState() {
    super.initState();
    _painter = AiraCorePainter(model: widget.model, frame: frame, compact: widget.compact);
    final p = widget.state.params;
    frame
      ..energy = p.energy
      ..spread = p.spread
      ..warmth = p.warmth
      ..state = widget.state
      ..stateAge = 99
      ..brightness = widget.brightness;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant AiraCoreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model || oldWidget.compact != widget.compact) {
      _painter = AiraCorePainter(model: widget.model, frame: frame, compact: widget.compact);
    }
    if (oldWidget.state != widget.state) {
      frame
        ..state = widget.state
        ..stateAge = 0;
    }
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, .1);
    _last = elapsed;
    final f = frame;
    // Smoothly approach the target state's parameters (≈350 ms).
    final p = widget.state.params;
    final k = (dt * 6).clamp(0.0, 1.0);
    f.energy += (p.energy - f.energy) * k;
    f.spread += (p.spread - f.spread) * k;
    f.warmth += (p.warmth - f.warmth) * k;
    f.brightness = widget.brightness;
    final motion = widget.reduceMotion ? .22 : 1.0;
    f.t += dt * p.speed * widget.speed * motion;
    f.clock += dt * (widget.reduceMotion ? .3 : 1.0);
    f.stateAge += dt;
    f.tapAge += dt;
    f.sound = (widget.soundLevel?.call() ?? 0).clamp(0.0, 1.0);
    // Gesture rotation eases back to rest.
    _dragYaw *= (1 - dt * .6);
    _dragPitch *= (1 - dt * .9);
    f.yaw = _dragYaw;
    f.pitch = _dragPitch;

    // Frame-rate cap per quality tier.
    final cap = widget.reduceMotion ? 24 : widget.quality.maxFps;
    final interval = Duration(microseconds: (1e6 / cap).round());
    if (elapsed - _lastPaint < interval - const Duration(milliseconds: 2)) return;
    final gap = (elapsed - _lastPaint).inMicroseconds / 1e6;
    _lastPaint = elapsed;
    // Adaptive detail: if we cannot sustain the cap, shed particles.
    _frameEma = _frameEma == 0 ? gap : _frameEma * .9 + gap * .1;
    if (_frameEma > 1.6 / cap) {
      _slowFor += gap;
      if (_slowFor > 2 && _adaptive > .45) {
        _adaptive -= .12;
        _slowFor = 0;
      }
    } else {
      _slowFor = 0;
    }
    f.detail = (widget.quality.detail * _adaptive * (widget.reduceMotion ? .7 : 1))
        .clamp(.2, 1.0);
    paintedFrames++;
    f.tick();
  }

  @override
  void dispose() {
    _ticker.dispose();
    frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = RepaintBoundary(
      child: CustomPaint(painter: _painter, isComplex: true, willChange: true,
          child: const SizedBox.expand()),
    );
    if (!widget.interactive) return paint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        _dragYaw = (_dragYaw + d.delta.dx * .01).clamp(-1.6, 1.6);
        _dragPitch = (_dragPitch + d.delta.dy * .008).clamp(-.8, .8);
      },
      onTapUp: (_) => frame.tapAge = 0,
      child: paint,
    );
  }
}

/// Full AIRA companion mode: live core, name/state header, scrollable live
/// model picker and per-model settings. Never talks to AI directly; it only
/// renders the shared JARVIS state supplied by [liveState].
class AiraModeView extends StatefulWidget {
  const AiraModeView({super.key, required this.liveState, this.soundLevel,
      this.developerControls = true});

  final ValueListenable<AiraVisualState> liveState;
  final double Function()? soundLevel;

  /// Manual state preview, the model gallery and the in-view header. The
  /// production main screen turns these off: state follows real events, and
  /// model choice lives in Appearance settings.
  final bool developerControls;

  @override
  State<AiraModeView> createState() => _AiraModeViewState();
}

class _AiraModeViewState extends State<AiraModeView> {
  AiraPreferences _prefs = AiraPreferences();
  AiraVisualState? _preview;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
    visualBus.addListener(_onVisualRequest);
  }

  void _reload() {
    AiraPreferences.load().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _loaded = true;
      });
    });
  }

  void _onVisualRequest() {
    if (visualBus.value?.airaModel != null) _reload();
  }

  @override
  void dispose() {
    visualBus.removeListener(_onVisualRequest);
    super.dispose();
  }

  void _update(void Function(AiraPreferences p) change) {
    setState(() => change(_prefs));
    _prefs.save();
  }

  @override
  Widget build(BuildContext context) {
    final systemReduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final reduce = _prefs.reduceMotion || systemReduce;
    return ValueListenableBuilder<AiraVisualState>(
      valueListenable: widget.liveState,
      builder: (context, live, _) {
        final state = widget.developerControls ? (_preview ?? live) : live;
        final m = _prefs.model;
        return LayoutBuilder(builder: (context, box) {
          final roomy = box.maxHeight >= 430;
          return ColoredBox(
            color: Colors.black,
            child: Stack(children: [
              Positioned.fill(
                child: AiraCoreView(
                  key: const ValueKey('aira-main-core'),
                  model: m,
                  state: state,
                  quality: _prefs.quality,
                  reduceMotion: reduce,
                  brightness: _prefs.brightnessOf(m),
                  speed: _prefs.speedOf(m),
                  soundLevel: widget.soundLevel,
                ),
              ),
              if (widget.developerControls) Positioned(
                top: 8, left: 14, right: 8,
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_prefs.assistantName.toUpperCase(),
                        key: const ValueKey('aira-name'),
                        style: TextStyle(color: Color.lerp(m.primary, Colors.white, .35),
                          fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 6)),
                      Text('${m.label.toUpperCase()} · ${m.tagline}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11,
                          letterSpacing: 1.2)),
                    ])),
                  _StateBadge(state: state, preview: _preview != null, color: m.primary),
                  IconButton(
                    tooltip: 'AIRA settings',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.tune, color: Colors.white),
                    onPressed: _openSettings,
                  ),
                ]),
              ),
              if (widget.developerControls && _loaded && roomy)
                Positioned(
                  left: 0, right: 0, bottom: 4,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _StateStrip(
                      selected: _preview,
                      onSelected: (s) => setState(() => _preview = s),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(height: 112, child: _ModelStrip(
                      prefs: _prefs, reduce: reduce,
                      onPick: (pick) => _update((p) => p.model = pick),
                    )),
                  ]),
                ),
              if (widget.developerControls && _loaded && !roomy)
                Positioned(
                  right: 8, bottom: 8,
                  child: FilledButton.tonalIcon(
                    onPressed: _openModelSheet,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(m.label),
                  ),
                ),
            ]),
          );
        });
      },
    );
  }

  void _openModelSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF05070C),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.of(ctx).size.height * .6,
        child: GridView.count(
          crossAxisCount: 2, padding: const EdgeInsets.all(12),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .95,
          children: [
            for (final m in AiraModel.values)
              _ModelCard(model: m, selected: m == _prefs.model,
                reduce: _prefs.reduceMotion,
                onTap: () {
                  _update((p) => p.model = m);
                  Navigator.of(ctx).pop();
                }),
          ],
        ),
      )),
    );
  }

  void _openSettings() {
    final nameCtl = TextEditingController(text: _prefs.assistantName);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF05070C),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void change(void Function(AiraPreferences p) fn) {
          _update(fn);
          setSheet(() {});
        }
        final m = _prefs.model;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(child: ListView(shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18), children: [
            const Text('AIRA SETTINGS', style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: 4),
            const Text('Visual only. AIRA uses the same JARVIS brain, chat, '
              'microphone and permissions as every other mode.',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtl, maxLength: 24,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Assistant display name',
                labelStyle: TextStyle(color: Colors.white70)),
              onSubmitted: (v) => change((p) => p.assistantName = AiraPreferences.sanitizeName(v)),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(
              onPressed: () => change((p) => p.assistantName = AiraPreferences.sanitizeName(nameCtl.text)),
              child: const Text('Save name'))),
            const Text('Graphics', style: TextStyle(color: Colors.white70)),
            SegmentedButton<AiraQuality>(
              segments: [for (final q in AiraQuality.values)
                ButtonSegment(value: q, label: Text(q.label))],
              selected: {_prefs.quality},
              onSelectionChanged: (s) => change((p) => p.quality = s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduce motion', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Slower, calmer animation and fewer particles',
                style: TextStyle(color: Colors.white54)),
              value: _prefs.reduceMotion,
              onChanged: (v) => change((p) => p.reduceMotion = v),
            ),
            Text('${m.label} brightness', style: const TextStyle(color: Colors.white70)),
            Slider(
              min: AiraPreferences.minBrightness, max: AiraPreferences.maxBrightness,
              value: _prefs.brightnessOf(m),
              onChanged: (v) => change((p) => p.brightness[m] = v),
            ),
            Text('${m.label} motion speed', style: const TextStyle(color: Colors.white70)),
            Slider(
              min: AiraPreferences.minSpeed, max: AiraPreferences.maxSpeed,
              value: _prefs.speedOf(m),
              onChanged: (v) => change((p) => p.speed[m] = v),
            ),
          ])),
        );
      }),
    ).whenComplete(nameCtl.dispose);
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state, required this.preview, required this.color});
  final AiraVisualState state;
  final bool preview;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('aira-state-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .7)),
        ),
        child: Text('${preview ? 'PREVIEW' : 'LIVE'} · ${state.label}',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700,
            letterSpacing: 1)),
      );
}

class _StateStrip extends StatelessWidget {
  const _StateStrip({required this.selected, required this.onSelected});
  final AiraVisualState? selected;
  final ValueChanged<AiraVisualState?> onSelected;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView(
          key: const ValueKey('aira-state-strip'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            _chip('Live', selected == null, () => onSelected(null)),
            for (final s in AiraVisualState.values)
              _chip(s.label[0] + s.label.substring(1).toLowerCase(), selected == s,
                  () => onSelected(s)),
          ],
        ),
      );

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ChoiceChip(
          label: Text(label), selected: on, onSelected: (_) => tap(),
          labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
          selectedColor: const Color(0xFF3A1B5C),
          backgroundColor: const Color(0xCC0A0A14),
          side: BorderSide(color: on ? const Color(0xFFE08BFF) : const Color(0xFF2E2A44)),
        ),
      );
}

class _ModelStrip extends StatelessWidget {
  const _ModelStrip({required this.prefs, required this.reduce, required this.onPick});
  final AiraPreferences prefs;
  final bool reduce;
  final ValueChanged<AiraModel> onPick;
  @override
  Widget build(BuildContext context) => ListView.separated(
        key: const ValueKey('aira-model-strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: AiraModel.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final m = AiraModel.values[i];
          return SizedBox(width: 96, child: _ModelCard(
            model: m, selected: m == prefs.model, reduce: reduce,
            onTap: () => onPick(m)));
        },
      );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.model, required this.selected, required this.reduce,
      required this.onTap});
  final AiraModel model;
  final bool selected;
  final bool reduce;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, selected: selected, label: 'AIRA model ${model.label}',
        child: InkWell(
          key: ValueKey('aira-model-${model.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF05060A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? model.primary : const Color(0xFF242836),
                width: selected ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Expanded(child: AiraCoreView(
                model: model, state: AiraVisualState.idle,
                quality: AiraQuality.battery, reduceMotion: reduce,
                compact: true, interactive: false)),
              Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                child: Text(model.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: selected ? Colors.white : Colors.white70,
                    fontSize: 11, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      );
}
