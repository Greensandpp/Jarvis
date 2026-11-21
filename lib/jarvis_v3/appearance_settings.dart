import 'package:flutter/material.dart';

import '../avatar/serpent_guardian_view.dart';
import '../services/jarvis_service.dart';
import '../widgets/aira/aira_models.dart';
import '../widgets/aira/aira_view.dart';
import '../widgets/jarvis_visual_mode_host.dart';
import 'assistant_activity.dart';
import 'chat_interface_settings.dart';
import 'neon_theme.dart';
import 'reference_avatar_stage.dart';
import 'hologram_theme_store.dart';

/// Compact assistant-mode selector (from the menu or a long-press on the
/// title). All six modes stay available.
Future<void> showAssistantModeSheet(BuildContext context) {
  final s = HologramThemeStore.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF0A0703),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: ValueListenableBuilder<String>(
        valueListenable: s,
        builder: (ctx, current, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'HOLOGRAM THEME',
                style: TextStyle(
                  color: NeonColors.gold,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final m in HologramThemeStore.themes)
              ListTile(
                key: ValueKey('v3-theme-$m'),
                leading: Icon(
                  Icons.auto_awesome,
                  color: m == current ? NeonColors.amber : Colors.white60,
                ),
                title: Text(
                  m.toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: m == current
                    ? const Icon(Icons.check, color: NeonColors.amber)
                    : null,
                onTap: () {
                  s.select(m);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Appearance: chat interface, introduction and animation presets.
class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key, this.settings});
  final ChatInterfaceSettings? settings;

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  late final ChatInterfaceSettings s =
      widget.settings ?? ChatInterfaceSettings.instance;
  AiraPreferences? _aira;

  @override
  void initState() {
    super.initState();
    if (!s.loaded) s.load();
    AiraPreferences.load().then((p) {
      if (mounted) setState(() => _aira = p);
    });
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(
      t.toUpperCase(),
      style: const TextStyle(
        color: NeonColors.gold,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          children: [
            _section('3D hologram theme'),
            ValueListenableBuilder<String>(
              valueListenable: HologramThemeStore.instance,
              builder: (context, current, _) => Wrap(
                children: [
                  for (final theme in HologramThemeStore.themes)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ChoiceChip(
                        label: Text(theme.toUpperCase()),
                        selected: current == theme,
                        onSelected: (_) =>
                            HologramThemeStore.instance.select(theme),
                      ),
                    ),
                ],
              ),
            ),
            _section('Rendering quality'),
            ListTile(
              title: const Text('3D quality'),
              subtitle: const Text(
                'Balanced / Battery saver: 30 FPS target. High / Ultra: 60 FPS target.',
              ),
              trailing: DropdownButton<String>(
                value: s.quality,
                items: [
                  for (final q in ChatInterfaceSettings.qualities)
                    DropdownMenuItem(
                      value: q,
                      child: Text(
                        q == 'battery' ? 'BATTERY SAVER' : q.toUpperCase(),
                      ),
                    ),
                ],
                onChanged: (v) => s.update(quality: v),
              ),
            ),
            _section('Chat interface'),
            SwitchListTile(
              key: const ValueKey('set-autohide'),
              title: const Text('Auto-hide conversation'),
              subtitle: const Text(
                'Fades the chat when you are inactive. History is kept.',
              ),
              value: s.autoHide,
              onChanged: (v) => s.update(autoHide: v),
            ),
            ListTile(
              title: const Text('Hide after'),
              trailing: DropdownButton<int>(
                key: const ValueKey('set-delay'),
                value: s.delaySeconds,
                items: [
                  for (final d in ChatInterfaceSettings.delays)
                    DropdownMenuItem(value: d, child: Text('$d seconds')),
                ],
                onChanged: s.autoHide ? (v) => s.update(delaySeconds: v) : null,
              ),
            ),
            SwitchListTile(
              title: const Text('Show chat while speaking'),
              value: s.showWhileSpeaking,
              onChanged: (v) => s.update(showWhileSpeaking: v),
            ),
            ListTile(
              title: const Text('Glow intensity'),
              subtitle: Slider(
                value: s.glow,
                onChanged: (v) => s.update(glow: v),
              ),
            ),
            ListTile(
              title: const Text('Font size'),
              subtitle: Slider(
                value: s.fontScale,
                min: 0.85,
                max: 1.4,
                divisions: 11,
                label: '${(s.fontScale * 100).round()}%',
                onChanged: (v) => s.update(fontScale: v),
              ),
            ),
            ListTile(
              title: const Text('Chat transparency'),
              subtitle: Slider(
                value: 1.1 - s.opacity,
                min: 0.2,
                max: 0.9,
                onChanged: (v) => s.update(opacity: 1.1 - v),
              ),
            ),
            SwitchListTile(
              title: const Text('Save JARVIS conversation on this device'),
              subtitle: const Text(
                'Off keeps the conversation for this session only.',
              ),
              value: s.saveHistory,
              onChanged: (v) => s.update(saveHistory: v),
            ),
            _section('Introduction and motion'),
            SwitchListTile(
              key: const ValueKey('set-intro'),
              title: const Text('Play introduction on launch'),
              value: s.introEnabled,
              onChanged: (v) => s.update(introEnabled: v),
            ),
            SwitchListTile(
              key: const ValueKey('set-reduce-motion'),
              title: const Text('Reduce motion'),
              subtitle: const Text(
                'Still 3D pose, no intro. The system setting is also respected.',
              ),
              value: s.reduceMotion,
              onChanged: (v) => s.update(reduceMotion: v),
            ),
            _section('Assistant mode'),
            ListTile(
              leading: const Icon(Icons.blur_circular),
              title: const Text('Choose assistant mode'),
              subtitle: ValueListenableBuilder<String>(
                valueListenable: HologramThemeStore.instance,
                builder: (c, m, _) => Text(m.toUpperCase()),
              ),
              onTap: () => showAssistantModeSheet(context),
            ),
            _section('AIRA animation preset'),
            if (_aira == null)
              const ListTile(title: Text('Loading…'))
            else
              for (final m in AiraModel.values)
                RadioListTile<AiraModel>(
                  value: m,
                  // ignore: deprecated_member_use
                  groupValue: _aira!.model,
                  title: Text(m.label),
                  subtitle: Text(m.tagline),
                  // ignore: deprecated_member_use
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _aira!.model = v);
                    _aira!.save();
                  },
                ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Developer Diagnostics only: renders each production visual in a chosen
/// state so animations can be reviewed. Never connected to the main screen.
class AnimationPreviewScreen extends StatefulWidget {
  const AnimationPreviewScreen({super.key});
  @override
  State<AnimationPreviewScreen> createState() => _AnimationPreviewScreenState();
}

class _AnimationPreviewScreenState extends State<AnimationPreviewScreen> {
  final _state = ValueNotifier(AssistantActivity.idle);
  final _phase = ValueNotifier(JarvisPhase.idle);
  int _which =
      0; // 0 JARVIS, 1 Serpent, 2 Serpent (procedural prototype), 3 AIRA
  double _level = 0.5;
  int _introKey = 0;

  static JarvisPhase _toPhase(AssistantActivity a) => switch (a) {
    AssistantActivity.listening => JarvisPhase.listening,
    AssistantActivity.thinking ||
    AssistantActivity.processing => JarvisPhase.thinking,
    AssistantActivity.executing => JarvisPhase.executing,
    AssistantActivity.speaking => JarvisPhase.speaking,
    _ => JarvisPhase.idle,
  };

  late final AiraPhaseBinding _aira = AiraPhaseBinding(
    _phase,
    () => _phase.value,
  );

  @override
  void dispose() {
    _aira.dispose();
    _state.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget view = switch (_which) {
      0 || 1 => ReferenceAvatarStage(
        key: ValueKey('preview-$_which-$_introKey'),
        reference: _which == 0
            ? AvatarReference.jarvis
            : AvatarReference.serpent,
        activity: _state,
        soundLevel: () => _level,
        playIntro: _introKey > 0,
      ),
      2 => SerpentGuardianView(
        phaseSource: _phase,
        phaseReader: () => _phase.value,
        soundReader: () => _level,
      ),
      _ => AiraModeView(liveState: _aira, soundLevel: () => _level),
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Animation preview (diagnostics)')),
      body: Column(
        children: [
          Expanded(child: view),
          Wrap(
            spacing: 6,
            children: [
              for (final (i, n) in [
                (0, 'JARVIS'),
                (1, 'Serpent'),
                (2, 'Serpent prototype'),
                (3, 'AIRA'),
              ])
                ChoiceChip(
                  label: Text(n),
                  selected: _which == i,
                  onSelected: (_) => setState(() => _which = i),
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final a in AssistantActivity.values)
                ChoiceChip(
                  key: ValueKey('preview-${a.name}'),
                  label: Text(a.label),
                  selected: _state.value == a,
                  onSelected: (_) => setState(() {
                    _state.value = a;
                    _phase.value = _toPhase(a);
                  }),
                ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 16),
              const Text('Level'),
              Expanded(
                child: Slider(
                  value: _level,
                  onChanged: (v) => setState(() => _level = v),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _introKey++),
                child: const Text('Replay intro'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
