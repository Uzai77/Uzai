"""App-Symbol von Uzai für Windows: assets/uzai.ico (16, 24, 32, 48, 64, 256) – genau wie icon.svg.

Ab 32 px auf der dunklen, weich gerundeten Kachel (Verlauf von oben, feine Lichtkante): das U aus
zwei Bändern mit Verlauf (außen hell nach tief, innen eine Spur dunkler) und die helle Lichtlinie
dazwischen. Klein (16 und 24 px, Infobereich) nur das U randvoll, ohne Kachel und ohne Linie (sie
wäre kleiner als ein Bildpunkt). Geometrie wie src/ui/marke_form.gd (H, B, STRICH, FUGE), Farben wie
tools/marke_rendern.gd (icon.svg) zum Markenviolett #A47BFF.

    pip install pillow
    python tools/make_logo.py
"""
import colorsys
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Wie marke_form.gd
H, B, STRICH, FUGE = 1.9, 1.7, 0.5, 0.07
# Kachel wie icon.svg: Seite 240 von 256, Ecken 54, das U 150 hoch.
TILE_TOP, TILE_BOTTOM, EDGE = "#201d29", "#0c0b10", "#3d3948"
ICON_H = 150.0
VIOLETT = "#a47bff"


def _hex(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def _hsv_rgb(h, s, v):
    return tuple(int(round(x * 255)) for x in colorsys.hsv_to_rgb(h, s, v))


def _mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _dunkler(c, k):
    return tuple(int(round(x * (1 - k))) for x in c)


def _heller(c, k):
    return tuple(int(round(x + (255 - x) * k)) for x in c)


def farben():
    """Wie uzai_logo.gd farben("marke"): Eloxal aus dem Akzent, außen hell → tief, innen tiefer."""
    r, g, b = [x / 255 for x in _hex(VIOLETT)]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    elox = _hsv_rgb(h, min(s * 1.35 + 0.12, 0.85), min(max(v * 0.62, 0.25), 0.7))
    tief = _dunkler(elox, 0.22)
    licht = _hsv_rgb(h, min(s * 0.9, 0.6), 1.0)
    return (_heller(elox, 0.28), tief), (elox, _dunkler(tief, 0.25)), licht


def u_bogen(r, cy, oben, n=96):
    """Linie in Form eines U: linker Schenkel von oben bis cy, Halbkreis unten, rechter Schenkel hinauf."""
    out = [(-r, oben), (-r, cy)]
    for i in range(1, n):
        a = math.pi + math.pi * i / n
        out.append((math.cos(a) * r, cy + math.sin(a) * r))
    out += [(r, cy), (r, oben)]
    return out


def baender():
    """[außen, innen] als Vielecke im Maß des Zeichens (Mitte im Ursprung, y nach oben) und die Linie."""
    r = B * 0.5
    cy = -H * 0.5 + r
    rx = r - STRICH * 0.5
    oben = H * 0.5
    aussen = u_bogen(r, cy, oben) + list(reversed(u_bogen(rx + FUGE * 0.5, cy, oben)))
    innen = u_bogen(rx - FUGE * 0.5, cy, oben) + list(reversed(u_bogen(r - STRICH, cy, oben)))
    return aussen, innen, u_bogen(rx, cy, oben)


def verlauf_flaeche(im, pts, oben, unten):
    """Vieleck mit Verlauf wie im SVG (Richtung 0,35 / 1 im umgebenden Rechteck)."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, y0, x1, y1 = int(min(xs)), int(min(ys)), int(math.ceil(max(xs))), int(math.ceil(max(ys)))
    w, h = max(1, x1 - x0), max(1, y1 - y0)
    grad = Image.new("RGBA", (w, h))
    px = grad.load()
    g2 = 0.35 * 0.35 + 1.0
    for y in range(h):
        for x in range(w):
            t = min(max((x / w * 0.35 + y / h) / g2, 0.0), 1.0)
            px[x, y] = _mix(oben, unten, t) + (255,)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon([(p[0] - x0, p[1] - y0) for p in pts], fill=255)
    im.paste(grad, (x0, y0), mask)


def kachel(big):
    s = big / 256.0
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([8 * s, 8 * s, 248 * s - 1, 248 * s - 1], radius=54 * s, fill=255)
    top, bot, edge = _hex(TILE_TOP), _hex(TILE_BOTTOM), _hex(EDGE)
    grad = Image.new("RGBA", (1, big))
    for y in range(big):
        t = min(max((y - 8 * s) / (240 * s), 0.0), 1.0)
        grad.putpixel((0, y), _mix(top, bot, t) + (255,))
    grad = grad.resize((big, big))
    rim = Image.new("L", (big, big), 0)
    ImageDraw.Draw(rim).rounded_rectangle([8 * s, 8 * s, 248 * s - 1, 248 * s - 1], radius=54 * s, outline=255, width=max(1, int(1.5 * s)))
    fade = Image.new("L", (1, big))
    for y in range(big):
        fade.putpixel((0, y), int(255 * max(0.0, 1.0 - (y - 8 * s) / (120 * s))))
    rim = Image.composite(rim, Image.new("L", (big, big), 0), fade.resize((big, big)))
    tile = Image.composite(Image.new("RGBA", (big, big), edge + (255,)), grad, rim)
    im.paste(tile, (0, 0), mask)
    return im


def raster(px):
    ss = 8 if px < 256 else 4
    big = px * ss
    aussen, innen, linie = baender()
    (a_o, a_u), (i_o, i_u), licht = farben()
    if px >= 32:
        im = kachel(big)
        k = big * ICON_H / 256.0 / H
        tf = lambda p: (big * 0.5 + p[0] * k, big * 0.5 - p[1] * k)
        verlauf_flaeche(im, [tf(p) for p in aussen], a_o, a_u)
        verlauf_flaeche(im, [tf(p) for p in innen], i_o, i_u)
        ImageDraw.Draw(im).line([tf(p) for p in linie], fill=licht + (255,), width=max(1, int(round(FUGE * k * 0.8))), joint="curve")
        return im.resize((px, px), Image.LANCZOS)
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    k = big / (H + 0.08)
    tf = lambda p: (big * 0.5 + p[0] * k, big * 0.5 - p[1] * k)
    # Klein heller, damit es auf dunklen und hellen Leisten steht.
    verlauf_flaeche(im, [tf(p) for p in aussen], _heller(a_o, 0.15), a_o)
    verlauf_flaeche(im, [tf(p) for p in innen], a_o, i_o)
    return im.resize((px, px), Image.LANCZOS)


def main():
    sizes = [16, 24, 32, 48, 64, 256]
    frames = [raster(p) for p in sizes]
    frames[-1].save(os.path.join(ROOT, "assets", "uzai.ico"), format="ICO", sizes=[(p, p) for p in sizes], append_images=frames[:-1])
    print("assets/uzai.ico (%s)" % ", ".join(map(str, sizes)))


if __name__ == "__main__":
    main()
