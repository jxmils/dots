# Build and upload Dotlings

The **Build and upload Dotlings** GitHub Actions workflow runs on pushes to `main`, pull requests,
and manual dispatch. Pull requests only check and archive without signing. On `main`, passing checks
are followed by a separately signed archive, App Store package export, upload and Apple processing check.
It uploads to the existing Dotlings app record, **6825127572**, with bundle ID **com.jasonmiller.dots**.
The registered Apple team is **KY3DU2D7QL**. Public repository variables `APPLE_APP_ID` and
`APPLE_TEAM_ID` can override those defaults; the workflow verifies that the app record matches Dotlings.

## One-time credentials

Add repository secrets at https://github.com/jxmils/dots/settings/secrets/actions.
Never commit these values or include them in screenshots, chat messages or Actions artifacts.

| Secret name | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | The Key ID of a team App Store Connect API key. |
| `APP_STORE_CONNECT_ISSUER_ID` | Its Issuer ID, shown in App Store Connect. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The entire original `.p8` PEM file, including its BEGIN/END lines. |
| `BUILD_CERTIFICATE_BASE64` | Base64 contents of an Apple Distribution `.p12` containing its private key. |
| `P12_PASSWORD` | The password used to export that `.p12`. |
| `APP_PROVISION_PROFILE_BASE64` | Base64 App Store Connect profile for `com.jasonmiller.dots`. |
| `WIDGET_PROVISION_PROFILE_BASE64` | Base64 App Store Connect profile for `com.jasonmiller.dots.widget`. |

An existing team API key can be reused if its role has access to upload builds for Dotlings.
Developer access is sufficient for this workflow; it does not create Apple certificates or profiles.
Use a team key: the workflow authenticates with an Issuer ID, and does not support individual keys.
Secrets saved in another repository are not automatically available here, and their values cannot
be read back from GitHub. Retain the original `.p8` download. A GitHub SSH key or PAT is not an Apple API key.

Create the team key in App Store Connect → Users and Access → Integrations → App Store Connect API →
Team Keys. The first API access request may require Account Holder approval. Apple only offers the
private `.p8` download once. Use an existing downloaded key when possible.

Both profiles must be App Store Connect distribution profiles, signed by the same certificate as the
`.p12`, for the registered team. Enable `group.com.jasonmiller.dots` and `iCloud.com.jasonmiller.dots`
with CloudKit on both App IDs. The app also needs Push Notifications. Generate profiles after configuring
these capabilities. The workflow checks the team, bundle IDs, expiration, production iCloud, App Group,
certificate match and push environment before the signed archive.

On a Mac, copy Base64 directly to the clipboard, then paste it into the matching GitHub secret:

```sh
base64 -i '/absolute/path/Distribution.p12' | pbcopy
base64 -i '/absolute/path/Dotlings_App_Store.mobileprovision' | pbcopy
base64 -i '/absolute/path/Dotlings_Widget_App_Store.mobileprovision' | pbcopy
```

Run one line at a time. Each replaces the clipboard. The file paths above are examples.
The `.p8` secret is its original text, not Base64. A `.cer` without its matching private key is not a `.p12`.
Cloud-managed signing in Xcode Cloud does not automatically install signing material in GitHub Actions.

## Running and checking an upload

1. Open Actions → Build and upload Dotlings → Run workflow → select `main`.
2. The check job verifies behavior, sprites, release automation and an unsigned native iOS archive.
3. The upload job installs temporary signing material and checks App Store Connect access.
4. It chooses a numeric build number greater than every existing build's first component. Both targets
   receive the same version and build number. Upload jobs are serialized, including manual reruns.
5. It signs and verifies the app and widget with production CloudKit and push entitlements, then exports
   and uploads the App Store package. Credentials are removed from the hosted runner even after failure.
6. Apple processing is polled for up to 20 minutes. Only `VALID` is reported as successful processing.
   The job summary links TestFlight; logs and `apple-upload-receipt.json` are retained for 14 days.

The workflow never submits for App Review or releases publicly. No API keys, certificates,
provisioning profiles, keychains or `.ipa` packages are uploaded as GitHub artifacts.
Release builds do not include the Debug screenshot capture harness.

If credentials are missing, the upload job fails with their names before a signed build is attempted.
After adding them, rerun the failed job or dispatch a fresh workflow; never paste secret values into a log.
If the upload succeeded but processing is pending or the network failed afterward, check TestFlight
and the retained receipt before retrying. The workflow does not automatically retry an upload.

Before testing invitations, deploy the CloudKit schema to Production in the CloudKit Console. Signing
with production entitlements does not deploy the schema. Two real devices with different iCloud accounts
are still needed to verify invitations and widgets. Choose internal/external testers in App Store Connect.

## References

- https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
- https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile
- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
