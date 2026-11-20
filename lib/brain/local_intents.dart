import 'package:intl/intl.dart';

import '../services/settings_service.dart';
import 'language.dart';
import 'visual_bus.dart';

/// Offline shortcuts: answered on the phone with no AI and no internet.
/// Everything else goes to the tool-calling brain.
class LocalIntents {
  LocalIntents._();

  static const _airaModels = {
    'neural': 'neuralReactor', 'reactor': 'neuralReactor', 'amber': 'amberHologram', 'electric': 'electricWeb',
    'lightning': 'electricWeb', 'head': 'aiHead', 'jelly': 'jellyfish', 'violet': 'violetVortex', 'vortex': 'violetVortex',
    'aurora': 'auroraRibbon', 'ribbon': 'auroraRibbon', 'dna': 'dnaHelix', 'helix': 'dnaHelix', 'crystal': 'crystalBloom',
    'solar': 'solarFlare', 'flare': 'solarFlare',
  };

  static String _t(ReplyLanguage l, String en, String ta, String tg) =>
      switch (l) { ReplyLanguage.tamil => ta, ReplyLanguage.tanglish => tg, ReplyLanguage.english => en };

  static String offlineHelp(ReplyLanguage l) => _t(l,
      'Offline I can still tell the time and date, switch visuals (say "switch to AIRA"), and change reply language or voice.',
      'இணையம் இல்லாமலும் நேரம், தேதி, காட்சி மாற்றம், மொழி மற்றும் குரல் மாற்றம் செய்ய முடியும்.',
      'Offline-la kooda time, date sollalam, visual maathalam ("AIRA-ku maathu"), language and voice maathalam.');

  /// Returns a reply, or null when the brain should handle it.
  static Future<String?> handle(String text, ReplyLanguage lang) async {
    final t = text.toLowerCase().trim();
    final s = SettingsService.instance;
    final now = DateTime.now();

    // Time / date (EN, Tamil script, Tanglish)
    if (RegExp(r"^(what('s)?( is)?( the)? )?time( now| is it| please)?\??$|^time enna|^mani enna|^இப்போ மணி|^நேரம் என்ன|^என்ன நேரம்").hasMatch(t)) {
      final hm = DateFormat('h:mm a').format(now);
      return _t(lang, 'It is $hm.', 'இப்போது நேரம் $hm.', 'Ippo time $hm.');
    }
    if (RegExp(r"^(what('s| is) )?(today'?s )?date( today)?\??$|^inniki (enna )?date|^இன்று தேதி|^இன்னைக்கு தேதி").hasMatch(t)) {
      final d = DateFormat('EEEE, d MMMM yyyy').format(now);
      return _t(lang, 'Today is $d.', 'இன்று $d.', 'Inniki $d.');
    }

    // Visual switching: "switch to aira", "aira mode", "AIRA-ku maathu", "show apex", "aira jellyfish"
    final vm = RegExp(r'\b(core|jarvis core|arc|aira|office|agent office|apex|mira|serpent guardian|serpent|naagam)\b').firstMatch(t);
    final switchVerb = RegExp(r'\b(switch|change|show|open|mode|maathu|maathu|maattu|மாற்று|காட்டு|style|visual|look)\b').hasMatch(t) ||
        t.split(RegExp(r'\s+')).length <= 3;
    if (vm != null && switchVerb && !t.contains('?') && !t.startsWith('what')) {
      var mode = vm.group(1)!;
      mode = switch (mode) { 'jarvis core' || 'arc' => 'core', 'agent office' => 'office',
        'serpent guardian' || 'naagam' => 'serpent', _ => mode };
      String? model;
      if (mode == 'aira') {
        for (final e in _airaModels.entries) {
          if (t.contains(e.key)) model = e.value;
        }
      }
      await requestVisual(mode: mode, airaModel: model);
      final name = mode.toUpperCase() + (model == null ? '' : ' · $model');
      return _t(lang, 'Switched to $name.', '$name காட்சிக்கு மாற்றினேன்.', '$name-ku maathiten.');
    }

    // Reply language
    final lm = RegExp(r'^(reply|speak|talk|pesu|pesunga|பேசு)( to me| with me| in| only)*\s*(tamil|english|tanglish|தமிழ்)|(\btamil|english|tanglish|தமிழ்)(\s?-?la|ில்)? ?(pesu|pesunga|பேசு|reply|mode)')
        .firstMatch(t);
    if ((lm != null && t.split(RegExp(r'\s+')).length <= 6) || t == 'auto language') {
      final want = t.contains('tanglish') ? 'tanglish' : (t.contains('tamil') || t.contains('தமிழ்')) ? 'tamil'
          : t.contains('english') ? 'english' : 'auto';
      await s.setReplyLanguage(want);
      final l2 = resolveReplyLanguage(want, text);
      return _t(l2, 'Okay, I will reply in $want.', 'சரி, இனி தமிழில் பதில் சொல்கிறேன்.', 'Seri, ippo irundhu Tanglish-la pesuren.');
    }

    // Voice gender
    if (RegExp(r'\b(female|girl|woman|lady|pen) (voice|kural)|பெண் குரல்').hasMatch(t)) {
      await s.setPreferFemaleVoice(true);
      return _t(lang, 'Female voice selected.', 'பெண் குரல் தேர்ந்தெடுக்கப்பட்டது.', 'Female voice set panniten.');
    }
    if (RegExp(r'\b(male|man|boy|aan) (voice|kural)|ஆண் குரல்').hasMatch(t)) {
      await s.setPreferFemaleVoice(false);
      return _t(lang, 'Default voice selected.', 'இயல்பு குரல் தேர்ந்தெடுக்கப்பட்டது.', 'Default voice set panniten.');
    }
    return null;
  }
}
