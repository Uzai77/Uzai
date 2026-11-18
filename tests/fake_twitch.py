#!/usr/bin/env python3
"""Nachgebautes Twitch für den Bereich Streams von Uzai (tests/net_twitch.gd, Bildschirm-Proben).

Verhält sich wie Twitch für die TV-App (Geräte-Anmeldung, inoffiziell) und die offizielle
Schnittstelle (Helix):
- POST /oauth2/device (Formular client_id, scopes): Code „ABCDEFGH“, Abstand 1 s. Unbekannte
  Kennung: 400 {"status":400,"message":"invalid client"}.
- POST /oauth2/token, Geräte-Code: erst „authorization_pending“, dann „slow_down“, dann die
  Anmeldung (Zugang a1, Erneuerung r1, 4 h). Mit /__set?norefresh=1 wie die Twitch-Apps: ohne
  Erneuerung und ohne Ablauf. Erneuern: neuer Zugang a2, a3 … und neue Erneuerung r2, r3 …;
  mit /__set?revoked=1 „Invalid refresh token“.
- GET /oauth2/validate (Authorization: OAuth …): Konto „testkonto“ (4242) und die Kennung.
- POST /oauth2/revoke: Abmelden.
- POST /gql: ohne Anmeldung mit TV- oder Web-Kennung; mit /__set?tv_blocked=1 lehnt die TV-Kennung
  ohne Anmeldung ab (Fehler wie „failed integrity check“) – dann muss Uzai die Web-Kennung nehmen.
  Mit Anmeldung: Zugang muss gelten und zur Kennung passen, sonst 401. Antworten aus
  tests/fixtures/twitch/ je nach Abfrage (followedLiveUsers, streams mit/ohne Sprache, games,
  game, searchUsers, user(login), Konto). /__set?no_user_self=1: „user“ ohne Angabe gibt null
  (dann muss currentUser klappen); /__set?stale=1: der nächste Aufruf mit dem aktuellen Zugang
  gibt 401; /__set?down=1: 500; /__set?rich=1: längere Listen (für Bildschirm-Proben).
- GET /helix/users, /helix/streams/followed, /helix/streams, /helix/games/top,
  /helix/search/channels, /helix/search/categories: nur mit eigener Client-ID „ownclient123“ und
  Bearer-Zugang (/__set?helix_tv=1: auch mit der Anmeldung der TV-Kennung).
- GET /img/<name>-<B>x<H>.png: ein ruhiges Farbbild in genau der Größe (für Bildschirm-Proben).
Aufruf: python3 fake_twitch.py <port>   (GET /__log zeigt alle Anfragen, POST /__reset leert)
"""
import json
import os
import re
import struct
import sys
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "twitch")
TV = "ue6666qo983tsx6so1t0vnawi233wa"
WEB = "kimne78kx3ncx6brgo4mv6wki5h1ko"
OWN = "ownclient123"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18792
BASE = "http://127.0.0.1:%d" % PORT
LOG = []
STATE = {}
PNGS = {}


def reset():
    STATE.clear()
    STATE.update({"polls": 0, "tokens": {}, "refresh": {}, "n": 0, "revoked": False, "norefresh": False,
                  "tv_blocked": False, "no_user_self": False, "nofollows": False, "nopersist": False, "nolive": False, "follow_pages": False, "stale": False, "down": False, "rich": False, "helix_tv": False})


reset()


def fix(name):
    with open(os.path.join(FIX, name), encoding="utf-8") as f:
        return json.loads(f.read().replace("{BASE}", BASE))


def png(w, h, seed):
    """Ruhiges Farbfeld: oben links Licht, unten rechts tief (Farbton aus dem Namen)."""
    import colorsys
    hue = (sum(seed.encode()) * 37 % 360) / 360.0
    rows = []
    for y in range(h):
        row = bytearray([0])
        v = y / max(1, h - 1)
        for x in range(0, w):
            u = x / max(1, w - 1)
            k = min(1.0, u * 0.5 + v * 0.7)
            r, g, b = colorsys.hsv_to_rgb(hue, 0.35 + 0.2 * k, 0.75 - 0.55 * k)
            row += bytes((int(r * 255), int(g * 255), int(b * 255)))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")


