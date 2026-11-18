#!/usr/bin/env python3
"""Übersicht und Prüfung der Zustandsautomaten von Uzai (nur Python-Standardbibliothek).

Ein Automat ist ein Feld mit Text-Zustand, dessen Setter src/core/zustand.gd meldet:

    ## Zweck in einer Zeile (steht so in der Übersicht).
    const ZUSTAENDE_X := { "": ["laedt"], "laedt": ["ok", "fehler"], "ok": [], "fehler": ["laedt"] }
    var feld := "":
        set(neu):
            Zustand.wechsel("bereich.name", ZUSTAENDE_X, feld, neu)
            feld = neu

Tabellen dürfen auch in einer anderen Datei stehen (gemeinsame Tabelle): Zustand.wechsel("…",
Andere.ZUSTAENDE_Y, feld, neu) mit const Andere := preload("res://…").

Aufruf:
    python3 -I tools/zustaende.py            # schreibt docs/ZUSTAENDE.md und docs/zustaende.json
    python3 -I tools/zustaende.py --pruefen  # prüft nur (Ausgang 1 bei Fehlern), schreibt nichts

Fehler:
    tabelle    Tabelle fehlt, ist kein reines Wörterbuch aus Texten oder nennt Ziele, die selbst
               kein Schlüssel sind (jeder Zustand steht als Schlüssel da, Endzustand mit []).
    zuweisung  Dem Feld wird im Quelltext ein Text zugewiesen, der kein Zustand der Tabelle ist
               (Tippfehler wie "laed" statt "laedt" fallen so sofort auf).
    name       Derselbe Automaten-Name mit zwei verschiedenen Tabellen.
    uebersicht docs/ZUSTAENDE.md oder docs/zustaende.json ist nicht aktuell (Werkzeug laufen lassen).
Warnung:
    erreichbar Ein Zustand ist vom Startzustand aus nicht erreichbar (oder der Start ist unbekannt).
    sackgasse  Ein Zustand ohne Ausgang, der nicht wie ein Ende heißt (fertig, done, aus …) und nicht
               unter "!" steht ("!": [...] nennt Zustände, die bewusst bleiben, z. B. ein Modus je Sitzung).

Läuft im Lint mit (tools/lint_gd.py ohne Argumente).
"""
import ast
import json
import os
import re
import sys

WECHSEL = re.compile(r'Zustand\.wechsel\(\s*"([^"]+)"\s*,\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)\s*,\s*'
                     r'(?:self\.)?([A-Za-z_][A-Za-z0-9_]*)')
MELDEN = re.compile(r'Zustand\.melden\(\s*"([^"]+)"')
PRELOAD = re.compile(r'^const\s+([A-Za-z_][A-Za-z0-9_]*)\s*:?=\s*preload\("res://([^"]+)"\)', re.M)
ENDE = {"fertig", "done", "aus", "zu", "ende", "beendet", "geschlossen", "weg", "abgelaufen"}


def _ohne_kommentare(text):
    """# … bis Zeilenende entfernen, aber nicht in Texten."""
    out = []
    for zeile in text.split("\n"):
        neu, in_text, i = [], None, 0
        while i < len(zeile):
            c = zeile[i]
            if in_text:
                neu.append(c)
                if c == "\\" and i + 1 < len(zeile):
                    neu.append(zeile[i + 1])
                    i += 2
                    continue
                if c == in_text:
                    in_text = None
            elif c in "\"'":
                in_text = c
                neu.append(c)
            elif c == "#":
                break
            else:
                neu.append(c)
            i += 1
        out.append("".join(neu))
    return "\n".join(out)


