# kiosk — command line guide

`kiosk` downloads app icons from the Google Play Store and the Apple App Store. It
searches by app name, then pulls the artwork from the store's image CDN.

```
kiosk search <query> [options]
kiosk get <query> [<query> …] [options]
kiosk --help | --version
```

## Setup

```bash
./native/build-cli.sh                          # builds native/build/kiosk
sudo cp native/build/kiosk /usr/local/bin/     # optional: put it on PATH
kiosk --version
```

The copy is a snapshot, not a link: after rebuilding, copy it again or the `kiosk` on
your `PATH` keeps running the old build. `kiosk --version` is the quickest check.

Every example below assumes `kiosk` is on your `PATH`. If it is not, use
`./native/build/kiosk` instead.

---

## 1. Finding apps

Search prints one row per result: bundle id, rating, name.

```bash
kiosk search spotify
```

```
com.spotify.music             Spotify: Music and Podcasts
com.spotify.tv.android  3.8★  Spotify: Music & Podcasts
com.spotify.s4a         3.6★  Spotify for Artists
fm.anchor.android       3.7★  Spotify for Creators
```

Search the App Store instead, and keep it short:

```bash
kiosk search notion --store appstore --limit 5
```

Search another storefront — useful for regional apps:

```bash
kiosk search stc --country sa
kiosk search "prayer times" --country sa --store appstore
```

Search several things at once:

```bash
kiosk search whatsapp telegram signal --limit 3
```

Get it as JSON for scripting:

```bash
kiosk search notion --json
kiosk search notion --json | jq -r '.[] | "\(.pkg)\t\(.name)"'
```

Search exits non-zero when nothing matched, so it works in conditionals:

```bash
if kiosk search "some obscure app" > /dev/null; then echo found; else echo none; fi
```

---

## 2. Downloading one icon

```bash
kiosk get whatsapp
```

Writes `com.whatsapp_512.png` into the current directory and prints the path.

Pick a size and a destination:

```bash
kiosk get whatsapp --size 1024 --out ~/Icons
```

Take it from the App Store:

```bash
kiosk get whatsapp --store appstore --size 1024 --out ~/Icons
```

Skip the guessing and name the app exactly:

```bash
kiosk get --pkg com.whatsapp --size 512 --out ~/Icons
kiosk get --pkg ph.telegra.Telegraph --store appstore --out ~/Icons
```

---

## 3. Downloading many icons

Each positional argument is one app; each gets its best match.

```bash
kiosk get whatsapp snapchat x github --size 512 --out ~/Icons
```

```
~/Icons/com.whatsapp_512.png
~/Icons/com.snapchat.android_512.png
~/Icons/com.twitter.android_512.png
~/Icons/com.github.android_512.png
```

Commas work the same way, which is handy when the list comes from somewhere else:

```bash
kiosk get "whatsapp, snapchat, x, github" --out ~/Icons
```

Several exact bundle ids:

```bash
kiosk get \
  --pkg com.spotify.music \
  --pkg com.snapchat.android \
  --pkg com.github.android \
  --size 512 --out ~/Icons
```

Every result of a search, not just the first — good for grabbing a whole category:

```bash
kiosk get "photo editor" --all --limit 10 --out ~/Icons
kiosk get snapchat --all --limit 5 --out ~/Icons     # Snapchat plus the lookalikes
```

From a file, one app per line:

```bash
cat apps.txt
# whatsapp
# snapchat
# notion

xargs -a apps.txt kiosk get --size 512 --out ~/Icons
```

Duplicates across queries and `--pkg` are collapsed before anything downloads, so
`kiosk get whatsapp --pkg com.whatsapp` fetches once, not twice.

---

## 4. Resolutions

`--size` is the simple case: it is both what is asked of the store and what you get.

```bash
kiosk get notion --size 256
```

Stores cap each icon at whatever master the developer uploaded, so a large request
can come back smaller. The CLI says so, and names the file after the real size:

```bash
kiosk get snapchat --size 1024 --out ~/Icons
# ~/Icons/com.snapchat.android_512.png  (store max 512px)
```

`--upscale` interpolates up to the size you asked for:

```bash
kiosk get snapchat --size 1024 --upscale --out ~/Icons
# ~/Icons/com.snapchat.android_1024.png
```

`--fetch` and `--out-size` split the two apart. Fetch the biggest master available,
then resample down — the sharpest way to make small icons:

```bash
kiosk get notion --fetch 1024 --out-size 128 --out ~/Icons
# ~/Icons/notion.id_128.png
```

