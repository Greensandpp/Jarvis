// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../../jarvis_v3/appearance_settings.dart';
import 'package:http/http.dart' as http;

import '../../brain/ai_reliability.dart';
import '../../brain/model_selector.dart';
import '../../services/ai_service.dart';
import '../../services/settings_service.dart';

/// Real connection test: DNS → TLS → key + model discovery → generation.
/// ONLINE is recorded only when a real completion succeeds.
class AiDiagnosticsScreen extends StatefulWidget {
  const AiDiagnosticsScreen({super.key, this.client});
  /// TEST DOUBLE hook for widget tests; the app uses a real client.
  final http.Client? client;
  @override
  State<AiDiagnosticsScreen> createState() => _AiDiagnosticsScreenState();
}

class _AiDiagnosticsScreenState extends State<AiDiagnosticsScreen> {
  final _s = SettingsService.instance;
  DiagReport? _report;
  bool _running = false;

  Future<void> _run() async {
    setState(() { _running = true; _report = null; });
    final client = widget.client ?? http.Client();
    final rep = await runDiagnostics(client: client, base: _s.baseUrl, key: _s.apiKey, model: _s.model);
    if (rep.models.isNotEmpty) {
      await _s.setDiscoveredModels(rankModels(rep.models, provider: _s.provider));
      await _s.setModelsDiscoveredAt(DateTime.now().millisecondsSinceEpoch);
    }
    if (rep.online) {
      if (rep.workingModel != _s.model) await _s.setModel(rep.workingModel);
      await _s.recordAiSuccess(rep.workingModel);
    } else {
      final failed = rep.steps.where((s) => s.status == StepStatus.fail).map((s) => s.name).join(', ');
      await _s.recordAiFailure(failed.startsWith('DNS') ? 'dns' : failed.contains('key') ? 'auth' : 'connect');
    }
    if (!mounted) return;
    setState(() { _running = false; _report = rep; });
  }

  Future<void> _pickModel() async {
    final ms = rankModels(_s.discoveredModels, provider: _s.provider);
    if (ms.isEmpty) return;
    const auto = '__auto__';
    final chosen = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(
      title: const Text('Choose model'),
      children: [
        SimpleDialogOption(key: const ValueKey('model-auto'), onPressed: () => Navigator.pop(ctx, auto),
          child: Text('Automatic (recommended) — ${ms.first}${_s.modelAuto ? '  ✓' : ''}')),
        for (final m in ms) SimpleDialogOption(key: ValueKey('model-$m'), onPressed: () => Navigator.pop(ctx, m),
          child: Text(m + (!_s.modelAuto && m == _s.model ? '  ✓' : '')))],
    ));
    if (chosen == auto) {
      await _s.setModelAuto(true);
      await _s.setModel(ms.first);
    } else if (chosen != null) {
      await _s.setModel(chosen, pin: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _s, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final rep = _report;
    final attempts = AiService.instance.lastModelAttempts;
    return Scaffold(
      appBar: AppBar(title: const Text('AI connection & diagnostics')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        OutlinedButton.icon(
          key: const ValueKey('diag-animation-preview'),
          icon: const Icon(Icons.animation),
          label: const Text('Developer: animation state preview'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const AnimationPreviewScreen())),
        ),
        const SizedBox(height: 8),
        Text('Status: ${_s.aiStatusLabel}', key: const ValueKey('ai-status'),
          style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Provider: ${_s.provider}${_s.provider == 'gemini' ? ' (preferred)' : ''}\n'
            'Model: ${_s.modelLabel}\nEndpoint: ${_s.baseUrl}', key: const ValueKey('diag-model')),
        if (attempts.isNotEmpty)
          Text('Last request: ${attempts.join(' → ')}', key: const ValueKey('diag-attempts'),
            style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        const Text('ONLINE is shown only after a real request succeeds. Errors are classified as DNS, TLS, '
          'connection, timeout, key, model, quota or server problems.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('run-diagnostics'),
          onPressed: _running ? null : _run,
          icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.network_check),
          label: Text(_running ? 'Testing…' : 'Test connection & discover models'),
        ),
        if (_s.discoveredModels.isNotEmpty)
          OutlinedButton(key: const ValueKey('diag-pick-model'), onPressed: _pickModel,
            child: Text('Choose from ${_s.discoveredModels.length} discovered models')),
        if (rep != null) ...[
          const SizedBox(height: 12),
          Text(rep.online ? 'ONLINE via ${rep.workingModel}' : 'NOT ONLINE', key: const ValueKey('diag-result'),
            style: TextStyle(fontWeight: FontWeight.w800, color: rep.online ? Colors.greenAccent : Colors.redAccent)),
          for (final st in rep.steps)
            ListTile(dense: true,
              leading: Icon(st.status == StepStatus.pass ? Icons.check_circle : st.status == StepStatus.fail ? Icons.error : Icons.remove_circle_outline,
                color: st.status == StepStatus.pass ? Colors.greenAccent : st.status == StepStatus.fail ? Colors.redAccent : Colors.grey),
              title: Text(st.name), subtitle: Text('${st.detail} (${st.ms} ms)')),
        ],
      ]),
    );
  }
}
