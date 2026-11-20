// ignore: deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/ai_service.dart';
import '../../trading/indicators.dart';
import '../../trading/journal_analyzer.dart';
import '../../trading/risk_engine.dart';

/// GreenSoil Trading AI (PAPER ONLY): deterministic risk gate and journal audit.
/// Never places orders, edits Pine scripts or touches PB7/Railway/Telegram.
class TradingAiScreen extends StatefulWidget {
  const TradingAiScreen({super.key});
  @override
  State<TradingAiScreen> createState() => _TradingAiScreenState();
}

class _TradingAiScreenState extends State<TradingAiScreen> {
  static const journalKey = 'trading_journal_csv_v1';
  final _entry = TextEditingController(), _sl = TextEditingController(), _conf = TextEditingController(),
      _time = TextEditingController(), _journal = TextEditingController(),
      _loss = TextEditingController(text: '0'), _open = TextEditingController(text: '0'),
      _candles = TextEditingController(), _oi = TextEditingController();
  String _instrument = 'NIFTY';
  String _gate = '', _audit = '', _ind = '', _oiOut = '', _chart = '';
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _journal.text = p.getString(journalKey) ?? '');
    });
  }

  @override
  void dispose() {
    for (final c in [_entry, _sl, _conf, _time, _journal, _loss, _open, _candles, _oi]) {
      c.dispose();
    }
    super.dispose();
  }

  void _check() {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(_time.text);
    final s = TradeSetup(
      instrument: _instrument,
      entry: double.tryParse(_entry.text) ?? 0,
      stopLoss: double.tryParse(_sl.text) ?? 0,
      confidence: double.tryParse(_conf.text) ?? 0,
      entryMinutesIst: m == null ? -1 : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!),
      candleClosed: true, htfConfirmed: true, quoteAgeSeconds: 0,
      realizedLossToday: double.tryParse(_loss.text) ?? 0,
      openPositions: int.tryParse(_open.text) ?? 0,
    );
    setState(() => _gate = evaluateTrade(s, TradingRules()).describe());
  }

  Future<void> _analyze() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(journalKey, _journal.text);
    setState(() => _audit = analyzeJournal(_journal.text, TradingRules()).describe());
  }

  void _indicators() {
    final c = parseCandles(_candles.text);
    setState(() => _ind = c.length < 10
        ? 'Need at least 10 valid candles (time,open,high,low,close,volume). Found ${c.length}. Nothing was invented.'
        : analyzeCandles(c).describe());
  }

  void _oiRun() {
    final r = analyzeOi(_oi.text);
    setState(() => _oiOut = r == null ? 'Need at least 3 rows: strike,ce_oi,pe_oi' : r.describe());
  }

  Future<void> _readChart() async {
    final blocked = AiService.instance.aiBlockedReason;
    if (blocked != null) {
      setState(() => _chart = 'Chart reading needs the AI brain: $blocked');
      return;
    }
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (img == null) return;
    setState(() {
      _reading = true;
      _chart = 'Reading chart…';
    });
    try {
      final raw = await AiService.instance.readTradingChart(base64Encode(await img.readAsBytes()));
      final j = judgeChartReading(raw);
      final read = j.read;
      setState(() => _chart = [
            '${j.verdict} · confluence ${j.score}/100 (from values visible on the screenshot)',
            if (read.isNotEmpty) 'Read: ${read['instrument'] ?? '?'} ${read['timeframe'] ?? ''} · price ${read['last_price'] ?? 'n/a'} · '
                'EMA9 ${read['ema9'] ?? 'n/a'} · MA9 ${read['ma9'] ?? 'n/a'} · VWAP ${read['vwap'] ?? 'n/a'} · '
                'Supertrend ${read['supertrend_dir'] ?? 'n/a'}',
            ...j.reasons.map((r) => '• $r'),
            if ('${read['notes'] ?? ''}'.isNotEmpty) 'AI notes: ${read['notes']}',
            'Verify every value on the chart yourself, then run the risk gate above. Paper only.',
          ].join('\n'));
    } catch (e) {
      setState(() => _chart = 'Chart reading failed: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Widget _field(TextEditingController c, String label, {bool number = true, Key? key}) => TextField(
        key: key, controller: c,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trading AI (paper only)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('🛡 PAPER ONLY. JARVIS never places orders, edits Pine scripts, changes the PB7 bot, deploys, '
          'or writes to production. Rules: entries after 09:30 IST on a confirmed 5-minute close, ≥70% confidence, '
          '≤ ₹1,200 risk per entry incl. fees, ₹3,000 daily stop, one position across NIFTY/SENSEX.',
          style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        const Text('Risk gate', style: TextStyle(fontWeight: FontWeight.w700)),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'NIFTY', label: Text('NIFTY')), ButtonSegment(value: 'SENSEX', label: Text('SENSEX'))],
          selected: {_instrument}, onSelectionChanged: (s) => setState(() => _instrument = s.first)),
        _field(_entry, 'Entry premium', key: const ValueKey('t-entry')),
        _field(_sl, 'Stop-loss premium', key: const ValueKey('t-sl')),
        _field(_conf, 'Confidence %', key: const ValueKey('t-conf')),
        _field(_time, 'Signal 5-min close time HH:MM (IST)', number: false, key: const ValueKey('t-time')),
        Row(children: [
          Expanded(child: _field(_loss, 'Loss booked today ₹', key: const ValueKey('t-loss'))),
          const SizedBox(width: 12),
          Expanded(child: _field(_open, 'Open positions', key: const ValueKey('t-open'))),
        ]),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('t-check'), onPressed: _check, child: const Text('Check against GreenSoil rules')),
        if (_gate.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_gate, key: const ValueKey('t-gate'))),
        const Divider(height: 32),
        const Text('Chart screenshot (TradingView / broker)', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text('Gemini reads only the values visible on your screenshot; missing values lower confidence and are never guessed.',
            style: TextStyle(fontSize: 12)),
        OutlinedButton.icon(key: const ValueKey('t-chart'), onPressed: _reading ? null : _readChart,
            icon: const Icon(Icons.image_search), label: const Text('Pick chart screenshot')),
        if (_chart.isNotEmpty) SelectableText(_chart, key: const ValueKey('t-chart-report')),
        const Divider(height: 32),
        const Text('Indicators from candles (EMA9, MA9, VWAP, Supertrend, structure)', style: TextStyle(fontWeight: FontWeight.w700)),
        TextField(key: const ValueKey('t-candles'), controller: _candles, maxLines: 5, minLines: 3,
            decoration: const InputDecoration(hintText: 'time,open,high,low,close,volume — oldest first (e.g. TradingView export)')),
        FilledButton(key: const ValueKey('t-ind'), onPressed: _indicators, child: const Text('Analyse candles')),
        if (_ind.isNotEmpty) SelectableText(_ind, key: const ValueKey('t-ind-report')),
        const Divider(height: 32),
        const Text('Option chain OI', style: TextStyle(fontWeight: FontWeight.w700)),
        TextField(key: const ValueKey('t-oi'), controller: _oi, maxLines: 4, minLines: 2,
            decoration: const InputDecoration(hintText: 'strike,ce_oi,pe_oi per line')),
        FilledButton(key: const ValueKey('t-oi-run'), onPressed: _oiRun, child: const Text('Analyse OI')),
        if (_oiOut.isNotEmpty) SelectableText(_oiOut, key: const ValueKey('t-oi-report')),
        const Divider(height: 32),
        const Text('Trade journal audit', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text('Paste your journal CSV (needs entry and exit columns). Stored only on this phone.', style: TextStyle(fontSize: 12)),
        TextField(key: const ValueKey('t-journal'), controller: _journal, maxLines: 6, minLines: 3,
          decoration: const InputDecoration(hintText: 'Date,Entry Time,Exit Time,Symbol,Side,Entry,Exit,SL,Qty,PnL,Fees,Confidence')),
        FilledButton(key: const ValueKey('t-audit'), onPressed: _analyze, child: const Text('Find errors in my journal')),
        if (_audit.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_audit, key: const ValueKey('t-report'))),
        const Divider(height: 32),
        const Text('Not connected: live market data / OI / bid-ask feed, PB7 PAPER bot status, Telegram reports. '
          'They show NOT CONNECTED until a read-only source is configured.', style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}
