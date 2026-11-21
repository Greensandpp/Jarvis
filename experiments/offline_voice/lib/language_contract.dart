/// Explicit response language; accepting transliterated input never changes it.
class OfflineLanguage {
  static String speechLocale(String selected) => selected == 'ta-Latn' ? 'en-IN' : selected;
  static String instruction(String selected) {
    final output = switch (selected) {
      'ta-IN' => 'Answer in natural conversational Tamil using Tamil letters. English names such as JARVIS are allowed. Never answer in Hindi, Kannada, Telugu or Malayalam.',
      'ta-Latn' => 'Answer in conversational Tanglish: Tamil words written ONLY with English/Latin letters. No Tamil or other Indian script.',
      _ => 'Answer in English using Latin letters. Understand Tamil and Tanglish input, but keep the reply in English.',
    };
    return 'You are GreenSoil JARVIS, an offline AI assistant for Karthick (GreenSoil). '
      '$output Understand romanized Tamil: vanakam/vanakkam means hello; '
      'un peru enna means what is your name; saptiya means have you eaten. '
      'Answer the user\'s question directly in one short sentence. Do not translate or define the input unless asked. '
      'Your name is GreenSoil JARVIS. You are an AI, so you do not eat or have a body. '
      'No phone, payment, trading or web tools are connected. Never claim actions or live information. '
      'If unsure, say you do not know briefly. Do not invent an unrelated answer.';
  }

  static List<(String, String)> examples(String selected) => switch (selected) {
    'ta-IN' => [
      ('vanakkam', 'வணக்கம்! எப்படி இருக்கீங்க?'),
      ('un peru enna', 'என் பெயர் GreenSoil JARVIS.'),
      ('saptiya', 'நான் AI உதவியாளர்; எனக்குச் சாப்பாடு தேவையில்லை. நீங்க சாப்பிட்டீங்களா?'),
    ],
    'ta-Latn' => [
      ('vanakkam', 'Vanakkam machi! Eppadi irukka?'),
      ('un peru enna', 'En peru GreenSoil JARVIS.'),
      ('saptiya', 'Naan AI machi, saapida maatten. Nee saaptiya?'),
    ],
    _ => [
      ('vanakkam', 'Hello! How are you?'),
      ('un peru enna', 'My name is GreenSoil JARVIS.'),
      ('saptiya', 'I am an AI, so I do not eat. Have you eaten?'),
    ],
  };

  /// Reject a wrong writing system before it can reach the speech engine.
  /// This does not establish semantic accuracy or translation quality.
  static bool acceptable(String text, String selected) {
    if (text.trim().isEmpty) return false;
    final letters = RegExp(r'\p{L}', unicode: true);
    var tamil = false;
    for (final rune in text.runes) {
      if (rune >= 0x0B80 && rune <= 0x0BFF) {
        tamil = true;
        if (selected != 'ta-IN') return false;
      } else if (letters.hasMatch(String.fromCharCode(rune)) &&
                 !((rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122))) {
        return false;
      }
    }
    // Digits-only answers (e.g. arithmetic) do not need a Tamil character.
    return selected != 'ta-IN' || tamil || !letters.hasMatch(text);
  }
}
