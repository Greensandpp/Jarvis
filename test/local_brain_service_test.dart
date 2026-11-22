import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/services/local_brain/local_brain_service.dart';
import 'package:private_agent/services/local_brain/model_engine.dart';

class FakePhoneModel implements PhoneModelEngine {
  int loads = 0, cancels = 0, releases = 0;
  bool wrongTamil = false;
  Completer<void>? pending;
  @override Future<void> load(String path) async { loads++; }
  @override Stream<String> reply(String prompt, String system) async* {
    if (pending != null) await pending!.future;
    if (system.contains('ONLY with English/Latin')) { yield 'Seri, dhinam oru neram padikka pannu.'; }
    else if (system.contains('Tamil letters') && !wrongTamil) { yield 'தினமும் ஒரு குறிப்பிட்ட நேரத்தில் சிறிது சிறிதாகப் படியுங்கள்.'; }
    else { yield 'Study a little each day and take regular breaks.'; }
  }
  @override void cancel() { cancels++; if (pending != null && !pending!.isCompleted) pending!.complete(); }
  @override Future<void> dispose() async { releases++; }
}
Map<String, dynamic> profile({int thermal = 0, int battery = 90, int memory = 8 * 1024 * 1024 * 1024}) => {
  'lowMemory': false, 'availableMemoryBytes': memory, 'thermalStatus': thermal,
  'batteryTemperatureC': 30, 'batteryPercent': battery, 'sdk': 36,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  LocalBrainService service(FakePhoneModel engine, {Map<String,dynamic>? telemetry}) => LocalBrainService(
    observeLifecycle: false, engineFactory: () => engine,
    profile: () async => telemetry ?? profile(),
    modelInfo: () async => {'path': '/private/owner.gguf', 'sha256': 'test-model-sha', 'bytes': 1024 * 1024},
  );
  test('hardware must be verified before a model loads; importing alone is not activation', () async {
    final engine = FakePhoneModel(); final s = service(engine, telemetry: profile(thermal: 3));
    await s.initialize(); expect(s.ready, isFalse);
    await s.benchmark(); expect(s.ready, isFalse); expect(engine.loads, 0);
    expect(s.status, contains('warm')); s.dispose();
    expect(LocalBrainService.unsafeProfile(profile(battery: 10), 1024), contains('Charge'));
    expect(LocalBrainService.unsafeProfile(profile(memory: 100), 1024), contains('RAM'));
    expect(LocalBrainService.unsafeProfile({}, 1024), isNotNull);
  });
  test('real profile and three language tests gate activation and are retained by model hash', () async {
    final engine = FakePhoneModel(); final s = service(engine);
    await s.initialize(); expect(engine.loads, 0); expect(s.ready, isFalse);
    await s.benchmark(); expect(s.ready, isTrue); expect(engine.loads, 1);
    expect(s.report!['samples'], hasLength(3));
    final text = await s.reply('How can I study?', 'en-IN'); expect(text, contains('Study'));
    final restored = service(FakePhoneModel()); await restored.initialize(); expect(restored.ready, isTrue);
    s.dispose(); restored.dispose();
  });
  test('wrong-language output never passes readiness', () async {
    final engine = FakePhoneModel()..wrongTamil = true; final s = service(engine);
    await s.benchmark(); expect(s.ready, isFalse); expect(s.status, contains('ta-IN'));
    expect(engine.releases, 1); s.dispose();
  });
  test('Tanglish has Roman Tamil subtitles and actual Tamil for the speech engine', () async {
    final s = service(FakePhoneModel()); await s.benchmark();
    final answer = await s.replyAnswer('un peru enna', 'ta-Latn');
    expect(answer.display, isNot(contains('தினமும்')));
    expect(answer.speech, contains('தினமும்'));
    expect(answer.locale, 'ta-IN'); s.dispose();
  });
  test('background cancels inference and never returns a stale reply for speech', () async {
    final engine = FakePhoneModel(); final s = service(engine); await s.benchmark();
    engine.pending = Completer<void>();
    final work = s.reply('a pending reply', 'en-IN');
    await Future<void>.delayed(Duration.zero);
    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    await expectLater(work, throwsA(isA<LocalBrainInterrupted>()));
    expect(engine.cancels, greaterThan(0)); s.dispose();
  });
  test('warming during generation revokes readiness and suppresses the answer', () async {
    final engine = FakePhoneModel(); final telemetry = profile();
    final s = service(engine, telemetry: telemetry); await s.benchmark();
    engine.pending = Completer<void>();
    final work = s.reply('a pending reply', 'en-IN');
    await Future<void>.delayed(Duration.zero);
    telemetry['thermalStatus'] = 3;
    engine.pending!.complete();
    await expectLater(work, throwsStateError);
    expect(s.ready, isFalse); expect(s.status, contains('warm'));
    expect(engine.releases, 1); s.dispose();
  });
}
