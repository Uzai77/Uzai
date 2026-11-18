# Aufruf: python tools/synth_musik.py assets/musik <ffmpeg> [name …]   (braucht numpy)
# Menümusik von Uzai (Roadmap 99): ruhige, selbst komponierte Loops, hier Ton für Ton erzeugt –
# keine Samples, keine fremden Melodien. Jedes Stück ist eine Schleife ohne Naht: Alles (Noten,
# Hall, Echo, Filter) wird kreisförmig gerechnet, was über das Ende hinausklingt, klingt am
# Anfang weiter. Ausgabe: OGG Vorbis (Stereo, 32 kHz) über FFmpeg, das als Programm mit festen
# Argumenten aufgerufen wird.
#
# Stücke (je Klangsatz eines, src/core/klang.gd):
#   ruhe   – Graphit: warme Flächen in D-Dur, ein paar Glockentöne
#   welle  – Welle: fließende Zupf-Arpeggios mit Echo
#   glas   – Klingen: helle, harmonische Glocken über einem Grundton
#   holz   – Kacheln: weiches Marimba-Muster, runder Bass
#   abend  – Regal: E-Piano-Akkorde, ruhig und warm
#   retro  – Retro: sanfte Puls- und Dreieckswellen wie auf alten Konsolen, ganz eigene Melodie
#   hell   – Minimal Hell: wenige, helle Klaviertöne mit viel Luft
import numpy as np, wave, sys, os, subprocess, tempfile

SR = 32000
OUT = sys.argv[1]
FFMPEG = sys.argv[2]
ONLY = sys.argv[3:]


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


class Loop:
    """Stereo-Puffer genau einer Schleife; Noten über das Ende hinaus laufen vorn weiter."""

    def __init__(self, sec):
        self.n = int(round(sec * SR))
        self.buf = np.zeros((2, self.n))

    def add(self, sig, at_sec, pan=0.0, gain=1.0):
        """sig: Mono (n,) oder Stereo (2, n). pan -1 … 1 (gleiche Leistung)."""
        if sig.ndim == 1:
            a = (pan + 1.0) * np.pi / 4.0
            sig = np.vstack([sig * np.cos(a), sig * np.sin(a)]) * np.sqrt(2.0)
        k = int(round(at_sec * SR)) % self.n
        m = sig.shape[1]
        idx = (np.arange(m) + k) % self.n
        np.add.at(self.buf[0], idx, sig[0] * gain)
        np.add.at(self.buf[1], idx, sig[1] * gain)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def adsr(n, a, r, sus=1.0, d=0.0, dl=1.0):
    t = np.arange(n) / SR
    total = n / SR
    e = np.minimum(t / max(a, 1e-4), 1.0)
    if d > 0:
        e = e * np.where(t < a, 1.0, dl + (1.0 - dl) * np.exp(-(t - a) / d))
    rel = np.clip((total - t) / max(r, 1e-4), 0.0, 1.0)
    return e * rel * sus


# --- Klangerzeuger ------------------------------------------------------------------------------

def pad(f, sec, a=1.6, r=2.4, bright=0.35, seed=0):
    """Weiche Fläche: verstimmte Obertöne, langsames Atmen, links und rechts leicht verschieden."""
    rng = np.random.default_rng(seed)
    t = t_axis(sec)
    out = np.zeros((2, len(t)))
    for ch in range(2):
        s = np.zeros_like(t)
        for k in range(1, 9):
            amp = (1.0 / k) * np.exp(-(k - 1) * (1.0 - bright) * 0.9)
            for det in (-0.004, 0.0, 0.004):
                d = det * (1 if ch == 0 else -1)
                s += amp * np.sin(2 * np.pi * f * k * (1 + d) * t + rng.uniform(0, 6.28))
        lfo = 1.0 + 0.08 * np.sin(2 * np.pi * (0.11 + 0.03 * ch) * t + rng.uniform(0, 6.28))
        out[ch] = s * lfo / 6.0
    return out * adsr(len(t), a, r)


