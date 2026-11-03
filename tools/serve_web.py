#!/usr/bin/env python3
"""Static server for build/web with a phone log: the shell POSTs its console errors, boot
milestones and game state to /log when it runs from a LAN address (or with ?dev=--log), and
every request + log line is appended to the file given as the 2nd argument.
    python3 tools/serve_web.py 8080 /tmp/web.log [cert.pem key.pem]
With a certificate pair the server speaks https (needed on a LAN address: the engine's audio
worklet only exists in a secure context; the phone must accept the self-signed certificate once).
"""
import datetime
import ssl
import http.server
import os
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
LOG = sys.argv[2] if len(sys.argv) > 2 else None
CERT = sys.argv[3:5] if len(sys.argv) > 4 else None
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")


def note(line):
    line = "%s %s" % (datetime.datetime.now().strftime("%H:%M:%S"), line)
    print(line, flush=True)
    if LOG:
        with open(LOG, "a") as f:
            f.write(line + "\n")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def log_message(self, fmt, *args):
        note("%s %s" % (self.client_address[0], fmt % args))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        if self.path.startswith("/log"):
            n = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(n).decode("utf-8", "replace")
            for line in body.splitlines():
                note("%s PHONE %s" % (self.client_address[0], line))
            self.send_response(204)
            self.end_headers()
        else:
            self.send_error(404)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


with Server(("0.0.0.0", PORT), Handler) as srv:
    if CERT:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(CERT[0], CERT[1])
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    note("serving %s on port %d (%s)" % (os.path.abspath(ROOT), PORT, "https" if CERT else "http"))
    srv.serve_forever()
