# Expert review of v010

Source: existing chat `blender expert`, conversation `6ade6451-305c-8331-852f-70b36e9c082d`, message `42abbf12-c63b-4aef-b8d5-057d2c9b7d6f`.

## Pixel access confirmed

**Yes. I inspected the actual pixels of `comparison-v010.png`, the full 1536 px render, and the 100% face/fur detail.** I also checked the exact `build-v010.py` construction.

## Blunt verdict

**v010 is no longer scary. It is clearly sweeter and substantially better than v007. It still is not Dusk.**

At present it reads as:

> **a dark velvet bean with two black teardrop insets**

The approved reference reads as:

> **a densely plush charcoal creature with large, warm, rounded glass eyes**

The main shell proportions are now close enough that I would **stop reshaping the entire body for one iteration**. The remaining identity gap is overwhelmingly caused by:

1. the accidental eye aperture;
2. the single-scale uniform groom;
3. flat, diffuse body lighting and manufactured-looking facial strokes.

## What v010 successfully fixed

The smaller single catchlight is much better. **The reflection is no longer the primary eye problem.** Keep one catchlight and do not enlarge it in the next pass.

The body is lower and more planted. The arms now droop rather than looking like tiny horizontal fins. The blush is smaller and higher. The coat no longer looks combed downward.

Those changes moved the character in the right direction.

# What still differs from the reference

## 1. The eyes are not authored shapes

Your own diagnosis is correct: both eyes are visibly clipped into mirrored teardrops. Their lower-inner boundaries narrow to points, and the exposed shapes differ across their width because the surrounding body surface is determining the outline.

The source creates each eye as a very shallow ellipsoid:

```python
rx, ry, rz = .155, .060, .164
eye = sphere(..., (x, front(x, z), z), (rx, ry, rz), ...)
```

Its centre sits directly on the curved body surface. Therefore, the visible eye outline is the intersection of two unrelated volumes rather than a designed oval. 

Moving that ellipsoid toward the camera would expose a rounder outline, but it would also restore the protruding marble appearance. **Do not move the current eye spheres forward. Replace them.**

The eyes are also now too close to uniformly black. The reference has a near-black upper region and centre, but a clearly perceptible warm brown lower region. v010 has suppressed the brown enough that the eye loses internal depth at normal size.

## 2. The groom is still velvet

The detail crop makes this unambiguous. The coat is present, but it reads as an extremely even nap:

- almost identical fibre spacing;
- almost identical thickness;
- almost identical length;
- little local directional grouping;
- no small pockets of denser and looser fibres;
- very little strand-level highlight separation.

The reference contains **micro-clumps**: tiny groups of fibres that lean together, separate slightly from neighbouring groups, and vary in length and brightness. They are not long locks, but they stop the coat from becoming a continuous grey surface.

The current builder mechanically encourages uniform velvet. It uses one groom layer, constant density, four-neighbour interpolation, one fixed `.00060` root radius, one identical sine-shaped bend, and a blanket `1.12×` fibre-colour multiplier. 

That combination smooths away the very variation the target needs.

## 3. The body is too diffusely lit

The body is visibly lighter and flatter than the target. More importantly, it lacks the small directional highlights that allow dark fur to remain legible.

The source explains why: the lighting helper defaults to `specular=0`, and all three body lights—key, fill, and rim—use that default. Only the dedicated eye light has specular enabled. 

Consequently, the coat is largely described by broad diffuse illumination and world light. Even an improved upright groom will still tend to merge into grey velvet when the fibres receive no useful directional specular response.

The candidate also uses AgX Medium Low Contrast, a world strength of `.22`, a fill of `180`, and a rim of `70`. Together with fibres brightened by 12%, that lifts too much of the charcoal mass.

## 4. The facial strokes still look manufactured

The thicker eyebrows helped their visibility, but the 100% crop reveals:

- flat, abruptly cut ends;
- constant thickness from end to end;
- a slightly rectangular profile;
- too much separation from the eyes.

