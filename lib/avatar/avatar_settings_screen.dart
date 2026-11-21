// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'avatar_runtime.dart';
import 'core/avatar_settings.dart';

/// Per-avatar Settings: colours (RGB / HEX), particles, size/position,
/// speed, glow, lightning, sounds, background and performance mode.
/// Every change is saved immediately and applied live to the avatar.
class AvatarSettingsScreen extends StatefulWidget {
  const AvatarSettingsScreen({super.key, this.avatarId = serpentGuardianId, this.title = 'Serpent Guardian'});
  final String avatarId;
  final String title;

  @override
  State<AvatarSettingsScreen> createState() => _AvatarSettingsScreenState();
}

class _AvatarSettingsScreenState extends State<AvatarSettingsScreen> {
  late AvatarSettings s;

  @override
  void initState() {
    super.initState();
    s = AvatarSettingsStore.listenable(widget.avatarId).value;
    AvatarSettingsStore.load(widget.avatarId).then((v) {
      if (mounted) setState(() => s = v);
    });
  }

  void _set(AvatarSettings next) {
    setState(() => s = next);
    AvatarSettingsStore.save(widget.avatarId, next);
  }

  Widget _slider(String key, String label, double value, double min, double max, ValueChanged<double> onChanged,
          {String Function(double)? fmt}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          SizedBox(width: 118, child: Text(label)),
          Expanded(
            child: Slider(
                key: ValueKey('avatar-$key'), value: value.clamp(min, max).toDouble(), min: min, max: max,
                onChanged: onChanged),
          ),
          SizedBox(
              width: 46,
              child: Text(fmt?.call(value) ?? value.toStringAsFixed(2), textAlign: TextAlign.right)),
        ]),
      );

  Widget _colorTile(String key, String label, int argb, ValueChanged<int> onChanged) => ListTile(
        key: ValueKey('avatar-color-$key'),
        title: Text(label),
        subtitle: Text(formatHex(argb)),
        trailing: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Color(argb),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white54),
            boxShadow: [BoxShadow(color: Color(argb).withValues(alpha: 0.6), blurRadius: 10)],
          ),
        ),
        onTap: () async {
          final picked = await showAvatarColorPicker(context, label, argb);
          if (picked != null) onChanged(picked);
        },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} avatar')),
      body: ListView(
        key: const ValueKey('avatar-settings-list'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
                'Real-time procedural prototype. The humanoid and serpent shapes are placeholders until the '
                'approved 3D model is supplied; colours, sizes and effects below carry over to it.',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ),
          const _Header('Colours'),
          _colorTile('primary', 'Primary (core / scales)', s.primaryColor, (v) => _set(s.copyWith(primaryColor: v))),
          _colorTile('secondary', 'Secondary (hologram)', s.secondaryColor, (v) => _set(s.copyWith(secondaryColor: v))),
          _colorTile('particle', 'Particle glitter', s.particleColor, (v) => _set(s.copyWith(particleColor: v))),
          _colorTile('accent', 'Sparks / accents', s.accentColor, (v) => _set(s.copyWith(accentColor: v))),
          const _Header('Particles'),
          _slider('density', 'Density', s.particleDensity, 0, 1, (v) => _set(s.copyWith(particleDensity: v)),
              fmt: (v) => '${(v * 100).round()}%'),
          const _Header('Size & position'),
          _slider('scale', 'Avatar size', s.scale, 0.6, 1.4, (v) => _set(s.copyWith(scale: v)),
              fmt: (v) => '${(v * 100).round()}%'),
          _slider('offsetX', 'Horizontal', s.offsetX, -0.3, 0.3, (v) => _set(s.copyWith(offsetX: v))),
          _slider('offsetY', 'Vertical', s.offsetY, -0.3, 0.3, (v) => _set(s.copyWith(offsetY: v))),
          const _Header('Motion & effects'),
          _slider('speed', 'Animation speed', s.speed, 0.25, 2, (v) => _set(s.copyWith(speed: v)),
              fmt: (v) => '${v.toStringAsFixed(2)}x'),
          _slider('glow', 'Glow intensity', s.glow, 0, 1.5, (v) => _set(s.copyWith(glow: v))),
          _slider('lightning', 'Lightning', s.lightning, 0, 1, (v) => _set(s.copyWith(lightning: v))),
          SwitchListTile(
            key: const ValueKey('avatar-background'),
            title: const Text('Background effects'),
            subtitle: const Text('Chamber glow and light bars behind the avatar'),
            value: s.backgroundEffects,
            onChanged: (v) => _set(s.copyWith(backgroundEffects: v)),
          ),
          const _Header('Sound'),
          SwitchListTile(
            key: const ValueKey('avatar-intro-sound'),
            title: const Text('Intro sound'),
            subtitle: const Text('Soft energy charge when the avatar forms (offline, generated)'),
            value: s.introSound,
            onChanged: (v) => _set(s.copyWith(introSound: v)),
          ),
          SwitchListTile(
            key: const ValueKey('avatar-outro-sound'),
            title: const Text('Outro sound'),
            value: s.outroSound,
            onChanged: (v) => _set(s.copyWith(outroSound: v)),
          ),
          const _Header('Performance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SegmentedButton<AvatarPerformanceMode>(
              key: const ValueKey('avatar-performance'),
              segments: const [
                ButtonSegment(value: AvatarPerformanceMode.quality, label: Text('Quality')),
                ButtonSegment(value: AvatarPerformanceMode.balanced, label: Text('Balanced')),
                ButtonSegment(value: AvatarPerformanceMode.battery, label: Text('Battery')),
              ],
              selected: {s.performance},
              onSelectionChanged: (v) => _set(s.copyWith(performance: v.first)),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('avatar-debug-stats'),
            title: const Text('Show performance stats'),
            subtitle: const Text('FPS, frame time, triangles, particles (on the avatar)'),
            value: s.showDebugStats,
            onChanged: (v) => _set(s.copyWith(showDebugStats: v)),
          ),
          const _Header('Preview'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 8, children: [
              FilledButton.tonal(
                key: const ValueKey('avatar-replay-intro'),
                onPressed: () {
                  sendAvatarCommand('replay_intro');
                  Navigator.of(context).maybePop();
                },
                child: const Text('Replay intro'),
              ),
              FilledButton.tonal(
                key: const ValueKey('avatar-preview-close'),
                onPressed: () {
                  sendAvatarCommand('close');
                  Navigator.of(context).maybePop();
                },
                child: const Text('Preview closing'),
              ),
              OutlinedButton(
                key: const ValueKey('avatar-reset'),
                onPressed: () => _set(AvatarSettings.defaults),
                child: const Text('Reset to defaults'),
              ),
            ]),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
      );
}