def bell(f, sec=3.5, ratio=2.0, index=1.6, decay=1.4, idecay=3.0):
    """Harmonische FM-Glocke (ganzzahliges Verhältnis: keine schiefen Obertöne)."""
    t = t_axis(sec)
    mod = np.sin(2 * np.pi * f * ratio * t) * index * np.exp(-t * idecay)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * decay)
    return s * adsr(len(t), 0.004, 0.3)


def pluck(f, sec=1.6, bright=0.6, decay=3.2):
    """Gezupft: höhere Obertöne verklingen schneller."""
    t = t_axis(sec)
    s = np.zeros_like(t)
    for k in range(1, 10):
        s += (bright ** (k - 1)) / k * np.sin(2 * np.pi * f * k * t) * np.exp(-t * decay * (1 + 0.55 * (k - 1)))
    return s * adsr(len(t), 0.003, 0.2)


def marimba(f, sec=1.4):
    t = t_axis(sec)
    s = np.sin(2 * np.pi * f * t) * np.exp(-t * 3.4)
    s += 0.28 * np.sin(2 * np.pi * f * 4.0 * t) * np.exp(-t * 14.0)
    s += 0.08 * np.sin(2 * np.pi * f * 10.0 * t) * np.exp(-t * 40.0)
    return s * adsr(len(t), 0.002, 0.15)


def epiano(f, sec=3.0, vel=1.0):
    """E-Piano: FM 1:1 mit abklingendem Index, leiser Zungen-Oberton."""
    t = t_axis(sec)
    idx = (0.9 + 0.8 * vel) * np.exp(-t * 2.2)
    s = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    s += 0.06 * vel * np.sin(2 * np.pi * f * 14.0 * t) * np.exp(-t * 18.0)
    trem = 1.0 + 0.05 * np.sin(2 * np.pi * 4.6 * t)
    return s * trem * np.exp(-t * 0.9) * adsr(len(t), 0.003, 0.4)


def piano(f, sec=4.0):
    """Leichtes Klavier: Obertöne mit etwas Spreizung, die hohen verklingen schneller."""
    t = t_axis(sec)
    s = np.zeros_like(t)
    b = 0.0004
    for k in range(1, 8):
        fk = f * k * np.sqrt(1 + b * k * k)
        s += (0.7 ** (k - 1)) * np.sin(2 * np.pi * fk * t) * np.exp(-t * (0.8 + 0.7 * k))
    return s * adsr(len(t), 0.003, 0.5)


def pulse(f, sec, duty=0.25, decay=0.0, a=0.01, r=0.06):
    """Bandbegrenzte Pulswelle (Obertöne bis 7 kHz, kein Aliasing), dazu eine weiche Hüllkurve."""
    t = t_axis(sec)
    s = np.zeros_like(t)
    k = 1
    while f * k < 7000:
        s += np.sin(np.pi * k * duty) / k * np.cos(2 * np.pi * f * k * t)
        k += 1
    s = s - s.mean()
    return s * np.exp(-t * decay) * adsr(len(t), a, r) * 0.6


def tri(f, sec, a=0.01, r=0.08):
    t = t_axis(sec)
    s = np.zeros_like(t)
    for k in range(1, 30, 2):
        if f * k > 7000:
            break
        s += ((-1) ** ((k - 1) // 2)) / (k * k) * np.sin(2 * np.pi * f * k * t)
    return s * adsr(len(t), a, r) * 0.8


def sub(f, sec, a=0.3, r=0.8):
    t = t_axis(sec)
    return np.sin(2 * np.pi * f * t) * adsr(len(t), a, r)


# --- Kreisförmige Bearbeitung (nahtlose Schleife) -----------------------------------------------

def lowpass(x, fc, order=2):
    """Weicher Tiefpass im Spektrum (kreisförmig: passt zur Schleife)."""
    X = np.fft.rfft(x, axis=-1)
    f = np.fft.rfftfreq(x.shape[-1], 1.0 / SR)
    H = 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))
    return np.fft.irfft(X * H, n=x.shape[-1], axis=-1)


