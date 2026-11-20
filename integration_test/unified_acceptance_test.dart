// On-device acceptance for the unified JARVIS app. Runs INSIDE the real APK on
// a CI emulator via `flutter drive` (real AiService, real network, real
// SharedPreferences, no mocks). No API key is present, so live Gemini answers
// are not tested here and stay UNVERIFIED.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/core/build_profile.dart';
import 'package:private_agent/main.dart' as app;
import 'package:private_agent/services/jarvis_service.dart';

const expectFlavor = String.fromEnvironment('EXPECT_FLAVOR', defaultValue: 'standard');

void report(String id, String status, String detail) {
  // Parsed by CI into the acceptance summary.
  // ignore: avoid_print
  print('ACCEPT $id $status $detail');
}

/// The HUD animates forever, so pumpAndSettle would never return.
Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<bool> waitFor(WidgetTester t, Finder f, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return true;
  }
  return false;
}

Future<void> scrollTo(WidgetTester t, Finder f) async {
  for (var i = 0; i < 25 && f.evaluate().isEmpty; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await pumpFor(t, const Duration(milliseconds: 400));
  }
  if (f.evaluate().isNotEmpty) {
    await t.ensureVisible(f.first);
    await pumpFor(t, const Duration(milliseconds: 400));
  }
}

