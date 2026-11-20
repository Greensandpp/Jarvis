// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      _time = TextEditingController(), _journal = TextEditingController();
  String _instrument = 'NIFTY';
  String _gate = '', _audit = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _journal.text = p.getString(journalKey) ?? '');
    });
  }

  @override
  void dispose() {
    for (final c in [_entry, _sl, _conf, _time, _journal]) {
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
    );
    setState(() => _gate = evaluateTrade(s, TradingRules()).describe());
  }

  Future<void> _analyze() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(journalKey, _journal.text);
    setState(() => _audit = analyzeJournal(_journal.text, TradingRules()).describe());
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
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('t-check'), onPressed: _check, child: const Text('Check against GreenSoil rules')),
        if (_gate.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_gate, key: const ValueKey('t-gate'))),
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
