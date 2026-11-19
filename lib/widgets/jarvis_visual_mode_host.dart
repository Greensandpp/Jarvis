// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/agent_office/agent_office.dart';
import '../services/gemini_live/live_voice_controller.dart';
import '../services/jarvis_service.dart';
import '../services/live_voice_session.dart';
import '../services/task_executor.dart';
import 'agent_office_view.dart';
import 'aira/aira_models.dart';
import 'aira/aira_view.dart';
import 'jarvis_hud_widget.dart';
import 'jarvis_local_visuals.dart';

/// Visual preference only: every mode shares the one native JARVIS brain,
/// chat history, tool router, permissions, microphone and task executor.
enum JarvisVisualMode {
  core('JARVIS Core', 'JARVIS', Icons.blur_circular),
  aira('AIRA', 'AIRA', Icons.auto_awesome),
  office('Agent Office', 'Office', Icons.groups_2_outlined),
  apex('APEX', 'APEX', Icons.change_history),
  mira('MIRA', 'MIRA', Icons.bubble_chart_outlined);

  const JarvisVisualMode(this.label, this.shortLabel, this.icon);
  final String label;
  final String shortLabel;
  final IconData icon;
}

/// Maps the shared JARVIS phase to an AIRA visual state. "Completed" is a
/// short transient shown when work/speech ends and the phase returns to idle.
class AiraPhaseBinding extends ValueNotifier<AiraVisualState> {
  AiraPhaseBinding(this._source, this._read) : super(AiraVisualState.idle) {
    _source.addListener(_sync);
    _sync();
  }
  final Listenable _source;
  final JarvisPhase Function() _read;
  JarvisPhase _last = JarvisPhase.idle;
  int _gen = 0;

  static AiraVisualState map(JarvisPhase p) => switch (p) {
        JarvisPhase.idle => AiraVisualState.idle,
        JarvisPhase.listening => AiraVisualState.listening,
        JarvisPhase.thinking => AiraVisualState.thinking,
        JarvisPhase.executing => AiraVisualState.processing,
        JarvisPhase.speaking => AiraVisualState.speaking,
      };

  void _sync() {
    final p = _read();
    if (p == _last) return;
    final wasWorking = _last == JarvisPhase.executing || _last == JarvisPhase.speaking;
    _last = p;
    final g = ++_gen;
    if (p == JarvisPhase.idle && wasWorking) {
      value = AiraVisualState.completed;
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (g == _gen) value = AiraVisualState.idle;
      });
    } else {
      value = map(p);
    }
  }

  @override
  void dispose() {
    _source.removeListener(_sync);
    super.dispose();
  }
}

class JarvisVisualModeHost extends StatefulWidget {
  const JarvisVisualModeHost({
    super.key,
    required this.onCommand,
    required this.onMicrophone,
    this.phaseSource,
    this.phaseReader,
    this.soundReader,
    this.coreBuilder,
    this.office,
    this.liveVoice,
    this.localTask,
    this.localTaskListenable,
  });

  final ValueChanged<String> onCommand;
  final Future<void> Function() onMicrophone;

  /// Injection points (tests). Defaults are the real shared singletons.
  final Listenable? phaseSource;
  final JarvisPhase Function()? phaseReader;
  final double Function()? soundReader;
  final WidgetBuilder? coreBuilder;
  final AgentOfficeController? office;
  final LiveVoiceController? liveVoice;
  final ({String goal, String state, int step}) Function()? localTask;
  final Listenable? localTaskListenable;

  @override
  State<JarvisVisualModeHost> createState() => JarvisVisualModeHostState();
}

class JarvisVisualModeHostState extends State<JarvisVisualModeHost> {
  static const storageKey = 'jarvis_visual_mode_v1';
  JarvisVisualMode mode = JarvisVisualMode.core;
  final command = TextEditingController();
  late final Listenable _phaseSource;
  late final JarvisPhase Function() _phase;
  late final double Function() _sound;
  late final AiraPhaseBinding _aira;
  late final LiveVoiceController _live;
  late final bool _ownsLive;

  static LiveVoiceController? _sharedLive;

  @override
  void initState() {
    super.initState();
    _phaseSource = widget.phaseSource ?? JarvisService.instance;
    _phase = widget.phaseReader ?? () => JarvisService.instance.phase;
    _ownsLive = false;
    _live = widget.liveVoice ?? (_sharedLive ??= LiveVoiceController(
      requestMicPermission: () async => (await Permission.microphone.request()).isGranted,
      pauseOtherMic: () => JarvisService.instance.stopListening(),
    ));
    _sound = widget.soundReader ??
        () => _live.active ? _live.level : JarvisService.instance.soundLevel.clamp(0.0, 1.0);
    _aira = AiraPhaseBinding(_phaseSource, _phase);
    _live.load();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final selected = JarvisVisualMode.values.firstWhere(
      (item) => item.name == prefs.getString(storageKey),
      orElse: () => JarvisVisualMode.core,
    );
    select(selected, persist: false);
  }

