#!/usr/bin/env python3
"""Nachgebauter Server für tests/net_abruf.gd: jede Art Antwort, die Uzais Netzfaden (src/core/abruf.gd)
aushalten muss. Nur 127.0.0.1.

  python3 tests/fake_netz.py <port> [<zertifikat.pem> <schluessel.pem>]

Mit Zertifikat spricht er TLS (die Probe erzeugt beides selbst und vertraut nur diesem Zertifikat).
"""
import gzip, json, ssl, sys, time, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1])
DATEN = json.dumps({"titel": "Uzai", "zahl": 7, "leer": None, "liste": [1, None, {"x": None}]}).encode()


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def kopf(self, code, laenge=None, mehr=None, typ="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", typ)
        if laenge is not None:
            self.send_header("Content-Length", str(laenge))
        for k, v in (mehr or {}).items():
            self.send_header(k, v)
        self.end_headers()

    def alles(self, code, inhalt, mehr=None, typ="application/json"):
        self.kopf(code, len(inhalt), mehr, typ)
        self.wfile.write(inhalt)

    def do_HEAD(self):
        self.kopf(200, len(DATEN))

    def do_POST(self):
        if urlparse(self.path).path == "/um/fremd":
            # Formular an einen anderen Ursprung weiterleiten: Uzai darf dem nicht folgen.
            n = int(self.headers.get("Content-Length", "0") or 0)
            if n:
                self.rfile.read(n)
            self.kopf(302, 0, {"Location": "http://localhost:%d/echo" % PORT})
            return
        self.echo()

    def do_PUT(self):
        self.echo()

    def do_DELETE(self):
        self.echo()

    def echo(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        text = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        self.alles(200, json.dumps({"methode": self.command, "inhalt": text, "laenge": self.headers.get("Content-Length"),
                                    "agent": self.headers.get("User-Agent"), "typ": self.headers.get("Content-Type"),
                                    "probe": self.headers.get("X-Probe"), "packen": self.headers.get("Accept-Encoding"),
                                    "host": self.headers.get("Host"), "zugang": self.headers.get("Authorization"),
                                    "schluessel": self.headers.get("X-API-Key")}).encode())

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        p = u.path
        if p == "/json":
            self.alles(200, DATEN)
        elif p == "/echo":
            self.echo()
        elif p == "/gzip":
            self.alles(200, gzip.compress(DATEN), {"Content-Encoding": "gzip"})
        elif p == "/deflate":
            self.alles(200, zlib.compress(DATEN), {"Content-Encoding": "deflate"})
        elif p == "/bombe":
            # 40 MB Nullen, gepackt rund 40 KB: darf nie ganz entpackt werden, wenn die Grenze kleiner ist.
            self.alles(200, gzip.compress(b"\0" * (40 * 1024 * 1024)), {"Content-Encoding": "gzip"})
        elif p == "/kaputt-gepackt":
            self.alles(200, b"das ist kein gzip", {"Content-Encoding": "gzip"})
        elif p == "/stuecke":
            self.kopf(200, None, {"Transfer-Encoding": "chunked"})
            for teil in [DATEN[:10], DATEN[10:25], DATEN[25:]]:
                self.wfile.write(b"%x\r\n" % len(teil) + teil + b"\r\n")
                self.wfile.flush()
                time.sleep(0.05)
            self.wfile.write(b"0\r\n\r\n")
        elif p == "/ohne-laenge":
            self.kopf(200, None, {"Connection": "close"})
            self.wfile.write(DATEN)
            self.close_connection = True
        elif p == "/leer":
            self.kopf(204, None)
        elif p == "/404":
            self.alles(404, b'{"fehler": "gibt es nicht"}')
        elif p == "/um/1":
            self.kopf(302, 0, {"Location": "/um/2"})
        elif p == "/um/2":
            self.kopf(301, 0, {"Location": "daneben"})
        elif p == "/um/daneben":
            self.kopf(302, 0, {"Location": "http://127.0.0.1:%d/json" % PORT})
        elif p == "/um/gleich":
            self.kopf(302, 0, {"Location": "/echo"})
        elif p == "/um/fremd":
            # Derselbe Server unter einem anderen Namen: für Uzai ein anderer Ursprung.
            self.kopf(302, 0, {"Location": "http://localhost:%d/echo" % PORT})
        elif p == "/um/schleife":
            self.kopf(302, 0, {"Location": "/um/schleife"})
        elif p == "/um/ohne-ziel":
            self.alles(302, b'{"umleitung": "ohne Ziel"}')
        elif p == "/307":
            self.alles(307, b"{}", {"Location": "/json"})
        elif p == "/gross":
            n = int(q.get("n", ["100000"])[0])
            self.kopf(200, n, typ="application/octet-stream")
            block = bytes(range(256)) * 256
            rest = n
            while rest > 0:
                self.wfile.write(block[:min(rest, len(block))])
                rest -= min(rest, len(block))
        elif p == "/langsam":
            # Tropft: alle 0,2 s ein Stück, zusammen 6 s. Bewegt sich also, dauert aber länger als die Frist.
            self.kopf(200, 30, typ="text/plain")
            for i in range(30):
                self.wfile.write(b"x")
                self.wfile.flush()
                time.sleep(0.2)
        elif p == "/still":
            # Verbindung annehmen, Anfrage lesen, dann nichts mehr – wie ein WLAN, das mittendrin wegfällt.
            time.sleep(600)
        elif p == "/halb":
            self.kopf(200, 1000, typ="text/plain")
            self.wfile.write(b"y" * 100)
            self.wfile.flush()
            time.sleep(600)
        elif p == "/abriss":
            self.kopf(200, 1000, typ="text/plain")
            self.wfile.write(b"z" * 100)
            self.wfile.flush()
            self.close_connection = True
        else:
            self.alles(404, b"{}")


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        pass   # Die Probe bricht Verbindungen mit Absicht ab: kein Fehlerbericht je Abbruch.


srv = Server(("127.0.0.1", PORT), H)
if len(sys.argv) >= 4:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(sys.argv[2], sys.argv[3])
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