It works in the other direction too; `--out-size` always produces exactly that size:

```bash
kiosk get snapchat --fetch 512 --out-size 1024 --out ~/Icons
# ~/Icons/com.snapchat.android_1024.png
```

A full sprite set for one app:

```bash
for size in 128 256 512 1024; do
  kiosk get notion --fetch 1024 --out-size "$size" --out ~/Icons
done
```

---

## 5. Pacing and rate limits

Downloads run one at a time with a pause between them, 250 ms by default.

```bash
kiosk get "wallpaper" --all --limit 30 --delay 750 --out ~/Icons   # gentle
kiosk get whatsapp snapchat --delay 0 --out ~/Icons                # no pause
```

`--delay` also paces the searches themselves, not just the icon downloads, since a
long batch does one search per name.

If a store rate-limits you anyway, an HTTP 429 or 5xx is retried up to three times,
honouring `Retry-After` — as seconds or as an HTTP date, clamped to a minute — and
otherwise backing off exponentially with jitter. A persistent 429 then makes `kiosk`
double its own pacing for the rest of the run, to a minimum of 1 s and a maximum of
10 s, and say so on stderr.

Nothing is silently dropped. An icon skipped because of a 429 goes back on a queue and
is retried once at the end of the run, after a longer pause; eight consecutive failures
stop the main pass and push everything still outstanding onto that same queue rather
than abandoning it. Whatever is still missing afterwards is listed by bundle id on
stderr:

```
kiosk: 2 not downloaded: com.example.one com.example.two
```

Other failures are reported as they happen and the run carries on. The exit status is
non-zero only if nothing at all was written.

---

## 6. Output and scripting

When stderr is a terminal you get a progress bar there:

```
[3/12] █████░░░░░░░░░░░░░ com.github.android
```

Redirect or pipe stdout and the bar stays out of the way — each written path is
printed as it lands:

```bash
kiosk get whatsapp snapchat x github --out ~/Icons > written.txt
```

`--json` prints one object per written file, with the real pixel size:

```bash
kiosk get spotify notion --json --out ~/Icons > written.json
jq -r '.[] | "\(.pkg) \(.pixels)px -> \(.path)"' written.json
```

```json
[
  {
    "name" : "Spotify: Music and Podcasts",
    "path" : "/Users/you/Icons/com.spotify.music_512.png",
    "pixels" : 512,
    "pkg" : "com.spotify.music"
  }
]
```

Search on one store, download from the other:

```bash
kiosk search notion --store appstore --json \
  | jq -r '.[].pkg' \
  | xargs -I{} kiosk get --pkg {} --store appstore --out ~/Icons
```

Quiet mode — keep only failures:

```bash
kiosk get whatsapp snapchat --out ~/Icons > /dev/null
```

---

## 7. Files

Icons are written as `<bundle id>_<pixels>.png`, where `<pixels>` is the size actually
produced. Nothing is overwritten: a name already in use gets ` 2`, ` 3`, and so on, so
running the same command twice leaves both copies.

```
com.spotify.music_512.png
com.spotify.music_512 2.png
```

Bundle ids from the stores are sanitised before they touch the filesystem, so odd
names cannot escape `--out`.

---

## 8. Option reference

| Option | Default | Meaning |
| --- | --- | --- |
| `--store <play\|appstore>` | `play` | Store to search. `google` and `apple` also accepted |
| `--country <cc>` | `us` | Storefront, e.g. `us`, `sa`, `gb`, `de` |
| `--limit <n>` | `20` | Results per search (1–50); with `--all`, how many are downloaded |
| `--size <px>` | `512` | Requested icon size, 16–4096 |
| `--fetch <px>` | `--size` | Size asked of the store, before resampling |
| `--out-size <px>` | — | Exact size of the written PNG, up or down |
| `--pkg <id>` | — | Download this exact bundle id. Repeatable |
| `--all` | off | Download every result of a query, not just the first |
| `--delay <ms>` | `250` | Pause between downloads, 0–60000 |
| `--out <dir>` | current dir | Destination, created if missing, `~` expanded |
| `--upscale` | off | Interpolate up when the store's icon is smaller than the request |
| `--json` | off | Machine-readable output |
| `--help`, `-h` | — | Usage |
| `--version`, `-v` | — | Version |

## 9. Exit status

| Code | Meaning |
| --- | --- |
| `0` | At least one icon written (or, for `search`, at least one result) |
| `1` | Nothing written, no results, or a bad argument |
