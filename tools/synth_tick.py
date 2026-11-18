#!/usr/bin/env python3
# Klangsatz „Tick“: alle Menüklänge aus einem Grundklang (docs/PLAN_GEFUEHL.md, Abschnitt 3).
# Nur Python-Standardbibliothek (wave, struct, math, random mit festem Startwert): gleiche Quelle,
# gleiche Dateien. Keine Aufnahmen, keine fremden Samples.
#
#   python3 tools/synth_tick.py                 rendert assets/sounds/*.wav (44,1 kHz, Stereo, 16 Bit),
#                                               druckt Länge, Spitze und RMS, schreibt KLANG-QUELLE.txt
#   python3 tools/synth_tick.py --pruefen       prüft die Dateien gegen die Tabelle (Rückgabe 1 bei Abweichung)
#   python3 tools/synth_tick.py --hoerprobe a.wav [--tabelle t.md]
#                                               alle Klänge hintereinander (und eine Tabelle dazu)
#
# Danach einmal: godot --headless --path . --import
#
# Der Grundklang: ein kurzer, tiefer, trockener Tick wie eine gute mechanische Taste.
# - Körper: Sinus mit kurzem Tonhöhenfall (f × 1,3 → f in etwa 8 ms), Anstieg 1,5 ms, Abklingen τ.
# - Holz: Bandrauschen 1,2–3 kHz, etwa 4 ms, h dB unter dem Körper (hörbar auf Fernsehlautsprechern).
# - Raum: ein kleiner, trockener Raum (−30 dB, bis 60 ms). Kein Hall, keine Glocke, keine Terz.
# Stellschrauben je Klang: Grundton f, Länge, Holzanteil h, Zahl und Abstand der Ticks, Pegel.
import hashlib, math, os, random, struct, sys, wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sounds")
GLAS = os.path.join(OUT, "glas")

# Pegel: Spitze relativ zu „select“. „select“ liegt mit dem Standardregler (0,6 × 0,75 ≈ −7 dB) bei
# etwa −24 dBFS Spitze, also in der Datei bei −17 dBFS.
REF_DB = -17.0
TOL_DB = 1.5

# Die Tabelle. Muss zu Klang.PALETTE in src/core/klang.gd passen (tests/logic_klang.gd prüft die
# Dateien dagegen). Länge ms, Pegel dB (Spitze zu select), Bewegung ms (Klang ≤ Bewegung + 60 ms),
# RMS dB (Kurzzeit, 50 ms, zu select; nur zur Kontrolle beim Ändern), Ereignis.
NACHKLANG_MS = 60
TABELLE = [
    # name               ms   pegel  bewg.    rms  Ereignis
    ("move",            35,  -14.0,    90,  -15.6, "Fokus"),
    ("tick",            25,  -12.0,    90,  -15.3, "Regler, Raste, Lautstärke"),
    ("bump",            60,  -10.0,   200,   -9.7, "Grenze erreicht"),
    ("select",          60,    0.0,    90,    0.0, "Bestätigen"),
    ("back",            70,   -3.0,   160,   -2.7, "Zurück"),
    ("open",           120,    0.0,   360,   -0.5, "Ebene oder Seite auf (ersetzt select)"),
    ("toggle_on",       30,   -8.0,    90,  -10.5, "Schalter an"),
    ("toggle_off",      30,   -8.0,    90,  -10.5, "Schalter aus"),
    ("tab",             90,   -8.0,   200,   -8.5, "Bereich, Unterbereich, App"),
    ("guide",          140,    1.0,   200,    2.1, "Guide auf (Signatur)"),
    ("guide_close",     70,   -4.0,   160,   -4.0, "Guide zu"),
    ("error",          180,   -2.0,   200,   -1.2, "Fehler"),
    ("notify",         200,   -4.0,   200,   -4.6, "Mitteilung"),
    ("launch",         350,    0.0,   360,    0.4, "Spielen"),
    ("boot",          1250,    2.0,  2400,    4.3, "Start-Signatur: Punkt, U, Name"),
    ("power_off",      920,    0.0,  1400,    2.6, "Ausschalten"),
    ("shutter",         90,   -4.0,   160,  -10.6, "Bildschirmfoto"),
    ("achievement",    800,    2.0,  1000,    3.0, "Erfolg"),
    ("unlock",         600,    2.0,  1000,    3.4, "Abzeichen"),
    ("unlock_rare",   1000,    2.0,  1200,    3.3, "seltenes Abzeichen"),
    ("unlock_retro",   600,    2.0,  1000,    2.7, "Erfolg im Retro-Spiel"),
]
RMS_TOL_DB = 2.0


