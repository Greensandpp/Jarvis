import 'package:flutter_test/flutter_test.dart';

import '../lib/livekit_session_bridge.dart';
import '../lib/voice_session_coordinator.dart';

class _NoopTransport implements VoiceTransport {
  @override
  Future<void> cancelAgentResponse() async {}
  @override
  Future<void> stopRemoteAudio() async {}
  @override
  Future<void> stopLocalTts() async {}
}

void main() {
  test('bridge constructs without exposing or requiring cloud secrets', () async {
    final bridge = LiveKitSessionBridge(
      tokenEndpoint: Uri.parse('https://example.invalid/api/livekit-token'),
      audioTransport: _NoopTransport(),
    );
    expect(bridge.isConnected, isFalse);
    expect(await bridge.interruptAndListen(), isNull);
    await bridge.dispose();
  });

  test('disconnected text send fails closed', () async {
    final bridge = LiveKitSessionBridge(
      tokenEndpoint: Uri.parse('https://example.invalid/api/livekit-token'),
      audioTransport: _NoopTransport(),
    );
    await expectLater(bridge.sendText('hello'), throwsStateError);
    await bridge.dispose();
  });
}
