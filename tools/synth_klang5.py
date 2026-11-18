#!/usr/bin/env python3
# Sound set „Handpan“ (default): a deep, soft handpan with a round attack and a long decay –
# the „Tief rund“ template selected in the listening test, rebuilt note by note. Also the setup
# sounds (assets/sounds/einrichtung/su_*.wav) in the same instrument.
# Python standard library only (wave, struct, math, cmath, random with a fixed seed): same source,
# same files. No recordings, no third-party samples. Building blocks from tools/synth_klang3.py and synth_klang4.py.
#
#   python3 tools/synth_klang5.py                  renders assets/sounds/handpan/*.wav and assets/sounds/einrichtung/*.wav,
#                                                  prints measurements, updates assets/sounds/KLANG-QUELLE.txt (SHA-256)
#   python3 tools/synth_klang5.py --einrichtung    only assets/sounds/einrichtung/*.wav
#   python3 tools/synth_klang5.py --pruefen        checks all files against table, template and targets (exit 1 on mismatch)
#   python3 tools/synth_klang5.py --hoerprobe ordner
#                                                  each file separately (name = event), hoerprobe.md with measurements
#
# Afterwards, once: godot --headless --path . --import
#
# The tone (template „Tief rund“): modal partials like a handpan note field – fundamental, octave, twelfth (3.01:
# slightly stretched) and the sub-octave (0.5, the „belly“). Amplitudes 1 : 0.175 : 0.06 : 0.24 (the
# overtones half as strong as on a bright instrument, the sub-octave 1.6 times), decay times
# τ = 0.5 s · s, 0.25 s · s, 0.1 s · s, 0.3 s · s (s: length of the note). Each partial starts at a random
# phase and swells in over 14 ms (half cosine over the decaying envelope) – no hand or noise strike,
# nothing glassy. A note lasts max(0.3 s, 2.4 s · s). Then a room: exponentially decaying noise
# (0.4 s), low-pass 4 kHz, 6 ms pre-delay, normalized to energy 1, wet 0.2; high-pass 70 Hz; the end
# is where the sound is 50 dB below its peak (gently faded out). Everything in D minor pentatonic
# (D F G A C), calm and low. Levels as short-term RMS (50 ms): the ratios of the listening test, everything
# 10 dB quieter than there (the listening test was mixed louder for comparison in the browser; in the game
# „Handpan“ sits at the level of the previous defaults): move −36, select −29, back −31, open −28 dBFS.
#
# The handpan deliberately rings on (open a good 2.5 s with room). Select is the exception: two quick, short
# notes in a small room (RAUM_KURZ, a good 0.8 s), because the template's long, deep note became tiring when
# clicking through quickly; the long sound is reserved for the Guide. That is why separate rules apply here
# instead of „sound ≤ movement + 60 ms“ (Klang.PALETTE): every sound has a maximum length (TABELLE), the core
# of the note is short where the movement is short (move, tick: τ 60 and 40 ms, then only the room), and Sfx
# handles the rest: move cuts off its own tail, a silenced player counts as free (src/core/sfx.gd).
# The power-off sound ends before the animation does (1.55 s; power_off.gd stops at 1.6 s at the latest).
# --pruefen also checks the template's measurements (VORLAGE): spectral centroid and decay stay as chosen.
import cmath, math, os, random, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth_klang3 as k3  # noqa: E402  (Filter, Dateien, Messung)
import synth_klang4 as k4  # noqa: E402  (FFT, Analyse, Messtabelle)

SR = k3.SR
ns, amp, db, peak, biquad, CENT = k3.ns, k3.amp, k3.db, k3.peak, k3.biquad, k3.CENT
VORLAUF_MS = k3.VORLAUF_MS
SOUNDS = k3.SOUNDS
QUELLE = k3.QUELLE
MARKE = "Klangsatz „Handpan“ aus tools/synth_klang5.py"
SATZ = "handpan"
NAME = "Handpan"
ORDNER = os.path.join(SOUNDS, SATZ)
EINR = "einrichtung"
EINR_ORDNER = os.path.join(SOUNDS, EINR)

# Pegel von „select“ als Kurzzeit-RMS (lautestes 50-ms-Fenster) in dBFS: 10 dB unter der Hörprobe (−19).
REF_DB = -29.0
HOERPROBE_DB = 10.0               # --hoerprobe hebt die Dateien so weit an: so laut wie die Vorlage

# --- Das Instrument (Vorlage „Tief rund“) ---------------------------------------------------------
VERH = (1.0, 2.0, 3.01, 0.5)
HELL, TIEF = 0.5, 1.6
AMPL = (1.0, 0.35 * HELL, 0.12 * HELL, 0.15 * TIEF)
TAU = (0.5, 0.25, 0.1, 0.3)       # s, mal der Länge s eines Tons
ANSTIEG_S = 0.014
HALL_S, HALL_NASS, HALL_LP, HALL_VOR_S = 0.4, 0.2, 4000.0, 0.006
## Kleiner Raum (Abklingzeit s, nass) für Klänge, die oft hintereinander kommen: Bestätigen (Hörprobe „B3“).
RAUM_KURZ = {"select": (0.18, 0.08)}
# Startwert des Raumrauschens. Ein Rauschraum verstärkt jede Tonhöhe zufällig anders: bei tonalen Klängen
# entscheidet die Verwirklichung, wie lange ein Ton im Raum steht. Von 400 Startwerten klingen mit diesem
# Bewegen, Bestätigen, Zurück und Öffnen am genauesten so ab wie die Vorlage (VORLAGE, Abweichung unter 10 %).
RAUM_START = "uzai-klang5-raum-372"
TIEFSTES_HZ = 70.0
ENDE_DB = -50.0                   # das Ende liegt dort, wo der Klang so weit unter seiner Spitze ist
AUSBLENDEN_MS = 10.0
KAPPEN_MS = 150.0                 # Ausblenden, wenn die Höchstlänge vor dem natürlichen Ende greift
SPITZE_MAX_DB = -6.0

