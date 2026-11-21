# Isolated Dart voice session gate

This is a pure Dart *experiment*, not a new APK or a replacement for the GreenSoil home screen.
The source is written independently; upstream Flutter starter was reviewed as a design reference.

## API and real-audio integration contract

- Only one coordinator creates/owns LiveKit session and Android TTS output.
- On interrupt: (1) request cancel from Gemini/LiveKit, (2) await stop acknowledgment from any TTS/audio player, (3) call beginListening(playbackStopped: true), (4) attach generation to every response callback.
- Reject all stale generations before starting any playback, and on *every* audio chunk.
- On disconnect, reconnect, app background/foreground, invalidate generation and explicitly release audio tracks.
- Use one output path for each response: Gemini realtime audio OR local Android TTS, never both.
- Persist no API secrets in the APK; use a secure authenticated token endpoint in any eventual LiveKit integration.
- Review preconnect audio buffering carefully against privacy requirements; disable by default for this experiment.
- Do not enable always-on microphone recording in this experiment.

## Unit tests

Requires Flutter SDK (not available in the current execution environment).
Run from repository root:

```bash
flutter test experiments/livekit_voice_butler/flutter/test/voice_session_gate_test.dart
```

These tests only verify pure state-gate logic, NOT real playback stop acknowledgments, LiveKit compatibility, or Android device behavior. No existing Flutter dependencies, package settings, Android code or CI files were modified.

## Phase 3: asynchronous coordination

`lib/voice_session_coordinator.dart` introduces a serialized lifecycle coordinator with an injectable `VoiceTransport` bridge. The bridge must wire real SDK functions for (1) Gemini response cancellation, (2) LiveKit remote audio stop, and (3) Android local TTS stop. No LiveKit SDK was installed or connected here.

- Repeated interrupts invalidate old generations immediately; only latest request may enter listening.
- Any stop failure blocks new listening (fail closed).
- Disconnect and app shutdown invalidate callbacks without waiting for transport calls.
- Explicitly test real stop acknowledgments on an iQOO 13 before integrating.
- `test/voice_session_coordinator_test.dart` adds six async regression scenarios.
- All tests remain UNVERIFIED until Flutter SDK execution succeeds.
