import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/brain/visual_bus.dart';
import 'package:private_agent/jarvis_v3/chat_interface_settings.dart';
import 'package:private_agent/jarvis_v3/jarvis_v3_home.dart';
import 'package:private_agent/jarvis_v3/holographic_stage.dart';
import 'package:private_agent/jarvis_v3/hologram_theme_store.dart';
import 'package:private_agent/jarvis_v3/visual_mode_store.dart';
import 'package:private_agent/theme/app_theme.dart';
import 'package:private_agent/widgets/jarvis_visual_mode_host.dart';

import 'fixtures/v3_fixtures.dart';

Future<FakeConversation> pumpHome(WidgetTester tester,
    {Size size = const Size(412, 915), bool intro = false}) async {
  SharedPreferences.setMockInitialValues({});
  ChatInterfaceSettings.instance.resetForTest();
  VisualModeStore.instance.value = JarvisVisualMode.core;
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final fake = FakeConversation();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: JarvisV3Home(
        key: UniqueKey(),
        bindings: fake.bindings(),
        onOpenMenu: () {},
        onOpenSettings: () {},
        playIntro: intro,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return fake;
}

double conversationOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const ValueKey('v3-conversation-opacity')))
    .opacity;

void main() {
  testWidgets('main screen is clean: header, humanoid, one dock; no manual state or gallery controls',
      (tester) async {
    await pumpHome(tester);
    expect(find.byKey(const ValueKey('v3-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('v3-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('v3-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('v3-status')), findsOneWidget);
    expect(find.byType(HolographicStage), findsOneWidget,
        reason: 'real WebGL stage replaces the image renderer');
    expect(find.byKey(const ValueKey('v3-dock')), findsOneWidget);
    // Text field, mic and send all inside the single dock.
    for (final k in ['v3-dock-input', 'v3-dock-mic', 'v3-dock-send']) {
      expect(find.descendant(of: find.byKey(const ValueKey('v3-dock')), matching: find.byKey(ValueKey(k))),
          findsOneWidget, reason: k);
    }
    // Removed clutter.
    expect(find.byKey(const ValueKey('mode-selector')), findsNothing, reason: 'six mode buttons');
    for (final s in ['PREVIEW', 'Idle', 'Listening', 'Thinking', 'Processing', 'LIVE: DISCONNECTED', 'placeholder']) {
      expect(find.textContaining(s), findsNothing, reason: s);
    }
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow or clipping at narrow, tall and wide sizes', (tester) async {
    for (final size in const [Size(360, 640), Size(412, 915), Size(480, 1040), Size(800, 1280)]) {
      await pumpHome(tester, size: size);
      expect(tester.takeException(), isNull, reason: '$size');
      final dock = tester.getRect(find.byKey(const ValueKey('v3-dock')));
      expect(dock.left, greaterThanOrEqualTo(0));
      expect(dock.right, lessThanOrEqualTo(size.width));
      expect(dock.bottom, lessThanOrEqualTo(size.height));
      final title = tester.getRect(find.byKey(const ValueKey('v3-title')));
      expect(title.top, greaterThanOrEqualTo(0));
      expect(title.overlaps(dock), isFalse);
    }
  });

  testWidgets('dock stays above the navigation bar inset and the keyboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ChatInterfaceSettings.instance.resetForTest();
    VisualModeStore.instance.value = JarvisVisualMode.core;
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: 48 * 3, top: 32 * 3);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320 * 3);
    addTearDown(tester.view.reset);
    final fake = FakeConversation();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: JarvisV3Home(bindings: fake.bindings(), onOpenMenu: () {}, onOpenSettings: () {}, playIntro: false),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final dock = tester.getRect(find.byKey(const ValueKey('v3-dock')));
    expect(dock.bottom, lessThanOrEqualTo(915 - 320), reason: 'above the keyboard');
    expect(tester.takeException(), isNull);
  });

  testWidgets('user and JARVIS bubbles use distinct colours and alignment', (tester) async {
    final fake = await pumpHome(tester);
    fake.think('Open YouTube');
    await tester.pump();
    fake.speak('Opening YouTube.');
    await tester.pump(const Duration(milliseconds: 50));
    final user = tester.getRect(find.byKey(const ValueKey('bubble-user')));
    final jarvis = tester.getRect(find.byKey(const ValueKey('bubble-jarvis')));
    expect(user.center.dx, greaterThan(206), reason: 'user right-aligned');
    expect(jarvis.center.dx, lessThan(206), reason: 'JARVIS left-aligned');
    final userText = tester.widget<Text>(find.byKey(const ValueKey('bubble-user')));
    final jarvisText = tester.widget<Text>(find.byKey(const ValueKey('bubble-jarvis')));
    expect(userText.style!.color, isNot(jarvisText.style!.color));
  });

  testWidgets('auto-hide follows real events end to end', (tester) async {
    final fake = await pumpHome(tester);
    fake.listen('what is the time');
    await tester.pump();
    expect(find.text('what is the time'), findsOneWidget, reason: 'live cyan transcript while listening');
    await tester.pump(const Duration(seconds: 30));
    expect(conversationOpacity(tester), 1, reason: 'never hides while listening');
    fake.think('what is the time');
    await tester.pump(const Duration(seconds: 30));
    expect(conversationOpacity(tester), 1, reason: 'never hides while thinking');
    fake.speak('It is ten thirty.');
    await tester.pump(const Duration(seconds: 30));
    expect(conversationOpacity(tester), 1, reason: 'kept during speech');
    fake.idle();
    await tester.pump(const Duration(seconds: 7));
    expect(conversationOpacity(tester), 1, reason: 'countdown starts after speaking ends');
    await tester.pump(const Duration(seconds: 2));
    expect(conversationOpacity(tester), 0, reason: 'hidden after 8 s idle');
    // History remains available through its explicit title control.
    expect(find.text('It is ten thirty.'), findsOneWidget);
    tester.state<JarvisV3HomeState>(find.byType(JarvisV3Home)).autoHide.reveal();
    await tester.pump();
    expect(conversationOpacity(tester), 1);
    // The dock and header stay visible throughout.
    expect(find.byKey(const ValueKey('v3-dock')), findsOneWidget);
  });

  testWidgets('input focus pauses auto-hide', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('v3-dock-input')));
    await tester.pump(const Duration(seconds: 20));
    expect(conversationOpacity(tester), 1);
  });

  testWidgets('an error stays visible until dismissed', (tester) async {
    final fake = await pumpHome(tester);
    fake.think('call mom');
    await tester.pump();
    fake.speak('The AI service is unavailable right now.', status: 'AI ERROR // NETWORK');
    await tester.pump();
    fake.idle();
    await tester.pump(const Duration(seconds: 40));
    expect(conversationOpacity(tester), 1);
    await tester.tap(find.byKey(const ValueKey('v3-ack-notice')));
    await tester.pump(const Duration(seconds: 9));
    expect(conversationOpacity(tester), 0);
  });

  testWidgets('send goes to the native router once; mic toggles the real recogniser', (tester) async {
    final fake = await pumpHome(tester);
    // No frame between typing and tapping: the tap must still dispatch.
    await tester.enterText(find.byKey(const ValueKey('v3-dock-input')), 'Set an alarm for 6');
    await tester.tap(find.byKey(const ValueKey('v3-dock-send')));
    await tester.pump();
    expect(fake.commands, ['Set an alarm for 6'], reason: 'exactly one dispatch');
    await tester.tap(find.byKey(const ValueKey('v3-dock-send')));
    await tester.pump();
    expect(fake.commands.length, 1, reason: 'empty input does not dispatch');
    await tester.tap(find.byKey(const ValueKey('v3-dock-mic')));
    await tester.pump();
    expect(fake.micToggles, 1);
  });

  testWidgets('six 3D themes retain the scene and do not restart the microphone', (tester) async {
    final fake=await pumpHome(tester);
    final original=tester.state(find.byType(HolographicStage));
    for(final theme in HologramThemeStore.themes) {
      HologramThemeStore.instance.value=theme;
      await tester.pump();
      expect(tester.widget<HolographicStage>(find.byType(HolographicStage)).theme,theme);
      expect(tester.state(find.byType(HolographicStage)),same(original));
      expect(fake.micToggles,0);
    }
  });

  testWidgets('intro remains active until renderer completion and skip disables it', (tester) async {
    await pumpHome(tester,intro:true);
    expect(find.byKey(const ValueKey('v3-skip-intro')),findsOneWidget);
    await tester.pump(const Duration(seconds:8));
    expect(find.byKey(const ValueKey('v3-skip-intro')),findsOneWidget,
      reason:'Flutter must not claim the WebGL intro completed on a timer');
    tester.widget<HolographicStage>(find.byType(HolographicStage)).onIntroFinished();
    await tester.pump();
    expect(find.byKey(const ValueKey('v3-skip-intro')),findsNothing);
    await pumpHome(tester,intro:true);
    await tester.tap(find.byKey(const ValueKey('v3-skip-intro')));
    await tester.pump();
    expect(tester.widget<HolographicStage>(find.byType(HolographicStage)).playIntro,isFalse);
  });

  testWidgets('reduced motion: no intro and no running animation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ChatInterfaceSettings.instance.resetForTest();
    ChatInterfaceSettings.instance.reduceMotion = true;
    addTearDown(ChatInterfaceSettings.instance.resetForTest);
    final fake = FakeConversation();
    await tester.pumpWidget(MaterialApp(
      home: JarvisV3Home(bindings: fake.bindings(), onOpenMenu: () {}, onOpenSettings: () {}),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('v3-skip-intro')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'no continuous animation');
  });

  testWidgets('voice/brain visual requests switch the V3 mode (e.g. "switch to apex")', (tester) async {
    await pumpHome(tester);
    await tester.runAsync(() => requestVisual(mode: 'apex'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('v3-real-3d')), findsOneWidget);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('jarvis_visual_mode_v1'), 'apex');
    expect(HologramThemeStore.instance.value, 'apex');
    await tester.runAsync(() => requestVisual(mode: 'core'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('v3-real-3d')), findsOneWidget);
  });

  testWidgets('dock text field stays transparent under the real app theme (light and dark)', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      SharedPreferences.setMockInitialValues({});
      ChatInterfaceSettings.instance.resetForTest();
      final fake = FakeConversation();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(body: JarvisV3Home(
            key: UniqueKey(), bindings: fake.bindings(), onOpenMenu: () {}, onOpenSettings: () {}, playIntro: false)),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('v3-dock-input')));
      await tester.pump();
      final deco = tester.widget<InputDecorator>(find.descendant(
          of: find.byKey(const ValueKey('v3-dock-input')), matching: find.byType(InputDecorator))).decoration;
      expect(deco.filled, isFalse, reason: 'no theme fill inside the neon dock');
      expect(deco.focusedBorder, InputBorder.none);
      expect(deco.enabledBorder, InputBorder.none);
    }
  });
}
