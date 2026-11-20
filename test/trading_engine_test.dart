import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/trading/journal_analyzer.dart';
import 'package:private_agent/trading/risk_engine.dart';

TradeSetup good() => TradeSetup(entry: 120, stopLoss: 110, confidence: 78, entryMinutesIst: 10 * 60 + 15,
    candleClosed: true, htfConfirmed: true, quoteAgeSeconds: 5);

void main() {
  final rules = TradingRules();

  test('valid setup is sized within ₹1,200 with TP1–TP8 (paper only)', () {
    final d = evaluateTrade(good(), rules);
    expect(d.trade, isTrue, reason: d.reasons.join(';'));
    expect(d.lots, 1);
    expect(d.quantity, 75);
    expect(d.estimatedRisk, lessThanOrEqualTo(1200));
    expect(d.targets.first, 130);
    expect(d.targets.last, 180);
    expect(d.toJson()['paper_only'], true);
  });

  test('every GreenSoil rule blocks independently', () {
    void blocked(TradeSetup s, String why) {
      final d = evaluateTrade(s, rules);
      expect(d.trade, isFalse);
      expect(d.reasons.join(';'), contains(why));
    }
    blocked(good()..entryMinutesIst = 9 * 60 + 25, '09:30');
    blocked(good()..candleClosed = false, '5-minute');
    blocked(good()..confidence = 69, 'below 70');
    blocked(good()..quoteAgeSeconds = -1, 'freshness unknown');
    blocked(good()..quoteAgeSeconds = 300, 'stale');
    blocked(good()..openPositions = 1, 'already open');
    blocked(good()..realizedLossToday = 3000, 'Daily hard-loss');
    blocked(good()..stopLoss = 100, 'too wide');
    blocked(good()..stopLoss = 125, 'wrong side');
    blocked(good()..instrument = 'BANKNIFTY', 'Only NIFTY');
  });

  test('journal audit finds duplicates, timing, confidence, risk and overlap problems', () {
    const csv = 'Date,Entry Time,Exit Time,Symbol,Side,Entry,Exit,SL,Qty,PnL,Fees,Confidence\n'
        '2026-11-17,09:20,09:40,NIFTY,LONG,100,110,90,75,710,40,80\n'
        '2026-11-17,10:00,10:30,NIFTY,LONG,120,100,100,75,-1540,40,65\n'
        '2026-11-17,10:15,10:45,SENSEX,LONG,300,320,290,20,900,40,75\n'
        '2026-11-17,10:15,10:45,SENSEX,LONG,300,320,290,20,900,40,75\n';
    final r = analyzeJournal(csv, rules);
    expect(r.trades, 3);
    expect(r.errors.join(';'), contains('duplicate'));
    expect(r.errors.join(';'), contains('does not match'));
    final v = r.violations.join(';');
    expect(v, contains('before 09:30'));
    expect(v, contains('< 70%'));
    expect(v, contains('planned risk'));
    expect(v, contains('overlapped'));
    expect(r.describe(), contains('do not predict'));
  });
}
