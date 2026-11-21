import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../brain/visual_bus.dart';

class HologramThemeStore extends ValueNotifier<String> {
  HologramThemeStore() : super('snake');
  static final instance = HologramThemeStore().._listenForVisualRequests();
  void _listenForVisualRequests() {
    visualBus.addListener(() {
      const themesByMode = {'serpent': 'snake', 'core': 'solar', 'aira': 'forest',
        'office': 'apex', 'apex': 'apex', 'mira': 'mira'};
      final theme = themesByMode[visualBus.value?.mode];
      if (theme != null) select(theme);
    });
  }
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
