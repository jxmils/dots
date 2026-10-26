# Expert review of v014

Source: existing chat `blender expert`, conversation `6ade6451-305c-8331-852f-70b36e9c082d`, message `8d16e967-7c82-49fb-b6ba-841c29d0633e`.

## Pixel access confirmed

I inspected the actual v014 matched comparison, native 1536 px render, 100% detail crop, the preceding v013 comparison, and `build-v014.py`.

**v014 remains rejected.** It is structurally much closer to Dusk, but the two remaining failures are now clearly **material-system failures**, not reasons to keep reshaping the model:

1. The eye reads as a flat brown annulus around a black disc.
2. The coat reads as alternating dark stubble and bright synthetic fibres rather than dense, soft plush.

Your proposed isolated material A/B is the correct next experiment. I would **not change pile density, length, tilt, body geometry, or lighting in the next study**.

# What now matches closely enough to freeze

For the next pass, freeze:

- Body silhouette and flattened base
- Camera and framing
- Eye centres, aperture size, and vertical-oval shape
- Corneal cap geometry and recessed eye bed
- Authored highlight position, eyelid occlusion, and attachment method
- Arms and tufts
- Blush mask location and size
- Brows
- Closed-smile geometry
- Current undercoat and pile geometry
- Current key, fill, rim, world lighting
- Eye-fill energy while testing the new eye material

The authored highlight construction is now technically sound. It is real editable geometry, follows the cap, is correctly hidden by a closed lid, and does not appear on the closed eye. Preserve that architecture.

The body is still slightly smoother and more regular than the reference, but the native crop shows that this is mostly a surface response problem. Another geometry change would confound the material comparison.

# What the pixels show

## 1. v014’s eyes are more legible than v013’s—but less glass-like

The progression from v013 to v014 is mixed:

- **Improved:** The pupil is now unmistakable.
- **Improved:** The catchlights are matched and stable.
- **Improved:** The vertical eye shapes are clean and intentional.
- **Regressed:** The eye now reads as a black centre inside a nearly uniform brown ring.
- **Regressed:** The brown appears painted on the outer surface rather than existing beneath glass.
- **Regressed:** The pure-white highlight reads like a dot placed onto the brown surface.

The target does not present a clean “pupil circle plus iris ring.” Its pupil, upper iris, and upper shadow merge into one deep dark region. The lower eye gradually warms toward brown. That continuous value structure is what produces softness.

The current source creates a pupil transition over only `r=.40–.51` and an outer rim over `r=.83–.97`. That is a relatively explicit radial design. The same opaque front surface carries the iris colour, coat, specular response, emission, and authored highlight. Consequently, every eye cue occupies essentially one plane. 

The cap itself is no longer the problem. The **colour needs to move behind it**.

## 2. The v014 coat confirms that shader response is now the bottleneck

Your diagnosis is correct.

The visible fibres now have enough geometric width to survive rendering. At 100% they are clearly present. Yet they alternate between:

- nearly black root marks;
- dark gaps exposing the shell;
- thin brighter shaft segments;
- occasional wire-like highlights.

That is not primarily a density failure.

The source currently combines three contrast-producing mechanisms:

- A Principled Hair BSDF for very dark charcoal fibres
- Per-strand roots at `0.91–0.98×` the coat colour
- Tips at `1.04–1.10×` the coat colour

The pile also has a lower roughness than the undercoat. On an almost-black material, those differences become much more visible than their numerical ranges suggest. The quadratic taper successfully preserves the fibres, but the current Hair BSDF makes those preserved fibres read as separate dark and bright strokes. 

So yes:

> **The next change should be the curve shader, not another density/tilt/length revision.**

## 3. The blush mismatch is partly a fur-shader symptom

The target blush appears diffused through many fine hairs.

In v014 it still reads as a luminous pink area beneath a darker scratched surface. The mask position is close, but the coat produces too much dark-over-bright contrast. A softer diffuse/sheened fibre shader should integrate the cheek colour into the coat before you alter the blush itself.

Do not change the blush mask yet.

# Smallest decisive next pass

## 1. Run the proposed Principled-fuzz A/B on the unchanged curves

Use the exact v014 groom, colours, lighting, sampling, and framing. Change only the materials.

### A: pure rough/sheened Principled BSDF

This is the most important diagnostic.

For the undercoat:

