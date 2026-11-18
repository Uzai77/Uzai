#!/usr/bin/env python3
"""Nachgebaute Filme-Quellen für die Netz-Probe (tests/net_medienquellen.gd).

- /plextv/api/v2/…   plex.tv: PIN (erst offen, dann bestätigt), Benutzer, Server-Liste
- /                  Plex Media Server: /identity (ohne Schlüssel), Bibliotheken, Weiterschauen,
                     Sammlungen, Details, Folgen, Suche (eine Antwort zu groß), Bilder,
                     /:/timeline und /:/scrobble; eine Bibliothek leitet auf einen fremden Host um
- /jf/…              Jellyfin: Server-Info, Quick Connect (erst offen, dann bestätigt), Anmeldung
                     mit Passwort, Views, Neu, Weiterschauen, Als Nächstes, Sammlungen, Details,
                     /Sessions/Playing…, /Sessions/Logout
- UDP <port>         Antwort auf „who is JellyfinServer?“: eine echte, eine auf ein anderes Gerät,
                     eine zu große
- /link/…            link.stremio.com: Code, dann Anmelde-Schlüssel
- /stremio/…         api.strem.io: getUser, addonCollectionGet, datastoreGet/Put, logout
Alles mit Schlüssel prüft den Schlüssel (sonst 401). GET /__log zeigt alle Anfragen mit Kopfzeilen.
Aufruf: python3 fake_medienquellen.py <port>
"""
import json
import socket
import struct
import sys
import threading
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18791
BASE = "http://127.0.0.1:%d" % PORT
LOG = []
STATE = {"pin_polls": 0, "qc_polls": 0, "link_polls": 0}

PLEX_TOKEN = "plexAuthToken123"
SERVER_ID = "abcdef0123456789"
JF_ID = "6c4b7f1e0f2a4b4e8b0a7f6c2d1e3a5b"
JF_USER = "4f1c2a3b5d6e7f8091a2b3c4d5e6f708"
JF_TOKEN = "a1b2c3d4e5f60718293a4b5c6d7e8f90"
ST_KEY = "stremio_auth_key_0123456789"


def png():
    raw = b"".join(b"\x00" + b"\x80\x40\x20" * 4 for _ in range(4))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


def movie(rk, title, rating, lib="1", extra=None):
    m = {"ratingKey": str(rk), "key": "/library/metadata/%d" % rk, "type": "movie", "title": title, "contentRating": rating, "year": 2020,
         "summary": "Beschreibung %s" % title, "thumb": "/library/metadata/%d/thumb/1" % rk, "art": "/library/metadata/%d/art/1" % rk,
         "duration": 6000000, "librarySectionID": lib, "Genre": [{"tag": "Drama"}], "addedAt": 1700000000 + rk}
    if extra:
        m.update(extra)
    return m


SHOW = {"ratingKey": "200", "type": "show", "title": "Kanalarbeit", "contentRating": "de/12", "thumb": "/library/metadata/200/thumb/1", "librarySectionID": "1"}
EPISODES = [{"ratingKey": str(300 + i), "type": "episode", "title": "Folge %d" % i, "parentIndex": 1, "index": i, "grandparentRatingKey": "200",
             "grandparentTitle": "Kanalarbeit", "duration": 2700000, "viewOffset": 600000 if i == 2 else 0, "lastViewedAt": 1760000000 if i == 2 else 0,
             "viewCount": 1 if i == 1 else 0, "Media": [{"id": 30 + i, "Part": [{"id": 3000 + i, "key": "/library/parts/%d/1/file.mkv" % (3000 + i), "size": 1000}]}]}
            for i in range(1, 4)]
MOVIE_FULL = movie(123, "Matrix", "de/16", extra={"viewOffset": 1200000, "lastViewedAt": 1760000500,
    "Role": [{"tag": "Keanu Reeves", "role": "Neo"}], "Guid": [{"id": "imdb://tt0133093"}],
    "Media": [{"id": 1, "videoResolution": "1080", "videoCodec": "hevc", "container": "mkv",
               "Part": [{"id": 11, "key": "/library/parts/11/1700000000/file.mkv", "size": 4000000000, "file": "/m/Matrix.mkv",
                         "Stream": [{"streamType": 3, "key": "/library/streams/77", "languageCode": "ger", "displayTitle": "Deutsch"}]}]}]})


