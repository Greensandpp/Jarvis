import 'dart:convert';
import 'dart:math' as math;

/// Indicator engine for owner-supplied candles (pasted, exported from
/// TradingView, or read from a chart screenshot by the AI). JARVIS has no live
/// feed; nothing here fetches or invents prices.
class Candle {
  final String time;
  final double open, high, low, close, volume;
  const Candle(this.time, this.open, this.high, this.low, this.close, this.volume);
}

List<Candle> parseCandles(String csv) {
  final out = <Candle>[];
  for (final raw in csv.split(RegExp(r'[\r\n;]+'))) {
    final p = raw.split(RegExp(r'[,\t ]+')).where((e) => e.isNotEmpty).toList();
    if (p.length < 5) continue;
    final nums = p.map(double.tryParse).toList();
    // Accept "time,o,h,l,c[,v]" or "o,h,l,c[,v]"
    // A leading non-numeric token (or a 6th column) is the time column.
    final off = nums[0] == null || p.length >= 6 ? 1 : 0;
    final v = [for (var i = off; i < p.length; i++) nums[i]];
    if (v.length < 4 || v.take(4).any((n) => n == null)) continue;
    final o = v[0]!, h = v[1]!, l = v[2]!, c = v[3]!;
    if (h < math.max(o, c) || l > math.min(o, c)) continue; // malformed row
    out.add(Candle(off == 1 ? p[0] : '${out.length}', o, h, l, c, v.length > 4 && v[4] != null ? v[4]! : 0));
  }
  return out;
}

List<double> ema(List<double> x, int n) {
  if (x.isEmpty) return [];
  final k = 2 / (n + 1);
  final out = <double>[x.first];
  for (var i = 1; i < x.length; i++) {
    out.add(x[i] * k + out.last * (1 - k));
  }
  return out;
}

List<double?> sma(List<double> x, int n) => [
      for (var i = 0; i < x.length; i++)
        i + 1 < n ? null : x.sublist(i + 1 - n, i + 1).reduce((a, b) => a + b) / n,
    ];

/// Cumulative session VWAP (typical price × volume). Null when there is no volume.
List<double?> vwap(List<Candle> c) {
  var pv = 0.0, vol = 0.0;
  return [
    for (final k in c)
      () {
        pv += (k.high + k.low + k.close) / 3 * k.volume;
        vol += k.volume;
        return vol == 0 ? null : pv / vol;
      }(),
  ];
}

/// Supertrend (ATR period, multiplier). Returns (line, isUp) per candle.
List<(double, bool)> supertrend(List<Candle> c, {int period = 10, double mult = 3}) {
  final out = <(double, bool)>[];
  if (c.isEmpty) return out;
  final tr = <double>[];
  for (var i = 0; i < c.length; i++) {
    final pc = i == 0 ? c[i].close : c[i - 1].close;
    tr.add(math.max(c[i].high - c[i].low, math.max((c[i].high - pc).abs(), (c[i].low - pc).abs())));
  }
  double atr = tr.first, fu = 0, fl = 0;
  var up = true;
  for (var i = 0; i < c.length; i++) {
    atr = i < period ? tr.sublist(0, i + 1).reduce((a, b) => a + b) / (i + 1) : (atr * (period - 1) + tr[i]) / period;
    final mid = (c[i].high + c[i].low) / 2;
    final bu = mid + mult * atr, bl = mid - mult * atr;
    if (i == 0) {
      fu = bu;
      fl = bl;
    } else {
      fu = (bu < fu || c[i - 1].close > fu) ? bu : fu;
      fl = (bl > fl || c[i - 1].close < fl) ? bl : fl;
      if (up && c[i].close < fl) {
        up = false;
      } else if (!up && c[i].close > fu) {
        up = true;
      }
    }
    out.add((up ? fl : fu, up));
  }
  return out;
}

