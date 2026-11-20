/// GreenSoil PAPER-ONLY risk gate. The AI may propose; only this decides
/// TRADE vs NO TRADE. It never places orders.
class TradingRules {
  int earliestEntryMinutes = 9 * 60 + 30;   // 09:30 IST
  int lastEntryMinutes = 15 * 60;
  double minConfidence = 70;
  double maxRiskPerEntry = 1200;           // ₹ incl. fees + slippage
  double dailyHardLoss = 3000;             // ₹
  int maxOpenPositions = 1;                // across NIFTY + SENSEX
  int maxQuoteAgeSeconds = 60;
  int niftyLot = 75;                       // verify with NSE
  int sensexLot = 20;                      // verify with BSE
  double brokeragePerOrder = 20;
  double statutoryPct = 0.12;              // % of premium turnover (estimate)
  double slippagePointsPerUnit = 0.5;
  double minRewardRisk = 1.5;
  List<double> ladderR = const [1, 1.5, 2, 2.5, 3, 4, 5, 6];
  final bool paperOnly = true;

  int lot(String instrument) => instrument.toUpperCase() == 'SENSEX' ? sensexLot : niftyLot;
}

class TradeSetup {
  TradeSetup({
    this.instrument = 'NIFTY', this.side = 'LONG', required this.entry, required this.stopLoss,
    required this.confidence, this.entryMinutesIst = -1, this.candleClosed = false,
    this.htfConfirmed = false, this.quoteAgeSeconds = -1, this.realizedLossToday = 0,
    this.openPositions = 0, this.evidence = '',
  });
  String instrument, side, evidence;
  double entry, stopLoss, confidence, realizedLossToday;
  int entryMinutesIst, quoteAgeSeconds, openPositions;
  bool candleClosed, htfConfirmed;
}

class TradeDecision {
  bool trade = false;
  final reasons = <String>[];
  final warnings = <String>[];
  int lots = 0, quantity = 0;
  double riskPerUnit = 0, estimatedRisk = 0, estimatedFees = 0, rewardRiskTp2 = 0;
  final targets = <double>[];
  final trailPlan = <String>[];

  String get verdict => trade ? 'TRADE (PAPER)' : 'NO TRADE';

  Map<String, Object> toJson() => {
        'verdict': verdict, 'reasons': reasons, 'warnings': warnings, 'lots': lots, 'quantity': quantity,
        'risk_per_unit': _r(riskPerUnit), 'estimated_risk_rupees': _r(estimatedRisk),
        'estimated_fees_rupees': _r(estimatedFees), 'reward_risk_tp2': _r(rewardRiskTp2),
        'targets': [for (var i = 0; i < targets.length; i++) {'tp': 'TP${i + 1}', 'price': _r(targets[i])}],
        'trailing_plan': trailPlan, 'paper_only': true,
      };

  String describe() {
    final b = StringBuffer('$verdict\n');
    for (final r in reasons) b.writeln('✗ $r');
    for (final w in warnings) b.writeln('! $w');
    if (lots > 0) {
      b.writeln('Size: $lots lot(s) = $quantity qty · est. risk ₹${estimatedRisk.round()} incl. fees ₹${estimatedFees.round()}');
      b.writeln('Targets: ${[for (var i = 0; i < targets.length; i++) 'TP${i + 1} ${_r(targets[i])}'].join(' · ')}');
      for (final t in trailPlan) b.writeln('• $t');
    }
    return b.toString().trim();
  }

  static double _r(double v) => (v * 100).roundToDouble() / 100;
}

