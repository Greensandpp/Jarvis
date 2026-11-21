"""Verify real main-entrypoint APK renderer logs after an in-place test update.
No app data or secrets are read: the debug bridge reports bounded scene metrics.
Exit 1 means not ready yet (the caller has a bounded wait); no success is inferred.
"""
import json
import pathlib
import sys

source, target, expected_theme = sys.argv[1:]
records = []
for line in pathlib.Path(source).read_text(errors='replace').splitlines():
    if 'HOLOGRAM_RENDERER_METRICS ' not in line:
        continue
    try:
        record = json.loads(line.split('HOLOGRAM_RENDERER_METRICS ', 1)[1])
    except (ValueError, TypeError):
        continue
    if isinstance(record, dict):
        records.append(record)
ready = [r for r in records if r.get('intro') == 'done' and r.get('theme') == expected_theme
         and r.get('engine') == 'Three.js r180 WebGL' and not r.get('contextLost')]
if len(ready) < 2:
    raise SystemExit(1)
a, b = ready[-2:]
if not (b.get('frame', 0) > a.get('frame', 0)
        and a.get('humanoidHead') != b.get('humanoidHead')
        and a.get('snakeHead') != b.get('snakeHead')
        and b.get('bones', 0) >= 36 and b.get('snakeBones') == 32
        and b.get('triangles', 0) > 1000):
    raise SystemExit(1)
bounds = b.get('snakeHeadBounds', {})
if not (all(-1 < v < 1 for v in bounds.get('min', []))
        and all(-1 < v < 1 for v in bounds.get('max', []))
        and len(bounds.get('min', [])) == 2 and len(bounds.get('max', [])) == 2):
    raise SystemExit(1)
pathlib.Path(target).write_text(json.dumps({'status': 'PASS', 'scope': 'Exact development APK main entrypoint / Android 16 emulator',
    'persistedTheme': expected_theme, 'before': a, 'after': b}, indent=2))
print('PRODUCTION_RENDERER PASS actual frames, independent moving joints, full head bounds, intro done, persisted theme', expected_theme)
