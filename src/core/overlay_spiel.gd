extends RefCounted
## Overlay im Spiel (Versuch, docs/OVERLAY.md) – die Seite in Uzai. Über Spielen im exklusiven Vollbild
## zeigt Windows kein Fenster; der Guide minimiert sie sonst kurz (main_fenster.gd). Für Spiele, bei
## denen du es einschaltest, lädt Uzai stattdessen eine kleine Bibliothek ins Spiel, die das Bild des
## Guides über das fertige Bild des Spiels zeichnet (native/overlay/: Direct3D 9 und 11).
##
## Hier: wem das erlaubt ist (nur auf Wunsch, nie bei Anti-Cheat, nicht bei Emulatoren), der Kopf der
## Bilddatei, das Schreiben ohne gerissene Bilder und der Aufruf des Starters. Alles Reine ist ohne
## Windows prüfbar (tests/logic_overlay.gd).

const MAGIC := 0x564F5A55            ## „UZOV“, wie native/overlay/uzai_overlay.h
const VERSION := 1
const KOPF := 64
const MAX_BREITE := 2048
const MAX_HOEHE := 2400
const BILD := "overlay/bild.bin"     ## unter dem Datenordner
const BIN := "overlay/bin"           ## dorthin legt Uzai Bibliothek und Starter aus dem Paket
const DATEIEN := ["uzai-overlay32.dll", "uzai-overlay64.dll", "uzai-overlay-start32.exe", "uzai-overlay-start64.exe"]

## Schutzprogramme, erkannt an Datei- und Ordnernamen im Spielordner (klein geschrieben, als Teil des
## Namens). Bei einem Treffer bleibt das Overlay aus – ohne Ausnahme und ohne Versuch, sich zu verstecken.
const ANTICHEAT := {
	"easyanticheat": "Easy Anti-Cheat", "eac_launcher": "Easy Anti-Cheat", "battleye": "BattlEye", "beservice": "BattlEye",
	"beclient": "BattlEye", "vanguard": "Vanguard", "vgk.sys": "Vanguard", "gameguard": "nProtect GameGuard",
	"nprotect": "nProtect GameGuard", "xigncode": "XIGNCODE", "mhyprot": "mhyprot", "anticheatexpert": "Anti-Cheat Expert",
	"ace-base": "Anti-Cheat Expert", "punkbuster": "PunkBuster", "pbsvc": "PunkBuster", "equ8": "EQU8", "faceit": "FACEIT",
	"ricochet": "Ricochet", "hyperion": "Hyperion", "zakynthos": "Zakynthos", "nexon game security": "Nexon Game Security",
	"denuvo-anti-cheat": "Denuvo Anti-Cheat", "treyarch anticheat": "Ricochet",
}
## Starter: was die Zahl sagt (uzai_inject.c).
const ERGEBNIS := {
	1: "Haken sitzt", 2: "weder Direct3D 9 noch 11 im Spiel", 3: "Haken ging nicht", 4: "Pfad fehlt", 5: "lief schon",
	6: "Direct3D 12 (nicht unterstützt)",
	10: "Aufruf falsch", 11: "Prozess nicht zu öffnen (höhere Rechte?)", 12: "falsche Bitbreite", 13: "Bibliothek fehlt",
	14: "kein Speicher im Spiel", 15: "Laden ging nicht", 16: "Modul nicht gefunden", 17: "Einsprung fehlt",
	18: "Start ging nicht", 19: "keine Antwort",
}


## Darf die Bibliothek in diesen Prozess? pid: Prozess hinter dem Spielfenster, gestartet: der Prozess,
## den Uzai selbst gestartet hat (0 bei Spielen aus einem Laden), aus_ordner: Prozesse, die aus dem
## Spielordner laufen. Nur der selbst gestartete Prozess oder einer aus dem Spielordner – nie ein
## Starter (Steam, Launcher des Herstellers) und nie ein Systemprozess.
static func prozess_passt(pid: int, gestartet: int, aus_ordner: Array) -> bool:
	if pid <= 4:
		return false
	return (gestartet > 4 and pid == gestartet) or aus_ordner.has(pid)


## Erkanntes Schutzprogramm in diesen Namen ("" keins). namen: Datei- und Ordnernamen aus dem Spielordner.
static func anticheat_in(namen: Array) -> String:
	for n: Variant in namen:
		var klein := str(n).to_lower()
		for k: String in ANTICHEAT:
			if klein.contains(k):
				return str(ANTICHEAT[k])
	return ""


## Namen im Spielordner, zwei Ebenen tief: der Spielordner selbst ganz (dort liegen die Schutzprogramme
## meist), darunter bis grenze Einträge (große Spiele haben Zehntausende Dateien).
static func ordner_namen(dir: String, tiefe := 2, grenze := 4000) -> Array:
	var out: Array = []
	var offen: Array = [[dir, 0]]
	while not offen.is_empty() and out.size() < grenze:
		var e: Array = offen.pop_front()
		var da := DirAccess.open(str(e[0]))
		if da == null:
			continue
		var ordner := da.get_directories()
		var namen: Array = Array(ordner) + Array(da.get_files())
		out.append_array(namen if int(e[1]) == 0 else namen.slice(0, maxi(0, grenze - out.size())))
		if int(e[1]) + 1 < tiefe:
			for d in ordner:
				offen.append([str(e[0]).path_join(d), int(e[1]) + 1])
	return out


## Was ohne Blick in den Spielordner feststeht: "" (weiter prüfen), "windows", "emulator" oder "ordner".
static func vorab(g: Dictionary, windows: bool) -> String:
	if not windows:
		return "windows"
	if str(g.get("source", "")) in ["rom", "disc", "app"]:
		return "emulator"
	return "ordner" if str(g.get("install_dir", "")) == "" else ""


