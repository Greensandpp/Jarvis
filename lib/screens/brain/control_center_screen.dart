import 'package:flutter/material.dart';

import '../../brain/brain.dart';
import '../../brain/jarvis_brain_service.dart';
import '../../brain/semantic_memory.dart';
import '../../brain/visual_bus.dart';
import '../../core/build_profile.dart';
import '../../services/conversational_memory_service.dart';
import '../../services/hermes_evolution_service.dart';
import '../../services/settings_service.dart';
import '../../services/skill_memory_service.dart';
import '../../services/voice_service.dart';
import '../settings/jarvis_settings_screen.dart';
import '../settings/permissions_screen.dart';
import '../settings/settings_screen.dart';
import 'ai_diagnostics_screen.dart';
import 'memory_tools.dart';
import 'trading_ai_screen.dart';

/// One place that reaches every JARVIS settings area. Existing original
/// screens are reused; new pages only cover what did not exist.
class ControlCenterScreen extends StatelessWidget {
  const ControlCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final s = SettingsService.instance;
    final items = <(String, String, IconData, VoidCallback)>[
      ('AI Brain', 'Tool-calling brain, reply language, status', Icons.psychology, () => go(const _BrainPage())),
      ('API key & Models', 'Provider, key (stored on phone), model', Icons.key, () => go(const SettingsScreen())),
      ('Diagnostics', 'AI DNS/TLS/key/model test, microphone & TTS', Icons.network_check, () => go(const _DiagnosticsPage())),
      ('Voice', 'Female voice, Tamil/English mic, neural voice', Icons.record_voice_over, () => go(const _VoicePage())),
      ('Memory & Backup', 'Recall, correct, undo, encrypted backup/restore', Icons.memory, () => go(const _MemoryPage())),
      ('Learning', 'Corrections JARVIS must follow, learned skills', Icons.school, () => go(const _LearningPage())),
      ('Trading (paper)', 'Risk gate, indicators, OI, journal audit', Icons.candlestick_chart, () => go(const TradingAiScreen())),
      ('Agents & Audit', 'Five agents and every tool action', Icons.groups, () => go(const _AgentsPage())),
      ('Tools', 'What JARVIS can do and what needs approval', Icons.build, () => go(const _ToolsPage())),
      ('Visuals', 'JARVIS Core, AIRA (10 models), Office, APEX, MIRA', Icons.auto_awesome, () => go(const _VisualsPage())),
      ('Permissions', 'Android permissions for this build', Icons.admin_panel_settings, () => go(const PermissionsScreen())),
      ('Automation', 'Original JARVIS workflows, routines, HUD settings', Icons.auto_mode, () => go(const JarvisSettingsScreen())),
      ('Device & PC', 'Phone controls; Windows companion status', Icons.devices, () => go(const _DevicePage())),
      ('Security & Privacy', 'Cloud AI/TTS/lookups, build type', Icons.security, () => go(const _SecurityPage())),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('JARVIS Control Center')),
      body: ListView(children: [
        ListTile(
          key: const ValueKey('cc-status'),
          leading: const Icon(Icons.info_outline),
          title: Text('${BuildProfile.label} · ${s.aiStatusLabel}'),
          subtitle: Text('Brain ${s.brainToolCalling ? 'ON' : 'OFF (original router)'} · reply ${s.replyLanguage}'),
        ),
        for (final it in items)
          ListTile(
            key: ValueKey('cc-${it.$1}'),
            leading: Icon(it.$3),
            title: Text(it.$1),
            subtitle: Text(it.$2),
            trailing: const Icon(Icons.chevron_right),
            onTap: it.$4,
          ),
      ]),
    );
  }
}

class _BrainPage extends StatefulWidget {
  const _BrainPage();
  @override
  State<_BrainPage> createState() => _BrainPageState();
}

