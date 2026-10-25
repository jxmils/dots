#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build/check}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
TMP=$(mktemp -d "$OUT/.checks.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
SDK=$(xcrun --show-sdk-path)
FLAGS=()
if [[ -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap && -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]]; then
  : > "$TMP/empty.modulemap"
  cat > "$TMP/overlay.yaml" <<YAML
{"version":0,"case-sensitive":"false","roots":[{"type":"directory","name":"/Library/Developer/CommandLineTools/usr/include/swift","contents":[{"type":"file","name":"module.modulemap","external-contents":"$TMP/empty.modulemap"}]}]}
YAML
  FLAGS+=(-vfsoverlay "$TMP/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$TMP/overlay.yaml")
fi
IOS=(-sdk "$SDK" -target arm64-apple-ios18.0-macabi -swift-version 5 -whole-module-optimization
     -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" -I "$SDK/System/iOSSupport/usr/lib/swift")
echo '== App type-check'
swiftc -typecheck -parse-as-library "${IOS[@]}" ${FLAGS[@]+"${FLAGS[@]}"} -D DEBUG Shared/*.swift Dots/*.swift
echo '== Widget type-check'
swiftc -typecheck -parse-as-library "${IOS[@]}" ${FLAGS[@]+"${FLAGS[@]}"} Shared/*.swift DotsWidget/*.swift
echo '== Plists and project'
plutil -lint Dots/Info.plist DotsWidget/Info.plist Dots/*.entitlements DotsWidget/*.entitlements Dots.xcodeproj/project.pbxproj
python3 Tools/check-sprite-build.py
echo '== Behavior and artwork checks'
swiftc -parse-as-library "${IOS[@]}" ${FLAGS[@]+"${FLAGS[@]}"} Shared/*.swift Dots/RestoreBudget.swift Dots/CircleModel.swift Tests/main.swift -o "$TMP/checks"
"$TMP/checks"
echo '== App and widget renders'
swiftc -parse-as-library "${IOS[@]}" ${FLAGS[@]+"${FLAGS[@]}"} Shared/*.swift Dots/RestoreBudget.swift Dots/CircleModel.swift Dots/DotsViews.swift Dots/CloudSharingView.swift Dots/DotsApp.swift Dots/CollectionViews.swift Tools/render.swift -D DOTS_RENDER -o "$TMP/render"
"$TMP/render" "$OUT"
test -s "$OUT/preview.png"
test -s Dots/Assets.xcassets/AppIcon.appiconset/AppIcon.png
sips -g hasAlpha Dots/Assets.xcassets/AppIcon.appiconset/AppIcon.png | grep -q 'hasAlpha: no'
echo 'CHECKS PASSED'
