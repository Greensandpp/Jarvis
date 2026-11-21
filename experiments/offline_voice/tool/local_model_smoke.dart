// Real SDK + real model inference. Runner blocks all AF_INET/AF_INET6 sockets.
import 'dart:io';
import 'dart:convert';
import 'package:greensoil_livekit_voice_experiment/offline_runtime.dart';
import 'package:greensoil_livekit_voice_experiment/language_contract.dart';
import 'package:greensoil_livekit_voice_experiment/tamil_text.dart';
Future<void> main(List<String> args) async {
  if (Platform.environment['LD_PRELOAD']?.contains('libdeny-net.so') != true) {
    throw StateError('Socket-blocking test harness missing');
  }
  try {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, 9);
    socket.destroy();
    throw StateError('Internet socket unexpectedly allowed');
  } on SocketException catch (e) {
    if (e.osError?.errorCode != 13) rethrow;
  }
  final model = PhoneModel();
  try {
    await model.load(args.single);
    final cases = <(String, String, bool Function(String))>[
      ('What is 2 plus 2? Reply with the digit only.', 'en-IN', (s) => s.contains('4')),
      ('vanakam', 'ta-IN', (s) => s.contains('வணக்க')),
      ('un peru enna', 'ta-IN', (s) => s.toLowerCase().contains('jarvis') || s.contains('ஜேஆர்விஸ்') || s.contains('ஜார்விஸ்')),
      ('saptiya', 'ta-IN', (s) => (s.contains('AI') || s.contains('செயற்கை')) &&
        ['சாப்ப', 'உணவ', 'உண்ண'].any(s.contains) && ['இல்லை', 'தில்லை', 'முடியாது', 'மாட்டேன்'].any(s.contains)),
      ('water ku tamil la enna', 'ta-IN', (s) => (s.contains('தண்ணீர்') || s.contains('நீர்')) && !s.contains('பாசனம்')),
      ('nee manushana illa AI ah', 'ta-IN', (s) => s.contains('AI') || s.contains('செயற்கை')),
      ('vanakam', 'ta-Latn', (s) => s.toLowerCase().contains('vanak')),
      ('un peru enna', 'ta-Latn', (s) => s.toLowerCase().contains('jarvis') || s.toLowerCase().contains('jaarvis') || s.toLowerCase().contains('jaearvis')),
      ('saptiya', 'ta-Latn', (s) => (RegExp(r'\bAI\b', caseSensitive: false).hasMatch(s) || s.toLowerCase().contains('seyarkai') || s.toLowerCase().contains('nunnarivu')) && ['saap', 'sap', 'unav'].any(s.toLowerCase().contains) && ['maatt', 'matt', 'maate', 'mate', 'illa', 'illai', 'mudiy', 'sapdala', 'saapdala'].any(s.toLowerCase().contains)),
      ('What is your name?', 'en-IN', (s) => s.toLowerCase().contains('jarvis')),
      ('உன் பெயர் என்ன?', 'ta-IN', (s) => s.toLowerCase().contains('jarvis') || s.contains('ஜார்விஸ்') || s.contains('ஜேஆர்விஸ்')),
      ('Have you eaten?', 'en-IN', (s) => s.toLowerCase().contains('ai') && ['not', 'no', 'cannot', "don't", "can't"].any(s.toLowerCase().contains)),
    ];
    final results = <Map<String, Object>>[];
    for (final probe in cases) {
      final watch = Stopwatch()..start();
      final output = StringBuffer();
      await for (final text in model.reply(probe.$1, probe.$2)) { output.write(text); }
      final raw = output.toString().trim();
      final answer = probe.$2 == 'ta-Latn' ? romanTamil(raw) : raw;
      final passed = OfflineLanguage.acceptable(answer, probe.$2) && probe.$3(answer);
      final result = <String, Object>{'input': probe.$1, 'language': probe.$2,
        'normalized_input': normalizeCommonTanglish(probe.$1), 'raw_model_reply': raw,
        'actual_reply': answer, 'passed': passed, 'elapsed_ms': watch.elapsedMilliseconds};
      results.add(result);
      stdout.writeln(jsonEncode(result));
    }
    stdout.writeln(jsonEncode({'language_probes_passed': results.where((r) => r['passed'] == true).length,
      'language_probes_total': results.length, 'network_sockets_blocked': true, 'phone_voice_tested': false}));
    if (results.any((r) => r['passed'] != true)) throw StateError('Offline language probes failed; do not ship APK');
  } finally { await model.dispose(); }
}
