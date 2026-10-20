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

- Install the same signed build on both; adopt different companions and select different moods.
- Invite B from A using Apple's private sharing sheet. Confirm B can see A after accepting.
- Invite A back from B. Confirm A now sees B. A single invitation is intentionally one-way;
  neither party receives permission to edit the other's name, creature, or mood.
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

The current version stores local state per installation. It publishes that installation's current companion
to the owner's private CloudKit record when connected. It does not yet reconcile two installations writing
different owner profiles under the same iCloud account; do not use two installations as simultaneous owners.
Friend updates use background CloudKit notifications and widget timeline fetches, both scheduled by iOS.
They are not guaranteed to arrive immediately.

## Apple references

- [CloudKit shared records](https://developer.apple.com/documentation/CloudKit/shared-records)
- [Apple CloudKit Sharing sample](https://github.com/apple/sample-cloudkit-sharing)
- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
