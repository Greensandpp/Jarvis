// Real SDK + real model inference. Runner blocks all AF_INET/AF_INET6 sockets.
import 'dart:io';
import 'dart:convert';
import 'package:greensoil_livekit_voice_experiment/offline_runtime.dart';
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
    final watch = Stopwatch()..start();
    final output = StringBuffer();
    await for (final text in model.reply('What is 2 plus 2? Reply with one short sentence.', 'en-IN')) {
      output.write(text);
    }
    final answer = output.toString().trim();
    if (answer.isEmpty || !answer.contains('4')) throw StateError('Local model smoke failed');
    stdout.writeln(jsonEncode({'real_model_reply': answer, 'elapsed_ms': watch.elapsedMilliseconds,
      'network_sockets_blocked': true, 'phone_voice_tested': false}));
  } finally { await model.dispose(); }
}
