# GreenSoil LiveKit voice-butler experiment (isolated)

Source inspiration: https://github.com/ruxakK/jarvis-voice-butler
No third-party implementation copied. Upstream root license was not confirmed;
do not vendor upstream source without verifying licensing and provenance.

## Scope and safety
This experiment resides solely on `experiment/livekit-voice-butler-20261121`.
No existing Flutter UI, Android applicationId, Gemini configuration, secrets,
APK, production code, deployment or GitHub Actions workflow is changed.

## First implementation
`voice_gate.py` is a Python standard-library proof of concept for:
- IDLE -> LISTENING -> THINKING -> SPEAKING -> IDLE transitions
- exclusive speech-output ownership (avoid overlapping Gemini and Android TTS)
- interruption generation IDs (reject stale speech after barge-in)
- denial of stale/early response callbacks

This is **logic only**: no microphone input, LiveKit connection, Tamil/Tanglish
recognition, cloud API usage, Android TTS, 3D UI, APK build or device tests.
Do not claim these behaviors are fixed on the phone.

## Verify
```bash
python -m unittest discover -s experiments/livekit_voice_butler -p 'test_*.py'
```

## Next gated steps
1. Verify existing Android audio owners and lifecycle on the baseline branch.
2. Add a disposable adapter mapping one event source to the gate, with explicit
   real player stop/cancel acknowledgments before opening another speech stream.
3. Stress-test interruptions, reconnection and background/foreground transitions.
4. Separately benchmark cloud minutes, Tamil/Tanglish quality and offline TTS.
5. Require explicit approval and regression PASS before any merge.
