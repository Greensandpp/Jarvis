import 'package:flutter_test/flutter_test.dart';
import '../lib/voice_session_gate.dart';

void main() {
  test('rejects listening while disconnected and before playback stops', () {
    final gate = VoiceSessionGate();
    expect(gate.beginListening(playbackStopped: true), isNull);
    gate.onConnected();
    expect(gate.beginListening(playbackStopped: false), isNull);
    expect(gate.snapshot.phase, VoicePhase.idle);
  });

  test('one speech owner per turn', () {
    final gate = VoiceSessionGate()..onConnected();
    final turn = gate.beginListening(playbackStopped: true)!;
    expect(gate.beginThinking(turn), isTrue);
    expect(gate.claimOutput(turn, 'gemini'), isTrue);
    expect(gate.claimOutput(turn, 'android_tts'), isFalse);
    expect(gate.mayEmitAudio(turn, 'gemini'), isTrue);
    expect(gate.finishOutput(turn, 'gemini'), isTrue);
    expect(gate.finishOutput(turn, 'gemini'), isFalse);
  });

  test('barge-in invalidates stale audio and stale response', () {
    final gate = VoiceSessionGate()..onConnected();
    final old = gate.beginListening(playbackStopped: true)!;
    gate.beginThinking(old);
    gate.claimOutput(old, 'gemini');
    expect(gate.beginListening(playbackStopped: false), isNull);
    final fresh = gate.beginListening(playbackStopped: true)!;
    expect(gate.mayEmitAudio(old, 'gemini'), isFalse);
    expect(gate.claimOutput(old, 'gemini'), isFalse);
    expect(gate.beginThinking(fresh), isTrue);
  });

  test('reconnect invalidates prior generation', () {
    final gate = VoiceSessionGate()..onConnected();
    final previous = gate.beginListening(playbackStopped: true)!;
    gate.beginThinking(previous);
    gate.onDisconnected();
    expect(gate.claimOutput(previous, 'gemini'), isFalse);
    gate.onConnected();
    expect(gate.claimOutput(previous, 'gemini'), isFalse);
    expect(gate.snapshot.phase, VoicePhase.idle);
  });

  test('stop invalidates queued output and permits new turn', () {
    final gate = VoiceSessionGate()..onConnected();
    final previous = gate.beginListening(playbackStopped: true)!;
    gate.beginThinking(previous);
    gate.stop();
    expect(gate.claimOutput(previous, 'gemini'), isFalse);
    expect(gate.beginListening(playbackStopped: true), isNotNull);
  });
}
