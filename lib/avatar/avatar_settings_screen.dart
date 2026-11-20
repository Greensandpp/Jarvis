import 'package:flutter/material.dart';
import '../brain/visual_bus.dart';
import '../services/settings_service.dart';
import '../widgets/jarvis_visual_mode_host.dart';
import '../widgets/aira/aira_models.dart';
import 'avatar_settings.dart';
import 'avatar_view.dart';

class AvatarSettingsScreen extends StatefulWidget {
  const AvatarSettingsScreen({super.key});
  @override
  State<AvatarSettingsScreen> createState() => _AvatarSettingsScreenState();
}

class _AvatarSettingsScreenState extends State<AvatarSettingsScreen> {
  final prefs = AvatarPreferences.instance;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    prefs.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void change(VoidCallback action) {
    action();
    prefs.save();
    setState(() {});
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> set,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Slider(
        key: ValueKey('avatar-$label'),
        value: value,
        min: min,
        max: max,
        onChanged: (v) => change(() => set(v)),
      ),
    ],
  );
  Widget color(String label, Color value, ValueChanged<Color> set) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextFormField(
      key: ValueKey('${prefs.selected.name}-$label-${colorHex(value)}'),
      initialValue: colorHex(value),
      decoration: InputDecoration(
        labelText: '$label · #RRGGBB or #AARRGGBB',
        suffixIcon: Icon(Icons.circle, color: value),
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) => parseHexColor(v ?? '') == null
          ? 'Enter 6 or 8 hexadecimal digits'
          : null,
      onFieldSubmitted: (v) {
        final c = parseHexColor(v);
        if (c != null) change(() => set(c));
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final s = prefs.current;
    return Scaffold(
      appBar: AppBar(title: const Text('Avatars & appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Original assets are preserved. New humanoids are procedural mesh concepts. '
            'Final rigged meshes, blendshapes, GPU particles and verified Tamil lip sync are pending.',
          ),
          DropdownButtonFormField<AvatarModel>(
            key: const ValueKey('avatar-picker'),
            initialValue: prefs.selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Avatar'),
            items: [
              for (final m in AvatarModel.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (m) async {
              if (m == null) return;
              await prefs.select(m);
              await requestVisual(mode: 'core');
              await SettingsService.instance.setJarvisScreenStyle(
                m == AvatarModel.originalHumanoid
                    ? JarvisScreenStyle.jarvis
                    : JarvisScreenStyle.arcReactor,
              );
              if (mounted) setState(() => _closing = false);
            },
          ),
          if (prefs.selected.procedural) ...[
            SizedBox(
              height: 280,
              child: ProceduralAvatarView(
                key: ValueKey(prefs.selected),
                model: prefs.selected,
                style: s,
                closing: _closing,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _closing = !_closing),
              child: Text(_closing ? 'Replay intro' : 'Preview closing'),
            ),
            if (prefs.selected == AvatarModel.serpent)
              ExpansionTile(
                title: const Text('Approved Serpent reference'),
                children: [
                  const Text(
                    'Original reference verified separately; final rigged source asset is not bundled.',
                  ),
                  const Text(
                    'Visual reference only. This image is not a reusable rig or animated 3D asset.',
                  ),
                ],
              ),
          ],
          DropdownButtonFormField<GraphicsProfile>(
            initialValue: s.profile,
            decoration: const InputDecoration(labelText: 'Graphics'),
            items: [
              for (final p in GraphicsProfile.values)
                DropdownMenuItem(value: p, child: Text(p.name)),
            ],
            onChanged: (v) => change(() => s.profile = v!),
          ),
          color('Primary glow', s.primary, (v) => s.primary = v),
          color('Secondary glow', s.secondary, (v) => s.secondary = v),
          color('Particles', s.particles, (v) => s.particles = v),
          color('Lightning', s.lightning, (v) => s.lightning = v),
          color('Background', s.background, (v) => s.background = v),
          slider('Avatar size', s.scale, .4, 1.6, (v) => s.scale = v),
          slider('Avatar horizontal position', s.x, -.5, .5, (v) => s.x = v),
          slider('Avatar vertical position', s.y, -.4, .4, (v) => s.y = v),
          slider('Animation speed', s.speed, .2, 2, (v) => s.speed = v),
          slider('Particle density', s.density, 0, 1, (v) => s.density = v),
          slider(
            'Particle size',
            s.particleSize,
            .3,
            3,
            (v) => s.particleSize = v,
          ),
          slider('Glitter intensity', s.glitter, 0, 1, (v) => s.glitter = v),
          slider(
            'Lightning frequency',
            s.lightningFrequency,
            0,
            1,
            (v) => s.lightningFrequency = v,
          ),
          slider(
            'Outer object movement',
            s.outerMotion,
            0,
            2,
            (v) => s.outerMotion = v,
          ),
          slider(
            'Background motion',
            s.backgroundMotion,
            0,
            2,
            (v) => s.backgroundMotion = v,
          ),
          slider('Lip sync intensity', s.lipSync, 0, 1, (v) => s.lipSync = v),
          SwitchListTile(
            title: const Text('Opening animation'),
            value: s.intro,
            onChanged: (v) => change(() => s.intro = v),
          ),
          SwitchListTile(
            title: const Text('Closing animation'),
            value: s.outro,
            onChanged: (v) => change(() => s.outro = v),
          ),
          SwitchListTile(
            title: const Text('Intro/outro sound cue'),
            subtitle: const Text(
              'System click prototype; cinematic sound asset pending.',
            ),
            value: s.audio,
            onChanged: (v) => change(() => s.audio = v),
          ),
          const Divider(),
          const Text('Chat bar'),
          color('Chat bar color', prefs.dockColor, (v) => prefs.dockColor = v),
          slider(
            'Chat bar height',
            prefs.dockHeight,
            48,
            88,
            (v) => prefs.dockHeight = v,
          ),
          slider(
            'Chat bar width',
            prefs.dockWidth,
            .65,
            1,
            (v) => prefs.dockWidth = v,
          ),
          slider(
            'Chat bar horizontal position',
            prefs.dockX,
            -1,
            1,
            (v) => prefs.dockX = v,
          ),
          slider(
            'Chat bar bottom position',
            prefs.dockBottom,
            0,
            180,
            (v) => prefs.dockBottom = v,
          ),
          const Divider(),
          const Text('Preserved visual modes'),
          for (final m in JarvisVisualMode.values)
            ListTile(
              title: Text(m.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await requestVisual(mode: m.name);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ExpansionTile(
            title: const Text('AIRA models'),
            children: [
              for (final m in AiraModel.values)
                ListTile(
                  title: Text(m.label),
                  onTap: () async {
                    await requestVisual(mode: 'aira', airaModel: m.name);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
