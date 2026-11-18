#!/usr/bin/env python3
"""Nachgebauter Steam-Store für die Netz-Probe des Shops (tests/net_shop.gd).

- GET /IStoreBrowseService/GetItems/v1/?input_json=…  wie api.steampowered.com: Name, Preis und
  „assets“ (asset_url_format mit ${FILENAME}, main_capsule, header, library_capsule, …).
- GET /store_item_assets/steam/apps/…  Bilder wie shared.steamstatic.com, nur unter den Pfaden,
  die es wirklich gibt:
    100  altes Spiel: alles unter den alten festen Adressen
    200  neues Spiel: alles nur im Ordner mit Prüfsumme (a1b2c3/…), alte Adressen geben 404
    300  Spiel ohne Hülle: nur Kapsel und Kopfbild (quer)
    400  kennt GetItems nicht; Kapsel und Kopfbild unter den alten Adressen
  Bilder sind einfarbige graue JPEGs (bzw. PNG für Schriftzüge) in der echten Größe.
- GET /__log (alle Anfragen), /__reset (Log leeren, Fehler aus), /__set?fail=1&delay=2
Aufruf: python3 fake_steam_store.py <port>
"""
import json
import struct
import sys
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LOG = []
STATE = {"fail": False, "delay": 0.0}

SIZES = {
    "library_600x900.jpg": (600, 900),
    "library_600x900_2x.jpg": (1200, 1800),
    "capsule_616x353.jpg": (616, 353),
    "header.jpg": (460, 215),
    "library_hero.jpg": (1920, 620),
    "library_hero_2x.jpg": (3840, 1240),
    "logo.png": (640, 360),
}

FULL = ["library_600x900.jpg", "library_600x900_2x.jpg", "capsule_616x353.jpg", "header.jpg",
        "library_hero.jpg", "library_hero_2x.jpg", "logo.png"]


def assets(fmt, prefix, files):
    keys = {"capsule_616x353.jpg": "main_capsule", "header.jpg": "header",
            "library_600x900.jpg": "library_capsule", "library_600x900_2x.jpg": "library_capsule_2x",
            "library_hero.jpg": "library_hero", "library_hero_2x.jpg": "library_hero_2x", "logo.png": "library_logo"}
    out = {"asset_url_format": fmt, "small_capsule": prefix + "capsule_231x87.jpg"}
    for f in files:
        out[keys[f]] = prefix + f
    return out


APPS = {
    100: {"name": "Altes Spiel", "dir": "", "files": FULL, "fmt": "steam/apps/100/${FILENAME}?t=100", "known": True},
    200: {"name": "Neues Spiel", "dir": "a1b2c3/", "files": FULL, "fmt": "steam/apps/200/${FILENAME}?t=200", "known": True},
    300: {"name": "Nur quer", "dir": "", "files": ["capsule_616x353.jpg", "header.jpg"], "fmt": "steam/apps/300/${FILENAME}?t=300", "known": True},
    400: {"name": "Unbekannt", "dir": "", "files": ["capsule_616x353.jpg", "header.jpg"], "fmt": "", "known": False},
}


def _bits_of(v):
    """Kategorie und Bits eines DC-Unterschieds (wie im JPEG-Standard)."""
    if v == 0:
        return 0, ""
    cat = abs(v).bit_length()
    if v > 0:
        return cat, format(v, "0%db" % cat)
    return cat, format(v + (1 << cat) - 1, "0%db" % cat)


def gray_jpeg(w, h, level):
    """Einfarbiges Graustufen-JPEG (baseline): je 8×8-Block nur ein DC-Wert, sonst nichts."""
    dc = (level - 128) * 8
    cat, bits = _bits_of(dc)
    out = bytearray(b"\xff\xd8")
    out += b"\xff\xdb" + struct.pack(">H", 67) + b"\x00" + bytes([1] * 64)
    out += b"\xff\xc0" + struct.pack(">HBHHB", 11, 8, h, w, 1) + bytes([1, 0x11, 0])
    # DC-Tabelle: zwei Codes der Länge 2 (Kategorie 0 → 00, Kategorie cat → 01)
    counts = [0, 2] + [0] * 14
    out += b"\xff\xc4" + struct.pack(">H", 3 + 16 + 2) + b"\x00" + bytes(counts) + bytes([0, cat])
    # AC-Tabelle: nur „Blockende“ (Code 0)
    counts = [1] + [0] * 15
    out += b"\xff\xc4" + struct.pack(">H", 3 + 16 + 1) + b"\x10" + bytes(counts) + bytes([0])
    out += b"\xff\xda" + struct.pack(">HB", 8, 1) + bytes([1, 0x00, 0, 63, 0])
    blocks = ((w + 7) // 8) * ((h + 7) // 8)
    stream = ("01" + bits + "0") + "000" * (blocks - 1)
    stream += "1" * (-len(stream) % 8)
    data = bytearray(int(stream[i:i + 8], 2) for i in range(0, len(stream), 8))
    for b in data:
        out.append(b)
        if b == 0xFF:
            out.append(0)
    out += b"\xff\xd9"
    return bytes(out)


def gray_png(w, h, level):
    raw = b"".join(b"\x00" + bytes([level, level, level, 255]) * w for _ in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def store_item(appid):
    app = APPS.get(appid)
    if app is None or not app["known"]:
        return {"appid": appid, "success": 2}
    return {
        "item_type": 0, "id": appid, "success": 1, "visible": True, "name": app["name"], "appid": appid,
        "is_free": False, "release": {"is_coming_soon": False},
        "best_purchase_option": {"packageid": appid * 10, "final_price_in_cents": "1999", "original_price_in_cents": "2999", "discount_pct": 33},
        "assets": assets(app["fmt"], app["dir"], app["files"]),
    }


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        p = u.path
        if p == "/__log":
            return self._send(200, json.dumps(LOG).encode())
        if p == "/__reset":
            LOG.clear()
            STATE["fail"] = False
            STATE["delay"] = 0.0
            return self._send(200, b"{}")
        if p == "/__set":
            if "fail" in q:
                STATE["fail"] = q["fail"] == ["1"]
            if "delay" in q:
                STATE["delay"] = float(q["delay"][0])
            return self._send(200, b"{}")
        LOG.append({"p": p, "q": u.query})
        if p == "/IStoreBrowseService/GetItems/v1/":
            if STATE["delay"] > 0:
                time.sleep(STATE["delay"])
            if STATE["fail"]:
                return self._send(503, b"Service Unavailable", "text/plain")
            try:
                req = json.loads(q.get("input_json", ["{}"])[0])
            except ValueError:
                return self._send(400, b"bad input_json", "text/plain")
            items = [store_item(int(e.get("appid", 0))) for e in req.get("ids", [])]
            return self._send(200, json.dumps({"response": {"store_items": items}}).encode())
        prefix = "/store_item_assets/steam/apps/"
        if p.startswith(prefix):
            rest = p[len(prefix):]
            appid_s, _, path = rest.partition("/")
            app = APPS.get(int(appid_s) if appid_s.isdigit() else -1)
            if app is not None:
                for f in app["files"]:
                    if path == app["dir"] + f:
                        w, h = SIZES[f]
                        level = 130 + (int(appid_s) // 100) * 25
                        if f.endswith(".png"):
                            return self._send(200, gray_png(w, h, level), "image/png")
                        return self._send(200, gray_jpeg(w, h, level), "image/jpeg")
        return self._send(404, b"Not Found", "text/plain")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18767
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
