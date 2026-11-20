import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed platform permission check never starts speech capture',
    () async {
      var starts = 0;
      const mic = MethodChannel('flutter.baseflow.com/permissions/methods');
      const speech = MethodChannel('com.privateagent/speech');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mic, (c) async {
            throw PlatformException(code: 'PERMISSION_ERROR');
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(speech, (c) async {
            starts++;
            return true;
          });
      expect(await VoiceService.instance.initSpeech(), isFalse);
      expect(starts, 0);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mic, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(speech, null);
    },
  );
}
