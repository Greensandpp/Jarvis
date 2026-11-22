import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/local_brain/local_answer.dart';
void main() {
  test('common Tanglish is normalized without supplying a canned answer', () {
    expect(LocalAnswer.prompt('un peru enna? Reply in Tanglish.', 'ta-Latn'), contains('What is your name?'));
    expect(LocalAnswer.prompt('What are black holes?', 'en-IN'), contains('What are black holes?'));
  });
  test('wrong script is withheld and Tamil speech is retained', () {
    final a = LocalAnswer.fromRaw('வணக்கம்!', 'ta-Latn');
    expect(a.display.toLowerCase(), contains('vanak')); expect(a.speech, 'வணக்கம்!');
    expect(a.locale, 'ta-IN');
    expect(() => LocalAnswer.fromRaw('नमस्ते', 'ta-Latn'), throwsStateError);
    expect(() => LocalAnswer.fromRaw('Hello', 'ta-Latn'), throwsStateError);
  });
  test('local handoff keeps recent context within its small model budget', () {
    final history = '${List.filled(900, 'old').join()}recent question';
    expect(LocalAnswer.context(history), hasLength(600));
    expect(LocalAnswer.context(history), endsWith('recent question'));
    expect(LocalAnswer.context('short history'), 'short history');
  });
}
