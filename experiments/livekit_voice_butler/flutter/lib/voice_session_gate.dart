/// Standalone Flutter/Dart experiment: no LiveKit or Android dependencies.
/// The adapter MUST stop the real audio player before invoking beginListening.
/// Not wired to the production GreenSoil JARVIS voice pipeline.
enum VoicePhase { idle, listening, thinking, speaking }

class VoiceSessionSnapshot {
  final VoicePhase phase;
  final int generation;
  final String? speakerOwner;

  const VoiceSessionSnapshot(this.phase, this.generation, this.speakerOwner);
}

class VoiceSessionGate {
  VoicePhase _phase = VoicePhase.idle;
  int _generation = 0;
  String? _speakerOwner;
  bool _connected = false;

  VoiceSessionSnapshot get snapshot =>
      VoiceSessionSnapshot(_phase, _generation, _speakerOwner);

  bool get connected => _connected;

  /// Connection transitions invalidate callbacks from the prior session.
  void onConnected() {
    _generation++;
    _connected = true;
    _phase = VoicePhase.idle;
    _speakerOwner = null;
  }

  /// Reconnect/disconnect MUST also terminate actual playback in the adapter.
  void onDisconnected() {
    _generation++;
    _connected = false;
    _phase = VoicePhase.idle;
    _speakerOwner = null;
  }

  /// Begin only after cancel/stop acknowledgment from all audio players.
  int? beginListening({required bool playbackStopped}) {
    if (!_connected || !playbackStopped) return null;
    _generation++;
    _speakerOwner = null;
    _phase = VoicePhase.listening;
    return _generation;
  }

  bool beginThinking(int generation) {
    if (!_connected ||
        generation != _generation ||
        _phase != VoicePhase.listening) return false;
    _phase = VoicePhase.thinking;
    return true;
  }

  bool claimOutput(int generation, String owner) {
    if (!_connected || owner.trim().isEmpty || generation != _generation ||
        (_phase != VoicePhase.thinking && _phase != VoicePhase.speaking)) {
      return false;
    }
    if (_speakerOwner != null && _speakerOwner != owner) return false;
    _speakerOwner = owner;
    _phase = VoicePhase.speaking;
    return true;
  }

  bool mayEmitAudio(int generation, String owner) =>
      _connected && generation == _generation &&
      _phase == VoicePhase.speaking && _speakerOwner == owner;

  bool finishOutput(int generation, String owner) {
    if (!mayEmitAudio(generation, owner)) return false;
    _speakerOwner = null;
    _phase = VoicePhase.idle;
    return true;
  }

  void stop() {
    _generation++;
    _speakerOwner = null;
    _phase = VoicePhase.idle;
  }
}
