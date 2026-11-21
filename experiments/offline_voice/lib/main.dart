// ignore_for_file: deprecated_member_use
// Compatible with older Flutter material API and current stable deprecation.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'offline_runtime.dart';
import 'language_contract.dart';

void main() => runApp(const OfflineApp());
const bridge = MethodChannel('gs.jarvis.offline/bridge');

class OfflineApp extends StatelessWidget {
  const OfflineApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark)),
    home: const OfflineScreen(),
  );
}

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});
  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}
class _OfflineScreenState extends State<OfflineScreen> with WidgetsBindingObserver {
  final _model = PhoneModel();
  final _input = TextEditingController();
  late final OfflineTurns _turns;
  String _status = 'Import the verified model to begin';
  String _answer = '';
  String _language = 'ta-IN';
  String _voices = 'Checking installed offline voices';
  bool _ready = false, _loading = false, _listening = false, _voice = true;
  int _micEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _turns = OfflineTurns(_model,
      stopAudio: () async { await bridge.invokeMethod('stop'); },
      speak: (text, language) async {
        await bridge.invokeMethod('speak', {'text': text, 'language': language});
      }, changed: (status, answer) {
        if (mounted) setState(() { _status = status; _answer = answer; });
      });
    unawaited(_capabilities());
  }
  Future<void> _capabilities() async {
    try {
      final data = await bridge.invokeMapMethod<String, dynamic>('capabilities');
      if (mounted) setState(() => _voices = '${data?['offlineVoices'] ?? []}');
    } catch (_) {
      if (mounted) setState(() => _voices = 'Native offline speech available only on Android');
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _turns.resumed();
      unawaited(_capabilities());
    } else {
      _micEpoch++;
      _listening = false;
      unawaited(_turns.stop(background: true));
    }
  }
  Future<void> _load({required bool import}) async {
    if (_loading || _ready) return;
    setState(() { _loading = true; _status = import ? 'Choose gemma-3-4b-it-Q4_K_M.gguf; verifying file…' : 'Verifying saved model…'; });
    try {
      final path = await bridge.invokeMethod<String>(import ? 'importModel' : 'savedModel');
      if (path == null) throw StateError('No verified model');
      if (!_turns.foreground) return;
      await _model.load(path);
      if (mounted) setState(() { _ready = true; _status = 'Model loaded on phone CPU'; });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _status = e.message ?? 'Model import unavailable');
    } catch (_) {
      if (mounted) setState(() => _status = 'Model not loaded. Import the exact verified GGUF file.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  Future<void> _stop() async {
    _micEpoch++;
    setState(() { _listening = false; _status = 'Stopped — microphone off'; });
    await _turns.stop();
  }
  Future<void> _listen() async {
    await _stop();
    if (!_ready || !_turns.foreground) return;
    final epoch = ++_micEpoch;
    setState(() { _listening = true; _status = 'Checking installed on-device recognition'; });
    try {
      final text = await bridge.invokeMethod<String>('listen', {'language': OfflineLanguage.speechLocale(_language)});
      if (!mounted || epoch != _micEpoch || !_turns.foreground) return;
      if (text != null && text.trim().isNotEmpty) {
        _input.text = text;
        unawaited(_turns.ask(text, _language, voice: _voice));
      }
    } on PlatformException catch (e) {
      if (mounted && epoch == _micEpoch) setState(() => _status = e.message ?? 'Offline recognition unavailable; use typed chat');
    } finally {
      if (mounted && epoch == _micEpoch) setState(() => _listening = false);
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _micEpoch++;
    unawaited(_turns.stop(background: true).whenComplete(_model.dispose));
    _input.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GREENSOIL // OFFLINE LAB')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Phone-local AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const Text('No API key, Railway or LiveKit required. No internet permission in this build. '
        'Download the model once using your browser, then import it. Offline chat has no monthly quota.'),
      const SizedBox(height: 12),
      const SelectableText('gemma-3-4b-it-Q4_K_M.gguf • 2.49 GB\nLanguage probes required before release. Tamil/Tanglish quality still needs your device test.'),
      FilledButton(onPressed: _loading || _ready ? null : () => _load(import: true), child: const Text('Import downloaded GGUF model')),
      OutlinedButton(onPressed: _loading || _ready ? null : () => _load(import: false), child: const Text('Load saved model')),
      DropdownButton<String>(value: _language, isExpanded: true, items: const [
        DropdownMenuItem(value: 'ta-IN', child: Text('தமிழ் / Tamil replies')),
        DropdownMenuItem(value: 'en-IN', child: Text('English replies')),
        DropdownMenuItem(value: 'ta-Latn', child: Text('Tanglish — Latin letters')),
      ], onChanged: (value) { if (value != null) { unawaited(_stop()); setState(() => _language = value); } }),
      SwitchListTile(title: const Text('Read replies with installed offline voice'), value: _voice,
        onChanged: (value) { setState(() => _voice = value); if (!value) unawaited(_stop()); }),
      const Text('Only installed offline voices are used. Voice gender/quality depends on Android.'),
      ExpansionTile(title: const Text('Offline speech diagnostics'), children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(_voices)),
      ]),
      const SizedBox(height: 12),
      TextField(controller: _input, maxLength: 1000, maxLines: 3, decoration: const InputDecoration(labelText: 'Message to local model', border: OutlineInputBorder())),
      FilledButton(onPressed: !_ready ? null : () { _micEpoch++; setState(() => _listening = false); unawaited(_turns.ask(_input.text, _language, voice: _voice)); }, child: const Text('Send locally')),
      OutlinedButton(onPressed: !_ready ? null : (_listening ? _stop : _listen), child: Text(_listening ? 'Mute / stop listening' : 'Stop reply and listen offline')),
      TextButton(onPressed: _stop, child: const Text('Stop voice and generation')),
      const SizedBox(height: 12),
      Text(_status, style: const TextStyle(color: Colors.cyanAccent)),
      const SizedBox(height: 12),
      SelectableText(_answer),
      const SizedBox(height: 16),
      const Text('Foreground, push-to-talk only. No automatic wake word, background mic, tools or cloud fallback. '
        'Missing Tamil speech packs remain unavailable. Voice gender depends on the installed engine. '
        'Replies are limited to 128 generated tokens for responsiveness; no 2-minute session or monthly timer.'),
    ]),
  );
}
