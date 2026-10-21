# Sky's approved neutral look

This is the version approved for preservation on 21 October 2026. Keep its
rounded sides, gently flattened base, very short fuzzy coat, small tucked curl,
brown eyes, pink cheeks and closed smile.

The accepted look uses the supplied artwork as a fixed texture on a shaped 3D
relief surface. No new image-generation prompt was used for this version.
`reference.png` is the original input, kept unchanged. It contains the supplied
six-expression atlas; the neutral model uses its first character.

## Rebuild

From the repository root, with Blender 5.1.0 installed:

```sh
bash Tools/rebuild-sky.sh
```

This writes `build/sky-model/Sky.blend`, `Sky.png` and `look-check.json`. Pass a
different output directory as the first argument, or set `BLENDER_BIN` to choose
the Blender executable. The default output stays inside this checkout on the
external drive. Blender includes the Python and NumPy used by the builder.

The command verifies the approved input hashes, rebuilds the surface and its
material, packs the original texture into the new model, and compares the render
with `approved-neutral.png`. A changed input, Blender version or mismatched render
fails the check. Builds cannot overwrite this source directory.

The comparison checks visible color and alpha separately, allowing at most two
8-bit color levels and one alpha level for render rounding. RGB values in fully
transparent pixels are excluded because they do not affect the displayed image.

## Source files

| File | Purpose |
| --- | --- |
| `approved-source.blend` | Complete preserved Blender scene from the approved preview, including its packed texture and earlier hidden modeling objects. |
| `approved-neutral.png` | Approved visual baseline. |
| `reference.png` | Original supplied artwork, with no regeneration or image edits. |
| `depth.json` | Exact depth samples of the accepted 129 × 129 relief surface. |
| `look.json` | Camera, projection, material, alpha, color and render settings, input hashes and appearance constraints. |
| `../../Tools/rebuild-sky.py` | Self-contained reconstruction script. |

The builder reads these checked-in inputs. It does not depend on temporary files,
the external artwork workspace, the earlier experimental generators, a network
service or another image-generation run.

## Facial work

This freezes the approved front view. It is not a finished character from every
angle. The neutral eyes, eyebrows and smile are currently painted into the fixed
texture; separating and rigging them remains unfinished work.

Keep the mouth closed and fixed. Future expressions should use the eyes, eyelids
and eyebrows while preserving this neutral appearance, silhouette and coat.
Keep this baseline intact when developing the rig. Native app integration and
TestFlight delivery have not been performed for this model.