# Die Tabelle: Höchstlänge ms (Datei samt Nachklang), Pegel dB (Kurzzeit-RMS zu „select“), Fassungen, Ereignis.
# Fassungen wie bei „Samt“: <name>.wav, <name>_v2.wav … (Klang.variante), nur ein paar Cent und Millisekunden
# verschieden, die erste genau wie die Vorlage.
TABELLE = [
    # name           ms   pegel  fass.  Ereignis
    ("move",        2100,  -7.0,  4, "Fokus: A4, kurz (Vorlage)"),
    ("tick",        2000,  -8.0,  3, "Regler, Raste, Lautstärke: C5, kürzer"),
    ("bump",        2300,  -5.0,  2, "Grenze erreicht: gedämpftes A3"),
    ("select",      1100,   0.0,  3, "Bestätigen: D4, 35 ms später A4, beide kurz, kleiner Raum (Hörprobe B3)"),
    ("back",        2600,  -2.0,  2, "Zurück: A4, 70 ms später D4 (Vorlage)"),
    ("open",        3000,   1.0,  1, "Ebene oder Seite auf: D3 A3 D4 F4 (Vorlage)"),
    ("toggle_on",   2500,  -3.0,  2, "Schalter an: F4 → A4"),
    ("toggle_off",  2500,  -4.0,  2, "Schalter aus: A4 → F4"),
    ("tab",         2600,  -4.0,  1, "Bereich, Unterbereich, App: F4 mit leiser Quinte (eine Fassung: beim Blättern mit LB/RB immer derselbe Ton)"),
    ("guide",       3000,   0.0,  1, "Guide auf: D4 F4 A4 D5"),
    ("guide_close", 2700,  -2.5,  1, "Guide zu: A4 F4 D4"),
    ("error",       2800,  -1.0,  1, "Fehler: D4, Tritonus abwärts Gis3"),
    ("notify",      2900,  -1.0,  1, "Mitteilung: A4 → D5"),
    ("launch",      3300,   1.0,  1, "Spielen: D3 + D4, A4, D5, F5"),
    ("boot",        4300,   2.0,  1, "Start-Signatur: Punkt 0,30 s (D3 + D4), U 0,62 s (A3), Name 1,08 s (D4 F4 A4 D5)"),
    ("power_off",   1550,  -0.5,  1, "Ausschalten: ab 0,62 s D5 A4 F4 D4 abwärts, endet vor 1,6 s"),
    ("shutter",     2100,  -4.0,  1, "Bildschirmfoto: C5, G4 gedämpft"),
    ("achievement", 3300,   2.0,  1, "Erfolg: D4 F4 A4 C5 D5 über D3"),
    ("unlock",      3100,   2.0,  1, "Abzeichen: A4 → D5 über D3"),
    ("unlock_rare", 3500,   2.0,  1, "seltenes Abzeichen: D4 A4 D5 F5 A5 über D3"),
    ("unlock_retro", 2400,  1.0,  1, "Erfolg im Retro-Spiel: D4 A4 D5, kürzer"),
    ("setup_step",  2600,  -2.0,  1, "Einrichtung: Schritt weiter, F4 mit Unteroktave (Grundton F, Klang.stufe_ton)"),
    ("setup_found", 2800,  -3.0,  1, "Einrichtung: etwas gefunden, F3 → F4 (Grundton F)"),
    ("setup_done",  3500,   2.0,  1, "Einrichtung fertig: D3 A3 D4 F4 A4 C5"),
    ("swell",       3600,   0.0,  1, "Licht geht an: Wirbel auf D3/A3 schwillt an, dann D4 A4 D5"),
]
PEGEL_TOL_DB = 1.0

