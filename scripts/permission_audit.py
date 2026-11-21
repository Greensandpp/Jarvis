#!/usr/bin/env python3
"""Permission + Play Protect risk audit from real `aapt dump` output.

Usage: permission_audit.py EVIDENCE_DIR OUT_MD
Reads <apk>-permissions.txt / -badging.txt written by the CI build step and the
merged manifest facts it can see there. It reports; it never changes or
bypasses any device security setting.
"""
import glob
import os
import re
import sys

# permission -> (protection level, why JARVIS has it, Play Protect / install risk)
CATALOG = {
    'android.permission.INTERNET': ('normal', 'AI provider, optional web lookups', 'low'),
    'android.permission.ACCESS_NETWORK_STATE': ('normal', 'offline/online detection', 'low'),
    'android.permission.RECORD_AUDIO': ('dangerous (runtime)', 'voice commands, Gemini voice input', 'medium: asked at runtime'),
    'android.permission.MODIFY_AUDIO_SETTINGS': ('normal', 'mic / speaker routing', 'low'),
    'android.permission.CAMERA': ('dangerous (runtime)', 'JARVIS Eye snapshot (on request)', 'medium: asked at runtime'),
    'android.permission.POST_NOTIFICATIONS': ('dangerous (runtime)', 'reminders, status notification', 'low'),
    'android.permission.VIBRATE': ('normal', 'haptics', 'low'),
    'android.permission.WAKE_LOCK': ('normal', 'keep listening while speaking', 'low'),
    'android.permission.SET_ALARM': ('normal', 'alarms by voice', 'low'),
    'android.permission.FOREGROUND_SERVICE': ('normal', 'listening service', 'low'),
    'android.permission.FOREGROUND_SERVICE_MICROPHONE': ('normal', 'always-on listening', 'medium: Play policy needs a visible reason'),
    'android.permission.FOREGROUND_SERVICE_SPECIAL_USE': ('normal', 'floating bubble service', 'medium: special-use FGS'),
    'android.permission.SYSTEM_ALERT_WINDOW': ('special (Settings toggle)', 'floating ARC bubble over apps', 'HIGH: overlay + accessibility combo is flagged often'),
    'android.permission.QUERY_ALL_PACKAGES': ('normal (Play-restricted)', 'open any installed app by name', 'HIGH: restricted on Play; sideload warning signal'),
    'android.permission.READ_CONTACTS': ('dangerous (runtime)', 'call / message contacts by name', 'medium-high: personal data'),
    'android.permission.PACKAGE_USAGE_STATS': ('special (Settings toggle)', 'app usage insights', 'medium-high'),
    'android.permission.WRITE_SETTINGS': ('special (Settings toggle)', 'brightness control', 'medium'),
    'android.permission.READ_EXTERNAL_STORAGE': ('dangerous, maxSdk 32', 'legacy file access (ignored on Android 13+)', 'low on Android 15/16'),
    'android.permission.WRITE_EXTERNAL_STORAGE': ('dangerous, maxSdk 29', 'legacy (ignored on Android 10+)', 'low on Android 15/16'),
    'android.permission.MANAGE_EXTERNAL_STORAGE': ('special', 'all-files access', 'HIGH'),
    'android.permission.REQUEST_INSTALL_PACKAGES': ('special', '-', 'HIGH'),
}


def perms(path):
    out = set()
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.search(r"name='([^']+)'", line)
        if m and 'permission' in line:
            out.add(m.group(1))
    return out


def badge(path):
    t = open(path, encoding='utf-8', errors='replace').read()
    pkg = re.search(r"package: name='([^']+)'.*?versionName='([^']*)'", t)
    sdk = re.search(r"targetSdkVersion:'(\d+)'", t)
    return (pkg.group(1) if pkg else '?', pkg.group(2) if pkg else '?', sdk.group(1) if sdk else '?')


def main(ev, out_md):
    rows = []
    apks = sorted(glob.glob(os.path.join(ev, '*-release-permissions.txt')))
    lines = ['# Permission & Play Protect audit (generated from CI `aapt` output)', '',
             'Source: `aapt dump permissions` / `aapt dump badging` of the release APKs built in this CI run.',
             'This report does not change, disable or bypass any device security (Play Protect, restricted settings).', '']
    full_set = std_set = set()
    for p in apks:
        name = os.path.basename(p).replace('-permissions.txt', '')
        b = os.path.join(ev, name + '-badging.txt')
        pkg, ver, sdk = badge(b) if os.path.exists(b) else ('?', '?', '?')
        ps = perms(p)
        if 'full' in name:
            full_set = ps
        else:
            std_set = ps
        lines += [f'## {name}', '', f'Package `{pkg}` · version `{ver}` · targetSdk {sdk} · {len(ps)} permissions', '',
                  '| Permission | Level | Used for | Play Protect / install risk |', '|---|---|---|---|']
        for perm in sorted(ps):
            lvl, why, risk = CATALOG.get(perm, ('other', 'library / plugin', 'review'))
            lines.append(f'| `{perm.replace("android.permission.", "")}` | {lvl} | {why} | {risk} |')
        lines.append('')
    only_full = sorted(full_set - std_set)
    lines += ['## Difference', '', f'Only in Full Control ({len(only_full)}): ' +
              (', '.join(f'`{p.replace("android.permission.", "")}`' for p in only_full) or 'none'), '',
              '## Play Protect risk summary (Full Control)', '',
              '* The Full Control APK combines an **accessibility service that can read the screen and perform gestures**, '
              'an **overlay (SYSTEM_ALERT_WINDOW)**, **QUERY_ALL_PACKAGES** and **contacts**. Sideloaded apps with this '
              'combination are the profile Play Protect warns about ("unsafe app" / "app scanned"), and on Android 13+ '
              'Android blocks enabling accessibility for sideloaded apps until the owner allows "restricted settings" '
              'in App info. That is the intended protection; JARVIS does not work around it.',
              '* The APKs are signed with the **CI debug key**. A debug-signed app is not installable from Play and every '
              'CI runner may produce a different key, so updates of the same package ID can fail with a signature '
              'mismatch. A stable owner release key (stored as encrypted CI secrets) is required for real updates.',
              '* **Standard** removes accessibility, overlay, contacts, all-package query, usage stats, WRITE_SETTINGS and '
              'Shizuku. It is the build to use day-to-day; Full Control only when screen automation is needed.',
              '* Lower-risk options for Full Control (owner decision, not applied automatically): keep the accessibility '
              'service disabled until needed; narrow `<queries>` instead of QUERY_ALL_PACKAGES; keep the notification '
              'listener disabled by default (it is: `android:enabled="false"`).', '']
    open(out_md, 'w', encoding='utf-8').write('\n'.join(lines))
    print('\n'.join(lines[:12]))
    print(f'... written {out_md}; full-only permissions: {only_full}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
