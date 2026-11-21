import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:greensoil_livekit_voice_experiment/offline_runtime.dart';

class FakeModel implements LocalModel {
  final streams = <StreamController<String>>[];
  int cancellations = 0;
  @override Future<void> load(String path) async {}
  @override Stream<String> reply(String text, String language) {
    final stream = StreamController<String>(); streams.add(stream); return stream.stream;
  }
  @override void cancel() { cancellations++; }
  @override Future<void> dispose() async {}
}
Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  test('background invalidates an in-flight reply and prevents speech', () async {
    final model = FakeModel(); final spoken = <String>[]; final updates = <String>[];
    final turns = OfflineTurns(model, stopAudio: () async {},
      speak: (text, _) async { spoken.add(text); }, changed: (_, text) => updates.add(text));
    final run = turns.ask('hello', 'en-IN', voice: true);
    await tick(); model.streams.single.add('old'); await tick();
    await turns.stop(background: true);
    model.streams.single.add('stale'); await model.streams.single.close(); await run;
    expect(spoken, isEmpty); expect(updates.any((s) => s.contains('stale')), isFalse);
    await turns.ask('hidden', 'en-IN', voice: true); expect(model.streams.length, 1);
  });
  test('new turn waits for cancelled inference and never speaks old output', () async {
    final model = FakeModel(); final spoken = <String>[];
    final turns = OfflineTurns(model, stopAudio: () async {},
      speak: (text, _) async { spoken.add(text); }, changed: (_, _) {});
    final old = turns.ask('first', 'en-IN', voice: true); await tick();
    final next = turns.ask('second', 'en-IN', voice: true); await tick();
    expect(model.streams.length, 1);
    model.streams.first.add('old'); await model.streams.first.close(); await old; await tick();
    expect(model.streams.length, 2);
    model.streams.last.add('new'); await model.streams.last.close(); await next;
    expect(spoken, ['new']);
  });
  test('typed-only mode never speaks and has no timer/monthly quota', () async {
    final model = FakeModel(); final spoken = <String>[];
    final turns = OfflineTurns(model, stopAudio: () async {},
      speak: (text, _) async { spoken.add(text); }, changed: (_, _) {});
    for (var i = 0; i < 20; i++) {
      final run = turns.ask('hello $i', 'ta-IN', voice: false); await tick();
      model.streams.last.add('வணக்கம்'); await model.streams.last.close(); await run;
    }
    expect(model.streams.length, 20); expect(spoken, isEmpty);
  });
  test('stop during pending native output barrier cannot start stale inference', () async {
    final model = FakeModel(); final barrier = Completer<void>();
    final turns = OfflineTurns(model, stopAudio: () => barrier.future,
      speak: (_, _) async {}, changed: (_, _) {});
    final run = turns.ask('cancel me', 'en-IN', voice: true);
    final stop = turns.stop(background: true); barrier.complete(); await stop; await run;
    expect(model.streams, isEmpty);
  });
  test('generation failure stays local and does not synthesize partial reply', () async {
    final model = FakeModel(); final statuses = <String>[]; final spoken = <String>[];
    final turns = OfflineTurns(model, stopAudio: () async {},
      speak: (text, _) async { spoken.add(text); }, changed: (s, _) => statuses.add(s));
    final run = turns.ask('hello', 'en-IN', voice: true); await tick();
    model.streams.single.addError(StateError('local runtime unavailable'));
    await model.streams.single.close(); await run;
    expect(statuses.last, contains('no cloud fallback')); expect(spoken, isEmpty);
  });
  test('wrong-script output is withheld and never spoken', () async {
    final model = FakeModel(); final spoken = <String>[]; final statuses = <String>[];
    final turns = OfflineTurns(model, stopAudio: () async {},
      speak: (text, _) async { spoken.add(text); }, changed: (s, _) => statuses.add(s));
    final run = turns.ask('saptiya', 'ta-IN', voice: true); await tick();
    model.streams.single.add('सप्ती।'); await model.streams.single.close(); await run;
    expect(spoken, isEmpty); expect(statuses.last, contains('reply withheld'));
  });
  test('Roman Tamil displays Latin text but speaks the original Tamil once', () async {
    final model = FakeModel(); final spoken = <String>[]; final shown = <String>[];
    final turns = OfflineTurns(model, stopAudio: () async {},
      speak: (text, language) async { spoken.add('$language:$text'); }, changed: (_, text) => shown.add(text));
    final run = turns.ask('saptiya', 'ta-Latn', voice: true); await tick();
    model.streams.single.add('நான் AI, சாப்பிட முடியாது.'); await model.streams.single.close(); await run;
    expect(shown.last, 'naan AI, saappida mudiyaathu.'); expect(spoken, ['ta-IN:நான் AI, சாப்பிட முடியாது.']);
  });
  test('an invented eating claim is withheld even in the correct writing system', () async {
    final model = FakeModel(); final spoken = <String>[]; final statuses = <String>[];
    final turns = OfflineTurns(model, stopAudio: () async {},
      speak: (text, _) async { spoken.add(text); }, changed: (s, _) => statuses.add(s));
    final run = turns.ask('saptiya', 'ta-IN', voice: true); await tick();
    model.streams.single.add('நான் சாப்பிட்டேன்.'); await model.streams.single.close(); await run;
    expect(spoken, isEmpty); expect(statuses.last, contains('reply withheld'));
  });
}
