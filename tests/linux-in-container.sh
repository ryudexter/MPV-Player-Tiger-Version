#!/bin/bash
# Installs this setup on a fresh Linux container and runs the smoke test on
# it, the way a person would: install.sh with its package-manager step, as an
# ordinary user with sudo, then tests/smoke.py against ~/.config/mpv.
#
#   docker run --rm -v "$PWD:/src:ro" debian:trixie bash /src/tests/linux-in-container.sh
#
# The CI runs it in Debian, Fedora and Arch containers. Run as root: it makes
# the user itself. /src is the checkout (read-only is fine; install.sh clones it).
set -euo pipefail
SRC=${1:-/src}

# just enough to make a user who can sudo, and to clone
if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null && apt-get install -y -qq sudo git ca-certificates >/dev/null
elif command -v dnf >/dev/null; then
    dnf install -y -q sudo git >/dev/null
elif command -v pacman >/dev/null; then
    pacman -Sy --needed --noconfirm --quiet sudo git >/dev/null
fi
id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester
echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
git config --system --add safe.directory '*'

echo "=== install.sh"
su - tester -c "MPV_SETUP_REPO=$SRC bash $SRC/install.sh"

echo "=== the Open With entry"
grep -E '^(Name|Exec|Icon)=' /home/tester/.local/share/applications/mpv-tiger.desktop

echo "=== smoke test"
su - tester -c 'python3 ~/.config/mpv/tests/smoke.py --config ~/.config/mpv --desktop --launcher'
