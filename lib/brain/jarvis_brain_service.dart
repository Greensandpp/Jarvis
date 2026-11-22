import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/build_profile.dart';
import '../models/task_history_entry.dart';
import '../services/ai_service.dart';
import '../services/hybrid_conversation_context.dart';
import '../services/local_brain/local_brain_service.dart';
import '../services/app_launcher_service.dart';
import '../services/calendar_reminder_service.dart';
import '../services/conversational_memory_service.dart';
import '../services/jarvis_tools_service.dart';
import '../services/message_drafting_service.dart';
import '../services/notes_knowledge_service.dart';
import '../services/settings_service.dart';
import '../services/system_control_service.dart';
import '../services/task_executor.dart';
import '../services/todo_service.dart';
import '../trading/indicators.dart';
import '../trading/journal_analyzer.dart';
import '../trading/risk_engine.dart';
import 'brain.dart';
import 'language.dart';
import 'local_intents.dart';
import 'semantic_memory.dart';
import 'visual_bus.dart';

/// Wires the tool-calling brain to the original JARVIS services.
class JarvisBrainService {
  JarvisBrainService._();
  static final JarvisBrainService instance = JarvisBrainService._();

  static const auditKey = 'jarvis_brain_audit_v1';

  late final JarvisBrain brain = JarvisBrain(
    tools: buildTools(),
    chat: (m, t) => AiService.instance.chatWithTools(m, tools: t),
  );

  ReplyLanguage lastLanguage = ReplyLanguage.english;

  bool get hasPending => brain.pending != null;
  void cancel() { brain.cancel(); LocalBrainService.instance.cancel(); }

  /// Main entry for voice and text. Returns the reply to speak/show.
  Future<BrainResult> handle(String text) async {
    final settings = SettingsService.instance;
    lastLanguage = resolveReplyLanguage(settings.replyLanguage, text);

    // 1. Pending approval: "yes" runs it, "no" drops it, anything else drops it too.
    if (brain.pending != null) {
      if (isYes(text)) return _finish(text, await brain.resolvePending(approved: true));
      if (isNo(text)) {
        final p = brain.pending!;
        if (p.tool.name == 'memory_suggestion_approve') {
          await ConversationalMemoryService.instance.dismissSuggestion('${p.args['id']}');
        }
        return _finish(text, await brain.resolvePending(approved: false));
      }
      brain.pending = null;
    }

    // 2. Offline shortcuts (work without AI / internet).
    final local = await LocalIntents.handle(text, lastLanguage);
    if (local != null) return _finish(text, BrainResult(local, const [], usedAi: false));

    // Chat-only local inference takes no cloud credentials and cannot execute tools.
    final phone = LocalBrainService.instance;
    await phone.initialize();
    if (phone.ready) {
      final language = switch (lastLanguage) {
        ReplyLanguage.tamil => 'ta-IN', ReplyLanguage.tanglish => 'ta-Latn', _ => 'en-IN',
      };
      try {
        final reply = await phone.replyAnswer(text, language);
        return await _finish(text, BrainResult(reply.display, const [], usedAi: true,
          speechText: reply.speech, speechLocale: reply.locale));
      } on LocalBrainInterrupted { throw BrainCancelled(); }
      catch (_) { return _finish(text, BrainResult('Phone-local AI could not complete this reply. ${phone.status}', const [], usedAi: false)); }
    }

    // 3. Open-ended reasoning with tools.
    final blocked = AiService.instance.aiBlockedReason;
    if (blocked != null) {
      return _finish(text, BrainResult('$blocked ${LocalIntents.offlineHelp(lastLanguage)}', const [], usedAi: false));
    }
    final memory = ConversationalMemoryService.instance;
    await memory.init();
    final recalled = await SemanticMemory.instance.recall(text, memory.facts, limit: 6);
    final history = memory.persistedHistory.length > 12
        ? memory.persistedHistory.sublist(memory.persistedHistory.length - 12)
        : memory.persistedHistory;
    final system = JarvisBrain.systemPrompt(
      language: lastLanguage,
      memories: recalled.map((f) => f.fact).toList(),
      now: DateFormat('EEE d MMM yyyy, HH:mm').format(DateTime.now()),
      tools: brain.tools,
    );
    final r = await brain.run(
      userText: text,
      history: [for (final h in history) {'role': h['role'] ?? 'user', 'content': h['content'] ?? ''}],
      system: '$system\nRecent conversation from another voice engine (context only):\n${HybridConversationContext.instance.prompt}',
    );
    return _finish(text, r);
  }

