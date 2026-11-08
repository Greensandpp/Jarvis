# GreenSoil JARVIS V2 — Privacy & Installation Status

## Non-negotiable owner requirement
No phone content, contacts, private messages, screenshots, files, credentials or device telemetry should be transmitted to unauthorized destinations. Default must be deny. External providers require separate explicit permission, and the user must know the classes of data sent.

## Changes implemented on isolated feature branch (not installed or production)
- Cloud AI HTTP chat and streaming require explicit allowCloudAi; localhost/127.0.0.1 remain allowed, but running an AI model locally is NOT bundled.
- Online Edge/Bing neural TTS requires separate allowCloudTts; local Android TTS fallback.
- Web/news/weather/commute geocoding/routing/airspace requests require allowExternalLookups.
- Home Assistant network traffic requires allowSmartHomeNetwork.
- Telegram remote bridge polling and outbound send require enabled toggle plus explicitly allowed numeric chat IDs.
- Android automatic cloud backup of app data disabled (allowBackup=false); manual secure backup is separate.
- First-launch always-on listening defaults off and speech recognizer retries paced.
- SMS permission UI mismatch corrected, macro recorder cannot claim success on method-channel failure.
- New permission controls exposed in settings. These are app-level guardrails, NOT a proven global network firewall.

## P0 unresolved and must not be described as verified
1. APK installation on the owner's Android 16 phone fails with generic "App not installed". Need exact PackageInstaller / SAI / adb install error. Storage is sufficient; isolated app ID is com.greensoil.jarvis.tamiltest. Do not uninstall working V1.
2. Android emulator CI diagnostics were inconclusive due to emulator boot/ADB stability, not a proven APK install failure.
3. Secrets (AI API keys, Telegram token, Home Assistant token) currently use SharedPreferences. Migrate with verified Android Keystore encrypted storage and safe existing-user migration. Never print keys in logs.
4. Built-in Android SpeechRecognizer may invoke Google or OEM speech services; fully offline speech requires verified on-device recognizer and no cloud fallback. Current microphone sessions cannot be certified offline.
5. Even with AI opt-in controls, other network APIs, plugins, WebViews, native channels, Android backups/telemetry, and dependencies require comprehensive inventory and real traffic inspection.
6. Current manifest permits cleartext traffic; audit all outbound destinations and enforce HTTPS or explicitly approved loopback/LAN access without breaking local model support.
7. Banking/UPI/OTP/secure screens must disable screen capture, overlays and automation rather than circumvent protections.
8. No actual Android 16 runtime testing of mic beep, Tamil/Tanglish, wake words, or network egress yet.
9. GitHub Actions for latest privacy commits have not produced a confirmed passing run. Build/test verification is required before release.
10. Existing JARVIS app and separate AIRA production must remain untouched.

## Verification gates before one consolidated release
- Flutter analyze, unit tests and Android APK build for exact final SHA
- APK package, signing, ABI, minSdk and installer diagnostic for Android 16
- Live device permission safety and no secret exposure in logs
- Test deny-by-default with DNS/network capture: AI, TTS, web, maps, radar, home, Telegram
- Explicit opt-in tests for every outbound destination, plus local/offline fallback
- Native STT cloud-leak assessment; avoid claiming 100% offline without proof
- Safe update and rollback, preserving working V1, signed release strategy, no unsafe uninstall

Prepared as a factual engineering handover; not a security certification.
