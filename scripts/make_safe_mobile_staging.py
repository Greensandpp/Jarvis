#!/usr/bin/env python3
"""Create a distinct minimal-permission JARVIS *staging only* variant.

Changes occur only in the CI worktree. Never edit production or Stable APK.
This is an installability differential test: phone-only features needing
runtime/special permissions are unavailable in these variants.

Variants (default: visualsafe, unchanged from the four-mode baseline):
  visualsafe  INTERNET + ACCESS_NETWORK_STATE only. Visual modes + text chat.
  voicesafe   visualsafe + RECORD_AUDIO + MODIFY_AUDIO_SETTINGS for the
              owner-opt-in Gemini Live voice test. No accessibility, overlay,
              contacts, package listing, settings writes, notification
              listener, usage stats, camera, storage or Shizuku.

Usage: make_safe_mobile_staging.py [--variant visualsafe|voicesafe|unifiedsafe] [--root DIR]
"""
from pathlib import Path
import argparse
import xml.etree.ElementTree as ET

VARIANTS = {
    "visualsafe": {
        "label": "GreenSoil JARVIS SAFE QA",
        "keep": {"android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"},
    },
    "unifiedsafe": {
        "label": "GreenSoil JARVIS UNIFIED QA",
        "keep": {
            "android.permission.INTERNET",
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.RECORD_AUDIO",
            "android.permission.MODIFY_AUDIO_SETTINGS",
        },
    },
    "voicesafe": {
        "label": "GreenSoil JARVIS VOICE QA",
        "keep": {
            "android.permission.INTERNET",
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.RECORD_AUDIO",
            "android.permission.MODIFY_AUDIO_SETTINGS",
        },
    },
}

parser = argparse.ArgumentParser()
parser.add_argument("--variant", choices=sorted(VARIANTS), default="visualsafe")
parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
args = parser.parse_args()
cfg = VARIANTS[args.variant]

root = Path(args.root)
gradle = root / "android/app/build.gradle.kts"
manifest = root / "android/app/src/main/AndroidManifest.xml"
g = gradle.read_text()
old = 'applicationIdSuffix = ".visualrelease"'
assert g.count(old) == 1, "expected isolated release suffix exactly once"
gradle.write_text(g.replace(old, f'applicationIdSuffix = ".{args.variant}"'))
ANDROID = "http://schemas.android.com/apk/res/android"
TOOLS = "http://schemas.android.com/tools"
ET.register_namespace('android', ANDROID)
ET.register_namespace('tools', TOOLS)
tree = ET.parse(manifest)
m = tree.getroot()
for element in list(m):
    if element.tag == "uses-permission" and element.get(f"{{{ANDROID}}}name") not in cfg["keep"]:
        m.remove(element)
app = m.find("application")
assert app is not None
app.set(f"{{{ANDROID}}}label", cfg["label"])
app.set(f"{{{ANDROID}}}usesCleartextTraffic", "false")
for element in list(app):
    if element.tag in {"provider", "service", "receiver"}:
        app.remove(element)
# Component permissions from Flutter dependencies may be reintroduced by
# manifest merging. Add tools:node removal declarations for known services.
for component, cname in [
    ("service", "flutter.overlay.window.flutter_overlay_window.OverlayService"),
]:
    node = ET.SubElement(app, component)
    node.set(f"{{{ANDROID}}}name", cname)
    node.set(f"{{{TOOLS}}}node", "remove")
# Merged library permissions must also be stripped, not just our own.
for perm in [
    "android.permission.SYSTEM_ALERT_WINDOW",
    "android.permission.QUERY_ALL_PACKAGES",
    "android.permission.READ_CONTACTS",
    "android.permission.WRITE_CONTACTS",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
    "android.permission.FOREGROUND_SERVICE_MICROPHONE",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.SCHEDULE_EXACT_ALARM",
    "android.permission.USE_EXACT_ALARM",
    "android.permission.WRITE_SETTINGS",
    "android.permission.PACKAGE_USAGE_STATS",
    "android.permission.CAMERA",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.REQUEST_INSTALL_PACKAGES",
    "android.permission.REQUEST_DELETE_PACKAGES",
    "moe.shizuku.manager.permission.API_V23",
]:
    if perm in cfg["keep"]:
        continue
    node = ET.SubElement(m, "uses-permission")
    node.set(f"{{{ANDROID}}}name", perm)
    node.set(f"{{{TOOLS}}}node", "remove")
tree.write(manifest, encoding="utf-8", xml_declaration=True)
print(f"Created isolated com.greensoil.jarvis.tamiltest.{args.variant} build configuration")
