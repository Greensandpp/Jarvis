# GreenSoil JARVIS — Serpent Guardian real-time 3D preparation

Branch `feature/serpent-guardian-rt3d-20261120` (based on `feature/jarvis-unified-20261120`, commit `56870e6`).
Nothing was merged to `main`, nothing was deployed, and no existing install is replaced.

**Status: PROTOTYPE.** The engine (state machine, rigs, VFX, audio/viseme hooks, settings) is real and runs live.
The humanoid and serpent **geometry are procedural placeholders**, labelled on screen
("PROCEDURAL PLACEHOLDER · engine test · not the final model"). The approved Serpent Guardian model is
**not** built yet; it needs the 3D assets listed in section 5.

## 1. What was inspected and preserved

| Item | Finding | Kept |
|---|---|---|
| Project | Flutter app `private_agent` (Dart 3.12, Flutter stable), repo `Greensandpp/Jarvis` | yes |
| Package identity | `com.greensoil.jarvis.unified` (Standard) and `.full` (Full Control) + build-type suffixes `.visualstaging` / `.visualrelease` | unchanged |
| Graphics today | 2D `CustomPainter` scenes only: JARVIS Core HUD, AIRA (10 models), Agent Office, APEX, MIRA. No 3D engine dependency | all kept |
| Home | Drawer (Menu) · JARVIS title · Settings; visual mode row; one visual at a time; compact Type + Mic + Live + Send dock | kept; Serpent is one more selectable mode |
| User settings | `SharedPreferences` keys (`jarvis_visual_mode_v1`, AIRA keys, …) | untouched; avatar uses its own new key |

## 2. Renderer decision (real-time 3D on Android)

| Option | Verdict |
|---|---|
| **Google Filament via Thermion (`thermion_flutter`)** | **Recommended for the final model.** Filament is Google's Android-first PBR engine with glTF 2.0, skinning and morph targets (needed for metallic armour, bone animation and viseme blendshapes). Thermion wraps it for Flutter stable with no engine fork. |
| Native Filament (`gltfio-android`) through a Flutter `Texture` | Fallback if Thermion has a blocker on the iQOO 13. More Kotlin glue, same engine. |
| `flutter_scene` (Flutter GPU / Impeller) | Not now: still an early preview that needs the master channel and the Flutter GPU flag. |
| Unity as a Library | Not recommended: adds tens of MB, a second runtime and licensing for one avatar. |
| Current procedural Canvas renderer (this branch) | Engine test bed only. Real-time and 3D-projected, but CPU-shaded and flat-lit; it cannot reach the reference image's quality. |

The engine code is renderer-independent: `lib/avatar/core/` is pure Dart (no Flutter import). A Filament backend
reuses the state machine, rig drive values, audio bus, viseme timeline and settings, and replaces only the
Canvas painter.

## 3. What is implemented (source)

