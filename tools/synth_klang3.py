#!/usr/bin/env python3
# Klangsatz „Perle“: präzise, physische Menüklänge mit einem gläsernen Kern und Luft (Standard bis 0.16;
# dann „Samt“ aus tools/synth_klang4.py, heute „Handpan“ aus tools/synth_klang5.py, das auch die Klänge der
# Einrichtung rendert).
# Nur Python-Standardbibliothek (wave, struct, math, random mit festem Startwert): gleiche Quelle,
# gleiche Dateien. Keine Aufnahmen, keine fremden Samples.
#
#   python3 tools/synth_klang3.py                  rendert assets/sounds/perle/*.wav (44,1 kHz, Stereo, 16 Bit),
#                                                  druckt Messwerte, ergänzt assets/sounds/KLANG-QUELLE.txt (SHA-256)
#   python3 tools/synth_klang3.py --pruefen        prüft die Dateien gegen die Tabelle (Rückgabe 1 bei Abweichung)
#   python3 tools/synth_klang3.py --hoerprobe a.wav
#                                                  alle Klänge hintereinander, gemischt wie in Uzai (dazu a.md)
#
# Danach einmal: godot --headless --path . --import
#
# Die Idee: Jeder Klang ist aus drei Schichten gebaut, die man an einem guten Gerät spürt.
# 1. Anschlag: ein sehr kurzer Rauschimpuls (0,4–1,5 ms, Bandpass 1,8–4,5 kHz) und ein „Tap“ – ein
#    Sinus mit steilem Tonhöhenfall in 1–3 ms. Das ist das Physische (eine Taste, die einrastet), und es
#    liegt genau dort, wo Fernsehlautsprecher gut sind. „select“ hat zwei Anschläge (Drücken, 8–12 ms
#    später Einrasten), daher das befriedigende „Klick“.
# 2. Kern: ein gläserner Ton (FM mit schnell fallendem Index: hell im Anschlag, rein im Verklingen,
#    dazu leise Teiltöne eines Glasstabs 2 : 2,76 : 5,4), mit einem winzigen Tonhöhenfall beim Anschlag.
#    Darunter eine leise Tiefe (Tap eine bis zwei Oktaven tiefer, sehr kurz): Gewicht ohne Klopfen.
# 3. Luft und Raum: gefiltertes Rauschen, dessen Bandpass mit der Bewegung wandert (Öffnen, Guide,
#    Reiter, Einfliegen), weiche Flächen aus verstimmten Stimmen mit sich öffnendem Filter (Start, Spielen,
#    Abschluss, „Licht an“), ein kleiner heller Raum, links und rechts eine Spur verschieden.
# Alle Töne aus E-Dur pentatonisch (E Fis Gis H Cis): jede Folge passt zusammen, auch durcheinander.
# Bewegen, Raste, Bestätigen, Zurück, Schalter, Rand und Reiter gibt es in 2–4 Fassungen (Datei
# <name>.wav, <name>_v2.wav, …): Sfx wählt zufällig, nie zweimal dieselbe hintereinander.
import hashlib, math, os, random, struct, sys, wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUNDS = os.path.join(ROOT, "assets", "sounds")
SATZ = "perle"
ORDNER = os.path.join(SOUNDS, SATZ)
QUELLE = os.path.join(SOUNDS, "KLANG-QUELLE.txt")
MARKE = "Klangsatz „Perle“ aus tools/synth_klang3.py"

# Pegel von „select“ als Kurzzeit-RMS (lautestes 50-ms-Fenster) in dBFS. „Filz & Glas“ liegt bei −27,5;
# die Anschläge hier haben mehr Spitze je Energie, darum etwas tiefer (Spitze von „select“ um −19 dBFS).
REF_DB = -29.5

# Die Tabelle: Länge ms, Pegel dB (Kurzzeit-RMS zu „select“), Bewegung ms (wie Klang.PALETTE in
# src/core/klang.gd: Klang ≤ Bewegung + 60 ms), Fassungen, Ereignis.
NACHKLANG_MS = 60
BOOT_MAX_MS = 2000
TABELLE = [
    # name              ms   pegel  bewg.  fass.  Ereignis
    ("move",            65,  -12.0,   90,   4, "Fokus"),
    ("tick",            50,  -13.0,   90,   3, "Regler, Raste, Lautstärke"),
    ("bump",           150,   -8.0,  200,   2, "Grenze erreicht"),
    ("select",         140,    0.0,   90,   3, "Bestätigen: Drücken und Einrasten"),
    ("back",           170,   -2.0,  160,   2, "Zurück: abwärts, weicher"),
    ("open",           340,    0.0,  360,   1, "Ebene oder Seite auf (ersetzt select)"),
    ("toggle_on",      120,   -4.0,   90,   2, "Schalter an"),
    ("toggle_off",     110,   -5.0,   90,   2, "Schalter aus"),
    ("tab",            200,   -5.0,  200,   2, "Bereich, Unterbereich, App"),
    ("guide",          260,    1.0,  200,   1, "Guide auf (Signatur)"),
    ("guide_close",    210,   -2.5,  160,   1, "Guide zu"),
    ("error",          250,   -1.0,  200,   1, "Fehler"),
    ("notify",         260,   -1.0,  200,   1, "Mitteilung"),
    ("launch",         420,    1.0,  360,   1, "Spielen"),
    ("boot",          1950,    3.0, 2400,   1, "Start-Signatur: Punkt 0,30 s, U 0,62 s, Name 1,08 s"),
    ("power_off",     1350,    0.0, 1400,   1, "Ausschalten (Zeichen fällt ab 0,62 s)"),
    ("shutter",        170,   -4.0,  160,   1, "Bildschirmfoto"),
    ("achievement",   1050,    2.0, 1000,   1, "Erfolg"),
    ("unlock",         950,    2.0, 1000,   1, "Abzeichen"),
    ("unlock_rare",   1250,    2.0, 1200,   1, "seltenes Abzeichen"),
    ("unlock_retro",   850,    1.0, 1000,   1, "Erfolg im Retro-Spiel"),
    ("setup_step",     200,   -2.0,  200,   1, "Einrichtung: Schritt weiter (aufsteigend: Klang.stufe_ton)"),
    ("setup_found",    420,   -3.0,  400,   1, "Einrichtung: etwas gefunden, fliegt ein (Glitzern)"),
    ("setup_done",    1200,    2.0, 1200,   1, "Einrichtung: fertig (kurzer Akkord)"),
    ("swell",         1500,    0.0, 1500,   1, "Licht geht an (Anschwellen)"),
]
PEGEL_TOL_DB = 1.0

# Die Klänge der Einrichtung (assets/sounds/einrichtung) rendert tools/synth_klang5.py (im Charakter von
# „Handpan“); die Hörprobe hier spielt sie weiter mit.
EINR = "einrichtung"
EINR_ORDNER = os.path.join(SOUNDS, EINR)
MARKE4 = "Klangsätze aus tools/synth_klang4.py"
SPITZE_MAX_DB = -6.0          # in der Datei; der Begrenzer auf „UI“ (−3 dB) greift so nie
ENDE_MAX_DB = (-26.0, -36.0)  # die letzten 10 ms vor dem Ausblenden, zur Spitze (unter / ab 200 ms)
BAND_MIN = 0.55               # Anteil der Energie zwischen 300 Hz und 4 kHz (Fernsehlautsprecher)
KORR_MIN = 0.55               # Stereo dezent: Korrelation links/rechts mindestens
VORLAUF_MS = 1.0              # jede Datei beginnt mit 1 ms Stille (beginnt sicher bei null)


def datei(name, k):
    """Dateiname der k-ten Fassung (0: <name>.wav, sonst <name>_v<k+1>.wav)."""
    return name + (".wav" if k == 0 else "_v%d.wav" % (k + 1))


