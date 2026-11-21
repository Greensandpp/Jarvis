# Live voice implementation checkpoint — 21 November 2026

This document supersedes the implementation-status statements in README phases
12–16; those sections remain as historical context. Existing JARVIS UI, settings,
Android identity, offline architecture, PB7 and Pine are unchanged.

## Verified starting evidence (historical recovery baseline)

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

## Initial blockers to live testing/deployment (see current setup below)

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

No service was created/deployed or paid provider activated during that initial recovery.
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

## Current platform setup — subsequent authorized staging phase

- Signed-in LiveKit project: `GreenSoil Jarvis`, ID `p_1m6mgo0konb`.
  Project URL: `wss://greensoil-jarvis-14y4nhhx.livekit.cloud`.
  Billing page confirmed Build plan, next invoice $0.00, no agent deployments.
- Dedicated key description `gs-voice-staging-20261121` was created after owner
  approval. Its credentials were privately set on the two staging services;
  neither key nor secret is in this repository. Existing key was not revoked.
- Google AI Studio confirmed project `greensoil-jarvis-ai` is Free tier.
  Its existing key was privately stored only on the worker service. Authenticated
  model inventory includes `gemini-2.5-flash-native-audio-preview-12-2025`.
  Public Gemini pricing lists that model's free-tier input/output as free.
- Railway services, in the existing project/environment only:
  `jarvis-livekit-token-staging` (`cc5a70f3-590a-4fbd-8c7e-e50800917d62`)
  and `jarvis-livekit-agent-staging` (`6e0ba272-41fb-4b21-92dc-4d218810d586`).
  Each has a dedicated 128 MB `/data` volume, one replica, 0.5 GB RAM/0.5 CPU
  limits. At credential setup, no source/deployment was attached and issuance
  remained disabled. Existing Gemini gateway was not changed.
- Token signing no longer requires a Gemini API key. Provider secrets belong
  only on the worker. The container initializes volume ownership as root then
  drops to user `voice` before listening or connecting to any provider.
- Railway browser sign-in returned `pkce_cookie_missing` after GitHub device
  approval. Private transfer through the authorized connected tools succeeded;
  further browser login is not required for deployment.
- `smoke_gemini.py` is an opt-in actual AgentSession/provider test with a
  counting sink. Zero frames FAIL, not PASS; it never runs in CI and never
  proves microphone input, phone playback, recognition, or speaker drain.
  In a SOCKS-proxied development environment its clients also need `socksio`
  and `python-socks[asyncio]`; this honors the existing proxy route.
- Railway public ingress overwrites X-Forwarded-Proto and enforces TLS:
  https://docs.railway.com/networking/public-networking/specs-and-limits
  There are no stable supported proxy CIDRs. Trusting all forwarded peers is
  appropriate only after verifying no TCP proxy and that every service in this
  private environment is trusted. Ignore the Forwarded header. Keep bearer auth
  and no-store responses regardless of scheme. Test spoofed headers over HTTP
  and HTTPS before enabling issuance; the initial generic proxy warning above
  is not authorization to blindly trust arbitrary deployments.

Provider free-tier status is not a Railway hosting invoice guarantee. No paid
subscription, billing upgrade or original JARVIS/PB7 change is authorized here.
Live audio, device QA and final deployment evidence must be reported from actual
results, separately from unit-test and SDK-construction passes.

The credential-backed staging test exposed a compatibility failure: google-genai
3.6.1 defaults to API `v1`, whose Live websocket route returns HTTP 404. Both
worker and smoke explicitly select `v1beta` and `vertexai=False`; a real-SDK
regression assertion protects against changing defaults or accidental Vertex use.
Staging agent mode has a 900-second process lifetime, followed by at most ten
seconds for shutdown. Keep Railway restart policy NEVER. This bounds idle
hosting during the first phone QA window; it is not an always-on production
release or a guarantee of a provider invoice. Sessions retain their separate
120-second signed deadline and persistent monthly allowance.

The first credential-backed room dispatch exposed `EOFError: unexpected EOF`
in Python 3.13's forkserver process startup. SDK worker processes now explicitly
use `spawn` with a 30-second initialization timeout. A real native-SDK child
initialization test runs both in Python CI and as UID 10001 inside the actual
staging container. A registered worker alone does not prove it can accept jobs.

### Opt-in room transport QA

`GS_VOICE_RUN_ROOM_SMOKE=true` on the isolated agent service starts one bounded
`smoke_room.py` client alongside the registered worker. Requires
`GS_VOICE_SMOKE_ENDPOINT` equal to the hard-coded isolated staging token URL and
`GS_VOICE_SMOKE_OWNER` supplied privately. Never set these in GitHub or the APK.
The client waits for worker registration, uses the real authenticated endpoint,
joins its owner-scoped room, waits for the named agent to listen, sends one short
`lk.chat` request and counts remote agent audio. No microphone/audio/video is
published, audio recording is disabled, redirects are refused, and output only
contains counters and error types. It consumes one normal 120-second reservation.
Clear the QA owner variable and set the opt-in to false after the one-shot test;
otherwise a service redeploy would repeat it. The worker's 15-minute timeout and
NEVER restart policy still apply. A passing room test does not validate physical
phone microphone, Tamil/Tanglish pronunciation, playback, or barge-in.
