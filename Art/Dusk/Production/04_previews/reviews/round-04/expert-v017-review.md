# Expert review of v017

Source: existing chat `blender expert`, conversation `6ade6451-305c-8331-852f-70b36e9c082d`, message `07a3ff1c-956a-43eb-acdc-a7845a1dbe0f`.

**Reject — but v017 is the first study whose material family is broadly correct.** At matched size it finally reads as plush rather than suede, chalk, or wire hair. What still blocks the reference’s sweetness is the shortened silhouette, low facial placement, overly dark/coarse coat, and under-developed eyes.

1. **Restore vertical proportions.** Your measurements are directionally correct: the body crown is approximately **15–20 px lower**, while the eyes and smile are about **6–8 px lower** at the matched display width. Replace the global `.92` vertical scale with roughly `.98`, including the eye/brow/mouth Z expressions. Raise tuft centres only about `.04` world units so their visible height shortens relative to the restored crown. Preserve width and baseline. 

2. **Refine—not rebuild—the coat.** Keep the current **70k fibres/7k guides** and disabled fuzz shadows. The density now works, but the pile remains too dark, thick, and locally matted. Lift the shared charcoal/fibre value by roughly **12–15%**, reduce Hair BSDF contribution from **18% to 10–12%**, and reduce pile bend from `.14–.26` to approximately `.08–.16`. Do not add sheen or further density. 

3. **Open and warm the eyes.** The lower brown is too faint, the black core dominates, and the authored white dots are visibly smaller than the reference. Increase lower-iris warmth by about **20–25%**, reduce pupil blending from `.88` toward `.80`, and enlarge highlight radius from `.020` to approximately `.025`. Tighten the eye-fur exclusion from `.97` toward `1.00` so strands no longer intrude onto the black glass.

Freeze the camera, width/base silhouette, eye spacing and aperture, corneal layering, cheeks, arms, and tuft shapes.

