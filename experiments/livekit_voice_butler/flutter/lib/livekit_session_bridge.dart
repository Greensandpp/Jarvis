import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;

import 'voice_session_coordinator.dart';
import 'microphone_consent_gate.dart';

/// Narrow SDK wrapper for a single LiveKit client session.
///
/// This is an isolated experiment. The LiveKit Flutter client Session API
/// supports start/end/sendText but does not expose a documented client-side
/// interrupt() method. Therefore, this bridge deliberately does NOT claim to
/// implement barge-in or a remote audio stop acknowledgment.
class LiveKitSessionBridge {
  LiveKitSessionBridge({
    required Uri tokenEndpoint,
    required VoiceTransport audioTransport,
  })  : _session = lk.Session.fromConfigurableTokenSource(
          lk.EndpointTokenSource(url: tokenEndpoint),
          options: lk.SessionOptions(preConnectAudio: false),
        ),
        coordinator = VoiceSessionCoordinator(audioTransport);

  final lk.Session _session;
  final VoiceSessionCoordinator coordinator;
  final MicrophoneConsentGate microphoneConsent = MicrophoneConsentGate();
  bool _closed = false;
  Future<void>? _connecting;

  lk.ConnectionState get connectionState => _session.connectionState;
  bool get isConnected =>
      !_closed && _session.connectionState == lk.ConnectionState.connected;

  /// Never embed LiveKit API key/secret in Flutter assets or APK.
  /// tokenEndpoint must be an authenticated server returning short-lived tokens.
  /// LiveKit Session.start may publish microphone after connecting, so the
  /// caller MUST request Android permission and obtain user consent first.
  Future<void> connect({required bool microphonePermissionGranted,
      required bool userApprovedMicrophone}) {
    if (_closed) throw StateError('Session bridge is disposed.');
    microphoneConsent.updatePermission(microphonePermissionGranted);
    if (userApprovedMicrophone) microphoneConsent.approveForSession();
    if (!microphoneConsent.mayConnect) {
      throw StateError('Microphone permission and explicit consent required.');
    }
    if (_connecting != null) return _connecting!;
    if (isConnected) return Future<void>.value();
    final pending = _connectOnce();
    _connecting = pending;
    return pending.whenComplete(() => _connecting = null);
  }

  Future<void> _connectOnce() async {
    try {
      await _session.start();
      if (_closed || !isConnected) {
        throw StateError('LiveKit session did not reach connected state.');
      }
      await coordinator.connected();
      // This observes authorization, not a guarantee that native capture
      // started; Session.start owns the underlying audio publication.
      microphoneConsent.requestMicrophoneEnable();
    } catch (_) {
      microphoneConsent.revoke();
      try {
        await coordinator.disconnected();
      } finally {
        await _session.end();
      }
      rethrow;
    }
  }

  /// Uses the documented LiveKit local participant control. A caller must
  /// coordinate this with Android foreground lifecycle/permission callbacks.
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (!isConnected) throw StateError('LiveKit is not connected.');
    if (enabled && !microphoneConsent.mayConnect) {
      throw StateError('Microphone consent or permission missing.');
    }
    await _session.room.localParticipant?.setMicrophoneEnabled(enabled);
    if (enabled) {
      microphoneConsent.requestMicrophoneEnable();
    } else {
      microphoneConsent.microphoneDisabled();
    }
  }

  /// Must be invoked when Android permission is revoked or user opts out.
  /// This method cannot substitute for native background lifecycle handling.
  Future<void> revokeMicrophone() async {
    microphoneConsent.revoke();
    if (isConnected) {
      await _session.room.localParticipant?.setMicrophoneEnabled(false);
    }
  }

  Future<void> sendText(String text) async {
    if (!isConnected) throw StateError('LiveKit is not connected.');
    final message = text.trim();
    if (message.isEmpty) return;
    await _session.sendText(message);
  }

  /// No simulated success: a real transport must acknowledge cancellation
  /// and stop of both remote audio and local TTS before listening resumes.
  Future<int?> interruptAndListen() {
    if (!isConnected) return Future<int?>.value(null);
    return coordinator.interruptAndListen();
  }

  Future<void> disconnect() async {
    if (_closed) return;
    microphoneConsent.revoke();
    try {
      await coordinator.disconnected();
    } finally {
      await _session.end();
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    microphoneConsent.revoke();
    try {
      await coordinator.close();
    } finally {
      try {
        await _session.end();
      } finally {
        await _session.dispose();
      }
    }
  }
}
