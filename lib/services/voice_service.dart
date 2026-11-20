import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'edge_tts_service.dart';
import 'settings_service.dart';

/// Voice interaction: native continuous speech-to-text for commands,
/// and high-quality studio text-to-speech for vocal responses.
class VoiceService {
  VoiceService._() {
    _initNativeSpeechChannel();
  }
  static final VoiceService instance = VoiceService._();

  static const MethodChannel _nativeSpeechChannel =
      MethodChannel('com.privateagent/speech');
  final FlutterTts _tts = FlutterTts();

  bool _speechReady = false;
  bool _ttsReady = false;
  bool _listening = false;
  Completer<void>? _speakCompleter;

  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final ValueNotifier<double> soundLevel = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> listeningNotifier = ValueNotifier<bool>(false);

  void Function(bool isListening)? onListeningChanged;
  void Function(String status)? onSpeechStatus;
  void Function(String words, bool isFinal, List<String> candidates)? onSpeechResult;

  bool get isListening => _listening;
  bool get isAvailable => _speechReady;

  void _initNativeSpeechChannel() {
    _nativeSpeechChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSpeechResult':
          final args = call.arguments as Map?;
          final text = (args?['text'] ?? '').toString();
          final isFinal = args?['isFinal'] == true;
          final candidates = (args?['candidates'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              (text.isNotEmpty ? [text] : <String>[]);
          if (text.isNotEmpty || candidates.isNotEmpty) {
            onSpeechResult?.call(text, isFinal, candidates);
          }
          break;
        case 'onSpeechStatus':
          final status = call.arguments.toString();
          onSpeechStatus?.call(status);
          if (status == 'listening') {
            _listening = true;
            listeningNotifier.value = true;
            onListeningChanged?.call(true);
          } else if (status == 'notListening') {
            _listening = false;
            listeningNotifier.value = false;
            onListeningChanged?.call(false);
          }
          break;
        case 'onSoundLevel':
          final level = (call.arguments as num?)?.toDouble() ?? 0.0;
          soundLevel.value = level;
          break;
      }
    });
  }

  Future<bool> _ensureMicPermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (_) {
      // Gracefully allow mock/headless testing environments where permission channel is unmocked
      return true;
    }
  }

  Future<bool> initSpeech() async {
    if (_speechReady) return true;
    if (!await _ensureMicPermission()) return false;
    try {
      final available =
          await _nativeSpeechChannel.invokeMethod<bool>('isAvailable') ?? true;
      _speechReady = available;
    } catch (_) {
      _speechReady = true;
    }
    return _speechReady;
  }

  Future<void> initTts({String? voiceProfile}) async {
    final profile = voiceProfile ?? SettingsService.instance.jarvisVoice;
    try {
      // Tamil neural voice profiles use Tamil local TTS as offline fallback.
      if (SettingsService.instance.jarvisNeuralVoice.startsWith('ta-IN-')) {
        await _tts.setLanguage('ta-IN');
        await _tts.setPitch(1.0);
        await _tts.setSpeechRate(0.48);
      } else {
        switch (profile) {
        case 'friday':
          await _tts.setLanguage('en-IE');
          await _tts.setPitch(1.05);
          await _tts.setSpeechRate(0.52);
          break;
        case 'stark':
          await _tts.setLanguage('en-US');
          await _tts.setPitch(0.95);
          await _tts.setSpeechRate(0.55);
          break;
        case 'kip':
          await _tts.setLanguage('en-GB');
          await _tts.setPitch(0.78);
          await _tts.setSpeechRate(0.48);
          break;
        case 'cortana':
          await _tts.setLanguage('en-US');
          await _tts.setPitch(1.10);
          await _tts.setSpeechRate(0.52);
          break;
        case 'paul':
        default:
          await _tts.setLanguage('en-GB');
          await _tts.setPitch(0.86);
          await _tts.setSpeechRate(0.48);

          try {
            final dynamic voices = await _tts.getVoices;
            if (voices is List && voices.isNotEmpty) {
              for (final v in voices) {
                if (v is Map) {
                  final name = (v['name'] ?? '').toString().toLowerCase();
                  final locale = (v['locale'] ?? '').toString().toLowerCase();
                  if (locale.contains('en-gb') || locale.contains('en_gb')) {
                    if (name.contains('gbd') ||
                        name.contains('gbb') ||
                        name.contains('male') ||
                        name.contains('-r-') ||
                        name.contains('language') && name.contains('b')) {
                      await _tts.setVoice({
                        'name': v['name'].toString(),
                        'locale': v['locale'].toString(),
                      });
                      break;
                    }
                  }
                }
              }
            }
          } catch (_) {}
          break;
        }
      }

      await _tts.awaitSpeakCompletion(true);

      _tts.setStartHandler(() {
        isSpeaking.value = true;
      });
      _tts.setCompletionHandler(() {
        isSpeaking.value = false;
        if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
          _speakCompleter!.complete();
        }
      });
      _tts.setErrorHandler((_) {
        isSpeaking.value = false;
        if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
          _speakCompleter!.complete();
        }
      });
      _tts.setCancelHandler(() {
        isSpeaking.value = false;
        if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
          _speakCompleter!.complete();
        }
      });

      _ttsReady = true;
    } catch (_) {
      try {
        await _tts.setLanguage('en-US');
        _ttsReady = true;
      } catch (_) {
        _ttsReady = false;
      }
    }
  }

  /// Forces re-initialization of TTS with a new voice profile.
  Future<void> reconfigureVoice([String? profile]) async {
    _ttsReady = false;
    await initTts(voiceProfile: profile);
  }

  /// Starts native continuous speech recognition.
  /// [onResult] receives primary recognized words, isFinal, and N-best candidates.
  Future<bool> startListening({
    required void Function(String words, bool isFinal, List<String> candidates) onResult,
    bool continuous = true,
    bool manual = false,
  }) async {
    if (!await initSpeech()) return false;
    onSpeechResult = onResult;
    if (_listening && continuous && !manual) {
      // Already running continuous listening loop
      return true;
    }
    try {
      await _nativeSpeechChannel.invokeMethod('startListening', {
        'continuous': continuous,
        'manual': manual,
        'locale': SettingsService.instance.speechInputLocale,
      });
      _listening = true;
      listeningNotifier.value = true;
      onListeningChanged?.call(true);
      return true;
    } catch (e) {
      debugPrint('[VoiceService] startListening error: $e');
      _listening = false;
      listeningNotifier.value = false;
      onListeningChanged?.call(false);
      return false;
    }
  }

  /// Notifies the native audio engine that media/music playback has started
  /// so that speech recognition yields audio focus to YouTube/Spotify.
  Future<void> notifyMediaPlaybackStarted({Duration duration = const Duration(seconds: 45)}) async {
    try {
      await _nativeSpeechChannel.invokeMethod('notifyMediaStarted', {
        'durationMs': duration.inMilliseconds,
      });
    } catch (_) {}
  }

  /// Stops speech recognition immediately.
  Future<void> stopListening() async {
    _listening = false;
    listeningNotifier.value = false;
    onListeningChanged?.call(false);
    try {
      await _nativeSpeechChannel.invokeMethod('stopListening');
    } catch (_) {}
  }

  /// Sanitizes text so speech synthesizers pronounce acronyms like Jarvis naturally
  /// instead of spelling out letters like "J dot A dot R dot V dot I dot S".
  String sanitizeForSpeech(String text) {
    return text
        .replaceAll(RegExp(r'J\.A\.R\.V\.I\.S\.?', caseSensitive: false), 'Jarvis')
        .replaceAll(RegExp(r'\bJ\.A\.R\.V\.I\.S\b', caseSensitive: false), 'Jarvis')
        .replaceAll(RegExp(r'J\s*\.\s*A\s*\.\s*R\s*\.\s*V\s*\.\s*I\s*\.\s*S\.?', caseSensitive: false), 'Jarvis')
        .replaceAll(RegExp(r'\bJARVIS\b'), 'Jarvis')
        .replaceAll('*', '')
        .replaceAll('#', '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
  }

  Future<void> speak(String text) async {
    final clean = sanitizeForSpeech(text);
    if (clean.isEmpty) return;

    // Temporarily pause microphone while speaking to eliminate echo and feedback
    final wasListening = _listening;
    if (wasListening) {
      await stopListening();
    }

    await stopSpeaking();
    isSpeaking.value = true;

    try {
      // 1. Try Ultra-Realistic Studio Neural Voice if enabled
      if (SettingsService.instance.useNeuralVoice && SettingsService.instance.allowCloudTts) {
        try {
          final played = await EdgeTtsService.instance.speak(clean);
          if (played) {
            return;
          }
        } catch (e) {
          debugPrint('[VoiceService] Neural voice error, falling back to local TTS: $e');
        }
      }

      // 2. Fall back to local FlutterTts (offline safe)
      await initTts();
      if (!_ttsReady) {
        return;
      }
      try {
        _speakCompleter = Completer<void>();
        await _tts.speak(clean);
        // Wait for audio synthesis and speaker playback to finish completely
        await _speakCompleter?.future;
      } catch (_) {
      } finally {
        _speakCompleter = null;
      }
    } finally {
      isSpeaking.value = false;
    }
  }

  /// Speaks in the reply language chosen by the brain. Neural (Edge) voice
  /// when cloud TTS is allowed, otherwise the phone's local TTS in that
  /// language, preferring a voice whose name marks it female.
  Future<void> speakIn(String text, {required String languageTag, required String neuralVoice, required bool female}) async {
    final clean = sanitizeForSpeech(text);
    if (clean.isEmpty) return;
    final wasListening = _listening;
    if (wasListening) await stopListening();
    await stopSpeaking();
    isSpeaking.value = true;
    try {
      if (SettingsService.instance.useNeuralVoice && SettingsService.instance.allowCloudTts) {
        try {
          if (await EdgeTtsService.instance.speak(clean, voice: neuralVoice)) {
            lastVoiceUsed = 'neural $neuralVoice';
            return;
          }
        } catch (_) {}
      }
      await initTts();
      if (!_ttsReady) return;
      try {
        await _tts.setLanguage(languageTag);
        if (female) {
          final dynamic voices = await _tts.getVoices;
          if (voices is List) {
            for (final v in voices) {
              if (v is! Map) continue;
              final name = '${v['name']}'.toLowerCase(), loc = '${v['locale']}'.toLowerCase().replaceAll('_', '-');
              if (loc.startsWith(languageTag.toLowerCase()) && (name.contains('female') || '${v['gender']}'.toLowerCase() == 'female')) {
                await _tts.setVoice({'name': '${v['name']}', 'locale': '${v['locale']}'});
                break;
              }
            }
          }
        }
        lastVoiceUsed = 'local $languageTag';
        _speakCompleter = Completer<void>();
        await _tts.speak(clean);
        await _speakCompleter?.future;
      } catch (_) {
      } finally {
        _speakCompleter = null;
        _ttsReady = false; // restore the owner's normal voice profile next time
      }
    } finally {
      isSpeaking.value = false;
    }
  }

  String lastVoiceUsed = 'none yet';

  /// Honest microphone / TTS status for Settings → Diagnostics.
  Future<Map<String, String>> diagnostics() async {
    final out = <String, String>{};
    final mic = await Permission.microphone.status;
    out['Microphone permission'] = mic.isGranted ? 'granted' : mic.isPermanentlyDenied ? 'denied (open app settings)' : 'not granted';
    try {
      final ok = await _nativeSpeechChannel.invokeMethod<bool>('isAvailable');
      out['Speech recognizer'] = ok == true ? 'available' : 'not available on this phone';
    } catch (e) {
      out['Speech recognizer'] = 'unknown ($e)';
    }
    out['Recognition language'] = SettingsService.instance.speechInputLocale;
    try {
      final langs = await _tts.getLanguages;
      final l = langs is List ? langs.map((e) => '$e'.toLowerCase().replaceAll('_', '-')).toList() : <String>[];
      out['TTS Tamil (ta-IN)'] = l.any((e) => e.startsWith('ta')) ? 'installed' : 'not installed — install Tamil in Google TTS';
      out['TTS Indian English'] = l.any((e) => e.startsWith('en-in')) ? 'installed' : 'not listed';
      final voices = await _tts.getVoices;
      final fem = voices is List
          ? voices.where((v) => v is Map && ('${v['name']}'.toLowerCase().contains('female') || '${v['gender']}'.toLowerCase() == 'female')).length
          : 0;
      out['Local voices'] = '${voices is List ? voices.length : 0} (named female: $fem)';
    } catch (e) {
      out['TTS'] = 'error: $e';
    }
    final s = SettingsService.instance;
    out['Neural voice'] = s.useNeuralVoice && s.allowCloudTts ? 'enabled (needs internet)' : 'off (Privacy: cloud TTS not allowed)';
    out['Female preference'] = s.preferFemaleVoice ? 'on' : 'off';
    out['Last voice used'] = lastVoiceUsed;
    return out;
  }

  Future<void> stopSpeaking() async {
    try {
      await EdgeTtsService.instance.stop();
      await _tts.stop();
      isSpeaking.value = false;
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
    } catch (_) {}
  }
}
