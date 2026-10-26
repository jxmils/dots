"""Publishable review layouts of actual Blender renders; no image repainting."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--revision', required=True)
args = parser.parse_args()
revision = args.revision
assert revision.startswith('v') and revision[1:].isdigit()
review = ROOT/'Art/Dusk/Review'
master = ROOT/f'Art/Dusk/Production/05_render_masters/style-{revision}-front.png'
reference = Image.open(review/'reference.png').convert('RGBA')
candidate = Image.open(master).convert('RGBA')
font_path = ROOT/'Brand/Fonts/Nunito-ExtraBold.ttf'
font = lambda size: ImageFont.truetype(str(font_path), size)

def bound(image):
    return image.getchannel('A').point(lambda x: 255 if x > 8 else 0).getbbox()

def registered(image, width=460, height=500):
    crop = image.crop(bound(image))
    factor = width/crop.width
    crop = crop.resize((width, round(crop.height*factor)), Image.Resampling.LANCZOS)
    result = Image.new('RGBA', (520, height))
    result.alpha_composite(crop, ((520-width)//2, height-20-crop.height))
    return result

comparison = Image.new('RGB', (1120, 620), 'white')
draw = ImageDraw.Draw(comparison)
for x, label, picture in [(20, 'Approved reference', reference), (580, f'Blender {revision} · unapproved', candidate)]:
    draw.text((x+30, 24), label, font=font(25), fill='#312f38')
    comparison.paste(registered(picture), (x, 80), registered(picture))
comparison.save(review/f'comparison-{revision}.png')

# Actual 100% candidate crop, with a separately labelled reference enlargement.
# The comparison above remains the authority for matched-width proportions.
box = bound(candidate)
face = candidate.crop((box[0]+round((box[2]-box[0])*.20),
                       box[1]+round((box[3]-box[1])*.35),
                       box[0]+round((box[2]-box[0])*.80),
                       box[1]+round((box[3]-box[1])*.80)))
detail = Image.new('RGB', (face.width, face.height+65), 'white')
ImageDraw.Draw(detail).text((15, 14), 'Actual render · 100% pixels', font=font(22), fill='#312f38')
detail.paste(face, (0, 65), face)
detail.save(review/f'detail-{revision}.png')
shutil.copy2(master, review/f'study-{revision}.png')
shutil.copy2(ROOT/'Tools/artwork/build-dusk-rig.py', review/f'build-{revision}.py')
shutil.copy2(ROOT/'Tools/artwork/build-dusk-rig.py', ROOT/f'Art/Dusk/Production/07_archive/build-dusk-rig-{revision}.py')
record = json.loads((review/'images.json').read_text())
record['latest_unapproved_study'] = f'study-{revision}.png'
record['sha256'].update({path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in review.glob(f'*-{revision}.*')})
(review/'images.json').write_text(json.dumps(record, indent=2)+'\n')
print(comparison.size, detail.size, master)
