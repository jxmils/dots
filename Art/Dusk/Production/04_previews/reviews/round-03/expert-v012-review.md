# Expert review of v012

Source: existing chat `blender expert`, conversation `6ade6451-305c-8331-852f-70b36e9c082d`, message `37f31a0f-9101-4dcb-8bd6-713093542a1b`.

## Pixel and source inspection confirmed

I inspected:

- the matched v012 comparison;
- the native v012 render;
- the four-column v011 diagnostic comparison;
- the full pile-readable test;
- the independent reflection-card test;
- `build-v012.py`;
- both diagnostic scripts;
- Blender 5.1’s Cycles `sync_light()` implementation.

**v012 remains rejected.** It has a credible Dusk body now, but the face still reads as a smooth dark mascot with glossy black discs rather than the approved fuzzy, warm-eyed Dusk.

## First: your Cycles finding is correct

My earlier reasoning based on `Light.diffuse_factor` and `Light.specular_factor` was wrong for Blender 5.1 Cycles.

The Blender 5.1 `sync_light()` path copies light type, dimensions, colour, strength, normalisation, shadows, MIS, caustics, bounce count, and portal state. It does **not** transfer either diffuse or specular factors. Meanwhile, `build-v012.py` still assigns those ineffective properties. 

That explains v012’s enormous lower-inner grey eye reflections:

- `EYE_BASE_FILL` was not diffuse-only.
- The two supposed specular-only glint lights were not specular-only.
- All three contributed through paths we intended to disable.

Use the verified object ray-visibility controls from now on:

```python
eye_fill.visible_glossy = False
eye_fill.visible_transmission = False

reflection_card.visible_diffuse = False
reflection_card.visible_glossy = True
```

One reproducibility issue: the branch copies of both `build-v012.py` and `diagnose-catchlights-v011.py` that I inspected still contain the ignored factor assignments and do **not** yet contain the `visible_glossy` / `visible_diffuse` settings you describe. The rendered A/B supports your renderer conclusion, but the next retained builder and diagnostic should record those actual flags so the source reproduces the evidence exactly. 

# What actually matches now

These are close enough to freeze for the **next** iteration:

- Body width, height, and flattened baseline
- Camera, framing, and focal length
- Eye centres and spacing
- Eye aperture dimensions and vertical-oval outline
- Current shallow cap geometry and recessed eye bed
- Gross arm positions
- Gross tuft positions
- Cheek centres and approximate footprint
- Brow positions
- Closed-smile centreline
- Body lighting and charcoal base colour
- Undercoat architecture

That does not mean all are finally approved. It means none of them is causing the dominant mismatch in v012, and changing them now would obscure the next comparison.

The v012 body is slightly smoother and more geometrically perfect than the target, but the pile correction should alter that perception. Do not reshape the body, arms, or tufts in v013.

# What the pixels prove

## 1. The pile-readable test is considerably closer than v012

Yes: **combine the readable-pile result with the v012 body and facial geometry.**

In the four-column diagnostic, the third candidate immediately moves into the target’s material family. It reads as fur rather than velvet. The full diagnostic confirms that individual fibres survive at useful scale.

However, do **not** copy the whole diagnostic unchanged. It is somewhat too coarse and broadly swept:

- lower-body fibres become ropey;
- forehead direction is more organised than the reference;
- arms and tufts become slightly shaggy;
- some local flow resembles miniature locks rather than plush micro-clumps.

The diagnostic changed three things simultaneously:

```python
root radius *= 2.8
radius = root_radius * (1 - .85 * t**2)
direction = normalize(normal * .86 + tangent * .70)
```

The last expression corresponds to roughly a 39° tilt. v012 already uses a random 32–48° tilt and one-neighbour interpolation, so **obliquity is no longer v012’s main failure**. The missing variable is strand survival: radius and taper. 

In v012, pile roots are only `.00032–.00055`, and every strand uses:

```python
root_radius * (1 - .97 * t)
```

