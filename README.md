# mpv — macOS setup

A hand-tuned [mpv](https://mpv.io) configuration for macOS: a single-instance
launcher, seven Lua scripts, and a `.app` wrapper that makes mpv behave like a
native double-click-to-play media player.

Every value in `mpv.conf` carries a comment explaining *why* it is set, usually
with the measurement that justified it.

## What it does that stock mpv doesn't

| | |
|---|---|
| **Shuffle with a real no-repeat guarantee** | Deals a Fisher–Yates permutation per cycle rather than tracking a played-set. Verified at 600 files / 1200 advances: two exact cycles, zero repeats. |
| **Back goes *back*** | While shuffled, `z` walks the history of what shuffle actually played — browser-style — not playlist order. |
| **Playlist moves keep your position** | Stock mpv only writes the resume point on quit, so `next`/`prev` silently lose it. Here `x`/`z` write it first. |
| **One window, always** | The launcher keeps a single long-lived mpv; opening a file adds to the running instance instead of spawning another. |
| **Folder is the playlist** | Opening one video queues the whole folder (videos only — no cover art as a "video"). |
| **Vertical volume bar** | Observes the `volume` *property*, so any new volume binding gets the bar for free. |
| **Quiet OSC** | The control bar only appears when you hover the bottom edge, and hides after 2s of a parked pointer. Casual mouse movement shows just a slim seek bar with the time underneath. |
| **No hairline** | macOS strokes a 1pt, 20%-white edge on every window, visible in fullscreen over dark video. `native-fs=yes` removes the window, and with it the stroke. |

## Keys

Seeks are all `exact` (plain `seek` drifts to the nearest keyframe).

| Key | |
|---|---|
| `Shift`+`←`/`→` | 1s |
| `a` / `d` | 3s |
| `←` / `→` | 6s |
| `Cmd`+`←`/`→` | 10s |
| `Option`+`←`/`→`, `PgUp`/`PgDn` | 60s |
| `↑`/`↓` or `w`/`s` | volume ±5 |
| `x` / `z` | next / previous (position-preserving) |
| `Cmd`+`z` | shuffle on/off |
| `c` / `v` | cycle subtitles / subtitles off |
| `g` | zoom to fill ↔ original aspect |
| `f` / `p` | fullscreen / switch *how* fullscreen works |
| `l` | reveal the playing file in Finder |
| `0` `0` | wipe all saved playback positions |

`Space` still pauses. `Enter`, `>`, `<` and `9` are deliberately inert — they
were easy to hit by accident and used to jump the playlist.

## Layout

```
mpv.conf              settings, every value commented with why
input.conf            all keybindings
mpv-open              single-instance launcher (Python)
field-guide.html      illustrated guide to the whole setup
scripts/
  shuffle-mode.lua      permutation-cycle shuffle + history for z
  fullscreen-mode.lua   native fullscreen on the laptop, legacy on a TV; p overrides
  vertical-volume.lua   vertical volume bar
  mouse-progress.lua    seek bar on mouse move, time readout at the bottom
  osc-idle-hide.lua     hides the control bar after 2s of a stationary pointer
  reveal-in-finder.lua  l → open -R
  watch-later-reset.lua 0 0 → wipe saved positions
app/
  Info.plist            UTI claims (11 video types + public.folder)
  main.applescript      the wrapper's source
  icons/                13 hand-made document icons
```

## Restoring on a new Mac

```sh
brew install mpv yt-dlp
brew install --cask quicklook-video          # MKV/WebM thumbnails
git clone git@github.com:ryudexter/mpv-macos-setup.git ~/.config/mpv
```

The `.app` wrapper is rebuilt by hand: create an AppleScript droplet from
`app/main.applescript` in Script Editor, save it as `/Applications/mpv.app`,
copy `app/Info.plist` over `Contents/Info.plist`, drop `app/icons/*.icns` into
`Contents/Resources/`, then `codesign -f -s - /Applications/mpv.app`.

> The launcher lives at `~/.config/mpv/mpv-open`, **outside** the bundle, on
> purpose. Editing anything inside `mpv.app` breaks its ad-hoc signature, and
> re-signing changes the cdhash macOS ties privacy grants to — which brings the
> "would like to access files in your Desktop folder" prompt back.

## Notes for future edits

Things that cost real time here, all recorded in the config comments too:

- macOS strips the Option modifier on arrow keys. `input-right-alt-gr=no` fixes
  **both** Option keys, despite the name.
- `#` starts a comment in `mpv.conf` — colour values must be quoted or they are
  silently dropped.
- `watch-later-options-remove` takes **one item per line**. A comma-separated
  list matches nothing, silently.
- `script-opts=` assigns the whole list; a second one would drop the ytdl_hook
  path. Always `script-opts-append=`.
- `osd-msg3` must be a single space to blank it — empty means "use the default".
- The launcher keeps one long-lived mpv, so a `mpv.conf` change needs a full
  `Cmd`+`Q`, not just closing the window. A config change that "didn't work" may
  simply never have been loaded.
- `autocreate-playlist=filter` means opening one file loads the whole folder, so
  a test that passes a single file does *not* get a 1-file playlist.
- The launcher exposes a permanent IPC socket at `/tmp/mpv-single.sock` — the
  way to inspect a live session without touching the config.
- For key problems, `--msg-level=input=trace --log-file=…` shows what mpv
  actually received. Measure; nearly every bug here looked like something else.
