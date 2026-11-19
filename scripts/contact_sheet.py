#!/usr/bin/env python3
"""CI helper: build a contact sheet of real emulator screenshots, report
pixel differences between two frames of each mode (animation evidence) and
print the sheet as base64 so it can be reviewed from the job log."""
import base64, glob, io, os, sys
from PIL import Image, ImageChops, ImageDraw

d = sys.argv[1]
os.chdir(d)
shots = sorted(glob.glob("mode-*-a.png")) + ["mode-aira-b.png"] + sorted(glob.glob("aira-*.png"))
shots = [s for s in shots if os.path.exists(s)]
for m in ["core", "aira", "office", "apex", "mira"]:
    a, b = f"mode-{m}-a.png", f"mode-{m}-b.png"
    if os.path.exists(a) and os.path.exists(b):
        diff = ImageChops.difference(Image.open(a).convert("RGB"), Image.open(b).convert("RGB"))
        changed = sum(1 for px in diff.convert("L").getdata() if px > 12)
        print(f"animation-diff {m}: {changed} pixels changed between frames 2 s apart")
W, H, cols = 270, 600, 6
rows = (len(shots) + cols - 1) // cols
sheet = Image.new("RGB", (cols * W, rows * (H + 18)), "black")
draw = ImageDraw.Draw(sheet)
for i, s in enumerate(shots):
    im = Image.open(s).convert("RGB").resize((W, H))
    x, y = (i % cols) * W, (i // cols) * (H + 18)
    sheet.paste(im, (x, y + 18))
    draw.text((x + 4, y + 2), s, fill="white")
buf = io.BytesIO()
sheet.save(buf, "JPEG", quality=70)
open("contact-sheet.jpg", "wb").write(buf.getvalue())
print("-----BEGIN CONTACT SHEET-----")
print(base64.b64encode(buf.getvalue()).decode())
print("-----END CONTACT SHEET-----")
