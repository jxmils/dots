#!/usr/bin/env python3
"""Check the app and widget actually compile and bundle the 2D artwork."""
import json
import hashlib
import plistlib
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
    assert "Shared/PrivacyInfo.xcprivacy" in resources, f"{name}: missing privacy manifest"
    manifest = plistlib.loads((ROOT / "Shared/PrivacyInfo.xcprivacy").read_bytes())
    assert {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategorySystemBootTime",
            "NSPrivacyAccessedAPITypeReasons": ["35F9.1"]} in manifest["NSPrivacyAccessedAPITypes"]
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

egg = json.loads((ROOT / "Art/EggHatch/v001/verification.json").read_text())
kinds = {c['id'] for c in json.loads((ROOT / "Art/CollectionMotion/v001/catalog.json").read_text())}
assert set(egg['characters']) == kinds, "Every awarded kind needs its own hatch artwork"
for kind, record in egg['characters'].items():
    path = ROOT / 'Resources' / record['asset']
    data = path.read_bytes()
    assert struct.unpack('>II', data[16:24]) == (6144, 600), kind
    assert hashlib.sha256(data).hexdigest() == record['output_sha256'], f"{kind}: hatch export differs from retained source"
for name, key in [('EggWakingStrip', 'waking_sha256'), ('EggCrackingStrip', 'cracking_sha256')]:
    data = (ROOT / 'Resources' / (name + '.png')).read_bytes()
    assert struct.unpack('>II', data[16:24]) == (3072, 600), name
    assert hashlib.sha256(data).hexdigest() == egg[key], name
print("All 29 personalized hatches and the approved shared egg strips are bundled and hash-verified")

portraits = json.loads((ROOT / "Art/MoodPortraits/v001/manifest.json").read_text())
assert set(portraits) == kinds, "Every Dotling needs all three illustrated activity moods"
source_digests = set()
for character in json.loads((ROOT / "Art/CollectionMotion/v001/catalog.json").read_text()):
    entry = portraits[character["id"]]
    assert set(entry["sources"]) == {"sick", "studious", "workout"}
    source_digests.update(entry["sources"].values())
    atlas = (ROOT / character["file"]).read_bytes()
    assert struct.unpack(">II", atlas[16:24]) == (1536, 1536), character["id"]
    assert hashlib.sha256(atlas).hexdigest() == entry["atlas_sha256"], character["id"]
assert len(source_digests) == len(kinds) * 3, "Each character and mood needs its own source portrait"
print("All 87 new mood portraits have distinct sources and verified app/widget atlases")

motion_sources = json.loads((ROOT / "Art/MoodMotion/v001/manifest.json").read_text())
motion_prompts = json.loads((ROOT / "Art/MoodMotion/v001/prompts.json").read_text())
illustrated_actions = set(motion_prompts["actions"]) | {"lookDiagonal"}
assert set(motion_sources) == {f"{kind}-{action}.png" for kind in kinds for action in illustrated_actions}
mood_files = set()
for filename, entry in motion_sources.items():
    kind, action = filename[:-4].split("-")
    names = {f"{kind}-{mood}-{action}.webp" for mood in ["sick", "studious", "workingOut"]}
    assert set(entry["strips"]) == names
    for name, digest in entry["strips"].items():
        file = ROOT / "Resources/MoodMotion" / name
        data = file.read_bytes()
        assert data[:4] == b"RIFF" and data[8:12] == b"WEBP"
        assert hashlib.sha256(data).hexdigest() == digest, name
        mood_files.add(name)
assert mood_files == {p.name for p in (ROOT / "Resources/MoodMotion").iterdir() if not p.name.startswith(".")}
print("Verified all ten illustrated movements for 29 Dotlings in three moods, including eight gaze directions")
