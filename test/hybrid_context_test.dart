import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:private_agent/jarvis_v3/conversation_store.dart';
import 'package:private_agent/services/jarvis_service.dart';
import 'package:private_agent/services/hybrid_conversation_context.dart';

void main() {
  test('streamed Live transcript updates a single assistant bubble', () {
    final signal = ValueNotifier(const ConversationSignals(phase: JarvisPhase.idle, userText: '', jarvisText: '', status: ''));
    final store = ConversationStore(source: signal, read: () => signal.value, persist: () => false);
    signal.value = const ConversationSignals(phase: JarvisPhase.listening, userText: 'Hello', jarvisText: '', status: 'LIVE');
    signal.value = const ConversationSignals(phase: JarvisPhase.speaking, userText: 'Hello', jarvisText: 'Hi', status: 'LIVE');
    signal.value = const ConversationSignals(phase: JarvisPhase.speaking, userText: 'Hello', jarvisText: 'Hi there', status: 'LIVE');
    expect(store.entries, hasLength(2));
    expect(store.entries.last.text, 'Hi there');
    store.dispose();
    signal.dispose();
  });
  test('engine handoff retains bounded complete turns without duplicate playback text', () {
    final context = HybridConversationContext();
    context.addTurn('unfinished', '');
    expect(context.turns, isEmpty);
    context.addTurn('Tamil please', 'வணக்கம்');
    context.addTurn('Tamil please', 'வணக்கம்');
    expect(context.turns, hasLength(1));
    for (var i = 0; i < 6; i++) { context.addTurn('question $i', 'answer $i'); }
    expect(context.turns, hasLength(4));
    expect(context.prompt, contains('question 5'));
    expect(context.prompt, isNot(contains('question 0')));
    context.clear();
    expect(context.prompt, isEmpty);
  });
}
