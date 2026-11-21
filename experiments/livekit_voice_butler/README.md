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

## Phase 13: agent-side response ownership registry (not connected)

`cancellation_registry.py` adds a strict one-active-response-per-room
registry. The cancellation operation validates principal, room, response
ID and exact generation before calling an injected backend stop function.
A new response cannot replace an active response until stop was positively
acknowledged; stale/double cancellations and wrong owner IDs are rejected.
`test_cancellation_registry.py` contains 8 offline tests, including an
end-to-end WSGI request against the registry.

**This is not a LiveKit integration:** upstream jarvis-voice-butler uses
`AgentSession` and Google realtime Gemini, but this experiment has not
wired the stop callback to that SDK, nor implemented authoritative room
membership storage. The sample stop callback in the tests is a FAKE,
not proof that real audio is cancelled. No API or APK has been deployed.
Before production, implement a bounded, non-reentrant agent cancellation
and output-queue drain acknowledgement, agent-side session lifecycle,
authentication, replay protection, and live tests.

## Phase 14: documented LiveKit AgentSession interruption adapter

The documented Python SDK `AgentSession.interrupt(force=True)` returns an
awaitable that resolves when LiveKit's interruption processing completes.
`livekit_agent_interrupt_adapter.py` now invokes this real SDK **method
shape**, by scheduling a coroutine on a separate running agent asyncio loop.
It adds explicit timeout, stopped-loop, stale-generation, and same-thread
deadlock defenses; five deterministic tests exercise these contracts with
fake session objects.

This adapter is **not** yet wired into a running `AgentSession`. The
backend must bind the actual session/loop, track authoritative response IDs
and room membership, and implement independent remote playback drain and
Android local TTS stop acknowledgements. In particular, a completed
`session.interrupt()` future is NOT evidence that the phone's audio device
has flushed its own buffer, or that Gemini stopped generating every queued
audio chunk. There is no live cloud test, production change, secret, or APK.