# Klänge der Einrichtung (assets/sounds/einrichtung, unabhängig vom Satz) im selben Instrument: Höchstlänge ms,
# Pegel dB (Kurzzeit-RMS zu „select“ von „Handpan“), Ereignis. Wo die Einrichtung die Tonhöhe selbst stimmt
# (Klang.stufe_ton: Dur-pentatonisch über dem Ton der Datei), ist der Grundton F: F G A C D – das sind genau
# die Töne von D-Moll pentatonisch, jede Stufe passt zum Menü. Diese Klänge haben nur F und seine Oktaven.
EINR_TABELLE = [
    ("su_einschalten", 4600, 2.0, "Start: D3 + D4 bei 0,30 s, A3 bei 0,62 s, D4 F4 A4 C5 D5 ab 1,08 s, ruhig"),
    ("su_weiter", 2600, -4.0, "weiter: F4 mit Unteroktave (Grundton F)"),
    ("su_zurueck", 2400, -6.0, "zurück: A4 → F4, weicher"),
    ("su_controller", 2900, 0.0, "Controller verbunden: A4 → D5"),
    ("su_taste", 2300, -5.0, "Taste: F4 (Grundton F)"),
    ("su_trigger", 1900, -9.0, "Trigger: kleiner Wirbel auf A3, schwillt mit dem Druck an"),
    ("su_test_fertig", 3000, 0.0, "alles getestet: D4 F4 A4 D5 aufwärts"),
    ("su_huelle", 1900, -9.0, "Hülle: F4 gedämpft mit Unteroktave (Grundton F)"),
    ("su_quelle", 2000, -6.0, "Quelle: A3, kurz"),
    ("su_gefunden", 3400, 1.0, "gefunden: Wirbel auf D3/A3, dann D4 F4 A4 C5 (je 25 ms versetzt)"),
    ("su_leer", 2700, -7.0, "nichts gefunden: zwei weiche Töne abwärts, A4 → D4"),
    ("su_kapitel", 2500, -7.0, "Kapitel: G4 mit Unteroktave"),
    ("su_mosaik", 2300, -8.0, "Mosaik: fünf leise Töne D5 A4 C5 F4 D5"),
    ("su_zimmer", 3500, -4.0, "Portal öffnet sich: Wirbel auf A3/D4 schwillt an, dann D4 A4 D5"),
    ("su_geschafft", 2900, 0.0, "geschafft: A4 → D5"),
    ("su_verbunden", 2900, 0.0, "verbunden: D4 F4 A4"),
    ("su_freund", 2000, -6.0, "Freund: F4, kurz (Grundton F)"),
    ("su_bereit", 4600, 1.0, "bereit: langsamer Wirbel auf D3/A3, dann D3 A3 D4 F4 A4 C5 D5 gefächert"),
]

# Messwerte der Vorlage (t07 „Tief rund“ der Hörprobe, 48 kHz mono): Spektralschwerpunkt Hz und die Abklingkurve
# – Zeit (s), bis die rückwärts aufsummierte Energie (Schroeder) 10, 20 und 30 dB unter ihrem Anfang liegt.
# --pruefen hält die Nachbildung daran.
# Bestätigen hat seit 0.16.8 eine eigene Vorlage: „B3“ aus der zweiten Hörprobe (zwei schnelle Töne, kurz).
SEL_SCHWERPUNKT, SEL_ABKLINGEN = 373.0, (0.165, 0.339, 0.481)
VORLAGE = {
    "move": (463.0, (0.19, 0.70, 1.12)),
    "select": (SEL_SCHWERPUNKT, SEL_ABKLINGEN),
    "back": (366.0, (0.55, 1.13, 1.66)),
    "open": (263.0, (0.68, 1.22, 1.81)),
}
VORLAGE_SCHWERPUNKT_TOL = 0.10     # Anteil
VORLAGE_ZEIT_TOL = 0.15            # Anteil (die Nachbildung liegt unter 10 %)

# Ziele (--pruefen). Wie bei „Samt“ – Bewegen und Raste dunkel, ohne Knacken, leise, gestaffelt; nichts über
# 5 kHz – aber ohne die Längen der Palette (siehe oben) und mit tieferem Band: die Unteroktave (0,5) und D3
# liegen gewollt unter 200 Hz („Tief rund“), Fernseher geben sie leiser wieder, der Grundton trägt.
NAV = ("move", "tick")
NAV_SCHWERPUNKT = 1500.0
NAV_UEBER_6K = 0.05
NAV_SPITZE_DB = -12.0
NAV_ABSTAND_DB = 6.0
KERN_SCHWERPUNKT = 2200.0
UEBER_5K_MAX = 0.03
ANSTIEG_MIN_MS = 5.0               # 10 → 90 %: jeder Anschlag schwillt weich an (14 ms halber Kosinus) …
# … geprüft an den Klängen aus einem Anschlag. Wo mehrere Töne klingen, schwankt die Hülle mit den
# Differenzfrequenzen der Teiltöne (Schwebung), und die Messung hielte jedes Wiederansteigen für einen Anschlag;
# dort sind es dieselben Anschläge, nur gestaffelt.
EINZELN = ("move", "tick", "bump", "setup_step", "su_weiter", "su_taste", "su_huelle", "su_quelle", "su_kapitel", "su_freund")
TV_MIN = 0.50                      # Anteil zwischen 200 Hz und 3 kHz
ENDE_MAX_DB = -36.0
KORR_MIN = 0.55


# --- Töne ------------------------------------------------------------------------------------------

_HALBTON = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "H": 2, "B": 2}


def note(n):
    """„D4“ → 293,7 Hz; „G#3“, „Bb3“ mit Vorzeichen (H und B sind dasselbe)."""
    name, okt = n[:-1], int(n[-1])
    vz = 1 if name.endswith("#") else (-1 if len(name) > 1 and name.endswith("b") else 0)
    return 440.0 * 2.0 ** ((_HALBTON[name[0]] + vz + 12 * (okt - 4)) / 12.0)


