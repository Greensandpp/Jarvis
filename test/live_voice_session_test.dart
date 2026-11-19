import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/live_voice_session.dart';

class FakeTransport implements LiveVoiceTransport {
  int connects = 0;
  int disconnects = 0;
  String? locale;
  String? voice;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> connect({required String voice, required String locale}) async {
    connects++;
    this.voice = voice;
    this.locale = locale;
    if (pending != null) await pending!.future;
    if (fail) throw StateError('sensitive provider error: secret');
  }

  @override
  Future<void> disconnect() async { disconnects++; }
}

void main() {
  test('no opt-in means no connection, no microphone start', () async {
    final fake = FakeTransport();
    final session = LiveVoiceSession(fake);
    expect(await session.start(consent: false), false);
    expect(fake.connects, 0);
    expect(session.status, LiveVoiceStatus.idle);
    session.dispose();
  });

  test('explicit opt-in connects with Tamil default; stop releases', () async {
    final fake = FakeTransport();
    final session = LiveVoiceSession(fake);
    expect(await session.start(consent: true), true);
    expect(fake.voice, 'Aoede');
    expect(fake.locale, 'ta-IN');
    expect(session.active, true);
    await session.stop();
    expect(fake.disconnects, 1);
    expect(session.active, false);
    session.dispose();
  });

  test('failed transport never leaks raw credential error', () async {
    final fake = FakeTransport()..fail = true;
    final session = LiveVoiceSession(fake);
    expect(await session.start(consent: true), false);
    expect(session.status, LiveVoiceStatus.failed);
    expect(session.error, isNot(contains('secret')));
    session.reset();
    expect(session.status, LiveVoiceStatus.idle);
    session.dispose();
  });

  test('stop during connection prevents late activation', () async {
    final fake = FakeTransport()..pending = Completer<void>();
    final session = LiveVoiceSession(fake);
    final startFuture = session.start(consent: true);
    await Future<void>.delayed(Duration.zero);
    await session.stop();
    fake.pending!.complete();
    expect(await startFuture, false);
    expect(session.active, false);
    session.dispose();
  });
}
