import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AvatarModel {
  originalOrb('Original orb'),
  originalHumanoid('Original humanoid'),
  serpent('Serpent Guardian'),
  cyber('Cybernetic guardian'),
  violet('Violet humanoid'),
  golden('Golden energy'),
  angelic('Angelic guardian'),
  crystal('Crystal humanoid'),
  cosmic('Cosmic humanoid'),
  nature('Nature guardian'),
  plasma('Plasma guardian'),
  lightning('Lightning guardian');

  const AvatarModel(this.label);
  final String label;
  bool get procedural => index >= 2;
}

enum GraphicsProfile { lite, balanced, ultra }

Color? parseHexColor(String text) {
  final hex = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex))
    return null;
  return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
}

String colorHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

double _bounded(Map m, String k, double fallback, double min, double max) {
  final n = m[k];
  return n is num && n.isFinite ? n.toDouble().clamp(min, max) : fallback;
}

/// Independent, versioned preferences for every avatar. Malformed/old values
/// fall back individually; no migration deletes a legacy asset or preference.
class AvatarStyle {
  Color primary = const Color(0xFF00FFC2), secondary = const Color(0xFF00D5FF);
  Color particles = const Color(0xFF9FFFE7),
      lightning = const Color(0xFF79EEFF);
  Color background = const Color(0xFF01080C);
  double scale = 1, x = 0, y = 0, speed = 1, density = .6, particleSize = 1;
  double glitter = .7,
      lightningFrequency = .3,
      outerMotion = 1,
      backgroundMotion = .5,
      lipSync = .7;
  bool intro = true, outro = true, audio = false;
  GraphicsProfile profile = GraphicsProfile.balanced;

  AvatarStyle();
  factory AvatarStyle.preset(AvatarModel model) {
    final s = AvatarStyle();
    final colors = switch (model) {
      AvatarModel.violet => (0xFFBB77FF, 0xFFFF55D5),
      AvatarModel.golden => (0xFFFFCD44, 0xFFFF7B21),
      AvatarModel.angelic => (0xFFCAEEFF, 0xFFFFD995),
      AvatarModel.crystal => (0xFF77EEFF, 0xFFAA88FF),
      AvatarModel.cosmic => (0xFF7B83FF, 0xFFFF69D2),
      AvatarModel.nature => (0xFF56FF83, 0xFFD3FF79),
      AvatarModel.plasma => (0xFFFF7958, 0xFFFF3A99),
      AvatarModel.lightning => (0xFF35BCFF, 0xFFE4F7FF),
      _ => (0xFF00FFC2, 0xFF00D5FF),
    };
    s.primary = Color(colors.$1);
    s.secondary = Color(colors.$2);
    return s;
  }
  factory AvatarStyle.fromJson(Map m, AvatarModel model) {
    final s = AvatarStyle.preset(model);
    Color c(String k, Color d) => parseHexColor('${m[k]}') ?? d;
    s.primary = c('primary', s.primary);
    s.secondary = c('secondary', s.secondary);
    s.particles = c('particles', s.particles);
    s.lightning = c('lightning', s.lightning);
    s.background = c('background', s.background);
    s.scale = _bounded(m, 'scale', 1, .4, 1.6);
    s.x = _bounded(m, 'x', 0, -.5, .5);
    s.y = _bounded(m, 'y', 0, -.4, .4);
    s.speed = _bounded(m, 'speed', 1, .2, 2);
    s.density = _bounded(m, 'density', .6, 0, 1);
    s.particleSize = _bounded(m, 'particleSize', 1, .3, 3);
    s.glitter = _bounded(m, 'glitter', .7, 0, 1);
    s.lightningFrequency = _bounded(m, 'lightningFrequency', .3, 0, 1);
    s.outerMotion = _bounded(m, 'outerMotion', 1, 0, 2);
    s.backgroundMotion = _bounded(m, 'backgroundMotion', .5, 0, 2);
    s.lipSync = _bounded(m, 'lipSync', .7, 0, 1);
    s.intro = m['intro'] is bool ? m['intro'] : true;
    s.outro = m['outro'] is bool ? m['outro'] : true;
    s.audio = m['audio'] == true;
    s.profile = GraphicsProfile.values.firstWhere(
      (p) => p.name == m['profile'],
      orElse: () => GraphicsProfile.balanced,
    );
    return s;
  }
  Map<String, dynamic> toJson() => {
    'primary': colorHex(primary),
    'secondary': colorHex(secondary),
    'particles': colorHex(particles),
    'lightning': colorHex(lightning),
    'background': colorHex(background),
    'scale': scale,
    'x': x,
    'y': y,
    'speed': speed,
    'density': density,
    'particleSize': particleSize,
    'glitter': glitter,
    'lightningFrequency': lightningFrequency,
    'outerMotion': outerMotion,
    'backgroundMotion': backgroundMotion,
    'lipSync': lipSync,
    'intro': intro,
    'outro': outro,
    'audio': audio,
    'profile': profile.name,
  };
}

class AvatarPreferences extends ChangeNotifier {
  AvatarPreferences();
  static final instance = AvatarPreferences();
  static const storageKey = 'jarvis_avatar_library_v1';
  AvatarModel selected = AvatarModel.originalOrb;
  final Map<AvatarModel, AvatarStyle> _styles = {};
  AvatarStyle styleFor(AvatarModel model) =>
      _styles.putIfAbsent(model, () => AvatarStyle.preset(model));
  AvatarStyle get current => styleFor(selected);
  double dockHeight = 52, dockWidth = 1, dockX = 0, dockBottom = 6;
  Color dockColor = const Color(0xFF00D5FF);
  bool _loaded = false;
  Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    try {
      final m = jsonDecode(p.getString(storageKey) ?? '{}') as Map;
      selected = AvatarModel.values.firstWhere(
        (v) => v.name == m['selected'],
        orElse: () => AvatarModel.originalOrb,
      );
      final styles = m['styles'];
      if (styles is Map) {
        for (final model in AvatarModel.values) {
          if (styles[model.name] is Map)
            _styles[model] = AvatarStyle.fromJson(styles[model.name], model);
        }
      }
      dockHeight = _bounded(m, 'dockHeight', 52, 48, 88);
      dockWidth = _bounded(m, 'dockWidth', 1, .65, 1);
      dockX = _bounded(m, 'dockX', 0, -1, 1);
      dockBottom = _bounded(m, 'dockBottom', 6, 0, 180);
      dockColor = parseHexColor('${m['dockColor']}') ?? dockColor;
    } catch (_) {
      /* Keep recoverable defaults, never prevent startup. */
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> select(AvatarModel model) async {
    selected = model;
    await save();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      storageKey,
      jsonEncode({
        'selected': selected.name,
        'styles': {
          for (final e in _styles.entries) e.key.name: e.value.toJson(),
        },
        'dockHeight': dockHeight,
        'dockWidth': dockWidth,
        'dockX': dockX,
        'dockBottom': dockBottom,
        'dockColor': colorHex(dockColor),
      }),
    );
    notifyListeners();
  }
}
