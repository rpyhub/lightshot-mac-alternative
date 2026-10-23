#!/bin/sh
# Derler, kurar ve GitHub Release için zip üretir: dist/LightShot-<sürüm>-arm64.zip
# (build.sh imzalamada takılırsa burada da durur: imzasız zip üretilmez)
set -e
cd "$(dirname "$0")/.."
./build.sh
V=$(sed -n 's/^VERSION=//p' build.sh | head -1)
mkdir -p dist; rm -f "dist/LightShot-$V-arm64.zip"
ditto -c -k --keepParent LightShot.app "dist/LightShot-$V-arm64.zip"
echo "Hazır: dist/LightShot-$V-arm64.zip"
