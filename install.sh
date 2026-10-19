#!/bin/bash
# Installs MPV Player: Tiger Version (this mpv setup) on a Mac or on Linux, or
# fills in whatever is missing from an existing install. Safe to run again: it
# never overwrites anything it did not make, and moves aside anything it has to
# replace. (Windows has its own: install.ps1.)
#
#   curl -fsSL https://raw.githubusercontent.com/ryudexter/MPV-Player-Tiger-Version/main/install.sh | bash
#
# or from a clone:   ./install.sh
#
# Options (through curl, pass them as  ... | bash -s -- --no-deps):
#   --no-deps      don't install anything with Homebrew, the Linux package
#                  manager or pipx
#   --no-remote    skip the MPV Remote script for the iPhone app (macOS only)
#   --rebuild-app  rebuild mpv.app even if it is already there. macOS ties the
#                  app's folder-access grants to its signature, so a rebuilt
#                  app asks for Desktop/Downloads access again.
#   --uninstall    Linux: take the "Open With" entry out again (the config
#                  folder stays). On a Mac, drag mpv.app to the Trash.
#
# On Linux it uses apt, dnf, pacman or zypper - asking for your password
# through sudo - and adds an "mpv (Tiger Version)" entry to the desktop's Open
# With menu instead of building an app.
#
# MPV_SETUP_REPO, MPV_SETUP_CONF and MPV_SETUP_APPS override the repository,
# the config folder and the Applications folder (for testing).

set -euo pipefail

REPO=${MPV_SETUP_REPO:-https://github.com/ryudexter/MPV-Player-Tiger-Version.git}
CONF=${MPV_SETUP_CONF:-$HOME/.config/mpv}
REMOTE_ZIP=https://github.com/ryudexter/mpv-remote/releases/latest/download/mpv-remote.zip
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# /Applications needs an admin account; anyone else gets ~/Applications, which
# Finder and Open With treat the same.
if [ -n "${MPV_SETUP_APPS:-}" ]; then APPS=$MPV_SETUP_APPS
elif [ -w /Applications ]; then APPS=/Applications
else APPS=$HOME/Applications
fi

deps=1 remote=1 rebuild=0 uninstall=0
for arg in "$@"; do
    case $arg in
        --no-deps)     deps=0 ;;
        --no-remote)   remote=0 ;;
        --rebuild-app) rebuild=1 ;;
        --uninstall)   uninstall=1 ;;
        *) echo "Unknown option: $arg (options: --no-deps --no-remote --rebuild-app --uninstall)" >&2
           exit 2 ;;
    esac
done

say()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*" >&2; }

OS=$(uname -s)
case $OS in
    Darwin|Linux) ;;
    *) echo "This setup is for macOS and Linux - and Windows, with install.ps1." >&2; exit 1 ;;
esac
# mpv on Linux follows XDG_CONFIG_HOME when it is set, so the setup must too
[ "$OS" = Linux ] && [ -z "${MPV_SETUP_CONF:-}" ] && CONF=${XDG_CONFIG_HOME:-$HOME/.config}/mpv
[ "$(id -u)" -ne 0 ] || { echo "Run this as yourself, not with sudo." >&2; exit 1; }
if [ "$OS" = Darwin ]; then
xcode-select -p >/dev/null 2>&1 || {
    echo "Needs Apple's command line tools first: run  xcode-select --install  then this again." >&2
    exit 1
}
fi

stamp=$(date +%Y%m%d-%H%M%S)
PREFIX=
[ "$OS" = Darwin ] && command -v brew >/dev/null 2>&1 && PREFIX=$(brew --prefix)

# Linux: where the "Open With" entry and its icon go (the XDG user locations)
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
DESKTOP_FILE=$DATA/applications/mpv-tiger.desktop
ICON_FILE=$DATA/icons/hicolor/256x256/apps/mpv-tiger.png

