import 'math3d.dart';

/// Mouth shapes (viseme set modelled on the common 15-viseme standard so a
/// future glTF face with ARKit/Oculus-style morph targets maps 1:1).
enum Viseme {
  sil, // rest / closed
  pp, // m b p (lips closed)
  ff, // f v (lip to teeth)
  th, // th (tongue between teeth)
  dd, // t d ட த (retroflex/dental stop)
  kk, // k g ங
  ch, // ch j sh ச ஜ ஷ
  ss, // s z ஸ
  nn, // n l ன ந ண ல ள
  rr, // r ர ற ழ
  aa, // a ஆ
  e, // e ஏ எ ஐ
  ih, // i ஈ இ
  oh, // o ஓ ஒ ஔ
  ou, // u ஊ உ
}

/// How far the jaw opens for each viseme (0 closed .. 1 wide).
const Map<Viseme, double> visemeJawOpen = {
  Viseme.sil: 0.0,
  Viseme.pp: 0.0,
  Viseme.ff: 0.12,
  Viseme.th: 0.18,
  Viseme.dd: 0.22,
  Viseme.kk: 0.25,
  Viseme.ch: 0.2,
  Viseme.ss: 0.12,
  Viseme.nn: 0.2,
  Viseme.rr: 0.28,
  Viseme.aa: 0.95,
  Viseme.e: 0.6,
  Viseme.ih: 0.42,
  Viseme.oh: 0.75,
  Viseme.ou: 0.45,
};

/// Lip rounding (0 spread .. 1 rounded) for each viseme.
const Map<Viseme, double> visemeRound = {
  Viseme.oh: 0.85,
  Viseme.ou: 1.0,
  Viseme.ch: 0.45,
  Viseme.rr: 0.3,
};

bool isVowelViseme(Viseme v) =>
    v == Viseme.aa || v == Viseme.e || v == Viseme.ih || v == Viseme.oh || v == Viseme.ou;

/// One timed mouth target. Produced by [TamilVisemeMapper] today; a TTS
/// engine with phoneme/word timing (Edge TTS word boundaries, a forced
/// aligner, or Gemini Live audio) can produce these directly later.
class VisemeEvent {
  const VisemeEvent(this.start, this.duration, this.viseme, {this.weight = 1});
  final double start;
  final double duration;
  final Viseme viseme;
  final double weight;
  double get end => start + duration;
}

/// Contract a face implementation must satisfy. The procedural placeholder
/// face implements it now; the final rigged glTF face (morph targets /
/// blendshapes) implements the same interface, so lip sync code is reused.
abstract class FaceRig {
  /// Normalised weights per viseme (sum ≈ 1 while speaking).
  void setVisemeWeights(Map<Viseme, double> weights);

  /// 0 closed .. 1 fully open.
  void setJawOpen(double open);

  /// 0 open eyes .. 1 closed.
  void setBlink(double amount);

  /// Gaze direction in -1..1 (x right, y up).
  void setGaze(double x, double y);

  /// Free-form expression channel (e.g. 'smile', 'focus') 0..1.
  void setExpression(String name, double amount);
}

/// Simple value-holding FaceRig the procedural renderer reads every frame.
class ProceduralFaceRig implements FaceRig {
  Map<Viseme, double> weights = const {Viseme.sil: 1};
  double jawOpen = 0;
  double blink = 0;
  double gazeX = 0, gazeY = 0;
  final Map<String, double> expressions = {};

  /// Derived lip rounding from current weights.
  double get round {
    var r = 0.0;
    weights.forEach((v, w) => r += (visemeRound[v] ?? 0) * w);
    return clamp01(r);
  }

  /// True when lips are pressed (m/b/p).
  double get lipsClosed => weights[Viseme.pp] ?? 0;

  @override
  void setVisemeWeights(Map<Viseme, double> w) => weights = w;
  @override
  void setJawOpen(double open) => jawOpen = clamp01(open);
  @override
  void setBlink(double amount) => blink = clamp01(amount);
  @override
  void setGaze(double x, double y) {
    gazeX = x.clamp(-1.0, 1.0).toDouble();
    gazeY = y.clamp(-1.0, 1.0).toDouble();
  }

  @override
  void setExpression(String name, double amount) => expressions[name] = clamp01(amount);
}

/// A playable sequence of visemes with smooth co-articulated blending.
class VisemeTimeline {
  VisemeTimeline(List<VisemeEvent> events) : events = List.unmodifiable(events);

  final List<VisemeEvent> events;

  static final empty = VisemeTimeline(const []);

  double get duration => events.isEmpty ? 0 : events.last.end;

  /// Blend window (seconds) at event boundaries.
  static const crossfade = 0.045;

  int _cursor = 0;

  int _find(double t) {
    if (events.isEmpty) return -1;
    if (_cursor >= events.length || events[_cursor].start > t) _cursor = 0;
    while (_cursor < events.length - 1 && events[_cursor].end <= t) {
      _cursor++;
    }
    return _cursor;
  }

