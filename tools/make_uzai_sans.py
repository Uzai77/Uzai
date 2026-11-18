"""Uzai Sans für die Leiste in mpv: feste Schnitte aus Hanken Grotesk (variabel, WOFF2).

mpv/libass kann mit der variablen WOFF2-Datei nicht sicher umgehen. Dieses Skript erzeugt vier
feste TTF-Schnitte mit eigenen Familiennamen (OFL 1.1 erlaubt das; Hanken Grotesk hat keinen
reservierten Namen) und gibt die Zeichenbreiten als Lua-Tabelle aus (für assets/mpv/uzai_osd.lua).

    pip install fonttools brotli
    python tools/make_uzai_sans.py assets/fonts/HankenGrotesk-latin.woff2 assets/mpv/fonts > widths.lua
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

STYLES = [(400, "Uzai Sans", "UzaiSans-Regular.ttf", "r"), (500, "Uzai Sans Medium", "UzaiSans-Medium.ttf", "m"),
          (700, "Uzai Sans Bold", "UzaiSans-Bold.ttf", "b"), (800, "Uzai Sans Black", "UzaiSans-Black.ttf", None)]
CHARS = list(range(32, 127)) + [ord(c) for c in "äöüÄÖÜßéèáàíóúñç„“”‚‘’–—…·€°×"]


def main(src, out):
    tables = []
    for weight, fam, fname, key in STYLES:
        inst = instancer.instantiateVariableFont(TTFont(src), {"wght": weight})
        name = inst["name"]
        ps = fam.replace(" ", "") + "-Regular"
        for rec in list(name.names):
            if rec.nameID in (1, 4):
                rec.string = fam
            elif rec.nameID == 2:
                rec.string = "Regular"
            elif rec.nameID == 6:
                rec.string = ps
            elif rec.nameID == 3:
                rec.string = "Uzai: " + ps
            elif rec.nameID in (16, 17, 25):
                name.removeNames(nameID=rec.nameID)
        # Jeder Schnitt ist eine eigene Familie „Regular“: libass soll nichts fett nachrechnen.
        inst["OS/2"].usWeightClass = 400
        inst["OS/2"].fsSelection = (inst["OS/2"].fsSelection & ~0b1100001) | 0b1000000
        inst["head"].macStyle = 0
        inst.flavor = None
        inst.save(f"{out}/{fname}")
        if key:
            upm = inst["head"].unitsPerEm
            cmap = inst.getBestCmap()
            parts = ["[%d]=%.3f" % (c, inst["hmtx"][cmap[c]][0] / upm) for c in CHARS if c in cmap]
            tables.append("\t%s = { %s }," % (key, ", ".join(parts)))
    print("local WIDTHS = {\n" + "\n".join(tables) + "\n}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
