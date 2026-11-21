import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      const audio = MethodChannel('com.privateagent/speech');
      expect(
        await audio.invokeMethod<bool>('acquireOutputFocus', {
          'requestId': 9001,
        }),
        isTrue,
      );
      expect(await audio.invokeMethod<bool>('releaseOutputFocus'), isTrue);
      expect(
        await audio.invokeMethod<bool>('acquireOutputFocus', {'requestId': -1}),
        isFalse,
      );
      // Real Android MediaPlayer, not a channel double. Rapid cancellation
      // must leave no pending player and no delayed restart.
      const player = MethodChannel('com.privateagent/accessibility');
      final wav = Uint8List(44 + 256000);
      final data = ByteData.sublistView(wav);
      wav.setRange(0, 4, 'RIFF'.codeUnits);
      data.setUint32(4, wav.length - 8, Endian.little);
      wav.setRange(8, 12, 'WAVE'.codeUnits);
      wav.setRange(12, 16, 'fmt '.codeUnits);
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, 1, Endian.little);
      data.setUint32(24, 16000, Endian.little);
      data.setUint32(28, 32000, Endian.little);
      data.setUint16(32, 2, Endian.little);
      data.setUint16(34, 16, Endian.little);
      wav.setRange(36, 40, 'data'.codeUnits);
      data.setUint32(40, 256000, Endian.little);
      final fixture = File(
        '${(await getTemporaryDirectory()).path}/jarvis-cancel-test.wav',
      );
      await fixture.writeAsBytes(wav);
      var preparingSamples = 0;
      for (var n = 0; n < 5; n++) {
        expect(
          await audio.invokeMethod<bool>('acquireOutputFocus', {
            'requestId': 9100 + n,
          }),
          isTrue,
        );
        final playback = player.invokeMethod<bool>('playAudioFile', {
          'path': fixture.path,
        });
        final pendingState = await audio.invokeMapMethod<String, dynamic>(
          'outputDiagnostics',
        );
        if (pendingState?['preparing'] == true) preparingSamples++;
        expect(await player.invokeMethod<bool>('stopAudio'), isTrue);
        expect(await playback, isFalse);
        final stopped = await audio.invokeMapMethod<String, dynamic>(
          'outputDiagnostics',
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final later = await audio.invokeMapMethod<String, dynamic>(
          'outputDiagnostics',
        );
        expect(later!['pending'], isFalse);
        expect(later['preparing'], isFalse);
        expect(later['playing'], isFalse);
        expect(
          later['starts'],
          stopped!['starts'],
          reason: 'cancelled prepare callback must not restart audio',
        );
        await audio.invokeMethod<bool>('releaseOutputFocus');
      }
      await fixture.delete();
      debugPrint(
        'NATIVE_AUDIO_CANCEL PASS 5 native play/cancel requests; preparing observed: $preparingSamples; no delayed restart',
      );

      Map<String, dynamic> a = {};
      for (var n = 0; n < 90; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        a = await stage.snapshot();
        if (a['intro'] == 'done') break;
      }
      expect(a['engine'], 'Three.js r180 WebGL');
      expect(a['bones'], greaterThanOrEqualTo(36));
      expect(a['snakeBones'], 32);
      expect(a['intro'], 'done');
      expect(a['armourPlates'], greaterThan(150));
      expect(a['materials'], 4);
      Map<String, dynamic> b = {};
      for (var n = 0; n < 40; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
        b = await stage.snapshot();
        if ((b['frame'] as num) >= (a['frame'] as num) + 2) break;
      }
      expect(b['frame'], greaterThanOrEqualTo((a['frame'] as num) + 2));
      expect(a['humanoidHead'], isNot(equals(b['humanoidHead'])));
      expect(a['snakeHead'], isNot(equals(b['snakeHead'])));
      final bounds = b['snakeHeadBounds'] as Map;
      for (final v in bounds['min'] as List) {
        expect(v, greaterThan(-1));
      }
      for (final v in bounds['max'] as List) {
        expect(v, lessThan(1));
      }
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
