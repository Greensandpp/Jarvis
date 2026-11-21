import 'package:flutter_test/flutter_test.dart';
import '../lib/microphone_consent_gate.dart';

void main() {
  test('mic denied until BOTH permission and session consent', () {
    final p = MicrophoneConsentGate();
    expect(p.mayConnect, false);
    expect(p.requestMicrophoneEnable(), false);
    p.updatePermission(true);
    expect(p.mayConnect, false);
    p.approveForSession();
    expect(p.mayConnect, true);
    expect(p.requestMicrophoneEnable(), true);
    expect(p.streaming, true);
  });

  test('revoke immediately invalidates streaming authorization', () {
    final p = MicrophoneConsentGate();
    p.updatePermission(true);
    p.approveForSession();
    p.requestMicrophoneEnable();
    p.revoke();
    expect(p.streaming, false);
    expect(p.requestMicrophoneEnable(), false);
  });

  test('permission loss prevents mic enable even with consent', () {
    final p = MicrophoneConsentGate();
    p.updatePermission(true);
    p.approveForSession();
    p.updatePermission(false);
    expect(p.requestMicrophoneEnable(), false);
    expect(p.streaming, false);
  });

  test('mic off does not silently revoke connection consent', () {
    final p = MicrophoneConsentGate();
    p.updatePermission(true);
    p.approveForSession();
    p.requestMicrophoneEnable();
    p.microphoneDisabled();
    expect(p.streaming, false);
    expect(p.mayConnect, true);
  });
}
