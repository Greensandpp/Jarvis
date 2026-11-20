// Native recognizer and permission channel doubles; no physical audio proof.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:private_agent/services/voice_service.dart';

void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
 var granted=true,starts=0;
 Future<void> status(String value) async {
   final done=Completer<void>();
   messenger.handlePlatformMessage('com.privateagent/speech',const StandardMethodCodec().encodeMethodCall(MethodCall('onSpeechStatus',value)),(_)=>done.complete());
   await done.future;
 }
 setUp(() async {
  SharedPreferences.setMockInitialValues({});await SettingsService.instance.init();
  granted=true;starts=0;
  messenger.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'),(call)async=>{Permission.microphone.value:granted?1:0});
  messenger.setMockMethodCallHandler(const MethodChannel('com.privateagent/speech'),(call)async {
    if(call.method=='startListening')starts++;
    return true;
  });
 });
 tearDown(()async {await VoiceService.instance.stopListening();});
 test('request acknowledgement is not capture; real ready/error/end events control microphone',()async {
   final v=VoiceService.instance;
   expect(await v.startListening(manual:true,onResult:(a,b,c){}),isTrue);
   expect(starts,1);expect(v.isListening,isFalse);
   await status('listening');expect(v.isListening,isTrue);
   await status('error:3');expect(v.isListening,isFalse);
   await status('listening');await status('endOfSpeech');expect(v.isListening,isFalse);
 });
 test('revoking permission after an earlier successful init blocks the next capture',()async {
   final v=VoiceService.instance;expect(await v.initSpeech(),isTrue);
   granted=false;
   expect(await v.startListening(manual:true,onResult:(a,b,c){}),isFalse);
   expect(starts,0);expect(v.isListening,isFalse);
 });
}
