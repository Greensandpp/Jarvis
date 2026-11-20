import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/jarvis_v3/hologram_theme_store.dart';

void main() {
  test(
    'all six themes persist through a fresh store without touching voice',
    () async {
      SharedPreferences.setMockInitialValues({});
      for (final t in HologramThemeStore.themes) {
        await HologramThemeStore().select(t);
        final restarted = HologramThemeStore();
        await restarted.load();
        expect(restarted.value, t);
      }
      await HologramThemeStore().select('unknown');
      final restarted = HologramThemeStore();
      await restarted.load();
      expect(restarted.value, 'mira');
    },
  );
}
