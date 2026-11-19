import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: deprecated_member_use
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/services/gemini_live/gemini_live_protocol.dart';
import 'package:private_agent/services/gemini_live/gemini_live_transport.dart';
import 'package:private_agent/services/gemini_live/live_voice_controller.dart';
import 'package:private_agent/services/live_voice_session.dart';

final _future = DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String();

http.Client _broker({String token = 'auth_tokens/ephemeral-abc', String? exp, int status = 200}) =>
    MockClient((req) async {
      expect(req.url.scheme, 'https');
      expect(req.headers['Authorization'], startsWith('Bearer '));
      return http.Response(jsonEncode({'token': token, 'expireTime': exp ?? _future}), status);
    });

class FakeSocket implements LiveSocket {
  final ctl = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;
  bool autoSetup = true;
  @override
  Stream<dynamic> get frames => ctl.stream;
  @override
  void send(String text) {
    sent.add(text);
    if (autoSetup && text.contains('"setup"')) {
      scheduleMicrotask(() => ctl.add(jsonEncode({'setupComplete': {}})));
    }
  }
  @override
  Future<void> close() async {
    closed = true;
    await ctl.close();
  }
}

class FakeAudio implements LiveAudioIo {
  final ctl = StreamController<Map<Object?, Object?>>.broadcast();
  final played = <int>[];
  var captures = 0, stops = 0, flushes = 0, releases = 0;
  bool grant = true;
  @override
  Stream<Map<Object?, Object?>> get events => ctl.stream;
  @override
  Future<bool> startCapture() async {
    captures++;
    return grant;
  }
  @override
  Future<void> stopCapture() async => stops++;
  @override
  Future<void> play(Uint8List pcm, int rate) async => played.add(rate);
  @override
  Future<void> flush() async => flushes++;
  @override
  Future<void> release() async => releases++;
}

String _audioFrame(int rate) => jsonEncode({
      'serverContent': {
        'modelTurn': {
          'parts': [
            {'inlineData': {'mimeType': 'audio/pcm;rate=$rate', 'data': base64Encode(List.filled(480, 7))}},
          ],
        },
      },
    });

