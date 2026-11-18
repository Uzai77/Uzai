#!/usr/bin/env python3
# Vier weiche Klangsätze: „Samt“ (Standard in 0.16), „Kiesel“, „Pad“ und „Haptik“ – das Gegenteil von
# penetrant: warm, leise, dunkel, auch nach tausend Drücken angenehm, trotzdem präzise. Standard ist heute
# „Handpan“ (tools/synth_klang5.py), das auch die Klänge der Einrichtung (assets/sounds/einrichtung) rendert.
# Nur Python-Standardbibliothek (wave, struct, math, random mit festem Startwert): gleiche Quelle,
# gleiche Dateien. Keine Aufnahmen, keine fremden Samples. Bausteine aus tools/synth_klang3.py.
#
#   python3 tools/synth_klang4.py [satz …]         rendert assets/sounds/<satz>/*.wav (alle vier oder die genannten),
#                                                  druckt Messwerte und ergänzt assets/sounds/KLANG-QUELLE.txt (SHA-256)
#   python3 tools/synth_klang4.py --pruefen        prüft alle Dateien gegen Tabelle und Ziele (Rückgabe 1 bei Abweichung)
#   python3 tools/synth_klang4.py --messen         Messtabelle der Kernklänge aller Sätze samt „Perle“
#   python3 tools/synth_klang4.py --hoerprobe ordner
#                                                  klang4_<satz>.wav je Satz (und „perle“), klang4_vergleich.wav, klang4_hoerprobe.md
#
# Danach einmal: godot --headless --path . --import
#
# Warum: „Perle“ setzt jeden Druck mit einem Rauschimpuls bei 1,8–4,5 kHz (0,25 ms Anstieg) und einem
# gläsernen Kern bei E6/H6 an – präzise, aber auf Dauer stechend. Hier gilt für alle vier Sätze:
#   - Bewegen und Raste: Schwerpunkt unter 1,5 kHz, unter 5 % der Energie über 6 kHz, Anstieg ab 2 ms
#     (kein Knacken), Spitze höchstens −12 dBFS, mindestens 6 dB leiser als Bestätigen;
#   - Bestätigen und Zurück: Schwerpunkt unter 2,2 kHz; nirgends Glas oder Metall über 5 kHz;
#   - die Energie liegt zwischen 200 Hz und 3 kHz (Fernsehlautsprecher), alles leiser als „Perle“.
# Kein Anschlag ist ein Impuls: jeder Ton schwillt in 3–6 ms an (halber Kosinus), Körper sind Rauschen
# unter einem Hann-Fenster von 4–8 ms durch einen Bandpass – weich wie ein Finger, ein Filz, ein Stoff.
# Töne aus E-Dur pentatonisch (E Fis Gis H Cis) wie „Perle“, eine Oktave tiefer.
#
# Die vier Richtungen:
#   samt    gedämpfte, runde Holz- und Filzanschläge (Finger auf weichem Holz): Holzstab-Teiltöne, die
#           oberen klingen sehr schnell ab, darunter ein Filzpolster um 300–500 Hz. Tiefe Mitten, kein Glas.
#   kiesel  ein glatter Stein auf Stoff: kleine, kurze, trockene Klicks um 0,9–1,2 kHz mit zwei
#           unharmonischen Teiltönen, ganz dezent tonal, fast ohne Raum. Minimal.
#   pad     sanfte Sinus-/FM-Zupfer mit Tiefpass, luftig, aber dunkel und kurz; Bewegen ist ein leiser
#           Luftzug mit einem Hauch Ton. Etwas mehr (dunkler) Raum.
#   haptik  fast nur Körper und Druck: sehr kurze, tiefe „Taps“ (wie eine Taptic Engine, um 230–300 Hz,
#           leicht gesättigt, damit Fernseher sie tragen), kaum Tonhöhe; nur Bestätigen, Öffnen, Spielen,
#           Erfolge und Start haben einen kleinen, warmen Akkord.
# Bewegen, Raste, Bestätigen, Zurück, Schalter, Rand und Reiter gibt es in 2–4 Fassungen (<name>.wav,
# <name>_v2.wav …): Sfx wählt zufällig, nie zweimal dieselbe hintereinander (Klang.variante).
import math, os, random, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth_klang3 as k3  # noqa: E402  (Bausteine: Filter, Raum, Fläche, Luft, Mischpult, Dateien)

SR = k3.SR
ns, amp, db, peak, add, biquad, note, CENT = k3.ns, k3.amp, k3.db, k3.peak, k3.add, k3.biquad, k3.note, k3.CENT
anstieg, tau_bis, rauschen = k3.anstieg, k3.tau_bis, k3.rauschen
VORLAUF_MS = k3.VORLAUF_MS
SOUNDS = k3.SOUNDS
QUELLE = k3.QUELLE
MARKE = "Klangsätze aus tools/synth_klang4.py"
MARKE5 = "Klangsatz „Handpan“ aus tools/synth_klang5.py"
PERLE = "perle"

# Satz: Kennung → (Name, Pegel von „select“ als Kurzzeit-RMS in dBFS, Beschreibung). „Perle“ liegt bei −29,5;
# die vier sind dunkler (weniger Energie, wo das Ohr am empfindlichsten ist) und trotzdem 2–3 dB tiefer.
SAETZE = {
    "samt": ("Samt", -32.0, "gedämpfte, runde Holz- und Filzanschläge, tiefe Mitten, kein Glas (Standard in 0.16)"),
    "kiesel": ("Kiesel", -32.5, "kleine, kurze, trockene Klicks wie ein glatter Stein auf Stoff, ganz dezent tonal"),
    "pad": ("Pad", -32.5, "sanfte Sinus-/FM-Zupfer mit Tiefpass, Bewegen als leiser Luftzug"),
    "haptik": ("Haptik", -31.0, "kurze, tiefe Taps fast ohne Tonhöhe, nur Bestätigen und Erfolge mit kleinem warmem Akkord"),
}
STD = "samt"

# Die Tabelle (für alle vier gleich): Länge ms, Pegel dB (Kurzzeit-RMS zu „select“), Bewegung ms (wie
# Klang.PALETTE in src/core/klang.gd: Klang ≤ Bewegung + 60 ms), Fassungen, Ereignis.
NACHKLANG_MS = 60
BOOT_MAX_MS = 2000
TABELLE = [
    # name              ms   pegel  bewg.  fass.  Ereignis
    ("move",            65,  -13.0,   90,   4, "Fokus"),
    ("tick",            50,  -14.0,   90,   3, "Regler, Raste, Lautstärke"),
    ("bump",           140,   -8.0,  200,   2, "Grenze erreicht"),
    ("select",         130,    0.0,   90,   3, "Bestätigen: Drücken und Setzen"),
    ("back",           170,   -2.0,  160,   2, "Zurück: abwärts, weicher"),
    ("open",           340,    0.0,  360,   1, "Ebene oder Seite auf (ersetzt select)"),
    ("toggle_on",      120,   -4.0,   90,   2, "Schalter an"),
    ("toggle_off",     110,   -5.0,   90,   2, "Schalter aus"),
    ("tab",            200,   -5.0,  200,   2, "Bereich, Unterbereich, App"),
    ("guide",          260,    0.0,  200,   1, "Guide auf (Signatur)"),
    ("guide_close",    210,   -2.5,  160,   1, "Guide zu"),
    ("error",          250,   -1.0,  200,   1, "Fehler"),
    ("notify",         260,   -1.0,  200,   1, "Mitteilung"),
    ("launch",         420,    1.0,  360,   1, "Spielen"),
    ("boot",          1950,    2.0, 2400,   1, "Start-Signatur: Punkt 0,30 s, U 0,62 s, Name 1,08 s"),
    ("power_off",     1350,   -0.5, 1400,   1, "Ausschalten (Zeichen fällt ab 0,62 s)"),
    ("shutter",        170,   -4.0,  160,   1, "Bildschirmfoto"),
    ("achievement",   1050,    2.0, 1000,   1, "Erfolg"),
    ("unlock",         950,    2.0, 1000,   1, "Abzeichen"),
    ("unlock_rare",   1250,    2.0, 1200,   1, "seltenes Abzeichen"),
    ("unlock_retro",   850,    1.0, 1000,   1, "Erfolg im Retro-Spiel"),
    ("setup_step",     200,   -2.0,  200,   1, "Einrichtung: Schritt weiter (aufsteigend: Klang.stufe_ton)"),
    ("setup_found",    420,   -3.0,  400,   1, "Einrichtung: etwas gefunden, kommt näher"),
    ("setup_done",    1200,    2.0, 1200,   1, "Einrichtung: fertig (kurzer Akkord)"),
    ("swell",         1500,    0.0, 1500,   1, "Licht geht an (Anschwellen)"),
]
PEGEL_TOL_DB = 1.0
NAV = ("move", "tick")

# Die Klänge der Einrichtung (assets/sounds/einrichtung) rendert seit „Handpan“ tools/synth_klang5.py.