def more(conn, n, prefix):
    """Längere Listen für Proben: die vorhandenen Einträge mit anderen Namen wiederholen."""
    edges = [e for e in conn["edges"] if e.get("node")]
    out = list(edges)
    names = ["Bergfunk", "Lofi Lounge", "Taktikbrett", "Hafenkran", "Sternwarte", "Kuppelbau", "Nachtfahrt", "Spielwiese"]
    i = 0
    while len(out) < n and edges:
        src = json.loads(json.dumps(edges[i % len(edges)]["node"]))
        nm = names[i % len(names)]
        lg = (prefix + nm).lower().replace(" ", "")
        if "broadcaster" in src and src["broadcaster"]:
            src["broadcaster"].update({"login": lg, "displayName": nm, "profileImageURL": BASE + "/img/avatar_%s-70x70.png" % lg})
            src["previewImageURL"] = BASE + "/img/live_user_%s-{width}x{height}.png" % lg
            src["viewersCount"] = max(50, int(src.get("viewersCount", 100) * 0.6))
            src["id"] = "x%d%s" % (i, prefix)
        out.append({"cursor": "m%d" % i, "node": src})
        i += 1
    conn["edges"] = out
    return conn


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, data=None, ctype="application/json"):
        body = b"" if data is None else (data if isinstance(data, bytes) else json.dumps(data).encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(n).decode() if n else ""
        if self.headers.get("Content-Type", "").startswith("application/json"):
            try:
                return json.loads(raw or "{}")
            except ValueError:
                return {}
        return {k: v[0] for k, v in parse_qs(raw).items()}

    def _log(self, body=None):
        e = {"m": self.command, "p": self.path, "auth": self.headers.get("Authorization", ""),
             "cid": self.headers.get("Client-Id", ""), "ua": self.headers.get("User-Agent", ""),
             "dev": self.headers.get("X-Device-Id", "")}
        if isinstance(body, dict):
            e["body"] = body
        LOG.append(e)

    def _token(self, prefix):
        a = self.headers.get("Authorization", "")
        if not a.startswith(prefix + " "):
            return None
        t = a[len(prefix) + 1:]
        return t if t in STATE["tokens"] else None

    def _new_tokens(self, client, refresh=True):
        STATE["n"] += 1
        a = "a%d" % STATE["n"]
        STATE["tokens"][a] = client
        out = {"access_token": a, "scope": ["chat:read", "user_read"], "token_type": "bearer"}
        if refresh and not STATE["norefresh"]:
            r = "r%d" % STATE["n"]
            STATE["refresh"][r] = client
            out["refresh_token"] = r
            out["expires_in"] = 14400
        return out

    # --- GET ------------------------------------------------------------------------------------
    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        if u.path == "/__log":
            return self._send(200, LOG)
        if u.path == "/__set":
            for k, v in q.items():
                STATE[k] = v == "1"
            return self._send(200, {"ok": True})
        if u.path.startswith("/img/"):
            m = re.search(r"-(\d+)x(\d+)\.png$", u.path)
            w, h = (int(m.group(1)), int(m.group(2))) if m else (64, 64)
            # Höchstens 480 Punkte breit gerechnet (reicht für ein Farbfeld, bleibt schnell).
            k = min(1.0, 480.0 / max(1, w))
            key = (int(w * k), int(h * k), u.path.split("/")[-1].split("-")[0])
            if key not in PNGS:
                PNGS[key] = png(max(1, key[0]), max(1, key[1]), key[2])
            return self._send(200, PNGS[key], "image/png")
        self._log()
        if u.path == "/oauth2/validate":
            t = self._token("OAuth")
            if t is None:
                return self._send(401, {"status": 401, "message": "invalid access token"})
            return self._send(200, {"client_id": STATE["tokens"][t], "login": "testkonto", "scopes": ["chat:read", "user_read"], "user_id": "4242", "expires_in": 14000})
        if u.path.startswith("/helix/"):
            t = self._token("Bearer")
            # Mit /__set?helix_tv=1 nimmt Helix auch die Anmeldung der TV-Kennung (Rückfall-Probe).
            ok_client = OWN if not STATE["helix_tv"] else self.headers.get("Client-Id", "")
            if t is None or self.headers.get("Client-Id", "") != ok_client or STATE["tokens"].get(t) != ok_client:
                return self._send(401, {"error": "Unauthorized", "status": 401, "message": "Invalid OAuth token"})
            p = u.path[len("/helix"):]
            if p == "/users":
                return self._send(200, {"data": [{"id": "4242", "login": "testkonto", "display_name": "Testkonto", "profile_image_url": BASE + "/img/avatar_testkonto-300x300.png"}]})
            if p == "/streams/followed":
                if q.get("user_id") != "4242":
                    return self._send(400, {"error": "Bad Request", "status": 400, "message": "user_id must match the token"})
                return self._send(200, fix("helix_followed.json"))
            if p == "/streams":
                return self._send(200, fix("helix_followed.json"))
            if p in ("/games/top", "/search/categories"):
                return self._send(200, {"data": [{"id": "27284", "name": "Retro", "box_art_url": BASE + "/img/box_27284-{width}x{height}.png"}]})
            if p == "/search/channels":
                return self._send(200, {"data": [{"broadcaster_login": "pixelbude", "display_name": "Pixelbude", "is_live": True, "thumbnail_url": BASE + "/img/avatar_pixelbude-300x300.png"}]})
            return self._send(404, {"error": "Not Found"})
        return self._send(404, {"error": "not found"})

    # --- POST -----------------------------------------------------------------------------------
    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/__reset":
            LOG.clear()
            reset()
            return self._send(200, {"ok": True})
        b = self._body()
        self._log(b)
        if u.path == "/oauth2/device":
            if b.get("client_id") not in (TV, OWN):
                return self._send(400, {"status": 400, "message": "invalid client"})
            STATE["polls"] = 0
            return self._send(200, {"device_code": "dev-" + b["client_id"], "expires_in": 1800, "interval": 1, "user_code": "ABCDEFGH",
                                    "verification_uri": "https://www.twitch.tv/activate?public=true&device-code=ABCDEFGH"})
        if u.path == "/oauth2/token":
            g = b.get("grant_type", "")
            if g == "urn:ietf:params:oauth:grant-type:device_code":
                if b.get("device_code") != "dev-" + str(b.get("client_id")):
                    return self._send(400, {"status": 400, "message": "invalid device code"})
                STATE["polls"] += 1
                if STATE["polls"] == 1:
                    return self._send(400, {"status": 400, "message": "authorization_pending"})
                if STATE["polls"] == 2:
                    return self._send(400, {"status": 400, "message": "slow_down"})
                return self._send(200, self._new_tokens(b["client_id"]))
            if g == "refresh_token":
                r = b.get("refresh_token", "")
                if STATE["revoked"] or r not in STATE["refresh"] or STATE["refresh"][r] != b.get("client_id"):
                    return self._send(400, {"status": 400, "message": "Invalid refresh token"})
                del STATE["refresh"][r]
                return self._send(200, self._new_tokens(b["client_id"]))
            return self._send(400, {"status": 400, "message": "unsupported grant type"})
        if u.path == "/oauth2/revoke":
            STATE["tokens"].pop(b.get("token", ""), None)
            return self._send(200, b"", "text/plain")
        if u.path == "/gql":
            return self._gql(b)
        return self._send(404, {"error": "not found"})

    def _gql(self, b):
        if STATE["down"]:
            return self._send(500, {"error": "Internal Server Error"})
        cid = self.headers.get("Client-Id", "")
        auth = self.headers.get("Authorization", "")
        query = str(b.get("query", ""))
        var = b.get("variables") or {}
        if auth:
            t = self._token("OAuth")
            if t is None or STATE["tokens"][t] != cid:
                return self._send(401, {"error": "Unauthorized", "status": 401, "message": "The \"Authorization\" token is invalid."})
            if STATE["stale"]:
                STATE["stale"] = False
                del STATE["tokens"][t]
                return self._send(401, {"error": "Unauthorized", "status": 401, "message": "The \"Authorization\" token is invalid."})
        else:
            if cid not in (TV, WEB):
                return self._send(400, {"error": "Bad Request", "status": 400, "message": "The \"Client-ID\" header is missing from the request."})
            if cid == TV and STATE["tv_blocked"]:
                return self._send(200, {"errors": [{"message": "failed integrity check", "path": ["streams"]}], "data": None})
        # Alle gefolgten Kanäle: follows (Abfragetext) oder gespeicherte Abfrage „ChannelFollows“.
        # /__set?nofollows=1: „service error“ am Feld; nopersist=1: Prüfsumme unbekannt;
        # follow_pages=1: zwei Seiten zu je 2.
        persisted = b.get("operationName") == "ChannelFollows"
        if "follows(first" in query or persisted:
            if not auth:
                return self._send(200, {"errors": [{"message": "unauthenticated"}], "data": {"currentUser": None}})
            if persisted and STATE["nopersist"]:
                return self._send(200, {"errors": [{"message": "PersistedQueryNotFound"}]})
            if STATE["nofollows"] and not persisted:
                return self._send(200, {"errors": [{"message": "service error", "path": ["currentUser", "follows"]}], "data": {"currentUser": {"id": "4242", "login": "testkonto", "displayName": "Testkonto", "follows": None}}})
            u = fix("followed.json")["data"]["user"]
            nodes = [e["node"] for e in u["followedLiveUsers"]["edges"] if e.get("node")]
            start = int(str(var.get("after") or var.get("cursor") or "0") or 0)
            size = 2 if STATE["follow_pages"] else 100
            page = nodes[start:start + size]
            edges = []
            for i, n in enumerate(page):
                node = {"id": n.get("id", ""), "login": n.get("login", ""), "displayName": n.get("displayName", "")} if persisted else n
                edges.append({"cursor": str(start + i + 1), "node": node})
            conn = {"edges": edges, "pageInfo": {"hasNextPage": start + size < len(nodes)}}
            me = {"id": u["id"], "login": u["login"], "displayName": u["displayName"], "follows": conn}
            return self._send(200, {"data": {"user" if persisted else "currentUser": me}})
        if "users(logins:" in query:
            u = fix("followed.json")["data"]["user"]
            want = [str(x).lower() for x in (var.get("logins") or [])]
            out = [e["node"] for e in u["followedLiveUsers"]["edges"] if e.get("node") and str(e["node"].get("login", "")).lower() in want]
            return self._send(200, {"data": {"users": out}})
        if "followedLiveUsers" in query and STATE["nolive"]:
            return self._send(200, {"errors": [{"message": "service error", "path": ["currentUser", "followedLiveUsers"]}], "data": {"currentUser": {"id": "4242", "login": "testkonto", "displayName": "Testkonto", "followedLiveUsers": None}}})
        if "followedLiveUsers" in query:
            # Wie Twitch: mehr als 30 auf einmal gibt nur „service error“ am Feld.
            if int(var.get("first", 0) or 0) > 30:
                return self._send(200, {"errors": [{"message": "service error", "path": ["currentUser", "followedLiveUsers"]}], "data": {"currentUser": {"id": "4242", "login": "testkonto", "displayName": "Testkonto", "followedLiveUsers": None}}})
            if not auth:
                return self._send(200, {"errors": [{"message": "unauthenticated"}], "data": {"user": None}})
            d = fix("followed.json")
            if query.lstrip().startswith("query($first: Int) { currentUser"):
                return self._send(200, {"data": {"currentUser": d["data"]["user"]}})
            if STATE["no_user_self"]:
                return self._send(200, {"errors": [{"message": "user requires an argument"}], "data": {"user": None}})
            return self._send(200, d)
        if query.startswith("query { currentUser {"):
            return self._send(200, {"data": {"currentUser": fix("me.json")["data"]["user"]}} if auth else {"data": {"currentUser": None}})
        if query.startswith("query { user {"):
            return self._send(200, fix("me.json") if auth else {"data": {"user": None}})
        if "searchUsers" in query:
            return self._send(200, fix("search.json"))
        if "game(id: $id, slug: $slug" in query:
            d = fix("game.json")
            if STATE["rich"]:
                more(d["data"]["game"]["streams"], 12, "k")
            return self._send(200, d)
        if "games(first" in query:
            d = fix("games.json")
            if STATE["rich"]:
                extra = [{"cursor": "g%d" % i, "node": {"id": "9%03d" % i, "displayName": n, "slug": n.lower(), "boxArtURL": BASE + "/img/box_9%03d-{width}x{height}.png" % i,
                          "viewersCount": 9000 - 700 * i, "broadcastersCount": 200 - 10 * i}} for i, n in enumerate(["Minecraft", "Music", "Elden Ring", "Chess", "Art", "Fortnite", "Valorant", "Software"])]
                d["data"]["games"]["edges"] = [e for e in d["data"]["games"]["edges"] if e.get("node") and e["node"].get("id")] + extra
            return self._send(200, d)
        if "user(login: $login)" in query:
            login = str(var.get("login", ""))
            if login == "retroraum":
                return self._send(200, fix("channel_offline.json"))
            if login == "pixelbude" or STATE["rich"]:
                d = fix("channel.json")
                if login != "pixelbude":
                    d["data"]["user"].update({"login": login, "displayName": login.capitalize()})
                return self._send(200, d)
            return self._send(200, {"data": {"user": None}})
        if "streams(first" in query and int(var.get("first", 0) or 0) > 30:
            return self._send(200, {"errors": [{"message": "argument 'first' value must be between 1 and 30."}], "data": None})
        if "streams(first" in query:
            d = fix("streams_de.json" if "broadcasterLanguages" in query else "streams_world.json")
            if STATE["rich"]:
                more(d["data"]["streams"], 10, "d" if "broadcasterLanguages" in query else "w")
            return self._send(200, d)
        return self._send(200, {"errors": [{"message": "unknown query"}], "data": None})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
