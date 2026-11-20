# JARVIS V3: status and evidence

Branch `ccr-26a57092-mc6r1g`, built on the reported checkpoint
`af7a82699e205f2c08ad8de467426f4502ba868a` (`feature/serpent-guardian-rt3d-20261120`).
`main`/`master` and all earlier branches and releases are untouched. Application IDs are unchanged
(`com.greensoil.jarvis.unified[.full].visualstaging` for debug, `.visualrelease` for release).

Labels: **PASS** (verified by a test or a run) · **FAIL** · **PARTIAL** (part is done, the rest is
listed) · **UNVERIFIED** (cannot be checked without the owner's phone) · **BLOCKED** (a missing input).

## What changed

| Area | Status | Notes |
| --- | --- | --- |
| Main screen layout | PASS | Black scene, amber JARVIS title, menu, real status and settings in the header; centred humanoid; one neon dock with text, mic and send. Code: `lib/jarvis_v3/jarvis_v3_home.dart`, `neon_dock.dart`. |
| Original humanoid | PASS | Uses the original approved render `assets/images/jarvis_male_hologram_gold.png` (Nov 3 commit). Not redrawn and not replaced by a procedural model. |
| Clutter removed | PASS | Six mode buttons, manual state chips, AIRA PREVIEW badge, model gallery and debug labels are gone from the main screen (widget test plus emulator check I17). |
| All six modes | PASS | JARVIS, AIRA, Office, APEX, MIRA, Serpent: compact selector in the menu, a long-press on the title, and Appearance. Voice "switch to apex" still works (test). |
| Neon conversation | PASS | Cyan right-aligned user bubbles, amber left-aligned JARVIS bubbles, icons, wrapping, live transcript while listening. Text colours reach above 12:1 contrast on the bubble fill. |
| Tamil text | PARTIAL | Tamil strings are stored and restored intact (unit test). The screenshots use English and Tanglish because the CI renderer has no Tamil font; the phone renders Tamil with its system font. |
| Conversation history | PASS | Built from real service transitions, kept on the device (Appearance, "Save JARVIS conversation"), full history on a title tap, clear with confirmation. |
| Smart auto-hide | PASS | On by default after 8 s (5/8/15/30). Stays visible while listening, thinking, processing, executing and speaking (setting), and while scrolling, typing, the keyboard is open, history is open or an error is not yet dismissed. Fades in 350 ms; history kept. 9 timer tests. |
| Event-driven animation | PASS | `assistant_activity.dart` derives IDLE, LISTENING, THINKING, PROCESSING, EXECUTING, SPEAKING, ERROR and DISCONNECTED from real signals. LISTENING requires the recogniser to be capturing; EXECUTING requires a running executor task. A generation counter stops a stale timer overriding a newer state. Manual previews: Diagnostics only. |
| Introduction | PASS | Particles, convergence, assembly, ignition, rings, then IDLE. Skip intro, once per launch, off with reduced motion (app setting or system). |
| Intro sound | BLOCKED | No approved intro sound asset in the repository and no audio player dependency. Send the sound and it will be added with a mute control. |
| Serpent Guardian | PARTIAL | Uses the owner-supplied reference render (`assets/images/serpent_guardian.jpg`, received Nov 20) with live eye, core and palm glows, a coiling neon trail, particles and portal rings. Real coiling and uncoiling, head tracking and the serpent-to-humanoid transformation need a rigged or layered model, which does not exist yet. The procedural prototype remains in Diagnostics only. |
| Head, hand and torso motion, lip-sync | PARTIAL | Whole-figure breathing, sway and voice-reactive eyes and core only. Separate head and hand movement and lip-sync need a layered or rigged version of the approved render (face and jaw as separate layers at minimum). Lip-sync is not implemented. |
| Performance | UNVERIFIED | The animation loop stops when the app is backgrounded; frame pacing is logged (`JARVIS_PERF` / `SERPENT_PERF` in logcat); particle density drops when frames run late. FPS and temperature on the iQOO 13 have not been measured. |
| Status label | PASS | The header shows NOT VERIFIED, ONLINE (only after a verified AI request), AI ERROR, AI NOT CONNECTED or the live activity, plus MIC STANDBY when the wake-word recogniser is open. Gemini Live showed "LIVE: DISCONNECTED" when it was simply not set up; it now says "LIVE: NOT SET UP" and moved to the menu. |
| Model display | PASS | The same `modelLabel` appears in Settings, Diagnostics, Control Center and the conversation view (check I15). |

## Security (Full Control)

Removed from the Full Control build (`android/app/src/full/AndroidManifest.xml`), checked in source by
`test/v3_security_test.dart` and in the merged APK by the CI gate:

- `QUERY_ALL_PACKAGES`. Launcher `<queries>` keep opening apps by name.
- Legacy storage, `MANAGE_EXTERNAL_STORAGE`, `REQUEST_INSTALL_PACKAGES`, `REQUEST_DELETE_PACKAGES`, `WRITE_CONTACTS`.
- The Shizuku provider (exported, cross-user) and its permission.
- The notification listener that read SMS and e-mail notification text, OTPs included. **Inbox triage is no longer available in either build.**

Kept, because they are what Full Control is for: the accessibility service (off until the owner turns
it on in Android settings), the floating bubble, `READ_CONTACTS`, usage stats and `WRITE_SETTINGS`.

**Play Protect status: BLOCKED / UNVERIFIED.** The CI gates pass, but only installing on the iQOO 13 can
show whether Play Protect still blocks the build. Two contributing factors remain that this branch cannot
fix by itself:

1. Every APK is signed with the CI debug key. Play Protect treats debug-signed, sideloaded apps with an
   accessibility service as high risk. A private release keystore kept by the owner is the legitimate fix.
2. An accessibility service that can read the screen and perform gestures is itself the main "sensitive
   data" signal. On Android 13 and later, sideloaded apps also meet Restricted Settings for this
   permission, and that is intended.

For these reasons the Full Control APK is **not** attached to the test release.

## Tests

- `flutter analyze`: 0 errors and 0 warnings (infos only, as before).
- `flutter test`: 238 passed, 0 failed (baseline before V3: 207). New: `v3_logic_test.dart` (activity engine, auto-hide, conversation store, header status), `v3_home_test.dart` (layout at 4 sizes, keyboard and nav insets, bubble colours and alignment, end-to-end auto-hide, errors stay until dismissed, single dispatch, every mode renders, intro stages, skip, reduced motion, voice mode switch), `v3_security_test.dart`.
- Emulator acceptance on Android 15 and 16: see the CI run; I16 (Serpent framing) and I17 (clean main screen, dock above the system bars, honest status) are new for V3.

## Screenshots

`docs/v3/`: rendered from the real widgets with the real assets (flutter_tester, 412x915 dp).
`00-reference-vs-v3.jpg` sets the original references beside the new screens. Emulator screenshots
are in the CI artifacts. **Visual sign-off on the phone is still the owner's.** A widget test does not
prove visual fidelity.
