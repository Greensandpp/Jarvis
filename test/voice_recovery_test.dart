import 'package:private_agent/services/voice_selection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:private_agent/services/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const tts = MethodChannel('flutter_tts');
  const speech = MethodChannel('com.privateagent/speech');
  const permission = MethodChannel('flutter.baseflow.com/permissions/methods');
  var granted = true, available = true, starts = 0;
  final voicesUsed = <String>[];

  setUp(() async {
    granted = true;
    available = true;
    starts = 0;
    voicesUsed.clear();
    SharedPreferences.setMockInitialValues({
      'jarvis_neural_voice': 'ta-IN-PallaviNeural',
      'privacy_allow_cloud_tts': false,
    });
    await SettingsService.instance.init();
    messenger.setMockMethodCallHandler(permission, (call) async {
      if (call.method == 'requestPermissions') {
        return {for (final id in call.arguments as List) id: granted ? 1 : 0};
      }
      return granted ? 1 : 0;
    });
    messenger.setMockMethodCallHandler(speech, (call) async {
      if (call.method == 'isAvailable') return available;
      if (call.method == 'startListening') starts++;
      return null;
    });
    messenger.setMockMethodCallHandler(tts, (call) async {
      if (call.method == 'getVoices') {
        // Default Tamil pack absent, English offline pack available.
        return [
          {
            'name': 'English female neural',
            'locale': 'en-IN',
            'gender': 'female',
            'network_required': '0',
          },
        ];
      }
      if (call.method == 'setVoice')
        voicesUsed.add('${call.arguments['name']}');
      if (call.method == 'speak') {
        Future<void>.delayed(const Duration(milliseconds: 10), () async {
          await messenger.handlePlatformMessage(
            'flutter_tts',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('speak.onComplete'),
            ),
            (_) {},
          );
        });
      }
      return 1;
    });
  });
  tearDown(() async {
    await VoiceService.instance.stopListening();
    await VoiceService.instance.stopSpeaking();
    messenger.setMockMethodCallHandler(permission, null);
    messenger.setMockMethodCallHandler(speech, null);
    messenger.setMockMethodCallHandler(tts, null);
  });

  test('Android 0/1 metadata excludes online and uninstalled voices', () {
    final selected = selectOfflineVoice([
      {'name': 'Online female', 'locale': 'ta-IN', 'network_required': '1'},
      {
        'name': 'Missing female',
        'locale': 'ta-IN',
        'network_required': '0',
        'features': 'notInstalled',
      },
      {
        'name': 'Local normal',
        'locale': 'ta-IN',
        'network_required': '0',
        'quality': 'normal',
      },
      {
        'name': 'Local high',
        'locale': 'ta-IN',
        'network_required': '0',
        'quality': 'very high',
      },
    ], 'ta-IN');
    expect(selected?['name'], 'Local high');
  });

  test(
    'English offline reply completes when default Tamil pack is missing',
    () async {
      await VoiceService.instance
          .speakIn(
            'Hello',
            languageTag: 'en-IN',
            neuralVoice: 'en-IN-NeerjaNeural',
            female: true,
          )
          .timeout(const Duration(seconds: 2));
      expect(voicesUsed, contains('English female neural'));
      expect(VoiceService.instance.isSpeaking.value, isFalse);
    },
  );
  test(
    'missing Tamil offline pack is reported without false playback',
    () async {
      await VoiceService.instance.speakIn(
        'வணக்கம்',
        languageTag: 'ta-IN',
        neuralVoice: 'ta-IN-PallaviNeural',
        female: true,
      );
      expect(voicesUsed, isEmpty);
      expect(
        VoiceService.instance.lastVoiceUsed,
        contains('No installed offline ta-IN'),
      );
    },
  );
  test(
    'revoked microphone permission blocks previously initialized recognizer',
    () async {
      final voice = VoiceService.instance;
      expect(await voice.startListening(onResult: (_, _, _) {}), isTrue);
      await voice.stopListening();
      granted = false;
      expect(await voice.startListening(onResult: (_, _, _) {}), isFalse);
      expect(starts, 1);
      expect(voice.isListening, isFalse);
    },
  );
  test('unavailable speech recognizer never starts microphone', () async {
    granted = false;
    await VoiceService.instance.initSpeech(); // Clear cached availability.
    granted = true;
    available = false;
    expect(
      await VoiceService.instance.startListening(onResult: (_, _, _) {}),
      isFalse,
    );
    expect(starts, 0);
  });
}
