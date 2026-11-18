#!/usr/bin/env python3
"""Prüft und formatiert Uzais GDScript (nur Python-Standardbibliothek).

Aufruf:
    python3 tools/lint_gd.py                 # prüft src/ und tests/
    python3 tools/lint_gd.py datei.gd ...    # nur diese Dateien oder Ordner
    python3 tools/lint_gd.py --fix           # repariert, was sicher geht, und prüft danach
    python3 tools/lint_gd.py --selbsttest    # prüft die Regeln an eingebauten Beispielen

Fehler (Ausgang 1):
    tabs       Einrückung nur mit Tabs (auch in Fortsetzungszeilen).
    laenge     Höchstens 160 Zeichen je Zeile. Gemessen ohne den längsten Text der Zeile: Texte
               werden nie geteilt, sie sind die Schlüssel der Übersetzung (i18n/en.json) und
               sollen im Quelltext am Stück auffindbar bleiben.
    leerzeichen  Keine Leerzeichen oder Tabs am Zeilenende.
    kopf       Jede Datei beginnt (nach extends/class_name/@tool) mit einer Kurzbeschreibung „##“.
    verboten   Kein str_to_var, bytes_to_var_with_objects oder Expression; load() und
               ResourceLoader.load() nur mit festem Pfad (Text „res://…“ oder KONSTANTE).
               Ausnahmen stehen mit Begründung in AUSNAHMEN.
    federn     Kein TRANS_BACK, TRANS_ELASTIC oder TRANS_BOUNCE (Takt, docs/DESIGN.md › Bewegung:
               ruhig, kein Überschwingen). Ausnahmen je Datei mit Grund in FEDERN_AUSNAHMEN.
    pool       Hintergrundarbeit nur über src/core/arbeit.gd: kein WorkerThreadPool.add_task und
               kein ResourceLoader.load_threaded_request im Programm (Grund im Kopf von arbeit.gd).
    netz       Abrufe nur über Net (src/core/net.gd, Netzfaden src/core/abruf.gd): kein HTTPRequest
               im Programm. Er friert Uzai ein, wenn ein Server schweigt (Grund im Kopf von abruf.gd).
Warnung (Ausgang bleibt 0):
    lang       Funktion mit mehr als FUNC_WARN Zeilen.
    takt       Wörtliche Dauer (Zahl) in tween_property/tween_method außerhalb von src/ui/u.gd –
               die Zeiten des Takts (U.T_ANTWORT … U.T_LICHT) sagen, was die Bewegung bedeutet.
    federn-alt Eine Ausnahme in FEDERN_AUSNAHMEN wird nicht mehr gebraucht (darf weg).

Ohne Argumente prüft es auch die Zustandsautomaten (tools/zustaende.py: Tabellen, Zuweisungen,
docs/ZUSTAENDE.md aktuell; Regeln zustand-…).

Inhalt mehrzeiliger Texte (in drei Anführungszeichen) ist Daten und wird nicht geprüft oder verändert.

--fix entfernt Leerzeichen am Zeilenende und bricht zu lange Zeilen um: nach einem Komma oder
einer öffnenden Klammer innerhalb von Klammern (dort erlaubt GDScript Zeilenumbrüche ohne
Zeichen), sonst vor „and“/„or“ mit „\\“. Nie in einem Lambda, nie in Texten. Zu lange reine
Kommentarzeilen werden an Wortgrenzen umbrochen. Danach vergleicht das Werkzeug die Token der
Datei vorher und nachher – weicht etwas ab (außer Leerraum), bleibt die Datei unverändert.
"""
import os
import re
import sys

MAX_LEN = 160
FUNC_WARN = 150
ROOTS = ("src", "tests")

# Verbotene Aufrufe auf fremden Daten (docs/SECURITY.md): sie können Objekte bauen oder Code
# ausführen. Nur feste Programmteile dürfen geladen werden.
VERBOTEN = ("str_to_var", "bytes_to_var_with_objects", "Expression")

