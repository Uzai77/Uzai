#!/usr/bin/env python3
# Klangsätze „Filz & Glas“, „Glas kurz“, „Filz“ und „Luft“: warme, musikalische Menüklänge, physikalisch angelehnt
# (modale Synthese: mehrere gedämpfte Teiltöne je Anschlag, weicher Anstieg, natürliches Abklingen,
# kurzer weicher Raum). Nur Python-Standardbibliothek (wave, struct, math, random mit festem
# Startwert): gleiche Quelle, gleiche Dateien. Keine Aufnahmen, keine fremden Samples.
#
#   python3 tools/synth_klang2.py                  rendert assets/sounds/<satz>/*.wav (44,1 kHz, Stereo,
#                                                  16 Bit) für alle Sätze (oder nur die genannten), druckt Messwerte und
#                                                  ergänzt assets/sounds/KLANG-QUELLE.txt (SHA-256)
#   python3 tools/synth_klang2.py --pruefen        prüft die Dateien gegen die Tabelle (Rückgabe 1 bei Abweichung)
#   python3 tools/synth_klang2.py --hoerprobe ordner [satz …]
#                                                  hoerprobe_<satz>.wav, hoerprobe_alle.wav und eine Tabelle
#
# Danach einmal: godot --headless --path . --import
#
# Warum nicht wie „Tick“: ein reiner Sinus bei 110–260 Hz ohne Obertöne, 1 ms Anstieg, mono, ohne Raum
# und für alle Klänge derselbe Grundklang – auf Fernsehlautsprechern bleibt davon ein dumpfes Klopfen.
# Hier hat jeder Anschlag mehrere Teiltöne, die höheren klingen schneller ab (der Klang wird beim
# Verklingen dunkler wie ein echter Körper), links und rechts sind eine Spur verstimmt (lebendig,
# breit), es gibt einen kleinen weichen Raum, und alle Töne kommen aus D-Dur pentatonisch (D E Fis A H),
# damit jede Folge zusammenpasst. Jeder Klang endet ungefähr mit seiner Bewegung.
import hashlib, math, os, random, struct, sys, wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUNDS = os.path.join(ROOT, "assets", "sounds")
QUELLE = os.path.join(SOUNDS, "KLANG-QUELLE.txt")
MARKE = "Klangsätze aus tools/synth_klang2.py"
MARKE3 = "Klangsatz „Perle“ aus tools/synth_klang3.py"

# Satz: Kennung → (Name, Pegel von „select“ als Kurzzeit-RMS in dBFS, Beschreibung).
# Zum Vergleich: „Glas“ liegt mit seiner Stärke (GAIN) bei etwa −25,6 dBFS, „Tick“ bei −27,5.
SAETZE = {
    "filzglas": ("Filz & Glas", -27.5, "der warme Körper von „Filz“ mit einem feinen, kürzeren Glas-Schimmer darüber (Standard)"),
    "glaskurz": ("Glas kurz", -28.0, "gläserne Glocken wie „Glas“, aber kurz, weich und leiser gestaffelt"),
    "filz": ("Filz", -27.5, "Holz-Marimba mit Filzschlägel: warm, rund, gedämpft"),
    "luft": ("Luft", -31.0, "gehauchte, leicht glockige Töne, sehr leise"),
}

# Die Tabelle (für alle Sätze gleich): Länge ms, Pegel dB (Kurzzeit-RMS zu „select“), Bewegung ms
# (wie Klang.PALETTE in src/core/klang.gd: Klang ≤ Bewegung + 60 ms), Ereignis.
NACHKLANG_MS = 60
BOOT_MAX_MS = 2000
TABELLE = [
    # name              ms   pegel  bewg.  Ereignis
    ("move",            90,  -11.0,   90, "Fokus"),
    ("tick",            70,  -12.0,   90, "Regler, Raste, Lautstärke"),
    ("bump",           160,   -8.0,  200, "Grenze erreicht"),
    ("select",         150,    0.0,   90, "Bestätigen"),
    ("back",           170,   -1.5,  160, "Zurück"),
    ("open",           300,    0.0,  360, "Ebene oder Seite auf (ersetzt select)"),
    ("toggle_on",      110,   -4.0,   90, "Schalter an"),
    ("toggle_off",     110,   -5.0,   90, "Schalter aus"),
    ("tab",            180,   -5.0,  200, "Bereich, Unterbereich, App"),
    ("guide",          260,    1.0,  200, "Guide auf (Signatur)"),
    ("guide_close",    200,   -2.5,  160, "Guide zu"),
    ("error",          240,    0.0,  200, "Fehler"),
    ("notify",         260,    0.0,  200, "Mitteilung"),
    ("launch",         420,    1.0,  360, "Spielen"),
    ("boot",          1900,    3.0, 2400, "Start-Signatur: Punkt 0,30 s, U 0,62 s, Name 1,08 s"),
    ("power_off",     1300,    0.0, 1400, "Ausschalten (Zeichen fällt ab 0,62 s)"),
    ("shutter",        160,   -4.0,  160, "Bildschirmfoto"),
    ("achievement",   1000,    2.0, 1000, "Erfolg"),
    ("unlock",         900,    2.0, 1000, "Abzeichen"),
    ("unlock_rare",   1200,    2.0, 1200, "seltenes Abzeichen"),
    ("unlock_retro",   800,    1.0, 1000, "Erfolg im Retro-Spiel"),
]
PEGEL_TOL_DB = 1.0
SPITZE_MAX_DB = -6.0      # in der Datei; der Begrenzer auf „UI“ (−3 dB) greift so nie
ENDE_MAX_DB = (-26.0, -36.0)  # die letzten 10 ms vor dem Ausblenden, zur Spitze (unter / ab 200 ms)

