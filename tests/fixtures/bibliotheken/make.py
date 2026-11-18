"""Beispiel-Datenbanken der Launcher für tests/logic_bibliotheken.gd bauen (Punkt 6):

- galaxy.db     wie GOG Galaxys galaxy-2.0.db (InstalledBaseProducts, LimitedDetails, GameTimes,
                LastPlayedDates), dazu eine große Tabelle (innere B-Baum-Seiten), ein langer Text
                (Überlaufseiten) und eine WITHOUT-ROWID-Tabelle
- amazon.sqlite wie Amazon Games' GameInstallInfo.sqlite (DbSet)
- butler.db     wie die itch-App (caves, games, install_locations)
- schleife.db   kaputt: die Wurzel einer Tabelle zeigt auf sich selbst
- product.db    wie Battle.nets product.db (Protobuf), mit einem Zusatz-Eintrag ohne Bedeutung

Nur Python mit sqlite3. Aufruf: python3 tests/fixtures/bibliotheken/make.py
"""
import os
import sqlite3
import struct

HERE = os.path.dirname(os.path.abspath(__file__))


def fresh(name):
    p = os.path.join(HERE, name)
    if os.path.exists(p):
        os.remove(p)
    c = sqlite3.connect(p)
    c.execute("PRAGMA page_size=1024")
    c.execute("PRAGMA journal_mode=DELETE")
    return p, c


def galaxy():
    p, c = fresh("galaxy.db")
    c.execute("CREATE TABLE InstalledBaseProducts (productId INTEGER PRIMARY KEY NOT NULL, installationPath TEXT NOT NULL, installationDate TEXT)")
    c.execute("CREATE TABLE LimitedDetails (id INTEGER PRIMARY KEY, productId INTEGER NOT NULL, title TEXT, images TEXT, languageCode TEXT)")
    c.execute("CREATE TABLE \"GameTimes\" (userId INTEGER NOT NULL, releaseKey TEXT NOT NULL, minutesInGame INTEGER NOT NULL, PRIMARY KEY (userId, releaseKey))")
    c.execute("CREATE TABLE LastPlayedDates (userId INTEGER, gameReleaseKey TEXT, lastPlayedDate TEXT)")
    c.execute("CREATE TABLE Ohne (k TEXT PRIMARY KEY, v TEXT) WITHOUT ROWID")
    c.execute("CREATE TABLE Viel (id INTEGER PRIMARY KEY, a TEXT, b INTEGER, c REAL)")
    c.executemany("INSERT INTO InstalledBaseProducts VALUES (?,?,?)", [
        (1207664663, "C:\\GOG Games\\The Witcher 3 Wild Hunt GOTY", "2024-01-02 10:00:00"),
        (1771589310, "D:\\GOG Games\\Disco Elysium", "2024-02-03 11:00:00"),
        (123, "C:\\..\\Windows", "2024-02-03 11:00:00"),
    ])
    c.executemany("INSERT INTO LimitedDetails (productId, title, images, languageCode) VALUES (?,?,?,?)", [
        (1207664663, "The Witcher® 3: Wild Hunt", "x" * 5000, "de-DE"),
        (1771589310, "Disco Elysium - The Final Cut", "{}", "de-DE"),
    ])
    c.executemany("INSERT INTO GameTimes VALUES (?,?,?)", [
        (1, "gog_1207664663", 5460), (2, "gog_1207664663", 12), (1, "steam_292030", 999), (1, "gog_1771589310", -5),
    ])
    c.executemany("INSERT INTO LastPlayedDates VALUES (?,?,?)", [
        (1, "gog_1207664663", "2024-05-01 18:20:11"), (1, "gog_1771589310", "kein Datum"),
    ])
    c.executemany("INSERT INTO Ohne VALUES (?,?)", [("a", "b")])
    c.executemany("INSERT INTO Viel (a, b, c) VALUES (?,?,?)", [("Zeile %d" % i, i * 1000003, i / 7.0) for i in range(3000)])
    c.commit()
    c.close()


def amazon():
    p, c = fresh("amazon.sqlite")
    c.execute("CREATE TABLE DbSet (Id TEXT PRIMARY KEY NOT NULL, InstallDirectory TEXT, Installed INTEGER, ProductTitle TEXT, ProductAsin TEXT)")
    c.executemany("INSERT INTO DbSet VALUES (?,?,?,?,?)", [
        ("amzn1.adg.product.2d7d6c8e-3a4f-4c2b-9a77-1f5d8c0b6e21", "C:\\Amazon Games\\Library\\Fallout 3", 1, "Fallout 3: Game of the Year Edition", "B0"),
        ("amzn1.adg.product.11111111-2222-3333-4444-555555555555", "C:\\Amazon Games\\Library\\Weg", 0, "Deinstalliert", "B1"),
        ("amzn1.adg.product.x\" & calc", "C:\\Amazon Games\\Library\\Boese", 1, "Böse ID", "B2"),
    ])
    c.commit()
    c.close()


