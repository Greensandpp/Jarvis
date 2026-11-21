import 'dart:math' as math;
// TEST DOUBLES: the microphone is a scripted LiveAudioIo and Gemini is a
// package:http MockClient. Real Tamil/Tanglish recognition accuracy and the
// voices on the owner's iQOO 13 stay UNVERIFIED until tested on the phone.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/brain/language.dart';
import 'package:private_agent/services/gemini_dictation.dart';
import 'package:private_agent/services/gemini_live/gemini_live_transport.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:private_agent/services/voice_selection.dart';
import 'package:private_agent/services/voice_service.dart';

/// Scripted microphone: [speechMs] of a 440 Hz tone, then silence.
class FakeMic implements LiveAudioIo {
  FakeMic({this.speechMs = 1200, this.silenceMs = 2000});
  final int speechMs;
  final int silenceMs;
  final _events = StreamController<Map<Object?, Object?>>.broadcast();
  var started = 0, stopped = 0;

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  Uint8List _chunk(bool loud) {
    const n = 1600; // 100 ms at 16 kHz
    final b = ByteData(n * 2);
    for (var i = 0; i < n; i++) {
      final v = loud
          ? (math.sin(2 * math.pi * 440 * i / 16000) * 12000).round()
          : 0;
      b.setInt16(i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  @override
  Future<bool> startCapture() async {
    started++;
    scheduleMicrotask(() async {
      for (var t = 0; t < speechMs + silenceMs; t += 100) {
        if (stopped > 0) break;
        _events.add({'type': 'mic', 'pcm': _chunk(t < speechMs)});
        await Future<void>.delayed(Duration.zero);
      }
    });
    return true;
  }

  @override
  Future<void> stopCapture() async => stopped++;
  @override
  Future<void> play(Uint8List pcm, int rate) async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> release() async {}
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  group('voice selection (Tamil / English, female, offline first)', () {
    final voices = [
      for (final m in [
        {
          'name': 'ta-in-x-tad-network',
          'locale': 'ta-IN',
          'network_required': '1',
        },
        {
          'name': 'ta-in-x-tac-local',
          'locale': 'ta-IN',
          'network_required': '0',
        },
        {'name': 'en-in-x-ene#male_1-local', 'locale': 'en-IN'},
        {'name': 'en-in-x-ahp#female_2-local', 'locale': 'en-IN'},
        {
          'name': 'en-in-x-cxx-network',
          'locale': 'en_IN',
          'gender': 'female',
          'network_required': '1',
        },
        {'name': 'en-us-x-sfg#female_1-local', 'locale': 'en-US'},
        {'name': '', 'locale': 'en-IN'},
        'not a map',
      ])
        TtsVoice.fromMap(m),
    ].whereType<TtsVoice>().toList();

    test('parses gender only from engine data; never guesses', () {
      expect(voices, hasLength(6));
      final byName = {for (final v in voices) v.name: v};
      expect(byName['en-in-x-ahp#female_2-local']!.gender, VoiceGender.female);
      expect(byName['en-in-x-ene#male_1-local']!.gender, VoiceGender.male);
      expect(byName['en-in-x-cxx-network']!.gender, VoiceGender.female);
      expect(byName['ta-in-x-tac-local']!.gender, VoiceGender.unknown);
      expect(byName['ta-in-x-tad-network']!.networkRequired, isTrue);
      expect(byName['en-in-x-cxx-network']!.locale, 'en-in');
      expect(byName['en-in-x-cxx-network']!.toFlutterTts()['locale'], 'en-IN');
      expect(byName['ta-in-x-tac-local']!.toFlutterTts()['locale'], 'ta-IN');
    });

    test(
      'female + offline preferred; Tamil falls back to an offline voice with honest reason',
      () {
        final en = chooseVoice(voices, 'en-IN');
        expect(
          en.voice!.name,
          'en-in-x-ahp#female_2-local',
          reason: 'female and works offline',
        );
        expect(en.reason, contains('female'));
        expect(
          chooseVoice(voices, 'en-IN', online: true).voice!.gender,
          VoiceGender.female,
        );
        final ta = chooseVoice(voices, 'ta-IN');
        expect(ta.voice!.name, 'ta-in-x-tac-local');
        expect(ta.reason, contains('gender not reported'));
        expect(
          chooseVoice(voices, 'en-IN', preferFemale: false).voice!.gender,
          VoiceGender.male,
        );
        expect(
          chooseVoice(voices, 'ta-IN', pinned: 'ta-in-x-tad-network').reason,
          'chosen by you',
        );
        expect(
          chooseVoice(
            voices,
            'ta-IN',
            pinned: 'en-in-x-ahp#female_2-local',
          ).voice!.locale,
          'ta-in',
          reason: 'a stale English pin cannot override Tamil',
        );
        final none = chooseVoice(voices, 'hi-IN');
        expect(none.voice, isNull);
        expect(none.reason, contains('engine default'));
      },
    );
  });

  group('Tamil / English / Tanglish input + output', () {
    test(
      'speech engine routing: Gemini only for mic taps, only when allowed',
      () {
        String e({
          String setting = 'auto',
          bool manual = true,
          bool available = true,
          bool broken = false,
          bool allowed = true,
        }) => VoiceService.engineFor(
          setting: setting,
          manual: manual,
          deviceAvailable: available,
          deviceBroken: broken,
          geminiAllowed: allowed,
        );
        expect(e(), 'device');
        expect(
          e(broken: true),
          'gemini',
          reason: 'phone recogniser failed earlier (iQOO case)',
        );
        expect(e(available: false), 'gemini');
        expect(e(setting: 'gemini'), 'gemini');
        expect(
          e(setting: 'gemini', manual: false),
          'device',
          reason: 'never stream always-on audio to the cloud',
        );
        expect(
          e(broken: true, allowed: false),
          'device',
          reason: 'Privacy Lock off → phone recogniser',
        );
        expect(e(setting: 'device', broken: true), 'device');
      },
    );

    test(
      'settings: bilingual auto microphone language and engine are persisted and validated',
      () async {
        final s = SettingsService.instance;
        expect(s.speechInputLocale, 'auto');
        await s.setSpeechInputLocale('ta-IN');
        expect(s.speechInputLocale, 'ta-IN');
        await s.setSpeechInputLocale('xx');
        expect(s.speechInputLocale, 'ta-IN');
        await s.setSpeechInputLocale('auto');
        expect(s.speechEngine, 'auto');
        await s.setSpeechEngine('gemini');
        expect(s.speechEngine, 'gemini');
        await s.setSpeechEngine('auto');
      },
    );

    test(
      'reply language and voice follow what was said (Tamil script / Tanglish / English)',
      () {
        expect(
          detectLanguage('இன்னைக்கு நிஃப்டி எப்படி இருக்கு?'),
          ReplyLanguage.tamil,
        );
        expect(
          detectLanguage('Machi inniki market epdi irukku'),
          ReplyLanguage.tanglish,
        );
        expect(detectLanguage('What is the time now?'), ReplyLanguage.english);
      },
    );

    test('free-only dictation denies remote inference before microphone capture', () async {
      final settings = SettingsService.instance;
      await settings.setProvider('gemini');
      await settings.setApiKey('test-only');
      await settings.setAllowCloudAi(true);
      final mic = FakeMic();
      var requests = 0;
      final dictation = GeminiDictation(audio: mic, client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }));
      expect(dictation.unavailableReason, contains('free-only'));
      await expectLater(dictation.listenOnce(), throwsStateError);
      expect(mic.started, 0);
      expect(requests, 0);
      await settings.setAllowCloudAi(false);
      await expectLater(dictation.listenOnce(), throwsStateError);
      expect(mic.started, 0);
    });

    test('transcript clean-up and WAV helpers', () {
      expect(cleanTranscript('Transcript: “வணக்கம் JARVIS”'), 'வணக்கம் JARVIS');
      expect(cleanTranscript('(no speech)'), '');
      expect(cleanTranscript('  open   whatsapp '), 'open whatsapp');
      final wav = pcmToWav(Uint8List(3200), 16000);
      final bd = ByteData.sublistView(wav);
      expect(bd.getUint32(24, Endian.little), 16000);
      expect(bd.getUint32(40, Endian.little), 3200);
      expect(pcmLevel(Uint8List(0)), 0);
    });
  });
}
