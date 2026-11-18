#!/usr/bin/env python3
"""Nachgebaute Nuvio-API (api.nuvio.tv, Supabase-artig) für tests/net_nuvio.gd.

- /auth/v1/token?grant_type=password|refresh_token, /auth/v1/logout
- /rest/v1/rpc/start_device_login_session, poll_tv_login_session (zweimal „pending“, dann
  „approved“), /functions/v1/tv-logins-exchange
- /rest/v1/rpc/get_sync_owner, sync_pull_profiles, sync_pull_library, sync_pull_watch_progress,
  sync_pull_watched_items, sync_pull_home_catalog_settings, sync_pull_collections,
  sync_pull_profile_settings_blob und alle sync_push_* / sync_delete_* (werden mitgeschrieben)
- /rest/v1/addons?…, /rest/v1/plugins?… (Tabellen)
- /addon/a1/ und /addon/a2/: zwei Stremio-Addons mit Katalogen; /repo/: Plugin-Repository
Jede API-Anfrage muss den öffentlichen Schlüssel (apikey) tragen. GET /__log, /__clear.
Aufruf: python3 fake_nuvio.py <port>
"""
import base64
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18767
BASE = "http://127.0.0.1:%d" % PORT
KEY = "sb_publishable_1Clq8rlTVACkdcZuqr6_AD__xUUC_EN"
LOG = []
STATE = {"polls": 0, "refreshes": 0}
# Änderungs-Ereignisse je Art (lib, progress, watched); Cursor beim ersten Abgleich: 100.
EVENTS = {"lib": [], "progress": [], "watched": []}
OWNER = "owner-uuid-1"


def jwt(sub):
    def b(d):
        return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")
    return "%s.%s.sig" % (b({"alg": "HS256"}), b({"sub": sub, "role": "authenticated"}))


def session(tag):
    return {"access_token": jwt("user-uuid-1") + tag, "token_type": "bearer", "expires_in": 3600,
            "refresh_token": "refresh-" + tag, "user": {"id": "user-uuid-1", "email": "lea@example.com"}}


def meta(i, kind="movie"):
    return {"id": "tt%03d" % i, "type": kind, "name": "Titel %d" % i, "poster": BASE + "/img/%d.jpg" % i,
            "background": BASE + "/img/b%d.jpg" % i, "description": "Text %d" % i, "releaseInfo": "20%02d" % i}


ADDONS = {
    "a1": {"id": "org.test.eins", "version": "1.0.0", "name": "Eins", "resources": ["catalog", "meta"],
           "types": ["movie", "series"], "idPrefixes": ["tt"],
           "catalogs": [{"type": "movie", "id": "top", "name": "Top Filme"},
                        {"type": "series", "id": "top", "name": "Top Serien"},
                        {"type": "movie", "id": "neu", "name": "Neu"}]},
    "a2": {"id": "org.test.zwei", "version": "2.0.0", "name": "Zwei", "resources": ["catalog"],
           "types": ["movie"], "catalogs": [{"type": "movie", "id": "beliebt", "name": "Beliebt"}]},
}

PROFILES = [
    {"id": "p1", "user_id": OWNER, "profile_index": 1, "name": "Lea", "avatar_color_hex": "#1E88E5",
     "uses_primary_addons": False, "uses_primary_plugins": False},
    {"id": "p2", "user_id": OWNER, "profile_index": 2, "name": "Kinder", "avatar_color_hex": "#FF5722",
     "uses_primary_addons": True, "uses_primary_plugins": True},
]

ADDON_ROWS = [
    {"id": "x2", "user_id": OWNER, "profile_id": 1, "url": BASE + "/addon/a2/manifest.json", "name": "Zwei", "enabled": True, "sort_order": 1},
    {"id": "x1", "user_id": OWNER, "profile_id": 1, "url": BASE + "/addon/a1", "name": "Eins", "enabled": True, "sort_order": 0},
]

PLUGIN_ROWS = [
    {"user_id": OWNER, "profile_id": 1, "url": BASE + "/repo/manifest.json", "name": "Repo", "enabled": True, "sort_order": 0, "repo_type": "NUVIO_JS"},
    {"user_id": OWNER, "profile_id": 1, "url": BASE + "/cs/repo.json", "name": "CS", "enabled": True, "sort_order": 1, "repo_type": "CLOUDSTREAM"},
]

LIBRARY = [
    {"content_id": "tt001", "content_type": "movie", "name": "Titel 1", "poster": BASE + "/img/1.jpg", "poster_shape": "POSTER",
     "background": None, "description": "Text 1", "release_info": "2001", "imdb_rating": 7.5, "genres": ["Drama"],
     "addon_base_url": BASE + "/addon/a1", "added_at": 1700000000000},
    {"content_id": "tt050", "content_type": "series", "name": "Serie 50", "poster": BASE + "/img/50.jpg", "poster_shape": "POSTER",
     "background": None, "description": None, "release_info": "2010-2014", "imdb_rating": None, "genres": [],
     "addon_base_url": None, "added_at": 1700000500000},
]

