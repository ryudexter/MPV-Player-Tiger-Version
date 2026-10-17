#!/bin/bash
# Installs MPV Player: Tiger Version (this mpv setup) on a Mac, or fills in
# whatever is missing from an existing install. Safe to run again: it never
# overwrites anything it did not make, and moves aside anything it has to
# replace.
#
#   curl -fsSL https://raw.githubusercontent.com/ryudexter/mpv-macos-setup/main/install.sh | bash
#
# or from a clone:   ./install.sh
#
# Options (through curl, pass them as  ... | bash -s -- --no-deps):
#   --no-deps      don't install anything with Homebrew or pipx
#   --no-remote    skip the MPV Remote script for the iPhone app
#   --rebuild-app  rebuild mpv.app even if it is already there. macOS ties the
#                  app's folder-access grants to its signature, so a rebuilt
#                  app asks for Desktop/Downloads access again.
#
# MPV_SETUP_REPO, MPV_SETUP_CONF and MPV_SETUP_APPS override the repository,
# the config folder and the Applications folder (for testing).

set -euo pipefail

REPO=${MPV_SETUP_REPO:-https://github.com/ryudexter/mpv-macos-setup.git}
CONF=${MPV_SETUP_CONF:-$HOME/.config/mpv}
REMOTE_ZIP=https://github.com/ryudexter/mpv-remote/releases/latest/download/mpv-remote.zip
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# /Applications needs an admin account; anyone else gets ~/Applications, which
# Finder and Open With treat the same.
if [ -n "${MPV_SETUP_APPS:-}" ]; then APPS=$MPV_SETUP_APPS
elif [ -w /Applications ]; then APPS=/Applications
else APPS=$HOME/Applications
fi

deps=1 remote=1 rebuild=0
for arg in "$@"; do
    case $arg in
        --no-deps)     deps=0 ;;
        --no-remote)   remote=0 ;;
        --rebuild-app) rebuild=1 ;;
        *) echo "Unknown option: $arg (options: --no-deps --no-remote --rebuild-app)" >&2
           exit 2 ;;
    esac
done

say()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*" >&2; }

