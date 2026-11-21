import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Least-privilege contract for the Full Control build (V3). The merged APK
/// is checked again in CI with aapt; this pins the source of the removals.
void main() {
  final full = File('android/app/src/full/AndroidManifest.xml').readAsStringSync();
  final standard = File('android/app/src/standard/AndroidManifest.xml').readAsStringSync();

  Set<String> removed(String xml) =>
      RegExp(r'<uses-permission android:name="([^"]+)" tools:node="remove"').allMatches(xml).map((m) => m.group(1)!).toSet();

  test('Full Control removes privileges it does not need', () {
    expect(removed(full), containsAll(<String>{
      'android.permission.QUERY_ALL_PACKAGES',
      'android.permission.READ_EXTERNAL_STORAGE',
      'android.permission.WRITE_EXTERNAL_STORAGE',
      'android.permission.MANAGE_EXTERNAL_STORAGE',
      'android.permission.REQUEST_INSTALL_PACKAGES',
      'android.permission.REQUEST_DELETE_PACKAGES',
      'android.permission.WRITE_CONTACTS',
      'moe.shizuku.manager.permission.API_V23',
    }));
    expect(full, contains('rikka.shizuku.ShizukuProvider" tools:node="remove"'));
    expect(full, contains('.InboxNotificationListenerService" tools:node="remove"'),
        reason: 'no reading of SMS / e-mail notification text (OTPs)');
    expect(full, contains('android:requestLegacyExternalStorage="false"'));
  });

  test('both builds can still open launcher apps by name', () {
    for (final xml in [full, standard]) {
      expect(xml, contains('android.intent.category.LAUNCHER'));
    }
  });

  test('Full Control keeps its core capability, accessibility stays off by default', () {
    final main = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(full, isNot(contains('AgentAccessibilityService" tools:node="remove"')));
    // The accessibility service only runs after the owner enables it in Android settings.
    expect(RegExp(r'AgentAccessibilityService"[\s\S]*?BIND_ACCESSIBILITY_SERVICE').hasMatch(main), isTrue);
  });
}
