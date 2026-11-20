#!/usr/bin/env bash
# Unified JARVIS acceptance on a CI emulator (never the owner's phone).
# Usage: unified_acceptance.sh OUT_DIR STANDARD_APK FULL_APK
# Prints "Uxx PASS|FAIL|UNVERIFIED <detail>" lines into OUT/summary.txt.
set -uo pipefail
OUT="$1"; STD_APK="$2"; FULL_APK="$3"
mkdir -p "$OUT"
STD=com.greensoil.jarvis.unified.visualstaging
FULL=com.greensoil.jarvis.unified.full.visualstaging
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

# U05 THINKING guard: command with no key must not leave JARVIS stuck in THINKING
seed $STD aira; launch $STD 16
f=$(dump dock); xy=$($UI "$f" find "Ask JARVIS") || xy=$($UI "$f" edits | head -1)
if [[ -n "$xy" ]]; then
  adb shell input tap $xy; sleep 1
  adb shell input text "what%sis%sthe%scapital%sof%sfrance"; sleep 1
  hide_kb
  f=$(dump dock2); sx=$($UI "$f" find "Send to native JARVIS")
  [[ -n "$sx" ]] && adb shell input tap $sx || adb shell input keyevent KEYCODE_ENTER
  t0=$(date +%s); sleep 3; shot "thinking-during"
  stuck=1
  for i in $(seq 1 45); do
    f=$(dump "phase-$i")
    if ! $UI "$f" has "JARVIS · THINKING" && ! $UI "$f" has "JARVIS · EXECUTING"; then stuck=0; break; fi
    sleep 3
  done
  dt=$(( $(date +%s) - t0 )); shot "thinking-after"; $UI "$f" texts > "$OUT/thinking-after-texts.txt"
  if [[ $stuck == 0 ]]; then res U05 PASS "left THINKING after ${dt}s; phase/status: $(grep -E 'JARVIS ·|AI ERROR|NOT CONNECTED|key' "$OUT/thinking-after-texts.txt" | head -3 | tr '\n' ' ')"
  else res U05 FAIL "still THINKING after ${dt}s"; fi
else res U05 FAIL "dock input not found"; fi
crashed $STD && res U05b FAIL "crash during command" || res U05b PASS "no crash during command"

# U06 Settings shows build type + honest AI status
seed $STD aira; launch $STD 16
f=$(dump home); xy=$($UI "$f" find "Settings")
if [[ -n "$xy" ]]; then
  adb shell input tap $xy; sleep 3; shot settings-top
  if tap_text settings-build "STANDARD BUILD" >/dev/null 2>&1 || wait_text settings-b "STANDARD BUILD" 3; then
    shot settings-build
    res U06 PASS "Settings shows STANDARD BUILD + notice"
  else res U06 FAIL "build label not found"; fi
  f=$(dump settings-ai)
  if $UI "$f" has "AI NOT CONNECTED" || $UI "$f" has "AI NOT VERIFIED" || $UI "$f" has "AI ERROR"; then
    res U07 PASS "AI status is not falsely ONLINE: $($UI "$f" texts | grep -E '^AI ' | head -1)"
  elif $UI "$f" has "AI ONLINE"; then res U07 FAIL "shows ONLINE without a verified request"
  else res U07 UNVERIFIED "status text not visible"; fi
  # U08 diagnostics
  if tap_text diag-open "Test connection & discover models"; then
    sleep 2; tap_text diag-run "Test connection & discover models" || true
    wait_text diag-res "DNS" 60; sleep 8; f=$(dump diag-final); shot diagnostics
    $UI "$f" texts > "$OUT/diagnostics-texts.txt"
    if $UI "$f" has "DNS"; then res U08 PASS "diagnostics ran: $(grep -iE 'DNS|HTTPS|key|Generate' "$OUT/diagnostics-texts.txt" | head -4 | tr '\n' ' ')"
    else res U08 FAIL "no diagnostic steps shown"; fi
    adb shell input keyevent KEYCODE_BACK; sleep 2
  else res U08 FAIL "diagnostics button not found"; fi