class _BrainPageState extends State<_BrainPage> {
  final s = SettingsService.instance;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AI Brain')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Text(s.aiStatusLabel, key: const ValueKey('brain-status'), style: const TextStyle(fontWeight: FontWeight.w700)),
          SwitchListTile(
            key: const ValueKey('brain-toggle'),
            title: const Text('Tool-calling brain'),
            subtitle: const Text('Open-ended reasoning with tools and five agents. Off = original single-shot intent router.'),
            value: s.brainToolCalling,
            onChanged: (v) async {
              await s.setBrainToolCalling(v);
              setState(() {});
            },
          ),
          const Text('Reply language'),
          SegmentedButton<String>(
            key: const ValueKey('brain-language'),
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Auto')),
              ButtonSegment(value: 'english', label: Text('English')),
              ButtonSegment(value: 'tamil', label: Text('தமிழ்')),
              ButtonSegment(value: 'tanglish', label: Text('Tanglish')),
            ],
            selected: {s.replyLanguage},
            onSelectionChanged: (v) async {
              await s.setReplyLanguage(v.first);
              setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Semantic memory (Gemini embeddings)'),
            subtitle: Text('Keyword search is used offline. Last recall: ${SemanticMemory.instance.lastMode}'),
            value: s.semanticMemory,
            onChanged: (v) async {
              await s.setSemanticMemory(v);
              setState(() {});
            },
          ),
          const Text('Offline shortcuts (no AI needed): time/date, "switch to AIRA/APEX/MIRA…", "Tamil-la pesu", "female voice". '
              'Everything else goes to the brain. Live Gemini behaviour is verified only after you add your key and the connection test passes.',
              style: TextStyle(fontSize: 12)),
        ]),
      );
}

class _DiagnosticsPage extends StatefulWidget {
  const _DiagnosticsPage();
  @override
  State<_DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<_DiagnosticsPage> {
  Map<String, String>? _voice;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Diagnostics')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          FilledButton.icon(
            key: const ValueKey('diag-ai'),
            icon: const Icon(Icons.network_check),
            label: const Text('AI connection test'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiDiagnosticsScreen())),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('diag-voice'),
            icon: const Icon(Icons.mic),
            label: const Text('Check microphone & voices'),
            onPressed: () async {
              final r = await VoiceService.instance.diagnostics();
              if (mounted) setState(() => _voice = r);
            },
          ),
          if (_voice != null)
            Column(key: const ValueKey('diag-voice-result'), children: [
              for (final e in _voice!.entries) ListTile(dense: true, title: Text(e.key), subtitle: Text(e.value)),
            ]),
          const Text('Speech accuracy for Tamil/Tanglish is UNVERIFIED until tested on your phone.', style: TextStyle(fontSize: 12)),
        ]),
      );
}

class _VoicePage extends StatefulWidget {
  const _VoicePage();
  @override
  State<_VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<_VoicePage> {
  final s = SettingsService.instance;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Voice')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          SwitchListTile(
            key: const ValueKey('voice-female'),
            title: const Text('Prefer a female voice'),
            subtitle: const Text('Neural: Pallavi (Tamil) / Neerja (Indian English). Local TTS: a voice named female, if the phone has one.'),
            value: s.preferFemaleVoice,
            onChanged: (v) async {
              await s.setPreferFemaleVoice(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Neural voice (needs internet and cloud-TTS permission)'),
            value: s.useNeuralVoice,
            onChanged: (v) async {
              await s.setUseNeuralVoice(v);
              setState(() {});
            },
          ),
          const Text('Microphone language'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en-IN', label: Text('English (India)')),
              ButtonSegment(value: 'ta-IN', label: Text('தமிழ்')),
            ],
            selected: {s.speechInputLocale == 'ta-IN' ? 'ta-IN' : 'en-IN'},
            onSelectionChanged: (v) async {
              await s.setSpeechInputLocale(v.first);
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => VoiceService.instance.speakIn('Vanakkam! JARVIS ready.',
                languageTag: 'en-IN', neuralVoice: s.preferFemaleVoice ? 'en-IN-NeerjaNeural' : s.jarvisNeuralVoice,
                female: s.preferFemaleVoice),
            child: const Text('Test voice'),
          ),
        ]),
      );
}

