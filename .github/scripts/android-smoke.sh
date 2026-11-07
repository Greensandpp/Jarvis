#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE="com.greensoil.jarvis.standalone"
APK="build/app/outputs/flutter-apk/app-debug.apk"

cleanup() {
  adb shell dumpsys activity activities > activity.txt 2>/dev/null || true
  adb logcat -d -v time > logcat.txt 2>/dev/null || true
  adb exec-out screencap -p > screenshot.png 2>/dev/null || true
  adb shell pidof "$PACKAGE" > app-pid.txt 2>/dev/null || true
}
trap cleanup EXIT

test -s "$APK" || { echo "::error::APK missing"; exit 1; }
adb wait-for-device
installed=0
for attempt in 1 2 3 4; do
  echo "Checking package manager, attempt $attempt"
  if adb shell pm path android >/dev/null 2>&1 && adb install --no-streaming -r "$APK"; then
    installed=1
    break
  fi
  echo "ADB/package manager not ready"
  adb reconnect || true
  sleep 15
done
if [[ "$installed" != 1 ]]; then
  echo "::error::APK failed to install after four attempts"
  exit 1
fi

adb shell pm path "$PACKAGE"
adb logcat -c || true
adb shell monkey -p "$PACKAGE" 1
sleep 15
app_pid="$(adb shell pidof "$PACKAGE" | tr -d '\r' || true)"
if [[ -z "$app_pid" ]]; then
  echo "::error::Jarvis app process is not running after launch"
  exit 1
fi
echo "Jarvis running as PID: $app_pid"
adb logcat -d -v time > logcat.txt || true
if grep -F "Process: $PACKAGE," logcat.txt; then
  echo "::error::Jarvis application-specific AndroidRuntime crash"
  exit 1
fi
echo "Android smoke passed: installed, launched, process alive, no app-specific fatal exception"