def _tabelle(src, name):
    """Liest const NAME := { … } (über mehrere Zeilen) als Python-Wörterbuch, sonst None."""
    m = re.search(r'^const\s+' + re.escape(name) + r'\s*:?=\s*\{', src, re.M)
    if not m:
        return None, 0, ""
    start = m.end() - 1
    tiefe, i, in_text = 0, start, None
    while i < len(src):
        c = src[i]
        if in_text:
            if c == "\\":
                i += 2
                continue
            if c == in_text:
                in_text = None
        elif c in "\"'":
            in_text = c
        elif c == "#":
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        elif c in "{[":
            tiefe += 1
        elif c in "}]":
            tiefe -= 1
            if tiefe == 0:
                break
        i += 1
    roh = _ohne_kommentare(src[start:i + 1])
    try:
        wert = ast.literal_eval(roh)
    except (ValueError, SyntaxError):
        return None, src.count("\n", 0, m.start()) + 1, ""
    zeile = src.count("\n", 0, m.start()) + 1
    # Zweck: die "##"-Zeilen direkt über der Tabelle.
    davor = src[:m.start()].rstrip("\n").split("\n")
    zweck = []
    while davor and davor[-1].lstrip().startswith("##"):
        zweck.insert(0, davor.pop().lstrip()[2:].strip())
    return wert, zeile, " ".join(z for z in zweck if z)


def _start(src, feld):
    m = re.search(r'^(?:static\s+)?var\s+' + re.escape(feld) + r'\s*(?::\s*String\s*)?:?=\s*"([^"]*)"', src, re.M)
    return m.group(1) if m else None


def _zuweisungen(src, feld):
    werte = set()
    for m in re.finditer(r'(?<![.\w])(?:self\.)?' + re.escape(feld) + r'\s*=\s*"([^"]*)"', src):
        davor = src[max(0, m.start() - 1):m.start()]
        if davor in ("=", "!", "<", ">"):
            continue
        werte.add(m.group(1))
    return werte


def sammeln(wurzel):
    """Alle Automaten: Liste von Wörterbüchern (name, datei, feld, start, zweck, tabelle, zeile)."""
    quellen = {}
    for ordner in ("src",):
        for r, _, fs in os.walk(os.path.join(wurzel, ordner)):
            for f in sorted(fs):
                if f.endswith(".gd"):
                    p = os.path.join(r, f)
                    with open(p, encoding="utf-8") as fh:
                        quellen[os.path.relpath(p, wurzel).replace(os.sep, "/")] = fh.read()
    maschinen, fehler = [], []
    gemeldet = {}
    for rel in sorted(quellen):
        for m in MELDEN.finditer(_ohne_kommentare(quellen[rel])):
            gemeldet.setdefault(m.group(1), set()).add(rel)
    for rel in sorted(quellen):
        src = quellen[rel]
        if "Zustand.wechsel(" not in src:
            continue
        code = _ohne_kommentare(src)   # Beispiele in Kommentaren zählen nicht
        preloads = {m.group(1): m.group(2) for m in PRELOAD.finditer(code)}
        gesehen = set()
        for m in WECHSEL.finditer(code):
            name, tab, feld = m.group(1), m.group(2), m.group(3)
            if (name, feld) in gesehen:
                continue
            gesehen.add((name, feld))
            tab_datei, tab_name, tab_src = rel, tab, src
            if "." in tab:
                ziel, tab_name = tab.split(".", 1)
                if ziel not in preloads or preloads[ziel] not in quellen:
                    fehler.append((rel, "tabelle", "%s: %s nicht gefunden (const %s := preload(…)?)" % (name, tab, ziel)))
                    continue
                tab_datei = preloads[ziel]
                tab_src = quellen[tab_datei]
            if not tab_name.startswith("ZUSTAENDE"):
                fehler.append((rel, "tabelle", "%s: Tabelle %s muss ZUSTAENDE… heißen" % (name, tab_name)))
            tabelle, zeile, zweck = _tabelle(tab_src, tab_name)
            if not isinstance(tabelle, dict) or not all(
                    isinstance(k, str) and isinstance(v, (list, tuple)) and all(isinstance(x, str) for x in v)
                    for k, v in tabelle.items()):
                fehler.append((tab_datei, "tabelle", "%s: %s ist kein Wörterbuch Text → [Texte]" % (name, tab_name)))
                continue
            maschinen.append({
                "name": name, "datei": rel, "feld": feld, "start": _start(src, feld),
                "zweck": zweck, "tabelle": {k: list(v) for k, v in tabelle.items()},
                "tabelle_ort": "%s:%d" % (tab_datei, zeile), "zuweisungen": sorted(_zuweisungen(code, feld)),
                "art": "setter",
            })
    # Nur gemeldete Automaten (Zustand.melden: Stand aus Einstellung, Funktion oder Schaltern, ohne Tabelle).
    tabellen_namen = {m["name"] for m in maschinen}
    for name in sorted(gemeldet):
        if name in tabellen_namen:
            continue
        maschinen.append({"name": name, "datei": sorted(gemeldet[name])[0], "feld": "", "start": None, "zweck": "",
                          "tabelle": {}, "tabelle_ort": "", "zuweisungen": [], "art": "melden"})
    return maschinen, fehler


