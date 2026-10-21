#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build/launch-kit}
CAPTURES=${2:-build/store-captures}
TMP=$(mktemp -d)
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
swiftc -parse-as-library -sdk "$SDK" -target arm64-apple-ios18.0-macabi -swift-version 5 \
  -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" -I "$SDK/System/iOSSupport/usr/lib/swift" \
  ${FLAGS[@]+"${FLAGS[@]}"} Tools/marketing.swift -o "$TMP/marketing"
"$TMP/marketing" "$OUT" "$CAPTURES"
