import 'package:flutter_test/flutter_test.dart';
import 'package:greensoil_livekit_voice_experiment/language_contract.dart';
void main() {
  test('wrong Indian scripts cannot pass Tamil speech admission', () {
    expect(OfflineLanguage.acceptable('ನಾನ್ ಪರಿಕ್ಷಿದು!', 'ta-IN'), isFalse);
    expect(OfflineLanguage.acceptable('सप्ती।', 'ta-IN'), isFalse);
    expect(OfflineLanguage.acceptable('வணக்கம்! எப்படி இருக்கீங்க?', 'ta-IN'), isTrue);
    expect(OfflineLanguage.acceptable('என் பெயர் GreenSoil JARVIS.', 'ta-IN'), isTrue);
    expect(OfflineLanguage.acceptable('4', 'ta-IN'), isTrue);
    expect(OfflineLanguage.acceptable('Hello!', 'ta-IN'), isFalse);
  });
  test('English and Tanglish require Latin while Tamil remains explicit', () {
    expect(OfflineLanguage.acceptable('En peru JARVIS.', 'ta-Latn'), isTrue);
    expect(OfflineLanguage.acceptable('வணக்கம்', 'ta-Latn'), isFalse);
    expect(OfflineLanguage.acceptable('हेलो', 'en-IN'), isFalse);
    expect(OfflineLanguage.speechLocale('ta-Latn'), 'ta-IN');
  });
  test('food capability accepts honest paraphrases and rejects unrelated/invented answers', () {
    expect(OfflineLanguage.cannotEat('No, I cannot eat food.', 'en-IN'), isTrue);
    expect(OfflineLanguage.cannotEat("I don't eat food.", 'en-IN'), isTrue);
    expect(OfflineLanguage.cannotEat('I ate food.', 'en-IN'), isFalse);
    expect(OfflineLanguage.cannotEat('I do not know.', 'en-IN'), isFalse);
    expect(OfflineLanguage.cannotEat('எனக்குச் சாப்பிட முடியாது.', 'ta-IN'), isTrue);
    expect(OfflineLanguage.cannotEat('எனக்குச் சாப்பிட வேண்டியதில்லை.', 'ta-IN'), isTrue);
    expect(OfflineLanguage.cannotEat('நான் சாப்பிட்டேன்.', 'ta-IN'), isFalse);
    expect(OfflineLanguage.cannotEat('என் பெயர் JARVIS.', 'ta-IN'), isFalse);
  });
}
