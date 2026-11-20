import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:private_agent/main.dart' as app;
import 'package:private_agent/jarvis_v3/holographic_stage.dart';
import 'package:private_agent/jarvis_v3/hologram_theme_store.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:private_agent/services/voice_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real Android startup is silent; WebGL renders moving skeletons and persists themes',
    (tester) async {
      await app.main();
      await tester.pump();
      expect(find.byType(HolographicStage), findsOneWidget);
      expect(find.byKey(const ValueKey('v3-dock')), findsOneWidget);
      final stage = tester.state<HolographicStageState>(
        find.byType(HolographicStage),
      );
      for (
        var i = 0;
        i < 80 && !stage.renderingReady && stage.rendererError == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
      }
      expect(stage.rendererError, isNull);
      expect(stage.renderingReady, isTrue);
      expect(VoiceService.instance.isSpeaking.value, isFalse);
      expect(VoiceService.instance.isListening, isFalse);
      expect(SettingsService.instance.jarvisAlwaysOn, isFalse);
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump();
      final a = await stage.snapshot();
      expect(a['engine'], 'Three.js r180 WebGL');
      expect(a['bones'], greaterThanOrEqualTo(36));
      expect(a['snakeBones'], 32);
      expect(a['intro'], 'done');
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
      final b = await stage.snapshot();
      expect(a['humanoidHead'], isNot(equals(b['humanoidHead'])));
      expect(a['snakeHead'], isNot(equals(b['snakeHead'])));
      // Change persisted theme only. The same scene and the same audio session survive.
      for (final theme in HologramThemeStore.themes) {
        await HologramThemeStore.instance.select(theme);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect((await stage.snapshot())['theme'], theme);
        expect(tester.state(find.byType(HolographicStage)), same(stage));
        expect(VoiceService.instance.isSpeaking.value, isFalse);
        final reload = HologramThemeStore();
        await reload.load();
        expect(reload.value, theme);
      }
      // UI screen evidence includes the real platform WebView (not a flutter_tester placeholder).
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('android-real-hologram');
      debugPrint('HOLOGRAM_ACCEPT PASS ${await stage.snapshot()}');
    },
  );
}