  /// Viseme weights at time [t] (seconds since speech start).
  Map<Viseme, double> sample(double t) {
    if (events.isEmpty || t < 0 || t >= duration) return const {Viseme.sil: 1};
    final i = _find(t);
    final cur = events[i];
    final out = <Viseme, double>{};
    void add(Viseme v, double w) => out[v] = (out[v] ?? 0) + w;
    final intoEnd = cur.end - t;
    if (intoEnd < crossfade && i + 1 < events.length) {
      final k = smoothstep(crossfade, 0, intoEnd) * 0.5;
      add(cur.viseme, (1 - k) * cur.weight);
      add(events[i + 1].viseme, k * events[i + 1].weight);
    } else if (t - cur.start < crossfade && i > 0) {
      final k = 0.5 - smoothstep(0, crossfade, t - cur.start) * 0.5;
      add(cur.viseme, (1 - k) * cur.weight);
      add(events[i - 1].viseme, k * events[i - 1].weight);
    } else {
      add(cur.viseme, cur.weight);
    }
    final rest = 1 - out.values.fold(0.0, (a, b) => a + b);
    if (rest > 0.001) add(Viseme.sil, rest);
    return out;
  }

  /// Jaw opening implied by the weights at [t].
  double jawOpen(double t) {
    var j = 0.0;
    sample(t).forEach((v, w) => j += (visemeJawOpen[v] ?? 0) * w);
    return clamp01(j);
  }

  /// Synthetic speech amplitude envelope (drives glow when no PCM tap).
  double amplitude(double t) {
    if (events.isEmpty || t < 0 || t >= duration) return 0;
    final e = events[_find(t)];
    if (e.viseme == Viseme.sil) return 0.05;
    final base = isVowelViseme(e.viseme) ? 0.75 : 0.4;
    final local = (t - e.start) / (e.duration <= 0 ? 1 : e.duration);
    return base * (0.75 + 0.25 * (1 - (2 * local - 1).abs())) * e.weight;
  }
}

/// Text → viseme timeline for Tamil script, Tanglish and English.
///
/// This is a timing *estimate* (rule based, ~13 phonemes/second) intended to
/// keep the mouth plausibly in sync with platform TTS. When a speech engine
/// exposes real phoneme/word timings they should replace this via
/// [VisemeTimeline] built from [VisemeEvent]s.
class TamilVisemeMapper {
  const TamilVisemeMapper({this.rate = 1.0});

  /// Speech-rate multiplier (1.0 ≈ normal TTS rate).
  final double rate;

  static const _vowelDur = 0.095, _longVowelDur = 0.15, _consDur = 0.055;
  static const _wordGap = 0.06, _commaGap = 0.18, _stopGap = 0.32;

  // Tamil independent vowels.
  static const Map<String, Viseme> _tamilVowels = {
    'அ': Viseme.aa, 'ஆ': Viseme.aa, 'இ': Viseme.ih, 'ஈ': Viseme.ih,
    'உ': Viseme.ou, 'ஊ': Viseme.ou, 'எ': Viseme.e, 'ஏ': Viseme.e,
    'ஐ': Viseme.e, 'ஒ': Viseme.oh, 'ஓ': Viseme.oh, 'ஔ': Viseme.oh,
  };
  static const _longTamil = {'ஆ', 'ஈ', 'ஊ', 'ஏ', 'ஐ', 'ஓ', 'ஔ', 'ா', 'ீ', 'ூ', 'ே', 'ை', 'ோ', 'ௌ'};

  // Tamil dependent vowel signs.
  static const Map<String, Viseme> _tamilSigns = {
    'ா': Viseme.aa, 'ி': Viseme.ih, 'ீ': Viseme.ih, 'ு': Viseme.ou, 'ூ': Viseme.ou,
    'ெ': Viseme.e, 'ே': Viseme.e, 'ை': Viseme.e, 'ொ': Viseme.oh, 'ோ': Viseme.oh, 'ௌ': Viseme.oh,
  };

  // Tamil consonants (incl. Grantha).
  static const Map<String, Viseme> _tamilConsonants = {
    'க': Viseme.kk, 'ங': Viseme.kk, 'ச': Viseme.ch, 'ஞ': Viseme.nn, 'ட': Viseme.dd,
    'ண': Viseme.nn, 'த': Viseme.dd, 'ந': Viseme.nn, 'ப': Viseme.pp, 'ம': Viseme.pp,
    'ய': Viseme.ih, 'ர': Viseme.rr, 'ல': Viseme.nn, 'வ': Viseme.ff, 'ழ': Viseme.rr,
    'ள': Viseme.nn, 'ற': Viseme.rr, 'ன': Viseme.nn, 'ஜ': Viseme.ch, 'ஷ': Viseme.ch,
    'ஸ': Viseme.ss, 'ஹ': Viseme.aa,
  };
  static const _virama = '்';

