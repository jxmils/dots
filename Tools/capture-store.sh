#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build/store-captures}
mkdir -p "$OUT"
xcrun simctl list devices available --json > "$OUT/devices.json"
DEVICE=$(python3 - "$OUT/devices.json" <<'PY'
import json,sys
devices=json.load(open(sys.argv[1]))['devices']
candidates=[d for runtime, values in devices.items() if 'iOS' in runtime for d in values if d.get('isAvailable') and 'Pro Max' in d['name']]
if not candidates: raise SystemExit('No supported iPhone Pro Max simulator is installed')
preferred=sorted(candidates,key=lambda d:('17 Pro Max' in d['name'],'16 Pro Max' in d['name'],d['name']),reverse=True)[0]
print(preferred['udid'])
PY
)
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState discharging --batteryLevel 100
xcodebuild -project Dots.xcodeproj -scheme Dots -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build/CaptureData \
  CODE_SIGNING_ALLOWED=NO build > "$OUT/build.log" 2>&1 || { tail -80 "$OUT/build.log"; exit 1; }
xcrun simctl install "$DEVICE" build/CaptureData/Build/Products/Debug-iphonesimulator/Dots.app
for page in home low friends widget collection hatch name profile; do
  xcrun simctl terminate "$DEVICE" com.jasonmiller.dots || true
  xcrun simctl launch "$DEVICE" com.jasonmiller.dots --capture-store --capture-page "$page"
  sleep 4
  xcrun simctl io "$DEVICE" screenshot "$OUT/$page.png"
done
xcrun swift Tools/audit-captures.swift "$OUT"
xcrun simctl shutdown "$DEVICE"
echo 'CAPTURES COMPLETE'