# Ausnahmen: (Datei, Funktion, Aufruf) → Begründung. Die Funktion statt der Zeile, damit eine
# Ausnahme beim Umbauen nicht still auf eine andere Stelle rutscht.
AUSNAHMEN = {
    ("src/main.gd", "_proben_starten", "load"):
        "Rundgang aus der festen Liste PROBEN oder Probe aus --uzai-script=: von probe_script_ok geprüft (im Export nur res://tests/…, das dort fehlt).",
    ("src/core/arbeit.gd", "geladen", "load"):
        "Vorgeladene Programmteile: nur Pfade unter res:// (in der Funktion geprüft), alle aus festen Listen im Programm.",
    ("src/core/capture.gd", "_font_file", "load"):
        "Schrift aus der festen Liste FONTS (res://assets/fonts/…).",
    ("src/core/menu_musik.gd", "_laden", "load"):
        "Menümusik: Name aus der festen Liste Klang.MUSIK, Pfad unter res://, vorher ResourceLoader.exists.",
    ("src/core/sfx.gd", "_build", "load"):
        "Klang: Name aus der festen Liste NAMES, Pfad unter res://assets/sounds, vorher ResourceLoader.exists.",
    ("src/room/stoffe.gd", "textur", "load"):
        "Oberflächen: Name aus der festen Liste TEXTUREN, Pfad unter res://assets/zimmer/tex, vorher ResourceLoader.exists.",
    ("src/room/moebel.gd", "_modell", "load"):
        "Möbel-Modelle: Datei aus der festen Liste MODELLE, Pfad unter res://assets/zimmer/modelle.",
    ("src/room/figur/figur_psx.gd", "_aufbereiten", "load"):
        "Figuren: Kennung aus der festen Liste PERSONEN (vorher geprüft), Pfad unter res://assets/figur/psx.",
    ("tests/check_scripts.gd", "_ready", "ResourceLoader.load"):
        "Kompilierprüfung: lädt jedes Skript unter res://src, nichts von außen.",
    ("tests/logic_controller.gd", "_ready", "load"):
        "Test: lädt drei feste Skripte aus res://src.",
    ("tests/probe_vorladen.gd", "_ready", "load"):
        "Probe: lädt feste Skripte aus res://src (Liste im Test).",
}

GENUTZT = set()   # Ausnahmen, die beim Lauf gebraucht wurden

# Überschwingen (Federn, Hüpfen) passt nicht zur Marke. Eine Ausnahme je Datei braucht einen Grund
# (Datei → Grund); federn-alt meldet Einträge, die nicht mehr gebraucht werden.
FEDERN = re.compile(r'\bTRANS_(BACK|ELASTIC|BOUNCE)\b')
POOL = re.compile(r'\bWorkerThreadPool\.add_(group_)?task\b|\bload_threaded_request\b')
NETZ = re.compile(r'\bHTTPRequest\.new\(')
PROBE_ENV = re.compile(r'OS\.get_environment\(\s*"UZAI_(?!DATA")')
FEDERN_AUSNAHMEN = {}
FEDERN_GENUTZT = set()

TWEEN_AUF = re.compile(r'\btween_(property|method)\(')
ZAHL = re.compile(r'^\d+(\.\d*)?$|^\.\d+$')

DECL_FUNC = re.compile(r'^(\t*)(?:static\s+)?func\s+([A-Za-z_]\w*)')
WORD = re.compile(r'[A-Za-z_]\w*')


# --- Zerlegen ------------------------------------------------------------------------------

class Zeile:
    """Eine Zeile mit dem, was der Zerleger über sie weiß."""
    __slots__ = ("text", "in_text", "tiefe_vor", "code", "kommentar", "tiefe_nach", "endet_im_text", "im_lambda")

    def __init__(self, text):
        self.text = text
        self.in_text = False       # beginnt innerhalb eines mehrzeiligen Textes
        self.tiefe_vor = 0         # offene Klammern vor der Zeile
        self.code = ""             # Code mit Texten durch Platzhalter ersetzt (gleiche Länge)
        self.kommentar = -1        # Index des Kommentarbeginns oder -1
        self.tiefe_nach = 0
        self.endet_im_text = False
        self.im_lambda = False     # Anweisung im Rumpf eines mehrzeiligen Lambdas in Klammern


def zerlegen(lines):
    """Geht die Datei Zeichen für Zeichen durch: Texte, Kommentare, Klammertiefe."""
    out = []
    quote = None        # offener mehrzeiliger Text („\"\"\"“ oder „'''“)
    tiefe = 0
    for text in lines:
        z = Zeile(text)
        z.in_text = quote is not None
        z.tiefe_vor = tiefe
        code = []
        i, n = 0, len(text)
        while i < n:
            c = text[i]
            if quote:
                if c == "\\":
                    code.append("~~")
                    i += 2
                    continue
                if text.startswith(quote, i):
                    code.append("~" * len(quote))
                    i += len(quote)
                    quote = None
                    continue
                code.append("~")
                i += 1
                continue
            if c == "#":
                z.kommentar = i
                break
            if c in "\"'":
                if text.startswith(c * 3, i):
                    quote = c * 3
                    code.append("~~~")
                    i += 3
                    continue
                j = i + 1
                while j < n and text[j] != c:
                    j += 2 if text[j] == "\\" else 1
                code.append("~" * (min(j, n - 1) + 1 - i))
                i = j + 1
                continue
            if c in "([{":
                tiefe += 1
            elif c in ")]}":
                tiefe = max(0, tiefe - 1)
            code.append(c)
            i += 1
        z.code = "".join(code)[:n]
        z.tiefe_nach = tiefe
        z.endet_im_text = quote is not None
        out.append(z)
    # Mehrzeilige Lambdas in Klammern: ihr Rumpf hängt an der Einrückung, obwohl Klammern offen sind.
    rumpf = []        # Klammertiefe je offenem Lambda-Rumpf
    for z in out:
        if z.in_text:
            continue
        while rumpf and z.tiefe_vor < rumpf[-1]:
            rumpf.pop()
        z.im_lambda = bool(rumpf) and z.tiefe_vor == rumpf[-1]
        code = (z.code[:z.kommentar] if z.kommentar >= 0 else z.code).rstrip()
        if z.tiefe_nach > 0 and code.endswith(":") and re.search(r'\bfunc\b', code) and not DECL_FUNC.match(z.text):
            rumpf.append(z.tiefe_nach)
    return out


