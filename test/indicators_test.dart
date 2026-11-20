import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/trading/indicators.dart';

String trend(bool up) {
  final b = StringBuffer();
  var p = 100.0;
  for (var i = 0; i < 40; i++) {
    // Impulse of 3 candles, pullback of 2: real swings with a net trend.
    final step = i % 5 < 3 ? 2.0 : -1.5;
    p += up ? step : -step;
    b.writeln('09:${(15 + i) % 60},${p - 0.3},${p + 1},${p - 1},$p,${1000 + i * 10}');
  }
  return b.toString();
}

void main() {
  test('EMA / SMA basics', () {
    expect(ema([1, 1, 1, 1], 9).last, closeTo(1, 1e-9));
    final s = sma([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 9);
    expect(s[7], isNull);
    expect(s[8], 5);
    expect(s[9], 6);
  });

  test('uptrend → bullish, supertrend up, above VWAP', () {
    final c = parseCandles(trend(true));
    expect(c.length, 40);
    final r = analyzeCandles(c);
    expect(r.supertrendUp, isTrue);
    expect(r.bias, 'BULLISH (CE)');
    expect(r.close > r.vwap!, isTrue);
    expect(r.tradeable, isTrue);
  });

  test('downtrend → bearish', () {
    final r = analyzeCandles(parseCandles(trend(false)));
    expect(r.bias, 'BEARISH (PE)');
    expect(r.supertrendUp, isFalse);
  });

  test('choppy data → NO TRADE', () {
    final b = StringBuffer();
    for (var i = 0; i < 30; i++) {
      final p = 100 + (i.isEven ? 1.0 : -1.0);
      b.writeln('$p,${p + 1},${p - 1},${i % 4 < 2 ? p + 0.5 : p - 0.5},1000');
    }
    final r = analyzeCandles(parseCandles(b.toString()));
    expect(r.tradeable, isFalse);
    expect(r.describe(), contains('NO TRADE'));
  });

  test('malformed rows are rejected, not guessed', () {
    expect(parseCandles('t,10,9,11,10,1\nfoo\n'), isEmpty); // high < open
  });

  test('OI: PCR, max pain, support/resistance', () {
    final r = analyzeOi('24000,100,500\n24100,300,400\n24200,600,200\n24300,900,50')!;
    expect(r.support, 24000);
    expect(r.resistance, 24300);
    expect(r.pcr, closeTo(1150 / 1900, 1e-9));
    expect(analyzeOi('1,2'), isNull);
  });

  test('chart reading: visible values drive the verdict, missing ones lower confidence', () {
    final full = judgeChartReading('{"readable":true,"last_price":150,"ema9":148,"ma9":147,"vwap":145,'
        '"supertrend_dir":"up","trend":"up","notes":""}');
    expect(full.verdict, 'BULLISH (CE) candidate');
    expect(full.score, 100);
    final sparse = judgeChartReading('Here: {"readable":true,"last_price":150,"ema9":null,"ma9":null,"vwap":null,'
        '"supertrend_dir":null,"trend":"up"}');
    expect(sparse.verdict, 'NO TRADE');
    expect(sparse.reasons.join(), contains('EMA9 not visible'));
    expect(judgeChartReading('{"readable":false,"notes":"blurry"}').verdict, 'NO TRADE');
    expect(judgeChartReading('no json').verdict, 'UNREADABLE');
  });
}
