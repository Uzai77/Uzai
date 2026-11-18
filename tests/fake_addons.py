#!/usr/bin/env python3
"""Nachgebaute Stremio-Addons und ein Plugin-Repository für die Netz-Probe (tests/net_filme.gd).

- /cinemeta/   Cinemeta-artig: Kataloge (mit Genre, Suche, skip; einer mit Pflicht-Genre),
               Details zu Filmen und einer Serie mit zwei Staffeln und Specials
- /streams/    Stream-Addon: direkte Adressen (eine mit proxyHeaders, eine gecacht „[RD+]“),
               infoHash-Streams (P2P) und eine ytId; antwortet etwas verzögert
- /zweit/      zweites Stream-Addon (schnell), Streams nur in den Folgen der Details (inline)
- /kaputt/     gültiges Manifest, aber jede Stream-Anfrage endet mit HTTP 500
- /einrichten/ Addon, das erst eingerichtet werden muss (configurationRequired)
- /subs/       Untertitel-Addon
- /plugins/    Plugin-Repository wie bei Nuvio mit JavaScript-Scrapern, die gegen /site/ laufen
- /cloudstream/repo.json  CloudStream-Repository (wird abgelehnt)
- /tmdb/3/find/…          TMDB-Ersatz für den optionalen Schlüssel
- /tmdb/3/movie/<id>/credits, /tmdb/3/tv/<id>/aggregate_credits   Besetzung mit profile_path
- /img/person-<name>.png  kleines Porträt (PNG im Hochformat) für Personenbilder
Aufruf: python3 fake_addons.py <port>   (GET /__log zeigt alle Anfragen)
"""
import base64
import struct
import zlib
import hashlib
import hmac
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote, parse_qs

LOG = []
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18766
BASE = "http://127.0.0.1:%d" % PORT

GENRES = ["Action", "Drama", "Sci-Fi", "Science Fiction"]


def movie(i, name, year, genres, extra=None):
    m = {
        "id": "tt%03d" % i, "imdb_id": "tt%03d" % i, "type": "movie", "name": name, "year": year,
        "releaseInfo": year, "imdbRating": "7.%d" % i, "genres": genres,
        "poster": BASE + "/img/p%d.jpg" % i, "background": BASE + "/img/b%d.jpg" % i,
        "description": "Beschreibung %d" % i,
    }
    if i != 3:
        m["logo"] = BASE + "/img/l%d.png" % i
    if extra:
        m.update(extra)
    return m


MOVIES = [
    movie(1, "Matrix", "1999", ["Action", "Sci-Fi"], {"moviedb_id": 603}),
    movie(2, "Zweiter Film", "2004", ["Drama"]),
    movie(3, "Dritter Film", "2011", ["Drama", "Sci-Fi"]),
]

SERIES_META = {
    "id": "tt100", "imdb_id": "tt100", "type": "series", "name": "Testserie", "releaseInfo": "2019–", "imdbRating": 8.1,
    "genre": ["Drama"], "moviedb_id": 1399, "poster": BASE + "/img/s.jpg", "background": BASE + "/img/sb.jpg", "logo": BASE + "/img/sl.png",
    "description": "Eine Serie zum Testen.", "runtime": "50 min",
    "links": [{"name": "Ada Muster", "category": "Cast", "url": "stremio:///search?search=Ada"},
              {"name": "Bo Regie", "category": "Directors", "url": "x"}, {"name": "Drama", "category": "Genres", "url": "y"}],
    "trailerStreams": [{"title": "Trailer", "ytId": "abc123"}],
    "videos": [
        {"id": "tt100:1:1", "name": "Anfang", "season": 1, "episode": 1, "released": "2019-01-01T00:00:00.000Z", "thumbnail": BASE + "/img/e11.jpg"},
        {"id": "tt100:1:2", "name": "Mitte", "season": 1, "episode": 2, "released": "2019-01-08T00:00:00.000Z"},
        {"id": "tt100:2:1", "name": "Zweite Staffel", "season": 2, "episode": 1, "released": "2020-01-01T00:00:00.000Z"},
        {"id": "tt100:2:2", "name": "Später", "season": 2, "episode": 2, "released": "2099-01-01T00:00:00.000Z"},
        {"id": "tt100:0:1", "name": "Special", "season": 0, "episode": 1, "released": "2018-06-01T00:00:00.000Z"},
    ],
}

