#!/bin/sh
# ikonu yeniden üretir: assets/AppIcon.icns ve docs/icon.png
set -e
cd "$(dirname "$0")/.."
[ -d /Library/Developer/CommandLineTools ] && export DEVELOPER_DIR=/Library/Developer/CommandLineTools
T=$(mktemp -d)
swiftc -O scripts/make_icon.swift -o "$T/make_icon"
"$T/make_icon" "$T"
iconutil -c icns "$T/AppIcon.iconset" -o assets/AppIcon.icns
cp "$T/icon.png" docs/icon.png
rm -rf "$T"
echo "yazıldı: assets/AppIcon.icns, docs/icon.png"