## Darf das Overlay in dieses Spiel? { ok, grund, schutz }. grund: "" (ja), "aus" (nicht eingeschaltet),
## "windows", "emulator" (dort hält Uzai an und liegt durchsichtig darüber), "ordner" (Spielordner
## unbekannt oder nicht lesbar: Anti-Cheat ließe sich nicht ausschließen), "anticheat".
## namen: ordner_namen des Spielordners (im Hintergrund holen: große Ordner, langsame Platten).
static func erlaubt(g: Dictionary, windows: bool, namen: Array) -> Dictionary:
	var vor := vorab(g, windows)
	if vor != "" or namen.is_empty():
		return { "ok": false, "grund": vor if vor != "" else "ordner", "schutz": "" }
	var schutz := anticheat_in(namen)
	if schutz != "":
		return { "ok": false, "grund": "anticheat", "schutz": schutz }
	if not bool(g.get("overlay", false)):
		return { "ok": false, "grund": "aus", "schutz": "" }
	return { "ok": true, "grund": "", "schutz": "" }


## Der Kopf der Bilddatei (64 Byte, Zahlen 32 Bit, kleines Ende zuerst).
static func kopf(zaehler: int, sichtbar: bool, breite: int, hoehe: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(KOPF)
	b.fill(0)
	b.encode_u32(0, MAGIC)
	b.encode_u32(4, VERSION)
	b.encode_u32(8, zaehler & 0xFFFFFFFF)
	b.encode_u32(12, 1 if sichtbar else 0)
	b.encode_u32(16, breite)
	b.encode_u32(20, hoehe)
	return b


## Passt ein Bild dieser Größe in die Datei?
static func groesse_ok(breite: int, hoehe: int) -> bool:
	return breite >= 1 and hoehe >= 1 and breite <= MAX_BREITE and hoehe <= MAX_HOEHE


## Nächster gerader Zähler nach z (der ungerade dazwischen heißt: Uzai schreibt gerade).
static func naechster(z: int) -> int:
	return ((z | 1) + 1) & 0xFFFFFFFF


## Bild schreiben (RGBA8), ohne dass die Bibliothek je ein halbes sieht: Zähler ungerade, Kopf und
## Punkte, Zähler gerade. Die Datei wird nie kürzer (im Spiel ist sie abgebildet). Gibt den neuen
## Zähler zurück (−1: ging nicht).
static func bild_schreiben(pfad: String, img: Image, sichtbar: bool, zaehler: int) -> int:
	if img == null or not groesse_ok(img.get_width(), img.get_height()):
		return -1
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(pfad.get_base_dir())
	var f := FileAccess.open(pfad, FileAccess.READ_WRITE if FileAccess.file_exists(pfad) else FileAccess.WRITE_READ)
	if f == null:
		return -1
	var neu := naechster(zaehler)
	f.seek(8)
	f.store_32((neu - 1) & 0xFFFFFFFF)
	f.flush()
	f.seek(KOPF)
	f.store_buffer(img.get_data())
	f.seek(0)
	f.store_buffer(kopf(neu - 1, sichtbar, img.get_width(), img.get_height()))
	f.seek(8)
	f.store_32(neu)
	f.close()
	return neu


## Nur „zeigen/verstecken“ umstellen (das Bild bleibt). Gibt den neuen Zähler zurück (−1: keine Datei).
static func sichtbar_setzen(pfad: String, sichtbar: bool, zaehler: int) -> int:
	if not FileAccess.file_exists(pfad):
		return -1
	var f := FileAccess.open(pfad, FileAccess.READ_WRITE)
	if f == null or f.get_length() < KOPF:
		return -1
	var neu := naechster(zaehler)
	f.seek(8)
	f.store_32((neu - 1) & 0xFFFFFFFF)
	f.seek(12)
	f.store_32(1 if sichtbar else 0)
	f.seek(8)
	f.store_32(neu)
	f.close()
	return neu


## Bibliothek und Starter aus dem Paket in den Datenordner legen (dort braucht Windows sie als Dateien).
## Gibt den Ordner zurück ("" wenn etwas fehlt).
static func auslegen(ziel: String) -> String:
	DirAccess.make_dir_recursive_absolute(ziel)
	for n: String in DATEIEN:
		var quelle := "res://assets/overlay/" + n
		if not FileAccess.file_exists(quelle):
			return ""
		var daten := FileAccess.get_file_as_bytes(quelle)
		var dort := ziel.path_join(n)
		if FileAccess.file_exists(dort) and FileAccess.get_file_as_bytes(dort) == daten:
			continue
		var f := FileAccess.open(dort, FileAccess.WRITE)
		if f == null:
			# Im laufenden Spiel geladen: die Datei ist gesperrt, aber da.
			if FileAccess.file_exists(dort):
				continue
			return ""
		f.store_buffer(daten)
		f.close()
	return ziel


## Den Starter rufen (blockiert bis zu einigen Sekunden – im Hintergrund aufrufen, src/core/arbeit.gd).
## Gibt seine Zahl zurück (ERGEBNIS; 1 und 5 heißen: die Bibliothek läuft im Spiel).
static func starter(bin_dir: String, bits: int, pid: int, bild: String) -> int:
	if pid <= 4 or not (bits in [32, 64]) or bin_dir == "":
		return 10
	var exe := bin_dir.path_join("uzai-overlay-start%d.exe" % bits)
	var dll := bin_dir.path_join("uzai-overlay%d.dll" % bits)
	var aus: Array = []
	var code := OS.execute(exe, PackedStringArray([str(pid), dll.replace("/", "\\"), bild.replace("/", "\\")]), aus, false, false)
	return code if ERGEBNIS.has(code) else 18
