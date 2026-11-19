import 'dart:ui' show Color;

import 'package:shared_preferences/shared_preferences.dart';

/// AIRA visual configuration. Purely visual: no AI, microphone, network or
/// storage of conversation content happens here.

/// Ten structurally different AIRA core designs. Each has its own renderer in
/// `aira_painter.dart`; they are not recolours of one sphere.
enum AiraModel {
  neuralReactor('Neural Reactor', 'Node sphere · synapse links',
      Color(0xFF34F5FF), Color(0xFFFF3BD4), Color(0xFF8A7BFF)),
  amberHologram('Amber Hologram', 'Gyroscopic light-string shell',
      Color(0xFFFFA62B), Color(0xFFFFE08A), Color(0xFF3FE9FF)),
  electricWeb('Electric Web', 'Plasma globe lightning',
      Color(0xFF4DB8FF), Color(0xFFD6F4FF), Color(0xFFB45CFF)),
  aiHead('AI Head', 'Neural profile · firing synapses',
      Color(0xFF2FD8FF), Color(0xFFFF4A3D), Color(0xFF5B7CFF)),
  jellyfish('Jellyfish', 'Bioluminescent pulsing bell',
      Color(0xFF3CFFE0), Color(0xFFFF6BD8), Color(0xFF9B6BFF)),
  violetVortex('Violet Vortex', 'Spiral accretion galaxy',
      Color(0xFFB45CFF), Color(0xFFFF4FD8), Color(0xFF6FD8FF)),
  auroraRibbon('Aurora Ribbon', 'Orbiting light ribbons',
      Color(0xFF3DFFA8), Color(0xFFB66BFF), Color(0xFF38D9FF)),
  dnaHelix('DNA Helix', 'Rotating double helix',
      Color(0xFF39F0FF), Color(0xFFFF4FB3), Color(0xFFFFE066)),
  crystalBloom('Crystal Bloom', 'Prismatic opening shards',
      Color(0xFFFF8BE6), Color(0xFF8CF6FF), Color(0xFFD7B8FF)),
  solarFlare('Solar Flare', 'Corona loops · ejecta',
      Color(0xFFFF8A1F), Color(0xFFFFE15A), Color(0xFFFF3B2F));

  const AiraModel(this.label, this.tagline, this.primary, this.secondary,
      this.accent);
  final String label;
  final String tagline;
  final Color primary;
  final Color secondary;
  final Color accent;

  static AiraModel fromName(String? name) => AiraModel.values.firstWhere(
        (m) => m.name == name,
        orElse: () => AiraModel.neuralReactor,
      );
}

/// Visual states, bound to the shared JARVIS phase (or a labelled preview).
enum AiraVisualState {
  idle('IDLE', 'Energy stable'),
  listening('LISTENING', 'Audio receptors open'),
  thinking('THINKING', 'Reasoning'),
  processing('PROCESSING', 'Executing task'),
  completed('COMPLETED', 'Task finished'),
  speaking('SPEAKING', 'Voice reply');

  const AiraVisualState(this.label, this.caption);
  final String label;
  final String caption;

  /// Motion multiplier, light energy, structural spread, hue warmth.
  ({double speed, double energy, double spread, double warmth}) get params =>
      switch (this) {
        AiraVisualState.idle => (speed: .55, energy: .62, spread: 1.0, warmth: 0),
        AiraVisualState.listening =>
          (speed: 1.0, energy: .82, spread: .9, warmth: 0),
        AiraVisualState.thinking =>
          (speed: .8, energy: .74, spread: .96, warmth: -.4),
        AiraVisualState.processing =>
          (speed: 1.85, energy: .95, spread: 1.04, warmth: .1),
        AiraVisualState.completed =>
          (speed: .7, energy: 1.0, spread: 1.12, warmth: .6),
        AiraVisualState.speaking =>
          (speed: 1.15, energy: .9, spread: 1.06, warmth: .3),
      };
}

/// Graphics budget. Particle counts and frame-rate caps scale with this.
enum AiraQuality {
  high('High', 60, 1.0),
  balanced('Balanced', 45, .66),
  battery('Battery', 30, .38);

  const AiraQuality(this.label, this.maxFps, this.detail);
  final String label;
  final int maxFps;
  final double detail;

  static AiraQuality fromName(String? name) => AiraQuality.values.firstWhere(
        (q) => q.name == name,
        orElse: () => AiraQuality.balanced,
      );
}

/// Owner choices for AIRA, persisted locally with SharedPreferences.
class AiraPreferences {
  AiraPreferences({
    this.model = AiraModel.neuralReactor,
    this.quality = AiraQuality.balanced,
    this.reduceMotion = false,
    this.assistantName = 'AIRA',
    Map<AiraModel, double>? brightness,
    Map<AiraModel, double>? speed,
  })  : brightness = brightness ?? {},
        speed = speed ?? {};

  AiraModel model;
  AiraQuality quality;
  bool reduceMotion;
  String assistantName;
  final Map<AiraModel, double> brightness;
  final Map<AiraModel, double> speed;

  static const kModel = 'aira_model_v1';
  static const kQuality = 'aira_quality_v1';
  static const kReduceMotion = 'aira_reduce_motion_v1';
  static const kName = 'aira_assistant_name_v1';
  static String kBrightness(AiraModel m) => 'aira_${m.name}_brightness_v1';
  static String kSpeed(AiraModel m) => 'aira_${m.name}_speed_v1';

  static const minBrightness = .6, maxBrightness = 1.5;
  static const minSpeed = .4, maxSpeed = 1.8;

  double brightnessOf(AiraModel m) =>
      (brightness[m] ?? 1.0).clamp(minBrightness, maxBrightness);
  double speedOf(AiraModel m) => (speed[m] ?? 1.0).clamp(minSpeed, maxSpeed);

  static String sanitizeName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\u0000-\u001F<>]'), '').trim();
    if (cleaned.isEmpty) return 'AIRA';
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }

  static Future<AiraPreferences> load() async {
    final p = await SharedPreferences.getInstance();
    final prefs = AiraPreferences(
      model: AiraModel.fromName(p.getString(kModel)),
      quality: AiraQuality.fromName(p.getString(kQuality)),
      reduceMotion: p.getBool(kReduceMotion) ?? false,
      assistantName: sanitizeName(p.getString(kName) ?? 'AIRA'),
    );
    for (final m in AiraModel.values) {
      final b = p.getDouble(kBrightness(m));
      final s = p.getDouble(kSpeed(m));
      if (b != null) prefs.brightness[m] = b;
      if (s != null) prefs.speed[m] = s;
    }
    return prefs;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kModel, model.name);
    await p.setString(kQuality, quality.name);
    await p.setBool(kReduceMotion, reduceMotion);
    await p.setString(kName, sanitizeName(assistantName));
    for (final e in brightness.entries) {
      await p.setDouble(kBrightness(e.key), e.value);
    }
    for (final e in speed.entries) {
      await p.setDouble(kSpeed(e.key), e.value);
    }
  }
}