  // Latin digraphs first (Tanglish: "th", "zh", "aa", "ee", "oo" ...).
  static const Map<String, (Viseme, bool)> _latinDigraphs = {
    'aa': (Viseme.aa, true), 'ee': (Viseme.ih, true), 'ii': (Viseme.ih, true),
    'oo': (Viseme.ou, true), 'uu': (Viseme.ou, true), 'ai': (Viseme.e, true),
    'au': (Viseme.oh, true), 'ou': (Viseme.oh, true), 'ea': (Viseme.ih, true),
    'th': (Viseme.th, false), 'dh': (Viseme.dd, false), 'ch': (Viseme.ch, false),
    'sh': (Viseme.ch, false), 'zh': (Viseme.rr, false), 'ng': (Viseme.kk, false),
    'ph': (Viseme.ff, false), 'wh': (Viseme.ou, false), 'kh': (Viseme.kk, false),
  };

  static const Map<String, Viseme> _latin = {
    'a': Viseme.aa, 'e': Viseme.e, 'i': Viseme.ih, 'o': Viseme.oh, 'u': Viseme.ou, 'y': Viseme.ih,
    'b': Viseme.pp, 'm': Viseme.pp, 'p': Viseme.pp, 'f': Viseme.ff, 'v': Viseme.ff, 'w': Viseme.ou,
    't': Viseme.dd, 'd': Viseme.dd, 'n': Viseme.nn, 'l': Viseme.nn, 'k': Viseme.kk, 'g': Viseme.kk,
    'q': Viseme.kk, 'c': Viseme.kk, 'x': Viseme.kk, 'j': Viseme.ch, 's': Viseme.ss, 'z': Viseme.ss,
    'r': Viseme.rr, 'h': Viseme.aa,
  };

  VisemeTimeline map(String text) {
    final r = rate <= 0.1 ? 0.1 : rate;
    final events = <VisemeEvent>[];
    var t = 0.0;
    void emit(Viseme v, double dur, {double weight = 1}) {
      final d = dur / r;
      // Merge identical consecutive visemes to avoid flutter.
      if (events.isNotEmpty && events.last.viseme == v && events.last.end >= t - 1e-9) {
        final last = events.removeLast();
        events.add(VisemeEvent(last.start, last.duration + d, v, weight: weight));
      } else {
        events.add(VisemeEvent(t, d, v, weight: weight));
      }
      t += d;
    }

    final chars = text.runes.map(String.fromCharCode).toList();
    var i = 0;
    while (i < chars.length) {
      final c = chars[i];
      final lower = c.toLowerCase();
      // Pauses.
      if (c.trim().isEmpty) {
        emit(Viseme.sil, _wordGap);
        i++;
        continue;
      }
      if (',;:'.contains(c)) {
        emit(Viseme.sil, _commaGap);
        i++;
        continue;
      }
      if ('.!?।'.contains(c)) {
        emit(Viseme.sil, _stopGap);
        i++;
        continue;
      }
      // Tamil.
      final tv = _tamilVowels[c];
      if (tv != null) {
        emit(tv, _longTamil.contains(c) ? _longVowelDur : _vowelDur);
        i++;
        continue;
      }
      final tc = _tamilConsonants[c];
      if (tc != null) {
        emit(tc, _consDur);
        final next = i + 1 < chars.length ? chars[i + 1] : '';
        if (next == _virama) {
          i += 2; // pure consonant, no vowel
        } else if (_tamilSigns.containsKey(next)) {
          emit(_tamilSigns[next]!, _longTamil.contains(next) ? _longVowelDur : _vowelDur);
          i += 2;
        } else {
          emit(Viseme.aa, _vowelDur * 0.8, weight: 0.85); // inherent 'a'
          i++;
        }
        continue;
      }
      if (_tamilSigns.containsKey(c) || c == _virama) {
        i++; // stray sign
        continue;
      }
      // Latin (Tanglish / English).
      if (i + 1 < chars.length) {
        final di = _latinDigraphs[lower + chars[i + 1].toLowerCase()];
        if (di != null) {
          final (v, isVowel) = di;
          emit(v, isVowel ? _longVowelDur : _consDur * 1.2);
          i += 2;
          continue;
        }
      }
      final lv = _latin[lower];
      if (lv != null) {
        emit(lv, isVowelViseme(lv) ? _vowelDur : _consDur);
        i++;
        continue;
      }
      if (RegExp(r'[0-9]').hasMatch(c)) {
        emit(Viseme.e, _vowelDur * 2); // digits are spoken as words
        emit(Viseme.nn, _consDur);
      }
      i++; // emoji / symbols are silent
    }
    // Trim trailing silence.
    while (events.isNotEmpty && events.last.viseme == Viseme.sil) {
      events.removeLast();
    }
    return VisemeTimeline(events);
  }
}
