#!/usr/bin/env python3
"""Create a distinct minimal-permission JARVIS *staging only* variant.

Changes occur only in the CI worktree. Never edit production or Stable APK.
This is an installability differential test: phone-only features needing
runtime/special permissions are unavailable in this variant.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
gradle = root / "android/app/build.gradle.kts"
manifest = root / "android/app/src/main/AndroidManifest.xml"
g = gradle.read_text()
old = 'applicationIdSuffix = ".visualrelease"'
assert g.count(old) == 1, "expected isolated release suffix exactly once"
gradle.write_text(g.replace(old, 'applicationIdSuffix = ".visualsafe"'))
ANDROID = "http://schemas.android.com/apk/res/android"
TOOLS = "http://schemas.android.com/tools"
ET.register_namespace('android', ANDROID)
ET.register_namespace('tools', TOOLS)
tree = ET.parse(manifest)
m = tree.getroot()
keep = {
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
}
for element in list(m):
    if element.tag == "uses-permission" and element.get(f"{{{ANDROID}}}name") not in keep:
        m.remove(element)
app = m.find("application")
assert app is not None
app.set(f"{{{ANDROID}}}label", "GreenSoil JARVIS SAFE QA")
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
tree.write(manifest, encoding="utf-8", xml_declaration=True)
print("Created isolated com.greensoil.jarvis.tamiltest.visualsafe build configuration")
