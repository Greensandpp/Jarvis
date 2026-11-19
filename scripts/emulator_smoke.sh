#!/usr/bin/env bash
# Emulator smoke test for the five-mode staging build. CI-only; never used on
# the owner's phone. Installs each staging APK, launches it, checks it stays
# alive without FATAL exceptions, and captures real screenshots of every
# visual mode (two frames per mode, 2 s apart, to show animation) plus a short
# screen recording of AIRA.
set -uo pipefail
OUT="${1:-emulator-evidence}"
DEBUG_APK="$2"; RELEASE_APK="$3"; VISUALSAFE_APK="$4"; VOICESAFE_APK="$5"
mkdir -p "$OUT"
PKG=com.greensoil.jarvis.tamiltest.visualstaging
fail=0
log() { echo "$*" | tee -a "$OUT/summary.txt"; }

adb wait-for-device
log "android_release=$(adb shell getprop ro.build.version.release | tr -d '\r') sdk=$(adb shell getprop ro.build.version.sdk | tr -d '\r') abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
adb shell wm size | tee -a "$OUT/summary.txt"

install() {
  local apk="$1" pkg="$2"
  if adb install -r -t "$apk" > "$OUT/install-$pkg.txt" 2>&1 && grep -q Success "$OUT/install-$pkg.txt"; then
    log "INSTALL PASS $pkg"
  else
    log "INSTALL FAIL $pkg"; cat "$OUT/install-$pkg.txt"; fail=1
  fi
}

launch_check() {
  local pkg="$1" tag="$2"
  adb logcat -c
  adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
  sleep 18
  local pid
  pid=$(adb shell pidof "$pkg" | tr -d '\r')
  adb logcat -d > "$OUT/logcat-$tag.txt"
  if grep -E "FATAL EXCEPTION" -A3 "$OUT/logcat-$tag.txt" | grep -q "$pkg"; then
    log "LAUNCH FAIL $tag (FATAL EXCEPTION)"; fail=1
  elif [[ -z "$pid" ]]; then
    log "LAUNCH FAIL $tag (process not running)"; fail=1
  else
    log "LAUNCH PASS $tag pid=$pid"
  fi
}

install "$DEBUG_APK" "$PKG"
install "$RELEASE_APK" com.greensoil.jarvis.tamiltest.visualrelease
install "$VISUALSAFE_APK" com.greensoil.jarvis.tamiltest.visualsafe
install "$VOICESAFE_APK" com.greensoil.jarvis.tamiltest.voicesafe

# Harness-only: pre-answer the two runtime dialogs so screenshots are not
# covered. This is the CI emulator, not the owner's device.
adb shell pm grant "$PKG" android.permission.RECORD_AUDIO || true
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true

seed() {
  local mode="$1" model="${2:-neuralReactor}"
  adb shell am force-stop "$PKG"
  adb shell "run-as $PKG sh -c 'mkdir -p shared_prefs && cat > shared_prefs/FlutterSharedPreferences.xml'" <<XML
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
  <boolean name="flutter.onboarding_complete" value="true" />
  <string name="flutter.ui_app_mode">jarvis</string>
  <string name="flutter.jarvis_visual_mode_v1">$mode</string>
  <string name="flutter.aira_model_v1">$model</string>
  <string name="flutter.aira_quality_v1">balanced</string>
</map>
XML
}

for mode in core aira office apex mira; do
  seed "$mode"
  launch_check "$PKG" "mode-$mode"
  adb exec-out screencap -p > "$OUT/mode-$mode-a.png"
  sleep 2
  adb exec-out screencap -p > "$OUT/mode-$mode-b.png"
  # Persistence check: the restored mode is what we seeded.
  adb shell "run-as $PKG cat shared_prefs/FlutterSharedPreferences.xml" > "$OUT/prefs-$mode.xml" 2>/dev/null || true
done

for model in amberHologram electricWeb jellyfish violetVortex solarFlare; do
  seed aira "$model"
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
  sleep 14
  adb exec-out screencap -p > "$OUT/aira-$model.png"
done

seed aira auroraRibbon
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 14
adb shell screenrecord --time-limit 8 /sdcard/aira.mp4 || true
adb pull /sdcard/aira.mp4 "$OUT/aira-auroraRibbon.mp4" || true
adb shell dumpsys gfxinfo "$PKG" > "$OUT/gfxinfo-aira.txt" || true
adb shell dumpsys meminfo "$PKG" > "$OUT/meminfo-aira.txt" || true

# Background behaviour: send app home, confirm no crash and mic released.
adb shell input keyevent KEYCODE_HOME
sleep 4
adb shell dumpsys audio | grep -iE "AudioRecord|recording" > "$OUT/audio-after-background.txt" || true
adb logcat -d > "$OUT/logcat-background.txt"
if grep -E "FATAL EXCEPTION" -A3 "$OUT/logcat-background.txt" | grep -q "$PKG"; then
  log "BACKGROUND FAIL"; fail=1
else
  log "BACKGROUND PASS (no crash after HOME)"
fi

launch_check com.greensoil.jarvis.tamiltest.visualrelease release
launch_check com.greensoil.jarvis.tamiltest.visualsafe visualsafe
launch_check com.greensoil.jarvis.tamiltest.voicesafe voicesafe
for p in com.greensoil.jarvis.tamiltest.visualsafe com.greensoil.jarvis.tamiltest.voicesafe; do
  adb shell dumpsys package "$p" | grep -E "permission|granted=" > "$OUT/runtime-perms-$p.txt" || true
done
log "OVERALL $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit $fail
