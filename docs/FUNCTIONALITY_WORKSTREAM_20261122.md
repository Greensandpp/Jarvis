# GreenSoil JARVIS — functionality-first workstream (2026-11-22)

## Scope and branch isolation

Owner assigned visual/UI/3D work to Claude. This branch is for **AI brain, local/offline voice, device actions, permission gates, privacy and reliability only**.

Baseline: `fix/reference-visual-and-brain-20261122` at `67e50aab7929b0e23c14d59dbacb5084dcef4c02`. Do not modify visuals, 3D assets, animation, theme code, APK packages, production credentials, or staging deployment.

## Grounded source findings

- `lib/brain/jarvis_brain_service.dart`: offline shortcut -> phone-local chat model (when ready) -> cloud/tool-calling branch. **Routing concern:** with phone-local model ready, device-control commands may be answered as chat rather than executing tool actions. Need deterministic classification and tests before any behavior change.
- `lib/brain/local_intents.dart`: offline shortcuts support time/date, visual/language/voice selection and handoff links. Most device controls are NOT offline shortcuts; do not advertise them as working without a tool execution path.
- `test/brain_tool_calling_test.dart`: simulated tool-calling gate coverage includes approval, blocked actions, verification, limits, language and local shortcuts. This is NOT a real-device or real-model proof.
- `test/free_only_policy_test.dart`: network access is intentionally blocked before cloud requests in free-only configuration. Do not turn on paid API calls, and do not interpret an installed ChatGPT/Gemini subscription as API access.
- PR #6 reports local GGUF + narrow language probes and 272 Flutter regression tests, but **physical iQOO 13 voice, thermal, app lifecycle and sustained performance remain unverified**. Its report also says LiveKit staging crashed, token/gateway sleeping (must be freshly checked before relying on it).

## Implementation sequence (functional code only)

1. **Tool-routing safety**: distinguish local chat from actionable intents; ensure local chat NEVER claims to complete phone action. Preserve owner confirmation for messages, calls, financial and sensitive actions. Test English/Tamil/Tanglish command variants.
2. **Voice lifecycle**: reproduce mic permission revocation, interruption, duplicate audio, silence, speaking cancellation; test with actual streaming audio and lifecycle states, not only mocked callbacks.
3. **Offline brain**: verify actual GGUF file import/checksum, RAM/thermal gate, offline network denial, cancellation and Tanglish conversational responses; measure latencies on physical device.
4. **Android controls**: classify each feature as Android intent, permission-gated OS API, external service, or unsupported; verify outcome rather than returning premature success.
5. **Security and spending**: no automatic payments/trades/OTP submission; no cloud request without provider/privacy consent; no API billable activation.
6. **Reliability**: lifecycle recovery and debug logs without recording credentials or private conversation content.
7. **Device acceptance**: iQOO 13 Android 16/17 tests with explicit human permissions; compare against preserved standalone voice APK.

## Current gate

This commit is **audit/planning only**; it makes no runtime behavior change. Functionality is NOT yet accepted; do not merge, ship, or enable broker/payment actions. Before touching shared runtime files, compare HEAD against Claude's active branch and keep changes cherry-pickable.
