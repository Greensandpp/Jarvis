import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/services/ai_service.dart';
import 'package:private_agent/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('remote inference is blocked before HTTP even with cloud consent and a key', () async {
    SharedPreferences.setMockInitialValues({
      'ai_provider': 'gemini',
      'ai_base_url': 'https://generativelanguage.googleapis.com/v1beta/openai',
      'ai_api_key': 'test-only-key', 'ai_model': 'gemini-test',
      'privacy_allow_cloud_ai': true,
    });
    await SettingsService.instance.init();
    var requests = 0;
    AiService.instance.debugClient = MockClient((_) async {
      requests++;
      throw StateError('network must never be reached');
    });
    expect(AiService.instance.aiBlockedReason, contains('Free-only'));
    await expectLater(AiService.instance.chat(message: 'hello'),
        throwsA(isA<AiException>().having((e) => e.message, 'message', contains('Free-only'))));
    await expectLater(AiService.instance.chatWithTools([{'role': 'user', 'content': 'hello'}]),
        throwsA(isA<AiException>()));
    expect(requests, 0);
  });
}
