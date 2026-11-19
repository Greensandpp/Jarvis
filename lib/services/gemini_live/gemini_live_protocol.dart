import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Wire protocol for the Gemini Live (BidiGenerateContent) WebSocket API.
/// Pure functions only: no I/O, no credentials. Audio in is 16 kHz mono
/// PCM16 little-endian; audio out is reported by the server (normally 24 kHz).

const liveInputRate = 16000;
const liveDefaultOutputRate = 24000;

/// Ephemeral-token endpoint. The access token is a short-lived
/// `auth_tokens/...` value minted by the owner's backend, never an API key.
Uri liveSocketUri(String accessToken, {String host = 'generativelanguage.googleapis.com'}) =>
    Uri(
      scheme: 'wss',
      host: host,
      path: '/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained',
      queryParameters: {'access_token': accessToken},
    );

class LiveConfig {
  const LiveConfig({
    required this.model,
    this.voice = 'Aoede',
    this.languageCode = 'ta-IN',
    this.systemInstruction,
  });
  final String model;
  final String voice;
  final String languageCode;
  final String? systemInstruction;

  /// Female-presenting prebuilt voices commonly offered by Gemini Live.
  /// Availability per model is not guaranteed and must be verified on device.
  static const femaleVoices = ['Aoede', 'Kore', 'Leda', 'Zephyr'];
  static const languages = {'ta-IN': 'Tamil', 'en-IN': 'English (India)'};
}

String buildSetupMessage(LiveConfig c) {
  final model = c.model.startsWith('models/') ? c.model : 'models/${c.model}';
  return jsonEncode({
    'setup': {
      'model': model,
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {'prebuiltVoiceConfig': {'voiceName': c.voice}},
          'languageCode': c.languageCode,
        },
      },
      if (c.systemInstruction != null)
        'systemInstruction': {
          'parts': [{'text': c.systemInstruction}],
        },
      'inputAudioTranscription': <String, dynamic>{},
      'outputAudioTranscription': <String, dynamic>{},
      'realtimeInputConfig': {
        'automaticActivityDetection': {'disabled': false},
        // Barge-in: user speech interrupts model playback.
        'activityHandling': 'START_OF_ACTIVITY_INTERRUPTS',
      },
    },
  });
}

String buildAudioChunk(Uint8List pcm16) => jsonEncode({
      'realtimeInput': {
        'audio': {'data': base64Encode(pcm16), 'mimeType': 'audio/pcm;rate=$liveInputRate'},
      },
    });

String buildAudioStreamEnd() => jsonEncode({
      'realtimeInput': {'audioStreamEnd': true},
    });

sealed class LiveServerEvent {
  const LiveServerEvent();
}

class LiveSetupComplete extends LiveServerEvent {
  const LiveSetupComplete();
}

class LiveAudioOut extends LiveServerEvent {
  const LiveAudioOut(this.pcm, this.rate);
  final Uint8List pcm;
  final int rate;
}

class LiveInterrupted extends LiveServerEvent {
  const LiveInterrupted();
}

class LiveTurnComplete extends LiveServerEvent {
  const LiveTurnComplete();
}

class LiveTranscript extends LiveServerEvent {
  const LiveTranscript(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

class LiveGoAway extends LiveServerEvent {
  const LiveGoAway(this.timeLeft);
  final String timeLeft;
}

class LiveUnknown extends LiveServerEvent {
  const LiveUnknown();
}

int _rateOf(String? mime) {
  final m = RegExp(r'rate=(\d+)').firstMatch(mime ?? '');
  return m == null ? liveDefaultOutputRate : int.parse(m.group(1)!);
}

/// Parses one server frame (text or binary JSON) into zero or more events.
List<LiveServerEvent> parseServerFrame(Object frame) {
  final String text;
  if (frame is String) {
    text = frame;
  } else if (frame is List<int>) {
    text = utf8.decode(frame, allowMalformed: true);
  } else {
    return const [LiveUnknown()];
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return const [LiveUnknown()];
  }
  if (decoded is! Map<String, dynamic>) return const [LiveUnknown()];
  final out = <LiveServerEvent>[];
  if (decoded.containsKey('setupComplete')) out.add(const LiveSetupComplete());
  final sc = decoded['serverContent'];
  if (sc is Map<String, dynamic>) {
    if (sc['interrupted'] == true) out.add(const LiveInterrupted());
    final turn = sc['modelTurn'];
    if (turn is Map && turn['parts'] is List) {
      for (final p in turn['parts'] as List) {
        final inline = p is Map ? p['inlineData'] : null;
        if (inline is Map && '${inline['mimeType']}'.startsWith('audio/pcm') &&
            inline['data'] is String) {
          try {
            out.add(LiveAudioOut(base64Decode(inline['data'] as String),
                _rateOf(inline['mimeType'] as String?)));
          } catch (_) {/* malformed chunk dropped */}
        }
      }
    }
    final inT = sc['inputTranscription'];
    if (inT is Map && inT['text'] is String) {
      out.add(LiveTranscript(inT['text'] as String, fromUser: true));
    }
    final outT = sc['outputTranscription'];
    if (outT is Map && outT['text'] is String) {
      out.add(LiveTranscript(outT['text'] as String, fromUser: false));
    }
    if (sc['turnComplete'] == true) out.add(const LiveTurnComplete());
  }
  final ga = decoded['goAway'];
  if (ga is Map) out.add(LiveGoAway('${ga['timeLeft'] ?? ''}'));
  return out.isEmpty ? const [LiveUnknown()] : out;
}

/// Linear resampler for mono PCM16 LE (used if a device cannot capture at
/// 16 kHz natively).
Uint8List resamplePcm16(Uint8List input, int fromRate, int toRate) {
  if (fromRate == toRate || input.length < 4) return input;
  final src = ByteData.sublistView(input);
  final n = input.length ~/ 2;
  final outN = (n * toRate / fromRate).floor();
  final out = ByteData(outN * 2);
  for (var i = 0; i < outN; i++) {
    final pos = i * fromRate / toRate;
    final i0 = pos.floor().clamp(0, n - 1);
    final i1 = (i0 + 1).clamp(0, n - 1);
    final frac = pos - i0;
    final s = src.getInt16(i0 * 2, Endian.little) * (1 - frac) +
        src.getInt16(i1 * 2, Endian.little) * frac;
    out.setInt16(i * 2, s.round().clamp(-32768, 32767), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// RMS level 0..1 of a PCM16 chunk, for the state-bound animation.
double pcmLevel(Uint8List pcm) {
  if (pcm.length < 2) return 0;
  final d = ByteData.sublistView(pcm);
  var sum = 0.0;
  final n = pcm.length ~/ 2;
  for (var i = 0; i < n; i++) {
    final v = d.getInt16(i * 2, Endian.little) / 32768.0;
    sum += v * v;
  }
  final rms = math.sqrt(sum / n);
  return (rms * 4).clamp(0.0, 1.0).toDouble();
}
