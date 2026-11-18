#!/usr/bin/env python3
"""Erzeugt die Tabelle der CEF-C-Schnittstelle für den Browser-Kern (tests/fixtures/cef_api_<Fassung>.json).

Der Browser-Kern (helper/uzai-browser-kern.cs) spricht Chromiums CEF über dessen C-Schnittstelle: Strukturen aus
Funktionszeigern, deren Reihenfolge CEF aus den C++-Kopfdateien ableitet (tools/make_capi_header.py im CEF-Quell-
baum). Dieses Werkzeug liest dieselben Kopfdateien (nur lesen, nichts davon wird ausgeführt) und schreibt für eine
feste API-Fassung (CEF_API_VERSION) auf:
  - je Klasse die Reihenfolge der Funktionszeiger (unversionierte Methoden in Erklärreihenfolge, danach versionierte
    nach ihrer „added“-Fassung; entfernte bleiben als Platzhalter) und daraus den Versatz jedes Zeigers,
  - die Layouts der von Hand geschriebenen C-Strukturen (cef_settings_t …) aus einem Layout-Auszug von clang
    (-fdump-record-layouts-complete, Ziel x86_64-pc-windows-msvc),
  - den Windows-API-Hash der Fassung aus cef_api_versions.json.
tests/browser_kern_cs.ps1 prüft damit, dass die C#-Strukturen des Kerns Bit für Bit passen.

Aufruf:
    python3 -I tools/cef_api_tabelle.py <cef-quellbaum> <layout.txt> <api-fassung> <ausgabe.json>
"""
import json
import os
import re
import subprocess
import sys

# Klassen, die der Kern braucht (C++-Name → wir rechnen den C-Namen selbst aus).
KLASSEN = [
    "CefApp", "CefBrowserProcessHandler", "CefClient", "CefLifeSpanHandler", "CefLoadHandler", "CefDisplayHandler",
    "CefRequestHandler", "CefResourceRequestHandler", "CefPermissionHandler", "CefDownloadHandler", "CefJSDialogHandler",
    "CefDialogHandler", "CefContextMenuHandler", "CefCommandHandler", "CefKeyboardHandler", "CefFocusHandler",
    "CefDevToolsMessageObserver", "CefBrowser", "CefBrowserHost", "CefFrame", "CefRequest", "CefRequestContext",
    "CefCallback", "CefAuthCallback", "CefJSDialogCallback", "CefDownloadItem", "CefBeforeDownloadCallback",
    "CefDownloadItemCallback", "CefMediaAccessCallback", "CefPermissionPromptCallback", "CefCommandLine",
    "CefRegistration", "CefTask", "CefValue", "CefMenuModel", "CefUnresponsiveProcessCallback", "CefFileDialogCallback",
    "CefSelectClientCertificateCallback", "CefRunContextMenuCallback", "CefContextMenuParams", "CefSSLInfo",
    "CefX509Certificate", "CefResponse", "CefTaskRunner", "CefNavigationEntry", "CefRequestContextHandler",
    "CefResourceHandler", "CefCookieManager", "CefDictionaryValue", "CefListValue", "CefBinaryValue",
    "CefPreferenceManager",
]
STRUKTUREN = [
    "_cef_base_ref_counted_t", "_cef_string_utf16_t", "_cef_rect_t", "_cef_point_t", "_cef_size_t", "_cef_settings_t",
    "_cef_request_context_settings_t", "_cef_browser_settings_t", "_cef_window_info_t", "_cef_popup_features_t",
    "_cef_version_info_t", "_cef_main_args_t", "_cef_key_event_t", "_cef_mouse_event_t", "_cef_insets_t",
    "_cef_range_t", "_cef_basetime_t", "_cef_media_sink_device_info_t", "_cef_cookie_t", "_cef_time_t",
]
ANNOTATION = re.compile(r"/\*--cef\((.*?)\)--\*/", re.S)
ZIEL_TAG = re.compile(r"<<<<CEF:(\d+)>>>>")


def capi_name(cppname, klasse=False):
    out = ""
    last = ""
    for ch in cppname:
        if out and ch.isalpha() and ch.upper() == ch and last.isalnum() and last.lower() == last:
            out += "_"
        out += ch.lower()
        last = ch
    return out + ("_t" if klasse else "")


def attribs(text):
    d = {}
    for teil in text.replace("\n", " ").split(","):
        teil = teil.strip()
        if not teil:
            continue
        if "=" in teil:
            k, v = teil.split("=", 1)
            d[k.strip()] = v.strip()
        else:
            d[teil] = True
    return d


def fassung(wert):
    if wert is None:
        return None
    if wert == "next":
        return 999998
    if wert == "experimental":
        return 999999
    return int(wert)


def klassen_lesen(include_dir, api):
    """Liest alle include/*.h und liefert {C++-Name: {source, methoden: [...], statisch: [...]}}."""
    out = {}
    for name in sorted(os.listdir(include_dir)):
        if not name.endswith(".h"):
            continue
        with open(os.path.join(include_dir, name), encoding="utf-8") as f:
            text = f.read()
        pos = 0
        while True:
            m = re.search(r"/\*--cef\(([^)]*)\)--\*/\s*class\s+(Cef\w+)\s*:\s*public\s+(?:virtual\s+)?(Cef\w+)\s*\{", text[pos:], re.S)
            if not m:
                break
            start = pos + m.end()
            attr = attribs(m.group(1))
            cname = m.group(2)
            ende = text.find("};", start)
            if ende < 0:
                break
            body = text[start:ende]
            pos = ende + 2
            out[cname] = _methoden(body, attr, api)
            out[cname]["datei"] = name
            out[cname]["eltern"] = m.group(3)
    # Geerbte Methoden stehen in der C-Struktur vor den eigenen (die Elternstruktur ist das Feld „base“).
    for cname in list(out):
        kette = []
        e = out[cname]["eltern"]
        while e in out:
            kette = out[e]["methoden"] + kette
            e = out[e]["eltern"]
        out[cname]["methoden"] = kette + out[cname]["methoden"]
    return out