The target brows are soft, short, rounded capsules with gently tapering ends.

The smile remains correctly closed, but close-up it has the same tube-like construction: constant thickness and visible edge shading. At normal size it becomes too faint, while at 100% it appears like a separate plastic strip. It needs tapered geometry rather than simply becoming thicker.

The cheeks are still airbrushed blobs because the uniform coat does not break up their edges. Their footprint is now reasonably close; I would not resize them again until the groom changes.

# The next three concrete corrections

## 1. Replace each eye sphere with a shallow authored lens

Build an explicit elliptical cap whose perimeter follows the body surface. This gives you complete control over the visible oval while keeping the centre shallow.

Use approximately the current frontal dimensions:

```python
rx = 0.150
rz = 0.160
bulge = 0.024 to 0.028
rim_offset = 0.003
```

For a point inside the ellipse:

```python
u = rho * cos(theta)
v = rho * sin(theta)

x = cx + rx * u
z = cz + rz * v

rho2 = u*u + v*v
surface_y = front(x, z)

# Negative Y is toward the camera in this scene.
y = surface_y - rim_offset - bulge * (1.0 - rho2)**2
```

At the boundary, the eye sits only about `.003` in front of the body. At the centre, it projects roughly `.027–.031`. That is only about one-tenth of the eye width: enough curvature for a glossy reflection, but nowhere near marble depth.

### Create a controlled eye bed

Slightly recess the body behind the cap:

```python
body_vertex_y += 0.006 to 0.010
```

Use a smooth elliptical falloff extending to approximately `1.08×` the eye radius, and apply it only to front-facing vertices.

For the groom:

- reject body-hair roots inside approximately `0.94×` the eye ellipse;
- shorten fibres smoothly between `0.94×` and `1.08×`;
- allow a very small amount of fur overlap at the outer boundary.

This creates the impression that the eye is pressed into plush without letting the body arbitrarily crop it.

### Preserve a rounded visible aperture

Expose roughly **93–96% of the complete oval**. A neutral upper lid may overlap only the uppermost **4–7%**. Do not use body intersection as the eyelid.

A subtle radial darkening in the eye shader can provide the rim. A separate thick black outline is unnecessary.

### Eye shader values

Keep the current single catchlight for the next test. The glint itself is now acceptable.

Raise only the lower-eye brown from the current maximum:

```python
(.0375, .012, .004)
```

to approximately:

```python
(.050, .016, .005)
```

Limit that warmth to the lower 35–40% of the cap. Keep the upper half and soft central region near-black. This is roughly a 35% increase, not a return to v007’s orange eye.

Suggested material range:

```python
Specular IOR Level = 0.22–0.27
Coat Weight        = 0.22–0.30
Coat Roughness     = 0.12–0.17
Emission Strength  = 0
```

The resulting read should be **dark eye first, warm depth second, tiny catchlight third**.

## 2. Replace the single groom with undercoat plus irregular pile

The target needs two perceptual scales.

### Dense undercoat

This supplies uninterrupted softness:

```text
Body fibres:       100,000–125,000
Guide count:       4,000–5,000
Max neighbours:    4
Body length:       .010–.017
Face length:       .008–.014
Tuft length:       .014–.022
Root radius:       .00028–.00042
Direction:         normal × .96 + tangent × .08
```

Keep this layer relatively uniform. It should prevent holes without becoming the visible character of the coat.

### Visible pile

This creates the reference’s small irregular fibre groups:

```text
Body fibres:       35,000–45,000
Guide count:       3,500–4,500
Max neighbours:    1 or 2
Body length:       .022–.034
Face length:       .018–.027
Tuft length:       .028–.042
Root radius:       .00042–.00072
Direction:         normal × .86 + tangent × .18
```

Using one or two interpolation neighbours is important. Four-neighbour averaging blends adjacent guide shapes into the even field visible in v010. With one or two neighbours, perhaps six to twelve nearby fibres inherit a common lean and form a micro-clump.