def ton(rng, f, s=1.0, a=1.0):
    """Ein Handpan-Ton (Vorlage): die vier Teiltöne mit zufälliger Startphase, Hülle exp(−t/τ), darüber in
    14 ms ein halber Kosinus. Länge max(0,3 s, 2,4 s · s). Liste, Spitze ≈ a."""
    n = int(max(0.3, 2.4 * s) * SR)
    out = [0.0] * n
    na = max(1, int(ANSTIEG_S * SR))
    an = [0.5 - 0.5 * math.cos(math.pi * i / na) for i in range(na)]
    for r, g, t in zip(VERH, AMPL, TAU):
        fr = f * r
        ph = rng.uniform(0.0, 6.28)
        if fr >= SR / 2.2:
            continue
        # z dreht sich je Wert um 2π f / SR und schrumpft um exp(−1 / (τ SR)): Imaginärteil = Sinus mal Hülle.
        w = cmath.exp(complex(-1.0 / (t * s * SR), 2.0 * math.pi * fr / SR))
        z = a * g * cmath.exp(complex(0.0, ph))
        for i in range(n):
            v = z.imag
            out[i] += v * an[i] if i < na else v
            z *= w
            if i > na and abs(z) < 1e-7:
                break
    return out


class Spiel:
    """Mischpult eines Klangs (mono, wie die Vorlage): Töne zu Zeitpunkten in ms."""

    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.x = []

    def ton(self, n, at_ms, a=1.0, s=1.0, cent=0.0):
        f = (note(n) if isinstance(n, str) else n) * CENT ** cent
        k3.add(self.x, int(at_ms * SR / 1000.0), ton(self.rng, f, s, a))

    def wirbel(self, noten, von_ms, bis_ms, schritt_ms, a0, a1, s=0.5):
        """Ein Wirbel: weiche Schläge im Wechsel auf noten, leise beginnend, bis a1 anschwellend."""
        k = max(1, int((bis_ms - von_ms) / schritt_ms))
        for i in range(k + 1):
            u = i / k
            self.ton(noten[i % len(noten)], von_ms + i * schritt_ms, a0 + (a1 - a0) * u * u, s, cent=(0.0, 3.0, -2.0)[i % 3])


# --- Raum und Fertigstellung (Vorlage: hall, fertig) ---------------------------------------------

_IR = {}


def _ir(hall_s=HALL_S):
    if ("ir", hall_s) not in _IR:
        n = int(hall_s * 5 * SR)
        r = random.Random(RAUM_START)
        ir = [r.gauss(0.0, 1.0) * math.exp(-i / SR / hall_s) for i in range(n)]
        ir = biquad(ir, "lp", HALL_LP)
        for i in range(int(HALL_VOR_S * SR)):
            ir[i] = 0.0
        e = math.sqrt(sum(v * v for v in ir))
        _IR[("ir", hall_s)] = [v / e for v in ir]
    return _IR[("ir", hall_s)]


def hall(x, raum=(HALL_S, HALL_NASS)):
    """Faltung mit dem Raum (über die FFT), trocken plus nass; Länge len(x) + len(ir). raum: (Abklingzeit s, nass)."""
    hall_s, nass = raum
    ir = _ir(hall_s)
    n = len(x) + len(ir)
    m = 1 << (n - 1).bit_length()
    if (m, hall_s) not in _IR:
        _IR[(m, hall_s)] = k4._fft_c([complex(v, 0.0) for v in ir] + [0j] * (m - len(ir)))
    H = _IR[(m, hall_s)]
    X = k4._fft_c([complex(v, 0.0) for v in x] + [0j] * (m - len(x)))
    y = k4._fft_c([a * b for a, b in zip(X, H)], True)
    out = [0.0] * n
    for i in range(n):
        out[i] = (x[i] if i < len(x) else 0.0) + nass * y[i].real / m
    return out


def kurz_rms(x):
    """Kurzzeit-RMS (dBFS) wie in der Hörprobe: lautestes 50-ms-Fenster, Schritt ein Wert."""
    w = ns(50)
    if len(x) <= w:
        return db(math.sqrt(sum(v * v for v in x) / max(1, len(x))))
    acc = [0.0]
    for v in x:
        acc.append(acc[-1] + v * v)
    return 10.0 * math.log10(max(acc[i + w] - acc[i] for i in range(len(x) - w + 1)) / w + 1e-12)


def fertig(x, ziel_db, max_ms, raum=(HALL_S, HALL_NASS)):
    """Raum, Hochpass, Ende 50 dB unter der Spitze (höchstens max_ms samt Vorlauf, dann länger ausgeblendet),
    Pegel, Spitze ≤ −6 dBFS, 1 ms Vorlauf. Gibt (L, R), beide gleich (wie die Vorlage)."""
    x = biquad(hall(x, raum), "hp", TIEFSTES_HZ)
    p = peak(x)
    grenze = p * amp(ENDE_DB)
    letzt = max(i for i, v in enumerate(x) if abs(v) > grenze)
    x = x[:letzt + 1]
    fade = ns(AUSBLENDEN_MS)
    cap = ns(max_ms - VORLAUF_MS)
    if len(x) > cap:
        x = x[:cap]
        fade = ns(KAPPEN_MS)
    fade = min(fade, len(x))
    for i in range(fade):
        x[len(x) - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade)
    g = amp(ziel_db - kurz_rms(x))
    x = [v * g for v in x]
    sp = peak(x)
    if sp > amp(SPITZE_MAX_DB):
        g = amp(SPITZE_MAX_DB) / sp
        x = [v * g for v in x]
    x = [0.0] * ns(VORLAUF_MS) + x
    x[-1] = 0.0
    return x, list(x)


# --- Die Klänge ------------------------------------------------------------------------------------

# Fassungen: Verstimmung in Cent und, wo zwei Töne folgen, der Abstand in ms.
CENT_FASS = {"move": (0.0, 6.0, -5.0, 9.0), "tick": (0.0, 7.0, -6.0), "bump": (0.0, -8.0), "select": (0.0, 5.0, -4.0),
             "back": (0.0, -5.0), "toggle_on": (0.0, 6.0), "toggle_off": (0.0, -6.0)}
