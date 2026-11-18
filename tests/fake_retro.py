#!/usr/bin/env python3
"""Nachgebaute offizielle Quellen für die Netz-Probe „Retro ohne Einrichtung“ (tests/net_retroauto.gd).

Uzai lenkt mit UZAI_RETRO_FAKE=http://127.0.0.1:<port> (nur zusammen mit UZAI_TEST_LOOPBACK=1) jede
feste https-Adresse hierher um: https://<host>/<pfad> → /<host>/<pfad>. Nachgebaut sind:
- api.github.com/repos/stenzek/duckstation/releases/latest  (Release mit einem Windows-Paket)
- github.com/stenzek/duckstation/releases/download/latest/…   (302 zum Dateiserver, wie GitHub)
- release-assets.githubusercontent.com/duck.zip               (das Paket, HEAD und GET)
- buildbot.libretro.com/nightly/windows/x86_64/latest/        (.index-extended und mgba-Kern)
Zustand über /__set?mode=…: gut | neu (andere Fassung) | falsch (falsche SHA-256) | slip (Paket mit
„../evil.txt“) | boese (Weiterleitung zu einem fremden Host) | gross (mehr Bytes als angekündigt) |
langsam (Paket tröpfelt) | kern_falsch (CRC des Kerns stimmt nicht).
Nichts davon ist ein echtes Programm – die „.exe“ ist ein paar Bytes Text.
Aufruf: python3 fake_retro.py <port>
"""
import hashlib
import io
import json
import os
import sys
import time
import zipfile
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

STATE = {"mode": "gut"}
EXE = "duckstation-qt-x64-ReleaseLTCG.exe"
FILLER = os.urandom(11 * 1024 * 1024)


def make_zip(entries, compress=zipfile.ZIP_DEFLATED):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compress) as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 1, 12, 0, 0))
            info.compress_type = zipfile.ZIP_STORED if name.endswith(".bin") else compress
            z.writestr(info, data)
    return buf.getvalue()


GOOD = make_zip([(EXE, b"MZ nur Text, kein Programm"), ("resources/gamecontrollerdb.txt", b"# Testdaten\n" * 200),
                 ("resources/big.bin", FILLER), ("translations/de.qm", b"qm" * 300)])
NEW = make_zip([(EXE, b"MZ neue Fassung, nur Text"), ("resources/big.bin", FILLER), ("translations/de.qm", b"qm" * 301)])
SLIP = make_zip([(EXE, b"MZ"), ("resources/big.bin", FILLER), ("../evil.txt", b"boese")])
CORE = make_zip([("mgba_libretro.dll", b"MZ Kern, nur Text " * 50)])


def package():
    m = STATE["mode"]
    if m == "slip":
        return SLIP
    if m == "neu":
        return NEW
    return GOOD


def release():
    data = package()
    digest = hashlib.sha256(data).hexdigest()
    if STATE["mode"] == "falsch":
        digest = hashlib.sha256(b"etwas anderes").hexdigest()
    return {
        "tag_name": "latest", "name": "Latest Rolling Release", "draft": False, "prerelease": False,
        "published_at": "2026-10-12T08:00:00Z" if STATE["mode"] != "neu" else "2026-10-20T08:00:00Z",
        "assets": [
            {"name": "duckstation-windows-x64-installer.exe", "size": 45000000, "digest": "sha256:" + "1" * 64,
             "browser_download_url": "https://github.com/stenzek/duckstation/releases/download/latest/duckstation-windows-x64-installer.exe"},
            {"name": "duckstation-windows-x64-release.zip", "size": len(data), "digest": "sha256:" + digest,
             "browser_download_url": "https://github.com/stenzek/duckstation/releases/download/latest/duckstation-windows-x64-release.zip"},
        ],
    }


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="application/octet-stream", head=False, extra=None, length=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body) if length is None else length))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if not head and body:
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass  # Uzai bricht ab (zu groß, Abbrechen) – so soll es sein

    def do_HEAD(self):
        self._route(True)

    def do_GET(self):
        self._route(False)

    def _route(self, head):
        u = urlparse(self.path)
        p = u.path
        if p == "/__set":
            STATE["mode"] = parse_qs(u.query).get("mode", ["gut"])[0]
            return self._send(200, b"ok", "text/plain", head)
        if p == "/api.github.com/repos/stenzek/duckstation/releases/latest":
            return self._send(200, json.dumps(release()).encode(), "application/json", head)
        if p == "/github.com/stenzek/duckstation/releases/download/latest/duckstation-windows-x64-release.zip":
            to = "https://evil.example/duck.zip" if STATE["mode"] == "boese" else "https://release-assets.githubusercontent.com/duck.zip?sig=abc"
            return self._send(302, b"", "text/plain", head, {"Location": to})
        if p == "/release-assets.githubusercontent.com/duck.zip":
            data = package()
            if STATE["mode"] == "gross":
                data = data + b"x" * 4096
            if head or STATE["mode"] != "langsam":
                return self._send(200, data, "application/zip", head)
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            try:
                for i in range(0, len(data), 32768):
                    self.wfile.write(data[i:i + 32768])
                    self.wfile.flush()
                    time.sleep(0.05)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if p == "/buildbot.libretro.com/nightly/windows/x86_64/latest/.index-extended":
            crc = zlib.crc32(CORE) & 0xFFFFFFFF
            if STATE["mode"] == "kern_falsch":
                crc ^= 0x1234
            body = ("2026-10-20 %08x mgba_libretro.dll.zip\n2026-10-20 0badc0de bsnes_libretro.dll.zip\n" % crc).encode()
            return self._send(200, body, "text/plain", head)
        if p == "/buildbot.libretro.com/nightly/windows/x86_64/latest/mgba_libretro.dll.zip":
            return self._send(200, CORE, "application/zip", head)
        self._send(404, b"nicht da", "text/plain", head)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