/// RGB sliders + HEX field + swatches. Returns 0xAARRGGBB or null.
Future<int?> showAvatarColorPicker(BuildContext context, String title, int initial) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(title: title, initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});
  final String title;
  final int initial;
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late int r, g, b;
  late final TextEditingController hex;
  String? error;

  static const swatches = [
    0xFF00E8A2, 0xFF00E5FF, 0xFF14B8A6, 0xFF22C55E, 0xFFB98CFF, 0xFF7C3AED,
    0xFFFFC857, 0xFFFF8A00, 0xFFFF4D6D, 0xFF3B82F6, 0xFFFFFFFF, 0xFFC0C7D0,
  ];

  int get argb => argbFrom(255, r, g, b);

  @override
  void initState() {
    super.initState();
    r = (widget.initial >> 16) & 0xFF;
    g = (widget.initial >> 8) & 0xFF;
    b = widget.initial & 0xFF;
    hex = TextEditingController(text: formatHex(argbFrom(255, r, g, b)));
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void _fromArgb(int v) {
    setState(() {
      r = (v >> 16) & 0xFF;
      g = (v >> 8) & 0xFF;
      b = v & 0xFF;
      error = null;
      hex.text = formatHex(argb);
    });
  }

  Widget _channel(String label, int value, Color tint, ValueChanged<int> set) => Row(children: [
        SizedBox(width: 16, child: Text(label)),
        Expanded(
          child: Slider(
            key: ValueKey('picker-$label'),
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: tint,
            onChanged: (v) => setState(() {
              set(v.round());
              hex.text = formatHex(argb);
              error = null;
            }),
          ),
        ),
        SizedBox(width: 30, child: Text('$value', textAlign: TextAlign.right)),
      ]);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            key: const ValueKey('picker-preview'),
            height: 44,
            decoration: BoxDecoration(
              color: Color(argb),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Color(argb).withValues(alpha: 0.7), blurRadius: 16)],
            ),
          ),
          const SizedBox(height: 8),
          _channel('R', r, Colors.redAccent, (v) => r = v),
          _channel('G', g, Colors.greenAccent, (v) => g = v),
          _channel('B', b, Colors.lightBlueAccent, (v) => b = v),
          TextField(
            key: const ValueKey('picker-hex'),
            controller: hex,
            decoration: InputDecoration(labelText: 'HEX (#RRGGBB) or rgb(r,g,b)', errorText: error),
            onSubmitted: _applyHex,
            onChanged: (t) {
              final v = parseHex(t);
              if (v != null) {
                setState(() {
                  r = (v >> 16) & 0xFF;
                  g = (v >> 8) & 0xFF;
                  b = v & 0xFF;
                  error = null;
                });
              }
            },
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in swatches)
              InkWell(
                key: ValueKey('swatch-${formatHex(c)}'),
                onTap: () => _fromArgb(c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: Colors.white38)),
                ),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('picker-ok'),
          onPressed: () {
            if (parseHex(hex.text) == null) {
              setState(() => error = 'Invalid colour');
              return;
            }
            Navigator.pop(context, argb);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  void _applyHex(String t) {
    final v = parseHex(t);
    if (v == null) {
      setState(() => error = 'Invalid colour');
    } else {
      _fromArgb(v);
    }
  }
}