# --- Bausteine -------------------------------------------------------------------------------

def db(x):
    return 20.0 * math.log10(x) if x > 1e-12 else -240.0


def amp(d):
    return 10.0 ** (d / 20.0)


def biquad(x, kind, fc, q):
    """RBJ-Biquad (Tiefpass oder Bandpass mit 0 dB Spitze)."""
    w = 2.0 * math.pi * fc / SR
    cw, sw = math.cos(w), math.sin(w)
    al = sw / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
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


def hochpass(x, fc=25.0):
    """Erster Ordnung: nimmt den Gleichanteil des ersten Halbbogens (kein Schub für die Membran)."""
    a = math.exp(-2.0 * math.pi * fc / SR)
    y = [0.0] * len(x)
    px = py = 0.0
    for i, v in enumerate(x):
        py = a * (py + v - px)
        px = v
        y[i] = py
    return y


def peak(x):
    return max((abs(v) for v in x), default=0.0)


def add(buf, at_s, part, gain=1.0):
    i0 = int(round(at_s * SR))
    need = i0 + len(part)
    if need > len(buf):
        buf.extend([0.0] * (need - len(buf)))
    for i, v in enumerate(part):
        buf[i0 + i] += v * gain


def anstieg(t, a):
    return 0.5 - 0.5 * math.cos(math.pi * t / a) if t < a else 1.0


def koerper(f, tau, fall=1.3, laenge=None):
    """Sinus mit kurzem Tonhöhenfall, Anstieg 1,5 ms, Abklingen tau (s). Spitze 1."""
    n = int((laenge or tau * 7.0) * SR)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        fi = f * (1.0 + (fall - 1.0) * math.exp(-t / 0.0027))
        ph += 2.0 * math.pi * fi / SR
        out[i] = math.sin(ph) * anstieg(t, 0.0015) * math.exp(-t / tau)
    p = peak(out)
    return [v / p for v in out]