ABSTAND_FASS = {"select": (35, 33, 37), "back": (70, 74), "toggle_on": (60, 56), "toggle_off": (60, 64)}


def baue(name, v):
    """Ein Ereignis des Satzes (Fassung v) als Liste (mono, ohne Raum)."""
    k = Spiel("uzai-klang5-handpan-%s-%d" % (name, v))
    t = k.ton
    c = CENT_FASS.get(name, (0.0,) * 4)[v]
    dt = ABSTAND_FASS.get(name, (70,) * 4)[v]
    if name == "move":
        t("A4", 0, 0.5, 0.12, c)
    elif name == "tick":
        # kürzer und eine Spur höher als Bewegen
        t("C5", 0, 0.5, 0.08, c)
    elif name == "bump":
        # gedämpft und tief: der Ton klingt kaum nach
        t("A3", 0, 0.9, 0.22, c)
    elif name == "select":
        # zwei schnelle, kurze Töne: hell genug zum Durchklicken, der lange Klang bleibt dem Guide
        t("D4", 0, 1.0, 0.28, c)
        t("A4", dt, 0.7, 0.25, c)
    elif name == "back":
        t("A4", 0, 0.6, 0.6, c)
        t("D4", dt, 0.9, 0.8, c)
    elif name == "open":
        for n, at, a in (("D3", 0, 0.8), ("A3", 70, 0.8), ("D4", 140, 0.7), ("F4", 210, 0.5)):
            t(n, at, a, 1.0)
    elif name in ("toggle_on", "toggle_off"):
        f1, f2 = ("F4", "A4") if name == "toggle_on" else ("A4", "F4")
        t(f1, 0, 0.55, 0.45, c)
        t(f2, dt, 0.8, 0.55, c)
    elif name == "tab":
        t("F4", 0, 0.85, 0.5, c)
        t("C5", 45, 0.35, 0.4, c)
    elif name == "guide":
        for n, at, a in (("D4", 0, 0.8), ("F4", 55, 0.7), ("A4", 110, 0.65), ("D5", 165, 0.55)):
            t(n, at, a, 0.9)
    elif name == "guide_close":
        for n, at, a in (("A4", 0, 0.55), ("F4", 55, 0.65), ("D4", 110, 0.8)):
            t(n, at, a, 0.7)
    elif name == "error":
        # Freundlich „nein“: D4, dann der Tritonus abwärts – fremd in der Tonleiter, aber weich und tief.
        t("D4", 0, 0.9, 0.55)
        t("G#3", 110, 0.9, 0.6)
    elif name == "notify":
        t("A4", 0, 0.75, 0.6)
        t("D5", 95, 0.7, 0.8)
    elif name == "launch":
        t("D3", 0, 0.7, 1.1)
        for n, at, a in (("D4", 0, 0.9), ("A4", 70, 0.7), ("D5", 140, 0.6), ("F5", 210, 0.45)):
            t(n, at, a, 1.0)
    elif name == "boot":
        # Punkt (0,30 s): D3 mit D4, U (0,62 s): A3, Name (1,08 s): D4 F4 A4 D5 gefächert.
        t("D3", 300, 0.8, 1.2)
        t("D4", 300, 0.55, 1.0)
        t("A3", 620, 0.7, 1.0)
        for i, (n, a) in enumerate((("D4", 0.6), ("F4", 0.55), ("A4", 0.5), ("D5", 0.42))):
            t(n, 1080 + 60 * i, a, 1.0)
    elif name == "power_off":
        # Ein leiser Druck, dann fällt das Zeichen (ab 0,62 s): D5 A4 F4 D4, kurz genug für 1,55 s.
        t("A3", 0, 0.35, 0.3)
        for i, (n, a) in enumerate((("D5", 0.45), ("A4", 0.55), ("F4", 0.65), ("D4", 0.8))):
            t(n, 620 + 50 * i, a, 0.55)
    elif name == "shutter":
        t("C5", 0, 0.6, 0.15)
        t("G4", 60, 0.7, 0.2)
    elif name in ("achievement", "unlock", "unlock_rare"):
        folge = {
            "achievement": (("D4", 0, 0.8), ("F4", 65, 0.75), ("A4", 130, 0.7), ("C5", 195, 0.6), ("D5", 260, 0.55)),
            "unlock": (("A4", 0, 0.8), ("D5", 80, 0.75)),
            "unlock_rare": (("D4", 0, 0.8), ("A4", 55, 0.75), ("D5", 110, 0.7), ("F5", 165, 0.55), ("A5", 220, 0.45)),
        }[name]
        s = 1.1 if name == "unlock_rare" else 1.0
        t("D3", 0, 0.5 if name != "unlock" else 0.45, 1.2)
        for n, at, a in folge:
            t(n, at, a, s)
    elif name == "unlock_retro":
        for n, at, a in (("D4", 0, 0.8), ("A4", 70, 0.75), ("D5", 140, 0.65)):
            t(n, at, a, 0.6)
    elif name == "setup_step":
        # Grundton F (Klang.stufe_ton stimmt ihn dur-pentatonisch hoch: F G A C D = D-Moll pentatonisch).
        t("F4", 0, 1.0, 0.7)
        t("F3", 0, 0.35, 0.6)
    elif name == "setup_found":
        t("F3", 0, 0.4, 0.5)
        t("F4", 70, 0.9, 0.8)
    elif name == "setup_done":
        for i, (n, a) in enumerate((("D3", 0.6), ("A3", 0.7), ("D4", 0.75), ("F4", 0.7), ("A4", 0.6), ("C5", 0.5))):
            t(n, 50 * i, a, 1.1)
    elif name == "swell":
        k.wirbel(("D3", "A3"), 0, 700, 60, 0.08, 0.5)
        for n, at, a in (("D4", 760, 0.7), ("A4", 775, 0.55), ("D5", 790, 0.4)):
            t(n, at, a, 1.1)
    else:
        raise KeyError(name)
    return k.x


