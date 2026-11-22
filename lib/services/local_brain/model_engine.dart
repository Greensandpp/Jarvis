import 'package:llamadart/llamadart.dart';

abstract interface class PhoneModelEngine {
  Future<void> load(String path);
  Stream<String> reply(String prompt, String system);
  void cancel();
  Future<void> dispose();
}

class LlamaPhoneModel implements PhoneModelEngine {
  final _engine = LlamaEngine(LlamaBackend());
  @override
  Future<void> load(String path) => _engine.setModel(
    LlamaModel(ModelSource.path(path)),
    params: const ModelParams(device: ComputeDevice.cpu, gpuLayers: 0,
      contextSize: 2048, numberOfThreads: 2, numberOfThreadsBatch: 2),
  );
  @override
  Stream<String> reply(String prompt, String system) async* {
    await for (final chunk in _engine.create([
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
    ], enableThinking: false, params: const GenerationParams(
      maxTokens: 96, temp: .3, seed: 42, reusePromptPrefix: false))) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }
  @override
  void cancel() => _engine.cancelGeneration();
  @override
  Future<void> dispose() => _engine.dispose();
}
