import 'risk_engine.dart';

/// Audits a trade journal CSV (flexible headers): performance, data errors,
/// GreenSoil rule violations and hypotheses to test with paper/walk-forward
/// data. Describes the past only; it never predicts profit.
class JournalReport {
  int trades = 0, wins = 0, losses = 0;
  double net = 0, avgWin = 0, avgLoss = 0, maxDrawdown = 0, fees = 0, giveback = 0;
  double? profitFactor;
  final errors = <String>[], violations = <String>[], hypotheses = <String>[];
  double get winRate => trades == 0 ? 0 : 100 * wins / trades;

  String describe() {
    final b = StringBuffer()
      ..writeln('$trades trades · win rate ${winRate.toStringAsFixed(1)}% · net ₹${net.round()} · max drawdown ₹${maxDrawdown.round()}');
    if (errors.isNotEmpty) { b.writeln('Data errors:'); for (final e in errors) b.writeln('• $e'); }
    if (violations.isNotEmpty) { b.writeln('Rule violations:'); for (final v in violations) b.writeln('• $v'); }
    if (hypotheses.isNotEmpty) { b.writeln('Hypotheses to test (paper / walk-forward):'); for (final h in hypotheses) b.writeln('• $h'); }
    b.write('Statistics describe past trades only; they do not predict future results.');
    return b.toString();
  }
}

const _aliases = {
  'date': ['date', 'day', 'trade_date'],
  'entry_time': ['entry_time', 'time', 'entrytime', 'in_time'],
  'exit_time': ['exit_time', 'exittime', 'out_time'],
  'instrument': ['instrument', 'symbol', 'index', 'underlying'],
  'side': ['side', 'direction', 'type'],
  'entry': ['entry', 'entry_price', 'buy', 'buy_price'],
  'exit': ['exit', 'exit_price', 'sell', 'sell_price'],
  'sl': ['sl', 'stop', 'stop_loss', 'stoploss'],
  'qty': ['qty', 'quantity', 'size'],
  'pnl': ['pnl', 'p&l', 'profit', 'net_pnl'],
  'fees': ['fees', 'charges', 'brokerage'],
  'confidence': ['confidence', 'conf', 'score'],
  'mfe': ['mfe', 'max_favorable', 'peak'],
};

List<String> _split(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var q = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (q && i + 1 < line.length && line[i + 1] == '"') { cur.write('"'); i++; } else { q = !q; }
    } else if (c == ',' && !q) {
      out.add(cur.toString().trim()); cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(cur.toString().trim());
  return out;
}

