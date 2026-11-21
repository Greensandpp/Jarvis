import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../avatar/avatar_runtime.dart' show publishAvatarSpeech, AvatarSound;
import 'edge_tts_service.dart';
import 'speech_output_controller.dart';
import 'gemini_dictation.dart';
import 'voice_selection.dart';
import 'settings_service.dart';

/// Voice interaction: native continuous speech-to-text for commands,
/// and high-quality studio text-to-speech for vocal responses.
class VoiceService {
  VoiceService._() {
    _initNativeSpeechChannel();
    AvatarSound.outputPlayer = playEffect;
  }
  static final VoiceService instance = VoiceService._();

  static const MethodChannel _nativeSpeechChannel =
      MethodChannel('com.privateagent/speech');
  final FlutterTts _tts = FlutterTts();

  bool _speechReady = false;
  bool _ttsReady = false;
  bool _listening = false;
  late final SpeechOutputController output = SpeechOutputController(
    stopDrivers: () async {
      await EdgeTtsService.instance.stop();
      try { await _tts.stop(); } catch (_) {}
      try { await _nativeSpeechChannel.invokeMethod('releaseOutputFocus'); } catch (_) {}
    },
    onSpeaking: (speaking) => isSpeaking.value = speaking,
  );

  final ValueNotifier<int> completedSpeech = ValueNotifier<int>(0);
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
          _trackRecognizerHealth(status);
          onSpeechStatus?.call(status);
          if (status == 'listening') {
            _listening = true;
            listeningNotifier.value = true;
            onListeningChanged?.call(true);
          } else if (status == 'notListening' || status == 'endOfSpeech' || status.startsWith('error:')) {
            _listening = false;
            listeningNotifier.value = false;
            onListeningChanged?.call(false);
          }
          break;
        case 'onOutputFocusLost':
          if ((call.arguments as num?)?.toInt() == output.activeRequestId) await stopSpeaking();
          break;
        case 'onSoundLevel':
          final level = (call.arguments as num?)?.toDouble() ?? 0.0;
          soundLevel.value = level;
          break;
      }
    });
  }

  // ---------------------------------------------------------------- engine

  int _fatalErrors = 0;
  bool _dictating = false;
  String lastSpeechEngine = 'device';

  /// Android SpeechRecognizer errors that mean "this recogniser cannot work
  /// here" (not a normal no-match / timeout): network(2), audio(3),
  /// server(4), client(5), busy(10/11), language not supported /
  /// unavailable(12/13). Missing mic permission (9) is not a recogniser
  /// fault — granting the permission fixes it — so it is not counted.
  static const fatalRecognizerErrors = {2, 3, 4, 5, 10, 11, 12, 13};

  void _trackRecognizerHealth(String status) {
    if (status == 'listening') return;
    if (!status.startsWith('error:')) return;
    final code = int.tryParse(status.substring(6));
    if (code == null || !fatalRecognizerErrors.contains(code)) {
      if (code == 6 || code == 7) _fatalErrors = 0; // normal silence / no match
      return;
    }
    _fatalErrors++;
    if (_fatalErrors >= 2) unawaited(SettingsService.instance.setDeviceSpeechBroken(true));
  }

  /// Which engine a listen request uses. Gemini voice input only for explicit
  /// mic taps (never always-on wake-word listening) and only when allowed.
  @visibleForTesting
  static String engineFor({required String setting, required bool manual, required bool deviceAvailable,
      required bool deviceBroken, required bool geminiAllowed}) {
    if (!manual || !geminiAllowed) return 'device';
    if (setting == 'gemini') return 'gemini';
    if (setting == 'auto' && (!deviceAvailable || deviceBroken)) return 'gemini';
    return 'device';
  }

  Future<bool> _startGeminiDictation(
      void Function(String words, bool isFinal, List<String> candidates) onResult) async {
    if (!await _ensureMicPermission()) return false;
    _dictating = true;
    _listening = true;
    lastSpeechEngine = 'gemini';
    listeningNotifier.value = true;
    onListeningChanged?.call(true);
    onSpeechStatus?.call('listening');
    unawaited(() async {
      var text = '';
      try {
        text = await GeminiDictation.instance.listenOnce(onLevel: (l) => soundLevel.value = l);
      } catch (e) {
        debugPrint('[VoiceService] Gemini voice input failed: $e');
        onSpeechStatus?.call('error:gemini');
      } finally {
        _dictating = false;
        _listening = false;
        soundLevel.value = 0;
        listeningNotifier.value = false;
        onListeningChanged?.call(false);
      }
      onSpeechStatus?.call('endOfSpeech');
      onResult(text, true, text.isEmpty ? const [] : [text]);
    }());
    return true;
  }

  Future<bool> _ensureMicPermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (_) {
      // Unknown permission state fails closed; tests must mock the permission channel.
      return false;
    }
  }

  Future<bool> initSpeech() async {
    if (!await _ensureMicPermission()) {
      _speechReady = false;
      return false;
    }
    if (_speechReady) return true;
    try {
      final available =
          await _nativeSpeechChannel.invokeMethod<bool>('isAvailable') ?? false;
      _speechReady = available;
    } catch (_) {
      _speechReady = false;
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
    await stopSpeaking();
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
    final s = SettingsService.instance;
    final engine = engineFor(
      setting: s.speechEngine,
      manual: manual,
      deviceAvailable: _speechReady || !(await _deviceRecognizerMissing()),
      deviceBroken: s.deviceSpeechBroken,
      geminiAllowed: GeminiDictation.instance.allowed,
    );
    if (engine == 'gemini') {
      if (_dictating) return true;
      if (_listening) await stopListening();
      onSpeechResult = onResult;
      return _startGeminiDictation(onResult);
    }
    lastSpeechEngine = 'device';
    if (!await initSpeech()) return false;
    onSpeechResult = onResult;
    if (_listening && continuous && !manual) {
      // Already running continuous listening loop
      return true;
    }
    try {
      final accepted = await _nativeSpeechChannel.invokeMethod<bool>('startListening', {
        'continuous': continuous,
        'manual': manual,
        'locale': SettingsService.instance.speechInputLocale,
      });
      // Capture becomes active only on the real recognizer ready event.
      return accepted == true;
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
    if (_dictating) GeminiDictation.instance.stop();
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

  int? _effectRequestId;
  Future<void> stopEffect() async {
    final id = _effectRequestId;
    if (id != null && id == output.activeRequestId) await output.stop();
    if (_effectRequestId == id) _effectRequestId = null;
  }

  /// Optional local intro/outro tones share the same owner and yield to speech.
  /// They never set SPEAKING or emit an assistant-completion event.
  Future<void> playEffect(String path) async {
    if (output.activeRequestId != null || output.externalSession) return;
    await output.speak((ticket) async {
      _effectRequestId = ticket.id;
      try {
        final granted = await _nativeSpeechChannel.invokeMethod<bool>('acquireOutputFocus', {'requestId': ticket.id}) ?? false;
        if (ticket.cancelled || !granted) return;
        await const MethodChannel('com.privateagent/accessibility').invokeMethod('playAudioFile', {'path': path});
      } catch (_) {
        // Effects are optional and must never block the home screen.
      } finally {
        if (!ticket.cancelled) {
          try { await _nativeSpeechChannel.invokeMethod('releaseOutputFocus'); } catch (_) {}
        }
        if (_effectRequestId == ticket.id) _effectRequestId = null;
      }
    }, speaking: false);
  }

  Future<void> speak(String text) => speakIn(text,
      languageTag: SettingsService.instance.jarvisNeuralVoice.startsWith('ta-') ? 'ta-IN' : 'en-IN',
      neuralVoice: SettingsService.instance.jarvisNeuralVoice,
      female: SettingsService.instance.preferFemaleVoice);

  Future<void> speakIn(
    String text, {
    required String languageTag,
    required String neuralVoice,
    required bool female,
  }) async {
    final clean = sanitizeForSpeech(text);
    if (clean.isEmpty) return;
    await output.speak((ticket) async {
      if (_listening) await stopListening();
      if (ticket.cancelled) return;
      bool focused = false;
      try {
        focused =
            await _nativeSpeechChannel.invokeMethod<bool>(
              'acquireOutputFocus',
              {'requestId': ticket.id},
            ) ??
            false;
      } catch (_) {}
      if (ticket.cancelled) return;
      if (!focused) {
        lastVoiceUsed = 'Audio focus unavailable — text only';
        return;
      }
      try {
        publishAvatarSpeech(clean, languageTag: languageTag);
        final settings = SettingsService.instance;
        if (neuralVoice.isNotEmpty &&
            settings.useNeuralVoice &&
            settings.allowCloudTts) {
          final played = await EdgeTtsService.instance.speak(
            clean,
            voice: neuralVoice,
          );
          if (ticket.cancelled) return;
          if (played) {
            completedSpeech.value++;
            lastVoiceUsed = 'neural $neuralVoice';
            return;
          }
        }
        await initTts();
        if (ticket.cancelled || !_ttsReady) return;
        final supported = await _tts.isLanguageAvailable(languageTag);
        if (ticket.cancelled) return;
        if (supported != true) {
          lastVoiceUsed = '$languageTag unavailable — text only';
          return;
        }
        await _tts.setLanguage(languageTag);
        final used = await _applyLocalVoice(languageTag, female: female);
        if (ticket.cancelled) return;
        if (used == null) {
          lastVoiceUsed = '$languageTag offline voice unavailable — text only';
          return;
        }
        lastVoiceUsed = 'local $languageTag · $used';
        final result = await _tts.speak(clean);
        if (!ticket.cancelled && (result == 1 || result == true)) completedSpeech.value++;
      } finally {
        // A cancelled request must never release the newer owner's focus.
        if (!ticket.cancelled) {
          try {
            await _nativeSpeechChannel.invokeMethod('releaseOutputFocus');
          } catch (_) {}
        }
      }
    });
  }

  String lastVoiceUsed = 'none yet';

  bool? _recognizerMissing;
  Future<bool> _deviceRecognizerMissing() async {
    if (_recognizerMissing != null) return _recognizerMissing!;
    try {
      final ok = await _nativeSpeechChannel.invokeMethod<bool>('isAvailable');
      _recognizerMissing = ok == false;
    } catch (_) {
      _recognizerMissing = false; // unknown: keep the original behaviour
    }
    return _recognizerMissing!;
  }

  List<TtsVoice>? _voices;

  /// Installed TTS voices (cached; refreshed by [autoSelectVoices]).
  Future<List<TtsVoice>> installedVoices({bool refresh = false}) async {
    if (_voices != null && !refresh) return _voices!;
    try {
      final dynamic raw = await _tts.getVoices;
      _voices = raw is List ? raw.map(TtsVoice.fromMap).whereType<TtsVoice>().toList() : <TtsVoice>[];
    } catch (_) {
      _voices = <TtsVoice>[];
    }
    return _voices!;
  }

  /// Picks the best installed Tamil and Indian-English voice (female when
  /// preferred, offline first) and stores the choice + reason. Pinned voices
  /// chosen by the owner are kept.
  Future<Map<String, VoiceChoice>> autoSelectVoices() async {
    final s = SettingsService.instance;
    final all = await installedVoices(refresh: true);
    final out = <String, VoiceChoice>{};
    for (final lang in const ['ta-IN', 'en-IN']) {
      final c = chooseVoice(all, lang, preferFemale: s.preferFemaleVoice, pinned: s.ttsVoicePinned(lang));
      out[lang] = c;
      await s.setTtsVoiceAuto(lang, c.voice?.name ?? '', c.reason);
    }
    return out;
  }

  /// Applies the chosen local voice for [languageTag] (offline fallback:
  /// the engine default for that language when nothing better exists).
  Future<String?> _applyLocalVoice(String languageTag, {required bool female}) async {
    final s = SettingsService.instance;
    final all = await installedVoices();
    final eligible = s.allowCloudTts ? all : all.where((v) => !v.networkRequired).toList();
    final c = chooseVoice(eligible, languageTag, preferFemale: female, pinned: s.ttsVoicePinned(languageTag));
    final v = c.voice;
    if (v != null) {
      try {
        final applied = await _tts.setVoice(v.toFlutterTts());
        if (applied == 1 || applied == true) return v.name;
        return null;
      } catch (_) {
        // Fall through to the engine default for the language.
      }
    }
    // An engine default can silently choose a network voice. Fail to text.
    return null;
  }

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
    final st = SettingsService.instance;
    out['Recognition language'] = st.speechInputLocale == 'auto'
        ? 'auto (Tamil + English + Tanglish)'
        : st.speechInputLocale;
    out['Speech engine'] = '${st.speechEngine}${st.deviceSpeechBroken ? ' · phone recogniser failed earlier → Gemini voice input on mic tap' : ''}'
        '${GeminiDictation.instance.allowed ? '' : ' · Gemini voice input unavailable: ${GeminiDictation.instance.unavailableReason}'}';
    out['Last speech engine'] = '$lastSpeechEngine (Gemini: ${GeminiDictation.instance.lastStatus})';
    for (final lang in const ['ta-IN', 'en-IN']) {
      final pinned = st.ttsVoicePinned(lang);
      out['Voice $lang'] = pinned.isNotEmpty
          ? '$pinned (chosen by you)'
          : '${st.ttsVoiceAuto(lang).isEmpty ? 'engine default' : st.ttsVoiceAuto(lang)} — ${st.ttsVoiceAutoReason(lang)}';
    }
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

  Future<void> stopSpeaking() => output.stop();
}
