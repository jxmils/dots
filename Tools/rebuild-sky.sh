#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SKY_BLENDER_BIN="${BLENDER_BIN:-}"
if [[ -z "$SKY_BLENDER_BIN" ]]; then
  SKY_BLENDER_BIN=$(command -v blender || true)
fi
if [[ -z "$SKY_BLENDER_BIN" && -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
  SKY_BLENDER_BIN=/Applications/Blender.app/Contents/MacOS/Blender
fi
if [[ -z "$SKY_BLENDER_BIN" ]]; then
  echo 'Install Blender 5.1.0 or set BLENDER_BIN to its executable.' >&2
  exit 1
fi
"$SKY_BLENDER_BIN" --background --factory-startup --python-exit-code 1 --python Tools/rebuild-sky.py -- \
  --output "${1:-build/sky-model}" --check