# --- Töne: D-Dur pentatonisch ------------------------------------------------------------------

_STUFEN = {"D": -7, "E": -5, "F#": -3, "A": 0, "B": 2}


def note(n):
    """„A4“ → 440 Hz (nur D, E, Fis, A, H)."""
    name, okt = n[:-1], int(n[-1])
    return 440.0 * 2.0 ** ((_STUFEN[name] + 12 * (okt - 4)) / 12.0)


# Motive (für „Glas kurz“ und „Luft“; „Filz“ eine Oktave tiefer): [(ms, Ton, dB[, τ höchstens s]), …].
MOTIV = {
    "move": [(0, "A5", 0)],
    "tick": [(0, "D6", 0)],
    "bump": [(0, "D4", 0)],
    "select": [(0, "D5", 0), (32, "A5", -1)],
    "back": [(0, "A5", -1), (32, "E5", 0)],
    "open": [(0, "D5", 0), (28, "A5", -1), (56, "D6", -5)],
    "toggle_on": [(0, "E5", -1), (24, "A5", 0)],
    "toggle_off": [(0, "A5", -1), (24, "E5", 0)],
    "tab": [(10, "F#5", 0)],
    "guide": [(0, "D5", 0), (22, "F#5", -1), (44, "A5", -2), (66, "D6", -5)],
    "guide_close": [(0, "A5", 0), (24, "F#5", -1), (48, "D5", -1)],
    "notify": [(0, "A5", 0), (110, "E6", -2)],
    "error": [(0, "A4", 0), (120, "F#4", 0)],
    "launch": [(0, "D5", 0), (40, "F#5", -1), (80, "A5", -2), (120, "D6", -3), (160, "F#6", -7)],
    # Start: jedes Bild beginnt mit seinem Ton (src/ui/boot.gd: DOT_AT, U_AT, NAME_AT); Punkt und U
    # klingen kurz genug, dass der nächste Ton frei einsetzt, der Name klingt bis zum Schluss.
    "boot": [(300, "D4", 0, 0.17), (300, "D5", -8, 0.12), (620, "A4", -4, 0.17), (1080, "F#5", -6), (1100, "D6", -11)],
    # Ausschalten: leiser Druck, dann fällt es abwärts, wenn das Zeichen zusammenfällt (power_off.gd: SQUASH ab 0,62 s).
    "power_off": [(0, "A5", -12, 0.08), (620, "D5", -2), (680, "A4", -4), (740, "D4", -5)],
    "shutter": [(0, "E6", 0), (60, "B5", -1)],
    "achievement": [(0, "D5", 0), (70, "F#5", 0), (140, "A5", 0), (210, "D6", -1)],
    "unlock": [(0, "A5", 0), (80, "D6", -1)],
    "unlock_rare": [(0, "D5", 0), (60, "A5", 0), (120, "D6", -1), (180, "F#6", -3), (240, "A6", -7)],
    "unlock_retro": [(0, "A5", 0), (90, "E6", -1)],
}
# Klänge, die länger nachklingen dürfen (Erfolge, Start): Abklingzeit × Faktor.
LANG = {"boot": 1.6, "power_off": 1.3, "achievement": 1.5, "unlock": 1.5, "unlock_rare": 1.5, "unlock_retro": 1.2}
# Leises Rauschen dazu (Luftzug beim Bereichswechsel und Spielstart): (Beginn ms, Dauer ms, von Hz, bis Hz, dB).
WISCH = {"tab": (0, 170, 700, 1700, -13.0), "launch": (0, 400, 400, 1600, -15.0)}


# --- Bausteine -------------------------------------------------------------------------------

def db(x):
    return 20.0 * math.log10(x) if x > 1e-12 else -240.0


def amp(d):
    return 10.0 ** (d / 20.0)


def biquad(x, kind, fc, q):
    """RBJ-Biquad: Tiefpass, Hochpass oder Bandpass (0 dB Spitze)."""
    w = 2.0 * math.pi * fc / SR
    cw, sw = math.cos(w), math.sin(w)
    al = sw / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:
        b0, b1, b2 = al, 0.0, -al
    a0, a1, a2 = 1 + al, -2 * cw, 1 - al
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def peak(x):
    return max((abs(v) for v in x), default=0.0)


def rms(x):
    return math.sqrt(sum(v * v for v in x) / len(x)) if x else 0.0


def add(buf, i0, part, gain=1.0):
    need = i0 + len(part)
    if need > len(buf):
        buf.extend([0.0] * (need - len(buf)))
    for i, v in enumerate(part):
        buf[i0 + i] += v * gain