TradeDecision evaluateTrade(TradeSetup s, TradingRules r) {
  final d = TradeDecision();
  final inst = s.instrument.toUpperCase();
  if (inst != 'NIFTY' && inst != 'SENSEX') d.reasons.add('Only NIFTY and SENSEX are supported.');
  if (s.entry <= 0 || s.stopLoss <= 0) d.reasons.add('Entry and stop-loss prices are required.');
  final longPrem = s.side.toUpperCase() != 'SHORT';
  if (s.entry > 0 && s.stopLoss > 0 && (longPrem ? s.stopLoss >= s.entry : s.stopLoss <= s.entry)) {
    d.reasons.add('Stop-loss is on the wrong side of entry.');
  }
  if (s.entryMinutesIst < 0) {
    d.reasons.add('Signal time unknown — cannot confirm the 09:30 IST rule.');
  } else {
    if (s.entryMinutesIst < r.earliestEntryMinutes) d.reasons.add('Before 09:30 IST — no entries yet.');
    if (s.entryMinutesIst > r.lastEntryMinutes) d.reasons.add('Too late in the session for a fresh entry.');
    if (s.entryMinutesIst % 5 != 0) d.warnings.add('Signal time is not on a 5-minute boundary.');
  }
  if (!s.candleClosed) d.reasons.add('Waiting for a confirmed 5-minute candle close.');
  if (!s.htfConfirmed) d.warnings.add('15-minute higher timeframe does not confirm.');
  if (s.confidence < r.minConfidence) {
    d.reasons.add('Confidence ${s.confidence.round()}% is below ${r.minConfidence.round()}%.');
  }
  if (s.quoteAgeSeconds < 0) {
    d.reasons.add('Quote freshness unknown — treat as stale.');
  } else if (s.quoteAgeSeconds > r.maxQuoteAgeSeconds) {
    d.reasons.add('Quote is stale (${s.quoteAgeSeconds}s old).');
  }
  if (s.openPositions >= r.maxOpenPositions) d.reasons.add('A position is already open (limit ${r.maxOpenPositions} across NIFTY/SENSEX).');
  if (s.realizedLossToday >= r.dailyHardLoss) d.reasons.add('Daily hard-loss limit of ₹${r.dailyHardLoss.round()} reached.');

  if (s.entry > 0 && s.stopLoss > 0) {
    final lot = r.lot(inst);
    final gap = (s.entry - s.stopLoss).abs();
    d.riskPerUnit = gap + r.slippagePointsPerUnit;
    final feesPerLot = 2 * r.brokeragePerOrder + (s.entry + s.stopLoss) * lot * r.statutoryPct / 100;
    final perLotRisk = d.riskPerUnit * lot + feesPerLot;
    final budget = [r.maxRiskPerEntry, (r.dailyHardLoss - s.realizedLossToday).clamp(0, double.infinity)].reduce((a, b) => a < b ? a : b);
    d.lots = perLotRisk <= 0 ? 0 : (budget / perLotRisk).floor();
    if (d.lots < 1) {
      d.reasons.add('Stop-loss too wide: one lot risks ₹${perLotRisk.round()} including fees/slippage, above the ₹${budget.round()} budget.');
      d.lots = 0;
    }
    d.quantity = d.lots * lot;
    d.estimatedFees = d.lots == 0 ? 0 : 2 * r.brokeragePerOrder + (s.entry + s.stopLoss) * d.quantity * r.statutoryPct / 100;
    d.estimatedRisk = d.riskPerUnit * d.quantity + d.estimatedFees;
    for (final m in r.ladderR) {
      d.targets.add(longPrem ? s.entry + m * gap : s.entry - m * gap);
    }
    if (d.targets.length >= 2) {
      final rewardTp2 = (d.targets[1] - s.entry).abs() - r.slippagePointsPerUnit;
      d.rewardRiskTp2 = d.riskPerUnit == 0 ? 0 : rewardTp2 / d.riskPerUnit;
      if (d.rewardRiskTp2 < r.minRewardRisk) d.warnings.add('Reward/risk to TP2 below ${r.minRewardRisk}.');
    }
    d.trailPlan.addAll([
      'At TP1: move stop to entry (risk-free).',
      'At TP2: trail stop to TP1.',
      'From TP3: trail one target behind price; exit the rest on a 5-minute close beyond the trail.',
    ]);
  }
  d.trade = d.reasons.isEmpty;
  return d;
}
