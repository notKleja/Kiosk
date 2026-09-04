# Kiosk

A small native macOS app for grabbing app icons. Search the Google Play Store or
the Apple App Store by app name, see results update as you type, then copy an icon
to the clipboard or save it as a PNG at 128–1024 px.

Built with SwiftUI and macOS 26's Liquid Glass, with no third-party dependencies.

![size](https://img.shields.io/badge/bundle-644%20KB-brightgreen)

## Requirements

- macOS 26 (Tahoe) or later
- Xcode command line tools (`xcode-select --install`)

## Build and run

```bash
./native/build.sh
open "native/build/Kiosk.app"
```

The script compiles `native/Sources/*.swift` with `swiftc`, assembles an `.app`
bundle, copies in the icon and ad-hoc signs it. There is no Xcode project to open.

## Using it

1. Type at least two characters — results refresh 250 ms after you stop typing.
2. Pick the store (Google Play or App Store), the icon size, and the storefront
   country. All three are remembered between launches.
3. On any row, the copy button puts the icon on the clipboard, and the size button
   writes a PNG into the save folder shown at the bottom. Use **Change** to pick a
   different folder.

Icons land as `<bundle id>_<size>.png`, for example `com.spotify.music_512.png`.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — how search, icon fetching, clipboard and
  saving work, and what breaks when the stores change.

## Licence

MIT © Kleja. See [LICENSE](LICENSE).