def teilton(f, a, tau, att, n, bend=0.0, bend_tau=0.008):
    """Ein gedämpfter Teilton: Anstieg als halber Kosinus über att s, dann e^(−t/τ).
    bend: kurzer Tonhöhenfall beim Anschlag (Anteil, z. B. 0,006 = +0,6 % → 0)."""
    out = [0.0] * n
    ph = 0.0
    k = 2.0 * math.pi / SR
    na = max(1, int(att * SR))
    d = math.exp(-1.0 / (tau * SR))
    e = 1.0
    for i in range(n):
        if bend:
            ph += k * f * (1.0 + bend * math.exp(-i / (bend_tau * SR)))
        else:
            ph += k * f
        g = (0.5 - 0.5 * math.cos(math.pi * i / na)) if i < na else 1.0
        out[i] = a * g * e * math.sin(ph)
        e *= d
        if e < 1e-5:
            break
    return out


def rauschen(rng, n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def wisch(rng, n, f0, f1, q=1.4):
    """Luftzug: Rauschen durch einen mitlaufenden Bandpass (f0 → f1), Hülle sin². Spitze 1."""
    x = rauschen(rng, n)
    out = [0.0] * n
    lo = bp = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        fc = f0 * (f1 / f0) ** t
        fk = 2.0 * math.sin(math.pi * fc / SR)
        hi = x[i] - lo - bp / q
        bp += fk * hi
        lo += fk * bp
        out[i] = bp * math.sin(math.pi * t) ** 2
    out = biquad(biquad(out, "lp", 2600.0, 0.707), "lp", 2600.0, 0.707)    # weich, kein Zischen
    p = peak(out) or 1.0
    return [v / p for v in out]


# --- Stimmen -----------------------------------------------------------------------------------
# Jede Stimme gibt (links, rechts) für einen Anschlag zurück. f: Grundton, tau: Abklingen des
# Grundtons (s), hell: 0 … 1 (Anschlagstärke: die Obertöne wachsen mit), n: Länge in Samples.

CENT = 2.0 ** (1.0 / 1200.0)


def glas_stimme(rng, f, tau, hell, n, retro=False):
    # Gläserne Glocke: fast harmonische Teiltöne (leicht gestreckt wie ein steifer Körper), die
    # höheren klingen schneller ab. Kein harter Anschlag: 3 ms Anstieg.
    if retro:
        modi = [(1.0, 1.0, 1.0), (3.0, 0.30, 0.55), (5.0, 0.16, 0.35), (7.0, 0.09, 0.25)]
    else:
        modi = [(1.0, 1.0, 1.0), (2.004, 0.24 * hell, 0.45), (3.011, 0.08 * hell, 0.30),
                (4.03, 0.030 * hell, 0.22), (5.43, 0.012 * hell, 0.15)]
    seiten = []
    for c in (CENT ** -0.8, CENT ** 0.8):
        s = [0.0] * n
        for r, a, tf in modi:
            fr = f * r * c
            if fr > 9000.0:
                continue
            add(s, 0, teilton(fr, a, tau * tf, 0.003, n))
        seiten.append(s)
    return seiten[0], seiten[1]


def filz_stimme(rng, f, tau, hell, n, retro=False):
    # Holzstab (Marimba) mit Filzschlägel: Teiltöne 1 : 4 : 9,85 wie ein gestimmter Stab mit Bogenschnitt,
    # dazu ein Hauch Oktave (Resonanzrohr). Filz: 4,5 ms Anstieg, Obertöne leise und sehr kurz,
    # beim Anschlag ein kleiner Tonhöhenfall und ein dumpfer Filzstoß. Gedämpft: kurzes τ.
    if retro:
        modi = [(1.0, 1.0, 1.0), (3.0, 0.26, 0.5), (5.0, 0.12, 0.3)]
    else:
        modi = [(1.0, 1.0, 1.0), (4.0, 0.15 * hell, 0.26), (9.85, 0.025 * hell, 0.09), (2.0, 0.035, 0.6)]
    stoss = biquad(biquad(rauschen(rng, int(0.012 * SR)), "lp", 700.0, 0.7), "lp", 700.0, 0.7)
    sp = peak(stoss) or 1.0
    stoss = [v / sp * amp(-24.0) * math.exp(-i / (0.0035 * SR)) * min(1.0, i / (0.0015 * SR)) for i, v in enumerate(stoss)]
    seiten = []
    for c in (CENT ** -1.0, CENT ** 1.0):
        s = [0.0] * n
        for r, a, tf in modi:
            fr = f * r * c
            if fr > 9000.0:
                continue
            add(s, 0, teilton(fr, a, tau * tf, 0.0045, n, bend=0.006))
        add(s, 0, stoss[:n])
        seiten.append(s)
    return seiten[0], seiten[1]


def luft_stimme(rng, f, tau, hell, n, retro=False):
    # Gehauchter Ton: ein weicher Kern (Sinus, leise Oktave – leicht glockig), dazu Rauschen, das um
    # den Ton schwingt (schmaler Bandpass – wie über eine Flasche geblasen), und ein Hauch breiter
    # Luft. Links und rechts eigenes Rauschen: weit, aber nie leer auf einer Seite.
    if retro:
        modi = [(1.0, 0.75, 1.0), (3.0, 0.18, 0.5), (5.0, 0.08, 0.3)]
    else:
        modi = [(1.0, 0.70, 1.0), (2.002, 0.07 * hell, 0.5), (3.006, 0.02 * hell, 0.3)]
    seiten = []
    for k, c in enumerate((CENT ** -1.2, CENT ** 1.2)):
        s = [0.0] * n
        for r, a, tf in modi:
            add(s, 0, teilton(f * r * c, a, tau * tf, 0.005, n))
        m = n + int(0.02 * SR)
        # Bandbreite etwa 60 Hz: tief nicht wabernd, hoch noch deutlich ein Ton.
        ton = biquad(rauschen(rng, m), "bp", f * c, max(4.0, min(14.0, f / 60.0)))[-n:]
        g = 0.42 / (rms(ton) or 1.0) * (0.35 if retro else 1.0)
        breit = biquad(biquad(rauschen(rng, m), "bp", min(3000.0, 2.3 * f), 0.9), "lp", 3200.0, 0.707)[-n:]
        gb = 0.10 / (rms(breit) or 1.0)
        na = int(0.009 * SR)
        d1, d2 = math.exp(-1.0 / (tau * 0.8 * SR)), math.exp(-1.0 / (tau * 0.35 * SR))
        e1 = e2 = 1.0
        for i in range(n):
            a = 0.5 - 0.5 * math.cos(math.pi * i / na) if i < na else 1.0
            s[i] += a * (ton[i] * g * e1 + breit[i] * gb * e2)
            e1 *= d1
            e2 *= d2
        seiten.append(s)
    return seiten[0], seiten[1]


# „Filz & Glas“: Anteil des Glases an der Energie eines Anschlags und wie viel kürzer es abklingt.
GLAS_ANTEIL = 0.45   # more glass, for a slightly glassier sound (was 0.28)
GLAS_TAU = 0.75      # Schimmer klingt länger mit (vorher 0,5)


def filzglas_stimme(rng, f, tau, hell, n, retro=False):
    # Körper: der Filz-Anschlag (Grundton, tiefe Teiltöne, weicher Filzstoß) auf f. Darüber ein feiner
    # Schimmer aus „Glas kurz“ eine Oktave höher (also auf dem Ton von „Glas kurz“), der etwa doppelt so
    # schnell abklingt: hell im Anschlag, warm im Verklingen. Der Schimmer bekommt genau GLAS_ANTEIL
    # der Energie und keine Teiltöne über 7,5 kHz (nicht schrill). Der Körper ist derselbe wie bei „Filz“.
    kl, kr = filz_stimme(rng, f, tau, hell, n, retro)
    fg = 2.0 * f
    gl, gr = glas_stimme(rng, fg, tau * GLAS_TAU, hell, n, retro)
    gl = biquad(gl, "lp", 7500.0, 0.707)
    gr = biquad(gr, "lp", 7500.0, 0.707)
    ek = sum(v * v for v in kl) + sum(v * v for v in kr)
    eg = sum(v * v for v in gl) + sum(v * v for v in gr)
    g = math.sqrt(GLAS_ANTEIL / (1.0 - GLAS_ANTEIL) * ek / eg) if eg > 0 else 0.0
    return [a + b * g for a, b in zip(kl, gl)], [a + b * g for a, b in zip(kr, gr)]


STIMME = {"filzglas": filzglas_stimme, "glaskurz": glas_stimme, "filz": filz_stimme, "luft": luft_stimme}
# Abklingen des Grundtons höchstens (s) und Anteil der Länge bis zum Ende (τ = Rest / TEILER).
TAU_MAX = {"filzglas": 0.17, "glaskurz": 0.30, "filz": 0.16, "luft": 0.26}
TEILER = {"filzglas": 6.2, "glaskurz": 6.0, "filz": 6.2, "luft": 6.2}
# Raum: (Nachhall s, Anteil dB, Vorverzögerung ms).
RAUM = {"filzglas": (0.30, -16.5, 2.5), "glaskurz": (0.34, -15.0, 3.0), "filz": (0.22, -19.0, 2.0), "luft": (0.42, -13.0, 5.0)}
# Sätze mit dem Filz-Körper: eine Oktave tiefer, eigene Motive für Start und Ausschalten.
FILZ_ARTIG = ("filz", "filzglas")


# --- Raum ------------------------------------------------------------------------------------

def _kamm(x, d, g, damp):
    y = [0.0] * len(x)
    buf = [0.0] * d
    j = 0
    lp = 0.0
    for i, v in enumerate(x):
        o = buf[j]
        lp = o * (1.0 - damp) + lp * damp
        buf[j] = v + lp * g
        j = (j + 1) % d
        y[i] = o
    return y


def _allpass(x, d, g=0.5):
    """Echter Allpass (Schroeder): v = x + g·v[−d], y = −g·v + v[−d]."""
    y = [0.0] * len(x)
    buf = [0.0] * d
    j = 0
    for i, v in enumerate(x):
        b = buf[j]
        w = v + g * b
        buf[j] = w
        j = (j + 1) % d
        y[i] = b - g * w
    return y


def raum(l, r, satz, rt_faktor=1.0):
    """Kleiner, weicher Raum: erst vier Allpässe, die den Anschlag zu einem dichten Schleier
    verwischen (keine hörbaren Echos), dann vier kurze, gedämpfte Kämme und zwei Allpässe je
    Seite, links und rechts verschieden – das macht ihn breit. Kurze Klänge bekommen einen
    kürzeren Nachhall, damit er mit dem Klang endet."""
    rt, wet_db, pre = RAUM[satz]
    lang = len(l) / SR
    rt = min(rt * rt_faktor, 0.5 * lang)
    wet = amp(wet_db - (5.0 if lang < 0.2 else 0.0))
    out = []
    for x, diff, kaemme, aps in ((l, (4.71, 3.59, 1.27, 0.93), (11.3, 13.7, 15.9, 17.9), (5.1, 1.7)),
                                 (r, (4.43, 3.31, 1.39, 0.87), (12.1, 14.3, 16.7, 18.7), (5.6, 1.9))):
        n = len(x)
        ein = biquad(x, "lp", 3800.0, 0.707)
        ein = ([0.0] * int(pre * SR / 1000.0) + ein)[:n]
        for ms, g in zip(diff, (0.72, 0.72, 0.62, 0.62)):
            ein = _allpass(ein, max(1, int(ms * SR / 1000.0)), g)
        nass = [0.0] * n
        for ms in kaemme:
            d = int(ms * SR / 1000.0)
            g = 10.0 ** (-3.0 * (ms / 1000.0) / rt)
            k = 0.5 * math.sqrt(1.0 - g * g)     # gleiche Energie, egal wie lang der Nachhall
            for i, v in enumerate(_kamm(ein, d, g, 0.35)):
                nass[i] += v * k
        for ms in aps:
            nass = _allpass(nass, int(ms * SR / 1000.0))
        out.append([a + b * wet for a, b in zip(x, nass)])
    return out[0], out[1]


# --- Ein Klang -------------------------------------------------------------------------------

def pan(l, r, p):
    """Gleiche Leistung, p in −1 … 1 (nur kleine Werte: die Töne einer Folge wandern eine Spur)."""
    a = (p + 1.0) * math.pi / 4.0
    gl, gr = math.cos(a) * math.sqrt(2.0), math.sin(a) * math.sqrt(2.0)
    return [v * gl for v in l], [v * gr for v in r]


# „Filz“: eigene Fassung, wo die Oktave tiefer nicht passt (Ton unter Fis3 oder zwei gleiche Töne).
FILZ_MOTIV = {
    # Der Punkt mit warmem Grund (D3 und D4), dann A3, dann Fis4 und D5.
    "boot": [(300, "D3", -2, 0.2), (300, "D4", -3, 0.14), (620, "A3", -3, 0.17), (1080, "F#4", -4), (1100, "D5", -9)],
    "power_off": [(0, "A4", -12, 0.08), (620, "D4", -2), (680, "A3", -4), (740, "D3", -4)],
}


def motiv(satz, name):
    """[(ms, Hz, dB, τ höchstens oder None), …]."""
    if satz in FILZ_ARTIG and name in FILZ_MOTIV:
        return [(e[0], note(e[1]), e[2], e[3] if len(e) > 3 else None) for e in FILZ_MOTIV[name]]
    neu = []
    for e in MOTIV[name]:
        f = note(e[1])
        if satz in FILZ_ARTIG:
            # Eine Oktave tiefer, aber nie unter Fis3 (sonst bleibt auf Fernsehlautsprechern nichts übrig).
            f /= 2.0
            if f < 180.0:
                f *= 2.0
        neu.append((e[0], f, e[2], e[3] if len(e) > 3 else None))
    return neu


def baue(satz, name, ms):
    rng = random.Random("uzai-klang2-%s-%s" % (satz, name))
    n = int(round(ms * SR / 1000.0))
    L, R = [0.0] * n, [0.0] * n
    stimme = STIMME[satz]
    teile = motiv(satz, name)
    for k, (t_ms, f, d, tau_max) in enumerate(teile):
        # Ganz kleine, feste Unregelmäßigkeit (±1 ms, ±0,4 dB): klingt gespielt, nicht gestanzt.
        t_ms = max(0.0, t_ms + rng.uniform(-1.0, 1.0) * (1.0 if k else 0.0))
        d += rng.uniform(-0.4, 0.4)
        i0 = int(t_ms * SR / 1000.0)
        rest = (ms - t_ms) / 1000.0
        teiler = TEILER[satz] * (1.15 if ms < 200 else 1.0)    # kurze Klänge: schon vor dem Ausblenden leise
        tau = min(TAU_MAX[satz] * LANG.get(name, 1.0), rest / teiler * LANG.get(name, 1.0) ** 0.5)
        if tau_max:
            tau = min(tau, tau_max)
        if name == "bump":
            tau *= 0.7          # Rand: dumpfer, kürzer
        hell = min(1.0, amp(d) * (0.55 if name == "bump" else 1.0))
        l, r = stimme(rng, f, tau, hell, n - i0, retro=(name == "unlock_retro"))
        # Folgen wandern leicht von links nach rechts (aufwärts) – nie weiter als ±0,18.
        p = 0.0 if len(teile) == 1 else (-0.18 + 0.36 * k / (len(teile) - 1)) * (1 if f >= teile[0][1] else -1)
        l, r = pan(l, r, p)
        add(L, i0, l, amp(d))
        add(R, i0, r, amp(d))
    if name in WISCH:
        b, dauer, f0, f1, wd = WISCH[name]
        for buf, seite in ((L, 0), (R, 1)):
            w = wisch(random.Random("uzai-klang2-wisch-%s-%s-%d" % (satz, name, seite)), int(dauer * SR / 1000.0), f0, f1)
            add(buf, int(b * SR / 1000.0), w, amp(wd) * (0.6 if satz in FILZ_ARTIG else 1.0))
    if name == "shutter":
        # Verschluss: zwei kurze, dunkle Rauschstöße unter den Tönen.
        for t_ms in (0, 60):
            st = biquad(rauschen(rng, int(0.02 * SR)), "bp", 2400.0, 0.8)
            sp = peak(st) or 1.0
            st = [v / sp * math.exp(-i / (0.004 * SR)) * min(1.0, i / (0.0008 * SR)) * amp(-12.0) for i, v in enumerate(st)]
            add(L, int(t_ms * SR / 1000.0), st)
            add(R, int(t_ms * SR / 1000.0), st)
    if name == "bump":
        L = biquad(L, "lp", 1400.0, 0.707)
        R = biquad(R, "lp", 1400.0, 0.707)
    L, R = L[:n], R[:n]
    L, R = raum(L, R, satz, 1.3 if name in LANG else 1.0)
    return L, R


def fertig(L, R, ziel_db):
    """Ohne Gleichanteil, sanft ausblenden, auf den Pegel der Tabelle (Kurzzeit-RMS)."""
    L = biquad(L, "hp", 30.0, 0.707)
    R = biquad(R, "hp", 30.0, 0.707)
    n = len(L)
    fade = min(int(0.025 * SR), n // 4)
    for i in range(fade):
        g = 0.5 - 0.5 * math.cos(math.pi * i / fade)
        L[n - 1 - i] *= g
        R[n - 1 - i] *= g
    g = amp(ziel_db) / (10.0 ** (messen(L, R)[1] / 20.0))
    return [v * g for v in L], [v * g for v in R]


# --- Dateien ---------------------------------------------------------------------------------

def schreibe(pfad, l, r):
    with wave.open(pfad, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        data = bytearray()
        for a, b in zip(l, r):
            data += struct.pack("<hh", max(-32767, min(32767, int(round(a * 32767.0)))), max(-32767, min(32767, int(round(b * 32767.0)))))
        w.writeframes(bytes(data))


def lies(pfad):
    with wave.open(pfad, "rb") as w:
        ch, sw, fr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw != 2:
        raise ValueError("nur 16 Bit")
    s = struct.unpack("<%dh" % (n * ch), raw)
    l = [v / 32767.0 for v in s[0::ch]]
    r = [v / 32767.0 for v in s[1::ch]] if ch > 1 else l
    return l, r, fr, ch


def messen(l, r):
    """Spitze (dBFS), Kurzzeit-RMS (lautestes 50-ms-Fenster, dBFS), Länge (ms), Ende (dB zur Spitze:
    RMS der 10 ms vor dem Ausblenden), Anfang (erster Wert), größter Sprung (zweite Differenz zur Spitze)."""
    p = max(peak(l), peak(r)) or 1e-9
    win = int(0.05 * SR)
    step = int(0.005 * SR)
    sq = [(a * a + b * b) / 2.0 for a, b in zip(l, r)]
    acc = [0.0]
    for v in sq:
        acc.append(acc[-1] + v)
    best = 0.0
    n = len(sq)
    for i in range(0, max(1, n - win + 1), step):
        j = min(n, i + win)
        best = max(best, (acc[j] - acc[i]) / win)
    fade = min(int(0.025 * SR), n // 4)
    a, b = max(0, n - fade - int(0.01 * SR)), n - fade
    ende = math.sqrt((acc[b] - acc[a]) / max(1, b - a)) / p
    sprung = 0.0
    for x in (l, r):
        for i in range(2, n):
            sprung = max(sprung, abs(x[i] - 2.0 * x[i - 1] + x[i - 2]))
    return db(p), db(math.sqrt(best)), n * 1000.0 / SR, db(ende), max(abs(l[0]), abs(r[0])), sprung / p


def sha(pfad):
    with open(pfad, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def quelle_schreiben():
    """Ergänzt KLANG-QUELLE.txt: alles vor MARKE bleibt (Tick, Glas), danach die Sätze von hier."""
    alt = ""
    if os.path.isfile(QUELLE):
        with open(QUELLE, encoding="utf-8") as f:
            alt = f.read()
    # Der Satz „Perle“ (tools/synth_klang3.py) steht dahinter und bleibt.
    danach = ""
    if MARKE3 in alt:
        danach = alt[alt.index(MARKE3):]
        alt = alt[:alt.index(MARKE3)]
    if MARKE in alt:
        alt = alt[:alt.index(MARKE)]
    zeilen = [MARKE + ": „Filz & Glas“ (filzglas/), „Glas kurz“ (glaskurz/), „Filz“ (filz/) und „Luft“ (luft/).",
              "Nur Python-Standardbibliothek, feste Startwerte (gleiche Quelle, gleiche Dateien). 44,1 kHz, Stereo, 16 Bit.",
              ""]
    for satz in SAETZE:
        for name, *_ in TABELLE:
            p = os.path.join(SOUNDS, satz, name + ".wav")
            if os.path.isfile(p):
                zeilen.append("%s  %s/%s.wav" % (sha(p), satz, name))
        zeilen.append("")
    with open(QUELLE, "w", encoding="utf-8", newline="\n") as f:
        f.write(alt.rstrip("\n") + "\n\n" + "\n".join(zeilen) + (("\n" + danach) if danach else ""))


def rendern(nur=None):
    for satz, (titel, ref, _) in SAETZE.items():
        if nur and satz not in nur:
            continue
        ordner = os.path.join(SOUNDS, satz)
        os.makedirs(ordner, exist_ok=True)
        print("Satz „%s“ (%s)" % (titel, satz))
        print("  %-13s %7s %8s %8s %8s %8s" % ("Klang", "Länge", "Spitze", "RMS", "RMS/sel", "Ende"))
        for name, ms, pegel, *_ in TABELLE:
            L, R = fertig(*baue(satz, name, ms), ref + pegel)
            schreibe(os.path.join(ordner, name + ".wav"), L, R)
            p, r, n, ende, _, _ = messen(L, R)
            print("  %-13s %5.0f ms %6.1f dB %6.1f dB %+7.1f dB %6.1f dB" % (name, n, p, r, r - ref, ende))
    quelle_schreiben()


def pruefen():
    fehler = 0
    for satz, (titel, ref, _) in SAETZE.items():
        werte = {}
        for name, ms, pegel, bew, _ in TABELLE:
            pfad = os.path.join(SOUNDS, satz, name + ".wav")
            if not os.path.isfile(pfad):
                print("  FAIL %s/%s fehlt" % (satz, name))
                fehler += 1
                continue
            l, r, fr, ch = lies(pfad)
            if fr != SR or ch != 2:
                print("  FAIL %s/%s: %d Hz, %d Kanäle (soll 44100, 2)" % (satz, name, fr, ch))
                fehler += 1
            werte[name] = messen(l, r)
            p, rm, n, ende, anfang, sprung = werte[name]
            grenze = BOOT_MAX_MS if name == "boot" else bew + NACHKLANG_MS
            pruef = [
                (abs(n - ms) <= 1.0, "Länge %.0f ms (soll %d)" % (n, ms)),
                (n <= grenze, "Länge ≤ %d ms" % grenze),
                (abs(rm - (ref + pegel)) <= PEGEL_TOL_DB, "RMS %.1f dBFS (soll %.1f ± %.1f)" % (rm, ref + pegel, PEGEL_TOL_DB)),
                (p <= SPITZE_MAX_DB, "Spitze %.1f dBFS ≤ %.0f" % (p, SPITZE_MAX_DB)),
                (ende <= ENDE_MAX_DB[0 if ms < 200 else 1], "verklungen vor dem Ausblenden (%.0f dB)" % ende),
                (anfang < 0.002, "beginnt bei null (kein Knacken)"),
            ]
            for ok, was in pruef:
                if not ok:
                    print("  FAIL %s/%s: %s" % (satz, name, was))
                fehler += 0 if ok else 1
        if "power_off" in werte:
            lauter = [k for k in werte if werte[k][1] > werte["power_off"][1] + 0.01]
            if not (werte["power_off"][1] <= werte["boot"][1] and lauter):
                print("  FAIL %s: Ausschalten ist der lauteste Klang" % satz)
                fehler += 1
    print("Ergebnis: %s" % ("alles ok" if fehler == 0 else "%d Fehler" % fehler))
    return 1 if fehler else 0


# --- Hörprobe --------------------------------------------------------------------------------
# Wie in Uzai gemischt: Standardregler 0,6 × 0,75, Bewegen nach Klang.bewegen (beim schnellen
# Drücken bis −8 dB leiser, Tonhöhe ±1,5 %, Lautstärke ±0,5 dB, schneidet den eigenen Nachklang ab),
# „tab“ aus der Richtung (±0,3), danach der Tiefpass der Leitung „UI“ (5,2 kHz).

ABLAUF = [("move", 0.0)] + [("move", a) for a in (0.16, 0.16, 0.14, 0.12, 0.12)] + [
    ("select", None), ("back", None), ("tab", None), ("tab", 0.45), ("open", None), ("guide", None),
    ("guide_close", None), ("notify", None), ("error", None), ("toggle_on", None), ("toggle_off", None),
    ("launch", None), ("boot", None)]
PAUSE = 0.5
REGLER = 0.6 * 0.75


def _balance(l, r, p):
    return [v * (1.0 - max(p, 0.0)) for v in l], [v * (1.0 + min(p, 0.0)) for v in r]


def hoerprobe_satz(satz, ordner_dateien):
    rng = random.Random("hoerprobe-" + satz)
    L, R = [0.0] * int(0.3 * SR), [0.0] * int(0.3 * SR)
    t = 0.3
    ende_vorher = t
    zeilen = []
    letzter_move = None     # (Beginn-Index, Länge) des laufenden „move“
    reihe = 0
    tabs = 0
    for name, abstand in ABLAUF:
        l, r, _, _ = lies(os.path.join(ordner_dateien, name + ".wav"))
        if abstand is None:
            t = ende_vorher + PAUSE
        else:
            t = t + abstand
        extra = 0.0
        pitch = 1.0
        p = 0.0
        if name == "move":
            if abstand and abstand * 1000 < 260:
                reihe += 1
            else:
                reihe = 0
            extra = -8.0 * min(reihe / 4.0, 1.0) + rng.uniform(-0.5, 0.5)
            pitch = 1.0 + rng.uniform(-1.0, 1.0) * 0.015
        if name == "tab":
            p = 0.3 if tabs == 0 else -0.3
            tabs += 1
        if pitch != 1.0:
            m = int(len(l) / pitch)
            l = [l[min(int(j * pitch), len(l) - 1)] for j in range(m)]
            r = [r[min(int(j * pitch), len(r) - 1)] for j in range(m)]
        l, r = _balance(l, r, p)
        i0 = int(t * SR)
        if name == "move" and letzter_move is not None:
            # Der neue Tupfer nimmt den alten weg (in Uzai gleitet die Lautstärke über den Mischpuffer).
            a, lang = letzter_move
            f = int(0.004 * SR)
            for i in range(i0, min(a + lang, len(L))):
                g = max(0.0, 1.0 - (i - i0) / f)
                L[i] *= g
                R[i] *= g
        g = REGLER * amp(extra)
        add(L, i0, l, g)
        add(R, i0, r, g)
        if name == "move":
            letzter_move = (i0, len(l))
        zeilen.append((t, name, len(l) / SR))
        ende_vorher = max(ende_vorher, t + len(l) / SR)
    n = int((ende_vorher + 0.6) * SR)
    L += [0.0] * (n - len(L))
    R += [0.0] * (n - len(R))
    L = biquad(L, "lp", 5200.0, 0.707)
    R = biquad(R, "lp", 5200.0, 0.707)
    return L, R, zeilen


def _k(x, nd=1):
    """Zahl mit Komma (deutsch)."""
    return ("%%.%df" % nd % x).replace(".", ",")


def hoerprobe(ziel, nur=None):
    os.makedirs(ziel, exist_ok=True)
    alle_l, alle_r = [], []
    saetze = [(k, v) for k, v in SAETZE.items() if not nur or k in nur]
    tab = ["# Hörproben der Klangsätze " + ", ".join("„%s“" % v[0] for _, v in saetze), "",
           "Gemischt wie in Uzai mit dem Standardregler (0,6 × 0,75 ≈ −7 dB), Bewegen nach den Regeln aus",
           "`klang.gd` (schnell gedrückt: bis −8 dB leiser, Tonhöhe ±1,5 %), „tab“ einmal von rechts, einmal von",
           "links, danach der Tiefpass der Leitung „UI“ (5,2 kHz). Zwischen den Klängen 0,5 s Pause.", ""]
    for k, (satz, (titel, ref, was)) in enumerate(saetze):
        L, R, zeilen = hoerprobe_satz(satz, os.path.join(SOUNDS, satz))
        pfad = os.path.join(ziel, "hoerprobe_%s.wav" % satz)
        schreibe(pfad, L, R)
        start = len(alle_l) / SR
        if k:
            start += 1.0
            alle_l += [0.0] * SR
            alle_r += [0.0] * SR
        alle_l += L
        alle_r += R
        p, rm, n, _, _, _ = messen(L, R)
        print("Hörprobe: %s %.1f s, Spitze %.1f dBFS" % (pfad, n / 1000.0, p))
        tab += ["## %s – `hoerprobe_%s.wav` (%s s; in `hoerprobe_alle.wav` ab %s s)" % (titel, satz, _k(n / 1000.0), _k(start)), "",
                was[0].upper() + was[1:] + ".", "",
                "| ab (Datei) | ab (alle) | Klang | Dauer |", "|---|---|---|---|"]
        for t, name, d in zeilen:
            tab.append("| %s s | %s s | %s | %.0f ms |" % (_k(t, 2), _k(start + t, 2), name, d * 1000))
        tab.append("")
    schreibe(os.path.join(ziel, "hoerprobe_alle.wav"), alle_l, alle_r)
    print("Hörprobe: %s %.1f s" % (os.path.join(ziel, "hoerprobe_alle.wav"), len(alle_l) / SR))
    with open(os.path.join(ziel, "hoerprobe_tabelle.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(tab) + "\n")


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--pruefen" in a:
        sys.exit(pruefen())
    if "--hoerprobe" in a:
        hoerprobe(a[a.index("--hoerprobe") + 1], [x for x in a if x in SAETZE] or None)
        sys.exit(0)
    rendern([x for x in a if x in SAETZE] or None)