# --- Töne: E-Dur pentatonisch --------------------------------------------------------------------

_STUFEN = {"D": -7, "E": -5, "F#": -3, "G#": -1, "A": 0, "B": 2, "C#": 4}


def note(n):
    """„E5“ → 659,3 Hz (E-Dur pentatonisch E Fis Gis H Cis; für die Einrichtung D-Dur pentatonisch D E Fis A H)."""
    name, okt = n[:-1], int(n[-1])
    return 440.0 * 2.0 ** ((_STUFEN[name] + 12 * (okt - 4)) / 12.0)


CENT = 2.0 ** (1.0 / 1200.0)


# --- Bausteine -----------------------------------------------------------------------------------

def db(x):
    return 20.0 * math.log10(x) if x > 1e-12 else -240.0


def amp(d):
    return 10.0 ** (d / 20.0)


def ns(ms):
    return int(round(ms * SR / 1000.0))


def biquad(x, kind, fc, q=0.707):
    """RBJ-Biquad: Tiefpass, Hochpass oder Bandpass (0 dB Spitze)."""
    w = 2.0 * math.pi * min(fc, 0.45 * SR) / SR
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


def norm(x):
    p = peak(x) or 1.0
    return [v / p for v in x]


def add(buf, i0, part, gain=1.0):
    need = i0 + len(part)
    if need > len(buf):
        buf.extend([0.0] * (need - len(buf)))
    for i, v in enumerate(part):
        buf[i0 + i] += v * gain


