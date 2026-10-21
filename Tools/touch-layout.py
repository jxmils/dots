"""Measure sprite origins without changing the generated PNG artwork.

Run with Pillow and NumPy after replacing touch atlases. One uniform scale is
shared by every pose of a creature; only drawing origins vary between frames.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def bounds(alpha):
    ys, xs = np.nonzero(alpha >= 128)
    return np.array([xs.min(), ys.min(), xs.max() + 1, ys.max() + 1])


rows = []
for path in sorted((ROOT / "Resources").glob("*TouchAtlas.png")):
    alpha = np.asarray(Image.open(path).getchannel("A"))
    occupied = alpha >= 64
    columns = occupied.sum(axis=0)
    lines = occupied.sum(axis=1)
    xs = [0] + [x - 65 + int(np.argmin(columns[x - 65:x + 65])) for x in (512, 1024)] + [1536]
    ys = [0, 450 + int(np.argmin(lines[450:575])), 1024]
    boxes = []
    for i in range(6):
        x, y = xs[i % 3], ys[i // 3]
        box = bounds(alpha[y:ys[i // 3 + 1], x:xs[i % 3 + 1]]) + [x, y, x, y]
        boxes.append(box)

    reference = np.asarray(Image.open(path.with_name(path.name.replace("TouchAtlas", "Atlas"))).getchannel("A"))[:512, :512]
    reference_box = bounds(reference)
    center = (reference_box[:2] + reference_box[2:]) / 2
    widths = [box[2] - box[0] for box in boxes]
    heights = [box[3] - box[1] for box in boxes]
    scale = min((reference_box[2] - reference_box[0]) / np.median(widths),
                (reference_box[3] - reference_box[1]) / np.median(heights))
    frames = []
    for i, box in enumerate(boxes):
        # Keep soft fur edges inside the measured cell boundaries.
        crop = np.array([max(xs[i % 3], box[0] - 8), max(ys[i // 3], box[1] - 8),
                         min(xs[i % 3 + 1], box[2] + 8), min(ys[i // 3 + 1], box[3] + 8)])
        origin = center - ((box[:2] + box[2:]) / 2 - crop[:2]) * scale
        frames.append([int(crop[0]), int(crop[1]), int(crop[2] - crop[0]), int(crop[3] - crop[1]),
                       round(float(origin[0]), 4), round(float(origin[1]), 4), round(float(scale), 6)])
    rows.append(f'        "{path.stem}": [\n' + ''.join('            ' + json.dumps(frame) + ',\n' for frame in frames) + '        ],\n')

output = '''// Drawing coordinates measured by Tools/touch-layout.py. The PNGs remain unchanged.
import Foundation

enum CompanionTouchLayout {
    // source x, y, width, height; destination x, y; uniform scale shared by all six poses
    static let frames: [String: [[CGFloat]]] = [
''' + ''.join(rows) + '    ]\n}\n'
(ROOT / 'Shared/CompanionTouchLayout.swift').write_text(output)
print(f'Measured {len(rows)} touch atlases without altering pixels')
