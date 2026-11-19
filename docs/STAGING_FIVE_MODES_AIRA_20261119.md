# GreenSoil JARVIS — Five-Mode + AIRA Staging (2026-11-19)

**Status: STAGING ONLY. Not an update for the installed JARVIS. Not promoted.**

Branch `staging/aira-five-modes-20261119`, based on
`feature/gemini-live-secure-fourmode-20261117@8af4622` which is a clean
descendant of the verified four-mode baseline
`feature/jarvis-four-modes-consolidated-20261115@a04e650` (CI run
43933978077 success). The voice branch added only 3 files (Live session
scaffold + tests + workflow) so it was taken whole, not cherry-picked.

Evidence for every PASS below comes from CI logs of the commit named in
the PR description, not from job names.

## What changed

| Area | Files |
|---|---|
| AIRA engine (10 models, 6 states) | `lib/widgets/aira/aira_models.dart`, `aira_painter.dart`, `aira_view.dart` |
| Five-mode selector + shared dock | `lib/widgets/jarvis_visual_mode_host.dart` |
| Agent Office (authenticated, read-only) | `lib/services/agent_office/agent_office.dart`, `lib/widgets/agent_office_view.dart` |
| Gemini Live transport | `lib/services/gemini_live/*.dart`, `lib/services/live_voice_session.dart` (+`fail()`) |
| Native audio bridge | `android/.../LiveAudioBridge.kt`, `MainActivity.kt` (+12 lines: register, onStop/onDestroy release) |
| Reference token broker (not deployed) | `tool/gemini_live_token_broker/broker.py` |
| Staging variants / CI | `scripts/make_safe_mobile_staging.py`, `scripts/emulator_smoke.sh`, `.github/workflows/jarvis-five-modes-staging.yml` |
| Tests | `test/aira_render_test.dart`, `five_mode_host_test.dart`, `agent_office_test.dart`, `gemini_live_test.dart`, `security_privacy_test.dart` |

**Untouched (0-line diff vs baseline):** `jarvis_hud_widget.dart` (JARVIS
Core), `home_screen.dart`, `jarvis_service.dart`, `AndroidManifest.xml`,
`build.gradle.kts` (package IDs, signing config, permissions).

## Design notes

- **One brain.** All modes call the same `onCommand` (`HomeScreen._submit`) and
  `JarvisService.instance.toggleListening`. AIRA reads `JarvisService.phase`
  (idle/listening/thinking/executing/speaking → AIRA states, plus a 1.8 s
  *Completed* transient). Mode switching only swaps the visual subtree.
- **Persistence.** Same key `jarvis_visual_mode_v1`; old values
  `core/office/apex/mira` restore unchanged; unknown → Core.
- **AIRA.** Original CustomPainter code, additive blending, batched points,
  pseudo-3D projection. Quality High 60 fps / Balanced 45 / Battery 30, adaptive
  particle shedding when frames run slow, reduce-motion (app setting or OS
  "remove animations"), per-model brightness/speed, renamable display name.
  Ticker stops off-screen and in background. Paint errors fall back to a
  simple gradient instead of a blank screen.
- **Office.** LIVE only if HTTPS + bearer-authenticated provider returns
  `mode: "live"`. Bundled JSON is always SAMPLE. Default DISCONNECTED. RED
  actions reported executed without owner approval are flagged; >3
  rejections flagged. The phone never approves/executes RED actions.
- **Gemini Live.** Broker URL + device token set by owner → broker returns
  single-use `auth_tokens/...` (≤35 min; raw `AIza` keys refused) →
  `BidiGenerateContentConstrained` WebSocket → 16 kHz PCM up, 24 kHz down,
  server `interrupted` flushes playback (barge-in). Mic: explicit tap +
  disclosure + runtime permission; wake-word recognizer paused first;
  stops on background/onStop; GoAway → one reconnect; any other drop →
  FAILED with a fixed safe message. No always-on, no lock-screen.

## Requirement status