if [ $uninstall = 1 ]; then
    [ "$OS" = Linux ] || { echo "On a Mac, drag mpv.app from Applications to the Trash." >&2; exit 1; }
    say "Removing the mpv (Tiger Version) entry from Open With"
    rm -f "$DESKTOP_FILE" "$ICON_FILE"
    command -v update-desktop-database >/dev/null 2>&1 \
        && update-desktop-database "$DATA/applications" 2>/dev/null || true
    note "Done. The config folder is left where it is: $CONF"
    exit 0
fi

# --- 1. What the scripts call out to -----------------------------------------

# Linux: the distribution's own packages, then pipx for the Python tools. Each
# package is asked for on its own, so one missing name (they differ between
# distributions, and between releases of one) does not stop the rest.
linux_deps() {
    say "Installing mpv and the tools the scripts use"
    local pm= pkgs= p
    if command -v apt-get >/dev/null 2>&1; then
        pm="sudo apt-get install -y"
        # gio (for the trash key) is in libglib2.0-bin on Debian and Ubuntu
        pkgs="mpv ffmpeg git python3 pipx libglib2.0-bin dbus"
        sudo apt-get update -qq || true
    elif command -v dnf >/dev/null 2>&1; then
        pm="sudo dnf install -y"
        pkgs="mpv ffmpeg-free git python3 pipx glib2 dbus-tools"
    elif command -v pacman >/dev/null 2>&1; then
        pm="sudo pacman -S --needed --noconfirm"
        pkgs="mpv ffmpeg git python python-pipx glib2 dbus"
    elif command -v zypper >/dev/null 2>&1; then
        pm="sudo zypper --non-interactive install"
        pkgs="mpv ffmpeg git python3 python3-pipx glib2-tools dbus-1"
    else
        warn "No apt, dnf, pacman or zypper here. Install these yourself: mpv (0.39 or newer),"
        warn "ffmpeg, git, python3 and pipx - then run this again with --no-deps."
        return
    fi
    # </dev/null: under curl | bash, stdin is the rest of this script, and a
    # package manager that reads it would swallow it (sudo asks on the tty).
    for p in $pkgs; do
        $pm "$p" </dev/null >/dev/null 2>&1 && note "$p: ok" || warn "$p didn't install with: $pm $p"
    done
    # pipx rather than the distribution for yt-dlp: YouTube changes often and a
    # distribution's yt-dlp is usually too old to keep up.
    if command -v pipx >/dev/null 2>&1; then
        for p in yt-dlp subliminal ffsubsync; do
            if [ -x "$HOME/.local/bin/$p" ]; then note "$p: already installed"
            else pipx install "$p" </dev/null >/dev/null 2>&1 && note "$p: installed" \
                || warn "$p didn't install: run  pipx install $p  later"
            fi
        done
    else
        warn "No pipx: YouTube links (yt-dlp), b and Alt+b (subliminal, ffsubsync) need it"
    fi
}

if [ $deps = 1 ] && [ "$OS" = Linux ]; then
    linux_deps
elif [ $deps = 1 ]; then
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
if [ "$OS" = Darwin ]; then
[ -n "$PREFIX" ] || PREFIX=/opt/homebrew
export PATH="$PREFIX/bin:$PATH"
[ -x "$PREFIX/bin/mpv" ] || warn "No mpv at $PREFIX/bin/mpv. This setup runs Homebrew's: brew install mpv"
else
    # The setup leans on mpv 0.39's folder playlists (autocreate-playlist) and
    # its searchable track menus. Ubuntu 24.04 LTS, for one, still ships 0.37.
    if ! command -v mpv >/dev/null 2>&1; then
        warn "No mpv on PATH. Install mpv 0.39 or newer from your distribution."
    else
        v=$(mpv --no-config --version 2>/dev/null | sed -n 's/^mpv v\{0,1\}\([0-9]*\)\.\([0-9]*\).*/\1 \2/p' | head -1)
        set -- $v
        if [ -n "${1:-}" ] && { [ "$1" -eq 0 ] && [ "${2:-0}" -lt 39 ]; }; then
            warn "This mpv is $1.$2. The setup needs 0.39 or newer: opening one video will not"
            warn "queue its folder, and Alt+c / Alt+l will do nothing. See \"Linux\" in README.md."
        else
            note "mpv ${1:-?}.${2:-?}"
        fi
    fi
    command -v git >/dev/null 2>&1 || { echo "Needs git: install it with your package manager, then run this again." >&2; exit 1; }