PROGRESS = [
    {"content_id": "tt002", "content_type": "movie", "video_id": "tt002", "season": None, "episode": None,
     "progress_key": "tt002", "position": 1800000, "duration": 6000000, "last_watched": 1800000000000},
    {"content_id": "tt050", "content_type": "series", "video_id": "tt050:1:2", "season": 1, "episode": 2,
     "progress_key": "tt050_s1e2", "position": 600000, "duration": 2400000, "last_watched": 1800000100000},
]

WATCHED = [
    {"content_id": "tt050", "content_type": "series", "title": "S1E1", "season": 1, "episode": 1, "watched_at": 1799999000000},
    {"content_id": "tt003", "content_type": "movie", "title": "Titel 3", "season": None, "episode": None, "watched_at": 1799990000000},
]

HOME = {"hide_unreleased_content": False, "items": [
    {"addon_id": "org.test.zwei", "type": "movie", "catalog_id": "beliebt", "enabled": True, "order": 0, "custom_title": "Meine Liebsten", "is_collection": False, "collection_id": ""},
    {"addon_id": "", "type": "", "catalog_id": "", "enabled": True, "order": 1, "custom_title": "", "is_collection": True, "collection_id": "c1"},
    {"addon_id": "org.test.eins", "type": "series", "catalog_id": "top", "enabled": True, "order": 2, "custom_title": "", "is_collection": False, "collection_id": ""},
    {"addon_id": "org.test.eins", "type": "movie", "catalog_id": "top", "enabled": False, "order": 3, "custom_title": "", "is_collection": False, "collection_id": ""},
]}

COLLECTIONS = [{"id": "c1", "title": "Wochenende", "pinToTop": False, "viewMode": "ROWS", "folders": [
    {"id": "f1", "title": "Spannung", "tileShape": "POSTER", "catalogSources": [{"addonId": "org.test.eins", "type": "movie", "catalogId": "neu"}]},
]}]