SONDER = ("*", "!")   # "*": von überall erreichbar; "!": bewusst ohne Ausgang (Endzustände)


def _zustaende(t):
    return [k for k in t if k not in SONDER]


def pruefen(maschinen):
    fehler, warnungen = [], []
    namen = {}
    for m in maschinen:
        if m.get("art") == "melden":
            continue
        t, n, ort = m["tabelle"], m["name"], m["datei"]
        bekannt = set(_zustaende(t))
        alle_ziele = {z for k, v in t.items() if k != "!" for z in v}
        for z in t.get("!", []):
            if z not in bekannt:
                fehler.append((m["tabelle_ort"], "tabelle", "%s: \"!\" nennt \"%s\", das kein Schlüssel ist" % (n, z)))
        for z in sorted(alle_ziele - bekannt):
            fehler.append((m["tabelle_ort"], "tabelle", "%s: Ziel \"%s\" ist kein Schlüssel" % (n, z)))
        for z in m["zuweisungen"]:
            if z not in bekannt:
                fehler.append((ort, "zuweisung", "%s: %s = \"%s\" steht nicht in der Tabelle" % (n, m["feld"], z)))
        sig = json.dumps(t, sort_keys=True)
        if n in namen and namen[n] != sig:
            fehler.append((ort, "name", "%s: derselbe Name mit anderer Tabelle" % n))
        namen[n] = sig
        start = m["start"]
        if start is None or start not in bekannt:
            warnungen.append((ort, "erreichbar", "%s: Startzustand unbekannt (%r)" % (n, start)))
        else:
            erreicht, offen = {start}, [start]
            while offen:
                z = offen.pop()
                for w in (list(t.get(z, [])) + list(t.get("*", []))) if z not in SONDER else []:
                    if w not in erreicht:
                        erreicht.add(w)
                        offen.append(w)
            for z in sorted(bekannt - erreicht):
                warnungen.append((ort, "erreichbar", "%s: \"%s\" ist vom Start \"%s\" aus nicht erreichbar" % (n, z, start)))
        for z in sorted(bekannt):
            if not t.get(z) and not t.get("*") and z not in ENDE and z not in t.get("!", []):
                warnungen.append((ort, "sackgasse", "%s: \"%s\" hat keinen Ausgang" % (n, z)))
    return fehler, warnungen


def _id(z):
    return "leer" if z == "" else re.sub(r"[^A-Za-z0-9_]", "_", z)


