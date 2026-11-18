#!/usr/bin/env python3
"""Baut die Filterliste des Uzai-Browsers (assets/browser/filter/filter.gz) aus den Rohlisten von EasyList.

Quellen (github.com/easylist/easylist, Lizenz GPLv3 oder CC BY-SA 3.0, siehe assets/browser/filter/LIZENZ.txt):
    easylist/*.txt, easyprivacy/*.txt, easylist_cookie/*.txt (Teil-Dateien des Repositorys)
Ausgabe: unser kompaktes Format (eine Regel je Zeile, erstes Zeichen = Art; Beschreibung in
helper/uzai-browser-gemeinsam.cs, UzbFilter, und src/core/browser_filter.gd):
    d <domäne>   t <domäne>   p <muster>|<flags>|<seiten>   a <muster>|<flags>|<seiten>
    h <selektor> s <seiten>|<selektor>   e <seiten>|<selektor>
Was wegfällt (bewusst, weil nur Daten erlaubt sind oder es in unserem Blocker nichts tut): Regeln mit Skript-
Anteilen (##+js, #$#, #?#, :-abp-, :has, :matches-css …), Optionen, die wir nicht kennen ($csp, $redirect,
$removeparam, $header, $popup, $genericblock, $elemhide …), reguläre Ausdrücke (/…/), zu lange Zeilen.
Die Liste wird dedupliziert, sortiert und mit gzip gepackt; die SHA-256 der gepackten Datei steht in
src/core/browser_filter.gd und helper/uzai-helper.ps1 (tests prüfen das).

Aufruf:
    python3 -I tools/filter_bauen.py <ordner-mit-easylist-rohlisten> <ausgabe.gz> [--bericht]
"""
import gzip
import hashlib
import os
import re
import sys

TYPEN = {"script": "s", "image": "i", "stylesheet": "c", "xmlhttprequest": "x", "subdocument": "f", "media": "m", "object": "o",
         "font": "F", "ping": "p", "other": "O", "websocket": "O", "beacon": "p"}
IGNORIERT_OPTION = {"~third-party", "~3p", "first-party", "1p", "~first-party", "~1p", "third-party", "3p", "domain", "match-case", "all"}
VERBOTEN_OPTION_PREFIX = ("csp", "redirect", "removeparam", "header", "popup", "genericblock", "generichide", "elemhide", "document",
                          "rewrite", "replace", "urltransform", "permissions", "cookie", "important", "badfilter", "method", "to",
                          "from", "denyallow", "ipaddress", "strict", "inline", "xhr", "webrtc", "doc", "frame", "popunder", "object-subrequest",
                          "ehide", "ghide", "specifichide", "shide", "empty", "mp4", "queryprune", "cname", "noop")
SELEKTOR_VERBOTEN = ("{", "}", ";", "\\", "/", ":-abp-", ":has(", ":has-text", ":matches-css", ":matches-path", ":xpath", ":style(",
                     ":remove(", ":upward(", ":nth-ancestor", ":min-text-length", ":watch-attr", ":matches-attr", ":others", ":if(",
                     ":if-not(", "url(", "expression", ":contains(", ":-moz", ":-webkit", ":not(:has")
SEITE_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{1,251}[a-z0-9]$")
MAX_ZEILE = 500


def seite_ok(d):
    return "." in d and SEITE_RE.match(d) is not None


def netz_regel(zeile):
    """Netzregel → ('p'|'a'|'d'|'t', text) oder None."""
    ausnahme = zeile.startswith("@@")
    if ausnahme:
        zeile = zeile[2:]
    if not zeile or zeile.startswith("/") and zeile.endswith("/") and len(zeile) > 2:
        return None
    muster, _, optionen = zeile.partition("$")
    flags = ""
    seiten = []
    typen_pos = []
    typen_neg = []
    if optionen:
        for o in optionen.split(","):
            o = o.strip()
            if not o:
                continue
            low = o.lower()
            if low in ("third-party", "3p"):
                flags += "3"
            elif low in ("~third-party", "~3p", "first-party", "1p"):
                flags += "1"
            elif low.startswith("domain=") or low.startswith("from="):
                for d in o.split("=", 1)[1].split("|"):
                    d = d.strip().lower()
                    neg = d.startswith("~")
                    if neg:
                        d = d[1:]
                    if seite_ok(d):
                        seiten.append(("~" if neg else "") + d)
            elif low in TYPEN:
                typen_pos.append(TYPEN[low])
            elif low.startswith("~") and low[1:] in TYPEN:
                typen_neg.append(TYPEN[low[1:]])
            elif low in IGNORIERT_OPTION:
                continue
            else:
                return None   # unbekannte oder verbotene Option: Regel fällt weg
    if typen_pos and typen_neg:
        return None
    if typen_pos:
        flags += "".join(sorted(set(typen_pos)))
    elif typen_neg:
        flags += "~" + "".join(sorted(set(typen_neg)))
    if "3" in flags and "1" in flags:
        return None
    if any(c <= " " or c > "~" for c in muster):
        return None
    if len(muster) < 2 or len(muster) > 300:
        return None
    # Reine Domänenregel ||domain^ ohne Pfad: als Domäne (schnell), mit third-party als t.
    m = re.match(r"^\|\|([a-z0-9][a-z0-9._-]*[a-z0-9])\^$", muster.lower())
    if m and not seiten and not ausnahme and flags in ("", "3") and seite_ok(m.group(1)):
        return ("t" if flags == "3" else "d", m.group(1))
    kern = muster.lstrip("|").rstrip("|").strip("*")
    if len(re.sub(r"[^a-z0-9]", "", kern.lower())) < 3:
        return None   # zu allgemein (z. B. „/*“) – unser Index braucht etwas Greifbares
    text = muster + "|" + flags + "|" + ",".join(seiten)
    return ("a" if ausnahme else "p", text)


