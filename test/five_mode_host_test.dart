// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/services/agent_office/agent_office.dart';
import 'package:private_agent/services/gemini_live/live_voice_controller.dart';
import 'package:private_agent/services/jarvis_service.dart' show JarvisPhase, JarvisService;
import 'package:private_agent/widgets/aira/aira_models.dart';
import 'package:private_agent/widgets/aira/aira_view.dart';
import 'package:private_agent/widgets/jarvis_local_visuals.dart';
import 'package:private_agent/widgets/jarvis_visual_mode_host.dart';

class _Phase extends ChangeNotifier {
  JarvisPhase value = JarvisPhase.idle;
  void set(JarvisPhase p) {
    value = p;
    notifyListeners();
  }
}

class _Harness {
  final phase = _Phase();
  final commands = <String>[];
  var mic = 0;
  final office = AgentOfficeController();
  final live = LiveVoiceController(observeLifecycle: false);
  final task = ChangeNotifier();

  Widget build() => MaterialApp(
        home: MediaQuery(
          // iQOO 13-class portrait phone in logical pixels with cutout insets.
          data: const MediaQueryData(size: Size(412, 915),
              padding: EdgeInsets.only(top: 36, bottom: 24)),
          child: Scaffold(body: JarvisVisualModeHost(
            onCommand: commands.add,
            onMicrophone: () async => mic++,
            phaseSource: phase,
            phaseReader: () => phase.value,
            soundReader: () => .3,
            coreBuilder: (_) => const Center(child: Text('NATIVE JARVIS HUD', key: ValueKey('core-hud'))),
            office: office,
            liveVoice: live,
            localTask: () => (goal: '', state: 'idle', step: 0),
            localTaskListenable: task,
          )),
        ),
      );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _chooseVisual(WidgetTester tester, String style) async {
  await tester.longPress(find.byKey(const ValueKey('visual-long-press-surface')));
  await _settle(tester);
  await tester.tap(find.byKey(ValueKey('mode-$style')));
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('voice-style requests change visuals without treating ordinary chat as commands', () {
    expect(JarvisService.visualStyleIntent('show MIRA'), 'mira');
    expect(JarvisService.visualStyleIntent('switch to APEX'), 'apex');
    expect(JarvisService.visualStyleIntent('aira ku maathu'), 'aira');
    expect(JarvisService.visualStyleIntent('show JARVIS core'), 'core');
    expect(JarvisService.visualStyleIntent('show models'), 'picker');
    expect(JarvisService.visualStyleIntent('what is MIRA?'), isNull);
    expect(JarvisService.visualStyleIntent('hello jarvis'), isNull);
  });

  testWidgets('all five modes are selectable and Core is the default', (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await _settle(tester);
    expect(JarvisVisualMode.values.map((m) => m.label),
        ['JARVIS Core', 'AIRA', 'Agent Office', 'APEX', 'MIRA']);
    for (final m in JarvisVisualMode.values) {
      expect(find.byKey(ValueKey('mode-${m.name}')), findsNothing);
    }
    expect(find.byKey(const ValueKey('core-hud')), findsOneWidget);
    // Unified dock stays available even on the original Arc Reactor.
    expect(find.byKey(const ValueKey('dock-input')), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('visual-long-press-surface')));
    await _settle(tester);
    for (final m in JarvisVisualMode.values) {
      expect(find.byKey(ValueKey('mode-${m.name}')), findsOneWidget);
    }
    // Dismiss bottom-sheet barrier before the test ends (no pending route timer).
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('visual choice saves but every fresh launch starts with Core', (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await _settle(tester);
    await _chooseVisual(tester, 'aira');
    await _settle(tester);
    expect(find.byType(AiraModeView), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jarvis_visual_mode_v1'), 'aira');

    // Simulated cold restart: new widget tree, same storage.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_Harness().build());
    await _settle(tester);
    expect(find.byKey(const ValueKey('core-hud')), findsOneWidget);
    expect(find.byType(AiraModeView), findsNothing);

    await _chooseVisual(tester, 'aira');
    expect(find.byType(AiraModeView), findsOneWidget);
    await _chooseVisual(tester, 'core');
    await _settle(tester);
    expect(find.byKey(const ValueKey('core-hud')), findsOneWidget);
    expect(prefs.getString('jarvis_visual_mode_v1'), 'core');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saved previous style never overrides the core startup screen', (tester) async {
    SharedPreferences.setMockInitialValues({'jarvis_visual_mode_v1': 'mira'});
    await tester.pumpWidget(_Harness().build());
    await _settle(tester);
    expect(find.byKey(const ValueKey('core-hud')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    SharedPreferences.setMockInitialValues({'jarvis_visual_mode_v1': 'bogus'});
    await tester.pumpWidget(_Harness().build());
    await _settle(tester);
    expect(find.byKey(const ValueKey('core-hud')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AIRA, Office, APEX and MIRA route text and mic to the same native callbacks',
      (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await _settle(tester);
    for (final m in [JarvisVisualMode.aira, JarvisVisualMode.office,
        JarvisVisualMode.apex, JarvisVisualMode.mira]) {
      await _chooseVisual(tester, m.name);
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('dock-input')), 'hello from ${m.name}');
      await tester.tap(find.byKey(const ValueKey('dock-send')));
      await tester.tap(find.byKey(const ValueKey('dock-mic')));
      await _settle(tester);
    }
    expect(h.commands, ['hello from aira', 'hello from office', 'hello from apex',
        'hello from mira']);
    expect(h.mic, 4);
    // Unconfigured Live voice is honestly DISCONNECTED, never "online".
    expect(find.text('LIVE: DISCONNECTED'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AIRA follows the shared JARVIS phase, with transient Completed', (tester) async {
    final phase = _Phase();
    final b = AiraPhaseBinding(phase, () => phase.value);
    expect(b.value, AiraVisualState.idle);
    phase.set(JarvisPhase.listening);
    expect(b.value, AiraVisualState.listening);
    phase.set(JarvisPhase.thinking);
    expect(b.value, AiraVisualState.thinking);
    phase.set(JarvisPhase.executing);
    expect(b.value, AiraVisualState.processing);
    phase.set(JarvisPhase.speaking);
    expect(b.value, AiraVisualState.speaking);
    phase.set(JarvisPhase.idle);
    expect(b.value, AiraVisualState.completed);
    await tester.pump(const Duration(seconds: 2));
    expect(b.value, AiraVisualState.idle);
    b.dispose();
  });

  testWidgets('phase updates retain the chosen AIRA visual and shared dock', (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await _settle(tester);
    await _chooseVisual(tester, 'aira');
    h.phase.set(JarvisPhase.speaking);
    await _settle(tester);
    expect(find.textContaining('LIVE · SPEAKING'), findsOneWidget);
    expect(find.text('JARVIS · SPEAKING'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AIRA model picker shows 10 live cards and persists choice', (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await _settle(tester);
    await _chooseVisual(tester, 'aira');
    await _settle(tester);
    final strip = find.byKey(const ValueKey('aira-model-strip'));
    expect(strip, findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('aira-model-solarFlare')), 150,
        scrollable: find.descendant(of: strip, matching: find.byType(Scrollable)));
    await tester.ensureVisible(find.byKey(const ValueKey('aira-model-solarFlare')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('aira-model-solarFlare')));
    await _settle(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AiraPreferences.kModel), 'solarFlare');
    expect(find.textContaining('SOLAR FLARE'), findsOneWidget);
    // Previews animate: the live core advances frames over time.
    final core = tester.state<AiraCoreViewState>(find.byKey(const ValueKey('aira-main-core')));
    final before = core.paintedFrames;
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(core.paintedFrames, greaterThan(before));
    // State preview chip is labelled PREVIEW, live state labelled LIVE.
    expect(find.textContaining('LIVE · IDLE'), findsOneWidget);
    final speaking = find.widgetWithText(ChoiceChip, 'Speaking');
    await tester.scrollUntilVisible(speaking, 120, scrollable: find.descendant(
        of: find.byKey(const ValueKey('aira-state-strip')), matching: find.byType(Scrollable)));
    await tester.ensureVisible(speaking);
    await _settle(tester);
    await tester.tap(speaking);
    await _settle(tester);
    expect(find.textContaining('PREVIEW · SPEAKING'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow screen with keyboard open keeps controls on screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 1300); // keyboard covers ~half
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await _settle(tester);
    await _chooseVisual(tester, 'aira');
    await _settle(tester);
    expect(tester.takeException(), isNull);
    final input = tester.getRect(find.byKey(const ValueKey('dock-input')));
    expect(input.bottom, lessThanOrEqualTo(1300 / 3));
    // Compact layout swaps the strip for a model button.
    expect(find.byKey(const ValueKey('aira-model-strip')), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('APEX and MIRA remain distinct offline renderers', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Row(children: [
      Expanded(child: JarvisLocalVisual(apex: true)),
      Expanded(child: JarvisLocalVisual(apex: false)),
    ])));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('APEX • REACTOR'), findsOneWidget);
    expect(find.text('MIRA • NEURAL FIELD'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
