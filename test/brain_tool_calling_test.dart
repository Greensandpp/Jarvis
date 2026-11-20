// TEST DOUBLE: the "model" here is a scripted function returning
// OpenAI-compatible messages. This proves the brain loop, approvals, safety
// and verification logic; it does NOT prove a live Gemini model behaves well.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/brain/brain.dart';
import 'package:private_agent/brain/jarvis_brain_service.dart';
import 'package:private_agent/brain/language.dart';
import 'package:private_agent/brain/local_intents.dart';
import 'package:private_agent/brain/semantic_memory.dart';
import 'package:private_agent/services/conversational_memory_service.dart';
import 'package:private_agent/services/settings_service.dart';

Map<String, dynamic> call(String name, Map<String, dynamic> args, [String id = 'c1']) => {
      'role': 'assistant', 'content': '',
      'tool_calls': [{'id': id, 'type': 'function', 'function': {'name': name, 'arguments': jsonEncode(args)}}],
    };
Map<String, dynamic> say(String t) => {'role': 'assistant', 'content': t};

ChatFn scripted(List<Map<String, dynamic>> replies, {List<List<Map<String, dynamic>>>? seen}) {
  var i = 0;
  return (m, t) async {
    seen?.add(List.of(m));
    return replies[i++];
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  var ran = 0;
  ToolSpec echo({ToolRisk risk = ToolRisk.safe, bool ok = true, bool available = true}) => ToolSpec(
        name: 'echo', description: 'echo', agent: JarvisAgent.operator, risk: risk, available: available,
        unavailableReason: 'needs Full Control build',
        parameters: {'x': {'type': 'string'}},
        describe: (a) => 'I will echo ${a['x']}',
        run: (a) async {
          ran++;
          return ok ? ToolResult(true, 'echoed ${a['x']}', verified: true) : const ToolResult.fail('echo broke');
        },
      );

  test('multi-step: tool result is fed back and the final answer uses it', () async {
    ran = 0;
    final seen = <List<Map<String, dynamic>>>[];
    final b = JarvisBrain(tools: [echo()], chat: scripted([
      call('echo', {'x': 'one'}), call('echo', {'x': 'two'}, 'c2'), say('Done: one and two.'),
    ], seen: seen));
    final r = await b.run(userText: 'echo one then two', history: const [], system: 'sys');
    expect(r.reply, 'Done: one and two.');
    expect(ran, 2);
    expect(r.steps.map((s) => s.outcome), ['ok', 'ok']);
    final toolMsg = seen.last.lastWhere((m) => m['role'] == 'tool');
    expect(jsonDecode(toolMsg['content'])['summary'], 'echoed two');
    expect(r.steps.first.agent, JarvisAgent.operator);
  });

  test('approval gate: nothing runs until yes; no declines', () async {
    ran = 0;
    final b = JarvisBrain(tools: [echo(risk: ToolRisk.approval)], chat: scripted([call('echo', {'x': 'secret'})]));
    final r = await b.run(userText: 'do it', history: const [], system: 's');
    expect(ran, 0);
    expect(r.pending, isNotNull);
    expect(r.reply, contains('I will echo secret'));
    final y = await b.resolvePending(approved: true);
    expect(ran, 1);
    expect(y.reply, 'echoed secret');
    final b2 = JarvisBrain(tools: [echo(risk: ToolRisk.approval)], chat: scripted([call('echo', {'x': 'z'})]));
    await b2.run(userText: 'x', history: const [], system: 's');
    expect((await b2.resolvePending(approved: false)).reply, contains('did not'));
    expect(ran, 1);
  });

  test('blocked and unavailable tools never run; they are not even offered', () async {
    ran = 0;
    final offered = <String>[];
    final b = JarvisBrain(tools: [echo(risk: ToolRisk.blocked)], chat: (m, t) async {
      offered.addAll(t.map((e) => e['function']['name'] as String));
      return offered.length > 5 ? say('ok') : call('echo', {'x': 'pay'});
    });
    final r = await b.run(userText: 'pay 500', history: const [], system: 's');
    expect(ran, 0);
    expect(offered, isEmpty);
    expect(r.steps.first.outcome, 'blocked');
    final u = JarvisBrain(tools: [echo(available: false)], chat: scripted([call('echo', {'x': 'a'}), say('Sorry, that needs the Full Control build.')]));
    final ur = await u.run(userText: 'x', history: const [], system: 's');
    expect(ran, 0);
    expect(ur.steps.first.outcome, 'unavailable');
  });

  test('verification: a reply claiming success after a failed tool is corrected', () async {
    final b = JarvisBrain(tools: [echo(ok: false)], chat: scripted([call('echo', {'x': 'a'}), say('All done, I opened it!')]));
    final r = await b.run(userText: 'x', history: const [], system: 's');
    expect(r.reply, startsWith('Problems: echo: echo broke'));
  });

  test('cancel stops the loop; max steps ends honestly', () async {
    late JarvisBrain b;
    b = JarvisBrain(tools: [echo()], chat: (m, t) async {
      b.cancel();
      return call('echo', {'x': 'a'});
    });
    await expectLater(b.run(userText: 'x', history: const [], system: 's'), throwsA(isA<BrainCancelled>()));
    final loop = JarvisBrain(tools: [echo()], maxSteps: 3, chat: (m, t) async => call('echo', {'x': 'again'}));
    final r = await loop.run(userText: 'x', history: const [], system: 's');
    expect(r.reply, contains('stopped after 3 steps'));
  });

  test('system prompt carries language, memory, five agents and safety rules', () {
    final p = JarvisBrain.systemPrompt(language: ReplyLanguage.tanglish, memories: ['capital is ₹75,000'], now: 'now',
        tools: JarvisBrainService.buildTools());
    expect(p, contains('Tanglish'));
    expect(p, contains('capital is ₹75,000'));
    for (final a in JarvisAgent.values) {
      expect(p, contains(a.title));
    }
    expect(p, contains('cannot place orders'));
    expect(p, contains('market_data: NOT CONNECTED'));
  });

  test('tool catalog: risky tools gated, payments blocked, schema valid', () {
    final tools = JarvisBrainService.buildTools();
    final by = {for (final t in tools) t.name: t};
    expect(by['payment_or_order']!.risk, ToolRisk.blocked);
    expect(by['draft_message']!.risk, ToolRisk.approval);
    expect(by['memory_save']!.risk, ToolRisk.approval);
    expect(by['memory_correct']!.risk, ToolRisk.approval);
    expect(by['phone_task']!.risk, ToolRisk.approval);
    expect(by['market_data']!.available, isFalse);
    expect(tools.map((t) => t.agent).toSet(), JarvisAgent.values.toSet());
    for (final t in tools) {
      final j = t.toOpenAi();
      expect((j['function']['parameters']['required'] as List).every((r) => (t.parameters).containsKey(r)), isTrue, reason: t.name);
    }
  });

  test('trade_risk_check and indicator tools run real engines', () async {
    final by = {for (final t in JarvisBrainService.buildTools()) t.name: t};
    final r = await by['trade_risk_check']!.run({'instrument': 'NIFTY', 'entry': 120, 'stop_loss': 110, 'confidence': 78,
      'time': '10:15', 'quote_age_seconds': 3});
    expect(r.summary, startsWith('TRADE (PAPER)'));
    final low = await by['trade_risk_check']!.run({'instrument': 'NIFTY', 'entry': 120, 'stop_loss': 110, 'confidence': 60, 'time': '10:15', 'quote_age_seconds': 3});
    expect(low.summary, startsWith('NO TRADE'));
    expect((await by['indicator_analysis']!.run({'candles_csv': '1,2,3'})).ok, isFalse);
  });

  group('language', () {
    test('detects Tamil script, Tanglish and English', () {
      expect(detectLanguage('இன்று வானிலை எப்படி?'), ReplyLanguage.tamil);
      expect(detectLanguage('inniki weather epdi irukku'), ReplyLanguage.tanglish);
      expect(detectLanguage('enna news?'), ReplyLanguage.tanglish);
      expect(detectLanguage('What is the weather today?'), ReplyLanguage.english);
      expect(resolveReplyLanguage('tamil', 'hello'), ReplyLanguage.tamil);
      expect(neuralVoiceFor(ReplyLanguage.tamil, female: true, englishDefault: 'x'), 'ta-IN-PallaviNeural');
    });
  });

  group('offline shortcuts', () {
    test('time, visual switch (persisted), language and voice', () async {
      expect(await LocalIntents.handle('what time is it', ReplyLanguage.english), startsWith('It is'));
      expect(await LocalIntents.handle('mani enna', ReplyLanguage.tanglish), startsWith('Ippo time'));
      expect(await LocalIntents.handle('switch to aira jellyfish', ReplyLanguage.english), contains('AIRA · jellyfish'));
      final p = await SharedPreferences.getInstance();
      expect(p.getString('jarvis_visual_mode_v1'), 'aira');
      expect(p.getString('aira_model_v1'), 'jellyfish');
      expect(await LocalIntents.handle('apex mode', ReplyLanguage.english), contains('APEX'));
      expect(await LocalIntents.handle('tamil la pesu', ReplyLanguage.tanglish), contains('தமிழில்'));
      expect(SettingsService.instance.replyLanguage, 'tamil');
      await LocalIntents.handle('female voice please', ReplyLanguage.english);
      expect(SettingsService.instance.preferFemaleVoice, isTrue);
      expect(await LocalIntents.handle('explain options greeks simply', ReplyLanguage.english), isNull);
    });
  });

  group('memory', () {
    final facts = [
      MemoryFact(id: '1', fact: 'My trading capital is 75000 rupees', createdAt: DateTime(2026, 11, 1)),
      MemoryFact(id: '2', fact: 'My daughter learns violin on Saturdays', createdAt: DateTime(2026, 11, 2)),
    ];
    test('keyword fallback when semantic recall is off', () async {
      final m = SemanticMemory(enabled: () => false);
      expect((await m.recall('how much capital do I trade with', facts)).single.id, '1');
      expect(m.lastMode, 'keyword');
    });
    test('semantic recall with an embedder (TEST DOUBLE vectors) finds paraphrases', () async {
      List<double> v(String t) => [
            t.contains('capital') || t.contains('money') ? 1.0 : 0.0,
            t.contains('violin') || t.contains('music') ? 1.0 : 0.0, 0.1,
          ];
      final m = SemanticMemory(enabled: () => true, embedder: (ts) async => ts.map(v).toList());
      final r = await m.recall('what music class does my kid have', facts);
      expect(r.first.id, '2');
      expect(m.lastMode, 'semantic');
      final failing = SemanticMemory(enabled: () => true, embedder: (_) async => throw Exception('offline'));
      expect((await failing.recall('trading capital', facts)).single.id, '1');
      expect(failing.lastMode, contains('keyword'));
    });
    test('facts persist in storage and reload after restart', () async {
      final mem = ConversationalMemoryService.instance;
      await mem.wipeAll();
      final f = await mem.addFact('Preferred index is NIFTY');
      await mem.correctFact(f.id, 'Preferred index is SENSEX');
      final raw = (await SharedPreferences.getInstance()).getString('jarvis_memory_facts_v1')!;
      final reloaded = (jsonDecode(raw) as List).map((e) => MemoryFact.fromJson(Map<String, dynamic>.from(e))).toList();
      expect(reloaded.single.fact, 'Preferred index is SENSEX');
      expect(reloaded.single.history, ['Preferred index is NIFTY']);
    });
  });

  test('approval words in English, Tamil and Tanglish', () {
    for (final y in ['yes', 'ok go ahead', 'seri', 'ஆமா', 'சரி']) {
      expect(JarvisBrainService.isYes(y), isTrue, reason: y);
    }
    for (final n in ['no', 'vendam', 'வேண்டாம்', 'cancel']) {
      expect(JarvisBrainService.isNo(n), isTrue, reason: n);
    }
  });

  test('JarvisBrainService: implicit fact → spoken approval → saved only after "yes"; "vendam" dismisses', () async {
    final svc = JarvisBrainService.instance;
    final mem = ConversationalMemoryService.instance;
    await mem.wipeAll();
    await SettingsService.instance.setReplyLanguage('auto');
    final r = await svc.handle('my favorite index is SENSEX');
    expect(r.reply, contains('Privacy Lock')); // honest: cloud AI not enabled in tests
    expect(r.reply, contains('Offline I can still'));
    expect(r.reply, contains('Shall I remember "my favorite index is SENSEX"'));
    expect(mem.facts, isEmpty);
    final y = await svc.handle('yes');
    expect(y.reply, contains('Remembered'));
    expect(mem.facts.single.fact, 'my favorite index is SENSEX');
    await svc.handle('i live in Chennai');
    expect(svc.hasPending, isTrue);
    await svc.handle('vendam');
    expect(mem.facts.length, 1);
    expect(await mem.suggestions(), isEmpty);
    final audit = await JarvisBrainService.loadAudit();
    expect(audit.map((e) => e['outcome']), containsAll(['approved · ok', 'declined']));
  });
}