def baue_einr(name):
    """Ein Klang der Einrichtung im selben Instrument (mono, ohne Raum)."""
    k = Spiel("uzai-klang5-einrichtung-%s" % name)
    t = k.ton
    if name == "su_einschalten":
        t("D3", 300, 0.8, 1.4)
        t("D4", 300, 0.5, 1.2)
        t("A3", 620, 0.7, 1.3)
        for i, (n, a) in enumerate((("D4", 0.6), ("F4", 0.55), ("A4", 0.5), ("C5", 0.45), ("D5", 0.4))):
            t(n, 1080 + 70 * i, a, 1.3)
    elif name == "su_weiter":
        t("F4", 0, 1.0, 0.7)
        t("F3", 0, 0.35, 0.6)
    elif name == "su_zurueck":
        t("A4", 0, 0.55, 0.4)
        t("F4", 80, 0.85, 0.6)
    elif name == "su_controller":
        t("A4", 0, 0.7, 0.5)
        t("D5", 100, 0.8, 0.8)
    elif name == "su_taste":
        t("F4", 0, 0.9, 0.45)
    elif name == "su_trigger":
        k.wirbel(("A3",), 0, 135, 45, 0.15, 0.6, s=0.3)
    elif name == "su_test_fertig":
        for n, at, a in (("D4", 0, 0.8), ("F4", 55, 0.75), ("A4", 110, 0.7), ("D5", 165, 0.7)):
            t(n, at, a, 0.9)
    elif name == "su_huelle":
        t("F4", 0, 0.85, 0.15)
        t("F3", 0, 0.3, 0.15)
    elif name == "su_quelle":
        t("A3", 0, 0.9, 0.35)
    elif name == "su_gefunden":
        k.wirbel(("D3", "A3"), 0, 300, 60, 0.1, 0.45)
        for i, (n, a) in enumerate((("D4", 0.7), ("F4", 0.65), ("A4", 0.6), ("C5", 0.5))):
            t(n, 360 + 25 * i, a, 1.1)
    elif name == "su_leer":
        t("A4", 0, 0.75, 0.5)
        t("D4", 140, 0.85, 0.6)
    elif name == "su_kapitel":
        t("G4", 0, 0.85, 0.5)
        t("G3", 0, 0.3, 0.45)
    elif name == "su_mosaik":
        for n, at, a in (("D5", 0, 0.55), ("A4", 70, 0.6), ("C5", 150, 0.5), ("F4", 215, 0.6), ("D5", 300, 0.55)):
            t(n, at, a, 0.35)
    elif name == "su_zimmer":
        k.wirbel(("A3", "D4"), 0, 480, 60, 0.06, 0.4)
        for n, at, a in (("D4", 520, 0.7), ("A4", 535, 0.55), ("D5", 550, 0.45)):
            t(n, at, a, 1.0)
    elif name == "su_geschafft":
        t("A4", 0, 0.75, 0.5)
        t("D5", 85, 0.85, 0.9)
    elif name == "su_verbunden":
        for n, at, a in (("D4", 0, 0.8), ("F4", 65, 0.75), ("A4", 130, 0.7)):
            t(n, at, a, 0.8)
    elif name == "su_freund":
        t("F4", 0, 0.8, 0.3)
    elif name == "su_bereit":
        k.wirbel(("D3", "A3"), 0, 840, 70, 0.05, 0.4)
        for i, (n, a) in enumerate((("D3", 0.6), ("A3", 0.6), ("D4", 0.65), ("F4", 0.6), ("A4", 0.55), ("C5", 0.45), ("D5", 0.4))):
            t(n, 880 + 40 * i, a, 1.4)
    else:
        raise KeyError(name)
    return k.x


# --- Dateien ---------------------------------------------------------------------------------------

def datei(name, v):
    return k3.datei(name, v)


def alle_dateien():
    for name, ms, pegel, fass, _ in TABELLE:
        for v in range(fass):
            yield name, v, ms, pegel


