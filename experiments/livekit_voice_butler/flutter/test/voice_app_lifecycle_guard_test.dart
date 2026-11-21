import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/microphone_consent_gate.dart';
import '../lib/voice_app_lifecycle_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background revokes consent immediately without auto-resume', () async {
    final consent = MicrophoneConsentGate()
      ..updatePermission(true)
      ..approveForSession();
    consent.requestMicrophoneEnable();
    final stopped = Completer<void>();
    var shutdownCount = 0;
    final guard = VoiceAppLifecycleGuard(
      consent: consent,
      shutdownVoice: () {
        shutdownCount++;
        return stopped.future;
      },
    )..attach();

    guard.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(consent.mayConnect, false);
    expect(consent.streaming, false);
    expect(shutdownCount, 1);

    guard.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(shutdownCount, 1);
    guard.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(consent.mayConnect, false);
    stopped.complete();
    await guard.pendingShutdown;
    guard.dispose();
  });

  test('inactive state requests session shutdown', () async {
    final consent = MicrophoneConsentGate()
      ..updatePermission(true)
      ..approveForSession();
    var shutdownCount = 0;
    final guard = VoiceAppLifecycleGuard(
      consent: consent,
      shutdownVoice: () async { shutdownCount++; },
    );
    guard.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await guard.pendingShutdown;
    expect(consent.mayConnect, false);
    expect(shutdownCount, 1);
    guard.dispose();
  });

  test('failed stop never restores mic approval', () async {
    final consent = MicrophoneConsentGate()
      ..updatePermission(true)
      ..approveForSession();
    final guard = VoiceAppLifecycleGuard(
      consent: consent,
      shutdownVoice: () async => throw StateError('driver stop failed'),
    );
    await expectLater(guard.shutdown(), throwsStateError);
    expect(guard.lastShutdownError, isA<StateError>());
    expect(consent.mayConnect, false);
    guard.dispose();
  });

  test('disposed guard cannot restart or reactivate session', () async {
    final consent = MicrophoneConsentGate()
      ..updatePermission(true)
      ..approveForSession();
    var stops = 0;
    final guard = VoiceAppLifecycleGuard(
      consent: consent,
      shutdownVoice: () async { stops++; },
    )..attach();
    guard.dispose();
    await guard.pendingShutdown;
    guard.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(consent.mayConnect, false);
    expect(stops, 1);
  });
}