CINEMETA = {
    "id": "com.linvo.cinemeta", "version": "3.0.13", "name": "Cinemeta Test", "description": "Nachbau",
    "types": ["movie", "series"], "idPrefixes": ["tt"],
    "resources": ["catalog", {"name": "meta", "types": ["movie", "series"], "idPrefixes": ["tt"]}],
    "catalogs": [
        {"type": "movie", "id": "top", "name": "Popular", "extra": [{"name": "genre", "options": GENRES}, {"name": "search"}, {"name": "skip"}]},
        {"type": "series", "id": "top", "name": "Popular", "extra": [{"name": "genre", "options": ["Drama"]}, {"name": "search"}, {"name": "skip"}]},
        {"type": "movie", "id": "year", "name": "New", "extra": [{"name": "genre", "isRequired": True, "options": ["2026"]}]},
        {"type": "movie", "id": "leer", "name": "Leer"},
        {"type": "series", "id": "last-videos", "name": "Last videos", "extra": [{"name": "lastVideosIds", "isRequired": True}]},
    ],
}

STREAMS = {
    "id": "org.test.streams", "version": "1.0.0", "name": "Stream-Test", "types": ["movie", "series"], "idPrefixes": ["tt"],
    "resources": ["stream"], "catalogs": [], "behaviorHints": {"configurable": True},
}
ZWEIT = {
    "id": "org.test.zweit", "version": "0.1.0", "name": "Zweit", "types": ["movie", "series"],
    "resources": [{"name": "stream", "types": ["series"], "idPrefixes": ["tt100"]}, {"name": "meta", "types": ["series"], "idPrefixes": ["tt100"]}],
    "catalogs": [],
}
KAPUTT = {"id": "org.test.kaputt", "version": "1.0.0", "name": "Kaputt", "types": ["movie", "series"], "resources": ["stream"], "catalogs": []}
EINRICHTEN = {"id": "org.test.cfg", "version": "1.0.0", "name": "Muss eingerichtet werden", "types": ["movie"], "resources": ["stream"],
              "catalogs": [], "behaviorHints": {"configurable": True, "configurationRequired": True}}
SUBS = {"id": "org.test.subs", "version": "1.0.0", "name": "Untertitel-Test", "types": ["movie", "series"], "idPrefixes": ["tt"],
        "resources": ["subtitles"], "catalogs": []}

PLUGINS = {
    "name": "Test-Plugins", "version": "1.0.0", "description": "Nachbau eines Nuvio-Repositorys",
    "scrapers": [
        {"id": "alpha", "name": "Alpha", "version": "1.0.0", "filename": "alpha.js", "supportedTypes": ["movie", "tv"], "enabled": True},
        {"id": "beta", "name": "Beta", "version": "1.1.0", "filename": "beta.js", "supportedTypes": ["movie"], "enabled": True},
        {"id": "fehler", "name": "Fehler", "version": "0.1.0", "filename": "fehler.js", "supportedTypes": ["movie", "tv"]},
        {"id": "aus", "name": "Aus", "version": "0.1.0", "filename": "aus.js", "supportedTypes": ["movie"], "enabled": False},
        {"id": "fehlt", "name": "Fehlt", "version": "0.1.0", "filename": "gibtsnicht.js", "supportedTypes": ["movie"]},
    ],
}

# Scraper wie in Nuvio-Repositories: CommonJS, getStreams(tmdbId, mediaType, season, episode).
ALPHA_JS = r"""
const cheerio = require('cheerio');
const BASE = '{{BASE}}';

async function getStreams(tmdbId, mediaType, season, episode) {
  const path = mediaType === 'movie' ? '/site/film/' + tmdbId : '/site/serie/' + tmdbId + '/' + season + '/' + episode;
  const res = await fetch(BASE + path, { headers: { 'X-Test': 'ja', 'Accept-Encoding': 'x-uzai-test' } });
  if (!res.ok) { console.error('Seite nicht geladen', res.status); return []; }
  const $ = cheerio.load(await res.text());
  const out = [];
  $('div.quelle').each(function (i, el) {
    const a = $(this).find('a.link');
    out.push({
      name: 'Alpha',
      title: $(el).find('h3').text() + ' (' + SCRAPER_ID + ')',
      url: new URL(a.attr('href'), BASE).href,
      quality: $(el).attr('data-q'),
      size: $(el).find('.groesse').text(),
      headers: { Referer: BASE + '/site/' },
    });
  });
  return out;
}
module.exports = { getStreams };
"""

