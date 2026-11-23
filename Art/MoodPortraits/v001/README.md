# Resting mood portraits

Each of the 29 Dotlings has a separate illustrated pose for Sick, Studious and Working Out. Each pose used the character’s approved reference PNG with the corresponding prompt in `prompts.json`. The 87 full-resolution source PNGs are retained on the Apple Apps drive under `Dotlings/Releases/distribution-20261117/allpets-store/{sick,studious,workout}-originals/`. The manifest identifies each reference, source image checksum and exported atlas.

Run `python3 Art/MoodPortraits/v001/build.py /path/to/originals-parent` with Pillow installed to regenerate the third row. The first two rows retain their original pixels. The app and widget read the same 512-pixel cells. Touch reactions for these moods load their illustrated motion clips and return to the chosen resting portrait.