fi

# --- 2. The config itself -----------------------------------------------------

say "Putting the setup in $CONF"
origin=$(git -C "$CONF" remote get-url origin 2>/dev/null || true)
if [ -d "$CONF/.git" ] && { [ "$origin" = "$REPO" ] || [[ $origin == *MPV-Player-Tiger-Version* || $origin == *mpv-macos-setup* ]]; }; then
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
if [ "$OS" = Darwin ] && [ "$PREFIX" != /opt/homebrew ]; then
    say "Pointing the setup at Homebrew in $PREFIX"
    sed -i '' "s#/opt/homebrew/bin/#$PREFIX/bin/#g" \
        mpv.conf mpv-open script-opts/thumbfast.conf script-opts/webm.conf
    ln -sfn "$PREFIX/bin/mpv" app/mpv-player.app/Contents/MacOS/mpv
    note "That changes 5 files git tracks. Before a git pull:  git stash; git pull; git stash pop"
fi

# --- 3. The Cmd+Delete sounds ---------------------------------------------------

# They come with the repo; this only rebuilds them, from this Mac's own system
# sounds, if they have gone missing.
if [ "$OS" = Darwin ] && [ ! -f sounds/trash-poof.wav ]; then
    say "Making the Cmd+Delete sounds from this Mac's system sounds"
    if ! command -v ffmpeg >/dev/null 2>&1; then
        warn "Needs ffmpeg (brew install ffmpeg). Cmd+Delete still works, just silently."
    elif sounds/make-trash-sounds.sh >/dev/null; then
        note "Made"
    else
        warn "Couldn't make them. Cmd+Delete still works, just silently."
    fi
fi

# --- 4. Linux: the Open With entry --------------------------------------------------

linux_desktop() {
    say "Adding mpv (Tiger Version) to Open With"
    mkdir -p "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON_FILE")" \
             "${XDG_STATE_HOME:-$HOME/.local/state}/mpv"    # ~~state: the volume, resume points
    cp app/icons/mpv.png "$ICON_FILE"
    # Exec names the launcher by absolute path: a desktop file expands nothing
    sed -e '/^#/d' -e "s#@@MPV_OPEN@@#$CONF/mpv-open#" linux/mpv-tiger.desktop > "$DESKTOP_FILE"
    chmod +x mpv-open
    command -v update-desktop-database >/dev/null 2>&1 \
        && update-desktop-database "$DATA/applications" 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 \
        && gtk-update-icon-cache -q -t "$DATA/icons/hicolor" 2>/dev/null || true
    note "Added $DESKTOP_FILE"
}

if [ "$OS" = Linux ]; then
    linux_desktop
    say "MPV Player: Tiger Version is installed"
    cat <<EOF
    Play a video: right-click it, then Open With > mpv (Tiger Version).
    Make it the default: in the file manager's Open With dialog, pick it and
    choose "Set as default" / "Always use". For every kind of video at once:
      xdg-mime default mpv-tiger.desktop \$(grep '^MimeType=' "$DESKTOP_FILE" | cut -d= -f2 | tr ';' ' ')
    The Cmd shortcuts in the guide are Ctrl here (Ctrl+Delete, Ctrl+t, ...).
    Every key and feature: $CONF/field-guide.html
    The MPV Remote iPhone app is macOS-only for now, so it is not installed here.
EOF
    exit 0
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
