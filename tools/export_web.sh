#!/bin/bash
# Exports the Web preset and keeps the shell artwork available offline.
set -euo pipefail
G=/Applications/Godot.app/Contents/MacOS/Godot
cd "$(dirname "$0")/.." || exit 1
mkdir -p build/web
"$G" --headless --path . --export-release Web build/web/index.html > build/web-export.log 2>&1 || { cat build/web-export.log; exit 1; }
cp web/static/.nojekyll web/static/cover.jpg web/static/loading-art.webp build/web/
# The generated worker only knows about engine files. Include the shell's image
# in the same versioned cache, using a relative URL for GitHub project Pages.
python3 - <<'PY'
from pathlib import Path
import json
import re
p = Path('build/web/index.service.worker.js')
s, count = re.subn(r'(const CACHED_FILES = )(\[[^\n]*\]);',
                  lambda m: m[1] + json.dumps(json.loads(m[2]) + ['loading-art.webp']) + ';',
                  p.read_text())
if count != 1:
    raise SystemExit('Export changed: could not add loading artwork to offline cache')
# GitHub Pages opens the directory URL, while Godot caches index.html. Resolve
# that navigation to the cached page so an offline revisit can actually boot.
original = 'let cached = await cache.match(event.request);'
if s.count(original) != 1:
    raise SystemExit('Export changed: could not normalize offline navigation')
s = s.replace(original, "const cacheKey = isNavigate && new URL(event.request.url).pathname.endsWith('/')\n"
              "\t\t\t\t\t? new URL('index.html', event.request.url).href : event.request;\n"
              "\t\t\t\tlet cached = await cache.match(cacheKey, { ignoreSearch: isNavigate });")
p.write_text(s)
PY
ls -la build/web | awk '{print $5, $9}'