void main() {
  group('protocol', () {
    test('setup requests audio, voice, language, transcription and barge-in', () {
      final j = jsonDecode(buildSetupMessage(const LiveConfig(model: 'gemini-x', voice: 'Kore',
          languageCode: 'ta-IN')))['setup'] as Map;
      expect(j['model'], 'models/gemini-x');
      expect(j['generationConfig']['responseModalities'], ['AUDIO']);
      expect(j['generationConfig']['speechConfig']['voiceConfig']['prebuiltVoiceConfig']['voiceName'], 'Kore');
      expect(j['generationConfig']['speechConfig']['languageCode'], 'ta-IN');
      expect(j.containsKey('inputAudioTranscription'), isTrue);
      expect(j['realtimeInputConfig']['activityHandling'], 'START_OF_ACTIVITY_INTERRUPTS');
      expect(jsonEncode(j), isNot(contains('key')));
    });

    test('audio chunks are 16 kHz PCM base64', () {
      final m = jsonDecode(buildAudioChunk(Uint8List.fromList([1, 2, 3, 4])));
      expect(m['realtimeInput']['audio']['mimeType'], 'audio/pcm;rate=16000');
      expect(base64Decode(m['realtimeInput']['audio']['data']), [1, 2, 3, 4]);
    });

    test('uses constrained ephemeral-token endpoint, not an API key param', () {
      final u = liveSocketUri('auth_tokens/abc');
      expect(u.scheme, 'wss');
      expect(u.path, contains('BidiGenerateContentConstrained'));
      expect(u.queryParameters.keys, ['access_token']);
    });

    test('parses audio, interruption, transcripts, turn end, goAway, binary frames', () {
      final audio = parseServerFrame(_audioFrame(24000)).single as LiveAudioOut;
      expect(audio.rate, 24000);
      expect(audio.pcm.length, 480);
      expect(parseServerFrame('{"serverContent":{"interrupted":true}}').single, isA<LiveInterrupted>());
      final t = parseServerFrame(jsonEncode({'serverContent': {
        'inputTranscription': {'text': 'vanakkam'}, 'outputTranscription': {'text': 'hello'},
        'turnComplete': true}}));
      expect(t.whereType<LiveTranscript>().map((e) => e.fromUser), [true, false]);
      expect(t.last, isA<LiveTurnComplete>());
      expect(parseServerFrame('{"goAway":{"timeLeft":"5s"}}').single, isA<LiveGoAway>());
      expect(parseServerFrame(utf8.encode('{"setupComplete":{}}')).single, isA<LiveSetupComplete>());
      expect(parseServerFrame('not json').single, isA<LiveUnknown>());
    });

    test('PCM resampling and level metering', () {
      final b = ByteData(48000 * 2 ~/ 10);
      for (var i = 0; i < b.lengthInBytes ~/ 2; i++) {
        b.setInt16(i * 2, (i.isEven ? 12000 : -12000), Endian.little);
      }
      final src = b.buffer.asUint8List();
      final out = resamplePcm16(src, 48000, 16000);
      expect(out.length, closeTo(src.length / 3, 2));
      expect(pcmLevel(src), greaterThan(.5));
      expect(pcmLevel(Uint8List(320)), 0);
    });
  });

  group('token broker client', () {
    test('accepts short-lived token', () async {
      final g = await LiveTokenClient(endpoint: 'https://broker.example/live',
          ownerSessionToken: 'dev_0123456789abcdef', client: _broker()).fetch(locale: 'ta-IN');
      expect(g.token, startsWith('auth_tokens/'));
    });

    test('refuses http broker, raw API keys, long-lived or expired tokens', () async {
      expect(LiveTokenClient.validateEndpoint('http://broker.example'), isNotNull);
      expect(LiveTokenClient.validateEndpoint('https://broker.example/?key=abc'), isNotNull);
      Future<void> bad(http.Client c) => expectLater(
          LiveTokenClient(endpoint: 'https://b.example', ownerSessionToken: 't' * 20, client: c)
              .fetch(locale: 'en-IN'), throwsA(isA<LiveTokenException>()));
      await bad(_broker(token: 'AIzaSyFAKE_FAKE_FAKE_FAKE_FAKE_FAKE_FAKE'));
      await bad(_broker(exp: DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String()));
      await bad(_broker(exp: DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String()));
      await bad(_broker(status: 403));
    });
  });

  group('transport', () {
    GeminiLiveTransport make(FakeSocket s, FakeAudio a, {Duration? timeout}) => GeminiLiveTransport(
        tokens: LiveTokenClient(endpoint: 'https://b.example', ownerSessionToken: 't' * 20,
            client: _broker()),
        audio: a, model: 'gemini-x', socketFactory: (_) async => s,
        setupTimeout: timeout ?? const Duration(seconds: 2));

    test('connect → setup → capture → stream mic → play → barge-in → clean stop', () async {
      final s = FakeSocket(), a = FakeAudio();
      final t = make(s, a);
      await t.connect(voice: 'Aoede', locale: 'ta-IN');
      expect(s.sent.first, contains('"setup"'));
      expect(a.captures, 1);
      final pcm = Uint8List.fromList(List.filled(3200, 3));
      a.ctl.add({'type': 'mic', 'pcm': pcm});
      await pumpEventQueue();
      expect(s.sent.last, contains('realtimeInput'));
      expect(t.sentChunks, 1);
      t.muted = true;
      a.ctl.add({'type': 'mic', 'pcm': pcm});
      await pumpEventQueue();
      expect(t.sentChunks, 1, reason: 'muted mic must not stream');
      s.ctl.add(_audioFrame(24000));
      await pumpEventQueue();
      expect(a.played, [24000]);
      s.ctl.add('{"serverContent":{"interrupted":true}}');
      await pumpEventQueue();
      expect(a.flushes, 1);
      await t.disconnect();
      expect(a.stops, 1);
      expect(a.releases, 1);
      expect(s.closed, isTrue);
      expect(s.sent.last, contains('audioStreamEnd'));
    });

    test('setup timeout releases everything and throws', () async {
      final s = FakeSocket()..autoSetup = false, a = FakeAudio();
      final t = make(s, a, timeout: const Duration(milliseconds: 50));
      await expectLater(t.connect(voice: 'Aoede', locale: 'ta-IN'), throwsA(anything));
      expect(a.captures, 0, reason: 'no mic before setup completes');
      expect(s.closed, isTrue);
    });

    test('focus loss and server close surface as drops', () async {
      final s = FakeSocket(), a = FakeAudio();
      final t = make(s, a);
      final drops = <LiveDropReason>[];
      t.drops.listen(drops.add);
      await t.connect(voice: 'Aoede', locale: 'ta-IN');
      a.ctl.add({'type': 'focus', 'value': 'lost'});
      await pumpEventQueue();
      await s.ctl.close();
      await pumpEventQueue();
      expect(drops, [LiveDropReason.focusLost, LiveDropReason.serverClosed]);
    });

    test('real WebSocket round-trip against a local mock Live server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <String>[];
      String? query;
      server.listen((req) async {
        query = req.uri.query;
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((m) {
          received.add(m as String);
          if (m.contains('"setup"')) ws.add(jsonEncode({'setupComplete': {}}));
          if (m.contains('realtimeInput') && !m.contains('audioStreamEnd')) {
            ws.add(utf8.encode(_audioFrame(24000))); // binary JSON like the real API
          }
        });
      });
      final a = FakeAudio();
      final t = GeminiLiveTransport(
        tokens: LiveTokenClient(endpoint: 'https://b.example', ownerSessionToken: 't' * 20,
            client: _broker()),
        audio: a, model: 'gemini-x',
        socketFactory: (uri) => IoLiveSocket.connect(uri.replace(
            scheme: 'ws', host: '127.0.0.1', port: server.port)),
      );
      await t.connect(voice: 'Leda', locale: 'en-IN');
      a.ctl.add({'type': 'mic', 'pcm': Uint8List(3200)});
      for (var i = 0; i < 50 && a.played.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(query, 'access_token=auth_tokens%2Fephemeral-abc');
      expect(received.first, contains('Leda'));
      expect(a.played, [24000]);
      await t.disconnect();
      await server.close(force: true);
    });
  });

  group('controller', () {
    setUp(() => SharedPreferences.setMockInitialValues({
          'gemini_live_broker_url': 'https://broker.example/live',
          'gemini_live_device_token': 'dev_0123456789abcdef',
        }));

    LiveVoiceController make(FakeSocket s, FakeAudio a, {bool mic = true, List<String>? log}) =>
        LiveVoiceController(
          observeLifecycle: false,
          requestMicPermission: () async {
            log?.add('perm');
            return mic;
          },
          pauseOtherMic: () async => log?.add('pause-wakeword'),
          transportFactory: (st) => GeminiLiveTransport(
            tokens: LiveTokenClient(endpoint: st.brokerUrl, ownerSessionToken: st.deviceToken,
                client: _broker()),
            audio: a, model: st.model, socketFactory: (_) async => s),
        );

    test('no consent, no mic permission or no broker → never connects', () async {
      final s = FakeSocket(), a = FakeAudio();
      final c = make(s, a, mic: false);
      await c.load();
      expect(await c.start(consent: false), isFalse);
      expect(await c.start(consent: true), isFalse);
      expect(c.message, contains('Microphone permission'));
      expect(s.sent, isEmpty);
      SharedPreferences.setMockInitialValues({});
      final d = make(s, a);
      await d.load();
      expect(await d.start(consent: true), isFalse);
      expect(d.message, contains('DISCONNECTED'));
    });

    test('start pauses the wake-word mic first, then goes live; stop releases', () async {
      final s = FakeSocket(), a = FakeAudio(), log = <String>[];
      final c = make(s, a, log: log);
      await c.load();
      expect(await c.start(consent: true), isTrue);
      expect(log, ['perm', 'pause-wakeword']);
      expect(c.status, LiveVoiceStatus.listening);
      await c.stop();
      expect(c.status, LiveVoiceStatus.idle);
      expect(a.releases, greaterThanOrEqualTo(1));
    });

    test('server close mid-session → FAILED with safe message, no silent restart', () async {
      final s = FakeSocket(), a = FakeAudio();
      final c = make(s, a);
      await c.load();
      await c.start(consent: true);
      await s.ctl.close();
      await pumpEventQueue();
      expect(c.status, LiveVoiceStatus.failed);
      expect(c.message, 'Live connection closed; tap to start again');
    });

    testWidgets('app going to background stops Live', (tester) async {
      final s = FakeSocket(), a = FakeAudio();
      final c = LiveVoiceController(
        requestMicPermission: () async => true,
        transportFactory: (st) => GeminiLiveTransport(
          tokens: LiveTokenClient(endpoint: st.brokerUrl, ownerSessionToken: st.deviceToken,
              client: _broker()),
          audio: a, model: st.model, socketFactory: (_) async => s),
      );
      await tester.runAsync(() async {
        await c.load();
        await c.start(consent: true);
      });
      expect(c.active, isTrue);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.runAsync(() => pumpEventQueue());
      expect(c.active, isFalse);
      c.dispose();
    });
  });
}
