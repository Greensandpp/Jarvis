import 'language_quality.dart';
import 'tamil_text.dart';

/// The model generates Tamil once; Tanglish display is a transliteration of
/// that same answer. Tamil speech never reads ASCII transliteration as English.
class LocalAnswer {
  const LocalAnswer(this.display, this.speech, this.locale);
  final String display, speech, locale;
  static String generationLanguage(String selected) => selected == 'ta-Latn' ? 'ta-IN' : selected;
  static String system(String selected) => OfflineLanguage.instruction(generationLanguage(selected));
  static String prompt(String input, String selected) => OfflineLanguage.userMessage(
    normalizeCommonTanglish(input), generationLanguage(selected));
  static LocalAnswer fromRaw(String raw, String selected) {
    if (!OfflineLanguage.acceptable(raw, generationLanguage(selected))) {
      throw StateError('The local model did not pass the ${generationLanguage(selected)} writing-system check');
    }
    final display = selected == 'ta-Latn' ? romanTamil(raw) : raw;
    if (!OfflineLanguage.acceptable(display, selected)) {
      throw StateError('Roman Tamil formatting unavailable');
    }
    return LocalAnswer(display, raw, OfflineLanguage.speechLocale(selected));
  }
}