/// Swing structure from the last pivots: HH/HL (up), LH/LL (down) or range.
String structure(List<Candle> c, {int w = 2}) {
  final highs = <double>[], lows = <double>[];
  for (var i = w; i < c.length - w; i++) {
    final win = c.sublist(i - w, i + w + 1);
    if (win.every((k) => k.high <= c[i].high)) highs.add(c[i].high);
    if (win.every((k) => k.low >= c[i].low)) lows.add(c[i].low);
  }
  if (highs.length < 2 || lows.length < 2) return 'unclear (not enough swings)';
  final hh = highs.last > highs[highs.length - 2], hl = lows.last > lows[lows.length - 2];
  if (hh && hl) return 'uptrend (higher high + higher low)';
  if (!hh && !hl) return 'downtrend (lower high + lower low)';
  return 'range / transition';
}

class IndicatorReport {
  final double close, ema9, ma9;
  final double? vwap;
  final double supertrend;
  final bool supertrendUp;
  final String structure, bias;
  final int score; // 0-100 confluence for the bias
  final List<String> reasons;
  const IndicatorReport(this.close, this.ema9, this.ma9, this.vwap, this.supertrend, this.supertrendUp, this.structure,
      this.bias, this.score, this.reasons);

  bool get tradeable => bias != 'NEUTRAL' && score >= 70;

  Map<String, dynamic> toJson() => {
        'close': close, 'ema9': _r(ema9), 'ma9': _r(ma9), 'vwap': vwap == null ? null : _r(vwap!),
        'supertrend': _r(supertrend), 'supertrend_dir': supertrendUp ? 'up' : 'down', 'structure': structure,
        'bias': bias, 'confluence': score, 'tradeable': tradeable, 'reasons': reasons,
      };

  String describe() => [
        'Close ${_r(close)} · EMA9 ${_r(ema9)} · MA9 ${_r(ma9)} · VWAP ${vwap == null ? 'n/a (no volume)' : _r(vwap!)}',
        'Supertrend ${supertrendUp ? 'UP' : 'DOWN'} at ${_r(supertrend)} · Structure: $structure',
        'Bias $bias, confluence $score/100 → ${tradeable ? 'setup candidate (still run the risk gate)' : 'NO TRADE'}',
        ...reasons.map((r) => '• $r'),
      ].join('\n');

  static double _r(double v) => (v * 100).roundToDouble() / 100;
}

IndicatorReport analyzeCandles(List<Candle> c) {
  final closes = c.map((k) => k.close).toList();
  final e = ema(closes, 9).last;
  final m = sma(closes, 9).last ?? closes.last;
  final vw = vwap(c).last;
  final st = supertrend(c).last;
  final s = structure(c);
  final last = closes.last;
  var bull = 0, bear = 0;
  final why = <String>[];
  void vote(bool b, int w, String txt) {
    if (b) {
      bull += w;
    } else {
      bear += w;
    }
    why.add(txt);
  }

  vote(last > e, 20, 'Close ${last > e ? 'above' : 'below'} EMA9');
  vote(e > m, 15, 'EMA9 ${e > m ? 'above' : 'below'} MA9');
  if (vw != null) vote(last > vw, 20, 'Close ${last > vw ? 'above' : 'below'} VWAP');
  vote(st.$2, 25, 'Supertrend ${st.$2 ? 'up' : 'down'}');
  if (s.startsWith('uptrend')) {
    bull += 20;
    why.add('Structure up');
  } else if (s.startsWith('downtrend')) {
    bear += 20;
    why.add('Structure down');
  } else {
    why.add('Structure $s');
  }
  final total = (vw == null ? 80 : 100);
  final bias = bull > bear ? 'BULLISH (CE)' : bear > bull ? 'BEARISH (PE)' : 'NEUTRAL';
  final score = ((math.max(bull, bear) / total) * 100).round();
  if (score < 70) why.add('Confluence below 70 → NO TRADE');
  return IndicatorReport(last, e, m, vw, st.$1, st.$2, s, score < 55 ? 'NEUTRAL' : bias, score, why);
}

