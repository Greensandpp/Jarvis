#!/usr/bin/env python3
"""Inspect arm64 PT_LOAD ELF alignment in an APK; Android 16 KB page diagnostics."""
import json
import struct
import sys
import zipfile

apk = sys.argv[1]
report = sys.argv[2]
rows = []
with zipfile.ZipFile(apk) as z:
    members = [n for n in z.namelist() if n.startswith("lib/arm64-v8a/") and n.endswith(".so")]
    for name in sorted(members):
        data = z.read(name)
        if data[:4] != b"\x7fELF" or data[4] not in (1, 2):
            rows.append({"library": name, "status": "INVALID_ELF"})
            continue
        fmt = "<" if data[5] == 1 else ">"
        elf64 = data[4] == 2
        off = struct.unpack_from(fmt + ("Q" if elf64 else "I"), data, 32 if elf64 else 28)[0]
        entsize = struct.unpack_from(fmt + "H", data, 54 if elf64 else 42)[0]
        count = struct.unpack_from(fmt + "H", data, 56 if elf64 else 44)[0]
        alignments = []
        for i in range(count):
            pos = off + i * entsize
            if pos + entsize > len(data):
                raise ValueError("Truncated ELF program headers in " + name)
            segment_type = struct.unpack_from(fmt + "I", data, pos)[0]
            if segment_type != 1:
                continue
            align = struct.unpack_from(fmt + ("Q" if elf64 else "I"), data, pos + (48 if elf64 else 28))[0]
            alignments.append(align)
        status = "ALIGNED_16K" if alignments and all(a >= 16384 and a % 16384 == 0 for a in alignments) else "UNALIGNED_16K"
        rows.append({"library": name, "load_alignment": alignments, "status": status})
summary = {"apk": apk, "arm64_library_count": len(members), "libraries": rows,
           "all_arm64_load_segments_16kb": bool(members) and all(r["status"] == "ALIGNED_16K" for r in rows)}
with open(report, "w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2)
for row in rows:
    print(row["status"], row["library"], row.get("load_alignment", []))
print("16KB ELF check:", "PASS" if summary["all_arm64_load_segments_16kb"] else "NEEDS_REVIEW")
if not summary["all_arm64_load_segments_16kb"]:
    sys.exit(2)
