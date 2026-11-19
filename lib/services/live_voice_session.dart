import 'dart:async';

import 'package:flutter/foundation.dart';

/// Transport boundary for a future Gemini Live connection. Implementations
/// must obtain a short-lived credential from a user-approved backend; never
/// embed API keys or send them through a platform method channel.
abstract interface class LiveVoiceTransport {
  Future<void> connect({required String voice, required String locale});
  Future<void> disconnect();
}

/// Explicit opt-in live voice state machine. No microphone or network
/// connection occurs until [start] receives consent=true.
enum LiveVoiceStatus { idle, connecting, listening, disconnecting, failed }

class LiveVoiceSession extends ChangeNotifier {
  LiveVoiceSession(this._transport);
  final LiveVoiceTransport _transport;
  LiveVoiceStatus _status = LiveVoiceStatus.idle;
  LiveVoiceStatus get status => _status;
  bool get active => _status == LiveVoiceStatus.listening;
  String? _error;
  String? get error => _error;
  int _generation = 0;
  bool _disposed = false;

  void _set(LiveVoiceStatus next, [String? reason]) {
    if (_disposed) return;
    _status = next;
    _error = reason;
    notifyListeners();
  }

  /// No implicit always-on / reconnect. User must explicitly authorize again.
  Future<bool> start({
    required bool consent,
    String voice = 'Aoede',
    String locale = 'ta-IN',
  }) async {
    if (!consent || _status != LiveVoiceStatus.idle) return false;
    final run = ++_generation;
    _set(LiveVoiceStatus.connecting);
    try {
      await _transport.connect(voice: voice, locale: locale);
      if (_disposed || run != _generation) {
        await _transport.disconnect();
        return false;
      }
      _set(LiveVoiceStatus.listening);
      return true;
    } catch (_) {
      // Never expose keys, URLs, credentials, or raw provider errors to UI/logs.
      if (run == _generation) {
        _set(LiveVoiceStatus.failed,
            'Voice connection unavailable. Check provider and permission settings.');
      }
      return false;
    }
  }

  Future<void> stop() async {
    ++_generation;
    if (_status == LiveVoiceStatus.idle) return;
    _set(LiveVoiceStatus.disconnecting);
    try {
      await _transport.disconnect();
    } finally {
      _set(LiveVoiceStatus.idle);
    }
  }

  /// Transport dropped mid-session (server close, focus loss, GoAway). Releases
  /// audio and reports a fixed, non-sensitive reason. No automatic restart.
  Future<void> fail(String reason) async {
    if (_status != LiveVoiceStatus.listening && _status != LiveVoiceStatus.connecting) {
      return;
    }
    ++_generation;
    try {
      await _transport.disconnect();
    } catch (_) {}
    _set(LiveVoiceStatus.failed, reason);
  }

  /// Reset only on an explicit owner action after failure.
  void reset() {
    if (_status == LiveVoiceStatus.failed) _set(LiveVoiceStatus.idle);
  }

  @override
  void dispose() {
    ++_generation;
    _disposed = true;
    // Caller must await stop() before disposing to release microphone/audio.
    super.dispose();
  }
}