def rauschen(rng, n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def holz(rng, dauer=0.004):
    """Bandrauschen 1,2–3 kHz, etwa 4 ms. Spitze 1."""
    n = int((dauer + 0.004) * SR)
    x = biquad(rauschen(rng, n), "bp", math.sqrt(1200.0 * 3000.0), 1.05)
    out = [v * anstieg(i / SR, 0.0003) * math.exp(-(i / SR) / (dauer / 3.3)) for i, v in enumerate(x)]
    p = peak(out)
    return [v / p for v in out]


def tick(rng, f, tau=0.018, h=-18.0, fall=1.3, tiefpass=0.0, unterton=None, laenge=None):
    """Der Grundklang. unterton: (dB, tau) – Sinus eine Oktave tiefer, etwas länger."""
    k = koerper(f, tau, fall, laenge)
    if h is not None:
        add(k, 0.0, holz(rng), amp(h))
    if unterton:
        u_db, u_tau = unterton
        add(k, 0.0005, koerper(f / 2.0, u_tau, 1.15, laenge), amp(u_db))
    if tiefpass:
        k = biquad(k, "lp", tiefpass, 0.707)
    return k


def luft(rng, dauer, fc, q, form="glocke"):
    """Gefiltertes Rauschen mit weicher Hülle. Spitze 1."""
    n = int(dauer * SR)
    x = biquad(rauschen(rng, n), "bp", fc, q)
    out = []
    for i, v in enumerate(x):
        t = i / dauer / SR
        if form == "glocke":
            e = math.sin(math.pi * t) ** 2
        else:  # atem: schnell auf, lange fallend
            e = anstieg(i / SR, 0.04) * (1.0 - t) ** 2
        out.append(v * e)
    p = peak(out)
    return [v / p for v in out]


def ton(f, dauer, rechteck=False):
    """Ein einzelner, gehaltener Ton (eine Höhe, kein Akkord). Spitze 1."""
    n = int(dauer * SR)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        if rechteck:
            v = sum(math.sin(2 * math.pi * f * k * t) / k for k in range(1, 12, 2) if f * k < 4000.0)
        else:
            v = math.sin(2 * math.pi * f * t) + 0.12 * math.sin(4 * math.pi * f * t)
        e = anstieg(t, 0.015) * math.exp(-t / (dauer * 0.45))
        out[i] = v * e
    p = peak(out)
    return [v / p for v in out]


def raum(mono):
    """Kleiner, trockener Raum: vier frühe Rückwürfe je Seite, −30 dB, bis 60 ms, gedämpft."""
    links, rechts = list(mono), list(mono)
    hell = biquad(mono, "lp", 2500.0, 0.707)
    for seite, zeiten in ((links, (0.0073, 0.0171, 0.0290, 0.0430)), (rechts, (0.0091, 0.0147, 0.0313, 0.0475))):
        for k, d in enumerate(zeiten):
            add(seite, d, hell, amp(-30.0) * (0.75 ** k))
    n = max(len(links), len(rechts))
    links.extend([0.0] * (n - len(links)))
    rechts.extend([0.0] * (n - len(rechts)))
    return links, rechts


def fertig(mono, ms, pegel_db):
    """Raum, ohne Gleichanteil, auf die Länge bringen (sanft ausblenden), auf den Pegel der Tabelle."""
    l, r = raum(hochpass(mono))
    n = int(round(ms * SR / 1000.0))
    l = (l + [0.0] * n)[:n]
    r = (r + [0.0] * n)[:n]
    fade = min(int(0.004 * SR), n // 4)
    for i in range(fade):
        g = 0.5 - 0.5 * math.cos(math.pi * i / fade)
        l[n - 1 - i] *= g
        r[n - 1 - i] *= g
    p = max(peak(l), peak(r))
    g = amp(REF_DB + pegel_db) / p
    return [v * g for v in l], [v * g for v in r]


# --- Die Palette -----------------------------------------------------------------------------

def klack(rng):
    """„select“: Druck 170 Hz, Loslassen 210 Hz nach 18 ms."""
    m = tick(rng, 170.0, tau=0.0085, h=-16.0)
    add(m, 0.018, tick(rng, 210.0, tau=0.0075, h=-18.0), 0.72)
    return m


def baue(name):
    rng = random.Random("uzai-tick-" + name)
    if name == "move":
        return tick(rng, 200.0, tau=0.0075, h=-24.0)
    if name == "tick":
        return tick(rng, 260.0, tau=0.0052, h=-20.0)
    if name == "bump":
        return tick(rng, 120.0, tau=0.013, h=-14.0, tiefpass=600.0)
    if name == "select":
        return klack(rng)
    if name == "back":
        return tick(rng, 150.0, tau=0.0145, h=None)
    if name == "open":
        m = klack(rng)
        add(m, 0.012, koerper(85.0, 0.026, 1.1), amp(-4.0))
        return m
    if name == "toggle_on":
        return tick(rng, 240.0, tau=0.0065, h=-18.0)
    if name == "toggle_off":
        return tick(rng, 170.0, tau=0.0065, h=-18.0)
    if name == "tab":
        m = tick(rng, 190.0, tau=0.011, h=-18.0)
        add(m, 0.004, luft(rng, 0.06, 2500.0, 0.7), amp(-15.0))
        return m
    if name == "guide":
        return tick(rng, 110.0, tau=0.022, h=-17.0, unterton=(-4.0, 0.03))
    if name == "guide_close":
        return tick(rng, 140.0, tau=0.0135, h=-20.0)
    if name == "error":
        m = tick(rng, 110.0, tau=0.016, h=-16.0)
        add(m, 0.090, tick(rng, 110.0, tau=0.016, h=-16.0), amp(-4.0))
        return m
    if name == "notify":
        # „Anklopfen“: zwei gleiche Ticks, 130 ms Abstand – Rhythmus statt Melodie.
        m = tick(rng, 230.0, tau=0.012, h=-16.0)
        add(m, 0.130, tick(rng, 230.0, tau=0.012, h=-16.0), 0.95)
        return m
    if name == "launch":
        m = klack(rng)
        add(m, 0.010, luft(rng, 0.33, 346.0, 0.87, "atem"), amp(-7.0))
        return m
    if name == "boot":
        # Punkt (0,30 s): tiefer Tick mit Unterton. U (0,62 s): leiser, etwas heller. Name (1,08 s):
        # nur ein Hauch Luft. Danach Stille (src/ui/boot.gd: DOT_AT, U_AT, NAME_AT).
        m = [0.0] * int(0.30 * SR)
        add(m, 0.30, tick(rng, 90.0, tau=0.03, h=-16.0, unterton=(-5.0, 0.045)))
        add(m, 0.62, tick(rng, 150.0, tau=0.014, h=-18.0), amp(-10.0))
        add(m, 1.08, luft(rng, 0.12, 1800.0, 0.8), amp(-24.0))
        return m
    if name == "power_off":
        # Gegenstück zum Start: der Druck (leiser Klack), dann derselbe tiefe Tick, tiefer (70 Hz),
        # wenn das Zeichen zusammenfällt (src/ui/power_off.gd: SQUASH ab 0,62 s).
        m = klack(rng)
        for i in range(len(m)):
            m[i] *= amp(-8.0)
        add(m, 0.62, tick(rng, 70.0, tau=0.034, h=-15.0, unterton=(-6.0, 0.05)))
        return m
    if name == "shutter":
        # Verschluss auf, zu: zwei Holz-Ticks, 60 ms Abstand (fast nur Holz).
        m = tick(rng, 300.0, tau=0.004, h=-3.0)
        add(m, 0.060, tick(rng, 260.0, tau=0.004, h=-3.0), 0.85)
        return m
    if name in ("achievement", "unlock", "unlock_rare", "unlock_retro"):
        # Ausnahme laut DESIGN: Tick und ein einzelner, gehaltener Ton (eine Höhe, kein Akkord).
        dauer = {"achievement": 0.8, "unlock": 0.6, "unlock_rare": 1.0, "unlock_retro": 0.6}[name]
        f = {"achievement": 330.0, "unlock": 349.2, "unlock_rare": 293.7, "unlock_retro": 440.0}[name]
        m = klack(rng)
        add(m, 0.03, ton(f, dauer - 0.03, rechteck=(name == "unlock_retro")), amp(-6.0 if name != "unlock_retro" else -10.0))
        return m
    raise KeyError(name)


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
    """Spitze (dBFS), Kurzzeit-RMS (größtes 50-ms-Fenster, dBFS), Länge (ms)."""
    p = max(peak(l), peak(r))
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
    return db(p), db(math.sqrt(best)), n * 1000.0 / SR


def sha(pfad):
    with open(pfad, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def quelle_schreiben():
    zeilen = [
        "Herkunft der Menüklänge von Uzai",
        "",
        "Alle Klänge sind selbst erzeugt: keine Aufnahmen, keine fremden Samples. Lizenz wie Uzai.",
        "",
        "Klangsatz „Tick“ (wählbar, dieser Ordner): tools/synth_tick.py, nur Python-Standardbibliothek,",
        "feste Startwerte (gleiche Quelle, gleiche Dateien). 44,1 kHz, Stereo, 16 Bit.",
        "",
    ]
    for name, *_ in TABELLE:
        p = os.path.join(OUT, name + ".wav")
        zeilen.append("%s  %s.wav" % (sha(p), name))
    zeilen += ["", "Klangsatz „Glas“ (Standard, Ordner glas/): die Klänge bis 0.11 in D-Dur, unverändert,",
               "erzeugt mit tools/synth.py (numpy), tools/synth_power.py, tools/synth_unlock.py und",
               "tools/synth_retro.py.", ""]
    if os.path.isdir(GLAS):
        for n in sorted(os.listdir(GLAS)):
            if n.endswith(".wav"):
                zeilen.append("%s  glas/%s" % (sha(os.path.join(GLAS, n)), n))
    # Die Sätze aus tools/synth_klang2.py (ab ihrer Überschrift) bleiben stehen.
    pfad = os.path.join(OUT, "KLANG-QUELLE.txt")
    rest = ""
    if os.path.isfile(pfad):
        with open(pfad, encoding="utf-8") as f:
            alt = f.read()
        marke = "Klangsätze aus tools/synth_klang2.py"
        if marke in alt:
            rest = "\n" + alt[alt.index(marke):]
    with open(pfad, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(zeilen) + "\n" + rest)


def rendern():
    os.makedirs(OUT, exist_ok=True)
    werte = {}
    for name, ms, pegel, *_ in TABELLE:
        l, r = fertig(baue(name), ms, pegel)
        schreibe(os.path.join(OUT, name + ".wav"), l, r)
        werte[name] = messen(l, r)
    ref_rms = werte["select"][1]
    print("%-13s %7s %8s %8s %9s" % ("Klang", "Länge", "Spitze", "RMS", "RMS/sel"))
    for name, *_ in TABELLE:
        p, rms, n = werte[name]
        print("%-13s %5.0f ms %6.1f dB %6.1f dB %+7.1f dB" % (name, n, p, rms, rms - ref_rms))
    quelle_schreiben()


def pruefen():
    fehler = 0
    werte = {}
    for name, ms, pegel, bew, rms_soll, _ in TABELLE:
        pfad = os.path.join(OUT, name + ".wav")
        if not os.path.isfile(pfad):
            print("  FAIL %s fehlt" % name)
            fehler += 1
            continue
        l, r, fr, ch = lies(pfad)
        if fr != SR or ch != 2:
            print("  FAIL %s: %d Hz, %d Kanäle (soll 44100, 2)" % (name, fr, ch))
            fehler += 1
        werte[name] = messen(l, r)
    if "select" not in werte:
        print("Ergebnis: select fehlt")
        return 1
    ref_rms = werte["select"][1]
    for name, ms, pegel, bew, rms_soll, _ in TABELLE:
        if name not in werte:
            continue
        p, rms, n = werte[name]
        pruef = [
            (abs(n - ms) <= 1.0, "Länge %.0f ms (soll %d)" % (n, ms)),
            (n <= bew + NACHKLANG_MS, "Länge ≤ Bewegung %d + %d ms" % (bew, NACHKLANG_MS)),
            (abs(p - (REF_DB + pegel)) <= TOL_DB, "Spitze %.1f dBFS (soll %.1f ± %.1f)" % (p, REF_DB + pegel, TOL_DB)),
            (abs((rms - ref_rms) - rms_soll) <= RMS_TOL_DB, "RMS %+.1f dB zu select (soll %+.1f ± %.1f)" % (rms - ref_rms, rms_soll, RMS_TOL_DB)),
        ]
        for ok, was in pruef:
            print("  %s %s: %s" % ("ok  " if ok else "FAIL", name, was))
            fehler += 0 if ok else 1
    # Ausschalten ist nicht mehr der lauteste Klang (heute RMS 5 dB über dem Start).
    if "power_off" in werte and "boot" in werte:
        lauter = [k for k in werte if werte[k][1] > werte["power_off"][1] + 0.01]
        ok = werte["power_off"][1] <= werte["boot"][1] and len(lauter) > 0
        print("  %s Ausschalten leiser als der Start und nicht der lauteste" % ("ok  " if ok else "FAIL"))
        fehler += 0 if ok else 1
    print("Ergebnis: %s" % ("alles ok" if fehler == 0 else "%d Fehler" % fehler))
    return 1 if fehler else 0


def hoerprobe(ziel, tabelle=None):
    """Alle Klänge hintereinander (je 0,6 s Pause), danach Blättern (Halten, 10 Schritte) wie in sfx.gd."""
    rng = random.Random(99)
    L, R = [], []
    pause = [0.0] * int(0.6 * SR)
    zeilen = []
    for name, ms, pegel, bew, _, was in TABELLE:
        l, r, _, _ = lies(os.path.join(OUT, name + ".wav"))
        p, rms, n = messen(l, r)
        zeilen.append((name, n, p, rms, pegel, was, len(L) / SR))
        L += l + pause
        R += r + pause
    # Blättern beim Halten: 400 ms, dann 162/120/96 ms; ab dem vierten Schritt bis −8 dB leiser,
    # Tonhöhe ±1,5 %, Lautstärke ±0,5 dB (Klang.bewegen in src/core/klang.gd).
    ml, mr, _, _ = lies(os.path.join(OUT, "move.wav"))
    t = len(L) / SR
    start = t
    abst = [0.4, 0.162, 0.162, 0.162, 0.12, 0.12, 0.12, 0.12, 0.096, 0.096, 0.096, 0.096]
    streak = 0
    for i, a in enumerate([0.0] + abst):
        t += a
        if a and a < 0.26:
            streak += 1
        g = amp(-8.0 * min(streak / 4.0, 1.0) + rng.uniform(-0.5, 0.5))
        k = rng.uniform(0.985, 1.015)
        n = int(len(ml) / k)
        sl = [ml[min(int(j * k), len(ml) - 1)] * g for j in range(n)]
        sr = [mr[min(int(j * k), len(mr) - 1)] * g for j in range(n)]
        add(L, t, sl)
        add(R, t, sr)
    L += pause
    R += pause
    n = max(len(L), len(R))
    L += [0.0] * (n - len(L))
    R += [0.0] * (n - len(R))
    # Lautstärke wie beim Standardregler (0,6 × 0,75), damit die Probe so laut ist wie in Uzai.
    g = 0.45
    schreibe(ziel, [v * g for v in L], [v * g for v in R])
    print("Hörprobe:", ziel, "%.1f s" % (n / SR))
    if tabelle:
        ref = [z for z in zeilen if z[0] == "select"][0]
        with open(tabelle, "w", encoding="utf-8") as f:
            f.write("# Klangsatz „Tick“ – Hörprobe\n\n")
            f.write("Reihenfolge wie in `hoerprobe.wav` (je 0,6 s Pause), danach ab %.1f s Blättern beim Halten "
                    "(13 Schritte, bis −8 dB leiser). Pegel in der Datei; in Uzai kommt der Regler dazu "
                    "(Standard 0,6 × 0,75 ≈ −7 dB, so ist auch die Hörprobe gemischt).\n\n" % start)
            f.write("| Ab | Name | Ereignis | Dauer | Pegel (Spitze zu select) | Spitze | RMS 50 ms |\n|---|---|---|---|---|---|---|\n")
            for name, n_ms, p, rms, pegel, was, ab in zeilen:
                f.write("| %.2f s | %s | %s | %.0f ms | %+.1f dB | %.1f dBFS | %.1f dBFS |\n" % (ab, name, was, n_ms, p - ref[2], p, rms))
        print("Tabelle:", tabelle)


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--pruefen" in a:
        sys.exit(pruefen())
    if "--hoerprobe" in a:
        i = a.index("--hoerprobe")
        tab = a[a.index("--tabelle") + 1] if "--tabelle" in a else None
        hoerprobe(a[i + 1], tab)
        sys.exit(0)
    rendern()
