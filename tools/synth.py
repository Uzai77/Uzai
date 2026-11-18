# Aufruf: python tools/synth.py assets/sounds   (braucht numpy)
# Uzai-Klänge: vorab gerendert, Stereo, 44,1 kHz, 16 Bit.
import numpy as np, wave, sys, os
SR = 44100
OUT = sys.argv[1]
rng = np.random.default_rng(7)

def t_axis(sec): return np.arange(int(sec * SR)) / SR

def env_adsr(n, a, d, s, r, sus_level):
    t = np.arange(n) / SR
    e = np.zeros(n)
    a_n, d_n, r_n = int(a*SR), int(d*SR), int(r*SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e[:a_n] = np.linspace(0, 1, a_n, endpoint=False) if a_n else []
    e[a_n:a_n+d_n] = np.linspace(1, sus_level, d_n, endpoint=False)
    e[a_n+d_n:a_n+d_n+s_n] = sus_level
    e[a_n+d_n+s_n:] = np.linspace(sus_level, 0, n - (a_n+d_n+s_n))
    return e

def onepole_lp(x, fc):
    a = np.exp(-2*np.pi*fc/SR)
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1-a)*x[i] + a*acc; y[i] = acc
    return y

def bell(freq, sec, decay=3.0, ratio=3.5, index=2.2, idecay=6.0):
    t = t_axis(sec)
    mod = np.sin(2*np.pi*freq*ratio*t) * index * np.exp(-t*idecay)
    return np.sin(2*np.pi*freq*t + mod) * np.exp(-t*decay)

def pad_voice(freq, sec, detune=0.0035):
    t = t_axis(sec)
    s = np.zeros_like(t)
    for k, amp in [(1, 1.0), (2, 0.32), (3, 0.12), (4, 0.05)]:
        for d in (-detune, 0, detune):
            s += amp * np.sin(2*np.pi*freq*k*(1+d)*t + rng.uniform(0, 6.28))
    return s / 3.0

def comb(x, delay, fb, damp):
    y = np.zeros(len(x) + delay); buf_lp = 0.0
    out = np.zeros_like(x)
    for i in range(len(x)):
        d = y[i]
        buf_lp = d*(1-damp) + buf_lp*damp
        y[i+delay] = x[i] + buf_lp*fb
        out[i] = d
    return out

def allpass(x, delay, g=0.5):
    buf = np.zeros(delay); out = np.zeros_like(x); idx = 0
    for i in range(len(x)):
        b = buf[idx]; o = -x[i] + b; buf[idx] = x[i] + b*g; out[i] = o; idx = (idx+1) % delay
    return out

