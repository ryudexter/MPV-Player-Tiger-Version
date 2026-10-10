#!/bin/bash
# Rebuilds the Cmd+Delete trash sounds in this folder from macOS's own system
# sounds. Needs ffmpeg (brew install ffmpeg). Run it from anywhere:
#   ~/.config/mpv/sounds/make-trash-sounds.sh
#
# Finder's "move to trash" is 2.2 s of three separate crumples peaking at
# -0.6 dB - too long and too loud as a confirmation (2026-10-10). Each sound
# here is ONE short piece of a system sound, played slower so it sits lower,
# with the top end rolled off, a short fade so it does not click, and the level
# set so they are all equally loud: -38 LUFS short-term, 9 LU under Finder's
# (~half as loud to the ear). The user heard all four and picked trash-poof,
# which trash-file.lua plays by default. Pick another with sound= in
# script-opts/trash_file.conf; finer volume is sound_volume= there, no rebuild.

set -euo pipefail
cd "$(dirname "$0")"
SYS=/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds

# make OUT SRC START END RATE LOWPASS FADE GAIN_DB
#   RATE < 1 is tape-style slowdown: 0.8 ~ 4 semitones lower and 1.25x longer
make() {
    local out=$1 src=$2 ss=$3 to=$4 rate=$5 lp=$6 fade=$7 gain=$8
    local len fst
    len=$(awk "BEGIN{printf \"%.4f\", ($to - $ss) / $rate}")
    fst=$(awk "BEGIN{printf \"%.4f\", $len - $fade}")
    ffmpeg -v error -y -ss "$ss" -to "$to" -i "$SYS/$src" \
        -af "aformat=channel_layouts=mono,asetrate=44100*$rate,aresample=44100,lowpass=f=$lp:p=2,highpass=f=90,afade=t=in:d=0.004,afade=t=out:st=$fst:d=$fade,volume=${gain}dB" \
        -c:a pcm_s16le "$out"
    echo "made $out"
}

# Finder's first, quietest crunch, ~4 semitones down - 0.33 s
make trash-crumple.wav        "finder/move to trash.aif"    0.00 0.26 0.80 3000 0.08 5
# the same crunch ~5 semitones down and duller - 0.36 s
make trash-crumple-lower.wav  "finder/move to trash.aif"    0.00 0.26 0.72 2200 0.08 5
# Finder's second, bigger crunch, ~4 semitones down - 0.30 s
make trash-crumple-fuller.wav "finder/move to trash.aif"    0.50 0.74 0.80 3000 0.08 3.4
# THE DEFAULT. Not paper: the Dock's "poof", ~5 semitones down - a soft low
# whoosh, 0.47 s
make trash-poof.wav           "dock/poof item off dock.aif" 0.00 0.34 0.72 2500 0.10 -4
