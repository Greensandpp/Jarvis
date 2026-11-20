#!/usr/bin/env bash
# The emulator action invokes each script line through sh. Keep all pipelines
# and failure handling in one explicit Bash process and test BOTH flavors.
set -uo pipefail
OUT=${1:?usage: jarvis_ci_acceptance.sh OUT_DIR}
mkdir -p "$OUT"
failed=0
if ! bash scripts/unified_acceptance.sh "$OUT" apks/JARVIS-UNIFIED-standard-debug.apk apks/JARVIS-UNIFIED-full-debug.apk; then
  printf 'Device acceptance failed\n' > "$OUT/device-failed"
  failed=1
fi
for flavor in standard full; do
  package=com.greensoil.jarvis.unified.visualstaging
  if [[ "$flavor" == full ]]; then package=com.greensoil.jarvis.unified.full.visualstaging; fi
  adb uninstall "$package" || true
  if SHOT_DIR="$OUT" flutter drive --flavor "$flavor" --dart-define="EXPECT_FLAVOR=$flavor" \
      --driver test_driver/integration_test.dart --target integration_test/unified_acceptance_test.dart \
      -d "${ANDROID_SERIAL:-emulator-5554}" 2>&1 | tee "$OUT/drive-$flavor.txt"; then
    printf '%s driver exit=0\n' "$flavor" >> "$OUT/driver-exits.txt"
  else
    printf '%s driver failed\n' "$flavor" >> "$OUT/driver-exits.txt"
    failed=1
  fi
  # An exit-zero driver without the complete in-app acceptance evidence fails.
  for n in {1..13}; do
    printf -v id 'I%02d' "$n"
    if ! grep -qE "ACCEPT $id PASS( |$)" "$OUT/drive-$flavor.txt"; then
      printf '%s missing %s PASS\n' "$flavor" "$id" >> "$OUT/driver-exits.txt"
      failed=1
    fi
  done
  if grep -qE 'ACCEPT I[0-9]+ FAIL|Some tests failed|EXCEPTION CAUGHT' "$OUT/drive-$flavor.txt"; then failed=1; fi
  if ! grep -q 'All tests passed' "$OUT/drive-$flavor.txt"; then failed=1; fi
done
exit "$failed"