def reverb(x, size=1.0, damp=0.35, seed=0):
    combs = [1557, 1617, 1491, 1422, 1277, 1356]
    off = 23 * seed
    y = sum(comb(x, int((c+off)*size), 0.80, damp) for c in combs) / len(combs)
    for a in (225+off//2, 556+off, 441+off):
        y = allpass(y, a)
    return y

def place(dst, src, at):
    i = int(at*SR); n = min(len(src), len(dst)-i)
    if n > 0: dst[i:i+n] += src[:n]

def stereo_mix(dry_l, dry_r, wet=0.28, size=1.0):
    wl = reverb(dry_l, size, seed=0); wr = reverb(dry_r, size, seed=1)
    return dry_l + wet*wl, dry_r + wet*wr

def save(name, l, r, peak_db=-1.5):
    st = np.stack([l, r], axis=1)
    m = np.max(np.abs(st)) or 1.0
    st = st / m * (10**(peak_db/20))
    # sanft ein- und ausblenden gegen Knacken
    fade = min(len(st)//4, int(0.006*SR))
    st[:fade] *= np.linspace(0, 1, fade)[:, None]
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    data = (st * 32767).astype('<i2').tobytes()
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
    print(name, round(len(l)/SR, 2), 's')

def pan(x, p):  # p: -1 links, +1 rechts
    return x*np.cos((p+1)*np.pi/4), x*np.sin((p+1)*np.pi/4)

# --- Start ------------------------------------------------------------------------
def boot():
    L = 4.8; n = int(L*SR)
    l = np.zeros(n); r = np.zeros(n)
    # 1) Luft: gefiltertes Rauschen, das bis zum Schlag anschwillt
    nz = rng.standard_normal(int(0.95*SR))
    sw = onepole_lp(nz, 900) - onepole_lp(nz, 180)
    e = np.linspace(0, 1, len(sw))**2.6
    sw *= e * 0.55
    a, b = pan(sw, -0.3); place(l, a, 0.0); place(r, b * 0.9, 0.0)
    a, b = pan(onepole_lp(rng.standard_normal(len(sw)), 1400) * e * 0.18, 0.4); place(l, a, 0.0); place(r, b, 0.0)
    hit = 0.82
    # 2) Bass-Schlag mit fallender Tonhöhe
    t = t_axis(1.6)
    f = 38 + 50*np.exp(-t*18)
    thump = np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-t*4.2) * 1.1
    click = rng.standard_normal(len(t)) * np.exp(-t*220) * 0.25
    place(l, thump + click, hit); place(r, thump + click, hit)
    # 3) Glockenakkord (D-Dur mit None) beim Erscheinen des Punkts
    chord = [(293.66, -0.5, 0.0), (440.0, 0.3, 0.025), (587.33, -0.2, 0.05), (739.99, 0.55, 0.075), (1108.73, -0.45, 0.1), (1318.51, 0.35, 0.13)]
    for fr, p, dl in chord:
        bl = bell(fr, 3.4, decay=1.25, ratio=3.5, index=1.6, idecay=5.0) * 0.22
        a, b = pan(bl, p); place(l, a, hit + dl); place(r, b, hit + dl)
    # 4) Warme Fläche
    for fr, p in [(73.42, 0), (146.83, -0.3), (220.0, 0.3), (277.18, -0.15), (369.99, 0.2)]:
        v = pad_voice(fr, 3.6)
        v = onepole_lp(v, 1800) * env_adsr(len(v), 0.55, 0.6, 0.65, 1.8, 0.7) * 0.11
        a, b = pan(v, p); place(l, a, hit - 0.08); place(r, b, hit - 0.08)
    # 5) Glitzer beim Schriftzug
    for i, (fr, p) in enumerate([(2349.32, -0.6), (2959.96, 0.5), (3520.0, -0.2), (4434.92, 0.7)]):
        sp = bell(fr, 1.4, decay=3.5, ratio=2.0, index=0.8, idecay=9) * 0.06
        a, b = pan(sp, p); place(l, a, 1.45 + i*0.07); place(r, b, 1.45 + i*0.07)
    l, r = stereo_mix(l, r, wet=0.42, size=1.25)
    # Ende ausblenden
    tail = int(1.0*SR); e = np.linspace(1, 0, tail)**1.5
    l[-tail:] *= e; r[-tail:] *= e
    save('boot', l, r, -1.0)

# --- Oberfläche -------------------------------------------------------------------
# Ab 0.5.1: leiser, weicher, gläserner. Jeder Klang hat einen sanften Anstieg (kein Knacken),
# kurze Hallfahne und liegt deutlich unter der Musik.
def soft(freq, sec, attack=0.004, decay=20.0, h2=0.15, h3=0.0):
    t = t_axis(sec)
    e = np.minimum(t/attack, 1.0) * np.exp(-t*decay)
    return (np.sin(2*np.pi*freq*t) + h2*np.sin(2*np.pi*2*freq*t) + h3*np.sin(2*np.pi*3*freq*t)) * e

def glide(f0, f1, sec, attack=0.003, decay=20.0):
    t = t_axis(sec)
    f = f0 + (f1 - f0) * np.minimum(t/0.06, 1.0)
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.minimum(t/attack, 1.0) * np.exp(-t*decay)

def air(sec, lo, hi, amp):
    t = t_axis(sec); nz = rng.standard_normal(len(t))
    return (onepole_lp(nz, hi) - onepole_lp(nz, lo)) * np.sin(np.pi*t/sec)**2 * amp

def click(amp=0.2, fc=6000):
    t = t_axis(0.012)
    return onepole_lp(rng.standard_normal(len(t)), fc) * np.exp(-t*900) * amp

def ui():
    # 0.6.3: alles in D-Dur (wie der Start), weichere Glocken (harmonisches FM, kleiner Index),
    # weniger Rauschen, Lautheit nach Rolle gestaffelt.
    m = onepole_lp(soft(554.37, 0.09, 0.006, 48, 0.08) + soft(831.61, 0.09, 0.005, 70, 0.0) * 0.18, 1800)
    l, r = stereo_mix(m, m, 0.05, 0.4); save('move', l, r, -20)
    k = onepole_lp(soft(987.77, 0.06, 0.003, 80, 0.05), 2600)
    l, r = stereo_mix(k, k, 0.04, 0.35); save('tick', l, r, -20.5)
    # Rand: D3 mit kräftigen Obertönen, damit es auch aus TV-Lautsprechern als weicher Tupfer ankommt
    bmp = onepole_lp(soft(146.83, 0.15, 0.008, 30, 0.6, 0.22), 900)
    l, r = stereo_mix(bmp, bmp, 0.04, 0.4); save('bump', l, r, -19)
    s = np.zeros(int(0.5*SR))
    place(s, soft(587.33, 0.35, 0.006, 17, 0.2) * 0.4, 0)
    place(s, soft(880.0, 0.4, 0.005, 14, 0.15) * 0.34, 0.045)
    place(s, soft(1760.0, 0.3, 0.004, 22, 0.0) * 0.04, 0.045)
    s = onepole_lp(s, 3000)
    l, r = stereo_mix(*pan(s, -0.04), 0.16, 0.7); save('select', l, r, -14)
    s = np.zeros(int(0.45*SR))
    place(s, soft(880.0, 0.35, 0.004, 18, 0.15) * 0.4, 0)
    place(s, soft(659.25, 0.35, 0.004, 17, 0.15) * 0.4, 0.042)
    s = onepole_lp(s, 2800)
    l, r = stereo_mix(s, s, 0.14, 0.6); save('back', l, r, -14.5)
    s = np.zeros(int(0.45*SR))
    place(s, glide(440, 739.99, 0.3, 0.004, 20) * 0.45, 0)
    place(s, bell(1318.51, 0.35, decay=14, ratio=2, index=0.25, idecay=30) * 0.14, 0.03)
    s = onepole_lp(s, 3200)
    l, r = stereo_mix(*pan(s, 0.05), 0.18, 0.6); save('open', l, r, -15)
    s = np.zeros(int(0.3*SR))
    place(s, click(0.06, 2400), 0)
    place(s, soft(1318.51, 0.25, 0.004, 24, 0.15) * 0.35, 0.006)
    l, r = stereo_mix(s, s, 0.1, 0.45); save('toggle_on', l, r, -16.5)
    s = np.zeros(int(0.3*SR))
    place(s, click(0.05, 2000), 0)
    place(s, soft(987.77, 0.22, 0.004, 28, 0.12) * 0.33, 0.006)
    l, r = stereo_mix(s, s, 0.1, 0.45); save('toggle_off', l, r, -16)
    # Bereich: weicher Wisch, Rauschen nur 400-1600 Hz, danach Tiefpass
    s = air(0.2, 400, 1600, 0.2)
    place(s, soft(739.99, 0.2, 0.005, 16, 0.2) * 0.3, 0.02)
    s = onepole_lp(s, 2600)
    l, r = stereo_mix(*pan(s, 0.0), 0.14, 0.6); save('tab', l, r, -16.5)
    # Guide: Dmaj9 statt Cmaj9, Glanz harmonisch (ratio 2), weniger Luft
    s = np.zeros(int(1.3*SR))
    for i, f in enumerate([293.66, 369.99, 440.0, 554.37, 659.25]):
        v = soft(f, 1.2, 0.035, 3.6, 0.28, 0.06) * 0.2
        place(s, onepole_lp(v, 2600), i*0.026)
    place(s, bell(1318.51, 0.9, decay=5, ratio=2, index=0.4, idecay=10) * 0.06, 0.13)
    place(s, air(0.3, 500, 2200, 0.12), 0)
    l, r = stereo_mix(*pan(s, 0.0), 0.32, 1.0); save('guide', l, r, -13)
    s = np.zeros(int(0.65*SR))
    for i, f in enumerate([659.25, 554.37, 440.0]):
        place(s, onepole_lp(soft(f, 0.5, 0.01, 8, 0.2) * 0.22, 2400), i*0.032)
    place(s, air(0.22, 400, 1800, 0.1), 0)
    l, r = stereo_mix(*pan(s, 0.0), 0.26, 0.8); save('guide_close', l, r, -16)
    # Mitteilung: zwei runde Glastöne (A5, E6), harmonisch, kürzer und leiser
    s = np.zeros(int(0.9*SR))
    place(s, bell(880.0, 0.8, decay=6.0, ratio=2, index=0.45, idecay=12) * 0.3, 0)
    place(s, bell(1318.51, 0.8, decay=5.5, ratio=2, index=0.4, idecay=12) * 0.24, 0.1)
    s = onepole_lp(s, 4000)
    l, r = stereo_mix(*pan(s, 0.1), 0.26, 0.9); save('notify', l, r, -12.5)
    # Fehler: A3 -> F#3 (kleine Terz nach unten, in der Tonart), leiser
    s = np.zeros(int(0.5*SR))
    place(s, onepole_lp(soft(220.0, 0.2, 0.005, 14, 0.4, 0.12), 1300) * 0.4, 0)
    place(s, onepole_lp(soft(185.0, 0.25, 0.005, 12, 0.4, 0.12), 1300) * 0.4, 0.14)
    l, r = stereo_mix(s, s, 0.12, 0.5); save('error', l, r, -13)
    # Spielstart: D-Dur-Arpeggio, weichere Glocken, Rauschanstieg dunkler
    s = np.zeros(int(1.6*SR))
    for i, f in enumerate([293.66, 369.99, 440.0, 587.33, 739.99]):
        place(s, bell(f, 1.2, decay=3.6, ratio=2, index=0.6) * 0.2, i*0.06)
    t = t_axis(0.8); nz = rng.standard_normal(len(t))
    place(s, (onepole_lp(nz, 1600) - onepole_lp(nz, 300)) * (t/0.8)**2 * 0.14, 0.0)
    s = onepole_lp(s, 4500)
    l, r = stereo_mix(*pan(s, 0.0), 0.35, 1.0); save('launch', l, r, -8)
    # Erfolg: D5-F#5-A5-D6, harmonische Glocken plus warme Fläche darunter
    s = np.zeros(int(1.6*SR))
    for i, f in enumerate([587.33, 739.99, 880.0, 1174.66]):
        place(s, bell(f, 1.3, decay=3.0, ratio=2, index=0.7) * 0.22, i*0.07)
    for f in (293.66, 440.0):
        place(s, onepole_lp(soft(f, 1.3, 0.06, 2.8, 0.25), 1500) * 0.12, 0.0)
    s = onepole_lp(s, 4500)
    l, r = stereo_mix(*pan(s, 0.0), 0.35, 1.0); save('achievement', l, r, -8)
    # Bildschirmfoto: Verschluss, dunkler
    t = t_axis(0.25); nz = rng.standard_normal(len(t))
    c = onepole_lp(onepole_lp(nz, 4500), 4500) * (np.exp(-t*80) + 0.6*np.exp(-np.maximum(t-0.07, 0)*90)*(t > 0.07)) * 0.6
    l, r = stereo_mix(c, c, 0.1, 0.4); save('shutter', l, r, -12)


os.makedirs(OUT, exist_ok=True)
ui()
if '--ohne-start' not in sys.argv:
    boot()
