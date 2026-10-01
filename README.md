# vekrona.github.io

GitHub Pages site for the [vekrona](https://github.com/vekrona/vekrona) project.

## Layout

- `index.html`: main page
- `CNAME`: custom domain `vekrona.com` for GitHub Pages
- `LICENSE`: MIT
- `.nojekyll`: tells GitHub Pages to serve every file as it is, so `README.md` and `TODO.md` are public too
- `.gitignore`: keeps `capture/out/` (raw captures and build leftovers) out of git
- `.shellcheckrc`: settings for `shellcheck capture/*.sh`
- `TODO.md`: out-of-scope problems found while building the site and its capture pipeline
- `404.html`: not-found page, served by GitHub Pages for any unknown path (absolute asset paths, `noindex`)
- `robots.txt`, `sitemap.xml`, `site.webmanifest`: crawler and install metadata
- `favicon.svg`: source of every icon; `favicon.ico` and `apple-touch-icon.png` sit in the root where crawlers look for them
- `assets/css/`: stylesheets
- `assets/js/`: small vanilla-JS enhancements (screenshot lightbox); unobtrusive, the page works fine without it
- `assets/img/`: images; every screenshot ships as `<name>.webp` (full size, what the lightbox opens) plus `<name>-480|768|1280.webp` and the same set as `.avif`, picked by `srcset`/`sizes` in a `<picture>`
- `assets/icons/`: 192 and 512 px PNG icons referenced by `site.webmanifest`
- `assets/fonts/`: self-hosted latin woff2 subsets (Atkinson Hyperlegible Next, variable 200-800; JetBrains Mono, weight 400) with their SIL OFL texts; the page makes no third-party requests
- `assets/video/`: videos and `poster.webp` (1280 px wide)
- `capture/`: scripts that regenerate screenshots and promotional video from the vekrona VM harness (the `.gitkeep` only keeps the directory)
  - `screenshots.sh [scene...]`: shoots the named scenes on the VM into `capture/out/screenshots/<scene>.png`, then runs `og.sh` (when `hero` was shot), `images.sh` for exactly those scenes, and `check-images.sh`. No arguments runs every scene, including `terminal-ops`. An unknown name is an error that lists the valid ones, before anything touches the VM. The Firefox pane in most scenes shows this site, whose hero image is itself a screenshot of the hero scene. So when `hero` is selected the script shoots it `HERO_PASSES` (2) times, re-encoding the hero images and uploading the site copy to the guest after each pass: the second pass shows the first pass inside its Firefox pane, and every other scene shows the second. No README note, no manual second run. A failing scene stops the run with `screenshots.sh: scene <name> failed (exit N)` and a non-zero exit status
  - `record.sh [clip...]`: the same selection for clips. Each clip is recorded to `capture/out/<clip>.partial.mp4`, checked to be a readable 1920x1080 video, and only then moved to `capture/out/<clip>.mp4`, so a failed or interrupted recording never replaces a good clip. A recorder that died mid-clip or dropped frames fails the clip with its log. The theme clip records again when DMS shows an error toast. The lock clip is recorded with `wf-recorder` like the others (see `scenes.sh`)
  - `video.sh`: host-only, assembles `assets/video/vekrona-promo.mp4`, `.webm` and `poster.webp` from all clips in `capture/out/`; it needs every clip to exist, so it never records anything itself. The clips are cross-faded (0.6 s) as pictures only. Captions are not part of that picture: each is rendered on its own transparent canvas (opaque box, bottom right, 30 pt) and overlaid afterwards, fading in during the second half of the cross-fade into its segment and out during the first half of the cross-fade out of it, so two captions are never visible together and nothing shows through the box. The two cards are drawn by `card.sh`, the same composition as `og.png`. The `SEGMENTS` table at its top is the single place for clip order, slot lengths and captions. Each row is `kind|slot seconds|clip name or card title|caption or card subtitle|fit`. Before it encodes anything it checks every clip name against `catalog.sh`, every caption, and every clip against its slot: with an empty `fit` a clip may be at most 3 s shorter (frozen on its last frame) or 0.5 s longer (cut off) than its slot; with `compress:HEAD:TAIL` a longer clip keeps its first HEAD and last TAIL seconds at normal speed and the middle is sped up evenly to fill the rest of the slot, at most 8x (the run prints the factor); a clip not longer than its slot is left alone, HEAD and TAIL must be above 0 and together shorter than the slot, and a clip more than 3 s shorter than its slot still fails. It also fails if a result is not the table's total length or if `index.html` states another length ("Video tour, N seconds", "vekrona in N seconds", the JSON-LD `PT..M..S` duration). Results are built in `capture/out/video-build/` and moved into `assets/video/` only when they pass
  - `check-images.sh [site-dir]`: host-only, parses `index.html` and `404.html` with Python's `html.parser` (`srcset` attributes split over several lines included) and fails when a referenced file is missing, a candidate's real pixel width differs from its `w` descriptor, or a file in `assets/img` is not referenced by exact name by the pages, stylesheets, scripts or manifest. `site-dir` defaults to the repo root; a copy of the tree can be checked instead. `screenshots.sh` runs it last; it runs standalone too
  - `catalog.sh`: the one list of scene and clip names (`SCREENSHOT_NAMES`, `CLIP_NAMES`) and the name check shared by `screenshots.sh`, `record.sh` and `images.sh`. A scene `foo-bar` is the function `scene_foo_bar` in `scenes.sh`, a clip the function `record_foo_bar`; adding one means adding its name to `catalog.sh` and writing that function
  - `scenes.sh`: the scene and clip functions, `capture_init` (checks the guest's tools, copies the finished site to `/tmp/vekrona-capture/site` in the guest, starts the site server, enables the idle inhibitor, stops the Tailscale tray service, resets btop's config, replaces the user's avatar after remembering the previous one) and the exit teardown. First thing, before anything touches the guest, it takes a non-blocking `flock` on `$XDG_RUNTIME_DIR/vekrona-capture-<vm>.lock`; a second run (`screenshots.sh` or `record.sh`, whichever) fails at once, naming the holder (pid and command), without touching the guest or the other run's files, and without any teardown. A run that finds leftovers of a killed earlier run in the guest (`/tmp/vekrona-capture`, the server unit, the recorder unit) restores the guest first and says so. Every run, successful or failed, ends by restoring the guest: recorder stopped, windows and panels closed, previous avatar back, clipboard and notification history emptied, theme back to tokyo-night, tray service restarted, idle inhibitor released, site server stopped (port 443 free again), `/tmp/vekrona-capture` removed; it prints each step as `restored: ...`. Every restore step is attempted on its own: a step that fails prints `NOT restored: ...` with its error and the remaining steps still run; the teardown then lists everything it could not restore and the run exits non-zero (`restoring the guest session failed, check it by hand`). Closing the capture's own processes (`end_process` in `remote.sh`) waits 15 s for a polite exit after the windows are closed; if the process is still there it says so on stderr, sends SIGTERM, waits 5 s, then SIGKILL, and fails only if the process survives that. It acts on the capture's Firefox by its profile path only (never another Firefox) and on `ghostty`, `btop` and `rofi` by name. A failing step is named (`scene hero failed (exit 1)`), and SIGINT or SIGTERM names the interrupted step before the teardown runs. Every scene that shows the desktop waits, through one function (`wait_for_focused_window` in `remote.sh`), for the bar's focused-window chip ("Ghostty • vekrona") to be drawn, see "The site address" below. Every scene also begins with `begin_scene`, which waits until the bar's weather widget shows a temperature (`wait_for_weather`; the host screenshots the bar and reads its middle with `tesseract`, because DMS keeps no weather cache: a freshly started shell shows a sun icon and "--°C" until its fetch finishes, and keeps showing it for tens of seconds when the guest has no working DNS). The notification history reset, which restarts the shell, waits the same way (`empty_notification_history`). The wait fails after 90 s naming the likely cause (no internet or DNS in the guest). The temperature itself is DMS's live reading for its default location (New York), so it follows the real weather and differs between shoots hours apart The lock clip is a real `wf-recorder` recording of the real chord: the desktop, Hyper+Escape locks the session, the password is typed one key at a time (`LOCK_TYPING_INTERVAL` apart, so each dot appears on its own), Enter unlocks it, and the clip ends on the unlocked desktop. `wf-recorder` does see the lock surface (measured: 30 fps, the dots appear one per key); only the few frames in which sway has attached the lock surface but the lock client has not drawn yet are black, and `drop_black_frames` removes them (the preceding desktop frame is held for that moment, so the lock screen appears with a hard cut). The keybindings clip opens its panel before the recording starts, because the panel is a black rectangle for about 0.1 s while it fills in; the clip starts on the filled panel
  - `site-server.py`: the static HTTPS file server the capture runs in the guest (a few lines of the Python standard library: `http.server` with a TLS socket, bound to 127.0.0.1)
  - `card.sh`: the title and end cards. `render_card WIDTH HEIGHT TITLE SUBTITLE OUT` draws the blurred hero as backdrop with the wordmark and subtitle in the palette of `common.sh`; point sizes scale with the width (the 1200x630 `og.png` is the reference), and a long title shrinks to fit three quarters of the width. `og.sh` and `video.sh` both call it, so the social card and the video cards cannot drift. `page_tagline` reads the tagline from the `<title>` of `index.html` (the part after "vekrona — "), so `og.png` and the page title cannot drift either
  - `remote.sh`: the guest-side functions (predicates, panels, recorder, teardown, the terminal scene's preconditions and snippet), sent over SSH in front of every command. The whole script is written to a temporary file in the guest and run from there with `/dev/null` as stdin, so a guest command that reads stdin cannot swallow the rest of the script. It has no side effects when sourced; scenes that need an unlocked, powered-on output ask for it through `begin_scene`. `shared.sh` (`wait_for`, the guest directory and the installer command line) is sent along and sourced on the host, so there is one of each
  - `firefox-user.js`: preferences for the throwaway Firefox profile of the Firefox scenes (no VPN toolbar button, no experiments, no default-browser prompt, no telemetry notice). Its proxy preferences send every request to a closed local port, so Firefox's own background fetches (Remote Settings, Nimbus experiments and the like) fail at once instead of hanging when the guest has no working internet or DNS; a request in flight at quit time held Firefox's shutdown for 20 to 30 s and, left alone, until its shutdown watchdog crashed it. The script appends `network.dns.localDomains` and the proxy exception (`network.proxy.no_proxies_on`) for the site's host when it starts Firefox
  - `common.sh`: host-only paths, the palette (`og.sh`, `video.sh` and the avatar use it) and small helpers, among them `publish_files`, through which every generated asset is moved into place with mode 644 (a `mktemp` file would keep mode 600); it never needs the VM. `lib.sh` adds the VM access (finds the VM's IP, runs commands over SSH, copies files, takes screenshots and recordings)
  - `og.sh`: host-only, builds the social-preview card `assets/img/og.png` from the captured hero (`capture/out/screenshots/hero.png`) with `card.sh`; `screenshots.sh` calls it, and it runs standalone without the VM. Its tagline is the page title's: currently "Fedora Sway desktop for work and gaming", which `og:image:alt` and `twitter:image:alt` in `index.html` quote
  - `images.sh`: host-only, turns every raw screenshot in `capture/out/screenshots/` into its web assets: `assets/img/<name>.webp`, `<name>.avif` and the narrower `<name>-<width>.webp|avif` variants (480, 768, 1280 px; never upscaled, so the 1280 px greeter shot gets 480 and 768 only). A scene's files are encoded in a temporary directory and replace the old ones only when every encode succeeded. WebP is q90 or lossless, whichever is smaller; AVIF is 4:4:4 libaom through `ffmpeg`, which it requires. `screenshots.sh` calls it, and it runs standalone without the VM; a missing raw PNG is an error. After changing the variant widths or the layout, update `srcset` and `sizes` in `index.html` to match (`check-images.sh` tells you what is off)
  - `fonts.sh`: shared JetBrainsMono Nerd Font lookup, sourced by `og.sh`, `video.sh` and `scenes.sh`
  - `vekrona-banner.sh`: the colored banner that `scenes.sh` copies into the VM and prints in the terminal windows of some scenes

## Capture requirements

The scripts that touch the VM (`screenshots.sh`, `record.sh`) need:

- the sibling checkout `../vekrona` with its `vm/` harness, and a VM created by it (`make -C vm create`), running and logged in to Sway; `capture/lib.sh` uses its SSH key and reads `VM_NAME`, `VM_USER` and `VM_PASSWORD` (default `vekrona`, the harness kickstart password, typed on the lock screen and the greeter)
- libvirt with `virsh` on the host, using `qemu:///system`
- on the host: ImageMagick (`magick`), `ffmpeg` and `ffprobe`, `make`, `tar`, `awk`, `sha256sum`, `ssh` and `scp`, `openssl`, `certutil` (nss-tools), `flock` and `tesseract` (reads the bar's weather widget); every script checks the commands it uses before it starts
- in the guest, which the vekrona install provides: `grim`, `wf-recorder`, `systemd-run`, `ghostty`, `firefox`, `btop`, `jq`, `dms`, `python3`, `curl`, `ss` and the `vekrona-*` tools (`capture_init` lists what is missing), and passwordless `sudo` (the site server is a transient system unit that has to listen on port 443); for the greeter scene the user must already be remembered by tuigreet (log in once through the greeter)
- for the terminal scene and clip additionally: a checkout of the vekrona repo at `~/vekrona` in the guest and passwordless `sudo` for `~/.local/bin/vekrona-snapshot`; both are checked before anything runs

The host-only scripts (`images.sh`, `og.sh`, `video.sh`, `check-images.sh`) need:

- ImageMagick (`magick`) and `ffprobe` (`check-images.sh` also `python3`)
- `ffmpeg` with `libaom-av1` (AVIF), `libx264` (MP4) and `libvpx-vp9` (WebM)
- the JetBrainsMono Nerd Font installed on the host, found by `fonts.sh`

`shellcheck capture/*.sh` from the repo root is clean; `.shellcheckrc` carries the settings.

## The site address in the Firefox pane

The Firefox scenes must show the page the way a visitor sees it: `vekrona.com` in the address bar, a normal padlock, no port. The capture does that without touching the guest's configuration:

- `capture_init` copies the finished site to `/tmp/vekrona-capture/site` and starts a transient system unit, `vekrona-capture-site.service` (`sudo systemd-run`, running as the capture user with only `CAP_NET_BIND_SERVICE`), that serves it with `site-server.py` on 127.0.0.1:443. Its request log is `site.log` next to the site copy.
- The throwaway Firefox profile resolves `vekrona.com` to the guest itself (`network.dns.localDomains`, appended by `open_firefox_site`; `/etc/hosts` stays untouched) and opens `https://vekrona.com/`.
- Plain HTTP was tried first and rejected: Firefox 156 labels it "Not Secure", with a struck-through shield and a visible `http://`. So the host builds, on every run, a throwaway CA and a two-day certificate for `vekrona.com` with `openssl` (in a temporary directory that is deleted when the run ends; nothing is written into the repository), puts the CA into a fresh NSS database with `certutil`, and copies that database into the Firefox profile. The server's certificate and key exist only in `/tmp/vekrona-capture/tls` in the guest. The profile trusts the CA alone, the guest's system trust store is not changed.
- Readiness is polled: the server answers with a verified certificate (`curl` with the CA and `vekrona.com` resolved to 127.0.0.1), the Firefox window title is the page's `<title>`, the server log shows the hero image and every preloaded font served with status 200, and the right half of the screen is a stable frame.
- The teardown closes the Firefox window and waits for the process of that profile to exit before it stops the unit (and resets a failed one), waits until port 443 is free and deletes the temporary directory with the certificate and key.

The chip: DMS's focused-window widget takes the focused window from the foreign-toplevel protocol and, when it misses the "activated" event of a freshly opened window (seen in about one scene in ten, usually just after a theme switch), shows no chip until focus changes again, however long one waits. `wait_for_focused_window` polls the bar for the chip and, when it is missing for 2 s, focuses the window again (`focus parent`, `focus child`), which makes sway send the event again; it says so on stderr and fails after three attempts.

## Reshooting everything

A complete reshoot, with monotone clocks in every asset, is:

```
capture/screenshots.sh && capture/record.sh && capture/video.sh
```

It takes about 15 minutes (measured without the terminal scene and clip: about 4 minutes for the stills, 4.5 for the clips, 1 for the video build; the terminal scene and clip add a few more). `screenshots.sh` does the hero pass twice by itself (see above), nothing else is needed for the nested picture to be current. In the guest, the terminal scene creates multiple btrfs snapshots (see "Redoing the terminal scene" below), plus transient things the teardown removes: the site server unit, `/tmp/vekrona-capture`, the Firefox profiles. Run only one of these scripts at a time: a second run is refused by the lock.

## Redoing the terminal scene

The terminal scene is not part of routine reshoots because it runs the installer's verify stage, which creates multiple btrfs snapshots. The scene still (`scene_terminal_ops`) runs `sudo vekrona-snapshot` (one snapshot) plus the verify stage (four snapshots: pre/post for a test install and pre/post for the removal). The clip (`record_terminal`) types and runs the verify stage again (four more snapshots). A complete reshoot creates nine snapshots total in the guest.

Run, from the repo root, with the VM running and logged in:

```
capture/screenshots.sh terminal-ops
capture/record.sh terminal
capture/video.sh
```

What to expect:

- `screenshots.sh terminal-ops` first checks the preconditions (the `~/vekrona` checkout, `vekrona-rollback`, passwordless `sudo` for `vekrona-snapshot`), then runs `vekrona-rollback --help`, the snapshot and the verify stage inside the guest, capturing their output. If any of them fails, or `vekrona-rollback --help` does not print its usage, the output and the command are printed to stderr and the run stops with `scene terminal-ops failed`. On success a full-screen terminal shows the three commands with their output, `capture/out/screenshots/terminal-ops.png` is taken, and `images.sh` and `check-images.sh` run. The new snapshot stays in the guest: find it with `sudo snapper -c root list` and prune it with `sudo snapper -c root delete <number>` if you do not want it.
- `record.sh terminal` opens a terminal in `~/vekrona`, waits for its prompt, records 0.5 s of the idle prompt, types `./install.sh --skip 10-nvidia 70` key by key with `type_slowly` (about 5 s), presses Enter, lets the verify stage run (a few seconds to a minute) and ends 2.5 s after the installer exits. The clip is longer than its 13 s slot, so `video.sh` prints `segment terminal: ...s recorded, played ...x faster except its first 6.5s and last 2.5s` and speeds up only the middle, so the typing and the closing summary play at normal speed; the caption (`./install.sh --skip 10-nvidia 70 — Verify stage`) does not claim real time. A clip that needs more than 8x, or is more than 3 s shorter than the slot, makes `video.sh` stop before it encodes anything.
- `video.sh` rebuilds `assets/video/` from all clips. The total stays 61 s, so the text in `index.html` stays valid. Look at the result before committing: the terminal segment should open on the empty prompt, show the command typed character by character, then the verify output, and end on the summary and the shell prompt.

The terminal scene runs the installer's verify stage, which fails if any assertion fails; the scene and clip will not run on a guest that fails verify. Before a reshoot, run `./install.sh --skip 10-nvidia 70` in the guest to ensure it passes (see `TODO.md` for the known Tailscale operator issue).

## Regenerating icons

All icons derive from `favicon.svg`. After editing it, run from the repo root:

```
magick -background none -density 1536 favicon.svg -resize 32x32 favicon.ico
magick -background '#1a1b26' -density 1536 favicon.svg -resize 180x180 -flatten -alpha off PNG24:apple-touch-icon.png
magick -background '#1a1b26' -density 1536 favicon.svg -resize 192x192 -flatten -alpha off PNG24:assets/icons/icon-192.png
magick -background '#1a1b26' -density 1536 favicon.svg -resize 512x512 -flatten -alpha off PNG24:assets/icons/icon-512.png
```

## Local preview

```
python3 -m http.server -d .
```

Then navigate to http://localhost:8000