By the midpoint, the radius has already fallen to 51.5%; near the tip, almost the entire visible strand is subpixel. The test’s quadratic taper retains most of the width through the body of the strand.

## 2. The reflection-card test is much better than v012’s lights

The independent reflection-card result gives:

- approximately matching catchlight size;
- approximately matching catchlight intensity;
- no giant grey eye patch;
- much better left/right symmetry.

It proves the eye cap can support a coherent highlight. The cap geometry itself no longer needs rebuilding.

It is not final because:

- the glints remain a little too central;
- the eyes underneath remain predominantly black;
- the brown iris structure is still too faint;
- the reference glints sit more deliberately in the upper-right quadrant.

The diagnostic selects an upper-right surface point and computes the reflected light direction from the true lens normal. That is the correct physical method when using reflection cards. 

## 3. v012’s eye colour remains structurally under-authored

There is another source-level issue: `build-v012.py` creates an `EyeColor` point attribute for each eye, but the material does not consume it. The material is still driven by the earlier Generated-coordinate node network. The explicit per-vertex iris/pupil calculation is therefore dead data. 

That is why the source appears to contain a richer pupil/iris definition, while the rendered eyes remain broad dark gradients.

# The decisive v013 changes

## 1. Use an explicit eye-tone attribute and authored 3D catchlights

I recommend the deliberate stylised solution now.

The target is not asking for optically rigorous product photography. It has deliberately placed, repeatable, emotionally useful highlights. A tiny editable 3D highlight patch is the most reliable way to reproduce that while remaining honest about the construction.

### Remove the current glint lights

Delete:

```python
EYE_GLINT_L
EYE_GLINT_R
```

Retain one broad eye fill only, and make its actual Cycles behaviour diffuse-only through ray visibility:

```python
eye_fill = light(
    'EYE_BASE_FILL',
    (0, -4, 2.2),
    45,          # lower than v012's 70
    4.5,
    receiver=eye_receivers,
    target=(0, 0, EYE_Z),
)

eye_fill.visible_glossy = False
eye_fill.visible_transmission = False
```

The exact energy may need a small A/B, but the critical correction is the ray visibility—not the old factor fields.

### Convert `EyeColor` into the actual material input

Replace the Generated-coordinate eye-colour network with a named attribute:

```python
eye_tone = en.new('ShaderNodeAttribute')
eye_tone.attribute_name = 'EyeTone'

el.new(eye_tone.outputs['Color'], eye_shader.inputs['Base Color'])
el.new(eye_tone.outputs['Color'], eye_shader.inputs['Emission Color'])

eye_shader.inputs['Emission Strength'].default_value = .025
eye_shader.inputs['Specular IOR Level'].default_value = .22
eye_shader.inputs['Coat Weight'].default_value = .20
eye_shader.inputs['Coat Roughness'].default_value = .16
```

The low emission is not intended to make the eye glow. It prevents the warm iris from disappearing when the eye is predominantly glossy and very dark.

For each front-cap vertex, calculate a soft pupil, iris, and outer rim:

```python
def ss(a, b, x):
    q = max(0.0, min(1.0, (x-a)/(b-a)))
    return q*q*(3.0-2.0*q)

dx = (vertex.co.x - x) / rx
dz = (vertex.co.z - z) / rz
r = math.hypot(dx, dz)

pupil = 1.0 - ss(.40, .51, r)
rim = ss(.83, .97, r)

# More warmth toward the bottom, but some dark brown remains around the pupil.
lower = ss(-.20, .85, -dz)

iris_dark = (.018, .0045, .0015)
iris_warm = (.085, .0220, .0060)
pupil_colour = (.0010, .0003, .0002)
rim_colour = (.0035, .0009, .0004)

iris_colour = tuple(
    iris_dark[i] * (1.0 - (.22 + .78*lower))
    + iris_warm[i] * (.22 + .78*lower)
    for i in range(3)
)

colour = tuple(
    iris_colour[i] * (1.0-pupil)
    + pupil_colour[i] * pupil
    for i in range(3)
)

colour = tuple(
    colour[i] * (1.0-rim)
    + rim_colour[i] * rim
    for i in range(3)
)
```