  Future<BrainResult> _finish(String text, BrainResult r) async {
    HybridConversationContext.instance.addTurn(text, r.reply);
    await _persistAudit();
    final mem = ConversationalMemoryService.instance;
    mem.lastNewSuggestion = null;
    // recordTurn performs the original "remember that…" capture (explicit =
    // approved) and turns implicit statements into suggestions.
    await mem.recordTurn(text, r.reply);
    final sug = mem.lastNewSuggestion;
    if (sug != null && brain.pending == null && r.pending == null) {
      final t = brain.tool('memory_suggestion_approve')!;
      brain.pending = PendingApproval(t, {'id': sug.id}, 'Shall I remember "${sug.fact}"?', text);
      return BrainResult('${r.reply} Shall I remember "${sug.fact}"? Say yes or no.'.trim(), r.steps,
          pending: brain.pending, usedAi: r.usedAi);
    }
    return r;
  }

  Future<void> _persistAudit() async {
    final p = await SharedPreferences.getInstance();
    final all = brain.audit.length > 200 ? brain.audit.sublist(brain.audit.length - 200) : brain.audit;
    await p.setString(auditKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<List<Map<String, dynamic>>> loadAudit() async {
    final p = await SharedPreferences.getInstance();
    try {
      return (jsonDecode(p.getString(auditKey) ?? '[]') as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static bool isYes(String t) => RegExp(
          r"^\s*(yes|yeah|yep|ok|okay|sure|confirm|go ahead|do it|proceed|approve|seri|sari|aamaa|aama|ஆமா|ஆம்|சரி|pannu)(?=$|[\s.,!?])",
          caseSensitive: false)
      .hasMatch(t);
  static bool isNo(String t) => RegExp(
          r"^\s*(no|nope|cancel|stop|don't|do not|vendam|venaam|illa|வேண்டாம்|இல்லை)(?=$|[\s.,!?])",
          caseSensitive: false)
      .hasMatch(t);

  static Map<String, dynamic> _p(String type, String desc, {List<String>? values}) =>
      {'type': type, 'description': desc, if (values != null) 'enum': values};

  static String _s(Map<String, dynamic> a, String k) => '${a[k] ?? ''}'.trim();
  static double? _d(Map<String, dynamic> a, String k) => a[k] is num ? (a[k] as num).toDouble() : double.tryParse(_s(a, k));

  /// The tool catalog. Every tool wraps an original JARVIS service.
  static List<ToolSpec> buildTools() {
    final full = BuildProfile.fullControl;
    return [
      // ── Commander ────────────────────────────────────────────────────
      ToolSpec(
        name: 'switch_visual',
        description: 'Change the JARVIS visual mode, optionally the AIRA model.',
        parameters: {
          'mode': _p('string', 'Visual mode', values: visualModes),
          'aira_model': _p('string', 'AIRA model name (only for aira)', values: const [
            'neuralReactor', 'amberHologram', 'electricWeb', 'aiHead', 'jellyfish', 'violetVortex', 'auroraRibbon',
            'dnaHelix', 'crystalBloom', 'solarFlare',
          ]),
        },
        required: const ['mode'],
        agent: JarvisAgent.commander,
        run: (a) async {
          final m = _s(a, 'mode');
          if (!visualModes.contains(m)) return ToolResult.fail('Unknown mode "$m".');
          final model = _s(a, 'aira_model');
          await requestVisual(mode: m, airaModel: model.isEmpty ? null : model);
          final p = await SharedPreferences.getInstance();
          final saved = p.getString('jarvis_visual_mode_v1') == m;
          return ToolResult(saved, saved ? 'Visual switched to $m${model.isEmpty ? '' : ' ($model)'}.' : 'Could not save mode.',
              verified: saved);
        },
      ),
      ToolSpec(
        name: 'set_reply_language',
        description: 'Set the reply language: auto follows the user; or always english / tamil / tanglish.',
        parameters: {'language': _p('string', 'Language', values: const ['auto', 'english', 'tamil', 'tanglish'])},
        required: const ['language'],
        agent: JarvisAgent.commander,
        run: (a) async {
          await SettingsService.instance.setReplyLanguage(_s(a, 'language'));
          final ok = SettingsService.instance.replyLanguage == _s(a, 'language');
          return ToolResult(ok, ok ? 'Reply language set to ${_s(a, 'language')}.' : 'Unsupported language.', verified: ok);
        },
      ),
      ToolSpec(
        name: 'set_voice',
        description: 'Voice settings: prefer a female voice, speech input language (en-IN / ta-IN).',
        parameters: {
          'female': _p('boolean', 'Prefer a female voice'),
          'speech_input_locale': _p('string', 'Microphone language', values: const ['en-IN', 'ta-IN', 'en-GB']),
        },
        agent: JarvisAgent.commander,
        run: (a) async {
          final s = SettingsService.instance;
          if (a['female'] is bool) await s.setPreferFemaleVoice(a['female'] as bool);
          final loc = _s(a, 'speech_input_locale');
          if (loc.isNotEmpty) await s.setSpeechInputLocale(loc);
          return ToolResult(true, 'Voice: ${s.preferFemaleVoice ? 'female' : 'default'} voice, mic ${s.speechInputLocale}.',
              verified: true);
        },
      ),
      ToolSpec(
        name: 'ai_status',
        description: 'Report the verified AI connection status and model.',
        agent: JarvisAgent.commander,
        run: (a) async => ToolResult(true, SettingsService.instance.aiStatusLabel, verified: true),
      ),
      // ── Researcher ───────────────────────────────────────────────────
      ToolSpec(
        name: 'web_search',
        description: 'Search the web for current information.',
        parameters: {'query': _p('string', 'Search query')},
        required: const ['query'],
        agent: JarvisAgent.researcher,
        run: (a) async {
          final r = await JarvisToolsService.instance.searchWeb(_s(a, 'query'));
          final locked = r.startsWith('Privacy Lock');
          return ToolResult(!locked && r.trim().isNotEmpty, r, verified: !locked);
        },
      ),
      ToolSpec(
        name: 'news',
        description: 'Latest news headlines, optionally on a topic.',
        parameters: {'topic': _p('string', 'Topic')},
        agent: JarvisAgent.researcher,
        run: (a) async {
          final r = await JarvisToolsService.instance.getLiveNews(_s(a, 'topic').isEmpty ? null : _s(a, 'topic'));
          return ToolResult(!r.startsWith('Privacy Lock'), r);
        },
      ),
      ToolSpec(
        name: 'weather',
        description: 'Current weather for a place.',
        parameters: {'location': _p('string', 'City')},
        required: const ['location'],
        agent: JarvisAgent.researcher,
        run: (a) async {
          final r = await JarvisToolsService.instance.getWeather(_s(a, 'location'));
          return ToolResult(!r.startsWith('Privacy Lock'), r);
        },
      ),
      // ── Operator ─────────────────────────────────────────────────────
      ToolSpec(
        name: 'open_app',
        description: 'Open an installed app by name.',
        parameters: {'app': _p('string', 'App name, e.g. TradingView, WhatsApp, YouTube')},
        required: const ['app'],
        agent: JarvisAgent.operator,
        run: (a) async {
          final r = await AppLauncherService.instance.launch(_s(a, 'app'));
          return r == null ? ToolResult.fail('Could not find or open "${_s(a, 'app')}".') : ToolResult(true, 'Opened $r.', verified: true);
        },
      ),
      ToolSpec(
        name: 'set_alarm',
        description: 'Set an alarm in the clock app.',
        parameters: {'hour': _p('integer', '0-23'), 'minute': _p('integer', '0-59'), 'label': _p('string', 'Label')},
        required: const ['hour', 'minute'],
        agent: JarvisAgent.operator,
        run: (a) async {
          final h = (_d(a, 'hour') ?? -1).toInt(), m = (_d(a, 'minute') ?? -1).toInt();
          if (h < 0 || h > 23 || m < 0 || m > 59) return const ToolResult.fail('Invalid time.');
          final ok = await SystemControlService.instance.setAlarm(hour: h, minute: m, label: _s(a, 'label').isEmpty ? 'JARVIS' : _s(a, 'label'));
          return ok ? ToolResult(true, 'Alarm request sent to the clock app for ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}.')
              : const ToolResult.fail('The clock app did not accept the alarm.');
        },
      ),
      ToolSpec(
        name: 'add_reminder',
        description: 'Add a reminder in JARVIS (local notification). time is ISO-8601 local time.',
        parameters: {'title': _p('string', 'What to remind'), 'time': _p('string', 'ISO-8601 local date-time')},
        required: const ['title'],
        agent: JarvisAgent.operator,
        run: (a) async {
          final t = DateTime.tryParse(_s(a, 'time'));
          final item = await CalendarReminderService.instance.addReminder(_s(a, 'title'), time: t);
          return ToolResult(true, 'Reminder saved: ${item.title} at ${DateFormat('d MMM HH:mm').format(item.dateTime)}.', verified: true);
        },
      ),
      ToolSpec(
        name: 'add_todo',
        description: 'Add a to-do item.',
        parameters: {'title': _p('string', 'Task'), 'priority': _p('string', 'low/medium/high', values: const ['low', 'medium', 'high'])},
        required: const ['title'],
        agent: JarvisAgent.operator,
        run: (a) async {
          final t = await TodoService.instance.addTodo(_s(a, 'title'), priority: _s(a, 'priority').isEmpty ? 'medium' : _s(a, 'priority'));
          return ToolResult(true, 'To-do added: ${t.title}.', verified: true);
        },
      ),
      ToolSpec(
        name: 'notes',
        description: 'Save a note or search notes.',
        parameters: {
          'action': _p('string', 'save or search', values: const ['save', 'search']),
          'title': _p('string', 'Note title'), 'text': _p('string', 'Note text or search query'),
        },
        required: const ['action', 'text'],
        agent: JarvisAgent.operator,
        run: (a) async {
          final n = NotesKnowledgeService.instance;
          if (_s(a, 'action') == 'save') {
            final e = await n.addNote(title: _s(a, 'title'), content: _s(a, 'text'));
            return ToolResult(true, 'Note saved: ${e.title}.', verified: true);
          }
          await n.init();
          final hits = n.searchNotes(_s(a, 'text'));
          return ToolResult(true, hits.isEmpty ? 'No matching notes.' : hits.take(5).map((e) => '${e.title}: ${e.content}').join('\n'));
        },
      ),
      ToolSpec(
        name: 'device_status',
        description: 'Battery level, charging state, date/time and system diagnostics.',
        agent: JarvisAgent.operator,
        run: (a) async {
          final b = await JarvisToolsService.instance.getBatteryStatus();
          final lvl = b['level'] as int? ?? -1;
          return ToolResult(true, '${lvl >= 0 ? 'Battery $lvl%' : 'Battery unknown'}${b['isCharging'] == true ? ', charging' : ''}. '
              '${JarvisToolsService.instance.getCurrentDateTime()}', verified: lvl >= 0);
        },
      ),
      ToolSpec(
        name: 'phone_controls',
        description: 'Volume up/down/mute, torch on/off, media play/pause/next.',
        parameters: {'action': _p('string', 'Action', values: const ['volume_up', 'volume_down', 'mute', 'unmute', 'torch_on', 'torch_off', 'play_pause', 'next', 'previous'])},
        required: const ['action'],
        agent: JarvisAgent.operator,
        run: (a) async {
          final sc = SystemControlService.instance;
          switch (_s(a, 'action')) {
            case 'volume_up': await sc.volumeUp();
            case 'volume_down': await sc.volumeDown();
            case 'mute': await sc.setMuted(true);
            case 'unmute': await sc.setMuted(false);
            case 'torch_on': return ToolResult(await JarvisToolsService.instance.setTorch(true), 'Torch on.');
            case 'torch_off': return ToolResult(await JarvisToolsService.instance.setTorch(false), 'Torch off.');
            case 'play_pause': await sc.togglePlayPause();
            case 'next': await sc.nextTrack();
            case 'previous': await sc.previousTrack();
            default: return const ToolResult.fail('Unknown action.');
          }
          final v = await sc.getVolume();
          return ToolResult(true, 'Done (${_s(a, 'action')}); media volume now ${(v * 100).round()}%.', verified: true);
        },
      ),
      ToolSpec(
        name: 'draft_message',
        description: 'Prepare a WhatsApp/SMS/email draft in that app. The owner reviews and presses send; JARVIS never sends.',
        parameters: {
          'recipient': _p('string', 'Name or number'), 'platform': _p('string', 'whatsapp/sms/email', values: const ['whatsapp', 'sms', 'email']),
          'text': _p('string', 'Message text'),
        },
        required: const ['recipient', 'platform', 'text'],
        agent: JarvisAgent.operator,
        risk: ToolRisk.approval,
        describe: (a) => 'I will open a ${_s(a, 'platform')} draft to ${_s(a, 'recipient')}: "${_s(a, 'text')}" (you press send)',
        run: (a) async {
          await MessageDraftingService.instance.prepareDraft(recipient: _s(a, 'recipient'), platform: _s(a, 'platform'), draftText: _s(a, 'text'));
          return ToolResult(true, 'Draft opened in ${_s(a, 'platform')}. Review it and press send yourself.');
        },
      ),
      ToolSpec(
        name: 'phone_task',
        description: 'Perform a multi-step task inside other apps by reading and tapping the screen (accessibility).',
        parameters: {'goal': _p('string', 'What to do, step by step if possible')},
        required: const ['goal'],
        agent: JarvisAgent.operator,
        risk: ToolRisk.approval,
        available: full,
        unavailableReason: BuildProfile.unavailable('Screen automation'),
        describe: (a) => 'I will operate your screen to: ${_s(a, 'goal')}. I will stop before any payment, OTP or PIN',
        run: (a) async {
          final st = await TaskExecutor.instance.executeTask(_s(a, 'goal'));
          return ToolResult(st == TaskStatus.success, 'Screen task ${st.name}.', verified: st == TaskStatus.success);
        },
      ),
      ToolSpec(
        name: 'payment_or_order',
        description: 'Any money transfer, UPI payment, purchase or live trading order.',
        agent: JarvisAgent.operator,
        risk: ToolRisk.blocked,
        run: (a) async => const ToolResult.fail('Blocked: JARVIS never makes payments or live orders. Do it yourself with OTP/UPI PIN.'),
      ),
      // ── Archivist ────────────────────────────────────────────────────
      ToolSpec(
        name: 'memory_recall',
        description: 'Search long-term memory about the owner.',
        parameters: {'query': _p('string', 'What to look for')},
        required: const ['query'],
        agent: JarvisAgent.archivist,
        run: (a) async {
          final m = ConversationalMemoryService.instance;
          await m.init();
          final hits = await SemanticMemory.instance.recall(_s(a, 'query'), m.facts, limit: 8);
          return ToolResult(true, hits.isEmpty ? 'Nothing remembered about that.' : hits.map((f) => f.fact).join('\n'),
              data: {'count': hits.length}, verified: true);
        },
      ),
      ToolSpec(
        name: 'memory_save',
        description: 'Propose saving a new long-term memory (needs the owner\'s approval).',
        parameters: {'fact': _p('string', 'The fact, in one sentence'), 'category': _p('string', 'preference/personal/work/habit/trading')},
        required: const ['fact'],
        agent: JarvisAgent.archivist,
        risk: ToolRisk.approval,
        describe: (a) => 'I would like to remember: "${_s(a, 'fact')}"',
        run: (a) async {
          final f = await ConversationalMemoryService.instance.addFact(_s(a, 'fact'), category: _s(a, 'category').isEmpty ? 'personal' : _s(a, 'category'));
          return ToolResult(true, 'Remembered: ${f.fact}', verified: true);
        },
      ),
      ToolSpec(
        name: 'memory_suggestion_approve',
        description: 'Internal: approve a suggested memory (only after the owner says yes).',
        parameters: {'id': _p('string', 'Suggestion id')},
        required: const ['id'],
        agent: JarvisAgent.archivist,
        risk: ToolRisk.approval,
        available: false, // never offered to the model; used only by the approval flow
        unavailableReason: 'internal',
        run: (a) async {
          final f = await ConversationalMemoryService.instance.approveSuggestion(_s(a, 'id'));
          return f == null ? const ToolResult.fail('Suggestion no longer exists.') : ToolResult(true, 'Remembered: ${f.fact}', verified: true);
        },
      ),
      ToolSpec(
        name: 'memory_correct',
        description: 'Propose correcting an existing memory (needs approval). old must match the remembered text closely.',
        parameters: {'old': _p('string', 'Existing memory text'), 'new': _p('string', 'Corrected text')},
        required: const ['old', 'new'],
        agent: JarvisAgent.archivist,
        risk: ToolRisk.approval,
        describe: (a) => 'I will change my memory "${_s(a, 'old')}" to "${_s(a, 'new')}" (old version kept)',
        run: (a) async {
          final m = ConversationalMemoryService.instance;
          await m.init();
          final hits = await SemanticMemory.instance.recall(_s(a, 'old'), m.facts, limit: 1);
          if (hits.isEmpty) return const ToolResult.fail('No matching memory to correct.');
          final f = await m.correctFact(hits.first.id, _s(a, 'new'));
          return ToolResult(f != null, 'Corrected: "${hits.first.fact}" → "${f?.fact}"', verified: f != null);
        },
      ),
      // ── Trading Analyst (paper only) ─────────────────────────────────
      ToolSpec(
        name: 'trade_risk_check',
        description: 'Check a NIFTY/SENSEX option trade idea against the GreenSoil rules and size it (paper only).',
        parameters: {
          'instrument': _p('string', 'NIFTY or SENSEX', values: const ['NIFTY', 'SENSEX']),
          'entry': _p('number', 'Option premium entry'), 'stop_loss': _p('number', 'Stop-loss premium'),
          'confidence': _p('number', 'Setup confidence 0-100'), 'time': _p('string', 'Entry time HH:MM IST'),
          'candle_closed': _p('boolean', '5-minute candle closed'), 'htf_confirmed': _p('boolean', 'Higher timeframe confirms'),
          'quote_age_seconds': _p('number', 'Age of the price quote in seconds (-1 unknown)'),
          'open_positions': _p('integer', 'Currently open positions'), 'realized_loss_today': _p('number', 'Loss booked today in ₹'),
        },
        required: const ['instrument', 'entry', 'stop_loss', 'confidence', 'time'],
        agent: JarvisAgent.analyst,
        run: (a) async {
          final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(_s(a, 'time'));
          final d = evaluateTrade(TradeSetup(
            instrument: _s(a, 'instrument').toUpperCase(),
            entry: _d(a, 'entry') ?? 0, stopLoss: _d(a, 'stop_loss') ?? 0, confidence: _d(a, 'confidence') ?? 0,
            entryMinutesIst: m == null ? -1 : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!),
            candleClosed: a['candle_closed'] != false, htfConfirmed: a['htf_confirmed'] != false,
            quoteAgeSeconds: (_d(a, 'quote_age_seconds') ?? -1).toInt(),
            openPositions: (_d(a, 'open_positions') ?? 0).toInt(), realizedLossToday: _d(a, 'realized_loss_today') ?? 0,
          ), TradingRules());
          return ToolResult(true, d.describe(), data: d.toJson(), verified: true);
        },
      ),
      ToolSpec(
        name: 'indicator_analysis',
        description: 'Compute EMA9, MA9, VWAP, Supertrend and market structure from OHLCV candles the owner supplied '
            '(pasted or read from a chart). Never invent candles.',
        parameters: {'candles_csv': _p('string', 'time,open,high,low,close,volume per line, oldest first')},
        required: const ['candles_csv'],
        agent: JarvisAgent.analyst,
        run: (a) async {
          final c = parseCandles(_s(a, 'candles_csv'));
          if (c.length < 10) return const ToolResult.fail('Need at least 10 candles; none were invented.');
          final r = analyzeCandles(c);
          return ToolResult(true, r.describe(), data: r.toJson(), verified: true);
        },
      ),
      ToolSpec(
        name: 'oi_analysis',
        description: 'Summarise an option chain the owner supplied: PCR, max pain, OI support/resistance.',
        parameters: {'chain_csv': _p('string', 'strike,ce_oi,pe_oi per line')},
        required: const ['chain_csv'],
        agent: JarvisAgent.analyst,
        run: (a) async {
          final r = analyzeOi(_s(a, 'chain_csv'));
          return r == null ? const ToolResult.fail('Need at least 3 strikes of OI data; none were invented.')
              : ToolResult(true, r.describe(), data: r.toJson(), verified: true);
        },
      ),
      ToolSpec(
        name: 'journal_audit',
        description: 'Audit the owner\'s saved trading journal for errors and rule violations.',
        agent: JarvisAgent.analyst,
        run: (a) async {
          final p = await SharedPreferences.getInstance();
          final csv = p.getString('trading_journal_csv_v1') ?? '';
          if (csv.trim().isEmpty) return const ToolResult.fail('No journal saved yet. Paste it in Settings → Trading AI.');
          return ToolResult(true, analyzeJournal(csv, TradingRules()).describe(), verified: true);
        },
      ),
      ToolSpec(
        name: 'market_data',
        description: 'Live NIFTY/SENSEX price, option chain, OI, bid/ask.',
        agent: JarvisAgent.analyst,
        available: false,
        unavailableReason: 'NOT CONNECTED: no read-only market-data source is configured, so JARVIS has no live prices or OI',
        run: (a) async => const ToolResult.fail('NOT CONNECTED'),
      ),
    ];
  }
}
