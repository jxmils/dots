# Expert review of v007

Source: existing chat `blender expert`, conversation `6ade6451-305c-8331-852f-70b36e9c082d`, message `7908cd07-45c0-4991-a006-e7b13d831ab9`.

The expert explicitly confirmed seeing the actual comparison and source render. This is a rejection of v007, not an appearance acceptance.

## Pixel access confirmed

**Yes—I can see the actual pixels now.** I inspected the matched white-background comparison for proportions and the larger `study-v007` render for the eye, coat, blush, and surface detail.

## Blunt verdict

**v007 is much less frightening than v006’s reported direction, but it still does not look like the approved Dusk.** It currently reads as:

> **a smooth soot-coloured mochi with caramel glass eyes and airbrushed pink makeup**

The reference reads as:

> **a tiny, densely plush charcoal creature with dark, gentle eyes and warmth diffused through its fur**

The hard iris ring and obvious downward comb are gone, so those corrections were directionally right. But both were overcorrected:

- The eyes changed from “staring marbles” into **bright amber cabochons**.
- The coat changed from “combed hair” into **smudged suede or dusty felt**.

The material identity is therefore still wrong, and that affects the entire vibe more than any rig detail.

# What is visibly different

## 1. The coat does not read as short fur

This is the largest whole-character mismatch.

In the reference, individual fibres remain visible across the face, forehead, cheeks, arms, tufts, and outer contour. The hairs are short, but they project outward enough to:

- break the silhouette softly;
- catch broad highlights;
- create fine directional variation;
- carry the cheek colour through the fibres;
- make the body feel airy and touchable.

In v007, the surface is mostly continuous and cloudy. There are mottled grey patches, but almost no readable strands. The result resembles **velour, suede, soot, or a low-resolution volume**, rather than plush.

The outer edge is also too clean. The reference has a subtle fuzzy halo; v007 has a largely solid geometric contour.

The source explains this appearance: the guide direction uses considerably more tangent motion than normal projection—`normal × .45` versus `tangent × .78`—with only `.016–.024` length. That lays the fibres along the body. Denoising then smooths the remaining fine structure. 

**So yes: the v007 groom is still wrong. It is no longer combed, but it has become too flat and indistinct.**

## 2. The eyes are still the main emotional problem

The eye size is now reasonably close. **Do not shrink them again.** The problem is the optical treatment.

The reference eyes are:

- predominantly near-black;
- softly dark brown in the lower portion;
- clearly deeper in the centre;
- glossy, but not mirror-like;
- punctuated by one small, nearly circular catchlight.

The v007 eyes are:

- much too orange and bright;
- brown across too much of their area;
- weak in central darkness;
- dominated by a large white pill-shaped reflection;
- accompanied by a large grey window reflection on the lower-left side.

That secondary grey reflection is especially harmful. It makes each eye look like a polished decorative stone rather than a living eye. The white highlight is also too large and elongated.

The source uses a coat weight of `.85`, coat roughness `.06`, nonzero emission, a dedicated catchlight with energy `1000` and size `2.5`, and another separate eye reflection light. That combination directly explains the candy-glass result. 

**So yes: the v007 eye reflections still read wrong.**

## 3. The candidate remains too much like a dome or head

At matched width, v007 is more circular and head-like. The approved character feels lower, heavier, and more settled:

- The target’s mass spreads outward through its lower half.
- Its transition into the flattened base is softer.
- The sides feel inflated and plush rather than geometrically domed.
- The target has a more convincing “sitting pebble” stance.

The v007 base is very straight and its lower corners are slightly firm. Its upper body describes a smooth dome, creating a large uninterrupted forehead. This contributes to the impression of a head or mochi rather than a whole tiny creature.

The appendages intensify that difference:

- **Arms:** v007’s arms are too small, low, and horizontally stubby. They resemble side ears or little handles. The reference arms are larger, vertically fuller, downward-drooping, and more deeply merged into the body.
- **Tufts:** v007’s tufts form a chunky crown of rounded balls. The reference has one clearly taller centre tuft and two shorter, more elongated companions, all softened by visible fur. Their roots merge naturally rather than creating dark separations between discrete blobs.

## 4. The facial colour hierarchy is reversed

In the target, the body contains rich fibre detail while the facial accents are restrained.

In v007:

- the body is visually quiet and nearly featureless;
- the eyes contain very bright white and orange;
- the cheeks become large luminous pink ovals.

That makes the face feel painted onto the body.

The blush is too large, too low, too saturated, and too pale at its centre. It resembles illuminated makeup. The target blush is warmer coral, smaller, slightly higher, and visibly carried by individual hairs.

The brows are also far too thin. In v007 they resemble small scratches or stitched lines. The target brows are short, rounded, softly dimensional capsules. Their thickness is important because they frame the eyes and make the expression gentle.