def markdown(maschinen):
    zeilen = [
        "# Zustände in Uzai",
        "",
        "Erzeugt von `tools/zustaende.py` aus den Tabellen im Quelltext – nicht von Hand ändern.",
        "Jeder Automat meldet seine Wechsel an `src/core/zustand.gd`: Wechsel außerhalb der Tabelle",
        "ändern nichts am Verhalten, fallen aber in Tests (`ZUSTAND-VERSTOSS`) und in",
        "`logs/zustaende.log` auf. Der Fehlerbericht nennt den Stand aller Automaten.",
        "",
        "Neuen Automaten anlegen: Tabelle `const ZUSTAENDE… := { zustand: [folgezustände] }` mit",
        "`##`-Zweck darüber, Setter mit `Zustand.wechsel(\"bereich.name\", TABELLE, feld, neu)`, dann",
        "`python3 -I tools/zustaende.py`. `\"*\"` nennt Zustände, die von überall erreichbar sind, `\"!\"` bewusste",
        "Endzustände (keine Sackgassen-Warnung).",
        "",
        "Maschinenlesbar: `docs/zustaende.json`. Was noch implizit ist (Kandidaten, bekannte offene",
        "Punkte): `docs/ZUSTAENDE_OFFEN.md`.",
        "",
        "| Automat | Feld | Datei | Zustände |",
        "|---|---|---|---|",
    ]
    gemeldet = [m for m in maschinen if m.get("art") == "melden"]
    maschinen = [m for m in maschinen if m.get("art") != "melden"]
    for m in maschinen:
        zeilen.append("| [%s](#%s) | `%s` | `%s` | %d |" % (m["name"], m["name"].replace(".", "").lower(), m["feld"],
                                                         m["datei"], len(_zustaende(m["tabelle"]))))
    for m in maschinen:
        t = m["tabelle"]
        zeilen += ["", "## %s" % m["name"], ""]
        if m["zweck"]:
            zeilen += [m["zweck"], ""]
        zeilen.append("Feld `%s` in `%s`, Tabelle `%s`, Start `%s`." % (
            m["feld"], m["datei"], m["tabelle_ort"], "?" if m["start"] is None else (m["start"] or "(leer)")))
        if t.get("*"):
            zeilen.append("Von überall erreichbar: %s." % ", ".join("`%s`" % (z or "(leer)") for z in t["*"]))
        if t.get("!"):
            zeilen.append("Bewusst ohne Ausgang: %s." % ", ".join("`%s`" % (z or "(leer)") for z in t["!"]))
        zeilen += ["", "```mermaid", "stateDiagram-v2"]
        for z in _zustaende(t):
            if z == "":
                zeilen.append("    leer : (leer)")
        if m["start"] is not None:
            zeilen.append("    [*] --> %s" % _id(m["start"]))
        for z in _zustaende(t):
            for w in t[z]:
                zeilen.append("    %s --> %s" % (_id(z), _id(w)))
        zeilen += ["```"]
    if gemeldet:
        zeilen += ["", "## Nur gemeldet (ohne Tabelle)", "",
                   "Stand aus Einstellung, Funktion oder mehreren Schaltern – `Zustand.melden()` nennt ihn für",
                   "Fehlerbericht und Verlauf, geprüft wird er nicht.", "", "| Automat | Datei |", "|---|---|"]
        for m in gemeldet:
            zeilen.append("| %s | `%s` |" % (m["name"], m["datei"]))
    return "\n".join(zeilen) + "\n"


def json_text(maschinen):
    aus = [{k: m[k] for k in ("name", "art", "datei", "feld", "start", "zweck", "tabelle", "tabelle_ort")} for m in maschinen]
    return json.dumps(aus, ensure_ascii=False, indent=1, sort_keys=True) + "\n"


def alles(wurzel, schreiben):
    """(fehler, warnungen) – fehler/warnungen: Liste (ort, regel, text)."""
    maschinen, fehler = sammeln(wurzel)
    f2, warnungen = pruefen(maschinen)
    fehler += f2
    ziele = {os.path.join(wurzel, "docs", "ZUSTAENDE.md"): markdown(maschinen),
             os.path.join(wurzel, "docs", "zustaende.json"): json_text(maschinen)}
    offen = os.path.join(wurzel, "docs", "ZUSTAENDE_OFFEN.md")
    if not os.path.exists(offen):
        fehler.append(("docs/ZUSTAENDE_OFFEN.md", "uebersicht", "fehlt – die Übersicht verweist darauf (von Hand gepflegt)"))
    for pfad, text in ziele.items():
        alt = None
        if os.path.exists(pfad):
            with open(pfad, encoding="utf-8") as fh:
                alt = fh.read()
        if alt == text:
            continue
        if schreiben:
            with open(pfad, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
        else:
            fehler.append((os.path.relpath(pfad, wurzel), "uebersicht",
                           "nicht aktuell – python3 -I tools/zustaende.py"))
    return fehler, warnungen, len(maschinen)


def main(argv):
    wurzel = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    fehler, warnungen, n = alles(wurzel, "--pruefen" not in argv)
    for ort, regel, text in fehler:
        print("%s: %s: %s" % (ort, regel, text))
    for ort, regel, text in warnungen:
        print("%s: Warnung %s: %s" % (ort, regel, text))
    print("zustaende: %d Automaten (mit Tabelle und nur gemeldet), Fehler: %d, Warnungen: %d" % (n, len(fehler), len(warnungen)))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
