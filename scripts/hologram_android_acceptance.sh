#!/usr/bin/env bash
set -euo pipefail
mkdir -p evidence/android
adb wait-for-device
adb shell getprop ro.build.version.sdk > evidence/android/sdk.txt
for flavor in standard full; do
  adb logcat -c
  mkdir -p "evidence/android/$flavor"
  SHOT_DIR="evidence/android/$flavor" flutter drive --keep-app-running --flavor "$flavor" --driver test_driver/integration_test.dart --target integration_test/holographic_acceptance_test.dart -d emulator-5554 2>&1 | tee "evidence/android/$flavor-drive.txt"
  package=com.greensoil.jarvis.unified.visualstaging
  if [ "$flavor" = full ]; then package=com.greensoil.jarvis.unified.full.visualstaging; fi
  # Install and launch the exact production-entrypoint APK being delivered,
  # after the integration test has exercised the underlying app services.
  adb shell am force-stop "$package"
  adb install -r "private-apks/JARVIS-$flavor-debug.apk" | tee "evidence/android/$flavor-install.txt"
  grep -q Success "evidence/android/$flavor-install.txt"
  adb shell am force-stop "$package"
  adb shell am start -W -n "$package/com.privateagent.private_agent.MainActivity" | tee "evidence/android/$flavor-launch.txt"
  grep -q 'Status: ok' "evidence/android/$flavor-launch.txt"
  app_pid=$(adb shell pidof "$package" | tr -d '\r')
  test -n "$app_pid"
  renderer_ready=false
  for attempt in $(seq 1 45); do
    adb logcat -d --pid="$app_pid" > "evidence/android/$flavor-production-logcat.txt"
    if python3 scripts/check_production_renderer.py "evidence/android/$flavor-production-logcat.txt" "evidence/android/$flavor-production-renderer.json" mira; then
      renderer_ready=true
      break
    fi
    sleep 1
  done
  if [ "$renderer_ready" != true ]; then
    adb exec-out screencap -p > "evidence/android/$flavor-production-renderer-failed.png"
    echo "Production APK did not render/persist its selected theme" >&2
    exit 1
  fi
  adb exec-out screencap -p > "evidence/android/$flavor-production-apk.png"
  adb shell uiautomator dump /sdcard/jarvis-window.xml >/dev/null
  adb shell cat /sdcard/jarvis-window.xml > "evidence/android/$flavor-window.xml"
  grep -q 'JARVIS' "evidence/android/$flavor-window.xml"
  grep -q 'Message JARVIS' "evidence/android/$flavor-window.xml"
  ! grep -E 'Private Agent|Phone Agent|Skip intro' "evidence/android/$flavor-window.xml"
  adb logcat -d --pid="$app_pid" > "evidence/android/$flavor-production-logcat.txt"
  ! grep -E 'FATAL EXCEPTION|Fatal signal|Abort message:' "evidence/android/$flavor-production-logcat.txt"
  adb shell dumpsys meminfo "$package" > "evidence/android/$flavor-meminfo.txt"
  adb shell dumpsys gfxinfo "$package" > "evidence/android/$flavor-gfxinfo.txt"
  adb shell dumpsys batterystats "$package" > "evidence/android/$flavor-batterystats.txt"
  adb logcat -d > "evidence/android/$flavor-logcat.txt"
  grep -q 'NATIVE_AUDIO_CANCEL PASS' "evidence/android/$flavor-drive.txt"
  grep -q 'HOLOGRAM_ACCEPT PASS' "evidence/android/$flavor-drive.txt"
  # These are disposable CI packages. Release their WebView/GPU processes
  # before the next independent variant; retain data for restart checks.
  adb shell am force-stop "$package"
done