def token(lines):
    """Bedeutsame Token der Datei (für den Vergleich vorher/nachher): Code-Token, Einrückung am
    Anfang jeder logischen Zeile, Texte im Wortlaut; Kommentare als Wortfolge getrennt."""
    toks, worte = [], []
    weiter = False   # Zeile davor endete mit „\\“
    for z in zerlegen(lines):
        t = z.text
        if z.in_text:
            toks.append(("TEXTZEILE", t))
            continue
        if z.kommentar >= 0:
            worte.extend(t[z.kommentar:].lstrip("#").split())
        code_end = z.kommentar if z.kommentar >= 0 else len(t)
        roh = t[:code_end]
        if roh.strip() == "":
            continue
        if z.tiefe_vor == 0 and not weiter:
            toks.append(("ZEILE", len(roh) - len(roh.lstrip("\t"))))
        s = roh.rstrip()
        weiter = s.endswith("\\") and not z.endet_im_text
        if weiter:
            s = s[:-1]
        for m in re.finditer(r'"""|\'\'\'|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_]\w*|\d[\w.]*|\S', s):
            toks.append(("T", m.group(0)))
    return toks, worte


# --- Umbrechen -----------------------------------------------------------------------------

def _stellen(z):
    """Erlaubte Umbruchstellen einer Zeile: [(Index, Art, Tiefe)] – Art „nach“ (Umbruch nach dem
    Zeichen davor, ohne Zeichen) oder „bs“ (Umbruch vor „and“/„or“ mit „\\“); Tiefe: Klammerebene
    in dieser Zeile (kleiner = lieber, so bleiben innere Listen zusammen).

    In einem einzeiligen Lambda („func(x): return …“) hängt der Rumpf an der Zeile; dort sind nur
    Umbrüche in Klammern erlaubt, die erst im Rumpf geöffnet werden. Öffnet die Zeile ein
    mehrzeiliges Lambda, bleibt sein Kopf am Zeilenende; davor darf umbrochen werden."""
    code = z.code
    end = z.kommentar if z.kommentar >= 0 else len(code)
    stellen = []
    stapel = []                   # offene Klammern dieser Zeile
    lam = []                      # offene Lambdas: [Tiefe des „func“, Tiefe des Rumpfs oder None]
    # In offenen Klammern (aber nicht im Rumpf eines mehrzeiligen Lambdas) darf überall umbrochen werden.
    getragen = 0 if z.im_lambda else z.tiefe_vor

    def frei(tiefe):
        """Darf auf dieser Klammertiefe (dieser Zeile) umbrochen werden?"""
        if lam:
            return lam[-1][1] is not None and tiefe > lam[-1][1]
        return tiefe > 0 or getragen > 0

    i = 0
    while i < end:
        c = code[i]
        lokal = len(stapel)
        if c.isalpha() or c == "_":
            m = WORD.match(code, i)
            w = m.group(0)
            if w == "func" and not DECL_FUNC.match(z.text):
                lam.append([lokal, None])
            elif w in ("and", "or", "if", "else") and i > 0 and code[i - 1] == " ":
                if frei(lokal):
                    stellen.append((i, "nach", lokal))
                elif not lam and z.tiefe_vor == 0 and lokal == 0 and w in ("and", "or"):
                    stellen.append((i, "bs", lokal))
            i = m.end()
            continue
        if c == ":" and lam and lam[-1][1] is None and lokal == lam[-1][0]:
            lam[-1][1] = lokal    # ab hier Rumpf des Lambdas
        elif c in "([{":
            stapel.append(i)
            erste = lam[-1][1] + 1 if lam and lam[-1][1] is not None else 1
            if len(stapel) == erste and frei(len(stapel)) and i + 1 < end and code[i + 1] not in ")]}":
                stellen.append((i + 1, "nach", len(stapel)))
        elif c in ")]}":
            if stapel:
                stapel.pop()
            elif getragen > 0:
                getragen -= 1
            while lam and len(stapel) < lam[-1][0]:
                lam.pop()
        elif c == "," and frei(lokal):
            j = i + 1
            while j < end and code[j] == " ":
                j += 1
            if j < end:
                stellen.append((j, "nach", lokal))
        i += 1
    return stellen


