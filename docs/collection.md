# Companions, daily check-ins and rewards

There are 29 creatures with six expressions each. The first random creature is free. The user warms an
egg by rubbing, then taps three times to reveal it. VoiceOver actions provide the same path without rubbing.
The reveal prefills a default creature name, which can be changed before taking them home. Names can
also be edited in Settings and are remembered separately for each owned creature. Blank input keeps
the default name. No hatch can duplicate an owned creature. Any owned creature can be selected from Collection.

A mood selection counts once per local calendar day. Additional selections still update the shared mood,
without awarding more days. Calendar day arithmetic covers daylight-saving changes. Earlier clock dates
are ignored by the check-in ledger; there is no server-side clock verification.

Reward streak milestones are:
5, 10, 25, 50, 100, 150, 200, 250, 300, 350, 365, 400, 450, 500, 550, 600, 650, 700, 750,
800, 850, 900, 950, 1000, 1100, 1250, 1400 and 1500 days.
Each grants one hatchable egg once. Repeating an old milestone cannot farm eggs. The 28 reward eggs
plus the first free creature provide all 29. Eggs do not expire and survive streak resets.

## Exactly three lifetime restores

After a gap, the next mood check-in offers an explicit choice: spend one restore to continue the streak,
or start a new streak. A restore adds only today's actual check-in; missed days do not count. Restores
never refill. After three are used, gaps start a new streak while keeping all creatures and earned eggs.
A pending choice is saved and resumes on relaunch.

A synchronizable Keychain receipt retains the number used outside the companion state. In-app deletion
and adoption of a new companion do not reset the budget. The receipt contains only a used count. It is
not deleted by the in-app deletion action; Settings explains this. iCloud Keychain behavior across reinstall,
new devices and offline simultaneous writes still requires device testing. This is not an authoritative
server-side multi-device entitlement service; local collection state is per installation.

## Interaction and mood colour

Boops briefly show a happy face; rubbing briefly shows a calm face. Neither changes the user's selected
mood or sends an unchosen mood to friends. The six labelled mood buttons, glow and widget accent use
mood colours; the creature's own material colour stays consistent. iOS may tint Lock Screen widgets.

## Acceptance evidence

Automated checks exercise daily counting, duplicate prevention, restored gaps, the three-use limit,
reset behavior, all milestones, migration and every decoded sprite. SwiftUI renders show the actual
screens and circular, rectangular and inline widget content. Haptics, touch feel, VoiceOver, iCloud
Keychain and two-device sharing still need signed physical-device acceptance.
