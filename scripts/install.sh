#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copies build/OpenGestures.app to ~/Applications. A previous copy there goes to the Trash, or next to
# the app if the Trash is not writable. Every check runs before a running copy is quit, and if
# anything fails after that, the old copy is put back and relaunched.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin; export PATH
cd "$(dirname "$0")/.."

src=build/OpenGestures.app
apps="$HOME/Applications"
dest="$apps/OpenGestures.app"
stage="$apps/.OpenGestures-new.app"
stamp=$(date +%Y%m%d-%H%M%S)
[ -d "$src" ] || { echo "No $src yet; run scripts/build-app.sh first." >&2; exit 1; }

mkdir -p "$apps"
rm -rf "$stage"
# Stage and verify the new copy first. Folders synced by iCloud (e.g. ~/Desktop) tag files with
# extended attributes that make the signature check fail; the installed copy must not carry them.
ditto "$src" "$stage"
xattr -cr "$stage"
codesign --verify --strict "$stage"

# Move the old copy aside while it is still running; the process keeps going from the moved bundle.
backup=
if [ -e "$dest" ]; then
    if [ -d "$HOME/.Trash" ] && [ -w "$HOME/.Trash" ]; then
        backup="$HOME/.Trash/OpenGestures-$stamp.app"
    else
        backup="$apps/OpenGestures-old-$stamp.app"
        echo "~/.Trash is not writable; keeping the old copy at $backup" >&2
    fi
    mv "$dest" "$backup" || { rm -rf "$stage"; exit 1; }
fi

was_running=false
done_ok=false
undo() {
    [ "$done_ok" = true ] && return
    rm -rf "$stage"
    if [ -n "$backup" ] && [ ! -e "$dest" ] && [ -e "$backup" ]; then mv "$backup" "$dest" || true; fi
    echo "Install failed; restored the previous copy." >&2
    if $was_running && [ -e "$dest" ]; then open "$dest" || true; fi
}
trap undo EXIT

# Quit a running copy (Apple Events may be refused, so fall back to a signal) and restart it afterwards.
if pgrep -xq OpenGestures; then
    was_running=true
    osascript -e 'quit app "OpenGestures"' >/dev/null 2>&1 || true
    sleep 1
    pkill -x OpenGestures 2>/dev/null || true
fi
mv "$stage" "$dest"
done_ok=true
echo "Installed $dest"
if $was_running; then open "$dest"; fi
