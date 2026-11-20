import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/services/gemini_live/live_voice_controller.dart';
import 'package:private_agent/services/jarvis_service.dart';
import 'package:private_agent/widgets/jarvis_visual_mode_host.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'locked phone layout has only shared input/mic/send, with large text and keyboard',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final phase = ValueNotifier(JarvisPhase.idle), commands = <String>[];
      final live = LiveVoiceController(observeLifecycle: false);
      var mic = 0;
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              viewInsets: EdgeInsets.only(bottom: 320),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: JarvisVisualModeHost(
                minimalist: true,
                phaseSource: phase,
                phaseReader: () => phase.value,
                soundReader: () => 0,
                coreBuilder: (_) =>
                    const Center(child: Icon(Icons.blur_circular)),
                liveVoice: live,
                onCommand: commands.add,
                onMicrophone: () async {
                  mic++;
                },
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('mode-selector')), findsNothing);
      expect(find.byKey(const ValueKey('dock-live')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('dock-input')), 'hello');
      await t.tap(find.byKey(const ValueKey('dock-send')));
      await t.pump();
      expect(commands, ['hello']);
      await t.tap(find.byKey(const ValueKey('dock-mic')));
      expect(mic, 1);
      phase.value = JarvisPhase.thinking;
      await t.pump();
      await t.tap(find.byKey(const ValueKey('dock-send')));
      expect(commands.last, 'cancel');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      phase.dispose();
      live.dispose();
    },
  );
}
