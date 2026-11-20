import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/jarvis_service.dart';

/// What the assistant is genuinely doing right now. Production animation is
/// driven only by this value, which is derived from real service events.
/// Manual previews live in Developer Diagnostics and never feed this engine.
enum AssistantActivity {
  idle('READY'),
  listening('LISTENING'),
  thinking('THINKING'),
  processing('PROCESSING'),
  executing('EXECUTING'),
  speaking('SPEAKING'),
  error('ERROR'),
  disconnected('AI NOT CONNECTED');

  const AssistantActivity(this.label);
  final String label;

  /// States during which the active conversation must stay on screen.
  bool get isActiveConversation =>
      this == listening || this == thinking || this == processing ||
      this == executing || this == speaking;
}

/// One snapshot of the real signals the engine reads.
@immutable
class ActivitySignals {
  const ActivitySignals({
    required this.phase,
    this.micCapturing = false,
    this.executorRunning = false,
    this.chatBusy = false,
    this.aiConfigured = true,
    this.errorStatus = false,
  });

  final JarvisPhase phase;

  /// The speech recogniser is actually capturing (not merely enabled).
  final bool micCapturing;

  /// An authorised device action is running in the task executor.
  final bool executorRunning;

  /// A chat reply is in flight outside the JARVIS phase machine.
  final bool chatBusy;

  /// An AI provider key/endpoint exists. Not the same as "verified online".
  final bool aiConfigured;

  /// The service reported a failure for the most recent command.
  final bool errorStatus;
}

/// Pure mapping from real signals to the visual state, kept separate so it can
/// be unit-tested without timers or platform channels.
AssistantActivity deriveActivity(ActivitySignals s) {
  switch (s.phase) {
    case JarvisPhase.listening:
      // Never show LISTENING unless the recogniser is really capturing.
      return s.micCapturing ? AssistantActivity.listening : AssistantActivity.idle;
    case JarvisPhase.thinking:
      return AssistantActivity.thinking;
    case JarvisPhase.executing:
      return s.executorRunning ? AssistantActivity.executing : AssistantActivity.processing;
    case JarvisPhase.speaking:
      return s.errorStatus ? AssistantActivity.error : AssistantActivity.speaking;
    case JarvisPhase.idle:
      if (s.executorRunning) return AssistantActivity.executing;
      if (s.chatBusy) return AssistantActivity.processing;
      if (s.errorStatus) return AssistantActivity.error;
      if (!s.aiConfigured) return AssistantActivity.disconnected;
      return AssistantActivity.idle;
  }
}

/// Event-driven activity engine. Every update carries a generation number, so
/// a delayed callback from an older request can never overwrite a newer state.
class AssistantActivityEngine extends ValueNotifier<AssistantActivity> {
  AssistantActivityEngine({
    required Listenable source,
    required ActivitySignals Function() read,
    this.errorHold = const Duration(seconds: 6),
  })  : _source = source,
        _read = read,
        super(AssistantActivity.idle) {
    _source.addListener(_sync);
    _sync();
  }

  final Listenable _source;
  final ActivitySignals Function() _read;
  final Duration errorHold;

  int _generation = 0;
  int get generation => _generation;
  Timer? _errorTimer;
  bool _errorAcknowledged = false;
  bool _disposed = false;

  /// The trader dismissed the error card; fall back to the real state.
  void acknowledgeError() {
    _errorAcknowledged = true;
    _errorTimer?.cancel();
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final signals = _read();
    var next = deriveActivity(signals);
    if (!signals.errorStatus) _errorAcknowledged = false;
    if (next == AssistantActivity.error && _errorAcknowledged) {
      next = signals.aiConfigured ? AssistantActivity.idle : AssistantActivity.disconnected;
    }
    if (next == value) return;
    final gen = ++_generation;
    _errorTimer?.cancel();
    value = next;
    if (next == AssistantActivity.error) {
      // ERROR is shown long enough to read, then the real state takes over
      // unless something newer has already replaced it.
      _errorTimer = Timer(errorHold, () {
        if (_disposed || gen != _generation) return;
        _errorAcknowledged = true;
        _sync();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _errorTimer?.cancel();
    _source.removeListener(_sync);
    super.dispose();
  }
}
