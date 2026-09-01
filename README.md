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
| **Seek thumbnails** | Hover the bottom strip and the frame at that point appears above the pointer. mpv has none of its own, and its built-in OSC cannot drive thumbfast — usually you have to adopt uosc's whole UI to get this. Here it is one 86-line bridge. |
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
script-opts/
  thumbfast.conf        preview size, idle shutdown, absolute mpv path
scripts/
  thumbfast.lua         upstream frame generator (po5/thumbfast, MPL-2.0)
  seek-thumbnail.lua    bridges the pointer to thumbfast
  shuffle-mode.lua      permutation-cycle shuffle + history for z
  fullscreen-mode.lua   native fullscreen on the laptop, legacy on a TV; p overrides
  vertical-volume.lua   vertical volume bar
  mouse-progress.lua    seek bar on mouse move, time readout at the bottom
  osc-idle-hide.lua     hides the control bar after 2s of a stationary pointer
  reveal-in-finder.lua  l → open -R
  watch-later-reset.lua 0 0 → reset this playlist's saved positions
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

## Seek thumbnails

Hovering the bottom strip — the same place you go to summon the controls —
shows the frame at that point in the film, above the pointer.

Two pieces do it. `thumbfast.lua` is upstream (po5/thumbfast, MPL-2.0) and does
the decoding: on the first hover it spawns a second, hidden mpv, feeds frames
back over a socket, and shuts itself down again after 30s idle. Opening a file
costs nothing extra — nothing runs until you actually hover the bar.
`seek-thumbnail.lua` is the local half: it watches the pointer, maps its x onto
the timeline, and tells thumbfast where to draw.

`osc-idle-hide.lua` gets a second, longer timeout for this strip (6s instead of
2s), because looking at a preview means holding the pointer still, and at the
normal 2s the thumbnail vanished exactly when you stopped to read it.

**To remove it entirely**, revert the one commit that added it:

```sh
git -C ~/.config/mpv revert --no-edit <commit>     # see: git log --oneline
```

That takes out both scripts, the config, and the idle-timeout change together,
leaving the setup exactly as it was. Then quit mpv fully (`Cmd`+`Q`) — the
launcher keeps one long-lived instance, so scripts are only re-read on a real
restart.

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
- The OSC's seek bar does **not** span the window: in the default bottombar
  layout it is inset between the elapsed and remaining timecodes (x≈234..874 in
  a 1280-wide window). Mapping a pointer across the full width instead is out by
  ~24s mid-bar on a 3-minute file. `seek-thumbnail.lua` derives the real bounds
  from osc.lua's own constants.
- mpv's OSC is compiled into the binary, not shipped as a file — but its Lua
  source is still recoverable with
  `strings /opt/homebrew/bin/mpv | grep -n 'local function bar_layout'`, which
  is where those constants came from.
- thumbfast spawns its helper by the bare name `mpv`, which relies on `PATH`. A
  GUI app launched from Finder does not inherit the shell `PATH`, so under
  `mpv.app` the spawn fails **silently** — no thumbnail, no error, while it
  works fine from a terminal. `script-opts/thumbfast.conf` pins the absolute
  path for that reason.
- `script-list` is not a property in 0.41. Querying it returns "property not
  found", which is easy to misread as "no scripts loaded".
- For key problems, `--msg-level=input=trace --log-file=…` shows what mpv
  actually received. Measure; nearly every bug here looked like something else.
