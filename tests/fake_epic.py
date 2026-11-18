#!/usr/bin/env python3
"""Nachgebaute Epic-Dienste für die Netz-Probe des Epic-Kontos (tests/net_epic.gd).

Uzai lenkt mit UZAI_EPIC_API=http://127.0.0.1:<port> alle drei Dienste hierher um:
- /account/account/api/oauth/token  (POST, Basic mit der Launcher-Client-ID; Code „good…“ → Anmeldung
  a1/r1, abgelaufener Code → 400 authorization_code_not_found; refresh_token r1 → a2/r2, r2 → a3/r3,
  „dead“ oder mit /__set?dead=1 → 400 invalid_refresh_token)
- /account/account/api/oauth/sessions/kill/<token>  (DELETE → 204)
- /library/library/api/public/items  (Bearer, zwei Seiten über nextCursor; mit Engine-Inhalt „ue“,
  Zusatzinhalt, Werkzeug, Spiel nur für Mac, Spiel ohne App-Namen im Katalog)
- /catalog/catalog/api/shared/namespace/<ns>/bulk/items?id=…  (Namespace „unbekannt“ → 404)
- /account/account/api/oauth/exchange  (GET, Bearer → Einmal-Code für den Spielstart, jedes Mal ein neuer;
  /__set?x=<Art> liefert böse Antworten: leer, space, quote, amp, nl, long, num, list, html, big, 500)
/__set?down=1 → alles 503, /__log zeigt alle Anfragen (ohne Körper), POST /__reset leert das Protokoll.
Aufruf: python3 fake_epic.py <port>
"""
import base64
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

CLIENT = "34a02cf8f4414e29b15921876da36f9a:daafbccc737745039dffe53d94fc76cf"
GOOD = "0123456789abcdef0123456789abcdef"
OLD = "fedcba9876543210fedcba9876543210"
LOG = []
STATE = {"down": False, "dead": False}
XMODE = {"x": "", "n": 0}


def exchange_reply():
    """Antwort von oauth/exchange je nach XMODE: (Status, Körper als Bytes, Inhaltstyp)."""
    XMODE["n"] += 1
    good = "%032x" % (0xC0DE0000 + XMODE["n"])
    bad = {
        "space": good[:16] + " " + good[17:],
        "quote": good[:16] + '" -x "' + good[22:],
        "amp": good[:16] + "&calc&" + good[22:],
        "nl": good + "\n",
        "long": "a" * 65,
        "num": 1234567890123456,
        "list": [good],
    }
    x = XMODE["x"]
    if x == "500":
        return 500, json.dumps({"errorCode": "errors.com.epicgames.common.server_error"}).encode(), "application/json"
    if x == "html":
        return 200, ("<html>" + good + "</html>").encode(), "text/html"
    if x == "big":
        return 200, json.dumps({"code": good, "pad": "x" * 10000}).encode(), "application/json"
    code = bad.get(x, good)
    return 200, json.dumps({"expiresInSeconds": 300, "code": code, "creatingClientId": "34a02cf8f4414e29b15921876da36f9a"}).encode(), "application/json"
TOKENS = {"r1": ("a2", "r2"), "r2": ("a3", "r3"), "r3": ("a4", "r4")}
VALID_ACCESS = {"a1", "a2", "a3", "a4"}


def img(t, u):
    return {"type": t, "url": "https://cdn1.epicgames.com/%s" % u, "width": 1, "height": 1, "md5": "x"}


CATALOG = {
    "ns-apex": {
        "item-apex": {"id": "item-apex", "namespace": "ns-apex", "title": "Apex Legends™",
                      "categories": [{"path": "games"}, {"path": "games/edition/base"}, {"path": "applications"}],
                      "releaseInfo": [{"id": "r", "appId": "Apex", "platform": ["Windows"]}],
                      "keyImages": [img("DieselGameBoxTall", "apex/tall.jpg"), img("DieselGameBox", "apex/wide.jpg"),
                                    img("Screenshot", "apex/shot.jpg")],
                      "description": "lang " * 50, "customAttributes": {"x": {"type": "STRING", "value": "y"}}},
        "item-apex-dlc": {"id": "item-apex-dlc", "namespace": "ns-apex", "title": "Apex Paket",
                          "categories": [{"path": "addons"}, {"path": "addons/durable"}],
                          "mainGameItem": {"id": "item-apex", "namespace": "ns-apex"},
                          "releaseInfo": [{"appId": "ApexDlc", "platform": ["Windows"]}], "keyImages": []},
    },
    "ns-kinglet": {
        "item-kinglet": {"id": "item-kinglet", "namespace": "ns-kinglet", "title": "Alan Wake 2",
                         "categories": [{"path": "games"}],
                         "releaseInfo": [{"appId": "Kinglet", "platform": ["Windows"]}],
                         "keyImages": [img("DieselGameBoxTall", "aw2/tall.jpg")]},
    },
    "ns-tool": {
        "item-tool": {"id": "item-tool", "namespace": "ns-tool", "title": "Ein Werkzeug",
                      "categories": [{"path": "applications"}, {"path": "software"}],
                      "releaseInfo": [{"appId": "Tool", "platform": ["Windows"]}], "keyImages": []},
    },
    "ns-mac": {
        "item-mac": {"id": "item-mac", "namespace": "ns-mac", "title": "Nur Mac",
                     "categories": [{"path": "games"}],
                     "releaseInfo": [{"appId": "MacOnly", "platform": ["Mac"]}], "keyImages": []},
    },
    "ns-noapp": {
        "item-noapp": {"id": "item-noapp", "namespace": "ns-noapp", "title": "Ohne App-Namen?",
                       "categories": [{"path": "games"}], "releaseInfo": [],
                       "keyImages": [img("OfferImageTall", "noapp/tall.jpg")]},
    },
}

