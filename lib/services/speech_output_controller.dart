import 'dart:async';

/// One owner for every spoken response. Cancelling invalidates synthesis as well
/// as playback; a late request can never regain ownership after interruption.
class SpeechTicket {
  SpeechTicket(this.id);
  final int id;
  final _cancelled = Completer<void>();
  bool get cancelled => _cancelled.isCompleted;
  Future<void> get cancellation => _cancelled.future;
  void cancel() {
    if (!cancelled) _cancelled.complete();
  }
}

class SpeechOutputController {
  SpeechOutputController({required this.stopDrivers, required this.onSpeaking});
  final Future<void> Function() stopDrivers;
  final void Function(bool) onSpeaking;
  int _id = 0;
  SpeechTicket? _current;
  Future<void> _barrier = Future.value();
  bool externalSession = false;
  int? get activeRequestId => _current?.id;

  Future<void> _stop() {
    final next = _barrier.then((_) => stopDrivers());
    _barrier = next.catchError((Object _) {});
    return next;
  }

  Future<void> speak(
    Future<void> Function(SpeechTicket) play, {
    bool speaking = true,
  }) async {
    if (externalSession) return;
    _current?.cancel();
    final ticket = SpeechTicket(++_id);
    _current = ticket;
    await _stop();
    if (ticket.cancelled || externalSession) return;
    if (speaking) onSpeaking(true);
    try {
      await Future.any([play(ticket), ticket.cancellation]);
    } finally {
      if (identical(_current, ticket)) {
        _current = null;
        if (speaking) onSpeaking(false);
      }
    }
  }

  Future<void> stop() async {
    _current?.cancel();
    _current = null;
    onSpeaking(false);
    await _stop();
  }
}
