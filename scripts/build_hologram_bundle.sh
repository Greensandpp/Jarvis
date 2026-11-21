#!/usr/bin/env bash
set -euo pipefail
# Pinned esbuild 0.27.0. A local offline bundle; no CDN at runtime.
"${ESBUILD:-esbuild}" assets/hologram/scene.js --bundle --format=iife --minify --target=chrome100 --outfile=assets/hologram/scene.bundle.js
