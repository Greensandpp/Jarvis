import 'dart:async';

import 'package:flutter/widgets.dart';

import 'microphone_consent_gate.dart';

/// Prevents an experimental voice session retaining microphone authorization
/// after the Flutter UI leaves the foreground.
///
/// This watcher does not enable a microphone, start a session, or request OS
/// permissions. The host must implement [shutdownVoice] to mute/release actual
/// Android and LiveKit audio tracks and handle any shutdown errors.
class VoiceAppLifecycleGuard with WidgetsBindingObserver {
  VoiceAppLifecycleGuard({
    required this.consent,
    required this.shutdownVoice,
  });

  final MicrophoneConsentGate consent;
  final Future<void> Function() shutdownVoice;

  bool _attached = false;
  bool _disposed = false;
  Future<void>? _pendingShutdown;
  Object? lastShutdownError;

  Future<void>? get pendingShutdown => _pendingShutdown;

  void attach() {
    if (_attached || _disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  Future<void> shutdown() {
    consent.revoke(); // Revoke before any await.
    return _pendingShutdown ??= _stopOnce();
  }

  Future<void> _stopOnce() async {
    try {
      await shutdownVoice();
    } catch (error) {
      lastShutdownError = error;
      rethrow;
    } finally {
      _pendingShutdown = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // Never auto-enable the microphone or restore consent.
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(shutdown().catchError((Object error, StackTrace stack) {
          // Error captured in lastShutdownError; host must report/escalate.
        }));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    consent.revoke();
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      _attached = false;
    }
    unawaited(shutdown().catchError((Object error, StackTrace stack) {
      // The hosting widget must await pendingShutdown where possible.
    }));
  }
}
