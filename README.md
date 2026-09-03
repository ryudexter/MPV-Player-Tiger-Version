# mpv — macOS setup

A hand-tuned [mpv](https://mpv.io) configuration for macOS: a single-instance
launcher, fourteen Lua scripts, and a `.app` wrapper that makes mpv behave like
a native double-click-to-play media player.

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
| **Skip the intro without chapters** | `/` runs the file at 100x behind a black frame until the audio drops below -30dB, which on a normal episode is the gap between the title sequence and the first line. Most files carry no chapter marks, so the chapter keys cannot do this. Lands within 24ms of where ffmpeg's own `silencedetect` puts the silence. |
| **Clip export** | `Cmd`+`t` sets an in and an out point on the playing file and writes the section to the Desktop as an h264 mp4, without leaving the player. Encoding is a second headless mpv, so the clip inherits the tracks and filters you are actually watching. |
| **Subtitles from the internet** | `b` downloads a subtitle for the playing file and switches it on — mpv's answer to VLC's VLsub, which mpv has no equivalent of out of the box. Anonymous sources only, no account anywhere. |
| **The right subtitle, not the first one** | `sub-auto=all` loads whole `Subs/` folders — one film here offers 35 — so `c` scores them by language tag, filename and the video's own stem instead of cycling through the lot. |
| **No hairline** | macOS strokes a 1pt, 20%-white edge on every window, visible in fullscreen over dark video. `native-fs=yes` removes the window, and with it the stroke. |

## Keys

Seeks are all `exact` (plain `seek` drifts to the nearest keyframe).

| Key | |
|---|---|
| `Shift`+`←`/`→` | previous / next chapter |
| `a` / `d` | 3s |
| `→` / `←` | 10s forward / 6s back |
| `Cmd`+`→` / `Cmd`+`←` | 30s forward / 10s back |
| `Option`+`←`/`→` | 60s (`PgUp`/`PgDn` are switched off) |
| `/` | skip the opening titles — jump to the next silence |
| `↑`/`↓` or `w`/`s` | volume ±5 |
| `x` / `z` | next / previous (position-preserving) |
| `Cmd`+`z` | shuffle on/off |
| `c` / `v` | subtitles: English → Turkish → off / subtitles off outright |
| `Alt`+`c` | choose a subtitle track from a searchable list |
| `Shift`+`c` / `Shift`+`x` | subtitle timing ±100ms |
| `b` / `Shift`+`b` | download subtitles / download again over one already there |
| `Alt`+`b` | re-time the subtitle against the film's audio |
| `g` | zoom to fill ↔ original aspect |
| `f` / `p` | fullscreen / switch *how* fullscreen works |
| `Cmd`+`t` | cut a clip out of what's playing and save it to the Desktop |
| `l` | reveal the playing file in Finder |
| `0` `0` | reset the saved playback positions of this playlist (see trap 9) |

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
  skiptosilence.conf    silence threshold, minimum length, mute while skipping
  webm.conf             mp4 output, quality, Desktop output dir, absolute mpv path
scripts/
  thumbfast.lua         upstream frame generator (po5/thumbfast, MPL-2.0)
  seek-thumbnail.lua    bridges the pointer to thumbfast
  shuffle-mode.lua      permutation-cycle shuffle + history for z
  fullscreen-mode.lua   native fullscreen on the laptop, legacy on a TV; p overrides
  vertical-volume.lua   vertical volume bar
  mouse-progress.lua    seek bar on mouse move, time readout at the bottom
  osc-idle-hide.lua     hides the control bar and cursor after 2s of stillness
  reveal-in-finder.lua  l → open -R
  watch-later-reset.lua 0 0 → reset this playlist's saved positions
  trash-file.lua        Cmd+Delete → /usr/bin/trash, playback untouched
  subtitle-pick.lua     c → score every sub track and pick the best English one
  subtitle-fetch.lua    b → download a subtitle with the subliminal CLI
  subtitle-sync.lua     Alt+b → re-time it with the ffsubsync CLI
  global-sound.lua      one volume level for everything, not one per file
  skiptosilence.lua     / → fast-forward to the next silence (detuur, MIT, patched)
  webm.lua              Cmd+T → clip out a section (ekisu/mpv-webm, MIT, patched)
app/
  Info.plist            UTI claims (11 video types + public.folder)
  main.applescript      the wrapper's source
  icons/                13 hand-made document icons
```

## Restoring on a new Mac

```sh
brew install mpv yt-dlp
brew install --cask quicklook-video          # MKV/WebM thumbnails
pipx install subliminal                      # subtitle downloads (the b key)
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

## Subtitles

Three keys, in the order you reach for them:

| | |
|---|---|
| `c` | subtitles on. Press again for Turkish, again for off. |
| `b` | none good enough? download one. |
| `Alt`+`b` | downloaded one is right but late? re-time it against the film's audio. |
| `Alt`+`c` | pick a specific track from a searchable list. |

**`c` chooses, then lets you change your mind.** The first press gives you
English, a second press Turkish, a third switches subtitles off — and the
message on screen says what the next press will do. A film that only has one of
the two languages is simply on, then off. `mpv.conf` sets `sub-file-paths=Subs` and
`sub-auto=all`, because releases park their subtitles in a subfolder under names
like `English.srt` that match nothing about the video — without it they are
invisible. The cost is volume: Project Hail Mary went from 1 track to 36.
Each press is worked out from what is currently selected, never from a
counter, so it stays in step after `v`, after picking something by hand with
`Alt`+`c`, or after moving to another film.

`subtitle-pick.lua` scores every track — the language in the tag or the
filename, embedded, filename matching this video's stem, minus points for SDH
and forced tracks — and selects the winner in one press. English and Turkish
sit in bands 500 points apart, wider than every other signal put together, so
an English track always wins when there is one and Turkish is the fallback;
nothing about being embedded or default can lift one language over the other.

> The stem bonus is what stops it picking the wrong episode. A Solo Leveling
> season folder holds 12 videos and 12 `.srt` files, and *all twelve* subtitle
> names contain "English" — from `[English Dub]` — so on the language signal
> alone episode 1's subtitles win no matter which episode is playing.

**`b` downloads one** — this config's answer to VLC's VLsub, which mpv has no
built-in equivalent of. It shells out to
[subliminal](https://github.com/Diaoul/subliminal), which hashes the video and
searches several sites at once, so it finds a subtitle timed for *this* rip
rather than guessing from the title. English and Turkish are requested in the
same search, so a film with both ends up with a `.en.srt` and a `.tr.srt` and
shows the English one, and a film with only Turkish subtitles still gets
subtitles. The result lands next to the video and is switched on when it
arrives. `Shift`+`b` downloads again over a subtitle file that is already there.

Anonymous sources only — nothing here has a login:

| | |
|---|---|
| `bsplayer` | movies **and** episodes, matched by file hash. The workhorse. |
| `gestdown` | episodes only (an addic7ed mirror). |
| `tvsubtitles` | episodes only. |
| `podnapisi` | listed, but the site currently has no DNS record at all. Kept so it starts working again by itself if it comes back. |

bsplayer, gestdown and podnapisi all carry Turkish as well as English, so both
languages are worth asking for — but with only these three, coverage is thin,
and **every movie depends on bsplayer alone**. Its server pool is unreliable:
it served four downloads during testing and then went dark, all nine of its
`sN.api.bsplayer-subtitles.com` hosts timing out, which `b` reports as
"Subtitle site unavailable (bsplayer) — try again".

subliminal can also query opensubtitles.com — the source VLsub uses, and by far
the largest Turkish collection — but that needs an account and an API key, so it
is deliberately left out. That is the one change that would make this reliable.

Measured 2026-09-02, driving the real config over IPC: a movie takes ~4s
(Margin Call, 1353 cues), an episode ~57s because two more sites are involved
(House of the Dragon S03E06, 733 cues). A file with nothing available says so
after ~59s.

**`Alt`+`b` re-times it.** A downloaded subtitle is often right but late,
timed for a different cut or frame rate; `Shift`+`c` moves it 100ms a press,
which is fine for half a second and hopeless for twelve.
[ffsubsync](https://github.com/smacke/ffsubsync) fixes it properly — it runs
the film's audio through voice detection, does the same to the subtitle's own
timings, and slides one against the other, correcting the frame rate too. The
file is rewritten in place, so the fix sticks; the original is kept once as
`<name>.srt.orig`, and any manual timing nudge is reset. External subtitles
only — an embedded track is not a file that can be rewritten.

> Verified by planting a subtitle 12s late on a 2h02 film: it came back
> `offset seconds: -12.040`, its first cue within 40ms of where it started, the
> backup holding the late version, no leftover temp file, `sub-delay` back to 0
> and the same track still selected.

> **Unresolved:** the identical command takes 12s from a shell and **242s when
> mpv spawns it**. CPU contention, pipe backpressure and the macOS background
> QoS class were each ruled out by measurement (see the comments in
> `subtitle-sync.lua`), and nothing else mpv spawns here is slowed at all. The
> timeout is 900s and the on-screen counter runs throughout, so a slow run
> looks slow rather than broken.

**Requires** `pipx install subliminal` and `pipx install ffsubsync`. Both are
called at their absolute `~/.local/bin/` paths — see the `PATH` note below.

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
- mpv's builtin `select.lua` menus (`Ctrl`+`p`, and the playlist selector inside
  it) install a **forced** input section that claims every printable key for
  their search box. While one is open, `0` is typed into the filter and never
  reaches the watch-later reset. Close the menu first.
- mpv **deletes** a file's `watch_later` entry the instant it resumes it
  (v0.41 `player/loadfile.c`), so while a resumed video plays there is nothing
  on disk for it — its position lives only in `time-pos`. Measuring a reset by
  the folder shrinking therefore reports 0 for the very file you are watching.
- mpv writes a `# redirect entry` for **every ancestor directory** of a file,
  all the way to the root: one video eight levels down leaves nine files
  behind. Counting the folder gives a count of directories, not of videos.
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
- Subtitle searches are slow enough to look hung: an episode legitimately took
  57s, so `subtitle-fetch.lua` allows 180s. A first draft allowed 60 and came
  within 3s of killing a search that was working.
- After a download, `subtitle-fetch.lua` selects the file it just fetched
  instead of re-scoring the list. `subtitle-pick.lua` rates an embedded English
  track above a downloaded one, which is right in general — but on a file with
  36 embedded tracks it meant `b` spent 57s fetching a subtitle and then
  displayed a different one.
- A `sub-add`ed subtitle has **no language at all** unless one is passed
  explicitly, even when the filename ends `.en.srt`; the same file auto-loaded
  from beside the video reports `lang=en`. The scoring reads that tag, so the
  read-only-folder path passes the language by hand.
- For subtitle work, hardlink a real video into a scratch folder: same bytes and
  therefore the same provider hash, no copy, and nothing written into the media
  library.
- For key problems, `--msg-level=input=trace --log-file=…` shows what mpv
  actually received. Measure; nearly every bug here looked like something else.
