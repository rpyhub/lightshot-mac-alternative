#!/bin/sh
# Testleri derler ve çalıştırır: ./tests/run.sh   (hata varsa çıkış kodu 1)
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
[ -d /Library/Developer/CommandLineTools ] && export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swiftc -target arm64-apple-macos13 main.swift ../Overlay.swift ../Features.swift -o "$OUT/t"
"$OUT/t"
