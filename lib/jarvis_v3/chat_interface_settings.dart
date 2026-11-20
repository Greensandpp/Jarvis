import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance -> Chat Interface, plus the introduction preferences.
/// Stored on the device only.
class ChatInterfaceSettings extends ChangeNotifier {
  ChatInterfaceSettings._();
  static final ChatInterfaceSettings instance = ChatInterfaceSettings._();

  /// Allowed auto-hide delays, in seconds.
  static const delays = [5, 8, 15, 30];

  static const _kAutoHide = 'v3_chat_auto_hide';
  static const _kDelay = 'v3_chat_auto_hide_delay_s';
  static const _kGlow = 'v3_chat_glow';
  static const _kFont = 'v3_chat_font_scale';
  static const _kOpacity = 'v3_chat_opacity';
  static const _kShowSpeaking = 'v3_chat_show_while_speaking';
  static const _kSave = 'v3_chat_save_history';
  static const _kIntro = 'v3_intro_enabled';
  static const _kIntroSound = 'v3_intro_sound';
  static const _kReduce = 'v3_reduce_motion';

  bool autoHide = true;
  int delaySeconds = 8;
  double glow = 0.6; // 0..1
  double fontScale = 1.0; // 0.85..1.4
  double opacity = 0.55; // bubble fill opacity 0.2..0.9
  bool showWhileSpeaking = true;
  bool saveHistory = true;
  bool introEnabled = true;
  bool introSound = false;
  bool reduceMotion = false;
  bool _loaded = false;
  bool get loaded => _loaded;

  Duration get delay => Duration(seconds: delaySeconds);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    autoHide = p.getBool(_kAutoHide) ?? true;
    final d = p.getInt(_kDelay) ?? 8;
    delaySeconds = delays.contains(d) ? d : 8;
    glow = (p.getDouble(_kGlow) ?? 0.6).clamp(0.0, 1.0);
    fontScale = (p.getDouble(_kFont) ?? 1.0).clamp(0.85, 1.4);
    opacity = (p.getDouble(_kOpacity) ?? 0.55).clamp(0.2, 0.9);
    showWhileSpeaking = p.getBool(_kShowSpeaking) ?? true;
    saveHistory = p.getBool(_kSave) ?? true;
    introEnabled = p.getBool(_kIntro) ?? true;
    introSound = p.getBool(_kIntroSound) ?? false;
    reduceMotion = p.getBool(_kReduce) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> update({
    bool? autoHide,
    int? delaySeconds,
    double? glow,
    double? fontScale,
    double? opacity,
    bool? showWhileSpeaking,
    bool? saveHistory,
    bool? introEnabled,
    bool? introSound,
    bool? reduceMotion,
  }) async {
    if (autoHide != null) this.autoHide = autoHide;
    if (delaySeconds != null && delays.contains(delaySeconds)) this.delaySeconds = delaySeconds;
    if (glow != null) this.glow = glow.clamp(0.0, 1.0);
    if (fontScale != null) this.fontScale = fontScale.clamp(0.85, 1.4);
    if (opacity != null) this.opacity = opacity.clamp(0.2, 0.9);
    if (showWhileSpeaking != null) this.showWhileSpeaking = showWhileSpeaking;
    if (saveHistory != null) this.saveHistory = saveHistory;
    if (introEnabled != null) this.introEnabled = introEnabled;
    if (introSound != null) this.introSound = introSound;
    if (reduceMotion != null) this.reduceMotion = reduceMotion;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoHide, this.autoHide);
    await p.setInt(_kDelay, this.delaySeconds);
    await p.setDouble(_kGlow, this.glow);
    await p.setDouble(_kFont, this.fontScale);
    await p.setDouble(_kOpacity, this.opacity);
    await p.setBool(_kShowSpeaking, this.showWhileSpeaking);
    await p.setBool(_kSave, this.saveHistory);
    await p.setBool(_kIntro, this.introEnabled);
    await p.setBool(_kIntroSound, this.introSound);
    await p.setBool(_kReduce, this.reduceMotion);
  }

  @visibleForTesting
  void resetForTest() {
    autoHide = true;
    delaySeconds = 8;
    glow = 0.6;
    fontScale = 1.0;
    opacity = 0.55;
    showWhileSpeaking = true;
    saveHistory = true;
    introEnabled = true;
    introSound = false;
    reduceMotion = false;
    _loaded = true;
  }
}
