"""Verify the exact frames consumed by the app and the delivered previews."""
from build import P, ROOT, TIMES, NAMES
from PIL import Image
from io import BytesIO
import json, hashlib

catalog = json.loads((P / 'catalog.json').read_text())
frames_checked = 0
gifs_checked = 0
sources_checked = 0
for character in catalog:
    directory = P / character['id']
    manifest = json.loads((directory / 'manifest.json').read_text())
    assert manifest['complete'] and manifest['frames'] == 73
    if character['id'] != 'dusk':
        for state, metadata in manifest['metadata'].items():
            source = directory / f'{state}-source.png'
            assert hashlib.sha256(source.read_bytes()).hexdigest() == metadata['source_sha256'], (source, 'export is stale')
            expected = 8 if state.startswith('look-') else len(TIMES[state])
            assert len(metadata['bounds']) == expected, (source, 'incomplete pose extraction')
            sources_checked += 1
    for state, durations in TIMES.items():
        asset = ROOT / 'Resources' / f'Companion{character["id"].capitalize()}Motion{NAMES[state]}.png'
        strip = Image.open(BytesIO(asset.read_bytes())).convert('RGBA')
        assert strip.size == (384 * len(durations), 416), asset
        for index in range(len(durations)):
            frame = Image.open(BytesIO((directory / 'frames' / f'{state}-{index+1:02}.png').read_bytes())).convert('RGBA')
            assert frame.size == (384, 416)
            assert strip.crop((384*index, 0, 384*(index+1), 416)).tobytes() == frame.tobytes(), (asset, index)
            alpha = frame.getchannel('A')
            assert all(alpha.getpixel(point) == 0 for point in [(0,0), (383,0), (0,415), (383,415)])
            bounds = alpha.getbbox()
            assert bounds and bounds[0] > 0 and bounds[1] > 0 and bounds[2] < 384 and bounds[3] < 416
            frames_checked += 1
    for gif in list((directory / 'gifs').glob('*.gif')) + [directory / 'all-animations.gif']:
        image = Image.open(BytesIO(gif.read_bytes()))
        assert image.info.get('loop') == 0 and image.n_frames > 1, gif
        for index in range(image.n_frames):
            image.seek(index)
            image.load()
            assert image.info['duration'] > 0
        gifs_checked += 1
    print('Verified', character['name'], flush=True)
assert frames_checked == 2117
assert sources_checked == 292
result = {'passed': True, 'characters': 29, 'app_frames_pixel_matched_to_preview': frames_checked,
          'individual_preview_gifs_decoded': gifs_checked, 'transparent_corners': True,
          'complete_silhouettes_inside_canvas': True,
          'source_strips_counted_and_hash_matched': sources_checked}
(P / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result), flush=True)
