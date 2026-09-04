# Architecture

Three Swift files, no dependencies.

| File | Role |
| --- | --- |
| `native/Sources/PlayStore.swift` | Talks to both stores and returns `PlayApp` values |
| `native/Sources/App.swift` | `IconModel`: state, debouncing, clipboard, saving, preferences |
| `native/Sources/ContentView.swift` | SwiftUI interface built on Liquid Glass |

## The app model

`PlayApp` is one search result: bundle id, display name, developer, rating, an icon
base URL, and the `StoreSource` it came from. The source decides how a size is turned
into a real URL, because the two stores template their artwork differently:

```swift
case .play:     "\(icon)=s\(size)-rw"          // …googleusercontent.com/<hash>=s512-rw
case .appStore: "\(icon)/\(size)x\(size)bb.png" // …mzstatic.com/…/512x512bb.png
```

This is the whole trick behind the app: both stores serve their icons from an image
CDN that resizes on demand, so any size up to 1024 px is a URL away and nothing has
to be upscaled locally.

## Searching

`PlayStore` is an `actor`, so all network work happens off the main thread and the
model can only touch it via `await`.

**App Store** uses Apple's public iTunes Search API — `https://itunes.apple.com/search`
with `entity=software` — and decodes the JSON. `artworkUrl512` has its last path
component stripped to leave the resizable base. Ratings come back as a double and are
rounded to one decimal.

**Google Play** has no public search API, so the store's search page is fetched with a
desktop user agent and parsed with regular expressions:

1. Find every `href="/store/apps/details?id=<package>"` link.
2. Take the 6000 characters that follow it as that result's block.
3. Inside the block, read the first `play-lh.googleusercontent.com/<hash>=sNN` URL as
   the icon, and pull the name, developer and rating out of `aria-label`, `DdYX5`,
   `wMUdtb` and `w2kbF`.

Duplicate packages are skipped, and results without an icon are dropped. Because this
depends on Google's markup, a change to those class names will break parsing — that is
the most likely thing to need fixing later. Google's old suggestion endpoint
(`market.android.com/suggest`) is gone, which is why suggestions come from running the
search itself rather than a cheaper autocomplete call.

## Typing, debouncing and stale results

`IconModel.query` schedules a search on every change. The pending task is cancelled,
and a new one waits 250 ms before hitting the network, so a burst of keystrokes costs
one request.

Every search increments a `generation` counter and captures its value. When a response
arrives it is discarded unless its generation still matches, which stops a slow early
request from overwriting the results of a later one.

## Clipboard

Copying converts the downloaded artwork to PNG through `NSBitmapImageRep`, then writes
three flavours to `NSPasteboard` so different apps can each take what they understand:

- a file URL in the temporary directory, named `<App Name> <size>px.png`
- an `NSPasteboardItem` carrying the PNG data and the app name as text
- an `NSImage`

Finder and file-oriented apps take the URL and keep the filename; editors take the
image; plain text fields get the name.

## Saving and preferences

Saving writes `<bundle id>_<size>.png` into the chosen folder, creating it if needed.
The folder is picked with `NSOpenPanel`. The app is not sandboxed, so a chosen folder
keeps working after a restart without security-scoped bookmarks.

Store, size, country and save folder are persisted in `UserDefaults` under the
`com.kleja.kiosk` domain and restored in `IconModel.init`.

## Interface

The UI uses the system Liquid Glass APIs rather than hand-made blur: `.glassEffect`
on the search capsule, result rows and the footer, `GlassEffectContainer` so nearby
glass shapes merge, and `.buttonStyle(.glass)` on the row buttons and the dropdown
triggers. The dropdowns are `Menu` with `.menuStyle(.button)`, which is what lets the
trigger itself be glass — a plain `Picker` renders as a standard bordered control.

Sizes are rendered with `Text(verbatim:)` so `1024px` is not localised into `1,024px`.

## Build

`native/build.sh` writes `Info.plist` (bundle id `com.kleja.kiosk`, minimum system
version 26.0), compiles all sources with `swiftc -O -parse-as-library` targeting
`arm64-apple-macos26.0`, copies `native/Resources/AppIcon.icns` in and ad-hoc signs the
bundle. Rebuilding after an icon change may need `lsregister -f` and `killall Dock`,
since macOS caches icons aggressively.
