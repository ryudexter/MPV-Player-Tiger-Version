# mpv — macOS setup

A hand-tuned [mpv](https://mpv.io) configuration for macOS: a single-instance
launcher, nineteen Lua scripts, and a `.app` wrapper that makes mpv behave like
a native double-click-to-play media player.

Every value in `mpv.conf` carries a comment explaining *why* it is set, usually
with the measurement that justified it.

## What it does that stock mpv doesn't

| | |
|---|---|
| **Shuffle with a real no-repeat guarantee** | Deals a Fisher–Yates permutation per cycle rather than tracking a played-set. Verified at 600 files / 1200 advances: two exact cycles, zero repeats. Applies to a video simply *ending*, not only to pressing next — which needs `keep-open=always`, since plain `yes` holds only at the last entry and let everything else advance in order. |
| **Back goes *back*** | While shuffled, `z` walks the history of what shuffle actually played — browser-style — not playlist order. |
| **Playlist moves keep your position** | Stock mpv only writes the resume point on quit, so `next`/`prev` silently lose it. Here `x`/`z` write it first. |
| **One window, always** | The launcher keeps a single long-lived mpv; opening a file adds to the running instance instead of spawning another. |
| **Opening a file takes you to it** | With mpv already running somewhere out of sight — typically forgotten in its own fullscreen Space — a double-click used to start the video playing where you could not see it. Now the player comes to the front, switching to its fullscreen Space. mpv's own `--focus-on=all` asks macOS for exactly this and is refused, because since macOS 14 an app in the background cannot bring itself forward; `open -a` on the running app is honoured, so the player runs from a tiny app bundle that `open -a` can name. An episode moving on by itself still never pulls you back. |
| **Speed never sticks** | Playback speed is a *right now* choice. Stock mpv saves it per file in the resume data, so a show watched once at 4x reopens at 4x for good. Here every file you open starts at 1x — while an episode auto-advancing inside a playlist keeps whatever speed you set, so a binge is not interrupted. |
| **Folder is the playlist** | Opening one video queues the whole folder (videos only — no cover art as a "video"). |
| **The folder loops, the session doesn't end** | Stock mpv terminates at the end of the last entry, which here would take the window, the playlist and the single instance with it. `loop-playlist=inf` wraps back to the first video instead; with shuffle on, the script deals a fresh random cycle rather than wrapping. A file that played through resumes at 0 on the next lap, because mpv drops its resume point at EOF. |
| **Vertical volume bar** | Observes the `volume` *property*, so any new volume binding gets the bar for free. |
| **Quiet OSC** | The control bar only appears when you hover the bottom edge, and hides after 2s of a parked pointer. Casual mouse movement shows just a slim seek bar and the time. |
| **The bar sits in the black strip** | A 16:9 video in fullscreen leaves an empty black strip under the picture, and stock mpv's bar sits at a fixed height of the *window*, so it lands over the bottom of the picture instead. Here the seek bar and the trackpad's volume bar drop into that strip, with the elapsed time left of the bar and the duration right of it, and come back up the moment there is no strip (a window, `g`, a video that fills the screen). Subtitles never meet it — they already sat above it — and while it is down there they come down too, to sit just above it: onto the bottom edge of the picture on 16:9, lower in the black on a wide film. With no strip they go back to clearing the bar where it then is. |
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
| `]` / `[` | speed ±10% |
| `}` / `{` | speed double / half |
| `Delete` (mpv's `BS`) | back to 1x |
| `Cmd`+`z` | shuffle on/off |
| `l` | audio language: English → the film's other languages → round again |
| `Alt`+`l` | choose a specific audio track from a searchable list |
| `c` / `v` | subtitles: step through every English then Turkish track, then off / off outright |
| `Alt`+`c` | choose a subtitle track from a searchable list |
| `Shift`+`c` / `Shift`+`x` | subtitle timing ±100ms |
| `b` / `Shift`+`b` | download subtitles / download again over one already there |
| `Alt`+`b` | re-time the subtitle against the film's audio |
| `g` | zoom to fill ↔ original aspect |
| `y` | sharper picture: auto → always on → off (auto = on for animation only) |
| `f` / `p` | fullscreen / switch *how* fullscreen works |
| `Cmd`+`t` | cut a clip out of what's playing and save it to the Desktop |
| `n` | even out loud and quiet passages (says on screen which way it went) |
| `m` / `T` / `L` | mute / stay on top / loop this file — the message says True / False, not mpv's yes / no |
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
  video-quality.conf    which folders count as animation, and the two presets
  thumbfast.conf        preview size, idle shutdown, absolute mpv path
  skiptosilence.conf    silence threshold, minimum length, mute while skipping
  webm.conf             mp4 output, quality, Desktop output dir, absolute mpv path
scripts/
  thumbfast.lua         upstream frame generator (po5/thumbfast, MPL-2.0)
  seek-thumbnail.lua    bridges the pointer to thumbfast
  shuffle-mode.lua      permutation-cycle shuffle + history for z
  fullscreen-mode.lua   native fullscreen on the laptop, legacy on a TV; p overrides, remembered per screen
  vertical-volume.lua   vertical volume bar
  mouse-progress.lua    seek bar on mouse move, time readout beside or under it
  bar-in-strip.lua      moves the bar into the black strip, subtitles just above it
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
  mpv-player.app/       the bundle the PLAYER runs from, so it can be brought
                        to the front (MacOS/mpv -> /opt/homebrew/bin/mpv)
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

`app/mpv-player.app` needs no building: it is an `Info.plist` and two
symlinks, one to Homebrew's `mpv` and one to `app/icons/mpv.icns`, and git
restores both. It is a different bundle from the wrapper — the wrapper is what
Finder opens, this is what the long-lived player runs from — and it claims no
file types, so it never appears under Open With, and Spotlight does not index
dot-folders, so searching "mpv" still finds only the wrapper (checked with
`mdfind`). If it goes missing the launcher falls back to the bare binary and
everything works except the raise.

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
to compare the same frame with and without. `auto` is the startup state and is
**not** remembered across runs — close mpv and it is back to auto.

**Adding a new show** is one line — append it to `animation_paths` in
`script-opts/video-quality.conf`, semicolon-separated. It is matched as plain
text anywhere in the path, ignoring case, so the folder name alone is enough.
Watch the `=`: mpv silently ignores `key = value` with spaces around it.

Only Mode A (HQ) is kept — 6 of the release's 39 shaders, 340K instead of
2.3MB. To try Mode B or C, fetch the [v4.0.1 zip][a4k] again and swap the
`CHAINS` lists in `scripts/video-quality.lua`.

### It measures the machine and moves between three rungs

An earlier note here said there was no "light" preset because there was nothing
to save. That measurement had been taken plugged in, **and on an idle machine**.
Both halves of that turned out to matter — so since 2026-09-20 the shaders are a
**ladder** rather than a fixed choice, and what runs is whichever rung the
machine has most recently shown it can afford:

| rung | shaders | GPU | when |
|---|---|---|---|
| **full** — Mode A (HQ) | 6 | ~76% | wall power, and the machine has been losing no frames for a minute |
| **light** — Clamp + `x2_M` + downscale | 4 | ~37% | the starting rung on wall power, and where it falls back to under load |
| **off** | 0 | ~36% | heavy load, or on battery |

On battery it is **off**, not light. The light chain is nearly free in dropped
frames but it is not free in watt-hours, and it is GPU spent on a picture nobody
asked for. <kbd>y</kbd> → "always on" still brings it back, and
`battery_chain=light` restores the old behaviour.

Measured on battery at 3456x2168 fullscreen, 1080p HEVC — three focus-gated
12-second samples per chain in one run, chains swapped over the IPC socket, so
the conditions are identical:

| chain | frames dropped | display rate | per-sample spread |
|---|---|---|---|
| full — Mode A (HQ) | **43.9%** | 60 fps | 43.1 / 42.1 / 46.4 |
| **light — `x2_M` upscale** | **0.5%** | **119 fps** | 0.0 / 1.4 / 0.0 |
| shaders off | ~0% | 120 fps | — |

So `light` is within noise of running no shaders at all, while still doing a
real CNN upscale. A middle option — Mode A with only the Restore stage removed,
keeping the VL upscale — was measured at **11.8%** (85 fps) and rejected: it is
the VL *upscale*, not Restore, that this machine cannot afford unplugged.

**On AC the full chain measures clean**, the same way: **0.00% dropped at
120 fps**, in the rounds whose no-shader baseline was also 0.00%. So the 43.9% is
a battery ceiling and not a general one — unplugged, `full` sat at 42–46% in
every sample; plugged in, it hits exactly zero.

**But 0.00% is a quiet machine, and this one is not quiet when it is plugged in.**
macOS holds background work back on battery and releases it the moment the cable
goes in. Measured 2026-09-20 with no player open at all: `mediaanalysisd` at ~60%
CPU with the hardware decoder pegged beside it for 41 hours straight, and the GPU
already reading **24% utilisation** before mpv was launched. Set against what the
chains themselves cost — off 36% / light 37% / **full 76–77%** GPU — the full
chain is what tips 1080p anime into visible stutter there, and the light chain is
not. That is why the default changed.

It also puts the 42.6%-on-AC reading below in a different light. Discarding it was
right: its no-shader baseline was 24%, so the number measured the machine and not
the shaders. But that 24% baseline was never the freak round it was filed as — it
is this machine's ordinary plugged-in state, and it is precisely the case the
default now has to survive.

Two traps, both of which caught an earlier version of this section:

- **Per-stage `vo-passes` timings lie.** The same Restore stage measured 9.05 ms
  in one run and 0.00 ms in another, and one chain's pass-sum drifted from
  29.45 ms to 11.40 ms minutes apart within a single run — the GPU timer charges
  the cost to whichever pass absorbs the pipeline stall. This section once
  claimed Restore was 80.5% of the frame on that basis, and the light chain was
  picked to match. Use `frame-drop-count` against wall-clock instead.
- **Only measure while mpv has focus.** Unfocused, macOS stops compositing it:
  playback carries on but the drop counters freeze, and every chain reads a
  flawless 0.0% — indistinguishable from success.
- **Gate every round on a no-shader baseline, before and after.** With zero
  shaders loaded the drop rate must be ~0; anything higher means something else
  on the machine is taking the display pipeline, and every number in that round
  is measuring that instead. A busy browser tab produced a 24% baseline and,
  with it, a completely fictitious 42.6% for the full chain on AC. Five rounds
  out of eight were thrown out this way on an otherwise idle-looking machine.

It switches live, and **silently**. There is exactly one `mp.osd_message` call
in the script and it sits in `cycle()`, so the only thing that ever puts a line
on screen is a press of <kbd>y</kbd> — never a load-driven rung change, never
plugging in or unplugging, never startup.

⚠️ That deliberately **reverses** the rule the rest of this file argues for, that
a picture changing by itself should say why or it reads as a fault. It is the
user's call on their own player (2026-09-21), made knowing that is the trade:
they would rather never see the line than be told about a change they did not
ask for. **Do not add an OSD back here as a fix for an unexplained picture
change** — see THE OSD RULE at the top of `scripts/video-quality.lua`.
Nothing is lost for diagnosis: every chain and power change still goes to the
log through `msg.info`, so `log-file=` recovers the whole history after the fact.

#### How it decides: mpv's own dropped frames, not a GPU meter

The signal is `frame-drop-count` and `vo-delayed-frame-count`, sampled over a
10-second window and expressed as a fraction of the frames that *should* have
been shown — so one threshold means the same thing on 23.976 fps film and on
60 fps video. Lose more than **2%** of a window and it steps down a rung
immediately. Stay under **0.5%** for a continuous minute and it climbs one.
Between the two it holds, which is what stops it oscillating around a single
number. Two reasons for that choice over reading the GPU:

- **It costs no fork.** A load monitor has to sample every few seconds to be any
  use, and a periodic fork under live audio is exactly the bug fixed in
  `9eac603` — it made mpv's CoreAudio callback miss its deadline, heard as a
  thump. Reading a property is in-process and free. Measured with real audio and
  the sampler stressed at a 2-second window, five times its normal rate:
  **0 skipped audio cycles in 60 s, against 0 for the sampler switched off.**
- **It measures the symptom, not a proxy.** Whatever is taking the machine —
  another app, a background index, thermal throttling — arrives as dropped
  frames, and a chain that cannot be afforded convicts itself.

Climbing recompiles the shaders, which is a visible hitch, so climbing is slow
and stepping down is immediate. A rung that fails straight after being climbed
to doubles its own wait, capped at 8× — so a machine that keeps refusing `full`
stops being asked every minute and settles at retrying every eight.

Three traps this had to be built around, all of them already recorded here:

- **The drop counters freeze when mpv is unfocused.** macOS stops compositing it,
  every window reads a flawless zero, and the ladder would climb to `full` on the
  strength of a measurement that never happened. Every sample is gated on
  `focused`.
- **Seeks, pauses, focus changes and shader recompiles all drop frames** for
  reasons that have nothing to do with sustained load. Each one marks the window
  in progress as unusable rather than letting it count.
- **`--vo=libmpv` with no render client manufactures dropped frames**, so it is
  useless for testing this — it reports overload on a completely idle machine.
  Drive the counters from a stub instead, or use a real window.

Switches in `script-opts/video-quality.conf`: `load_aware=no` pins the chain and
stops it moving, `ac_max_chain=light` lowers the ceiling so it never reaches
Mode A, `battery_chain=light` puts the old battery behaviour back, and
`power_aware=no` ignores the cable altogether.

### …and it stops paying for frames you cannot see

Added 2026-09-10, after "the battery drains much faster on anime". This is the
bigger of the two savings, and unlike the shader preset it applies to **every**
video, not just animation.

`mpv.conf` sets `video-sync=display-resample`, which locks playback to the
display clock and removes a small hitch every ~8 seconds. What it costs is that
the renderer runs at the **screen's** rate rather than the video's: this panel
refreshes 120 times a second for a film with 24 new frames a second, so four
out of every five trips through the scaler and the shaders redraw a frame that
is already on screen. `video-sync=audio` feeds the same frames through the same
scaler and the same shaders — the picture is pixel for pixel what it was — and
simply stops paying for the repeats.

Measured on Attack on Titan (1080p HEVC), fullscreen 3456x2168, mpv focused,
three 12-second samples per cell, median GPU "Device Utilization %":

| | `display-resample` | `audio` |
|---|---|---|
| no shaders | 33 / 37 / 37 % | **11 / 11 / 11 %** |
| light preset | 37 / 37 / 37 % | **17 / 17 / 18.5 %** |

Zero dropped frames in all twelve samples. On the battery preset that is
**roughly half the GPU work for an identical picture** — a bigger saving than
turning the shaders off altogether would give you.

The cost is the hitch coming back: 120 / 23.976 = 5.005, so about every 8
seconds one frame is held for an extra refresh. Smoothness on the cable,
endurance off it. Set `battery_video_sync=` (empty) in
`script-opts/video-quality.conf` to keep the smoothness on battery too.

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
| `c` | subtitles on. Press again to step through the rest, again for off. |
| `b` | none good enough? download one. |
| `Alt`+`b` | downloaded one is right but late? re-time it against the film's audio. |
| `Alt`+`c` | pick a specific track from a searchable list. |

**`c` chooses, then lets you change your mind.** The first press gives you the
best English track there is. Each press after that moves to the next one — any
other English tracks first, then Turkish, then off — and the message on screen
says what the next press will do. A film with one track of one language is
simply on, then off. `mpv.conf` sets `sub-file-paths=Subs` and
`sub-auto=all`, because releases park their subtitles in a subfolder under names
like `English.srt` that match nothing about the video — without it they are
invisible. The cost is volume: Project Hail Mary went from 1 track to 36.
Each press is worked out from what is currently selected, never from a
counter, so it stays in step after `v`, after picking something by hand with
`Alt`+`c`, or after moving to another film.

`subtitle-pick.lua` scores every track — the language in the tag or the
filename, embedded, filename matching this video's stem, minus points for SDH,
forced and signs-only tracks — and selects the winner in one press. English and
Turkish sit in bands 500 points apart, wider than every other signal put
together, so an English track always wins when there is one and Turkish is the
fallback; nothing about being embedded or default can lift one language over
the other.

> **A release with two tracks of one language used to defeat this** (fixed
> 2026-09-10). Attack on Titan carries "Signs & Songs" and "Full Subtitles",
> both embedded, both tagged `eng` — and they scored *identically*, so the tie
> broke on track order and `c` landed on the signs track, which captions
> on-screen text and song lyrics but not one word of the dialogue. Subtitles
> were on and nothing appeared while people talked. Pressing `c` again went
> straight to off, because the cycle only ever held the single best track per
> language. Both halves are fixed: a signs-only track now scores 50 below a
> full one, and the cycle walks every track of a language before moving on.
> Solo Leveling had the same shape, an embedded "English Signs" against the
> full dialogue in a sidecar `.srt`, and was picking the signs track too.

> **Only tracks that belong to this file are in the cycle.** With
> `sub-auto=all`, opening one Solo Leveling episode loads all twelve `.srt`
> files in the folder, and all twelve read as English. An external subtitle
> only becomes a step in the cycle if its name matches the video's — unless
> *none* of them do, which is exactly the `Subs/English.srt` case, where the
> filter stands down rather than leaving you with nothing. Five is the cap per
> language; `Alt`+`c` reaches anything past it.

> **A subtitle named after nothing but its language code** — `tur.srt`, as
> Project Hail Mary ships — arrives from mpv with *no* language tag at all,
> because mpv only reads a code out of a name shaped `<stem>.<code>.srt`. Those
> are now matched by comparing the whole filename stem against the language
> codes, so Turkish is reachable there. It has to be an exact match on the
> stem, never a substring: "tur" inside `Return` or `Saturday` would otherwise
> turn an English subtitle Turkish.

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

## When macOS itself breaks the player

**macOS 27 (September 2026).** Two keys went wrong the day the OS was upgraded:
the volume keys took about two seconds to be heard, and `/` (skip to silence)
sailed past the intro and landed a minute or more into the episode. One cause
for both.

macOS 27 refuses the channel-layout call mpv makes while setting up its
CoreAudio output whenever the samples are **planar**, so mpv silently falls back
to its AVFoundation output — and that driver holds a fixed **two second**
buffer, against CoreAudio's 0.2s:

```
[ao/coreaudio]    unable to set the input channel layout on the audio unit (…/-50)
[ao/avfoundation] using soft-buffer of 96000 samples.        96000 / 48000 = 2.0s
```

Two seconds of audio was therefore already queued at all times, which is exactly
what each symptom was:

| symptom | why the buffer caused it |
|---|---|
| volume lags ~2s | mpv applies volume in the filter chain, *before* the output buffer, so the queued audio plays out at the old level first |
| `/` overshoots | the script runs the file at speed 100 and watches `silencedetect`, so a 2s buffer puts the detector ~200 **seconds** of film ahead of the reported position |
| last ~1.3s of every file silent | the fallback driver never drains its buffer at EOF ([#18461](https://github.com/mpv-player/mpv/issues/18461)) |

The fix is one line in `mpv.conf`, `audio-format=float`: hand the audio unit
**interleaved** samples, which macOS 27 accepts. Lossless — the decoder already
produces 32-bit float and this changes only the memory layout, not the depth or
the rate. A second block covers mono files, whose layout is refused whatever the
format, by asking for stereo output on those files alone.

Measured on a real episode, pressing `/` at 0:00, against `ffmpeg
-af silencedetect` as the oracle (true next silence 6.04s):

| | lands at | takes |
|---|---|---|
| broken (AVFoundation) | 54.6s, then 330.9s | 0.5–3.7s |
| fixed (CoreAudio) | 6.09s, 6.17s, 6.17s | ~0.35s |

Upstream bug: [mpv#18384](https://github.com/mpv-player/mpv/issues/18384), open
at the time of writing. **Both blocks come out of `mpv.conf` once it is fixed.**

🔑 The general lesson: mpv falling back to another audio driver is not a quiet
substitution, and it says so only at `-v`. If timing, volume or anything
audio-adjacent goes strange after an OS upgrade, run
`mpv --msg-level=ao=v` and read which driver it actually settled on.

## Notes for future edits

Things that cost real time here, all recorded in the config comments too:

- **An OS upgrade can change which audio driver mpv uses, silently.** macOS 27
  broke `ao_coreaudio`; the AVFoundation fallback's 2s buffer then broke the
  volume keys and `/` at once. See "When macOS itself breaks the player" above.
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
- **`loop-playlist` and `keep-open` compete for the same instant.** Both act at
  the end of the *last* playlist entry, and whichever holds mpv there first
  decides what plays next — which matters because that instant is also where
  `shuffle-mode.lua` picks its next video. `keep-open=yes` **loses** the race,
  and shuffle silently degraded to sequential play once `loop-playlist=inf` was
  set: measured on an 8-clip folder, `0..7,0..7` with the loop against
  `0..7,5,6,7,2,3,4` without it.
- **`keep-open=yes` holds only at the last entry; `always` holds at every
  file.** That is both why shuffle used to be "play the folder in order, then
  jump at random when it runs out", and how it now wins the race above:
  `always` stops mpv at the end of *every* file, long before the playlist can
  run out. Measured with `loop-playlist=inf` on: `0,3,1,5,4,7,6,2` then
  `3,0,7,6,1,5,2,4` — two clean permutations. `shuffle-mode.lua` therefore
  forces `always` and leaves `loop-playlist` alone entirely.
- **`keep-open=always` means the script owns the end of the folder, so it must
  handle the case where there is nothing to deal.** A folder with a single
  video would otherwise sit paused on its last frame with shuffle on, because
  the loop that would have restarted it never gets the chance. `on_eof` seeks
  to 0 instead when `go_forward` reports it could not move.
- The launcher exposes a permanent IPC socket at `/tmp/mpv-single.sock` — the
  way to inspect a live session without touching the config.
- **A background app cannot bring itself to the front** (macOS 14's
  "cooperative activation"). Measured with mpv fullscreen on its own Space and
  Finder in front: `NSApp.activate` (what `--focus-on=all` calls),
  `NSRunningApplication activateWithOptions:` and `lsappinfo setfront` all
  return success and leave Finder in front. `open -a <bundle>` on the running
  app is honoured — Space switch included, ~0.08s — also for a window that is
  behind others, minimised or hidden. It needs a bundle to name, so the player
  runs through `app/mpv-player.app/Contents/MacOS/mpv`, a symlink: macOS then
  registers the running process as that app (`lsappinfo info <pid>` shows the
  bundle path). A symlink changes nothing else — mpv only switches to its own
  bundle behaviour on `MPVBUNDLE=true`, and privacy prompts are still charged
  to the wrapper, because a child inherits its parent's responsible process
  whatever it is.
- `open -a` on that bundle while the running mpv was **not** started from it
  raises nothing: it launches a second, empty player, which quits at once for
  want of a file. The launcher asks `lsappinfo` first. Name the bundle by path,
  not with `open -b`: that resolves the ID through Launch Services' database,
  and a test copy of the bundle under `/tmp` was never findable there (rc 1).
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
