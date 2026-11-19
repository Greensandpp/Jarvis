// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../services/agent_office/agent_office.dart';

/// Mobile-first five-agent office. Shows ONLY authenticated provider state;
/// otherwise every role reads NOT CONNECTED. Local executor status (the real
/// on-device JARVIS task) is passed in by the host.
class AgentOfficeView extends StatefulWidget {
  const AgentOfficeView({
    super.key,
    required this.controller,
    required this.localTask,
    required this.localTaskListenable,
  });

  final AgentOfficeController controller;
  final ({String goal, String state, int step}) Function() localTask;
  final Listenable localTaskListenable;

  @override
  State<AgentOfficeView> createState() => _AgentOfficeViewState();
}

class _AgentOfficeViewState extends State<AgentOfficeView> {
  static const cyan = Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    widget.controller.load().then((_) {
      if (widget.controller.configured) widget.controller.refresh();
    });
  }

  Color _stateColor(AgentState s) => switch (s) {
        AgentState.idle => Colors.white54,
        AgentState.working => cyan,
        AgentState.handoff => const Color(0xFFB98BFF),
        AgentState.rejected => const Color(0xFFFF5A6A),
        AgentState.waiting => const Color(0xFFFFC14D),
        AgentState.done => const Color(0xFF6BFFA0),
      };

  @override
  Widget build(BuildContext context) {
    final ctl = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([ctl, widget.localTaskListenable]),
      builder: (context, _) {
        final snap = ctl.snapshot;
        final local = widget.localTask();
        final banner = switch (snap.source) {
          OfficeSource.authenticated => ('LIVE · AUTHENTICATED PROVIDER', const Color(0xFF6BFFA0)),
          OfficeSource.sample => ('SAMPLE DATA · NOT LIVE WORK', const Color(0xFFFFC14D)),
          OfficeSource.disconnected => ('DISCONNECTED', const Color(0xFFFF5A6A)),
        };
        return RefreshIndicator(
          onRefresh: ctl.refresh,
          child: ListView(
            key: const ValueKey('agent-office-list'),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            children: [
              Row(children: [
                const Expanded(child: Text('JARVIS AGENT OFFICE', style: TextStyle(
                  color: cyan, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.5))),
                IconButton(
                  tooltip: 'Configure authenticated status provider',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.link, color: cyan),
                  onPressed: _configure,
                ),
              ]),
              Container(
                key: const ValueKey('office-source-banner'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: banner.$2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(banner.$1, style: TextStyle(color: banner.$2, fontWeight: FontWeight.w800)),
                  if (snap.error != null)
                    Text(snap.error!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (snap.isLive && snap.mission.isNotEmpty)
                    Text('Mission: ${snap.mission}', style: const TextStyle(color: Colors.white)),
                  if (snap.fetchedAt != null)
                    Text('Fetched ${snap.fetchedAt!.toLocal().toIso8601String().substring(11, 19)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ),
              for (final v in snap.policyViolations)
                Card(color: const Color(0xFF3A0A12), child: ListTile(
                  leading: const Icon(Icons.gpp_bad, color: Color(0xFFFF5A6A)),
                  title: Text(v, style: const TextStyle(color: Colors.white)))),
              const SizedBox(height: 8),
              Card(color: const Color(0xFF071B20), child: ListTile(
                leading: const Icon(Icons.phone_android, color: cyan),
                title: Text(local.goal.isEmpty ? 'No active on-device task' : local.goal,
                  style: const TextStyle(color: Colors.white)),
                subtitle: Text('On-device JARVIS executor (real): ${local.state} · step ${local.step}',
                  style: const TextStyle(color: Colors.white70)),
              )),
              for (final role in AgentRole.values) _roleCard(role, snap),
              if (snap.isLive && snap.blockers.isNotEmpty) ...[
                _heading('Blockers'),
                for (final b in snap.blockers) _line(Icons.block, b),
              ],
              if (snap.isLive && snap.qaResults.isNotEmpty) ...[
                _heading('QA results'),
                for (final q in snap.qaResults) _line(Icons.fact_check, q),
              ],
              if (snap.isLive && snap.handoffs.isNotEmpty) ...[
                _heading('Handoffs'),
                for (final h in snap.handoffs)
                  Card(color: const Color(0xFF0B0F1A), child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text('${h.from.label} → ${h.to.label}\n'
                      'Goal: ${h.goal}\nWork: ${h.work}\nEvidence: ${h.evidence}\n'
                      'Status: ${h.status}\nBlockers: ${h.blockers}\nNext: ${h.next}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  )),
              ],
              if (snap.isLive && snap.approvals.isNotEmpty) ...[
                _heading('Approval / audit log'),
                for (final a in snap.approvals)
                  _line(a.tier == PermissionTier.red ? Icons.lock : Icons.lock_open,
                    '[${a.tier.name.toUpperCase()}] ${a.action} — ${a.status}'
                    '${a.tier == PermissionTier.red ? (a.approvedByOwner ? ' (owner approved)' : ' (owner approval required)') : ''}'),
              ],
              if (snap.isLive && snap.events.isNotEmpty) ...[
                _heading('Event history'),
                for (final e in snap.events.reversed.take(30))
                  _line(Icons.history, '${e.agent.label}: ${e.state.name} — ${e.message}'
                    '${e.evidence.isEmpty ? '' : ' · evidence: ${e.evidence}'}'),
              ],
              const SizedBox(height: 8),
              const Text(
                'Permission tiers: GREEN read/search/draft · YELLOW create/edit in work folder · '
                'RED send/post/purchase/delete/permissions/accounts/deploy = owner approval on the '
                'authenticated server. The phone never approves or executes RED actions from here. '
                'Max 3 rejection loops, then escalate to owner.',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  Widget _roleCard(AgentRole role, OfficeSnapshot snap) {
    final st = snap.isLive ? snap.agents[role] : null;
    final label = !snap.isLive
        ? (snap.source == OfficeSource.sample ? 'SAMPLE · not real work' : 'NOT CONNECTED · no simulated progress')
        : st == null ? 'No status reported' : '${st.state.name.toUpperCase()} · ${st.task}';
    final color = st == null ? Colors.white38 : _stateColor(st.state);
    return Card(
      key: ValueKey('office-role-${role.name}'),
      color: const Color(0xFF07141A),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: .18),
          child: Icon(Icons.person_outline, color: color)),
        title: Text(role.label, style: const TextStyle(color: Colors.white)),
        subtitle: Text('$label\n${role.duty}', style: const TextStyle(color: Colors.white60)),
        isThreeLine: true,
      ),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(t.toUpperCase(), style: const TextStyle(color: cyan,
          fontWeight: FontWeight.w700, letterSpacing: 1.2)));

  Widget _line(IconData i, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        ]));

  Future<void> _configure() async {
    final ctl = widget.controller;
    final url = TextEditingController(text: ctl.endpoint);
    final token = TextEditingController();
    String? error;
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Authenticated status provider'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Read-only HTTPS endpoint returning sanitized team-status JSON '
            '(mode "live"). The token stays on this phone. Leave unconfigured to keep '
            'the office DISCONNECTED.', style: TextStyle(fontSize: 12)),
          TextField(controller: url, decoration: const InputDecoration(labelText: 'https:// endpoint')),
          TextField(controller: token, obscureText: true,
            decoration: const InputDecoration(labelText: 'Bearer token')),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
        ])),
        actions: [
          if (ctl.configured)
            TextButton(onPressed: () async {
              await ctl.disconnect();
              if (ctx.mounted) Navigator.pop(ctx);
            }, child: const Text('Disconnect')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            final e = await ctl.configure(url.text, token.text);
            if (e != null) {
              setD(() => error = e);
              return;
            }
            if (ctx.mounted) Navigator.pop(ctx);
            await ctl.refresh();
          }, child: const Text('Save & refresh')),
        ],
      ),
    ));
    url.dispose();
    token.dispose();
  }
}