# Ziele (für alle vier Sätze geprüft, --pruefen).
NAV_SCHWERPUNKT = 1500.0      # Hz
NAV_UEBER_6K = 0.05           # Anteil der Energie
NAV_ANSTIEG_MS = 2.0          # 10 → 90 % der Hüllkurve
NAV_SPITZE_DB = -12.0         # dBFS
NAV_ABSTAND_DB = 6.0          # Kurzzeit-RMS mindestens so viel unter „select“
KERN_SCHWERPUNKT = 2200.0     # select, back
UEBER_5K_MAX = 0.03           # Anteil der Energie über 5 kHz, jeder Klang
TV_MIN = 0.70                 # Anteil zwischen 200 Hz und 3 kHz (Fernsehlautsprecher), Kernklänge
TV_MIN_ALLE = 0.55            # … alle anderen (Flächen reichen tiefer)
SPITZE_MAX_DB = -6.0
ENDE_MAX_DB = (-26.0, -36.0)
KORR_MIN = 0.55
KERN = ("move", "tick", "select", "back", "toggle_on", "tab", "bump")


def datei(name, k):
    return k3.datei(name, k)


# --- Bausteine -----------------------------------------------------------------------------------

def modal(f, ms, moden, att_ms=4.0, cent=0.0, bend=0.0, bend_ms=4.0, fm=None):
    """Modaler Anschlag: moden [(Verhältnis, Amplitude, τ in s)], jeder Teilton mit eigenem Abklingen,
    alle schwellen in att_ms an (halber Kosinus, kein Impuls), erst danach klingen sie ab. Teiltöne über 5 kHz entfallen.
    bend: kleiner Tonhöhenfall (Anteil, fällt mit bend_ms). fm: (Verhältnis, Index, Index-τ ms) auf den Grundton."""
    n = ns(ms)
    out = [0.0] * n
    f *= CENT ** cent
    k = 2.0 * math.pi / SR
    na = max(1, ns(att_ms))
    dbb = math.exp(-1.0 / max(1.0, bend_ms * SR / 1000.0))
    for j, (r, a, tau) in enumerate(moden):
        fr = f * r
        if fr > 5000.0 or a <= 0.0:
            continue
        d = math.exp(-1.0 / (tau * SR))
        e, ph, phm, bb = 1.0, 0.0, 0.0, bend
        ratio = 0.0
        if fm and j == 0:
            ratio, ii, itau = fm
            di = math.exp(-1.0 / (itau * SR / 1000.0))
        for i in range(n):
            inc = k * fr * (1.0 + bb)
            bb *= dbb
            ph += inc
            if ratio:
                phm += inc * ratio
                v = math.sin(ph + ii * math.sin(phm))
                ii *= di
            else:
                v = math.sin(ph)
            out[i] += a * anstieg(i, na) * e * v
            if i >= na:
                e *= d
                if e < 1e-5:
                    break
    return out


