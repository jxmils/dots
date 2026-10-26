# Expert review of v011

Source: existing chat `blender expert`, conversation `6ade6451-305c-8331-852f-70b36e9c082d`, message `b7d7ed74-fecd-4ac8-9b4c-ff130df3fd17`.

## Pixel access confirmed

**Yes. I inspected the actual pixels of the matched v011 comparison, the 1536 px render, and the 100% face/fur crop, then checked the corresponding geometry, groom, materials, and lights in `build-v011.py`.**

## Verdict

**v011 is a real improvement, but it remains rejected.**

The authored lens solved the accidental teardrop aperture. The body no longer feels frightening, the silhouette is close, and Dusk now reads as a gentle character. But the material identity is still wrong:

> **v011 looks like a smooth charcoal felt mascot with two black buttons.**

The reference looks like:

> **a densely fuzzy charcoal creature with deep, warm glass eyes.**

The remaining gap is no longer “the entire model is wrong.” It is now concentrated in three systems:

1. eye volume and illumination;
2. visible-pile scale and grouping;
3. integration of the brows and closed smile into the coat.

# What v011 successfully fixed

These parts are now sufficiently close to **freeze for v012**:

- **Camera, focal length, and framing**
- **Eye centre positions**
- **Body height, width, and flattened base**
- **Gross arm placement**
- **Gross tuft placement**
- **Blush mask position and approximate footprint**
- **The recessed eye-bed concept**
- **The authored closed-lens topology**
- **The fixed closed-mouth policy**
- **The body key/fill/rim/world-light values**
- **The current neutral pose**

“Freeze” here means do not change them in the next look-development pass. It does **not** mean final approval. The new groom will materially change the apparent size of the arms, tufts, cheeks, and silhouette, so those should only be reconsidered afterward.

The overall body value is also now dark enough. Do **not** darken the body again. Its problem is missing fibre separation, not insufficient blackness.

# Confirmed v011 problems

## 1. The eye outline is solved, but the eyes have become flat black buttons

The complete oval apertures are much better. There are no longer pointed lower corners or accidental body intersections.

However, the actual pixels show:

- viewer-left eye is almost completely dead black;
- viewer-right eye contains the only meaningful catchlight;
- the right glint is too central;
- there is a small peripheral specular streak;
- lower-eye brown is barely perceptible;
- the caps look flatter than the reference eyes;
- the eye shapes are a little too close to circles.

The target eyes have greater verticality, more soft internal brown, and enough curvature to feel glassy without looking mounted on the surface.

### The asymmetry has a specific source cause

The body lights are linked to the body receiver collection, while the eyes are assigned to a different eye receiver collection. The eyes therefore do not receive the body key or fill. They receive one dedicated eye light at global position `x=2.0`, with `diffuse=0`, so the light is both **off-axis** and **specular-only**. The helper also aims every light toward the body centre rather than aiming the eye light at an eye. 

This is why one eye receives the useful specular event and the other largely disappears. It is not primarily an eye-colour problem.

The source also currently uses a neutral upper-lid coverage seed of `.08`, rather than `.04`:

```python
coverage = .08 + (1 - .08) * closure
```

That is not the principal visible failure, so leave it unchanged for v012. 

## 2. Your projected-length diagnosis is correct

The visible pile currently uses:

```python
direction = (normal * .86 + tangent * .18).normalized()
```

That represents a tilt of only:

\[
\arctan(0.18/0.86) \approx 11.8^\circ .
\]

On the camera-facing region, only about:

\[
\sin(11.8^\circ) \approx 20\%
\]

of the strand’s physical length becomes an image-plane displacement. With the current facial pile length of `.018–.027`, the visible projected component is only approximately `.0037–.0055` scene units. That is why the fibres are barely more than a pixel or two in the native render and vanish after app-scale reduction.

So yes:

> **`.86 normal / .18 tangent` is too upright to reproduce the reference.**

The two-layer architecture was the right move, but the pile still behaves like the top nap of velvet rather than visible fuzzy fibres. The current two-neighbour interpolation and 40,000-fibre pile also fill the surface too continuously, smoothing out the intended micro-clumps. 

## 3. The smile and brows are still separate manufactured pieces

At comparison size, the smile becomes too thin. In the 100% crop, it reads as a raised crescent with a wedge-like cross-section.

The underlying causes are visible in the builder:

- it remains a circular beveled tube;
- it protrudes over the body;
- the fur has no dedicated mouth clearance mask;
- the pile partly masks its edges;
- the taper acts across the entire tube rather than creating a shallow inset line.

The brows have improved, but they remain too far above the eyes and their longitudinal taper makes them look like short wedges instead of soft plush capsules. The current source uses `.028` brow thickness, a strong endpoint taper, and a brow baseline that still leaves too much forehead gap. 

# v012: the next three corrections

## 1. Keep the eye cap, but add modest volume and localised eye lighting

Do not return to spheres. The authored cap is the correct architecture.

