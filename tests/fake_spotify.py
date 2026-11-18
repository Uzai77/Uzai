#!/usr/bin/env python3
"""Nachgebaute Spotify-Web-API für die Netz-Probe von Uzai (tests/net_musik.gd).

Verhält sich wie eine eigene App im „Development Mode“ nach den Änderungen 2026:
- Playlists: Anzahl unter „items“, Einträge mit „item“ (und „track“ als Altlast),
  GET /playlists/{id}/tracks ist weg (403), fremde Playlists geben keine Titel (403).
- Suche: limit über 10 ist ein Fehler (400). Spotify-Mixe nur über die Suche.
- Bibliothek: PUT/DELETE /me/library?uris=… und GET /me/library/contains?uris=…
- Abspielen ohne aktives Gerät: 404 NO_ACTIVE_DEVICE.
- Künstler: /artists/{id} (beim Künstler „weg“ ohne Bild und Follower), /artists/{id}/top-tracks
  nur für „a1“ (sonst 403 wie bei Apps, denen Spotify die Top-Titel nicht mehr gibt).
- Alle Titel: Künstler „viel“ mit 23 Veröffentlichungen auf drei Seiten (höchstens 10 je Seite),
  doppelter Fassung, Remaster, Single vor dem Album und einem Album mit 60 Titeln (zwei Seiten);
  /albums?ids= ist gesperrt (403) außer mit /__set?several=1; das große Album antwortet beim
  ersten Mal 429 mit Retry-After: 1. Künstler „gesperrt“: /artists/{id}/albums 403, die Suche
  artist:"Gesperrt" blättert über 24 Treffer (mit fremden Künstlern und einer Doppelung).
„Mit Spotify angemeldet“: Schlüssel des Webplayers „apptokWebplayer0123456789“ mit Client-Token
„clienttokWebplayer0123456789“ (beides liefert in der Probe die nachgebaute Seite, nicht dieser Server).
- Mit dem Schlüssel: pathfinder (auch profileAttributes für die Kontoprüfung), spclient, Dealer, Kategorie
  „Für dich gemacht“ mit den persönlichen Mixen, Titel jeder Playlist, Suche bis 50, /tracks?ids=;
  „nurintern“ nur über /spclient/context-resolve (zwei Seiten).
- authorization_code mit PKCE (S256 wird geprüft, Rücksprung http://127.0.0.1:<Port>/login) für die PKCE-Probe;
  die früheren Wege der QR-Anmeldung (device_code, refresh_token mit der Desktop-Kennung) bleiben unbenutzt.
- Zustände: app401 (Web-API und pathfinder lehnen den Schlüssel ab), app429 (bremst ihn mit Retry-After 3600),
  nocat (Kategorie weg: made-for-x mit verschachtelten Ansichten), spcno (spclient lehnt ihn ab).
Aufruf: python3 fake_spotify.py <port>   (GET /__log zeigt alle Anfragen, POST /__set?devices=1)
"""
import base64
import hashlib
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LOG = []
WS = []            # offene Dealer-Websockets: (wfile, lock)
STATE = {"devices": [], "active": "", "saved": set(), "oldscope": False, "oldlib": False,
         "nofollow": False, "unregistered": False, "expired": False, "bare403": False, "several": False, "slowed": False,
         "novolume": False, "appdead": False, "app401": False, "app429": False, "nocat": False, "devfail": False, "spcno": False,
         "webquota": False, "pfno": False, "ctno": False, "strictrot": False, "libfail": False, "appcur": None, "rot": 2,
         "paused": False, "shuffle": False, "conn": "", "ws": 0,
         # Abspielen über Spotify Connect: was geladen ist, und wie sich das Gerät bei „play“ verhält.
         # stumm: nimmt an und wird aktiv, lädt aber nichts (so stand es am PC, 13.11.). streng: führt nur die
         # vollständige Form aus. nurziel: nur mit dem Zielgerät als Absender. nurtitel: nur einen einzelnen Titel.
         # haengt: lädt, steht aber, bis „resume“ kommt.
         "track": "", "ctx": "", "stumm": False, "streng": False, "nurziel": False, "nurtitel": False, "haengt": False,
         "polls": 0, "challenge": ""}
APP = "65b708073fc0480ea92a077233ca87bd"
# Persisted-Query-Hash von „homeSection“ (wie bei nocturne/psst). Muss zur Anfrage passen.
PF_HOME_HASH = "c11ff5d8f508cb1a3dad3f15ee80611cda7df7e6fb45212e466fb3e84a680bf9"


def form(body):
    return {k: v[0] for k, v in parse_qs(body).items()}


def mix(pid, name):
    return playlist(pid, name, "", 50, True)


def track(i, album="Platte", art=True):
    return {
        "type": "track", "id": "t%d" % i, "uri": "spotify:track:t%d" % i, "name": "Titel %d" % i,
        "duration_ms": 180000 + i * 1000, "explicit": False,
        "artists": [{"id": "a1", "name": "Künstler"}],
        "album": {"name": album, "images": ([{"url": "http://127.0.0.1:9/big.jpg"}, {"url": "http://127.0.0.1:9/mid.jpg"}] if art else None)},
    }


def album(aid, name, date, kind="album", precision="day"):
    return {
        "id": aid, "uri": "spotify:album:" + aid, "name": name, "album_type": kind,
        "release_date": date, "release_date_precision": precision, "total_tracks": 3,
        "artists": [{"name": "Künstler"}], "images": [{"url": "http://127.0.0.1:9/a.jpg"}],
    }


def playlist(pid, name, owner, total=3, spotify=False):
    return {
        "id": pid, "uri": "spotify:playlist:" + pid, "name": name, "collaborative": False,
        "description": "Mit <b>Fett</b> &amp; Spaß", "images": [{"url": "http://127.0.0.1:9/p.jpg"}],
        "owner": {"id": "spotify" if spotify else owner, "display_name": "Spotify" if spotify else owner},
        "items": {"href": "x", "total": total},
    }


VIEL = {"id": "viel", "name": "Viele"}


def vtrack(tid, name, dur, artists=None):
    return {"type": "track", "id": tid, "uri": "spotify:track:" + tid, "name": name, "duration_ms": dur,
            "explicit": False, "artists": artists or [dict(VIEL)]}


