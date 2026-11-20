# Dotlings Privacy Policy

Effective date: 20 November 2026

Dotlings is provided by Jason Miller. This policy explains the information used by the iPhone app and its widgets.

## Information you choose to provide

You choose a first name or nickname, names for your companions, a preferred companion, and one of the available moods. You do not create a separate Dotlings account, enter an email address or phone number, upload contacts, or give the app access to your location, camera or microphone.

Your device stores your companion collection, names, current mood, check-in dates, streak progress, earned eggs, used streak restores, friend list and widget preferences. A generated identifier distinguishes your shared companion from other companions. Widgets use a shared on-device copy of the information needed to display your selected friend's latest received mood.

## When you invite a friend

Starting with version 1.0.1, friend links use Google Firebase. When you choose to send or accept a link, Dotlings creates a random account ID for your device. This works without an email, password or iCloud sign-in. Firebase handles that ID and the connection information needed to provide the service. The app keeps the credentials for that ID in your device’s Keychain so the app and its widget can fetch updates.

When you invite someone, Dotlings stores your chosen name, pet name, pet appearance, latest mood and update time in its Firebase database. It also stores invitations, their expiry dates and the IDs of connected friends so it can check who has access. A new friend link gives you and the first person who accepts it access to each other’s chosen name, Dotling and current mood. The app explains this before they accept. Send each link directly to the person you want to invite. Unused links expire after seven days. Earlier one-way invitations keep their original permissions. Firebase hosts the invitation page and processes service data under [Google’s privacy policy](https://policies.google.com/privacy).

Earlier iCloud invitations still use Apple’s CloudKit. For those connections, your shared companion and latest mood use your private iCloud database. [Apple’s privacy policy](https://www.apple.com/legal/privacy/).

## How information is used

Information is used to display and name your companions, remember your chosen profile companion, record daily check-ins and rewards, enforce the three lifetime streak restores, share the mood you explicitly select, and show the latest received friend information in widgets. Playing with a companion does not automatically change or share a mood.

Dotlings does not include advertising, third-party analytics or tracking SDKs. We do not sell personal information, use it for targeted advertising, or send your mood to an AI chat service.

## Retention, sharing controls and deletion

Starting in 1.0.1, opening Dotlings saves a recovery copy of your own companion, name, mood, collection, progress and sharing preference in this iPhone’s Keychain. Dotlings reads it on reinstall on the same device. It excludes friends and their moods. Deleting your companion inside Dotlings also clears this copy. Other local information is removed when you delete the app, subject to Apple's device backup and storage behavior. In Your profile, open Manage friend links to turn off a link. Use Manage older iCloud invitations for invitations sent with version 1.0. You can leave another person's circle from their details screen.

The Delete my companion & shared mood action removes your local companion, collection, check-in progress, cached friend list and preferences, and deletes your Firebase identity, your shared mood, your invitations and your followed-friend list. It also deletes your private CloudKit sharing zone if you used older Apple invitations. Removing your own information does not delete a friend's independently owned record. Changes to access take effect on another person's cached screen or widget after that device successfully refreshes; information they have independently copied cannot be recalled by the app.

A small Keychain receipt containing only the number of used lifetime streak restores is retained separately so deleting or restarting a companion does not replenish the three-use allowance. Where enabled, this receipt can sync through iCloud Keychain. It does not contain your name, mood, friend list or companion collection. Apple's backups and iCloud account controls may retain or manage additional copies under Apple's policies.

## Support and this website

For support or privacy questions, email Jason Miller at [jasonversamiller@gmail.com](mailto:jasonversamiller@gmail.com). If you email us, we use your email address and the information in your message to respond to your request. Please do not send passwords or Apple Account credentials.

You can also submit a general question at https://github.com/jxmils/dots/issues/new/choose. GitHub issues are public: include a general description rather than private names, moods, Apple Account details or other sensitive information. GitHub processes website visits and submitted issue information under its own privacy statement: https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement.

## Changes and contact

We will update this policy and its effective date when the app's information practices change. For questions about this policy or your information, contact Jason Miller at [jasonversamiller@gmail.com](mailto:jasonversamiller@gmail.com) or visit the support page: https://github.com/jxmils/dots/blob/main/docs/support.md.
