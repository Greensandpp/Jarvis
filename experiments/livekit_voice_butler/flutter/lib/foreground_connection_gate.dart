/// Pure connection authorization epoch for a foreground-only mic experiment.
///
/// Any pending asynchronous connect, mic enable or text operation must verify
/// its captured ticket after awaiting permissions and network operations.
/// It cannot by itself terminate a native SDK operation already in flight.
class ForegroundConnectionGate {
  int _epoch = 0;
  bool _foreground = true;

  int? begin() => _foreground ? _epoch : null;
  bool isCurrent(int? ticket) =>
      ticket != null && _foreground && ticket == _epoch;

  void wentToBackground() {
    _foreground = false;
    _epoch += 1;
  }

  void resumed() {
    // Never reauthorize a previously invalidated ticket.
    _foreground = true;
  }

  void invalidate() {
    _epoch += 1;
  }
}
