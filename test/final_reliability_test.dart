import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/brain/ai_reliability.dart';
import 'package:private_agent/brain/brain.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:private_agent/services/voice_selection.dart';
import 'package:private_agent/widgets/neon_composer.dart';

http.Response reply([String text = 'OK']) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': text},
      },
    ],
  }),
  200,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ai_provider': 'gemini',
      'ai_api_key': 'test-key',
      'ai_model': 'working-flash',
    });
    await SettingsService.instance.init();
  });
  test(
    'same provider, provider round trip and restart preserve verified model',
    () async {
      final s = SettingsService.instance;
      await s.recordAiSuccess('working-flash');
      await s.setProvider('gemini');
      expect(s.model, 'working-flash');
      await s.setProvider('openai');
      expect(s.aiVerified, isFalse);
      await s.setProvider('gemini');
      await s.init();
      expect(s.model, 'working-flash');
      expect(s.aiVerified, isTrue);
    },
  );
  test(
    'new credential or endpoint cannot inherit discovery or verification',
    () async {
      final s = SettingsService.instance;
      await s.setDiscoveredModels(['working-flash']);
      await s.recordAiSuccess('working-flash');
      await s.setApiKey('different-key');
      expect(s.discoveredModels, isEmpty);
      expect(s.aiVerified, isFalse);
      await s.setApiKey('test-key');
      expect(s.aiVerified, isTrue);
      await s.setBaseUrl('https://example.org/v1');
      expect(s.aiVerified, isFalse);
    },
  );
  for (final code in [429, 503, 404]) {
    test(
      '$code discovers alternate model and returns exactly one completion',
      () async {
        final sent = <String>[];
        var discoveries = 0;
        final result = await completeWithFallback(
          preferred: 'old',
          cached: [],
          discover: () async {
            discoveries++;
            return ['new-flash'];
          },
          sleep: (_) async {},
          send: (m) async {
            sent.add(m);
            return m == 'old' ? http.Response('', code) : reply();
          },
        );
        expect(result.model, 'new-flash');
        expect(sent, ['old', 'new-flash']);
        expect(discoveries, 1);
      },
    );
  }
  test(
    'repeated quota errors stop at four attempts with bounded backoff',
    () async {
      var count = 0;
      final delays = <int>[];
      await expectLater(
        completeWithFallback(
          preferred: 'm',
          cached: ['m'],
          discover: () async => ['m'],
          sleep: (d) async => delays.add(d.inMilliseconds),
          send: (_) async {
            count++;
            return http.Response('', 429);
          },
        ),
        throwsA(isA<AiFailure>()),
      );
      expect(count, 4);
      expect(delays, [600, 1200, 2400]);
    },
  );
  test(
    'invalid key and empty 200 responses never become verified success',
    () async {
      for (final response in [http.Response('', 401), reply('')]) {
        var count = 0;
        await expectLater(
          completeWithFallback(
            preferred: 'm',
            cached: ['m'],
            discover: () async => ['other'],
            send: (_) async {
              count++;
              return response;
            },
          ),
          throwsA(isA<AiFailure>()),
        );
        expect(count, 1);
      }
    },
  );
  test(
    'repeated action payload with different IDs executes once per request',
    () async {
      var actions = 0, turns = 0;
      final brain = JarvisBrain(
        tools: [
          ToolSpec(
            name: 'open_app',
            description: 'open',
            agent: JarvisAgent.operator,
            run: (_) async {
              actions++;
              return const ToolResult(true, 'opened');
            },
          ),
        ],
        chat: (_, _) async {
          if (++turns > 2) return {'content': 'Done'};
          return {
            'tool_calls': [
              {
                'id': 'call_$turns',
                'function': {
                  'name': 'open_app',
                  'arguments': turns == 1
                      ? '{"app":"clock","x":1}'
                      : '{"x":1,"app":"clock"}',
                },
              },
            ],
          };
        },
      );
      await brain.run(userText: 'open clock', history: [], system: 'test');
      expect(actions, 1);
      await brain.run(
        userText: 'open clock again',
        history: [],
        system: 'test',
      );
      expect(actions, 1); // second conversation has no tool call
    },
  );
  test(
    'Tamil female offline neural preferred; network-only and wrong locale excluded',
    () {
      final voices = [
        {
          'name': 'English female',
          'locale': 'en-IN',
          'network_required': 'false',
        },
        {
          'name': 'Tamil female online',
          'locale': 'ta-IN',
          'network_required': 'true',
        },
        {'name': 'Tamil male', 'locale': 'ta-IN', 'network_required': 'false'},
        {
          'name': 'Tamil female neural',
          'locale': 'ta-IN',
          'network_required': 'false',
        },
      ];
      expect(
        selectOfflineVoice(voices, 'ta-IN')?['name'],
        'Tamil female neural',
      );
      expect(selectOfflineVoice(voices, 'en-IN')?['name'], 'English female');
      expect(selectOfflineVoice(voices, 'fr-FR'), isNull);
      expect(
        selectOfflineVoice([
          {'name': 'Unknown', 'locale': 'ta-IN'},
        ], 'ta-IN'),
        isNull,
      );
    },
  );
  testWidgets(
    'composer remains transparent under filled theme; mic and send retain callbacks',
    (t) async {
      final c = TextEditingController();
      var sends = 0, mics = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.blue,
            ),
          ),
          home: Scaffold(
            body: SafeArea(
              child: NeonComposer(
                controller: c,
                onSend: () {
                  sends++;
                },
                onMicrophone: () {
                  mics++;
                },
              ),
            ),
          ),
        ),
      );
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.filled, isFalse);
      expect(field.decoration!.focusedBorder, InputBorder.none);
      await t.tap(find.byIcon(Icons.mic_none));
      await t.enterText(find.byType(TextField), 'vanakkam');
      await t.tap(find.byIcon(Icons.send_rounded));
      expect(sends, 1);
      expect(mics, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
