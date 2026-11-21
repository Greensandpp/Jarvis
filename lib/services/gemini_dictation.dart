import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../brain/ai_reliability.dart';
import '../brain/model_selector.dart';
import 'gemini_live/gemini_live_transport.dart';
import 'settings_service.dart';

/// Push-to-talk speech input through Gemini (Tamil, English and Tanglish).
///
/// Used when the phone's own speech recogniser is missing or keeps failing
/// (seen on the owner's iQOO 13), or when the owner picks "Gemini" as the
/// speech engine. Only runs on an explicit mic tap — never for always-on
/// wake-word listening — and only when cloud AI is allowed in Privacy.
/// Audio is recorded in memory (16 kHz mono PCM), sent once, and discarded.
class GeminiDictation {
  GeminiDictation({LiveAudioIo? audio, http.Client? client, SettingsService? settings})
      : _audio = audio,
        _client = client,
        _settingsOverride = settings;

  static final GeminiDictation instance = GeminiDictation();

  LiveAudioIo? _audio;
  http.Client? _client;
  final SettingsService? _settingsOverride;
  SettingsService get _s => _settingsOverride ?? SettingsService.instance;
  LiveAudioIo get audio => _audio ??= NativeLiveAudio();
  http.Client get client => _client ??= http.Client();
  set debugClient(http.Client c) => _client = c;
  set debugAudio(LiveAudioIo a) => _audio = a;

  static const sampleRate = 16000;
  Completer<void>? _stop;
  bool _busy = false;
  bool get busy => _busy;
  String lastStatus = 'idle';

  /// Why dictation cannot run right now, or null when it can.
  String? get unavailableReason {
    return 'free-only mode: cloud dictation billing unverified; use on-device recognition or text';
  }

  bool get allowed => unavailableReason == null;

  /// Stops recording early; the captured audio is still transcribed.
  void stop() {
    final c = _stop;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Records until [silence] after speech, [maxDuration], or [stop], then
  /// returns the transcript ('' when nothing was said). [onLevel] receives
  /// a 0..1 loudness per audio chunk (drives the mic/avatar animation).
  Future<String> listenOnce({
    void Function(double level)? onLevel,
    Duration maxDuration = const Duration(seconds: 12),
    Duration silence = const Duration(milliseconds: 1400),
    Duration noSpeechTimeout = const Duration(seconds: 6),
    double speechThreshold = 0.04,
  }) async {
    final why = unavailableReason;
    if (why != null) throw StateError('Gemini voice input unavailable: $why');
    if (_busy) throw StateError('Gemini voice input already running');
    _busy = true;
    lastStatus = 'recording';
    final pcm = BytesBuilder(copy: false);
    final stop = _stop = Completer<void>();
    var heardSpeech = false;
    var silentMs = 0;
    var totalMs = 0;
    StreamSubscription<Map<Object?, Object?>>? sub;
    try {
      sub = audio.events.listen((e) {
        if (e['type'] != 'mic') return;
        final chunk = e['pcm'];
        if (chunk is! Uint8List || chunk.isEmpty) return;
        pcm.add(chunk);
        final level = pcmLevel(chunk);
        onLevel?.call(level);
        final ms = chunk.length ~/ 2 * 1000 ~/ sampleRate;
        totalMs += ms;
        if (level >= speechThreshold) {
          heardSpeech = true;
          silentMs = 0;
        } else {
          silentMs += ms;
        }
        if ((heardSpeech && silentMs >= silence.inMilliseconds) ||
            totalMs >= maxDuration.inMilliseconds ||
            (!heardSpeech && totalMs >= noSpeechTimeout.inMilliseconds)) {
          if (!stop.isCompleted) stop.complete();
        }
      });
      final started = await audio.startCapture();
      if (!started) throw StateError('microphone could not start');
      await stop.future.timeout(maxDuration + const Duration(seconds: 2), onTimeout: () {});
    } finally {
      await sub?.cancel();
      try {
        await audio.stopCapture();
      } catch (_) {
        // Capture may already be stopped.
      }
      onLevel?.call(0);
      _stop = null;
    }
    try {
      if (!heardSpeech) {
        lastStatus = 'no speech';
        return '';
      }
      lastStatus = 'transcribing';
      final text = await transcribe(pcmToWav(pcm.takeBytes(), sampleRate));
      lastStatus = 'ok';
      return text;
    } catch (e) {
      lastStatus = 'failed: ${AiFailure.fromException(e).kind.name}';
      rethrow;
    } finally {
      _busy = false;
    }
  }

  static const prompt = 'Transcribe this voice command exactly as spoken. The speaker uses Tamil, English, or '
      'Tanglish (Tamil mixed with English). Write Tamil speech in Tamil script, English in English, and '
      'Tanglish exactly as spoken in English letters. Do not translate, answer or add anything. '
      'Output only the transcript. If there is no speech, output nothing.';

  /// Sends one WAV clip to Gemini (OpenAI-compatible `input_audio`) and
  /// returns the cleaned transcript. Uses the selected model with the same
  /// bounded 429/503 fallback as chat.
  Future<String> transcribe(Uint8List wav) async {
    final base = _s.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final body = (String model) => jsonEncode({
          'model': model,
          'temperature': 0,
          'max_tokens': 512,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'input_audio',
                  'input_audio': {'data': base64Encode(wav), 'format': 'wav'},
                },
              ],
            },
          ],
        });
    Future<String> send(String model) async {
      final r = await client
          .post(Uri.parse('$base/chat/completions'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${_s.apiKey}'},
              body: body(model))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw AiFailure.fromHttp(r.statusCode, r.body);
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final c = j['choices']?[0]?['message']?['content'];
      final text = c is String ? c : (c is List ? c.map((p) => p is Map ? '${p['text'] ?? ''}' : '$p').join() : '');
      return cleanTranscript(text);
    }

    final res = await callWithModelFallback<String>(
      selected: _s.model,
      ranked: rankModels(_s.discoveredModels, provider: _s.provider),
      attempt: send,
      maxAttempts: 3,
      deadline: const Duration(seconds: 40),
    );
    return res.value;
  }
}

/// RMS loudness of 16-bit little-endian PCM, scaled to 0..1.
double pcmLevel(Uint8List pcm) {
  final n = pcm.length ~/ 2;
  if (n == 0) return 0;
  final bd = ByteData.sublistView(pcm);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final v = bd.getInt16(i * 2, Endian.little) / 32768.0;
    sum += v * v;
  }
  final rms = math.sqrt(sum / n);
  return (rms * 4).clamp(0.0, 1.0).toDouble();
}

/// Wraps 16-bit mono PCM in a WAV header.
Uint8List pcmToWav(Uint8List pcm, int rate) {
  final h = ByteData(44);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      h.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  h.setUint32(4, 36 + pcm.length, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  str(36, 'data');
  h.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder()
        ..add(h.buffer.asUint8List())
        ..add(pcm))
      .toBytes();
}

/// Removes quotes / labels models sometimes add around a transcript.
String cleanTranscript(String raw) {
  var t = raw.trim();
  t = t.replaceFirst(RegExp(r'^(transcript|transcription)\s*:\s*', caseSensitive: false), '');
  if (t.length >= 2 && ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith('“') && t.endsWith('”')))) {
    t = t.substring(1, t.length - 1).trim();
  }
  if (RegExp(r'^\(?(no speech|silence|inaudible)\)?\.?$', caseSensitive: false).hasMatch(t)) return '';
  return t.replaceAll(RegExp(r'\s+'), ' ');
}
