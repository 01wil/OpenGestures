#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copies build/OpenGestures.app to ~/Applications. A previous copy there goes to the Trash.
set -eu
cd "$(dirname "$0")/.."

src=build/OpenGestures.app
dest="$HOME/Applications/OpenGestures.app"
[ -d "$src" ] || { echo "No $src yet; run scripts/build-app.sh first." >&2; exit 1; }

osascript -e 'quit app "OpenGestures"' >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
if [ -e "$dest" ]; then
    mv "$dest" "$HOME/.Trash/OpenGestures-$(date +%Y%m%d-%H%M%S).app"
fi
cp -R "$src" "$dest"
echo "Installed $dest"
