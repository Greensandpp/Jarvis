import 'dart:async';
import 'package:llamadart/llamadart.dart';

abstract class LocalModel {
  Future<void> load(String path);
  Stream<String> reply(String text, String language);
  void cancel();
  Future<void> dispose();
}

/// File-only load; no URL model source, download manager or inference server.
class PhoneModel implements LocalModel {
  final LlamaEngine _engine = LlamaEngine(LlamaBackend());
  @override
  Future<void> load(String path) async {
    await _engine.setModel(LlamaModel(ModelSource.path(path)), params: const ModelParams(
      device: ComputeDevice.cpu, gpuLayers: 0, contextSize: 2048,
      numberOfThreads: 4, numberOfThreadsBatch: 4,
    ));
  }

  @override
  Stream<String> reply(String text, String language) async* {
    // No tools, memory upload, hidden network fallback or automatic greeting.
    final messages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text:
        'You are GreenSoil JARVIS, an offline assistant. Reply briefly in '
        '${language == 'ta-IN' ? 'Tamil' : 'English or Tanglish matching the user'}. '
        'No phone, web, payment or trading tools are connected. Never claim '
        'you performed actions or checked live information. Answer in 1-3 sentences.'),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: text),
    ];
    await for (final chunk in _engine.create(messages,
      enableThinking: false,
      params: const GenerationParams(maxTokens: 192, temp: 0.6),
    )) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  void cancel() => _engine.cancelGeneration();
  @override
  Future<void> dispose() => _engine.dispose();
}

/// Owns one output and invalidates every old operation before any await.
/// A new turn waits for the old native generation to finish cancellation.
class OfflineTurns {
  OfflineTurns(this.model, {required this.stopAudio, required this.speak,
    required this.changed});
  final LocalModel model;
  final Future<void> Function() stopAudio;
  final Future<void> Function(String, String) speak;
  final void Function(String, String) changed;
  int _epoch = 0;
  bool foreground = true;
  Future<void> _inferenceDone = Future.value();

  Future<void> stop({bool background = false}) async {
    _epoch++;
    if (background) foreground = false;
    model.cancel();
    await stopAudio();
  }

  void resumed() => foreground = true;

  Future<void> ask(String text, String language, {required bool voice}) async {
    if (!foreground || text.trim().isEmpty || text.length > 1000) return;
    final epoch = ++_epoch;
    model.cancel();
    await stopAudio();
    await _inferenceDone;
    if (!foreground || epoch != _epoch) return;
    final done = Completer<void>();
    _inferenceDone = done.future;
    var output = '';
    try {
      changed('Thinking locally', '');
      await for (final delta in model.reply(text, language)) {
        if (!foreground || epoch != _epoch) break;
        output += delta;
        changed('Generating locally', output);
      }
    } catch (_) {
      if (foreground && epoch == _epoch) changed('Local generation failed; no cloud fallback', output);
      return;
    } finally {
      done.complete();
    }
    if (!foreground || epoch != _epoch) return;
    changed('Local reply complete', output);
    if (voice && output.trim().isNotEmpty) {
      try {
        // Native channel serializes stop/speak; the epoch is checked again
        // after every inference wait. Background also stops native TTS.
        await speak(output, language);
      } catch (_) {
        if (foreground && epoch == _epoch) changed('Text ready; installed offline voice unavailable', output);
      }
    }
  }
}
