import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../live_voice_session.dart';
import 'gemini_live_protocol.dart';

/// Short-lived credential minted by the owner's backend. The APK never holds
/// a Gemini API key; the backend holds it and returns a constrained,
/// single-use `auth_tokens/...` value.
class LiveTokenGrant {
  const LiveTokenGrant(this.token, this.expiresAt, {this.model});
  final String token;
  final DateTime expiresAt;
  final String? model;
}

class LiveTokenException implements Exception {
  const LiveTokenException(this.message);
  final String message;
  @override
  String toString() => 'LiveTokenException: $message';
}

class LiveTokenClient {
  LiveTokenClient({required this.endpoint, required this.ownerSessionToken,
      http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final String endpoint;
  final String ownerSessionToken;
  final http.Client _client;
  final DateTime Function() _now;
  static const maxLifetime = Duration(minutes: 35);

  static String? validateEndpoint(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasAuthority) return 'Enter a full https:// URL';
    if (u.scheme != 'https') return 'Token broker must use HTTPS';
    if (u.userInfo.isNotEmpty || u.queryParameters.keys.any(
        (k) => k.toLowerCase().contains('key') || k.toLowerCase().contains('token'))) {
      return 'Do not put credentials in the URL';
    }
    return null;
  }

  Future<LiveTokenGrant> fetch({required String locale}) async {
    if (validateEndpoint(endpoint) != null) {
      throw const LiveTokenException('Token broker not configured');
    }
    final res = await _client.post(Uri.parse(endpoint), headers: {
      'Authorization': 'Bearer $ownerSessionToken',
      'Content-Type': 'application/json',
    }, body: jsonEncode({'purpose': 'gemini_live', 'locale': locale, 'freeOnly': true}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 429) {
      throw const LiveTokenException('Free quota exhausted; use offline voice');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const LiveTokenException('Token broker rejected this device');
    }
    if (res.statusCode != 200) throw const LiveTokenException('Token broker unavailable');
    final Object? j;
    try {
      j = jsonDecode(res.body);
    } catch (_) {
      throw const LiveTokenException('Token broker returned invalid data');
    }
    if (j is! Map) throw const LiveTokenException('Token broker returned invalid data');
    if (j['billingEnabled'] != false || j['freeTier'] != true || j['estimatedCostInr'] != 0) {
      throw const LiveTokenException('Free-only: broker billing state unverified; cloud blocked');
    }
    final token = '${j['token'] ?? ''}';
    final exp = DateTime.tryParse('${j['expireTime'] ?? ''}');
    if (token.isEmpty || exp == null) throw const LiveTokenException('Token missing expiry');
    if (!token.startsWith('auth_tokens/')) {
      // A raw API key must never reach the phone.
      throw const LiveTokenException('Broker returned a long-lived key; refused');
    }
    final now = _now();
    if (!exp.isAfter(now)) throw const LiveTokenException('Token already expired');
    if (exp.difference(now) > maxLifetime) {
      throw const LiveTokenException('Token lifetime too long; refused');
    }
    return LiveTokenGrant(token, exp, model: j['model'] is String ? j['model'] as String : null);
  }
}

/// Minimal socket abstraction so the transport can be tested without network.
abstract interface class LiveSocket {
  Stream<dynamic> get frames;
  void send(String text);
  Future<void> close();
}

class IoLiveSocket implements LiveSocket {
  IoLiveSocket(this._ws);
  final WebSocket _ws;
  static Future<LiveSocket> connect(Uri uri) async {
    final ws = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 12));
    ws.pingInterval = const Duration(seconds: 20);
    return IoLiveSocket(ws);
  }

  @override
  Stream<dynamic> get frames => _ws;
  @override
  void send(String text) => _ws.add(text);
  @override
  Future<void> close() => _ws.close(WebSocketStatus.normalClosure);
}

/// Native audio I/O boundary (see LiveAudioBridge.kt).
abstract interface class LiveAudioIo {
  Stream<Map<Object?, Object?>> get events; // mic chunks, focus and route events
  Future<bool> startCapture();
  Future<void> stopCapture();
  Future<void> play(Uint8List pcm, int rate);
  Future<void> flush();
  Future<void> release();
}

class NativeLiveAudio implements LiveAudioIo {
  static const _m = MethodChannel('greensoil/live_audio');
  static const _e = EventChannel('greensoil/live_audio/events');
  Stream<Map<Object?, Object?>>? _events;

  @override
  Stream<Map<Object?, Object?>> get events => _events ??= _e
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .cast<Map<Object?, Object?>>();
  @override
  Future<bool> startCapture() async => (await _m.invokeMethod<bool>('startCapture')) ?? false;
  @override
  Future<void> stopCapture() => _m.invokeMethod('stopCapture');
  @override
  Future<void> play(Uint8List pcm, int rate) =>
      _m.invokeMethod('play', {'pcm': pcm, 'rate': rate});
  @override
  Future<void> flush() => _m.invokeMethod('flush');
  @override
  Future<void> release() => _m.invokeMethod('release');
}

enum LiveDropReason { serverClosed, goAway, focusLost, audioDevice, protocol }

