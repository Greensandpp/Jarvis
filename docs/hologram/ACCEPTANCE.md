# GreenSoil JARVIS holographic development acceptance

Date: 2026-11-21 IST. Isolated branch: `fix/jarvis-holographic-home-20261121`.

## Verified source baseline

Remote V3 head `44e5e98a00031032758445132ee60018736b630d` plus the voice tap / completion / startup changes from `ba3fcfbf506002b308446031adec8c56381a48bc`. Remote branch heads were fetched afresh. Known historical CI `44808224751` completed successfully, but is not acceptance evidence for this candidate.

## Code changes and root causes

- Root always opens JARVIS, including fresh installations and saved legacy Agent settings. Agents remain under Settings → Agents. No automatic startup greeting. Backend agent implementations retained.
- Multiple services previously bypassed VoiceService and called Edge playback directly. Translation also created another FlutterTts instance. Those services now use the same SpeechOutputController. Speech tickets invalidate pending synthesis and serialize driver cancellation. Edge synthesis checks its generation before starting MediaPlayer; cancelled cloud work cannot resume and fall back to a second local voice. Stale TTS completion handlers no longer mutate a newer session.
- Explicit ARC taps interrupt the current output or finalize a capture once. Continuous recognition is controlled by the Always-On setting; opening the home no longer automatically requests the microphone or starts repeated recognizer rearming. Backgrounding without Always-On cancels capture and playback. Live audio takes exclusive output ownership.
- Proactive monitor follows screen lifecycle and no longer leaks its periodic timer after leaving the home.
- Production home uses a silent local Three.js r180 WebGL runtime in Android WebView. Content Security Policy forbids network requests, image/media loading and external navigation. Its bridge accepts only a mic tap and bounded renderer telemetry. No Android execution bridge is exposed to JavaScript.
- Existing one-input neon dock, user/assistant colours, expandable history and configurable auto-hide retained. Six 3D themes persist independently of speech and conversation.

## Actual 3D asset inventory

- `assets/hologram/three.core.js`, `three.module.js`: vendored Three.js 0.180.0, MIT licence included.
- `scene.js`: original procedural humanoid SkinnedMesh (38 bones, rigid armour attachments, shoulders/elbows/wrists, 20 finger joints, jaw and two eye bones), independent serpent SkinnedMesh (32 bones, weighted skin, head and jaw), platform and environmental meshes.
- `scene.bundle.js`: offline production bundle; no image character, remote loader, CDN or speech engine.
- Intro: platform and energy, under-mesh silhouette, armour assembly, emissive reactor/eyes, independent snake materialization, camera approach and return to service-driven animation. Skip/disable supported, once per launch.
- Six palettes and environments: Snake, Forest trunks, Solar rings, Inferno plasma shards, APEX geometric HUD, MIRA crystals. A prototype of articulated armour, not final reference-quality modelling or phoneme-accurate facial animation.

## Local executable results

| Check | Result | Evidence |
|---|---|---|
| Flutter tests | PASS — 243 tests | Flutter 3.50.1 / Dart 3.14.0, `flutter test --reporter expanded` |
| Analyzer | PASS — zero errors/warnings | `flutter analyze --no-fatal-infos` exit 0; 75 informational messages, mostly SDK Material deprecations |
| Rapid speech replacements | PASS | 30 requests leave one valid playback ticket; cancellation during synthesis, stale completion and driver ordering checked |
| Voice-controller regressions | PASS | `test/speech_output_controller_test.dart` |
| Startup / composer / theme / intro callback | PASS | `test/widget_test.dart`, `test/v3_home_test.dart`, `test/hologram_theme_test.dart` |
| Independent skeletal motion | PASS | `node scripts/hologram_test.mjs`; humanoid and serpent move independently, valid skin weights, real vertex deformation |
| Rendered WebGL browser evidence | UNVERIFIED locally | Local Chromium cannot create its Unix socket in this workspace; CI test provided |
| Android builds / install / manifest | UNVERIFIED until CI | Both variants and merged-permission/signature checks provided |
| Android 16 WebView runtime | UNVERIFIED until CI | Fresh startup, actual renderer readiness, bone motion, intro completion and persisted themes test provided |
| iQOO 13 Android 16/17 | UNVERIFIED | No attached owner device or Android 17 emulator |

## Security and remaining blockers

No merge, deployment, production release, paid API activation or Android-security bypass. Repository is public, so every new development APK is encrypted with a per-session recipient public key before Actions upload; no unencrypted Full Control binary is published. Existing build types use CI debug signing, not an owner production signing key. Signature mismatch with an older installation must not be solved by disabling Play Protect or deleting owner data.

The historical app still supports owner-entered cloud API keys stored in SharedPreferences. They are not hardcoded into this candidate, but that legacy storage does **not** meet the requested broker-only key architecture. A separately provisioned authenticated chat broker and migration are still required; no cloud backend is deployed here. Gemini Live already has a reference ephemeral-token broker but its actual service/configuration is unverified. No assertion of unlimited cloud use or a provider-enforced ₹1,000 cap is made. Provider billing and complete usage reconciliation remain unimplemented.

Local basic intents, reminders/notes and app launch paths are preserved. No local LLM or Tamil voice pack is bundled. Tamil recognition/TTS depends on installed device resources; missing local language is text-only, not a silent wrong-language fallback. Installed female voice availability must be measured on the phone.

Tap interruption is implemented. Acoustic barge-in during ordinary local TTS is not implemented: recognition pauses to prevent speaker feedback. Native Gemini Live audio has AEC/noise suppression capability checks and interruption support, but requires configured broker/consent and device testing. There is no separately bundled local wake-word engine. Android-compliant foreground/lockscreen restrictions and actual OEM beeps remain device-specific.

## Regression acceptance checklist

| Defect / feature | Candidate status |
|---|---|
| Wrong startup / Private Agent on launch | PASS in widget tests; Android test pending |
| Simultaneous male/female speech, direct service bypasses | Controller regression PASS; actual audible phone test UNVERIFIED |
| Repeated ARC tap speech / state race | Existing tap guards retained; cancellation tests PASS; physical mic tests UNVERIFIED |
| Mic permission/lifecycle, resume and periodic beep | No implicit startup capture; OEM/device behavior UNVERIFIED |
| Missing Tamil / offline resources / always-ear | Honest capability diagnostics retained; device availability UNVERIFIED |
| Hands-free acoustic interruption | NOT IMPLEMENTED for local TTS; Live integration UNVERIFIED |
| Actual model selection/display/fallback | Existing bounded discovery/fallback retained; model tests PASS; live provider UNVERIFIED |
| Static image workaround / head, arms, fingers / snake | Replaced with genuine 3D skeletal prototype; movement tests PASS |
| Intro / theme persistence / one chat input / auto-hide | Unit/widget tests PASS; rendered Android acceptance pending |
| Full APK install warning / Android 16/17 / Play Protect | Android 16 emulator test pending; Android 17 / OEM Play Protect UNVERIFIED |
| Initial permissions / security / overlay | Existing reduced-permission manifests retained; merged APK audit pending |
| Billing / ₹1,000 spending protection / broker-only keys | BLOCKED / incomplete as described above |
| Performance, memory, battery | UNVERIFIED on phone; desktop/emulator FPS must be labelled by environment |

Final acceptance has not been claimed. A working articulated prototype is a permitted intermediate deliverable; final detailed modelling, phone speech tests, broker/billing protection and Android 17 acceptance remain necessary.