The closed smile itself is conceptually right. Keep it closed. It only needs slightly more material presence and warmth after the surrounding face is corrected.

# The next three concrete Blender corrections

For the next study, I would change **only these three systems**. Do not begin animation or add more expression controls.

## 1. Rebuild the coat as upright microfuzz

Replace the current laid-over direction with a predominantly outward groom.

A suitable starting change is:

```python
direction = (normal * 0.84 + tangent * 0.24).normalized()
```

instead of effectively favouring the tangent. Remove the global downward bias from:

```python
flow = variation + Vector((0, 0, -.12))
```

Use directionally random tangent variation around the normal, not a shared downward flow.

Start with:

```python
body_length = random.uniform(.021, .029)
face_length = random.uniform(.018, .024)
tuft_length = random.uniform(.024, .033)
```

Use a much smaller low-frequency bend—approximately `.06–.10 × length`, rather than the current broad `.22 × length` arc. The coat should exhibit many tiny irregularities, not smooth curved strokes.

For this style-frame test:

- Keep the high fibre count.
- Make the fibre colour about **10–15% lighter than the body shell**.
- Lower Hair BSDF roughness from `.70` to roughly `.58–.63`.
- Render at **256 samples or more with denoising disabled** for the review still. Denoising can be reconsidered only after the groom reads correctly.
- Change the view look from **AgX Medium High Contrast** to a lower-contrast AgX look so the charcoal fibre variation is not crushed.
- Do not increase the rim light to manufacture a fuzzy outline. Correct fibre orientation and exposure first.

The required result is not longer “hair.” It is a dense, short, standing nap whose individual fibres remain barely visible.

## 2. Rebuild the eye lighting and shader without changing their footprint

Keep the current approximate eye dimensions. Do not shrink them further.

Change the eye treatment to:

```python
Emission Strength = 0.0
Coat Weight       = 0.25–0.35
Coat Roughness    = 0.12–0.18
Specular IOR Level = 0.22–0.28
```

Darken the brightest brown in the procedural gradient by roughly half. Brown should primarily appear in the **lower third** of the eye; the upper and central areas should remain near-black. Preserve a soft dark centre without introducing a hard iris ring.

For the lights:

- Delete `EYE_SOFT_REFLECTION` entirely for the next test.
- Set the catchlight’s diffuse contribution to zero.
- Reduce the catchlight size from `2.5` to approximately `.4–.6`.
- Start around `250–400` energy rather than `1000`.
- Retain one small, circular catchlight in the upper portion of each eye.
- Do not add the large grey secondary reflection back.

The target test is simple: at matched size, the viewer should see **dark eyes first and tiny white sparks second**. In v007, the reflection currently arrives first.

## 3. Squash the character and strengthen the soft facial forms

Apply a controlled silhouette correction:

- Reduce body height by approximately **7–9%**.
- Increase lower-body width by approximately **3–5%**.
- Preserve the broad flattened base, but round the lower corners and remove the hard cut-line feeling.
- Keep maximum fullness in the lower half rather than at the dome.

Then adjust the attached forms:

### Arms

Increase each arm’s visible vertical size by roughly **18–22%** and its width by approximately **10%**. Move the attachment slightly upward and rotate the end downward. The arms should look like soft drooping nubs grown from the body, not ears mounted at its sides.

### Tufts

Make the centre tuft approximately **15% taller and 10% narrower**. Make the side tufts smaller and more clearly subordinate. Increase the visual separation of their upper tips while overlapping their roots more deeply with the body.

### Brows and blush

Increase brow thickness from `.022` to approximately `.032–.035`. Keep them short, nearly horizontal, rounded, and neutral.

For the cheeks:

- Reduce the coloured footprint by approximately **25%**.
- Move the centres slightly upward, around `.04–.05` in the current scene scale.
- Reduce maximum mask strength from `.86` toward approximately `.50–.58`.
- Shift the colour from pink-magenta toward a warmer muted coral.
- Ensure the revised upright groom visibly crosses the blush.

Keep the closed smile. Increase its thickness only slightly—from `.013` to around `.015`—and use a very dark warm brown rather than neutral black.

# What the next still must prove

The next revision should pass three visual tests before any finer tuning:

1. **At thumbnail size**, the body reads as plush rather than smooth felt.
2. **The eyes read as nearly black**, with one restrained point of light—not amber objects with window reflections.
3. **In silhouette alone**, Dusk reads as a low, settled creature with drooping arms and three soft tufts—not a domed head with ears and a crown.

v007 is a meaningful improvement, but it is **not yet close enough to accept**. The next matched-width still should retain the same neutral pose, white background, camera, and framing so these three corrections can be judged without introducing new variables.

