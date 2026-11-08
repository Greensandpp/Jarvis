# GreenSoil JARVIS V2 — Android 16 installation diagnosis

## Current grounded status (2026-11-08)
- Working original GreenSoil JARVIS V1 is installed. Keep it and its data; do not uninstall.
- V2 builds are side-by-side test package `com.greensoil.jarvis.tamiltest`, not V1 `com.greensoil.jarvis.custom`.
- Previous diagnostics on an older V2 APK verified v2 APK signature (true), minSdk=26, targetSdk=36; emulator never reached `adb install` because the runner's animation-settings command failed with ADB Broken pipe.
- Owner's Android 16 phone returns the generic package-installer message "App not installed"; precise `INSTALL_FAILED_*` code has **not** been captured.
- Previous builds use GitHub runner-generated Android debug keystores. Signer may differ between runs. Reinstall/update of the *same* package signed with a different certificate can fail; never present this as the proven cause without device-side logs.

## Safe phone-first diagnostic
1. Confirm downloaded file is the exact `app-debug.apk` inside the correct GitHub Actions artifact, extracted from ZIP. The ZIP itself cannot be installed.
2. Verify Android system Settings > Apps for package `com.greensoil.jarvis.tamiltest` / GreenSoil JARVIS Tamil Test, including cloned/work profile apps; don't remove the working `com.greensoil.jarvis.custom`.
3. Use Android's standard Package Installer or a reputable APK installer that shows the **full install failure code**. Capture the error text; do not disable Play Protect or Android security restrictions to force installation.
4. With trusted ADB access, `adb install -t path/to/app-debug.apk` yields the exact `Failure [INSTALL_FAILED_*]` message. Android 16 on-phone local ADB may also produce this output if enabled.
5. Use the error code to distinguish UPDATE_INCOMPATIBLE/signature collision, VERSION_DOWNGRADE, NO_MATCHING_ABIS, INVALID_APK, insufficient storage, policy block or other causes. Avoid guessing.

## New CI verification workflow
`.github/workflows/greensoil-install-diagnostics.yml` now builds from *the exact current branch head*, runs Flutter analyze/tests, checks package ID, APK signature, 16KB zip alignment, SHA256, and separately attempts an Android 11 clean install. Android 11 install success would not by itself confirm Android 16 install success; emulator failures do not imply device-side APK corruption.

## Production signing strategy
A reproducible signer/key must be maintained securely in private build infrastructure or encrypted GitHub Actions secrets. Never upload an unencrypted keystore, API key, token or password into the public repository, screenshots or chat. Only distribute a new installable package when it has a verified identity and an update/rollback plan. If existing V2 package is signed with a different key, first back up any V2 app-only data before considering removal; working V1 need not be affected because package IDs differ.

## Release acceptance
Final exact SHA built, tests pass, APK signature checks, 16KB alignment, real Android 16 installation succeeds, privacy and Accessibility safe-mode tests pass; only then identify a candidate as the final APK.