/// Option-chain OI summary from owner-supplied rows: strike,ce_oi,pe_oi[,ce_chg,pe_chg].
class OiReport {
  final double pcr, maxPain, support, resistance;
  final String read;
  const OiReport(this.pcr, this.maxPain, this.support, this.resistance, this.read);
  String describe() => 'PCR ${pcr.toStringAsFixed(2)} · max pain $maxPain · OI support (max PE) $support · '
      'OI resistance (max CE) $resistance\n$read';
  Map<String, dynamic> toJson() => {'pcr': pcr, 'max_pain': maxPain, 'support': support, 'resistance': resistance, 'read': read};
}

OiReport? analyzeOi(String csv) {
  final rows = <List<double>>[];
  for (final line in csv.split(RegExp(r'[\r\n;]+'))) {
    final v = line.split(RegExp(r'[,\t ]+')).map(double.tryParse).toList();
    if (v.length >= 3 && v.take(3).every((x) => x != null)) rows.add([for (final x in v) x ?? 0]);
  }
  if (rows.length < 3) return null;
  final ce = rows.fold(0.0, (a, r) => a + r[1]), pe = rows.fold(0.0, (a, r) => a + r[2]);
  final sup = rows.reduce((a, b) => b[2] > a[2] ? b : a)[0];
  final res = rows.reduce((a, b) => b[1] > a[1] ? b : a)[0];
  double pain(double k) => rows.fold(0.0, (a, r) => a + r[1] * math.max(0, k - r[0]) + r[2] * math.max(0, r[0] - k));
  final mp = rows.map((r) => r[0]).reduce((a, b) => pain(a) <= pain(b) ? a : b);
  final pcr = ce == 0 ? 0.0 : pe / ce;
  final read = pcr > 1.2 ? 'Put writers dominant (supportive) — confirm with price structure.'
      : pcr < 0.8 ? 'Call writers dominant (capping) — confirm with price structure.'
      : 'Balanced OI — no edge from OI alone.';
  return OiReport(pcr, mp, sup, res, read);
}

/// Turns the AI's chart reading (JSON, values may be null) into a confluence
/// verdict with the same rules as [analyzeCandles]. Missing values lower the
/// score; nothing is filled in.
({String verdict, int score, List<String> reasons, Map<String, dynamic> read}) judgeChartReading(String json) {
  Map<String, dynamic> j;
  try {
    final start = json.indexOf('{'), end = json.lastIndexOf('}');
    j = Map<String, dynamic>.from(jsonDecodeSafe(json.substring(start, end + 1)));
  } catch (_) {
    return (verdict: 'UNREADABLE', score: 0, reasons: ['The AI reply was not valid JSON.'], read: const {});
  }
  if (j['readable'] != true) {
    return (verdict: 'NO TRADE', score: 0, reasons: ['Chart not readable: ${j['notes'] ?? ''}'], read: j);
  }
  double? n(String k) => j[k] is num ? (j[k] as num).toDouble() : null;
  final px = n('last_price');
  var bull = 0, bear = 0, possible = 0;
  final why = <String>[];
  void vote(String name, double? v, int w) {
    possible += w;
    if (px == null || v == null) {
      why.add('$name not visible');
      return;
    }
    if (px > v) {
      bull += w;
    } else {
      bear += w;
    }
    why.add('Price ${px > v ? 'above' : 'below'} $name');
  }

  vote('EMA9', n('ema9'), 20);
  vote('MA9', n('ma9'), 15);
  vote('VWAP', n('vwap'), 20);
  possible += 25;
  if (j['supertrend_dir'] == 'up') {
    bull += 25;
    why.add('Supertrend up');
  } else if (j['supertrend_dir'] == 'down') {
    bear += 25;
    why.add('Supertrend down');
  } else {
    why.add('Supertrend not visible');
  }
  possible += 20;
  if (j['trend'] == 'up') bull += 20;
  if (j['trend'] == 'down') bear += 20;
  final score = ((math.max(bull, bear) / possible) * 100).round();
  final verdict = score < 70 ? 'NO TRADE' : bull > bear ? 'BULLISH (CE) candidate' : 'BEARISH (PE) candidate';
  if (score < 70) why.add('Confluence $score < 70 → NO TRADE');
  return (verdict: verdict, score: score, reasons: why, read: j);
}

dynamic jsonDecodeSafe(String s) => const JsonDecoder().convert(s);
