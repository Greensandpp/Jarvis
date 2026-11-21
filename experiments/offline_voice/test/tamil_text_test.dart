import 'package:flutter_test/flutter_test.dart';
import 'package:greensoil_livekit_voice_experiment/tamil_text.dart';
void main() {
  test('only complete common utterances are normalized; replies are not supplied', () {
    expect(normalizeCommonTanglish('  un peru enna? '), 'What is your name?');
    expect(normalizeCommonTanglish('Saptiya!'), 'As an AI assistant, can you eat food?');
    expect(normalizeCommonTanglish('nee manushana illa AI ah'), 'Are you a human or an AI?');
    expect(normalizeCommonTanglish('water ku tamil la enna'), 'What is the Tamil word for "water"?');
    expect(normalizeCommonTanglish('un peru enna and tell me a story'), 'un peru enna and tell me a story');
  });
  test('Tamil speech is rendered to readable ASCII without inventing an answer', () {
    expect(romanTamil('நான் AI'), 'naan AI');
    expect(romanTamil('சாப்பிட மாட்டேன்.'), 'saappida maattaen.');
    expect(romanTamil('என் பெயர் GreenSoil JARVIS.'), 'en peyar GreenSoil JARVIS.');
    expect(romanTamil('தமிழ் ௨'), 'thamizh 2');
  });
}
