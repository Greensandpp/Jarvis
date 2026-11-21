import 'dart:async';

/// One cleanup owner for pending/connected SDK sessions and their hard timeout.
/// Closing revokes ownership synchronously before awaiting network cleanup.
class SessionLease {
  SessionLease({required this.stop, required Duration duration}) {
    _timer = Timer(duration, () => unawaited(close().catchError((Object _) {
      // Cleanup owns its try/finally; a timer has no caller to await errors.
    })));
  }

  final Future<void> Function() stop;
  Timer? _timer;
  Future<void>? _closing;
  bool _closed = false;
  bool get isClosed => _closed;

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _timer?.cancel();
    // Future.sync also captures synchronous cleanup errors.
    return _closing = Future<void>.sync(stop);
  }
}