def langer_text(z):
    """Länge des längsten Texts in der Zeile (Texte bricht das Werkzeug nie, sie sind auch die
    Schlüssel der Übersetzung)."""
    code = z.code[:z.kommentar] if z.kommentar >= 0 else z.code
    return max((len(m.group(0)) for m in re.finditer(r'~+', code)), default=0)


def nur_text_zu_lang(z):
    """Zu lang nur wegen eines einzelnen Texts: ohne ihn hätte die Zeile höchstens MAX_LEN."""
    return len(z.text) - langer_text(z) <= MAX_LEN - 2


def umbrechen(z):
    """Bricht eine zu lange Code-Zeile um; liefert die neuen Zeilen oder None. Erst so, dass jedes
    Stück passt; geht das nicht und ist die Zeile nicht nur wegen eines Texts zu lang, dann so,
    dass nur noch der lange Text auf einer eigenen Zeile übersteht."""
    teile = _umbrechen(z, False)
    if teile is None and not nur_text_zu_lang(z):
        teile = _umbrechen(z, True)
    return teile


def _umbrechen(z, locker):
    t = z.text
    stellen = _stellen(z)
    if not stellen:
        return None
    einzug = t[:len(t) - len(t.lstrip("\t"))]
    pre = einzug + ("\t" if z.tiefe_vor > 0 and not z.im_lambda else "\t\t")

    def stueck(a, b, erstes):
        s = t[a:b] if erstes else pre + t[a:b].lstrip(" ")
        return s.rstrip(" ")

    def passt(a, b, erstes, extra=0):
        """Passt das Stück – oder macht es nur ein einzelner Text zu lang?"""
        n = len(stueck(a, b, erstes)) + extra
        if n <= MAX_LEN:
            return 2
        if not locker:
            return 0
        text = max((len(m.group(0)) for m in re.finditer(r'~+', z.code[a:b])), default=0)
        return 1 if n - text <= MAX_LEN - 2 else 0

    teile, start, erstes = [], 0, True
    while True:
        if passt(start, len(t), erstes):
            teile.append(stueck(start, len(t), erstes))
            break
        moeglich = [s for s in stellen if s[0] > start and t[start:s[0]].strip(" \t") != ""]
        guete = {s: passt(start, s[0], erstes, 2 if s[1] == "bs" else 0) for s in moeglich}
        passend = [s for s in moeglich if guete[s] == 2]
        if passend:
            flach = min(s[2] for s in passend)
            wahl = [s for s in passend if s[2] == flach][-1]
        else:
            # Nur ein langer Text: das kürzeste Stück, das ihn ganz enthält.
            mit_text = [s for s in moeglich if guete[s] == 1]
            if not mit_text:
                return None
            wahl = mit_text[0]
        teile.append(stueck(start, wahl[0], erstes) + (" \\" if wahl[1] == "bs" else ""))
        start, erstes = wahl[0], False
    return teile if len(teile) > 1 else None


def kommentar_umbrechen(text):
    """Reine Kommentarzeile an Wortgrenzen umbrechen (gleicher Einzug, gleiches „#“/„##“)."""
    m = re.match(r'^(\s*)(#+)( ?)(.*)$', text)
    if not m:
        return None
    einzug, rauten, _, inhalt = m.groups()
    # Eingerückte Fortsetzung (z. B. „##   weiter“) behalten.
    innen = re.match(r'^(\s*)', inhalt).group(1)
    kopf = einzug + rauten + " " + innen
    worte = inhalt.split(" ")
    zeilen, cur = [], ""
    for w in worte:
        if w == "" and cur == "":
            continue
        probe = (cur + " " + w) if cur else w
        if len(kopf) + len(probe) > MAX_LEN and cur:
            zeilen.append(kopf + cur)
            cur = w
        else:
            cur = probe
    if cur:
        zeilen.append(kopf + cur)
    return zeilen if len(zeilen) > 1 else None