def quelle_schreiben():
    """Ergänzt KLANG-QUELLE.txt am Ende: alles vor MARKE bleibt, ab MARKE dieser Satz und die Einrichtung."""
    alt = ""
    if os.path.isfile(QUELLE):
        with open(QUELLE, encoding="utf-8") as f:
            alt = f.read()
    if MARKE in alt:
        alt = alt[:alt.index(MARKE)]
    zeilen = [MARKE + " (%s/): tiefe, weiche Handpan (Vorlage „Tief rund“), D-Moll pentatonisch, mit Raum." % SATZ,
              "Nur Python-Standardbibliothek, feste Startwerte (gleiche Quelle, gleiche Dateien). 44,1 kHz, Stereo, 16 Bit.",
              ""]
    for name, v, *_ in alle_dateien():
        p = os.path.join(ORDNER, datei(name, v))
        if os.path.isfile(p):
            zeilen.append("%s  %s/%s" % (k3.sha(p), SATZ, datei(name, v)))
    zeilen += ["", "Klänge der Einrichtung (einrichtung/, unabhängig vom Satz) aus tools/synth_klang5.py: dieselbe Handpan,",
               "D-Moll pentatonisch, Grundton F, wo die Einrichtung die Tonhöhe stimmt.", ""]
    for name, *_ in EINR_TABELLE:
        p = os.path.join(EINR_ORDNER, name + ".wav")
        if os.path.isfile(p):
            zeilen.append("%s  %s/%s.wav" % (k3.sha(p), EINR, name))
    with open(QUELLE, "w", encoding="utf-8", newline="\n") as f:
        f.write(alt.rstrip("\n") + "\n\n" + "\n".join(zeilen) + "\n")


def rendern(satz=True, einrichtung=True):
    if satz:
        os.makedirs(ORDNER, exist_ok=True)
        print("Satz „%s“ (%s)" % (NAME, SATZ))
        print(k4.KOPF)
        for name, v, ms, pegel in alle_dateien():
            L, R = fertig(baue(name, v), REF_DB + pegel, ms, RAUM_KURZ.get(name, (HALL_S, HALL_NASS)))
            k3.schreibe(os.path.join(ORDNER, datei(name, v)), L, R)
            print(k4._zeile(name, v, k4.analyse(L, R), REF_DB))
    if einrichtung:
        os.makedirs(EINR_ORDNER, exist_ok=True)
        print("Einrichtung (%s)" % EINR)
        print(k4.KOPF)
        for name, ms, pegel, _ in EINR_TABELLE:
            L, R = fertig(baue_einr(name), REF_DB + pegel, ms)
            k3.schreibe(os.path.join(EINR_ORDNER, name + ".wav"), L, R)
            print(k4._zeile(name, 0, k4.analyse(L, R), REF_DB))
    quelle_schreiben()


# --- Prüfen ----------------------------------------------------------------------------------------

def abklingen(x):
    """Abklingkurve nach Schroeder: Zeiten (s), bis die von hinten aufsummierte Energie 10, 20 und 30 dB unter
    der gesamten liegt – glatt, unabhängig vom Zufall einzelner Fenster."""
    e = [0.0] * (len(x) + 1)
    for i in range(len(x) - 1, -1, -1):
        e[i] = e[i + 1] + x[i] * x[i]
    ges = e[0] or 1e-30
    out = []
    for d in (-10.0, -20.0, -30.0):
        g = ges * 10.0 ** (d / 10.0)
        out.append(next(i for i, v in enumerate(e) if v <= g) / SR)
    return out