  void select(JarvisVisualMode next, {bool persist = true}) {
    if (mode != next && mounted) {
      setState(() { mode = next; });
    }
    if (persist) {
      SharedPreferences.getInstance().then((p) => p.setString(storageKey, next.name));
    }
  }

  void _send() {
    final text = command.text.trim();
    if (text.isEmpty) return;
    command.clear();
    // Commands stay inside the native JARVIS router, never a visual site.
    widget.onCommand(text);
  }

  @override
  void dispose() {
    command.dispose();
    _aira.dispose();
    if (_ownsLive) _live.dispose();
    super.dispose();
  }

  ({String goal, String state, int step}) _localTask() {
    if (widget.localTask != null) return widget.localTask!();
    final e = TaskExecutor.instance;
    return (goal: e.currentGoal ?? '', state: e.state.name, step: e.step);
  }

  Widget _body() => switch (mode) {
        JarvisVisualMode.core => widget.coreBuilder?.call(context) ?? const JarvisHudWidget(),
        JarvisVisualMode.aira => AiraModeView(liveState: _aira, soundLevel: _sound),
        JarvisVisualMode.office => AgentOfficeView(
            controller: widget.office ?? AgentOfficeController.instance,
            localTask: _localTask,
            localTaskListenable: widget.localTaskListenable ?? TaskExecutor.instance,
          ),
        JarvisVisualMode.apex => const JarvisLocalVisual(apex: true),
        JarvisVisualMode.mira => const JarvisLocalVisual(apex: false),
      };

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00E5FF);
    return ColoredBox(color: Colors.black, child: Column(children: [
      SizedBox(height: 58, child: Row(
        key: const ValueKey('mode-selector'),
        children: [
          for (final item in JarvisVisualMode.values)
            Expanded(child: Semantics(
              button: true, selected: mode == item, label: '${item.label} mode',
              child: InkWell(
                key: ValueKey('mode-${item.name}'),
                onTap: () => select(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                  decoration: BoxDecoration(
                    color: mode == item ? const Color(0xFF064C55) : const Color(0xFF06161B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: mode == item ? cyan : const Color(0xFF27515A)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(item.icon, size: 18, color: mode == item ? cyan : Colors.white70),
                    Text(item.shortLabel, maxLines: 1, overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: mode == item ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
              ),
            )),
        ],
      )),
      Expanded(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(key: ValueKey(mode), child: _body()),
      )),
      if (mode != JarvisVisualMode.core)
        SafeArea(top: false, child: _SharedDock(
          controller: command,
          phaseSource: _phaseSource,
          phase: _phase,
          live: _live,
          onSend: _send,
          onMicrophone: widget.onMicrophone,
        )),
    ]));
  }
}

/// One dock, shared by AIRA / Office / APEX / MIRA: text + native mic +
/// explicit opt-in Gemini Live. All route to the same native JARVIS service.
class _SharedDock extends StatelessWidget {
  const _SharedDock({required this.controller, required this.phaseSource,
      required this.phase, required this.live, required this.onSend,
      required this.onMicrophone});
  final TextEditingController controller;
  final Listenable phaseSource;
  final JarvisPhase Function() phase;
  final LiveVoiceController live;
  final VoidCallback onSend;
  final Future<void> Function() onMicrophone;

  static const cyan = Color(0xFF00E5FF);

  String _liveLabel() {
    if (!live.configured) return 'LIVE: DISCONNECTED';
    return switch (live.status) {
      LiveVoiceStatus.idle => 'LIVE: OFF',
      LiveVoiceStatus.connecting => 'LIVE: CONNECTING',
      LiveVoiceStatus.listening => live.muted ? 'LIVE: MIC MUTED' : 'LIVE: ON AIR',
      LiveVoiceStatus.disconnecting => 'LIVE: STOPPING',
      LiveVoiceStatus.failed => 'LIVE: FAILED',
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([phaseSource, live]),
      builder: (context, _) {
        final p = phase();
        final listening = p == JarvisPhase.listening;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 6, 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text('JARVIS · ${p.name.toUpperCase()}',
                key: const ValueKey('dock-phase'),
                style: const TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1)),
              const Spacer(),
              Flexible(child: Text(live.message ?? _liveLabel(),
                key: const ValueKey('dock-live-status'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: live.active ? const Color(0xFF6BFFA0) : Colors.white54,
                  fontSize: 11))),
            ]),
            Row(children: [
              Expanded(child: TextField(
                key: const ValueKey('dock-input'),
                controller: controller, onSubmitted: (_) => onSend(), maxLength: 500,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  counterText: '', hintText: 'Ask JARVIS privately',
                  isDense: true,
                  hintStyle: const TextStyle(color: Colors.white60), filled: true,
                  fillColor: const Color(0xFF061A20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                ),
              )),
              IconButton(tooltip: listening ? 'Stop listening' : 'Speak to JARVIS',
                key: const ValueKey('dock-mic'),
                onPressed: () { onMicrophone(); },
                icon: Icon(listening ? Icons.mic : Icons.mic_none,
                  color: listening ? const Color(0xFFFF5AD8) : cyan)),
              GestureDetector(
                onLongPress: () => showLiveVoiceSettings(context, live),
                child: IconButton(
                  key: const ValueKey('dock-live'),
                  tooltip: live.active ? 'Stop Gemini Live' : 'Start Gemini Live (opt-in)',
                  onPressed: () => _toggleLive(context),
                  icon: Icon(live.active ? Icons.stop_circle : Icons.graphic_eq,
                    color: live.active ? const Color(0xFF6BFFA0) : Colors.white70)),
              ),
              IconButton(tooltip: 'Send to native JARVIS', key: const ValueKey('dock-send'),
                onPressed: onSend, icon: const Icon(Icons.send, color: cyan)),
            ]),
          ]),
        );
      },
    );
  }

  Future<void> _toggleLive(BuildContext context) async {
    if (live.active || live.status == LiveVoiceStatus.connecting) {
      await live.stop();
      return;
    }
    if (!live.configured) {
      await showLiveVoiceSettings(context, live);
      return;
    }
    if (!live.settings.disclosureAccepted) {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Start Gemini Live voice?'),
        content: const Text(
          'While Live is ON, microphone audio is streamed to Google Gemini through a '
          'short-lived token from your own broker. Nothing is recorded to storage. '
          'Live stops when you tap stop or leave the app. No always-on or lock-screen listening.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I agree')),
        ],
      ));
      if (ok != true) return;
      live.settings.disclosureAccepted = true;
      await live.saveSettings(live.settings);
    }
    await live.start(consent: true);
  }
}