Do not give every guide the same bend. For each pile guide, randomise:

```text
Bend amplitude:    .04–.12 × strand length
Bend side:         positive or negative
Bend phase:        random
Length multiplier: .78–1.24
Radius multiplier: .70–1.30
```

Use two tangent fields:

```python
macro = tangent_projection(noise_vector(point * 7))
micro = tangent_projection(noise_vector(point * 43 + seed_offset))
tangent = (macro * .65 + micro * .35).normalized()
```

The macro component lets tiny neighbouring groups lean together; the micro component prevents them from turning into another combed flow.

### Vary the density

Drive the visible-pile density with a medium-frequency noise field, approximately:

```text
Density multiplier: .65–1.35
Noise scale:        35–50
```

This should produce small variations, not bald patches. At 1536 px, the clumps should generally occupy only two to six pixels.

### Vary colour along each strand

Remove this blanket operation:

```python
value * 1.12
```

Instead make roots dark and lift only the tips:

```text
Root colour: .96–1.00 × coat colour
Tip colour:  1.04–1.07 × coat colour
Random per-curve value variation: ±3%
```

Use Hair Info’s intercept to mix root and tip colours, or store a different colour at each curve point. This will restore a dark body while allowing individual fibre tips to catch light.

## 3. Correct body lighting and round the facial strokes

### Body lighting

Enable specular response on the fur:

```python
KEY_SOFT:
    energy = 280–310
    specular = .60
    diffuse = 1.0

FILL_SOFT:
    energy = 105–130
    specular = .12
    diffuse = .75

RIM_SOFT:
    energy = 35–45
    specular = .40
    diffuse = .25
```

Reduce the world strength from `.22` to approximately `.10–.12`.

For the first revised render, use AgX Medium High Contrast rather than Medium Low Contrast. The softer fill and world values should keep this from becoming harsh, while the additional contrast will restore the target’s dark charcoal body.

Keep the current dedicated eye catchlight unchanged initially. A new shallow eye cap will alter its apparent shape by itself.

### Rounded brows

The current `tube()` helper uses a constant bevel radius and filled caps, which produces the visible cut ends.

Use per-control-point curve radii:

```text
.15, .45, .78, 1.0, 1.0, .78, .45, .15
```

Reduce brow bevel depth from `.033` to approximately `.027–.029`, and move the brows down about `.012–.018`. They should sit more closely over the eyes without touching them.

Give them a small smooth arch rather than a kink:

```python
z += .010 * sin(pi * t)
```

### Closed smile

Retain the fixed smile, but use:

```text
Bevel depth: .0115–.0125
End radius:  .05–.10 of centre radius
Roughness:   .70–.80
Specular:    very low
```

The smile should remain readable because of its warm dark-brown value, not because it is a thick shiny tube.

# What not to change in v011

For the next still, freeze:

- camera and framing;
- body width and height;
- eye centres;
- blush footprint;
- single catchlight;
- basic arm placement;
- neutral expression.

The arms are a little heavy and the tuft cluster is still smoother and more bead-like than the reference, but both judgments are contaminated by the incorrect groom. Revising them again now would make it difficult to tell whether the coat alone corrected their appearance.

Nothing in the images suggests that Blender 5.1 is causing the visual mismatch. The current problems follow directly from the eye intersection, groom construction, and lighting configuration. There is no reason to delay this look-development iteration for 5.2.3.

## v011 visual gates

The next revision should meet these before any animation work:

1. Both eyes have complete, intentionally matched vertical-oval outlines with no pointed lower corners.
2. At normal comparison size, a restrained warm lower-eye region is visible without the eyes becoming orange.
3. At 100%, the coat resolves into many tiny fibre bundles rather than a homogeneous nap.
4. At thumbnail size, the body remains dark charcoal rather than middle grey.
5. The brows and smile terminate softly with no flat cut ends.

**v010 is progress, but it remains rejected.** The shallow cap and two-layer groom are the decisive next changes.

