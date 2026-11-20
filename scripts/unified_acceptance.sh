#!/usr/bin/env bash
# Unified JARVIS acceptance on a CI emulator (never the owner's phone).
# Usage: unified_acceptance.sh OUT_DIR STANDARD_APK FULL_APK
# Device-level checks only (install, permissions, launch, modes, background).
# Prints "Uxx PASS|FAIL|UNVERIFIED <detail>" lines into OUT/summary.txt.
set -uo pipefail
OUT="$1"; STD_APK="$2"; FULL_APK="$3"
mkdir -p "$OUT"
STD=com.greensoil.jarvis.unified.recoverydev
FULL=com.greensoil.jarvis.unified.full.recoverydev
UI="python3 $(dirname "$0")/ui.py"
fails=0; n=0
log() { echo "$*" | tee -a "$OUT/summary.txt"; }
res() { local id="$1" st="$2"; shift 2; log "$id $st $*"; [[ $st == FAIL ]] && fails=$((fails+1)); return 0; }
shot() { adb exec-out screencap -p > "$OUT/$1.png"; }
dump() { adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1; adb pull /sdcard/ui.xml "$OUT/ui-$1.xml" > /dev/null 2>&1; echo "$OUT/ui-$1.xml"; }
crashed() { adb logcat -d | grep -E "FATAL EXCEPTION" -A3 | grep -q "$1"; }
hide_kb() { adb shell dumpsys input_method | grep -q "mInputShown=true" && adb shell input keyevent KEYCODE_BACK; sleep 1; }
# Tap the first node containing $2, scrolling down up to 5 times. $1 = tag.
tap_text() {
  local tag="$1" text="$2" i f xy
  for i in 0 1 2 3 4 5; do
    f=$(dump "$tag-$i"); xy=$($UI "$f" find "$text") && { adb shell input tap $xy; sleep 2; return 0; }
    adb shell input swipe 540 1700 540 700 400; sleep 1
  done
  return 1
}
wait_text() { # tag text timeout_s
  local t=0 f
  while (( t < $3 )); do f=$(dump "$1"); $UI "$f" has "$2" && return 0; sleep 3; t=$((t+3)); done
  return 1
}
seed() { # pkg mode model extra-xml
  adb shell am force-stop "$1"
  adb shell "run-as $1 sh -c 'mkdir -p shared_prefs && cat > shared_prefs/FlutterSharedPreferences.xml'" <<XML
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
  <boolean name="flutter.onboarding_complete" value="true" />
  <string name="flutter.ui_app_mode">jarvis</string>
  <string name="flutter.jarvis_visual_mode_v1">$2</string>
  <string name="flutter.aira_model_v1">${3:-neuralReactor}</string>
  <string name="flutter.aira_quality_v1">balanced</string>
  ${4:-}
</map>
XML
}
launch() { adb logcat -c; adb shell monkey -p "$1" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1; sleep "${2:-16}"; }

adb wait-for-device
log "device android=$(adb shell getprop ro.build.version.release | tr -d '\r') sdk=$(adb shell getprop ro.build.version.sdk | tr -d '\r')"

# U01 both builds install side by side (distinct application IDs)
adb install -r -t "$STD_APK" > "$OUT/install-std.txt" 2>&1; a=$?
adb install -r -t "$FULL_APK" > "$OUT/install-full.txt" 2>&1; b=$?
if [[ $a == 0 && $b == 0 ]] && adb shell pm list packages | grep -q "$STD" && adb shell pm list packages | grep -q "$FULL"; then
  res U01 PASS "standard ($STD) and full ($FULL) installed side by side"
else res U01 FAIL "install std=$a full=$b"; cat "$OUT"/install-*.txt; fi
adb shell pm grant $STD android.permission.RECORD_AUDIO || true
adb shell pm grant $STD android.permission.POST_NOTIFICATIONS || true
adb shell pm grant $FULL android.permission.POST_NOTIFICATIONS || true

# U02 runtime permission inventory of the standard build
adb shell dumpsys package $STD | grep -E "android.permission|granted=" > "$OUT/perms-standard.txt"
if grep -qE "SYSTEM_ALERT_WINDOW|QUERY_ALL_PACKAGES|READ_CONTACTS|WRITE_SETTINGS|PACKAGE_USAGE_STATS|BIND_ACCESSIBILITY|shizuku" "$OUT/perms-standard.txt"; then
  res U02 FAIL "high-risk permission present in standard build"
else res U02 PASS "standard build has no accessibility/overlay/contacts/all-packages/usage/settings/Shizuku permissions"; fi
adb shell dumpsys package $STD | grep -iE "AccessibilityService|OverlayService" > "$OUT/components-standard.txt" || true
[[ -s "$OUT/components-standard.txt" ]] && res U02b FAIL "accessibility/overlay component registered" || res U02b PASS "no accessibility/overlay service registered"

# U03 the original five visual modes still render in the unified build
ok=1
for mode in core aira office apex mira; do
  seed $STD $mode; launch $STD 16
  shot "mode-$mode-a"; sleep 2; shot "mode-$mode-b"
  if crashed $STD || [[ -z "$(adb shell pidof $STD | tr -d '\r')" ]]; then ok=0; log "  mode $mode crashed"; fi
done
[[ $ok == 1 ]] && res U03 PASS "core/aira/office/apex/mira launched; 2 frames each (see mode-*.png)" || res U03 FAIL "a mode crashed"

# U04 AIRA models
ok=1
for model in amberHologram electricWeb jellyfish violetVortex solarFlare; do
  seed $STD aira $model; launch $STD 13; shot "aira-$model"; crashed $STD && ok=0
done
[[ $ok == 1 ]] && res U04 PASS "5 AIRA models rendered (aira-*.png)" || res U04 FAIL "AIRA model crash"

# U05–U12 (THINKING guard, Settings, diagnostics, Trading AI, full-build label)
# run inside the app via integration_test/unified_acceptance_test.dart
# (uiautomator cannot reach idle on the continuously animated HUD).

# U13 background
adb shell input keyevent KEYCODE_HOME; sleep 4
crashed $STD || crashed $FULL && res U13 FAIL "crash after HOME" || res U13 PASS "no crash after HOME"

res U14 UNVERIFIED "live Gemini answer: no API key in CI (owner enters it on the phone)"
res U15 UNVERIFIED "voice recognition quality / Tamil female voice: emulator has no real microphone or iQOO voices"
res U16 UNVERIFIED "accessibility automation, overlay, contacts in full build: need owner grants on a real device"
log "OVERALL $([[ $fails == 0 ]] && echo PASS || echo "FAIL ($fails)")"
exit $fails