PAGE1 = [
    {"namespace": "ns-apex", "catalogItemId": "item-apex", "appName": "Apex", "recordType": "APPLICATION", "sandboxType": "PUBLIC"},
    {"namespace": "ns-apex", "catalogItemId": "item-apex-dlc", "appName": "ApexDlc", "recordType": "APPLICATION"},
    {"namespace": "ue", "catalogItemId": "item-ue", "appName": "UE_5.3"},
    {"namespace": "ns-kinglet", "catalogItemId": "item-kinglet", "appName": "Kinglet"},
]
PAGE2 = [
    {"namespace": "ns-tool", "catalogItemId": "item-tool", "appName": "Tool"},
    {"namespace": "ns-mac", "catalogItemId": "item-mac", "appName": "MacOnly"},
    {"namespace": "ns-noapp", "catalogItemId": "item-noapp", "appName": "NoAppGame"},
    {"namespace": "unbekannt", "catalogItemId": "item-weg", "appName": "Weg"},
    {"namespace": "ns-kinglet", "catalogItemId": "", "appName": "Leer"},
]


def token(access, refresh):
    return {"access_token": access, "expires_in": 28800, "expires_at": "2026-10-17T20:00:00.000Z",
            "token_type": "bearer", "refresh_token": refresh, "refresh_expires": 1987200,
            "account_id": "acc1", "client_id": "34a02cf8f4414e29b15921876da36f9a", "displayName": "Spieler",
            "app": "launcher", "in_app_id": "acc1"}


def err(code, name, msg="x"):
    return code, {"errorCode": name, "errorMessage": msg, "numericErrorCode": 1, "originatingService": "fake"}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, data=None):
        body = b"" if data is None else json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _entry(self, form=None):
        u = urlparse(self.path)
        e = {"m": self.command, "p": u.path, "q": u.query, "auth": self.headers.get("Authorization", "")}
        if form is not None:
            e["grant"] = form.get("grant_type", [""])[0]
            e["token_type"] = form.get("token_type", [""])[0]
        LOG.append(e)
        return u

    def do_GET(self):
        if self.path.startswith("/__log"):
            return self._send(200, LOG)
        if self.path.startswith("/__set"):
            q = parse_qs(urlparse(self.path).query)
            for k in STATE:
                if k in q:
                    STATE[k] = q[k][0] == "1"
            if "x" in q:
                XMODE["x"] = q["x"][0]
            return self._send(200, STATE)
        u = self._entry()
        if STATE["down"]:
            return self._send(503, {"errorCode": "errors.com.epicgames.common.server_error"})
        bearer = self.headers.get("Authorization", "")
        if not bearer.startswith("Bearer ") or bearer[7:] not in VALID_ACCESS:
            return self._send(*err(401, "errors.com.epicgames.common.authentication.token_verification_failed"))
        q = parse_qs(u.query)
        if u.path == "/account/account/api/oauth/exchange":
            code, body, ctype = exchange_reply()
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if u.path == "/library/library/api/public/items":
            if q.get("cursor", [""])[0] == "c2":
                return self._send(200, {"responseMetadata": {"stateToken": "s"}, "records": PAGE2})
            return self._send(200, {"responseMetadata": {"nextCursor": "c2", "stateToken": "s"}, "records": PAGE1})
        parts = u.path.split("/")
        # /catalog/catalog/api/shared/namespace/<ns>/bulk/items
        if u.path.startswith("/catalog/catalog/api/shared/namespace/") and u.path.endswith("/bulk/items"):
            ns = parts[6]
            if ns not in CATALOG:
                return self._send(*err(404, "errors.com.epicgames.catalog.namespace_not_found"))
            out = {i: CATALOG[ns][i] for i in q.get("id", []) if i in CATALOG[ns]}
            return self._send(200, out)
        return self._send(404, {"errorCode": "errors.com.epicgames.common.not_found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(n).decode() if n else ""
        if self.path.startswith("/__reset"):
            LOG.clear()
            return self._send(200, {})
        form = parse_qs(raw)
        u = self._entry(form)
        if STATE["down"]:
            return self._send(503, {"errorCode": "errors.com.epicgames.common.server_error"})
        if u.path != "/account/account/api/oauth/token":
            return self._send(404, {})
        if self.headers.get("Authorization", "") != "Basic " + base64.b64encode(CLIENT.encode()).decode():
            return self._send(*err(401, "errors.com.epicgames.account.invalid_client_credentials"))
        grant = form.get("grant_type", [""])[0]
        if grant == "authorization_code":
            code = form.get("code", [""])[0]
            if code == GOOD:
                return self._send(200, token("a1", "r1"))
            return self._send(*err(400, "errors.com.epicgames.account.oauth.authorization_code_not_found"))
        if grant == "refresh_token":
            r = form.get("refresh_token", [""])[0]
            if STATE["dead"] or r not in TOKENS:
                return self._send(*err(400, "errors.com.epicgames.account.auth_token.invalid_refresh_token"))
            a, nr = TOKENS[r]
            return self._send(200, token(a, nr))
        return self._send(*err(400, "errors.com.epicgames.common.oauth.unsupported_grant_type"))

    def do_DELETE(self):
        u = self._entry()
        if u.path.startswith("/account/account/api/oauth/sessions/kill/"):
            return self._send(204)
        return self._send(404, {})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
