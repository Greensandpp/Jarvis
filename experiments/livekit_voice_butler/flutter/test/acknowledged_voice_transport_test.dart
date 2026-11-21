import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import '../lib/acknowledged_voice_transport.dart';
import '../lib/voice_session_coordinator.dart';
import '../lib/voice_session_gate.dart';

void main() {
  test('positive acknowledgements permit a new listening turn', () async {
    final coordinator = VoiceSessionCoordinator(
      AcknowledgedVoiceTransport(
        cancelAgent: () async => true,
        stopRemote: () async => true,
        stopTts: () async => true,
      ),
    );
    await coordinator.connected();
    final id = await coordinator.interruptAndListen();
    expect(id, isNotNull);
    expect(coordinator.gate.snapshot.phase, VoicePhase.listening);
  });

  test('no remote audio acknowledgement blocks listening', () async {
    final coordinator = VoiceSessionCoordinator(
      AcknowledgedVoiceTransport(
        cancelAgent: () async => true,
        stopRemote: () async => false,
        stopTts: () async => true,
      ),
    );
    await expectLater(coordinator.connected(), throwsA(
      isA<AudioStopNotAcknowledged>(),
    ));
    expect(coordinator.gate.connected, false);
  });

  test('missing agent cancellation acknowledgement blocks barge-in', () async {
    var grantCancel = true;
    final coordinator = VoiceSessionCoordinator(
      AcknowledgedVoiceTransport(
        cancelAgent: () async => grantCancel,
        stopRemote: () async => true,
        stopTts: () async => true,
      ),
    );
    await coordinator.connected();
    grantCancel = false;
    expect(await coordinator.interruptAndListen(), isNull);
    expect(coordinator.gate.snapshot.phase, VoicePhase.idle);
  });

  test('local TTS failure still attempts every stop callback', () async {
    var count = 0;
    final coordinator = VoiceSessionCoordinator(
      AcknowledgedVoiceTransport(
        cancelAgent: () async { count++; return true; },
        stopRemote: () async { count++; return true; },
        stopTts: () async { count++; return false; },
      ),
    );
    await expectLater(
      coordinator.connected(), throwsA(isA<AudioStopNotAcknowledged>()),
    );
    expect(count, 3);
  });
  test('unresponsive remote audio stop times out and fails closed', () async {
    final neverCompletes = Completer<bool>();
    final coordinator = VoiceSessionCoordinator(
      AcknowledgedVoiceTransport(
        cancelAgent: () async => true,
        stopRemote: () => neverCompletes.future,
        stopTts: () async => true,
        stopTimeout: const Duration(milliseconds: 10),
      ),
    );
    await expectLater(
      coordinator.connected(),
      throwsA(isA<AudioStopNotAcknowledged>()),
    );
    expect(coordinator.gate.connected, false);
  });

  test('late positive response after timeout cannot start listening', () async {
    final stopped = Completer<bool>();
    final coordinator = VoiceSessionCoordinator(
      AcknowledgedVoiceTransport(
        cancelAgent: () async => true,
        stopRemote: () => stopped.future,
        stopTts: () async => true,
        stopTimeout: const Duration(milliseconds: 10),
      ),
    );
    await expectLater(
      coordinator.connected(),
      throwsA(isA<AudioStopNotAcknowledged>()),
    );
    stopped.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.gate.connected, false);
    expect(coordinator.gate.snapshot.phase, VoicePhase.idle);
  });

}
