import 'dart:convert';

import 'ai_reliability.dart';
import 'language.dart';

/// The five internal JARVIS agents. Every tool belongs to one; the audit log
/// records which agent acted. They share one brain (one model conversation),
/// so "delegation" is the model picking that agent's tools.
enum JarvisAgent { commander, researcher, operator, analyst, archivist }

extension JarvisAgentInfo on JarvisAgent {
  String get title => switch (this) {
        JarvisAgent.commander => 'Commander',
        JarvisAgent.researcher => 'Researcher',
        JarvisAgent.operator => 'Operator',
        JarvisAgent.analyst => 'Trading Analyst',
        JarvisAgent.archivist => 'Archivist',
      };
  String get role => switch (this) {
        JarvisAgent.commander => 'plans, talks to you, changes JARVIS settings and visuals',
        JarvisAgent.researcher => 'web search, news, weather',
        JarvisAgent.operator => 'apps, alarms, reminders, notes, phone controls',
        JarvisAgent.analyst => 'GreenSoil risk gate, indicators, journal audit (paper only)',
        JarvisAgent.archivist => 'long-term memory: recall, proposals, corrections',
      };
}

/// safe: runs immediately · approval: waits for an explicit "yes" ·
/// blocked: never runs (e.g. orders, payments).
enum ToolRisk { safe, approval, blocked }

class ToolResult {
  final bool ok;
  final String summary;
  final Map<String, dynamic> data;
  /// True when the tool checked that its effect really happened (e.g. the app
  /// launcher reported success), not just that it was requested.
  final bool verified;
  const ToolResult(this.ok, this.summary, {this.data = const {}, this.verified = false});
  const ToolResult.fail(this.summary, {this.data = const {}})
      : ok = false,
        verified = false;
  Map<String, dynamic> toJson() => {'ok': ok, 'verified': verified, 'summary': summary, if (data.isNotEmpty) 'data': data};
}

class ToolSpec {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON schema "properties"
  final List<String> required;
  final JarvisAgent agent;
  final ToolRisk risk;
  final bool available;
  final String? unavailableReason;
  final Future<ToolResult> Function(Map<String, dynamic> args) run;
  /// Human description of what will happen, shown/spoken before approval.
  final String Function(Map<String, dynamic> args)? describe;

  const ToolSpec({
    required this.name,
    required this.description,
    this.parameters = const {},
    this.required = const [],
    required this.agent,
    this.risk = ToolRisk.safe,
    this.available = true,
    this.unavailableReason,
    required this.run,
    this.describe,
  });

  Map<String, dynamic> toOpenAi() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': '[${agent.title}] $description',
          'parameters': {'type': 'object', 'properties': parameters, 'required': required},
        },
      };
}

class AuditEntry {
  final DateTime at;
  final String tool;
  final JarvisAgent agent;
  final Map<String, dynamic> args;
  final String outcome; // ok / failed / awaiting approval / approved / declined / blocked / unavailable
  final String summary;
  AuditEntry(this.tool, this.agent, this.args, this.outcome, this.summary) : at = DateTime.now();
  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(), 'tool': tool, 'agent': agent.name, 'args': args, 'outcome': outcome, 'summary': summary,
      };
}

class PendingApproval {
  final ToolSpec tool;
  final Map<String, dynamic> args;
  final String description;
  final String originalRequest;
  PendingApproval(this.tool, this.args, this.description, this.originalRequest);
}

class BrainResult {
  final String reply;
  final List<AuditEntry> steps;
  final PendingApproval? pending;
  final bool usedAi;
  final String? speechText, speechLocale;
  const BrainResult(this.reply, this.steps, {this.pending, this.usedAi = true, this.speechText, this.speechLocale});
}

class BrainCancelled implements Exception {
  @override
  String toString() => 'Request cancelled.';
}

typedef ChatFn = Future<Map<String, dynamic>> Function(
    List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools);

/// Tool-calling brain: plan → call tools → read real results → answer.
/// Open-ended questions go to the model; predefined commands are only offline
/// shortcuts handled before this (see local_intents.dart).
class JarvisBrain {
  JarvisBrain({required this.tools, required this.chat, this.maxSteps = 6});

  final List<ToolSpec> tools;
  final ChatFn chat;
  final int maxSteps;
  final List<AuditEntry> audit = [];
  PendingApproval? pending;
  int _generation = 0;