def butler():
    p, c = fresh("butler.db")
    c.execute("CREATE TABLE caves (id TEXT PRIMARY KEY, game_id INTEGER, install_folder_name TEXT, install_location_id TEXT, custom_install_folder TEXT, verdict TEXT, seconds_run INTEGER, last_touched_at DATETIME)")
    c.execute("CREATE TABLE games (id INTEGER PRIMARY KEY, title TEXT, classification TEXT)")
    c.execute("CREATE TABLE install_locations (id TEXT PRIMARY KEY, path TEXT)")
    c.executemany("INSERT INTO install_locations VALUES (?,?)", [("loc1", "C:\\Users\\Demo\\AppData\\Roaming\\itch")])
    c.executemany("INSERT INTO games VALUES (?,?,?)", [(115302, "A Short Hike", "game"), (9, "Pixel-Pinsel", "tool"), (10, "Ohne Programm", "game")])
    c.executemany("INSERT INTO caves VALUES (?,?,?,?,?,?,?,?)", [
        ("0b6c2f3e-8d61-4b0e-9d61-3c1f6b8f2a10", 115302, "a-short-hike", "loc1", None,
            '{"basePath":"C:\\\\Users\\\\Demo\\\\AppData\\\\Roaming\\\\itch\\\\apps\\\\a-short-hike","candidates":[{"path":"..\\\\..\\\\boese.exe","flavor":"windows"},{"path":"AShortHike.exe","flavor":"windows"}]}',
            11400, "2024-04-10 09:00:00.123456+00:00"),
        ("1c6c2f3e-8d61-4b0e-9d61-3c1f6b8f2a11", 9, "pinsel", "loc1", None, "{}", 60, None),
        ("2c6c2f3e-8d61-4b0e-9d61-3c1f6b8f2a12", 10, "../../Windows", "loc1", None, "kaputt", 0, None),
    ])
    c.commit()
    c.close()


def schleife():
    p, c = fresh("schleife.db")
    c.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, a TEXT)")
    c.executemany("INSERT INTO t (a) VALUES (?)", [("x" * 50,) for _ in range(400)])
    c.commit()
    root = c.execute("SELECT rootpage FROM sqlite_master WHERE name='t'").fetchone()[0]
    c.close()
    data = bytearray(open(p, "rb").read())
    off = (root - 1) * 1024
    assert data[off] == 5, "Wurzel ist keine innere Seite"
    # Rechter Zeiger der Wurzel → die Wurzel selbst (Schleife).
    data[off + 8:off + 12] = struct.pack(">I", root)
    open(p, "wb").write(bytes(data))


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def field(num, payload):
    if isinstance(payload, int):
        return varint(num << 3) + varint(payload)
    if isinstance(payload, str):
        payload = payload.encode()
    return varint((num << 3) | 2) + varint(len(payload)) + payload


def product(uid, code, path, installed=True):
    # CachedProductState (4) → BaseProductState (1) → installed (1)
    state = field(1, field(1, 1 if installed else 0))
    return field(1, field(1, uid) + field(2, code) + field(3, field(1, path) + field(2, "eu")) + field(4, state))


def productdb():
    body = b""
    body += product("prometheus", "Pro", "C:/Program Files (x86)/Overwatch")
    body += product("wow", "WoW", "C:/Program Files (x86)/World of Warcraft")
    body += product("agent", "agent", "C:/ProgramData/Battle.net/Agent")
    body += product("battle.net", "App", "C:/Program Files (x86)/Battle.net")
    body += product("d3", "D3", "C:/Program Files (x86)/Diablo III", installed=False)
    body += product("x", "B\u00f6se;calc", "C:/Spiele/X")
    body += field(2, b"\x08\x01")  # anderes Feld (aktive Installationen)
    body += struct.pack("<I", 0)  # Rest ohne Bedeutung
    open(os.path.join(HERE, "product.db"), "wb").write(body)


if __name__ == "__main__":
    galaxy()
    amazon()
    butler()
    schleife()
    productdb()
    for f in sorted(os.listdir(HERE)):
        print(f, os.path.getsize(os.path.join(HERE, f)))
