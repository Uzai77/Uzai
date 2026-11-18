# Aufruf: python tools/synth_power.py assets/sounds   (braucht numpy)
# Ausschaltklang (power_off.wav): das Gegenstück zum Startklang (tools/synth.py, boot), in D-Dur
# wie alle Uzai-Klänge. Läuft im Takt der Ausschalt-Animation (src/ui/power_off.gd):
#   0,00 s  warme Glocken fallen in einem Dreiklang abwärts (Fis – D – A – D), die Oberfläche
#           tritt zurück
#   0,05 s  eine leise Fläche aus D und A trägt sie und klingt mit aus
#   0,62 s  das Zeichen fällt zu einer Linie zusammen: ein weicher, tiefer Ton gleitet abwärts,
#           dazu ein Hauch Luft, der dunkler wird (wie eine Röhre, die ausgeht – nur sanft)
#   1,25 s  vorbei (kurzer Raum, sanft ausgeblendet; bis zum Ende der Animation ist Stille)
# Normiert auf -3 dBFS Spitze; vor dem Speichern wird auf Übersteuern geprüft.
import numpy as np, wave, sys, os

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/sounds'
rng = np.random.default_rng(23)
LENGTH = 1.25
COLLAPSE = 0.62


def t_axis(sec): return np.arange(int(sec * SR)) / SR


def onepole_lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    return y


def sweep_lp(x, f0, f1):
    # Tiefpass, dessen Grenze von f0 nach f1 wandert (exponentiell)
    y = np.empty_like(x); acc = 0.0
    n = len(x)
    for i in range(n):
        fc = f0 * (f1 / f0) ** (i / max(n - 1, 1))
        a = np.exp(-2 * np.pi * fc / SR)
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    return y


def bell(freq, sec, decay=3.0, ratio=3.5, index=1.0, idecay=7.0):
    t = t_axis(sec)
    mod = np.sin(2 * np.pi * freq * ratio * t) * index * np.exp(-t * idecay)
    att = np.minimum(t / 0.004, 1.0)
    return np.sin(2 * np.pi * freq * t + mod) * np.exp(-t * decay) * att


def pad_voice(freq, sec, detune=0.003):
    t = t_axis(sec)
    s = np.zeros_like(t)
    for k, amp in [(1, 1.0), (2, 0.28), (3, 0.08)]:
        for d in (-detune, 0, detune):
            s += amp * np.sin(2 * np.pi * freq * k * (1 + d) * t + rng.uniform(0, 6.28))
    return s / 3.0


def comb(x, delay, fb, damp):
    y = np.zeros(len(x) + delay); buf_lp = 0.0
    out = np.zeros_like(x)
    for i in range(len(x)):
        d = y[i]
        buf_lp = d * (1 - damp) + buf_lp * damp
        y[i + delay] = x[i] + buf_lp * fb
        out[i] = d
    return out


def allpass(x, delay, g=0.5):
    buf = np.zeros(delay); out = np.zeros_like(x); idx = 0
    for i in range(len(x)):
        b = buf[idx]; o = -x[i] + b; buf[idx] = x[i] + b * g; out[i] = o; idx = (idx + 1) % delay
    return out


def reverb(x, size=1.0, damp=0.4, seed=0):
    combs = [1557, 1617, 1491, 1422, 1277, 1356]
    off = 23 * seed
    y = sum(comb(x, int((c + off) * size), 0.74, damp) for c in combs) / len(combs)
    for a in (225 + off // 2, 556 + off, 441 + off):
        y = allpass(y, a)
    return y


def place(dst, src, at):
    i = int(at * SR); n = min(len(src), len(dst) - i)
    if n > 0: dst[i:i + n] += src[:n]


def pan(x, p):
    return x * np.cos((p + 1) * np.pi / 4), x * np.sin((p + 1) * np.pi / 4)


def power_off():
    n = int(LENGTH * SR)
    l = np.zeros(n); r = np.zeros(n)
    # 1) Glocken abwärts: Fis5, D5, A4, D4 – weich (kleiner Modulationsindex), die tiefste trägt.
    notes = [(739.99, 0.45, 0.00, 0.13), (587.33, -0.3, 0.085, 0.15), (440.0, 0.25, 0.17, 0.17), (293.66, -0.1, 0.27, 0.21)]
    for fr, p, at, amp in notes:
        b = bell(fr, LENGTH - at, decay=3.4, ratio=2.0, index=0.7, idecay=9.0) * amp
        b = onepole_lp(b, 3200)
        a, c = pan(b, p); place(l, a, at); place(r, c, at)
    # 2) Warme Fläche aus D3 und A3, schwillt kurz an und klingt mit aus.
    for fr, p in [(146.83, -0.2), (220.0, 0.2), (293.66, 0.0)]:
        v = pad_voice(fr, LENGTH - 0.05)
        t = t_axis(LENGTH - 0.05)
        env = np.minimum(t / 0.12, 1.0) * np.exp(-t * 2.6)
        v = onepole_lp(v, 1400) * env * 0.075
        a, c = pan(v, p); place(l, a, 0.05); place(r, c, 0.05)
    # 3) Zusammenfallen: tiefer Ton gleitet von D3 nach D2 hinab, weich angesetzt.
    sec = LENGTH - COLLAPSE
    t = t_axis(sec)
    f = 73.42 + (146.83 - 73.42) * np.exp(-t * 6.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    env = np.minimum(t / 0.03, 1.0) * np.exp(-t * 5.5)
    low = (np.sin(ph) + 0.18 * np.sin(2 * ph)) * env * 0.20
    place(l, low, COLLAPSE); place(r, low, COLLAPSE)
    # dazu ein Hauch Luft, der dunkler wird
    nz = rng.standard_normal(len(t))
    air = sweep_lp(sweep_lp(nz, 1600, 140), 1600, 140) * np.minimum(t / 0.02, 1.0) * np.exp(-t * 7.0) * 0.16
    a, c = pan(air, -0.15); place(l, a, COLLAPSE); place(r, c * 0.9, COLLAPSE)
    # 4) Raum, dann sanft ausblenden (Ende in Stille).
    wl = reverb(l, 1.0, seed=0); wr = reverb(r, 1.0, seed=1)
    l = l + 0.30 * wl; r = r + 0.30 * wr
    tail = int(0.38 * SR); e = np.linspace(1, 0, tail) ** 1.8
    l[-tail:] *= e; r[-tail:] *= e
    save('power_off', l, r, -3.0)


def save(name, l, r, peak_db):
    st = np.stack([l, r], axis=1)
    st -= st.mean(axis=0)
    m = np.max(np.abs(st)) or 1.0
    st = st / m * (10 ** (peak_db / 20))
    fade = int(0.006 * SR)
    st[:fade] *= np.linspace(0, 1, fade)[:, None]
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    peak = np.max(np.abs(st))
    assert peak < 0.999, 'übersteuert'
    data = (np.round(st * 32767)).astype('<i2').tobytes()
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
    print(name, round(len(l) / SR, 2), 's, Spitze %.1f dBFS' % (20 * np.log10(peak)))


os.makedirs(OUT, exist_ok=True)
power_off()