def formatieren(src):
    """Gibt den reparierten Text zurück (oder den alten, wenn der Token-Vergleich scheitert)."""
    lines = src.split("\n")
    zs = zerlegen(lines)
    neu = []
    for z in zs:
        t = z.text
        if not z.in_text and not z.endet_im_text:
            t = t.rstrip(" \t")
            z.text = t
            if len(t) > MAX_LEN:
                if z.kommentar >= 0 and t[:z.kommentar].strip() == "":
                    teile = kommentar_umbrechen(t)
                else:
                    teile = umbrechen(z)
                if teile:
                    neu.extend(teile)
                    continue
        elif not z.in_text:
            # Zeile beginnt Code und öffnet einen mehrzeiligen Text: nur Code-Ende säubern geht nicht sicher.
            pass
        neu.append(t)
    ergebnis = "\n".join(neu)
    vorher, vw = token(lines)
    nachher, nw = token(ergebnis.split("\n"))
    if vorher != nachher or vw != nw:
        return src, False
    return ergebnis, True


# --- Prüfen --------------------------------------------------------------------------------

def _argumente(code, start):
    """Argumente eines Aufrufs ab der Klammer bei start bis zur schließenden (oberste Ebene).
    Liefert (liste, geschlossen)."""
    args, tiefe, cur = [], 0, ""
    for ch in code[start:]:
        if ch in "([{":
            tiefe += 1
            if tiefe == 1:
                continue
        elif ch in ")]}":
            tiefe -= 1
            if tiefe == 0:
                args.append(cur.strip())
                return args, True
        if ch == "," and tiefe == 1:
            args.append(cur.strip())
            cur = ""
        else:
            cur += ch
    return args, False


def _takt_dauer(zs, idx, code, m):
    """Die Dauer (viertes Argument) eines tween_property/tween_method-Aufrufs, sonst None.
    Ein tween_method mit mehrzeiligem Lambda endet in einer Zeile „, von, bis, dauer)“."""
    args, zu = _argumente(code, m.end() - 1)
    if zu:
        return args[3] if len(args) >= 4 else None
    for k in range(idx + 1, min(idx + 40, len(zs))):
        c = zs[k].code[:zs[k].kommentar] if zs[k].kommentar >= 0 else zs[k].code
        st = c.strip()
        if st.startswith(",") and zs[k].tiefe_vor == 1:
            rest, zu2 = _argumente("(" + st[1:], 0)
            if zu2 and rest:
                return rest[-1]
            return None
    return None


def _funktion_an(lines_info, idx):
    """Name der Funktion, in der Zeile idx steht ("" auf oberster Ebene)."""
    for k in range(idx, -1, -1):
        m = DECL_FUNC.match(lines_info[k].text)
        if m and not lines_info[k].in_text:
            return m.group(2)
    return ""


