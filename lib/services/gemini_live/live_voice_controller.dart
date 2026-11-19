import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../live_voice_session.dart';
import 'gemini_live_protocol.dart';
import 'gemini_live_transport.dart';

/// Owner settings for Gemini Live. The broker URL and the owner's device
/// session token are stored locally; no Gemini API key exists on the phone.
class LiveVoiceSettings {
  LiveVoiceSettings({
    this.brokerUrl = '',
    this.deviceToken = '',
    this.voice = 'Aoede',
    this.locale = 'ta-IN',
    this.model = 'gemini-live-2.5-flash-preview',
    this.disclosureAccepted = false,
  });
  String brokerUrl, deviceToken, voice, locale, model;
  bool disclosureAccepted;

  bool get configured => brokerUrl.isNotEmpty && deviceToken.isNotEmpty &&
      LiveTokenClient.validateEndpoint(brokerUrl) == null;

  static const _k = 'gemini_live_';
  static Future<LiveVoiceSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return LiveVoiceSettings(
      brokerUrl: p.getString('${_k}broker_url') ?? '',
      deviceToken: p.getString('${_k}device_token') ?? '',
      voice: p.getString('${_k}voice') ?? 'Aoede',
      locale: p.getString('${_k}locale') ?? 'ta-IN',
      model: p.getString('${_k}model') ?? 'gemini-live-2.5-flash-preview',
      disclosureAccepted: p.getBool('${_k}disclosure') ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('${_k}broker_url', brokerUrl.trim());
    await p.setString('${_k}device_token', deviceToken.trim());
    await p.setString('${_k}voice', voice);
    await p.setString('${_k}locale', locale);
    await p.setString('${_k}model', model.trim());
    await p.setBool('${_k}disclosure', disclosureAccepted);
  }
}

typedef TransportFactory = GeminiLiveTransport Function(LiveVoiceSettings s);

/// The single shared Live voice controller used by every visual mode.
/// - Never starts without an explicit tap + consent + granted mic permission.
/// - Pauses the existing wake-word recognizer before taking the microphone.
/// - Stops automatically when the app leaves the foreground.
/// - On a server GoAway, reconnects once with a fresh token; otherwise fails
///   visibly and waits for the owner.
class LiveVoiceController extends ChangeNotifier with WidgetsBindingObserver {
  LiveVoiceController({
    TransportFactory? transportFactory,
    Future<bool> Function()? requestMicPermission,
    Future<void> Function()? pauseOtherMic,
    bool observeLifecycle = true,
  })  : _factory = transportFactory ?? _defaultFactory,
        _requestMic = requestMicPermission ?? (() async => false),
        _pauseOtherMic = pauseOtherMic ?? (() async {}) {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  static GeminiLiveTransport _defaultFactory(LiveVoiceSettings s) => GeminiLiveTransport(
        tokens: LiveTokenClient(endpoint: s.brokerUrl, ownerSessionToken: s.deviceToken),
        audio: NativeLiveAudio(),
        model: s.model,
      );

  final TransportFactory _factory;
  final Future<bool> Function() _requestMic;
  final Future<void> Function() _pauseOtherMic;

  LiveVoiceSettings settings = LiveVoiceSettings();
  LiveVoiceSession? _session;
  GeminiLiveTransport? _transport;
  final List<StreamSubscription<dynamic>> _subs = [];
  int _reconnects = 0;
  double level = 0;
  bool modelSpeaking = false;
  String lastHeard = '';
  String lastSaid = '';
  String? message;

  LiveVoiceStatus get status => _session?.status ?? LiveVoiceStatus.idle;
  bool get active => status == LiveVoiceStatus.listening;
  bool get configured => settings.configured;
  bool get muted => _transport?.muted ?? false;

  Future<void> load() async {
    settings = await LiveVoiceSettings.load();
    notifyListeners();
  }

  Future<void> saveSettings(LiveVoiceSettings s) async {
    settings = s;
    await s.save();
    notifyListeners();
  }

  /// Explicit owner action only.
  Future<bool> start({required bool consent}) async {
    if (!consent) return false;
    if (!settings.configured) {
      message = 'DISCONNECTED · Gemini Live token broker not configured';
      notifyListeners();
      return false;
    }
    if (status != LiveVoiceStatus.idle && status != LiveVoiceStatus.failed) return false;
    if (!await _requestMic()) {
      message = 'Microphone permission is required for Live voice';
      notifyListeners();
      return false;
    }
    await _pauseOtherMic();
    await _teardown();
    final t = _factory(settings);
    _transport = t;
    final session = LiveVoiceSession(t);
    _session = session;
    session.addListener(notifyListeners);
    _subs
      ..add(t.transcripts.listen((tr) {
        if (tr.fromUser) {
          lastHeard = tr.text;
        } else {
          lastSaid = tr.text;
        }
        notifyListeners();
      }))
      ..add(t.levels.listen((l) => level = l))
      ..add(t.speaking.listen((s) {
        modelSpeaking = s;
        notifyListeners();
      }))
      ..add(t.drops.listen(_onDrop));
    message = null;
    final ok = await session.start(consent: true, voice: settings.voice, locale: settings.locale);
    if (!ok) message = session.error ?? 'Voice connection unavailable';
    notifyListeners();
    return ok;
  }

  Future<void> _onDrop(LiveDropReason r) async {
    final s = _session;
    if (s == null) return;
    if (r == LiveDropReason.goAway && _reconnects < 1) {
      _reconnects++;
      await s.stop();
      await start(consent: true);
      return;
    }
    await s.fail(switch (r) {
      LiveDropReason.focusLost => 'Live voice paused: another app took audio focus',
      LiveDropReason.goAway => 'Live session ended by server; tap to start again',
      _ => 'Live connection closed; tap to start again',
    });
    message = s.error;
    notifyListeners();
  }

  void toggleMute() {
    final t = _transport;
    if (t == null) return;
    t.muted = !t.muted;
    notifyListeners();
  }

  Future<void> stop() async {
    _reconnects = 0;
    await _session?.stop();
    await _teardown();
    modelSpeaking = false;
    level = 0;
    notifyListeners();
  }

  Future<void> _teardown() async {
    final subs = List.of(_subs);
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
    final old = _session;
    _session = null;
    if (old != null) {
      if (old.status != LiveVoiceStatus.idle && old.status != LiveVoiceStatus.failed) {
        await old.stop();
      }
      old.removeListener(notifyListeners);
      old.dispose();
    }
    _transport = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (active || status == LiveVoiceStatus.connecting) unawaited(stop());
    }
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final s = _session;
    s?.removeListener(notifyListeners);
    unawaited(_teardown());
    super.dispose();
  }

  /// Language hint shown in UI.
  String get languageLabel => LiveConfig.languages[settings.locale] ?? settings.locale;
}