def highpass(x, fc):
    X = np.fft.rfft(x, axis=-1)
    f = np.fft.rfftfreq(x.shape[-1], 1.0 / SR)
    H = 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** 4)
    return np.fft.irfft(X * H, n=x.shape[-1], axis=-1)


def reverb(x, sec=3.2, damp=2600.0, seed=3):
    """Hall als Faltung mit selbst erzeugter Impulsantwort (abklingendes, gedämpftes Rauschen)."""
    n = x.shape[-1]
    rng = np.random.default_rng(seed)
    m = min(int(sec * SR), n - 1)
    t = np.arange(m) / SR
    out = np.zeros_like(x)
    for ch in range(2):
        ir = rng.standard_normal(m) * np.exp(-t * 6.9 / sec)
        ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        full = np.zeros(n)
        full[:m] = ir
        full = lowpass(full, damp, 1)
        full /= np.sqrt(np.sum(full ** 2)) + 1e-9
        out[ch] = np.fft.irfft(np.fft.rfft(x[ch]) * np.fft.rfft(full), n=n)
    return out


def echo(x, sec, fb=0.35, n_taps=4, cross=True):
    """Echo (Ping-Pong) als verschobene Kopien – kreisförmig."""
    out = x.copy()
    k = int(round(sec * SR))
    g = 1.0
    cur = x
    for i in range(1, n_taps + 1):
        g *= fb
        cur = np.roll(cur, k, axis=-1)
        if cross:
            cur = cur[::-1]
        out = out + lowpass(cur, 3200.0, 1) * g
    return out


def master(x, wet, rms=0.1, peak=0.8):
    """Alle Stücke gleich laut (Effektivwert), Spitzen nie über peak."""
    y = x + wet
    y = highpass(y, 32.0)
    y = y / (np.sqrt(np.mean(y ** 2)) + 1e-9) * rms
    top = np.max(np.abs(y))
    return y * (peak / top) if top > peak else y


# --- Stücke -------------------------------------------------------------------------------------

def ruhe():
    """Graphit: 60 BPM, ein Akkord je Takt (4 s), acht Takte."""
    bar = 4.0
    L = Loop(bar * 8)
    chords = [
        [50, 57, 61, 64, 66], [47, 54, 57, 61, 62], [43, 50, 54, 57, 59], [45, 52, 59, 61, 64],
        [42, 50, 57, 61, 64], [40, 47, 50, 54, 55], [43, 50, 54, 57, 59], [45, 52, 57, 59, 62],
    ]
    for i, ch in enumerate(chords):
        for j, n in enumerate(ch):
            L.add(pad(midi(n), bar + 2.6, a=1.8, r=2.6, bright=0.28, seed=i * 10 + j), i * bar - 0.3, gain=0.12)
        L.add(sub(midi(ch[0] - 12 if ch[0] > 45 else ch[0]), bar + 1.0, 0.6, 1.2), i * bar, gain=0.16)
    # Glocken: wenige Töne, die Melodie atmet mit den Akkorden.
    motif = [(0, 2.0, 78), (0, 3.0, 76), (1, 1.0, 73), (1, 2.5, 74), (2, 2.0, 71), (3, 0.0, 73),
             (3, 3.0, 76), (4, 2.0, 78), (4, 3.0, 81), (5, 1.0, 79), (5, 2.5, 78), (6, 2.0, 74), (7, 1.0, 76), (7, 3.0, 73)]
    for b, beat, n in motif:
        L.add(bell(midi(n), 4.0, ratio=2.0, index=1.2, decay=1.2), b * bar + beat, pan=0.35 * np.sin(n), gain=0.1)
    dry = lowpass(L.buf, 3800.0)
    return master(dry, reverb(dry, 4.0, 2200.0) * 0.55)


