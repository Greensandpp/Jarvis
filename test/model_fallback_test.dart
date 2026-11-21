// TEST DOUBLES: HTTP goes to package:http MockClient (in-process). These prove
// JARVIS's model selection / fallback / de-duplication logic, NOT that a live
// Gemini key works — that stays UNVERIFIED until the owner tests on the phone.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/brain/ai_reliability.dart';
import 'package:private_agent/brain/brain.dart';
import 'package:private_agent/brain/model_selector.dart';
import 'package:private_agent/screens/brain/ai_diagnostics_screen.dart';
import 'package:private_agent/services/ai_service.dart';
import 'package:private_agent/services/settings_service.dart';

String chat(String text) => jsonEncode({'choices': [{'message': {'role': 'assistant', 'content': text}}]});
const discovered = ['models/gemini-2.5-pro', 'models/gemini-2.5-flash-lite', 'models/gemini-2.5-flash',
  'models/gemini-3.0-flash-preview-05-20', 'models/gemini-2.0-flash'];

Future<void> resetAi() async {
  final s = SettingsService.instance;
  await s.setProvider('gemini');
  // A test double uses loopback; production remote inference remains blocked.
  await s.setBaseUrl('http://127.0.0.1:11434/v1');
  await s.setApiKey('k-test');
  await s.setAllowCloudAi(true);
  await s.setModel('gemini-2.5-flash');
  await s.setModelAuto(true);
  await s.setDiscoveredModels(rankModels(discovered));
  await s.setModelsDiscoveredAt(DateTime.now().millisecondsSinceEpoch);
  AiService.instance.cooldowns.clear();
  AiService.instance.retrySleep = (_) async {};
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  group('ranking and automatic selection', () {
    test('stable Flash first, then Flash-Lite, Pro, previews; newest version first', () {
      expect(rankModels(discovered), [
        'gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-2.5-flash-lite', 'gemini-2.5-pro',
        'gemini-3.0-flash-preview-05-20',
      ]);
      expect(pickBestModel(['gemini-3.5-flash-lite', 'gemini-3.5-flash', 'gemini-2.5-flash']), 'gemini-3.5-flash');
      expect(pickBestModel(const []), isNull);
      expect(GeminiModelInfo.parse('models/gemini-2.5-flash-lite')!.tier, 'flash-lite');
      expect(GeminiModelInfo.parse('gemini-2.5-pro-preview-06-05')!.preview, isTrue);
      expect(GeminiModelInfo.parse('deepseek-chat'), isNull);
    });
  });

  group('callWithModelFallback (bounded)', () {
    test('429 on the selected model → next model answers, selection kept, model cools down', () async {
      final cd = ModelCooldowns();
      final calls = <String>[];
      final r = await callWithModelFallback<String>(
        selected: 'gemini-2.5-flash', ranked: rankModels(discovered), cooldowns: cd, sleep: (_) async {},
        attempt: (m) async {
          calls.add(m);
          if (m == 'gemini-2.5-flash') throw AiFailure.fromHttp(429, '{"error":{"message":"quota"}}');
          return 'ok from $m';
        });
      expect(r.value, 'ok from gemini-2.0-flash');
      expect(r.selectedUnavailable, isFalse, reason: 'a temporary 429 must not change the selection');
      expect(calls, ['gemini-2.5-flash', 'gemini-2.0-flash']);
      expect(cd.cooling('gemini-2.5-flash', DateTime.now()), isTrue);
      expect(r.attempts.map((a) => '$a'), ['gemini-2.5-flash:429', 'gemini-2.0-flash:ok']);
    });

    test('503 retries the same model once with backoff, then falls back', () async {
      final sleeps = <Duration>[];
      final calls = <String>[];
      final r = await callWithModelFallback<String>(
        selected: 'a', ranked: ['a', 'b'], sleep: (d) async => sleeps.add(d),
        attempt: (m) async {
          calls.add(m);
          if (m == 'a') throw AiFailure.fromHttp(503, 'overloaded');
          return m;
        });
      expect(r.model, 'b');
      expect(calls, ['a', 'a', 'b']);
      expect(sleeps, hasLength(1));
    });

    test('never more than maxAttempts requests; failure is reported as quota', () async {
      var n = 0;
      await expectLater(
        callWithModelFallback<String>(
          selected: 'a', ranked: ['a', 'b', 'c', 'd', 'e', 'f'], maxAttempts: 4, sleep: (_) async {},
          attempt: (m) async {
            n++;
            throw AiFailure.fromHttp(429, '');
          }),
        throwsA(isA<AiFailure>().having((f) => f.kind, 'kind', AiFailureKind.rateLimit)));
      expect(n, 4);
    });

    test('key / network errors are not retried on other models', () async {
      var n = 0;
      await expectLater(
        callWithModelFallback<String>(selected: 'a', ranked: ['a', 'b'], sleep: (_) async {}, attempt: (m) async {
          n++;
          throw AiFailure.fromHttp(401, '');
        }),
        throwsA(isA<AiFailure>().having((f) => f.kind, 'kind', AiFailureKind.auth)));
      expect(n, 1);
    });

    test('a cooling model is skipped on the next request', () async {
      final cd = ModelCooldowns()..mark('a', const Duration(minutes: 1), DateTime.now(), 'rate limit');
      final calls = <String>[];
      final r = await callWithModelFallback<String>(selected: 'a', ranked: ['a', 'b'], cooldowns: cd,
          sleep: (_) async {}, attempt: (m) async {
        calls.add(m);
        return m;
      });
      expect(calls, ['b']);
      expect(r.attempts.first.outcome, 'skipped-cooldown');
    });
  });

  group('AiService with a test-double Gemini server', () {
    setUp(resetAi);

    test('HTTP 429 on the selected model: reply comes from a fallback; selection unchanged', () async {
      final seen = <String>[];
      AiService.instance.debugClient = MockClient((r) async {
        final m = jsonDecode(r.body)['model'] as String;
        seen.add(m);
        if (m == 'gemini-2.5-flash') return http.Response('{"error":{"code":429,"message":"Resource exhausted"}}', 429);
        return http.Response(chat('Vanakkam from $m'), 200);
      });
      final reply = await AiService.instance.chat(message: 'hi');
      expect(reply, 'Vanakkam from gemini-2.0-flash');
      expect(seen, ['gemini-2.5-flash', 'gemini-2.0-flash'], reason: 'one request per model, no duplicates');
      final s = SettingsService.instance;
      expect(s.model, 'gemini-2.5-flash');
      expect(s.aiLastOkModel, 'gemini-2.0-flash');
      expect(s.modelLabel, contains('last reply via gemini-2.0-flash'));
      expect(s.aiStatusLabel, startsWith('AI ONLINE'));
    });

    test('HTTP 503 everywhere: bounded attempts then an honest server error', () async {
      var n = 0;
      AiService.instance.debugClient = MockClient((r) async {
        n++;
        return http.Response('{"error":{"code":503,"message":"The model is overloaded"}}', 503);
      });
      await expectLater(AiService.instance.chat(message: 'hi'),
          throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiFailureKind.server)));
      expect(n, lessThanOrEqualTo(4));
      expect(SettingsService.instance.aiStatusLabel, 'AI ERROR · SERVER');
    });

    test('model discovery auto-selects the best model and persists the list; manual pin is kept', () async {
      final s = SettingsService.instance;
      await s.setModel('gemini-1.5-flash');
      await s.setModelsDiscoveredAt(0);
      var gets = 0;
      AiService.instance.debugClient = MockClient((r) async {
        gets++;
        return http.Response(jsonEncode({'data': [for (final d in discovered) {'id': d}]}), 200);
      });
      expect(await AiService.instance.discoverAndSelectModels(), 'gemini-2.5-flash');
      expect(s.model, 'gemini-2.5-flash');
      expect(s.discoveredModels.first, 'gemini-2.5-flash');
      // Throttled: no second network call within the max age.
      expect(await AiService.instance.discoverAndSelectModels(), isNull);
      expect(gets, 1);
      // Owner pins a model → discovery keeps it.
      await s.setModel('gemini-2.5-pro', pin: true);
      expect(s.modelAuto, isFalse);
      await AiService.instance.discoverAndSelectModels(force: true);
      expect(s.model, 'gemini-2.5-pro');
      expect(s.modelLabel, startsWith('gemini-2.5-pro (manual)'));
    });

    test('Privacy Lock: no discovery request while cloud AI is off', () async {
      final s = SettingsService.instance;
      await s.setAllowCloudAi(false);
      var n = 0;
      AiService.instance.debugClient = MockClient((r) async {
        n++;
        return http.Response('{}', 200);
      });
      expect(await AiService.instance.discoverAndSelectModels(force: true), isNull);
      expect(n, 0);
    });

    test('Gemini stays preferred: Google keys select Gemini automatically', () async {
      final s = SettingsService.instance;
      await s.setProvider('deepseek');
      await s.setApiKey('AIzaSyTESTKEY0000000000');
      expect(s.provider, 'gemini');
      expect(s.baseUrl, contains('generativelanguage.googleapis.com'));
      expect(SettingsService.providers['gemini']!.model, startsWith('gemini-'));
    });
  });

  group('no duplicate Android actions', () {
    late int opened;
    ToolSpec openApp() => ToolSpec(
          name: 'open_app', description: 'open', agent: JarvisAgent.operator,
          run: (a) async {
            opened++;
            return ToolResult(true, 'Opened ${a['app']}', verified: true);
          });
    Map<String, dynamic> callMsg(String id) => {
          'role': 'assistant', 'content': '',
          'tool_calls': [
            {'id': id, 'type': 'function', 'function': {'name': 'open_app', 'arguments': '{"app":"WhatsApp"}'}},
          ],
        };

    setUp(() => opened = 0);

    test('the same tool call repeated inside one request runs once', () async {
      var step = 0;
      final brain = JarvisBrain(tools: [openApp()], chat: (m, t) async {
        step++;
        if (step <= 2) return callMsg('c$step');
        return {'role': 'assistant', 'content': 'WhatsApp is open.'};
      });
      final r = await brain.run(userText: 'open whatsapp', history: const [], system: 's');
      expect(opened, 1);
      expect(r.steps.map((s) => s.outcome), ['ok', 'deduplicated']);
      expect(r.reply, 'WhatsApp is open.');
    });

    test('a re-sent command (e.g. after an AI fallback) does not act on the phone twice', () async {
      Future<BrainResult> once(JarvisBrain b) => b.run(userText: 'open whatsapp', history: const [], system: 's');

      var turn = 0;
      final brain = JarvisBrain(tools: [openApp()], chat: (m, t) async {
        turn++;
        return turn.isOdd ? callMsg('c$turn') : {'role': 'assistant', 'content': 'Done.'};
      });
      await once(brain);
      final second = await once(brain);
      expect(opened, 1);
      expect(second.steps.single.summary, contains('not repeated'));
      // After the window the same action is allowed again.
      brain.clock = () => DateTime.now().add(const Duration(seconds: 30));
      await once(brain);
      expect(opened, 2);
    });
  });

  testWidgets('Diagnostics shows the same model and follows changes made elsewhere', (tester) async {
    await resetAi();
    await tester.pumpWidget(const MaterialApp(home: AiDiagnosticsScreen()));
    await tester.pump();
    expect(find.textContaining('Model: gemini-2.5-flash (auto)'), findsOneWidget);
    await SettingsService.instance.setModel('gemini-2.5-flash-lite', pin: true);
    await tester.pump();
    expect(find.textContaining('Model: gemini-2.5-flash-lite (manual)'), findsOneWidget);
    expect(find.textContaining('Provider: gemini (preferred)'), findsOneWidget);
  });
}