class _MemoryPage extends StatefulWidget {
  const _MemoryPage();
  @override
  State<_MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<_MemoryPage> {
  final m = ConversationalMemoryService.instance;
  final _add = TextEditingController();
  @override
  void initState() {
    super.initState();
    m.init().then((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Memory & Backup')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Text('${m.facts.length} memories on this phone', key: const ValueKey('mem-count')),
          Row(children: [
            Expanded(child: TextField(key: const ValueKey('mem-add-text'), controller: _add,
                decoration: const InputDecoration(hintText: 'Add a memory (you approve by adding it)'))),
            IconButton(key: const ValueKey('mem-add'), icon: const Icon(Icons.add), onPressed: () async {
              if (_add.text.trim().isEmpty) return;
              await m.addFact(_add.text.trim());
              _add.clear();
              setState(() {});
            }),
          ]),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(key: const ValueKey('mem-export'), icon: const Icon(Icons.lock), label: const Text('Encrypted backup'),
                onPressed: () => exportMemoryDialog(context)),
            OutlinedButton.icon(key: const ValueKey('mem-import'), icon: const Icon(Icons.restore), label: const Text('Restore'),
                onPressed: () async {
                  await importMemoryDialog(context);
                  setState(() {});
                }),
          ]),
          for (final f in m.facts)
            ListTile(
              key: ValueKey('mem-${f.id}'),
              title: Text(f.fact),
              subtitle: Text('${f.category}${f.history.isEmpty ? '' : ' · corrected ${f.history.length}× (was "${f.history.last}")'}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (f.history.isNotEmpty)
                  IconButton(tooltip: 'Undo correction', icon: const Icon(Icons.undo), onPressed: () async {
                    await undoCorrection(context, f);
                    setState(() {});
                  }),
                IconButton(tooltip: 'Correct', icon: const Icon(Icons.edit), onPressed: () async {
                  await correctFactDialog(context, f);
                  setState(() {});
                }),
                IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () async {
                  await m.deleteFact(f.id);
                  setState(() {});
                }),
              ]),
            ),
        ]),
      );
}

class _LearningPage extends StatefulWidget {
  const _LearningPage();
  @override
  State<_LearningPage> createState() => _LearningPageState();
}

class _LearningPageState extends State<_LearningPage> {
  final _c = TextEditingController();
  int _skills = 0;
  @override
  void initState() {
    super.initState();
    SkillMemoryService.instance.all().then((s) => mounted ? setState(() => _skills = s.length) : null);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = ConversationalMemoryService.instance;
    final corrections = m.facts.where((f) => f.category == 'correction').toList();
    final h = HermesEvolutionService.instance.lastEvolvedAt;
    return Scaffold(
      appBar: AppBar(title: const Text('Learning')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Text('Teach JARVIS: corrections are stored as approved memories and recalled into future answers when relevant. '
            'JARVIS never changes its own code.', style: TextStyle(fontSize: 12)),
        TextField(key: const ValueKey('learn-text'), controller: _c,
            decoration: const InputDecoration(hintText: 'e.g. "When I say Sensex expiry, I mean Friday weekly expiry"')),
        FilledButton(key: const ValueKey('learn-save'), onPressed: () async {
          if (_c.text.trim().isEmpty) return;
          await m.addFact(_c.text.trim(), category: 'correction');
          _c.clear();
          setState(() {});
        }, child: const Text('Save correction')),
        const SizedBox(height: 8),
        Text('Corrections: ${corrections.length} · Learned automation skills: $_skills · '
            'Context last synthesised: ${h == null ? 'never' : h.toLocal().toString().split('.').first}'),
        for (final f in corrections) ListTile(dense: true, title: Text(f.fact)),
      ]),
    );
  }
}

class _AgentsPage extends StatefulWidget {
  const _AgentsPage();
  @override
  State<_AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<_AgentsPage> {
  List<Map<String, dynamic>> _audit = const [];
  @override
  void initState() {
    super.initState();
    JarvisBrainService.loadAudit().then((a) => mounted ? setState(() => _audit = a.reversed.toList()) : null);
  }

  @override
  Widget build(BuildContext context) {
    final tools = JarvisBrainService.instance.brain.tools;
    return Scaffold(
      appBar: AppBar(title: const Text('Agents & Audit')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final a in JarvisAgent.values)
          ListTile(
            key: ValueKey('agent-${a.name}'),
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(a.title),
            subtitle: Text('${a.role} · ${tools.where((t) => t.agent == a).length} tools · '
                '${_audit.where((e) => e['agent'] == a.name).length} recent actions'),
          ),
        const Divider(),
        Text('Audit log (${_audit.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_audit.isEmpty) const Text('No tool actions yet.'),
        for (final e in _audit.take(60))
          ListTile(dense: true, title: Text('${e['tool']} · ${e['outcome']}'), subtitle: Text('${e['at']}\n${e['summary']}')),
      ]),
    );
  }
}

