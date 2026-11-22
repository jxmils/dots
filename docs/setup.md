# Apple configuration and physical-device verification

The project contains the following proposed identifiers. They are configuration values, not a claim that
they have been registered in the developer account:

| Item | Identifier |
|---|---|
| App | `com.jasonmiller.dots` |
| Widget | `com.jasonmiller.dots.widget` |
| App Group | `group.com.jasonmiller.dots` |
| CloudKit container | `iCloud.com.jasonmiller.dots` |

## Required setup

1. In the Apple Developer account, register both bundle IDs. Assign the App Group and iCloud/CloudKit
   container to both. Enable Push Notifications for the main app.
2. In Xcode, select the intended development team on both targets. Keep automatic signing enabled.
   The entitlements are included in the repository; no certificates, keys or profiles belong in Git.
3. Run a signed development build, adopt a companion, and invite a friend. This creates the `Companion`
   record type and fields in the CloudKit development environment: `companionID` (String), `ownerName`
   (String), `petName` (String), `mood` (String), `kind` (String), and `updatedAt` (Date/Time).
   Sharing uses a private custom zone and private `CKShare`, not a public database or public links.
4. Before TestFlight, deploy the CloudKit schema to Production in CloudKit Console. TestFlight uses
   the production environment. Register the app in App Store Connect and configure a signing/upload
   workflow only after these identifiers and the schema exist.

No Apple account changes, CloudKit schema deployment, tester invitations, or App Store submission were
performed by the source generation or check scripts.

## Device acceptance checklist

Use two supported iPhones on current iOS, each signed in to a different iCloud account.

- Install the same signed build on both; hatch the free creature, rename it and select different moods.
- Rub and tap the egg, and test its accessible alternatives. Boop and pet the creature; verify the reaction
  does not alter the selected mood. Check Reduce Motion and haptics.
- Verify same-day mood changes count once, earned eggs reveal unowned creatures, and selection from
  Collection persists. Test gaps with each of the three lifetime restores, then a fourth gap.
- Delete and hatch again; confirm the restore budget remains used. Test the Keychain receipt after
  reinstall and on a second device, including offline changes, before claiming cross-device enforcement.
- Invite B from A with a new friend link. After B confirms mutual sharing, check both directions, then disconnect from B and confirm both lose access. Repeat with a full personal iCloud account. Signing out should show a sign-in prompt when sharing.
- Check that existing one-way Apple shares still have their original access.
- Test acceptance with the receiving app already running and with the app fully closed, including
  first launch before adoption.
- Change A's mood. Refresh B and check the displayed mood, companion style and original timestamp.
- Test two friends with different update times. Verify latest mode picks the newest one and pinning
  chooses the specified friend regardless of ordering. Test separate widget configurations.
- Add all three Lock Screen widget families and the small Home Screen widget. Test accented/tinted
  rendering, tap-to-open, Reduce Motion, long names, and larger accessibility text sizes.
- Turn off network access, change a mood, reconnect, and open the app. Verify local persistence and retry.
- Remove a participant in A's Manage sharing. Refresh B and confirm A disappears, including pinned widgets.
- Leave A's circle from B; confirm the received share disappears and the local widget selection clears.
- Delete A's companion; confirm the share is revoked, A returns to adoption, and B loses access after refreshing.
- Verify iCloud signed-out, restricted-account, unavailable-container, and missing-entitlement errors.
- Repeat on a second device using the same iCloud account before claiming multi-device owner sync.

## Current limitations

Version 1.0.1 restores the owner’s pet and collection from a device-only Keychain item on same-iPhone reinstall. Open the update once to protect existing pets. Explicit in-app deletion clears the recovery item. It publishes that installation's current companion
to the owner's private CloudKit record when connected. It does not yet reconcile two installations writing
different owner profiles under the same iCloud account; do not use two installations as simultaneous owners.
Friend updates use background CloudKit notifications and widget timeline fetches, both scheduled by iOS.
They are not guaranteed to arrive immediately.

## Apple references

