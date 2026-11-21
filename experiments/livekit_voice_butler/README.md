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

## Phase 12: private HTTP cancellation handler (not deployed)

`cancellation_server.py` implements a stdlib WSGI POST /cancel
handler matching the experimental Flutter cancellation client schema.
The application requires injected callbacks for bearer-token verification,
per-room ownership authorization, and actual agent cancellation plus
positive confirmation. If the agent fails to confirm or raises an error,
the response is NOT successful. The handler rejects non-HTTPS proxy
metadata, invalid HTTP method/content type, malformed IDs, oversized
payloads, and bad/missing authorization.

`test_cancellation_server.py` contains 9 deterministic offline HTTP tests.
Existing GitHub Actions Python job executes these via test_*.py discovery.

WARNING: This is a testable handler contract, NOT a running backend.
There is no live token verifier, cancellation-capable agent, real room
registry, WSGI deployment, or Android client binding. Production deployment
would require validated TLS proxy configuration, token validation with
expiry/audience, authorization, response-generation ownership binding,
replay protection, rate limiting, observability and a real agent-side
cancel-and-confirm implementation. No secrets or live cloud bills.
