# Character artwork and playback

The app uses transparent 2D PNG sprites for all 29 companions, all nine moods and all 12 egg stages.
Home, friend details, profile, collection, hatching and widgets share `CompanionArt` and `CompanionView`.
There is no live 3D character view or model resource in either target. App identifiers, saved names,
owned pets, mood choices, sharing, widgets, streak rewards and lifetime restores keep their existing format.

## Creating artwork

1. Start with the original identity reference. Generate one canonical, front-facing character.
2. Attach that approved character to every later generation. Make one horizontal strip per action or
   expression, with complete separated silhouettes. A spacing guide is a reference, never visible artwork.
3. Preserve the body shape, fine short fuzz, attached arms, eye construction, cheeks and closed smile.
   Do not add feet, talking mouths, particles, props, hearts or stars to touch reactions.
4. Retain the original outputs, exact prompts and reference paths. Remove the flat magenta background,
   clean its edge fringe, extract whole poses, then register one shared scale and ground baseline.
   Do not independently stretch frames. Keep intentional vertical motion only for an explicit jump.
5. Export full-color RGBA PNGs. GIF and video files are previews. Inspect the result on light and dark
   backgrounds, then at actual phone and widget sizes before replacing the bundled PNG.

The prompt and attached reference establish identity together; text alone cannot reproduce identical pixels.
`Art/Dusk/SpriteTrial/` retains Dusk's source artwork, prompts, spacing guide, extracted frames, hashes
and processing measurements. Rebuild and install that selected strip with Python, Pillow and NumPy:

```sh
python3 Tools/artwork/prepare-dusk-trial.py --install
```

All 29 companions have 10 motion atlases each: idle, move right, move left, wave, jump,
disappointed, waiting, thinking, reviewing, and a 16-direction look sequence. The collection contains
2,117 frames. `Art/CollectionMotion/v001/README.md` records the retained source and execution workflow.
The older Dusk trial is preserved for provenance. Widgets display still images.

Sick, Studious and Working Out occupy the third row of each character’s mood atlas. Sick holds a thermometer at the mouth. Studious wears reading glasses and holds an open book. Working Out wears a headband and holds a pair of small dumbbells. All three use the same resting scale and touch reactions as the other moods. Exact prompts and export settings are in `Art/MoodPortraits/v001/`.

## Interaction

Tap for a short blink, swipe left or right for the matching movement, or rub for the character's signature reaction. The main companion, friend detail,
and owned-character detail play a random emote every six seconds across every
character and mood. Holding the companion opens no menu. Consecutive
emotes differ, and each returns to the selected mood. The timer pauses while the
view is hidden, the app is inactive, or Reduce Motion is enabled. A fresh
six-second interval starts on return. A tick during petting, another reaction,
or frame decoding is skipped so the current interaction can finish.
Signature reactions reuse the registered portrait for the selected mood. Clouds drift, rounded
characters rock or nod, and Sprout/Bonsai move only their crown. Body scale stays fixed.
`DotlingSignature.reaction(for:)` contains the per-character name, duration and amplitude for all 29.
A sine envelope brings motion and velocity to zero at both ends (1.6–2.7 seconds).
Crown motion tapers to zero before the face and renders the original texture in pixel-height bands;
no new images, 3D assets, expression substitutions, scaling, haptics or effects are introduced.
Repeated taps during a blink let it finish. Releasing a rub lets it settle naturally.
The original action strips remain available; they temporarily change pose as before.
Actions work from every mood and return to that mood when finished. Happy has a continuous idle loop;
the other five moods use their registered rest portraits between actions. The movement clips are
shared across moods, not separately generated mood-specific animation packs.

All rest portraits use the Happy motion scale to prevent a size jump when interaction begins.
Playback stops offscreen and resets on mood or character changes. Reduce Motion keeps a still portrait.
Hatching retains its illustrated warming, cracking and reveal sequence. No app-generated haptics,
reaction captions or floating icons are used.

## Checks and delivery

Run `bash Tools/check.sh`. It checks the app/widget source and resource lists, type-checks both targets,
exercises persistence, rewards, hatching and sprite playback, inspects all mood/touch and egg frames,
and renders the actual SwiftUI screens and widget layouts. `Tools/check-sprite-build.py` fails if a
target includes a retired 3D model or renderer, omits an active source/sprite, or bundles a Dusk strip
different from its retained export. The same checks run before the GitHub TestFlight upload job.

Local checks do not prove perceived animation smoothness on a physical device. Confirm those
with the signed TestFlight build. Native iPhone screenshots run in the separate store-capture workflow,
which also triggers when sprite resources change.

## Preserved 3D experiments

The unshipped 3D prototype source, models, generators and comparison renders are preserved separately
on the external drive at `/Volumes/new one/Apple Apps/Dotlings/Archive3D-2026-10-25` with a SHA256
manifest. The earlier approved Sky reference and reconstruction recipe remain in `Art/Sky/` as
historical source artwork. Neither archive is compiled into the app or widget.

## Circle order

Press and hold a friend card in My circle, then drag and release it over another card.
Dropping on the upper half inserts before it; the lower half inserts after it. A quiet outline
marks the destination. A normal tap still opens the friend. VoiceOver offers Move up/down actions.
There is no Arrange button or separate editing sheet. Native drag recognition leaves ordinary
scrolling available. Orders save only on a valid drop, so cancellation does not rearrange anything.
The process-only transfer type and per-view scope reject unrelated drags; missing/departed friend IDs
are ignored. `CircleState.friendOrder` retains the order across refreshes and app launches.
New people append after the arranged friends. Widget latest-mood selection remains chronological.

Set `DOTLINGS_CAPTURE_SIGNATURES=1` when running `Tools/check.sh` to render a GIF of all 29
signature reactions through the same Canvas view used in the app. Physical iPhone testing is
still needed to assess native drag lift, scrolling, cancellation and drop feel.

The custom drag type is declared in the app Info.plist, as required by Apple’s
[CodableRepresentation documentation](https://developer.apple.com/documentation/coretransferable/codablerepresentation).