def welle():
    """Welle: 80 BPM, Achtel-Arpeggios aus gezupften Tönen, Echo von links nach rechts."""
    beat = 60.0 / 80.0
    bar = beat * 4
    L = Loop(bar * 8)
    chords = [[55, 59, 62, 66], [57, 61, 64, 66], [54, 57, 61, 64], [47, 54, 57, 62],
              [55, 59, 62, 66], [57, 61, 64, 69], [59, 62, 66, 69], [50, 57, 62, 64]]
    order = [0, 1, 2, 3, 2, 1, 3, 2]
    for i, ch in enumerate(chords):
        for s in range(8):
            n = ch[order[s]] + (12 if s in (3, 6) else 0)
            vel = 0.75 if s % 2 else 1.0
            L.add(pluck(midi(n), 1.8, bright=0.45, decay=2.4), i * bar + s * beat / 2, pan=-0.4 + 0.8 * (s / 7.0), gain=0.11 * vel)
        L.add(pad(midi(ch[0] - 12), bar + 2.0, a=1.0, r=1.8, bright=0.2, seed=i), i * bar - 0.2, gain=0.08)
        L.add(pad(midi(ch[2]), bar + 2.0, a=1.4, r=1.8, bright=0.2, seed=i + 40), i * bar - 0.2, gain=0.05)
        L.add(sub(midi(ch[0] - 24), bar + 0.6, 0.2, 0.8), i * bar, gain=0.17)
    dry = lowpass(L.buf, 4200.0)
    wet = echo(dry, beat * 0.75, fb=0.32, n_taps=4) - dry
    return master(dry + wet * 0.7, reverb(dry, 3.0, 2600.0) * 0.4)


def glas():
    """Klingen: 72 BPM, helle Glocken über dem Grundton E – kühl, klar, viel Raum."""
    beat = 60.0 / 72.0
    bar = beat * 4
    L = Loop(bar * 8)
    for i in range(8):
        root = 40 if i < 6 else 38
        L.add(pad(midi(root + 12), bar + 3.0, a=2.0, r=3.0, bright=0.18, seed=i), i * bar - 0.5, gain=0.1)
        L.add(pad(midi(root + 19), bar + 3.0, a=2.4, r=3.0, bright=0.15, seed=i + 9), i * bar - 0.5, gain=0.06)
    mel = [(0, 0, 71), (0, 1.5, 76), (0, 3, 78), (1, 1, 83), (1, 2.5, 81), (2, 0, 78), (2, 2, 76), (3, 1, 74),
           (3, 3, 76), (4, 0, 71), (4, 1.5, 76), (4, 3, 79), (5, 1, 83), (5, 2.5, 86), (6, 0, 83), (6, 2, 81), (7, 1, 78), (7, 3, 76)]
    for b, bt, n in mel:
        p = 0.5 * np.cos(n * 1.7)
        L.add(bell(midi(n), 4.5, ratio=3.0, index=0.9, decay=0.9, idecay=2.0), b * bar + bt * beat, pan=p, gain=0.09)
        L.add(bell(midi(n + 12), 2.0, ratio=2.0, index=0.5, decay=2.4), b * bar + bt * beat + 0.01, pan=-p, gain=0.025)
    dry = lowpass(L.buf, 5200.0)
    return master(dry, reverb(dry, 5.0, 3200.0) * 0.75)


def holz():
    """Kacheln: 92 BPM, weiches Marimba-Muster mit Pausen, runder Bass, leise Fläche."""
    beat = 60.0 / 92.0
    bar = beat * 4
    L = Loop(bar * 8)
    chords = [[62, 66, 69, 73], [59, 62, 66, 69], [55, 59, 62, 66], [57, 61, 64, 67],
              [62, 66, 69, 74], [59, 62, 66, 71], [55, 59, 62, 64], [57, 61, 64, 69]]
    bass = [38, 35, 31, 33, 38, 35, 31, 33]
    pattern = [(0, 0), (1, 1), (1.5, 2), (2.5, 3), (3, 1), (3.5, 2)]
    for i, ch in enumerate(chords):
        for bt, k in pattern:
            vel = 1.0 if bt in (0, 2.5) else 0.7
            L.add(marimba(midi(ch[k])), i * bar + bt * beat, pan=-0.3 + 0.2 * k, gain=0.13 * vel)
        if i % 2 == 1:
            L.add(marimba(midi(ch[3] + 12)), i * bar + 3.75 * beat, pan=0.4, gain=0.06)
        L.add(pluck(midi(bass[i]), 2.0, bright=0.25, decay=1.6), i * bar, gain=0.22)
        L.add(pluck(midi(bass[i] + 7), 1.2, bright=0.25, decay=2.0), i * bar + 2.5 * beat, gain=0.12)
        L.add(pad(midi(ch[0] - 12), bar + 1.5, a=1.2, r=1.6, bright=0.15, seed=i), i * bar - 0.2, gain=0.05)
    dry = lowpass(L.buf, 4000.0)
    return master(dry, reverb(dry, 2.2, 2400.0) * 0.35)


