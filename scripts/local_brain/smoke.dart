// Runs the application's actual model adapter. This is Linux QA, not a phone benchmark.
import 'dart:convert';
import 'dart:io';
import '../../lib/services/local_brain/model_engine.dart';
import '../../lib/services/local_brain/language_quality.dart';
import '../../lib/services/local_brain/local_answer.dart';

Future<void> main(List<String> args) async {
  if (Platform.environment['LD_PRELOAD']?.contains('libdeny-net.so') != true) {
    throw StateError('Network denial harness is required');
  }
  try {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, 9);
    socket.destroy();
    throw StateError('Internet sockets were not blocked');
  } on SocketException catch (e) {
    if (e.osError?.errorCode != 13) rethrow;
  }
  final engine = LlamaPhoneModel();
  final results = <Map<String, Object>>[];
  try {
    await engine.load(args.single);
    for (final language in ['en-IN', 'ta-IN', 'ta-Latn']) {
      final watch = Stopwatch()..start();
      final output = StringBuffer();
      final question = language == 'en-IN' ? 'What is 2 plus 2?' :
        language == 'ta-IN' ? 'உன் பெயர் என்ன?' : 'un peru enna? Reply in Tanglish.';
      await for (final text in engine.reply(LocalAnswer.prompt(question, language), LocalAnswer.system(language))) {
        output.write(text);
      }
      final generated = LocalAnswer.fromRaw(output.toString().trim(), language);
      final answer = generated.display;
      final semantic = language == 'en-IN' ? RegExp(r'\b(4|four)\b', caseSensitive: false).hasMatch(answer) :
        answer.toLowerCase().contains('jarvis') || answer.contains('ஜார்விஸ்');
      final result = <String, Object>{'language': language, 'input': question,
        'reply': answer, 'speech': generated.speech, 'speech_locale': generated.locale,
        'elapsed_ms': watch.elapsedMilliseconds,
        'passed': semantic && OfflineLanguage.acceptable(answer, language)};
      results.add(result); stdout.writeln(jsonEncode(result));
    }
    stdout.writeln(jsonEncode({'network_sockets_blocked': true, 'platform': 'Linux CI',
      'phone_tested': false, 'passed': results.every((r) => r['passed'] == true)}));
    if (results.any((r) => r['passed'] != true)) throw StateError('Real local model language probe failed');
  } finally { await engine.dispose(); }
}