def _methoden(body, klasse_attr, api):
    """Methoden einer Klasse in C-Reihenfolge (unversioniert zuerst, dann nach added), mit Platzhaltern."""
    roh = []
    statisch = []
    for m in ANNOTATION.finditer(body):
        attr = attribs(m.group(1))
        rest = body[m.end():m.end() + 400].lstrip()
        klammer = rest.find("(")
        if klammer < 0:
            continue
        dm = re.search(r"(\w+)\s*$", rest[:klammer])
        if not dm:
            continue
        name = dm.group(1)
        ist_statisch = rest.startswith("static")
        added = fassung(attr.get("added"))
        removed = fassung(attr.get("removed"))
        eintrag = {"cpp": name, "c": capi_name(name), "added": added, "removed": removed}
        if ist_statisch:
            statisch.append(eintrag)
        else:
            roh.append(eintrag)
    # Reihenfolge wie make_capi_header: unversionierte, dann je added-Fassung aufsteigend.
    gruppen = {0: []}
    for e in roh:
        k = e["added"] or 0
        gruppen.setdefault(k, []).append(e)
    methoden = []
    for k in sorted(gruppen):
        if k > api:
            break
        for e in gruppen[k]:
            if e["removed"] is not None and e["removed"] <= api:
                methoden.append(e["c"] + "_removed")
            else:
                methoden.append(e["c"])
    return {
        "source": "client" if klasse_attr.get("source") == "client" else "library",
        "added": fassung(klasse_attr.get("added")),
        "methoden": methoden,
        "statisch": [e["c"] for e in statisch if (e["added"] or 0) <= api and (e["removed"] is None or e["removed"] > api)],
    }


def layouts_lesen(pfad):
    """Layout-Auszug von clang → {struktur: {size, felder: {name: offset}}} (nur oberste Ebene)."""
    out = {}
    aktuell = None
    tiefe_basis = None
    with open(pfad, encoding="utf-8") as f:
        for zeile in f:
            m = re.match(r"\s*(\d+) \| (struct \S+|[\w:<>()* ,\[\]_]+?)\s*$", zeile.rstrip("\n"))
            if zeile.startswith("*** Dumping"):
                aktuell = None
                continue
            if m and m.group(2).startswith("struct ") and aktuell is None:
                aktuell = m.group(2).split()[1]
                out[aktuell] = {"size": 0, "felder": {}}
                tiefe_basis = len(zeile) - len(zeile.lstrip(" "))
                continue
            if aktuell is None:
                continue
            sm = re.search(r"\[sizeof=(\d+), align=(\d+)\]", zeile)
            if sm and zeile.strip().startswith("|"):
                out[aktuell]["size"] = int(sm.group(1))
                aktuell = None
                continue
            fm = re.match(r"\s*(\d+) \|(\s+)(.+?)\s+(\w+)\s*$", zeile.rstrip("\n"))
            if fm:
                einrueckung = len(fm.group(2))
                # Nur direkte Felder (eine Stufe tiefer als der Strukturkopf), keine Felder eingebetteter Strukturen.
                if einrueckung == 3:
                    out[aktuell]["felder"][fm.group(4)] = int(fm.group(1))
    return out


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(2)
    quelle, layout, api, ziel = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    include_dir = os.path.join(quelle, "include")
    klassen = klassen_lesen(include_dir, api)
    fehlend = [k for k in KLASSEN if k not in klassen]
    if fehlend:
        print("Klassen nicht gefunden: %s" % fehlend)
        sys.exit(1)
    with open(os.path.join(quelle, "cef_api_versions.json"), encoding="utf-8") as f:
        versionen = json.load(f)
    try:
        commit = subprocess.run(["git", "-C", quelle, "log", "-1", "--format=%H %cs"], capture_output=True, text=True, check=False).stdout.strip()
    except OSError:
        commit = ""
    strukturen = layouts_lesen(layout)
    fehlend = [s for s in STRUKTUREN if s not in strukturen or strukturen[s]["size"] == 0]
    if fehlend:
        print("Strukturen nicht im Layout: %s" % fehlend)
        sys.exit(1)
    aus = {
        "api": api,
        "hash_windows": versionen["hashes"][str(api)]["windows"],
        "api_min": int(versionen["min"]),
        "api_last": int(versionen["last"]),
        "quelle": "CEF %s" % commit,
        "zeigergroesse": 8,
        "basis": 40,
        "klassen": {},
        "strukturen": {s.lstrip("_"): strukturen[s] for s in STRUKTUREN},
    }
    for k in KLASSEN:
        d = klassen[k]
        aus["klassen"][capi_name(k, True)] = {
            "cpp": k, "source": d["source"], "methoden": d["methoden"], "statisch": d["statisch"],
            "versatz": {m: 40 + 8 * i for i, m in enumerate(d["methoden"])},
            "size": 40 + 8 * len(d["methoden"]),
        }
    with open(ziel, "w", encoding="utf-8") as f:
        json.dump(aus, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    print("ok: %d Klassen, %d Strukturen → %s" % (len(aus["klassen"]), len(aus["strukturen"]), ziel))


if __name__ == "__main__":
    main()
