// TEST DOUBLES: every HTTP call here goes to package:http MockClient (local,
// in-process). These prove JARVIS's classification/retry/fallback logic, NOT
// that a live provider works. Live Gemini stays UNVERIFIED until the owner
// enters a key on the phone.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/brain/ai_reliability.dart';
import 'package:private_agent/services/ai_service.dart';
import 'package:private_agent/services/settings_service.dart';

/// Exact body Google returned to the emulator for an invalid key (CI run 44580226200).
const googleInvalidKey = '{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.",'
    '"status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID"}]}}';

String chat(String text) => jsonEncode({'choices': [{'message': {'role': 'assistant', 'content': text}}]});

void main() {
  group('failure classification', () {
    test('HTTP codes map to distinct kinds; Google invalid key (400) is AUTH', () {
      expect(AiFailure.fromHttp(400, googleInvalidKey).kind, AiFailureKind.auth);
      expect(AiFailure.fromHttp(400, '{"error":{"message":"bad json"}}').kind, AiFailureKind.badRequest);
      expect(AiFailure.fromHttp(401, '').kind, AiFailureKind.auth);
      expect(AiFailure.fromHttp(403, '').kind, AiFailureKind.auth);
      expect(AiFailure.fromHttp(404, '').kind, AiFailureKind.modelNotFound);
      expect(AiFailure.fromHttp(429, '').kind, AiFailureKind.rateLimit);
      expect(AiFailure.fromHttp(503, '').kind, AiFailureKind.server);
    });

    test('transport exceptions: DNS vs TLS vs connect vs timeout', () {
      expect(AiFailure.fromException(const SocketException('Failed host lookup: generativelanguage.googleapis.com')).kind, AiFailureKind.dns);
      expect(AiFailure.fromException(http.ClientException('Failed host lookup: x')).kind, AiFailureKind.dns);
      expect(AiFailure.fromException(const HandshakeException('CERTIFICATE_VERIFY_FAILED')).kind, AiFailureKind.tls);
      expect(AiFailure.fromException(const SocketException('Connection refused')).kind, AiFailureKind.connect);
      expect(AiFailure.fromException(TimeoutException('x')).kind, AiFailureKind.timeout);
    });

    test('messages never contain keys', () {
      final f = AiFailure.fromHttp(400, '{"error":{"message":"bad key AIzaSyABCDEFGHIJKLMNOP1234 key=AIzaSyABCDEFGHIJKLMNOP1234"}}');
      expect(f.detail, isNot(contains('AIzaSy')));
      expect(redact('Bearer sk-abcdefghijklmnop'), contains('[redacted-key]'));
    });
  });

  test('retry with backoff on 429/5xx, not on 401', () async {
    final sleeps = <Duration>[];
    var n = 0;
    final v = await withRetry(() async {
      n++;
      if (n < 3) throw AiFailure.fromHttp(n == 1 ? 429 : 503, '');
      return 'ok';
    }, sleep: (d) async => sleeps.add(d));
    expect(v, 'ok');
    expect(sleeps, hasLength(2));
    expect(sleeps[1] > sleeps[0], isTrue);
    n = 0;
    await expectLater(withRetry(() async { n++; throw AiFailure.fromHttp(401, ''); }, sleep: (d) async {}),
        throwsA(isA<AiFailure>().having((f) => f.kind, 'kind', AiFailureKind.auth)));
    expect(n, 1);
  });

  test('model discovery parses OpenAI-compatible list and filters non-chat models', () async {
    final c = MockClient((r) async {
      expect(r.url.path, '/v1beta/openai/models');
      expect(r.headers['Authorization'], 'Bearer k');
      return http.Response(jsonEncode({'data': [
        {'id': 'models/gemini-2.5-flash'}, {'id': 'models/gemini-2.5-pro'},
        {'id': 'models/text-embedding-004'}, {'id': 'models/gemini-2.5-flash-preview-tts'}, {'id': 'gemini-2.0-flash'},
      ]}), 200);
    });
    final ms = await discoverModels(c, 'https://generativelanguage.googleapis.com/v1beta/openai', 'k');
    expect(ms, ['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.0-flash']);
    expect(fallbackOrder('old', ms), ['old', 'gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-2.5-pro']);
  });

  group('diagnostics (test double server)', () {
    Future<List<InternetAddress>> okDns(String h) async => [InternetAddress.loopbackIPv4];

    test('DNS failure stops early and is labelled DNS', () async {
      final rep = await runDiagnostics(client: MockClient((_) async => http.Response('', 200)),
          base: 'https://x.example/v1', key: 'k', model: 'm',
          resolve: (h) async => throw const SocketException('Failed host lookup'));
      expect(rep.online, isFalse);
      expect(rep.steps.first.status, StepStatus.fail);
      expect(rep.steps.skip(1).every((s) => s.status == StepStatus.skipped), isTrue);
    });

    test('invalid key: TLS passes, key step fails, generation skipped', () async {
      var calls = 0;
      final rep = await runDiagnostics(client: MockClient((r) async {
        calls++;
        return calls == 1 ? http.Response('', 403) : http.Response(googleInvalidKey, 400);
      }), base: 'https://x.example/v1', key: 'bad', model: 'm', resolve: okDns);
      expect(rep.steps[1].status, StepStatus.pass);
      expect(rep.steps[2].status, StepStatus.fail);
      expect(rep.steps[2].detail, contains('rejected the API key'));
      expect(rep.steps[3].status, StepStatus.skipped);
      expect(rep.online, isFalse);
    });

    test('preferred model 404 → falls back to a discovered model → ONLINE', () async {
      final rep = await runDiagnostics(client: MockClient((r) async {
        if (r.method == 'GET' && !r.headers.containsKey('Authorization')) return http.Response('', 401);
        if (r.method == 'GET') return http.Response(jsonEncode({'data': [{'id': 'models/gemini-2.5-flash'}]}), 200);
        final model = jsonDecode(r.body)['model'];
        return model == 'gemini-2.0-flash' ? http.Response('{"error":{"message":"not found"}}', 404) : http.Response(chat('OK'), 200);
      }), base: 'https://x.example/v1', key: 'k', model: 'gemini-2.0-flash', resolve: okDns);
      expect(rep.online, isTrue);
      expect(rep.workingModel, 'gemini-2.5-flash');
      expect(rep.steps.last.detail, contains('fell back'));
    });
  });

  group('AiService integration (test double server)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'ai_provider': 'gemini', 'ai_base_url': 'https://generativelanguage.googleapis.com/v1beta/openai',
        'ai_api_key': 'k-test', 'ai_model': 'gemini-2.0-flash',
        'privacy_allow_cloud_ai': true, // owner opt-in required by Privacy Lock
      });
      await SettingsService.instance.init();
    });

    test('404 on the configured model → discovers models, retries, remembers working model', () async {
      AiService.instance.debugClient = MockClient((r) async {
        if (r.method == 'GET') return http.Response(jsonEncode({'data': [{'id': 'models/gemini-2.5-flash'}]}), 200);
        final model = jsonDecode(r.body)['model'];
        if (model == 'gemini-2.0-flash') return http.Response('{"error":{"message":"model not found"}}', 404);
        return http.Response(chat('Vanakkam!'), 200);
      });
      final reply = await AiService.instance.chat(message: 'hi');
      expect(reply, 'Vanakkam!');
      expect(SettingsService.instance.model, 'gemini-2.5-flash');
      expect(SettingsService.instance.aiStatusLabel, startsWith('AI ONLINE'));
    });

    test('DNS failure surfaces as AiException(kind: dns) and status shows it', () async {
      AiService.instance.debugClient = MockClient((r) async => throw const SocketException('Failed host lookup: generativelanguage.googleapis.com'));
      await expectLater(AiService.instance.chat(message: 'hi'),
          throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiFailureKind.dns)));
      expect(SettingsService.instance.aiStatusLabel, 'AI ERROR · DNS');
    });

    test('invalid key (Google 400) surfaces as auth, not network', () async {
      AiService.instance.debugClient = MockClient((r) async => http.Response(googleInvalidKey, 400));
      await expectLater(AiService.instance.chat(message: 'hi'),
          throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiFailureKind.auth)
              .having((e) => e.message, 'message', contains('rejected the API key'))));
    });
  });
}