| Requirement | Status | Evidence / reason |
|---|---|---|
| 5 selectable modes, persisted, return to Core | PASS (unit/widget) | `five_mode_host_test.dart` |
| Same native brain/chat/mic across modes | PASS (widget) | routing test: 4 modes → same callbacks |
| JARVIS Core unchanged | PASS (source) | 0-line diff of HUD/home/service |
| AIRA 10 distinct, bright, animated models | PASS (pixel tests) | `aira_render_test.dart`: peak=1.00, mean 0.039–0.083, motion>0.004, min pairwise diff 0.020 |
| AIRA 6 states distinct | PASS (pixel tests) | each state differs from idle for all 10 models |
| AIRA on real Android rendering | PASS (emulator) | Android 15 + 16 screenshots reviewed: 10-model picker, Neural Reactor, Amber Hologram, Electric Web, Jellyfish, Solar Flare, Violet Vortex all render bright on OLED black |
| Animation over time on device | PASS (emulator) | pixels changed between frames 2 s apart (API 36): Core 561k, AIRA 195k, APEX 141k, MIRA 168k; Office 0 (static list, expected) |
| Offline visuals never use network | PASS | zero HttpClient creations; banned-import scan |
| Mobile layout 412×915, keyboard open | PASS (widget) | selector fits; dock stays on screen; compact picker |
| Agent Office honest data | PASS (unit) | sample≠live, sanitization, tiers, 3-loop cap |
| Office live provider | UNVERIFIED | no authenticated provider exists yet |
| Gemini Live protocol + transport | PASS vs local mock | real `dart:io` WebSocket round trip to local mock server |
| Gemini Live against Google | **UNVERIFIED / BLOCKED** | needs owner-approved broker + key; not provided |
| Native audio (AEC/NS, focus, BT) | BUILD PASS, behaviour UNVERIFIED | compiles in CI; needs a physical device |
| Tamil / English / Tanglish voice | **UNVERIFIED** | needs owner-consented on-device recordings |
| Wake word, hands-free | unchanged existing feature | not re-tested here |
| Android 15/16 emulator install + launch | PASS | all 4 APKs install; all 5 modes launch with no FATAL; HOME/background no crash; release, visualsafe, voicesafe launch |
| AIRA badge matches shared phase | **OPEN** | one API 36 frame showed dock `JARVIS · SPEAKING` with badge `LIVE · IDLE`. Not reproduced in tests; a defensive mid-build guard was added but is unproven. Re-check on device |
| Frame rate / jank on device | **UNVERIFIED** | `dumpsys gfxinfo` does not count Flutter's own surface frames; software-GPU emulator is not representative. Needs iQOO profiling |
| Memory (debug APK, AIRA, emulator) | observed | PSS ≈ 430 MB on a JIT debug build; release build not measured |
| 16 KB ELF alignment (release) | PASS (CI) | `16KB ELF check: PASS` |
| No credentials in repo | PASS | `security_privacy_test.dart` scan |
| iQOO 13 physical install / Play Protect | **UNVERIFIED (blocker)** | see below |

## Permission audit (main build — unchanged, needs owner decision)

Declared in our manifest: INTERNET, ACCESS_NETWORK_STATE, WAKE_LOCK,
SYSTEM_ALERT_WINDOW, FOREGROUND_SERVICE(+SPECIAL_USE, MICROPHONE),
QUERY_ALL_PACKAGES, RECORD_AUDIO, READ_CONTACTS, POST_NOTIFICATIONS, VIBRATE,
WRITE_SETTINGS, MODIFY_AUDIO_SETTINGS, SET_ALARM, CAMERA,
READ/WRITE_EXTERNAL_STORAGE (legacy max SDK), PACKAGE_USAGE_STATS.
Components: AccessibilityService (screen read + gestures + screenshots),
NotificationListener (disabled by default), Shizuku provider (disabled),
overlay foreground service. `usesCleartextTraffic="true"` (used by Home
Assistant LAN, local Ollama, ISS API).

**Merged from libraries (found in real `aapt` output, not in our manifest):**
`REQUEST_DELETE_PACKAGES`, `moe.shizuku.manager.permission.API_V23`, plus
VIBRATE/POST_NOTIFICATIONS/WAKE_LOCK.

