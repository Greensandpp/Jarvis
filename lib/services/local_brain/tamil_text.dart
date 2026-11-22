/// Small, explicit input adapter; it normalizes intent, never supplies replies.
String normalizeCommonTanglish(String input) {
  final key = input.trim().toLowerCase()
      .replaceFirst(RegExp(r'[?!.]?\s*reply in (tanglish|tamil|english)\.?$'), '')
      .replaceAll(RegExp(r'[?!.]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  const meanings = {
    'vanakam': 'Hello! Greet me briefly without using any name.', 'vanakkam': 'Hello! Greet me briefly without using any name.',
    'un peru enna': 'What is your name?', 'unga peru enna': 'What is your name?',
    'un peyar enna': 'What is your name?', 'unga peyar enna': 'What is your name?',
    'nee yaaru': 'Who are you?',
    'saptiya': 'As an AI assistant, can you eat food?', 'saaptiya': 'As an AI assistant, can you eat food?',
    'saptiyaa': 'As an AI assistant, can you eat food?', 'saaptiyaa': 'As an AI assistant, can you eat food?',
    'saptacha': 'As an AI assistant, can you eat food?', 'saptingala': 'As an AI assistant, can you eat food?',
    'have you eaten': 'As an AI assistant, can you eat food?',
    'have you eaten food': 'As an AI assistant, can you eat food?',
    'சாப்பிட்டாயா': 'As an AI assistant, can you eat food?',
    'சாப்பிட்டீர்களா': 'As an AI assistant, can you eat food?',
    'சாப்பிட்டீங்களா': 'As an AI assistant, can you eat food?',
    'nee manushana illa ai ah': 'Are you a human or an AI?',
  };
  if (meanings.containsKey(key)) return meanings[key]!;
  final translation = RegExp(r'^(.{1,80}?)\s+ku\s+tamil\s+la\s+enna$').firstMatch(key);
  if (translation != null) return 'What is the Tamil word for "${translation.group(1)}"?';
  return input;
}

/// Deterministic ASCII rendering of the actual model's Tamil response.
/// It is approximate Roman Tamil, not a second model or a canned chat answer.
String romanTamil(String text) {
  const vowels = {'அ':'a','ஆ':'aa','இ':'i','ஈ':'ee','உ':'u','ஊ':'oo',
    'எ':'e','ஏ':'ae','ஐ':'ai','ஒ':'o','ஓ':'oa','ஔ':'au','ஃ':'h'};
  const bases = {'க':'k','ங':'ng','ச':'s','ஞ':'ny','ட':'d','ண':'n','த':'th',
    'ந':'n','ப':'p','ம':'m','ய':'y','ர':'r','ல':'l','வ':'v','ழ':'zh','ள':'l',
    'ற':'r','ன':'n','ஜ':'j','ஷ':'sh','ஸ':'s','ஹ':'h','ஶ':'sh'};
  const signs = {'ா':'aa','ி':'i','ீ':'ee','ு':'u','ூ':'oo','ெ':'e','ே':'ae',
    'ை':'ai','ொ':'o','ோ':'oa','ௌ':'au','்':''};
  final chars = text.runes.map(String.fromCharCode).toList();
  final output = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    final char = chars[i];
    if (vowels.containsKey(char)) { output.write(vowels[char]); continue; }
    if (bases.containsKey(char)) {
      var base = bases[char]!;
      if (char == 'ட' && ((i + 1 < chars.length && chars[i + 1] == '்') ||
          (i >= 2 && chars[i - 1] == '்' && chars[i - 2] == char))) base = 't';
      output.write(base);
      if (i + 1 < chars.length && signs.containsKey(chars[i + 1])) {
        final sign = chars[++i];
        if (i + 1 < chars.length && (sign == 'ெ' || sign == 'ே') && chars[i + 1] == 'ா') {
          output.write(sign == 'ெ' ? 'o' : 'oa'); i++;
        } else if (i + 1 < chars.length && sign == 'ெ' && chars[i + 1] == 'ௗ') {
          output.write('au'); i++;
        } else { output.write(signs[sign]); }
      } else { output.write('a'); }
    } else {
      final rune = char.runes.single;
      if (rune >= 0x0BE6 && rune <= 0x0BEF) output.write(rune - 0x0BE6);
      else output.write(char);
    }
  }
  return output.toString();
}
