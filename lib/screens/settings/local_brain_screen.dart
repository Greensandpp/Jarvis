import 'package:flutter/material.dart';
import '../../services/local_brain/local_brain_service.dart';

class LocalBrainScreen extends StatefulWidget {
  const LocalBrainScreen({super.key});
  @override
  State<LocalBrainScreen> createState() => _LocalBrainScreenState();
}
class _LocalBrainScreenState extends State<LocalBrainScreen> {
  final brain = LocalBrainService.instance;
  Map<String, dynamic>? profile;
  bool _acting = false;
  String? error;
  @override
  void initState() { super.initState(); brain.addListener(_changed); _refresh(); }
  void _changed() { if (mounted) setState(() {}); }
  Future<void> _refresh() async {
    await brain.initialize();
    try { profile = await brain.deviceProfile(); } catch (_) { error = 'Phone profile unavailable'; }
    _changed();
  }
  Future<void> _run(Future<void> Function() action) async {
    if (_acting) return;
    setState(() { _acting = true; error = null; });
    try { await action(); } catch (_) { error = 'Operation cancelled or unavailable; no cloud request was made'; }
    if (mounted) setState(() => _acting = false);
    await _refresh();
  }
  @override
  void dispose() { brain.removeListener(_changed); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phone-local AI')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Conversation on this phone', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      const Text('Runs a local GGUF language model inside JARVIS. No API key, PC or cloud inference is used. '
        'Import a trusted model already downloaded to your phone, then test it here. Importing a file does not enable it.'),
      const SizedBox(height: 16),
      ListTile(contentPadding: EdgeInsets.zero, leading: Icon(brain.ready ? Icons.offline_bolt : Icons.memory),
        title: Text(brain.ready ? 'LOCAL AI · OFFLINE · ₹0 API' : 'Local conversation not ready'), subtitle: Text(brain.status)),
      if (profile != null) Text('Available RAM: ${((profile!['availableMemoryBytes'] as num? ?? 0) / 1073741824).toStringAsFixed(1)} GB\n'
        'Battery: ${profile!['batteryPercent']}% · ${profile!['batteryTemperatureC']} °C\n'
        'Android thermal level: ${profile!['thermalStatus']}'),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _acting || brain.busy ? null : () => _run(brain.importModel),
        icon: const Icon(Icons.file_open), label: const Text('Import trusted GGUF file')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: _acting || brain.busy || brain.model == null ? null : () => _run(brain.benchmark),
        icon: const Icon(Icons.speed), label: const Text('Test this model on my phone')),
      if (brain.model != null) TextButton.icon(
        onPressed: _acting || brain.busy ? null : () => _run(brain.removeModel),
        icon: const Icon(Icons.delete_outline), label: const Text('Remove imported model from JARVIS')),
      if (_acting || brain.busy) ...[
        const SizedBox(height: 12), const LinearProgressIndicator(),
        TextButton(onPressed: brain.cancel, child: const Text('Cancel model test')),
      ],
      if (error != null) Text(error!, style: const TextStyle(color: Colors.orange)),
      const SizedBox(height: 16),
      const Text('Before activation JARVIS checks available RAM, response time, Tamil/English/Tanglish writing, '
        'battery and heat. These short tests do not prove factual accuracy or all-day thermal behavior. '
        'Local conversation cannot execute phone actions. Existing command permissions remain separate.'),
      if (brain.report != null) ...[
        const SizedBox(height: 16),
        const Text('On-phone test results', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final sample in (brain.report!['samples'] as List? ?? [])) ExpansionTile(
          title: Text('${sample['language']} · ${sample['milliseconds']} ms'),
          children: [Padding(padding: const EdgeInsets.all(12), child: Text('${sample['replyPreview'] ?? ''}'))]),
      ],
    ]),
  );
}
