#!/bin/bash
# Serves the web export locally on every interface: http://localhost:8080/ on this Mac, and
# http://<this Mac's LAN IP>:8080/ from a phone on the same Wi-Fi (ipconfig getifaddr en0).
# No special headers needed: no-threads build. Note the PWA service worker only registers on
# localhost or https, so a LAN visit runs without the offline cache (everything else works).
# The shell posts the phone's console errors, boot milestones and game state to /log when it
# runs from a LAN address; everything is appended to the log file (2nd arg, default
# build/web.log) so a phone session can be read from this Mac.
# A phone needs https (the engine's audio worklet only exists in a secure context; localhost
# is exempt): pass a self-signed cert + key as args 3 and 4 and accept the certificate warning
# once on the phone, e.g.
#   openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 60 \
#     -subj "/CN=mashawi dev" -addext "subjectAltName=IP:$(ipconfig getifaddr en0),DNS:localhost"
#   tools/serve_web.sh 8443 build/web.log cert.pem key.pem
cd "$(dirname "$0")/.." || exit 1
SCHEME=http; [ -n "$3" ] && SCHEME=https
echo "LAN URL: $SCHEME://$(ipconfig getifaddr en0 2>/dev/null || hostname):${1:-8080}/   log: ${2:-build/web.log}"
exec python3 tools/serve_web.py "${1:-8080}" "${2:-build/web.log}" "${@:3}"