else res U06 FAIL "Settings button not found"; fi

# U09/U10 Trading AI risk gate + journal audit (journal seeded through prefs)
J='Date,Entry Time,Exit Time,Symbol,Side,Entry,Exit,SL,Qty,PnL,Fees,Confidence&#10;2026-11-17,09:20,09:40,NIFTY,LONG,100,110,90,75,710,40,80&#10;2026-11-17,10:00,10:30,NIFTY,LONG,120,100,100,75,-1540,40,65'
seed $STD aira neuralReactor "<string name=\"flutter.trading_journal_csv_v1\">$J</string>"
launch $STD 16
f=$(dump home2); xy=$($UI "$f" find "Settings"); adb shell input tap $xy; sleep 3
if tap_text trade-open "Trading AI (paper only)"; then
  sleep 2; f=$(dump trade); mapfile -t E < <($UI "$f" edits)
  vals=(120 110 78 10:15); for i in 0 1 2 3; do
    [[ -n "${E[$i]:-}" ]] && { adb shell input tap ${E[$i]}; sleep 1; adb shell input text "${vals[$i]}"; sleep 1; }
  done
  hide_kb
  tap_text trade-check "Check against GreenSoil rules" || true
  sleep 2; f=$(dump trade-res); shot trading-gate; $UI "$f" texts > "$OUT/trading-texts.txt"
  if grep -q "TRADE (PAPER)" "$OUT/trading-texts.txt" && grep -q "TP1" "$OUT/trading-texts.txt"; then
    res U09 PASS "valid setup → TRADE (PAPER) with sizing and TP ladder"
  elif grep -q "NO TRADE" "$OUT/trading-texts.txt"; then res U09 FAIL "valid setup blocked: $(grep '✗' "$OUT/trading-texts.txt" | head -2 | tr '\n' ' ')"
  else res U09 FAIL "no gate result"; fi
  tap_text trade-audit "Find errors in my journal" || true
  sleep 2; f=$(dump audit); shot trading-audit; $UI "$f" texts > "$OUT/audit-texts.txt"
  if grep -qiE "before 09:30|< 70%|does not match" "$OUT/audit-texts.txt"; then res U10 PASS "journal audit flagged rule violations on device"
  else res U10 FAIL "audit report missing"; fi
else res U09 FAIL "Trading AI button not found"; res U10 FAIL "not reached"; fi
crashed $STD && res U11 FAIL "standard build crashed during tests" || res U11 PASS "no crash in standard build"

# U12 full build launches and identifies itself
seed $FULL aira; launch $FULL 16
f=$(dump full-home); shot full-home
if crashed $FULL || [[ -z "$(adb shell pidof $FULL | tr -d '\r')" ]]; then res U12 FAIL "full build crashed"
else
  xy=$($UI "$f" find "Settings"); [[ -n "$xy" ]] && adb shell input tap $xy; sleep 3
  if tap_text full-build "FULL CONTROL BUILD" > /dev/null 2>&1 || wait_text full-b "FULL CONTROL BUILD" 3; then
    shot full-settings; res U12 PASS "full build runs; Settings shows FULL CONTROL BUILD"
  else res U12 FAIL "full build label not found"; fi
fi
$UI "$(dump full-home2)" has "Show floating bubble" && log "  (full build exposes floating bubble button)"

# U13 background
adb shell input keyevent KEYCODE_HOME; sleep 4
crashed $STD || crashed $FULL && res U13 FAIL "crash after HOME" || res U13 PASS "no crash after HOME"

res U14 UNVERIFIED "live Gemini answer: no API key in CI (owner enters it on the phone)"
res U15 UNVERIFIED "voice recognition quality / Tamil female voice: emulator has no real microphone or iQOO voices"
res U16 UNVERIFIED "accessibility automation, overlay, contacts in full build: need owner grants on a real device"
log "OVERALL $([[ $fails == 0 ]] && echo PASS || echo "FAIL ($fails)")"
exit $fails