def polster(rng, fc, kontakt_ms, q=0.9, lp=None, abkl_ms=None):
    """Weicher Körper: Rauschen zweimal durch einen Bandpass um fc (wahlweise Tiefpass), danach unter eine
    Hülle gelegt – Anstieg halbes Hann-Fenster über kontakt_ms / 2, dann exponentiell weg (abkl_ms).
    Erst filtern, dann formen: so bestimmt die Hülle den Anstieg, nicht der Zufall. Kein Impuls. Spitze 1."""
    abkl = abkl_ms if abkl_ms is not None else kontakt_ms * 0.5
    nk = max(2, ns(kontakt_ms) // 2)
    n = nk + ns(abkl * 7.0 + 2.0)
    vor = ns(20.0)
    x = biquad(biquad(rauschen(rng, n + vor), "bp", fc, q), "bp", fc, q)
    if lp:
        x = biquad(x, "lp", lp)
    x = x[vor:]
    d = math.exp(-1.0 / (abkl * SR / 1000.0))
    e = 1.0
    for i in range(n):
        if i < nk:
            g = 0.5 - 0.5 * math.cos(math.pi * i / nk)
        else:
            g = e
            e *= d
        x[i] *= g
    return k3.norm(x)


def tap(f, tau_ms, fall=1.35, fall_ms=3.0, att_ms=2.6):
    """Haptischer Tap: Sinus, der in fall_ms von f × fall auf f fällt, Anstieg att_ms (halber Kosinus). Spitze 1."""
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
        if i >= na:
            e *= d
    return k3.norm(out)


def saettigen(x, drive):
    p = peak(x) or 1.0
    t = math.tanh(drive)
    return [math.tanh(drive * v / p) / t * p for v in x]


# Holzstab mit Filzschlägel (Samt): Grundton, ein Hauch Oktave (Resonanzkörper), der gestimmte zweite
# Teilton eines Marimbastabs (3,93) – leise und sehr schnell weg, dazu ein unharmonischer Holz-Teilton.
def moden_holz(tau, hell=1.0):
    return [(1.0, 1.0, tau), (2.0, 0.07 * hell, tau * 0.45), (3.93, 0.10 * hell, tau * 0.16), (2.71, 0.05 * hell, tau * 0.22)]


# Glatter Stein (Kiesel): fast nur ein kurzer Grundton, zwei unharmonische Teiltöne, alles schnell gedämpft (Stoff).
def moden_stein(tau, hell=1.0):
    return [(1.0, 1.0, tau), (1.59, 0.32 * hell, tau * 0.5), (2.37, 0.12 * hell, tau * 0.3)]


class Satz:
    """Ein Klangsatz: die Bausteine, aus denen alle Ereignisse gebaut sind. Unterklassen setzen den Charakter."""
    kennung = ""
    raum_rt, raum_nass, raum_hell = 0.12, -22.0, 2600.0
    tiefpass = 3000.0
    luft_lp = 2200.0

    def __init__(self, k):
        self.k = k

    # Der tonale Anschlag des Satzes.
    def schlag(self, f, at, g, tau, hell=1.0, cent=0.0, pan=0.0):
        raise NotImplementedError

    # Der Druck ohne Ton (Finger, Filz, Stoff, Tap).
    def druck(self, at, g, fc=380.0, kontakt=10.0, pan=0.0):
        self.k.mono(polster(self.k.rng, fc, kontakt, 0.9, lp=1400.0), at, g, pan)

    def luft(self, at, ms, f0, f1, g, q=1.2, auf=0.4):
        k = self.k
        l = biquad(k3.hauch(k.rng, ms, f0, f1, q, auf), "lp", self.luft_lp)
        r = biquad(k3.hauch(k.rng, ms, f0, f1, q, auf), "lp", self.luft_lp)
        k.stereo(l, r, at, g)

    def flaeche(self, freqs, at, ms, g, auf_ms, ab_ms, hell0=0.8, hell1=1.6, **kw):
        l, r = k3.flaeche(self.k.rng, freqs, ms, auf_ms, ab_ms, hell0=hell0, hell1=hell1, **kw)
        self.k.stereo(biquad(l, "lp", 2000.0), biquad(r, "lp", 2000.0), at, g)

    # Bestätigen: Drücken und Setzen.
    def select(self, at, g, f, tau, cent=0.0, latch=9.0):
        self.druck(at, g - 6.0)
        self.schlag(f, at + latch, g, tau, cent=cent)
        self.schlag(f / 2.0, at + latch, g - 9.0, tau * 0.5, hell=0.5, cent=cent)

    # Kleiner Akkord (nur „Haptik“ setzt ihn anders, die anderen zupfen ihn).
    def akkord(self, freqs, at, g, tau, schritt=14.0):
        for i, f in enumerate(freqs):
            self.schlag(f, at + schritt * i, g - 1.5 * i, tau, pan=-0.12 + 0.24 * i / max(1, len(freqs) - 1))

    def fertig_filter(self):
        self.k.filter("lp", self.tiefpass)

    def raum(self, mal=1.0, nass=0.0):
        self.k.raum(self.raum_rt * mal, self.raum_nass + nass, 2.5, self.raum_hell)

    def move(self, v, ms):
        raise NotImplementedError

    def tick(self, v, ms):
        raise NotImplementedError


class Samt(Satz):
    kennung = "samt"
    raum_rt, raum_nass, raum_hell = 0.14, -21.0, 2400.0
    tiefpass = 2800.0

    att = 5.5

    def schlag(self, f, at, g, tau, hell=1.0, cent=0.0, pan=0.0, att=None):
        k = self.k
        att = self.att if att is None else att
        for c, gl, gr in ((-0.8, 1.0, 0.0), (0.8, 0.0, 1.0)):
            x = modal(f, k_rest(k, at), moden_holz(tau, hell), att_ms=att, cent=cent + c)
            a = (pan + 1.0) * math.pi / 4.0
            k.stereo([v * math.cos(a) * math.sqrt(2.0) * gl for v in x], [v * math.sin(a) * math.sqrt(2.0) * gr for v in x], at, g)
        # Filz: ein kurzes Polster unter dem Ton (Kontakt 6 ms, um den Grundton herum, dunkel)
        k.mono(polster(k.rng, max(260.0, min(f * 0.9, 700.0)), 9.0, 0.8, lp=1500.0), at, g - 11.0, pan)

    def move(self, v, ms):
        # Finger auf weichem Holz: H4, rund, sehr kurz; Fassungen: ein paar Cent, mehr oder weniger Holz.
        cent = (0.0, 14.0, -16.0, 26.0)[v]
        hell = (1.0, 0.8, 1.15, 0.9)[v]
        self.schlag(note("B4"), 0, 0.0, tau_bis(ms - 8, 40.0), hell=hell, cent=cent, att=4.5)
        self.druck(0, -9.0, fc=(360.0, 400.0, 330.0, 380.0)[v], kontakt=10.0)
        self.k.filter("lp", 2200.0)
        self.raum(0.7, -3.0)

    def tick(self, v, ms):
        # Raste: kürzer, eine Quinte höher (Fis5), weniger Körper.
        cent = (0.0, 18.0, -14.0)[v]
        self.schlag(note("F#5"), 0, 0.0, tau_bis(ms - 6, 42.0), hell=0.7, cent=cent, att=4.4)
        self.druck(0, -12.0, fc=520.0, kontakt=8.0)
        self.k.filter("lp", 2400.0)
        self.raum(0.5, -4.0)


class Kiesel(Satz):
    kennung = "kiesel"
    raum_rt, raum_nass, raum_hell = 0.07, -26.0, 2600.0
    tiefpass = 3000.0

    def schlag(self, f, at, g, tau, hell=1.0, cent=0.0, pan=0.0, att=4.2):
        k = self.k
        # Stein: tiefer als der Ton, kurz; der Ton selbst nur als leiser, sauberer Kern darüber.
        x = modal(f, k_rest(k, at), moden_stein(min(tau, 0.02), hell), att_ms=att, cent=cent)
        k.mono(x, at, g - 1.0, pan)
        k.mono(modal(f, k_rest(k, at), [(1.0, 1.0, tau)], att_ms=att + 1.0, cent=cent + 3.0), at, g - 9.0, pan)
        k.mono(polster(k.rng, 900.0, 7.0, 1.0, lp=1800.0), at, g - 12.0, pan)

    def druck(self, at, g, fc=800.0, kontakt=7.0, pan=0.0):
        self.k.mono(polster(self.k.rng, fc, kontakt, 1.0, lp=1800.0), at, g, pan)

    def select(self, at, g, f, tau, cent=0.0, latch=10.0):
        # Stein setzt auf (leise, höher) und liegt (voller, tiefer): klick – klack.
        self.schlag(f * 1.5, at, g - 7.0, 0.012, cent=cent)
        self.schlag(f, at + latch, g, tau, cent=cent)
        self.druck(at + latch, g - 10.0, fc=600.0, kontakt=9.0)

    def move(self, v, ms):
        cent = (0.0, 20.0, -18.0, 35.0)[v]
        f = (1000.0, 1060.0, 950.0, 1020.0)[v]
        k = self.k
        k.mono(modal(f, ms - 2, moden_stein(0.0065, (1.0, 0.8, 1.1, 0.9)[v]), att_ms=4.4, cent=cent), 0, 0.0)
        k.mono(polster(k.rng, 700.0, 7.0, 1.0, lp=1600.0), 0, -10.0)
        k.filter("lp", 2600.0)
        self.raum(0.8, -2.0)

    def tick(self, v, ms):
        cent = (0.0, 22.0, -15.0)[v]
        k = self.k
        k.mono(modal(1180.0, ms - 2, moden_stein(0.0045, 0.7), att_ms=5.0, cent=cent), 0, 0.0)
        k.mono(polster(k.rng, 900.0, 6.5, 1.0, lp=1700.0), 0, -12.0)
        k.filter("lp", 2600.0)


class Pad(Satz):
    kennung = "pad"
    raum_rt, raum_nass, raum_hell = 0.26, -17.0, 2200.0
    tiefpass = 2400.0
    luft_lp = 1800.0

    def schlag(self, f, at, g, tau, hell=1.0, cent=0.0, pan=0.0, att=5.0):
        k = self.k
        # FM-Zupfer: Modulator 1:1, Index fällt in 14 ms (weich hell im Anschlag, dann reiner Sinus),
        # links und rechts ±3 Cent (breit wie eine Fläche), eine Spur Oktave tiefer darunter.
        rest = k_rest(k, at)
        for c, gl, gr in ((-3.0, 1.0, 0.25), (3.0, 0.25, 1.0)):
            x = modal(f, rest, [(1.0, 1.0, tau), (2.0, 0.05 * hell, tau * 0.4)], att_ms=att, cent=cent + c, fm=(1.0, 0.9 * hell, 14.0))
            k.stereo([v * gl for v in x], [v * gr for v in x], at, g - 1.0, )
        k.mono(modal(f / 2.0, rest, [(1.0, 1.0, tau * 0.6)], att_ms=att + 2.0, cent=cent), at, g - 12.0, pan)

    def druck(self, at, g, fc=600.0, kontakt=8.0, pan=0.0):
        # ein kleiner Luftstoß statt eines Körpers
        self.k.mono(polster(self.k.rng, fc, kontakt, 0.7, lp=1500.0, abkl_ms=8.0), at, g, pan)

    def select(self, at, g, f, tau, cent=0.0, latch=0.0):
        self.druck(at, g - 9.0, fc=700.0, kontakt=8.0)
        self.schlag(f, at, g, tau, cent=cent)
        self.schlag(f * 1.5, at + 12.0, g - 10.0, tau * 0.6, cent=cent, hell=0.5)

    def move(self, v, ms):
        # Ein leiser Luftzug (Bandpass wandert 500 → 1000 Hz) mit einem Hauch Ton (H4, sehr weich).
        k = self.k
        f0, f1 = ((520.0, 980.0), (600.0, 1050.0), (480.0, 900.0), (560.0, 1000.0))[v]
        x = k3.hauch(k.rng, ms - 26, f0, f1, 1.6, 0.3)
        k.mono(biquad(x, "lp", 1600.0), 0, 0.0)
        cent = (0.0, 12.0, -10.0, 20.0)[v]
        k.mono(modal(note("B4"), ms - 4, [(1.0, 1.0, 0.012)], att_ms=5.0, cent=cent, fm=(1.0, 0.6, 6.0)), 0, -4.0)
        self.raum(0.6, -2.0)

    def tick(self, v, ms):
        k = self.k
        cent = (0.0, 15.0, -12.0)[v]
        k.mono(modal(note("E5"), ms - 3, [(1.0, 1.0, 0.008)], att_ms=5.0, cent=cent, fm=(1.0, 0.8, 5.0)), 0, 0.0)
        k.mono(polster(k.rng, 800.0, 8.0, 0.8, lp=1500.0), 0, -10.0)
        k.filter("lp", 2200.0)


class Haptik(Satz):
    kennung = "haptik"
    raum_rt, raum_nass, raum_hell = 0.08, -26.0, 2000.0
    tiefpass = 2400.0

    def tap(self, f, at, g, tau_ms, fall=1.35, pan=0.0, att=4.2):
        """Tap mit leichter Sättigung (Obertöne bei 2f, 3f tragen ihn auf dem Fernseher) und einem
        kurzen Polster eine Oktave höher (der Druck)."""
        k = self.k
        x = saettigen(tap(f, tau_ms, fall, 3.0, att), 1.8)
        k.mono(x, at, g, pan)
        k.mono(polster(k.rng, f * 2.2, 8.0, 0.9, lp=1400.0), at, g - 11.0, pan)

    def schlag(self, f, at, g, tau, hell=1.0, cent=0.0, pan=0.0):
        # Kaum Tonhöhe: ein Tap zwischen 210 und 340 Hz (folgt dem Ton nur grob), darüber leise der Ton.
        ft = max(210.0, min(340.0, 140.0 + f * 0.25))
        self.tap(ft * CENT ** cent, at, g, 9.0 + 6.0 * hell, pan=pan)
        self.k.mono(modal(f, k_rest(self.k, at), [(1.0, 1.0, min(tau, 0.06))], att_ms=5.0, cent=cent), at, g - 14.0, pan)

    def druck(self, at, g, fc=240.0, kontakt=9.0, pan=0.0):
        self.tap(fc, at, g, 7.0, pan=pan)

    def akkord(self, freqs, at, g, tau, schritt=10.0):
        # Klein und warm: weiche Sinustöne (Anstieg 8 ms) mit einem Hauch FM, kaum gestaffelt.
        k = self.k
        rest = k_rest(k, at)
        for i, f in enumerate(freqs):
            x = modal(f, rest - schritt * i, [(1.0, 1.0, tau), (2.0, 0.04, tau * 0.4)], att_ms=8.0, fm=(1.0, 0.5, 12.0), cent=(-2.0, 2.0, 0.0, 1.0)[i % 4])
            k.mono(x, at + schritt * i, g - 1.5 * i, -0.12 + 0.24 * i / max(1, len(freqs) - 1))

    def select(self, at, g, f, tau, cent=0.0, latch=28.0):
        # Drücken (tiefer Tap) und Loslassen (kürzer, etwas höher), dazu ein kleiner warmer Akkord.
        self.tap(225.0 * CENT ** cent, at, g, 10.0)
        self.tap(290.0 * CENT ** cent, at + latch, g - 5.0, 7.0)
        self.akkord([f / 2.0, f / 2.0 * 1.26, f / 2.0 * 1.5], at + 4.0, g - 11.0, tau * 0.8)

    def move(self, v, ms):
        cent = (0.0, 25.0, -20.0, 40.0)[v]
        self.tap(235.0 * CENT ** cent, 0, 0.0, (8.0, 7.0, 8.5, 7.5)[v], fall=(1.35, 1.3, 1.4, 1.32)[v])
        self.k.filter("lp", 1800.0)

    def tick(self, v, ms):
        cent = (0.0, 20.0, -18.0)[v]
        self.tap(300.0 * CENT ** cent, 0, 0.0, 5.0, fall=1.25, att=4.4)
        self.k.filter("lp", 1800.0)


SAETZE_KLASSEN = {"samt": Samt, "kiesel": Kiesel, "pad": Pad, "haptik": Haptik}


def k_rest(k, at):
    """Restlänge des Klangs ab at (ms)."""
    return max(1.0, (k.n - ns(at + VORLAUF_MS)) * 1000.0 / SR)


# --- Die Klänge ----------------------------------------------------------------------------------

def baue(satz, name, ms, v):
    k = k3.Klang(ms, "uzai-klang4-%s-%s-%d" % (satz, name, v))
    S = SAETZE_KLASSEN[satz](k)
    rng = k.rng
    rest = lambda at: ms - VORLAUF_MS - at
    # bis hierher klingt ein Ton um tief_db ab: 25 ms vor dem Ende (dort blendet fertig() aus)
    ende = lambda at: max(5.0, rest(at) - 25.0)
    haptik = satz == "haptik"
    E4, Gis4, H4, E5, Gis5, H5, Cis5, E3, H3 = (note(x) for x in ("E4", "G#4", "B4", "E5", "G#5", "B5", "C#5", "E3", "B3"))
    if name == "move":
        S.move(v, ms)
    elif name == "tick":
        S.tick(v, ms)
    elif name == "bump":
        # Rand: ein weicher, tiefer Anschlag, der nachgibt (Tonhöhe fällt), Druck darunter.
        cent = (0.0, -30.0)[v]
        S.druck(0, -2.0, fc=300.0, kontakt=9.0)
        S.schlag(E4, 1.0, -2.0, tau_bis(ende(1), 40.0), hell=0.5, cent=cent)
        k.filter("lp", 1800.0)
        S.raum(0.7)
    elif name == "select":
        cent = (0.0, 12.0, -10.0)[v]
        S.select(0, 0.0, E5, tau_bis(ende(10), 38.0), cent=cent, latch=(9.0, 8.0, 11.0)[v] if not haptik else (28.0, 24.0, 32.0)[v])
        S.fertig_filter()
        S.raum()
    elif name == "back":
        # Abwärts und weicher: H4 → E4, langsamer Anstieg, dunkler.
        t2 = (32.0, 38.0)[v]
        cent = (0.0, -14.0)[v]
        S.schlag(H4, 0.5, -4.0, 0.03, hell=0.6, cent=cent, pan=0.08)
        S.schlag(E4, t2, 0.0, tau_bis(ende(t2), 40.0), hell=0.8, cent=cent, pan=-0.05)
        S.druck(t2, -10.0, fc=320.0, kontakt=9.0)
        k.filter("lp", 2200.0)
        S.raum()
    elif name == "open":
        # Bestätigen, dann öffnet sich Luft nach oben (passt zur Animation), dazu H4 und E5 als Akzent.
        S.select(0, 0.0, E5, 0.07, latch=9.0 if not haptik else 26.0)
        S.luft(0, 320, 350.0, 1500.0, -11.0, q=1.4, auf=0.35)
        if haptik:
            S.akkord([E4, Gis4, H4, E5], 40, -8.0, tau_bis(ende(40), 40.0), schritt=16.0)
        else:
            S.schlag(H5 / 2.0 * 2.0, 36, -6.0, tau_bis(ende(36), 40.0), pan=0.1)
            S.schlag(E5 * 1.0, 66, -9.0, tau_bis(ende(66), 40.0), pan=0.16)
        S.fertig_filter()
        S.raum(1.6, 2.0)
    elif name in ("toggle_on", "toggle_off"):
        an = name == "toggle_on"
        cent = (0.0, 15.0 if an else -15.0)[v]
        t2 = (26.0, 22.0)[v]
        f1, f2 = (H4, E5) if an else (E5, H4)
        S.schlag(f1, 0.3, -5.0, 0.014, hell=0.7, cent=cent, pan=-0.08 if an else 0.08)
        S.schlag(f2, t2, 0.0, tau_bis(ende(t2), 38.0), hell=1.0 if an else 0.6, cent=cent, pan=0.08 if an else -0.08)
        S.druck(t2, -10.0)
        k.filter("lp", 2600.0 if an else 2000.0)
        S.raum(0.8)
    elif name == "tab":
        # Seitwärts: ein kurzer Luftzug (je Fassung auf- oder abwärts), darauf ein runder Ton.
        f = (Cis5, H4)[v]
        S.luft(0, 190, 450.0 if v == 0 else 1100.0, 1100.0 if v == 0 else 450.0, -8.0, q=1.1, auf=0.3)
        S.schlag(f, 10, 0.0, tau_bis(ende(10), 38.0))
        S.fertig_filter()
        S.raum(1.3)
    elif name == "guide":
        # Signatur: Luft steigt, darauf ein Arpeggio E4 Gis4 H4 E5 von links nach rechts.
        S.luft(0, 245, 300.0, 1400.0, -9.0, q=1.3, auf=0.45)
        S.druck(0, -6.0, fc=300.0, kontakt=9.0)
        for i, (f, t, g) in enumerate(((E4, 0, 0.0), (Gis4, 22, -1.5), (H4, 44, -2.5), (E5, 66, -4.0))):
            S.schlag(f, t + 0.5, g, tau_bis(ende(t), 46.0), pan=-0.15 + 0.1 * i)
        S.fertig_filter()
        S.raum(1.8, 2.0)
    elif name == "guide_close":
        S.luft(0, 195, 1400.0, 320.0, -10.0, q=1.2, auf=0.22)
        for i, (f, t, g) in enumerate(((E5, 0, -5.0), (H4, 24, -2.0), (E4, 48, 0.0))):
            S.schlag(f, t + 0.5, g, tau_bis(ende(t), 46.0), hell=0.7, pan=0.12 - 0.12 * i)
        k.filter("lp", 2200.0)
        S.raum(1.5, 1.0)
    elif name == "error":
        # Freundlich „nein“: zwei weiche Töne abwärts (Gis4 → E4), eine Spur verstimmt (schwebt), dunkel.
        for t, f, g in ((0, Gis4, 0.0), (110, E4, -1.0)):
            S.druck(t, -8.0, fc=280.0, kontakt=9.0)
            S.schlag(f, t + 0.5, g, tau_bis(ende(t), 46.0) if t else 0.04, hell=0.6)
            S.schlag(f * CENT ** 22.0, t + 0.5, g - 8.0, 0.035, hell=0.4)
        k.filter("lp", 2000.0)
        S.raum(1.2)
    elif name == "notify":
        # Mitteilung: H4, dann E5 – eine freundliche Quarte aufwärts.
        S.schlag(H4, 0.5, 0.0, 0.05, pan=-0.1)
        S.schlag(E5, 95.5, -0.5, tau_bis(ende(95), 42.0), pan=0.1)
        S.druck(95, -12.0)
        S.fertig_filter()
        S.raum(1.4, 1.0)
    elif name == "launch":
        # Spielen: Bestätigen, dann zieht alles nach oben (Gis4 … Gis5), Luft steigt, eine dunkle Fläche schwillt.
        S.select(0, 0.0, E5, 0.06, latch=9.0 if not haptik else 26.0)
        if haptik:
            S.akkord([E4, Gis4, H4, E5, Gis5], 40, -6.0, tau_bis(ende(40), 40.0), schritt=26.0)
        else:
            for i, (f, t, g) in enumerate(((Gis4, 36, -2.0), (H4, 72, -3.0), (E5, 108, -4.0), (Gis5, 144, -8.0))):
                S.schlag(f, t, g, tau_bis(ende(t), 40.0), pan=-0.1 + 0.08 * i)
        S.luft(0, 380, 300.0, 1600.0, -10.0, q=1.2, auf=0.55)
        S.flaeche([E3, H3], 0, 400, -14.0, 140, 230, hell0=0.9, hell1=1.8)
        S.fertig_filter()
        S.raum(2.4, 2.0)
    elif name == "boot":
        # Start: eine dunkle Fläche öffnet sich bis zum Punkt (0,30 s); Punkt: tiefes E (E3 + E4); U (0,62 s):
        # H4; Name (1,08 s): E-Dur gezupft (E4 Gis4 H4 E5), darüber leise Luft. Verklingt vor 1,95 s.
        S.flaeche([E3, H3, E4], 0, 1500, -9.0, 320, 700, hell0=0.7, hell1=1.6)
        S.druck(300, -4.0, fc=260.0, kontakt=8.0)
        S.schlag(E4, 301, 0.0, 0.14, pan=-0.06)
        S.schlag(E3 if not haptik else E4, 301, -6.0, 0.12, hell=0.5)
        S.schlag(H4, 620.5, -4.0, 0.12, pan=0.1)
        if haptik:
            S.akkord([E4, Gis4, H4, E5], 1080, -2.0, tau_bis(ende(1080), 44.0), schritt=18.0)
        else:
            for i, (f, t, g) in enumerate(((E4, 0, -2.0), (Gis4, 20, -3.0), (H4, 40, -4.0), (E5, 60, -6.0))):
                S.schlag(f, 1080 + t, g, tau_bis(ende(1080 + t), 44.0), pan=-0.15 + 0.1 * i)
        S.luft(1000, 650, 900.0, 1800.0, -18.0, q=1.6, auf=0.3)
        S.fertig_filter()
        k.raum(0.6, -14.0, 5.0, S.raum_hell)
    elif name == "power_off":
        # Ausschalten: ein leiser Druck, dann fällt es abwärts (E5 H4 Gis4 E4), die Fläche schließt sich.
        S.druck(0, -14.0)
        S.schlag(H4, 0.5, -16.0, 0.03)
        for i, (f, t, g) in enumerate(((E5, 620, -6.0), (H4, 672, -4.0), (Gis4, 724, -3.0), (E4, 776, -2.0))):
            S.schlag(f, t, g, tau_bis(ende(t), 46.0), hell=0.7, pan=0.15 - 0.1 * i)
        S.flaeche([E4, H3, E3], 600, 700, -10.0, 60, 600, hell0=1.6, hell1=0.6)
        S.luft(620, 520, 1300.0, 300.0, -16.0, q=1.2, auf=0.2)
        S.fertig_filter()
        k.raum(0.55, -15.0, 5.0, S.raum_hell)
    elif name == "shutter":
        # Verschluss: zwei weiche Anschläge (auf, zu) und ein kleiner Ton.
        S.druck(0, -2.0, fc=520.0, kontakt=9.0)
        S.druck(58, -4.0, fc=420.0, kontakt=9.0)
        S.schlag(Cis5 * 2.0 if not haptik else Cis5, 2, -10.0, 0.025, hell=0.5)
        k.filter("lp", 2600.0)
        S.raum(0.8)
    elif name in ("achievement", "unlock", "unlock_rare", "unlock_retro"):
        retro = name == "unlock_retro"
        folge = {
            "achievement": ((E4, 0, 0.0), (Gis4, 65, -0.5), (H4, 130, -1.0), (E5, 195, -2.0), (Gis5, 260, -7.0)),
            "unlock": ((H4, 0, 0.0), (E5, 80, -1.0)),
            "unlock_rare": ((E4, 0, 0.0), (H4, 55, -0.5), (E5, 110, -1.0), (Gis5, 165, -3.0), (H5, 220, -6.0)),
            "unlock_retro": ((E4, 0, 0.0), (H4, 70, -1.0), (E5, 140, -2.0)),
        }[name]
        S.select(0, -2.0, folge[0][0] * 2.0 if folge[0][0] < 400.0 else folge[0][0], 0.05, latch=9.0 if not haptik else 26.0)
        if haptik and not retro:
            S.akkord([f for f, _, _ in folge], 30, -3.0, min(0.2, tau_bis(ende(30), 44.0)), schritt=folge[1][1] * 0.5)
        else:
            for i, (f, t, g) in enumerate(folge):
                tau = min(0.17, tau_bis(ende(t), 44.0))
                if retro:
                    # Rechteck-Ton, kräftig tiefpassgefiltert: Erinnerung an früher, ohne Schärfe.
                    sq = modal(f, rest(t), [(1.0, 1.0, min(tau, 0.09)), (3.0, 0.3, min(tau, 0.09) * 0.7), (5.0, 0.16, min(tau, 0.09) * 0.5),
                                            (7.0, 0.08, min(tau, 0.09) * 0.4)], att_ms=3.0)
                    k.mono(biquad(sq, "lp", 1800.0), t + 0.5, g, -0.12 + 0.12 * i)
                else:
                    S.schlag(f, t + 0.5, g, tau, pan=-0.16 + 0.32 * i / max(1, len(folge) - 1))
        if not retro:
            # Funkeln, aber warm: kleine Töne aus der Tonleiter bis höchstens Cis6, leise und weich.
            zahl = {"achievement": 4, "unlock": 3, "unlock_rare": 6}[name]
            t0 = folge[-1][1] + 40
            for j in range(zahl):
                f = note(rng.choice(("E6", "G#5", "B5", "C#6", "F#5")))
                t = t0 + j * rng.uniform(32.0, 52.0)
                k.mono(modal(f, rest(t), [(1.0, 1.0, min(0.05, tau_bis(ende(t), 46.0)))], att_ms=6.0, fm=(1.0, 0.3, 8.0)), t,
                       -16.0 - rng.uniform(0.0, 4.0), rng.uniform(-0.3, 0.3))
            akk = [E3, H3, E4] if name != "unlock" else [H3, E4]
            lang = rest(0)
            S.flaeche(akk, 20, lang - 40, -12.0, 120, lang * 0.55, hell0=1.4, hell1=0.9)
        S.fertig_filter()
        k.raum(0.5 if not retro else 0.25, -15.0 if not retro else -19.0, 5.0, S.raum_hell)
    elif name == "setup_step":
        # Schritt weiter: Bestätigen mit einem Hauch nach oben. Aufsteigend über die Tonhöhe beim Abspielen
        # (Klang.stufe_ton: E-Dur pentatonisch, Stufe 0 = dieser Ton).
        S.select(0, 0.0, E5, tau_bis(ende(8), 40.0), latch=8.0 if not haptik else 24.0)
        S.luft(0, 140, 500.0, 1300.0, -15.0, q=1.3, auf=0.35)
        S.fertig_filter()
        S.raum(1.4)
    elif name == "setup_found":
        # Etwas kommt näher (Luft steigt, wird lauter) und landet weich mit drei kleinen Tönen.
        S.luft(0, 280, 300.0, 1400.0, -5.0, q=1.4, auf=0.82)
        land = 235.0
        S.druck(land, -8.0)
        S.schlag(E5, land, -3.0, tau_bis(ende(land), 40.0))
        for j, f in enumerate((H5, Gis5, note("E6"))):
            t = land + 18.0 + j * 22.0
            k.mono(modal(f, rest(t), [(1.0, 1.0, min(0.05, tau_bis(ende(t), 40.0)))], att_ms=5.0, fm=(1.0, 0.4, 6.0)), t, -10.0 - 2.0 * j,
                   (-0.2, 0.2, -0.05)[j])
        S.fertig_filter()
        S.raum(2.0, 2.0)
    elif name == "setup_done":
        # Fertig: E-Dur mit None (Fis), gezupft, dunkle Fläche darunter.
        S.select(0, -3.0, E5, 0.05, latch=9.0 if not haptik else 26.0)
        akk = ((E4, 0, -3.0), (H4, 24, -3.0), (E5, 48, -2.0), (Gis5, 72, -3.0), (H5, 96, -5.0), (note("F#5"), 120, -9.0))
        if haptik:
            S.akkord([E4, Gis4, H4, E5], 20, -2.0, min(0.2, tau_bis(ende(20), 44.0)), schritt=24.0)
        else:
            for i, (f, t, g) in enumerate(akk):
                S.schlag(f, t + 0.5, g, min(0.2, tau_bis(ende(t), 44.0)), pan=-0.18 + 0.36 * i / (len(akk) - 1))
        S.flaeche([E3, H3, E4], 10, ms - 40, -11.0, 90, 750, hell0=1.0, hell1=1.6)
        S.luft(80, 700, 900.0, 1800.0, -20.0, q=1.6, auf=0.25)
        S.fertig_filter()
        k.raum(0.5, -14.0, 5.0, S.raum_hell)
    elif name == "swell":
        # Licht geht an: eine dunkle Fläche schwillt an und öffnet sich ein wenig, Luft steigt mit, oben ein
        # weicher Glanz (H4 und E5).
        S.flaeche([E3, H3, E4, Gis4, H4], 0, ms - 20, -2.0, 760, 680, hell0=0.6, hell1=2.0, ab_ab=780)
        S.luft(0, 900, 250.0, 1600.0, -10.0, q=1.1, auf=0.85)
        k.mono(modal(E5, rest(760), [(1.0, 1.0, min(0.17, tau_bis(ende(760), 44.0)))], att_ms=10.0, fm=(1.0, 0.4, 12.0)), 760, -10.0, 0.1)
        k.mono(modal(H4, rest(772), [(1.0, 1.0, min(0.17, tau_bis(ende(772), 44.0)))], att_ms=10.0, fm=(1.0, 0.4, 12.0)), 772, -12.0, -0.1)
        S.fertig_filter()
        k.raum(0.6, -15.0, 6.0, S.raum_hell)
    else:
        raise KeyError(name)
    return k.L[:k.n], k.R[:k.n]


def fertig(L, R, ziel_db):
    return k3.fertig(L, R, ziel_db)


# --- Messen --------------------------------------------------------------------------------------

def _fft_c(x, invers=False):
    """FFT (Radix 2) einer komplexen Liste, Länge eine Zweierpotenz. invers: ohne 1/n."""
    n = len(x)
    x = list(x)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            x[i], x[j] = x[j], x[i]
    sg = 1.0 if invers else -1.0
    m = 2
    while m <= n:
        w = complex(math.cos(sg * 2.0 * math.pi / m), math.sin(sg * 2.0 * math.pi / m))
        h = m // 2
        tw = [1.0 + 0j] * h
        for t in range(1, h):
            tw[t] = tw[t - 1] * w
        for s0 in range(0, n, m):
            for t in range(h):
                a = x[s0 + t]
                b = x[s0 + t + h] * tw[t]
                x[s0 + t] = a + b
                x[s0 + t + h] = a - b
        m *= 2
    return x


def _fft(re):
    """Leistungsspektrum (|X|², halbe Länge) eines reellen Signals, Länge auf Zweierpotenz aufgefüllt."""
    n = 1
    while n < len(re):
        n *= 2
    x = _fft_c([complex(v, 0.0) for v in re] + [0j] * (n - len(re)))
    return [abs(v) ** 2 for v in x[:n // 2]], n


def huelle(x):
    """Hüllkurve: Betrag des analytischen Signals (Hilbert über die FFT), über 0,5 ms geglättet – folgt dem
    Anstieg auch tiefer Töne genau (eine Spitzenwert-Hülle springt bei 165 Hz in Schritten von 3 ms). Geglättet über 1 ms."""
    n0 = len(x)
    n = 1
    while n < n0 + ns(10.0):
        n *= 2
    X = _fft_c([complex(v, 0.0) for v in x] + [0j] * (n - n0))
    for i in range(1, n // 2):
        X[i] *= 2.0
    for i in range(n // 2 + 1, n):
        X[i] = 0j
    z = _fft_c(X, True)
    env = [abs(v) / n for v in z[:n0]]
    w = max(1, ns(1.0))
    acc = 0.0
    out = [0.0] * n0
    for i in range(n0):
        acc += env[i]
        if i >= w:
            acc -= env[i - w]
        out[i] = acc / min(i + 1, w)
    return out


def _k_gewicht(x):
    """K-Bewertung nach ITU-R BS.1770 (Kuhschwanz +4 dB ab 1,7 kHz, Hochpass 38 Hz), bei 44,1 kHz nachgebaut."""
    f0, gdb, q = 1681.97, 3.99984, 0.7072
    A = 10.0 ** (gdb / 40.0)
    w = 2.0 * math.pi * f0 / SR
    al = math.sin(w) / (2.0 * q)
    cw = math.cos(w)
    sa = 2.0 * math.sqrt(A) * al
    b0 = A * ((A + 1) + (A - 1) * cw + sa)
    b1 = -2 * A * ((A - 1) + (A + 1) * cw)
    b2 = A * ((A + 1) + (A - 1) * cw - sa)
    a0 = (A + 1) - (A - 1) * cw + sa
    a1 = 2 * ((A - 1) - (A + 1) * cw)
    a2 = (A + 1) - (A - 1) * cw - sa
    y = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return biquad(y, "hp", 38.13, 0.5)


def anstieg_ms(x):
    """Steilster Anstieg (ms): für jeden Anschlag, der mindestens 30 % der größten Spitze erreicht und aus der
    Stille kommt (das Tal davor unter 10 % seiner Spitze und unter 15 % der größten), die Zeit von 10 auf
    90 % seiner Spitze – der kleinste Wert zählt. Unter 2 ms knackt oder sticht es."""
    env = huelle(x)
    n = len(env)
    mx = max(env) or 1e-12
    r = ns(3.0)
    best = 1e9
    i = 1
    while i < n - 1:
        v = env[i]
        if v >= 0.3 * mx and v > env[i - 1] and v >= max(env[max(0, i - r):min(n, i + r + 1)]):
            j = i
            while j > 0 and env[j - 1] <= env[j] and env[j - 1] > 0.0:
                j -= 1
            if env[j] < min(0.1 * v, 0.15 * mx):
                t10 = next(k for k in range(j, i + 1) if env[k] >= 0.1 * v)
                t90 = next(k for k in range(j, i + 1) if env[k] >= 0.9 * v)
                best = min(best, (t90 - t10) * 1000.0 / SR)
                i += r
        i += 1
    if best < 1e9:
        return best
    # kein abgesetzter Anschlag (Fläche, Anschwellen): vom ersten Zehntel bis 90 % der größten Spitze
    t10 = next(k for k in range(n) if env[k] >= 0.1 * mx)
    t90 = next(k for k in range(n) if env[k] >= 0.9 * mx)
    return (t90 - t10) * 1000.0 / SR


def analyse(l, r):
    """Messwerte über messen() hinaus: Spektralschwerpunkt (Hz, nach Betrag gewichtet wie üblich, Teiltöne
    ab −60 dB unter dem stärksten), Energieanteile über 5 und 6 kHz und zwischen 200 Hz und 3 kHz, Anstieg
    (ms, anstieg_ms), Lautheit (K-bewertet, lautestes 50-ms-Fenster, dB)."""
    m = k3.messen(l, r, True)
    mono = [(a + b) * 0.5 for a, b in zip(l, r)]
    p, n = _fft(mono)
    df = SR / n
    ges = sum(p) or 1e-30
    mag = [math.sqrt(v) for v in p]
    boden = max(mag) * 1e-3
    zaehler = sum(i * df * v for i, v in enumerate(mag) if v >= boden)
    m["schwerpunkt"] = zaehler / (sum(v for v in mag if v >= boden) or 1e-30)
    m["ueber5k"] = sum(v for i, v in enumerate(p) if i * df > 5000.0) / ges
    m["ueber6k"] = sum(v for i, v in enumerate(p) if i * df > 6000.0) / ges
    m["tv23"] = sum(v for i, v in enumerate(p) if 200.0 <= i * df <= 3000.0) / ges
    m["anstieg"] = anstieg_ms(mono)
    kl, kr = _k_gewicht(l), _k_gewicht(r)
    win = ns(50)
    sq = [(x * x + y * y) / 2.0 for x, y in zip(kl, kr)]
    acc = [0.0]
    for v in sq:
        acc.append(acc[-1] + v)
    best = 0.0
    for i in range(0, max(1, len(sq) - win + 1), ns(5)):
        j = min(len(sq), i + win)
        best = max(best, (acc[j] - acc[i]) / win)
    m["laut"] = db(math.sqrt(best))
    return m


# --- Dateien -------------------------------------------------------------------------------------

def ordner(satz):
    return os.path.join(SOUNDS, satz)


def alle_dateien():
    for name, ms, pegel, bew, fass, _ in TABELLE:
        for v in range(fass):
            yield name, v, ms, pegel, bew


def quelle_schreiben(saetze):
    """Ergänzt KLANG-QUELLE.txt: alles vor MARKE bleibt, ab MARKE die Sätze von hier; der Abschnitt von
    tools/synth_klang5.py (ab MARKE5, „Handpan“ und die Einrichtung) steht dahinter und bleibt."""
    alt = ""
    if os.path.isfile(QUELLE):
        with open(QUELLE, encoding="utf-8") as f:
            alt = f.read()
    danach = ""
    if MARKE5 in alt:
        danach = alt[alt.index(MARKE5):]
        alt = alt[:alt.index(MARKE5)]
    if MARKE in alt:
        alt = alt[:alt.index(MARKE)]
    zeilen = [MARKE + ": " + ", ".join("„%s“ (%s/)" % (SAETZE[s][0], s) for s in SAETZE) + ".",
              "Weich und leise: Holz und Filz, Stein auf Stoff, gedämpfte FM-Zupfer, tiefe Taps; E-Dur pentatonisch.",
              "Nur Python-Standardbibliothek, feste Startwerte (gleiche Quelle, gleiche Dateien). 44,1 kHz, Stereo, 16 Bit.",
              ""]
    for s in SAETZE:
        for name, v, *_ in alle_dateien():
            p = os.path.join(ordner(s), datei(name, v))
            if os.path.isfile(p):
                zeilen.append("%s  %s/%s" % (k3.sha(p), s, datei(name, v)))
    with open(QUELLE, "w", encoding="utf-8", newline="\n") as f:
        f.write(alt.rstrip("\n") + "\n\n" + "\n".join(zeilen) + "\n" + ("\n" + danach if danach else ""))


KOPF = "  %-12s %s %6s %7s %7s %6s %6s %5s %5s %5s %5s %6s" % ("Klang", "F", "ms", "Spitze", "RMS", "zuSel", "Schw.", ">5k", ">6k", "TV", "Anst", "Laut")


def _zeile(name, v, m, ref):
    return "  %-12s %d %6.0f %7.1f %7.1f %+6.1f %6.0f %5.1f %5.1f %5.0f %5.1f %6.1f" % (
        name, v + 1, m["ms"], m["spitze"], m["rms"], m["rms"] - ref, m["schwerpunkt"], m["ueber5k"] * 100, m["ueber6k"] * 100,
        m["tv23"] * 100, m["anstieg"], m["laut"])


def rendern(saetze):
    for s in saetze:
        os.makedirs(ordner(s), exist_ok=True)
        ref = SAETZE[s][1]
        print("Satz „%s“ (%s)" % (SAETZE[s][0], s))
        print(KOPF)
        for name, v, ms, pegel, _ in alle_dateien():
            L, R = fertig(*baue(s, name, ms, v), ref + pegel)
            k3.schreibe(os.path.join(ordner(s), datei(name, v)), L, R)
            print(_zeile(name, v, analyse(L, R), ref))
    quelle_schreiben(saetze)


def _lies(pfad):
    return k3.lies(pfad)[:2]


def pruefen():
    fehler = 0

    def fail(was):
        nonlocal fehler
        print("  FAIL " + was)
        fehler += 1

    perle = {}
    for name in ("move", "tick", "select", "back", "open"):
        perle[name] = analyse(*_lies(os.path.join(ordner(PERLE), name + ".wav")))
    for s in SAETZE:
        ref = SAETZE[s][1]
        werte = {}
        for name, v, ms, pegel, bew in alle_dateien():
            pfad = os.path.join(ordner(s), datei(name, v))
            d = "%s/%s" % (s, datei(name, v))
            if not os.path.isfile(pfad):
                fail(d + " fehlt")
                continue
            l, r, fr, ch = k3.lies(pfad)
            if fr != SR or ch != 2:
                fail("%s: %d Hz, %d Kanäle" % (d, fr, ch))
            m = analyse(l, r)
            werte.setdefault(name, []).append(m)
            grenze = BOOT_MAX_MS if name == "boot" else bew + NACHKLANG_MS
            pr = [
                (abs(m["ms"] - ms) <= 1.0, "Länge %.0f ms (soll %d)" % (m["ms"], ms)),
                (m["ms"] <= grenze, "Länge ≤ %d ms" % grenze),
                (abs(m["rms"] - (ref + pegel)) <= PEGEL_TOL_DB, "RMS %.1f dBFS (soll %.1f)" % (m["rms"], ref + pegel)),
                (m["spitze"] <= SPITZE_MAX_DB, "Spitze %.1f dBFS ≤ %.0f" % (m["spitze"], SPITZE_MAX_DB)),
                (m["ende"] <= ENDE_MAX_DB[0 if ms < 200 else 1], "verklungen vor dem Ausblenden (%.0f dB)" % m["ende"]),
                (m["rand"] < 0.0012, "beginnt und endet bei null"),
                (m["korr"] >= KORR_MIN, "Stereo dezent (Korrelation %.2f)" % m["korr"]),
                (m["ueber5k"] <= UEBER_5K_MAX, "über 5 kHz %.1f %% ≤ %.0f %%" % (m["ueber5k"] * 100, UEBER_5K_MAX * 100)),
                (m["tv23"] >= (TV_MIN if name in KERN else TV_MIN_ALLE), "200 Hz–3 kHz %.0f %%" % (m["tv23"] * 100)),
            ]
            if name in NAV:
                pr += [
                    (m["schwerpunkt"] < NAV_SCHWERPUNKT, "Schwerpunkt %.0f Hz < %.0f" % (m["schwerpunkt"], NAV_SCHWERPUNKT)),
                    (m["ueber6k"] < NAV_UEBER_6K, "über 6 kHz %.1f %%" % (m["ueber6k"] * 100)),
                    (m["anstieg"] >= NAV_ANSTIEG_MS, "Anstieg %.1f ms ≥ %.0f" % (m["anstieg"], NAV_ANSTIEG_MS)),
                    (m["spitze"] <= NAV_SPITZE_DB, "Spitze %.1f dBFS ≤ %.0f" % (m["spitze"], NAV_SPITZE_DB)),
                ]
            if name in ("select", "back"):
                pr.append((m["schwerpunkt"] < KERN_SCHWERPUNKT, "Schwerpunkt %.0f Hz < %.0f" % (m["schwerpunkt"], KERN_SCHWERPUNKT)))
            for ok, was in pr:
                if not ok:
                    fail("%s: %s" % (d, was))
        if "select" in werte:
            sel = werte["select"][0]
            for nav in NAV:
                for m in werte.get(nav, []):
                    if m["rms"] > sel["rms"] - NAV_ABSTAND_DB:
                        fail("%s/%s: RMS %.1f nicht %.0f dB unter select (%.1f)" % (s, nav, m["rms"], NAV_ABSTAND_DB, sel["rms"]))
            for name in perle:
                if name in werte and werte[name][0]["laut"] >= perle[name]["laut"]:
                    fail("%s/%s: nicht leiser als „Perle“ (%.1f / %.1f dB)" % (s, name, werte[name][0]["laut"], perle[name]["laut"]))
            if not (-28.0 < sel["spitze"] < -16.0):
                fail("%s/select: Spitze %.1f dBFS (soll −28 … −16)" % (s, sel["spitze"]))
    print("Ergebnis: %s" % ("alles ok" if fehler == 0 else "%d Fehler" % fehler))
    return 1 if fehler else 0


def messtabelle(namen=("move", "tick", "select", "back", "open", "toggle_on", "guide", "notify", "achievement", "boot")):
    """Messwerte der Kernklänge je Satz (erste Fassung), Perle zum Vergleich; Lautheit relativ zu Perle."""
    zeilen = []
    perle = {n: analyse(*_lies(os.path.join(ordner(PERLE), n + ".wav"))) for n in namen}
    for s in [PERLE] + list(SAETZE):
        for n in namen:
            m = perle[n] if s == PERLE else analyse(*_lies(os.path.join(ordner(s), n + ".wav")))
            zeilen.append((s, n, m, m["laut"] - perle[n]["laut"]))
    print("  %-7s %-12s %6s %7s %7s %6s %5s %5s %5s %5s %7s" % ("Satz", "Klang", "ms", "Spitze", "RMS", "Schw.", ">5k", ">6k", "TV", "Anst", "zuPerle"))
    for s, n, m, d in zeilen:
        print("  %-7s %-12s %6.0f %7.1f %7.1f %6.0f %5.1f %5.1f %5.0f %5.1f %+7.1f" % (s, n, m["ms"], m["spitze"], m["rms"], m["schwerpunkt"],
              m["ueber5k"] * 100, m["ueber6k"] * 100, m["tv23"] * 100, m["anstieg"], d))
    return zeilen


# --- Hörproben -----------------------------------------------------------------------------------
# Gemischt wie in Uzai: Standardregler 0,6 × 0,75, Bewegen nach Klang.bewegen (Tonhöhe ±1,5 %, Lautstärke
# ±0,5 dB, schneidet den eigenen Nachklang ab, gehalten bis −8 dB), Fassungen zufällig ohne Wiederholung
# (Klang.variante), Liste abwärts eine Spur tiefer (Klang.kontext), „tab“ aus der Richtung, danach der
# Tiefpass der Leitung „UI“ (5,2 kHz). Zum Abhören alles um genau ABHOEREN_DB lauter – für alle Sätze
# gleich, die Unterschiede in der Lautstärke bleiben hörbar.

REGLER = 0.6 * 0.75
ABHOEREN_DB = 12.0


class Mischer:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.L, self.R = [], []
        self.letzte = {}
        self.cache = {}
        self.lauf = None
        self.zeilen = []

    def fass(self, satz, name):
        n = 0
        while os.path.isfile(os.path.join(ordner(satz), datei(name, n))):
            n += 1
        return max(1, n)

    def spiel(self, satz, name, at, pitch=1.0, db_=0.0, pan=0.0, abschnitt=""):
        n = self.fass(satz, name)
        vor = self.letzte.get((satz, name), -1)
        z = self.rng.random()
        if n <= 1:
            v = 0
        elif vor < 0:
            v = min(n - 1, int(z * n))
        else:
            v = min(n - 2, int(z * (n - 1)))
            v = v + 1 if v >= vor else v
        self.letzte[(satz, name)] = v
        key = (satz, name, v)
        if key not in self.cache:
            self.cache[key] = _lies(os.path.join(ordner(satz), datei(name, v)))
        l, r = self.cache[key]
        if pitch != 1.0:
            m = int(len(l) / pitch)
            l = [l[min(int(j * pitch), len(l) - 1)] for j in range(m)]
            r = [r[min(int(j * pitch), len(r) - 1)] for j in range(m)]
        i0 = ns(at * 1000.0)
        L, R = self.L, self.R
        need = i0 + len(l)
        if need > len(L):
            L.extend([0.0] * (need - len(L)))
            R.extend([0.0] * (need - len(R)))
        if name in NAV and self.lauf is not None:
            a, lang = self.lauf
            f = ns(4)
            for i in range(i0, min(a + lang, len(L))):
                g = max(0.0, 1.0 - (i - i0) / f)
                L[i] *= g
                R[i] *= g
        gl = REGLER * amp(db_) * (1.0 - max(pan, 0.0))
        gr = REGLER * amp(db_) * (1.0 + min(pan, 0.0))
        add(L, i0, l, gl)
        add(R, i0, r, gr)
        if name in NAV:
            self.lauf = (i0, len(l))
        self.zeilen.append((at, satz, name, v, len(l) * 1000.0 / SR, abschnitt))
        return at + len(l) / SR

    def blaettern(self, satz, t, anzahl, abstand, abschnitt):
        ende = t
        for i in range(anzahl):
            y = i / max(1, anzahl - 1)
            p = (1.0 + (0.5 - y) * 0.03) * (1.0 + self.rng.uniform(-1.0, 1.0) * 0.015)
            ende = self.spiel(satz, "move", t, p, self.rng.uniform(-0.5, 0.5), abschnitt=abschnitt if i == 0 else "")
            t += abstand
        return ende

    def fertig(self, ziel, rest_s=0.3):
        L = self.L + [0.0] * ns(rest_s * 1000.0)
        R = self.R + [0.0] * ns(rest_s * 1000.0)
        L = biquad(L, "lp", 5200.0, 0.5)
        R = biquad(R, "lp", 5200.0, 0.5)
        g = amp(ABHOEREN_DB)
        L = [max(-1.0, min(1.0, v * g)) for v in L]
        R = [max(-1.0, min(1.0, v * g)) for v in R]
        k3.schreibe(ziel, L, R)
        sp = db(max(peak(L), peak(R)))
        # Lautheit der ganzen Probe (K-bewertet, nur wo etwas klingt: Fenster über −50 dB)
        kl, kr = _k_gewicht(L), _k_gewicht(R)
        win = ns(100)
        e = []
        for i in range(0, len(kl) - win, win):
            e.append(sum(kl[j] * kl[j] + kr[j] * kr[j] for j in range(i, i + win, 4)) / (win / 4) / 2.0)
        aktiv = [v for v in e if v > amp(-50.0) ** 2]
        laut = db(math.sqrt(sum(aktiv) / len(aktiv))) if aktiv else -120.0
        return len(L) / SR, sp, laut


def probe_satz(satz, ziel):
    """Dieselbe Folge für jeden Satz: 12× Liste blättern im Menütempo, Rand, Regler, Bestätigen ×3,
    Zurück ×2, Schalter an/aus, Reiter, Guide auf/zu, Mitteilung, Erfolg, Start."""
    m = Mischer("uzai-klang4-hoerprobe")
    t = 0.4
    ende = m.blaettern(satz, t, 12, 0.3, "Liste blättern (12×, Menütempo)")
    t = ende + 0.5
    ende = m.spiel(satz, "bump", t, 0.92, abschnitt="Rand unten")
    t = ende + 0.6
    for i in range(8):
        ende = m.spiel(satz, "tick", t, 1.0 + m.rng.uniform(-1.0, 1.0) * 0.015, m.rng.uniform(-0.5, 0.5), abschnitt="Regler (8 Rasten)" if i == 0 else "")
        t += 0.13
    t = ende + 0.6
    for i in range(3):
        ende = m.spiel(satz, "select", t, abschnitt="Bestätigen ×3" if i == 0 else "")
        t = ende + 0.55
    for i in range(2):
        ende = m.spiel(satz, "back", t, abschnitt="Zurück ×2" if i == 0 else "")
        t = ende + 0.55
    ende = m.spiel(satz, "toggle_on", t, abschnitt="Schalter an, aus")
    t = ende + 0.45
    ende = m.spiel(satz, "toggle_off", t)
    t = ende + 0.55
    ende = m.spiel(satz, "tab", t, pan=0.3, abschnitt="Reiter")
    t = ende + 0.6
    ende = m.spiel(satz, "guide", t, abschnitt="Guide auf, zu")
    t = ende + 0.9
    ende = m.spiel(satz, "guide_close", t)
    t = ende + 0.6
    ende = m.spiel(satz, "notify", t, abschnitt="Mitteilung")
    t = ende + 0.7
    ende = m.spiel(satz, "achievement", t, abschnitt="Erfolg")
    t = ende + 0.8
    ende = m.spiel(satz, "boot", t, abschnitt="Start")
    lang, sp, laut = m.fertig(ziel)
    return m.zeilen, lang, sp, laut


def probe_vergleich(ziel, saetze):
    """Kurz: 8× blättern, Bestätigen, Zurück – nacheinander je Satz, dazwischen 1 s Stille."""
    m = Mischer("uzai-klang4-vergleich")
    t = 0.4
    starts = []
    for s in saetze:
        starts.append((s, t))
        ende = m.blaettern(s, t, 8, 0.3, "Blättern 8×")
        t = ende + 0.45
        ende = m.spiel(s, "select", t, abschnitt="Bestätigen")
        t = ende + 0.5
        ende = m.spiel(s, "back", t, abschnitt="Zurück")
        t = ende + 1.0
    lang, sp, laut = m.fertig(ziel, 0.1)
    return starts, m.zeilen, lang, sp, laut


def hoerprobe(ziel_ordner):
    os.makedirs(ziel_ordner, exist_ok=True)
    saetze = [PERLE] + list(SAETZE)
    md = ["# Klang 4 – Hörproben", "",
          "Gemischt wie in Uzai (Standardregler 0,6 × 0,75 ≈ −7 dB, Bewegen mit Zufall ±1,5 % / ±0,5 dB, Fassungen ohne Wiederholung, "
          "Tiefpass 5,2 kHz der Leitung „UI“), zum Abhören **alle gleich um +12 dB** lauter – die Unterschiede in der Lautstärke "
          "zwischen den Sätzen bleiben also hörbar. F = Fassung.", ""]
    laut = {}
    for s in saetze:
        name = SAETZE[s][0] if s in SAETZE else "Perle"
        ziel = os.path.join(ziel_ordner, "klang4_%s.wav" % s)
        zeilen, lang, sp, ld = probe_satz(s, ziel)
        laut[s] = ld
        print("Hörprobe %s: %.1f s, Spitze %.1f dBFS, Lautheit %.1f dB" % (ziel, lang, sp, ld))
        md += ["## %s – `%s`" % (name, ziel), "",
               "%.1f s, Spitze %.1f dBFS, Lautheit (K-bewertet, nur wo es klingt) %.1f dB%s." % (
                   lang, sp, ld, "" if s == PERLE else ", %+.1f dB zu „Perle“" % (ld - laut[PERLE])), "",
               "| ab | Abschnitt | Klang | F | Dauer |", "|---|---|---|---|---|"]
        for at, _, n, v, d, ab in zeilen:
            md.append("| %.2f s | %s | %s | %d | %.0f ms |" % (at, ab, n, v + 1, d))
        md.append("")
    ziel = os.path.join(ziel_ordner, "klang4_vergleich.wav")
    starts, zeilen, lang, sp, ld = probe_vergleich(ziel, saetze)
    print("Vergleich %s: %.1f s" % (ziel, lang))
    md += ["## Vergleich – `%s`" % ziel, "",
           "Je Satz dieselbe kurze Folge (8× blättern, Bestätigen, Zurück), dazwischen 1 s Stille.", "",
           "| ab | Satz |", "|---|---|"]
    for s, t in starts:
        md.append("| %.2f s | %s |" % (t, SAETZE[s][0] if s in SAETZE else "Perle (bisher)"))
    md.append("")
    with open(os.path.join(ziel_ordner, "klang4_hoerprobe.md"), "w", encoding="utf-8") as f:
        # Dezimalkomma nur in Zahlen (Pfade bleiben, wie sie sind)
        f.write(re.sub(r"(\d)\.(\d)", r"\1,\2", "\n".join(md)) + "\n")
    print("Tabelle:", os.path.join(ziel_ordner, "klang4_hoerprobe.md"))


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--pruefen" in a:
        sys.exit(pruefen())
    if "--messen" in a:
        messtabelle()
        sys.exit(0)
    if "--hoerprobe" in a:
        hoerprobe(a[a.index("--hoerprobe") + 1])
        sys.exit(0)
    if "--einrichtung" in a:
        print("Die Klänge der Einrichtung rendert tools/synth_klang5.py --einrichtung.")
        sys.exit(1)
    rendern([s for s in a if s in SAETZE] or list(SAETZE))