BETA_JS = r"""
var BASE = '{{BASE}}';
function getStreams(tmdbId, mediaType) {
  var C = require('crypto-js');
  return fetch(BASE + '/site/api', { method: 'POST', body: JSON.stringify({ id: tmdbId, typ: mediaType }), headers: { 'Content-Type': 'application/json' } })
    .then(function (r) { return r.json(); })
    .then(function (j) {
      if (!j) return [];
      var sig = C.HmacSHA256(j.payload, 'geheim').toString();
      if (sig !== j.sig) throw new Error('Signatur falsch');
      var links = JSON.parse(C.enc.Base64.parse(j.payload).toString(C.enc.Utf8));
      var roundtrip = C.AES.decrypt(C.AES.encrypt('ok', 'pw').toString(), 'pw').toString(C.enc.Utf8);
      return links.map(function (l) {
        return { name: 'Beta ' + roundtrip, title: l.t, url: l.u, quality: l.q, size: l.s, infoHash: l.h };
      });
    });
}
module.exports.getStreams = getStreams;
"""

FEHLER_JS = r"""
async function getStreams() { throw new Error('Absichtlich kaputt'); }
module.exports = { getStreams };
"""

AUS_JS = r"""
module.exports = { getStreams: async () => [{ name: 'Aus', url: '{{BASE}}/v/aus.mkv' }] };
"""

FILM_HTML = """<!doctype html><html><head><title>Film {id}</title></head><body>
<div class="liste">
 <div class="quelle" data-q="1080p"><h3>Film {id} &amp; mehr</h3><a class="link" href="/v/{id}-1080.m3u8">ansehen</a><span class="groesse">2.1 GB</span></div>
 <div class="quelle" data-q="720p"><h3>Film {id} klein</h3><a class="link" href="/v/{id}-720.m3u8">ansehen</a><span class="groesse">900 MB</span></div>
</div></body></html>"""


def stream_list(vid):
    tag = vid.replace(":", "-")
    return [
        {"name": "Stream-Test\n4K", "title": "Film.2160p.WEB-DL.DV.HEVC\n💾 18.4 GB", "url": BASE + "/v/%s-2160.mkv" % tag,
         "behaviorHints": {"bingeGroup": "test-2160", "proxyHeaders": {"request": {"Referer": BASE + "/", "User-Agent": "TestUA/1"}}}},
        {"name": "[RD+] Stream-Test\n720p", "title": "Film.720p.WEBRip\n💾 1.2 GB", "url": BASE + "/v/%s-720rd.mkv" % tag,
         "behaviorHints": {"bingeGroup": "test-720rd"}},
        {"name": "Stream-Test\n1080p", "description": "Film 1080p BluRay x264 · 💾 8.5 GB", "url": BASE + "/v/%s-1080.mkv" % tag,
         "subtitles": [{"id": "s1", "url": BASE + "/sub/inline.srt", "lang": "ger"}], "behaviorHints": {"bingeGroup": "test-1080"}},
        {"name": "Torrent\n1080p", "title": "Film.1080p 💾 4.0 GB", "infoHash": "0123456789abcdef0123456789abcdef01234567", "fileIdx": 0},
        {"name": "Torrent\n4K", "title": "Film.2160p", "infoHash": "fedcba9876543210fedcba9876543210fedcba98"},
        {"name": "Trailer", "ytId": "dQw4"},
    ]


def person_png(name):
    """Porträt 60 × 90 im Hochformat: Farbe aus dem Namen, oben hell (Gesicht), unten dunkel."""
    h = int(hashlib.md5(name.encode()).hexdigest()[:6], 16)
    r, g, b = 80 + h % 150, 80 + (h >> 8) % 150, 80 + (h >> 16) % 150
    w, ht = 60, 90
    rows = b""
    for y in range(ht):
        row = bytearray([0])
        for x in range(w):
            f = 1.0 - y / ht * 0.7
            if (x - 30) ** 2 + (y - 32) ** 2 < 15 ** 2:   # heller Kopf oben in der Mitte
                f = 1.35
            row += bytes([min(255, int(c * f)) for c in (r, g, b)])
        rows += bytes(row)
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, ht, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def tmdb_credits(kind, tid):
    if kind == "movie" and tid == "702":
        return {"id": 702, "cast": [{"name": "Keanu R.", "character": "Neo", "profile_path": "/keanu-tmdb.jpg"}],
                "crew": [{"name": "Wachowski", "job": "Director", "profile_path": "/wachowski.jpg"}]}
    if kind == "tv" and tid == "1399":
        return {"id": 1399, "cast": [{"name": "Ada Muster", "profile_path": "/ada-tmdb.jpg", "roles": [{"character": "Kapitänin"}]}], "crew": []}
    return None


