import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/brain/memory_backup.dart';
import 'package:private_agent/services/conversational_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('backup round-trips; wrong passphrase and tampering are rejected', () {
    final b = encryptBackup('{"x":"நன்றி"}', 'secret-pass', iterations: 1000);
    expect(b, isNot(contains('நன்றி')));
    expect(decryptBackup(b, 'secret-pass'), '{"x":"நன்றி"}');
    expect(() => decryptBackup(b, 'wrong-pass'), throwsA(isA<BackupException>()));
    final tampered = b.replaceFirst(RegExp(r'"data":"(.)'), '"data":"A');
    expect(() => decryptBackup(tampered == b ? b.replaceFirst('"data":"A', '"data":"B') : tampered, 'secret-pass'),
        throwsA(isA<BackupException>()));
    expect(() => encryptBackup('x', '123'), throwsA(isA<BackupException>()));
  });

  test('memory: explicit remember, correction with history + undo, relevance, encrypted export/import', () async {
    final m = ConversationalMemoryService.instance;
    await m.wipeAll();
    await m.recordTurn('Remember that my trading capital is 50000 rupees', 'Noted.');
    await m.recordTurn('remember my daughter likes violin', 'Noted.');
    expect(m.facts.map((f) => f.fact), contains('my trading capital is 50000 rupees'));
    final cap = m.facts.firstWhere((f) => f.fact.contains('capital'));
    final c = await m.correctFact(cap.id, 'my trading capital is 75000 rupees');
    expect(c!.history, ['my trading capital is 50000 rupees']);
    expect(m.relevantFacts('what is my trading capital?').first.fact, contains('75000'));
    expect(m.relevantFacts('weather tomorrow'), isEmpty);

    final backup = await m.exportEncrypted('owner-pass', iterations: 1000);
    await m.clearAllFacts();
    expect(m.facts, isEmpty);
    await expectLater(m.importEncrypted(backup, 'bad-pass'), throwsA(isA<BackupException>()));
    expect(m.facts, isEmpty);
    expect(await m.importEncrypted(backup, 'owner-pass'), 2);
    expect(await m.importEncrypted(backup, 'owner-pass'), 0, reason: 'no duplicates');
    final restored = m.facts.firstWhere((f) => f.fact.contains('capital'));
    expect(restored.history, hasLength(1));
    expect((await m.undoCorrection(restored.id))!.fact, contains('50000'));
  });
}