def viel_releases(guest=False):
    """Veröffentlichungen von „viel“ wie bei Spotify: erst Alben, dann Singles (je neueste zuerst)."""
    rel = [("viel-a1", "Drittes Album", "2024-03-01", "album", "album"),
           ("viel-r", "Zweites Album (Remastered 2023)", "2023-01-01", "album", "album"),
           ("viel-a2", "Zweites Album", "2020-06-01", "album", "album"),
           ("viel-a2x", "Zweites Album", "2020-06-01", "album", "album"),
           ("viel-big", "Großes Album", "2018-01-01", "album", "album")]
    rel += [("viel-f%d" % n, "Album %d" % n, "%d-01-01" % (2000 + n), "album", "album") for n in range(15, -1, -1)]
    rel += [("viel-s2", "Neu", "2026-09-01", "single", "single"), ("viel-s1", "Hit", "2020-05-01", "single", "single")]
    if guest:
        rel += [("viel-g", "Sampler", "2022-02-02", "compilation", "appears_on")]
    out = []
    for rid, name, date, kind, grp in rel:
        a = album(rid, name, date, kind)
        a["album_group"] = grp
        a["artists"] = [dict(VIEL)] if grp != "appears_on" else [{"id": "va", "name": "Verschiedene"}]
        out.append(a)
    return out


def viel_tracks(aid):
    if aid == "viel-a1":
        return [vtrack("a1-%d" % i, "Lied %d" % i, 150000 + i * 7000) for i in range(1, 5)]
    if aid in ("viel-a2", "viel-a2x"):
        return [vtrack(aid + "-hit", "Hit", 200000), vtrack(aid + "-2", "Zwei 2", 170000), vtrack(aid + "-3", "Zwei 3", 171000)]
    if aid == "viel-r":
        return [vtrack("r-hit", "Hit - Remastered 2023", 201000), vtrack("r-2", "Zwei 2 - 2023 Remaster", 170500), vtrack("r-3", "Zwei 3", 171000)]
    if aid == "viel-big":
        return [vtrack("big-%d" % i, "Groß %d" % i, 120000 + i * 3000) for i in range(60)]
    if aid == "viel-s1":
        return [vtrack("s1-hit", "Hit", 200500)]
    if aid == "viel-s2":
        return [vtrack("s2-neu", "Neu", 190000)]
    if aid == "viel-g":
        return [vtrack("g-1", "Gast", 210000, [{"id": "va2", "name": "Andere"}, dict(VIEL)]), vtrack("g-2", "Fremd", 220000, [{"id": "va2", "name": "Andere"}])]
    if aid.startswith("viel-f"):
        n = aid[6:]
        return [vtrack("f-" + n, "Füller " + n, 100000 + int(n) * 1000)]
    return []