```python
undercoat = nodes.new('ShaderNodeBsdfPrincipled')
undercoat.inputs['Roughness'].default_value = 0.86
undercoat.inputs['Specular IOR Level'].default_value = 0.08
undercoat.inputs['Sheen Weight'].default_value = 0.28
undercoat.inputs['Sheen Roughness'].default_value = 0.85
```

For the visible pile:

```python
pile = nodes.new('ShaderNodeBsdfPrincipled')
pile.inputs['Roughness'].default_value = 0.78
pile.inputs['Specular IOR Level'].default_value = 0.10
pile.inputs['Sheen Weight'].default_value = 0.34
pile.inputs['Sheen Roughness'].default_value = 0.80
```

Connect `FurColor` to `Base Color`.

For this A/B, remove longitudinal colour changes. Give every point on a given strand the same colour:

```python
curve_value = rng.uniform(.97, 1.03)
strand_colour = tuple(
    channel * curve_value
    for channel in coat_color(point)
)

for index in range(7):
    colors.extend((*strand_colour, 1))
```

Do **not** make the roots darker or the tips brighter in this first material test. Let geometry and lighting create the strand variation.

This will tell us whether the dark-stubble/bright-wire effect is primarily the Hair BSDF plus the along-strand colour ramp. I expect it to remove a large part of the problem.

### B: mostly Principled with a little Hair BSDF

If pure Principled looks too much like painted microscopic tubes, create a second test:

```text
80–85% rough/sheened Principled BSDF
15–20% Principled Hair BSDF
```

Use the same nearly constant strand colour in both branches.

The small Hair component can restore subtle directional fibre response without allowing hair absorption and anisotropy to dominate the appearance.

### Do not change these during the A/B

Keep fixed:

```text
Pile guides/fibres: 2800 / 26000
Root radius:         .00078–.00125
Taper:               1 – .85t²
Tilt:                36–44°
Current lengths
One interpolation neighbour
All lights
All geometry
```

If the pure-Principled version still looks sparse after the dark stubs disappear, then increase pile fibres by only about 15–20% in a later pass. Do not pre-emptively add density now.

# 2. Separate the iris from the corneal cap

An experienced character artist would not ask one opaque surface to be simultaneously:

- cornea;
- iris;
- pupil;
- limbal rim;
- internal illumination;
- reflection layer;
- authored highlight.

Use three visual layers:

```text
Outer corneal shell
Inner iris/pupil surface
Authored highlight patch
```

Your existing cap becomes the outer cornea. Keep its shape and position.

## Outer cornea

The front corneal shell should contain no iris colour and no emission. Use a clear glossy/transmissive material.

A coherent Principled starting point is:

```python
cornea.inputs['Base Color'].default_value = (1, 1, 1, 1)
cornea.inputs['Roughness'].default_value = .05
cornea.inputs['IOR'].default_value = 1.40
cornea.inputs['Transmission Weight'].default_value = 1.0
cornea.inputs['Coat Weight'].default_value = .10
cornea.inputs['Coat Roughness'].default_value = .04
```

Use only the front cap as the clear shell if the closed volume creates excessive double refraction.

## Inner iris/pupil surface

Create a second shallow oval approximately `.007–.012` behind the corneal front. It can follow the same eye perimeter but should be nearly flat or only gently concave.

Move the `EyeTone` attribute onto this inner surface.

The iris material should be comparatively matte:

```python
iris.inputs['Roughness'].default_value = .50
iris.inputs['Specular IOR Level'].default_value = .12
iris.inputs['Coat Weight'].default_value = 0
iris.inputs['Emission Strength'].default_value = .006  # or zero in the A/B
```

The current `.025` emission contributes to the painted appearance because the annulus retains almost the same value independent of surface orientation. Use the eye fill to reveal the iris rather than making the iris broadly self-lit.

## Replace the donut map with a vertical eye gradient

Use a vertically driven brown field first, then add a very soft pupil.

Conceptually:

```python
lower_warmth = smoothstep((-dz + .25) / 1.15)

upper_colour = (.004, .0012, .0006)
lower_colour = (.075, .020, .0055)

iris_colour = mix(upper_colour, lower_colour, lower_warmth)
```

Then apply a broad pupil rather than the current narrow transition:

