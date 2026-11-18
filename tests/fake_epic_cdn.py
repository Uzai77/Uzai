#!/usr/bin/env python3
"""Nachgebaute Epic-Dienste und Download-Server für Uzais eigenen Epic-Installer
(tests/net_epic_install.gd), dazu Beispieldateien im echten Format für tests/logic_epic_install.gd.

Schreibt Manifeste (binär nach Epics Aufbau, Fassung 18 und 22, gepackt oder nicht, und das alte
JSON mit „Blob“-Zahlen) und Chunks (Kopf Fassung 3, zlib oder roh) – unabhängig von Uzais Leser.

Server (Uzai mit UZAI_EPIC_API=http://127.0.0.1:<port> und UZAI_TEST_LOOPBACK=1):
- POST /account/account/api/oauth/token  (Code „0123…cdef“ → a1/r1, Erneuern r1 → a2/r2 …)
- GET  /launcher/launcher/api/public/assets/v2/platform/Windows/namespace/ns-kinglet/catalogItem/
       item-kinglet/app/Kinglet/label/Live  (Bearer) → Manifest-Adressen: erst ein kaputter Server
       (/cdnbad, 503), dann der richtige (/cdn), mit queryParams
- GET  /cdn/<build>/Kinglet.manifest, /cdn/<build>/ChunksV4/… (ohne Anmeldung)
- /__set?build=2|corrupt=<n>|corrupt_all=1|slow=<ms>|evilcdn=1|badhash=1|evil=<name>|down=1
  /__log (alle Anfragen, mit Kopf „Authorization“), /__files (Name → SHA-1 der aktuellen Fassung),
  POST /__reset (Protokoll und Schalter zurück)
Aufruf: python3 fake_epic_cdn.py <port>    bzw.    python3 fake_epic_cdn.py --fixtures <ordner>
"""
import hashlib
import json
import os
import random
import struct
import sys
import time
import zlib
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

MAGIC = 0x44BEC00C
CHUNK_MAGIC = 0xB1FE3AA2
GOOD = "0123456789abcdef0123456789abcdef"


# --- Schreiber im Epic-Format ------------------------------------------------------------------

