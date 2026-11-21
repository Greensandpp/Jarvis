// Platform channel doubles: verifies the actual VoiceService routing, not
// physical sound or the voices installed on the owner's phone.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:private_agent/services/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pending = <Completer<dynamic>>[];
  final calls = <String>[];
  var acceptVoice = true;
  setUp(() async {
    acceptVoice = true;
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.privateagent/speech'),
      (call) async => true,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.privateagent/accessibility'),
      (call) async => true,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'getVoices')
        return [
          {
            'name': 'en-in-female-local',
            'locale': 'en-IN',
            'gender': 'female',
            'network_required': '0',
          },
        ];
      if (call.method == 'setVoice')
        return acceptVoice && (call.arguments as Map)['locale'] == 'en-IN'
            ? 1
            : 0;
      if (call.method == 'isLanguageAvailable') return true;
      if (call.method == 'speak') {
        final c = Completer<dynamic>();
        pending.add(c);
        return c.future;
      }
      return 1;
    });
  });
  tearDown(() async {
    await VoiceService.instance.stopSpeaking();
    for (final c in pending) {
      if (!c.isCompleted) c.complete(1);
    }
    pending.clear();
    calls.clear();
  });
  test(
    'current focus loss stops output and late completion cannot replay it',
    () async {
      final voice = VoiceService.instance;
      final completions = voice.completedSpeech.value;
      final work = voice.speak('interrupt this reply');
      for (var i = 0; i < 50 && pending.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(pending, hasLength(1));
      final done = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'com.privateagent/speech',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('onOutputFocusLost', voice.output.activeRequestId),
            ),
            (_) => done.complete(),
          );
      await done.future;
      await work;
      expect(voice.isSpeaking.value, isFalse);
      pending.single.complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(voice.isSpeaking.value, isFalse);
      expect(calls.where((v) => v == 'speak'), hasLength(1));
      expect(
        voice.completedSpeech.value,
        completions,
        reason: 'interruption is not successful completion',
      );
    },
  );
  test('a rejected voice cannot silently use the engine default', () async {
    acceptVoice = false;
    await VoiceService.instance.speak('requested female voice');
    expect(calls.where((v) => v == 'speak'), isEmpty);
    expect(VoiceService.instance.lastVoiceUsed, contains('text only'));
  });
  test('denied focus cannot start TTS playback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.privateagent/speech'),
          (call) async => call.method != 'acquireOutputFocus',
        );
    await VoiceService.instance.speak('must stay text only');
    expect(calls.where((v) => v == 'speak'), isEmpty);
    expect(VoiceService.instance.isSpeaking.value, isFalse);
  });
  test(
    'cancel and replace use one TTS instance; stale completion cannot clear new output',
    () async {
      final voice = VoiceService.instance;
      final a = voice.speak('first reply');
      for (var i = 0; i < 30 && pending.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(pending.length, 1);
      final oldRequest = voice.output.activeRequestId;
      expect(voice.isSpeaking.value, isTrue);
      await voice.stopSpeaking();
      await a;
      expect(voice.isSpeaking.value, isFalse);
      final b = voice.speak('replacement reply');
      for (var i = 0; i < 30 && pending.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(pending.length, 2);
      expect(voice.isSpeaking.value, isTrue);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final stale = Completer<void>();
      messenger.handlePlatformMessage(
        'com.privateagent/speech',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onOutputFocusLost', oldRequest),
        ),
        (_) => stale.complete(),
      );
      await stale.future;
      expect(
        voice.isSpeaking.value,
        isTrue,
        reason: 'stale focus loss cannot cancel the new request',
      );
      pending.first.complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(
        voice.isSpeaking.value,
        isTrue,
        reason: 'late first completion must not own the second session',
      );
      pending.last.complete(1);
      await b;
      expect(voice.isSpeaking.value, isFalse);
      expect(calls.where((v) => v == 'speak').length, 2);
    },
  );
}
