import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../hybrid_conversation_context.dart';
import 'language_quality.dart';
import 'local_answer.dart';
import 'model_engine.dart';

class LocalBrainInterrupted implements Exception {}

/// File-only CPU inference in this app process. Importing is not activation:
/// actual phone memory, latency, language, battery and heat gates run first.
class LocalBrainService extends ChangeNotifier with WidgetsBindingObserver {
  LocalBrainService({PhoneModelEngine Function()? engineFactory,
    Future<Map<String, dynamic>> Function()? profile,
    Future<Map<String, dynamic>?> Function()? modelInfo,
    bool observeLifecycle = true})
      : _factory = engineFactory ?? (() => LlamaPhoneModel()),
        _profile = profile ?? _nativeProfile,
        _modelInfo = modelInfo ?? _nativeInfo {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
  }
  static final instance = LocalBrainService();
  static const channel = MethodChannel('greensoil/local_brain');
  static const reportKey = 'phone_local_brain_benchmark_v1';
  final PhoneModelEngine Function() _factory;
  final Future<Map<String, dynamic>> Function() _profile;
  final Future<Map<String, dynamic>?> Function() _modelInfo;
  PhoneModelEngine? _engine;
  Map<String, dynamic>? model, report;
  Future<void>? _initializing;
  Future<void> _inflight = Future.value();
  bool ready = false, busy = false, _foreground = true, _disposed = false;
  int _epoch = 0;
  String status = 'Phone-local AI is not configured';
  static Future<Map<String, dynamic>> _nativeProfile() async =>
      await channel.invokeMapMethod<String, dynamic>('profile') ?? {};
  static Future<Map<String, dynamic>?> _nativeInfo() => channel.invokeMapMethod<String, dynamic>('modelInfo');

  static String? unsafeProfile(Map<String, dynamic> p, int modelBytes, {bool loaded = false}) {
    if (p['lowMemory'] != false) return 'Available memory could not be verified';
    final available = (p['availableMemoryBytes'] as num?)?.toInt() ?? 0;
    final needed = loaded ? 384 * 1024 * 1024 : (modelBytes * 1.35).round() + 768 * 1024 * 1024;
    if (available < needed) return 'Not enough available RAM for this model';
    if ((p['thermalStatus'] as num? ?? -1) < 0) return 'Thermal state unavailable';
    if ((p['thermalStatus'] as num) >= 2) return 'Phone is warm; allow it to cool before local AI';
    final temperature = (p['batteryTemperatureC'] as num? ?? -1).toDouble();
    if (temperature < 0 || temperature >= 40) return 'Battery temperature unavailable or too high';
    if ((p['batteryPercent'] as num? ?? -1) < 20) return 'Charge the phone above 20% before local AI';
    return null;
  }

  Future<void> initialize() => _initializing ??= _restore();
  Future<void> _restore() async {
    try {
      model = await _modelInfo();
      final raw = (await SharedPreferences.getInstance()).getString(reportKey);
      final saved = raw == null ? null : jsonDecode(raw);
      final profile = await _profile();
      if (model != null && saved is Map<String, dynamic> &&
          saved['sha256'] == model!['sha256'] && saved['sdk'] == profile['sdk'] &&
          saved['passed'] == true && unsafeProfile(profile, (model!['bytes'] as num).toInt()) == null) {
        report = saved; ready = true; status = 'Phone-local model benchmark passed';
      } else { status = model == null ? 'Import a local model to enable conversation' : 'Local model requires an on-phone benchmark'; }
    } catch (_) { status = 'Phone-local model is not ready; open Phone-local AI setup'; }
    _changed();
  }

  Future<Map<String, dynamic>> deviceProfile() => _profile();
  Future<void> importModel() async {
    if (busy) return;
    cancel(); await _inflight; await _release();
    final picked = await channel.invokeMapMethod<String, dynamic>('chooseModel');
    if (picked == null) return;
    model = picked; ready = false; report = null;
    await (await SharedPreferences.getInstance()).remove(reportKey);
    status = 'Model imported; run the on-phone benchmark before activation';
    _changed();
  }

  Future<void> removeModel() async {
    cancel(); await _inflight; await _release();
    await channel.invokeMethod<void>('deleteModel');
    await (await SharedPreferences.getInstance()).remove(reportKey);
    ready = false; model = null; report = null;
    status = 'Local model removed from this app'; _changed();
  }