SETTINGS = {"version": 1, "features": {"layout_settings": {
    "selected_layout": {"type": "string", "value": "MODERN"},
    "hero_section_enabled": {"type": "boolean", "value": True},
    "continue_watching_enabled": {"type": "boolean", "value": True},
    "hero_catalog_keys": {"type": "string_set", "value": ["org.test.eins_series_top"]},
}}}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, data=None, raw=None, ctype="application/json"):
        body = raw if raw is not None else (b"" if data is None else json.dumps(data).encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw or b"{}")
        except Exception:
            return {"_raw": raw.decode("utf-8", "replace")}

    def _api_ok(self, needs_auth=True):
        if self.headers.get("apikey") != KEY:
            self._send(401, {"message": "No API key found in request"})
            return False
        if needs_auth and not (self.headers.get("Authorization") or "").startswith("Bearer "):
            self._send(401, {"message": "JWT missing"})
            return False
        return True

    def do_GET(self):
        u = urlparse(self.path)
        p = u.path
        q = parse_qs(u.query)
        if p == "/__log":
            return self._send(200, LOG)
        if p == "/__event":
            kind = (q.get("kind") or ["lib"])[0]
            ev = json.loads((q.get("json") or ["{}"])[0])
            ev["event_id"] = 100 + len(EVENTS[kind]) + 1
            EVENTS[kind].append(ev)
            return self._send(200, ev)
        if p == "/__stoer":
            # Einen Aufruf scheitern lassen (rpc=<Name>&code=503); ohne rpc: Störung aufheben.
            STATE["stoer"] = {}
            if q.get("rpc"):
                STATE["stoer"][q["rpc"][0]] = int((q.get("code") or ["503"])[0])
            return self._send(200, [])
        if p == "/__clear":
            LOG.clear()
            STATE["polls"] = 0
            return self._send(200, [])
        LOG.append({"m": "GET", "p": p, "q": u.query, "auth": self.headers.get("Authorization") or ""})
        if p.startswith("/addon/"):
            parts = p.split("/")
            a = ADDONS.get(parts[2])
            if a is None:
                return self._send(404, {})
            rest = "/".join(parts[3:])
            if rest in ("", "manifest.json"):
                return self._send(200, a)
            if rest.startswith("catalog/"):
                _, kind, cat = rest.split("/")[:3]
                cat = cat.replace(".json", "")
                start = {"top": 1, "neu": 20, "beliebt": 30}.get(cat, 40)
                return self._send(200, {"metas": [meta(start + i, kind) for i in range(5)]})
            if rest.startswith("meta/"):
                _, kind, mid = rest.split("/")[:3]
                mid = mid.replace(".json", "")
                m = meta(int(mid[2:]), kind)
                if kind == "series":
                    m["videos"] = [{"id": "%s:1:%d" % (mid, e), "season": 1, "episode": e, "title": "Folge %d" % e, "released": "2010-01-0%dT00:00:00Z" % e} for e in (1, 2, 3)]
                return self._send(200, {"meta": m})
            return self._send(404, {})
        if p == "/repo/manifest.json":
            return self._send(200, {"name": "Test-Repo", "version": "1", "scrapers": [
                {"id": "probe", "name": "Probe", "filename": "probe.js", "supportedTypes": ["movie", "tv"], "enabled": True}]})
        if p == "/repo/probe.js":
            return self._send(200, raw=b"function getStreams(){return Promise.resolve([])}\nmodule.exports={getStreams};", ctype="application/javascript")
        if p in ("/rest/v1/addons", "/rest/v1/plugins"):
            if not self._api_ok():
                return
            uid = (q.get("user_id") or [""])[0].replace("eq.", "")
            pid = int((q.get("profile_id") or ["eq.1"])[0].replace("eq.", ""))
            rows = ADDON_ROWS if p.endswith("addons") else PLUGIN_ROWS
            return self._send(200, [r for r in rows if r["user_id"] == uid and r["profile_id"] == pid])
        return self._send(404, {"message": "nicht da"})

    def do_POST(self):
        u = urlparse(self.path)
        p = u.path
        q = parse_qs(u.query)
        body = self._body()
        LOG.append({"m": "POST", "p": p, "q": u.query, "body": body, "auth": self.headers.get("Authorization") or ""})
        if p == "/auth/v1/token":
            if not self._api_ok(False):
                return
            g = (q.get("grant_type") or [""])[0]
            if g == "password":
                if body.get("email") == "lea@example.com" and body.get("password") == "geheim":
                    return self._send(200, session("pw"))
                return self._send(400, {"error": "invalid_grant", "error_description": "Invalid login credentials"})
            if g == "refresh_token":
                STATE["refreshes"] += 1
                if str(body.get("refresh_token", "")).startswith("refresh-"):
                    return self._send(200, session("r%d" % STATE["refreshes"]))
                return self._send(400, {"error": "invalid_grant"})
        if p == "/auth/v1/logout":
            return self._send(204)
        if p == "/functions/v1/tv-logins-exchange":
            if not self._api_ok(False):
                return
            if body.get("code") == "DEV-123" and body.get("device_nonce"):
                return self._send(200, session("qr"))
            return self._send(400, {"message": "bad code"})
        if p.startswith("/rest/v1/rpc/"):
            name = p.split("/")[-1]
            anon = name in ("start_device_login_session", "poll_tv_login_session", "start_tv_login_session")
            if not self._api_ok(not anon):
                return
            if name in STATE.get("stoer", {}):
                return self._send(STATE["stoer"][name], {"message": "gestört"})
            if name == "start_device_login_session":
                return self._send(200, [{"device_code": "DEV-123", "user_code": "ABCD-EFGH", "verification_uri": "https://nuvio.tv/link",
                                         "verification_uri_complete": "https://nuvio.tv/link?code=ABCD-EFGH", "expires_at": "2099-01-01T00:00:00Z",
                                         "poll_interval_seconds": 2}])
            if name == "poll_tv_login_session":
                STATE["polls"] += 1
                st = "approved" if STATE["polls"] >= 3 else "pending"
                return self._send(200, [{"status": st, "expires_at": "2099-01-01T00:00:00Z", "poll_interval_seconds": 2}])
            if name == "get_sync_owner":
                return self._send(200, OWNER)
            if name == "sync_pull_profiles":
                return self._send(200, PROFILES)
            if name in ("sync_get_library_delta_cursor", "sync_get_watch_progress_delta_cursor", "sync_get_watched_items_delta_cursor"):
                return self._send(200, 100)
            delta = {"sync_pull_library_delta": "lib", "sync_pull_watch_progress_delta": "progress", "sync_pull_watched_items_delta": "watched"}
            if name in delta:
                since = int(body.get("p_since_event_id", 0))
                return self._send(200, [e for e in EVENTS[delta[name]] if e["event_id"] > since])
            if name == "sync_pull_library":
                off = int(body.get("p_offset", 0))
                return self._send(200, LIBRARY[off:off + int(body.get("p_limit", 500))])
            if name == "sync_pull_watch_progress":
                return self._send(200, PROGRESS)
            if name == "sync_pull_watched_items":
                return self._send(200, WATCHED)
            if name == "sync_pull_home_catalog_settings":
                if body.get("p_platform") != "home_catalog_shared":
                    return self._send(200, [])
                return self._send(200, [{"profile_id": 1, "platform": "home_catalog_shared", "settings_json": HOME}])
            if name == "sync_pull_collections":
                return self._send(200, [{"profile_id": 1, "collections_json": COLLECTIONS}])
            if name == "sync_pull_profile_settings_blob":
                return self._send(200, [{"profile_id": 1, "settings_json": SETTINGS}])
            if name.startswith("sync_push_") or name.startswith("sync_delete_"):
                return self._send(204)
            return self._send(404, {"code": "PGRST202", "message": "Could not find the function public.%s" % name})
        return self._send(404, {})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