```python
pupil_radius = math.sqrt(
    (dx / .92)**2 +
    ((dz - .02) / 1.02)**2
)

pupil = 1 - smoothstep((pupil_radius - .28) / (.59 - .28))
```

Instead of replacing the iris completely with black, darken it progressively:

```python
pupil_dark = (.0008, .00025, .00015)

colour = mix(
    iris_colour,
    pupil_dark,
    pupil * .88,
)
```

Then add a broad, subtle limbal fade:

```python
rim = smoothstep((radial - .76) / (.98 - .76))
colour = mix(colour, (.0025, .0007, .00035), rim)
```

This should produce:

- dark pupil;
- no hard pupil-ring boundary;
- nearly black upper eye;
- warm lower eye;
- dark outer edge;
- continuous value flow rather than a brown doughnut.

The v013 gradient was emotionally closer to the target than the v014 ring. Retain v014’s pupil concept, but embed it softly into v013’s vertical value distribution.

# 3. Keep the authored highlight, but soften its optical read

The highlight’s **placement and occlusion are now sufficiently close to freeze**.

Its material is not.

The current patch uses pure white emission at strength `2.5` with a hard geometric boundary. That is why it looks like a white spot attached to the eye. 

Keep the same position and cap-following geometry, but create a radial feather:

```text
Inner 55–60%: nearly white
Outer 40–45%: fade smoothly to transparent
```

Use a `HighlightMask` point attribute to mix:

```text
Transparent BSDF
Emission shader
```

A suitable starting point is:

```text
Centre emission: 0.8–1.2
Centre colour:   slightly warm white, not absolute white
Outer edge:      zero opacity/emission
```

Do not shrink or move the patch yet. First see how the same highlight reads over a genuine cornea and recessed iris.

# Add the dim reflection card—but give it only one job

Your reflection-card test is worthwhile.

Use it to create a **broad, low-contrast corneal gradient**, not the primary catchlight.

The main dot remains the authored geometry. The card supplies the missing glass volume.

For a real emissive card object:

```python
card.visible_camera = False
card.visible_diffuse = False
card.visible_glossy = True
card.visible_shadow = False
```

Make it:

- broad;
- dim grey, not white;
- above and slightly to one side of the camera;
- large enough that both eyes receive a similar soft reflection.

Because the authored patches already enforce exact matching catchlight positions, the card does not need millimetre-perfect left/right symmetry. It should be faint enough that one sees a gentle upper corneal lift only after noticing the eye.

Do not tune the eye-fill energy and card intensity simultaneously. Hold `eye_fill_energy=140` for the first layered-eye render, add the card at one deliberately faint level, and judge the result. The v014 helper now uses the actual Cycles ray visibility flags, so the earlier ignored light-factor issue is no longer contaminating this test. 

# What an experienced character artist would do here

For the fur:

> **Diffuse/sheened plush undercoat + slightly directional pile**, not exclusively Hair BSDF on almost-black fibres.

For the eyes:

> **Recessed matte iris/pupil + clear corneal shell + controlled reflection + authored highlight.**

Those constructions deliberately separate visual jobs. They are easier to art-direct and much more stable across expressions and modest turns than asking one material layer to simulate everything.

# What not to change in the next study

Do not change:

- shell profile;
- arms;
- tufts;
- eye dimensions or position;
- highlight position;
- brows;
- smile;
- blush;
- groom geometry;
- density;
- tilt;
- lighting;
- camera.

Produce the next comparison as a small matrix if practical:

| Variant | Fur | Eye |
|---|---|---|
| A | Pure Principled plush | Layered cornea/iris, no reflection card |
| B | 80/20 Principled/Hair | Layered cornea/iris, faint card |

The authored highlight should appear in both.

## Next acceptance gates

The next still remains rejected unless:

1. The coat no longer alternates between black stubs and pale wires.
2. Fibre colour stays coherent from root to tip.
3. Fine strands survive at 512 px without becoming woolly.
4. The eye no longer has an obvious pupil-plus-brown-ring construction.
5. The upper eye merges into near-black while the lower eye remains warm.
6. The cornea produces subtle broad depth behind the authored dot.
7. The authored highlight no longer reads as a hard white sticker.
8. The cheeks appear embedded in the coat rather than shining through scratches.

**v014 has enough geometric fidelity to stop modelling. The next decisive work is entirely shader-layering and material response.**