[ "$(uname -s)" = Darwin ] || { echo "This setup is for macOS." >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || { echo "Run this as yourself, not with sudo." >&2; exit 1; }
xcode-select -p >/dev/null 2>&1 || {
    echo "Needs Apple's command line tools first: run  xcode-select --install  then this again." >&2
    exit 1
}

stamp=$(date +%Y%m%d-%H%M%S)
PREFIX=
command -v brew >/dev/null 2>&1 && PREFIX=$(brew --prefix)

# --- 1. What the scripts call out to -----------------------------------------

if [ $deps = 1 ]; then
    say "Installing mpv and the tools the scripts use"
    [ -n "$PREFIX" ] || {
        echo "Needs Homebrew first: install it from https://brew.sh, then run this again." >&2
        exit 1
    }
    for f in mpv yt-dlp pipx; do       # mpv brings ffmpeg with it
        if brew list --formula "$f" >/dev/null 2>&1; then note "$f: already installed"
        else brew install "$f"; fi
    done
    # Finder thumbnails and previews for MKV, WebM and the rest. Nice to have.
    if brew list --cask quicklook-video >/dev/null 2>&1; then note "quicklook-video: already installed"
    else brew install --cask quicklook-video \
        || warn "quicklook-video didn't install: Finder just won't preview MKV or WebM files"
    fi
    # The scripts run these from ~/.local/bin, pipx's default, by absolute
    # path: an app opened from Finder does not get the shell's PATH.
    for p in subliminal ffsubsync; do
        if [ -x "$HOME/.local/bin/$p" ]; then note "$p: already installed"
        else "$PREFIX/bin/pipx" install "$p" \
            || warn "$p didn't install: run  pipx install $p  later (b / Alt+b need it)"
        fi
    done
fi
[ -n "$PREFIX" ] || PREFIX=/opt/homebrew
export PATH="$PREFIX/bin:$PATH"
[ -x "$PREFIX/bin/mpv" ] || warn "No mpv at $PREFIX/bin/mpv. This setup runs Homebrew's: brew install mpv"

# --- 2. The config itself -----------------------------------------------------

say "Putting the setup in $CONF"
origin=$(git -C "$CONF" remote get-url origin 2>/dev/null || true)
if [ -d "$CONF/.git" ] && { [ "$origin" = "$REPO" ] || [[ $origin == *mpv-macos-setup* ]]; }; then
    note "Already there. To update it later:  git -C \"$CONF\" pull"
else
    # Clone next to it first, so a failed clone leaves the old config in place.
    mkdir -p "$(dirname "$CONF")"
    git clone --quiet "$REPO" "$CONF.installing-$stamp"
    backup=
    if [ -e "$CONF" ]; then
        backup="$CONF.backup-$stamp"
        mv "$CONF" "$backup"
        note "Your previous mpv config is now at $backup"
    fi
    mv "$CONF.installing-$stamp" "$CONF"
    # Keep its resume positions, so nothing half-watched restarts from 0.
    if [ -n "$backup" ] && [ -d "$backup/watch_later" ]; then
        cp -R "$backup/watch_later" "$CONF/"
        note "Kept its saved playback positions"
    fi
fi
cd "$CONF"

# The setup names Homebrew's paths outright, because an app opened from Finder
# does not get the shell's PATH. Homebrew on Intel lives in /usr/local instead.
if [ "$PREFIX" != /opt/homebrew ]; then
    say "Pointing the setup at Homebrew in $PREFIX"
    sed -i '' "s#/opt/homebrew/bin/#$PREFIX/bin/#g" \
        mpv.conf mpv-open script-opts/thumbfast.conf script-opts/webm.conf
    ln -sfn "$PREFIX/bin/mpv" app/mpv-player.app/Contents/MacOS/mpv
    note "That changes 5 files git tracks. Before a git pull:  git stash; git pull; git stash pop"
fi

# --- 3. The Cmd+Delete sounds ---------------------------------------------------

# They come with the repo; this only rebuilds them, from this Mac's own system
# sounds, if they have gone missing.
if [ ! -f sounds/trash-poof.wav ]; then
    say "Making the Cmd+Delete sounds from this Mac's system sounds"
    if ! command -v ffmpeg >/dev/null 2>&1; then
        warn "Needs ffmpeg (brew install ffmpeg). Cmd+Delete still works, just silently."
    elif sounds/make-trash-sounds.sh >/dev/null; then
        note "Made"
    else
        warn "Couldn't make them. Cmd+Delete still works, just silently."
    fi
fi

# --- 4. mpv.app, the wrapper Finder opens videos with ----------------------------

say "Setting up $APPS/mpv.app"
app="$APPS/mpv.app"
bundle_id=
[ -d "$app" ] && bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$app/Contents/Info.plist" 2>/dev/null || true)

if [ -d "$app" ] && [ "$bundle_id" != io.mpv.wrapper ]; then
    warn "There's already a different mpv.app there (${bundle_id:-unknown}). Left it alone."
    warn "To get this setup's double-click-to-play app, move that one away and run this again."
elif [ -d "$app" ] && [ $rebuild = 0 ]; then
    note "Already there. (--rebuild-app rebuilds it; macOS then asks for folder access again.)"
else
    build=$(mktemp -d)
    # osacompile reports its own re-signing on stderr even when all is well.
    osacompile -o "$build/mpv.app" app/main.applescript 2>"$build/osacompile.log" \
        || { cat "$build/osacompile.log" >&2; exit 1; }
    rm "$build/osacompile.log"
    # Keep the executable name osacompile chose; app/Info.plist names it too.
    exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$build/mpv.app/Contents/Info.plist")
    cp app/Info.plist "$build/mpv.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $exe" "$build/mpv.app/Contents/Info.plist"
    cp app/icons/*.icns "$build/mpv.app/Contents/Resources/"
    codesign -f -s - "$build/mpv.app" 2>/dev/null
    mkdir -p "$APPS"
    [ -d "$app" ] && rm -rf "$app"
    mv "$build/mpv.app" "$app"
    rmdir "$build"
    "$LSREGISTER" -f "$app" 2>/dev/null || true    # so Open With lists it right away
    note "Built"
fi

# --- 5. MPV Remote, for the iPhone app -------------------------------------------

if [ $remote = 1 ]; then
    say "Installing MPV Remote (control mpv from the MPV Player Remote iPhone app)"
    dl=$(mktemp -d)
    if curl -fsSL -o "$dl/mpv-remote.zip" "$REMOTE_ZIP" \
        && ditto -x -k "$dl/mpv-remote.zip" "$dl" \
        && [ -f "$dl/mpv-remote/main.lua" ]; then
        rm -rf scripts/mpv-remote
        mv "$dl/mpv-remote" scripts/mpv-remote
        note "Installed. It starts with mpv; pair with the code shown over the video."
    else
        warn "Couldn't download it. It's at $REMOTE_ZIP — unzip it into $CONF/scripts/"
    fi
    rm -rf "$dl"
fi

say "MPV Player: Tiger Version is installed"
cat <<EOF
    Play a video: right-click it, then Open With > mpv.
    Make mpv the default: select a video, press Cmd-I, pick mpv under
    "Open with", then click Change All.
    Every key and feature: $CONF/field-guide.html
EOF
