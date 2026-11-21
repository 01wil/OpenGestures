#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Removes OpenGestures from this Mac: quits it, resets its Accessibility grant, moves
# ~/Applications/OpenGestures.app to the Trash and unregisters it from Launch Services. It then asks
# before deleting the config folder and before removing the local signing certificate.
# Usage: scripts/uninstall.sh [--all]   (--all answers yes to both questions)
# The login item belongs to the app bundle (SMAppService), so removing the app removes it.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin; export PATH
cd "$(dirname "$0")/.."

all=false
case "${1:-}" in
    "") ;;
    --all) all=true ;;
    *) echo "Usage: $0 [--all]" >&2; exit 2 ;;
esac

bundle_id=io.github.01wil.OpenGestures
dest="$HOME/Applications/OpenGestures.app"
config="${XDG_CONFIG_HOME:-$HOME/.config}/opengestures"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

ask() {
    $all && return 0
    printf '%s [y/N] ' "$1"
    read -r reply || reply=
    case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

if pgrep -xq OpenGestures; then
    osascript -e 'quit app "OpenGestures"' >/dev/null 2>&1 || true
    sleep 1
    pkill -x OpenGestures 2>/dev/null || true
    echo "Quit OpenGestures."
fi

# tccutil resolves the bundle identifier through the installed app, so reset before removing it.
if tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1; then
    echo "Reset the Accessibility permission."
else
    echo "Could not reset the Accessibility permission; remove OpenGestures in System Settings > Privacy & Security > Accessibility."
fi

if [ -e "$dest" ]; then
    "$lsregister" -u "$dest" 2>/dev/null || true
    if [ -d "$HOME/.Trash" ] && [ -w "$HOME/.Trash" ]; then
        trashed="$HOME/.Trash/OpenGestures-$(date +%Y%m%d-%H%M%S).app"
        mv "$dest" "$trashed"
        echo "Moved the app to $trashed"
    else
        echo "~/.Trash is not writable; delete $dest yourself." >&2
    fi
else
    echo "$dest is not installed."
fi

if [ -d "$config" ]; then
    if ask "Delete the config folder $config?"; then
        rm -rf "$config"
        echo "Deleted $config"
    else
        echo "Kept $config"
    fi
fi

if ask "Remove the \"OpenGestures Local Dev\" signing certificate from your keychain?"; then
    sh scripts/remove-signing-cert.sh
else
    echo "Kept the signing certificate. scripts/remove-signing-cert.sh removes it later."
fi
