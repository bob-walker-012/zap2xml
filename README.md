# zap2xml (grid-affiliates fork)

Docker/Unraid container for [zap2xml](https://github.com/spencerlandis/zap2xml), grabbing XMLTV guide data from
**`https://tvlistings.gracenote.com/grid-affiliates.html?aid=orbebb`** and writing it to an output file you choose.

Forked from `spencerlandis/zap2xml` (which itself came from the old `shuaiscott` / `michaelbarany` images). Upstream
image `michaelbarany/zap2xml` has not been rebuilt in 8+ years and its grabber calls the legacy `gapzap` affiliate id,
which Gracenote now answers with `400 No lineups are available for this ZIP`.

## What this fork changes

| Change | Detail |
| --- | --- |
| Affiliate id | `gapzap` → **`orbebb`**, used for both `aid=` and `AffiliateID=`, overridable with `-Q` / `AFFILIATE_ID` |
| Grid request | Now matches what the grid-affiliates page actually sends: `lineupId=` (empty), `headendId=<id>`, `country`, `timezone`, `device`, `postalCode`, `pref`, `userId=-`, `aid`, `languagecode` |
| Login | Kept — `USERNAME`/`PASSWORD` for a TV Listings account, plus an account-free path with `LINEUP_ID` + `ZIPCODE` |
| Output file | `OUTPUT_FILE` (default `/data/xmltv.xml`), or `-o <file>` directly; written to `.tmp` then atomically moved so readers never see a half file |
| Storage | `/data` volume for the XMLTV file + cache, so it survives container updates |
| Unraid | `PUID`/`PGID`/`UMASK`, `TZ`, non-root drop via `su-exec`, healthcheck, ready-made template XML |
| HTTP | Optional built-in `httpd` on port 8080 (busybox, no apache) for clients that want a URL instead of a file |
| Image | `ghcr.io/bob-walker-012/zap2xml`, built for `linux/amd64` + `linux/arm64` by GitHub Actions |

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `USERNAME` / `PASSWORD` | *empty* | TV Listings account. Optional — leave blank and use the lineup instead |
| `USERNAME2` / `PASSWORD2` | *empty* | Second account; both grabs get sorted and merged into one file |
| `LINEUP_ID` | *empty* | Provider headend id (e.g. `WA46626`). Used when no login is set |
| `ZIPCODE` | *empty* | Postal code for the lineup (e.g. `98101`) |
| `AFFILIATE_ID` | `orbebb` | Gracenote affiliate id from `?aid=` |
| `OUTPUT_FILE` | `/data/xmltv.xml` | Where the XMLTV file lands |
| `OPT_ARGS` | `-U -D -I` | Extra `zap2xml.pl` flags (`-a` all channels, `-d 7` days, `-I` icons, `-D` details… ) |
| `SLEEPTIME` | `43200` | Seconds between refreshes (12 h) |
| `RUN_ONCE` | `false` | `true` = grab once and exit (handy for cron-driven setups) |
| `ENABLE_HTTP` | `true` | Serve the output dir over HTTP on `HTTP_PORT` |
| `HTTP_PORT` | `8080` | HTTP port inside the container |
| `PUID` / `PGID` | `99` / `100` | Owner of the files (Unraid `nobody`/`users`) |
| `UMASK` | `022` | File mode mask |
| `TZ` | `America/New_York` | Container timezone |

### Finding your LINEUP_ID

1. Open `https://tvlistings.gracenote.com/grid-affiliates.html?aid=orbebb`, pick your provider (Change Provider).
2. Press F12 → Console → run:
   ```js
   JSON.parse(localStorage['zap2it.providerData.provider']).headendId
   ```
3. That id (`WA46626`, `PC:…`, etc.) is `LINEUP_ID`; the postcode you entered is `ZIPCODE`.

With a login you don't need either — the account's saved provider is used automatically.

## Docker

```bash
docker run -d --name zap2xml \
  -p 8080:8080 \
  -v /mnt/user/appdata/zap2xml:/data \
  -e TZ=America/Los_Angeles \
  -e LINEUP_ID=WA46626 -e ZIPCODE=98101 \
  -e OUTPUT_FILE=/data/xmltv.xml \
  -e OPT_ARGS="-U -D -I -a" \
  ghcr.io/bob-walker-012/zap2xml:latest
```

Output: `/mnt/user/appdata/zap2xml/xmltv.xml`, or `http://<host>:8080/xmltv.xml`.

## Unraid install

### Option A — template file (2 minutes)

1. Copy [`unraid/zap2xml.xml`](unraid/zap2xml.xml) to your Unraid box:
   `/boot/config/plugins/dockerMan/templates-user/my-zap2xml.xml`
   ```bash
   wget -O /boot/config/plugins/dockerMan/templates-user/my-zap2xml.xml \
     https://raw.githubusercontent.com/bob-walker-012/zap2xml/master/unraid/zap2xml.xml
   ```
2. Unraid → **Docker** → **Add Container** → template dropdown → **zap2xml**.
3. Fill in `ZIPCODE` + `LINEUP_ID` (or `USERNAME`/`PASSWORD`), hit **Apply**.
4. Guide file appears at `/mnt/user/appdata/zap2xml/xmltv.xml`.

The template also works via **Docker → Add Container → Template: paste URL** with the raw GitHub URL above.

### Option B — manual

Docker tab → Add Container → Name `zap2xml`, Repository `ghcr.io/bob-walker-012/zap2xml:latest`,
Network Bridge, port `8080 → 8080`, path `/mnt/user/appdata/zap2xml → /data`, then add the env vars from the table.

### Pointing Plex / Emby / Jellyfin at it

Use the file path directly (best), or add the URL as an XMLTV guide source:
`http://<unraid-ip>:8080/xmltv.xml`.

## Building locally

```bash
git clone https://github.com/bob-walker-012/zap2xml.git
cd zap2xml
docker build -t zap2xml:local .
docker run --rm -e LINEUP_ID=WA46626 -e ZIPCODE=98101 -e RUN_ONCE=true \
  -v "$PWD/data:/data" zap2xml:local
```

Pushing a tag (`git tag v1.0.0 && git push --tags`) publishes `ghcr.io/bob-walker-012/zap2xml:1.0.0`, `:1.0`, `:latest`.
Make the GHCR package public once (GitHub → your profile → Packages → zap2xml → Package settings → Change visibility)
or Unraid's pull will 401.

## Notes

- `zap2xml.pl` is third-party code marked *"for personal use only, not for redistribution"*. This fork keeps that
  notice intact — use it for your own guide data.
- Gracenote serves ~275 channels for a typical US lineup; `-a` includes every channel, otherwise only favourites from
  your TV Listings account are exported.
- Full grabs with `-D -I` take a while (details = one extra request per program, throttled). If you hit rate limits,
  raise `SLEEPTIME` or drop `-D`.
