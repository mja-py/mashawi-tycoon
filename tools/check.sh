#!/bin/bash
# Compile-check every GDScript file inside the running project (autoloads available).
# Prints "all scripts parse" and exits 0, or lists failures and exits 1.
G=/Applications/Godot.app/Contents/MacOS/Godot
cd "$(dirname "$0")/.." || exit 1
out=$("$G" --headless --path . --quit-after 600 -- --checkscripts 2>&1)
rc=$?
if [ $rc -ne 0 ] || echo "$out" | grep -qE 'SCRIPT ERROR|Parse Error|FAILED'; then
  echo "$out" | grep -E 'SCRIPT ERROR|Parse Error|FAILED|at:' | head -20
  exit 1
fi
echo "all scripts parse ($(echo "$out" | grep -o '[0-9]* scripts' | head -1))"
