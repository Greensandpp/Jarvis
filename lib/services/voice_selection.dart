/// Pure-Dart selection of on-device TTS voices (flutter_tts `getVoices`).
///
/// Android voice lists differ per phone and engine (Google, Samsung, vivo).
/// Gender is only taken from what the engine actually reports: a `gender`
/// field or a gender marker in the voice name (e.g. `#female_1`). Voices
/// without such data are "unknown" — never claimed to be female.
enum VoiceGender { female, male, unknown }

class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    this.gender = VoiceGender.unknown,
    this.networkRequired = false,
    this.quality,
  });

  final String name;
  final String locale; // normalised, lower-case, dash separated (ta-in)
  final VoiceGender gender;
  final bool networkRequired;
  final int? quality; // Android Voice quality (100..500) when reported

  static TtsVoice? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final name = '${raw['name'] ?? ''}'.trim();
    final locale = '${raw['locale'] ?? ''}'.trim().toLowerCase().replaceAll(
      '_',
      '-',
    );
    if (name.isEmpty || locale.isEmpty) return null;
    final lname = name.toLowerCase();
    final g = '${raw['gender'] ?? ''}'.toLowerCase();
    final gender =
        g == 'female' || RegExp(r'(^|[#_\-\s])female').hasMatch(lname)
        ? VoiceGender.female
        : g == 'male' || RegExp(r'(^|[#_\-\s])male').hasMatch(lname)
        ? VoiceGender.male
        : VoiceGender.unknown;
    final net = '${raw['network_required'] ?? raw['networkRequired'] ?? ''}'
        .toLowerCase();
    final networkRequired =
        net == '1' ||
        net == 'true' ||
        lname.endsWith('-network') ||
        lname.contains('network');
    final q = int.tryParse('${raw['quality'] ?? ''}');
    return TtsVoice(
      name: name,
      locale: locale,
      gender: gender,
      networkRequired: networkRequired,
      quality: q,
    );
  }

  Map<String, String> toFlutterTts() => {'name': name, 'locale': locale};

  @override
  String toString() =>
      '$name ($locale, ${gender.name}${networkRequired ? ', online' : ', offline'})';
}

class VoiceChoice {
  const VoiceChoice(this.voice, this.reason);
  final TtsVoice?
  voice; // null → let the engine use its default for the language
  final String reason;
}

/// Ranks voices for [languageTag] ("ta-IN" / "en-IN"). Order:
/// 1. matching language (exact region before same language other region),
/// 2. requested gender (female when [preferFemale]) before unknown before other,
/// 3. offline (local) voices first unless [online] is true — so the voice
///    still works without internet,
/// 4. higher reported quality, then name for stability.
List<TtsVoice> rankVoices(
  List<TtsVoice> all,
  String languageTag, {
  bool preferFemale = true,
  bool online = false,
}) {
  final tag = languageTag.toLowerCase().replaceAll('_', '-');
  final lang = tag.split('-').first;
  final matching = all
      .where((v) => v.locale == tag || v.locale.split('-').first == lang)
      .toList();
  int genderScore(TtsVoice v) {
    if (v.gender == VoiceGender.unknown) return 1;
    final wanted = preferFemale ? VoiceGender.female : VoiceGender.male;
    return v.gender == wanted ? 0 : 2;
  }

  matching.sort((a, b) {
    final r = (a.locale == tag ? 0 : 1).compareTo(b.locale == tag ? 0 : 1);
    if (r != 0) return r;
    final g = genderScore(a).compareTo(genderScore(b));
    if (g != 0) return g;
    if (!online && a.networkRequired != b.networkRequired)
      return a.networkRequired ? 1 : -1;
    final q = (b.quality ?? 0).compareTo(a.quality ?? 0);
    if (q != 0) return q;
    return a.name.compareTo(b.name);
  });
  return matching;
}

/// Picks the voice to use and explains why (shown in Diagnostics).
VoiceChoice chooseVoice(
  List<TtsVoice> all,
  String languageTag, {
  bool preferFemale = true,
  bool online = false,
  String? pinned,
}) {
  if (pinned != null && pinned.isNotEmpty) {
    for (final v in all) {
      if (v.name == pinned &&
          v.locale.split('-').first ==
              languageTag.toLowerCase().replaceAll('_', '-').split('-').first)
        return VoiceChoice(v, 'chosen by you');
    }
  }
  final ranked = rankVoices(
    all,
    languageTag,
    preferFemale: preferFemale,
    online: online,
  );
  if (ranked.isEmpty) {
    return VoiceChoice(
      null,
      'no $languageTag voice installed — using the engine default '
      '(install it in Settings → Text-to-speech)',
    );
  }
  final v = ranked.first;
  final g = v.gender == VoiceGender.female
      ? 'female (reported by the voice engine)'
      : v.gender == VoiceGender.unknown
      ? 'gender not reported by the engine'
      : 'no female voice reported for this language';
  return VoiceChoice(v, '$g · ${v.networkRequired ? 'online' : 'offline'}');
}
