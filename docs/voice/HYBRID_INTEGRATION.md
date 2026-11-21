# GreenSoil hybrid voice integration candidate

Branch: `integration/hybrid-native-voice-20261121`. Draft PR: https://github.com/Greensandpp/Jarvis/pull/5

## Recovery references

- Latest detailed Guardian base: `a6477d48e4223dc2eb1876d68ae5535a95918ca3`.
- Source ZIP SHA-256: `c25bafd391c5c6c338df9b8645349caf5882c86926e2273d2650065eae828f84`.
- The original ZIP and its embedded standalone `android/app/build/outputs/apk/debug/app-debug.apk` are unchanged. The ZIP's private local configuration was not copied into this repository.
- Main/stable branches and all Railway services are unchanged. This integration uses existing JARVIS application IDs and source, not a replacement app.

## Source behavior

The reference Kotlin GeminiLiveManager uses OkHttp WebSocket, 16 kHz PCM16 mono capture, 24 kHz PCM playback, VOICE_COMMUNICATION, echo cancellation and noise suppression. It suppresses microphone transmission during model speech, which prevents genuine server barge-in. Its unbounded audio channel can also accumulate stale speech.

The existing JARVIS transport and native LiveAudioBridge retain the same PCM and Android audio approach. This candidate keeps mic streaming during model output, uses the provider interruption event to invalidate and flush queued PCM, and uses a bounded playback queue. Fifty-millisecond capture packets replace the old 100 ms bridge packets. Latency improvement remains UNVERIFIED until measured against the standalone APK.

The detailed 3D Guardian source, skeletal geometry, five original modes, renderer gates, existing output tickets and native MediaPlayer cancellation are preserved. Live phases and subtitles are wired to the original V3 home. Voice commands can choose Ryan, Tamil Pallavi or Valluvar. Installed offline voices remain distinct from online voice names.

## Cost and credentials

There is no paid-mode switch in this candidate. Legacy remote text inference, embeddings and cloud dictation with unverified billing are blocked. Loopback inference remains possible, but a loopback endpoint must actually run locally; a local proxy to a paid service is not offline AI.

The Live broker request includes `freeOnly: true`. Before opening a Gemini WebSocket the client requires all of:

- a short-lived `auth_tokens/...` token;
- `billingEnabled: false`;
- `freeTier: true`;
- `estimatedCostInr: 0`.

These fields are an authenticated broker contract, not independent proof of Google's billing state. The broker operator must verify the key's owning project and billing status. Do not invent these fields or enable paid billing to make the UI connect. Missing verification fails closed. Free quota is limited, not unlimited. No API-key rotation is implemented.

Broker credentials are encrypted using Android Keystore AES-GCM. Existing plaintext broker tokens migrate only after a successful secure write. Provider API keys from the reference are never copied into the APK. Existing unrelated user AI settings are preserved, but unverified cloud inference is blocked.

Ryan is the legacy Microsoft Edge consumer online synthesis implementation (`en-GB-RyanNeural`), recovered from source history. It is not a supported Azure API integration, is not offline, and has no permanent free/unlimited guarantee. Tamil online choices are `ta-IN-PallaviNeural` and `ta-IN-ValluvarNeural`. A supported paid voice service is not provisioned automatically.

Official app handoffs (`open ChatGPT`, `open Gemini`) use external app/browser URLs and do not reuse subscriptions as developer API credit or scrape app sessions.

## Infrastructure readiness

Existing JARVIS AI staging project: `89e7565b-7c4f-49d9-9e20-f95341b9e6c4`; environment `5bb25799-ff36-4e9d-9e0d-548818bb22b3`.

The existing `jarvis-livekit-token-staging` issues LiveKit tokens; it is not the direct Gemini ephemeral-token broker expected by this native transport. The older `jarvis-gemini-gateway` runs source from Greensandpp/openalgo. No service was replaced, redeployed or provisioned. Direct Live activation is therefore UNVERIFIED and remains blocked without a compatible verified-free broker.

## Required phone acceptance — all UNVERIFIED

- iQOO 13 installation/signature compatibility, cold start and single greeting.
- Actual natural voice quality and Tamil/English/Tanglish recognition.
- Ryan/Tamil endpoint availability and installed offline voice genders.
- Acoustic interruption, echo behavior, speaker route and Bluetooth.
- Response latency versus the original standalone APK.
- Real network reconnection and provider quota exhaustion.
- Battery drain, device memory pressure, heat and background/lock-screen lifecycle.
- Phone actions, WhatsApp, reminders, camera, chart assistance, shopping and payment confirmations.

No generative local model is selected or downloaded without actual phone profiling and benchmark evidence. Existing offline intents are available; they are not an open-ended local LLM. Settings can report available RAM, battery and Android thermal status. Full language, latency and sustained thermal tests remain prerequisites to choosing a model. No PC is required by the native audio path or these diagnostics.

## Rollback

Keep the standalone reference installed. Do not uninstall any app to resolve a signing mismatch. This candidate's development package can conflict with an older development build's different CI debug certificate; use the original installed baseline until a compatible signed update is available. Do not disable Play Protect.

Source rollback: use the unchanged detailed Guardian base above; do not reset a stable branch or overwrite user data. This draft PR is unmerged. Credentials remain device-local. Reconnect configuration should be entered only on the owner's phone after backend verification.

## Monthly expense

Additional paid services or billing enabled by this change: none. No paid Gemini, LiveKit or voice call was made for QA. Additional recurring expense authorized here: ₹0. Existing Railway charges/account balances were not audited, so total account expenditure cannot be claimed as ₹0. ₹1,000/month is a preference requiring separate approval, not an active paid budget.