  /// Device actions (Operator agent) executed recently, keyed by tool + args.
  /// A duplicate request inside [actionDedupWindow] (double speech result,
  /// re-sent command after an AI fallback) returns the first result instead
  /// of acting on the phone twice.
  final Map<String, ({DateTime at, ToolResult result})> _recentActions = {};
  Duration actionDedupWindow = const Duration(seconds: 12);
  DateTime Function() clock = DateTime.now;

  /// Canonical key for a tool call (argument order does not matter).
  static String actionKey(String tool, Map<String, dynamic> args) {
    final keys = args.keys.toList()..sort();
    return '$tool:${jsonEncode({for (final k in keys) k: args[k]})}';
  }

  void cancel() => _generation++;

  ToolSpec? tool(String name) {
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  static String systemPrompt({
    required ReplyLanguage language,
    required List<String> memories,
    required String now,
    String persona = 'You are JARVIS, the owner\'s private assistant on their Android phone.',
    List<ToolSpec> tools = const [],
  }) {
    final unavailable = tools.where((t) => !t.available && t.unavailableReason != 'internal').map((t) => '${t.name}: ${t.unavailableReason}').toList();
    return [
      persona,
      'Current time: $now (IST).',
      languageInstruction(language),
      'You have five internal agents: ${JarvisAgent.values.map((a) => '${a.title} (${a.role})').join('; ')}. '
          'Use their tools when the request needs real data or an action; answer directly when it does not.',
      'Plan multi-step tasks and call tools one after another. Base every factual claim about an action ONLY on '
          'tool results: if a result says ok=false, say it failed and why. Never claim something was done, sent, '
          'opened or saved unless a tool result says so. Never invent market prices, OI or news.',
      'Trading: analysis and PAPER-only plans. You cannot place orders, move money, change Pine scripts, the PB7 '
          'bot, Railway or broker settings. Payments always need the owner to enter OTP/UPI PIN themselves.',
      'Memory changes (save/correct) need the owner\'s approval; propose them with the memory tools.',
      if (memories.isNotEmpty) 'Relevant things you remember about the owner (use only if relevant):\n- ${memories.join('\n- ')}',
      if (unavailable.isNotEmpty) 'Not available in this build: ${unavailable.join('; ')}.',
      'Keep spoken replies short (1–4 sentences) unless asked for detail.',
    ].join('\n\n');
  }

  /// Executes the pending approval after the owner said yes (or drops it).
  Future<BrainResult> resolvePending({required bool approved}) async {
    final p = pending;
    pending = null;
    if (p == null) return const BrainResult('There is nothing waiting for approval.', [], usedAi: false);
    if (!approved) {
      final e = AuditEntry(p.tool.name, p.tool.agent, p.args, 'declined', 'Owner declined');
      audit.add(e);
      return BrainResult('Okay, I did not do it.', [e], usedAi: false);
    }
    final r = await _runOnce(p.tool, p.args, <String, ToolResult>{});
    final e = AuditEntry(p.tool.name, p.tool.agent, p.args, r.ok ? 'approved · ok' : 'approved · failed', r.summary);
    audit.add(e);
    return BrainResult(r.ok ? r.summary : 'I tried, but it failed: ${r.summary}', [e], usedAi: false);
  }

  /// Runs a tool at most once per request (identical repeated calls reuse the
  /// first result) and at most once per [actionDedupWindow] for device
  /// actions, so retries/fallbacks can never repeat an Android action.
  Future<ToolResult> _runOnce(ToolSpec t, Map<String, dynamic> args, Map<String, ToolResult> thisRun) async {
    final key = actionKey(t.name, args);
    final same = thisRun[key];
    if (same != null) return same;
    final now = clock();
    _recentActions.removeWhere((_, v) => now.difference(v.at) > actionDedupWindow);
    final recent = t.agent == JarvisAgent.operator ? _recentActions[key] : null;
    if (recent != null) {
      final r = ToolResult(recent.result.ok, '${recent.result.summary} (already done a moment ago — not repeated)',
          data: recent.result.data, verified: recent.result.verified);
      thisRun[key] = r;
      return r;
    }
    final r = await _safeRun(t, args);
    thisRun[key] = r;
    if (t.agent == JarvisAgent.operator) _recentActions[key] = (at: clock(), result: r);
    return r;
  }

  /// Number of device actions remembered for de-duplication (tests).
  int get recentActionCount => _recentActions.length;

  Future<ToolResult> _safeRun(ToolSpec t, Map<String, dynamic> args) async {
    try {
      return await t.run(args).timeout(const Duration(seconds: 45));
    } catch (e) {
      return ToolResult.fail('${t.name} error: ${redact('$e')}');
    }
  }

  Future<BrainResult> run({
    required String userText,
    required List<Map<String, dynamic>> history,
    required String system,
  }) async {
    final gen = ++_generation;
    final steps = <AuditEntry>[];
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      ...history,
      {'role': 'user', 'content': userText},
    ];
    final catalog = tools.where((t) => t.available && t.risk != ToolRisk.blocked).map((t) => t.toOpenAi()).toList();
    final executed = <String, ToolResult>{};

    for (var step = 0; step < maxSteps; step++) {
      if (gen != _generation) throw BrainCancelled();
      final msg = await chat(messages, catalog);
      if (gen != _generation) throw BrainCancelled();
      final calls = (msg['tool_calls'] as List?) ?? const [];
      final content = (msg['content'] as String?)?.trim() ?? '';
      if (calls.isEmpty) {
        return BrainResult(_verifyReply(content, steps), steps);
      }
      messages.add({'role': 'assistant', 'content': content, 'tool_calls': calls});
      for (final c in calls) {
        final id = '${c['id'] ?? 'call_$step'}';
        final name = '${c['function']?['name'] ?? ''}';
        Map<String, dynamic> args;
        try {
          final raw = c['function']?['arguments'];
          args = raw is Map ? Map<String, dynamic>.from(raw) : (jsonDecode('${raw ?? '{}'}') as Map).cast<String, dynamic>();
        } catch (_) {
          args = {};
        }
        final t = tool(name);
        ToolResult r;
        if (t == null) {
          r = const ToolResult.fail('Unknown tool.');
          steps.add(AuditEntry(name, JarvisAgent.commander, args, 'failed', 'unknown tool'));
        } else if (!t.available) {
          r = ToolResult.fail(t.unavailableReason ?? 'Not available in this build.');
          steps.add(AuditEntry(name, t.agent, args, 'unavailable', r.summary));
        } else if (t.risk == ToolRisk.blocked) {
          r = const ToolResult.fail('Blocked by JARVIS safety rules.');
          steps.add(AuditEntry(name, t.agent, args, 'blocked', r.summary));
        } else if (t.risk == ToolRisk.approval) {
          final d = t.describe?.call(args) ?? '${t.name} ${jsonEncode(args)}';
          pending = PendingApproval(t, args, d, userText);
          final e = AuditEntry(name, t.agent, args, 'awaiting approval', d);
          steps.add(e);
          audit.addAll(steps);
          return BrainResult('$d — shall I go ahead? Say yes or no.', steps, pending: pending);
        } else {
          final dup = executed.containsKey(actionKey(t.name, args));
          r = await _runOnce(t, args, executed);
          steps.add(AuditEntry(name, t.agent, args, dup ? 'deduplicated' : (r.ok ? 'ok' : 'failed'), r.summary));
        }
        messages.add({'role': 'tool', 'tool_call_id': id, 'name': name, 'content': jsonEncode(r.toJson())});
      }
    }
    audit.addAll(steps);
    return BrainResult('I stopped after $maxSteps steps without finishing. ${_failures(steps)}'.trim(), steps);
  }

  String _failures(List<AuditEntry> steps) {
    final f = steps.where((s) => s.outcome == 'failed' || s.outcome == 'unavailable' || s.outcome == 'blocked').toList();
    return f.isEmpty ? '' : 'Problems: ${f.map((s) => '${s.tool}: ${s.summary}').join('; ')}';
  }

  /// Guards against the model claiming success when every tool failed.
  String _verifyReply(String reply, List<AuditEntry> steps) {
    audit.addAll(steps);
    if (reply.isEmpty) {
      return steps.isEmpty ? 'I have no answer for that.' : steps.map((s) => s.summary).join(' ');
    }
    final acted = steps.where((s) => s.outcome != 'awaiting approval').toList();
    if (acted.isNotEmpty && acted.every((s) => s.outcome != 'ok' && s.outcome != 'deduplicated')) {
      final admits = RegExp(r"fail|couldn|could not|can't|cannot|unable|not available|error|blocked|முடிய|illa", caseSensitive: false)
          .hasMatch(reply);
      if (!admits) return '${_failures(acted)}. $reply';
    }
    return reply;
  }
}
