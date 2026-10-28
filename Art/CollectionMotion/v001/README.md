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

`Shared/DotlingAnimation.swift` selects the appropriate character strip. Tap to wave, double-tap to hop, rub to hold closed eyes with haptics, swipe horizontally to move sideways, or hold to choose any movement. The new set applies to animated happy companions; other mood portraits and their existing touch sequences remain in place. Active clips are decoded off the main thread before their playback clock starts. Reduce Motion uses a still frame, completed actions return to idle, and offscreen views stop playback and release their loaded frames.

`verification.json` records exact pixel matching between all 2,117 preview frames and the app strips, source hashes and pose counts for all 292 generated strips, transparent margins, and GIF decoding. Earlier audit logs retain the rejected spacing and border cases; the final verification refers to the selected corrected sources.

Generation completion, export and app verification are separate steps. Consult the manifests and check log for their actual status.

The release checkout contains the app strips, canonical references, prompts, generation receipts, manifests and processing scripts. Full source PNGs, extracted frames and GIF review masters are retained with this package on the external drive; the build and review commands above require those retained masters. The iOS build consumes only the bundled 2D strips and does not use Blender or a 3D model.