def pruefen(rel, src):
    """Liefert (fehler, warnungen) als Listen von (Zeile, Regel, Text)."""
    lines = src.split("\n")
    zs = zerlegen(lines)
    fehler, warn = [], []
    # Kopf
    kopf_ok = False
    for z in zs:
        s = z.text.strip()
        if s == "" or re.match(r'^(extends|class_name|@tool|@icon|@static_unload)\b', s):
            continue
        kopf_ok = s.startswith("##")
        break
    if not kopf_ok:
        fehler.append((1, "kopf", "Datei beginnt nicht mit einer Kurzbeschreibung (##)"))
    # Konstanten mit festem Pfad im Programm: load(SELF) ist so sicher wie load("res://…").
    feste = set(re.findall(r'(?m)^const\s+([A-Za-z_]\w*)\s*:?=\s*"res://', src))
    func_start, func_name, func_einzug = None, "", 0
    for idx, z in enumerate(zs):
        t = z.text
        nr = idx + 1
        if z.in_text:
            continue
        einzug = t[:len(t) - len(t.lstrip(" \t"))]
        if " " in einzug and t.strip() != "":
            fehler.append((nr, "tabs", "Einrückung mit Leerzeichen"))
        if not z.endet_im_text and t != t.rstrip(" \t"):
            fehler.append((nr, "leerzeichen", "Leerzeichen am Zeilenende"))
        if z.endet_im_text:
            auf = max(t.rfind('"""'), t.rfind("'''"))
            zu_lang = auf > MAX_LEN
        else:
            zu_lang = len(t) > MAX_LEN and not nur_text_zu_lang(z)
        if zu_lang:
            fehler.append((nr, "laenge", "Zeile hat %d Zeichen (höchstens %d)" % (len(t), MAX_LEN)))
        code = z.code[:z.kommentar] if z.kommentar >= 0 else z.code
        for m in WORD.finditer(code):
            w = m.group(0)
            vor = code[:m.start()].rstrip()
            aufruf = None
            if w in VERBOTEN and not vor.endswith("."):
                aufruf = w
            elif w == "load" and code[m.end():m.end() + 1] == "(":
                if vor.endswith("ResourceLoader."):
                    aufruf = "ResourceLoader.load"
                elif vor.endswith("."):
                    continue
                else:
                    aufruf = "load"
                arg = t[m.end() + 1:].lstrip()
                k = re.match(r'^([A-Za-z_]\w*)\)', arg)
                if arg.startswith('"res://') or (k and k.group(1) in feste):
                    continue
            if aufruf:
                key = (rel, _funktion_an(zs, idx), aufruf)
                GENUTZT.add(key)
                if key not in AUSNAHMEN:
                    fehler.append((nr, "verboten", "%s ohne festen Pfad oder auf fremden Daten (Funktion %s)" % (aufruf, key[1] or "–")))
        if POOL.search(code) and rel != "src/core/arbeit.gd" and not rel.startswith("tests/"):
            fehler.append((nr, "pool", "Hintergrundarbeit über Arbeit.los/auftrag/ergebnis bzw. Arbeit.vorladen (src/core/arbeit.gd)"))
        if NETZ.search(code) and not rel.startswith("tests/"):
            fehler.append((nr, "netz", "Abrufe über Net.request/get_json/download_big (src/core/abruf.gd), nicht über HTTPRequest"))
        # Am Text der Zeile selbst (ohne Kommentar): In z.code stehen statt der Texte Platzhalter – der Name der
        # Umgebungsvariable wäre dort nie zu finden, und die Regel griffe nie.
        roh = t[:z.kommentar] if z.kommentar >= 0 else t
        if PROBE_ENV.search(roh) and not rel.startswith("tests/"):
            fehler.append((nr, "probe-env", "Test-Umleitungen über Config.probe_env lesen (gilt im ausgelieferten Programm nicht), nicht über OS.get_environment"))
        # Takt: kein Überschwingen; Dauern mit Namen statt Zahlen.
        if FEDERN.search(code):
            if rel in FEDERN_AUSNAHMEN:
                FEDERN_GENUTZT.add(rel)
            else:
                fehler.append((nr, "federn", "Überschwingen (TRANS_BACK/ELASTIC/BOUNCE) – Kurve „Ankommen“ nehmen (U.ankommen)"))
        if rel != "src/ui/u.gd":
            for mt in TWEEN_AUF.finditer(code):
                d = _takt_dauer(zs, idx, code, mt)
                if d is not None and ZAHL.match(d):
                    warn.append((nr, "takt", "wörtliche Dauer %s in tween_%s – U.T_ANTWORT … U.T_LICHT nehmen" % (d, mt.group(1))))
        # Funktionslänge
        m = DECL_FUNC.match(t)
        if m or (func_start is not None and t.strip() != "" and not t.startswith("\t" * (func_einzug + 1))
                 and z.tiefe_vor == 0 and not t.lstrip("\t").startswith("#")):
            if func_start is not None:
                laenge = _letzte_zeile(zs, func_start, idx) - func_start
                if laenge > FUNC_WARN:
                    warn.append((func_start + 1, "lang", "Funktion %s hat %d Zeilen" % (func_name, laenge)))
                func_start = None
            if m:
                func_start, func_name, func_einzug = idx, m.group(2), len(m.group(1))
    if func_start is not None:
        laenge = _letzte_zeile(zs, func_start, len(zs)) - func_start
        if laenge > FUNC_WARN:
            warn.append((func_start + 1, "lang", "Funktion %s hat %d Zeilen" % (func_name, laenge)))
    return fehler, warn


def _letzte_zeile(zs, start, ende):
    k = ende
    while k - 1 > start and (zs[k - 1].text.strip() == "" or zs[k - 1].text.lstrip().startswith("#")):
        k -= 1
    return k


# --- Ablauf --------------------------------------------------------------------------------

def dateien(args, wurzel):
    ziele = args or [os.path.join(wurzel, r) for r in ROOTS]
    for z in ziele:
        if os.path.isfile(z):
            yield z
            continue
        for dp, dn, fn in os.walk(z):
            dn[:] = sorted(d for d in dn if not d.startswith("."))
            for f in sorted(fn):
                if f.endswith(".gd"):
                    yield os.path.join(dp, f)


