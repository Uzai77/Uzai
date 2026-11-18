#!/usr/bin/env python3
"""Eigene, nahtlos kachelbare PBR-Karten für das Zimmer backen (Albedo, Normal, Rauheit).

Alles hier entsteht aus Rauschen (FFT, periodisch – darum ohne Naht), nichts ist fremd. Die Karten
liegen fertig unter assets/zimmer/tex/ und werden von src/room/stoffe.gd geladen; der Fragment-Shader
rechnet dann keine Rauschfunktionen mehr, sondern liest Normal- und Rauheitskarten wie jedes Spiel.

    python3 tools/zimmer_texturen.py [zielordner]        (Standard: assets/zimmer/tex)

Braucht numpy und Pillow. Feste Startwerte: jeder Lauf erzeugt dieselben Bilder.
"""
import os
import sys

import numpy as np
from PIL import Image

ZIEL = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "zimmer", "tex")


def rauschen(n, beta=1.8, seed=1, aniso=1.0):
    """Periodisches 1/f^beta-Rauschen (0…1), aniso > 1: in x gestreckt (Fasern)."""
    rng = np.random.default_rng(seed)
    weiss = rng.standard_normal((n, n))
    f = np.fft.fft2(weiss)
    fy = np.fft.fftfreq(n)[:, None]
    fx = np.fft.fftfreq(n)[None, :] * aniso
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    f = f / (r ** (beta * 0.5))
    f[0, 0] = 0.0
    h = np.real(np.fft.ifft2(f))
    h = (h - h.min()) / (h.max() - h.min() + 1e-9)
    return h


