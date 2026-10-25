#!/usr/bin/env python3
"""Check the app and widget actually compile and bundle the 2D artwork."""
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
project = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(ROOT / "Dots.xcodeproj/project.pbxproj")
]))["objects"]
targets = {obj["name"]: obj for obj in project.values() if obj.get("isa") == "PBXNativeTarget"}
for name, folder in [("Dots", "Dots"), ("DotsWidget", "DotsWidget")]:
    sources, resources = set(), set()
    for phase_id in targets[name]["buildPhases"]:
        phase = project[phase_id]
        if phase["isa"] not in ("PBXSourcesBuildPhase", "PBXResourcesBuildPhase"):
            continue
        paths = sources if phase["isa"] == "PBXSourcesBuildPhase" else resources
        for build_id in phase.get("files", []):
            paths.add(project[project[build_id]["fileRef"]]["path"])
    expected = {str(p.relative_to(ROOT)) for directory in ["Shared", folder]
                for p in (ROOT / directory).glob("*.swift")}
    assert sources == expected, f"{name}: project source list differs from active source files"
    for path in sources:
        source = (ROOT / path).read_text()
        assert "import RealityKit" not in source and "import SceneKit" not in source, path
        assert "LiveCompanionView" not in source and "SkyMoodPreview" not in source, path
    expected_art = {str(p.relative_to(ROOT)) for p in (ROOT / "Resources").glob("*.png")}
    assert expected_art <= resources, f"{name}: missing sprite resources: {expected_art - resources}"
    assert not any(p.endswith(".usdz") or "Archive3D" in p or "Resources/Models/" in p
                   for p in sources | resources), f"{name}: includes a retired 3D prototype"
    for path in sources | resources:
        assert (ROOT / path).exists(), f"{name}: missing file {path}"

strip = ROOT / "Resources/CompanionDuskBlink.png"
assert struct.unpack(">II", strip.read_bytes()[16:24]) == (3072, 512)
assert strip.read_bytes() == (ROOT / "Art/Dusk/SpriteTrial/idle.png").read_bytes(), "Dusk export differs from retained source"
print("App and widget use only 2D sources, bundle every sprite, and include Dusk's retained strip")
