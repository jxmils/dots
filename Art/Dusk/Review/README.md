# Dusk look review

Artwork-only review branch for Jason and the existing **blender expert** chat,
`6ade6451-305c-8331-852f-70b36e9c082d`. The shipping app and TestFlight assets are unchanged.

`reference.png` is the approved target. All numbered Blender studies remain
unapproved. The current submitted study is **v029**, combining a packed fur-only
material, short native Hair Curves, transferred diffuse normals, layered eyes and
an authored closed smile. The expert's latest completed review rejected v029 as a faithful close match,
while calling it very close. Finer lifted fur and richer eye optics remain required.

- `comparison-v029.png`: target left, actual Blender render right.
- `study-v029.png`: untouched actual 1536-square RGBA render.
- `detail-v029.png`: actual full-pixel detail.
- `build-v029.py`: exact source snapshot, originally at `Tools/artwork/build-dusk-rig.py`.
- `quarter-v029.png`: actual 25-degree rig turn, no generated side picture.

Comparisons use white and equal visible character width/bottom baseline. Source
renders are included separately. Layout/cropping does not redraw the character.
The single fur-material tile is a surface sample containing no face or character;
the body, facial parts, arms, tufts, controls and deformations are actual 3D geometry.
Restore a source snapshot to its original Tools/artwork path in an isolated checkout
before rebuilding an old version. Current model/rebuild instructions are in
`../Production/README.md`.
