# Dusk appearance prototype

This is an editable Blender character and a sequence of **unapproved look studies**.
The approved image is retained as the target. No study has been declared an exact match.
The shipping PNG app and TestFlight build 7 are unchanged. No animation Actions,
HEVC clips, runtime integration or iPhone performance qualification are claimed.

## Current study

- Editable master: `02_blender/dusk_rig_v028.blend`
- Exact builder snapshot: `../Review/build-v028.py`
- RGBA master: `05_render_masters/style-v028-front.png`
- Matched comparison: `../Review/comparison-v028.png`
- Full-pixel face/fur detail: `../Review/detail-v028.png`
- Structural receipt, when complete: `02_blender/dusk_rig_v028.checks.json`

Earlier masters and failed tests remain on the external drive. Immutable images and
source snapshots in `../Review` are published only on `art/dusk-look-review` for the
existing `blender expert` chat, conversation `6ade6451-305c-8331-852f-70b36e9c082d`.
Its actual image-specific critiques are retained under `04_previews/reviews/`.
The expert rejected v007, v010, v011, v012, v014, v017 and v027.
Its v027 review selected the combined textured-undercoat/native-pile direction,
which v028 implements. Its review of v028 is pending. It described v017's
material family as broadly correct while rejecting its proportions, coat and eyes.
That statement is a limited visual finding, not final approval.

## Construction

All visible character parts are real geometry. No reference portrait is projected
onto the model. The sole raster material is the packed fur-only swatch
`03_textures/charcoal-short-fur-v002.png`; it contains no face, body outline or character.
Its exact built-in image-generation prompt is retained in
`03_textures/charcoal-short-fur-v002.prompt.txt`, with inputs and SHA256 in the adjacent JSON.
Exact rebuilds use that retained PNG; rerunning a generative prompt need not give identical pixels. The image layouts are
simple registration/compositing of the untouched Blender renders.

The model has an authored closed body profile, two arms, three tufts, a fixed closed
smile, separate brows and eyelids, eight armature controls and seven facial properties.
The smile never opens. No speaking controls or tongue are present.

Eyes use a recessed, procedurally coloured iris behind a thin non-refracting clear
varnish and a feathered authored highlight patch. Highlights are explicitly stylized
editable 3D geometry, not claimed to be physical light reflections. Camera-ray tests
check that neutral highlights are visible and closed eyelids occlude them.

The short coat uses native Hair Curves, retained fixed-seed guides, native interpolation
and Deform Curves on Surface. Exact root UV coordinates are sampled after interpolation;
separate body-cap UV islands prevent attachment drift. Undercoat and visible pile are
separate layers. The visible pile combines evaluated skin-normal shading (67 percent)
with actual curve normals (33 percent) in its plush branch; the small Hair BSDF
branch retains the directional strand response. The tiled surface material supplies
dense undercoat detail and the native curves supply real fibers and fuzzy edges.
The latest study targets approximately 113,000 interpolated fibers
from 14,750 guides. The prototype uses mostly rough/sheened Principled shading with a
small Hair BSDF contribution, constant color along individual strands and disabled
fuzz shadow casting as an explicit art-direction choice. Eye and mouth masks keep the
face readable. These are appearance decisions, not physical-fur validation.

Cycles 5.1 ignores the Light diffuse/specular factor fields used in early studies.
The current eye fill uses actual object ray-visibility flags. Its glossy/reflection
separation must be preserved. Source evidence:
https://github.com/blender/blender/blob/v5.1.0/intern/cycles/blender/light.cpp

## Runtime and reproducibility

Actual authoring/rendering: **Blender 5.1.0**, build `adfe2921d5f3`, Apple Metal.
The intended production pin remains 5.2.3 LTS. Its isolated official Apple Silicon
installation was checksum-verified but hangs before startup on this Mac; it has not
been used successfully. Do not label these renders as 5.2.3 output.
Toolchains remain outside the repository under `../Toolchains` on the external drive.

The working builder refuses to overwrite an existing revision. It requires the exact
production version unless the explicit 5.1.0 trial flag is supplied. Example:

```sh
blender -b --python-exit-code 1 --python Tools/artwork/build-dusk-rig.py -- \
  --trial-blender-version 5.1.0 --revision v029 --look-review
blender -b Art/Dusk/Production/02_blender/dusk_rig_v029.blend \
  --python-exit-code 1 --python Tools/artwork/check-dusk-rig.py
python3 Tools/artwork/package-dusk-look-review.py --revision v029
```

Restore a selected immutable `../Review/build-vNNN.py` snapshot to
`Tools/artwork/build-dusk-rig.py` in an isolated checkout before rebuilding that study. The live
builder may contain later changes. All material choices and meaningful CLI settings
are recorded in the per-revision JSON receipt. The review render is 1536 square,
16-bit RGBA, 256 Cycles samples without denoising, fixed seed, fixed 90 mm camera.
Pillow is needed only for the review layout/export, not to create the 3D character.

## Check boundaries and next gate

`check-dusk-rig.py` verifies the closed body, required rig binding, facial-control
movement/return, fixed smile, highlight occlusion, evaluated fiber counts and sampled
root attachment under neutral and eight deterministic deformations. These checks do
not prove visual fidelity, temporal stability or playback performance.

The supplied production specification says: **Do not proceed to animation until this
image looks right.** That gate remains closed. After appearance acceptance, qualify
turns and deformation, author named Actions, render complete RGBA sequences, inspect
fur stability, encode transparent playback assets, and separately test iOS playback.
The generic poster, app-context and delivery files from v006 remain historical evidence
of a rejected study and must not be mistaken for current approved delivery assets.
