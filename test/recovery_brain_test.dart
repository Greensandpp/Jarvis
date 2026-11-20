import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/brain/brain.dart';
import 'package:private_agent/brain/jarvis_brain_service.dart';

Map<String, dynamic> call(String args) => {
  'tool_calls': [
    {
      'id': 'a',
      'function': {'name': 'action', 'arguments': args},
    },
  ],
};
void main() {
  test('qualified approval text never authorizes a sensitive action', () {
    for (final answer in [
      "yes but don't send",
      'okay wait',
      'yes no',
      'seri vendam',
      'yes?',
    ]) {
      expect(JarvisBrainService.isYes(answer), isFalse, reason: answer);
    }
    for (final answer in ['yes', 'ok go ahead', 'seri', 'சரி']) {
      expect(JarvisBrainService.isYes(answer), isTrue, reason: answer);
    }
  });

  test(
    'invalid/missing/extra/enum/out-of-range arguments never reach Android or approval',
    () async {
      for (final args in [
        '{}',
        '{"hour":"10"}',
        '{"hour":25}',
        '{"hour":10,"extra":1}',
        '{"hour":10,"kind":"pay"}',
        'not json',
        '[]',
      ]) {
        var ran = 0, n = 0;
        final brain = JarvisBrain(
          tools: [
            ToolSpec(
              name: 'action',
              description: 'alarm',
              agent: JarvisAgent.operator,
              risk: ToolRisk.approval,
              parameters: {
                'hour': {'type': 'integer', 'minimum': 0, 'maximum': 23},
                'kind': {
                  'type': 'string',
                  'enum': ['alarm'],
                },
              },
              required: ['hour'],
              run: (a) async {
                ran++;
                return const ToolResult(true, 'ok');
              },
            ),
          ],
          chat: (m, t) async =>
              n++ == 0 ? call(args) : {'content': 'Could not do that.'},
        );
        final r = await brain.run(userText: 'alarm', history: [], system: 's');
        expect(ran, 0, reason: args);
        expect(r.pending, isNull);
        expect(r.steps.single.outcome, 'failed');
      }
    },
  );
  test('cancel revokes an outstanding approval', () async {
    var ran = 0;
    final brain = JarvisBrain(
      tools: [
        ToolSpec(
          name: 'action',
          description: 'a',
          agent: JarvisAgent.operator,
          risk: ToolRisk.approval,
          run: (a) async {
            ran++;
            return const ToolResult(true, 'done');
          },
        ),
      ],
      chat: (m, t) async => call('{}'),
    );
    await brain.run(userText: 'x', history: [], system: 's');
    brain.cancel();
    await brain.resolvePending(approved: true);
    expect(ran, 0);
  });
  test('cancel during first tool prevents the rest of a model batch', () async {
    final started = Completer<void>(), finish = Completer<ToolResult>();
    var ran = 0;
    final brain = JarvisBrain(
      tools: [
        ToolSpec(
          name: 'action',
          description: 'a',
          agent: JarvisAgent.operator,
          run: (a) async {
            ran++;
            started.complete();
            return finish.future;
          },
        ),
      ],
      chat: (m, t) async => {
        'tool_calls': [
          ...call('{}')['tool_calls'],
          {
            'id': 'b',
            'function': {'name': 'action', 'arguments': jsonEncode({})},
          },
        ],
      },
    );
    final work = brain.run(userText: 'x', history: [], system: 's');
    final result = expectLater(work, throwsA(isA<BrainCancelled>()));
    await started.future;
    brain.cancel();
    finish.complete(const ToolResult(true, 'done'));
    await result;
    expect(ran, 1);
  });
  test('nested schemas reject invalid array values', () {
    final t = ToolSpec(
      name: 'action',
      description: 'a',
      agent: JarvisAgent.operator,
      parameters: {
        'rows': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'n': {'type': 'number'},
            },
            'required': ['n'],
            'additionalProperties': false,
          },
        },
      },
      run: (a) async => const ToolResult(true, 'ok'),
    );
    expect(
      t.validate({
        'rows': [
          {'n': 'secret'},
        ],
      }),
      isNotNull,
    );
    expect(
      t.validate({
        'rows': [
          {'n': 2.0},
        ],
      }),
      isNull,
    );
  });
}
