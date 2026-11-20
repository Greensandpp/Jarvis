#!/usr/bin/env python3
"""Tiny uiautomator helper for CI emulator tests (never used on the owner's phone).

ui.py dump.xml find "<substring>"   -> prints "x y" centre of first node whose
                                        text or content-desc contains substring
ui.py dump.xml has "<substring>"    -> exit 0 if present
ui.py dump.xml edits                -> prints "x y" of every EditText, one per line
ui.py dump.xml texts                -> prints all visible text/content-desc
"""
import re, sys, xml.etree.ElementTree as ET
path, cmd = sys.argv[1], sys.argv[2]
arg = sys.argv[3] if len(sys.argv) > 3 else ''
try:
    root = ET.parse(path).getroot()
except Exception:
    sys.exit(2)
def centre(n):
    a, b, c, d = map(int, re.findall(r'\d+', n.get('bounds', '[0,0][0,0]')))
    return f'{(a + c) // 2} {(b + d) // 2}'
nodes = list(root.iter('node'))
label = lambda n: (n.get('text') or '') + ' ' + (n.get('content-desc') or '')
if cmd == 'find':
    for n in nodes:
        if arg.lower() in label(n).lower():
            print(centre(n)); sys.exit(0)
    sys.exit(1)
if cmd == 'has':
    sys.exit(0 if any(arg.lower() in label(n).lower() for n in nodes) else 1)
if cmd == 'edits':
    for n in nodes:
        if n.get('class') == 'android.widget.EditText':
            print(centre(n))
    sys.exit(0)
if cmd == 'texts':
    for n in nodes:
        t = label(n).strip()
        if t:
            print(t.replace('\n', ' | '))
