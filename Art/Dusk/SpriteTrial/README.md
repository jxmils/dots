# Dusk sprite workflow trial

This retains the user's supplied prompt workflow applied to Dusk, the black Dotling. The app now uses 2D sprites throughout. This strip supplies Dusk's happy resting pose and gentle tap/rub reaction. Other moods and the other 28 pets retain their existing 2D mood and touch atlases.

- `canonical.png`: clean transparent base, with a closed smile.
- `idle-preview.gif`: opaque preview on cream; six timed poses.
- `idle.png`: transparent 3072 × 512 atlas, six 512 × 512 cells.
- `idle-01.png` through `idle-06.png`: individual full-color transparent frames.
- `canonical-magenta.png` and `idle-magenta.png`: unchanged image-generation outputs.
- `canonical-prompt.txt` and `idle-prompt.txt`: exact adapted prompts sent to the built-in image generator.
- `idle-spacing-guide.png`: code-created spacing reference, not part of the artwork.
- `processing.json`: source dimensions, crop bounds, uniform scale, frame order and timing.
- `quality-check.json`: transparency and silhouette consistency measurements.

Both generation calls used `Resources/CompanionDuskAtlas.png` as an identity reference. The idle call also used the saved canonical base and the six-slot guide. The supplied pack's references to ChatGPT pets were adapted to the Dotlings app; its dark-eye, three-tuft, two-arm, closed-mouth and no-leg constraints were preserved. Body movement was kept minimal.

The model returned six complete poses with narrower gaps than requested. The fifth source pose reopened the eyes too far, so the export reuses the third half-lid pose for reopening. The selected cycle is source frames 1, 2, 3, 4, 3, 6. This is documented instead of presenting the generated sequence as exact compliance with the prompt.

The requested local processing removes the magenta background, recovers contaminated edge colors, extracts whole poses and aligns them with one shared scale and baseline. It does not redraw the character. Originals are retained. Rebuild with Python, Pillow and NumPy:

```sh
python3 Tools/artwork/prepare-dusk-trial.py --install
```

The idle source is 2172 × 724; each character is about 344–347 pixels wide. The larger export dimensions do not add generated detail. The GIF is only a preview. PNGs remain the source assets.

Only the base and blink sequence have been generated in this pack. There is no new walking, jumping or mood strip here. In the app, rubbing holds the closed-eye drawing until release; tapping plays one gentle blink. The preview GIF's idle timing is not the app's touch timing. See [the active sprite workflow](../../../docs/sprites.md) for runtime behavior and validation.