def find_tmdb(imdb):
    if imdb == "tt001":
        return {"movie_results": [{"id": 603, "title": "Matrix (deutsch)", "overview": "Deutsche Beschreibung."}], "tv_results": []}
    if imdb == "tt002":
        return {"movie_results": [{"id": 702, "title": "Zweiter Film DE", "overview": ""}], "tv_results": []}
    if imdb == "tt100":
        return {"movie_results": [], "tv_results": [{"id": 1399, "name": "Testserie DE", "overview": "Serie auf Deutsch."}]}
    return {"movie_results": [], "tv_results": []}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, data=None, ctype="application/json", raw=None):
        body = raw if raw is not None else (b"" if data is None else json.dumps(data).encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        u = urlparse(self.path)
        LOG.append({"m": "POST", "p": u.path, "q": u.query, "h": {k.lower(): v for k, v in self.headers.items()}, "b": body})
        if u.path == "/site/api":
            try:
                req = json.loads(body)
            except Exception:
                return self._send(400, {"err": "kein JSON"})
            links = [{"t": "Beta %s" % req.get("id"), "u": BASE + "/v/beta-%s.mp4" % req.get("id"), "q": "4K", "s": "12 GB"},
                     {"t": "Beta P2P", "u": "magnet:?xt=urn:btih:abc", "q": "1080p", "s": "3 GB", "h": "abc"}]
            payload = base64.b64encode(json.dumps(links).encode()).decode()
            sig = hmac.new(b"geheim", payload.encode(), hashlib.sha256).hexdigest()
            return self._send(200, {"payload": payload, "sig": sig})
        self._send(404, {"err": "nicht gefunden"})

    def do_GET(self):
        u = urlparse(self.path)
        p = unquote(u.path)
        LOG.append({"m": "GET", "p": u.path, "q": u.query, "h": {k.lower(): v for k, v in self.headers.items()}})
        if p == "/__log":
            return self._send(200, LOG)
        if p == "/__clear":
            LOG.clear()
            return self._send(200, {"ok": True})
        parts = p.strip("/").split("/")
        root = parts[0] if parts else ""
        if root == "cinemeta":
            return self.cinemeta(parts[1:])
        if root == "streams":
            if parts[1:] == ["manifest.json"]:
                return self._send(200, STREAMS)
            if len(parts) == 4 and parts[1] == "stream":
                time.sleep(0.4)
                return self._send(200, {"streams": stream_list(parts[3][:-5])})
        if root == "zweit":
            if parts[1:] == ["manifest.json"]:
                return self._send(200, ZWEIT)
            if len(parts) == 4 and parts[1] == "stream":
                return self._send(200, {"streams": []})
            if len(parts) == 4 and parts[1] == "meta":
                vids = [dict(v) for v in SERIES_META["videos"]]
                for v in vids:
                    v["streams"] = [{"name": "Zweit inline", "title": "inline 480p", "url": BASE + "/v/inline-%s.mp4" % v["id"].replace(":", "-")}]
                # Personen mit Bild (TMDB-Form), die Cinemeta für diese Serie nicht hat.
                cc = [{"name": "Ada Muster", "character": "Kommissarin", "profile_path": "/ada.jpg"}]
                return self._send(200, {"meta": {"id": "tt100", "type": "series", "name": "Testserie", "videos": vids, "credits_cast": cc}})
        if root == "kaputt":
            if parts[1:] == ["manifest.json"]:
                return self._send(200, KAPUTT)
            return self._send(500, None, raw=b"Interner Fehler", ctype="text/plain")
        if root == "einrichten" and parts[1:] == ["manifest.json"]:
            return self._send(200, EINRICHTEN)
        if root == "subs":
            if parts[1:] == ["manifest.json"]:
                return self._send(200, SUBS)
            if len(parts) == 4 and parts[1] == "subtitles":
                return self._send(200, {"subtitles": [
                    {"id": "os-1", "url": BASE + "/sub/de.srt", "lang": "ger"},
                    {"id": "os-2", "url": BASE + "/sub/en.srt", "lang": "eng"},
                    {"id": "os-3", "url": BASE + "/sub/de.srt", "lang": "ger"},
                ]})
        if root == "plugins":
            name = parts[1] if len(parts) > 1 else ""
            if name == "manifest.json":
                return self._send(200, PLUGINS)
            js = {"alpha.js": ALPHA_JS, "beta.js": BETA_JS, "fehler.js": FEHLER_JS, "aus.js": AUS_JS}.get(name)
            if js:
                return self._send(200, raw=js.replace("{{BASE}}", BASE).encode(), ctype="application/javascript")
        if root == "cloudstream" and parts[1:] == ["repo.json"]:
            return self._send(200, {"name": "CS", "manifestVersion": 1, "pluginLists": [BASE + "/cloudstream/plugins.json"]})
        if root == "site":
            if self.headers.get("X-Test") != "ja":
                return self._send(403, None, raw=b"ohne Kopfzeile kein Zugang", ctype="text/plain")
            if len(parts) >= 3 and parts[1] in ("film", "serie"):
                key = "-".join(parts[2:])
                return self._send(200, raw=FILM_HTML.replace("{id}", key).encode(), ctype="text/html; charset=utf-8")
        if root == "img" and len(parts) == 2 and parts[1].startswith("person-") and parts[1].endswith(".png"):
            return self._send(200, raw=person_png(parts[1][7:-4]), ctype="image/png")
        if root == "tmdb" and len(parts) == 5 and parts[4] in ("credits", "aggregate_credits"):
            if parse_qs(u.query).get("api_key", [""])[0] != "testkey":
                return self._send(401, {"status_message": "Invalid API key"})
            cr = tmdb_credits(parts[2], parts[3])
            return self._send(200, cr) if cr else self._send(404, {"status_message": "not found"})
        if root == "tmdb" and len(parts) == 4 and parts[2] == "find":
            q = parse_qs(u.query)
            if q.get("api_key", [""])[0] != "testkey":
                return self._send(401, {"status_message": "Invalid API key"})
            return self._send(200, find_tmdb(parts[3]))
        self._send(404, {"err": "nicht gefunden", "path": p})

    def cinemeta(self, rest):
        if rest == ["manifest.json"]:
            return self._send(200, CINEMETA)
        if len(rest) >= 3 and rest[0] == "catalog":
            typ, cid = rest[1], rest[2]
            extra = {}
            if len(rest) == 4:
                cid = rest[2]
                for kv in rest[3][:-5].split("&"):
                    if "=" in kv:
                        k, v = kv.split("=", 1)
                        extra[k] = v
            elif cid.endswith(".json"):
                cid = cid[:-5]
            if cid == "leer":
                return self._send(200, {"metas": []})
            items = MOVIES if typ == "movie" else [{k: SERIES_META[k] for k in ("id", "type", "name", "poster", "background", "logo", "releaseInfo", "imdbRating", "genre")}]
            if "search" in extra:
                s = extra["search"].lower()
                items = [m for m in items if s in m["name"].lower()]
            if "genre" in extra:
                items = [m for m in items if extra["genre"] in m.get("genres", m.get("genre", []))]
            if "skip" in extra:
                items = items[:1]
            return self._send(200, {"metas": items})
        if len(rest) == 3 and rest[0] == "meta":
            mid = rest[2][:-5]
            if rest[1] == "series" and mid == "tt100":
                return self._send(200, {"meta": SERIES_META})
            for m in MOVIES:
                if m["id"] == mid:
                    full = dict(m)
                    full.update({"runtime": "136 min", "cast": ["Keanu R."], "director": ["Wachowski"], "released": m["year"] + "-03-31T00:00:00.000Z"})
                    if mid == "tt001":
                        # Wie Cinemeta: Bilder in app_extras.cast (volle Adresse) und credits_cast (TMDB-Pfad).
                        full["cast"] = ["Keanu R.", "Carrie-Anne M."]
                        full["app_extras"] = {"cast": [{"name": "Keanu R.", "character": "Neo", "photo": BASE + "/img/person-keanu.png"}],
                                              "directors": [{"name": "Wachowski", "photo": None}]}
                        full["credits_cast"] = [{"name": "Keanu R.", "character": "Neo", "profile_path": "/keanu.jpg"},
                                                {"name": "Carrie-Anne M.", "character": "Trinity", "profile_path": "/carrie.jpg"},
                                                {"name": "Laurence F.", "character": "Morpheus", "profile_path": None}]
                    return self._send(200, {"meta": full})
            return self._send(200, {"meta": None})
        self._send(404, {"err": "nicht gefunden"})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