| Requirement | Where | Notes |
|---|---|---|
| State machine INTRO → MATERIALIZING → IDLE / LISTENING / THINKING / SPEAKING / CLOSING | `core/avatar_state_machine.dart` | Storyboard timing: 1.5 s intro, humanoid 1.7 s, serpent 1.3 s, reveal 1.5 s. Requests during formation are queued, cross-fades take 0.4 s, CLOSING dissolves, and the intro can be replayed. It follows the shared JARVIS phase. |
| Articulated serpent | `core/rigs.dart` `SerpentRig` | Catmull-Rom spline through 18 animated controls, coiling around the humanoid and rising behind it. Travelling S-waves, slow coil drift, neck rise and lower. The head yaw/pitch is independent, the hinged jaw opens occasionally and wider at the reveal, the eyes pulse and move their gaze, and the body is positioned relative to the humanoid. |
| Glowing animated scales | `core/avatar_scene.dart` `_serpentMesh` | Offset scale rows, travelling shimmer band, fresnel hologram, additive translucency, frontier glow while forming |
| Humanoid placeholder | `HumanoidRig` | Floating pose, hover, breathing (chest/shoulders), micro head turns, arm raise on activation and listening, finger curl, energy orbs in the palms, chest core |
| Rings, ribbons, glitter, sparks, lightning, chest glow | `avatar_scene.dart` | Platform rings power on, tilted orbit rings, 3 spiral ribbons, a particle pool (glitter, sparks, formation particles), midpoint-displacement lightning between core, hands, serpent and platform |
| Mic / audio reaction hooks | `core/audio_reactive.dart` | Attack/release envelope plus onset pulses. Mic comes from the JARVIS recogniser (or the Gemini Live level). Output currently comes from the viseme envelope; a future PCM tap calls `pushOutput()` |
| Viseme / phoneme interface for Tamil lip sync | `core/viseme.dart` | 15-viseme set, `FaceRig` interface, `VisemeEvent` timeline with co-articulated blending, rule-based mapper for Tamil script, Tanglish and English. `VoiceService.speak/speakIn` publish each line |
| Persistent per-avatar settings | `core/avatar_settings.dart`, `avatar_runtime.dart`, `avatar_settings_screen.dart` | RGB sliders and a HEX/`rgb()` field with swatches for primary, secondary, particle and accent colours. Also particle density, size, X/Y position, speed, glow, lightning, intro/outro sound (offline-generated WAV), background effects, Quality/Balanced/Battery mode and a stats overlay. Changes apply live. Key: `avatar_settings_v1_serpent_guardian` |
| Minimal home | `widgets/jarvis_visual_mode_host.dart` | One new mode, "Serpent", on the existing selector. The same Type + Mic + Send dock is routed to native JARVIS. Long-press the avatar for settings; double-tap replays the intro |
| Voice/brain | `brain/local_intents.dart`, `visual_bus.dart` | "serpent mode", "switch to serpent guardian" and "naagam mode" switch the visual; the brain's `set_visual` tool accepts `serpent` |
| Performance telemetry | `avatar_perf.dart` | `SERPENT_PERF` logcat line every 5 s: fps, CPU p50/p95, UI/raster p95, triangles, particles |

## 4. Verification report

Evidence comes from GitHub Actions run 44757133303 (commit `b82b3ca`, workflow `.github/workflows/serpent-guardian.yml`).
The test-only prerelease `serpent-guardian-proto-44757133303-1` holds the APKs, screenshots, perf logs and test logs.

| Check | Result | Evidence |
|---|---|---|
| `flutter analyze` (errors and warnings fatal) | PASS | 0 errors, 0 warnings (infos only, the same kind as the existing code) |
| Full unit/widget suite: 185 tests (existing tests plus new avatar core and view tests) | PASS | `flutter-test.txt` |
| State machine timeline, queueing, cross-fades, CLOSING, replay | PASS-UNIT | `avatar_core_test.dart` |
| Serpent spline continuity, independent head/jaw, humanoid breathing/hover/arm raise | PASS-UNIT | `avatar_core_test.dart` |
| Tamil / Tanglish viseme mapping, normalised blending, jaw drive | PASS-UNIT | `avatar_core_test.dart` |
| Audio envelope / onset hooks | PASS-UNIT | `avatar_core_test.dart` |
| Settings: JSON round trip, corrupted storage, HEX/RGB parsing, per-avatar key, live apply, persistence | PASS-UNIT | both test files |
| Settings screen: HEX picker, invalid HEX rejected, sliders, Battery mode, intro sound switch | PASS-UNIT | `serpent_guardian_view_test.dart` |
| Existing host: Serpent is one selectable mode; dock text + mic still reach native JARVIS | PASS-UNIT | `serpent_guardian_view_test.dart` |
| Release APKs build (Standard 72.1 MB, Full 72.2 MB), 16 KB alignment, permission policy unchanged | PASS | build job |
| U01–U04, U13 (install side by side, permissions, original 5 modes, AIRA models, background) on Android 15 and 16 emulators | PASS-DEVICE | `device-summary-API35/36.txt` |
| U03S Serpent Guardian launches in Balanced / Quality / Battery without a crash; perf logged | PASS-DEVICE | `serpent-*.png`, `serpent-perf-*.txt` |
| In-app acceptance I01–I13 (existing features) on Android 15 and 16 | PASS-DEVICE, 0 FAIL | `in-app-summary-API35/36.txt` |
| Real-phone frame rate (iQOO 13, GPU) | UNVERIFIED | Needs the owner's phone; enable "Show performance stats" or read `adb logcat \| grep SERPENT_PERF` |
| Lip sync against real Tamil TTS audio | UNVERIFIED | Mouth follows estimated timing; needs on-phone listening test |
| Final approved Serpent Guardian look | NOT BUILT | Needs the assets in section 5 |