class _ToolsPage extends StatelessWidget {
  const _ToolsPage();
  @override
  Widget build(BuildContext context) {
    final tools = JarvisBrainService.instance.brain.tools;
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(children: [
        for (final t in tools)
          ListTile(
            dense: true,
            leading: Icon(!t.available ? Icons.block : t.risk == ToolRisk.blocked ? Icons.gpp_bad
                : t.risk == ToolRisk.approval ? Icons.front_hand : Icons.check_circle_outline),
            title: Text('${t.name} · ${t.agent.title}'),
            subtitle: Text('${t.description}\n${!t.available ? 'NOT AVAILABLE: ${t.unavailableReason}'
                : t.risk == ToolRisk.blocked ? 'BLOCKED by safety rules'
                : t.risk == ToolRisk.approval ? 'Asks you first' : 'Runs when needed'}'),
          ),
      ]),
    );
  }
}

class _VisualsPage extends StatelessWidget {
  const _VisualsPage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Visuals')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const Text('Choose the home visual. Long-press the AIRA view for per-model brightness/speed. You can also say "switch to MIRA".'),
          Wrap(spacing: 8, children: [
            for (final m in visualModes)
              FilledButton.tonal(key: ValueKey('vis-$m'), onPressed: () async {
                await requestVisual(mode: m);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Visual: ${m.toUpperCase()}')));
                }
              }, child: Text(m.toUpperCase())),
          ]),
          const SizedBox(height: 12),
          const Text('AIRA models'),
          Wrap(spacing: 6, children: [
            for (final m in const ['neuralReactor', 'amberHologram', 'electricWeb', 'aiHead', 'jellyfish', 'violetVortex',
              'auroraRibbon', 'dnaHelix', 'crystalBloom', 'solarFlare'])
              ActionChip(key: ValueKey('aira-$m'), label: Text(m), onPressed: () => requestVisual(mode: 'aira', airaModel: m)),
          ]),
        ]),
      );
}

class _DevicePage extends StatelessWidget {
  const _DevicePage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Device & PC')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const ListTile(title: Text('Phone controls'), subtitle: Text('Apps, alarms, reminders, to-dos, notes, volume, torch, media, '
              'message drafts (you press send). Ask JARVIS by voice or text.')),
          ListTile(title: const Text('Screen automation (other apps)'),
              subtitle: Text(BuildProfile.fullControl ? 'Available in this Full Control build after you enable the accessibility service. '
                  'Always asks first; stops before payments, OTP or PIN.' : BuildProfile.unavailable('Screen automation'))),
          const ListTile(title: Text('Windows PC companion'), subtitle: Text('NOT BUILT: no PC agent or pairing exists yet, '
              'so JARVIS cannot control a PC.')),
        ]),
      );
}

class _SecurityPage extends StatefulWidget {
  const _SecurityPage();
  @override
  State<_SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<_SecurityPage> {
  final s = SettingsService.instance;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Security & Privacy')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Text(BuildProfile.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (BuildProfile.isStandard) const Text(BuildProfile.standardNotice, style: TextStyle(fontSize: 12)),
          SwitchListTile(key: const ValueKey('sec-cloud-ai'), title: const Text('Allow cloud AI'),
              subtitle: const Text('Needed for the Gemini brain. Off = nothing leaves the phone.'),
              value: s.allowCloudAi, onChanged: (v) async {
                await s.setAllowCloudAi(v);
                setState(() {});
              }),
          SwitchListTile(title: const Text('Allow cloud voice (neural TTS)'), value: s.allowCloudTts, onChanged: (v) async {
            await s.setAllowCloudTts(v);
            setState(() {});
          }),
          SwitchListTile(title: const Text('Allow web search / news / weather'), value: s.allowExternalLookups, onChanged: (v) async {
            await s.setAllowExternalLookups(v);
            setState(() {});
          }),
          const ListTile(title: Text('Always enforced'), subtitle: Text('No payments or live orders by JARVIS · OTP/UPI PIN only by you · '
              'messages are drafts you send · memory changes need approval · API key stays on this phone · PAPER-only trading.')),
        ]),
      );
}
