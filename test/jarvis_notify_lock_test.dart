// Regression for the device failure seen in CI run 44664160976 (Android 15/16):
// "setState() called when widget tree was locked" from
// JarvisHudWidget.dispose → JarvisService.onExitJarvisMode → notifyListeners.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/services/jarvis_service.dart';
import 'package:private_agent/services/settings_service.dart';

class _ExitsOnDispose extends StatefulWidget {
  const _ExitsOnDispose();
  @override
  State<_ExitsOnDispose> createState() => _ExitsOnDisposeState();
}

class _ExitsOnDisposeState extends State<_ExitsOnDispose> {
  @override
  void dispose() {
    JarvisService.instance.onExitJarvisMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  // Create the singleton (and its periodic proactive timer) outside the
  // fake-async test zone.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    JarvisService.instance;
  });

  testWidgets('notifying from dispose does not throw and still reaches listeners', (t) async {
    var builds = 0;
    final show = ValueNotifier(true);
    await t.pumpWidget(MaterialApp(home: Column(children: [
      ListenableBuilder(listenable: JarvisService.instance, builder: (_, __) {
        builds++;
        return Text(JarvisService.instance.statusMessage);
      }),
      ValueListenableBuilder<bool>(valueListenable: show, builder: (_, v, __) => v ? const _ExitsOnDispose() : const SizedBox()),
    ])));
    final before = builds;
    show.value = false;
    await t.pump();
    expect(t.takeException(), isNull);
    await t.pump();
    expect(builds, greaterThan(before), reason: 'deferred notification must still be delivered');
  });
}