def rauschen(rng, n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def anstieg(i, na):
    return 0.5 - 0.5 * math.cos(math.pi * i / na) if i < na else 1.0


def tau_bis(rest_ms, tief_db=40.0):
    """Abklingzeit (s), mit der ein Ton in rest_ms um tief_db fällt."""
    return max(0.002, rest_ms / 1000.0 / (tief_db / 8.686))


# Teiltöne (Verhältnis, Amplitude, Abklingen als Anteil von τ). „glas“: ein Glasstab, dazu die Oktave
# (macht den Ton rund wie eine Perle statt spitz); „weich“: fast nur Grundton; „retro“: ungerade (Rechteck).
MODI = {
    "glas": [(1.0, 1.0, 1.0), (2.0, 0.16, 0.55), (2.756, 0.09, 0.35), (5.404, 0.03, 0.16)],
    "hell": [(1.0, 1.0, 1.0), (2.0, 0.22, 0.5), (2.756, 0.14, 0.32), (5.404, 0.05, 0.15)],
    "weich": [(1.0, 1.0, 1.0), (2.0, 0.08, 0.5), (3.0, 0.02, 0.3)],
    "retro": [(1.0, 1.0, 1.0), (3.0, 0.33, 0.8), (5.0, 0.2, 0.6), (7.0, 0.14, 0.45), (9.0, 0.11, 0.35)],
    # Gestimmter Holzstab (Marimba): 1 : 3,93 : 9,2, dazu ein Hauch Oktave vom Resonanzrohr.
    "marimba": [(1.0, 1.0, 1.0), (3.93, 0.22, 0.28), (9.2, 0.05, 0.1), (2.0, 0.05, 0.7)],
}


def ton(f, ms, tau, att_ms=1.5, modi="glas", fm=None, bend=0.004, bend_ms=4.0, cent=0.0):
    """Ein tonaler Anschlag: Teiltöne mit eigenem Abklingen, weicher Anstieg (halber Kosinus über
    att_ms), kleiner Tonhöhenfall (bend: Anteil, fällt mit bend_ms). fm: (Verhältnis, Index, Index-τ ms)
    auf den Grundton – hell im Anschlag, rein im Verklingen. Spitze ≈ 1."""
    n = ns(ms)
    out = [0.0] * n
    f *= CENT ** cent
    k = 2.0 * math.pi / SR
    na = max(1, ns(att_ms))
    db_ = math.exp(-1.0 / max(1.0, bend_ms * SR / 1000.0))
    for r, a, tf in MODI[modi]:
        fr = f * r
        if fr > 7500.0:
            continue
        d = math.exp(-1.0 / (tau * tf * SR))
        e, ph, phm, bb = 1.0, 0.0, 0.0, bend
        if fm and r == 1.0:
            ratio, idx, itau = fm
            di = math.exp(-1.0 / (itau * SR / 1000.0))
            ii = idx
        else:
            ratio = 0.0
        for i in range(n):
            inc = k * fr * (1.0 + bb)
            bb *= db_
            ph += inc
            if ratio:
                phm += inc * ratio
                v = math.sin(ph + ii * math.sin(phm))
                ii *= di
            else:
                v = math.sin(ph)
            out[i] += a * anstieg(i, na) * e * v
            e *= d
            if e < 1e-5:
                break
    return out


def klick(rng, fc, tau_ms=0.6, q=1.1, att_ms=0.25):
    """Der Anschlag: Rauschimpuls durch einen Bandpass um fc, Anstieg att_ms, Abklingen tau_ms. Spitze 1."""
    n = ns(att_ms + tau_ms * 9.0 + 2.0)
    x = biquad(biquad(rauschen(rng, n), "bp", fc, q), "bp", fc, q)
    na = max(1, ns(att_ms))
    d = math.exp(-1.0 / (tau_ms * SR / 1000.0))
    out, e = [0.0] * n, 1.0
    for i in range(n):
        out[i] = x[i] * anstieg(i, na) * (e if i >= na else 1.0)
        if i >= na:
            e *= d
    return norm(out)


def tap(f, tau_ms, fall=1.8, fall_ms=1.2, att_ms=0.25):
    """Ein „Tap“ wie eine Haptik-Rückmeldung: Sinus, der in fall_ms von f × fall auf f fällt, sehr kurz. Spitze 1."""
    n = ns(att_ms + tau_ms * 8.0)
    out = [0.0] * n
    k = 2.0 * math.pi / SR
    na = max(1, ns(att_ms))
    d = math.exp(-1.0 / (tau_ms * SR / 1000.0))
    df = math.exp(-1.0 / (fall_ms * SR / 1000.0))
    ph, e, b = 0.0, 1.0, fall - 1.0
    for i in range(n):
        ph += k * f * (1.0 + b)
        b *= df
        out[i] = math.sin(ph) * anstieg(i, na) * e
        e *= d
    return norm(out)


def hauch(rng, ms, f0, f1, q=1.3, auf=0.4):
    """Luft: Rauschen durch einen mitlaufenden Bandpass (f0 → f1, exponentiell). Hülle: sin² bis zum
    Anteil auf, dann cos² bis null. Spitze 1."""
    n = ns(ms)
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
        e = math.sin(0.5 * math.pi * t / auf) ** 2 if t < auf else math.cos(0.5 * math.pi * (t - auf) / (1.0 - auf)) ** 2
        out[i] = bp * e
    return norm(biquad(out, "lp", 5000.0))


def flaeche(rng, freqs, ms, auf_ms, ab_ms, hell0=1.2, hell1=3.0, ab_ab=None, verst=7.0):
    """Weiche Fläche: je Ton drei Stimmen (−verst, 0, +verst Cent; links, Mitte, rechts), sägezahnartige
    Teiltöne bis 8, deren Helligkeit von hell0 nach hell1 wandert (Filter öffnet sich). Anstieg auf_ms
    (halber Kosinus), Ende ab_ms vor Schluss beginnend (oder ab ab_ab ms) bis null. Gibt (L, R), Spitze ≈ 1."""
    n = ns(ms)
    L, R = [0.0] * n, [0.0] * n
    k = 2.0 * math.pi / SR
    na = max(1, ns(auf_ms))
    a_beg = ns(ab_ab) if ab_ab is not None else n - ns(ab_ms)
    a_len = max(1, min(ns(ab_ms), n - a_beg))
    BLOCK = 32
    hull = [0.0] * n
    for i in range(n):
        g = anstieg(i, na)
        if i >= a_beg:
            j = i - a_beg
            g *= 0.5 + 0.5 * math.cos(math.pi * min(1.0, j / a_len))
        hull[i] = g
    for f in freqs:
        for v, (c, gl, gr) in enumerate(((-verst, 1.25, 0.55), (0.0, 0.9, 0.9), (verst, 0.55, 1.25))):
            fv = f * CENT ** c
            ph0 = rng.uniform(0.0, 2.0 * math.pi)
            for h in range(1, 9):
                fh = fv * h
                if fh > 6000.0:
                    break
                inc = k * fh
                ph = ph0 * h
                for b0 in range(0, n, BLOCK):
                    t = b0 / max(1, n - 1)
                    hell = hell0 + (hell1 - hell0) * t
                    a = math.exp(-(h - 1) / hell) / h
                    for i in range(b0, min(n, b0 + BLOCK)):
                        ph += inc
                        s = math.sin(ph) * a * hull[i]
                        L[i] += s * gl
                        R[i] += s * gr
    p = max(peak(L), peak(R)) or 1.0
    return [x / p for x in L], [x / p for x in R]


def saettigen(x, drive):
    """Sanfte Sättigung (tanh) auf einem Signal mit Spitze ≈ 1: Obertöne im Mittenband, runde Spitzen."""
    t = math.tanh(drive)
    return [math.tanh(drive * v) / t for v in x]


# --- Raum ----------------------------------------------------------------------------------------

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


def raum(l, r, rt, wet_db, pre_ms=3.0, hell=4500.0):
    """Kleiner, heller Raum: Diffusion (vier Allpässe), vier gedämpfte Kämme, zwei Allpässe – links und
    rechts mit anderen Zeiten (breit, aber nie leer auf einer Seite). rt höchstens die halbe Länge."""
    n = len(l)
    rt = min(rt, 0.5 * n / SR)
    wet = amp(wet_db)
    out = []
    for x, diff, kaemme, aps in ((l, (4.71, 3.59, 1.27, 0.93), (11.3, 13.7, 15.9, 17.9), (5.1, 1.7)),
                                 (r, (4.43, 3.31, 1.39, 0.87), (12.1, 14.3, 16.7, 18.7), (5.6, 1.9))):
        ein = biquad(biquad(x, "lp", hell), "hp", 250.0)
        ein = ([0.0] * ns(pre_ms) + ein)[:n]
        for ms, g in zip(diff, (0.7, 0.7, 0.6, 0.6)):
            ein = _allpass(ein, max(1, ns(ms)), g)
        nass = [0.0] * n
        for ms in kaemme:
            d = ns(ms)
            g = 10.0 ** (-3.0 * (ms / 1000.0) / rt)
            kk = 0.5 * math.sqrt(1.0 - g * g)
            for i, v in enumerate(_kamm(ein, d, g, 0.3)):
                nass[i] += v * kk
        for ms in aps:
            nass = _allpass(nass, ns(ms))
        out.append([a + b * wet for a, b in zip(x, nass)])
    return out[0], out[1]


# --- Mischpult für einen Klang -------------------------------------------------------------------

class Klang:
    def __init__(self, ms, seed):
        self.n = ns(ms)
        self.L = [0.0] * self.n
        self.R = [0.0] * self.n
        self.rng = random.Random(seed)

    def mono(self, part, at_ms, gain_db=0.0, pan=0.0):
        """Ein Teil in die Mitte (pan: −1 … 1, gleiche Leistung)."""
        a = (pan + 1.0) * math.pi / 4.0
        g = amp(gain_db)
        i0 = ns(at_ms + VORLAUF_MS)
        add(self.L, i0, part, g * math.cos(a) * math.sqrt(2.0))
        add(self.R, i0, part, g * math.sin(a) * math.sqrt(2.0))

    def stereo(self, l, r, at_ms, gain_db=0.0):
        i0 = ns(at_ms + VORLAUF_MS)
        add(self.L, i0, l, amp(gain_db))
        add(self.R, i0, r, amp(gain_db))

    def ton(self, f, at_ms, gain_db, tau, pan=0.0, breit=0.8, **kw):
        """Ein Ton, links und rechts um ±breit Cent verstimmt (lebendig, kaum breiter)."""
        rest = (self.n - ns(at_ms + VORLAUF_MS)) * 1000.0 / SR
        ms = kw.pop("ms", rest)
        cent = kw.pop("cent", 0.0)
        l = ton(f, min(ms, rest), tau, cent=cent - breit, **kw)
        r = ton(f, min(ms, rest), tau, cent=cent + breit, **kw)
        a = (pan + 1.0) * math.pi / 4.0
        self.stereo([v * math.cos(a) * math.sqrt(2.0) for v in l], [v * math.sin(a) * math.sqrt(2.0) for v in r], at_ms, gain_db)

    def klick(self, fc, at_ms, gain_db, tau_ms=0.6, q=1.1, pan=0.0):
        self.mono(klick(self.rng, fc, tau_ms, q), at_ms, gain_db, pan)

    def tap(self, f, at_ms, gain_db, tau_ms, fall=1.8, fall_ms=1.2):
        self.mono(tap(f, tau_ms, fall, fall_ms), at_ms, gain_db)

    def hauch(self, at_ms, ms, f0, f1, gain_db, q=1.3, auf=0.4):
        # links und rechts eigenes Rauschen: luftig breit, aber gleich hell
        self.stereo(hauch(self.rng, ms, f0, f1, q, auf), hauch(self.rng, ms, f0, f1, q, auf), at_ms, gain_db)

    def flaeche(self, freqs, at_ms, ms, gain_db, auf_ms, ab_ms, **kw):
        l, r = flaeche(self.rng, freqs, ms, auf_ms, ab_ms, **kw)
        self.stereo(l, r, at_ms, gain_db)

    def filter(self, kind, fc, q=0.707):
        self.L = biquad(self.L, kind, fc, q)
        self.R = biquad(self.R, kind, fc, q)

    def saettigen(self, drive):
        p = max(peak(self.L), peak(self.R)) or 1.0
        self.L = [v * p for v in saettigen([v / p for v in self.L], drive)]
        self.R = [v * p for v in saettigen([v / p for v in self.R], drive)]

    def raum(self, rt, wet_db, pre_ms=3.0, hell=4500.0):
        self.L, self.R = raum(self.L[:self.n], self.R[:self.n], rt, wet_db, pre_ms, hell)


def einrasten(k, at_ms, latch_ms, f, gain_db=0.0, tau=0.045, cent=0.0, fuenfte=-9.0, druck_fc=2600.0, raste_fc=4200.0):
    """Das Herz von „select“: Drücken (dunkler Klick + Tap), latch_ms später Einrasten (heller Klick),
    darauf der gläserne Kern f mit leiser Quinte und eine kurze Tiefe zwei Oktaven tiefer."""
    k.klick(druck_fc, at_ms, gain_db - 7.0, tau_ms=0.7)
    k.tap(f, at_ms, gain_db - 8.0, tau_ms=5.0, fall=1.5)
    t = at_ms + latch_ms
    k.klick(raste_fc, t, gain_db - 3.5, tau_ms=0.45, q=1.3)
    k.ton(f, t, gain_db, tau, fm=(2.0, 1.5, 9.0), cent=cent)
    if fuenfte is not None:
        k.ton(f * 1.5, t + 1.0, gain_db + fuenfte, tau * 0.7, fm=(2.0, 0.8, 6.0), cent=cent, pan=0.12)
    k.tap(f / 4.0 if f / 4.0 >= 150.0 else f / 2.0, t, gain_db - 9.0, tau_ms=14.0, fall=1.4, fall_ms=3.0)


# --- Die Klänge ----------------------------------------------------------------------------------

def baue(name, ms, v):
    k = Klang(ms, "uzai-klang3-%s-%d" % (name, v))
    rng = k.rng
    rest = lambda at: ms - VORLAUF_MS - at
    if name == "move":
        # Ein gläserner Tupfer bei E6 mit einem Hauch Tiefe: weich, kurz, nie spitz. Fassungen: andere
        # Klickfarbe, ein paar Cent Unterschied, mehr oder weniger Glas.
        cent = (0.0, 18.0, -22.0, 35.0)[v]
        k.klick((3300.0, 3700.0, 3000.0, 3500.0)[v], 0, -10.0, tau_ms=0.45, q=1.2)
        k.ton(note("E6"), 0.3, 0.0, tau_bis(rest(0), 44.0), att_ms=1.2, modi="glas" if v % 2 == 0 else "hell",
              fm=(2.0, (0.9, 1.1, 0.8, 1.0)[v], 4.0), cent=cent)
        k.tap(note("E4"), 0.0, -12.0, tau_ms=5.0, fall=1.6)
        k.filter("lp", 5200.0)
        k.raum(0.12, -21.0, 2.0)
    elif name == "tick":
        # Raste: kürzer, heller, präziser (H6), fast nur Anschlag.
        cent = (0.0, 25.0, -20.0)[v]
        k.klick((4200.0, 3900.0, 4500.0)[v], 0, -6.0, tau_ms=0.35, q=1.4)
        k.ton(note("B6"), 0.2, 0.0, tau_bis(rest(0), 44.0), att_ms=0.8, modi="glas", fm=(2.0, 0.6, 3.0), cent=cent)
        k.tap(note("B4"), 0.0, -14.0, tau_ms=3.5, fall=1.6)
        k.filter("lp", 5600.0)
        k.raum(0.08, -23.0, 1.5)
    elif name == "bump":
        # Rand: gedämpft, aber nicht dumpf – ein weicher Anschlag auf E5 mit kurzem „Federn“ (Tonhöhe
        # fällt deutlich), darunter die Tiefe; Klick dunkel. Nicht tonal hervorstechend.
        cent = (0.0, -30.0)[v]
        k.klick((1500.0, 1300.0)[v], 0, -8.0, tau_ms=1.0, q=0.9)
        k.tap(note("E5"), 0, -2.0, tau_ms=9.0, fall=1.35, fall_ms=6.0)
        k.ton(note("E5") / 1.0, 1.0, -5.0, tau_bis(rest(1), 38.0), att_ms=2.0, modi="weich", fm=(1.0, 1.4, 8.0), bend=0.05, bend_ms=10.0, cent=cent)
        k.tap(note("E4"), 0, -4.0, tau_ms=16.0, fall=1.3, fall_ms=5.0)
        k.saettigen(1.6)
        k.filter("lp", 2600.0)
        k.raum(0.1, -22.0, 2.0)
    elif name == "select":
        latch = (10.0, 8.0, 12.0)[v]
        cent = (0.0, 12.0, -10.0)[v]
        einrasten(k, 0, latch, note("E5"), 0.0, tau=tau_bis(rest(latch), 36.0), cent=cent)
        k.saettigen(1.3)
        k.filter("lp", 6000.0)
        k.raum(0.16, -18.0, 2.5)
    elif name == "back":
        # Abwärts und weicher: H5 → E5, langsamer Anstieg, kein heller Klick, dunkler.
        t2 = (30.0, 36.0)[v]
        cent = (0.0, -14.0)[v]
        k.klick(1900.0, 0, -13.0, tau_ms=1.1, q=0.9)
        k.ton(note("B5"), 0.5, -3.0, 0.022, att_ms=3.0, modi="weich", fm=(2.0, 0.7, 6.0), cent=cent, pan=0.1)
        k.ton(note("E5"), t2, 0.0, tau_bis(rest(t2), 38.0), att_ms=3.5, modi="glas", fm=(2.0, 0.8, 8.0), cent=cent, pan=-0.05)
        k.tap(note("E4"), t2, -12.0, tau_ms=10.0, fall=1.3)
        k.filter("lp", 3800.0)
        k.raum(0.16, -19.0, 3.0)
    elif name == "open":
        # Einrasten, dann öffnet sich Luft nach oben (passt zur Animation: 0,36 s), dazu H5 und E6 als Akzent.
        einrasten(k, 0, 9.0, note("E5"), 0.0, tau=0.06)
        k.hauch(0, 320, 700.0, 3600.0, -9.0, q=1.5, auf=0.33)
        k.ton(note("B5"), 34, -4.5, tau_bis(rest(34), 40.0), modi="glas", fm=(2.0, 0.9, 6.0), pan=0.1)
        k.ton(note("E6"), 64, -8.0, tau_bis(rest(64), 40.0), modi="hell", fm=(2.0, 0.7, 5.0), pan=0.18)
        k.saettigen(1.2)
        k.raum(0.3, -15.0, 4.0)
    elif name in ("toggle_on", "toggle_off"):
        an = name == "toggle_on"
        cent = (0.0, 15.0 if an else -15.0)[v]
        t2 = (26.0, 22.0)[v]
        f1, f2 = (note("E5"), note("B5")) if an else (note("B5"), note("E5"))
        k.klick(2500.0 if an else 2100.0, 0, -9.0, tau_ms=0.7)
        k.ton(f1, 0.3, -4.0, 0.012, att_ms=1.0, modi="glas", fm=(2.0, 0.9, 4.0), cent=cent, pan=-0.08 if an else 0.08)
        k.klick(4300.0 if an else 2900.0, t2, -4.0 if an else -8.0, tau_ms=0.45 if an else 0.7, q=1.3)
        k.ton(f2, t2, 0.0, tau_bis(rest(t2), 36.0), att_ms=1.0 if an else 2.5, modi="hell" if an else "weich",
              fm=(2.0, 1.2 if an else 0.6, 6.0), cent=cent, pan=0.08 if an else -0.08)
        k.tap(f2 / 4.0 if f2 / 4.0 >= 150.0 else f2 / 2.0, t2, -11.0, tau_ms=8.0, fall=1.4)
        if not an:
            k.filter("lp", 3600.0)
        k.raum(0.12, -20.0, 2.0)
    elif name == "tab":
        # Seitwärts: ein kurzer Luftzug (wandert, je Fassung auf- oder abwärts), darauf ein runder Ton.
        f = (note("C#6"), note("B5"))[v]
        k.hauch(0, 190, 1300.0 if v == 0 else 2600.0, 2600.0 if v == 0 else 1300.0, -7.0, q=1.1, auf=0.3)
        k.klick(3000.0, 6, -11.0, tau_ms=0.5)
        k.ton(f, 8, 0.0, tau_bis(rest(8), 38.0), att_ms=1.8, modi="glas", fm=(2.0, 0.9, 6.0))
        k.tap(f / 4.0, 8, -13.0, tau_ms=8.0, fall=1.4)
        k.raum(0.2, -17.0, 3.0)
    elif name == "guide":
        # Signatur: Luft steigt, darauf ein schnelles Arpeggio E5 Gis5 H5 E6 von links nach rechts.
        k.hauch(0, 245, 500.0, 3200.0, -8.0, q=1.4, auf=0.45)
        k.klick(3000.0, 0, -9.0, tau_ms=0.5)
        k.tap(note("E4"), 0, -6.0, tau_ms=18.0, fall=1.4, fall_ms=3.0)
        for i, (nn, t, g) in enumerate((("E5", 0, 0.0), ("G#5", 20, -1.5), ("B5", 40, -3.0), ("E6", 62, -5.0))):
            k.ton(note(nn), t + 0.5, g, tau_bis(rest(t), 46.0), modi="glas", fm=(2.0, 1.0, 6.0), pan=-0.15 + 0.1 * i)
        k.saettigen(1.2)
        k.raum(0.3, -15.0, 4.0)
    elif name == "guide_close":
        k.hauch(0, 195, 2600.0, 600.0, -9.0, q=1.3, auf=0.22)
        k.klick(2200.0, 0, -13.0, tau_ms=0.8)
        for i, (nn, t, g) in enumerate((("E6", 0, -5.0), ("B5", 22, -2.0), ("E5", 44, 0.0))):
            k.ton(note(nn), t + 0.5, g, tau_bis(rest(t), 46.0), att_ms=2.5, modi="glas", fm=(2.0, 0.7, 5.0), pan=0.12 - 0.12 * i)
        k.filter("lp", 4200.0)
        k.raum(0.24, -16.0, 3.0)
    elif name == "error":
        # Freundlich „nein“: zwei weiche, etwas holzige Töne abwärts (Gis4 → E4), FM unharmonisch
        # (Verhältnis 1,41), gesättigt – auf dem Fernseher deutlich, nie schrill.
        for t, nn, g in ((0, "G#4", 0.0), (105, "E4", -1.0)):
            k.klick(1600.0, t, -10.0, tau_ms=1.0, q=0.9)
            k.ton(note(nn), t + 0.5, g, tau_bis(rest(t), 48.0) if t else 0.05, att_ms=2.0, modi="weich", fm=(1.41, 1.8, 18.0), bend=0.01)
            k.ton(note(nn) * 2.0, t + 0.5, g - 10.0, 0.03, att_ms=2.0, modi="weich")
        k.saettigen(2.0)
        k.filter("lp", 3200.0)
        k.raum(0.16, -19.0, 2.5)
    elif name == "notify":
        # Mitteilung: H5, dann E6 – eine freundliche Quarte aufwärts, gläsern.
        k.klick(3400.0, 0, -11.0, tau_ms=0.5)
        k.ton(note("B5"), 0.5, 0.0, 0.04, modi="glas", fm=(2.0, 1.1, 7.0), pan=-0.1)
        k.klick(3800.0, 95, -12.0, tau_ms=0.5)
        k.ton(note("E6"), 95.5, -0.5, tau_bis(rest(95), 40.0), modi="hell", fm=(2.0, 1.0, 7.0), pan=0.1)
        k.tap(note("E4"), 95, -14.0, tau_ms=10.0)
        k.raum(0.2, -17.0, 3.0)
    elif name == "launch":
        # Spielen: Einrasten, dann zieht alles nach oben – Arpeggio E5 … Gis6, Luft steigt, eine Fläche
        # schwillt kurz an. Endet mit der Bewegung (0,36 s).
        einrasten(k, 0, 9.0, note("E5"), 0.0, tau=0.05, fuenfte=None)
        for i, (nn, t, g) in enumerate((("G#5", 35, -2.0), ("B5", 70, -3.0), ("E6", 105, -4.0), ("G#6", 140, -9.0))):
            k.ton(note(nn), t, g, tau_bis(rest(t), 40.0), modi="glas", fm=(2.0, 1.0, 6.0), pan=-0.1 + 0.08 * i)
        k.hauch(0, 380, 400.0, 3600.0, -8.0, q=1.2, auf=0.55)
        k.flaeche([note("E4"), note("B4")], 0, 400, -13.0, 140, 230, hell0=1.5, hell1=4.0)
        k.saettigen(1.2)
        k.raum(0.38, -14.0, 4.0)
    elif name == "boot":
        # Start: eine Fläche öffnet sich bis zum Punkt (0,30 s); Punkt: Einrasten in der Tiefe (E4 + E5);
        # U (0,62 s): H5; Name (1,08 s): E-Dur-Akkord gezupft, darüber Luft. Alles verklingt vor 1,95 s.
        k.flaeche([note("E3"), note("B3"), note("E4")], 0, 1500, -9.0, 320, 700, hell0=1.0, hell1=2.6)
        k.klick(2400.0, 300, -7.0, tau_ms=0.8)
        k.tap(note("E4"), 300, -3.0, tau_ms=18.0, fall=1.5, fall_ms=3.0)
        k.ton(note("E5"), 301, 0.0, 0.12, modi="glas", fm=(2.0, 1.3, 10.0), pan=-0.08)
        k.ton(note("E4"), 301, -6.0, 0.12, modi="weich", fm=(2.0, 0.9, 10.0))
        k.klick(3600.0, 620, -11.0, tau_ms=0.5)
        k.ton(note("B5"), 620.5, -4.0, 0.1, modi="glas", fm=(2.0, 1.0, 8.0), pan=0.1)
        for i, (nn, t, g) in enumerate((("E5", 0, -3.0), ("G#5", 18, -4.0), ("B5", 36, -5.0), ("E6", 54, -8.0))):
            k.ton(note(nn), 1080 + t, g, tau_bis(rest(1080 + t), 44.0), modi="glas", fm=(2.0, 1.0, 8.0), pan=-0.15 + 0.1 * i)
        k.hauch(1000, 650, 1800.0, 4200.0, -16.0, q=1.6, auf=0.3)
        k.saettigen(1.1)
        k.raum(0.6, -13.0, 5.0)
    elif name == "power_off":
        # Ausschalten: ein leiser Druck, dann fällt es abwärts (E6 H5 Gis5 E5), die Fläche schließt sich.
        k.klick(2400.0, 0, -15.0, tau_ms=0.7)
        k.ton(note("B5"), 0.5, -16.0, 0.03, modi="glas", fm=(2.0, 0.6, 5.0))
        for i, (nn, t, g) in enumerate((("E6", 620, -6.0), ("B5", 670, -4.0), ("G#5", 720, -3.0), ("E5", 770, -2.0))):
            k.ton(note(nn), t, g, tau_bis(rest(t), 46.0), att_ms=3.0, modi="glas", fm=(2.0, 0.7, 6.0), pan=0.15 - 0.1 * i)
        k.flaeche([note("E4"), note("B3"), note("E3")], 600, 700, -10.0, 60, 600, hell0=3.0, hell1=0.8)
        k.hauch(620, 520, 2400.0, 450.0, -15.0, q=1.2, auf=0.2)
        k.raum(0.55, -14.0, 5.0)
    elif name == "shutter":
        # Verschluss: zwei knackige mechanische Anschläge (auf, zu) und ein kleiner heller Glanz.
        for t, fc, g in ((0, 3300.0, -5.0), (55, 2600.0, -7.0)):
            k.klick(fc, t, g, tau_ms=1.4, q=0.9)
            k.tap(1400.0 if t == 0 else 1100.0, t, g - 5.0, tau_ms=3.0, fall=1.6)
        k.ton(note("C#7"), 2, -8.0, 0.025, att_ms=0.8, modi="glas")
        k.raum(0.12, -19.0, 2.0)
    elif name in ("achievement", "unlock", "unlock_rare", "unlock_retro"):
        retro = name == "unlock_retro"
        folge = {
            "achievement": (("E5", 0, 0.0), ("G#5", 65, -0.5), ("B5", 130, -1.0), ("E6", 195, -2.0), ("G#6", 260, -9.0)),
            "unlock": (("B5", 0, 0.0), ("E6", 80, -1.0)),
            "unlock_rare": (("E5", 0, 0.0), ("B5", 55, -0.5), ("E6", 110, -1.0), ("G#6", 165, -3.0), ("B6", 220, -7.0)),
            "unlock_retro": (("E5", 0, 0.0), ("B5", 70, -1.0), ("E6", 140, -2.0)),
        }[name]
        einrasten(k, 0, 9.0, note(folge[0][0]), -2.0, tau=0.05, fuenfte=None, raste_fc=3800.0)
        for i, (nn, t, g) in enumerate(folge):
            tau = min(0.17, tau_bis(rest(t), 44.0))
            if retro:
                k.ton(note(nn), t + 0.5, g, min(tau, 0.09), att_ms=1.0, modi="retro", bend=0.0, pan=-0.12 + 0.12 * i)
            else:
                k.ton(note(nn), t + 0.5, g, tau, modi="hell" if i == len(folge) - 1 else "glas", fm=(2.0, 1.2, 9.0),
                      pan=-0.16 + 0.32 * i / max(1, len(folge) - 1))
        if not retro:
            # Glitzern: kleine hohe Töne aus der Tonleiter, zufällig verteilt, leise.
            zahl = {"achievement": 4, "unlock": 4, "unlock_rare": 7}[name]
            t0 = folge[-1][1] + 40
            for j in range(zahl):
                nn = rng.choice(("E7", "G#6", "B6", "C#7", "F#6"))
                t = t0 + j * rng.uniform(28.0, 46.0)
                k.ton(note(nn), t, -15.0 - rng.uniform(0.0, 5.0), min(0.05, tau_bis(rest(t), 46.0)), att_ms=0.8, modi="glas",
                      pan=rng.uniform(-0.3, 0.3))
            akkord = [note("E4"), note("B4"), note("E5")] if name != "unlock" else [note("B4"), note("E5")]
            lang = rest(0)
            k.flaeche(akkord, 20, lang - 40, -12.0, 120, lang * 0.55, hell0=2.0, hell1=1.2)
            k.hauch(150, min(600, lang - 200), 2600.0, 4500.0, -19.0, q=1.6, auf=0.3)
        else:
            k.filter("lp", 4500.0)
        k.saettigen(1.15)
        k.raum(0.5 if not retro else 0.25, -14.0 if not retro else -18.0, 5.0)
    elif name == "setup_step":
        # Schritt weiter: ein klarer Ton mit Einrasten und einem Hauch nach oben. Aufsteigend über die
        # Tonhöhe beim Abspielen (Klang.stufe_ton: E-Dur pentatonisch, Stufe 0 = dieser Ton).
        einrasten(k, 0, 8.0, note("E5"), 0.0, tau=tau_bis(rest(8), 40.0), fuenfte=-11.0)
        k.hauch(0, 140, 1400.0, 3200.0, -14.0, q=1.3, auf=0.35)
        k.raum(0.2, -17.0, 3.0)
    elif name == "setup_found":
        # Etwas fliegt ein: Luft kommt näher (steigt, wird lauter), landet mit einem kleinen Glitzern.
        k.hauch(0, 280, 700.0, 3400.0, -6.0, q=1.4, auf=0.82)
        land = 235.0
        k.tap(note("E5"), land, -10.0, tau_ms=6.0, fall=1.5)
        k.klick(4000.0, land, -10.0, tau_ms=0.4, q=1.3)
        for j, nn in enumerate(("B6", "E7", "G#6", "C#7")):
            t = land + j * 21.0
            k.ton(note(nn), t, -2.0 - 2.0 * j, min(0.045, tau_bis(rest(t), 40.0)), att_ms=0.8, modi="glas",
                  fm=(2.0, 0.7, 3.0), pan=(-0.22, 0.2, -0.08, 0.26)[j])
        k.ton(note("E6"), land, -4.0, tau_bis(rest(land), 40.0), modi="glas", fm=(2.0, 1.0, 5.0))
        k.raum(0.25, -15.0, 3.0)
    elif name == "setup_done":
        # Fertig: ein E-Dur-Akkord mit None (Fis) gezupft, Fläche darunter, ein letztes Einrasten.
        einrasten(k, 0, 9.0, note("E5"), -3.0, tau=0.05, fuenfte=None)
        akk = (("E4", 0, -3.0), ("B4", 22, -3.0), ("E5", 44, -2.0), ("G#5", 66, -2.5), ("B5", 88, -3.5), ("F#6", 110, -8.0))
        for i, (nn, t, g) in enumerate(akk):
            k.ton(note(nn), t + 0.5, g, min(0.2, tau_bis(rest(t), 44.0)), modi="glas", fm=(2.0, 1.0, 9.0), pan=-0.18 + 0.36 * i / (len(akk) - 1))
        k.flaeche([note("E3"), note("B3"), note("E4")], 10, ms - 40, -11.0, 90, 750, hell0=1.4, hell1=2.6)
        k.hauch(80, 700, 2400.0, 4400.0, -19.0, q=1.6, auf=0.25)
        k.saettigen(1.15)
        k.raum(0.5, -13.0, 5.0)
    elif name == "swell":
        # Licht geht an: eine Fläche schwillt an und öffnet sich (Filter auf), Luft steigt mit; oben
        # angekommen ein weicher, heller Glanz (E6 und H5).
        k.flaeche([note("E3"), note("B3"), note("E4"), note("G#4"), note("B4")], 0, ms - 20, -2.0, 760, 680, hell0=0.8, hell1=3.4, ab_ab=780)
        k.hauch(0, 900, 300.0, 3200.0, -9.0, q=1.1, auf=0.85)
        k.ton(note("E6"), 760, -9.0, min(0.17, tau_bis(rest(760), 44.0)), att_ms=6.0, modi="glas", fm=(2.0, 0.8, 12.0), pan=0.1)
        k.ton(note("B5"), 772, -11.0, min(0.17, tau_bis(rest(772), 44.0)), att_ms=6.0, modi="glas", fm=(2.0, 0.8, 12.0), pan=-0.1)
        k.raum(0.6, -14.0, 6.0)
    else:
        raise KeyError(name)
    return k.L[:k.n], k.R[:k.n]


def fertig(L, R, ziel_db):
    """Ohne Gleichanteil und ohne Tiefstes (Fernseher), sanft ausblenden, auf den Pegel der Tabelle."""
    L = biquad(L, "hp", 70.0)
    R = biquad(R, "hp", 70.0)
    n = len(L)
    fade = min(ns(20), n // 5)
    for i in range(fade):
        g = 0.5 - 0.5 * math.cos(math.pi * i / fade)
        L[n - 1 - i] *= g
        R[n - 1 - i] *= g
    L[-1] = R[-1] = 0.0
    g = amp(ziel_db) / (10.0 ** (messen(L, R)["rms"] / 20.0))
    return [v * g for v in L], [v * g for v in R]


# --- Dateien und Messung -------------------------------------------------------------------------

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


def messen(l, r, voll=False):
    """Spitze und Kurzzeit-RMS (lautestes 50-ms-Fenster) in dBFS, Länge ms, Ende (dB zur Spitze: RMS der
    10 ms vor dem Ausblenden), Rand (größter Betrag der ersten und letzten zwei Werte). voll: dazu
    Energieanteile je Band (unter 300 Hz, 300 Hz–1 kHz, 1–4 kHz, darüber), Korrelation links/rechts."""
    p = max(peak(l), peak(r)) or 1e-9
    win = ns(50)
    step = ns(5)
    sq = [(a * a + b * b) / 2.0 for a, b in zip(l, r)]
    acc = [0.0]
    for v in sq:
        acc.append(acc[-1] + v)
    best = 0.0
    n = len(sq)
    for i in range(0, max(1, n - win + 1), step):
        j = min(n, i + win)
        best = max(best, (acc[j] - acc[i]) / win)
    fade = min(ns(20), n // 5)
    a, b = max(0, n - fade - ns(10)), n - fade
    ende = math.sqrt((acc[b] - acc[a]) / max(1, b - a)) / p
    rand = max(abs(x) for x in (l[0], l[1], r[0], r[1], l[-1], l[-2], r[-1], r[-2]))
    m = {"spitze": db(p), "rms": db(math.sqrt(best)), "ms": n * 1000.0 / SR, "ende": db(ende), "rand": rand}
    if voll:
        mono = [(x + y) * 0.5 for x, y in zip(l, r)]
        ges = sum(v * v for v in mono) or 1e-12
        tief = biquad(biquad(mono, "lp", 300.0), "lp", 300.0)
        hoch = biquad(biquad(mono, "hp", 4000.0), "hp", 4000.0)
        mitte_tief = biquad(biquad(biquad(mono, "hp", 300.0), "hp", 300.0), "lp", 1000.0)
        e_t = sum(v * v for v in tief) / ges
        e_h = sum(v * v for v in hoch) / ges
        e_mt = sum(v * v for v in mitte_tief) / ges
        m["band"] = (e_t, e_mt, max(0.0, 1.0 - e_t - e_h - e_mt), e_h)
        m["tv"] = max(0.0, 1.0 - e_t - e_h)
        sl = sum(x * x for x in l) or 1e-12
        sr = sum(x * x for x in r) or 1e-12
        m["korr"] = sum(x * y for x, y in zip(l, r)) / math.sqrt(sl * sr)
    return m


def sha(pfad):
    with open(pfad, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def alle_dateien():
    for name, ms, pegel, bew, fass, _ in TABELLE:
        for v in range(fass):
            yield name, v, ms, pegel, bew


def quelle_schreiben():
    """Ergänzt KLANG-QUELLE.txt: alles vor MARKE bleibt (Tick, Glas, Filz & Glas …), ab MARKE dieser Satz; der
    Abschnitt von tools/synth_klang4.py (ab MARKE4) steht dahinter und bleibt."""
    alt = ""
    if os.path.isfile(QUELLE):
        with open(QUELLE, encoding="utf-8") as f:
            alt = f.read()
    danach = ""
    if MARKE4 in alt:
        danach = alt[alt.index(MARKE4):]
        alt = alt[:alt.index(MARKE4)]
    if MARKE in alt:
        alt = alt[:alt.index(MARKE)]
    zeilen = [MARKE + " (perle/): Anschlag, gläserner Kern, Luft und Raum, E-Dur pentatonisch.",
              "Nur Python-Standardbibliothek, feste Startwerte (gleiche Quelle, gleiche Dateien). 44,1 kHz, Stereo, 16 Bit.",
              ""]
    for name, v, *_ in alle_dateien():
        p = os.path.join(ORDNER, datei(name, v))
        if os.path.isfile(p):
            zeilen.append("%s  %s/%s" % (sha(p), SATZ, datei(name, v)))
    with open(QUELLE, "w", encoding="utf-8", newline="\n") as f:
        f.write(alt.rstrip("\n") + "\n\n" + "\n".join(zeilen) + "\n" + ("\n" + danach if danach else ""))


def _zeile(name, v, m):
    b = m["band"]
    return "  %-12s %d %5.0f ms %6.1f dB %6.1f dB %+6.1f dB %6.1f dB  %3.0f %3.0f %3.0f %3.0f %%  %4.0f %%  %.2f" % (
        name, v + 1, m["ms"], m["spitze"], m["rms"], m["rms"] - REF_DB, m["ende"],
        b[0] * 100, b[1] * 100, b[2] * 100, b[3] * 100, m["tv"] * 100, m["korr"])


KOPF = "  %-12s %s %8s %9s %9s %9s %9s  %s  %s  %s" % ("Klang", "F", "Länge", "Spitze", "RMS", "zu sel", "Ende",
                                                     "<300 –1k –4k >4k", "TV", "Korr")


def rendern():
    os.makedirs(ORDNER, exist_ok=True)
    print("Satz „Perle“ (%s)" % SATZ)
    print(KOPF)
    for name, v, ms, pegel, _ in alle_dateien():
        L, R = fertig(*baue(name, ms, v), REF_DB + pegel)
        schreibe(os.path.join(ORDNER, datei(name, v)), L, R)
        print(_zeile(name, v, messen(L, R, True)))
    quelle_schreiben()


def pruefen():
    fehler = 0
    werte = {}
    for name, v, ms, pegel, bew in alle_dateien():
        pfad = os.path.join(ORDNER, datei(name, v))
        if not os.path.isfile(pfad):
            print("  FAIL %s fehlt" % datei(name, v))
            fehler += 1
            continue
        l, r, fr, ch = lies(pfad)
        if fr != SR or ch != 2:
            print("  FAIL %s: %d Hz, %d Kanäle (soll 44100, 2)" % (datei(name, v), fr, ch))
            fehler += 1
        m = messen(l, r, True)
        if v == 0:
            werte[name] = m
        grenze = BOOT_MAX_MS if name == "boot" else bew + NACHKLANG_MS
        soll_ms = ms
        pruef = [
            (abs(m["ms"] - soll_ms) <= 1.0, "Länge %.0f ms (soll %.0f)" % (m["ms"], soll_ms)),
            (m["ms"] <= grenze, "Länge ≤ %d ms" % grenze),
            (abs(m["rms"] - (REF_DB + pegel)) <= PEGEL_TOL_DB, "RMS %.1f dBFS (soll %.1f ± %.1f)" % (m["rms"], REF_DB + pegel, PEGEL_TOL_DB)),
            (m["spitze"] <= SPITZE_MAX_DB, "Spitze %.1f dBFS ≤ %.0f" % (m["spitze"], SPITZE_MAX_DB)),
            (m["ende"] <= ENDE_MAX_DB[0 if ms < 200 else 1], "verklungen vor dem Ausblenden (%.0f dB)" % m["ende"]),
            (m["rand"] < 0.0012, "beginnt und endet bei null (kein Knacken)"),
            (m["tv"] >= BAND_MIN, "Energie 300 Hz–4 kHz %.0f %% ≥ %.0f %%" % (m["tv"] * 100, BAND_MIN * 100)),
            (m["korr"] >= KORR_MIN, "Stereo dezent (Korrelation %.2f ≥ %.2f)" % (m["korr"], KORR_MIN)),
        ]
        for ok, was in pruef:
            if not ok:
                print("  FAIL %s: %s" % (datei(name, v), was))
            fehler += 0 if ok else 1
    if "select" in werte and "move" in werte:
        sel = werte["select"]["spitze"]
        if not (-24.0 < sel < -16.0):
            print("  FAIL select: Spitze %.1f dBFS (soll −24 … −16)" % sel)
            fehler += 1
        for k in ("move", "tick"):
            if werte[k]["spitze"] >= sel - 5.0:
                print("  FAIL %s: nicht deutlich leiser als select (Spitze %.1f)" % (k, werte[k]["spitze"]))
                fehler += 1
    if "power_off" in werte and "boot" in werte:
        lauter = [k for k in werte if werte[k]["rms"] > werte["power_off"]["rms"] + 0.01]
        if not (werte["power_off"]["rms"] <= werte["boot"]["rms"] and lauter):
            print("  FAIL Ausschalten ist der lauteste Klang")
            fehler += 1
    print("Ergebnis: %s" % ("alles ok" if fehler == 0 else "%d Fehler" % fehler))
    return 1 if fehler else 0


# --- Hörprobe ------------------------------------------------------------------------------------
# Gemischt wie in Uzai: Standardregler 0,6 × 0,75, Bewegen nach Klang.bewegen (schnell: bis −8 dB leiser,
# Tonhöhe ±1,5 %, Lautstärke ±0,5 dB, schneidet den eigenen Nachklang ab), Fassungen zufällig ohne
# Wiederholung (Klang.variante), Liste abwärts eine Spur tiefer (Klang.kontext), „tab“ aus der Richtung,
# Schritte der Einrichtung aufsteigend (Klang.stufe_ton), danach der Tiefpass der Leitung „UI“ (5,2 kHz).

REGLER = 0.6 * 0.75
STUFEN = (0, 2, 4, 7, 9)


def stufe_ton(s):
    s = max(0, min(10, s))
    return 2.0 ** ((STUFEN[s % 5] + 12 * (s // 5)) / 12.0)


def hoerprobe(ziel):
    rng = random.Random("uzai-klang3-hoerprobe")
    fass = {name: f for name, _, _, _, f, _ in TABELLE}
    cache = {}

    def lade(name, v):
        if (name, v) not in cache:
            pfad = os.path.join(EINR_ORDNER, name + ".wav") if name.startswith("su_") else os.path.join(ORDNER, datei(name, v))
            cache[(name, v)] = lies(pfad)[:2]
        return cache[(name, v)]

    letzte = {}

    def variante(name):
        n = fass.get(name, 1)
        if n <= 1:
            return 0
        vor = letzte.get(name, -1)
        z = rng.random()
        k = min(n - 1, int(z * n)) if vor < 0 else min(n - 2, int(z * (n - 1)))
        if vor >= 0 and k >= vor:
            k += 1
        letzte[name] = k
        return k

    L, R = [0.0] * ns(400), [0.0] * ns(400)
    zeilen = []
    t = 0.4
    move_lauf = [None]

    def spiel(name, at, pitch=1.0, db_=0.0, pan=0.0, abschnitt=""):
        v = variante(name)
        l, r = lade(name, v)
        if pitch != 1.0:
            m = int(len(l) / pitch)
            l = [l[min(int(j * pitch), len(l) - 1)] for j in range(m)]
            r = [r[min(int(j * pitch), len(r) - 1)] for j in range(m)]
        i0 = ns(at * 1000.0)
        if name in ("move", "tick") and move_lauf[0] is not None:
            a, lang = move_lauf[0]
            f = ns(4)
            for i in range(i0, min(a + lang, len(L))):
                g = max(0.0, 1.0 - (i - i0) / f)
                L[i] *= g
                R[i] *= g
        gl = REGLER * amp(db_) * (1.0 - max(pan, 0.0))
        gr = REGLER * amp(db_) * (1.0 + min(pan, 0.0))
        add(L, i0, l, gl)
        add(R, i0, r, gr)
        if name in ("move", "tick"):
            move_lauf[0] = (i0, len(l))
        zeilen.append((at, name, v, len(l) * 1000.0 / SR, abschnitt))
        return at + len(l) / SR

    # 1) Blättern durch eine Liste: erst einzeln, dann gehalten (schneller, leiser), abwärts eine Spur tiefer.
    abst = [0.0, 0.42, 0.38, 0.4, 0.4, 0.162, 0.162, 0.162, 0.12, 0.12, 0.12, 0.12, 0.096, 0.096, 0.096, 0.096]
    reihe = 0
    for i, a in enumerate(abst):
        t += a
        reihe = reihe + 1 if (a and a < 0.26) else 0
        y = i / (len(abst) - 1)
        p = (1.0 + (0.5 - y) * 0.03) * (1.0 + rng.uniform(-1.0, 1.0) * 0.015)
        ende = spiel("move", t, p, -8.0 * min(reihe / 4.0, 1.0) + rng.uniform(-0.5, 0.5), abschnitt="Liste blättern" if i == 0 else "")
    t = ende + 0.5
    spiel("bump", t, 0.92, abschnitt="Rand unten")
    t += 0.7
    # 2) Regler: acht Rasten.
    for i in range(8):
        ende = spiel("tick", t, 1.0 + rng.uniform(-1.0, 1.0) * 0.015, rng.uniform(-0.5, 0.5), abschnitt="Regler" if i == 0 else "")
        t += 0.11
    t = ende + 0.6
    # 3) Die Einzelklänge.
    for name, pan in (("select", 0.0), ("select", 0.0), ("select", 0.0), ("back", 0.0), ("back", 0.0), ("toggle_on", 0.0), ("toggle_off", 0.0),
                      ("tab", 0.3), ("tab", -0.3), ("open", 0.0), ("guide", 0.0), ("guide_close", 0.0), ("notify", 0.0), ("error", 0.0),
                      ("shutter", 0.0), ("launch", 0.0)):
        ende = spiel(name, t, pan=pan, abschnitt="Einzelklänge" if name == "select" and not any(z[1] == "select" for z in zeilen) else "")
        t = ende + 0.5
    # 4) Einrichtung: vier Schritte aufwärts, etwas gefunden, fertig, Licht an.
    for s in range(4):
        ende = spiel("setup_step", t, stufe_ton(s), abschnitt="Einrichtung" if s == 0 else "")
        t = ende + 0.42
    for name in ("setup_found", "setup_done", "swell"):
        ende = spiel(name, t)
        t = ende + 0.6
    # 5) Erfolge, Start, Ausschalten.
    for name in ("achievement", "unlock", "unlock_rare", "unlock_retro", "boot", "power_off"):
        ende = spiel(name, t, abschnitt="Erfolge und Signaturen" if name == "achievement" else "")
        t = ende + 0.7
    # 6) Die Klänge der Einrichtung (eigener Ordner, tools/synth_klang4.py).
    su = sorted(f[:-4] for f in os.listdir(EINR_ORDNER) if f.startswith("su_") and f.endswith(".wav")) if os.path.isdir(EINR_ORDNER) else []
    for i, name in enumerate(su):
        ende = spiel(name, t, abschnitt="Einrichtung (eigener Ordner)" if i == 0 else "")
        t = ende + 0.6
    n = ns(t * 1000.0) + ns(300)
    L += [0.0] * (n - len(L))
    R += [0.0] * (n - len(R))
    L = biquad(L, "lp", 5200.0, 0.5)
    R = biquad(R, "lp", 5200.0, 0.5)
    # Zum Abhören lauter (alles gleich viel, die Staffelung bleibt): Spitze auf −6 dBFS.
    plus = -6.0 - messen(L, R)["spitze"]
    L = [v * amp(plus) for v in L]
    R = [v * amp(plus) for v in R]
    schreibe(ziel, L, R)
    print("Hörprobe: %s %.1f s, zum Abhören %+.1f dB lauter als in Uzai (Spitze −6 dBFS)" % (ziel, len(L) / SR, plus))
    md = os.path.splitext(ziel)[0] + ".md"
    with open(md, "w", encoding="utf-8") as f:
        f.write("# Klangsatz „Perle“ – Hörprobe\n\nGemischt wie in Uzai (Standardregler 0,6 × 0,75 ≈ −7 dB, Tiefpass 5,2 kHz), "
                "zum Abhören insgesamt %s dB lauter (Staffelung unverändert). F = Fassung.\n\n"
                "| ab | Abschnitt | Klang | F | Dauer |\n|---|---|---|---|---|\n" % ("%+.1f" % plus).replace(".", ","))
        for at, name, v, d, ab in zeilen:
            f.write("| %s s | %s | %s | %d | %.0f ms |\n" % (("%.2f" % at).replace(".", ","), ab, name, v + 1, d))
    print("Tabelle:", md)


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--pruefen" in a:
        sys.exit(pruefen())
    if "--hoerprobe" in a:
        hoerprobe(a[a.index("--hoerprobe") + 1])
        sys.exit(0)
    if "--einrichtung" in a:
        print("Die Klänge der Einrichtung rendert tools/synth_klang5.py --einrichtung.")
        sys.exit(1)
    rendern()