- [CloudKit shared records](https://developer.apple.com/documentation/CloudKit/shared-records)
- [Apple CloudKit Sharing sample](https://github.com/apple/sample-cloudkit-sharing)
- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

## Production schema and mood-sync errors

A TestFlight error saying `Cannot create new type Companion in production schema` means the container's
production schema is missing the app's record type. Rebuilding or re-signing the app does not deploy it.

In [CloudKit Console](https://icloud.developer.apple.com/), select team `KY3DU2D7QL` and container
`iCloud.com.jasonmiller.dots`. Inspect Development record types and verify `Companion` has all six fields
listed above. Also verify the private-sharing schema created by a successful development invitation.
Choose **Deploy Schema Changes**, review the additive types and fields, deploy, then inspect Production
to confirm they are present. Do not reset environments or delete records. Finally test a mood update and
an invitation between two TestFlight devices; a successful archive is not evidence of working CloudKit sync.

The app keeps mood updates locally and reports background sync failures under **My circle**, with a retry
button. It never puts CloudKit record IDs or server diagnostics into the mood-selection alert. This calmer
error handling is separate from, and does not substitute for, the production schema deployment.

See Apple's [schema deployment instructions](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).


## Device-only mood test friend

In a TestFlight build (or a DEBUG build), hold the **dotlings** wordmark for three seconds, then choose **Add test friend on this device**. This is deliberately opt-in: new installs have no test friends, and ordinary App Store builds do not expose the control. It is not tied to a name such as Jason or enabled for every tester.

The local Sky companion appears as **Test friend** in My circle. While the app is active it cycles Happy → Calm → Sleepy → A little low → Overwhelmed → Focused → Sick → Studious → Working Out, every five seconds. The open detail view follows the current mood. The clock stops running in the background; reopening catches up from the saved start time. Nothing is sent to CloudKit, and the user's mood, check-in streak and collection are unaffected. Cloud refreshes preserve this local friend.

You can pin it to a widget, but widget refresh timing is controlled by iOS: the five-second cadence is an in-app test, not a promise of Lock Screen refresh frequency. In the friend's profile, choose **Remove test friend** to remove it and clear its pin. Normal App Store launches remove this testing data. This test does not validate real friend sharing or replace deploying the CloudKit production schema.

### Mutual friend links

Both phones use separate signed-in iCloud accounts. New links use the public CloudKit database in the existing Dotlings container. The schema in `Friends/Dotlings.ckdb` grants creation and reading to signed-in accounts and limits writes to the creator of each record. Names and moods are encrypted on the device. Each invitation reserves a pair of record IDs. Its recipient can claim their ID once. Subsequent mood updates use a key derived from both devices’ Curve25519 keys. Ending a connection clears its payload and reserves its ID against reuse.

Check invitations from Messages and the manual paste flow on two signed-in iPhones. Check an update in each direction, expiry, a forwarded link, disconnection, widget refresh and a full personal iCloud account. Older private CKShare invitations keep their original permissions. Firebase artifacts in `Friends/` describe a previous TestFlight build only.

### Friend mood alerts

The app offers **Friend mood notifications** under **Your profile → Your circle**. For the public friend-link flow, deploy the queryable String field `DotlingFriendSlot.moodTopic` from `Friends/Dotlings.ckdb` before distributing this build. The topic is derived from the friend's opaque slot ID. It contains no name or mood. New clients set it when they publish an encrypted update. Older private iCloud shares use the existing shared-database subscription.

To test, connect two iPhones on separate iCloud accounts, enable notifications on the receiving phone and allow the iOS prompt. On the sending phone choose Sick, Studious, then Working Out, allowing each change to sync. Check with the receiver in the foreground and background. Each alert should open My circle. Repeating a mood, renaming the pet or cycling the local test friend should stay quiet. Turning alerts off should also keep the phone quiet. iOS can delay or combine background updates.

In a friend's profile, **Unpin from my widget** returns widgets using the app setting to the latest shared mood. A widget configured directly in iOS to show one specific friend keeps that selection.
