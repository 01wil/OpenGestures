#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Regenerates Resources/AppIcon-1024.png and Resources/AppIcon.icns.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin; export PATH
cd "$(dirname "$0")/.."
swift scripts/make-icon.swift
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
iconset="$tmp/AppIcon.iconset"; mkdir -p "$iconset"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon-1024.png --out "$iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon-1024.png --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
