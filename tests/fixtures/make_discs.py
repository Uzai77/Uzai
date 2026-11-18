"""Testabbilder für die Disc-Erkennung (tests/logic_disc.gd) bauen: echte ISO9660-Abbilder mit
pycdlib, daraus .bin-Rohsektoren (2352 Bytes, Mode 2 und Mode 1) mit passender .cue. Ergebnis ist
tests/fixtures/discs.zip (Abbilder fast nur Nullen, darum winzig).

Aufruf: PYTHONPATH=<pycdlib> python3 tests/fixtures/make_discs.py
"""
import io
import os
import zipfile

import pycdlib

HERE = os.path.dirname(os.path.abspath(__file__))


def iso_bytes(cnf, extra=0):
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=1, vol_ident="TESTDISC")
    # Viele Dateien vor SYSTEM.CNF: das Wurzelverzeichnis reicht dann über mehrere Sektoren.
    for i in range(extra):
        data = b"x" * 10
        iso.add_fp(io.BytesIO(data), len(data), "/A%03d.DAT;1" % i)
    if cnf is not None:
        iso.add_fp(io.BytesIO(cnf), len(cnf), "/SYSTEM.CNF;1")
    exe = b"\0" * 3000
    iso.add_fp(io.BytesIO(exe), len(exe), "/SLES_503.30;1")
    out = io.BytesIO()
    iso.write_fp(out)
    iso.close()
    return out.getvalue()


def raw(iso, mode):
    """2048er-Sektoren in 2352er-Rohsektoren packen (Sync, Kopf, ggf. Unterkopf, Daten)."""
    out = bytearray()
    for n in range(len(iso) // 2048):
        sec = bytearray(2352)
        sec[0] = 0
        sec[1:11] = b"\xff" * 10
        sec[11] = 0
        lba = n + 150
        m, s, f = lba // 4500, (lba // 75) % 60, lba % 75
        sec[12:15] = bytes(int(str(v), 16) for v in (m, s, f))
        sec[15] = mode
        start = 24 if mode == 2 else 16
        sec[start:start + 2048] = iso[n * 2048:(n + 1) * 2048]
        out += sec
    return bytes(out)


def main():
    ps2 = b"BOOT2 = cdrom0:\\SLES_503.30;1\r\nVER = 1.00\r\nVMODE = PAL\r\n"
    ps1 = b"BOOT = cdrom:\\SCES_008.67;1\r\nTCB = 4\r\nEVENT = 10\r\nSTACK = 801FFFF0\r\n"
    ps1_noserial = b"BOOT = cdrom:\\PSX.EXE;1\r\n"
    files = {
        "Shadow of the Colossus (Europe).iso": iso_bytes(ps2),
        "Viele Dateien.iso": iso_bytes(b"BOOT2 = cdrom0:\\SLUS_203.12;1\r\n", extra=90),
        "Ohne CNF.iso": iso_bytes(None),
        "Ohne Nummer.iso": iso_bytes(ps1_noserial),
        "Final Fantasy VII (Disc 1).bin": raw(iso_bytes(ps1), 2),
        "Mode1.bin": raw(iso_bytes(b"BOOT = cdrom:\\SLPS_011.23;1\r\n"), 1),
        "SLUS-20946 Name im Dateinamen.chd": b"MComprHD" + b"\0" * 100,
        "Kaputt.iso": b"\0" * 5000,
    }
    files["Final Fantasy VII (Disc 1).cue"] = (
        'FILE "Final Fantasy VII (Disc 1).bin" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n').encode()
    files["Mode1.cue"] = b'FILE "Mode1.bin" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n'
    files["Spiel.m3u"] = b"Final Fantasy VII (Disc 1).cue\n"
    with zipfile.ZipFile(os.path.join(HERE, "discs.zip"), "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(files.items()):
            z.writestr(name, data)
    print("ok", os.path.getsize(os.path.join(HERE, "discs.zip")), "Bytes")


if __name__ == "__main__":
    main()