This gives:

- a real near-black pupil;
- dark brown iris around it;
- warmer lower iris;
- dark outer boundary;
- no hard painted iris ring.

The warm maximum should be tested at `.075`, `.085`, and `.095` in a face-only crop if necessary. My preferred starting point is `.085`; v007’s orange problem came from its bright reflections and broad amber field, not merely from having visible brown.

### Add a real 3D highlight patch

Use the same normalised eye coordinate for both eyes:

```python
u = .30    # screen-right within each eye
v = .48    # upper portion
```

Find the corresponding front-cap vertex and create a tiny flattened sphere aligned to its surface normal:

```python
target_x = cx + EYE_RX * u
target_z = EYE_Z + EYE_RZ * v

front_vertices = eye.data.vertices[:1 + lens_rows*lens_cols]
vertex = min(
    front_vertices,
    key=lambda q:
        ((q.co.x-target_x)/EYE_RX)**2
        + ((q.co.z-target_z)/EYE_RZ)**2
)

p = vertex.co.copy()
normal = vertex.normal.normalized()

bpy.ops.mesh.primitive_uv_sphere_add(
    segments=32,
    ring_count=16,
    radius=1,
    location=p + normal * .005,
)

highlight = bpy.context.object
highlight.name = 'EYE_HIGHLIGHT_' + label
highlight.rotation_mode = 'QUATERNION'
highlight.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(normal)
highlight.scale = (.016, .016, .004)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

highlight.data.materials.append(catchlight_mat)
highlight.visible_shadow = False
bind(highlight)
```

Use a white or very slightly warm-white emissive material:

```python
catchlight_mat = material(
    'MAT_AUTHORED_EYE_HIGHLIGHT',
    (.92, .92, .90),
    .22,
)

shader = catchlight_mat.node_tree.nodes['Principled BSDF']
shader.inputs['Emission Color'].default_value = (1, 1, .98, 1)
shader.inputs['Emission Strength'].default_value = .65
shader.inputs['Specular IOR Level'].default_value = .10
```

This is:

- real editable geometry;
- attached to the eye surface;
- not an image texture;
- not a camera-facing bitmap;
- stable across both eyes;
- stable through a modest body turn.

Document it explicitly as a **stylised authored catchlight**, just as animated films commonly author eye highlights for expression and continuity.

### Physical-reflection alternative

The reflection-card test is a viable fallback. To refine it:

- target normalised location `u=.34`, `v=.50`;
- reduce disk size from `.35` to about `.24–.27`;
- compute the reflected ray exactly as the diagnostic does;
- set `card.visible_diffuse = False`;
- set the base fill’s `visible_glossy = False`.

But I recommend the authored geometry because it gives exact matching placement without another cycle of light-normal tuning.

## 2. Keep v012’s groom architecture, but adopt the diagnostic width survival

Do not revert to the whole v011 diagnostic groom. Keep:

- two layers;
- v012 undercoat;
- one-neighbour pile interpolation;
- macro/micro tangent field;
- noise-modulated pile density;
- current eye and mouth masks;
- 26,000 body-pile fibres;
- 2,800 body-pile guides.

Change the pile only.

### Use moderately thick roots

Instead of:

```python
root_radius = rng.uniform(.00032, .00055)
```

use:

```python
root_radius = rng.uniform(.00078, .00125)
```

This is roughly a 2.3–2.4× increase, rather than the diagnostic’s full 2.8×. Based on the A/B pixels:

- 1× is clearly invisible;
- 2.8× is the first confidently readable result;
- 2.3–2.4× should preserve readability while reducing the diagnostic’s coarse, woolly quality.

### Use the diagnostic’s quadratic taper

For pile:

```python
radius_factor = 1.0 - .85 * t*t
```

For undercoat, retain the existing fine taper:

```python
radius_factor = 1.0 - .97 * t
```

Thus:

