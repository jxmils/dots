"""Pack the painted action sheets. Usage: python build.py SOURCE_ROOT [--partial]."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RESOURCES = ROOT / "Resources"
DEST = RESOURCES / "MoodMotion"
CATALOG = json.loads((ROOT / "Art/CollectionMotion/v001/catalog.json").read_text())
ACTIONS = tuple(json.loads((HERE / "prompts.json").read_text())["actions"]) + ("lookDiagonal",)
MOODS = ("sick", "studious", "workingOut")
WIDTH, HEIGHT = 384, 416


def valleys(alpha, count):
    """Find the gap closest to each expected cut before separating adjacent poses."""
    projection = np.sum(alpha >= 32, axis=0)
    length = len(projection)
    cell = length / count
    cuts = [0]
    for i in range(1, count):
        target = cell * i
        candidates = np.arange(round(target - cell * .23), round(target + cell * .23))
        score = projection[candidates] + abs(candidates - target) / cell
        cuts.append(int(candidates[np.argmin(score)]))
    return cuts + [length]


def extract(cell):
    alpha = np.asarray(cell.getchannel("A"))
    regions, _ = ndimage.label(alpha >= 13)
    sizes = np.bincount(regions.ravel())
    big = sizes >= max(22, sizes[1:].max(initial=0) * .0015)
    big[0] = False
    keep = ndimage.binary_dilation(big[regions], iterations=2)
    new_alpha = np.where(keep, alpha, 0).astype(np.uint8)
    bounds = Image.fromarray(new_alpha).getbbox()
    if not bounds or (new_alpha > 127).sum() < cell.width * cell.height * .085:
        raise ValueError("Missing full-body pose")
    cell.putalpha(Image.fromarray(new_alpha))
    return cell.crop(bounds)


def render_sheet(job):
    path, kind, action, resting = job
    with Image.open(path) as src:
        sheet = src.convert("RGBA")
    alpha = np.asarray(sheet.getchannel("A"))
    if np.mean(alpha < 10) < .1:
        # Selected retry sheets use the project's flat magenta key. Preserve the
        # untouched master and remove the key only when all four corners agree.
        rgb = np.asarray(sheet.convert("RGB"), dtype=np.float32)
        red, green, blue = rgb.transpose(2, 0, 1)
        excess = np.minimum(red, blue) - green
        key = (excess > 90) & (red > 155) & (blue > 155)
        corners = [key[:8, :8], key[:8, -8:], key[-8:, :8], key[-8:, -8:]]
        if not all(corner.mean() > .95 for corner in corners):
            raise ValueError(f"Missing transparency: {path}")
        # Refine the one-pixel fur edge. Rosy cheeks and plum props inside the
        # character keep their original colors.
        boundary = ndimage.binary_dilation(key, iterations=2) & ~key
        opacity = np.ones(key.shape, dtype=np.float32)
        opacity[key] = 0
        opacity[boundary] = np.clip(1 - np.maximum(0, excess[boundary]) / 255, 0, 1)
        recovered = (rgb[boundary] - (1-opacity[boundary, None]) * np.array([255,0,255])) / np.maximum(.01, opacity[boundary, None])
        rgb[boundary] = np.clip(recovered, 0, 255)
        sheet = Image.fromarray(rgb.astype(np.uint8)).convert("RGBA")
        sheet.putalpha(Image.fromarray(np.uint8(opacity * 255)))
        alpha = np.asarray(sheet.getchannel("A"))
    ycuts = valleys(alpha.T, 3)
    output = {}
    for row, mood in enumerate(MOODS):
        top, bottom = ycuts[row:row + 2]
        xcuts = valleys(alpha[top:bottom], 4)
        poses = [extract(sheet.crop((x, top, right, bottom))) for x, right in zip(xcuts, xcuts[1:])]
        left, top_bound, right, baseline = resting
        target_width, target_height = right - left, baseline - top_bound
        scale = min(target_width / max(p.width for p in poses),target_height / max(p.height for p in poses))
        strip = Image.new("RGBA", (WIDTH * 4, HEIGHT))
        for index, pose in enumerate(poses):
            w, h = max(1, round(pose.width * scale)), max(1, round(pose.height * scale))
            pose = pose.resize((w, h), Image.Resampling.LANCZOS)
            lift = round((0,.045,.12,0)[index] * target_height) if action == "jump" else 0
            offset = round((-.04,-.01,.035,.055)[index] * target_width) if action.startswith("move") else 0
            if action == "moveLeft":
                offset = -offset
            x = max(2,min(WIDTH-w-2,round((left+right-w)/2)+offset))
            y = max(2,min(HEIGHT-h-2,baseline-h-lift))
            strip.paste(pose,(index*WIDTH+x,y))
        name = f"{kind}-{mood}-{action}.webp"
        dest = DEST / name
        pending = dest.with_suffix(".tmp")
        strip.save(pending, "WEBP", quality=91, method=3, exact=False)
        pending.replace(dest)
        output[name] = hashlib.sha256(dest.read_bytes()).hexdigest()
    return path.name, {"source":hashlib.sha256(path.read_bytes()).hexdigest(),"strips":output}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--partial", action="store_true",help="Pack the sheets already on disk")
    args=parser.parse_args()
    DEST.mkdir(exist_ok=True)
    manifest_path = HERE / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    jobs=[]
    for c in CATALOG:
        kind=c["id"]
        with Image.open(RESOURCES / f"Companion{kind.capitalize()}MotionIdle.png") as idle:
            anchor=idle.crop((0,0,WIDTH,HEIGHT)).convert("RGBA").getchannel("A").point(lambda a: 255 if a>=32 else 0).getbbox()
        for action in ACTIONS:
            source=args.source/"originals"/f"{kind}-{action}.png"
            if not source.is_file():
                if args.partial: continue
                raise ValueError(f"Missing source: {source}")
            record=manifest.get(source.name,{})
            if record.get("source") == hashlib.sha256(source.read_bytes()).hexdigest():
                intact = all(
                    (DEST / name).is_file()
                    and hashlib.sha256((DEST / name).read_bytes()).hexdigest() == digest
                    for name, digest in record["strips"].items()
                )
                if intact and len(record["strips"]) == len(MOODS):
                    continue
            jobs.append((source,kind,action,anchor))
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(render_sheet, job): job[0] for job in jobs}
        for future in as_completed(futures):
            try:
                name, entry = future.result()
                manifest[name] = entry
            except (OSError, ValueError) as error:
                if not args.partial:
                    raise
                print(f"Pending inspection: {futures[future].name}: {error}", flush=True)
    pending_manifest = manifest_path.with_suffix(".tmp")
    pending_manifest.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    pending_manifest.replace(manifest_path)
    print(f"Packed {len(manifest)} source sheets and {sum(len(v['strips']) for v in manifest.values())} transparent character/mood strips.")


if __name__=="__main__":
    main()
