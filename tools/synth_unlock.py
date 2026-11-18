# Aufruf: python tools/synth_unlock.py assets/sounds   (braucht numpy)
# Klänge der Erfolgs-Pop-ups (unlock, unlock_rare, unlock_retro): eigene Klänge, in D-Dur wie
# alle Uzai-Klänge (siehe tools/synth.py). Aufbau jeweils passend zur Bewegung des Pop-ups:
#   0,00 s  weicher, runder „Plopp“, wenn der Kreis aufspringt
#   0,08 s  erster Glockenton, wenn der Lichtring ausläuft
#   0,20 s  zweiter, hellerer Ton (eine Quarte höher), wenn sich die Pille öffnet
#   danach  ein leiser Schimmer aus hohen, harmonischen Teiltönen und etwas Raum
# Selten: drei Töne nach oben, längerer, goldener Schimmer (eine kleine Kaskade hoher Glocken).
# Retro: dieselbe Geste mit weichen Rechteck-Tönen (nur ungerade Obertöne, gerundet) und einem
# kurzen Arpeggio – erinnert an alte Konsolen, ohne zu piepsen.
# Normiert auf -8 dBFS Spitze, ohne Übersteuern (Spitze wird vor dem Speichern geprüft).
import numpy as np, wave, sys, os

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/sounds'
rng = np.random.default_rng(11)


def t_axis(sec): return np.arange(int(sec * SR)) / SR


def onepole_lp(x, fc):
    # einfache Tiefpass-Rundung (vektorisiert über lfilter-ähnliche Rekursion in Blöcken)
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    return y


def bell(freq, sec, decay=3.0, ratio=2.0, index=0.7, idecay=8.0, attack=0.004):
    """FM-Glocke mit ganzzahligem Verhältnis: harmonisch, keine schiefen Obertöne."""
    t = t_axis(sec)
    mod = np.sin(2 * np.pi * freq * ratio * t) * index * np.exp(-t * idecay)
    env = np.minimum(t / attack, 1.0) * np.exp(-t * decay)
    return np.sin(2 * np.pi * freq * t + mod) * env


def softsquare(freq, sec, decay=4.0, attack=0.006, harmonics=(1, 3, 5, 7)):
    """Rechteck aus wenigen ungeraden Obertönen, nach oben schnell leiser: rund statt spitz."""
    t = t_axis(sec)
    s = np.zeros_like(t)
    for h in harmonics:
        s += np.sin(2 * np.pi * freq * h * t) / h * np.exp(-t * decay * (1 + 0.5 * (h - 1)))
    env = np.minimum(t / attack, 1.0) * np.exp(-t * decay)
    return s * env


