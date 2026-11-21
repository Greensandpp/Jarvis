import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/jarvis_v3/chat_interface_settings.dart';
import 'package:private_agent/jarvis_v3/assistant_activity.dart';
import 'package:private_agent/jarvis_v3/jarvis_v3_home.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:private_agent/services/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'four renderer presets persist; invalid saved and requested values are bounded',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = ChatInterfaceSettings.instance;
      for (final q in ChatInterfaceSettings.qualities) {
        await s.update(quality: q);
        s.quality = 'invalid';
        await s.load();
        expect(s.quality, q);
      }
      await s.update(quality: 'untrusted');
      expect(s.quality, 'battery');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('v3_render_quality', 'unknown');
      await s.load();
      expect(s.quality, 'balanced');
    },
  );
  test('AI failure classes remain distinct and cannot look connected', () {
    for (final entry in {
      'auth': 'AUTH REQUIRED',
      'noKey': 'CONFIGURATION MISSING',
      'dns': 'OFFLINE',
      'connect': 'OFFLINE',
      'timeout': 'OFFLINE',
      'modelNotFound': 'ERROR · MODELNOTFOUND',
    }.entries) {
      expect(
        headerStatus(
          activity: AssistantActivity.idle,
          aiVerified: true,
          aiErrorKind: entry.key,
          standbyMic: false,
        ).label,
        entry.value,
      );
    }
  });
  test(
    'HTTP 200 malformed content never verifies model or connection',
    () async {
      SharedPreferences.setMockInitialValues({
        'ai_provider': 'gemini',
        'ai_api_key': 'k-test',
        'ai_model': 'gemini-2.5-flash',
        'privacy_allow_cloud_ai': true,
      });
      final settings = SettingsService.instance;
      await settings.init();
      AiService.instance.debugClient = MockClient(
        (r) async => http.Response(jsonEncode({'choices': []}), 200),
      );
      await expectLater(
        AiService.instance.chat(message: 'hi'),
        throwsA(isA<AiException>()),
      );
      expect(settings.aiVerified, isFalse);
      expect(settings.aiLastErrorKind, 'parse');
    },
  );
}
