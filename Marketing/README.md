# Dotlings launch kit

The public app name is Dotlings. Registered Apple identifiers and the Dots Xcode scheme are retained.

## Upload map

- Header: `app-store/header-3840x1646.png` or `app-store/universal-5244x2950.png`.
- Search Results: `app-store/search-results-3840x2560.png`, its 1920x1280 version, or the universal 5244x2950 image.
- App Previews and Screenshots: upload the eight numbered PNGs from `screenshots/6.9-inch` in order. A matching 6.5-inch set is included.
- The 1024px app icon is compiled into the app. SVG and transparent PNG logos are for brand use, not screenshot/header upload.
- Listing copy: `listing-en-US.txt` and `listing-en-US.json`.
- Privacy Policy URL: https://github.com/jxmils/dots/blob/main/docs/privacy.md
- Support URL: https://github.com/jxmils/dots/blob/main/docs/support.md

The uploadable creative images are opaque sRGB PNGs. Header and search exports follow Apple's creative asset dimensions. Screenshots show native iPhone simulator captures of the app UI with fictional sample profiles. The capture harness is compiled only in Debug, and is excluded from release builds.

## Reproduce

The Dotlings store captures workflow builds the Debug app and captures eight native screens with `Tools/capture-store.sh`. Download its `dotlings-native-screenshots` artifact and pass that folder to:

    bash Tools/marketing.sh /absolute/output/folder /absolute/native/capture/folder
    python3 Tools/audit-marketing.py /absolute/output/folder

Marketing exports use the actual app capture on the search creative and screenshot cards. The original creature assets are generated with built-in image_gen; exact prompts and source provenance are in Brand/prompts.json. Layout and type are code-rendered. Logos include font-independent SVG outlines. Nunito ExtraBold is bundled under the SIL Open Font License in Brand/Fonts/OFL.txt.

## Before App Review

The app record has been created by the owner. This kit does not submit an app or upload a signed build. App Store Connect still needs a signed build, private reviewer contact email/phone, completed age rating and privacy declarations, pricing/availability, and production CloudKit verification. Enter accurate accessibility declarations only after device checks. There is no separate Dotlings login. The review-notes draft describes optional iCloud sharing and the first hatch.

App Preview video and iPhone Duo captures are not included. These optional assets need footage/captures from the corresponding supported experience.

Apple references checked 21 October 2026:
- https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- https://developer.apple.com/app-store/asset-best-practices/