```python
if layer == 'pile':
    radius_factor = 1.0 - .85*t*t
else:
    radius_factor = 1.0 - .97*t

radii.append(root_radius * radius_factor)
```

This is at least as important as the root multiplier. It keeps most of each visible fibre wide enough to survive downsampling.

### Do not make the pile more oblique

The v012 range already brackets the successful diagnostic angle. Narrow it slightly for consistency:

```python
tilt = math.radians(rng.uniform(36, 44))
```

Do not increase beyond that. The diagnostic’s `.70` tangent coefficient is about 39°, right in this interval.

### Shorten v012’s pile slightly before thickening it

V012’s current lengths plus the new width would likely become too shaggy. Use:

```text
Face:       .021–.031
Other body: .024–.037
Tufts:      .030–.044
```

For example:

```python
if surface.name.startswith('TUFT_'):
    interval = (.030, .044)
elif face_region:
    interval = (.021, .031)
else:
    interval = (.024, .037)
```

Use:

```python
bend = rng.uniform(.06, .14) * rng.choice([-1, 1])
```

The diagnostic’s `.10–.22` bend contributes to the broad woolly sweeps visible on its forehead and lower body.

### Reduce bright-tip exaggeration

V012 currently allows pile tips up to `1.18×` the coat colour. On thicker fibres that will become conspicuously grey.

Use:

```python
color_variation = rng.uniform(.95, 1.05)
root_color = rng.uniform(.91, .98)
tip_color = rng.uniform(1.04, 1.10)
```

The fibres should be visible because of width, local orientation, and specular response—not because their tips are pale.

## 3. Leave the new facial geometry alone for this pass

The v012 inset smile is much better than the old tube. In the matched comparison it now reads as a closed smile, not a plastic cord. It is a little too thin and dark compared with the reference, but changing the pile will materially alter how much of it remains visible.

For v013:

- keep the current ribbon dimensions;
- keep the current mouth channel;
- keep brow geometry and position;
- keep blush geometry and colour.

After the thicker pile is applied:

- if the smile disappears, increase its half-width by only 10–15%;
- if brows become buried, raise their centre by `.005` rather than making them thicker;
- do not change either pre-emptively.

# Image-specific conclusion

## v012 itself

The main visible failures are:

- huge lower-inner grey eye reflections;
- eyes that remain too black outside those reflections;
- almost no readable iris/pupil organisation;
- fur that resolves into thin antialiased wisps rather than plush fibres;
- a smooth geometric forehead and cheeks;
- eye rims that are cleaner than the target because surrounding pile remains too fine.

## Pile-readable A/B

This is **the closest coat so far**. It proves that thicker fibres with a slow taper are necessary. It is slightly too coarse and directional, so carry over its width logic—not its entire direction/bend modification.

## Reflection-card A/B

This is **the closest catchlight behaviour so far**. It proves that the eye cap geometry can produce matching reflections. It still leaves the interior too black and the dots slightly too central. Authored 3D highlight geometry is the more direct final solution.

# Freeze list for v013

Freeze:

- shell geometry;
- camera;
- eye positions;
- eye aperture and cap geometry;
- recessed eye beds;
- arms and tufts;
- cheeks;
- brows;
- smile geometry;
- undercoat;
- body lighting.

Change only:

1. renderer-correct eye fill and removal of ineffective glint lights;
2. explicit iris/pupil attribute plus authored 3D highlight geometry;
3. pile radius, taper, modestly reduced length, and tip colour.

## v013 gates

Do not accept v013 unless, at matched 512 px scale:

- both catchlights occupy the same upper-right relative position;
- no grey fill reflection covers a large eye region;
- pupil, dark iris, and warm lower iris are all distinguishable;
- eye highlights remain small and round;
- individual body fibres remain visible after downscaling;
- the coat forms fine local clumps rather than long locks or uniform velvet;
- the body remains dark charcoal rather than becoming silver-grey;
- the smile and brows remain legible without appearing attached on top.

**The body identity is now close enough to hold still. The decisive remaining work is optical authorship and fibre survival.**