def zellen(n, zahl, seed=3, jitter=0.9):
    """Worley-Abstände (nächster und zweitnächster Punkt, 0…1 in Zellbreiten), periodisch: je
    Bildpunkt nur die eigene und die acht Nachbarzellen."""
    rng = np.random.default_rng(seed)
    g = n / zahl
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    jx = (rng.random((zahl, zahl)) - 0.5) * jitter
    jy = (rng.random((zahl, zahl)) - 0.5) * jitter
    cx = np.floor(xs / g).astype(int)
    cy = np.floor(ys / g).astype(int)
    best = np.full((n, n), 1e9, np.float32)
    zweit = np.full((n, n), 1e9, np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            ix = (cx + ox) % zahl
            iy = (cy + oy) % zahl
            px = (cx + ox + 0.5 + jx[iy, ix]) * g
            py = (cy + oy + 0.5 + jy[iy, ix]) * g
            d = np.sqrt((xs - px) ** 2 + (ys - py) ** 2)
            m = d < best
            zweit = np.where(m, best, np.minimum(zweit, d))
            best = np.where(m, d, best)
    return best / g, zweit / g


def normal_aus_hoehe(h, staerke=1.0):
    """Tangentraum-Normalkarte (OpenGL-Y-Konvention, wie Godot) aus einer Höhe 0…1."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * h.shape[1]
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * h.shape[0]
    nx = -dx * staerke
    ny = dy * staerke
    nz = np.ones_like(h) * 64.0
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], axis=-1)
    return (n * 0.5 + 0.5)


def speichern(name, farbe, normal, rau, q=(86, 84, 82), normal_n=0, farbe_an=True):
    """Karten als JPEG; normal_n > 0 verkleinert die Normalkarte (feine Muster brauchen keine 1K)."""
    os.makedirs(ZIEL, exist_ok=True)
    if farbe_an:
        f8 = (np.clip(farbe, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(f8, "RGB").save(os.path.join(ZIEL, name + "_farbe.jpg"), quality=q[0], subsampling=0)
    n8 = (np.clip(normal, 0, 1) * 255).astype(np.uint8)
    nimg = Image.fromarray(n8, "RGB")
    if normal_n and normal_n < nimg.size[0]:
        nimg = nimg.resize((normal_n, normal_n), Image.LANCZOS)
    nimg.save(os.path.join(ZIEL, name + "_normal.jpg"), quality=q[1], subsampling=0)
    r8 = (np.clip(rau, 0, 1) * 255).astype(np.uint8)
    rimg = Image.fromarray(r8, "L")
    if normal_n and normal_n < rimg.size[0]:
        rimg = rimg.resize((normal_n, normal_n), Image.LANCZOS)
    rimg.save(os.path.join(ZIEL, name + "_rau.jpg"), quality=q[2])
    print(name, "mittel", np.round(np.clip(farbe, 0, 1).reshape(-1, 3).mean(axis=0), 3), "rau", round(float(np.clip(rau, 0, 1).mean()), 3))


def grau(h, n):
    return np.repeat(h[:, :, None], 3, axis=2) if h.ndim == 2 else h


def putz():
    n = 512
    fein = rauschen(n, 1.3, 11)
    grob = rauschen(n, 2.6, 12)
    h = fein * 0.55 + grob * 0.45
    farbe = grau(0.84 + (grob - 0.5) * 0.05 + (fein - 0.5) * 0.03, n)
    speichern("putz", farbe, normal_aus_hoehe(h, 0.35), 0.86 + (fein - 0.5) * 0.12)


def beton():
    n = 1024
    fl = rauschen(n, 2.4, 21)
    fein = rauschen(n, 1.2, 22)
    poren = (rauschen(n, 0.9, 23) > 0.86).astype(np.float32)
    h = fl * 0.6 + fein * 0.4 - poren * 0.5
    farbe = grau(0.62 + (fl - 0.5) * 0.22 + (fein - 0.5) * 0.08 - poren * 0.25, n)
    speichern("beton", farbe, normal_aus_hoehe(h, 0.5), 0.72 + (fl - 0.5) * 0.2 + poren * 0.2, normal_n=512)


def stoff(name, faeden, seed, flaum=0.0, rau0=0.9):
    n = 512
    ys, xs = np.mgrid[0:n, 0:n] / n
    web = (0.5 + 0.5 * np.sin(xs * faeden * 2 * np.pi)) * (0.5 + 0.5 * np.sin(ys * faeden * 2 * np.pi))
    web2 = (0.5 + 0.5 * np.cos(xs * faeden * 2 * np.pi)) * (0.5 + 0.5 * np.cos(ys * faeden * 2 * np.pi))
    unruhe = rauschen(n, 1.4, seed)
    fasern = rauschen(n, 0.8, seed + 1)
    h = np.maximum(web, web2) * 0.7 + unruhe * 0.2 + fasern * 0.1 * (1.0 + flaum)
    farbe = grau(0.78 + (np.maximum(web, web2) - 0.5) * 0.12 + (unruhe - 0.5) * 0.08 + (fasern - 0.5) * 0.06, n)
    speichern(name, farbe, normal_aus_hoehe(h, 0.45 + flaum * 0.3), rau0 + (fasern - 0.5) * 0.1)


def teppich():
    n = 1024
    d1, d2 = zellen(n, 96, 31)
    flor = np.clip(1.0 - d1 * 1.4, 0, 1)
    unruhe = rauschen(n, 1.6, 32)
    fein = rauschen(n, 0.7, 33)
    h = flor * 0.6 + unruhe * 0.25 + fein * 0.15
    farbe = grau(0.74 + (flor - 0.5) * 0.14 + (unruhe - 0.5) * 0.1 + (fein - 0.5) * 0.06, n)
    speichern("teppich", farbe, normal_aus_hoehe(h, 0.8), 0.93 + (fein - 0.5) * 0.08, normal_n=512)


def leder():
    n = 512
    d1, d2 = zellen(n, 40, 41)
    rand = np.clip((d2 - d1) * 2.2, 0, 1)
    falten = rauschen(n, 2.0, 42)
    fein = rauschen(n, 1.0, 43)
    h = rand * 0.55 + falten * 0.3 + fein * 0.15
    farbe = grau(0.72 + (rand - 0.5) * 0.1 + (falten - 0.5) * 0.14 + (fein - 0.5) * 0.04, n)
    speichern("leder", farbe, normal_aus_hoehe(h, 0.6), 0.52 + (1.0 - rand) * 0.18 + (fein - 0.5) * 0.08)


def holz(name, hell, dunkel, ringe, seed, poren=1.0, kontrast=1.0):
    """Furnier: Fasern längs (x), Jahresringe als weiche Bänder quer dazu (leicht verzogen), feine
    Poren – ruhig, ohne Körnung; die Ringe tragen die Farbe, die Normalkarte bleibt flach."""
    n = 1024
    ys, xs = np.mgrid[0:n, 0:n] / n
    # Jahresringe: lange, ruhig verzogene Bänder (hohe Anisotropie, kleine Amplitude), kein Flecken.
    verzug = rauschen(n, 3.0, seed, 28.0)
    band = (ys * ringe * 1.6 + (verzug - 0.5) * 1.5 + xs * 0.25)
    ring = 0.5 + 0.5 * np.sin(band * 2 * np.pi)
    ring = ring ** 2.2
    spaet = np.clip((ring - 0.42) * 2.0, 0, 1) ** 1.4    # Spätholz: weiche dunkle Bänder
    faser = rauschen(n, 2.0, seed + 1, 120.0)             # feine Fasern längs
    linien = np.clip((rauschen(n, 1.4, seed + 3, 220.0) - 0.78) * 5.0, 0, 1)   # Gefäßlinien
    pore = np.clip((rauschen(n, 1.2, seed + 2, 90.0) - 0.9) * 10.0, 0, 1) * poren
    t = np.clip(0.64 - spaet * 0.42 * kontrast + (faser - 0.5) * 0.22 - linien * 0.12 - (ring - 0.5) * 0.08, 0, 1)
    farbe = np.array(hell)[None, None, :] * t[:, :, None] + np.array(dunkel)[None, None, :] * (1.0 - t[:, :, None])
    farbe = farbe * (1.0 - pore[:, :, None] * 0.18)
    h = -spaet * 0.2 + faser * 0.15 - linien * 0.3 - pore * 0.3 + 0.5
    speichern(name, farbe, normal_aus_hoehe(h, 0.26), 0.46 + (faser - 0.5) * 0.1 + spaet * 0.08 + linien * 0.08 + pore * 0.1)


def lack():
    n = 512
    schale = rauschen(n, 1.1, 51)
    grob = rauschen(n, 2.2, 52)
    h = schale * 0.7 + grob * 0.3
    speichern("lack", grau(np.ones((n, n)) * 0.98, n), normal_aus_hoehe(h, 0.12), 0.34 + (grob - 0.5) * 0.1 + (schale - 0.5) * 0.04, farbe_an=False)


def metall_buerste():
    n = 512
    streifen = rauschen(n, 1.0, 61, 40.0)
    fein = rauschen(n, 0.6, 62, 60.0)
    kratzer = (rauschen(n, 0.5, 63, 30.0) > 0.9).astype(np.float32)
    h = streifen * 0.6 + fein * 0.3 - kratzer * 0.3
    farbe = grau(0.82 + (streifen - 0.5) * 0.1 + (fein - 0.5) * 0.04 - kratzer * 0.1, n)
    speichern("metall_buerste", farbe, normal_aus_hoehe(h, 0.25), 0.36 + (streifen - 0.5) * 0.2 + kratzer * 0.25)


def kunststoff():
    n = 512
    korn = rauschen(n, 0.7, 71)
    grob = rauschen(n, 2.0, 72)
    h = korn * 0.6 + grob * 0.4
    speichern("kunststoff", grau(0.97 + (grob - 0.5) * 0.03, n), normal_aus_hoehe(h, 0.2), 0.55 + (korn - 0.5) * 0.12 + (grob - 0.5) * 0.08, farbe_an=False)


def haut():
    """Poren und feine Linien für die Figur (Normal- und Rauheitskarte, neutral in der Farbe)."""
    n = 1024
    d1, d2 = zellen(n, 160, 81, 1.0)
    poren = np.clip(1.0 - d1 * 2.6, 0, 1) ** 2
    linien = rauschen(n, 1.0, 82, 3.0) * 0.5 + rauschen(n, 1.0, 83, 0.33) * 0.5
    fein = rauschen(n, 0.8, 84)
    h = -poren * 0.5 + linien * 0.35 + fein * 0.15 + 0.5
    speichern("haut", grau(np.ones((n, n)), n), normal_aus_hoehe(h, 0.22), 0.52 + poren * 0.2 + (fein - 0.5) * 0.1, normal_n=512, farbe_an=False)


if __name__ == "__main__":
    putz()
    beton()
    stoff("stoff", 48, 91)
    stoff("leinen", 30, 93, 0.3, 0.92)
    stoff("cord", 18, 95, 0.6, 0.88)
    teppich()
    leder()
    holz("holz_eiche", (0.80, 0.63, 0.44), (0.56, 0.40, 0.25), 9, 101)
    holz("holz_walnuss", (0.46, 0.31, 0.21), (0.24, 0.15, 0.10), 12, 111, 1.0, 0.9)
    holz("holz_hell", (0.90, 0.83, 0.70), (0.76, 0.66, 0.50), 7, 121, 0.6, 0.7)
    lack()
    metall_buerste()
    kunststoff()
    haut()
    print("fertig:", ZIEL)
