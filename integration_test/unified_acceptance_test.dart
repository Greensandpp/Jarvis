// On-device acceptance for the unified JARVIS app. Runs INSIDE the real APK on
// a CI emulator via `flutter drive` (real AiService, real network, real
// SharedPreferences, no mocks). No API key is present, so live Gemini answers
// are not tested here and stay UNVERIFIED.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/core/build_profile.dart';
import 'package:private_agent/avatar/avatar_settings.dart';
import 'package:private_agent/avatar/avatar_view.dart';
import 'package:private_agent/main.dart' as app;
import 'package:private_agent/screens/brain/memory_tools.dart';
import 'package:private_agent/services/conversational_memory_service.dart';
import 'package:private_agent/services/jarvis_service.dart';

const expectFlavor = String.fromEnvironment(
  'EXPECT_FLAVOR',
  defaultValue: 'standard',
);

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
  if (f.evaluate().isEmpty && find.byType(Scrollable).evaluate().isNotEmpty) {
    // Target may be above: go back to the top and search downwards again.
    await t.fling(find.byType(Scrollable).first, const Offset(0, 6000), 5000);
    await pumpFor(t, const Duration(seconds: 1));
    for (var i = 0; i < 25 && f.evaluate().isEmpty; i++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await pumpFor(t, const Duration(milliseconds: 400));
    }
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

Future<void> home(WidgetTester t) async {
  // Snackbars from a previous section sit over the dock's Send button.
  for (final m in find.byType(ScaffoldMessenger).evaluate()) {
    (m as StatefulElement).state is ScaffoldMessengerState
        ? (m.state as ScaffoldMessengerState).clearSnackBars()
        : null;
  }
  t
      .state<NavigatorState>(find.byType(Navigator).first)
      .popUntil((r) => r.isFirst);
  await pumpFor(t, const Duration(seconds: 2));
}

Future<void> openCc(WidgetTester t, String name, {bool fromCc = false}) async {
  if (!fromCc) {
    await home(t);
    await t.tap(find.byTooltip('Settings').first);
    await pumpFor(t, const Duration(seconds: 2));
    final cc = find.byKey(const ValueKey('open-control-center'));
    await scrollTo(t, cc);
    await t.tap(cc);
    await pumpFor(t, const Duration(seconds: 2));
  }
  final tile = find.byKey(ValueKey('cc-$name'));
  await scrollTo(t, tile);
  await t.tap(tile);
  await pumpFor(t, const Duration(seconds: 2));
}

/// Runs one acceptance section; an exception is a FAIL, never a crash of the run.
Future<void> section(String id, Future<(bool, String)> Function() body) async {
  try {
    final (ok, detail) = await body();
    report(id, ok ? 'PASS' : 'FAIL', detail);
  } catch (e) {
    report(id, 'FAIL', 'exception: ${'$e'.split('\n').first}');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  var surfaceConverted = false;
  Future<void> shot(WidgetTester t, String name) async {
    try {
      // Android: the Flutter surface may be converted to an image only once.
      if (!surfaceConverted) {
        await binding.convertFlutterSurfaceToImage();
        surfaceConverted = true;
      }
      await t.pump();
      await binding.takeScreenshot(name);
    } catch (e) {
      // ignore: avoid_print
      print('screenshot $name failed: $e');
    }
  }

  testWidgets(
    'unified JARVIS acceptance ($expectFlavor build)',
    (t) async {
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
      report(
        'I01',
        BuildProfile.flavor == expectFlavor ? 'PASS' : 'FAIL',
        'appFlavor=${BuildProfile.flavor} expected=$expectFlavor',
      );
      final bubble = find.byTooltip('Show floating bubble');
      final hasBubble = bubble.evaluate().isNotEmpty;
      report(
        'I02',
        !hasBubble ? 'PASS' : 'FAIL',
        'locked home keeps overlay control inside Settings ($expectFlavor)',
      );

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
            if (js.phase != JarvisPhase.thinking &&
                js.phase != JarvisPhase.executing) {
              stuck = false;
              break;
            }
          }
          final secs = DateTime.now().difference(started).inSeconds;
          await pumpFor(t, const Duration(seconds: 2));
          await shot(t, 'i-command-result');
          final viaBrain = js.lastHandledByBrain;
          report(
            'I03',
            stuck || !viaBrain ? 'FAIL' : 'PASS',
            '${stuck ? "still THINKING" : "left THINKING"} after ${secs}s via ${viaBrain ? "brain" : "legacy path"}; phase=${js.phase.name}; '
                'status="${js.statusMessage}"; reply="${js.lastJarvisSpeech.replaceAll('\n', ' ')}"',
          );
          // Let any spoken reply finish before navigating.
          await pumpFor(t, const Duration(seconds: 4));
        } else {
          report('I03', 'FAIL', 'dock input not found');
        }
      }

      // Dismiss the user-requested conversation view before navigation.
      await home(t);
      // I04 Settings: build label + honest AI status
      await t.tap(find.byTooltip('Settings').first);
      await pumpFor(t, const Duration(seconds: 3));
      final label = find.byKey(const ValueKey('build-profile'));
      await scrollTo(t, label);
      if (label.evaluate().isNotEmpty) {
        final txt = textOf(label);
        final want = expectFlavor == 'standard'
            ? 'STANDARD BUILD'
            : 'FULL CONTROL BUILD';
        final notice = find
            .byKey(const ValueKey('build-profile-notice'))
            .evaluate()
            .isNotEmpty;
        report(
          'I04',
          txt == want && notice == (expectFlavor == 'standard')
              ? 'PASS'
              : 'FAIL',
          'Settings shows "$txt"; standard notice ${notice ? "shown" : "absent"}',
        );
        await shot(t, 'i-settings-$expectFlavor');
      } else {
        report('I04', 'FAIL', 'build label not found in Settings');
      }
      final status = find.byKey(const ValueKey('settings-ai-status'));
      if (status.evaluate().isNotEmpty) {
        final s = textOf(status);
        report(
          'I05',
          s.startsWith('AI ONLINE') ? 'FAIL' : 'PASS',
          'AI status with no key: "$s"',
        );
      } else {
        report('I05', 'FAIL', 'AI status not found');
      }

      // I06 diagnostics against the real network (no key → must stop at key step, never ONLINE)
      final diagBtn = find.byKey(const ValueKey('open-ai-diagnostics'));
      await scrollTo(t, diagBtn);
      if (diagBtn.evaluate().isNotEmpty) {
        await t.tap(diagBtn);
        await pumpFor(t, const Duration(seconds: 2));
        await t.tap(find.byKey(const ValueKey('run-diagnostics')));
        final done = await waitFor(
          t,
          find.byKey(const ValueKey('diag-result')),
          const Duration(seconds: 90),
        );
        await pumpFor(t, const Duration(seconds: 1));
        await shot(t, 'i-diagnostics');
        final tiles = find
            .byType(ListTile)
            .evaluate()
            .map((e) {
              final lt = e.widget as ListTile;
              String s(Widget? w) => w is Text ? (w.data ?? '') : '';
              return '${s(lt.title)}: ${s(lt.subtitle)}';
            })
            .join(' | ');
        final st = textOf(find.byKey(const ValueKey('ai-status')));
        report(
          'I06',
          done && !st.contains('ONLINE') ? 'PASS' : 'FAIL',
          'status="$st" steps: $tiles',
        );
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
      Future<String> gate(
        String entry,
        String sl,
        String conf,
        String time,
      ) async {
        // The form is in a lazy ListView: scroll back to the top so the fields exist.
        await t.fling(
          find.byType(Scrollable).first,
          const Offset(0, 4000),
          4000,
        );
        await pumpFor(t, const Duration(seconds: 1));
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
      report(
        'I07',
        ok.startsWith('TRADE (PAPER)') &&
                ok.contains('TP8') &&
                blocked.startsWith('NO TRADE') &&
                blocked.contains('09:30') &&
                blocked.contains('70')
            ? 'PASS'
            : 'FAIL',
        'valid → "${ok.split('\n').take(2).join(' / ')}"; 09:20 & 65% → "${blocked.replaceAll('\n', ' / ')}"',
      );

      const csv =
          'Date,Entry Time,Exit Time,Symbol,Side,Entry,Exit,SL,Qty,PnL,Fees,Confidence\n'
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
      final saved =
          (await SharedPreferences.getInstance()).getString(
            'trading_journal_csv_v1',
          ) ??
          '';
      report(
        'I08',
        r.contains('before 09:30') && r.contains('70%') && saved == csv
            ? 'PASS'
            : 'FAIL',
        'audit: "${r.replaceAll('\n', ' / ')}" ; journal persisted=${saved == csv}',
      );

      // I09 indicators + OI from pasted data on device
      await section('I09', () async {
        final b = StringBuffer();
        var px = 100.0;
        for (var i = 0; i < 40; i++) {
          px += i % 5 < 3 ? 2.0 : -1.5;
          b.writeln('t$i,${px - 0.3},${px + 1},${px - 1},$px,${1000 + i * 10}');
        }
        final c = find.byKey(const ValueKey('t-candles'));
        await scrollTo(t, c);
        await t.enterText(c, b.toString());
        await scrollTo(t, find.byKey(const ValueKey('t-ind')));
        await t.tap(find.byKey(const ValueKey('t-ind')));
        await pumpFor(t, const Duration(seconds: 1));
        final ir = find.byKey(const ValueKey('t-ind-report'));
        await scrollTo(t, ir);
        final ind = ir.evaluate().isEmpty ? '' : textOf(ir);
        final o = find.byKey(const ValueKey('t-oi'));
        await scrollTo(t, o);
        await t.enterText(
          o,
          '24000,100,500\n24100,300,400\n24200,600,200\n24300,900,50',
        );
        await scrollTo(t, find.byKey(const ValueKey('t-oi-run')));
        await t.tap(find.byKey(const ValueKey('t-oi-run')));
        await pumpFor(t, const Duration(seconds: 1));
        final or = find.byKey(const ValueKey('t-oi-report'));
        await scrollTo(t, or);
        final oi = or.evaluate().isEmpty ? '' : textOf(or);
        await shot(t, 'i-trading-indicators');
        return (
          ind.contains('BULLISH') &&
              ind.contains('Supertrend UP') &&
              oi.contains('PCR'),
          'indicators: "${ind.split('\n').take(3).join(' / ')}" · OI: "${oi.split('\n').first}"',
        );
      });

      // I10 Control Center: every section opens
      await section('I10', () async {
        await home(t);
        await t.tap(find.byTooltip('Settings').first);
        await pumpFor(t, const Duration(seconds: 2));
        final cc = find.byKey(const ValueKey('open-control-center'));
        await scrollTo(t, cc);
        await t.tap(cc);
        await pumpFor(t, const Duration(seconds: 2));
        await shot(t, 'i-control-center');
        const sections = [
          'AI Brain',
          'API key & Models',
          'Diagnostics',
          'Voice',
          'Memory & Backup',
          'Learning',
          'Trading (paper)',
          'Agents & Audit',
          'Tools',
          'Visuals',
          'Permissions',
          'Automation',
          'Device & PC',
          'Security & Privacy',
        ];
        final opened = <String>[], failed = <String>[];
        for (final name in sections) {
          final tile = find.byKey(ValueKey('cc-$name'));
          await scrollTo(t, tile);
          if (tile.evaluate().isEmpty) {
            failed.add(name);
            continue;
          }
          await t.tap(tile);
          await pumpFor(t, const Duration(milliseconds: 1500));
          final ok =
              find.byType(AppBar).evaluate().length >= 2 ||
              find.byType(BackButton).evaluate().isNotEmpty;
          (ok ? opened : failed).add(name);
          if (name == 'Agents & Audit') await shot(t, 'i-agents');
          if (name == 'Tools') await shot(t, 'i-tools');
          await t.pageBack();
          await pumpFor(t, const Duration(milliseconds: 800));
        }
        return (
          failed.isEmpty,
          '${opened.length}/${sections.length} sections opened${failed.isEmpty ? '' : '; failed: $failed'}',
        );
      });

      // I11 voice diagnostics shows real microphone/TTS facts
      await section('I11', () async {
        await openCc(t, 'Diagnostics');
        await t.tap(find.byKey(const ValueKey('diag-voice')));
        final ok = await waitFor(
          t,
          find.byKey(const ValueKey('diag-voice-result')),
          const Duration(seconds: 20),
        );
        await pumpFor(t, const Duration(seconds: 1));
        await shot(t, 'i-voice-diagnostics');
        final rows = find
            .descendant(
              of: find.byKey(const ValueKey('diag-voice-result')),
              matching: find.byType(ListTile),
            )
            .evaluate()
            .map((e) {
              final lt = e.widget as ListTile;
              return '${(lt.title as Text).data}=${(lt.subtitle as Text).data}';
            })
            .join('; ');
        return (ok && rows.contains('Microphone permission'), rows);
      });

      // I12 memory: add, correct (history), undo, encrypted backup, wrong passphrase, restore
      await section('I12', () async {
        final mem = ConversationalMemoryService.instance;
        await mem.wipeAll();
        await openCc(t, 'Memory & Backup');
        await t.enterText(
          find.byKey(const ValueKey('mem-add-text')),
          'My trading capital is 50000 rupees',
        );
        await t.tap(find.byKey(const ValueKey('mem-add')));
        await pumpFor(t, const Duration(seconds: 1));
        await t.tap(find.byTooltip('Correct').first);
        await pumpFor(t, const Duration(seconds: 1));
        await t.enterText(
          find.byType(TextField).last,
          'My trading capital is 75000 rupees',
        );
        await t.tap(find.text('OK'));
        await pumpFor(t, const Duration(seconds: 2));
        final corrected =
            mem.facts.first.fact.contains('75000') &&
            mem.facts.first.history.length == 1;
        await shot(t, 'i-memory-corrected');
        await t.tap(find.byTooltip('Undo correction').first);
        await pumpFor(t, const Duration(seconds: 1));
        final undone = mem.facts.first.fact.contains('50000');
        await t.tap(find.byTooltip('Correct').first);
        await pumpFor(t, const Duration(seconds: 1));
        await t.enterText(
          find.byType(TextField).last,
          'My trading capital is 75000 rupees',
        );
        await t.tap(find.text('OK'));
        await pumpFor(t, const Duration(seconds: 2));
        // export
        await t.tap(find.byKey(const ValueKey('mem-export')));
        await pumpFor(t, const Duration(seconds: 1));
        await t.enterText(find.byType(TextField).last, 'owner-pass-1');
        await t.tap(find.text('OK'));
        // PBKDF2 runs in a background isolate; wait for the backup file (max 90 s).
        final file = await memoryBackupFile();
        var clip = '';
        final until = DateTime.now().add(const Duration(seconds: 90));
        while (DateTime.now().isBefore(until) &&
            !clip.contains('jarvis-memory-backup')) {
          await pumpFor(t, const Duration(seconds: 1));
          if (await file.exists()) clip = await file.readAsString();
        }
        final snack = find.byType(SnackBar).evaluate().isEmpty
            ? ''
            : find
                  .descendant(
                    of: find.byType(SnackBar),
                    matching: find.byType(Text),
                  )
                  .evaluate()
                  .map((e) => (e.widget as Text).data ?? '')
                  .join(' ');
        // ignore: avoid_print
        print('I12 export snackbar: $snack');
        final exported =
            clip.contains('jarvis-memory-backup') && !clip.contains('75000');
        await mem.clearAllFacts();
        await t.pageBack();
        await pumpFor(t, const Duration(seconds: 1));
        await openCc(t, 'Memory & Backup', fromCc: true);
        Future<void> restore(String pass) async {
          t
              .state<ScaffoldMessengerState>(
                find.byType(ScaffoldMessenger).first,
              )
              .clearSnackBars();
          await pumpFor(t, const Duration(milliseconds: 500));
          await t.tap(find.byKey(const ValueKey('mem-import')));
          await pumpFor(t, const Duration(seconds: 1));
          await t.tap(find.text('OK')); // backup text pre-filled from clipboard
          await pumpFor(t, const Duration(seconds: 1));
          await t.enterText(find.byType(TextField).last, pass);
          await t.tap(find.text('OK'));
          // wait for the result snackbar (decryption runs in an isolate)
          await waitFor(t, find.byType(SnackBar), const Duration(seconds: 90));
          await pumpFor(t, const Duration(seconds: 1));
        }

        await restore('wrong-pass');
        final rejected =
            mem.facts.isEmpty &&
            find.textContaining('Wrong passphrase').evaluate().isNotEmpty;
        await shot(t, 'i-memory-wrong-pass');
        await pumpFor(t, const Duration(seconds: 4));
        await restore('owner-pass-1');
        final restored =
            mem.facts.length == 1 &&
            mem.facts.first.fact.contains('75000') &&
            mem.facts.first.history.length == 1;
        await shot(t, 'i-memory-restored');
        final stored =
            (await SharedPreferences.getInstance()).getString(
              'jarvis_memory_facts_v1',
            ) ??
            '';
        return (
          corrected &&
              undone &&
              exported &&
              rejected &&
              restored &&
              stored.contains('75000'),
          'corrected=$corrected undo=$undone exportEncrypted=$exported wrongPassRejected=$rejected restored=$restored persisted=${stored.contains('75000')}',
        );
      });

      // I13 offline visual switching through the same command path as voice
      await section('I13', () async {
        await home(t);
        final sp = await SharedPreferences.getInstance();
        await sp.setString('aira_model_v1', 'neuralReactor');
        final input = find.byKey(const ValueKey('dock-input'));
        if (!await waitFor(t, input, const Duration(seconds: 8)))
          return (false, 'dock not visible');
        await t.enterText(input, 'switch to apex');
        await t.tap(find.byKey(const ValueKey('dock-send')));
        String? p1;
        final until = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(until) && p1 != 'apex') {
          await pumpFor(t, const Duration(seconds: 1));
          p1 = (await SharedPreferences.getInstance()).getString(
            'jarvis_visual_mode_v1',
          );
        }
        final heard = JarvisService.instance.lastUserSpeech,
            st = JarvisService.instance.statusMessage;
        await shot(t, 'i-voice-switch-apex');
        final reply = JarvisService.instance.lastJarvisSpeech;
        await pumpFor(t, const Duration(seconds: 3));
        final input2 = find.byKey(const ValueKey('dock-input'));
        if (input2.evaluate().isNotEmpty) {
          await t.enterText(input2, 'aira jellyfish mode');
          await t.tap(find.byKey(const ValueKey('dock-send')));
          final until2 = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(until2) &&
              (await SharedPreferences.getInstance()).getString(
                    'aira_model_v1',
                  ) !=
                  'jellyfish') {
            await pumpFor(t, const Duration(seconds: 1));
          }
        }
        final p = await SharedPreferences.getInstance();
        await shot(t, 'i-voice-switch-aira-jellyfish');
        return (
          p1 == 'apex' &&
              p.getString('jarvis_visual_mode_v1') == 'aira' &&
              p.getString('aira_model_v1') == 'jellyfish',
          'after "switch to apex": $p1 (heard "$heard", status "$st", reply "$reply"); after "aira jellyfish mode": '
              '${p.getString('jarvis_visual_mode_v1')}/${p.getString('aira_model_v1')}',
        );
      });

      await section('I14', () async {
        await openCc(t, 'Visuals');
        await t.tap(find.byKey(const ValueKey('avatar-picker')));
        await pumpFor(t, const Duration(milliseconds: 500));
        await t.tap(find.text('Serpent Guardian').last);
        await pumpFor(t, const Duration(seconds: 3));
        await home(t);
        await pumpFor(t, const Duration(seconds: 4));
        final visible = find.byType(ProceduralAvatarView).evaluate().isNotEmpty;
        final noStrip = find
            .byKey(const ValueKey('mode-selector'))
            .evaluate()
            .isEmpty;
        await shot(t, 'i-serpent-frame-a');
        await pumpFor(t, const Duration(seconds: 1));
        await shot(t, 'i-serpent-frame-b');
        final reload = AvatarPreferences();
        await reload.load();
        return (
          visible && noStrip && reload.selected == AvatarModel.serpent,
          'Settings selected serpent; renderer=$visible noPermanentStrip=$noStrip persisted=${reload.selected.name}',
        );
      });
      await section('I15', () async {
        final settings = AvatarPreferences.instance;
        settings.current.primary = const Color(0xFF33FFBB);
        settings.current.speed = 1.2;
        settings.dockHeight = 60;
        await settings.save();
        await settings.select(AvatarModel.golden);
        await pumpFor(t, const Duration(seconds: 1));
        settings.current.speed = .7;
        await settings.save();
        await settings.select(AvatarModel.serpent);
        await pumpFor(t, const Duration(seconds: 2));
        final reload = AvatarPreferences();
        await reload.load();
        final good =
            reload.current.speed == 1.2 &&
            reload.styleFor(AvatarModel.golden).speed == .7 &&
            reload.dockHeight == 60;
        await shot(t, 'i-serpent-customized');
        return (
          good,
          'Per-model customization and dock persisted in a new store=$good',
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
