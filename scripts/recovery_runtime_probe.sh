#!/usr/bin/env bash
# Measurements on disposable CI emulators, not physical battery certification.
set -uo pipefail
out="$1"
for pkg in com.greensoil.jarvis.unified.recoverydev com.greensoil.jarvis.unified.full.recoverydev; do
  name="${pkg##*.}"
  [[ "$pkg" == *.full.* ]] && name=full || name=standard
  adb shell dumpsys meminfo "$pkg" > "$out/memory-$name.txt" 2>&1
  adb shell dumpsys gfxinfo "$pkg" > "$out/frames-$name.txt" 2>&1
  adb shell am force-stop "$pkg"
  adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 3
  adb shell pidof "$pkg" > "$out/restart-$name-pid.txt"
  adb exec-out screencap -p > "$out/restart-$name.png"
  # Retain only avatar selection, never credentials or conversation data.
  adb shell run-as "$pkg" cat shared_prefs/FlutterSharedPreferences.xml 2>/dev/null | python3 -c 'import sys,json,xml.etree.ElementTree as E; r=E.parse(sys.stdin); n=r.find(".//string[@name=\"flutter.jarvis_avatar_library_v1\"]"); print(json.dumps({"selected":json.loads(n.text).get("selected")}))' > "$out/restart-$name-avatar.json"
  adb shell dumpsys meminfo "$pkg" > "$out/memory-$name-restarted.txt" 2>&1
  adb shell input keyevent KEYCODE_HOME
  sleep 2
  adb shell dumpsys meminfo "$pkg" > "$out/memory-$name-background.txt" 2>&1
done
adb shell dumpsys battery > "$out/emulator-battery.txt"
