import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HologramThemeStore extends ValueNotifier<String> {
  HologramThemeStore() : super('snake');
  static final instance = HologramThemeStore();
  static const themes = ['snake', 'forest', 'solar', 'inferno', 'apex', 'mira'];
  static const storageKey = 'jarvis_hologram_theme_v1';
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(storageKey);
    if (themes.contains(saved)) value = saved!;
  }

  Future<void> select(String theme) async {
    if (!themes.contains(theme)) return;
    value = theme;
    final p = await SharedPreferences.getInstance();
    await p.setString(storageKey, theme);
  }
}