def pruefen():
    fehler = 0

    def fail(was):
        nonlocal fehler
        print("  FAIL " + was)
        fehler += 1

    def gemeinsam(name, m, fr, ch, ms, soll_db):
        return [
            (fr == SR and ch == 2, "44,1 kHz, Stereo (%d Hz, %d Kanäle)" % (fr, ch)),
            (m["ms"] <= ms + 0.5, "Länge %.0f ms ≤ %d" % (m["ms"], ms)),
            (abs(m["rms"] - soll_db) <= PEGEL_TOL_DB or (m["rms"] < soll_db and m["spitze"] >= SPITZE_MAX_DB - 0.1),
             "RMS %.1f dBFS (soll %.1f)" % (m["rms"], soll_db)),
            (m["spitze"] <= SPITZE_MAX_DB + 0.05, "Spitze %.1f dBFS ≤ %.0f" % (m["spitze"], SPITZE_MAX_DB)),
            (m["ende"] <= ENDE_MAX_DB, "verklungen vor dem Ausblenden (%.0f dB)" % m["ende"]),
            (m["rand"] < 0.0012, "beginnt und endet bei null"),
            (m["korr"] >= KORR_MIN, "Stereo (Korrelation %.2f)" % m["korr"]),
            (m["ueber5k"] <= UEBER_5K_MAX, "über 5 kHz %.1f %% ≤ %.0f %%" % (m["ueber5k"] * 100, UEBER_5K_MAX * 100)),
            (m["tv23"] >= TV_MIN, "200 Hz–3 kHz %.0f %% ≥ %.0f %%" % (m["tv23"] * 100, TV_MIN * 100)),
            (name not in EINZELN or m["anstieg"] >= ANSTIEG_MIN_MS, "Anstieg %.1f ms ≥ %.0f (weich)" % (m["anstieg"], ANSTIEG_MIN_MS)),
        ]

    werte = {}
    for name, v, ms, pegel in alle_dateien():
        pfad = os.path.join(ORDNER, datei(name, v))
        d = "%s/%s" % (SATZ, datei(name, v))
        if not os.path.isfile(pfad):
            fail(d + " fehlt")
            continue
        l, r, fr, ch = k3.lies(pfad)
        m = k4.analyse(l, r)
        werte.setdefault(name, []).append(m)
        pr = gemeinsam(name, m, fr, ch, ms, REF_DB + pegel)
        if name in NAV:
            pr += [
                (m["schwerpunkt"] < NAV_SCHWERPUNKT, "Schwerpunkt %.0f Hz < %.0f" % (m["schwerpunkt"], NAV_SCHWERPUNKT)),
                (m["ueber6k"] < NAV_UEBER_6K, "über 6 kHz %.1f %%" % (m["ueber6k"] * 100)),
                (m["spitze"] <= NAV_SPITZE_DB, "Spitze %.1f dBFS ≤ %.0f" % (m["spitze"], NAV_SPITZE_DB)),
            ]
        if name in ("select", "back"):
            pr.append((m["schwerpunkt"] < KERN_SCHWERPUNKT, "Schwerpunkt %.0f Hz < %.0f" % (m["schwerpunkt"], KERN_SCHWERPUNKT)))
        if name in VORLAGE and v == 0:
            sw, zv = VORLAGE[name]
            z = abklingen([(a + b) * 0.5 for a, b in zip(l, r)])
            pr += [
                (abs(m["schwerpunkt"] / sw - 1.0) <= VORLAGE_SCHWERPUNKT_TOL, "Schwerpunkt %.0f Hz wie die Vorlage (%.0f)" % (m["schwerpunkt"], sw)),
                (all(abs(a / b - 1.0) <= VORLAGE_ZEIT_TOL for a, b in zip(z, zv)),
                 "Abklingen −10/−20/−30 dB bei %s s wie die Vorlage (%s)" % ("/".join("%.2f" % a for a in z), "/".join("%.2f" % b for b in zv))),
            ]
        for ok, was in pr:
            if not ok:
                fail("%s: %s" % (d, was))
    if "select" in werte:
        sel = werte["select"][0]
        for nav in NAV:
            for m in werte.get(nav, []):
                if m["rms"] > sel["rms"] - NAV_ABSTAND_DB:
                    fail("%s/%s: RMS %.1f nicht %.0f dB unter select (%.1f)" % (SATZ, nav, m["rms"], NAV_ABSTAND_DB, sel["rms"]))
        lauteste = max(m["rms"] for ms_ in werte.values() for m in ms_)
        if "power_off" in werte and werte["power_off"][0]["rms"] >= lauteste:
            fail("%s/power_off: Ausschalten ist der lauteste Klang" % SATZ)
    for name, ms, pegel, _ in EINR_TABELLE:
        pfad = os.path.join(EINR_ORDNER, name + ".wav")
        d = "%s/%s.wav" % (EINR, name)
        if not os.path.isfile(pfad):
            fail(d + " fehlt")
            continue
        l, r, fr, ch = k3.lies(pfad)
        m = k4.analyse(l, r)
        pr = gemeinsam(name, m, fr, ch, ms, REF_DB + pegel)
        pr.append((m["schwerpunkt"] < KERN_SCHWERPUNKT, "Schwerpunkt %.0f Hz < %.0f" % (m["schwerpunkt"], KERN_SCHWERPUNKT)))
        for ok, was in pr:
            if not ok:
                fail("%s: %s" % (d, was))
    print("Ergebnis: %s" % ("alles ok" if fehler == 0 else "%d Fehler" % fehler))
    return 1 if fehler else 0


# --- Hörprobe --------------------------------------------------------------------------------------

def hoerprobe(ziel):
    """Jede Datei einzeln (Dateiname = Ereignis, Fassungen mit _v2 …), um HOERPROBE_DB angehoben (so laut wie
    die Vorlage in der Hörprobe), und hoerprobe.md mit Messwerten der angehobenen Dateien."""
    os.makedirs(ziel, exist_ok=True)
    md = ["# Handpan – Hörprobe", "", "Jede Datei wie in Uzai (44,1 kHz, Stereo), zum Abhören um %+.0f dB angehoben (so laut wie die Vorlage). "
          "Pegel als Kurzzeit-RMS (50 ms)." % HOERPROBE_DB, "",
          "| Datei | Länge | RMS | Spitze | Schwerpunkt | Abklingen −10 / −20 / −30 dB | Ereignis |", "|---|---|---|---|---|---|---|"]
    quellen = [(os.path.join(ORDNER, datei(n, v)), datei(n, v), txt) for n, ms, _, fass, txt in TABELLE for v in range(fass)]
    quellen += [(os.path.join(EINR_ORDNER, n + ".wav"), n + ".wav", txt) for n, _, _, txt in EINR_TABELLE]
    for pfad, name, txt in quellen:
        g = amp(HOERPROBE_DB)
        l, r = ([v * g for v in x] for x in k3.lies(pfad)[:2])
        k3.schreibe(os.path.join(ziel, name), l, r)
        m = k3.messen(l, r)
        z = abklingen(l)
        sw = k4.analyse(l, r)["schwerpunkt"]
        md.append("| %s | %.2f s | %.1f dBFS | %.1f dBFS | %.0f Hz | %s s | %s |" % (name, m["ms"] / 1000.0, m["rms"], m["spitze"], sw,
                                                                            " / ".join("%.2f" % a for a in z), txt))
    with open(os.path.join(ziel, "hoerprobe.md"), "w", encoding="utf-8") as f:
        f.write(re.sub(r"(\d)\.(\d)", r"\1,\2", "\n".join(md)) + "\n")
    print("Hörprobe:", ziel, "(%d Dateien)" % len(quellen))


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--pruefen" in a:
        sys.exit(pruefen())
    if "--hoerprobe" in a:
        hoerprobe(a[a.index("--hoerprobe") + 1])
        sys.exit(0)
    if "--einrichtung" in a:
        rendern(False, True)
        sys.exit(0)
    rendern()