### Adjust the cap without changing its centre or area

Use:

```python
EYE_RX = .145
EYE_RZ = .166
EYE_BULGE = .034
EYE_RIM_OFFSET = .003
```

This preserves almost exactly the same frontal area as `.150 × .160`, but makes the eye more vertically oval. Increasing only the centre bulge from `.026` to `.034` adds glass volume while retaining the flush perimeter and recessed eye bed.

The crucial distinction is:

- **do not move the entire eye forward;**
- **increase only the cap curvature toward its centre.**

That creates volume without recreating mounted marbles.

### Give both eyes a broad, reflection-free base fill

Add one eye-only light linked to both eyes:

```python
light(
    'EYE_BASE_FILL',
    location=(0, -4.0, 2.2),
    energy=70,
    size=4.5,
    specular=0.0,
    diffuse=.75,
    receiver=eye_all_receivers,
    target=(0, 0, EYE_Z),
)
```

This is not a catchlight. Its job is to reveal the existing near-black-to-brown shader equally in both eyes.

Retain the current `.050, .016, .005` lower brown for this pass. Do not increase it simultaneously. It may already be sufficient once the eyes receive actual diffuse illumination. The current procedural eye colour is otherwise structurally reasonable. 

### Replace the single global glint light with one local light per eye

Create three eye receiver collections:

```python
eye_all_receivers
eye_L_receiver
eye_R_receiver
```

Link each eye to `eye_all_receivers` and its corresponding individual collection.

Modify the light helper so it accepts an explicit target:

```python
def light(name, location, energy, size, receiver, target,
          specular=0.0, diffuse=1.0):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.shape = 'DISK'
    data.size = size
    data.specular_factor = specular
    data.diffuse_factor = diffuse

    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.light_linking.receiver_collection = receiver
    obj.location = location
    obj.rotation_euler = (
        Vector(target) - obj.location
    ).to_track_quat('-Z', 'Y').to_euler()
    return obj
```

Then use matching local offsets:

```python
for side, label, receiver in [
    (-1, 'L', eye_L_receiver),
    ( 1, 'R', eye_R_receiver),
]:
    cx = side * EYE_X
    target = (cx, front(cx, EYE_Z), EYE_Z)

    light(
        f'EYE_GLINT_{label}',
        location=(cx + .12, -3.4, EYE_Z + .32),
        energy=120,
        size=.22,
        specular=1.0,
        diffuse=0.0,
        receiver=receiver,
        target=target,
    )
```

The same **local** `+.12` horizontal offset places both glints toward the same screen-space side of their respective eyes. Because each light is linked to only one eye, neither can create a second streak in the opposite eye.

This remains a genuine three-dimensional specular reflection. It is not a painted catchlight or 2D eye texture.

Remove the existing global `EYE_CATCHLIGHT`.

### Expected v012 eye result

- two matching small upper catchlights;
- no peripheral streak;
- equal brown visibility;
- slightly taller ovals;
- modest centre curvature;
- flush embedded rims.

## 2. Make the pile visibly oblique, sparser, and guide-clumped

Retain two layers, but stop making the visible pile nearly normal to the face.

### Undercoat

Its role is only to prevent visible holes:

```text
Body guides:       4,000
Body fibres:       85,000
Max neighbours:    4

Face length:       .007–.012
Other body:        .009–.015
Tufts:             .012–.020

Root radius:       .00018–.00030
Tilt:              3–10 degrees
```

Use an undercoat-specific material:

```text
Longitudinal roughness: .72
Radial roughness:       .76
```

Keep its colour close to or slightly darker than the shell.

### Visible pile

Use:

```text
Body guides:       2,800
Body fibres:       26,000
Max neighbours:    1

Face length:       .028–.040
Other body:        .030–.045
Tufts:             .035–.052

Root radius:       .00032–.00055
Tilt:              32–48 degrees
Bend:              .05–.15 × length
```

Generate tilt as an angle, not opaque coefficient ratios:

```python
tilt = math.radians(rng.uniform(32, 48))
direction = (
    normal * math.cos(tilt) +
    tangent * math.sin(tilt)
).normalized()
```

This changes the projected component from about 20% of strand length to approximately 53–74%. Combined with the slightly longer pile, it should create roughly four to six times the visible image-plane fibre length on the frontal face.

That is the scale correction the pixels require.

### Use one interpolation neighbour

Change:

```python
interpolate.inputs['Max Neighbors'].default_value = 2
```

to:

```python
interpolate.inputs['Max Neighbors'].default_value = 1
```

for the pile only.

With roughly nine children per guide, nearby fibres will inherit one common guide lean and form a small lock. Two-neighbour interpolation averages neighbouring shapes and recreates the uniform velvet field.

### Give pile and undercoat separate materials

The current code gives both layers the same Hair BSDF. That allows the dense undercoat to dominate the final material response. 

Use a pile-specific material:

```text
Longitudinal roughness: .48–.52
Radial roughness:       .62–.68
```