def jf_item(i, name, typ="Movie", rating="FSK-12"):
    iid = ("%02x" % i) * 16
    return {"Id": iid, "Name": name, "Type": typ, "OfficialRating": rating, "ProductionYear": 2021, "ImageTags": {"Primary": "tag%d" % i},
            "BackdropImageTags": ["bd%d" % i], "RunTimeTicks": 60000000000, "ParentId": "f1",
            "UserData": {"PlaybackPositionTicks": 9000000000 if i == 1 else 0, "Played": False, "LastPlayedDate": "2026-10-20T19:30:00Z"},
            "MediaSources": [{"Id": iid, "Protocol": "File", "Container": "mkv", "Size": 123456, "Path": "/m/%s.mkv" % name,
                              "MediaStreams": [{"Type": "Video", "Codec": "h264", "Height": 1080},
                                               {"Type": "Subtitle", "Codec": "subrip", "Language": "ger", "IsExternal": True, "Index": 2}]}]}


JF_ITEMS = [jf_item(1, "Nachtfalter"), jf_item(2, "Salz", rating="FSK-0"), jf_item(3, "Die Werft", "Series")]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj=None, raw=None, ctype="application/json", headers=None):
        body = raw if raw is not None else (json.dumps(obj).encode() if obj is not None else b"")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n).decode("utf-8", "replace") if n else ""

    def _log(self, method, body=""):
        LOG.append({"m": method, "p": self.path, "h": {k.lower(): v for k, v in self.headers.items()}, "b": body})

    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")

    def do_DELETE(self):
        self._route("DELETE")

    def _route(self, method):
        body = self._body() if method in ("POST", "DELETE") else ""
        u = urlparse(self.path)
        p = u.path
        q = parse_qs(u.query)
        if p == "/__log":
            return self._send(200, LOG)
        if p == "/__clear":
            LOG.clear()
            return self._send(200, {})
        self._log(method, body)
        if p.startswith("/plextv/"):
            return self._plextv(method, p[7:], q)
        if p.startswith("/jf/"):
            return self._jf(method, p[3:], q, body)
        if p.startswith("/link/"):
            return self._link(p[5:], q)
        if p.startswith("/stremio/"):
            return self._stremio(p[8:], body)
        return self._pms(method, p, q)

    # --- plex.tv -------------------------------------------------------------------------
    def _plextv(self, method, p, q):
        if not self.headers.get("X-Plex-Client-Identifier") or self.headers.get("X-Plex-Product") != "Uzai":
            return self._send(400, {"errors": [{"message": "client"}]})
        if p == "/api/v2/pins" and method == "POST":
            return self._send(201, {"id": 4812, "code": "K7QZ", "product": "Uzai", "trusted": False, "expiresIn": 900, "authToken": None})
        if p == "/api/v2/pins/4812":
            STATE["pin_polls"] += 1
            tok = PLEX_TOKEN if STATE["pin_polls"] >= 2 else None
            return self._send(200, {"id": 4812, "code": "K7QZ", "authToken": tok, "expiresIn": 800})
        if self.headers.get("X-Plex-Token") != PLEX_TOKEN:
            return self._send(401, {"errors": []})
        if p == "/api/v2/user":
            return self._send(200, {"id": 1, "username": "robin", "title": "Robin"})
        if p == "/api/v2/resources":
            return self._send(200, [
                {"name": "Testserver", "provides": "server", "owned": True, "clientIdentifier": SERVER_ID, "accessToken": PLEX_TOKEN, "presence": True,
                 "connections": [{"protocol": "http", "address": "127.0.0.1", "port": PORT, "uri": BASE, "local": True, "relay": False}]},
                {"name": "Telefon", "provides": "player", "clientIdentifier": "phone000000000"},
            ])
        return self._send(404, {})

    # --- Plex Media Server ----------------------------------------------------------------
    def _pms(self, method, p, q):
        if p == "/identity":
            return self._send(200, {"MediaContainer": {"size": 0, "machineIdentifier": SERVER_ID, "version": "1.41.0"}})
        if self.headers.get("X-Plex-Token") != PLEX_TOKEN:
            return self._send(401, {})
        mc = lambda md: self._send(200, {"MediaContainer": md})
        if p == "/library/sections":
            return mc({"Directory": [{"key": "1", "type": "movie", "title": "Filme"}, {"key": "2", "type": "movie", "title": "Umgeleitet"}]})
        if p == "/library/sections/1/all":
            if q.get("type", [""])[0] == "2":
                return mc({"Metadata": [SHOW]})
            return mc({"Metadata": [movie(123, "Matrix", "de/16"), movie(124, "Pinguin-Post", "de/0")]})
        if p == "/library/sections/2/all":
            return self._send(302, {}, headers={"Location": "http://evil.invalid/steal"})
        if p.endswith("/collections"):
            return mc({"Metadata": [{"ratingKey": "901", "type": "collection", "title": "Krimis", "childCount": 2}]})
        if p == "/hubs/continueWatching/items":
            return mc({"Metadata": [EPISODES[1], movie(123, "Matrix", "de/16", extra={"viewOffset": 1200000, "lastViewedAt": 1760000500})]})
        if p == "/library/metadata/123":
            return mc({"Metadata": [MOVIE_FULL]})
        if p == "/library/metadata/200":
            return mc({"Metadata": [SHOW]})
        if p == "/library/metadata/200/allLeaves":
            return mc({"Metadata": EPISODES})
        if p == "/hubs/search":
            if q.get("query", [""])[0] == "gross":
                return self._send(200, raw=b'{"MediaContainer":{"Metadata":[' + b'{"x":"' + b"a" * (5 * 1024 * 1024) + b'"}]}}')
            return mc({"Hub": [{"type": "movie", "Metadata": [movie(123, "Matrix", "de/16")]}]})
        if p == "/photo/:/transcode":
            return self._send(200, raw=png(), ctype="image/png")
        if p in ("/:/timeline", "/:/scrobble", "/:/unscrobble"):
            return self._send(200, {})
        return self._send(404, {})

    # --- Jellyfin --------------------------------------------------------------------------
    def _jf(self, method, p, q, body):
        auth = self.headers.get("Authorization") or ""
        if p == "/System/Info/Public":
            return self._send(200, {"ServerName": "Keller", "Version": "10.10.7", "ProductName": "Jellyfin Server", "Id": JF_ID, "LocalAddress": BASE + "/jf"})
        if 'DeviceId="' not in auth or 'Client="Uzai"' not in auth:
            return self._send(400, {})
        if p == "/QuickConnect/Enabled":
            return self._send(200, True)
        if p == "/QuickConnect/Initiate" and method == "POST":
            return self._send(200, {"Secret": "0f1e2d3c4b5a69788796a5b4c3d2e1f0", "Code": "482913", "Authenticated": False})
        if p == "/QuickConnect/Connect":
            STATE["qc_polls"] += 1
            return self._send(200, {"Secret": "0f1e2d3c4b5a69788796a5b4c3d2e1f0", "Code": "482913", "Authenticated": STATE["qc_polls"] >= 2})
        if p in ("/Users/AuthenticateWithQuickConnect", "/Users/AuthenticateByName") and method == "POST":
            data = json.loads(body or "{}")
            if p.endswith("ByName") and data.get("Pw") != "richtig":
                return self._send(401, {})
            return self._send(200, {"User": {"Name": "Robin", "Id": JF_USER}, "AccessToken": JF_TOKEN, "ServerId": JF_ID})
        if 'Token="%s"' % JF_TOKEN not in auth:
            return self._send(401, {})
        if p == "/Users/%s/Views" % JF_USER:
            return self._send(200, {"Items": [{"Id": "f1", "Name": "Filme", "CollectionType": "movies"}, {"Id": "f9", "Name": "Musik", "CollectionType": "music"}]})
        if p == "/Users/%s/Items/Latest" % JF_USER:
            return self._send(200, JF_ITEMS)
        if p == "/Users/%s/Items/Resume" % JF_USER:
            return self._send(200, {"Items": [JF_ITEMS[0]]})
        if p == "/Shows/NextUp":
            return self._send(200, {"Items": []})
        if p == "/Users/%s/Items" % JF_USER:
            if q.get("IncludeItemTypes", [""])[0] == "BoxSet":
                return self._send(200, {"Items": [{"Id": "c1", "Name": "Krimis", "Type": "BoxSet", "ChildCount": 2}]})
            return self._send(200, {"Items": JF_ITEMS, "TotalRecordCount": 3})
        if p.startswith("/Users/%s/Items/" % JF_USER):
            iid = p.rsplit("/", 1)[1]
            for it in JF_ITEMS:
                if it["Id"] == iid:
                    return self._send(200, it)
            return self._send(404, {})
        if p.startswith("/Sessions/") or p.startswith("/Users/%s/PlayedItems/" % JF_USER):
            return self._send(204, raw=b"")
        return self._send(404, {})

    # --- Stremio -------------------------------------------------------------------------------
    def _link(self, p, q):
        if p == "/create":
            return self._send(200, {"result": {"code": "XU4K2", "link": "https://link.stremio.com?code=XU4K2", "qrcode": ""}})
        if p == "/read":
            STATE["link_polls"] += 1
            if STATE["link_polls"] < 2:
                return self._send(200, {"error": {"message": "Not authorized yet", "code": 1}})
            return self._send(200, {"result": {"authKey": ST_KEY}})
        return self._send(404, {})

    def _stremio(self, p, body):
        data = json.loads(body or "{}")
        if data.get("authKey") != ST_KEY:
            return self._send(200, {"error": {"message": "Session not found", "code": 1}})
        if p == "/getUser":
            return self._send(200, {"result": {"email": "robin@example.invalid"}})
        if p == "/addonCollectionGet":
            return self._send(200, {"result": {"addons": [
                {"transportUrl": "https://addon.example/abc/manifest.json", "manifest": {"name": "Mein Addon"}},
                {"transportUrl": "http://127.0.0.1:11470/local-addon/manifest.json", "manifest": {"name": "Local"}}]}})
        if p == "/datastoreGet":
            return self._send(200, {"result": [
                {"_id": "tt0133093", "name": "Matrix", "type": "movie", "removed": False, "temp": False, "_mtime": "2026-10-20T10:00:00.000Z",
                 "state": {"timeOffset": 1800000, "duration": 8160000, "video_id": "tt0133093", "lastWatched": "2026-10-20T21:00:00.000Z", "overallTimeWatched": 5}},
                {"_id": "tt0903747", "name": "Breaking Bad", "type": "series", "removed": False, "temp": False, "_mtime": "2026-10-21T10:00:00.000Z", "state": {}}]})
        if p in ("/datastorePut", "/logout"):
            return self._send(200, {"result": {"success": True}})
        return self._send(404, {})


def udp():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", PORT))
    while True:
        data, addr = s.recvfrom(2048)
        if data.strip() != b"who is JellyfinServer?":
            continue
        s.sendto(json.dumps({"Address": BASE + "/jf", "Id": JF_ID, "Name": "Keller", "EndpointAddress": None}).encode(), addr)
        s.sendto(json.dumps({"Address": "http://10.0.0.99:8096", "Id": "bb" * 16, "Name": "Fremd"}).encode(), addr)
        s.sendto(json.dumps({"Address": BASE + "/jf", "Id": "cc" * 16, "Name": "x" * 3000}).encode(), addr)


threading.Thread(target=udp, daemon=True).start()
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