def abend():
    """Regal: 70 BPM, E-Piano-Akkorde (Gmaj9 – F#m7 – Em9 – A13), ruhiger Bass."""
    beat = 60.0 / 70.0
    bar = beat * 4
    L = Loop(bar * 8)
    chords = [[55, 59, 62, 66, 69], [54, 57, 61, 64], [52, 55, 59, 62, 66], [57, 61, 66, 67, 71],
              [55, 59, 62, 66, 69], [54, 57, 61, 64, 69], [52, 55, 59, 62, 66], [57, 59, 62, 64, 67]]
    bass = [43, 42, 40, 45, 43, 42, 40, 45]
    rhythm = [(0.0, 1.0), (1.5, 0.55), (2.5, 0.75)]
    for i, ch in enumerate(chords):
        for bt, vel in rhythm:
            for j, n in enumerate(ch):
                L.add(epiano(midi(n), 2.6, vel), i * bar + bt * beat + j * 0.012, pan=-0.25 + 0.5 * j / len(ch), gain=0.07 * vel)
        L.add(pluck(midi(bass[i] - 12), 2.6, bright=0.2, decay=1.0), i * bar, gain=0.26)
        L.add(pluck(midi(bass[i] - 5), 1.2, bright=0.2, decay=1.8), i * bar + 3 * beat, gain=0.12)
    mel = [(1, 3.0, 78), (2, 0.5, 76), (3, 2.0, 73), (5, 3.0, 76), (6, 0.5, 74), (6, 2.0, 71), (7, 2.5, 69)]
    for b, bt, n in mel:
        L.add(epiano(midi(n), 3.0, 0.6), b * bar + bt * beat, pan=0.2, gain=0.06)
    dry = lowpass(L.buf, 3600.0)
    return master(dry, reverb(dry, 2.6, 2000.0) * 0.4)


