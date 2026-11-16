# GreenSoil JARVIS Mobile — Source Audit & Implementation Roadmap
Date: 2026-11-17
Scope: original Flutter JARVIS on `Greensandpp/Jarvis`, four-mode consolidated feature branch.
Owner-safe: isolated package, no production changes, no order execution, no paid services authorized.

## Evidence examined
- `README.md`: upstream PrivateAgent/J.A.R.V.I.S. marketing and architecture (Arc Reactor, Iron Man bust, TaskExecutor, Hermes memory, voice, macros, overlays and cloud/local model options). README is **not** proof all components are supported on this owner's phone.
- `APK_INSTALL_RECOVERY_ANDROID16.md`: distinct V1/V2 packages, generic `App not installed`, possible signing mismatch, device-side error absent.
- `SECURITY_PRIVACY_V2_STATUS.md`: privacy toggles, unresolved secure-storage migration and egress verification.
- `TRADING_OVERLAY_REQUIREMENTS.md`: NIFTY/SENSEX PAPER-only scope, verified market data, source timestamps, five-minute locked-close, no auto-orders.
- `Jarvis-Claude-Independent/CLAUDE_BUILD_STATUS.md`: separate contender's privacy/voice improvements, **not automatically present** in this repository.
- Android manifest, Flutter entry, HomeScreen, `JarvisVisualModeHost`, current CI evidence and mobile screenshots.

## Actual baseline and boundaries
- Original working blue JARVIS V1: `com.greensoil.jarvis.custom` (do not replace).
- Consolidated V2 source: `com.greensoil.jarvis.tamiltest`, isolated four-mode QA variants `.visualstaging` and `.visualrelease`.
- Current four-mode source: Core existing native HUD, Office real TaskExecutor state and five role placeholders, APEX/MIRA original offline Flutter painters.
- APEX/MIRA are **visual styles**, not licensed APEX assistant engines or a real connected agent team. No user conversations, tokens or screenshots are sent to the old Vercel preview websites by these modes.
- All commands/microphone routes use the existing native JARVIS host, not independent third-party brains. They still require real mobile device functional verification.
- Existing blue JARVIS may show “System check: 1 part not working”; exact failed subsystem needs diagnostics, not guesswork.

## Critical blockers and priority
**P0 Install** — GitHub Android 16 x86_64 emulator clean-install PASS, ARM64 libraries and 16KB zip/ELF checks PASS, but physical iQOO 13 install still fails with generic `App not installed` for debug and release. Phone has adequate free storage; neither emulator success nor changing visual code proves the physical blocker resolved. Only device-side PackageInstaller/ADB failure log can identify exact cause. Don't uninstall the working V1 or disable Play Protect. Avoid repeated identical ZIP releases.

**P0 Privacy** — Investigate secrets in SharedPreferences, network destinations for AI/TTS/Telegram, SMS/notification/accessibility permissions, and secure screen protections. Never assert “100% offline” from README alone. Apply safe, test-covered changes without destroying existing data.

**P0 Native chat/voice** — Test Gemini/OpenClaw path, Tamil/English/Tanglish STT, no unsolicited beeping, mic permission, TTS, graceful offline fallback and no duplicate text/confirmation dialogs. These are NOT physically verified.

**P1 One-home UI** — Preserve blue reactor as default, let owner select Core/Office/APEX/MIRA in settings/mode selector. Persist the choice. Use native visual renderers, readable controls and resource-aware animation, not unverified remote websites.

**P1 Agent Office** — Five roles must only display “working” if there is real agent status from an authenticated event source. Real Chief→Research/Strategy→Writer→Reviewer handoffs, evidence, rejection and approvals remain unimplemented. No fabricated dashboard progress.

**P1 Trading Mode** — Open TradingView with owner consent, NIFTY/SENSEX read-only/PAPER monitoring, verified premium/OI/index feeds and locked-close. Do NOT change Railway bot, TradingView alerts, broker settings or real orders. Never claim real-time capture without an authorized data feed.

**P2 Quality** — Dynamic animations (listening/thinking/speaking/completed), gestures, ARC bubble shortcuts, local/offline content, owner credits and eventual secure device-to-device backup. Credit original upstream work per license; do not claim third-party licensed APEX source is embedded.

## Release gates
1. Flutter analyzer and tests PASS for exact SHA; APK signing, package ID and ARM64 16KB validations PASS.
2. Android 15/16 emulators install and launch. Record actual outputs.
3. iQOO physical installation PASS with known signer and no removal of V1; otherwise status remains **BLOCKED**.
4. Test: all four modes, persistence after restart, font scaling, keyboard, voice, battery, app backgrounds, approvals, local/offline error handling, native data privacy.
5. No production deployment or “final APK ready” claim until owner-approved physical QA.
