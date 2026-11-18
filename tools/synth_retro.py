# Aufruf: python tools/synth_retro.py tools/themes/retro/klaenge   (braucht numpy)
# Klänge des eingebauten Themes „Retro“: weiche Rechteck- und Pulswellen wie auf alten Konsolen,
# aber gerundet (Tiefpass, kurze Hüllkurven ohne Klick) und leise – wie die Uzai-Klänge in D-Dur.
# Mono, 22,05 kHz, 16 Bit: winzig im Paket.
import numpy as np, wave, sys, os
SR = 22050
OUT = sys.argv[1]

def t_axis(sec): return np.arange(int(sec * SR)) / SR

def pulse(freq, sec, duty=0.5):
    t = t_axis(sec)
    ph = (t * freq) % 1.0
    return np.where(ph < duty, 1.0, -1.0)

def env(n, a=0.004, r=0.04, hold=0.0):
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0)
    tail = np.clip((n / SR - t) / max(r, 1e-4), 0.0, 1.0)
    return e * tail

def lowpass(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    return y

def note(f, sec, duty=0.5, decay=18.0, vol=1.0):
    x = pulse(f, sec, duty)
    t = t_axis(sec)
    return x * np.exp(-t * decay) * env(len(x), 0.003, min(0.03, sec * 0.4)) * vol

def seq(notes, gap, sec, **kw):
    total = gap * (len(notes) - 1) + sec
    out = np.zeros(int(total * SR) + 1)
    for i, f in enumerate(notes):
        s = note(f, sec, **kw)
        k = int(i * gap * SR)
        out[k:k + len(s)] += s
    return out

D5, Fs5, A5, D6, Fs6, A6 = 587.33, 739.99, 880.0, 1174.66, 1479.98, 1760.0
A4, D4, Fs4, A3, D3 = 440.0, 293.66, 369.99, 220.0, 146.83

SOUNDS = {
    "move": lambda: note(A5, 0.045, 0.25, 60.0, 0.55),
    "tick": lambda: note(D6, 0.03, 0.25, 80.0, 0.4),
    "bump": lambda: note(A3, 0.08, 0.5, 30.0, 0.7),
    "select": lambda: seq([D5, A5], 0.055, 0.11, duty=0.25, decay=16.0),
    "back": lambda: seq([A5, D5], 0.05, 0.1, duty=0.25, decay=18.0),
    "open": lambda: seq([D5, Fs5, A5], 0.04, 0.1, duty=0.25, decay=16.0, vol=0.8),
    "toggle_on": lambda: seq([Fs5, D6], 0.04, 0.08, duty=0.5, decay=22.0, vol=0.7),
    "toggle_off": lambda: seq([D6, Fs5], 0.04, 0.08, duty=0.5, decay=22.0, vol=0.7),
    "tab": lambda: seq([A4, D5], 0.03, 0.07, duty=0.125, decay=26.0, vol=0.8),
    "guide": lambda: seq([D5, Fs5, A5, D6], 0.06, 0.22, duty=0.25, decay=8.0, vol=0.7),
    "guide_close": lambda: seq([D6, A5, Fs5], 0.05, 0.14, duty=0.25, decay=12.0, vol=0.6),
    "notify": lambda: seq([A5, D6], 0.09, 0.25, duty=0.5, decay=9.0, vol=0.5),
    "error": lambda: seq([D4, D4], 0.12, 0.09, duty=0.5, decay=14.0, vol=0.6),
    "launch": lambda: seq([D5, Fs5, A5, D6, Fs6, A6], 0.06, 0.3, duty=0.25, decay=7.0, vol=0.55),
}

os.makedirs(OUT, exist_ok=True)
for name, fn in SOUNDS.items():
    x = lowpass(fn(), 3200.0)
    x = lowpass(x, 5200.0)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * 0.42
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
    print(name, len(data), "Bytes")
