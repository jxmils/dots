#!/usr/bin/env python3
"""Export approved generated egg poses; no redrawing, warping, or interpolation.

Requires Pillow and numpy. Source originals remain in the external production
folder. Run with --production ROOT --approved ROOT --output Resources.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = (512, 600)
BASELINE = 474
BG = (247, 244, 240)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(path):
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(float)
    key = np.median(np.concatenate([rgb[:24].reshape(-1, 3), rgb[-24:].reshape(-1, 3)]), axis=0)
    strength = min(key[0] - key[1], key[2] - key[1])
    assert strength > 100, (path, key)
    raw = 1 - np.clip(np.minimum(rgb[:, :, 0] - rgb[:, :, 1], rgb[:, :, 2] - rgb[:, :, 1]) / strength, 0, 1)
    interior = np.asarray(Image.fromarray(((raw > .58) * 255).astype('uint8')).filter(ImageFilter.MinFilter(5))) > 0
    alpha = np.where(interior, 1, raw)
    alpha[alpha < .05] = 0
    fg = np.clip((rgb - (1 - alpha[:, :, None]) * key) / np.maximum(alpha[:, :, None], .001), 0, 255)
    rgba = np.dstack([fg, alpha * 255]).astype('uint8')
    rgba[alpha == 0, :3] = 0
    occupied = np.sum(alpha > .65, axis=0) > 2
    edges = np.diff(np.pad(occupied.astype(int), (1, 1)))
    runs = [(a, b) for a, b in zip(np.where(edges == 1)[0], np.where(edges == -1)[0]) if b - a > 12]
    assert len(runs) == 6, (path, runs)
    boxes, widths, centers = [], [], []
    for left, right in runs:
        yy, _ = np.where(alpha[:, left:right] > .25)
        box = (max(0, int(left) - 3), max(0, int(yy.min()) - 3), min(rgb.shape[1], int(right) + 3), min(rgb.shape[0], int(yy.max()) + 4))
        x0, y0, x1, y1 = box
        region = alpha[y1 - 95:y1, x0:x1]
        weights = region.sum(axis=0)
        centers.append(x0 + np.dot(np.arange(len(weights)), weights) / weights.sum())
        _, xs = np.where(region > .65)
        widths.append(int(xs.max() - xs.min() + 1))
        boxes.append(box)
    scale = 280 / float(np.median(widths))
    frames = []
    for box, center in zip(boxes, centers):
        x0, y0, x1, y1 = box
        crop = Image.fromarray(rgba[y0:y1, x0:x1]).resize((round((x1 - x0) * scale), round((y1 - y0) * scale)), Image.Resampling.LANCZOS)
        x, y = round(SIZE[0] / 2 - (center - x0) * scale), BASELINE - crop.height
        assert x >= 12 and y >= 35 and x + crop.width <= SIZE[0] - 12, (path, box, x, y, crop.size)
        frame = Image.new('RGBA', SIZE)
        frame.alpha_composite(crop, (x, y))
        frames.append(frame)
    return frames, {'source_sha256': digest(path), 'bounds': boxes, 'uniform_scale': scale, 'lower_shell_widths': widths}


def strip(frames, path):
    canvas = Image.new('RGBA', (SIZE[0] * len(frames), SIZE[1]))
    for i, frame in enumerate(frames):
        canvas.alpha_composite(frame, (SIZE[0] * i, 0))
    canvas.save(path)
    return digest(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--production', type=Path, required=True)
    parser.add_argument('--approved', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    previews = args.production / 'previews'
    previews.mkdir(exist_ok=True)
    catalog = json.loads((args.production / 'catalog.json').read_text())
    shared = {state: [Image.open(args.approved / 'frames' / f'{state}-{i:02}.png').convert('RGBA') for i in range(1, 7)] for state in ['waking', 'cracking']}
    receipt = {'canvas': SIZE, 'baseline': BASELINE, 'approved_preview_sha256': digest(args.approved / 'previews/egg-waking-cracking-hatching.gif'), 'characters': {}}
    receipt['waking_sha256'] = strip(shared['waking'], args.output / 'EggWakingStrip.png')
    receipt['cracking_sha256'] = strip(shared['cracking'], args.output / 'EggCrackingStrip.png')
    final_sheet = Image.new('RGB', (7 * 200, 5 * 230), BG)
    all_frames = []
    for index, character in enumerate(catalog):
        kind = character['id']
        folder = args.production / kind
        record, frames = {}, {}
        if kind != 'lavender' and not all((folder / f'{s}-magenta.png').exists() for s in ['hatching', 'reveal']):
            assert args.partial, f'Missing generated source for {kind}'
            continue
        for state in ['hatching', 'reveal']:
            if kind == 'lavender':
                frames[state] = [Image.open(args.approved / 'frames' / f'{state}-{i:02}.png').convert('RGBA') for i in range(1, 7)]
                record[state] = {'source_sha256': digest(args.approved / 'sources' / f'{state}-magenta.png'), 'approved_frames_preserved': True}
            else:
                frames[state], record[state] = extract(folder / f'{state}-magenta.png')
        frames['hatching'][0] = shared['cracking'][-1].copy()
        frames['reveal'][0] = frames['hatching'][-1].copy()
        poses = frames['hatching'] + frames['reveal']
        filename = f'EggHatch{kind.capitalize()}Strip.png'
        record.update(asset=filename, frames=12, reference_sha256=digest(folder / 'reference.png'), output_sha256=strip(poses, args.output / filename))
        receipt['characters'][kind] = record
        contact = Image.new('RGB', (6 * 256, 2 * 320), BG)
        for j, frame in enumerate(poses):
            thumb = frame.resize((256, 300), Image.Resampling.LANCZOS)
            contact.paste(thumb, ((j % 6) * 256, (j // 6) * 320), thumb)
        contact.save(previews / f'{kind}-sequence.png')
        final = poses[-1].resize((188, 220), Image.Resampling.LANCZOS)
        x, y = (index % 7) * 200, (index // 7) * 230
        final_sheet.paste(final, (x + 6, y), final)
        ImageDraw.Draw(final_sheet).text((x + 75, y + 210), kind, fill=(65, 48, 78))
        all_frames.append((index, shared['waking'] + shared['cracking'][1:] + frames['hatching'][1:] + frames['reveal'][1:]))
    final_sheet.save(previews / 'all-reveals.png')
    if len(all_frames) == len(catalog):
        gif = []
        durations = [1000,180,140,140,180,500,260,240,260,180,250,160,160,160,180,380,160,160,250,170,1600]
        for frame_index in range(21):
            scene = Image.new('RGB', (7 * 160, 5 * 190), BG)
            for index, frames in all_frames:
                im = frames[frame_index].resize((160, 188), Image.Resampling.LANCZOS)
                scene.paste(im, ((index % 7) * 160, (index // 7) * 190), im)
                ImageDraw.Draw(scene).text(((index % 7) * 160 + 65, (index // 7) * 190 + 177), catalog[index]['id'], fill=(65,48,78))
            gif.append(scene)
        gif[0].save(previews / 'all-dotlings-hatching.gif', save_all=True, append_images=gif[1:], duration=durations, loop=0, disposal=2)
    (args.production / 'verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'Exported {len(receipt["characters"])}/{len(catalog)} character reveals, plus the approved waking and cracking strips.')


if __name__ == '__main__':
    main()
