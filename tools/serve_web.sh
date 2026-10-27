#!/bin/bash
# Serves the web export locally: http://localhost:8080/  (no special headers needed: no-threads build)
cd "$(dirname "$0")/../build/web" || { echo "export the Web preset first"; exit 1; }
python3 -m http.server "${1:-8080}"
