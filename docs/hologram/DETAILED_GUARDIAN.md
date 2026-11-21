# Detailed Guardian development candidate — 21 November 2026

Foundation: authenticated voice-safety commit 7761932b642d7d5cc91215673bf06829f72cc80d (CI 44851104070 successful, including both Android 16 variants). New isolated branch: fix/jarvis-detailed-guardian-20261121. Existing branches and package identities remain unchanged.

## Actual geometry and rendering

Three.js r180 WebGL2, fully offline bundle. Original `guardian.js` parametric sculpture with 169 bevelled/curved armour parts, 38 articulated bones, 53,188 humanoid triangles. Four material groups in a genuine SkinnedMesh after assembly. Helmet, faceplate, separate eye/jaw bones, layered chest/abdomen/limbs, five two-segment fingers per hand, reactor and metallic trims. No character photographs, sprites or BoxGeometry armour. The separately rigged 32-bone serpent uses tapered, scale-ridged skin, sculpted hood/head, eyes, jaw, fangs and tongue. Helmet clearance path keeps its head beside the face. Its world-space trail follows its actual head.

Cinematic stages: platform, particle convergence, live skeleton helper, separated armour assembly, reactor/eyes, independent serpent appearance/coiling, camera approach, idle. Skip and reduced motion preserved. Intro audio remains disabled; optional soundtrack is not implemented. Speaking jaw motion is state/level driven rather than phoneme-accurate lip sync.

Neutral studio PMREM reflections and ACES tone mapping preserve metallic depth. High/Ultra enable actual GPU bright-pass bloom. Balanced/Battery target 30 FPS with bounded resolution/particle counts; High/Ultra target 60 FPS. These are targets, not verified phone measurements. Context restoration rebuilds the procedural environment. Existing six themes and conversation/voice continuity remain.

## Reliability changes

Preserves serialized greeting and exclusive SpeechOutputController / Live audio ownership. Rejects a stale pinned TTS voice from another language. When cloud TTS is not authorized, only voices reported as local are eligible, with text fallback rather than an engine default that could select a network voice. Resource availability and reported gender are device-specific.

AI success is recorded only after parsing usable content or tool calls. Remembered prior-session success cannot imply a current connection. Configuration missing, auth required, offline transport and other errors are distinguished. No provider credentials, broker deployment, paid activation or provider-enforced spending cap is introduced. Existing owner-provided configuration is preserved.

## Verification and gates

Local Node rig tests passed: articulation, bone deformation/weights, independent motion, assembly, six palettes, non-box geometry, detail inventory, helmet clearance, quality presets and intro stages. Shell syntax and Python compile checks passed. Local Flutter execution is UNVERIFIED: restored workspace lacks pub-cache packages and startup dependency restoration timed out. CI must run analyzer/full Flutter suite and actual WebGL checks before APK build; Android 16 emulator acceptance gates encrypted artifact delivery. Physical iQOO 13 / Android 17, installed Tamil resources, acoustic echo/barge-in, thermal/battery impact and Play Protect outcomes remain UNVERIFIED.

Full is a test-only development variant, encrypted before GitHub artifact upload using the existing recipient public key. No production signing key is available. CI debug certificates are not a verified in-place upgrade path for an existing installation. Do not uninstall the working app, disable Play Protect or enable broad permissions to work around a failure.

Visual reference fidelity remains subject to actual renderer inspection and owner acceptance. A parametric detailed model is not a claim of film-quality character modelling.

## Follow-up hardening

Native assistant audio focus is coordinated with speech request IDs for local TTS and cloud MP3 playback. Denial is text-only; loss cancels the current ticket and native audio, with no automatic replay. Stale focus events cannot stop a replacement utterance. A successful engine completion emits COMPLETED briefly, then derives the current real state; cancelled/missing-resource speech does not emit completion. Provider/key/endpoint changes invalidate prior verification; CONNECTING reflects actual HTTP work.

The final CI additionally records a real WebGL motion video, checks native Android audio-focus grant/release/invalid IDs, installs the exact delivery APK after integration testing, launches its production entrypoint, captures its screen, scans its process log for fatal crashes and records memory/gfx/battery diagnostics. This is emulator evidence only. Actual audible phone focus behavior and acoustic barge-in remain unverified.

First candidate bc293b042cd8fec224ddfda401df1967fa20075c passed CI 44855578917: 251 Flutter tests, WebGL, Android 16 integration on both variants, signatures/permission/ELF/ZIP alignment. Screenshot review exposed a cropped serpent head and foreground MIRA crystals. The follow-up moves the head lane inward (still clear of the face) and keeps environmental objects behind the character. Emulator snapshots were 3.53 / 6.00 FPS; this is not a phone performance result and does not meet the 30/60 target on SwiftShader. That run's post-drive meminfo had no app process; the follow-up installs/launches the actual delivery APK before resource capture.

Signing compatibility: the first new CI certificate digest 17f664a8f523c9dca7f8f39b644b04b01ffad93e75d0e4698b359d2588535010 differs from the earlier 7ae6a83 build certificate c940bdc910cd490b6cc9c9613f256de5f4429441c7e87c49be3f5762d327ce97. Same-package installation over that old build is blocked by Android signature enforcement. This is a verified migration blocker; retaining the old signing key or an owner-approved migration is required. No uninstall, package rename or protection bypass is authorized here.

Native cancellation audit also found a transitional-state race: `stopAudio` queried `isPlaying()` before release, while `onPrepared` unconditionally started the player. A transitional-state error could skip release, leaving delayed audio queued. Native playback now uses generation and focus-ID guards, unconditionally releases on cancellation/focus release, detaches callbacks and settles only its own result. The final Android integration exercises five real MediaPlayer play/cancel requests per variant using a private silent WAV fixture, records observed preparing states and asserts no pending/playing player or delayed start. This is native lifecycle evidence, not proof of audible female/Tamil speech on the phone.
