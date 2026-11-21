import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import '../lib/voice_session_coordinator.dart';
import '../lib/voice_session_gate.dart';

class FakeTransport implements VoiceTransport {
  int agentCancels = 0;
  int remoteStops = 0;
  int localStops = 0;
  bool failLocal = false;
  Completer<void>? remoteStopBarrier;

  @override
  Future<void> cancelAgentResponse() async {
    agentCancels++;
  }

  @override
  Future<void> stopRemoteAudio() async {
    remoteStops++;
    await remoteStopBarrier?.future;
  }

  @override
  Future<void> stopLocalTts() async {
    localStops++;
    if (failLocal) throw StateError('stop failed');
  }
}

void main() {
  test('interrupt awaits real stop acknowledgements', () async {
    final t = FakeTransport();
    final c = VoiceSessionCoordinator(t);
    await c.connected();
    t.remoteStopBarrier = Completer<void>();
    final pending = c.interruptAndListen();
    await Future<void>.delayed(Duration.zero);
    expect(c.gate.snapshot.phase, VoicePhase.idle);
    t.remoteStopBarrier!.complete();
    final turn = await pending;
    expect(turn, isNotNull);
    expect(c.gate.snapshot.phase, VoicePhase.listening);
    expect(t.localStops, 2); // connect + interrupt
  });

  test('stale chunks rejected on interrupt while stops pending', () async {
    final t = FakeTransport();
    final c = VoiceSessionCoordinator(t);
    await c.connected();
    final old = await c.interruptAndListen();
    expect(c.startThinking(old!), isTrue);
    expect(c.claimOutput(old, 'gemini'), isTrue);
    t.remoteStopBarrier = Completer<void>();
    final pending = c.interruptAndListen();
    expect(c.canPlay(old, 'gemini'), isFalse);
    t.remoteStopBarrier!.complete();
    final current = await pending;
    expect(current, isNotNull);
    expect(c.claimOutput(old, 'gemini'), isFalse);
  });

  test('stop failure fails closed, no new listening', () async {
    final t = FakeTransport();
    final c = VoiceSessionCoordinator(t);
    await c.connected();
    t.failLocal = true;
    final turn = await c.interruptAndListen();
    expect(turn, isNull);
    expect(c.gate.snapshot.phase, VoicePhase.idle);
    expect(t.agentCancels, 2);
  });

  test('later interruption supersedes earlier queued interruption', () async {
    final t = FakeTransport();
    final c = VoiceSessionCoordinator(t);
    await c.connected();
    final first = c.interruptAndListen();
    final second = c.interruptAndListen();
    expect(await first, isNull);
    expect(await second, isNotNull);
  });

  test('disconnect invalidates output before awaiting shutdown', () async {
    final t = FakeTransport();
    final c = VoiceSessionCoordinator(t);
    await c.connected();
    final id = (await c.interruptAndListen())!;
    c.startThinking(id);
    c.claimOutput(id, 'gemini');
    t.remoteStopBarrier = Completer<void>();
    final pending = c.disconnected();
    expect(c.canPlay(id, 'gemini'), isFalse);
    t.remoteStopBarrier!.complete();
    await pending;
    expect(c.gate.connected, isFalse);
  });

  test('close prevents future new listening', () async {
    final t = FakeTransport();
    final c = VoiceSessionCoordinator(t);
    await c.connected();
    await c.close();
    expect(await c.interruptAndListen(), isNull);
  });
}
