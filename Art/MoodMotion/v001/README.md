# Illustrated mood movements

All 29 Dotlings have ten actions in Sick, Studious and Working Out. An action sheet contains four painted poses for each of the three moods. Both running directions are drawn separately so the faces, headbands, thermometers and asymmetric characters turn the right way. Four additional diagonals complete the eight-direction gaze. The 319 original sheets contain 3,828 painted poses.

The reference for each character combines its three approved mood portraits in Sick, Studious, Working Out order. Every generation uses that reference and the shared instructions plus its action text in `prompts.json`. Keep the full-resolution references and outputs on the Apple Apps drive in `Dotlings/Releases/distribution-20261117/mood-motion-20261123/`.

Run `python3 Art/MoodMotion/v001/build.py /path/to/mood-motion-20261123` with Pillow, NumPy and SciPy. The builder separates the poses, fits each sequence to the existing character’s resting envelope, and preserves takeoff and landing for hops. The app bundles transparent WebP strips in MoodMotion. The widget uses the existing static mood atlas. The app decodes only the selected character, mood and action. Timing and key-pose order are defined by DotlingAnimation. The exact rest portrait anchors long holds, and Reduce Motion uses the resting illustration.
