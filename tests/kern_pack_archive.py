#!/usr/bin/env python3
"""Baut Probe-Archive für den Entpacker des Helfers (UzKernPack, tests/kern_pack_cs.ps1).

Aufbau wie die echten Verteilungen (156.0): die signierte (.tar.xz) hat chrome_elf.dll, libcef.dll … gleich im
Hauptordner, ohne Release/ und ohne Bootstrap; die minimal (.tar.bz2, auch .tar.xz) hat Release/bootstrap.exe.

Aufruf: python3 -I tests/kern_pack_archive.py <leerer Ordner>  → schreibt die Archive und faelle.json
(faelle: Name → Datei, Art, erwartetes Ergebnis; voll: ganze bzip2-Ströme → SHA-256 des Inhalts oder Fehler;
SHA-256 der beiden Dateien). Deterministisch (fester Zufall), nur Python und xz-utils, falls vorhanden (sonst
entfallen die Fälle, die xz-utils brauchen)."""
import bz2
import hashlib
import io
import json
import lzma
import os
import random
import shutil
import subprocess
import sys
import tarfile

ziel = sys.argv[1]
rnd = random.Random(15101)
KOPF = "cef_binary_154.3.2+g1234abc+chromium-154.0.7871.4_windows64"
SIGNIERT = KOPF + "_signed"
MINIMAL = KOPF + "_minimal"


def zufall(n):
    return rnd.randbytes(n)


