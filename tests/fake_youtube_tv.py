#!/usr/bin/env python3
"""Nachgebautes YouTube für die Fernseher-Anmeldung von Uzai (tests/net_youtube_tv.gd).

Verhält sich wie YouTube für die TV-App (SmartTube-Weg, inoffiziell):
- GET /tv: TV-Seite mit <script id="base-js" src="…/base.js">, darin clientId und Schlüssel
  (mit /__set?nobasejs=1 ohne Skript – dann muss Uzai die bekannte öffentliche Kennung nehmen).
- POST /o/oauth2/device/code (JSON): Code „ABCD-EFGH“, Abstand 1 s.
- POST /o/oauth2/token (JSON): Geräte-Code erst „authorization_pending“, dann „slow_down“, dann
  die Anmeldung (Zugang a1, Erneuerung r1). Erneuern mit r1 gibt a2, a3 …; mit /__set?revoked=1
  „invalid_grant“. Falsche Client-ID oder falscher Schlüssel: 401 invalid_client.
- POST /youtubei/v1/browse|next|player|account/accounts_list: nur mit gültigem Zugang und dem
  Fernseher-Client (TVHTML5), sonst 401 bzw. 400. Antworten aus tests/fixtures/youtube_tv/
  (Startseite FEwhat_to_watch, Abos FEsubscriptions, Kanalliste FEchannels).
  /__set?broken=1: Startseite in unbekannter Form; /__set?down=1: 500; /__set?stale=1: der
  nächste Aufruf mit dem aktuellen Zugang gibt 401 (abgelaufen, etwa nach dem Ruhezustand).
- GET /api/stats/playback: „gesehen“ (nur mit Zugang).
- POST /revoke: Abmelden.
Aufruf: python3 fake_youtube_tv.py <port>   (GET /__log zeigt alle Anfragen, POST /__reset leert)
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "youtube_tv")
CLIENT_ID = "111111111111-fakeclient.apps.googleusercontent.com"
CLIENT_SECRET = "fakesecret123"
FALLBACK_ID = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
FALLBACK_SECRET = "SboVhoG9s0rNafixCSGGKXAT"
LOG = []
STATE = {}


def reset():
    STATE.clear()
    STATE.update({"polls": 0, "access": set(), "n": 0, "revoked": False, "broken": False, "down": False,
                  "stale": False, "nobasejs": False})


reset()


def fix(name):
    with open(os.path.join(FIX, name), "rb") as f:
        return f.read()


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
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw.decode() or "{}")
        except ValueError:
            return {"_form": parse_qs(raw.decode())}

    def _log(self, body=None):
        e = {"m": self.command, "p": self.path, "auth": self.headers.get("Authorization", ""),
             "ua": self.headers.get("User-Agent", ""), "cname": self.headers.get("X-YouTube-Client-Name", "")}
        if isinstance(body, dict):
            e["body"] = body
        LOG.append(e)

    def _client_ok(self, b):
        return (b.get("client_id"), b.get("client_secret")) in [(CLIENT_ID, CLIENT_SECRET), (FALLBACK_ID, FALLBACK_SECRET)]

    def _bearer(self):
        a = self.headers.get("Authorization", "")
        return a[7:] if a.startswith("Bearer ") else ""

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/__log":
            return self._send(200, LOG)
        if u.path == "/__set":
            for k, v in parse_qs(u.query).items():
                STATE[k] = v[0] == "1"
            return self._send(200, {"ok": True})
        self._log()
        if u.path == "/tv":
            if STATE["nobasejs"]:
                return self._send(200, b"<html><head><title>YouTube</title></head></html>", "text/html")
            return self._send(200, fix("tv.html"), "text/html")
        if u.path.endswith("/base.js"):
            return self._send(200, fix("base.js"), "text/javascript")
        if u.path == "/api/stats/playback":
            if self._bearer() not in STATE["access"]:
                return self._send(401, {"error": "unauthorized"})
            return self._send(204)
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/__reset":
            LOG.clear()
            reset()
            return self._send(200, {"ok": True})
        b = self._body()
        self._log(b)
        if u.path == "/o/oauth2/device/code":
            if b.get("client_id") not in (CLIENT_ID, FALLBACK_ID):
                return self._send(401, {"error": "invalid_client"})
            return self._send(200, {"device_code": "dev1", "user_code": "ABCD-EFGH", "expires_in": 1800,
                                    "interval": 1, "verification_url": "https://www.google.com/device"})
        if u.path == "/o/oauth2/token":
            if not self._client_ok(b):
                return self._send(401, {"error": "invalid_client", "error_description": "Unauthorized"})
            if b.get("grant_type") == "http://oauth.net/grant_type/device/1.0":
                if b.get("code") != "dev1":
                    return self._send(400, {"error": "invalid_grant"})
                STATE["polls"] += 1
                if STATE["polls"] == 1:
                    return self._send(428, {"error": "authorization_pending"})
                if STATE["polls"] == 2:
                    return self._send(403, {"error": "slow_down"})
                STATE["access"].add("a1")
                STATE["revoked"] = False
                return self._send(200, {"access_token": "a1", "expires_in": 3600, "refresh_token": "r1",
                                        "scope": "https://www.googleapis.com/auth/youtube", "token_type": "Bearer"})
            if b.get("grant_type") == "refresh_token":
                if STATE["revoked"] or b.get("refresh_token") != "r1":
                    return self._send(400, {"error": "invalid_grant", "error_description": "Token has been expired or revoked."})
                STATE["n"] += 1
                tok = "a%d" % (STATE["n"] + 1)
                STATE["access"].add(tok)
                return self._send(200, {"access_token": tok, "expires_in": 3600, "token_type": "Bearer"})
            return self._send(400, {"error": "unsupported_grant_type"})
        if u.path == "/revoke":
            STATE["revoked"] = True
            STATE["access"].clear()
            return self._send(200, {})
        if u.path.startswith("/youtubei/v1/"):
            tok = self._bearer()
            if STATE["stale"] and tok in STATE["access"]:
                STATE["stale"] = False
                STATE["access"].discard(tok)
            if tok not in STATE["access"]:
                return self._send(401, {"error": {"code": 401, "status": "UNAUTHENTICATED"}})
            client = (b.get("context") or {}).get("client") or {}
            if client.get("clientName") != "TVHTML5" or not client.get("clientVersion"):
                return self._send(400, {"error": {"code": 400, "message": "Precondition check failed."}})
            if STATE["down"]:
                return self._send(500, {"error": {"code": 500}})
            ep = u.path[len("/youtubei/v1/"):]
            if ep == "browse":
                if STATE["broken"]:
                    return self._send(200, {"responseContext": {}, "contents": {"tvBrowseRendererV2": {"newThing": [{"id": 1}]}}})
                if b.get("browseId") == "FEwhat_to_watch":
                    return self._send(200, fix("home.json"))
                if b.get("browseId") == "FEsubscriptions":
                    return self._send(200, fix("subs.json"))
                if b.get("browseId") == "FEchannels":
                    return self._send(200, fix("channels.json"))
                c = b.get("continuation")
                if c == "HOMEPAGE2":
                    return self._send(200, fix("home_more.json"))
                if c == "HOMEPAGE3":
                    return self._send(200, fix("home_more2.json"))
                return self._send(400, {"error": {"code": 400}})
            if ep == "next":
                return self._send(200, fix("next.json"))
            if ep == "account/accounts_list":
                return self._send(200, fix("accounts.json"))
            if ep == "player":
                base = "http://%s" % self.headers.get("Host", "127.0.0.1")
                return self._send(200, fix("player.json").replace(b"{BASE}", base.encode()))
            return self._send(404, {"error": {"code": 404}})
        return self._send(404, {"error": "not found"})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18793
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
