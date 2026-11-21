import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/v3_fixtures.dart';

import 'package:private_agent/jarvis_v3/assistant_activity.dart';
import 'package:private_agent/jarvis_v3/chat_auto_hide.dart';
import 'package:private_agent/jarvis_v3/conversation_store.dart';
import 'package:private_agent/jarvis_v3/jarvis_v3_home.dart';
import 'package:private_agent/services/jarvis_service.dart';

void main() {
  group('activity engine (real events only)', () {
    test('maps every phase and refuses a false LISTENING', () {
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.idle)), AssistantActivity.idle);
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.listening, micCapturing: true)),
          AssistantActivity.listening);
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.listening, micCapturing: false)),
          AssistantActivity.idle, reason: 'never show recording when the recogniser is not capturing');
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.thinking)), AssistantActivity.thinking);
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.executing, executorRunning: true)),
          AssistantActivity.executing);
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.executing)),
          AssistantActivity.processing, reason: 'EXECUTING only while a device action really runs');
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.speaking)), AssistantActivity.speaking);
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.speaking, errorStatus: true)),
          AssistantActivity.error);
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.idle, aiConfigured: false)),
          AssistantActivity.disconnected);
      expect(deriveActivity(const ActivitySignals(phase: JarvisPhase.idle, chatBusy: true)),
          AssistantActivity.processing);
    });

    testWidgets('full cycle IDLE -> LISTENING -> THINKING -> SPEAKING -> IDLE', (tester) async {
      final src = FakeSignals();
      final engine = AssistantActivityEngine(source: src, read: () => src.signals);
      final seen = <AssistantActivity>[];
      engine.addListener(() => seen.add(engine.value));
      src.set(const ActivitySignals(phase: JarvisPhase.listening, micCapturing: true));
      src.set(const ActivitySignals(phase: JarvisPhase.thinking));
      src.set(const ActivitySignals(phase: JarvisPhase.speaking));
      src.set(const ActivitySignals(phase: JarvisPhase.idle));
      expect(seen, [
        AssistantActivity.listening,
        AssistantActivity.thinking,
        AssistantActivity.speaking,
        AssistantActivity.idle,
      ]);
      engine.dispose();
    });

    testWidgets('a stale error timer never overrides a newer state', (tester) async {
      final src = FakeSignals();
      final engine = AssistantActivityEngine(
          source: src, read: () => src.signals, errorHold: const Duration(seconds: 2));
      src.set(const ActivitySignals(phase: JarvisPhase.idle, errorStatus: true));
      expect(engine.value, AssistantActivity.error);
      // A new request starts before the error hold elapses.
      src.set(const ActivitySignals(phase: JarvisPhase.thinking));
      await tester.pump(const Duration(seconds: 3));
      expect(engine.value, AssistantActivity.thinking);
      // The error hold itself returns to the real state when nothing newer happened.
      src.set(const ActivitySignals(phase: JarvisPhase.idle, errorStatus: true));
      expect(engine.value, AssistantActivity.error);
      await tester.pump(const Duration(seconds: 3));
      expect(engine.value, AssistantActivity.idle);
      engine.dispose();
    });
  });

  group('chat auto-hide', () {
    ChatAutoHideController make({bool enabled = true, int s = 8, bool speaking = true}) =>
        ChatAutoHideController(enabled: enabled, delay: Duration(seconds: s), showWhileSpeaking: speaking)
          ..reveal();

    testWidgets('hides after the configured inactivity delay', (tester) async {
      final c = make();
      await tester.pump(const Duration(seconds: 7));
      expect(c.visible, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(c.visible, isFalse);
      c.dispose();
    });

    testWidgets('delays 5/15/30 s are honoured', (tester) async {
      for (final s in [5, 15, 30]) {
        final c = make(s: s);
        await tester.pump(Duration(seconds: s - 1));
        expect(c.visible, isTrue, reason: '$s s');
        await tester.pump(const Duration(seconds: 2));
        expect(c.visible, isFalse, reason: '$s s');
        c.dispose();
      }
    });

    testWidgets('never hides while listening, thinking, executing or speaking', (tester) async {
      for (final a in [
        AssistantActivity.listening,
        AssistantActivity.thinking,
        AssistantActivity.processing,
        AssistantActivity.executing,
        AssistantActivity.speaking,
      ]) {
        final c = make();
        c.setActivity(a);
        await tester.pump(const Duration(seconds: 60));
        expect(c.visible, isTrue, reason: a.name);
        // Countdown begins only after the activity ends.
        c.setActivity(AssistantActivity.idle);
        await tester.pump(const Duration(seconds: 7));
        expect(c.visible, isTrue, reason: '${a.name} just ended');
        await tester.pump(const Duration(seconds: 2));
        expect(c.visible, isFalse, reason: '${a.name} + 8 s idle');
        c.dispose();
      }
    });

    testWidgets('speaking can be allowed to hide when "show while speaking" is off', (tester) async {
      final c = make(speaking: false);
      c.setActivity(AssistantActivity.speaking);
      await tester.pump(const Duration(seconds: 9));
      expect(c.visible, isFalse);
      c.dispose();
    });

    testWidgets('a hidden conversation reappears on activity and on tap', (tester) async {
      final c = make();
      await tester.pump(const Duration(seconds: 9));
      expect(c.visible, isFalse);
      c.setActivity(AssistantActivity.listening);
      expect(c.visible, isTrue);
      c.setActivity(AssistantActivity.idle);
      await tester.pump(const Duration(seconds: 9));
      expect(c.visible, isFalse);
      c.reveal();
      expect(c.visible, isTrue);
      c.dispose();
    });

    testWidgets('scroll, focus, keyboard, history and pending notices pause the timer', (tester) async {
      for (final h in ChatHold.values) {
        final c = make();
        c.hold(h);
        await tester.pump(const Duration(seconds: 40));
        expect(c.visible, isTrue, reason: h.name);
        c.release(h);
        await tester.pump(const Duration(seconds: 7));
        expect(c.visible, isTrue, reason: '${h.name} released; countdown restarted');
        await tester.pump(const Duration(seconds: 2));
        expect(c.visible, isFalse, reason: h.name);
        c.dispose();
      }
    });

    testWidgets('auto-hide off keeps the conversation visible', (tester) async {
      final c = make(enabled: false);
      await tester.pump(const Duration(seconds: 60));
      expect(c.visible, isTrue);
      c.dispose();
    });

    testWidgets('dispose cancels the pending timer', (tester) async {
      final c = make();
      expect(c.countingDown, isTrue);
      c.dispose();
      await tester.pump(const Duration(seconds: 10)); // no callback after dispose
    });
  });

  group('conversation store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('records real user and JARVIS turns once, keeps Tamil text intact', (tester) async {
      final src = FakeConversation();
      final store = ConversationStore(source: src, read: () => src.signals, persist: () => true);
      src.listen('நாளைக்கு weather எப்படி');
      expect(store.entries, isEmpty, reason: 'partial speech is not history');
      expect(store.liveTranscript, 'நாளைக்கு weather எப்படி');
      src.think('நாளைக்கு weather எப்படி?');
      src.speak('நாளை மழை வாய்ப்பு 40%. Umbrella eduthukonga.');
      src.speak('நாளை மழை வாய்ப்பு 40%. Umbrella eduthukonga.'); // duplicate notify
      src.idle();
      expect(store.entries.map((e) => (e.role, e.text)).toList(), [
        (ConversationRole.user, 'நாளைக்கு weather எப்படி?'),
        (ConversationRole.jarvis, 'நாளை மழை வாய்ப்பு 40%. Umbrella eduthukonga.'),
      ]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      // Restored in a new session.
      final again = ConversationStore(source: FakeConversation(), read: () => src.signals, persist: () => true);
      await tester.runAsync(again.load);
      expect(again.entries.length, 2);
      expect(again.entries.last.text, contains('மழை'));
      store.dispose();
      again.dispose();
    });

    testWidgets('errors stay pinned until acknowledged', (tester) async {
      final src = FakeConversation();
      final store = ConversationStore(source: src, read: () => src.signals, persist: () => false);
      src.think('open the app');
      src.speak('The AI service is busy. Please try again.', status: 'AI ERROR // RATE_LIMIT');
      expect(store.entries.last.kind, ConversationKind.error);
      expect(store.hasPendingNotice, isTrue);
      store.acknowledgeAll();
      expect(store.hasPendingNotice, isFalse);
      store.dispose();
    });

    testWidgets('save off keeps nothing on the device', (tester) async {
      final src = FakeConversation();
      final store = ConversationStore(source: src, read: () => src.signals, persist: () => false);
      src.think('hello');
      src.speak('Hello.');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      final p = await SharedPreferences.getInstance();
      expect(p.getString(ConversationStore.storageKey), isNull);
      store.dispose();
    });
  });

  test('header status is derived from real state and never claims ONLINE unverified', () {
    expect(headerStatus(activity: AssistantActivity.idle, aiVerified: false, aiErrorKind: '', standbyMic: false).label,
        'NOT VERIFIED');
    expect(headerStatus(activity: AssistantActivity.idle, aiVerified: true, aiErrorKind: '', standbyMic: false).label,
        'CONNECTED');
    expect(headerStatus(activity: AssistantActivity.idle, aiVerified: true, aiErrorKind: '', standbyMic: true).label,
        'CONNECTED · MIC STANDBY');
    expect(headerStatus(activity: AssistantActivity.idle, aiVerified: true, aiErrorKind: 'quota', standbyMic: false).label,
        'ERROR · QUOTA');
    expect(headerStatus(activity: AssistantActivity.disconnected, aiVerified: false, aiErrorKind: '', standbyMic: false).label,
        'CONFIGURATION MISSING');
  });
}

class FakeSignals extends ChangeNotifier {
  ActivitySignals signals = const ActivitySignals(phase: JarvisPhase.idle);
  void set(ActivitySignals s) {
    signals = s;
    notifyListeners();
  }
}
