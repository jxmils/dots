"""Append three illustrated resting moods to every original six-pose atlas."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MOODS = ("sick", "studious", "workout")
CELL = 512


def export_pose(path):
    with Image.open(path) as source:
        rgba = source.convert("RGBA")
    alpha = rgba.getchannel("A")
    min_alpha, max_alpha = alpha.getextrema()
    if min_alpha > 3 or max_alpha < 245:
        raise ValueError(f"Expected a transparent character: {path}")
    bounds = alpha.point(lambda p: 255 if p >= 10 else 0).getbbox()
    if bounds is None:
        raise ValueError(f"Empty sprite: {path}")
    x, y, right, bottom = bounds
    portrait = rgba.crop((max(0, x - 3), max(0, y - 3),
                          min(rgba.width, right + 3), min(rgba.height, bottom + 3)))
    portrait.thumbnail((480, 462), Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", (CELL, CELL))
    cell.paste(portrait, ((CELL - portrait.width) // 2, 488 - portrait.height))
    return cell


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Folder containing {mood}-originals/{character}.png")
    args = parser.parse_args()
    manifest = {}
    catalog = json.loads((ROOT / "Art/CollectionMotion/v001/catalog.json").read_text())
    for character in catalog:
        kind = character["id"]
        path = ROOT / character["file"]
        with Image.open(path) as previous:
            if previous.width != CELL * 3 or previous.height not in (CELL * 2, CELL * 3):
                raise ValueError(f"Unexpected base atlas: {path}")
            existing = previous.convert("RGBA").crop((0, 0, CELL * 3, CELL * 2))
        atlas = Image.new("RGBA", (CELL * 3, CELL * 3))
        atlas.paste(existing, (0, 0))
        sources = {}
        for i, mood in enumerate(MOODS):
            original = args.source / f"{mood}-originals" / f"{kind}.png"
            cell = export_pose(original)
            atlas.paste(cell, (CELL * i, CELL * 2))
            sources[mood] = hashlib.sha256(original.read_bytes()).hexdigest()
        atlas.save(path, compress_level=7)
        manifest[kind] = {"reference": f"Art/CollectionMotion/v001/{kind}/reference.png",
                          "sources": sources, "atlas_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
