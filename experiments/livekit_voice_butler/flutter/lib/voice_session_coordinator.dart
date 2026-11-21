import 'dart:async';

import 'voice_session_gate.dart';

/// Injectable audio transport interface. A LiveKit/Android integration must
/// implement these operations using actual SDK/player acknowledgements.
abstract interface class VoiceTransport {
  Future<void> cancelAgentResponse();
  Future<void> stopRemoteAudio();
  Future<void> stopLocalTts();
}

/// Async-safe coordination layer. No mic permission, backend credentials,
/// session creation or production services are touched.
class VoiceSessionCoordinator {
  VoiceSessionCoordinator(this.transport);

  final VoiceTransport transport;
  final VoiceSessionGate gate = VoiceSessionGate();

  Future<void> _serialized = Future<void>.value();
  int _epoch = 0;
  bool _closed = false;

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = Completer<T>();
    final prior = _serialized;
    _serialized = () async {
      try {
        await prior;
      } catch (_) {
        // Earlier errors are delivered to their own callers.
      }
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    }();
    return result.future;
  }

  Future<void> connected() => _exclusive(() async {
        if (_closed) return;
        await _stopAll();
        gate.onConnected();
      });

  /// The epoch invalidates queued callbacks immediately on entry.
  /// The gate only starts listening AFTER all stop calls finish.
  Future<int?> interruptAndListen() {
    final requestEpoch = ++_epoch;
    gate.stop(); // Invalidate old voice chunks synchronously.
    return _exclusive(() async {
      if (_closed || !gate.connected || requestEpoch != _epoch) {
        return null;
      }
      try {
        await _stopAll();
      } catch (_) {
        // Fail closed: never claim audio was stopped.
        return null;
      }
      if (_closed || !gate.connected || requestEpoch != _epoch) {
        return null;
      }
      return gate.beginListening(playbackStopped: true);
    });
  }

  bool startThinking(int generation) => !_closed &&
      gate.beginThinking(generation);

  bool claimOutput(int generation, String owner) => !_closed &&
      gate.claimOutput(generation, owner);

  bool canPlay(int generation, String owner) => !_closed &&
      gate.mayEmitAudio(generation, owner);

  bool finishOutput(int generation, String owner) => !_closed &&
      gate.finishOutput(generation, owner);

  Future<void> disconnected() {
    ++_epoch;
    gate.onDisconnected(); // Invalidate callbacks immediately.
    return _exclusive(() async {
      await _stopAll();
    });
  }

  Future<void> close() {
    _closed = true;
    ++_epoch;
    gate.onDisconnected();
    return _exclusive(() async {
      await _stopAll();
    });
  }

  Future<void> _stopAll() async {
    // Collect errors but still attempt every stop; failure blocks listening.
    Object? firstError;
    StackTrace? firstStack;
    for (final stop in <Future<void> Function()>[
      transport.cancelAgentResponse,
      transport.stopRemoteAudio,
      transport.stopLocalTts,
    ]) {
      try {
        await stop();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}
