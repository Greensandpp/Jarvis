# Live voice implementation checkpoint — 21 November 2026

This document supersedes the implementation-status statements in README phases
12–16; those sections remain as historical context. Existing JARVIS UI, settings,
Android identity, offline architecture, PB7 and Pine are unchanged.

## Verified starting evidence

Authenticated GitHub connector confirmed branch HEAD
`c27305ea913ba706d2d54c862b9031969f3c6ca4` (later than `3127e4ca`).
GitHub Actions runs `44881266454` (tests) and `44881266438` (APK) succeeded
for that HEAD. Those results are the baseline, not validation of new code.

Railway project `GreenSoil-JARVIS-AI-Staging`, environment `staging`, has
one service `jarvis-gemini-gateway`. It runs code from
`Greensandpp/openalgo`, root `/greensoil_lab/gemini_gateway`; it is not a
LiveKit worker. Last deployment `dcc2164c-faf2-442c-8789-3eb76b1e42f3`
was `SLEEPING` at inspection. Its authorized variable-name inventory includes
`GEMINI_API_KEY`, `GATEWAY_ACCESS_TOKEN`, and ElevenLabs settings, but **no**
`LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, or
`GS_VOICE_OWNER_BEARER`. Values were redacted and never printed. Existing
Gemini metadata does not establish model access, free-tier status, or voice support.

## Implementation

- Real `livekit-api` JWT signer, microphone-only join, named agent dispatch.
- Dispatch carries a signed owner/room/absolute-expiry grant; the worker rejects
  tampering, wrong rooms, expiry and grant replay before opening Gemini.
- Real `AgentServer` + `AgentSession` + Google `RealtimeModel`, native audio only.
  Kore is requested; female perception, language quality and availability still
  require provider/device listening tests. No second TTS, greeting or action tools.
- Provider-native turn detection and SDK interruption; false interruption resume
  disabled. No claim that phone speaker buffers or every provider chunk drain.
- Maximum 120 seconds including setup latency, bounded close and room deletion;
  owner departure closes the session. No retry with another paid model.
- SQLite reserves the full session allowance before signing: one active reserved
  room, max 1800 seconds/month; failed joins are not refunded. Each worker also
  persists consumed grants. Token TTL alone is NOT a connected-session limit.
- Flutter pending-session ownership, timeout, serialized mic toggles, stale
  foreground checks, explicit native Room disposal, masked/unpersisted owner auth.
- The APK workflow runs Python SDK integration and Flutter checks before build;
  only encrypted APK bytes can be uploaded from this public repository.

## Exact blockers to live testing/deployment

1. A real LiveKit WSS endpoint and server keypair, set privately on dedicated
   staging services. Do not paste credentials into issues, chat, source or logs.
2. A separate private strong `GS_VOICE_OWNER_BEARER`, delivered to the owner over
   an authenticated private channel. The gateway access token is not reused.
3. Provider-console verification that both Gemini live audio AND LiveKit transport
   are free-only with paid billing/overage disabled. Set
   `GS_VOICE_FREE_TIER_VERIFIED=true` only after this evidence exists. A boolean,
   minute cap or provider budget alert does not independently guarantee ₹1000.
   No paid path or paid activation is authorized by this implementation.
4. Explicit available `GS_VOICE_GEMINI_MODEL`, tested against the configured
   provider account; no guessed default model. Set `GEMINI_API_KEY` privately on
   the worker. Token and worker preflight require all configuration.
5. Dedicated token and worker staging services, each one replica with persistent
   writable SQLite volume paths via `GS_VOICE_LEDGER_PATH`. Do not repoint or
   redeploy the existing Gemini gateway. Persistent state is required before enable.
6. TLS proxy configuration verified to sanitize forwarded scheme headers. WSGI
   checks `wsgi.url_scheme`, not arbitrary client `X-Forwarded-Proto`. Configure
   Gunicorn trusted proxy IPs from the actual platform; never blindly allow `*`.

No service was created/deployed or paid provider activated during recovery.
Keep `GS_VOICE_TOKEN_ISSUANCE_ENABLED` and `GS_VOICE_AGENT_ENABLED` off until
these prerequisites are satisfied. Default-off `/health` can run without secrets;
health does not mean live voice works.

## Local / CI checks

```sh
python -m pip install -r experiments/livekit_voice_butler/requirements-agent.txt -r experiments/livekit_voice_butler/requirements-token.txt
python -m unittest discover -s experiments/livekit_voice_butler -p 'test_*.py' -v
```

SDK tests instantiate actual SDK classes and verify signed JWTs. Job lifecycle
tests use mocked network/provider objects. They do not call Gemini or LiveKit.
Flutter analysis and unit tests run in GitHub CI. Local Flutter setup was stopped
by automatic review because the setup attempted an instance-metadata request;
that denied path was not bypassed. CI uses a separate hosted runner.

## Dedicated staging launch after prerequisites

Build with repository-root context and this experiment's Dockerfile. Configure
`GS_VOICE_ROLE=token` or `agent`; every other role fails. Required private env is
listed above. For token service use `/health`, one Gunicorn worker, and explicit
`FORWARDED_ALLOW_IPS` from verified TLS proxy configuration. For worker enable
`GS_VOICE_AGENT_ENABLED=true`; enable token issuance last.

Before calling voice verified, test on iQOO 13: Tamil, English, Tanglish, voice
selection, ten repeated start/stop cycles, mute/unmute, speaking interruption,
old-response suppression, network loss, screen lock/background, two-minute
server deadline, second-session refusal, replay rejection and provider usage.
Offline voice is NOT implemented by this experiment. Never auto-enable a paid
fallback or merge into original JARVIS without separate approval.
