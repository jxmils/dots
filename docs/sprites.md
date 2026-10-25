# Character artwork and playback

The app uses transparent 2D PNG sprites for all 29 companions, all six moods and all 12 egg stages.
Home, friend details, profile, collection, hatching and widgets share `CompanionArt` and `CompanionView`.
There is no live 3D character view or model resource in either target. App identifiers, saved names,
owned pets, mood choices, sharing, widgets, streak rewards and lifetime restores keep their existing format.

## Creating artwork

1. Start with the original identity reference. Generate one canonical, front-facing character.
2. Attach that approved character to every later generation. Make one horizontal strip per action or
   expression, with complete separated silhouettes. A spacing guide is a reference, never visible artwork.
3. Preserve the body shape, fine short fuzz, attached arms, eye construction, cheeks and closed smile.
   Do not add feet, talking mouths, particles, props, hearts or stars to touch reactions.
4. Retain the original outputs, exact prompts and reference paths. Remove the flat magenta background,
   clean its edge fringe, extract whole poses, then register one shared scale and ground baseline.
   Do not independently stretch frames. Keep intentional vertical motion only for an explicit jump.
5. Export full-color RGBA PNGs. GIF and video files are previews. Inspect the result on light and dark
   backgrounds, then at actual phone and widget sizes before replacing the bundled PNG.

The prompt and attached reference establish identity together; text alone cannot reproduce identical pixels.
`Art/Dusk/SpriteTrial/` retains Dusk's source artwork, prompts, spacing guide, extracted frames, hashes
and processing measurements. Rebuild and install that selected strip with Python, Pillow and NumPy:

```sh
python3 Tools/artwork/prepare-dusk-trial.py --install
```

`Resources/CompanionDuskBlink.png` is six 512 × 512 cells in one horizontal row. It supplies Dusk's happy
rest and touch response. Dusk's other five moods keep their existing mood and touch art; this migration
does not claim new strips have been generated for all moods or pets. All other current atlases use
three columns and two rows. `CompanionArt` accepts column/row counts, and registered crop layouts keep
the original touch and egg sources aligned. Add each new strip to both targets and keep the same static
rest frame in the app and widgets. Widgets display still images.

## Interaction

`SpritePlayback` samples elapsed time and blends registered drawings at up to 60 display updates per
second. This smooths transitions; it does not create 60 distinct drawn frames per second. The character
geometry is never warped or scaled during touch. Dusk's new strip plays one blink on tap and gently
closes its eyes on rubbing, holding that pose until release. The remaining companions retain their
existing illustrated reactions. Soft haptics accompany strokes and taps. No reaction captions or
floating icons are added.

Release blends from the currently visible pose to the selected mood. Rapid touches start from the
current blend. Gesture cancellation, backgrounding, mood/companion changes and disappearance clear the
touch state. Reduce Motion uses the still rest frame for the new Dusk strip and a short response for
the existing packs. Hatching keeps its illustrated warming, cracking and reveal sequence with haptics.

## Checks and delivery

Run `bash Tools/check.sh`. It checks the app/widget source and resource lists, type-checks both targets,
exercises persistence, rewards, hatching and sprite playback, inspects all mood/touch and egg frames,
and renders the actual SwiftUI screens and widget layouts. `Tools/check-sprite-build.py` fails if a
target includes a retired 3D model or renderer, omits an active source/sprite, or bundles a Dusk strip
different from its retained export. The same checks run before the GitHub TestFlight upload job.

Local checks do not prove physical-device haptics or perceived animation smoothness. Confirm those
with the signed TestFlight build. Native iPhone screenshots run in the separate store-capture workflow,
which also triggers when sprite resources change.

## Preserved 3D experiments

The unshipped 3D prototype source, models, generators and comparison renders are preserved separately
on the external drive at `/Volumes/new one/Apple Apps/Dotlings/Archive3D-2026-10-25` with a SHA256
manifest. The earlier approved Sky reference and reconstruction recipe remain in `Art/Sky/` as
historical source artwork. Neither archive is compiled into the app or widget.
