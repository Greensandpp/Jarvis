// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../brain/ai_reliability.dart';
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
    setState(() {
      _running = true;
      _report = null;
    });
    final client = widget.client ?? http.Client();
    final connection = _s.aiConnectionId, model = _s.model;
    final rep = await runDiagnostics(
      client: client,
      base: _s.baseUrl,
      key: _s.apiKey,
      model: _s.model,
    );
    if (widget.client == null) client.close();
    if (connection != _s.aiConnectionId || model != _s.model) {
      if (mounted)
        setState(() {
          _running = false;
        });
      return;
    }
    if (rep.models.isNotEmpty) await _s.setDiscoveredModels(rep.models);
    if (rep.online) {
      if (rep.workingModel != _s.model) await _s.setModel(rep.workingModel);
      await _s.recordAiSuccess(rep.workingModel);
    } else {
      final failed = rep.steps
          .where((s) => s.status == StepStatus.fail)
          .map((s) => s.name)
          .join(', ');
      await _s.recordAiFailure(
        failed.startsWith('DNS')
            ? 'dns'
            : failed.contains('key')
            ? 'auth'
            : 'connect',
      );
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = rep;
    });
  }

  Future<void> _pickModel() async {
    final ms = _s.discoveredModels;
    if (ms.isEmpty) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose model'),
        children: [
          for (final m in ms)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(m + (m == _s.model ? '  ✓' : '')),
            ),
        ],
      ),
    );
    if (chosen != null) {
      await _s.setModel(chosen);
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rep = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('AI connection & diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Status: ${_s.aiStatusLabel}',
            key: const ValueKey('ai-status'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Provider: ${_s.provider} · Model: ${_s.model}\nEndpoint: ${_s.baseUrl}',
          ),
          const SizedBox(height: 4),
          const Text(
            'ONLINE is shown only after a real request succeeds. Errors are classified as DNS, TLS, '
            'connection, timeout, key, model, quota or server problems.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('run-diagnostics'),
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check),
            label: Text(
              _running ? 'Testing…' : 'Test connection & discover models',
            ),
          ),
          if (_s.discoveredModels.isNotEmpty)
            OutlinedButton(
              onPressed: _pickModel,
              child: Text(
                'Choose from ${_s.discoveredModels.length} discovered models',
              ),
            ),
          if (rep != null) ...[
            const SizedBox(height: 12),
            Text(
              rep.online ? 'ONLINE via ${rep.workingModel}' : 'NOT ONLINE',
              key: const ValueKey('diag-result'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: rep.online ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
            for (final st in rep.steps)
              ListTile(
                dense: true,
                leading: Icon(
                  st.status == StepStatus.pass
                      ? Icons.check_circle
                      : st.status == StepStatus.fail
                      ? Icons.error
                      : Icons.remove_circle_outline,
                  color: st.status == StepStatus.pass
                      ? Colors.greenAccent
                      : st.status == StepStatus.fail
                      ? Colors.redAccent
                      : Colors.grey,
                ),
                title: Text(st.name),
                subtitle: Text('${st.detail} (${st.ms} ms)'),
              ),
          ],
        ],
      ),
    );
  }
}