This should produce soft, narrow strand highlights without making the coat wet or silky.

### Increase meaningful colour variation

For undercoat:

```text
Per-cluster multiplier: .94–1.02
Root multiplier:        .92–.98
Tip multiplier:         .98–1.04
```

For pile:

```text
Per-cluster multiplier: .92–1.08
Root multiplier:        .88–.98
Tip multiplier:         1.08–1.18
```

The tip lift must remain dark charcoal; it should reveal fibres, not turn them grey.

### Make density variation larger in physical scale

The current pile density noise scale of `43` is too fine once the result is downscaled. Use approximately:

```python
density_noise = noise.noise(vertex.co * 26, ...)
multiplier = clamp(1 + .50 * density_noise, .50, 1.50)
```

The undercoat will hide true gaps, while the pile will form visibly denser and looser regions.

### Tighten the eye-fur transition

The present `.94 → 1.08` fade creates a broad, clean gasket around the eyes. Use:

```python
def eye_fur_density_fade(point):
    return smoothstep((eye_rho(point) - .97) / .07)  # full at 1.04

def eye_fur_length_factor(point):
    fade = smoothstep((eye_rho(point) - .98) / .06)
    return .55 + .45 * fade
```

Reject pile roots only inside approximately `.97`, not `.94`. Longer neighbouring fibres can then overlap the rim slightly, embedding the eyes in plush without obscuring the authored oval.

## 3. Replace the tube smile and lower/round the brows

### Smile: use an inset ribbon, not a round tube

Keep the current smile centreline, width, and closed expression. Replace the beveled tube with a shallow mesh strip that follows the body.

For each centreline point:

1. calculate its tangent in the `x–z` plane;
2. calculate the perpendicular screen-plane direction;
3. generate two vertices on either side;
4. place the strip only about `.003–.004` in front of the body.

Suggested half-width:

```python
t = index / (len(points) - 1)
end_taper = smoothstep(min(t, 1 - t) / .18)
half_width = .0015 + .0055 * end_taper
```

Centre position:

```python
centre = Vector((x, front(x, z) - .0035, z))
```

Material:

```text
Base colour:  (.012, .0035, .0018)
Roughness:    .88–.92
Specular:     .02–.04
```

The strip should feel like a tiny dark line settled into the fur—not a cord resting on top of it.

### Add a narrow mouth-groom channel

Compute the shortest `x–z` distance from each groom root to the smile centreline.

Within roughly `.010` scene units:

```text
Pile density: 25%
Pile length:  35%
```

Fade both back to full by approximately `.028`.

Do not create a bald region. The purpose is only to stop fibres from randomly covering the thin smile.

### Brows: reduce the gap and stop tapering over the entire form

Move their baseline down another:

```python
.025
```

Keep their centres and general orientation.

The current sinusoidal radius taper acts over the whole brow, giving it a wedge/crescent appearance. Replace it with a central constant-radius plateau and short rounded ramps at the ends:

```python
def rounded_capsule_radius(t, edge=.22):
    if t < edge:
        q = t / edge
        return math.sqrt(max(0, 1 - (1 - q)**2))
    if t > 1 - edge:
        q = (1 - t) / edge
        return math.sqrt(max(0, 1 - (1 - q)**2))
    return 1.0
```

Use:

```text
Brow centre radius: .025–.027
Brow centreline length: current length or at most 5% shorter
```

This should produce a short rounded plush capsule rather than a pointed stroke.

# Freeze versus continue changing

## Freeze for v012

- body profile;
- camera;
- framing;
- eye centres;
- body recess depth;
- arm geometry;
- tuft geometry;
- blush mask geometry;
- body material colour;
- body light values;
- neutral lid coverage;
- closed-mouth centreline and expression.

## Continue changing

- eye cap aspect ratio and centre bulge;
- all eye-only lighting;
- pile length, angle, density, interpolation, and material;
- eye-rim fur transition;
- brow vertical position and longitudinal profile;
- mouth cross-section and local groom clearance.

## Do not touch yet

Do not resize the arms, reshape the tufts, enlarge the cheeks, or relight the body in v012. The longer oblique pile will alter all four visually. Changing them now would confound the groom evaluation.

# v012 acceptance gates

The next still should not advance unless:

1. both eyes have similarly positioned small catchlights;
2. both eyes reveal equal warm lower-brown depth;
3. neither eye reads as a flat black button or protruding marble;
4. facial pile fibres remain visible at the matched 512 px comparison scale;
5. the coat resolves into small local locks rather than velvet;
6. the smile remains readable without looking raised or plastic;
7. the brows sit close enough to the eyes and end softly;
8. the gross silhouette remains unchanged from v011.

**v011 has crossed from “wrong character” to “correct structural base with wrong surface language.”** The body and camera can now be held stable. The decisive v012 work is the per-eye optical rig, the much more oblique one-neighbour pile, and the inset facial strokes.

