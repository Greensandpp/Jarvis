#!/usr/bin/env bash
set -euo pipefail
mkdir -p evidence/android
adb wait-for-device
adb shell getprop ro.build.version.sdk > evidence/android/sdk.txt
for flavor in standard full; do
  adb logcat -c
  SHOT_DIR=evidence/android flutter drive --flavor "$flavor" --driver test_driver/integration_test.dart --target integration_test/holographic_acceptance_test.dart -d emulator-5554 2>&1 | tee "evidence/android/$flavor-drive.txt"
  adb logcat -d > "evidence/android/$flavor-logcat.txt"
  grep -q 'HOLOGRAM_ACCEPT PASS' "evidence/android/$flavor-drive.txt"
done
