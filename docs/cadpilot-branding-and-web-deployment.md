# CadPilot branding and web deployment

## Product identity

- User-facing product name: **CadPilot**.
- The previous `CadPilot AI` label has been removed from app, browser, platform, documentation, and schema display text.
- Internal package IDs, method-channel names, storage keys, API environment names, and `.cadpilot` file compatibility remain unchanged.

## Brand assets

- `tablet_app/assets/branding/cadpilot-brand-master.png` is the untouched user-supplied logo artwork.
- `tablet_app/assets/branding/cadpilot-icon-master.png` is the square symbol-only icon derived from that artwork for small-size use.
- Web favicon/PWA icons and Android/iOS launcher icons are generated from the square icon master.

## Web deployment

- Production URL: https://cadpilot.vercel.app
- Flutter Web is built locally in release mode and deployed through Vercel's prebuilt static output path.
- Live verification confirmed HTTP 200, `<title>CadPilot</title>`, a successful favicon response, and Flutter bootstrap loading.

## Verification

- `flutter analyze --no-pub` passed.
- All 100 Flutter tests passed.
- Android debug APK built successfully.
- Flutter Web release build succeeded.

The generated icon asset used the built-in image editing workflow with the supplied logo as its reference.
