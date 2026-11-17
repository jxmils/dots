#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build/check}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
TMP=$(mktemp -d "$OUT/.checks.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
SDK=$(xcrun --show-sdk-path)
CHECK_ARCH=$(uname -m)
case "$CHECK_ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported check host architecture: $CHECK_ARCH" >&2; exit 1 ;;
esac
FLAGS=()
if [[ -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap && -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]]; then
  : > "$TMP/empty.modulemap"
  cat > "$TMP/overlay.yaml" <<YAML
{"version":0,"case-sensitive":"false","roots":[{"type":"directory","name":"/Library/Developer/CommandLineTools/usr/include/swift","contents":[{"type":"file","name":"module.modulemap","external-contents":"$TMP/empty.modulemap"}]}]}
YAML
  FLAGS+=(-vfsoverlay "$TMP/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$TMP/overlay.yaml")
fi
IOS=(-sdk "$SDK" -target "${CHECK_ARCH}-apple-ios18.0-macabi" -swift-version 5 -whole-module-optimization
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
echo '== Compile app and widget preview harness'
swiftc -parse-as-library "${IOS[@]}" ${FLAGS[@]+"${FLAGS[@]}"} Shared/*.swift Dots/RestoreBudget.swift Dots/CircleModel.swift Dots/DotsViews.swift Dots/CloudSharingView.swift Dots/DotsApp.swift Dots/CollectionViews.swift Tools/render.swift -D DOTS_RENDER -o "$TMP/render"
if [[ "${DOTLINGS_HEADLESS:-0}" == "1" ]]; then
  echo 'SKIPPED: SwiftUI GPU screen renders on headless host; full visual checks remain the local default'
else
  "$TMP/render" "$OUT"
  if [[ "${DOTLINGS_CAPTURE_SIGNATURES:-0}" == "1" ]]; then
    DOTLINGS_SIGNATURE_PREVIEW=1 "$TMP/render" "$OUT"
  fi
  test -s "$OUT/preview.png"
fi
test -s Dots/Assets.xcassets/AppIcon.appiconset/AppIcon.png
sips -g hasAlpha Dots/Assets.xcassets/AppIcon.appiconset/AppIcon.png | grep -q 'hasAlpha: no'
if [[ "${DOTLINGS_HEADLESS:-0}" == "1" ]]; then
  echo 'HEADLESS CHECKS PASSED (GPU previews not run)'
else
  echo 'CHECKS PASSED'
fi
