#!/usr/bin/env bash
# The emulator action executes each YAML line with POSIX sh; keep Bash pipeline
# status handling inside this explicit script so failures cannot be hidden.
set -uo pipefail
out="$1"
mkdir -p "$out"
bash scripts/unified_acceptance.sh "$out" apks/JARVIS-UNIFIED-standard-debug.apk apks/JARVIS-UNIFIED-full-debug.apk || echo 'device checks reported failures' > "$out/device-failed"
for flavor in standard full; do
  pkg=com.greensoil.jarvis.unified.recoverydev
  [[ "$flavor" == full ]] && pkg=com.greensoil.jarvis.unified.full.recoverydev
  adb uninstall "$pkg" || true
  SHOT_DIR="$out" flutter drive --flavor "$flavor" --dart-define="EXPECT_FLAVOR=$flavor" --driver test_driver/integration_test.dart --target integration_test/unified_acceptance_test.dart -d emulator-5554 2>&1 | tee "$out/drive-$flavor.txt"
  driver_exit=${PIPESTATUS[0]}
  echo "$driver_exit" > "$out/drive-$flavor.exit"
done
bash scripts/recovery_runtime_probe.sh "$out"
# The always-run summary gate checks every recorded exit and required result.