  Future<void> benchmark() async {
    if (busy || !_foreground) return;
    await initialize();
    if (model == null) { status = 'Import a trusted GGUF model first'; _changed(); return; }
    final epoch = ++_epoch;
    ready = false; busy = true; _changed();
    final done = Completer<void>(); _inflight = done.future;
    final samples = <Map<String, dynamic>>[];
    final overall = Stopwatch()..start();
    try {
      final before = await _profile();
      final unsafe = unsafeProfile(before, (model!['bytes'] as num).toInt(), loaded: _engine != null);
      if (unsafe != null) throw StateError(unsafe);
      status = 'Testing local model on this phone'; _changed();
      await _load(epoch);
      for (final language in ['en-IN', 'ta-IN', 'ta-Latn']) {
        _check(epoch);
        final timer = Stopwatch()..start();
        final question = language == 'ta-IN' ? 'ஒரு மாணவர் தினமும் படிப்பதை எளிய முறையில் எப்படி திட்டமிடலாம்?' :
          language == 'ta-Latn' ? 'Dhinam padikka easy plan epdi podalam? Reply in Tanglish.' : 'Suggest a simple daily study routine.';
        final raw = await _collect(LocalAnswer.prompt(question, language), LocalAnswer.system(language), epoch);
        final answer = LocalAnswer.fromRaw(raw, language);
        final reply = answer.display;
        final after = await _profile();
        final unsafe = unsafeProfile(after, (model!['bytes'] as num).toInt(), loaded: true);
        final quality = OfflineLanguage.acceptable(reply, language);
        samples.add({'language': language, 'milliseconds': timer.elapsedMilliseconds,
          'writingSystemPassed': quality, 'replyPreview': reply, 'profile': after});
        if (!quality) throw StateError('This model did not pass the $language response test');
        if (unsafe != null) throw StateError(unsafe);
        if (timer.elapsedMilliseconds > 60000) throw StateError('This model is too slow for the current phone');
      }
      _check(epoch);
      report = {'passed': true, 'sha256': model!['sha256'], 'sdk': before['sdk'],
        'before': before, 'samples': samples, 'totalMilliseconds': overall.elapsedMilliseconds,
        'testedAt': DateTime.now().toUtc().toIso8601String()};
      await (await SharedPreferences.getInstance()).setString(reportKey, jsonEncode(report));
      ready = true; status = 'LOCAL AI READY · offline · ₹0 API';
    } on LocalBrainInterrupted {
      status = 'Local model test cancelled';
    } catch (error) {
      status = error is StateError ? '${error.message}' : 'Model could not run locally; no cloud request was made';
      await _release();
    } finally { busy = false; done.complete(); _changed(); }
  }

  Future<String> reply(String text, String language) async {
    return (await replyAnswer(text, language)).display;
  }

  Future<LocalAnswer> replyAnswer(String text, String language) async {
    await initialize();
    if (!ready || model == null) throw StateError('Phone-local model is not ready');
    if (!_foreground || busy) throw LocalBrainInterrupted();
    final epoch = ++_epoch; busy = true; _changed();
    final done = Completer<void>(); _inflight = done.future;
    try {
      final unsafe = unsafeProfile(await _profile(), (model!['bytes'] as num).toInt(), loaded: _engine != null);
      if (unsafe != null) { ready = false; status = unsafe; throw StateError(unsafe); }
      await _load(epoch);
      final system = '${LocalAnswer.system(language)}\nRecent conversation (context only):\n${LocalAnswer.context(HybridConversationContext.instance.prompt)}';
      if (text.length > 600) throw StateError('Please shorten this local question to 600 characters');
      final input = text;
      final answer = await _collect(LocalAnswer.prompt(input, language), system, epoch);
      _check(epoch);
      final after = unsafeProfile(await _profile(), (model!['bytes'] as num).toInt(), loaded: true);
      _check(epoch);
      if (after != null) { ready = false; status = after; throw StateError(after); }
      final result = LocalAnswer.fromRaw(answer, language);
      status = 'LOCAL AI · offline · ₹0 API';
      return result;
    } catch (_) {
      await _release();
      rethrow;
    } finally { busy = false; done.complete(); _changed(); }
  }

  Future<void> _load(int epoch) async {
    _check(epoch);
    if (_engine == null) {
      _engine = _factory();
      await _engine!.load(model!['path'] as String);
      _check(epoch);
    }
  }
  Future<String> _collect(String prompt, String system, int epoch) async {
    var text = ''; var timedOut = false;
    final timer = Timer(const Duration(seconds: 60), () { timedOut = true; _engine?.cancel(); });
    try {
      await for (final delta in _engine!.reply(prompt, system)) {
        _check(epoch); text += delta;
        if (text.length > 2000) { _engine?.cancel(); break; }
      }
    } finally { timer.cancel(); }
    _check(epoch);
    if (timedOut) throw StateError('Local response timed out; use a smaller model');
    if (text.trim().isEmpty) throw StateError('The local model produced no answer');
    return text.trim();
  }
  void _check(int epoch) { if (_disposed || !_foreground || epoch != _epoch) throw LocalBrainInterrupted(); }
  void cancel() { ++_epoch; _engine?.cancel(); }
  Future<void> _release() async { final engine = _engine; _engine = null; await engine?.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      cancel(); final epoch = _epoch;
      unawaited(_inflight.then((_) async { if (epoch == _epoch) await _release(); }));
    }
  }
  void _changed() { if (!_disposed) notifyListeners(); }
  @override
  void dispose() { _disposed = true; cancel(); WidgetsBinding.instance.removeObserver(this); unawaited(_inflight.then((_) => _release())); super.dispose(); }
}
