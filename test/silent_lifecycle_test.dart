// A successful native sensor response previously started unsolicited speech.
// These are platform-channel regressions, not physical sound verification.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/air_gesture_service.dart';
import 'package:private_agent/services/charging_telemetry_service.dart';

void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 final calls=<String>[];
 setUp(() {
  calls.clear();
  final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('com.privateagent/accessibility'),(call)async {
    if(call.method=='getChargingTelemetry')return {'isCharging':true,'batteryLevel':80};
    return true;
  });
  messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),(call)async {calls.add(call.method);return 1;});
 });
 test('home lifecycle starts and stops real sensor path without any speech request',()async {
  final gestures=AirGestureService.instance;
  expect(await gestures.start(announce:false),isTrue);
  await Future<void>.delayed(Duration.zero);
  expect(calls,isEmpty);
  await gestures.stop(announce:false);
  await Future<void>.delayed(Duration.zero);
  expect(calls,isEmpty);
 });
 test('reading charging diagnostics updates telemetry without a second spoken response',()async {
  final charging=ChargingTelemetryService.instance;
  await charging.queryTelemetry();
  await charging.queryTelemetry();
  await Future<void>.delayed(Duration.zero);
  expect(charging.batteryLevel,80);expect(calls,isEmpty);expect(charging.showCinematicHud.value,isFalse);
 });
}
