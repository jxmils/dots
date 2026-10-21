# Dotlings

A small companion for your feelings, and a quiet way to keep your friends close.

Native iPhone app, iOS 18 and later. Hatch one of 29 original squishy companions for free, give it a name,
and choose a mood: happy, calm, sleepy, a little low, overwhelmed, or focused. No free-text status,
AI conversation, inferred feelings, feeding obligations, advertising, or analytics.

## The first version

- A free random first hatch: warm a little egg by rubbing it, then give it three gentle taps.
- 29 distinct companions, each with six expressions. Original Lilac, Sky and feet-free Cloud remain.
- Tap to boop and squish, rub to pet, soft haptics, temporary reactions and Reduce Motion support.
- Daily mood check-ins earn nonduplicate random creatures at streak milestones starting at 5, 10,
  25, 50, 100, 150 and 200 days. Three lifetime restores can bridge missed days; otherwise only
  the streak resets. Earned creatures and eggs remain. Each milestone is earned once.
- Mood selection, persistent names and preferences, an animated squish that respects Reduce Motion.
- Private iCloud invitations. Invite someone to see your current mood; accept their invitation to see theirs.
  Each person controls their own read-only share. There is no public profile or contact upload.
- Choose any owned companion as your preferred profile Dot; the same creature and its remembered name
  appear at home, on your profile, and in the mood shared with friends and their widgets.
- A friend circle ordered by latest mood; pin one friend for your widget.
- Circular, rectangular, and inline Lock Screen widgets and a small Home Screen widget.
  Each widget can use the app preference, show the latest friend, or select a specific friend.
- Share management, leaving a friend's circle, and deletion of your own shared companion.
- Empty states contain no simulated friends. The screenshot renderer uses explicitly labelled sample data.

## Run and check

Open `Dots.xcodeproj`, select the Dots scheme, and choose your signing team for both targets.
Configure the App Group and CloudKit container in [docs/setup.md](docs/setup.md) before testing invitations.
Local adoption and mood changes do not need an iCloud connection.

`Tools/check.sh` type-checks both targets, checks storage/widget selection and all 174 transparent sprites,
and renders the real SwiftUI screens and widget content. It uses the iOS compatibility frameworks in the
macOS SDK and runs on an Apple Silicon Mac with the Command Line Tools or full Xcode.
The output directory defaults to `build/check`; pass an absolute path to put the renders elsewhere.

The GitHub workflow also archives the actual iOS app and embedded widget without distribution signing.
There is no automatic TestFlight upload or App Store submission in this repository.

## Verification boundary

Local code/type checks and preview renders do not verify iCloud entitlements, two-person invitations,
push delivery, physical-device rendering, or actual Lock Screen refresh behavior. Those require the
registered Apple identifiers, a signed build, and two physical devices with different iCloud accounts.
See the retained checklist in [docs/setup.md](docs/setup.md).

Widgets request refreshes and display the original mood timestamp; iOS controls refresh timing.
A pinned friend who becomes unavailable produces an empty state, rather than silently showing someone else.
Failed network refreshes retain the last received mood. Successful refreshes replace the full shared set,
removing revoked access. Mood changes are saved locally before an upload is attempted.

## Source

- `Dots/`: SwiftUI screens, model, iCloud invitation handling, sharing sheet.
- `Shared/`: companion/mood model, storage, CloudKit operations, character and widget views.
- `DotsWidget/`: App Intent configuration and timeline provider.
- `Resources/`: all 29 project-owned character atlases (174 expressions).
- `Tools/`: project generation, render and check tools; `Tests/`: meaningful state/persistence checks.
- `docs/*prompts.json`: the exact built-in imagegen prompts used for the artwork.
- `docs/collection.md`: hatching, reward and lifetime restore rules.
- `docs/mood-colours.md`: mood colour rationale and limitations.

The Xcode project is checked in. `ruby Tools/project.rb` can regenerate it with the `xcodeproj` gem.
The character designs are original; Dotlings is independent of OpenAI and Club Penguin.

The public app name is **Dotlings**. The existing Dots project/scheme, registered bundle IDs, App Group,
CloudKit container and storage keys remain unchanged for signing and data continuity.
