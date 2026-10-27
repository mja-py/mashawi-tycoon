#!/bin/bash
# Exports the Web preset into build/web and copies the static extras (.nojekyll, cover.jpg).
G=/Applications/Godot.app/Contents/MacOS/Godot
cd "$(dirname "$0")/.." || exit 1
mkdir -p build/web
"$G" --headless --path . --export-release Web build/web/index.html 2>&1 | grep -E 'DONE|ERROR' | tail -2
cp web/static/.nojekyll web/static/cover.jpg build/web/
ls -la build/web | awk '{print $5, $9}'