def text(n):
    woerter = [b"chromium", b"sandbox", b"uzai", b"controller", b"libcef", b"bootstrap", b"\n", b"{", b"}", b"0x1f"]
    out = b" ".join(rnd.choices(woerter, k=n // 5 + 8))
    return out[:n]


BOOT = b"MZ" + zufall(180_000) + text(220_000) + b"\0" * 70_000 + b"ab" * 9_000
ELF = b"MZ" + text(90_000) + zufall(40_000)


def tar(eintraege, fmt=tarfile.PAX_FORMAT):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w", format=fmt) as t:
        for name, daten, art in eintraege:
            i = tarfile.TarInfo(name)
            i.mtime = 1_700_000_000
            if art == "dir":
                i.type = tarfile.DIRTYPE
                t.addfile(i)
            elif art == "link":
                i.type = tarfile.SYMTYPE
                i.linkname = daten
                t.addfile(i)
            else:
                i.size = len(daten)
                t.addfile(i, io.BytesIO(daten))
    return b.getvalue()


def signiert(elf=ELF, extra=()):
    """Wie cef_binary_…_signed: Laufzeit oben, locales/, kein Release/, kein Bootstrap."""
    B = SIGNIERT
    return [(B, None, "dir"), (B + "/catalog.cat", zufall(20_000), "file"), (B + "/locales", None, "dir"),
            (B + "/locales/de.pak", text(400_000), "file"), (B + "/libcef.dll", zufall(900_000), "file"),
            (B + "/d3dcompiler_47.dll", zufall(50_000), "file")] + list(extra) + [
            (B + "/chrome_elf.dll", elf, "file"), (B + "/vulkan-1.dll", zufall(30_000), "file")]


def minimal(boot=BOOT, extra=()):
    """Wie cef_binary_…_minimal: include/ (lang), libcef_dll/, Release/ mit Bootstrap und Laufzeit, Debug/ nie."""
    B = MINIMAL
    lang = B + "/include/" + "/".join(["sehr_lange_ordner_namen_%d" % k for k in range(6)]) + "/cef_api_hash.h"
    return [(B, None, "dir"), (B + "/README.txt", text(3000), "file"), (lang, text(1_500_000), "file"),
            (B + "/libcef_dll/wrapper.cc", text(600_000), "file"), (B + "/Release/libcef.lnk", "libcef.dll", "link"),
            (B + "/Debug/bootstrap.exe", b"MZdebug" + zufall(5000), "file")] + list(extra) + [
            (B + "/Release/bootstrap.exe", boot, "file"), (B + "/Release/bootstrapc.exe", b"MZ" + zufall(9000), "file"),
            (B + "/Release/chrome_elf.dll", b"MZ" + zufall(9000), "file"), (B + "/Release/libcef.dll", zufall(400_000), "file")]


def xz_py(daten, check=lzma.CHECK_CRC64, preset=1):
    return lzma.compress(daten, format=lzma.FORMAT_XZ, check=check, preset=preset)


def xz_cli(daten, *opt):
    xz = shutil.which("xz")
    if not xz:
        return None
    return subprocess.run([xz, "-c", "-T1"] + list(opt), input=daten, stdout=subprocess.PIPE, check=True).stdout


faelle = {}
voll = {}


def fall(name, endung, art, daten, erwartet):
    if daten is None:
        return
    datei = name + endung
    with open(os.path.join(ziel, datei), "wb") as f:
        f.write(daten)
    faelle[name] = {"datei": datei, "art": art, "erwartet": erwartet}


def ganz(name, daten, erwartet):
    """Ein bzip2-Strom, der ganz gelesen wird: erwartet = SHA-256 des Inhalts oder der Fehler."""
    with open(os.path.join(ziel, name + ".bz2"), "wb") as f:
        f.write(daten)
    voll[name] = erwartet


def eos_bit(daten):
    """Bitstelle der Strom-CRC am Ende eines bzip2-Stroms (48 Bit Endmarke, 32 Bit CRC, 0–7 Füllbits)."""
    n = len(daten) * 8
    wert = int.from_bytes(daten, "big")
    for pad in range(8):
        crc_ab = n - pad - 32
        marke = (wert >> (n - crc_ab)) & ((1 << 48) - 1)
        if marke == 0x177245385090:
            return crc_ab
    raise SystemExit("Endmarke nicht gefunden")


def kippen(daten, bit):
    b = bytearray(daten)
    b[bit // 8] ^= 0x80 >> (bit % 8)
    return bytes(b)


ok = ""
# --- signierte Verteilung (xz): nur chrome_elf.dll im Hauptordner ---
t = tar(signiert())
t_xz = xz_py(t)
S = "signiert"
fall("s_pax_crc64", ".tar.xz", S, xz_py(t, lzma.CHECK_CRC64, 6), ok)
fall("s_gnu_crc32_bloecke", ".tar.xz", S, xz_cli(tar(signiert(), tarfile.GNU_FORMAT), "-1", "--check=crc32", "--block-size=256KiB"), ok)
fall("s_ustar_sha256", ".tar.xz", S, xz_cli(tar(signiert(), tarfile.USTAR_FORMAT), "-1", "--check=sha256"), ok)
fall("s_ohne_pruefsumme_stufe0", ".tar.xz", S, xz_py(t, lzma.CHECK_NONE, 0), ok)
fall("s_stufe9", ".tar.xz", S, xz_py(t, lzma.CHECK_CRC64, 9), ok)
h = len(t) // 2
fall("s_zwei_stroeme", ".tar.xz", S, xz_py(t[:h]) + b"\0" * 8 + xz_py(t[h:], lzma.CHECK_CRC32), ok)
fall("s_bcj_filter", ".tar.xz", S, xz_cli(t, "--x86", "--lzma2=preset=1"), "xz: Filter 0x4 wird nicht unterstützt (nur LZMA2)")
fall("s_ohne_elf", ".tar.xz", S, xz_py(tar([e for e in signiert() if not e[0].endswith("/chrome_elf.dll")])), "chrome_elf.dll fehlt im Archiv; Hauptordner:")
# Der Hauptordner der signierten heißt nicht zwingend „cef_binary_…“ (Nutzerprotokoll 0.16.27): jeder Name gilt.
fall("s_anderer_hauptordner", ".tar.xz", S, xz_py(tar([(n.replace(SIGNIERT, "uzai_unbekannt", 1), d, a) for n, d, a in signiert()])), ok)
# chrome_elf.dll nur tiefer (alter Aufbau, Debug/): gilt nicht – nur die im Hauptordner.
fall("s_elf_nur_tiefer", ".tar.xz", S, xz_py(tar([(n.replace("/chrome_elf.dll", "/Release/chrome_elf.dll"), d, a) for n, d, a in signiert()]
                                                  + [(SIGNIERT + "/Debug/chrome_elf.dll", ELF, "file")])), "chrome_elf.dll fehlt im Archiv; Hauptordner:")
fall("s_pfad_mit_punkten", ".tar.xz", S, xz_py(tar([("cef_binary_../chrome_elf.dll", ELF, "file")] + signiert())), "tar: Name kaputt")
fall("s_seltsame_namen", ".tar.xz", S, xz_py(tar(signiert(extra=[("/abs/pfad.txt", b"x", "file"), (SIGNIERT + "/a:b~(c).txt", b"x", "file"),
                                                                (SIGNIERT + "/ümlaut.txt", b"x", "file")]))), ok)
fall("s_kein_programm", ".tar.xz", S, xz_py(tar(signiert(elf=b"PK" + ELF[2:]))), "tar: chrome_elf.dll ist kein Programm")
kaputt = bytearray(t_xz)
kaputt[len(kaputt) // 3] ^= 0x55
fall("s_kaputt", ".tar.xz", S, bytes(kaputt), "*")
fall("s_kein_xz", ".tar.xz", S, t[:4096], "xz: kein xz-Archiv")
fall("s_abgeschnitten", ".tar.xz", S, t_xz[:300_000], "xz: Archiv endet zu früh")
# Die signierte hat keinen Bootstrap (so lief 0.16.19 fest): als minimal gelesen → fehlt, mit Übersicht.
fall("s_als_minimal", ".tar.xz", "minimal", t_xz, "bootstrap.exe fehlt im Archiv; Hauptordner:")

# --- minimal-Verteilung (bzip2, auch xz): nur Release/bootstrap.exe ---
M = "minimal"
m = tar(minimal())
m_bz1 = bz2.compress(m, 1)
fall("m_bz2_stufe9", ".tar.bz2", M, bz2.compress(m, 9), ok)
fall("m_bz2_stufe1_bloecke", ".tar.bz2", M, m_bz1, ok)
fall("m_bz2_gnu", ".tar.bz2", M, bz2.compress(tar(minimal(), tarfile.GNU_FORMAT), 5), ok)
h = len(m) // 3
fall("m_bz2_zwei_stroeme", ".tar.bz2", M, bz2.compress(m[:h], 2) + bz2.compress(m[h:], 9), ok)
fall("m_xz", ".tar.xz", M, xz_py(m), ok)
cli = shutil.which("bzip2")
if cli:
    fall("m_bzip2_cli", ".tar.bz2", M, subprocess.run([cli, "-c", "-3"], input=m, stdout=subprocess.PIPE, check=True).stdout, ok)
fall("m_ohne_bootstrap", ".tar.bz2", M, bz2.compress(tar([e for e in minimal() if not e[0].endswith("Release/bootstrap.exe")]), 9),
     "bootstrap.exe fehlt im Archiv; Hauptordner:")
fall("m_nur_debug", ".tar.bz2", M, bz2.compress(tar([(n.replace("/Release/bootstrap.exe", "/bin/bootstrap.exe"), d, a) for n, d, a in minimal()]), 9),
     "bootstrap.exe fehlt im Archiv; Hauptordner:")
fall("m_zu_gross", ".tar.bz2", M, bz2.compress(tar(minimal(boot=b"MZ" + b"\0" * (17 << 20))), 9), "tar: bootstrap.exe zu groß")
fall("m_zu_klein", ".tar.bz2", M, bz2.compress(tar(minimal(boot=b"MZ")), 9), "tar: bootstrap.exe zu klein")
fall("m_kein_programm", ".tar.bz2", M, bz2.compress(tar(minimal(boot=b"\x7fELF" + BOOT[4:])), 9), "tar: bootstrap.exe ist kein Programm")
kaputt = bytearray(m_bz1)
kaputt[len(kaputt) // 3] ^= 0x55
fall("m_kaputt", ".tar.bz2", M, bytes(kaputt), "*")
fall("m_abgeschnitten", ".tar.bz2", M, m_bz1[: len(m_bz1) // 2], "bzip2: Archiv endet zu früh")
# Bytes 10–13: CRC des ersten Blocks (4 Kopf, 6 Blockmarke); Bit 112: „zufällig“.
fall("m_block_crc", ".tar.bz2", M, kippen(m_bz1, 13 * 8 + 7), "bzip2: Prüfsumme des Blocks falsch")
fall("m_zufaellig", ".tar.bz2", M, kippen(m_bz1, 14 * 8), "bzip2: zufällige Blöcke werden nicht unterstützt")
fall("m_kein_bz2", ".tar.bz2", M, m[:4096], "bzip2: kein bzip2-Archiv")
fall("m_falsche_stufe", ".tar.bz2", M, b"BZh0" + m_bz1[4:], "bzip2: kein bzip2-Archiv")
# Die CRC des Blocks, in dem der Bootstrap endet, wird auch geprüft (der Rest des Archivs wird nicht gelesen):
# Bootstrap als letzte Datei, die CRC des letzten Blocks (Blockmarke bitweise gesucht) gekippt.
hinten = bz2.compress(tar([e for e in minimal() if not e[0].endswith("Release/bootstrap.exe")] + [(MINIMAL + "/Release/bootstrap.exe", BOOT, "file")]), 1)
bitfolge = bin(int.from_bytes(hinten, "big"))[2:].zfill(len(hinten) * 8)
marke = bitfolge.rfind(bin(0x314159265359)[2:].zfill(48))
fall("m_letzter_block_crc", ".tar.bz2", M, kippen(hinten, marke + 48 + 5), "bzip2: Prüfsumme des Blocks falsch")
fall("m_kein_format", ".tar.gz", M, m_bz1, "Format unbekannt")

# --- ganze bzip2-Ströme (Strom-CRC, mehrere Ströme, Rest danach) ---
roh = m + b"\0" * 300_000 + bytes(range(256)) * 50 + b"x" * 1000
ganz("v_stufe1", bz2.compress(roh, 1), hashlib.sha256(roh).hexdigest())
ganz("v_zwei_stroeme", bz2.compress(roh[:5000], 9) + bz2.compress(roh[5000:], 3), hashlib.sha256(roh).hexdigest())
ganz("v_leer", bz2.compress(b""), hashlib.sha256(b"").hexdigest())
ganz("v_laeufe", bz2.compress(b"a" * 1_000_000 + b"b" * 3 + b"c" * 4 + b"d" * 5 + b"e" * 259 + b"f" * 260, 9),
     hashlib.sha256(b"a" * 1_000_000 + b"b" * 3 + b"c" * 4 + b"d" * 5 + b"e" * 259 + b"f" * 260).hexdigest())
e = bz2.compress(roh[:200_000], 9)
ganz("v_strom_crc", kippen(e, eos_bit(e) + 31), "bzip2: Prüfsumme des Stroms falsch")
ganz("v_rest_danach", e + b"xyz", "bzip2: Daten nach dem Ende")
ganz("v_abgeschnitten", e[:-3], "bzip2: Archiv endet zu früh")

with open(os.path.join(ziel, "faelle.json"), "w") as f:
    json.dump({"faelle": faelle, "voll": voll, "bootstrap": hashlib.sha256(BOOT).hexdigest(), "elf": hashlib.sha256(ELF).hexdigest()}, f)
print(len(faelle))