def selbsttest():
    """Jede Regel einmal auslösen und einmal nicht – so fällt auf, wenn eine Regel bricht."""
    proben = {
        "gut": ('extends Node\n## Kurz.\n\nfunc a() -> void:\n\tvar s := load("res://x.gd")\n', []),
        "kopf": ('extends Node\nvar a := 1\n', ["kopf"]),
        "tabs": ('extends Node\n## K.\nfunc a() -> void:\n    pass\n', ["tabs"]),
        "leer": ('extends Node\n## K.\nvar a := 1 \n', ["leerzeichen"]),
        "lang": ('extends Node\n## K.\nvar a := [' + ", ".join(["1"] * 60) + ']\n', ["laenge"]),
        "langer_text": ('extends Node\n## K.\nvar a := "' + "x" * 170 + '"\n', []),
        "str_to_var": ('extends Node\n## K.\nfunc a(t: String) -> void:\n\tvar v = str_to_var(t)\n', ["verboten"]),
        "objekte": ('extends Node\n## K.\nfunc a(b: PackedByteArray) -> void:\n\tbytes_to_var_with_objects(b)\n', ["verboten"]),
        "expression": ('extends Node\n## K.\nfunc a() -> void:\n\tvar e := Expression.new()\n', ["verboten"]),
        "load": ('extends Node\n## K.\nfunc a(p: String) -> void:\n\tload(p)\n', ["verboten"]),
        "text": ('extends Node\n## K.\nconst T := """\n    eingerückt   \n"""\n', []),
        "im_text": ('extends Node\n## K.\nvar t := "str_to_var(x) # kein Aufruf"\n', []),
        "federn": ('extends Node\n## K.\nfunc a(t: Tween) -> void:\n\tt.set_trans(Tween.TRANS_BACK)\n', ["federn"]),
        "federn_kommentar": ('extends Node\n## K.\nvar a := 1  # kein TRANS_BACK\n', []),
        "pool": ('extends Node\n## K.\nfunc a() -> void:\n\tWorkerThreadPool.add_task(a)\n', ["pool"]),
        "pool_laden": ('extends Node\n## K.\nfunc a() -> void:\n\tResourceLoader.load_threaded_request("res://x.gd")\n', ["pool"]),
        "netz": ('extends Node\n## K.\nfunc a() -> void:\n\tvar r := HTTPRequest.new()\n\tadd_child(r)\n', ["netz"]),
        "netz_code": ('extends Node\n## K.\nfunc a(r: int) -> bool:\n\treturn r == HTTPRequest.RESULT_SUCCESS\n', []),
        "probe_env": ('extends Node\n## K.\nfunc a() -> String:\n\treturn OS.get_environment("UZAI_TWITCH_API")\n', ["probe-env"]),
        "probe_env_daten": ('extends Node\n## K.\nfunc a() -> String:\n\treturn OS.get_environment("UZAI_DATA") + Config.probe_env("UZAI_TWITCH_API")\n', []),
    }
    falsch = 0
    for name, (src, erwartet) in proben.items():
        f, _ = pruefen("probe.gd", src)
        regeln = sorted({r for _, r, _ in f})
        if regeln != sorted(erwartet):
            falsch += 1
            print("Selbsttest %s: erwartet %s, bekommen %s" % (name, erwartet, regeln))
    takt = 'extends Node\n## K.\nfunc a(t: Tween, n: Node) -> void:\n\tt.tween_property(n, "x", 1.0, 0.25)\n' \
        '\tt.tween_property(n, "x", 1.0, U.T_ORT)\n\tt.tween_method(func(v: float) -> void:\n\t\tn.x = v\n\t, 0.0, 1.0, 0.5)\n'
    _, w = pruefen("probe.gd", takt)
    if sorted(nr for nr, r, _ in w if r == "takt") != [4, 6]:
        falsch += 1
        print("Selbsttest takt: erwartet Warnungen in Zeile 4 und 6, bekommen %s" % [nr for nr, r, _ in w if r == "takt"])
    umbruch = [
        '\tvar x := foo(' + ", ".join('"wert%d"' % i for i in range(30)) + ')',
        '\tif ' + " and ".join("bedingung_%d" % i for i in range(20)) + ':',
        '\tarr.map(func(x): return bar(' + ", ".join("a%d" % i for i in range(40)) + '))',
    ]
    # Rumpf eines mehrzeiligen Lambdas in Klammern: dort hängt alles an der Einrückung.
    rumpf = 'extends Node\n## K.\nfunc a() -> void:\n\tfoo(func() -> void:\n\t\tif ' + " and ".join("b%d" % i for i in range(40)) + ':\n\t\t\tpass\n\t)\n'
    if formatieren(rumpf)[0] != rumpf:
        falsch += 1
        print("Selbsttest Lambda-Rumpf: umbrochen, obwohl es nicht sicher ist")
    for k, z in enumerate(umbruch):
        src = 'extends Node\n## K.\nfunc a() -> void:\n' + z + '\n'
        neu, ok = formatieren(src)
        langes = [l for l in neu.split("\n") if len(l) > MAX_LEN]
        if not ok or langes:
            falsch += 1
            print("Selbsttest Umbruch %d: nicht wie erwartet" % k)
    print("Selbsttest: %s" % ("alles ok" if falsch == 0 else "%d Fehler" % falsch))
    return falsch == 0


