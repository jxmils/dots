# Expert review of v027

Source: existing chat `blender expert`, conversation `6ade6451-305c-8331-852f-70b36e9c082d`, message `3aebe228-2beb-4f96-bf0c-27c899c9f742`.

**Reject both.** **v027 is visually closer overall**: its value, softness, silhouette, and face read more like Dusk at app size. v020 has more convincing physical fibres but is too dark and clumpy; v021 is clearly over-dense and matted. The v027 quarter turn proves the mapping is stable, but also exposes the remaining problem: the coat stays attached like embossed/printed felt instead of showing changing fibre parallax and highlights.

1. **Use v027 as the undercoat, not the finished coat.** Keep its fur tile for low-frequency colour/roughness, but reduce bump from `.35/.006` to roughly `.15/.0025`. Overlay a **v020-density** real pile—approximately 60–90k fibres, not v021’s 250k—with v027’s shorter lengths. This gives genuine silhouette breakup without returning to wool.

2. **Yes, transferred skin normals are the right next test.** Sample the evaluated deformed surface normal after `Deform Curves on Surface`, store it per curve point, and use approximately **65–70% skin normal / 30–35% curve normal** for the Principled-plush branch. Keep the real curve normal for the small Hair/specular branch. Applying 75% skin normal to the entire shader would risk flattening the strands again; splitting diffuse and directional response is the sound version.

3. **Integrate the face into the pile.** v027’s eyes and cheeks still look placed onto a felt surface: eye rims are too clean, blush is bright and radially streaked, and the lower iris is slightly less luminous than the target. Let the restored real pile overlap the eye boundary by a few pixels with a smooth density ramp, reduce blush peak intensity about 10%, and lift only the lower-eye brown—not the whole eye.

The final direction is therefore **v027 textured undercoat + moderate real pile + transferred diffuse normals**, not pure texture and not dense native curves. The remaining sweetness gap is surface integration, not gross geometry.

