import 'package:flutter/foundation.dart';

import 'package:private_agent/jarvis_v3/assistant_activity.dart';
import 'package:private_agent/jarvis_v3/conversation_store.dart';
import 'package:private_agent/jarvis_v3/jarvis_v3_home.dart';
import 'package:private_agent/services/jarvis_service.dart';

/// TEST DOUBLE of the JARVIS service: drives phases the way the real service
/// does (listen -> think -> speak -> idle) without audio or network.
class FakeConversation extends ChangeNotifier {
  JarvisPhase phase = JarvisPhase.idle;
  String user = '';
  String jarvis = '';
  String status = 'READY';
  bool mic = false;
  bool executor = false;
  bool configured = true;
  double level = 0;
  final commands = <String>[];
  int micToggles = 0;

  ConversationSignals get signals =>
      ConversationSignals(phase: phase, userText: user, jarvisText: jarvis, status: status);

  ActivitySignals get activity => ActivitySignals(
        phase: phase,
        micCapturing: mic,
        executorRunning: executor,
        aiConfigured: configured,
        errorStatus: status.startsWith('AI ERROR'),
      );

  void listen(String partial) {
    phase = JarvisPhase.listening;
    mic = true;
    user = partial;
    notifyListeners();
  }

  void think(String request) {
    mic = false;
    user = request;
    status = 'COMPUTING';
    phase = JarvisPhase.thinking;
    notifyListeners();
  }

  void execute() {
    executor = true;
    phase = JarvisPhase.executing;
    notifyListeners();
  }

  void speak(String reply, {String status = 'RESPONDING'}) {
    executor = false;
    jarvis = reply;
    this.status = status;
    phase = JarvisPhase.speaking;
    notifyListeners();
  }

  void idle() {
    mic = false;
    executor = false;
    phase = JarvisPhase.idle;
    notifyListeners();
  }

  JarvisV3Bindings bindings({bool verified = true}) => JarvisV3Bindings(
        source: this,
        activitySignals: () => activity,
        conversationSignals: () => signals,
        soundLevel: () => level,
        toggleMic: () async {
          micToggles++;
          mic ? idle() : listen('');
        },
        onCommand: (t) {
          commands.add(t);
          think(t);
        },
        aiVerified: () => verified,
        aiErrorKind: () => '',
        standbyMic: () => false,
      );
}
