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
| **English audio, without asking** | A film with several soundtracks plays in English. Stock mpv takes whichever track the file flags as default — on Solo Leveling season 2 that is Japanese. `l` steps through the other languages. |
| **The right subtitle, not the first one** | `sub-auto=all` loads whole `Subs/` folders — one film here offers 35 — so `c` scores them by language tag, filename and the video's own stem instead of cycling through the lot. |
| **Animation gets sharpened, by itself** | Anime4K redraws the line art on animated shows instead of merely enlarging it — 97 episodes here are 1080p on a 3456x2234 panel. It picks the files on its own from a folder list, leaves live action alone, and `y` overrides the choice. Nothing is written to the video: it is a live effect on the frame on its way to the screen. |
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
| `l` | audio language: English → the film's other languages → round again |
| `Alt`+`l` | choose a specific audio track from a searchable list |
| `c` / `v` | subtitles: English → Turkish → off / subtitles off outright |
| `Alt`+`c` | choose a subtitle track from a searchable list |
| `Shift`+`c` / `Shift`+`x` | subtitle timing ±100ms |
| `b` / `Shift`+`b` | download subtitles / download again over one already there |
| `Alt`+`b` | re-time the subtitle against the film's audio |
| `g` | zoom to fill ↔ original aspect |
| `y` | sharper picture: auto → always on → off (auto = on for animation only) |
| `f` / `p` | fullscreen / switch *how* fullscreen works |
| `Cmd`+`t` | cut a clip out of what's playing and save it to the Desktop |
| `i` | reveal the playing file in Finder |
| `0` `0` | reset the saved playback positions of this playlist (see trap 9) |

`Space` still pauses. `Enter`, `>`, `<` and `9` are deliberately inert — they
were easy to hit by accident and used to jump the playlist.

## Layout

```
mpv.conf              settings, every value commented with why
input.conf            all keybindings
mpv-open              single-instance launcher (Python)
field-guide.html      illustrated guide to the whole setup
shaders/              Anime4K v4.0.1, Mode A (HQ) only — 6 of the 39 files (MIT)
script-opts/
  video-quality.conf    which folders count as animation
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
  reveal-in-finder.lua  i → open -R
  watch-later-reset.lua 0 0 → reset this playlist's saved positions
  trash-file.lua        Cmd+Delete → /usr/bin/trash, playback untouched
  video-quality.lua     Anime4K on animation only; y cycles auto/on/off
  audio-pick.lua        English soundtrack by default; l → next language
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

## Sharper picture (animation)

Animated shows are sharpened automatically. Everything here is 1080p and the
laptop panel is 3456x2234, so every frame is being stretched; [Anime4K][a4k]
redraws the line art rather than just enlarging it. Faces, eyelashes and the
edges of flat colour come back noticeably crisper.

**Nothing is written to your video files.** Shaders are a live effect — the GPU
redraws each frame on its way to the screen, the way a filter on a camera
preview works. The file is opened read-only and stays byte-for-byte identical,
and `glsl-shaders` is not one of mpv's 47 watch-later options, so resume
positions are untouched. Switch it off and the picture is instantly back.

It chooses per video. A file whose path contains one of the names in
`script-opts/video-quality.conf` gets the shaders; everything else keeps the
`high-quality` profile from `mpv.conf`. **Live action is excluded on purpose** —
anime shaders on real footage make skin look waxy and put halos on edges.

| `y` | auto → always on → off → auto. The message says which you landed on. |
|---|---|

Use **always on** for an animated film that is not in the list yet, and **off**
to compare the same frame with and without.

**Adding a new show** is one line — append it to `animation_paths` in
`script-opts/video-quality.conf`, semicolon-separated. It is matched as plain
text anywhere in the path, ignoring case, so the folder name alone is enough.
Watch the `=`: mpv silently ignores `key = value` with spaces around it.

Only Mode A (HQ) is kept — 6 of the release's 39 shaders, 340K instead of
2.3MB. To try Mode B or C, fetch the [v4.0.1 zip][a4k] again and swap the
`SHADERS` list in `scripts/video-quality.lua`.

There is no "light" preset because there is nothing to save: measured at
3456x2168 fullscreen, every preset up to Mode A *ultra* ran with **zero dropped
and zero delayed frames, even at 4x playback speed**.

[a4k]: https://github.com/bloc97/Anime4K

## Audio languages

A film with an English soundtrack and a Turkish one, or an anime with an English
dub and the Japanese original, comes up **in English**. `l` switches.

| | |
|---|---|
| *(nothing)* | English plays by default. |
| `l` | next language, and the message says what the press after that will give. |
| `Alt`+`l` | pick a specific track — the second English mix, or a commentary. |

Stock mpv has no preference of its own: it plays whichever track the file flags
as default, whatever language that happens to be. On Solo Leveling season 2 —
Japanese first, English second, neither flagged — that means Japanese, every
episode. `mpv.conf` now sets `alang=en`, which mpv applies inside its own track
selection, so the right track is chosen before the audio decoder is even created
and nothing switches once playback has started. One code is enough: mpv
normalises language tags through its own ISO 639 table, so `en` matches `eng`
and `en-US` too.

`scripts/audio-pick.lua` covers the two cases a language list cannot reach:

- **A track with no language tag.** A soundtrack titled "English AC3 5.1" and
  tagged with nothing at all is invisible to `alang`, so mpv falls back to the
  default-flagged track — the Turkish one. The script reads the title. This is
  the same shape as the subtitle problem below, where a bare `English.srt`
  carries no tag either.
- **An English commentary listed first.** With `eng`/`eng`/`tur` and the
  director's commentary flagged default, `alang=en` is satisfied by the
  commentary and stops there. The script scores tracks within a language and
  pushes commentary, audio description and karaoke tracks to the bottom.

**`l` steps through languages, not tracks.** A film with an English 5.1 mix, an
English stereo mix and a Turkish dub is two presses round, not three. When a
file has only one language but several tracks in it, `l` steps through those
tracks instead, so the key is never dead — and `Alt`+`l` (or mpv's own `#`,
left live) reaches any single track directly.

> Verified 2026-09-03 over IPC across all 25 Solo Leveling episodes: the 13
> season 2 files open in English and `l` gives Japanese and back; the 12 season
> 1 files have one English track each. Plus six synthetic shapes — tagged,
> untagged, title-only, two-English-plus-commentary, no-English-at-all and
> silent — for the cases the library does not happen to contain.

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
- Only **three** single keys were ever unbound: `h`, `k`, `y`. `e j o r t u`
  all look free in `input.conf` but are live mpv builtins. `i` was one of them
  (the stats overlay) until reveal-in-finder took it; stats survive on `Shift`+`I`.
- A track list appearing is not the same as a track being *selected*. Polling
  `track-list` and reading `current-tracks/audio` straight after gave one false
  failure in 25 — poll for the selection itself.
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
- A saved position is keyed on an MD5 of the path **bytes**, but APFS is
  normalisation-*insensitive*: `film-ö.mp4` spelled composed (`c3 b6`) and
  decomposed (`6f cc 88`) open the same inode and get two separate
  `watch_later` entries. `autocreate-playlist` normally hides this by rebuilding
  entries from mpv's own `readdir`, but it does not run when mpv is handed
  several files at once — a Finder multi-select — so a path arriving in the
  other form keeps it, and its entry becomes unreachable. `watch-later-reset.lua`
  deletes both spellings, via `iconv`'s `UTF-8-MAC` (macOS's own decomposed
  form). Measured 2026-09-03: deleting the composed spelling of a decomposed
  entry cleared all 8 ancestor redirects but left the position, still resuming
  at 43.2s.
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