Future<void> showLiveVoiceSettings(BuildContext context, LiveVoiceController live) async {
  final s = live.settings;
  final broker = TextEditingController(text: s.brokerUrl);
  final token = TextEditingController(text: s.deviceToken);
  final model = TextEditingController(text: s.model);
  var voice = s.voice, locale = s.locale;
  String? error;
  await showModalBottomSheet<void>(
    context: context, isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        const Text('Gemini Live (opt-in)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Text('Requires your own token broker that holds the Gemini key server-side '
          'and returns short-lived tokens. No API key is stored in this app.',
          style: TextStyle(fontSize: 12)),
        TextField(controller: broker, decoration: const InputDecoration(labelText: 'Broker https:// URL')),
        TextField(controller: token, obscureText: true,
          decoration: const InputDecoration(labelText: 'Device session token (for your broker)')),
        TextField(controller: model, decoration: const InputDecoration(labelText: 'Live model id')),
        DropdownButtonFormField<String>(
          initialValue: const ['Aoede', 'Kore', 'Leda', 'Zephyr'].contains(voice) ? voice : 'Aoede',
          decoration: const InputDecoration(labelText: 'Voice (female presets)'),
          items: [for (final v in const ['Aoede', 'Kore', 'Leda', 'Zephyr'])
            DropdownMenuItem(value: v, child: Text(v))],
          onChanged: (v) => voice = v ?? voice),
        DropdownButtonFormField<String>(
          initialValue: locale,
          decoration: const InputDecoration(labelText: 'Primary language (Tanglish follows Tamil/English)'),
          items: const [
            DropdownMenuItem(value: 'ta-IN', child: Text('Tamil (ta-IN)')),
            DropdownMenuItem(value: 'en-IN', child: Text('English India (en-IN)')),
          ],
          onChanged: (v) => locale = v ?? locale),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
        const SizedBox(height: 8),
        FilledButton(onPressed: () async {
          final url = broker.text.trim();
          if (url.isNotEmpty) {
            final err = LiveVoiceSettingsValidator.validate(url, token.text);
            if (err != null) { set(() => error = err); return; }
          }
          await live.saveSettings(LiveVoiceSettings(
            brokerUrl: url, deviceToken: token.text.trim(), voice: voice, locale: locale,
            model: model.text.trim().isEmpty ? s.model : model.text.trim(),
            disclosureAccepted: s.disclosureAccepted));
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ])),
    )),
  );
  broker.dispose();
  token.dispose();
  model.dispose();
}

@visibleForTesting
class LiveVoiceSettingsValidator {
  static String? validate(String url, String token) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || !u.hasAuthority) return 'Broker must be an https:// URL';
    if (token.trim().length < 16) return 'Device token looks too short';
    return null;
  }
}
