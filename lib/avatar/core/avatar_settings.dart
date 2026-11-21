import 'dart:convert';

/// Rendering budget. Battery caps at 30 fps and disables blur glows.
enum AvatarPerformanceMode { quality, balanced, battery }

/// Per-avatar, persisted appearance and behaviour settings.
///
/// Pure Dart: colours are stored as 0xAARRGGBB ints so the same settings can
/// drive the procedural renderer now and a Filament material later.
class AvatarSettings {
  const AvatarSettings({
    this.primaryColor = 0xFF00E8A2, // emerald
    this.secondaryColor = 0xFF00E5FF, // cyan
    this.particleColor = 0xFFB98CFF, // violet glitter
    this.accentColor = 0xFFFFC857, // gold sparks
    this.particleDensity = 0.7,
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.speed = 1.0,
    this.glow = 1.0,
    this.lightning = 0.6,
    this.introSound = true,
    this.outroSound = true,
    this.backgroundEffects = true,
    this.performance = AvatarPerformanceMode.balanced,
    this.showDebugStats = false,
  });

  final int primaryColor;
  final int secondaryColor;
  final int particleColor;
  final int accentColor;
  final double particleDensity; // 0..1
  final double scale; // 0.6..1.4
  final double offsetX; // -0.3..0.3 of screen width
  final double offsetY; // -0.3..0.3 of screen height
  final double speed; // 0.25..2
  final double glow; // 0..1.5
  final double lightning; // 0..1
  final bool introSound;
  final bool outroSound;
  final bool backgroundEffects;
  final AvatarPerformanceMode performance;
  final bool showDebugStats;

  static const defaults = AvatarSettings();

  static double _c(num? v, double lo, double hi, double fallback) {
    final d = v?.toDouble();
    if (d == null || !d.isFinite) return fallback;
    return d < lo ? lo : (d > hi ? hi : d);
  }

  AvatarSettings copyWith({
    int? primaryColor,
    int? secondaryColor,
    int? particleColor,
    int? accentColor,
    double? particleDensity,
    double? scale,
    double? offsetX,
    double? offsetY,
    double? speed,
    double? glow,
    double? lightning,
    bool? introSound,
    bool? outroSound,
    bool? backgroundEffects,
    AvatarPerformanceMode? performance,
    bool? showDebugStats,
  }) =>
      AvatarSettings(
        primaryColor: primaryColor ?? this.primaryColor,
        secondaryColor: secondaryColor ?? this.secondaryColor,
        particleColor: particleColor ?? this.particleColor,
        accentColor: accentColor ?? this.accentColor,
        particleDensity: _c(particleDensity ?? this.particleDensity, 0, 1, 0.7),
        scale: _c(scale ?? this.scale, 0.6, 1.4, 1),
        offsetX: _c(offsetX ?? this.offsetX, -0.3, 0.3, 0),
        offsetY: _c(offsetY ?? this.offsetY, -0.3, 0.3, 0),
        speed: _c(speed ?? this.speed, 0.25, 2, 1),
        glow: _c(glow ?? this.glow, 0, 1.5, 1),
        lightning: _c(lightning ?? this.lightning, 0, 1, 0.6),
        introSound: introSound ?? this.introSound,
        outroSound: outroSound ?? this.outroSound,
        backgroundEffects: backgroundEffects ?? this.backgroundEffects,
        performance: performance ?? this.performance,
        showDebugStats: showDebugStats ?? this.showDebugStats,
      );

  Map<String, Object> toJson() => {
        'v': 1,
        'primary': formatHex(primaryColor),
        'secondary': formatHex(secondaryColor),
        'particle': formatHex(particleColor),
        'accent': formatHex(accentColor),
        'density': particleDensity,
        'scale': scale,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'speed': speed,
        'glow': glow,
        'lightning': lightning,
        'introSound': introSound,
        'outroSound': outroSound,
        'background': backgroundEffects,
        'performance': performance.name,
        'debug': showDebugStats,
      };

  /// Tolerant decoder: unknown/invalid fields fall back to defaults and
  /// numeric values are clamped, so corrupted storage can never crash.
  factory AvatarSettings.fromJson(Map<String, dynamic> j) {
    const d = defaults;
    int col(String k, int f) => parseHex(j[k]?.toString() ?? '') ?? f;
    bool b(String k, bool f) => j[k] is bool ? j[k] as bool : f;
    num? n(String k) => j[k] is num ? j[k] as num : null;
    final perf = AvatarPerformanceMode.values
        .where((m) => m.name == j['performance'])
        .firstOrNull ?? d.performance;
    return AvatarSettings(
      primaryColor: col('primary', d.primaryColor),
      secondaryColor: col('secondary', d.secondaryColor),
      particleColor: col('particle', d.particleColor),
      accentColor: col('accent', d.accentColor),
      particleDensity: _c(n('density'), 0, 1, d.particleDensity),
      scale: _c(n('scale'), 0.6, 1.4, d.scale),
      offsetX: _c(n('offsetX'), -0.3, 0.3, d.offsetX),
      offsetY: _c(n('offsetY'), -0.3, 0.3, d.offsetY),
      speed: _c(n('speed'), 0.25, 2, d.speed),
      glow: _c(n('glow'), 0, 1.5, d.glow),
      lightning: _c(n('lightning'), 0, 1, d.lightning),
      introSound: b('introSound', d.introSound),
      outroSound: b('outroSound', d.outroSound),
      backgroundEffects: b('background', d.backgroundEffects),
      performance: perf,
      showDebugStats: b('debug', d.showDebugStats),
    );
  }

  String encode() => jsonEncode(toJson());

  static AvatarSettings decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return AvatarSettings.fromJson(j);
    } catch (_) {
      // Corrupted storage falls back to defaults.
    }
    return defaults;
  }

  /// Storage key for one avatar's settings.
  static String storageKey(String avatarId) => 'avatar_settings_v1_$avatarId';

  @override
  bool operator ==(Object other) => other is AvatarSettings && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

/// Parses "#RRGGBB", "RRGGBB", "#AARRGGBB" or "rgb(r,g,b)". Returns 0xAARRGGBB.
int? parseHex(String input) {
  final s = input.trim();
  final rgb = RegExp(r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$', caseSensitive: false)
      .firstMatch(s);
  if (rgb != null) {
    final c = [for (var i = 1; i <= 3; i++) int.parse(rgb.group(i)!)];
    if (c.any((v) => v > 255)) return null;
    return argbFrom(255, c[0], c[1], c[2]);
  }
  var h = s.startsWith('#') ? s.substring(1) : s;
  if (h.startsWith('0x') || h.startsWith('0X')) h = h.substring(2);
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) return null;
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) return 0xFF000000 | int.parse(h, radix: 16);
  if (h.length == 8) return int.parse(h, radix: 16);
  return null;
}

/// Formats as "#RRGGBB" (alpha dropped when opaque) or "#AARRGGBB".
String formatHex(int argb) {
  final a = (argb >> 24) & 0xFF;
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  if (a == 0xFF) return '#$rgb';
  return '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
}

int argbFrom(int a, int r, int g, int b) =>
    ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