Likely Play Protect risk drivers for a sideloaded, debug-key-signed APK:
AccessibilityService with `canTakeScreenshot`/`typeAllMask`, QUERY_ALL_PACKAGES,
SYSTEM_ALERT_WINDOW, REQUEST_DELETE_PACKAGES, notification listener,
WRITE_SETTINGS/PACKAGE_USAGE_STATS, and a signing certificate that changes
every CI run (ephemeral debug keystore).

## Play Protect — legitimate plan (no bypass)

1. **Differential test (owner, 2 minutes):** install
   `GreenSoil-JARVIS-5MODE-STAGING-visualsafe.apk` and then
   `…-voicesafe.apk` on the iQOO 13. They have no accessibility, overlay,
   contacts, package listing, settings, usage-stats, delete-packages or
   Shizuku. If they install while the full build is blocked, the block is
   permission-driven; if they are also blocked, it is signing/provenance.
   Do **not** turn off Play Protect; just report what the dialog says.
2. **Stable signing:** release builds should use the owner's own upload
   key (kept out of the repo, injected as a CI secret) instead of a
   per-run debug key. Needs owner approval.
3. **Legitimate distribution:** Play Console internal testing track (Play
   scans and trusts it) and/or Google's Play Protect developer appeal for
   the specific package.
4. **Permission minimisation (owner approval required):** make
   QUERY_ALL_PACKAGES → `<queries>` for known launch targets; drop
   REQUEST_DELETE_PACKAGES via `tools:node="remove"` unless used; keep
   accessibility/overlay/notification features behind explicit in-app
   consent screens (already default-disabled where possible).
5. **Diagnostics if still blocked:** the installer's exact text,
   `adb install` failure code and `adb logcat -s PackageInstaller` from a
   PC (optional, owner's choice).

## Staging artifacts

CI artifact `JARVIS-5MODE-AIRA-STAGING-APKS-NOT-UPDATE` (a ZIP — GitHub
always zips artifacts). Extract it; it contains four APKs with distinct
package IDs that install **beside** the working JARVIS, never over it:

| APK | Package | Purpose |
|---|---|---|
| `…-debug.apk` | `com.greensoil.jarvis.tamiltest.visualstaging` | full features, debuggable |
| `…-visualrelease.apk` | `…tamiltest.visualrelease` | full features, release mode |
| `…-visualsafe.apk` | `…tamiltest.visualsafe` | visuals + text only (Play Protect differential) |
| `…-voicesafe.apk` | `…tamiltest.voicesafe` | visuals + text + mic for Live voice test |

All are signed with the CI runner's temporary debug key (APK Signature Scheme
v2 verified). SHA-256 values are printed in the job log (`SHA256SUMS`).

Effective permissions from `aapt` (CI): **visualsafe** = INTERNET,
ACCESS_NETWORK_STATE, VIBRATE, POST_NOTIFICATIONS, WAKE_LOCK. **voicesafe** =
the same plus RECORD_AUDIO and MODIFY_AUDIO_SETTINGS. Full builds = the
manifest set plus merged REQUEST_DELETE_PACKAGES and Shizuku API_V23.

## Rollback

Nothing was merged, deployed or force-pushed. To roll back:

- Delete the branch: `git push origin --delete staging/aira-five-modes-20261119`
- Or revert individual commits on the branch with `git revert <sha>`.
- On a phone, uninstall only the staging package(s) above; the original
  JARVIS package and its data are untouched (different application IDs).
- The four-mode baseline and Live scaffold branches are unchanged.

## Not done / blocked

- Real Gemini Live session: needs owner-approved broker, Gemini key on the
  server, and a model id/voice check. `broker.py` is a reference only.
- Live transcripts are shown in the dock but are not yet merged into the
  text chat history (avoids a second AI reply; needs design decision).
- Separate `Jarvis_Android_Assistant.zip` (Kotlin Gemini sample): **not
  uploaded**, not inspected, nothing copied from it.
- OpenClaw/Railway gateway, trading/Pine/Telegram: not touched.
- Physical iQOO 13 install, Tamil voice quality, battery drain: owner device test.
