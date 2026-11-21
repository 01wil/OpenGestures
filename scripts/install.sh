#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copies build/OpenGestures.app to ~/Applications. A previous copy there goes to the Trash.
set -eu
cd "$(dirname "$0")/.."

src=build/OpenGestures.app
dest="$HOME/Applications/OpenGestures.app"
[ -d "$src" ] || { echo "No $src yet; run scripts/build-app.sh first." >&2; exit 1; }

# Quit a running copy (Apple Events may be refused, so fall back to a signal) and restart it afterwards.
was_running=false
if pgrep -xq OpenGestures; then
    was_running=true
    osascript -e 'quit app "OpenGestures"' >/dev/null 2>&1 || true
    sleep 1
    pkill -x OpenGestures 2>/dev/null || true
fi
mkdir -p "$HOME/Applications"
if [ -e "$dest" ]; then
    mv "$dest" "$HOME/.Trash/OpenGestures-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "$src" "$dest"
# Folders synced by iCloud (e.g. ~/Desktop) tag files with extended attributes that make the
# signature check fail; the installed copy must not carry them.
xattr -cr "$dest"
codesign --verify --strict "$dest"
echo "Installed $dest"
if $was_running; then open "$dest"; fi