String textOf(Finder f) {
  final w = f.evaluate().first.widget;
  if (w is Text) return w.data ?? '';
  if (w is SelectableText) return w.data ?? '';
  return '';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name) async {
    try {
      await binding.convertFlutterSurfaceToImage();
      await t.pump();
      await binding.takeScreenshot(name);
    } catch (e) {
      // ignore: avoid_print
      print('screenshot $name failed: $e');
    }
  }

  testWidgets('unified JARVIS acceptance ($expectFlavor build)', (t) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarding_complete', true);
    await p.setString('ui_app_mode', 'jarvis');
    await p.setString('jarvis_visual_mode_v1', 'aira');
    await p.setString('aira_model_v1', 'neuralReactor');
    await p.setString('aira_quality_v1', 'balanced');
    await p.remove('ai_api_key');
    app.main();
    await pumpFor(t, const Duration(seconds: 10));
    await shot(t, 'i-home-aira');

    // I01 build profile matches the flavor this APK was built with
    report('I01', BuildProfile.flavor == expectFlavor ? 'PASS' : 'FAIL',
        'appFlavor=${BuildProfile.flavor} expected=$expectFlavor');
    final bubble = find.byTooltip('Show floating bubble');
    final hasBubble = bubble.evaluate().isNotEmpty;
    report('I02', hasBubble == (expectFlavor == 'full') ? 'PASS' : 'FAIL',
        'floating-bubble button ${hasBubble ? "shown" : "hidden"} in $expectFlavor build');

    if (expectFlavor == 'standard') {
      // I03 THINKING guard on the real router (no key configured)
      final input = find.byKey(const ValueKey('dock-input'));
      if (await waitFor(t, input, const Duration(seconds: 10))) {
        await t.enterText(input, 'what is the capital of france');
        await t.tap(find.byKey(const ValueKey('dock-send')));
        final started = DateTime.now();
        await pumpFor(t, const Duration(seconds: 2));
        await shot(t, 'i-command-sent');
        final js = JarvisService.instance;
        var stuck = true;
        final end = started.add(const Duration(seconds: 140));
        while (DateTime.now().isBefore(end)) {
          await t.pump(const Duration(milliseconds: 500));
          if (js.phase != JarvisPhase.thinking && js.phase != JarvisPhase.executing) {
            stuck = false;
            break;
          }
        }
        final secs = DateTime.now().difference(started).inSeconds;
        await pumpFor(t, const Duration(seconds: 2));
        await shot(t, 'i-command-result');
        report('I03', stuck ? 'FAIL' : 'PASS',
            '${stuck ? "still THINKING" : "left THINKING"} after ${secs}s; phase=${js.phase.name}; '
            'status="${js.statusMessage}"; reply="${js.lastJarvisSpeech.replaceAll('\n', ' ')}"');
        // Let any spoken reply finish before navigating.
        await pumpFor(t, const Duration(seconds: 4));
      } else {
        report('I03', 'FAIL', 'dock input not found');
      }
    }

    // I04 Settings: build label + honest AI status
    await t.tap(find.byTooltip('Settings').first);
    await pumpFor(t, const Duration(seconds: 3));
    final label = find.byKey(const ValueKey('build-profile'));
    await scrollTo(t, label);
    if (label.evaluate().isNotEmpty) {
      final txt = textOf(label);
      final want = expectFlavor == 'standard' ? 'STANDARD BUILD' : 'FULL CONTROL BUILD';
      final notice = find.byKey(const ValueKey('build-profile-notice')).evaluate().isNotEmpty;
      report('I04', txt == want && notice == (expectFlavor == 'standard') ? 'PASS' : 'FAIL',
          'Settings shows "$txt"; standard notice ${notice ? "shown" : "absent"}');
      await shot(t, 'i-settings-$expectFlavor');
    } else {
      report('I04', 'FAIL', 'build label not found in Settings');
    }
    final status = find.byKey(const ValueKey('settings-ai-status'));
    if (status.evaluate().isNotEmpty) {
      final s = textOf(status);
      report('I05', s.startsWith('AI ONLINE') ? 'FAIL' : 'PASS', 'AI status with no key: "$s"');
    } else {
      report('I05', 'FAIL', 'AI status not found');
    }
    if (expectFlavor != 'standard') return;

    // I06 diagnostics against the real network (no key → must stop at key step, never ONLINE)
    final diagBtn = find.byKey(const ValueKey('open-ai-diagnostics'));
    await scrollTo(t, diagBtn);
    if (diagBtn.evaluate().isNotEmpty) {
      await t.tap(diagBtn);
      await pumpFor(t, const Duration(seconds: 2));
      await t.tap(find.byKey(const ValueKey('run-diagnostics')));
      final done = await waitFor(t, find.byKey(const ValueKey('diag-result')), const Duration(seconds: 90));
      await pumpFor(t, const Duration(seconds: 1));
      await shot(t, 'i-diagnostics');
      final tiles = find.byType(ListTile).evaluate().map((e) {
        final lt = e.widget as ListTile;
        String s(Widget? w) => w is Text ? (w.data ?? '') : '';
        return '${s(lt.title)}: ${s(lt.subtitle)}';
      }).join(' | ');
      final st = textOf(find.byKey(const ValueKey('ai-status')));
      report('I06', done && !st.contains('ONLINE') ? 'PASS' : 'FAIL', 'status="$st" steps: $tiles');
      await t.pageBack();
      await pumpFor(t, const Duration(seconds: 2));
    } else {
      report('I06', 'FAIL', 'diagnostics button not found');
    }

    // I07/I08 Trading AI risk gate + journal audit
    final tradeBtn = find.byKey(const ValueKey('open-trading-ai'));
    await scrollTo(t, tradeBtn);
    if (tradeBtn.evaluate().isEmpty) {
      report('I07', 'FAIL', 'Trading AI button not found');
      return;
    }
    await t.tap(tradeBtn);
    await pumpFor(t, const Duration(seconds: 2));
    Future<String> gate(String entry, String sl, String conf, String time) async {
      await t.enterText(find.byKey(const ValueKey('t-entry')), entry);
      await t.enterText(find.byKey(const ValueKey('t-sl')), sl);
      await t.enterText(find.byKey(const ValueKey('t-conf')), conf);
      await t.enterText(find.byKey(const ValueKey('t-time')), time);
      await scrollTo(t, find.byKey(const ValueKey('t-check')));
      await t.tap(find.byKey(const ValueKey('t-check')));
      await pumpFor(t, const Duration(seconds: 1));
      final r = find.byKey(const ValueKey('t-gate'));
      return r.evaluate().isEmpty ? '' : textOf(r);
    }
    final ok = await gate('120', '110', '78', '10:15');
    await shot(t, 'i-trading-valid');
    final blocked = await gate('120', '110', '65', '09:20');
    await shot(t, 'i-trading-blocked');
    report('I07', ok.startsWith('TRADE (PAPER)') && ok.contains('TP8') && blocked.startsWith('NO TRADE') &&
            blocked.contains('09:30') && blocked.contains('70') ? 'PASS' : 'FAIL',
        'valid → "${ok.split('\n').take(2).join(' / ')}"; 09:20 & 65% → "${blocked.replaceAll('\n', ' / ')}"');

    const csv = 'Date,Entry Time,Exit Time,Symbol,Side,Entry,Exit,SL,Qty,PnL,Fees,Confidence\n'
        '2026-11-17,09:20,09:40,NIFTY,LONG,100,110,90,75,710,40,80\n'
        '2026-11-17,10:00,10:30,NIFTY,LONG,120,100,100,75,-1540,40,65\n';
    final j = find.byKey(const ValueKey('t-journal'));
    await scrollTo(t, j);
    await t.enterText(j, csv);
    await scrollTo(t, find.byKey(const ValueKey('t-audit')));
    await t.tap(find.byKey(const ValueKey('t-audit')));
    await pumpFor(t, const Duration(seconds: 2));
    final rep = find.byKey(const ValueKey('t-report'));
    await scrollTo(t, rep);
    final r = rep.evaluate().isEmpty ? '' : textOf(rep);
    await shot(t, 'i-trading-audit');
    final saved = (await SharedPreferences.getInstance()).getString('trading_journal_csv_v1') ?? '';
    report('I08', r.contains('before 09:30') && r.contains('70%') && saved == csv ? 'PASS' : 'FAIL',
        'audit: "${r.replaceAll('\n', ' / ')}" ; journal persisted=${saved == csv}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
