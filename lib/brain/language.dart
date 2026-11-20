/// Reply-language detection for Tamil / English / Tanglish input.
enum ReplyLanguage { english, tamil, tanglish }

const _tanglishWords = {
  'enna', 'epdi', 'eppadi', 'irukku', 'iruku', 'irukeenga', 'pannu', 'pannunga', 'panna', 'pannanum',
  'seri', 'sari', 'vanakkam', 'nalla', 'romba', 'konjam', 'illa', 'illai', 'venum', 'vendam', 'sollu',
  'sollunga', 'machi', 'paaru', 'paarunga', 'eppo', 'inniki', 'innaiku', 'naalaiku', 'naalai', 'yenna',
  'enakku', 'unakku', 'onnu', 'ennoda', 'neenga', 'naan', 'nan', 'theriyuma', 'theriyum', 'podu', 'vaa',
  'poi', 'kudu', 'kudunga', 'aagum', 'aachu', 'mudiyuma', 'mudiyum', 'ethana', 'evlo', 'yaaru', 'enga',
  'inga', 'anga', 'paathu', 'vechu', 'adhu', 'idhu', 'ithu', 'athu', 'open pannu', 'nandri',
};

ReplyLanguage detectLanguage(String text) {
  if (RegExp(r'[஀-௿]').hasMatch(text)) {
    // Tamil script mixed with many English words is still answered in Tamil.
    return ReplyLanguage.tamil;
  }
  final words = text.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return ReplyLanguage.english;
  final hits = words.where(_tanglishWords.contains).length;
  if (hits >= 2 || (hits == 1 && words.length <= 4)) return ReplyLanguage.tanglish;
  return ReplyLanguage.english;
}

/// Resolves the language preference: 'auto' follows the user's input.
ReplyLanguage resolveReplyLanguage(String preference, String input) => switch (preference) {
      'tamil' => ReplyLanguage.tamil,
      'english' => ReplyLanguage.english,
      'tanglish' => ReplyLanguage.tanglish,
      _ => detectLanguage(input),
    };

String languageInstruction(ReplyLanguage l) => switch (l) {
      ReplyLanguage.tamil => 'Reply in Tamil (Tamil script). Keep numbers, ₹ amounts and app names as they are.',
      ReplyLanguage.tanglish => 'Reply in Tanglish: conversational Tamil written in English letters, mixed with English words, '
          'the way the user wrote. Do not switch to Tamil script.',
      ReplyLanguage.english => 'Reply in clear Indian English.',
    };

/// Edge neural voice for the reply language, honouring a female preference.
String neuralVoiceFor(ReplyLanguage l, {required bool female, required String englishDefault}) => switch (l) {
      ReplyLanguage.tamil => female ? 'ta-IN-PallaviNeural' : 'ta-IN-ValluvarNeural',
      ReplyLanguage.tanglish => female ? 'en-IN-NeerjaNeural' : 'en-IN-PrabhatNeural',
      ReplyLanguage.english => female ? 'en-IN-NeerjaNeural' : englishDefault,
    };
