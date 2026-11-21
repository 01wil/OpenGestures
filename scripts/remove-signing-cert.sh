#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Removes the "OpenGestures Local Dev" certificate and its private key from your login keychain, and
# the code-signing trust that make-signing-cert.sh added. Safe to run again when nothing is left.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin; export PATH
name="OpenGestures Local Dev"
keychain="$HOME/Library/Keychains/login.keychain-db"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

found=false
if security find-certificate -c "$name" -p "$keychain" > "$dir/cert.pem" 2>/dev/null && [ -s "$dir/cert.pem" ]; then
    found=true
    if security remove-trusted-cert "$dir/cert.pem" 2>/dev/null; then
        echo "Removed the code-signing trust for \"$name\"."
    else
        echo "No trust setting for \"$name\" to remove."
    fi
fi

# Deletes the certificate together with its private key. Repeat in case an older run left duplicates.
deleted=0
while security delete-identity -c "$name" "$keychain" >/dev/null 2>&1; do
    deleted=$((deleted + 1))
done
# A certificate without a matching key is not an identity; remove what is left.
while security delete-certificate -c "$name" "$keychain" >/dev/null 2>&1; do
    deleted=$((deleted + 1))
done

if [ "$deleted" -gt 0 ]; then
    echo "Deleted \"$name\" from the login keychain."
elif $found; then
    echo "Could not delete \"$name\"; remove it in Keychain Access." >&2
    exit 1
else
    echo "\"$name\" is not installed; nothing to remove."
fi