**Performance (CI emulator, debug build, SwiftShader software GPU — far slower than a phone; treat as relative only).**
Dart scene CPU time per frame: p50 4–5 ms, p95 20–35 ms (debug JIT). Geometry: about 3,500 triangles (Balanced),
4,300 (Quality) and 2,600 (Battery), with 65–400 particles. Raster p95 is about 1 s with blur glows and about 0.2 s in
Battery mode (no blur). This shows that soft blur is the main raster cost on a software GPU. The emulator ran at
3–9 fps, so the intro timeline also ran slowly there: simulation steps are capped at 0.1 s per frame. Phone numbers are
UNVERIFIED.

**Framing fix after this run:** the screenshots showed the hands and serpent head touching the screen edges, so the default
camera now fits a 3.8-unit tall view instead of 3.25. The Avatar size slider still scales it.

## 5. Required final 3D assets (not available — placeholders used)

1. **Serpent Guardian humanoid, `.glb` (glTF 2.0)**, matching the approved reference: face, helmet, silver-black scale armour, emerald/cyan seams, chest reactor, armour fins and hands.
   - About 40–70k triangles (LOD0) plus a LOD1 at about 15k for Battery mode.
   - PBR metallic-roughness textures at 2K (base colour, ORM, normal, emissive), KTX2/Basis compressed.
   - Separate emissive mask for the seams, eyes and chest core, so the colour settings can tint them.
2. **Humanoid skeleton**: humanoid bone naming (hips, spine, chest, neck, head, jaw, shoulders, arms, hands with 3 fingers + thumb, legs). Skinned with at most 4 influences per vertex.
3. **Facial morph targets (blendshapes)**: the 15 visemes in `Viseme` (`sil, PP, FF, TH, DD, kk, CH, SS, nn, RR, aa, E, ih, oh, ou`), plus `jawOpen`, `blinkL`/`blinkR`, `smile` and `focus`.
4. **Serpent / cobra `.glb`**: translucent hologram body with a scale UV layout. Either a spine chain of 24–48 bones (driven by `SerpentRig` spline samples), or a tube mesh skinned to it. Separate head with a `jaw` bone, eye emissive and fangs.
5. **Body animation clips** (optional, blended on top of procedural motion): idle breathing, hover, arm raise ("power"), listening lean, thinking pose, closing dissolve pose.
6. **Hologram materials**: Filament `.filamat` files compiled with the matching `matc` version (fresnel hologram, additive scales, dissolve with noise threshold for formation).
7. **Audio (optional)**: licensed intro/outro sound effects if the generated ones are not wanted.
8. **Licence/ownership** of the reference character design, for the 3D artist or vendor.

## 6. Next steps (in order)

1. Add Thermion (Filament) behind the existing `JarvisVisualMode.serpent` slot, gated by a feature flag. Load a test glTF and measure on the iQOO 13.
2. Map `RigDrive`, `SerpentRig` spine samples and `ProceduralFaceRig` values to bones and morph weights.
3. Replace the estimated viseme timing with real timings (Edge TTS word boundaries or Gemini Live audio) for Tamil.
