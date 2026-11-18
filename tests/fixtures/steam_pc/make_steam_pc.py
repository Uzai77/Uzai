#!/usr/bin/env python3
"""Baut die Beispieldateien für tests/logic_steam_erfolge.gd: ein kleiner Steam-Ordner wie am PC.

    python3 -I tests/fixtures/steam_pc/make_steam_pc.py

appcache/stats/UserGameStatsSchema_480.bin   Schema (binäre KeyValues): 4 Erfolge in zwei Statistiken,
                                             deutsch/englisch, einer geheim, Bilder
appcache/stats/UserGameStats_12345_480.bin   Spielerdaten von Konto 12345: 2 frei (mit Zeit)
appcache/stats/UserGameStatsSchema_481.bin   kaputt (mitten im Text abgeschnitten)
appcache/stats/UserGameStats_12345_481.bin   dazu passend (wird nie gebraucht)
appcache/stats/UserGameStatsSchema_482.bin   Schema ohne Spielerdatei
userdata/12345/config/localconfig.vdf        Status „abwesend“ im neuen Format (WebStorage)
userdata/777/config/localconfig.vdf          nur PersonaStateDesired (älterer Client)
config/loginusers.vdf                        Konto 12345 online, Konto 777 im Offline-Modus
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
STEAM64 = 76561197960265728


def kv(d):
    """Binäre KeyValues: 0x00 Abschnitt, 0x01 Text, 0x02 int32, 0x08 Ende."""
    out = b""
    for k, v in d.items():
        key = k.encode("utf-8") + b"\0"
        if isinstance(v, dict):
            out += b"\x00" + key + kv(v) + b"\x08"
        elif isinstance(v, int):
            out += b"\x02" + key + struct.pack("<i", v)
        else:
            out += b"\x01" + key + str(v).encode("utf-8") + b"\0"
    return out


def ach(name, bit, de, en, desc_de, hidden, icon, gray):
    return {"name": name, "bit": bit, "display": {
        "name": {"english": en, "german": de, "token": "NEW_ACHIEVEMENT_%d" % bit},
        "desc": {"english": "en: " + desc_de, "german": desc_de},
        "hidden": "1" if hidden else "0", "icon": icon, "icon_gray": gray}}


def schema(appid, name):
    return kv({str(appid): {"gamename": name, "version": 3, "stats": {
        "1": {"type": "4", "id": "1", "bits": {
            "0": ach("ACH_WIN_ONE_GAME", 0, "Sieger", "Winner", "Gewinne ein Spiel.", False, "aaa111.jpg", "aaa111_g.jpg"),
            "1": ach("ACH_WIN_100_GAMES", 1, "Meister", "Champion", "Gewinne 100 Spiele.", False, "bbb222.jpg", "bbb222_g.jpg"),
            "2": ach("ACH_TRAVEL_FAR", 2, "Weit gereist", "Interstellar", "Reise weit.", True, "ccc333.jpg", "../böse.jpg")}},
        "2": {"type": "4", "id": "2", "bits": {
            "0": ach("ACH_SECRET_END", 0, "Ende", "The End", "Sieh das Ende.", False, "ddd444.jpg", "ddd444_g.jpg")}},
        "3": {"type": "1", "id": "3", "name": "NumGames"}}}}) + b"\x08"


def user(acct):
    # Statistik 1: Bits 0 und 2 frei (data = 0b101), Zeiten dazu; Statistik 2: nichts; 3: Zahl.
    return kv({"cache": {"crc": 1234, "PendingChanges": 0,
                         "1": {"data": 5, "AchievementTimes": {"0": 1760000000, "2": 1761000000}},
                         "2": {"data": 0},
                         "3": {"data": 17}}}) + b"\x08"


def write(rel, data):
    p = os.path.join(HERE, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        f.write(data)


write("appcache/stats/UserGameStatsSchema_480.bin", schema(480, "Spacewar"))
write("appcache/stats/UserGameStats_12345_480.bin", user(12345))
write("appcache/stats/UserGameStatsSchema_481.bin", schema(481, "Kaputt")[:57])
write("appcache/stats/UserGameStats_12345_481.bin", user(12345))
write("appcache/stats/UserGameStatsSchema_482.bin", schema(482, "Ohne Spielerdatei"))

write("userdata/12345/config/localconfig.vdf", (
    '"UserLocalConfigStore"\n{\n\t"friends"\n\t{\n\t\t"PersonaStateDesired"\t\t"1"\n\t}\n'
    '\t"WebStorage"\n\t{\n\t\t"FriendStoreLocalPrefs_12345"\t\t"{\\"ePersonaState\\":3,\\"strNonFriendsAllowedToMsg\\":\\"\\"}"\n'
    '\t}\n}\n').encode("utf-8"))
write("userdata/777/config/localconfig.vdf",
      '"UserLocalConfigStore"\n{\n\t"friends"\n\t{\n\t\t"PersonaStateDesired"\t\t"7"\n\t}\n}\n'.encode("utf-8"))
write("config/loginusers.vdf", (
    '"users"\n{\n\t"%d"\n\t{\n\t\t"AccountName"\t\t"a"\n\t\t"WantsOfflineMode"\t\t"0"\n\t}\n'
    '\t"%d"\n\t{\n\t\t"AccountName"\t\t"b"\n\t\t"WantsOfflineMode"\t\t"1"\n\t}\n}\n' % (STEAM64 + 12345, STEAM64 + 777)).encode("utf-8"))
print("ok")