def kosmetik_regel(zeile):
    """Kosmetikregel → ('h'|'s'|'e', text) oder None."""
    for trenner, art in (("#@#", "e"), ("##", "h")):
        k = zeile.find(trenner)
        if k < 0:
            continue
        seiten_roh, selektor = zeile[:k], zeile[k + len(trenner):]
        if "#?#" in zeile or "#$#" in zeile or "#%#" in zeile or "##+js" in zeile or "#@#+js" in zeile:
            return None
        selektor = selektor.strip()
        if len(selektor) < 2 or len(selektor) > 300:
            return None
        if any(v in selektor for v in SELEKTOR_VERBOTEN):
            return None
        if any(c < " " or c > "~" for c in selektor):
            return None
        seiten = []
        if seiten_roh:
            for d in seiten_roh.split(","):
                d = d.strip().lower()
                neg = d.startswith("~")
                if neg:
                    d = d[1:]
                if not seite_ok(d):
                    return None
                seiten.append(("~" if neg else "") + d)
        if art == "e":
            if not seiten:
                return None
            return ("e", ",".join(seiten) + "|" + selektor)
        if not seiten:
            return ("h", selektor)
        if all(s.startswith("~") for s in seiten):
            return None   # „überall außer …“ – zu grob für unsere Form
        return ("s", ",".join(s for s in seiten if not s.startswith("~")) + "|" + selektor)
    return None


def bauen(ordner, ausgabe, bericht=False):
    regeln = set()
    zaehler = {"d": 0, "t": 0, "p": 0, "a": 0, "h": 0, "s": 0, "e": 0, "weg": 0}
    dateien = 0
    for wurzel, _dirs, namen in os.walk(ordner):
        for name in sorted(namen):
            if not name.endswith(".txt"):
                continue
            dateien += 1
            with open(os.path.join(wurzel, name), encoding="utf-8", errors="replace") as f:
                for zeile in f:
                    zeile = zeile.strip()
                    if not zeile or zeile.startswith("!") or zeile.startswith("[") or len(zeile) > MAX_ZEILE:
                        continue
                    r = kosmetik_regel(zeile) if ("##" in zeile or "#@#" in zeile) else netz_regel(zeile)
                    # Allgemeine Kosmetik der Cookie-Liste fällt weg: riesig, viele Fehltreffer, und Banner erledigt der
                    # Cookie-Knopf im Skript; die seitenspezifischen Regeln und die Netzsperren bleiben.
                    if r is not None and r[0] == "h" and "cookie" in wurzel.lower():
                        r = None
                    if r is None:
                        zaehler["weg"] += 1
                        continue
                    regeln.add(r[0] + " " + r[1])
                    zaehler[r[0]] += 1
    zeilen = sorted(regeln)
    daten = ("\n".join(zeilen) + "\n").encode("utf-8")
    os.makedirs(os.path.dirname(ausgabe) or ".", exist_ok=True)
    with open(ausgabe, "wb") as f:
        with gzip.GzipFile(fileobj=f, mode="wb", mtime=0, compresslevel=9) as g:
            g.write(daten)
    sha = hashlib.sha256(open(ausgabe, "rb").read()).hexdigest()
    if bericht:
        print("Dateien: %d, Regeln: %d (%s), verworfen: %d" % (dateien, len(zeilen), ", ".join("%s %d" % (k, zaehler[k]) for k in "dtpahse"), zaehler["weg"]))
        print("roh %d KB, gepackt %d KB" % (len(daten) // 1024, os.path.getsize(ausgabe) // 1024))
    print("SHA-256 %s" % sha)
    return sha


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    bauen(sys.argv[1], sys.argv[2], "--bericht" in sys.argv)