int _minutes(String t) {
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
  return m == null ? -1 : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

double? _num(String s) => double.tryParse(s.replaceAll('₹', '').replaceAll(',', '').trim());

JournalReport analyzeJournal(String csv, TradingRules rules) {
  final r = JournalReport();
  final lines = csv.replaceAll('\r', '').split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) { r.errors.add('Journal has no data rows.'); return r; }
  final header = _split(lines.first);
  final col = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final h = header[i].toLowerCase().replaceAll(' ', '_');
    _aliases.forEach((k, v) { if (v.contains(h)) col.putIfAbsent(k, () => i); });
  }
  for (final need in ['entry', 'exit']) {
    if (!col.containsKey(need)) r.errors.add('Missing column: $need');
  }
  final seen = <String>{};
  final dayLoss = <String, double>{};
  final windows = <(String, int, int)>[];
  double grossWin = 0, grossLoss = 0, peak = 0, equity = 0;
  var earlyExits = 0, lowConf = 0;
  for (var li = 1; li < lines.length; li++) {
    final f = _split(lines[li]);
    String g(String k) => col.containsKey(k) && col[k]! < f.length ? f[col[k]!] : '';
    final row = li + 1;
    final date = g('date'), inst = g('instrument').toUpperCase(), side = g('side').toUpperCase();
    final em = _minutes(g('entry_time')), xm = _minutes(g('exit_time'));
    final entry = _num(g('entry')), exit = _num(g('exit')), sl = _num(g('sl')), qty = _num(g('qty'));
    final pnlRec = _num(g('pnl')), fee = _num(g('fees')) ?? 0, conf = _num(g('confidence')), mfe = _num(g('mfe'));
    final id = '$date|$em|$inst|$entry|$qty';
    if (!seen.add(id)) { r.errors.add('Row $row: duplicate of an earlier trade (excluded from stats).'); continue; }
    if (entry == null || exit == null) { r.errors.add('Row $row: entry or exit price missing.'); continue; }
    if (em >= 0 && xm >= 0 && xm < em) r.errors.add('Row $row: exit time is before entry time.');
    final isShort = side.startsWith('S');
    final computed = qty == null ? null : (isShort ? entry - exit : exit - entry) * qty - fee;
    final pnl = pnlRec ?? computed;
    if (pnl == null) { r.errors.add('Row $row: cannot compute P&L (no qty or pnl).'); continue; }
    if (pnlRec != null && computed != null && (pnlRec - computed).abs() > [50.0, computed.abs() * .05].reduce((a, b) => a > b ? a : b)) {
      r.errors.add('Row $row: recorded P&L ${pnlRec.round()} does not match prices × qty − fees (${computed.round()}).');
    }
    r.trades++; r.fees += fee; r.net += pnl; equity += pnl;
    if (equity > peak) peak = equity;
    if (peak - equity > r.maxDrawdown) r.maxDrawdown = peak - equity;
    if (pnl > 0) { r.wins++; grossWin += pnl; } else { r.losses++; grossLoss += -pnl; }
    if (em >= 0 && em < rules.earliestEntryMinutes) r.violations.add('Row $row: entry before 09:30 IST.');
    if (conf != null && conf < rules.minConfidence) { lowConf++; r.violations.add('Row $row: taken at ${conf.round()}% confidence (< 70%).'); }
    if (sl != null && qty != null) {
      final risk = (entry - sl).abs() * qty + fee;
      if (risk > rules.maxRiskPerEntry) r.violations.add('Row $row: planned risk ₹${risk.round()} > ₹${rules.maxRiskPerEntry.round()}.');
    }
    final before = dayLoss[date] ?? 0;
    final after = before - pnl;
    dayLoss[date] = after;
    if (after > rules.dailyHardLoss && before <= rules.dailyHardLoss) r.violations.add('Row $row: daily loss passed ₹${rules.dailyHardLoss.round()} on $date.');
    if (mfe != null && qty != null) {
      final best = (isShort ? entry - mfe : mfe - entry) * qty;
      if (best > 0 && pnl < best) r.giveback += best - (pnl > 0 ? pnl : 0);
      if (best > 0 && pnl > 0 && pnl < .4 * best) earlyExits++;
    }
    if (em >= 0 && xm >= 0) {
      for (final w in windows) {
        if (w.$1 == date && em < w.$3 && w.$2 < xm) {
          r.violations.add('Row $row: overlapped another open position (single-position rule).');
          break;
        }
      }
      windows.add((date, em, xm));
    }
  }
  r.avgWin = r.wins == 0 ? 0 : grossWin / r.wins;
  r.avgLoss = r.losses == 0 ? 0 : grossLoss / r.losses;
  r.profitFactor = grossLoss == 0 ? null : grossWin / grossLoss;
  if (r.trades > 0 && r.avgLoss > r.avgWin && r.winRate < 60) r.hypotheses.add('Average loss exceeds average win: test tighter structural SLs or skipping trades with reward/risk < 1.5.');
  if (r.giveback > (grossWin > 1 ? grossWin : 1) * .3) r.hypotheses.add('Large profit giveback: test moving SL to entry at TP1 and trailing after TP2.');
  if (earlyExits >= 2) r.hypotheses.add('Several exits captured <40% of the move: test holding a runner with a trailing stop.');
  if (lowConf > 0) r.hypotheses.add('Trades below 70% confidence were taken: enforce NO TRADE; compare their results separately.');
  if (r.fees > 0 && r.fees > r.net.abs() * .3) r.hypotheses.add('Fees/slippage are a large share of P&L: test fewer, higher-quality entries.');
  if (r.trades < 30) r.hypotheses.add('Only ${r.trades} trades: too few for reliable conclusions; validate any change with walk-forward and paper trading.');
  return r;
}
