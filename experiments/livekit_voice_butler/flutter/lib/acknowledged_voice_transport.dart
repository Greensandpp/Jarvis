import 'voice_session_coordinator.dart';

/// An adapter boundary that requires positive completion acknowledgments.
///
/// The caller must supply real LiveKit agent cancellation, remote playback
/// muting and Android/local TTS cancellation callbacks. No SDK implementation
/// is fabricated here. A boolean 'true' is a positive acknowledgement only
/// when the actual backend/player confirms the operation.
typedef StopWithAcknowledgement = Future<bool> Function();

class AudioStopNotAcknowledged implements Exception {
  const AudioStopNotAcknowledged(this.operation);
  final String operation;

  @override
  String toString() => 'AudioStopNotAcknowledged($operation)';
}

class AcknowledgedVoiceTransport implements VoiceTransport {
  AcknowledgedVoiceTransport({
    required this.cancelAgent,
    required this.stopRemote,
    required this.stopTts,
  });

  final StopWithAcknowledgement cancelAgent;
  final StopWithAcknowledgement stopRemote;
  final StopWithAcknowledgement stopTts;

  Future<void> _requireStop(
    String operation,
    StopWithAcknowledgement operationCallback,
  ) async {
    if (!await operationCallback()) {
      throw AudioStopNotAcknowledged(operation);
    }
  }

  @override
  Future<void> cancelAgentResponse() =>
      _requireStop('agent cancellation', cancelAgent);

  @override
  Future<void> stopRemoteAudio() =>
      _requireStop('remote audio', stopRemote);

  @override
  Future<void> stopLocalTts() =>
      _requireStop('local TTS', stopTts);
}
