"""Validate upload dimensions, PNG opacity, outlined logos and listing field limits."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET

root = Path(sys.argv[1])
required = {
    "logos/app-icon-1024.png": (1024, 1024),
    "app-store/header-3840x1646.png": (3840, 1646),
    "app-store/universal-5244x2950.png": (5244, 2950),
    "app-store/search-results-3840x2560.png": (3840, 2560),
    "app-store/search-results-1920x1280.png": (1920, 1280),
}
names = ["home", "low", "friends", "widget", "collection", "hatch", "name", "profile"]
for i, name in enumerate(names, 1):
    for folder, size in [("6.9-inch", (1320, 2868)), ("6.5-inch", (1284, 2778)),
                         ("6.3-inch", (1206, 2622)), ("6.1-inch", (1179, 2556))]:
        required[f"screenshots/{folder}/{i:02d}-{name}.png"] = size

manifest = []
for name, size in required.items():
    data = (root / name).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", name
    width, height, depth, color, _, _, _ = struct.unpack(">IIBBBBB", data[16:29])
    assert (width, height) == size, (name, width, height)
    assert color == 2 and depth == 8, f"{name}: upload images must be opaque 8-bit RGB"
    manifest.append({"file": name, "width": width, "height": height, "mode": "RGB", "sha256": hashlib.sha256(data).hexdigest()})

for name in ["mark-color.svg", "lockup-color.svg", "wordmark-dark.svg", "wordmark-light.svg"]:
    tree = ET.parse(root / "logos" / name)
    assert not any(element.tag.endswith("}text") for element in tree.iter()), f"{name}: wordmarks must be font-independent outlines"

listing = json.loads(Path("Marketing/listing-en-US.json").read_text())
limits = {"name": 30, "subtitle": 30, "promotional_text": 170, "description": 4000, "keywords": 100, "review_notes": 4000}
for field, limit in limits.items():
    assert len(listing[field]) <= limit, (field, len(listing[field]), limit)

(root / "asset-manifest.json").write_text(json.dumps({"validated_upload_assets": manifest, "listing_field_lengths": {k: len(listing[k]) for k in limits}}, indent=2) + "\n")
print(f"Verified {len(required)} upload images, four outlined logos and all listing field limits")
