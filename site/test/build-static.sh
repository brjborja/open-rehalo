#!/usr/bin/env bash
# Copies only the files the website serves into dist/site, ready for GitHub Pages.
set -euo pipefail
site=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=$site/../dist/site

rm -rf "$out"
mkdir -p "$out"
cp "$site"/{index.html,style.css,firmware.js,ring.js} "$out/"
cp -R "$site/assets" "$out/"

# Every local file the page references must be there, and nothing unreferenced ships.
for f in $(cd "$out/assets" && find . -type f ! -name OFL.txt | sed 's|^\./|assets/|'); do
  grep -qF "$f" "$out/index.html" "$out/style.css" || { echo "unused, removed: $f"; rm "$out/$f"; }
done
for f in $(grep -oE '(src|href)="[^"#:]+"' "$out/index.html" | sed -E 's/.*"(.*)"/\1/' | sort -u); do
  [ -e "$out/$f" ] || { echo "missing: $f"; exit 1; }
done
du -sh "$out"
