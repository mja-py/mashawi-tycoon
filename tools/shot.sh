#!/bin/bash
# Usage: tools/shot.sh <out.png> [delay] [game args...]
# Runs the game windowed with dev flags and saves a screenshot.
G=/Applications/Godot.app/Contents/MacOS/Godot
OUT="$1"; shift
DELAY="${1:-4}"; shift
cd "$(dirname "$0")/.." || exit 1
"$G" --path . --resolution 1280x720 -- "$@" --screenshot="$OUT" --delay="$DELAY" 2>&1 | grep -i -E 'error|script' | grep -v -i 'opengl|vulkan|metal' | head -12