def retro():
    """Retro: 96 BPM, Puls 25 % für die Melodie, Dreieck im Bass, leise Arpeggios – ein ruhiges
    Titelbild-Stück für ein Spiel, das es nie gab. Melodie ganz eigen (D-Dur, A-B-Form)."""
    beat = 60.0 / 96.0
    bar = beat * 4
    L = Loop(bar * 16)
    prog = [[62, 66, 69], [59, 62, 66], [55, 59, 62], [57, 61, 64]] * 2 + [[55, 59, 62], [57, 61, 64], [54, 57, 61], [59, 62, 66],
                                                                         [55, 59, 62], [57, 61, 64], [50, 54, 57], [57, 61, 64]]
    bass = [38, 35, 31, 33] * 2 + [31, 33, 30, 35, 31, 33, 38, 33]
    # Melodie: (Takt, Schlag, Ton, Länge in Schlägen)
    mel = [(0, 0, 74, 1.5), (0, 1.5, 76, 0.5), (0, 2, 78, 2), (1, 0, 76, 1), (1, 1, 74, 1), (1, 2, 71, 2),
           (2, 0, 71, 1.5), (2, 1.5, 74, 0.5), (2, 2, 79, 2), (3, 0, 78, 1), (3, 1, 76, 1), (3, 2, 73, 2),
           (4, 0, 74, 1.5), (4, 1.5, 76, 0.5), (4, 2, 78, 2), (5, 0, 81, 1), (5, 1, 79, 1), (5, 2, 78, 2),
           (6, 0, 76, 1), (6, 1, 74, 1), (6, 2, 71, 1), (6, 3, 73, 1), (7, 0, 76, 3),
           (8, 0, 79, 2), (8, 2, 78, 1), (8, 3, 76, 1), (9, 0, 76, 2), (9, 2, 73, 2),
           (10, 0, 78, 2), (10, 2, 76, 1), (10, 3, 73, 1), (11, 0, 74, 3),
           (12, 0, 79, 1.5), (12, 1.5, 81, 0.5), (12, 2, 83, 2), (13, 0, 81, 1), (13, 1, 79, 1), (13, 2, 76, 2),
           (14, 0, 78, 1), (14, 1, 76, 1), (14, 2, 74, 2), (15, 0, 73, 2), (15, 2, 76, 2)]
    for b, bt, n, ln in mel:
        L.add(pulse(midi(n), ln * beat * 0.92 + 0.05, duty=0.25, decay=0.6, a=0.012, r=0.07), b * bar + bt * beat, pan=0.12, gain=0.16)
        # Echo eine Achtel später, leiser: der klassische „zweite Kanal“.
        L.add(pulse(midi(n), ln * beat * 0.9, duty=0.125, decay=1.0, a=0.01, r=0.06), b * bar + bt * beat + beat * 0.5, pan=-0.3, gain=0.05)
    for i, ch in enumerate(prog):
        for s in range(8):
            n = ch[s % 3] + (12 if s >= 6 else 0)
            L.add(pulse(midi(n), beat * 0.45, duty=0.125, decay=4.0, a=0.004, r=0.05), i * bar + s * beat / 2, pan=-0.2, gain=0.035)
        for s in range(4):
            n = bass[i] + (7 if s == 2 else 0) + (12 if s == 3 else 0)
            L.add(tri(midi(n - 12), beat * 0.85), i * bar + s * beat, gain=0.22)
    dry = lowpass(L.buf, 3400.0, 2)
    return master(dry, reverb(dry, 1.4, 2400.0) * 0.18)


def hell():
    """Minimal Hell: 66 BPM, wenige helle Klaviertöne über Dmaj7 und Gmaj7/D – viel Luft."""
    beat = 60.0 / 66.0
    bar = beat * 4
    L = Loop(bar * 8)
    chords = [[50, 57, 61, 66], [50, 55, 59, 66], [50, 57, 61, 64], [47, 54, 57, 62],
              [50, 57, 61, 66], [50, 55, 59, 64], [45, 52, 57, 61], [45, 52, 55, 61]]
    for i, ch in enumerate(chords):
        for j, n in enumerate(ch):
            L.add(piano(midi(n), 4.5), i * bar + j * 0.06, pan=-0.3 + 0.2 * j, gain=0.07)
    mel = [(0, 2, 78), (0, 3, 76), (1, 1.5, 74), (2, 2, 73), (2, 3, 76), (3, 1, 74), (4, 2, 81),
           (4, 3, 78), (5, 1.5, 76), (6, 2, 73), (6, 3, 74), (7, 1, 76)]
    for b, bt, n in mel:
        L.add(piano(midi(n), 4.0), b * bar + bt * beat, pan=0.25, gain=0.09)
    dry = lowpass(L.buf, 5000.0)
    return master(dry, reverb(dry, 3.6, 3000.0) * 0.6)


PIECES = {"ruhe": ruhe, "welle": welle, "glas": glas, "holz": holz, "abend": abend, "retro": retro, "hell": hell}

os.makedirs(OUT, exist_ok=True)
for name, fn in PIECES.items():
    if ONLY and name not in ONLY:
        continue
    y = fn()
    data = (np.clip(y.T, -1, 1) * 32767).astype("<i2").tobytes()
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
        ogg = os.path.join(OUT, name + ".ogg")
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "2",
                        "-map_metadata", "-1", ogg], check=True)
    print(name, "%.1f s" % (y.shape[1] / SR), os.path.getsize(ogg), "Bytes")
