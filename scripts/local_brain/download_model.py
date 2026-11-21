"""Explicit build-time QA download, never imported by the application."""
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

config = json.loads(Path(__file__).with_name('model.json').read_text())
url = f"https://huggingface.co/{config['repository']}/resolve/{config['revision']}/{config['filename']}"
target = Path(sys.argv[1])
partial = target.with_suffix('.partial')
h = hashlib.sha256()
size = 0
try:
    with urllib.request.urlopen(url, timeout=120) as response, partial.open('wb') as output:
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > config['bytes']: raise ValueError('Oversized model')
            h.update(chunk); output.write(chunk)
    if size != config['bytes'] or h.hexdigest() != config['sha256']:
        raise ValueError('Model checksum mismatch')
    partial.replace(target)
    print(json.dumps({'model_bytes': size, 'sha256': h.hexdigest(), 'verified': True}))
finally:
    partial.unlink(missing_ok=True)
