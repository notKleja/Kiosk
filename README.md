# Kiosk

Grab app icons from the Google Play Store and the Apple App Store — as a native
macOS app, or as a `kiosk` command line tool for scripts and bulk downloads.

Both search by app name and pull the icon straight from the store's image CDN, so
you get the real artwork at up to 1024 px rather than a screenshot of a listing.

Written in SwiftUI and AppKit with no third-party dependencies. The app bundle is
about 2 MB; the CLI is about 200 KB.

---

## Install

Requires **macOS 26 (Tahoe) or later** and the Xcode command line tools
(`xcode-select --install`).

```bash
git clone https://github.com/notKleja/Kiosk.git
cd Kiosk

./native/build.sh        # the app     -> native/build/Kiosk.app
./native/build-cli.sh    # the CLI     -> native/build/kiosk
```

Prebuilt app bundles are attached to each
[release](https://github.com/notKleja/Kiosk/releases). They are ad-hoc signed, so the
first launch needs right-click → **Open**.

To put the CLI on your `PATH`:

```bash
sudo cp native/build/kiosk /usr/local/bin/kiosk
```

---

## The app

```bash
open native/build/Kiosk.app
```

1. Type at least two characters. Results refresh 250 ms after you stop typing.
2. Choose the store, icon size, storefront country, and whether an undersized icon
   should be upscaled (**Upscale**) or left at the store's maximum (**Max size**).
   All four are remembered between launches.
3. On any row: the copy button puts the icon on the clipboard, the download button
   writes a PNG into the folder shown at the bottom (**Change** picks another).

---

## The CLI

```
kiosk search <query> [options]
kiosk get <query> [<query> …] [options]
kiosk --help | --version
```

### Searching

```bash
kiosk search spotify
```

```
com.spotify.music             Spotify: Music and Podcasts
com.spotify.tv.android  3.8★  Spotify: Music & Podcasts
com.spotify.s4a         3.6★  Spotify for Artists
fm.anchor.android       3.7★  Spotify for Creators
```

Add `--json` for a machine-readable array of `pkg`, `name`, `developer`, `rating`,
`icon` and `store`:

```bash
kiosk search notion --store appstore --limit 5 --json | jq -r '.[].pkg'
```

### Downloading

Every positional argument is one app name; each downloads its best match. Commas
work too, so `"whatsapp, snapchat"` is the same as two arguments.

```bash
kiosk get whatsapp snapchat x github --size 512 --out ~/Icons
```

```
~/Icons/com.whatsapp_512.png
~/Icons/com.snapchat.android_512.png
~/Icons/com.twitter.android_512.png
~/Icons/com.github.android_512.png
```

Other ways to choose what gets downloaded:

```bash
# every result of a search, not just the first
kiosk get "photo editor" --all --limit 10 --out ~/Icons

# exact bundle ids, no guessing
kiosk get --pkg com.spotify.music --pkg com.snapchat.android --out ~/Icons

# the Apple App Store instead, at full size
kiosk get telegram --store appstore --size 1024 --out ~/Icons
```

### Options

| Option | Default | Meaning |
| --- | --- | --- |
| `--store <play\|appstore>` | `play` | Which store to search. `google` and `apple` also work |
| `--country <cc>` | `us` | Storefront, e.g. `us`, `sa`, `gb` |
| `--limit <n>` | `20` | Results per search (1–50); with `--all`, how many get downloaded |
| `--size <px>` | `512` | Requested icon size, 16–4096 |
| `--fetch <px>` | `--size` | Size asked of the store, before any resampling |
| `--out-size <px>` | — | Exact size of the written PNG, resampled from what arrived |
| `--pkg <id>` | — | Download this exact bundle id. Repeatable |
| `--all` | off | Download every result of each query, not just the first |
| `--delay <ms>` | `250` | Pause between downloads. `0` disables it |
| `--out <dir>` | current dir | Where to write. Created if missing, `~` expanded |
| `--upscale` | off | Interpolate up when the store's icon is smaller than `--size` |
| `--json` | off | Machine-readable output |

### Filenames and sizes

Files are written as `<bundle id>_<pixels>.png`, where `<pixels>` is the size
actually delivered — stores cap each icon at whatever master the developer uploaded,
so a 1024 px request can legitimately come back as 512 px. `--upscale` interpolates
to the requested size instead; the CLI notes the cap either way:

```
~/Icons/com.snapchat.android_512.png  (store max 512px)
```

`--fetch` and `--out-size` split the two resolutions apart when you want the sharpest
possible small icon: fetch the largest master the store has, then resample down.

```bash
kiosk get notion --fetch 1024 --out-size 128 --out ~/Icons   # notion.id_128.png
```

Nothing is ever overwritten: an existing name gets ` 2`, ` 3`, and so on.

### Batches, progress and rate limits

Downloads run one at a time with `--delay` between them. When stderr is a terminal a
progress bar is drawn there, so redirecting stdout stays clean:

```
[3/12] █████░░░░░░░░░░░░░ com.github.android
```

Piped or redirected, each path is printed as it lands and no bar appears. A single
failed icon is reported on stderr and the batch continues; the exit status is
non-zero only when nothing was written at all.

If either store rate-limits you, an HTTP 429 or 5xx is retried up to three times,
honouring `Retry-After` when present and backing off exponentially when it is not.

### Scripting

```bash
# icons for a whole list of apps, one per line in apps.txt
xargs -a apps.txt kiosk get --size 512 --out ~/Icons

# capture what was written
kiosk get spotify notion --json --out ~/Icons > written.json
jq -r '.[] | "\(.pkg) \(.pixels)px -> \(.path)"' written.json
```

---

## Tests

```bash
./native/tests/run.sh
```

Eighteen offline assertions covering the filename sanitiser, the icon-host allow-list
and URL construction. No network access, no XCTest, no SwiftPM.

---

## How it works

App and CLI share the same `PlayStore` and `IconRenderer`. The App Store side uses
Apple's public iTunes Search API; Google Play has no public search API, so its search
page is parsed — which is the part most likely to need repair when Google changes
their markup.

Store data is treated as untrusted: filenames are sanitised, icon URLs must be https
on `play-lh.googleusercontent.com` or `mzstatic.com`, responses have timeouts and size
ceilings, and anything that does not decode as an image is rejected.

Full detail in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Licence

MIT © Kleja. See [LICENSE](LICENSE).
