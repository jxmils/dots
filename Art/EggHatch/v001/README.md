# Approved plush egg hatching

Approved on 18 November 2026. The user approved the complete waking, cracking,
hatching and reveal GIF, then requested integration for whichever Dotling is
awarded and a TestFlight build. This replaces the previous runtime egg artwork.

## Art and production method

The egg is creamy ivory with a lilac base, three lilac spots on its cap, extremely
short plush fur, rosy cheeks and a small closed smile. The lower shell becomes
a sleeping-face cup. The cap tips back as the actual awarded creature rises,
rests in the cup and blinks. There are no haptics, particles or added feet.

The approved Lavender sequence is preserved pixel for pixel. Each of the other
28 characters has two separately generated six-pose strips: hatching and reveal.
Each generation uses the corresponding approved egg strip and the character's
canonical idle frame. Only the creature inside the egg is replaced. Original
shapes, materials and features are retained, including leaves, cloud lobes,
the coconut crown, bowling dimples and the coffee bean crease.

This is generated 2D sprite playback. It is not a Blender render or a live 3D rig.
The prompts and references define the production method, but another image
generation call is not guaranteed to return identical pixels. Preserve the
selected original strips for deterministic re-export.

Original generated strips, references, exact prompts, inspection sheets and GIFs:

`/Volumes/new one/Apple Apps/Dotlings/Releases/egg-integration-20261118`

Approved original preview and its source art:

`/Volumes/new one/Apple Apps/Dotlings/Releases/egg-preview-20261118/v001`

`provenance.json` records the selected calls and their reference files.
`verification.json` records input/output hashes, crop bounds and uniform scales.

## Export

Use `Tools/artwork/build-egg-strips.py` with Pillow and numpy. Supply the production
folder with `--production`, approved preview folder with `--approved`, and
`Resources` with `--output`. Then run `ruby Tools/artwork/register-egg-art.rb`.

The exporter removes flat magenta and its edge fringe, extracts six separate
complete poses, and aligns the lower shell to a common baseline. It uses one
uniform scale per source strip. It does not stretch individual poses, redraw
features, synthesize in-between images or use optical flow. Clip joins share
exact anchor pixels. Each transparent frame is 512 by 600 pixels, with baseline
474. There are two shared six-frame strips and 29 twelve-frame character strips.

## Runtime

The warming gesture and three taps remain accessible through VoiceOver actions.
The third crack saves the awarded, previously unowned creature before playback.
That exact kind chooses the twelve-frame reveal strip and the final naming
portrait; there is no default Lavender reveal for other kinds. The frame loader
decodes the sequence off the main thread before opening and retains the frames
through the animation. Only one pre-drawn image is shown at a time.

`EggStage.ceremony` keeps the approved pose timings. Repeated taps during the
ceremony cannot consume another egg. Leaving the active scene completes the
already-saved award. Reduce Motion skips the rocking and rising poses. Default
names, custom naming and the choice to keep the current profile Dotling remain.

## Checks

`Tools/check.sh` checks the app and widget, reward behavior, every character's
24-frame sequence, transparent corners, visible artwork, unique reveals and
exact clip joins. `Tools/check-sprite-build.py` checks resource membership and
the retained export hashes. The normal local check also renders SwiftUI screens.
With `DOTLINGS_CAPTURE_HATCH=1`, it additionally exports `hatching-in-app.gif`
through the actual `EggArtwork` view for Lavender, Dusk, Bonsai and Coconut.

Physical touch feel and VoiceOver navigation still require device acceptance.
