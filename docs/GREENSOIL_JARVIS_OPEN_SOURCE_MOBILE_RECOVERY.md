# GreenSoil JARVIS — Open-source research and mobile release gates (2026-11-17)

## Scope and hard boundaries

**Target:** existing Flutter blue-reactor JARVIS with JARVIS Core, Agent Office, APEX and MIRA selectable in one app on iQOO 13 Android 16; Gemini/OpenClaw remains the brain. **Do not replace** current Stable APK signing, app data, OpenClaw cloud production, or any trading system. No paid services or account privilege changes.

## Directly inspected upstream references (architecture concepts only — NO source copied)

1. **Bwarhness/jarvis-assistant** (Apache-2.0): Kotlin/Compose, native assistant gesture, on-device openWakeWord foreground service, separate STT/TTS and agent client. Good model for an isolated Android wake-word module, subject to Android background mic notification and battery behavior. https://github.com/Bwarhness/jarvis-assistant
2. **OpenAppCapabilityProtocol/hark**: Flutter local-on-device capability discovery/Android intent dispatch. Useful example for safe command routing; only supported app capabilities, and owner permission gates. https://github.com/OpenAppCapabilityProtocol/hark
3. **involvex/nova-assistant**: Flutter local-first assistant with on-device speech, screen awareness and model boundary; research only for offline fallback. https://github.com/involvex/nova-assistant
4. **wxxsfxyzm/InstallerX-Revived** (GPL-3.0): installer status and failure categories (`INSTALL_FAILED_*`). Separate diagnostic tool — must not vendor its GPL code into GreenSoil without license review. Authorizer None can request ordinary user-confirmed installs; Shizuku/Root are optional privileged modes and not required by the GreenSoil plan. https://github.com/wxxsfxyzm/InstallerX-Revived ; https://wxxsfxyzm.github.io/InstallerX-Revived-Website/guide/exceptions.html
5. Android official compatibility rules: ZIP alignment and **ELF PT_LOAD alignment** are separate checks, and neither proves OEM installer acceptance. https://developer.android.com/guide/practices/page-sizes
6. Android `PackageInstaller` exposes failure reason classes (blocked, conflict, invalid, incompatible, storage). No specific one is established for this physical device yet. https://developer.android.com/reference/android/content/pm/PackageInstaller

## Evidence already collected from our original build

- Android 16 x86_64 emulator fresh install PASS for distinct debug/release package IDs.
- ARM64 library presence PASS; 16KB ZIP alignment PASS; four ARM64 libraries 16KB ELF PT_LOAD alignment PASS.
- Real iQOO 13 installs of debug + release test APK consistently reported generic `App not installed` despite extracting ZIP; phone-originated exact installer status **UNVERIFIED**.
- User declined Termux/ADB debugging. Do not request or assume it.
- Earlier build's `android:label` says `GreenSoil JARVIS Tamil Test`; this is an app display label, not proof of a matching package ID.

## New isolated mobile compatibility experiment

`scripts/make_safe_mobile_staging.py` creates a worktree-only release variant with a unique `com.greensoil.jarvis.tamiltest.visualsafe` application ID, a minimal app manifest and reduced sensitive components/permissions. GitHub CI must validate package identity, signing and install on a fresh Android 16 emulator and publish a *clearly labelled diagnostic* artifact.

**It is NOT a full working JARVIS release:** phone capabilities like microphone, overlays, contacts, accessibility and Shizuku may be unavailable. Visuals and network connectivity can be checked separately. Treat APK download as optional until CI PASS. Do not ask the user to uninstall the existing app or disable Play Protect/verification.

## Safe progression (gates)

1. CI build + analyzer + tests PASS on the consolidated branch, ARM64 ELF and package signature verify, Android 16 clean install.
2. Non-ADB diagnostic option: InstallerX Revived in **authorizer None** mode can report install errors after normal user confirmation; use only official stable binaries, no root/Shizuku/verification-bypass toggle. A user may decline this.
3. Minimal-permission visual staging physical install test (PASS/FAIL with screenshot and exact installer reason if available).
4. If PASS: isolate which extra manifest component/permission causes OEM rejection via gradual additive test builds; keep safe mode default until resolved.
5. If FAIL: focus on firmware installer policy, package state, APK integrity/delivery, ABI and the on-device reason; do not churn code.
6. Only then: physical smoke for 4 modes, Tamil/Tanglish STT and voice, task approvals, app switching, battery/network/offline behavior.
7. Integrate features from open-source examples as **separate permission-scoped modules** with license review, regression tests and user-controlled activation. Never reuse third-party credentials or server URLs.

## Feature integration order

- **First:** native four-mode selector and stable blue JARVIS Core (currently staged). Avoid loading live APEX/MIRA sites with user chat or credentials.
- **Second:** native command router + user approvals. Green: read/draft; Yellow: local worktree edits; Red: send/payment/delete/trading side effects — explicit confirmation, no hidden actions.
- **Third:** local-first language pipeline for Tamil/English/Tanglish and optional wake word with a visible microphone state.
- **Fourth:** Agent Office backed by actual audited task events; display *NOT CONNECTED* until specialist agents exist. No fake metrics, no fake 24/7.
- **Fifth:** offline cached HUD and model-specific visuals, mobile touch performance, mode persistence and one shared AI memory contract.
- **Sixth:** real device signed update only after signature compatibility and full physical-device QA.

This document is an evidence/engineering plan, not a claim that features or phone installation are complete.
