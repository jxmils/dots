# Collection animation source

This package extends Dusk's approved 73-frame animation set to the other 28 Dotlings. Every character keeps its own reference silhouette, colour, close-fitting plush fur, eyes, crown and defining features. Mouths stay closed. These are generated 2D sprites with a rendered plush appearance, not animated 3D models.

`catalog.json` records the identities and original references. `jobs.json` records every generation prompt and its inputs. Each selected strip retains its original PNG and a generation receipt. Generation uses the built-in image generator, one horizontal strip per movement. Dusk reuses the retained `Art/Dusk/SpritePreview/complete-v001` frames unchanged.

The ten app states are idle/blink, move right, move left, wave, hop, disappointed, waiting, thinking, reviewing, and look around. Look around joins two eight-pose sequences. The four cardinal views are a separate preview extracted from that sequence, not extra app frames. Characters with asymmetric silhouettes or markings have separately generated left movements. Other left movements mirror each corresponding right frame without reversing the order.

## Build and review

With Pillow and NumPy installed:

```sh
python3 Art/CollectionMotion/v001/build.py --export-app --workers 4
ruby Art/CollectionMotion/v001/register_resources.rb
python3 Art/CollectionMotion/v001/gallery.py
python3 Art/CollectionMotion/v001/verify.py
bash Tools/check.sh build/check-collection-motion
```

The builder removes the sampled magenta background, keeps coloured interiors opaque, preserves complete silhouettes, applies one uniform scale within each sequence, aligns the resting baseline and retains the hop's vertical displacement. It never stretches the images or draws replacement artwork.

Each character receives transparent 384 × 416 frame files, ten app strips, individual movement GIFs, and a GIF showing its complete set. `preview.html` lets you select a movement and see all characters together, with pause and speed controls. `all-dotlings-all-animations.gif` shows the complete collection and `all-dotlings-<state>.gif` isolates a movement.

`Shared/DotlingAnimation.swift` selects the appropriate character strip. Tap to wave, double-tap to hop, rub to hold closed eyes with haptics, swipe horizontally to move sideways, or hold to choose any movement. The same ten movements and gestures are available in all six moods for every companion. A reaction temporarily shows the approved movement frames, then restores the selected mood portrait. Happy retains its quiet idle loop; the other moods keep their existing expression at rest. Blink from the menu is a single cycle. Changing mood or companion resets playback and cancels pending loads. These are shared movement clips, not six newly generated expression variants of every clip. Active clips are decoded off the main thread before their playback clock starts. Reduce Motion uses a still frame, completed actions return to the selected mood, and offscreen views stop playback and release their loaded frames.

`verification.json` records exact pixel matching between all 2,117 preview frames and the app strips, source hashes and pose counts for all 292 generated strips, transparent margins, and GIF decoding. Earlier audit logs retain the rejected spacing and border cases; the final verification refers to the selected corrected sources.

Generation completion, export and app verification are separate steps. Consult the manifests and check log for their actual status.

The release checkout contains the app strips, canonical references, prompts, generation receipts, manifests and processing scripts. Full source PNGs, extracted frames and GIF review masters are retained with this package on the external drive; the build and review commands above require those retained masters. The iOS build consumes only the bundled 2D strips and does not use Blender or a 3D model.

## Execution and release workflow

Keep this execution style for future updates:

1. Inspect the current app, artwork manifests and last release receipt before changing anything. Verify that `/Volumes/new one` is mounted with UUID `D08B27A7-BE4D-4C38-927F-516B04BAD4E7`. Keep source, generated assets, build output and Apple materials on that drive.
2. Preserve the approved 2D artwork and its provenance. Reuse complete registered frames and their established timings. Do not resume the retired 3D pipeline, stretch the character, add floating effects or introduce an open mouth. New art should go through the same reference-based strip generation, cleanup, registration and visual review described above.
3. Make focused changes in the shared sprite player so all 29 companions receive the same behavior. Decode strips off the main thread before playback. Keep haptics, accessibility actions, Reduce Motion, cancellation and offscreen cleanup intact. Mood changes must not retain another mood's pending animation.
4. Test the behavior being changed, including all six moods, every action, return to rest and Reduce Motion. Run `bash Tools/check.sh build/check-all-moods` for app/widget type checks, resource coverage, behavior and render checks. Review the rendered screens. If art changes, also rebuild the gallery and run the pixel/alpha/GIF verifier; code-only changes do not require regenerating approved art.
5. Package only the intended files against current `main`. Preserve unrelated local work and original artwork. Review the exact release diff and use the existing human Git identity. Do not include Apple credentials or certificates in Git.
6. When a TestFlight release is authorized, push the verified release to `main`. The existing **Build and upload Dotlings** workflow checks and archives the app and widget, chooses an unused build number, signs, uploads and waits for Apple processing using the configured secrets.
7. Follow that exact workflow run. An accepted upload is not completion: verify Apple reports `VALID`, record the version, build number, commit and run URL under `/Volumes/new one/Apple Apps/Dotlings/Releases/`, and report the result. If processing times out, inspect the uploaded build before retrying; never create duplicate builds just because a wait expired. TestFlight deployment does not authorize a public App Review submission.
8. Give concise progress updates about findings and remaining work. Ask only for genuinely missing information or a new visual approval; existing release authorization does not need to be requested again.


## Resting mood registration and touch polish

All displayed portraits now use `CompanionArt.displayImage`. Happy uses the exact first approved idle frame; other moods retain their existing artwork and receive one uniform fit into that frame's silhouette envelope, centered horizontally and aligned to its bottom baseline on the same 384 × 416 canvas. Transparent padding is preserved. Actions are not resized frame by frame, and no source artwork is redrawn. The same registered portrait is used before loading, at rest, after touch, in Reduce Motion, and for static cards/widgets. Regression checks compare all 174 portraits with their character's Happy anchor; rendered comparison sheets cover representative characters.

Haptics are prepared when the app becomes active and the interactive pet appears. A retained Core Haptics engine plays quiet selection taps, soft pet taps and short tactile rubbing pulses, with UIKit fallback if custom haptics are unavailable. Rubbing is rate-limited, backgrounding stops playback, and idle animation never vibrates. Mood choices, tabs, friend/profile navigation, collection selection and pinning have feedback. **Profile → Touch → Gentle haptics** defaults on and can turn feedback off. Engine restart and fallback follow [Apple's Core Haptics lifecycle guidance](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics). Compile/render tests cannot confirm tactile strength; that requires a physical iPhone.

The visual pass keeps the existing palette and character art, with a softer mood halo, lighter selection fills, restrained borders, closer hero spacing and opacity-only button press feedback. Streak information remains confined to Collection.
