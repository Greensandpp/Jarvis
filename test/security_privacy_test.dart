import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:private_agent/widgets/aira/aira_models.dart';
import 'package:private_agent/widgets/aira/aira_view.dart';
import 'package:private_agent/widgets/jarvis_local_visuals.dart';

/// Exact permission inventory of the main manifest (audited 2026-11-19).
/// Any addition must be a deliberate, owner-approved change to this list.
const auditedPermissions = {
  'android.permission.INTERNET',
  'android.permission.ACCESS_NETWORK_STATE',
  'android.permission.WAKE_LOCK',
  'android.permission.SYSTEM_ALERT_WINDOW',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
  'android.permission.QUERY_ALL_PACKAGES',
  'android.permission.RECORD_AUDIO',
  'android.permission.FOREGROUND_SERVICE_MICROPHONE',
  'android.permission.READ_CONTACTS',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.VIBRATE',
  'android.permission.WRITE_SETTINGS',
  'android.permission.MODIFY_AUDIO_SETTINGS',
  'android.permission.SET_ALARM',
  'android.permission.CAMERA',
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.WRITE_EXTERNAL_STORAGE',
  'android.permission.PACKAGE_USAGE_STATS',
};

const forbidden = {
  'android.permission.READ_SMS', 'android.permission.SEND_SMS', 'android.permission.RECEIVE_SMS',
  'android.permission.READ_CALL_LOG', 'android.permission.PROCESS_OUTGOING_CALLS',
  'android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_BACKGROUND_LOCATION',
  'android.permission.READ_PHONE_STATE', 'android.permission.BIND_DEVICE_ADMIN',
  'android.permission.REQUEST_INSTALL_PACKAGES', 'android.permission.MANAGE_EXTERNAL_STORAGE',
  'android.permission.CAPTURE_AUDIO_OUTPUT', 'android.permission.READ_LOGS',
};

Set<String> _perms(String xml) => RegExp(r'<uses-permission[^>]*android:name="([^"]+)"([^>]*)>')
    .allMatches(xml)
    .where((m) => !m.group(2)!.contains('tools:node="remove"'))
    .map((m) => m.group(1)!)
    .toSet();

class _CountingOverrides extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    return super.createHttpClient(context);
  }
}

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('main manifest permission inventory is exactly the audited set', () {
    expect(_perms(manifest), auditedPermissions);
    expect(_perms(manifest).intersection(forbidden), isEmpty);
  });

  test('sensitive components are protected, disabled by default or not exported', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(RegExp(r'AgentAccessibilityService"[\s\S]*?BIND_ACCESSIBILITY_SERVICE').hasMatch(manifest), isTrue);
    expect(RegExp(r'InboxNotificationListenerService"\s*android:enabled="false"').hasMatch(manifest), isTrue);
    expect(RegExp(r'ShizukuProvider"[\s\S]*?android:enabled="false"').hasMatch(manifest), isTrue);
    expect(RegExp(r'FileProvider"[\s\S]*?android:exported="false"').hasMatch(manifest), isTrue);
  });

  test('Live audio bridge records only on explicit start and never to disk', () {
    final k = File('android/app/src/main/kotlin/com/privateagent/private_agent/LiveAudioBridge.kt')
        .readAsStringSync();
    expect(k, contains('checkSelfPermission'));
    expect(k, isNot(contains('FileOutputStream')));
    expect(k, isNot(contains('MediaRecorder.OutputFormat')));
    final main = File('android/app/src/main/kotlin/com/privateagent/private_agent/MainActivity.kt')
        .readAsStringSync();
    expect(RegExp(r'override fun onStop\(\)[\s\S]{0,200}liveAudio\?\.release\(\)').hasMatch(main), isTrue);
  });

  test('no credentials are embedded in source, scripts or Android project', () {
    final key = RegExp(r'AIza[0-9A-Za-z_\-]{35}');
    final privateKey = RegExp(r'-----BEGIN (RSA |EC )?PRIVATE KEY-----');
    final gh = RegExp(r'\bgh[pousr]_[A-Za-z0-9]{36}\b');
    final openai = RegExp(r'\bsk-[A-Za-z0-9]{32,}\b');
    final hits = <String>[];
    for (final dir in ['lib', 'android', 'scripts', 'tool', '.github']) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final f in d.listSync(recursive: true).whereType<File>()) {
        if (f.path.contains('/build/') || f.path.endsWith('.png') || f.path.endsWith('.jar')) continue;
        final String text;
        try {
          text = f.readAsStringSync();
        } catch (_) {
          continue;
        }
        for (final p in [key, privateKey, gh, openai]) {
          if (p.hasMatch(text)) hits.add('${f.path}: ${p.pattern}');
        }
        if (RegExp(r'^\.env').hasMatch(f.uri.pathSegments.last)) hits.add('${f.path}: .env file');
      }
    }
    expect(hits, isEmpty);
  });

  test('offline visual renderers import no network, WebView or platform channel code', () {
    for (final path in ['lib/widgets/aira/aira_models.dart', 'lib/widgets/aira/aira_painter.dart',
        'lib/widgets/aira/aira_view.dart', 'lib/widgets/jarvis_local_visuals.dart']) {
      final src = File(path).readAsStringSync();
      for (final banned in ['package:http', 'dart:io', 'webview', 'MethodChannel', 'Uri.parse']) {
        expect(src.contains(banned), isFalse, reason: '$path contains $banned');
      }
    }
  });

  testWidgets('rendering AIRA, APEX and MIRA creates zero HTTP clients', (tester) async {
    final counter = _CountingOverrides();
    await HttpOverrides.runWithHttpOverrides(() async {
      for (final m in AiraModel.values) {
        await tester.pumpWidget(MaterialApp(home: AiraCoreView(
            model: m, state: AiraVisualState.processing)));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpWidget(const MaterialApp(home: JarvisLocalVisual(apex: true)));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(const MaterialApp(home: JarvisLocalVisual(apex: false)));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(const SizedBox());
    }, counter);
    expect(counter.clients, 0);
  });

  test('minimal-permission staging variants strip every sensitive capability', () async {
    for (final variant in ['visualsafe', 'voicesafe']) {
      final tmp = await Directory.systemTemp.createTemp('jarvis_$variant');
      try {
        Directory('${tmp.path}/android/app/src/main').createSync(recursive: true);
        File('android/app/build.gradle.kts').copySync('${tmp.path}/android/app/build.gradle.kts');
        File('android/app/src/main/AndroidManifest.xml')
            .copySync('${tmp.path}/android/app/src/main/AndroidManifest.xml');
        final r = await Process.run('python3', ['-I', 'scripts/make_safe_mobile_staging.py',
            '--variant', variant, '--root', tmp.path]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        final out = File('${tmp.path}/android/app/src/main/AndroidManifest.xml').readAsStringSync();
        final expected = {
          'android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE',
          if (variant == 'voicesafe') ...{
            'android.permission.RECORD_AUDIO', 'android.permission.MODIFY_AUDIO_SETTINGS'},
        };
        expect(_perms(out), expected, reason: variant);
        expect(out, contains('android:usesCleartextTraffic="false"'));
        expect(out, isNot(contains('AgentAccessibilityService')));
        expect(out, isNot(contains('InboxNotificationListenerService')));
        expect(out, contains('tools:node="remove"'));
        final g = File('${tmp.path}/android/app/build.gradle.kts').readAsStringSync();
        expect(g, contains('applicationIdSuffix = ".$variant"'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    }
  });
}
