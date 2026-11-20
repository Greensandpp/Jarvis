import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/avatar_settings.dart';

/// Identifier of the (single) avatar shipped today. Settings are stored per
/// avatar id so future avatars (final glTF Serpent Guardian, AIRA girl, …)
/// keep independent colours/sizes.
const serpentGuardianId = 'serpent_guardian';

/// Persistent per-avatar settings with a live notifier so open avatar views
/// update instantly while the user edits colours or sliders.
class AvatarSettingsStore {
  AvatarSettingsStore._();
  static final Map<String, ValueNotifier<AvatarSettings>> _live = {};

  static ValueNotifier<AvatarSettings> listenable(String avatarId) =>
      _live.putIfAbsent(avatarId, () => ValueNotifier<AvatarSettings>(AvatarSettings.defaults));

  static Future<AvatarSettings> load(String avatarId) async {
    final prefs = await SharedPreferences.getInstance();
    final s = AvatarSettings.decode(prefs.getString(AvatarSettings.storageKey(avatarId)));
    listenable(avatarId).value = s;
    return s;
  }

  static Future<void> save(String avatarId, AvatarSettings s) async {
    listenable(avatarId).value = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AvatarSettings.storageKey(avatarId), s.encode());
  }

  static Future<void> reset(String avatarId) => save(avatarId, AvatarSettings.defaults);
}

/// A line JARVIS is about to speak (feeds viseme lip sync).
class AvatarSpeechCue {
  AvatarSpeechCue(this.text, {this.languageTag = 'en-IN', this.rate = 1.0}) : at = DateTime.now();
  final String text;
  final String languageTag;
  final double rate;
  final DateTime at;
}

/// Published by VoiceService right before speech starts.
final ValueNotifier<AvatarSpeechCue?> avatarSpeechBus = ValueNotifier<AvatarSpeechCue?>(null);

void publishAvatarSpeech(String text, {String languageTag = 'en-IN', double rate = 1.0}) {
  if (text.trim().isEmpty) return;
  avatarSpeechBus.value = AvatarSpeechCue(text, languageTag: languageTag, rate: rate);
}

/// Commands for an on-screen avatar ('replay_intro', 'close').
final ValueNotifier<String?> avatarCommandBus = ValueNotifier<String?>(null);

void sendAvatarCommand(String command) {
  // Re-sending the same command must still notify.
  avatarCommandBus.value = null;
  avatarCommandBus.value = command;
}

/// Offline-synthesised intro / outro sounds (no audio assets, no network).
/// Played through the app's existing native MediaPlayer channel.
class AvatarSound {
  AvatarSound._();
  static const _channel = MethodChannel('com.privateagent/accessibility');
  static final Map<String, String> _files = {};

  static bool get _supported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  /// [kind] is 'intro' (rising energy charge) or 'outro' (falling power-down).
  static Future<void> play(String kind) async {
    if (!_supported) return;
    try {
      var path = _files[kind];
      if (path == null) {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/avatar_$kind.wav');
        await f.writeAsBytes(synthesize(kind), flush: true);
        path = _files[kind] = f.path;
      }
      await _channel.invokeMethod('playAudioFile', {'path': path});
    } catch (e) {
      debugPrint('[AvatarSound] $kind not played: $e');
    }
  }

  /// 16-bit mono WAV, 22.05 kHz: shimmering sweep with a soft hum bed.
  @visibleForTesting
  static Uint8List synthesize(String kind) {
    const rate = 22050;
    final seconds = kind == 'outro' ? 1.4 : 2.2;
    final n = (rate * seconds).round();
    final pcm = Int16List(n);
    var phase1 = 0.0, phase2 = 0.0, phase3 = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / rate;
      final k = t / seconds;
      final rising = kind != 'outro';
      final sweep = rising ? 140 + 520 * k * k : 520 - 420 * k;
      phase1 += 2 * math.pi * sweep / rate;
      phase2 += 2 * math.pi * (sweep * 2.01) / rate;
      phase3 += 2 * math.pi * 55 / rate;
      final shimmer = math.sin(2 * math.pi * (rising ? 7 + 18 * k : 18 - 14 * k) * t);
      final env = rising
          ? math.min(1.0, t / 0.25) * (1 - math.pow(k, 6).toDouble())
          : (1 - k) * math.min(1.0, t / 0.05);
      final s = (0.45 * math.sin(phase1) + 0.18 * math.sin(phase2) * (0.5 + 0.5 * shimmer) +
              0.22 * math.sin(phase3)) *
          env * 0.5;
      pcm[i] = (s * 32767).round().clamp(-32768, 32767).toInt();
    }
    final bytes = BytesBuilder();
    void str(String s) => bytes.add(s.codeUnits);
    void u32(int v) => bytes.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    void u16(int v) => bytes.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
    final data = pcm.buffer.asUint8List();
    str('RIFF');
    u32(36 + data.length);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(rate);
    u32(rate * 2);
    u16(2);
    u16(16);
    str('data');
    u32(data.length);
    bytes.add(data);
    return bytes.toBytes();
  }
}
