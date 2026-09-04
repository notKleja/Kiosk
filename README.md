# Kiosk

A small native macOS app for grabbing app icons. Search the Google Play Store or
the Apple App Store by app name, see results update as you type, then copy an icon
to the clipboard or save it as a PNG at 128–1024 px. A `kiosk` command line tool
does the same thing without the window.

Built with SwiftUI and macOS 26's Liquid Glass, with no third-party dependencies.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode command line tools (`xcode-select --install`)

## Build and run

```bash
./native/build.sh
open "native/build/Kiosk.app"
```

The script compiles `native/Sources/*.swift` with `swiftc`, assembles a ~2 MB `.app`
bundle, copies in the icon and ad-hoc signs it. There is no Xcode project to open.
Prebuilt bundles are attached to each [release](https://github.com/notKleja/Kiosk/releases);
because they are ad-hoc signed, the first launch needs right-click → Open.

## Using it

1. Type at least two characters — results refresh 250 ms after you stop typing.
2. Pick the store, the icon size, the storefront country, and whether an icon smaller
   than the requested size should be upscaled (**Upscale**) or left at the store's
   maximum (**Max size**). All four are remembered between launches.
3. On any row, the copy button puts the icon on the clipboard and the download button
   writes a PNG into the folder shown at the bottom. Use **Change** to pick another.

Icons land as `<bundle id>_<pixels>.png` — for example `com.spotify.music_512.png` —
where `<pixels>` is the size actually delivered. Stores cap each icon at the size its
developer uploaded, so asking for 1024 px can legitimately return 512 px unless
**Upscale** is on. An existing file is never overwritten; the next one gets ` 2`,
` 3`, and so on.

## Command line

```bash
./native/build-cli.sh
./native/build/kiosk search spotify
./native/build/kiosk get telegram --store appstore --size 1024 --out ~/Icons
./native/build/kiosk get spotify whatsapp notion --out ~/Icons
./native/build/kiosk get "photo editor" --all --limit 10 --delay 500 --out ~/Icons
```

`search` lists bundle ids, ratings and names. `get` takes any number of queries and
downloads the first match of each, or every result with `--all`, or exact bundle ids
with repeated `--pkg`. Downloads are paced by `--delay` (250 ms by default) and a
progress bar is drawn on stderr when the terminal is interactive, so piping stays
clean. Rate limiting from either store is respected: an HTTP 429 or 5xx is retried up
to three times, honouring `Retry-After` and otherwise backing off exponentially.

Both commands accept `--store`, `--country`, `--limit`, `--size`, `--upscale` and
`--json`. Run `kiosk --help` for the full list.

## Tests

```bash
./native/tests/run.sh
```

Eighteen offline assertions covering the filename sanitiser, the icon-host allow-list
and URL construction. No network access required.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — how search, icon fetching, clipboard and
  saving work, how untrusted store data is handled, and what breaks when the stores
  change their markup.

## Licence

MIT © Kleja. See [LICENSE](LICENSE).
