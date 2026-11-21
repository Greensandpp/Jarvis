import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interaction mode of the home screen.
///
/// - [agent]: agent mode — tasks are executed on the device via the
///   observe → think → act loop (accessibility service required).
/// - [chat]: plain chatbot mode — messages get a conversational LLM reply,
///   no screen reading and no device actions.
/// - [jarvis]: JARVIS mode — hands-free voice-first autonomous agent & assistant
///   with live holographic Iron Man HUD animation, intelligent action/chat routing,
///   and full device control.
enum AppMode { agent, chat, jarvis }

/// Visual HUD display style for JARVIS mode.
///
/// - [arcReactor]: Arc Reactor (3D spherical consciousness core with gyroscopic armillary rings).
/// - [jarvis]: Jarvis (3D Iron Man hologram suit avatar with reactive telemetry).
enum JarvisScreenStyle { arcReactor, jarvis }

/// Central, observable store for all user-configurable settings.
///
/// Backed by SharedPreferences. Access via [SettingsService.instance] after
/// calling [init] once at app start.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;

  bool get isReady => _prefs != null;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Ensure system prompt is enabled so models always receive the agent action grammar
    if (_prefs?.getBool('ai_use_system_prompt') != true) {
      await _prefs?.setBool('ai_use_system_prompt', true);
    }
    // The default provider changed to Gemini. Owners who saved a key while
    // the old DeepSeek default applied keep exactly what they had.
    final p = _prefs;
    if (p != null && p.getString('ai_provider') == null && (p.getString('ai_api_key') ?? '').isNotEmpty) {
      await p.setString('ai_provider', (p.getString('ai_api_key') ?? '').startsWith('AIza') ? 'gemini' : 'deepseek');
    }
  }

  /// Ordered, user-selected Arc Reactor shortcut keys.
  /// App shortcuts are represented as `app:<Android app label or package>`.
  /// The allowlisted action catalog is rendered in the overlay editor.
  static const List<String> defaultArcShortcuts = [
    'open_tradingview', 'toggle_torch', 'payment_safety', 'summarize_screen',
  ];
  List<String> get arcShortcuts =>
      _prefs?.getStringList('arc_shortcuts_v1') ?? defaultArcShortcuts;
  Future<void> setArcShortcuts(List<String> value) async {
    // No duplicates; limits panel clutter and stored data.
    final cleaned = value.map((e) => e.trim()).where((e) => e.isNotEmpty)
        .toSet().take(20).toList();
    await _prefs?.setStringList('arc_shortcuts_v1', cleaned);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // AI provider
  // ------------------------------------------------------------------

  /// Well-known OpenAI-compatible providers.
  static const Map<String, ({String label, String baseUrl, String model})>
  providers = {
    'deepseek': (
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
    ),
    'openai': (
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
    ),
    'gemini': (
      label: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      // 2.0-flash returned HTTP 404 for some keys; requests now also fall back
      // to models discovered for the key (Settings → Test connection).
      model: 'gemini-2.5-flash',
    ),
    'openrouter': (
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openai/gpt-4o-mini',
    ),
    'nvidia': (
      label: 'NVIDIA NIM',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'meta/llama-3.3-70b-instruct',
    ),
    'ollama': (
      label: 'Ollama (local)',
      baseUrl: 'http://127.0.0.1:11434/v1',
      model: 'llama3.2',
    ),
    'custom': (label: 'Custom (OpenAI-compatible)', baseUrl: '', model: ''),
  };

  /// Google Gemini is the preferred provider for new installs; an existing
  /// stored choice is never overwritten.
  String get provider => _prefs?.getString('ai_provider') ?? 'gemini';
  Future<void> setProvider(String value) async {
    await _prefs?.setString('ai_provider', value);
    final preset = providers[value];
    if (preset != null && preset.baseUrl.isNotEmpty) {
      await _prefs?.setString('ai_base_url', preset.baseUrl);
      await _prefs?.setString('ai_model', preset.model);
    }
    // Models discovered for another provider do not apply here.
    await _prefs?.setStringList('ai_discovered_models', const []);
    await _prefs?.setInt('ai_models_discovered_at', 0);
    notifyListeners();
  }

  String get baseUrl =>
      _prefs?.getString('ai_base_url') ??
      providers[provider]?.baseUrl ??
      providers['gemini']!.baseUrl;
  Future<void> setBaseUrl(String value) async {
    await _prefs?.setString('ai_base_url', value.trim());
    notifyListeners();
  }

  /// Chat models discovered for the current key (GET {base}/models).
  List<String> get discoveredModels => _prefs?.getStringList('ai_discovered_models') ?? const [];
  Future<void> setDiscoveredModels(List<String> m) async {
    await _prefs?.setStringList('ai_discovered_models', m);
    notifyListeners();
  }

  /// "ONLINE" is only claimed after a real request succeeded.
  bool _verifiedThisSession = false;
  bool get aiVerified => _verifiedThisSession && (_prefs?.getBool('ai_verified') ?? false);
  int get aiLastOkAt => _prefs?.getInt('ai_last_ok_at') ?? 0;
  String get aiLastOkModel => _prefs?.getString('ai_last_ok_model') ?? '';
  String get aiLastErrorKind => _prefs?.getString('ai_last_error_kind') ?? '';

  Future<void> recordAiSuccess(String model) async {
    final changed = aiLastOkModel != model || aiLastErrorKind.isNotEmpty || !aiVerified;
    _verifiedThisSession = true;
    await _prefs?.setBool('ai_verified', true);
    await _prefs?.setInt('ai_last_ok_at', DateTime.now().millisecondsSinceEpoch);
    await _prefs?.setString('ai_last_ok_model', model);
    await _prefs?.setString('ai_last_error_kind', '');
    if (changed) notifyListeners();
  }

  Future<void> recordAiFailure(String kind) async {
    final changed = aiLastErrorKind != kind;
    await _prefs?.setString('ai_last_error_kind', kind);
    _verifiedThisSession = false;
    await _prefs?.setBool('ai_verified', false);
    if (changed) notifyListeners();
  }

  /// Automatic model selection (default ON). Choosing a model by hand in
  /// Settings or Diagnostics pins it (auto OFF) until auto is re-enabled.
  bool get modelAuto => _prefs?.getBool('ai_model_auto') ?? true;
  Future<void> setModelAuto(bool value) async {
    await _prefs?.setBool('ai_model_auto', value);
    notifyListeners();
  }

  /// When the model list was last discovered for this key (epoch ms).
  int get modelsDiscoveredAt => _prefs?.getInt('ai_models_discovered_at') ?? 0;
  Future<void> setModelsDiscoveredAt(int ms) async {
    await _prefs?.setInt('ai_models_discovered_at', ms);
  }

  /// One line shown everywhere the model appears (Settings, Diagnostics,
  /// Control Center, chat dock) so they can never disagree.
  String get modelLabel {
    final used = aiLastOkModel;
    final temp = used.isNotEmpty && used != model && aiVerified ? ' · last reply via $used' : '';
    return '$model (${modelAuto ? 'auto' : 'manual'})$temp';
  }

  /// Honest status line: never ONLINE without a verified request.
  String get aiStatusLabel {
    if (apiKey.isEmpty && provider != 'ollama') return 'CONFIGURATION MISSING';
    if (aiLastErrorKind == 'auth') return 'AUTH REQUIRED';
    if (const ['dns', 'connect', 'timeout'].contains(aiLastErrorKind)) return 'OFFLINE';
    if (aiLastErrorKind.isNotEmpty) return 'AI ERROR · ${aiLastErrorKind.toUpperCase()}';
    if (aiVerified) return 'AI ONLINE · $aiLastOkModel';
    return 'AI NOT VERIFIED · run test';
  }

  String get apiKey => _prefs?.getString('ai_api_key') ?? '';
  Future<void> setApiKey(String value) async {
    final key = value.trim();
    final changed = key != apiKey;
    await _prefs?.setString('ai_api_key', key);
    if (changed) {
      // A new key has its own model list; rediscover on next use.
      await _prefs?.setInt('ai_models_discovered_at', 0);
    }
    // Google AI Studio keys ("AIza…") only work with Gemini: select it so the
    // default settings work without further changes. A custom endpoint is kept.
    if (key.startsWith('AIza') && provider != 'gemini' && provider != 'custom') {
      await setProvider('gemini');
      return;
    }
    notifyListeners();
  }

  String get model =>
      _prefs?.getString('ai_model') ??
      providers[provider]?.model ??
      'gemini-2.5-flash';
  /// [pin] = chosen by the owner (turns automatic selection off).
  Future<void> setModel(String value, {bool pin = false}) async {
    final v = value.trim();
    final changed = v != model;
    await _prefs?.setString('ai_model', v);
    if (pin && changed) await _prefs?.setBool('ai_model_auto', false);
    notifyListeners();
  }

  /// Defaults to 2048 so reasoning models (which burn completion tokens on
  /// hidden thinking before answering) still have budget left for the reply.
  int get maxTokens => _prefs?.getInt('ai_max_tokens') ?? 2048;
  Future<void> setMaxTokens(int value) async {
    await _prefs?.setInt('ai_max_tokens', value.clamp(128, 16384));
    notifyListeners();
  }

  double get temperature => _prefs?.getDouble('ai_temperature') ?? 0.2;
  Future<void> setTemperature(double value) async {
    await _prefs?.setDouble('ai_temperature', value.clamp(0.0, 2.0));
    notifyListeners();
  }

  bool get useSystemPrompt => _prefs?.getBool('ai_use_system_prompt') ?? true;
  Future<void> setUseSystemPrompt(bool value) async {
    await _prefs?.setBool('ai_use_system_prompt', value);
    notifyListeners();
  }

  /// Neural online TTS sends the exact spoken text outside the phone.
  /// Keep it disabled unless separately authorized.
  bool get allowCloudTts => _prefs?.getBool('privacy_allow_cloud_tts') ?? false;
  Future<void> setAllowCloudTts(bool value) async {
    await _prefs?.setBool('privacy_allow_cloud_tts', value);
    notifyListeners();
  }

  /// Web search, weather, maps, radar and other third-party lookups can
  /// disclose queries or locations. Keep them opt-in and independent of AI.
  bool get allowExternalLookups =>
      _prefs?.getBool('privacy_allow_external_lookups') ?? false;
  Future<void> setAllowExternalLookups(bool value) async {
    await _prefs?.setBool('privacy_allow_external_lookups', value);
    notifyListeners();
  }

  /// Local network smart-home commands can transmit device names and actions.
  /// Keep disabled until the operator explicitly pairs a trusted controller.
  bool get allowSmartHomeNetwork =>
      _prefs?.getBool('privacy_allow_smart_home_network') ?? false;
  Future<void> setAllowSmartHomeNetwork(bool value) async {
    await _prefs?.setBool('privacy_allow_smart_home_network', value);
    notifyListeners();
  }

  /// Deny cloud AI requests by default. A user must explicitly enable them.
  /// This is a partial app-level safeguard, not a complete network firewall.
  bool get allowCloudAi => _prefs?.getBool('privacy_allow_cloud_ai') ?? false;
  Future<void> setAllowCloudAi(bool value) async {
    await _prefs?.setBool('privacy_allow_cloud_ai', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Agent loop
  // ------------------------------------------------------------------

  int get maxSteps => _prefs?.getInt('agent_max_steps') ?? 15;
  Future<void> setMaxSteps(int value) async {
    await _prefs?.setInt('agent_max_steps', value.clamp(3, 40));
    notifyListeners();
  }

  /// Delay between loop iterations, lets the UI settle after each action.
  int get stepDelayMs => _prefs?.getInt('agent_step_delay_ms') ?? 1200;
  Future<void> setStepDelayMs(int value) async {
    await _prefs?.setInt('agent_step_delay_ms', value.clamp(200, 10000));
    notifyListeners();
  }

  bool get skillsEnabled => _prefs?.getBool('agent_skills_enabled') ?? true;
  Future<void> setSkillsEnabled(bool value) async {
    await _prefs?.setBool('agent_skills_enabled', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Telegram
  // ------------------------------------------------------------------

  bool get telegramEnabled => _prefs?.getBool('telegram_enabled') ?? false;
  Future<void> setTelegramEnabled(bool value) async {
    await _prefs?.setBool('telegram_enabled', value);
    notifyListeners();
  }

  String get telegramToken => _prefs?.getString('telegram_token') ?? '';
  Future<void> setTelegramToken(String value) async {
    await _prefs?.setString('telegram_token', value.trim());
    notifyListeners();
  }

  /// Chat ids allowed to control the device. Empty = the first chat that
  /// messages the bot becomes the owner (and is remembered).
  List<String> get telegramAllowedChats =>
      _prefs?.getStringList('telegram_allowed_chats') ?? const [];
  Future<void> setTelegramAllowedChats(List<String> value) async {
    await _prefs?.setStringList('telegram_allowed_chats', value);
    notifyListeners();
  }

  String get telegramOwnerChatId =>
      _prefs?.getString('telegram_owner_chat') ?? '';
  Future<void> setTelegramOwnerChatId(String value) async {
    await _prefs?.setString('telegram_owner_chat', value.trim());
    notifyListeners();
  }

  int get telegramUpdateOffset => _prefs?.getInt('telegram_offset') ?? 0;
  Future<void> setTelegramUpdateOffset(int value) async {
    await _prefs?.setInt('telegram_offset', value);
  }

  // ------------------------------------------------------------------
  // ------------------------------------------------------------------
  // Interaction mode
  // ------------------------------------------------------------------

  /// Whether the home screen sends messages to the agent loop
  /// ([AppMode.agent]), treats them as plain conversation
  /// ([AppMode.chat]), or enters voice-first hands-free ([AppMode.jarvis]).
  AppMode get appMode {
    final raw = _prefs?.getString('ui_app_mode') ?? 'agent';
    if (raw == 'genie') return AppMode.agent;
    return AppMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => AppMode.agent,
    );
  }

  Future<void> setAppMode(AppMode mode) async {
    await _prefs?.setString('ui_app_mode', mode.name);
    notifyListeners();
  }

  // Appearance, voice & onboarding
  // ------------------------------------------------------------------

  /// Visual HUD display style for JARVIS mode.
  /// Options: [JarvisScreenStyle.arcReactor] ("Arc Reactor"), [JarvisScreenStyle.jarvis] ("Jarvis").
  JarvisScreenStyle get jarvisScreenStyle {
    final raw = _prefs?.getString('jarvis_screen_style') ?? 'arcReactor';
    return JarvisScreenStyle.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => JarvisScreenStyle.arcReactor,
    );
  }

  Future<void> setJarvisScreenStyle(JarvisScreenStyle value) async {
    await _prefs?.setString('jarvis_screen_style', value.name);
    notifyListeners();
  }

  /// Tool-calling brain (open-ended reasoning + tools). When off, the original
  /// single-shot intent router is used.
  bool get brainToolCalling => _prefs?.getBool('jarvis_brain_tool_calling') ?? true;
  Future<void> setBrainToolCalling(bool v) async {
    await _prefs?.setBool('jarvis_brain_tool_calling', v);
    notifyListeners();
  }

  /// Reply language: auto (follow the user's Tamil / English / Tanglish), or fixed.
  String get replyLanguage {
    final v = _prefs?.getString('jarvis_reply_language') ?? 'auto';
    return const ['auto', 'english', 'tamil', 'tanglish'].contains(v) ? v : 'auto';
  }
  Future<void> setReplyLanguage(String v) async {
    if (!const ['auto', 'english', 'tamil', 'tanglish'].contains(v)) return;
    await _prefs?.setString('jarvis_reply_language', v);
    notifyListeners();
  }

  /// Prefer a female voice (Edge neural Pallavi/Neerja, or a female local TTS voice).
  bool get preferFemaleVoice => _prefs?.getBool('jarvis_prefer_female_voice') ?? true;
  Future<void> setPreferFemaleVoice(bool v) async {
    await _prefs?.setBool('jarvis_prefer_female_voice', v);
    notifyListeners();
  }

  /// Use Gemini embeddings for memory recall when online (keyword fallback offline).
  bool get semanticMemory => _prefs?.getBool('jarvis_semantic_memory') ?? true;
  Future<void> setSemanticMemory(bool v) async {
    await _prefs?.setBool('jarvis_semantic_memory', v);
    notifyListeners();
  }

  /// Whether JARVIS listens continuously like Google Home without tapping.
  bool get jarvisAlwaysOn => _prefs?.getBool('jarvis_always_on') ?? false;
  Future<void> setJarvisAlwaysOn(bool value) async {
    await _prefs?.setBool('jarvis_always_on', value);
    notifyListeners();
  }

  /// Microphone recognition language is independent of the spoken JARVIS voice.
  /// Indian English is a better default for local accents; Tamil can be selected.
  /// Microphone language: 'auto' = Tamil + English + Tanglish (Indian English
  /// recogniser with Tamil language detection on Android 14+, Gemini voice
  /// input fallback), or a fixed 'en-IN' / 'ta-IN' / 'en-GB'.
  static const speechLocales = ['auto', 'en-IN', 'ta-IN', 'en-GB'];
  String get speechInputLocale {
    final locale = _prefs?.getString('jarvis_speech_input_locale') ?? 'auto';
    return speechLocales.contains(locale) ? locale : 'auto';
  }

  Future<void> setSpeechInputLocale(String locale) async {
    if (!speechLocales.contains(locale)) return;
    await _prefs?.setString('jarvis_speech_input_locale', locale);
    notifyListeners();
  }

  /// Speech engine: 'auto' (phone recogniser; Gemini voice input on a mic tap
  /// when the phone recogniser is missing or keeps failing), 'device', 'gemini'.
  static const speechEngines = ['auto', 'device', 'gemini'];
  String get speechEngine {
    final e = _prefs?.getString('jarvis_speech_engine') ?? 'auto';
    return speechEngines.contains(e) ? e : 'auto';
  }

  Future<void> setSpeechEngine(String e) async {
    if (!speechEngines.contains(e)) return;
    await _prefs?.setString('jarvis_speech_engine', e);
    notifyListeners();
  }

  /// Set when the phone recogniser failed repeatedly (auto engine then uses
  /// Gemini voice input for mic taps). Cleared from Settings → Voice.
  bool get deviceSpeechBroken => _prefs?.getBool('jarvis_device_speech_broken') ?? false;
  Future<void> setDeviceSpeechBroken(bool v) async {
    if (v == deviceSpeechBroken) return;
    await _prefs?.setBool('jarvis_device_speech_broken', v);
    notifyListeners();
  }

  /// Local TTS voice per language: pinned by the owner ('' = automatic) and
  /// the automatic choice with its reason (for Diagnostics).
  String ttsVoicePinned(String lang) => _prefs?.getString('tts_voice_pinned_$lang') ?? '';
  Future<void> setTtsVoicePinned(String lang, String name) async {
    await _prefs?.setString('tts_voice_pinned_$lang', name);
    notifyListeners();
  }

  String ttsVoiceAuto(String lang) => _prefs?.getString('tts_voice_auto_$lang') ?? '';
  String ttsVoiceAutoReason(String lang) => _prefs?.getString('tts_voice_auto_reason_$lang') ?? '';
  Future<void> setTtsVoiceAuto(String lang, String name, String reason) async {
    await _prefs?.setString('tts_voice_auto_$lang', name);
    await _prefs?.setString('tts_voice_auto_reason_$lang', reason);
    notifyListeners();
  }

  /// Voice profile: 'paul' (British Jarvis), 'friday' (Irish), 'stark' (US), 'kip' (Deep), 'cortana' (Smooth).
  String get jarvisVoice => _prefs?.getString('jarvis_voice') ?? 'friday';
  Future<void> setJarvisVoice(String value) async {
    await _prefs?.setString('jarvis_voice', value);
    notifyListeners();
  }

  /// Studio Neural Voice (Edge-TTS) for ultra-realistic human speech.
  /// Defaults to en-GB-RyanNeural (Paul Bettany British JARVIS style).
  String get jarvisNeuralVoice =>
      _prefs?.getString('jarvis_neural_voice') ?? 'en-IN-NeerjaNeural';
  Future<void> setJarvisNeuralVoice(String value) async {
    await _prefs?.setString('jarvis_neural_voice', value);
    notifyListeners();
  }

  /// Whether to prioritize ultra-realistic neural human voices over offline TTS.
  bool get useNeuralVoice =>
      _prefs?.getBool('jarvis_use_neural_voice') ?? true;
  Future<void> setUseNeuralVoice(bool value) async {
    await _prefs?.setBool('jarvis_use_neural_voice', value);
    notifyListeners();
  }

  /// Self-evolving skills & workflows like Hermes Agent.
  bool get jarvisWorkflowsEnabled =>
      _prefs?.getBool('jarvis_workflows_enabled') ?? true;
  Future<void> setJarvisWorkflowsEnabled(bool value) async {
    await _prefs?.setBool('jarvis_workflows_enabled', value);
    notifyListeners();
  }

  /// Local-First Privacy Mode: forces on-device processing via local Ollama
  /// (127.0.0.1:11434) and offline voice synthesis, zero cloud data leakage.
  bool get localFirstPrivacyMode =>
      _prefs?.getBool('local_first_privacy_mode') ?? false;
  Future<void> setLocalFirstPrivacyMode(bool value) async {
    await _prefs?.setBool('local_first_privacy_mode', value);
    if (value) {
      await setProvider('ollama');
      await setUseNeuralVoice(false);
    }
    notifyListeners();
  }

  /// Permission system: prompts for explicit confirmation before high-risk operations
  /// (e.g. sending messages, placing calls, deleting data, purchases).
  bool get confirmRiskyActions =>
      _prefs?.getBool('confirm_risky_actions') ?? true;
  Future<void> setConfirmRiskyActions(bool value) async {
    await _prefs?.setBool('confirm_risky_actions', value);
    notifyListeners();
  }

  ThemeMode get themeMode {
    final raw = _prefs?.getString('ui_theme_mode') ?? 'system';
    return ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString('ui_theme_mode', mode.name);
    notifyListeners();
  }

  bool get onboardingComplete =>
      _prefs?.getBool('onboarding_complete') ?? false;
  Future<void> setOnboardingComplete(bool value) async {
    await _prefs?.setBool('onboarding_complete', value);
    notifyListeners();
  }

  /// Whether the assistant should speak results aloud via TTS.
  bool get voiceFeedback => _prefs?.getBool('voice_feedback') ?? false;
  Future<void> setVoiceFeedback(bool value) async {
    await _prefs?.setBool('voice_feedback', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Advanced Features: Smart Home, Commute, Jarvis Eye, Macro Recorder
  // ------------------------------------------------------------------

  /// Smart Home / Home Assistant URL (e.g. http://192.168.1.100:8123)
  String get homeAssistantUrl =>
      _prefs?.getString('smart_home_ha_url') ?? 'http://homeassistant.local:8123';
  Future<void> setHomeAssistantUrl(String value) async {
    await _prefs?.setString('smart_home_ha_url', value.trim());
    notifyListeners();
  }

  /// Home Assistant Long-Lived Access Token
  String get homeAssistantToken =>
      _prefs?.getString('smart_home_ha_token') ?? '';
  Future<void> setHomeAssistantToken(String value) async {
    await _prefs?.setString('smart_home_ha_token', value.trim());
    notifyListeners();
  }

  /// Whether Smart Home integration is enabled
  bool get smartHomeEnabled =>
      _prefs?.getBool('smart_home_enabled') ?? true;
  Future<void> setSmartHomeEnabled(bool value) async {
    await _prefs?.setBool('smart_home_enabled', value);
    notifyListeners();
  }

  /// Default Smart Home entity ID (e.g. light.living_room)
  String get smartHomeDefaultEntity =>
      _prefs?.getString('smart_home_default_entity') ?? 'light.living_room';
  Future<void> setSmartHomeDefaultEntity(String value) async {
    await _prefs?.setString('smart_home_default_entity', value.trim());
    notifyListeners();
  }

  /// Commute: Home address / origin
  String get commuteHomeAddress =>
      _prefs?.getString('commute_home_address') ?? 'Downtown';
  Future<void> setCommuteHomeAddress(String value) async {
    await _prefs?.setString('commute_home_address', value.trim());
    notifyListeners();
  }

  /// Commute: Work / standard destination address
  String get commuteWorkAddress =>
      _prefs?.getString('commute_work_address') ?? 'Tech Park';
  Future<void> setCommuteWorkAddress(String value) async {
    await _prefs?.setString('commute_work_address', value.trim());
    notifyListeners();
  }

  /// Commute travel mode: 'driving', 'transit', 'walking', 'cycling'
  String get commuteMode =>
      _prefs?.getString('commute_mode') ?? 'driving';
  Future<void> setCommuteMode(String value) async {
    await _prefs?.setString('commute_mode', value);
    notifyListeners();
  }

  /// Proactive Commute & Traffic warnings before meetings
  bool get proactiveCommuteEnabled =>
      _prefs?.getBool('proactive_commute_enabled') ?? true;
  Future<void> setProactiveCommuteEnabled(bool value) async {
    await _prefs?.setBool('proactive_commute_enabled', value);
    notifyListeners();
  }

  /// Jarvis Eye Multimodal Camera Perception
  bool get jarvisEyeEnabled =>
      _prefs?.getBool('jarvis_eye_enabled') ?? true;
  Future<void> setJarvisEyeEnabled(bool value) async {
    await _prefs?.setBool('jarvis_eye_enabled', value);
    notifyListeners();
  }

  /// Autonomous Macro Recorder
  bool get macroRecorderEnabled =>
      _prefs?.getBool('macro_recorder_enabled') ?? true;
  Future<void> setMacroRecorderEnabled(bool value) async {
    await _prefs?.setBool('macro_recorder_enabled', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Autonomous Proactive Vocalization & Scheduled Nudges
  // ------------------------------------------------------------------

  /// Master switch: whether JARVIS can speak up proactively on its own
  bool get jarvisAutoSpeakEnabled =>
      _prefs?.getBool('jarvis_auto_speak_enabled') ?? true;
  Future<void> setJarvisAutoSpeakEnabled(bool value) async {
    await _prefs?.setBool('jarvis_auto_speak_enabled', value);
    notifyListeners();
  }

  /// Whether JARVIS automatically opens a hands-free confirmation window
  /// ("Yes" or "No") after asking a proactive question
  bool get proactiveVoiceConfirmationEnabled =>
      _prefs?.getBool('proactive_voice_confirmation_enabled') ?? true;
  Future<void> setProactiveVoiceConfirmationEnabled(bool value) async {
    await _prefs?.setBool('proactive_voice_confirmation_enabled', value);
    notifyListeners();
  }

  /// Proactive Bedtime / Night Mode prompt (around 9:30 PM - 11 PM)
  bool get proactiveNightModePrompt =>
      _prefs?.getBool('proactive_night_mode_prompt') ?? true;
  Future<void> setProactiveNightModePrompt(bool value) async {
    await _prefs?.setBool('proactive_night_mode_prompt', value);
    notifyListeners();
  }

  /// Proactive Morning Briefing prompt (around 7:30 AM - 9 AM)
  bool get proactiveMorningBriefingPrompt =>
      _prefs?.getBool('proactive_morning_briefing_prompt') ?? true;
  Future<void> setProactiveMorningBriefingPrompt(bool value) async {
    await _prefs?.setBool('proactive_morning_briefing_prompt', value);
    notifyListeners();
  }

  /// Proactive Study & Focus Protocol prompt (afternoon study session)
  bool get proactiveStudyPrompt =>
      _prefs?.getBool('proactive_study_prompt') ?? true;
  Future<void> setProactiveStudyPrompt(bool value) async {
    await _prefs?.setBool('proactive_study_prompt', value);
    notifyListeners();
  }

  /// Proactive Remaining Tasks Review (late afternoon agenda check)
  bool get proactiveTaskReminderPrompt =>
      _prefs?.getBool('proactive_task_reminder_prompt') ?? true;
  Future<void> setProactiveTaskReminderPrompt(bool value) async {
    await _prefs?.setBool('proactive_task_reminder_prompt', value);
    notifyListeners();
  }

  /// Proactive Upcoming Meeting Reminders (15-30m before calendar events)
  bool get proactiveMeetingReminders =>
      _prefs?.getBool('proactive_meeting_reminders') ?? true;
  Future<void> setProactiveMeetingReminders(bool value) async {
    await _prefs?.setBool('proactive_meeting_reminders', value);
    notifyListeners();
  }

  /// Proactive Low Battery Warning (< 20%)
  bool get proactiveBatteryAlert =>
      _prefs?.getBool('proactive_battery_alert') ?? true;
  Future<void> setProactiveBatteryAlert(bool value) async {
    await _prefs?.setBool('proactive_battery_alert', value);
    notifyListeners();
  }
}
