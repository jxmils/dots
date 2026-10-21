"""Measure egg drawing origins; preserve all generated pixels and proportions."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent.parent
entries = []
for name in ['EggWakeAtlas', 'EggOpenAtlas']:
    alpha = Image.open(root / 'Resources' / (name + '.png')).getchannel('A')
    frames = []
    for index in range(6):
        x, y = index % 3 * 512, index // 3 * 512
        bounds = alpha.crop((x, y, x + 512, y + 512)).point(lambda value: 255 if value >= 200 else 0).getbbox()
        frames.append([x, y, 512, 512, 256 - (bounds[0] + bounds[2]) / 2, 450 - bounds[3], 1])
    entries.append(f'        "{name}": [\n' + ''.join('            ' + json.dumps(frame) + ',\n' for frame in frames) + '        ],\n')
(root / 'Shared/EggArtLayout.swift').write_text(
    '// Drawing origins measured by Tools/egg-layout.py. No image warping.\nimport Foundation\n\nenum EggArtLayout {\n'
    '    static let frames: [String: [[CGFloat]]] = [\n' + ''.join(entries) + '    ]\n}\n')
