"""Deterministic chroma cleanup, extraction and registration from the supplied workflow.

The generated magenta originals remain unchanged. This does not redraw poses.
Run with Python, Pillow and NumPy from the repository root.
"""
from pathlib import Path
import json
import argparse
import shutil
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'Art/Dusk/SpriteTrial'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--install', action='store_true', help='Copy the finished blink strip into app resources')
args = parser.parse_args()


def extract(path, count):
    raw = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)
    r, g, b = raw.transpose(2, 0, 1)
    dominance = np.maximum(0, np.minimum(r, b) - g)
    background = (r > 150) & (b > 150) & (g < 110) & (dominance > 100)
    band = np.asarray(Image.fromarray(background.astype('uint8') * 255).filter(ImageFilter.MaxFilter(7))) > 0
    alpha = np.ones(r.shape, dtype=np.float32)
    alpha[background] = 0
    fringe = band & ~background & (dominance > 8)
    alpha[fringe] = np.clip(1 - dominance[fringe] / 255, 0, 1)
    # Recover foreground color from the known magenta matte at the edge.
    rgb = np.clip((raw - (1-alpha[..., None])*np.array([255, 0, 255])) / np.maximum(alpha[..., None], .01), 0, 255)
    rgb[alpha < .02] = 0
    alpha[alpha < .02] = 0
    rgba = Image.fromarray(np.dstack((rgb, alpha*255)).round().astype('uint8'))
    occupied = np.sum(alpha > .08, axis=0) > max(4, raw.shape[0] * .003)
    edges = np.diff(np.r_[False, occupied, False].astype('int8'))
    spans = list(zip(np.where(edges == 1)[0], np.where(edges == -1)[0]))
    spans = [(int(a), int(b)) for a, b in spans if b-a > raw.shape[1]/(count*3)]
    if len(spans) != count:
        raise RuntimeError(f'{path.name}: expected {count} complete poses, found {len(spans)}')
    poses = []
    boxes = []
    for a, b in spans:
        # Include faint fur just outside the substantial body columns.
        a=max(0,a-3); b=min(raw.shape[1],b+3)
        y, x = np.where(alpha[:,a:b] > .04)
        box = (a+int(x.min()), int(y.min()), a+int(x.max())+1, int(y.max())+1)
        boxes.append(box); poses.append(rgba.crop(box))
    return poses, boxes, list(Image.open(path).size)


base, base_boxes, base_size = extract(OUT/'canonical-magenta.png', 1)
poses, boxes, source_size = extract(OUT/'idle-magenta.png', 6)
scale = min(436/max(p.width for p in poses), 420/max(p.height for p in poses))
frames = []
# Pose 5 was fully open; reuse pose 3 to reopen through the same half-lid position.
order = [0, 1, 2, 3, 2, 5]
for index, source in enumerate(order):
    pose=poses[source]
    size=(round(pose.width*scale), round(pose.height*scale))
    pose=pose.resize(size, Image.Resampling.LANCZOS)
    frame=Image.new('RGBA', (512,512))
    frame.alpha_composite(pose, (round((512-pose.width)/2), 460-pose.height))
    frame.save(OUT/f'idle-{index+1:02}.png'); frames.append(frame)
base_pose=base[0]
base_scale=min(436/base_pose.width,420/base_pose.height)
base_pose=base_pose.resize((round(base_pose.width*base_scale),round(base_pose.height*base_scale)),Image.Resampling.LANCZOS)
canonical=Image.new('RGBA',(512,512))
canonical.alpha_composite(base_pose,(round((512-base_pose.width)/2),460-base_pose.height))
canonical.save(OUT/'canonical.png')
strip=Image.new('RGBA',(512*6,512))
for i,frame in enumerate(frames): strip.alpha_composite(frame,(i*512,0))
strip.save(OUT/'idle.png')

# GIF is an opaque preview only. Transparent full-color PNGs are the source assets.
cream=(249,245,238)
previews=[]
for frame in frames:
    preview=Image.new('RGB',frame.size,cream); preview.paste(frame,mask=frame.getchannel('A')); previews.append(preview)
palette_source=Image.new('RGB',(512*6,512),cream)
for i,p in enumerate(previews): palette_source.paste(p,(i*512,0))
palette=palette_source.quantize(colors=256)
gif=[p.quantize(palette=palette,dither=Image.Dither.NONE) for p in previews]
durations=[1000,300,90,150,90,700]
gif[0].save(OUT/'idle-preview.gif',save_all=True,append_images=gif[1:],duration=durations,loop=0,disposal=2)
report={'tool':'Built-in image generator; deterministic local postprocessing as requested',
        'canonical_source_size':base_size,'idle_source_size':source_size,
        'original_pose_bounds':boxes,'canonical_bounds':base_boxes,
        'source_frame_order_zero_based':order,'uniform_scale':scale,
        'export_frame_size':[512,512],'atlas_size':[3072,512],
        'baseline_y':460,'durations_ms':durations,
        'note':'Output dimensions do not imply extra generated detail. Original magenta files are retained.',
        'runtime_asset':'Resources/CompanionDuskBlink.png',
        'runtime_use':'Dusk happy rest and touch; other moods keep their original 2D atlases'}
(OUT/'processing.json').write_text(json.dumps(report,indent=2)+'\n')
if args.install:
    shutil.copy2(OUT/'idle.png', ROOT/'Resources/CompanionDuskBlink.png')
print(json.dumps(report,indent=2))