/// Real Gemini Live transport: fetches an ephemeral token, opens the
/// constrained WebSocket, streams 16 kHz mic PCM, plays model audio and
/// supports barge-in (server `interrupted` flushes playback immediately).
class GeminiLiveTransport implements LiveVoiceTransport {
  GeminiLiveTransport({
    required this.tokens,
    required this.audio,
    required this.model,
    Future<LiveSocket> Function(Uri uri)? socketFactory,
    this.setupTimeout = const Duration(seconds: 10),
    this.systemInstruction,
  }) : _socketFactory = socketFactory ?? IoLiveSocket.connect;

  final LiveTokenClient tokens;
  final LiveAudioIo audio;
  final String model;
  final String? systemInstruction;
  final Duration setupTimeout;
  final Future<LiveSocket> Function(Uri uri) _socketFactory;

  LiveSocket? _socket;
  StreamSubscription<dynamic>? _frames;
  StreamSubscription<Map<Object?, Object?>>? _audioSub;
  bool muted = false;
  bool _closing = false;
  int _epoch = 0;
  bool _dropped = false;

  // Observable outputs for the UI (all text stays on device).
  final _transcripts = StreamController<LiveTranscript>.broadcast();
  final _drops = StreamController<LiveDropReason>.broadcast();
  final _levels = StreamController<double>.broadcast();
  final _speaking = StreamController<bool>.broadcast();
  Stream<LiveTranscript> get transcripts => _transcripts.stream;
  Stream<LiveDropReason> get drops => _drops.stream;
  Stream<double> get levels => _levels.stream;
  Stream<bool> get speaking => _speaking.stream;
  int sentChunks = 0;
  int playedChunks = 0;

  @override
  Future<void> connect({required String voice, required String locale}) async {
    _closing = false;
    _dropped = false;
    final epoch = ++_epoch;
    final grant = await tokens.fetch(locale: locale);
    if (epoch != _epoch) throw const SocketException('cancelled');
    final socket = await _socketFactory(liveSocketUri(grant.token));
    if (epoch != _epoch) { await socket.close(); throw const SocketException('cancelled'); }
    _socket = socket;
    final setupDone = Completer<void>();
    _frames = socket.frames.listen((frame) {
      if (_closing || epoch != _epoch) return;
      for (final ev in parseServerFrame(frame)) {
        switch (ev) {
          case LiveSetupComplete():
            if (!setupDone.isCompleted) setupDone.complete();
          case LiveAudioOut(:final pcm, :final rate):
            playedChunks++;
            _speaking.add(true);
            _levels.add(pcmLevel(pcm));
            unawaited(audio.play(pcm, rate).catchError((Object _) { _drop(LiveDropReason.audioDevice); }));
          case LiveInterrupted():
            unawaited(audio.flush().catchError((Object _) { _drop(LiveDropReason.audioDevice); })); // barge-in
            _speaking.add(false);
          case LiveTurnComplete():
            _speaking.add(false);
          case LiveTranscript():
            _transcripts.add(ev);
          case LiveGoAway():
            _drop(LiveDropReason.goAway);
          case LiveUnknown():
            break;
        }
      }
    }, onError: (_) {
      if (!setupDone.isCompleted) setupDone.completeError(const SocketException('closed'));
      _drop(LiveDropReason.serverClosed);
    }, onDone: () {
      if (!setupDone.isCompleted) setupDone.completeError(const SocketException('closed'));
      _drop(LiveDropReason.serverClosed);
    });
    socket.send(buildSetupMessage(LiveConfig(
      model: grant.model ?? model, voice: voice, languageCode: locale,
      systemInstruction: systemInstruction)));
    try {
      await setupDone.future.timeout(setupTimeout);
    } catch (_) {
      await disconnect();
      rethrow;
    }
    _audioSub = audio.events.listen((e) {
      switch (e['type']) {
        case 'mic':
          final pcm = e['pcm'];
          if (pcm is Uint8List && !muted && _socket != null) {
            _levels.add(pcmLevel(pcm));
            _socket!.send(buildAudioChunk(pcm));
            sentChunks++;
          }
        case 'error':
          _drop(LiveDropReason.audioDevice);
        case 'focus':
          if (e['value'] == 'lost' || e['value'] == 'denied') _drop(LiveDropReason.focusLost);
        case 'route':
          if (e['value'] == 'noisy') muted = true; // headset unplugged: pause mic
      }
    });
    final ok = await audio.startCapture();
    if (!ok) {
      await disconnect();
      throw const SocketException('audio focus denied');
    }
  }

  void _drop(LiveDropReason r) {
    if (_closing || _dropped) return;
    _dropped = true;
    _drops.add(r);
  }

  @override
  Future<void> disconnect() async {
    _closing = true;
    ++_epoch;
    final s = _socket;
    _socket = null;
    try {
      s?.send(buildAudioStreamEnd());
    } catch (_) {}
    await _audioSub?.cancel();
    _audioSub = null;
    await _frames?.cancel();
    _frames = null;
    try {
      await audio.stopCapture();
      await audio.flush();
      await audio.release();
    } catch (_) {}
    try {
      await s?.close();
    } catch (_) {}
    _speaking.add(false);
  }
}