def helfer_doppelt(pfad):
    """Befehle, die im switch von Invoke-Command-Json zweimal stehen: [(Name, erste Zeile, zweite Zeile)].

    PowerShell führt bei mehreren passenden Zweigen alle aus; der erste endet mit return, der zweite
    wird also nie erreicht (so standen 'proc-windows' und 'alive' lange doppelt da).
    """
    try:
        zeilen = open(pfad, encoding="utf-8").read().split("\n")
    except OSError:
        return []
    funde, gesehen, drin = [], {}, False
    zweig = re.compile(r"^        '([A-Za-z0-9_-]+)' \{")
    for nr, z in enumerate(zeilen, 1):
        if z.startswith("function Invoke-Command-Json"):
            drin = True
            continue
        if drin and z.startswith("}"):
            break
        m = zweig.match(z) if drin else None
        if m:
            if m.group(1) in gesehen:
                funde.append((m.group(1), gesehen[m.group(1)], nr))
            else:
                gesehen[m.group(1)] = nr
    return funde


def main(argv):
    wurzel = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    fix = "--fix" in argv
    if "--selbsttest" in argv:
        return 0 if selbsttest() else 1
    args = [a for a in argv if not a.startswith("--")]
    zeige_warn = "--warnungen" in argv
    n_fehler = n_warn = n_dateien = 0
    for p in dateien(args, wurzel):
        rel = os.path.relpath(p, wurzel).replace(os.sep, "/")
        with open(p, encoding="utf-8", newline="") as fh:
            src = fh.read()
        if fix:
            neu, ok = formatieren(src)
            if not ok:
                print("%s: Umbruch nicht sicher (Token weichen ab) – unverändert" % rel)
            elif neu != src:
                with open(p, "w", encoding="utf-8", newline="") as fh:
                    fh.write(neu)
                src = neu
        n_dateien += 1
        # Geprüft wird mit LF: Unter Windows checkt Git mit core.autocrlf (Standard, auch auf GitHubs Windows-Läufern)
        # mit CRLF aus. Das \r am Zeilenende zählte sonst als Zeichen und brach die Ausnahmen für lange Zeilen.
        f, w = pruefen(rel, src.replace("\r\n", "\n"))
        for nr, regel, text in f:
            print("%s:%d: %s: %s" % (rel, nr, regel, text))
        if zeige_warn:
            for nr, regel, text in w:
                print("%s:%d: Warnung %s: %s" % (rel, nr, regel, text))
        n_fehler += len(f)
        n_warn += len(w)
    if not args:
        # Eine Ausnahme, die nichts mehr betrifft, fällt auf statt still stehen zu bleiben.
        for key in sorted(set(AUSNAHMEN) - GENUTZT):
            print("%s: ausnahme: %s in %s wird nicht mehr gebraucht" % (key[0], key[2], key[1]))
            n_fehler += 1
        # Federn-Ausnahmen, die erledigt sind: nur Warnung (andere Pakete räumen in eigenen Dateien
        # auf, ohne hier zu ändern).
        for rel in sorted(set(FEDERN_AUSNAHMEN) - FEDERN_GENUTZT):
            if zeige_warn:
                print("%s: Warnung federn-alt: Ausnahme wird nicht mehr gebraucht (%s)" % (rel, FEDERN_AUSNAHMEN[rel]))
            n_warn += 1
        # Zustandsautomaten (src/core/zustand.gd, tools/zustaende.py): Tabellen, Zuweisungen, Übersicht.
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        sys.dont_write_bytecode = True   # kein tools/__pycache__ im Projekt
        import zustaende
        z_fehler, z_warn, _ = zustaende.alles(wurzel, schreiben=False)
        for ort, regel, text in z_fehler:
            print("%s: zustand-%s: %s" % (ort, regel, text))
        if zeige_warn:
            for ort, regel, text in z_warn:
                print("%s: Warnung zustand-%s: %s" % (ort, regel, text))
        n_fehler += len(z_fehler)
        n_warn += len(z_warn)
        # Helfer: kein Befehl zweimal im selben switch (der zweite Zweig würde nie erreicht).
        for name, erste, zweite in helfer_doppelt(os.path.join(wurzel, "helper", "uzai-helper.ps1")):
            print("helper/uzai-helper.ps1:%d: helfer-doppelt: Befehl '%s' steht schon in Zeile %d" % (zweite, name, erste))
            n_fehler += 1
    print("lint: %d Dateien, Fehler: %d, Warnungen: %d" % (n_dateien, n_fehler, n_warn))
    return 1 if n_fehler else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
