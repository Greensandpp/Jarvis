// Renders the V3 main screen to PNG files for visual review.
// Runs only with: flutter test test/visual_capture_test.dart --dart-define=CAPTURE_DIR=<dir>
// (CI passes it; a normal `flutter test` skips these.)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/jarvis_v3/chat_interface_settings.dart';
import 'package:private_agent/jarvis_v3/jarvis_v3_home.dart';
import 'package:private_agent/jarvis_v3/visual_mode_store.dart';
import 'package:private_agent/widgets/jarvis_visual_mode_host.dart';

import 'fixtures/v3_fixtures.dart';

const captureDir = String.fromEnvironment('CAPTURE_DIR');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) {
        loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Bold.ttf', 'Roboto-Medium.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  // Let fades and other implicit animations reach their rendered value.
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$captureDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _precacheAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final a in ['assets/images/jarvis_male_hologram_gold.png', 'assets/images/serpent_guardian.jpg']) {
      final data = await rootBundle.load(a);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      await codec.getNextFrame();
    }
  });
}

void main() {
  testWidgets('capture V3 screens', (tester) async {
    if (captureDir.isEmpty) return;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    ChatInterfaceSettings.instance.resetForTest();
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 36 * 3, bottom: 24 * 3);
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    final fake = FakeConversation();

    Future<void> mount(JarvisVisualMode mode, {bool intro = false}) async {
      VisualModeStore.instance.value = mode;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: JarvisV3Home(
              key: UniqueKey(),
              bindings: fake.bindings(),
              onOpenMenu: () {},
              onOpenSettings: () {},
              playIntro: intro,
            ),
          ),
        ),
      ));
      // Let Image.asset decode for real.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await _precacheAssets(tester);
    await mount(JarvisVisualMode.core);
    await tester.pump(const Duration(milliseconds: 1500));
    await _shot(tester, boundary, '01-jarvis-idle-empty');

    fake.think('Hey JARVIS, nalaikku Chennai weather eppadi?');
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, boundary, '02-jarvis-thinking');
    fake.speak('Tomorrow in Chennai: 31°C, light rain after 4 PM. Umbrella eduthukonga, sir.');
    fake.level = 0.7;
    await tester.pump(const Duration(milliseconds: 700));
    await _shot(tester, boundary, '03-jarvis-speaking-conversation');
    fake.idle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 9));
    await _shot(tester, boundary, '04-jarvis-idle-chat-auto-hidden');
    fake.listen('open youtube and play');
    fake.level = 0.8;
    await tester.pump(const Duration(milliseconds: 700));
    await _shot(tester, boundary, '05-jarvis-listening-live-transcript');
    fake.idle();

    await mount(JarvisVisualMode.serpent);
    await tester.pump(const Duration(milliseconds: 1500));
    await _shot(tester, boundary, '06-serpent-idle');
    fake.execute();
    await tester.pump(const Duration(milliseconds: 900));
    await _shot(tester, boundary, '07-serpent-executing');
    fake.idle();

    await mount(JarvisVisualMode.aira);
    await tester.pump(const Duration(milliseconds: 1500));
    await _shot(tester, boundary, '08-aira-clean');

    for (final (ms, n) in [(250, 'a-particles'), (900, 'b-convergence'), (1600, 'c-assembly'), (2300, 'd-ignition'), (3600, 'e-stable')]) {
      await mount(JarvisVisualMode.core, intro: true);
      await tester.pump(Duration(milliseconds: ms));
      await _shot(tester, boundary, '09-intro-$n');
    }
    await tester.pumpWidget(const SizedBox());
  });
}