def fstr(s):
    if not s:
        return struct.pack("<i", 0)
    try:
        b = s.encode("ascii")
        return struct.pack("<i", len(b) + 1) + b + b"\0"
    except UnicodeEncodeError:
        u = s.encode("utf-16-le")
        return struct.pack("<i", -(len(u) // 2 + 1)) + u + b"\0\0"


def guid_hex(g):
    return "%08X%08X%08X%08X" % g


def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


class Chunk:
    def __init__(self, rnd, data, window, compress=True):
        self.guid = tuple(rnd.getrandbits(32) for _ in range(4))
        self.hash = rnd.getrandbits(64)
        self.window = window
        self.data = data + b"\0" * (window - len(data))
        self.sha = hashlib.sha1(self.data).digest()
        self.group = zlib.crc32(struct.pack("<IIII", *self.guid)) % 100
        self.compress = compress
        self.raw = self.serialise()

    def serialise(self, guid=None, stored=None, ver=3):
        body = zlib.compress(self.data) if self.compress else self.data
        st = (1 if self.compress else 0) if stored is None else stored
        head_size = {2: 62, 3: 66, 4: 98}[ver]
        h = struct.pack("<IIII", CHUNK_MAGIC, ver, head_size, len(body))
        h += struct.pack("<IIII", *(guid or self.guid)) + struct.pack("<Q", self.hash) + struct.pack("B", st)
        h += self.sha + struct.pack("B", 2)
        if ver >= 3:
            h += struct.pack("<I", self.window)
        if ver >= 4:
            h += b"\0" * 32
        return h + body

    def path(self, feature):
        if feature >= 22:
            return "ChunksV5/plain/%02d/%s_%s.chunk" % (self.group, b64u(struct.pack("<Q", self.hash)), b64u(struct.pack("<IIII", *self.guid)))
        d = "ChunksV4" if feature >= 15 else ("ChunksV3" if feature >= 6 else "ChunksV2")
        return "%s/%02d/%016X_%s.chunk" % (d, self.group, self.hash, guid_hex(self.guid))


def make_build(seed, files, window=65536, compress_every=1):
    """files: [(name, bytes)] → (chunks, file_entries). Die Dateien liegen hintereinander im
    Datenstrom; jeder Chunk ist ein Fenster daraus (das letzte mit Nullen aufgefüllt)."""
    rnd = random.Random(seed)
    stream = b"".join(d for _, d in files)
    chunks = []
    for i in range(0, max(1, len(stream)), window):
        chunks.append(Chunk(rnd, stream[i:i + window], window, compress=(i // window) % compress_every == 0 if compress_every else False))
    entries = []
    pos = 0
    for name, data in files:
        parts = []
        left = len(data)
        p = pos
        while left > 0:
            ci = p // window
            off = p % window
            n = min(left, window - off)
            parts.append((chunks[ci].guid, off, n))
            p += n
            left -= n
        entries.append({"name": name, "sha": hashlib.sha1(data).digest(), "parts": parts, "symlink": ""})
        pos += len(data)
    return chunks, entries


def binary_manifest(app, build, exe, args, chunks, entries, feature=18, compress=True, stored_extra=0, bad_sha=False,
                    count_override=None, part_size=28):
    meta = struct.pack("<B", 2) + struct.pack("<I", feature) + struct.pack("B", 0) + struct.pack("<I", 0)
    meta += fstr(app) + fstr(build) + fstr(exe) + fstr(args)
    meta += struct.pack("<I", 1) + fstr("prereq-1") + fstr("Visual C++") + fstr("Installers/vc.exe") + fstr("/quiet")
    meta += fstr("build-id") + fstr("") + fstr("")
    meta = struct.pack("<I", len(meta) + 4) + meta
    n = len(chunks)
    cdl = b"".join(struct.pack("<IIII", *c.guid) for c in chunks)
    cdl += b"".join(struct.pack("<Q", c.hash) for c in chunks)
    cdl += b"".join(c.sha for c in chunks)
    cdl += b"".join(struct.pack("B", c.group) for c in chunks)
    cdl += b"".join(struct.pack("<I", c.window) for c in chunks)
    cdl += b"".join(struct.pack("<q", len(c.raw)) for c in chunks)
    if feature >= 22:
        cdl += b"\0" * (16 * n)
        cdl += b"".join(struct.pack("<I", len(c.raw)) for c in chunks)
        cdl += b"\0" * (16 * n)
    cdl = struct.pack("B", 0) + struct.pack("<I", n if count_override is None else count_override) + cdl
    cdl = struct.pack("<I", len(cdl) + 4) + cdl
    fml = b"".join(fstr(e["name"]) for e in entries)
    fml += b"".join(fstr(e["symlink"]) for e in entries)
    fml += b"".join(e["sha"] for e in entries)
    fml += b"".join(struct.pack("B", 0) for e in entries)
    fml += b"".join(struct.pack("<I", 0) for e in entries)
    for e in entries:
        fml += struct.pack("<I", len(e["parts"]))
        for g, off, size in e["parts"]:
            fml += struct.pack("<I", part_size) + struct.pack("<IIII", *g) + struct.pack("<II", off, size) + b"\0" * (part_size - 28)
    fml += b"".join(struct.pack("<I", 0) for e in entries)
    fml += b"".join(fstr("application/octet-stream") for e in entries)
    fml += b"".join(hashlib.sha256(e["sha"]).digest() for e in entries)
    fml = struct.pack("B", 2) + struct.pack("<I", len(entries)) + fml
    fml = struct.pack("<I", len(fml) + 4) + fml
    cf = struct.pack("B", 0) + struct.pack("<I", 1) + fstr("Schluessel") + fstr("Wert")
    cf = struct.pack("<I", len(cf) + 4) + cf
    body = meta + cdl + fml + cf
    sha = hashlib.sha1(body).digest()
    if bad_sha:
        sha = bytes(20 - 1) + b"\x01"
    data = zlib.compress(body) if compress else body
    stored = (1 if compress else 0) | stored_extra
    head = struct.pack("<IIII", MAGIC, 73 if feature >= 22 else 41, len(body), len(data)) + sha + struct.pack("B", stored) + struct.pack("<I", feature)
    if feature >= 22:
        head += b"\0" * 32
    return head + data


def blob(num, nbytes):
    return "".join("%03d" % ((num >> (8 * i)) & 0xFF) for i in range(nbytes))


def blob_bytes(b):
    return "".join("%03d" % x for x in b)


def json_manifest(app, build, exe, args, chunks, entries):
    d = {"ManifestFileVersion": blob(13, 4), "bIsFileData": False, "AppID": blob(0, 4), "AppNameString": app,
         "BuildVersionString": build, "LaunchExeString": exe, "LaunchCommand": args, "PrereqIds": [], "PrereqName": "",
         "PrereqPath": "", "PrereqArgs": "", "FileManifestList": [], "ChunkHashList": {}, "ChunkShaList": {},
         "DataGroupList": {}, "ChunkFilesizeList": {}, "CustomFields": {}}
    for e in entries:
        d["FileManifestList"].append({"Filename": e["name"], "FileHash": blob_bytes(e["sha"]), "FileChunkParts": [
            {"Guid": guid_hex(g), "Offset": blob(off, 4), "Size": blob(size, 4)} for g, off, size in e["parts"]]})
    for c in chunks:
        k = guid_hex(c.guid)
        d["ChunkHashList"][k] = blob(c.hash, 8)
        d["ChunkShaList"][k] = c.sha.hex().upper()
        d["DataGroupList"][k] = blob(c.group, 1)
        d["ChunkFilesizeList"][k] = blob(len(c.raw), 8)
    return json.dumps(d, ensure_ascii=False).encode("utf-8")


# --- Spiel für die Netz-Probe ----------------------------------------------------------------

def game_files(build):
    r = random.Random(100 + build)
    exe = bytes(random.Random(5).getrandbits(8) for _ in range(150000))
    pak = bytes(r.getrandbits(8) for _ in range(700000)) if build == 1 else bytes(r.getrandbits(8) for _ in range(760000))
    files = [("Game/Binaries/Win64/Kinglet.exe", exe), ("Game/Content/Paks/data.pak", pak),
             ("Game/Content/Movies/Intro Film.bk2", b"BIK" * 4000), ("Game/Content/Sprache/Übersetzung.txt", "Grüße\n".encode() * 50),
             ("Engine/leer.dat", b"")]
    if build == 1:
        files.append(("Game/readme.txt", b"Alte Fassung\n" * 30))
    else:
        files.append(("Game/neu.txt", b"Neue Fassung\n" * 30))
    return files


BUILDS = {}


def build_of(n):
    if n not in BUILDS:
        files = game_files(n)
        chunks, entries = make_build(n, files, window=65536, compress_every=3)
        man = binary_manifest("Kinglet", "1.0.%d" % n, "Game/Binaries/Win64/Kinglet.exe", "-SaveToUserDir -nosplash", chunks, entries)
        BUILDS[n] = {"files": files, "chunks": {c.path(18): c for c in chunks}, "manifest": man}
    return BUILDS[n]


def evil_manifest(kind):
    """Bösartige Manifeste für die Netz-Probe (mit gültiger Prüfsumme laut Epic)."""
    files = [("ok.txt", b"ok"), ("../ausserhalb.txt", b"boese")] if kind == "dotdot" else [("ok.txt", b"ok"), ("C:/Windows/boese.dll", b"x")]
    chunks, entries = make_build(9, files, window=4096)
    return binary_manifest("Kinglet", "boese", "ok.txt", "", chunks, entries)


# --- Beispieldateien für den Logik-Test -----------------------------------------------------------

def fixtures(out):
    os.makedirs(out, exist_ok=True)
    rnd = random.Random(42)
    data_a = bytes(rnd.getrandbits(8) for _ in range(10000))
    data_b = b"Hallo Welt\n" * 300
    files = [("Spiel/Start.exe", data_a), ("Spiel/Daten/teil.bin", data_b), ("Spiel/Ünïcödé Datei.txt", "Grüße".encode() * 20),
             ("leer.txt", b"")]
    chunks, entries = make_build(1, files, window=4096, compress_every=2)
    info = {"files": {n: hashlib.sha1(d).hexdigest() for n, d in files}, "chunks": [], "app": "Probe", "build": "1.2.3",
            "exe": "Spiel/Start.exe", "args": "-nosplash \"-pfad=C:\\Spiele\" -x"}
    with open(os.path.join(out, "v18.manifest"), "wb") as f:
        f.write(binary_manifest("Probe", "1.2.3", "Spiel/Start.exe", info["args"], chunks, entries))
    with open(os.path.join(out, "v22_roh.manifest"), "wb") as f:
        f.write(binary_manifest("Probe", "1.2.3", "Spiel/Start.exe", "", chunks, entries, feature=22, compress=False))
    os.makedirs(os.path.join(out, "chunks"), exist_ok=True)
    for i, c in enumerate(chunks):
        with open(os.path.join(out, "chunks", "%d.chunk" % i), "wb") as f:
            f.write(c.raw)
        info["chunks"].append({"guid": guid_hex(c.guid), "path18": c.path(18), "path22": c.path(22), "sha": c.sha.hex(), "win": c.window})
    c0 = chunks[0]
    with open(os.path.join(out, "chunk_v4.bin"), "wb") as f:
        f.write(c0.serialise(ver=4))
    with open(os.path.join(out, "chunk_v2.bin"), "wb") as f:
        f.write(c0.serialise(ver=2))
    with open(os.path.join(out, "chunk_verschluesselt.bin"), "wb") as f:
        f.write(c0.serialise(stored=3))
    with open(os.path.join(out, "chunk_falsche_guid.bin"), "wb") as f:
        f.write(c0.serialise(guid=(1, 2, 3, 4)))
    # JSON-Manifest: Fenster immer 1 MiB
    jfiles = [("Alt/spiel.exe", data_a), ("Alt/daten.txt", data_b)]
    jchunks, jentries = make_build(2, jfiles, window=1024 * 1024)
    with open(os.path.join(out, "alt.json.manifest"), "wb") as f:
        f.write(json_manifest("AltesSpiel", "0.9", "Alt/spiel.exe", "-alt", jchunks, jentries))
    with open(os.path.join(out, "alt_chunk.bin"), "wb") as f:
        f.write(jchunks[0].raw)
    info["json"] = {"files": {n: hashlib.sha1(d).hexdigest() for n, d in jfiles}, "chunk": {"guid": guid_hex(jchunks[0].guid),
                    "path": jchunks[0].path(13), "sha": jchunks[0].sha.hex()}}
    # Bösartige Manifeste
    def evil(name, flist, **kw):
        ch, en = make_build(3, flist, window=4096)
        mod = kw.pop("mod", None)
        if mod:
            mod(ch, en)
        with open(os.path.join(out, "boese_%s.manifest" % name), "wb") as f:
            f.write(binary_manifest("Boese", "1", "a.txt", "", ch, en, **kw))
    evil("punktpunkt", [("a.txt", b"a"), ("Spiel/../../raus.txt", b"x")])
    evil("absolut", [("a.txt", b"a"), ("/etc/passwd", b"x")])
    evil("laufwerk", [("a.txt", b"a"), ("C:\\Windows\\system32\\boese.dll", b"x")])
    evil("rueckstrich", [("a.txt", b"a"), ("Spiel\\..\\..\\raus.txt", b"x")])
    evil("datenstrom", [("a.txt", b"a"), ("a.txt:versteckt", b"x")])
    evil("geraet", [("a.txt", b"a"), ("Spiel/CON.txt", b"x")])
    evil("doppelt", [("a.txt", b"a"), ("A.TXT", b"x")])
    evil("datei_als_ordner", [("a.txt", b"a"), ("a.txt/b.txt", b"x")])
    evil("leerer_teil", [("a.txt", b"a"), ("Spiel//b.txt", b"x")])
    evil("punkt_am_ende", [("a.txt", b"a"), ("Spiel./b.txt", b"x")])
    evil("verknuepfung", [("a.txt", b"a"), ("link", b"x")], mod=lambda ch, en: en[1].__setitem__("symlink", "../../Windows"))
    evil("teil_ausserhalb", [("a.txt", b"a" * 100)],
         mod=lambda ch, en: en[0].__setitem__("parts", [(en[0]["parts"][0][0], 4090, 100)]))
    evil("fremde_guid", [("a.txt", b"a" * 100)], mod=lambda ch, en: en[0].__setitem__("parts", [((9, 9, 9, 9), 0, 100)]))
    evil("ohne_pruefsumme", [("a.txt", b"a")], mod=lambda ch, en: en[0].__setitem__("sha", b"\0" * 20))
    evil("verschluesselt", [("a.txt", b"a")], stored_extra=2)
    evil("kopf_pruefsumme", [("a.txt", b"a")], bad_sha=True)
    evil("riesige_anzahl", [("a.txt", b"a")], count_override=0x7FFFFFF0)
    evil("teil_kopf", [("a.txt", b"a")], part_size=20)
    with open(os.path.join(out, "erwartet.json"), "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)


# --- Server ---------------------------------------------------------------------------------

LOG = []
STATE = {}


def reset():
    STATE.clear()
    STATE.update({"build": 1, "corrupt": 0, "corrupt_all": False, "slow": 0, "evilcdn": False, "badhash": False, "evil": "", "down": False})


reset()
TOKENS = {"r1": ("a2", "r2"), "r2": ("a3", "r3"), "r3": ("a4", "r4"), "r4": ("a5", "r5")}
VALID = {"a1", "a2", "a3", "a4", "a5"}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, data=None, ctype="application/json"):
        body = data if isinstance(data, (bytes, bytearray)) else (b"" if data is None else json.dumps(data).encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _log(self):
        u = urlparse(self.path)
        LOG.append({"m": self.command, "p": u.path, "q": u.query, "auth": self.headers.get("Authorization", "")})
        return u

    def do_GET(self):
        if self.path.startswith("/__log"):
            return self._send(200, LOG)
        if self.path.startswith("/__files"):
            b = build_of(int(STATE["build"]))
            return self._send(200, {n: hashlib.sha1(d).hexdigest() for n, d in b["files"]})
        if self.path.startswith("/__set"):
            for k, v in parse_qs(urlparse(self.path).query).items():
                if k in ("build", "corrupt", "slow"):
                    STATE[k] = int(v[0])
                elif k == "evil":
                    STATE[k] = v[0]
                elif k in STATE:
                    STATE[k] = v[0] == "1"
            return self._send(200, STATE)
        u = self._log()
        if STATE["down"]:
            return self._send(503, {"errorCode": "errors.com.epicgames.common.server_error"})
        port = self.server.server_address[1]
        n = int(STATE["build"])
        if u.path.startswith("/cdnbad/"):
            return self._send(503, b"weg", "text/plain")
        if u.path.startswith("/cdn/"):
            rest = u.path[len("/cdn/"):]
            ver, _, sub = rest.partition("/")
            b = build_of(int(ver.lstrip("b") or 1))
            if sub == "Kinglet.manifest":
                if STATE["evil"]:
                    return self._send(200, evil_manifest(STATE["evil"]), "application/octet-stream")
                return self._send(200, b["manifest"], "application/octet-stream")
            c = b["chunks"].get(sub)
            if c is None:
                return self._send(404, b"", "text/plain")
            if STATE["slow"]:
                time.sleep(STATE["slow"] / 1000.0)
            raw = c.raw
            if STATE["corrupt_all"] or STATE["corrupt"] > 0:
                if STATE["corrupt"] > 0:
                    STATE["corrupt"] -= 1
                raw = bytearray(raw)
                raw[-1] ^= 0xFF
                raw = bytes(raw)
            return self._send(200, raw, "application/octet-stream")
        bearer = self.headers.get("Authorization", "")
        if not bearer.startswith("Bearer ") or bearer[7:] not in VALID:
            return self._send(401, {"errorCode": "errors.com.epicgames.common.authentication.token_verification_failed"})
        want = "/launcher/launcher/api/public/assets/v2/platform/Windows/namespace/ns-kinglet/catalogItem/item-kinglet/app/Kinglet/label/Live"
        if u.path == want:
            b = build_of(n)
            man = evil_manifest(STATE["evil"]) if STATE["evil"] else b["manifest"]
            h = hashlib.sha1(man).hexdigest()
            if STATE["badhash"]:
                h = "1" * 40
            host = "https://evil.example.com" if STATE["evilcdn"] else "http://127.0.0.1:%d" % port
            return self._send(200, {"elements": [{"appName": "Kinglet", "labelName": "Live-Windows", "buildVersion": "1.0.%d" % n, "hash": h,
                                                   "useSignedUrl": False, "manifests": [
                                                       {"uri": "%s/cdnbad/b%d/Kinglet.manifest" % (host, n)},
                                                       {"uri": "%s/cdn/b%d/Kinglet.manifest" % (host, n),
                                                        "queryParams": [{"name": "f_token", "value": "abc123"}]}]}]})
        return self._send(404, {"errorCode": "errors.com.epicgames.common.not_found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(n).decode() if n else ""
        if self.path.startswith("/__reset"):
            LOG.clear()
            reset()
            return self._send(200, {})
        u = self._log()
        if u.path != "/account/account/api/oauth/token":
            return self._send(404, {})
        form = parse_qs(raw)
        grant = form.get("grant_type", [""])[0]
        if grant == "authorization_code" and form.get("code", [""])[0] == GOOD:
            return self._send(200, tok("a1", "r1"))
        if grant == "refresh_token" and form.get("refresh_token", [""])[0] in TOKENS:
            a, r = TOKENS[form["refresh_token"][0]]
            return self._send(200, tok(a, r))
        return self._send(400, {"errorCode": "errors.com.epicgames.account.oauth.authorization_code_not_found"})


def tok(a, r):
    return {"access_token": a, "expires_in": 28800, "token_type": "bearer", "refresh_token": r, "refresh_expires": 1987200,
            "account_id": "acc1", "displayName": "Spieler"}


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--fixtures":
        fixtures(sys.argv[2])
    else:
        ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