def pop(sec=0.12, f0=180.0, f1=420.0, amount=1.0):
    """Runder Plopp: Sinus, der schnell nach oben gleitet, ohne Klick."""
    t = t_axis(sec)
    f = f1 - (f1 - f0) * np.exp(-t * 38.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    env = np.minimum(t / 0.003, 1.0) * np.exp(-t * 30.0)
    return np.sin(ph) * env * amount


def breath(sec, lo=2500, hi=7000, amount=0.04):
    """Hauch: gefiltertes Rauschen, das an- und abschwillt (der ‚Schimmer‘ unter den Tönen)."""
    n = int(sec * SR)
    nz = rng.standard_normal(n)
    band = onepole_lp(nz, hi) - onepole_lp(nz, lo)
    t = np.arange(n) / SR
    env = (1 - np.exp(-t * 14)) * np.exp(-t * 3.2)
    return band * env * amount


def place(dst, src, at, gain=1.0):
    i = int(at * SR); n = min(len(src), len(dst) - i)
    if n > 0: dst[i:i + n] += src[:n] * gain


def comb(x, delay, fb, damp):
    y = np.zeros(len(x) + delay); lp = 0.0
    out = np.zeros_like(x)
    for i in range(len(x)):
        d = y[i]; lp = d * (1 - damp) + lp * damp
        y[i + delay] = x[i] + lp * fb; out[i] = d
    return out


def allpass(x, delay, g=0.5):
    buf = np.zeros(delay); out = np.zeros_like(x); idx = 0
    for i in range(len(x)):
        b = buf[idx]; o = -x[i] + b; buf[idx] = x[i] + b * g; out[i] = o; idx = (idx + 1) % delay
    return out


def reverb(x, size=1.0, damp=0.4, seed=0):
    combs = [1557, 1617, 1491, 1422, 1277, 1356]
    off = 23 * seed
    y = sum(comb(x, int((c + off) * size), 0.80, damp) for c in combs) / len(combs)
    for a in (225 + off // 2, 556 + off, 441 + off):
        y = allpass(y, a)
    return y


def pan(x, p):
    return x * np.cos((p + 1) * np.pi / 4), x * np.sin((p + 1) * np.pi / 4)


def stereo(parts, n, wet=0.3, size=1.0):
    l = np.zeros(n); r = np.zeros(n)
    for sig, at, p in parts:
        a, b = pan(sig, p); place(l, a, at); place(r, b, at)
    wl = reverb(l, size, seed=0); wr = reverb(r, size, seed=1)
    return l + wet * wl, r + wet * wr


def save(name, l, r, peak_db=-8.0):
    st = np.stack([l, r], axis=1)
    m = np.max(np.abs(st)) or 1.0
    st = st / m * (10 ** (peak_db / 20))
    fade = int(0.006 * SR)
    st[:fade] *= np.linspace(0, 1, fade)[:, None]
    tail = int(0.08 * SR)
    st[-tail:] *= np.linspace(1, 0, tail)[:, None] ** 2
    assert np.max(np.abs(st)) < 0.99, 'übersteuert'
    data = (st * 32767).astype('<i2').tobytes()
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
    rms = 20 * np.log10(np.sqrt(np.mean(st ** 2)) + 1e-9)
    print(f'{name}: {len(l) / SR:.2f} s, Spitze {20 * np.log10(np.max(np.abs(st))):.1f} dBFS, RMS {rms:.1f} dBFS')


D4, Fs4, A4, D5, E5, Fs5, A5, B5, D6, E6, Fs6, A6, D7 = 293.66, 369.99, 440.0, 587.33, 659.25, 739.99, 880.0, 987.77, 1174.66, 1318.51, 1479.98, 1760.0, 2349.32


def unlock():
    L = 1.5; n = int(L * SR)
    parts = [
        (onepole_lp(pop(0.14, 190, 440), 2200) * 0.55, 0.0, 0.0),
        # zwei Glocken: A5, dann D6 (Quarte nach oben) – heller und länger
        (bell(A5, 1.2, decay=4.2, index=0.55) * 0.42, 0.08, -0.12),
        (bell(D6, 1.4, decay=3.1, index=0.6) * 0.40, 0.20, 0.12),
        # warmer Grund: D4 + A4, sehr leise, damit es nicht dünn klingt
        (onepole_lp(bell(D4, 1.3, decay=2.6, index=0.2), 1400) * 0.20, 0.08, 0.0),
        (onepole_lp(bell(A4, 1.3, decay=3.0, index=0.2), 1600) * 0.12, 0.20, 0.0),
        # Schimmer: F#6 und A6 ganz leise, dazu ein Hauch
        (bell(Fs6, 1.0, decay=4.5, index=0.3) * 0.07, 0.30, -0.4),
        (bell(A6, 1.0, decay=5.0, index=0.3) * 0.055, 0.36, 0.4),
        (breath(1.0, 3000, 8000, 0.05), 0.22, 0.0),
    ]
    l, r = stereo(parts, n, wet=0.32, size=1.0)
    l = onepole_lp(l, 7500); r = onepole_lp(r, 7500)
    save('unlock', l, r, -8.0)


def unlock_rare():
    L = 2.1; n = int(L * SR)
    parts = [
        (onepole_lp(pop(0.16, 160, 400, 1.0), 2000) * 0.6, 0.0, 0.0),
        # drei Töne nach oben: D6 – F#6 – A6, mit breiterem Grund (D-Dur über zwei Oktaven)
        (bell(D6, 1.4, decay=3.0, index=0.6) * 0.38, 0.08, -0.2),
        (bell(Fs6, 1.5, decay=2.8, index=0.6) * 0.34, 0.19, 0.15),
        (bell(A6, 1.8, decay=2.2, index=0.65) * 0.34, 0.30, 0.0),
        (onepole_lp(bell(D4, 1.9, decay=1.8, index=0.25), 1300) * 0.26, 0.08, 0.0),
        (onepole_lp(bell(A4, 1.8, decay=2.0, index=0.2), 1500) * 0.16, 0.19, 0.0),
        (onepole_lp(bell(Fs5, 1.6, decay=2.2, index=0.2), 2200) * 0.10, 0.30, 0.0),
        (breath(1.6, 3500, 9000, 0.06), 0.28, 0.0),
    ]
    # goldene Kaskade: kleine, schnelle Glocken über die Töne der Tonart nach oben, leiser werdend
    casc = [D6, E6, Fs6, A6, B5 * 2, D7]
    for i, f in enumerate(casc):
        parts.append((bell(f, 0.7, decay=6.5, index=0.35, idecay=14) * (0.10 - i * 0.012), 0.52 + i * 0.055, -0.6 + i * 0.24))
    l, r = stereo(parts, n, wet=0.38, size=1.15)
    l = onepole_lp(l, 8000); r = onepole_lp(r, 8000)
    save('unlock_rare', l, r, -7.5)


def unlock_retro():
    L = 1.5; n = int(L * SR)
    parts = [
        (onepole_lp(pop(0.12, 220, 520, 0.9), 2400) * 0.5, 0.0, 0.0),
        # kurzes Arpeggio D5-F#5-A5 als weiche Rechtecke, dann D6 lang (wie ein „Level geschafft“)
        (onepole_lp(softsquare(D5, 0.12, decay=14), 3200) * 0.22, 0.07, -0.25),
        (onepole_lp(softsquare(Fs5, 0.12, decay=14), 3200) * 0.22, 0.12, 0.0),
        (onepole_lp(softsquare(A5, 0.12, decay=14), 3200) * 0.22, 0.17, 0.25),
        (onepole_lp(softsquare(D6, 1.0, decay=3.6), 3600) * 0.30, 0.23, 0.0),
        # eine echte Glocke darunter, damit es zu den anderen Uzai-Klängen passt
        (bell(D6, 1.1, decay=3.4, index=0.4) * 0.16, 0.23, 0.0),
        (onepole_lp(bell(D4, 1.1, decay=2.8, index=0.2), 1300) * 0.16, 0.07, 0.0),
        (breath(0.8, 2500, 6500, 0.03), 0.25, 0.0),
    ]
    l, r = stereo(parts, n, wet=0.26, size=0.8)
    l = onepole_lp(l, 6500); r = onepole_lp(r, 6500)
    save('unlock_retro', l, r, -8.5)


os.makedirs(OUT, exist_ok=True)
unlock()
unlock_rare()
unlock_retro()
