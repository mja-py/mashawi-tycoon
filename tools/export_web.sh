#!/bin/bash
# Exports the Web preset with the shell artwork and license notices.
set -euo pipefail
G=/Applications/Godot.app/Contents/MacOS/Godot
cd "$(dirname "$0")/.." || exit 1
mkdir -p build/web
"$G" --headless --path . --export-release Web build/web/index.html > build/web-export.log 2>&1 || { cat build/web-export.log; exit 1; }
cp web/static/.nojekyll web/static/cover.jpg web/static/loading-art.webp build/web/
cp LICENSE.txt assets/fonts/OFL-BalooBhaijaan2.txt build/web/
# Include the shell artwork and notices in the versioned offline cache.
python3 - <<'PY'
from pathlib import Path
import json
import re
p = Path('build/web/index.service.worker.js')
s, count = re.subn(r'(const CACHED_FILES = )(\[[^\n]*\]);',
                  lambda m: m[1] + json.dumps(json.loads(m[2]) + [
                      'loading-art.webp', 'LICENSE.txt', 'OFL-BalooBhaijaan2.txt']) + ';',
                  p.read_text())
if count != 1:
    raise SystemExit('Export changed: could not add shell assets to offline cache')
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
