// ignore_for_file: deprecated_member_use
// Flutter 3.47 deprecates material.dart while older stable supports it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:permission_handler/permission_handler.dart';

import 'foreground_connection_gate.dart';

void main() => runApp(const GreenSoilVoiceExperimentApp());

/// Disposable, standalone LiveKit test client. NOT a replacement for JARVIS.
/// It deliberately does not contain Gemini keys, LiveKit API secrets,
/// automatic wake-up, background audio, or a fake local TTS fallback.
class GreenSoilVoiceExperimentApp extends StatelessWidget {
  const GreenSoilVoiceExperimentApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GreenSoil Voice Lab',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xff00d9f4),
          useMaterial3: true,
        ),
        home: const VoiceExperimentScreen(),
      );
}

class VoiceExperimentScreen extends StatefulWidget {
  const VoiceExperimentScreen({super.key});

  @override
  State<VoiceExperimentScreen> createState() => _VoiceExperimentScreenState();
}

class _VoiceExperimentScreenState extends State<VoiceExperimentScreen>
    with WidgetsBindingObserver {
  final _endpointController = TextEditingController();
  final _textController = TextEditingController();
  final _foregroundGate = ForegroundConnectionGate();
  livekit.Session? _session;
  bool _busy = false;
  bool _connected = false;
  bool _microphoneOn = false;
  String _status = 'Disconnected — no microphone capture';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foregroundGate.resumed();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // A permission or network await may still be running. Invalidate its
      // ticket immediately so it cannot reconnect the microphone on return.
      _foregroundGate.wentToBackground();
      unawaited(_disconnect());
    }
  }

  Future<void> _connect() async {
    if (_busy || _session != null) return;
    final ticket = _foregroundGate.begin();
    if (ticket == null) return;
    final endpoint = Uri.tryParse(_endpointController.text.trim());
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty) {
      _updateStatus('Enter an HTTPS endpoint for short-lived LiveKit tokens.');
      return;
    }
    setState(() => _busy = true);
    livekit.Session? candidate;
    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted || !_foregroundGate.isCurrent(ticket)) {
        _updateStatus('Microphone permission denied. Nothing connected.');
        return;
      }
      candidate = livekit.Session.fromConfigurableTokenSource(
        livekit.EndpointTokenSource(url: endpoint),
        options: livekit.SessionOptions(preConnectAudio: false),
      );
      // Session.start may publish mic after connection. The user explicitly
      // pressed Connect and granted Android permission first.
      await candidate.start();
      if (!mounted ||
          !_foregroundGate.isCurrent(ticket) ||
          candidate.connectionState != livekit.ConnectionState.connected) {
        throw StateError('No connected LiveKit session.');
      }
      _session = candidate;
      _connected = true;
      _microphoneOn = true;
      _updateStatus('Connected. Microphone enabled by LiveKit.');
    } catch (error) {
      _updateStatus('Connection failed: $error');
      if (candidate != null) {
        // Network cleanup failures must not be presented as a connection.
        try {
          await candidate.end();
        } catch (_) {}
        await candidate.dispose();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMicrophone() async {
    if (!_connected || _busy) return;
    final session = _session;
    final participant = session?.room.localParticipant;
    if (participant == null) {
      _updateStatus('LiveKit local participant unavailable.');
      return;
    }
    final enable = !_microphoneOn;
    final ticket = _foregroundGate.begin();
    if (ticket == null) return;
    if (enable) {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted || !_foregroundGate.isCurrent(ticket)) {
        _updateStatus('Microphone permission denied or session left foreground.');
        return;
      }
    }
    if (!_foregroundGate.isCurrent(ticket) || session != _session) return;
    try {
      await participant.setMicrophoneEnabled(enable);
      if (mounted) {
        setState(() => _microphoneOn = enable);
        _updateStatus(enable ? 'Microphone on' : 'Microphone muted');
      }
    } catch (error) {
      _updateStatus('Microphone control error: $error');
    }
  }

  Future<void> _sendText() async {
    final session = _session;
    final message = _textController.text.trim();
    if (!_connected || session == null || message.isEmpty) return;
    try {
      await session.sendText(message);
      _textController.clear();
      _updateStatus('Text sent to connected agent.');
    } catch (error) {
      _updateStatus('Text send failed: $error');
    }
  }

  Future<void> _disconnect() async {
    _foregroundGate.invalidate();
    final session = _session;
    if (session == null) return;
    _session = null;
    _connected = false;
    _microphoneOn = false;
    _updateStatus('Disconnecting — microphone authorization revoked.');
    try {
      await session.room.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {
      // Still terminate the session.
    }
    try {
      await session.end();
    } catch (_) {
      // A failed network teardown is not proof of continued capture.
    } finally {
      await session.dispose();
    }
    _updateStatus('Disconnected');
  }

  void _updateStatus(String text) {
    if (mounted) setState(() => _status = text);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundGate.wentToBackground();
    _endpointController.dispose();
    _textController.dispose();
    // Called only when detached from UI. Widgets must call _disconnect before
    // navigation where possible. No background work is intentionally started.
    unawaited(_disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('GREENSOIL // VOICE LAB')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Icon(Icons.graphic_eq, size: 78, color: Color(0xff00d9f4)),
              const SizedBox(height: 12),
              const Text('Isolated LiveKit voice client',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Experimental connection test only. Not the JARVIS 3D home. '
                'No Gemini or LiveKit secret is bundled. A separately running '
                'agent and authenticated token endpoint are required.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _endpointController,
                enabled: !_connected && !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'HTTPS token endpoint',
                  hintText: 'https://your-server.example/api/livekit-token',
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _busy ? null : (_connected ? _disconnect : _connect),
                icon: Icon(_connected ? Icons.call_end : Icons.mic),
                label: Text(_connected ? 'Disconnect' : 'Connect with mic consent'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _connected && !_busy ? _toggleMicrophone : null,
                icon: Icon(_microphoneOn ? Icons.mic : Icons.mic_off),
                label: Text(_microphoneOn ? 'Mute microphone' : 'Unmute microphone'),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _textController,
                enabled: _connected,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Send text to agent',
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _connected ? _sendText : null,
                child: const Text('Send text'),
              ),
              const SizedBox(height: 20),
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                'Barge-in, local TTS cancellation, Tamil recognition, '
                'background listening and remote audio-drain acknowledgment '
                'are NOT enabled or verified here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.amberAccent),
              ),
            ],
          ),
        ),
      );
}
