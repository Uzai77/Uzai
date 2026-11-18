#!/usr/bin/env python3
"""Sucht toten Code: Funktionen, Konstanten, Signale und Felder unter src/, deren Name im ganzen
Projekt nur an der Definition steht (nur Python-Standardbibliothek).

    python3 -I tools/tot_code.py            # Liste, eine Zeile je Fund
    python3 -I tools/tot_code.py --dateien  # dazu Dateien unter src/, die nichts mehr nennt

Gezählt wird jedes Vorkommen des Namens als Wort in Programm, Tests, Werkzeugen, Szenen und Daten
(auch in Texten: call("name"), has_method("name"), Signale in Szenen). Kommt der Name nur einmal vor,
ruft ihn nichts. Nicht gemeldet werden Funktionen, die Godot selbst ruft (_ready, _draw …), Namen,
die das Programm zusammensetzt (DYNAMISCH unten: Anfang des Namens, mit Fundstelle), und was mit
Grund stehen bleibt (BLEIBT).

Grob in eine Richtung: Trägt eine andere Funktion denselben Namen, bleibt eine tote unentdeckt.
Ein Fund ist ein Hinweis, kein Urteil – vor dem Löschen ansehen (Aufzählungen eines Protokolls
dürfen vollständig bleiben, auch wenn ein Wert noch nicht gebraucht wird).
"""
import collections
import pathlib
import re
import subprocess
import sys

# Von Godot gerufen, nie aus dem Programm.
GODOT = set("""_ready _process _physics_process _input _unhandled_input _unhandled_key_input _gui_input
_draw _notification _init _enter_tree _exit_tree _get_minimum_size _get _set _get_property_list
_to_string _get_message _get_plural_message _has_point _can_drop_data _drop_data _get_drag_data
_make_custom_tooltip _shortcut_input _get_configuration_warnings _validate_property _iter_init
_iter_next _iter_get _static_init""".split())

# Namen, die erst zur Laufzeit entstehen: Anfang → wo sie zusammengesetzt werden.
DYNAMISCH = {
    "_page_": "src/ui/layers/pad_help.gd: call(\"_page_\" + id)",
}

# Bleibt mit Absicht, obwohl es nichts nennt: Name → Grund.
BLEIBT = {
    "ST_UNINSTALLED": "Steams Zustände stehen vollständig da (src/core/install_parse.gd).",
    "ST_UPDATE_STOPPING": "Steams Zustände stehen vollständig da (src/core/install_parse.gd).",
    "PT_IMAGE": "Arten der Wiedergabe stehen vollständig da (src/core/music.gd).",
    "EMSG_ADD_FRIEND_RESPONSE": "Nachrichtennummern des Steam-Protokolls (src/core/steam_cm.gd).",
    "NUR_VOM_GASTGEBER": "Nennt die Regel des Zimmer-Protokolls; durchgesetzt in src/room/freundestest.gd (_nachricht).",
}

TEXT = re.compile(r"\.(gd|tscn|json|ps1|js|lua|py|sh|cfg|godot|uzaitheme|gdshader|gdshaderinc)$")
WORT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ARTEN = (
    ("Funktion", re.compile(r"\s*(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(")),
    ("Konstante", re.compile(r"\s*const\s+([A-Za-z_]\w*)\b")),
    ("Signal", re.compile(r"\s*signal\s+([A-Za-z_]\w*)\b")),
    ("Feld", re.compile(r"(?:static\s+)?var\s+([A-Za-z_]\w*)\b")),   # nur ohne Einzug: Felder der Datei
)


def lesen(wurzel: pathlib.Path) -> dict:
    namen = subprocess.run(["git", "ls-files"], cwd=wurzel, capture_output=True, text=True).stdout.split("\n")
    texte = {}
    for n in namen:
        if not n or n.startswith("third_party/") or n == "i18n/en.json" or n.endswith("crypto-js.js") or not TEXT.search(n):
            continue
        try:
            texte[n] = (wurzel / n).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            pass
    return texte


def main(argv: list) -> int:
    wurzel = pathlib.Path(__file__).resolve().parent.parent
    texte = lesen(wurzel)
    zahl = collections.Counter()
    for t in texte.values():
        zahl.update(WORT.findall(t))
    funde = []
    for datei, t in sorted(texte.items()):
        if not datei.startswith("src/") or not datei.endswith(".gd"):
            continue
        for nr, zeile in enumerate(t.split("\n"), 1):
            for art, muster in ARTEN:
                m = muster.match(zeile)
                if not m:
                    continue
                name = m.group(1)
                if zahl[name] == 1 and name not in GODOT and name not in BLEIBT and not any(name.startswith(a) for a in DYNAMISCH):
                    funde.append((datei, nr, art, name))
                break
    for datei, nr, art, name in funde:
        print("%s:%d: %s %s" % (datei, nr, art, name))
    waisen = []
    if "--dateien" in argv:
        alles = "\n".join(texte.values())
        for datei in sorted(texte):
            if not datei.startswith("src/") or not re.search(r"\.(gd|gdshader|gdshaderinc|tscn)$", datei):
                continue
            kurz = datei.rsplit("/", 1)[-1]
            klasse = re.search(r"^class_name\s+(\w+)", texte[datei], re.M)
            if alles.count(datei) == 0 and sum(t.count(kurz) for d, t in texte.items() if d != datei) == 0 \
                    and not (klasse and zahl[klasse.group(1)] > 1):
                waisen.append(datei)
        for datei in waisen:
            print("%s: Datei, die nichts mehr nennt" % datei)
    print("tot_code: %d Funde%s" % (len(funde), (", %d Dateien" % len(waisen)) if "--dateien" in argv else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