def gesperrt_hits():
    """Suchtreffer für artist:"Gesperrt": 24 Stück, zwei von anderen, eine Doppelung (gleiche Aufnahme)."""
    out = []
    for i in range(24):
        t = vtrack("gs-%d" % i, "Treffer %d" % i, 150000 + i * 4000, [{"id": "gesperrt", "name": "Gesperrt"}])
        if i in (5, 17):
            t["artists"] = [{"id": "jemand", "name": "Gesperrt Cover"}]
        if i == 12:
            t["name"] = "Treffer 3"
            t["duration_ms"] = 150000 + 3 * 4000 + 800
        t["album"] = {"id": "ga%d" % (i // 4), "uri": "spotify:album:ga%d" % (i // 4), "name": "Platte %d" % (i // 4), "album_type": "album",
                      "release_date": "%d-01-01" % (2010 + i // 4), "release_date_precision": "day", "artists": [{"name": "Gesperrt"}], "images": []}
        out.append(t)
    return out


def days_ago(n):
    return time.strftime("%Y-%m-%d", time.gmtime(time.time() - n * 86400))


def pf_playlist(pid, name, owner="spotify"):
    """Eine Playlist in der Form, wie pathfinder sie in homeSection liefert."""
    return {"uri": "spotify:playlist:" + pid, "content": {"data": {
        "__typename": "Playlist", "uri": "spotify:playlist:" + pid, "name": name,
        "description": "Für dich",
        "images": {"items": [{"sources": [{"url": "https://i.scdn.co/image/%s" % pid}]}]},
        "ownerV2": {"data": {"name": "Spotify" if owner == "spotify" else owner, "uri": "spotify:user:" + owner}}}}}


def home_section(uri):
    """Antwort von „homeSection“: persönliche Mixe (api-partner, nicht api.spotify.com)."""
    if uri == "spotify:section:0JQ5DAUnp4wcj0bCb3wh3S":   # Für dich gemacht
        items = [pf_playlist("37i9dQZEVXcDW", "Dein Mix der Woche"),
                 pf_playlist("37i9dQZEVXbRR", "Release Radar"),
                 pf_playlist("37i9dQZF1E3d1", "Daily Mix 1"),
                 pf_playlist("37i9dQZF1E3d2", "Daily Mix 2"),
                 {"uri": "spotify:artist:x", "content": {"data": {"__typename": "Artist", "uri": "spotify:artist:x", "name": "Kein Mix"}}},
                 pf_playlist("37i9dQZF1EIchill", "Chill Mix")]
    elif uri == "spotify:section:0JQ5DAnM3wGh0gz1MXnu89":  # Deine Top-Mixe
        items = [pf_playlist("37i9dQZF1EpRep", "In Dauerschleife"),
                 pf_playlist("37i9dQZF1EcCap", "Deine Zeitkapsel")]
    else:
        items = []
    return {"data": {"homeSections": {"sections": [
        {"uri": uri, "data": {"title": {"transformedLabel": "Für dich"}},
         "sectionItems": {"totalCount": len(items), "items": items}}]}}}


# --- pathfinder: Antworten in der Form des Web-Clients --------------------------------------------
def pf_artist_ref(aid="a1", name="Künstler"):
    return {"uri": "spotify:artist:" + aid, "profile": {"name": name}}


def pf_track(i, with_uri=True):
    t = {"__typename": "Track", "name": "Titel %d" % i, "duration": {"totalMilliseconds": 180000 + i * 1000},
         "contentRating": {"label": "NONE"}, "artists": {"items": [pf_artist_ref()]},
         "albumOfTrack": {"uri": "spotify:album:al%d" % i, "name": "Platte",
                          "coverArt": {"sources": [{"url": "http://127.0.0.1:9/mid.jpg", "width": 300}, {"url": "http://127.0.0.1:9/big.jpg", "width": 640}]}}}
    if with_uri:
        t["uri"] = "spotify:track:t%d" % i
    return t


def pf_album(aid, name, date, kind="ALBUM"):
    return {"__typename": "Album", "uri": "spotify:album:" + aid, "name": name, "type": kind,
            "date": {"isoString": date + "T00:00:00Z", "precision": "DAY"}, "tracks": {"totalCount": 3},
            "coverArt": {"sources": [{"url": "http://127.0.0.1:9/a.jpg", "width": 300}]}, "artists": {"items": [pf_artist_ref()]}}


def pf_pl(pid, name, owner, total, spotify=False):
    o = "spotify" if spotify else owner
    return {"__typename": "Playlist", "uri": "spotify:playlist:" + pid, "name": name, "description": "Mit <b>Fett</b> &amp; Spaß",
            "images": {"items": [{"sources": [{"url": "http://127.0.0.1:9/p.jpg"}]}]},
            "ownerV2": {"data": {"uri": "spotify:user:" + o, "name": "Spotify" if spotify else owner}}, "content": {"totalCount": total}}


def pf_answer(op, v):
    """Antwort von pathfinder auf eine Abfrage (None: unbekannt)."""
    if op == "libraryV3":
        f = (v.get("filters") or [""])[0]
        if f == "Playlists":
            items = [{"item": {"_uri": "spotify:playlist:eigen", "data": pf_pl("eigen", "Eigene", "ich", 3)}},
                     {"item": {"_uri": "spotify:user:ich:folder:x", "data": {"__typename": "Folder", "uri": "spotify:user:ich:folder:x", "name": "Ordner"}}},
                     {"item": {"data": pf_pl("fremd", "Fremde", "lena", 112)}}]
        elif f == "Albums":
            items = [{"item": {"data": pf_album("gesp", "Gespeichert", "2010-01-01")}}]
        elif f == "Artists":
            items = [{"item": {"data": {"__typename": "Artist", "uri": "spotify:artist:a2", "profile": {"name": "Andere"}}}}]
        else:
            items = []
        return {"data": {"me": {"libraryV3": {"totalCount": len(items), "items": items}}}}
    if op == "fetchLibraryTracks":
        return {"data": {"me": {"library": {"tracks": {"totalCount": 1, "items": [{"track": {"_uri": "spotify:track:t5", "data": pf_track(5, False)}}]}}}}}
    if op == "searchDesktop":
        term = str(v.get("searchTerm", "")).lower()
        pls = []
        if "discover" in term:
            pls = [{"data": pf_pl("dw", "Discover Weekly", "", 30, True)}]
        return {"data": {"searchV2": {"tracksV2": {"items": [{"item": {"data": pf_track(30)}}]},
                                      "artists": {"items": [{"data": {"__typename": "Artist", "uri": "spotify:artist:a1", "profile": {"name": "Künstler"}}}]},
                                      "albumsV2": {"items": [{"data": pf_album("such", "Gefunden", "2020-01-01")}]},
                                      "playlists": {"items": pls}}}}
    if op == "userTopContent":
        prof = {}
        if v.get("includeTopTracks"):
            prof["topTracks"] = {"items": [{"data": pf_track(i)} for i in (1, 2, 3)]}
        if v.get("includeTopArtists"):
            prof["topArtists"] = {"items": [{"data": {"__typename": "Artist", "uri": "spotify:artist:a1", "profile": {"name": "Künstler"}}}]}
        return {"data": {"me": {"profile": prof}}}
    if op == "fetchPlaylist":
        pid = str(v.get("uri", "")).split(":")[-1]
        if pid == "nurintern":
            return {"data": {"playlistV2": {"__typename": "NotFound"}}}
        nums = [1, 2] if pid == "eigen" else [70, 71, 72]
        off, lim = int(v.get("offset", 0)), int(v.get("limit", 100))
        page = nums[off:off + lim]
        return {"data": {"playlistV2": {"__typename": "Playlist", "uri": v.get("uri"), "name": pid,
                                        "content": {"totalCount": len(nums), "items": [{"itemV2": {"data": pf_track(n)}} for n in page]}}}}
    if op == "getAlbum":
        t = pf_track(20)
        return {"data": {"albumUnion": {"uri": v.get("uri"), "name": "Album", "tracksV2": {"totalCount": 1, "items": [{"track": t}]}}}}
    if op == "getTrack":
        n = int(str(v.get("uri", "spotify:track:t0")).split(":")[-1][1:] or 0)
        return {"data": {"trackUnion": pf_track(n)}}
    if op == "queryArtistOverview":
        aid = str(v.get("uri", "")).split(":")[-1]
        return {"data": {"artistUnion": {"__typename": "Artist", "uri": "spotify:artist:" + aid, "profile": {"name": "Künstler" if aid == "a1" else "Andere"},
                                         "visuals": {"avatarImage": {"sources": [{"url": "http://127.0.0.1:9/k.jpg", "width": 640}]}},
                                         "stats": {"followers": 51234},
                                         "discography": {"topTracks": {"items": [{"track": pf_track(40)}, {"track": pf_track(41)}]},
                                                         "albums": {"items": [{"releases": {"items": [pf_album(aid + "-neu", "Neu " + aid, days_ago(3)), pf_album(aid + "-alt", "Alt " + aid, "2019-05-01")]}}]},
                                                         "singles": {"items": []}}}}}
    if op == "areEntitiesInLibrary":
        return {"data": {"lookup": [{"__typename": "TrackResponseWrapper", "data": {"__typename": "Track", "saved": u in STATE["saved"]}} for u in v.get("uris", [])]}}
    if op in ("addToLibrary", "removeFromLibrary"):
        for u in v.get("libraryItemUris", []):
            (STATE["saved"].add if op == "addToLibrary" else STATE["saved"].discard)(u)
        key = "addLibraryItems" if op == "addToLibrary" else "removeLibraryItems"
        return {"data": {key: {"__typename": "AddLibraryItemsResponse" if op == "addToLibrary" else "RemoveLibraryItemsResponse"}}}
    return None


# --- Spotify Connect --------------------------------------------------------------------------------
CONNECT_TYPES = {"Computer": "COMPUTER", "Smartphone": "SMARTPHONE", "Speaker": "SPEAKER", "TV": "TV"}


def cluster():
    devs = {}
    for d in STATE["devices"]:
        devs[d["id"]] = {"device_id": d["id"], "name": d["name"], "device_type": CONNECT_TYPES.get(d["type"], "UNKNOWN"),
                         "volume": int(d.get("volume_percent", 50) * 65535 / 100), "capabilities": {}}
    ps = {}
    if STATE["active"]:
        # Aktiv heißt nicht geladen: Ohne Titel meldet das Gerät einen leeren Zustand.
        t = STATE["track"]
        ps = {"is_playing": bool(t), "is_paused": STATE["paused"], "timestamp": str(int(time.time() * 1000)),
              "position_as_of_timestamp": "1000", "duration": "181000", "context_uri": STATE["ctx"],
              "options": {"shuffling_context": STATE["shuffle"], "repeating_context": False, "repeating_track": False}}
        if t:
            nr = t.rsplit(":", 1)[-1][1:]
            ps["track"] = {"uri": t, "metadata": {"title": "Titel " + (nr if nr.isdigit() else "1"), "artist_name": "Künstler", "album_title": "Platte",
                                                  "image_url": "spotify:image:ab67"}}
            ps["next_tracks"] = [{"uri": "spotify:track:t2", "metadata": {"title": "Titel 2", "artist_name": "Künstler"}},
                                 {"uri": "spotify:delimiter"}, {"uri": "spotify:track:t3"}]
    return {"active_device_id": STATE["active"], "devices": devs, "player_state": ps}


def _teil(cmd, key):
    return cmd.get(key) if isinstance(cmd.get(key), dict) else {}


def play_greift(cmd, von, ziel):
    """Führt das Gerät den Abspielbefehl aus? Angenommen (HTTP 200) wird er in jedem Fall."""
    ctx, opts, lp = _teil(cmd, "context"), _teil(cmd, "options"), _teil(cmd, "logging_params")
    if STATE["stumm"]:
        return False
    if STATE["streng"] and not (isinstance(ctx.get("metadata"), dict) and opts.get("initially_paused") is False and "seek_to" in opts
                                and isinstance(lp.get("page_instance_ids"), list) and isinstance(lp.get("interaction_ids"), list)):
        return False
    if STATE["nurziel"] and von != ziel:
        return False
    if STATE["nurtitel"] and not str(ctx.get("uri") or "").startswith("spotify:track:"):
        return False
    return True


def play_titel(cmd):
    """Der Titel, mit dem ein Abspielbefehl beginnt."""
    ctx, opts = _teil(cmd, "context"), _teil(cmd, "options")
    uri = str(ctx.get("uri") or "")
    if uri.startswith("spotify:track:"):
        return uri
    skip = _teil(opts, "skip_to")
    if skip.get("track_uri"):
        return str(skip["track_uri"])
    pages = ctx.get("pages") if isinstance(ctx.get("pages"), list) else []
    tracks = pages[0].get("tracks") if pages and isinstance(pages[0], dict) and isinstance(pages[0].get("tracks"), list) else []
    if tracks:
        return str(tracks[min(int(skip.get("track_index") or 0), len(tracks) - 1)].get("uri") or "")
    return "spotify:track:t1"


def ws_frame(text):
    b = text.encode()
    n = len(b)
    if n < 126:
        head = bytes([0x81, n])
    elif n < 65536:
        head = bytes([0x81, 126]) + n.to_bytes(2, "big")
    else:
        head = bytes([0x81, 127]) + n.to_bytes(8, "big")
    return head + b


def ws_push(text):
    for w, lock in list(WS):
        try:
            with lock:
                w.write(ws_frame(text))
                w.flush()
        except Exception:
            pass


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, data=None):
        body = b"" if data is None else json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _text(self, code, text):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _err(self, code, msg, reason=None):
        e = {"status": code, "message": msg}
        if reason:
            e["reason"] = reason
        self._send(code, {"error": e})

    def _dealer(self, q):
        """Dealer-Websocket: Handschlag, dann die Connection-Id, Ping/Pong, bis der Client schließt."""
        if q.get("access_token") != ["apptokWebplayer0123456789"]:
            return self._err(401, "Invalid token")
        key = self.headers.get("Sec-WebSocket-Key") or ""
        acc = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.wfile.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                          "Sec-WebSocket-Accept: %s\r\n\r\n" % acc).encode())
        STATE["ws"] += 1
        conn = "conn%d" % STATE["ws"]
        STATE["conn"] = conn
        lock = threading.Lock()
        entry = (self.wfile, lock)
        WS.append(entry)
        self.wfile.flush()
        time.sleep(0.1)   # wie beim echten Dealer: die erste Nachricht kommt nach dem Handschlag
        with lock:
            self.wfile.write(ws_frame(json.dumps({"headers": {"Spotify-Connection-Id": conn}, "method": "PUT", "type": "message",
                                                  "uri": "hm://pusher/v1/connections/" + conn})))
            self.wfile.flush()
        try:
            while True:
                hd = self.rfile.read(2)
                if len(hd) < 2:
                    break
                op = hd[0] & 0x0F
                n = hd[1] & 0x7F
                if n == 126:
                    n = int.from_bytes(self.rfile.read(2), "big")
                elif n == 127:
                    n = int.from_bytes(self.rfile.read(8), "big")
                mask = self.rfile.read(4) if hd[1] & 0x80 else b"\0\0\0\0"
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(self.rfile.read(n)))
                if op == 8:
                    with lock:
                        self.wfile.write(bytes([0x88, 0]))
                        self.wfile.flush()
                    break
                if op == 9:
                    with lock:
                        self.wfile.write(bytes([0x8A, len(data)]) + data)
                        self.wfile.flush()
                elif op == 1 and b"ping" in data:
                    with lock:
                        self.wfile.write(ws_frame(json.dumps({"type": "pong"})))
                        self.wfile.flush()
        except Exception:
            pass
        if entry in WS:
            WS.remove(entry)
        self.close_connection = True

    def _connect(self, method, rest, body):
        """Spotify Connect: Zustand (nur mit gültiger Connection-Id), Befehle, Lautstärke, Wechsel."""
        ids = [d["id"] for d in STATE["devices"]]
        if rest.startswith("devices/") and method == "PUT":
            if not STATE["conn"] or (self.headers.get("X-Spotify-Connection-Id") or "") != STATE["conn"]:
                return self._send(400, {"error": "Missing or invalid connection id"})
            return self._send(200, cluster())
        parts = rest.split("/")
        target = parts[-1] if len(parts) >= 5 else ""
        if rest.startswith("player/command/from/") and method == "POST":
            cmd = json.loads(body or "{}").get("command")
            if not isinstance(cmd, dict):
                return self._send(400, {"error_type": "BAD_COMMAND", "message": "Payload does not contain a command object"})
            if target not in ids:
                return self._send(404, {"error_type": "DEVICE_NOT_FOUND"})
            ep = cmd.get("endpoint")
            if ep == "play":
                STATE["active"] = target
                if play_greift(cmd, parts[3], target):
                    STATE["track"] = play_titel(cmd)
                    STATE["ctx"] = str(_teil(cmd, "context").get("uri") or "")
                    STATE["paused"] = STATE["haengt"]
            elif ep == "pause":
                STATE["paused"] = True
            elif ep == "resume":
                STATE["paused"] = False
            elif ep == "set_shuffling_context":
                STATE["shuffle"] = bool(cmd.get("value"))
            return self._send(200, {"ack_id": "ack%d" % len(LOG)})
        if rest.startswith("connect/volume/from/") and method == "PUT":
            if target not in ids:
                return self._send(404, {"error_type": "DEVICE_NOT_FOUND"})
            for d in STATE["devices"]:
                if d["id"] == target:
                    d["volume_percent"] = round(int(json.loads(body or "{}").get("volume", 0)) * 100 / 65535)
            return self._send(200, {})
        if rest.startswith("connect/transfer/from/") and method == "POST":
            if target not in ids:
                return self._send(404, {"error_type": "DEVICE_NOT_FOUND"})
            STATE["active"] = target
            if not STATE["track"]:
                # Übernehmen stellt wieder her, was zuletzt lief.
                STATE["track"] = "spotify:track:t1"
                STATE["ctx"] = "spotify:playlist:eigen"
            return self._send(200, {"ack_id": "t"})
        return self._err(404, "Not found")

    def _json429(self, msg, retry_after):
        body = json.dumps({"error": {"status": 429, "message": msg}}).encode()
        self.send_response(429)
        self.send_header("Retry-After", str(retry_after))
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _route(self, method):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        p = u.path
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        auth = self.headers.get("Authorization") or ""
        if not p.startswith("/__"):
            LOG.append({"m": method, "p": p, "q": u.query, "b": body, "t": auth.replace("Bearer ", ""),
                        "c": self.headers.get("X-Spotify-Connection-Id") or ""})
        if p.startswith("/dealer") and (self.headers.get("Upgrade") or "").lower() == "websocket":
            return self._dealer(q)
        if p == "/__log":
            return self._send(200, LOG)
        if p == "/__push":
            # Der Dealer meldet: der Zustand bei Spotify Connect hat sich geändert.
            ws_push(json.dumps({"type": "message", "uri": "hm://connect-state/v1/cluster", "headers": {"Content-Type": "application/json"}, "payloads": []}))
            return self._send(200, {"ok": True, "ws": len(WS)})
        if p == "/__set":
            if "devices" in q:
                STATE["devices"] = [{"id": "pc1", "name": "WOHNZIMMER", "type": "Computer", "is_active": False, "volume_percent": 50}] if q.get("devices") in (["1"], ["2"]) else []
                if q.get("devices") == ["2"]:
                    # Handy, gesperrte Box, schlafender Lautsprecher (erst wecken), sturer Fernseher.
                    STATE["devices"] += [{"id": "handy", "name": "Handy", "type": "Smartphone", "is_active": False},
                                         {"id": "box", "name": "Box", "type": "Speaker", "is_active": False, "is_restricted": True},
                                         {"id": "schlaf", "name": "Küche", "type": "Speaker", "is_active": False},
                                         {"id": "stur", "name": "Fernseher", "type": "TV", "is_active": False}]
                    STATE["woken"] = False
                STATE["active"] = ""
                STATE["track"] = ""
                STATE["ctx"] = ""
            for k in ("oldscope", "oldlib", "nofollow", "unregistered", "expired", "bare403", "several", "novolume",
                      "appdead", "app401", "app429", "nocat", "devfail", "spcno", "webquota", "pfno", "ctno", "strictrot", "libfail",
                      "stumm", "streng", "nurziel", "nurtitel", "haengt"):
                STATE[k] = q.get(k) == ["1"]
            STATE["appcur"] = None
            STATE["paused"] = False
            STATE["shuffle"] = False
            return self._send(200, {"ok": True})
        f = form(body)
        if p == "/oauth2/device/authorize":
            if f.get("client_id") != APP or STATE["devfail"]:
                return self._send(400, {"error": "unauthorized_client", "error_description": "Client not allowed"})
            STATE["polls"] = 0
            return self._send(200, {"device_code": "dc1", "user_code": "ABCDEF", "verification_uri": "https://spotify.com/pair",
                                    "verification_uri_complete": "https://spotify.com/pair?code=ABCDEF", "expires_in": 3599, "interval": 1})
        if p == "/authorize":
            # Statt der Seite im Browser: Prüfwert merken und den Code gleich zurückgeben.
            STATE["challenge"] = q.get("code_challenge", [""])[0]
            return self._send(200, {"code": "c1", "redirect_uri": q.get("redirect_uri", [""])[0]})
        if p == "/api/token" and f.get("client_id") == APP:
            app_scope = "user-read-playback-state user-modify-playback-state playlist-read-private user-library-read user-top-read user-follow-read user-personalized"
            ok = {"access_token": "apptokWebplayer0123456789", "token_type": "Bearer", "expires_in": 3600, "scope": app_scope}
            g = f.get("grant_type", "")
            if g == "urn:ietf:params:oauth:grant-type:device_code":
                if f.get("device_code") != "dc1":
                    return self._send(400, {"error": "invalid_request"})
                STATE["polls"] += 1
                if STATE["polls"] < 2:
                    return self._send(400, {"error": "authorization_pending"})
                return self._send(200, dict(ok, refresh_token="appr1"))
            if g == "authorization_code":
                want = base64.urlsafe_b64encode(hashlib.sha256(f.get("code_verifier", "").encode()).digest()).decode().rstrip("=")
                red = f.get("redirect_uri", "")
                if f.get("code") != "c1" or want != STATE["challenge"] or not (red.startswith("http://127.0.0.1:") and red.endswith("/login")):
                    return self._send(400, {"error": "invalid_grant", "error_description": "PKCE or redirect mismatch"})
                return self._send(200, dict(ok, refresh_token="appr1"))
            if g == "refresh_token":
                rt = f.get("refresh_token") or ""
                if STATE["appdead"] or not rt.startswith("appr"):
                    return self._send(400, {"error": "invalid_grant", "error_description": "Refresh token revoked"})
                if STATE["strictrot"]:
                    # Wie Spotify: jede Erneuerung dreht die Erneuerung, die alte gilt danach nicht mehr.
                    if STATE["appcur"] is not None and rt != STATE["appcur"]:
                        return self._send(400, {"error": "invalid_grant", "error_description": "Refresh token revoked"})
                    time.sleep(0.3)
                    STATE["rot"] += 1
                    STATE["appcur"] = "appr%d" % STATE["rot"]
                    return self._send(200, dict(ok, refresh_token=STATE["appcur"]))
                return self._send(200, dict(ok, refresh_token="appr2"))
            return self._send(400, {"error": "unsupported_grant_type"})
        if p == "/api/token":
            # Seit Juli 2026: Anmeldungen enden nach sechs Monaten, dann invalid_grant.
            if STATE["expired"] and "grant_type=refresh_token" in body:
                return self._send(400, {"error": "invalid_grant", "error_description": "Refresh token revoked"})
            scope = "user-read-playback-state user-modify-playback-state user-library-read user-library-modify user-read-recently-played playlist-read-private"
            if not STATE["oldscope"]:
                scope += " user-top-read"
                if not STATE["nofollow"]:
                    scope += " user-follow-read"
            return self._send(200, {"access_token": "tok", "token_type": "Bearer", "expires_in": 3600, "scope": scope})
        app = auth == "Bearer apptokWebplayer0123456789"
        # Client-Token (wie die echten Spotify-Clients): JSON rein, JSON raus. Für pathfinder/spclient.
        if p == "/clienttoken/v1/clienttoken":
            if STATE["ctno"]:
                return self._send(500, {"error": "server_error"})
            return self._send(200, {"response_type": "RESPONSE_GRANTED_TOKEN_RESPONSE",
                                    "granted_token": {"token": "clienttokWebplayer0123456789", "expires_after_seconds": 3600, "refresh_after_seconds": 3000}})
        # Pathfinder (api-partner): GraphQL mit Persisted Query. Nur mit der App-Anmeldung und Client-Token.
        if p == "/pathfinder/v2/query":
            ct = self.headers.get("client-token") or ""
            if not app or ct != "clienttokWebplayer0123456789" or STATE["app401"]:
                return self._err(401, "Invalid token")
            if STATE["pfno"]:
                return self._json429("API rate limit exceeded", 30)
            req = json.loads(body or "{}")
            op = req.get("operationName", "")
            h = req.get("extensions", {}).get("persistedQuery", {}).get("sha256Hash", "")
            if op == "homeSection":
                if h != PF_HOME_HASH:
                    return self._send(400, {"errors": [{"message": "PersistedQueryNotFound"}]})
                sec = req.get("variables", {}).get("uri", "")
                return self._send(200, home_section(sec))
            if op == "profileAttributes":
                return self._send(200, {"data": {"me": {"profile": {"name": "Ich (App)", "username": "ich"}}}})
            ans = pf_answer(op, req.get("variables", {}))
            if ans is not None:
                return self._send(200, ans)
            return self._send(400, {"errors": [{"message": "PersistedQueryNotFound"}]})
        if p.startswith("/spclient/"):
            # Interne Schnittstelle der Spotify-Apps: nur mit der App-Anmeldung, Antwort als JSON.
            if not app or STATE["spcno"]:
                return self._err(401, "Invalid token")
            if p.endswith("spotify:playlist:nurintern"):
                return self._send(200, {"uri": "spotify:playlist:nurintern", "metadata": {"context_description": "Nur intern"},
                                        "pages": [{"tracks": [{"uri": "spotify:track:t60", "uid": "a"}, {"uri": "spotify:track:t61", "uid": "b"},
                                                              {"uri": "spotify:episode:e1", "uid": "c"}],
                                                   "next_page_url": "hm://context-resolve/v1/seite2/nurintern"}]})
            if p == "/spclient/recently-played/v3/user/ich/recently-played":
                return self._send(200, {"playContexts": [{"uri": "spotify:playlist:x", "lastPlayedTrackUri": "spotify:track:t6"},
                                                         {"lastPlayedTrackUri": "spotify:track:t6"}, {"lastPlayedTrackUri": "spotify:track:t7"}]})
            if p.startswith("/spclient/connect-state/v1/"):
                return self._connect(method, p[len("/spclient/connect-state/v1/"):], body)
            if p.endswith("/seite2/nurintern"):
                return self._send(200, {"pages": [{"tracks": [{"uri": "spotify:track:t62", "uid": "d", "metadata": {"title": "Nur Name"}},
                                                              {"uri": "spotify:track:t60", "uid": "e"}]}]})
            return self._err(404, "Not found")
        if app and STATE["app401"]:
            return self._err(401, "Invalid access token")
        if app and STATE["app429"]:
            return self._json429("API rate limit exceeded", 3600)
        # Seit Dez. 2025: die Web-API (api.spotify.com) bremst die Kennung der Desktop-App dauerhaft
        # (429), während pathfinder und spclient mit demselben Schlüssel weiter antworten.
        if app and STATE["webquota"] and p.startswith("/v1"):
            return self._json429("API rate limit exceeded", 11)
        if auth not in ("Bearer tok", "Bearer apptokWebplayer0123456789"):
            return self._err(401, "No token provided")
        # Development Mode: Konto steht nicht unter „User Management“ der App.
        # Spotify schickt diese Ablehnung als reinen Text, nicht als JSON.
        if STATE["unregistered"]:
            return self._text(403, "Check settings on developer.spotify.com/dashboard, the user may not be registered.")
        # Abgelehnt ohne jeden Grund (leerer Rumpf).
        if STATE["bare403"]:
            return self._send(403)
        v = p[3:] if p.startswith("/v1") else p
        if v == "/me":
            return self._send(200, {"id": "ich", "display_name": "Ich"})
        if v == "/me/playlists":
            items = [playlist("eigen", "Eigene", "ich"), None, playlist("fremd", "Fremde", "lena", 112)]
            if app:
                # Wie die Spotify-App fehlen gefolgte Mixe von Spotify nicht (eigene Apps: null).
                items.append(mix("37i9dQZEVXbRR", "Release Radar"))
            return self._send(200, {"items": items, "next": None})
        if v == "/browse/categories/0JQ5DAqbMKFHOzuVTgTizF/playlists":
            if not app or STATE["nocat"]:
                return self._err(404, "Not found")
            return self._send(200, {"message": "Für dich gemacht", "playlists": {"items": [
                mix("37i9dQZF1E3d1", "Daily Mix 1"), mix("37i9dQZEVXcDW", "Dein Mix der Woche"), None,
                mix("37i9dQZEVXbRR", "Release Radar"), mix("37i9dQZF1E3d2", "Daily Mix 2"), mix("37i9dQZF1EIchill", "Chill Mix"),
                playlist("fan", "Release Radar", "fan")]}})
        if v == "/views/made-for-x":
            if not app:
                return self._err(404, "Not found")
            return self._send(200, {"content": {"items": [
                {"type": "view", "name": "Deine Top-Mixe", "content": {"items": [mix("37i9dQZF1EpRep", "In Dauerschleife"), mix("37i9dQZF1E3d3", "Daily Mix 3")]}},
                {"type": "view", "name": "Zeitreise", "content": {"items": [mix("37i9dQZF1EcCap", "Deine Zeitkapsel"), {"type": "album", "uri": "spotify:album:x", "name": "Kein Mix"}]}}]}})
        if v == "/tracks" and app:
            ids = q.get("ids", [""])[0].split(",")
            return self._send(200, {"tracks": [track(int(i[1:])) if i.startswith("t") and i[1:].isdigit() and i != "t62" else None for i in ids]})
        if v.startswith("/playlists/") and app:
            parts = v.split("/")
            if parts[2] == "nurintern":
                return self._err(404, "Not found")
            if len(parts) > 3 and parts[3] in ("items", "tracks"):
                return self._send(200, {"items": [{"item": track(70)}, {"item": track(71)}, {"item": track(72)}], "next": None, "total": 3})
        if v.startswith("/playlists/"):
            parts = v.split("/")
            pid, what = parts[2], parts[3] if len(parts) > 3 else ""
            if what == "tracks":
                return self._err(403, "Forbidden")
            if what == "items":
                if pid != "eigen":
                    return self._err(403, "Forbidden")
                return self._send(200, {"items": [{"item": track(1)}, {"item": track(2), "track": track(2)}, {"item": None}], "next": None, "total": 2})
        if STATE["oldlib"] and v.startswith("/me/library"):
            return self._err(404, "Service not found")
        if STATE["oldscope"] and (v.startswith("/me/top/") or v == "/me/following"):
            return self._err(403, "Insufficient client scope")
        if STATE["nofollow"] and v == "/me/following":
            return self._err(403, "Insufficient client scope")
        if STATE["libfail"] and v in ("/me/tracks", "/me/library") and method in ("PUT", "DELETE"):
            return self._err(500, "Server error")
        if v == "/me/tracks" and method in ("PUT", "DELETE"):
            return self._send(200)
        if v == "/me/tracks/contains":
            return self._send(200, [True])
        if v == "/me/library" and method in ("PUT", "DELETE"):
            if not q.get("uris"):
                return self._err(400, "Missing required field: uris")
            for u2 in q["uris"][0].split(","):
                (STATE["saved"].add if method == "PUT" else STATE["saved"].discard)(u2)
            return self._send(200)
        if v == "/me/library/contains":
            return self._send(200, [u2 in STATE["saved"] for u2 in q.get("uris", [""])[0].split(",")])
        if v == "/me/tracks":
            return self._send(200, {"items": [{"added_at": "x", "track": track(5)}], "next": None})
        if v == "/me/player/recently-played":
            return self._send(200, {"items": [{"track": track(6), "played_at": "x"}, {"track": track(6), "played_at": "y"}, {"track": track(7), "played_at": "z"}]})
        if v == "/me/top/tracks":
            r = q.get("time_range", ["medium_term"])[0]
            ids = [1, 2, 3] if r == "short_term" else [8, 9, 10, 11, 12, 1, 6]
            return self._send(200, {"items": [track(i) for i in ids]})
        if v == "/me/top/artists":
            return self._send(200, {"items": [{"id": "a1", "name": "Künstler"}]})
        if v == "/me/following":
            return self._send(200, {"artists": {"items": [{"id": "a2", "name": "Andere"}], "next": None}})
        if v.startswith("/artists/") and v.endswith("/albums") and v.split("/")[2] in ("viel", "gesperrt"):
            if v.split("/")[2] == "gesperrt":
                return self._err(403, "Forbidden")
            limit = int(q.get("limit", ["20"])[0])
            if limit > 10:
                return self._err(400, "Invalid limit")
            off = int(q.get("offset", ["0"])[0])
            rel = viel_releases("appears_on" in q.get("include_groups", [""])[0])
            page = rel[off:off + limit]
            return self._send(200, {"items": page, "total": len(rel), "limit": limit, "offset": off,
                                    "next": ("x" if off + limit < len(rel) else None)})
        if v == "/albums":
            if not STATE["several"]:
                return self._err(403, "Forbidden")
            ids = q.get("ids", [""])[0].split(",")
            if len(ids) > 20:
                return self._err(400, "Too many ids requested")
            out = []
            for rid in ids:
                a = next((r for r in viel_releases(True) if r["id"] == rid), None)
                if a is None:
                    out.append(None)
                    continue
                a = dict(a)
                items = viel_tracks(rid)
                a["tracks"] = {"items": items[:50], "total": len(items), "next": ("x" if len(items) > 50 else None)}
                out.append(a)
            return self._send(200, {"albums": out})
        if v.startswith("/albums/viel-") and v.endswith("/tracks"):
            rid = v.split("/")[2]
            if rid == "viel-big" and not STATE["slowed"]:
                STATE["slowed"] = True
                body = json.dumps({"error": {"status": 429, "message": "API rate limit exceeded"}}).encode()
                self.send_response(429)
                self.send_header("Retry-After", "1")
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            limit = int(q.get("limit", ["20"])[0])
            if limit > 50:
                return self._err(400, "Invalid limit")
            off = int(q.get("offset", ["0"])[0])
            items = viel_tracks(rid)
            return self._send(200, {"items": items[off:off + limit], "total": len(items), "next": ("x" if off + limit < len(items) else None)})
        if v.startswith("/artists/") and v.endswith("/albums"):
            aid = v.split("/")[2]
            if int(q.get("limit", ["20"])[0]) > 10:
                return self._err(400, "Invalid limit")
            return self._send(200, {"items": [album(aid + "-neu", "Neu " + aid, days_ago(3)), album(aid + "-alt", "Alt " + aid, "2019-05-01"),
                                              album(aid + "-jahr", "Jahr " + aid, "2026", precision="year")]})
        if v.startswith("/artists/") and v.count("/") == 2:
            aid = v.split("/")[2]
            if aid == "a1":
                return self._send(200, {"id": "a1", "uri": "spotify:artist:a1", "name": "Künstler", "genres": ["spielmusik"],
                                        "followers": {"total": 51234}, "images": [{"url": "http://127.0.0.1:9/k.jpg"}]})
            if aid == "weg":
                return self._send(200, {"id": "weg", "uri": "spotify:artist:weg", "name": "Weg"})
            return self._err(404, "Not found")
        if v.startswith("/artists/") and v.endswith("/top-tracks"):
            if v.split("/")[2] != "a1":
                return self._err(403, "Forbidden")
            return self._send(200, {"tracks": [track(40), track(41)]})
        if v == "/me/albums":
            return self._send(200, {"items": [{"added_at": "x", "album": album("gesp", "Gespeichert", "2010-01-01")}]})
        if v.startswith("/albums/") and v.endswith("/tracks"):
            t = track(20)
            del t["album"]
            return self._send(200, {"items": [t], "next": None})
        if v == "/search":
            if int(q.get("limit", ["5"])[0]) > (50 if app else 10):
                return self._err(400, "Invalid limit")
            types = q.get("type", [""])[0].split(",")
            out = {}
            if "playlist" in types:
                qq = q.get("q", [""])[0].lower()
                items = [None]
                if "discover" in qq or "mix der woche" in qq:
                    items += [playlist("dw", "Discover Weekly", "", 30, True), playlist("kopie", "Discover Weekly", "fan")]
                if "release" in qq:
                    items += [playlist("rr", "Release Radar", "", 30, True)]
                out["playlists"] = {"items": items}
            if "track" in types and 'artist:"Gesperrt"' in q.get("q", [""])[0]:
                off = int(q.get("offset", ["0"])[0])
                hits = gesperrt_hits()
                out["tracks"] = {"items": hits[off:off + 10], "total": len(hits), "offset": off}
                return self._send(200, out)
            if "track" in types:
                out["tracks"] = {"items": [track(30)]}
                if 'artist:"Weg"' in q.get("q", [""])[0]:
                    weg = track(50)
                    weg["artists"] = [{"id": "weg", "name": "Weg"}]
                    out["tracks"] = {"items": [weg, track(30)]}
            if "artist" in types:
                out["artists"] = {"items": [{"id": "a1", "uri": "spotify:artist:a1", "name": "Künstler"}, None]}
            if "album" in types:
                out["albums"] = {"items": [album("such", "Gefunden", "2020-01-01")]}
            return self._send(200, out)
        if v == "/me/player/devices":
            return self._send(200, {"devices": STATE["devices"]})
        if v == "/me/player/volume" and method == "PUT":
            # Lautstärke: ohne Premium (novolume=1) lehnt Spotify ab.
            if STATE["novolume"]:
                return self._err(403, "Player command failed: Premium required", "PREMIUM_REQUIRED")
            for d in STATE["devices"]:
                if d["id"] == STATE["active"]:
                    d["volume_percent"] = int(q.get("volume_percent", ["0"])[0])
            return self._send(204)
        if v == "/me/player" and method == "PUT":
            req = json.loads(body or "{}")
            ids = req.get("device_ids", [])
            if ids and ids[0] == "box":
                return self._err(403, "Player command failed: Restricted device", "UNKNOWN")
            if ids and ids[0] == "schlaf" and not STATE.get("woken"):
                if req.get("play") is False:
                    STATE["woken"] = True
                    return self._send(204)
                return self._err(404, "Device not found")
            if ids and ids[0] == "stur":
                return self._send(204)
            if ids and any(d["id"] == ids[0] for d in STATE["devices"]):
                STATE["active"] = ids[0]
                for d in STATE["devices"]:
                    d["is_active"] = d["id"] == ids[0]
                return self._send(204)
            return self._err(404, "Device not found")
        if v.startswith("/me/player/play") or v.startswith("/me/player/pause") or v.startswith("/me/player/next") or v.startswith("/me/player/queue"):
            if method == "GET":
                return self._send(200, {"currently_playing": track(1), "queue": [track(2), track(3)]})
            if not STATE["active"]:
                return self._err(404, "Player command failed: No active device found", "NO_ACTIVE_DEVICE")
            ctx = json.loads(body or "{}").get("context_uri", "") if body else ""
            if ctx == "spotify:playlist:gesperrt":
                return self._err(404, "Not found.")
            return self._send(204)
        if v == "/me/player":
            if not STATE["active"]:
                return self._send(204)
            return self._send(200, {"is_playing": True, "progress_ms": 1000, "item": track(1), "device": next((d for d in STATE["devices"] if d["id"] == STATE["active"]), STATE["devices"][0]),
                                    "context": {"uri": "spotify:playlist:eigen"}, "shuffle_state": False, "repeat_state": "off"})
        return self._err(404, "Service not found")

    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")

    def do_PUT(self):
        self._route("PUT")

    def do_DELETE(self):
        self._route("DELETE")


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
