# Aufruf: python3 tools/synth_start.py assets/sounds   (braucht numpy)
# Startklang der Startanimation (start.wav, src/ui/boot.gd), eigene Synthese in D-Dur wie alle
# Uzai-Klänge – ruhig und hochwertig, ein klarer Akkord statt Effekten (Zeiten = Konstanten in boot.gd):
#   0,35 s  ein leiser, tiefer Grund (D und A) schwillt an, während sich die Lichtlinie zieht
#   1,10 s  der Akkord, wenn die Linie steht: Dmaj9, weiche Glocken mit langem, ruhigem Nachklang,
#           leicht in die Breite gestellt
#   danach klingt alles in einem kleinen Raum aus
# Stereo, 44,1 kHz, 16 bit; Spitze -3 dBFS, vor dem Speichern auf Übersteuern geprüft.
# Deterministisch (fester Zufall): Derselbe Aufruf ergibt dieselbe Datei.
import numpy as np, wave, sys, os

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/sounds'
rng = np.random.default_rng(77)
LENGTH = 3.6
LINIE_AB = 0.35
AKKORD = 1.10

D2, A2, D3, FIS3, A3, CIS4, E4, A4 = 73.42, 110.0, 146.83, 185.0, 220.0, 277.18, 329.63, 440.0


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def place(buf, x, at):
    i = int(at * SR)
    n = min(x.shape[-1], buf.shape[-1] - i)
    if n > 0:
        buf[..., i:i + n] += x[..., :n]


def onepole_lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def bell(freq, sec, decay=1.2, ratio=2.0, index=0.35, idecay=4.0, att=0.015):
    t = t_axis(sec)
    mod = np.sin(2 * np.pi * freq * ratio * t) * index * np.exp(-t * idecay)
    return np.sin(2 * np.pi * freq * t + mod) * np.exp(-t * decay) * np.minimum(t / att, 1.0)


def grund(sec):
    # D2 und A2, weich (wenige Obertöne, Tiefpass), schwellen bis zum Akkord an und klingen mit aus.
    t = t_axis(sec)
    s = np.zeros_like(t)
    for f, amp in [(D2, 1.0), (A2, 0.55), (D3, 0.3)]:
        for d in (-0.003, 0.003):
            s += amp * (np.sin(2 * np.pi * f * (1 + d) * t) + 0.25 * np.sin(4 * np.pi * f * (1 + d) * t))
    s = onepole_lp(s / 4.0, 900.0)
    an = np.clip(t / (AKKORD - LINIE_AB), 0.0, 1.0) ** 1.8
    ab = np.exp(-np.maximum(t - (AKKORD - LINIE_AB), 0.0) / 1.1)
    return s * an * ab * 0.35


def akkord(sec):
    out = np.zeros((2, int(sec * SR)))
    for f, a, dec in [(D3, 0.5, 0.9), (A3, 0.42, 1.0), (FIS3, 0.3, 1.1), (CIS4, 0.22, 1.25), (E4, 0.2, 1.35), (A4, 0.12, 1.6)]:
        for ch, d in ((0, -0.002), (1, 0.002)):
            out[ch] += bell(f * (1 + d), sec, decay=dec) * a
    return out


def raum(x, mix=0.2):
    out = np.zeros_like(x)
    for ch in range(2):
        acc = np.zeros(x.shape[1])
        for d_ms, fb in [(29.7, 0.78), (37.1, 0.76), (41.1, 0.74), (43.7, 0.72)]:
            d = int((d_ms + ch * 1.3) * SR / 1000)
            y = np.zeros(x.shape[1])
            lp = 0.0
            for i in range(x.shape[1]):
                fbv = y[i - d] if i >= d else 0.0
                lp = lp * 0.4 + fbv * 0.6
                y[i] = x[ch, i] + lp * fb
            acc += y
        out[ch] = x[ch] * (1 - mix) + acc * mix * 0.25
    return out


def main():
    n = int(LENGTH * SR)
    buf = np.zeros((2, n))
    g = grund(LENGTH - LINIE_AB)
    place(buf, np.vstack([g * 0.98, g * 1.02]), LINIE_AB)
    place(buf, akkord(LENGTH - AKKORD), AKKORD)
    buf = raum(buf)
    t = np.arange(n) / SR
    buf *= np.clip((LENGTH - t) / 0.6, 0.0, 1.0)
    buf *= 10 ** (-3 / 20) / np.max(np.abs(buf))
    assert np.max(np.abs(buf)) <= 1.0, 'übersteuert'
    data = (np.clip(buf.T, -1, 1) * 32767).astype('<i2').tobytes()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, 'start.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(path, '%.2f s' % LENGTH)


if __name__ == '__main__':
    main()
