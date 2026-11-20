// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/avatar/avatar_runtime.dart';
import 'package:private_agent/avatar/avatar_settings_screen.dart';
import 'package:private_agent/avatar/core/avatar_settings.dart';
import 'package:private_agent/avatar/core/avatar_state_machine.dart';
import 'package:private_agent/avatar/serpent_guardian_view.dart';
import 'package:private_agent/brain/visual_bus.dart';
import 'package:private_agent/services/agent_office/agent_office.dart';
import 'package:private_agent/services/gemini_live/live_voice_controller.dart';
import 'package:private_agent/services/jarvis_service.dart' show JarvisPhase;
import 'package:private_agent/widgets/jarvis_visual_mode_host.dart';

class _Phase extends ChangeNotifier {
  JarvisPhase value = JarvisPhase.idle;
  void set(JarvisPhase p) {
    value = p;
    notifyListeners();
  }
}

Future<void> _frames(WidgetTester t, double seconds) async {
  final n = (seconds * 30).round();
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 33));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AvatarSettingsStore.listenable(serpentGuardianId).value = AvatarSettings.defaults;
  });

  Widget app(_Phase phase, {double sound = 0.4, GlobalKey<SerpentGuardianViewState>? key}) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(412, 915)),
          child: Scaffold(
            body: SerpentGuardianView(
                key: key, phaseReader: () => phase.value, phaseSource: phase, soundReader: () => sound),
          ),
        ),
      );

  testWidgets('renders live, runs the intro timeline and follows JARVIS phases', (tester) async {
    final phase = _Phase();
    final key = GlobalKey<SerpentGuardianViewState>();
    await tester.pumpWidget(app(phase, key: key));
    expect(find.byKey(const ValueKey('serpent-guardian-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('serpent-placeholder-label')), findsOneWidget,
        reason: 'placeholder geometry must be labelled on screen');
    expect(key.currentState!.state, AvatarState.intro);
    await _frames(tester, 2.0);
    expect(key.currentState!.state, AvatarState.materializing);
    await _frames(tester, 4.6);
    expect(key.currentState!.state, AvatarState.idle);
    expect(key.currentState!.perf.snapshot().frames, greaterThan(100), reason: 'painted every frame');

    for (final p in [JarvisPhase.listening, JarvisPhase.thinking, JarvisPhase.executing, JarvisPhase.speaking]) {
      phase.set(p);
      await _frames(tester, 0.3);
      expect(key.currentState!.state, AvatarStateMachine.stateForPhase(p.name));
    }
    publishAvatarSpeech('Vanakkam boss, naan ready.');
    var jaw = 0.0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 33));
      final j = key.currentState!.scene.face.jawOpen;
      if (j > jaw) jaw = j;
    }
    expect(jaw, greaterThan(0.3), reason: 'speech cue drives the mouth');
    phase.set(JarvisPhase.idle);
    await _frames(tester, 0.5);

    sendAvatarCommand('close');
    await _frames(tester, 2);
    expect(key.currentState!.scene.machine.closed, isTrue);
    sendAvatarCommand('replay_intro');
    await tester.pump(const Duration(milliseconds: 33));
    expect(key.currentState!.state, AvatarState.intro);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings persist per avatar and apply live', (tester) async {
    final phase = _Phase();
    final key = GlobalKey<SerpentGuardianViewState>();
    await tester.pumpWidget(app(phase, key: key));
    await _frames(tester, 0.3);
    await AvatarSettingsStore.save(serpentGuardianId,
        const AvatarSettings(primaryColor: 0xFFFF00AA, performance: AvatarPerformanceMode.battery, scale: 0.8));
    await _frames(tester, 0.2);
    final s = key.currentState!.scene.settings;
    expect(s.primaryColor, 0xFFFF00AA);
    expect(key.currentState!.scene.budget.targetFps, 30);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('avatar_settings_v1_serpent_guardian'), contains('#FF00AA'));
    // Fresh load (cold start) restores the same values.
    AvatarSettingsStore.listenable(serpentGuardianId).value = AvatarSettings.defaults;
    final loaded = await AvatarSettingsStore.load(serpentGuardianId);
    expect(loaded.scale, 0.8);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings screen: HEX colour picker, sliders, switches, performance', (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AvatarSettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('avatar-color-primary')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('picker-hex')), '#123ABC');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('picker-ok')));
    await tester.pumpAndSettle();
    expect(AvatarSettingsStore.listenable(serpentGuardianId).value.primaryColor, 0xFF123ABC);
    expect(find.text('#123ABC'), findsOneWidget);

    // Invalid HEX is rejected with an error, not applied.
    await tester.tap(find.byKey(const ValueKey('avatar-color-secondary')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('picker-hex')), '#XYZ');
    await tester.tap(find.byKey(const ValueKey('picker-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid colour'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(AvatarSettingsStore.listenable(serpentGuardianId).value.secondaryColor, AvatarSettings.defaults.secondaryColor);

    await tester.drag(find.byKey(const ValueKey('avatar-density')), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(AvatarSettingsStore.listenable(serpentGuardianId).value.particleDensity, lessThan(0.7));

    await tester.scrollUntilVisible(find.byKey(const ValueKey('avatar-performance')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Battery'));
    await tester.pumpAndSettle();
    expect(AvatarSettingsStore.listenable(serpentGuardianId).value.performance, AvatarPerformanceMode.battery);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('avatar-intro-sound')), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('avatar-intro-sound')));
    await tester.pumpAndSettle();
    expect(AvatarSettingsStore.listenable(serpentGuardianId).value.introSound, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(AvatarSettings.decode(prefs.getString('avatar_settings_v1_serpent_guardian')).introSound, isFalse);
  });

  testWidgets('Serpent Guardian is one selectable mode in the existing host; dock routes to native JARVIS',
      (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final phase = _Phase();
    final commands = <String>[];
    var mic = 0;
    final live = LiveVoiceController(observeLifecycle: false);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(412, 915)),
        child: Scaffold(
          body: JarvisVisualModeHost(
            onCommand: commands.add,
            onMicrophone: () async => mic++,
            phaseSource: phase,
            phaseReader: () => phase.value,
            soundReader: () => .2,
            coreBuilder: (_) => const Center(child: Text('NATIVE JARVIS HUD', key: ValueKey('core-hud'))),
            office: AgentOfficeController(),
            liveVoice: live,
            localTask: () => (goal: '', state: 'idle', step: 0),
            localTaskListenable: ChangeNotifier(),
          ),
        ),
      ),
    ));
    await _frames(tester, 0.3);
    expect(visualModes, contains('serpent'));
    await tester.tap(find.byKey(const ValueKey('mode-serpent')));
    await _frames(tester, 0.5);
    expect(find.byType(SerpentGuardianView), findsOneWidget);
    expect(find.byKey(const ValueKey('core-hud')), findsNothing, reason: 'one selected avatar at a time');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jarvis_visual_mode_v1'), 'serpent');
    await tester.enterText(find.byKey(const ValueKey('dock-input')), 'hello guardian');
    await tester.tap(find.byKey(const ValueKey('dock-send')));
    await tester.tap(find.byKey(const ValueKey('dock-mic')));
    await _frames(tester, 0.2);
    expect(commands, ['hello guardian']);
    expect(mic, 1);
    await tester.tap(find.byKey(const ValueKey('mode-core')));
    await _frames(tester, 0.4);
    expect(find.byType(SerpentGuardianView), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
