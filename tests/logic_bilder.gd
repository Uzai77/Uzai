extends Node
## Bilder ohne SteamGridDB-Schlüssel (Punkt 47): woher welches Bild kommt, Steam-Bilder für
## EA-/Epic-/PC-Spiele nur bei genau gleichem Namen, Downloads nur über https und begrenzt.
## Ohne Netz. Aufruf: godot --headless --path . res://tests/logic_bilder.tscn

const MediaS := preload("res://src/core/media.gd")
const NetS := preload("res://src/core/net.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_sources()
	_match()
	await _match_cached()
	_net()
	await _fehlt()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## „Wie viele Spiele sind ohne Cover?“ (media.gd, _fehlt_gemerkt): die bekannte Zahl sofort, das Nachzählen
## nebenbei über mehrere Bilder – nie wieder alle paar Sekunden ein ganzer Durchgang in einem Zug.
func _fehlt() -> void:
	print("Spiele ohne Cover: zählen und nachzählen")
	var spiele: Array = []
	for i in 400:
		spiele.append({ "id": "rom:fehlt%d" % i, "source": "rom", "system": "snes", "title": "Fehlt %d" % i,
			"images": { "cover": "da.png" } if i % 4 == 0 else {} })
	var liste := func() -> Array: return spiele
	check(Media._fehlt_gemerkt("probe", liste) == 300, "erster Aufruf zählt sofort (300 von 400 ohne Cover)")
	# Ein Spiel bekommt ein Bild, ohne dass sich der Stand ändert – wie eine Datei, die jemand in den Medienordner legt.
	spiele[1]["images"] = { "cover": "neu.png" }
	check(Media._fehlt_gemerkt("probe", liste) == 300 and not Media._fehlt_zaehlt.has("probe"), "frisch gezählt: die bekannte Zahl, kein Nachzählen")
	Media._fehlt_merk["probe"][1] = Time.get_ticks_msec() - Media.FEHLT_MS - 1
	check(Media._fehlt_gemerkt("probe", liste) == 300 and Media._fehlt_zaehlt.has("probe"), "älter als FEHLT_MS: die bekannte Zahl sofort, das Nachzählen läuft")
	await get_tree().process_frame
	check(Media._fehlt_zaehlt.has("probe"), "400 Spiele: nicht in einem Bild (Scheiben zu %d)" % Media.FEHLT_SCHEIBE)
	for i in 6:
		await get_tree().process_frame
	check(not Media._fehlt_zaehlt.has("probe") and Media._fehlt_gemerkt("probe", liste) == 299, "wenige Bilder später steht die neue Zahl")
	# Ändert sich währenddessen der Stand, gilt die frische Zählung – das alte Nachzählen überschreibt sie nicht.
	Media._fehlt_merk["probe"][1] = Time.get_ticks_msec() - Media.FEHLT_MS - 1
	Media._fehlt_gemerkt("probe", liste)
	spiele[2]["images"] = { "cover": "neu.png" }
	spiele[3]["images"] = { "cover": "neu.png" }
	Media.bilder_stand += 1
	check(Media._fehlt_gemerkt("probe", liste) == 297, "geänderter Stand: sofort neu gezählt")
	spiele[3]["images"] = {}
	for i in 8:
		await get_tree().process_frame
	check(not Media._fehlt_zaehlt.has("probe") and Media._fehlt_gemerkt("probe", liste) == 297, "ein überholtes Nachzählen ändert die Zahl nicht")


func _src(game: Dictionary, kind: String, opts := {}) -> Array:
	return Array(MediaS.remote_sources(game, kind, opts))


func _sources() -> void:
	print("Woher die Bilder kommen")
	var steam := { "source": "steam", "appid": "1172470" }
	check(_src(steam, "cover") == ["steam"] and _src(steam, "logo") == ["steam"], "Steam-Spiel: vom Steam-Server")
	check(_src(steam, "cover", { "steam": false, "sgdb": true }) == ["sgdb"], "Steam-Bilder aus: nur mit eigenem Schlüssel")
	var epic := { "source": "epic", "art": { "cover": "https://cdn1.epicgames.com/x.jpg" } }
	check(_src(epic, "cover") == ["art", "steam_match"], "Epic: erst Epics Katalogbild, dann Steam mit gleichem Namen")
	check(_src({ "source": "ea" }, "hero") == ["steam_match"], "EA: Steam-Bilder bei gleichem Namen")
	check(_src({ "source": "pc" }, "logo", { "sgdb": true }) == ["steam_match", "sgdb"], "PC-Spiel: Steam vor SteamGridDB")
	check(_src({ "source": "ea" }, "shot") == [], "Spielszene gibt es bei Steam nicht als Bildart")
	var rom := { "source": "rom", "system": "snes" }
	check(_src(rom, "cover") == ["libretro"] and _src(rom, "logo") == ["libretro"], "Emulator-Spiel: Cover und Schriftzug von Libretro")
	check(_src(rom, "hero") == ["steam_match"] and _src(rom, "hero", { "sgdb": true }) == ["sgdb", "steam_match"],
			"Hintergrund: SteamGridDB (mit Schlüssel), dann Steam bei gleichem Namen (Neuauflage)")
	check(_src(rom, "hero", { "steam": false }) == [] and _src({ "source": "disc", "system": "ps2" }, "hero", { "sgdb": true }) == ["sgdb", "steam_match"],
			"Steam-Bilder aus: ohne Schlüssel kein Hero (dann Retro-Bühne); Disc wie Emulator-Spiel")
	check(_src(rom, "cover") == ["libretro"] and _src(rom, "wide") == [], "Steam-Pendant nur für den Hintergrund, Cover bleiben vom System")
	_hero()
	check(_src(rom, "cover", { "libretro": false }) == [], "Libretro aus: nichts")
	check(_src({ "source": "disc", "system": "ps2" }, "shot", { "sgdb": true }) == ["shot"], "Disc: Spielszenen wie Emulator-Spiele, nie von SteamGridDB")
	check(_src({ "source": "disc", "system": "ps2" }, "cover") == ["libretro"], "Disc: Cover von Libretro")


## Hero-Tauglichkeit: Nur breite, große Bilder füllen den Kopf; alles andere ungeschnitten auf die
## Retro-Bühne (retro_buehne.gd).
func _hero() -> void:
	print("Taugt ein Bild als Hero?")
	check(MediaS.hero_tauglich(Vector2i(1920, 620)) and MediaS.hero_tauglich(Vector2i(3840, 1240)), "Steam/SteamGridDB-Hero")
	check(MediaS.hero_tauglich(Vector2i(1600, 900)) and MediaS.hero_tauglich(Vector2i(1600, 650)), "großes 16 : 9 (Wikipedia) und 1600 × 650 (SteamGridDB)")
	check(not MediaS.hero_tauglich(Vector2i(640, 480)) and not MediaS.hero_tauglich(Vector2i(256, 224)), "Spielszenen alter Systeme nie")
	check(not MediaS.hero_tauglich(Vector2i(1599, 600)), "unter 1600 breit nie")
	check(not MediaS.hero_tauglich(Vector2i(1600, 1200)) and not MediaS.hero_tauglich(Vector2i(2048, 1536)), "4 : 3 auch groß nicht (würde beschnitten)")
	check(not MediaS.hero_tauglich(Vector2i(1920, 0)) and not MediaS.hero_tauglich(Vector2i.ZERO), "kaputte Größe: nein")
	var items := [
		{ "url": "https://cdn2.steamgriddb.com/hero/klein.png", "width": 1280, "height": 413 },
		{ "url": "", "width": 1920, "height": 620 },
		{ "url": "https://cdn2.steamgriddb.com/hero/gross.png", "width": 1920, "height": 620 },
	]
	check(MediaS.sgdb_wahl(items, "hero") == "https://cdn2.steamgriddb.com/hero/gross.png", "SteamGridDB: kleiner Hero übersprungen")
	check(MediaS.sgdb_wahl(items.slice(0, 1), "hero") == "", "nur kleine Heroes: keiner")
	check(MediaS.sgdb_wahl(items, "cover") == "https://cdn2.steamgriddb.com/hero/klein.png", "Cover: das erste wie bisher")
	check(MediaS.sgdb_wahl([{ "url": "https://x/h.png" }], "hero") == "https://x/h.png", "ohne Größenangabe: wie bisher")
	check(MediaS.sgdb_wahl(null, "hero") == "" and MediaS.sgdb_wahl(["x", 3], "hero") == "", "kaputte Antwort: nichts")


func _match() -> void:
	print("Steam-Spiel mit gleichem Namen")
	var items := [
		{ "type": "app", "name": "Battlefield™ 2042", "id": 1517290 },
		{ "type": "app", "name": "Apex Legends™", "id": 1172470 },
		{ "type": "app", "name": "Mass Effect™ Legendary Edition", "id": 1328670 },
		{ "type": "sub", "name": "Apex Legends", "id": 9 },
		{ "type": "app", "name": "Legend of Zelda, The", "id": 77 },
	]
	check(MediaS.steam_title_match(items, "Apex Legends") == 1172470, "™ und Schreibweise egal")
	check(MediaS.steam_title_match(items, "Mass Effect Legendary Edition") == 1328670, "langer Name")
	check(MediaS.steam_title_match(items, "Battlefield 1") == 0, "nie ein anderer Teil der Reihe")
	check(MediaS.steam_title_match(items, "Die Sims 4") == 0 and MediaS.steam_title_match(items, "Apex") == 0, "kein unscharfer Treffer")
	check(MediaS.steam_title_match(items, "The Legend of Zelda") == 77, "„, The“ hinten zählt wie vorn")
	check(MediaS.steam_title_match([{ "type": "sub", "name": "Apex Legends", "id": 9 }], "Apex Legends") == 0, "nur Spiele, keine Pakete")
	check(MediaS.steam_title_match(null, "Apex Legends") == 0 and MediaS.steam_title_match(items, "") == 0, "kaputte Antwort, leerer Name")


func _match_cached() -> void:
	print("Gemerkte Treffer (ohne Netz)")
	var now := int(Time.get_unix_time_from_system())
	var hit := { "id": "ea:test1", "source": "ea", "title": "Apex Legends", "steam_match": 1172470, "steam_match_title": "Apex Legends",
			"steam_match_t": now - 90 * 86400 }
	check(await Media.steam_match_id(hit) == 1172470, "Treffer bleibt gemerkt")
	var none := { "id": "ea:test2", "source": "ea", "title": "Gibt Es Nicht", "steam_match": -1, "steam_match_title": "Gibt Es Nicht",
			"steam_match_t": now - 86400 }
	check(await Media.steam_match_id(none) == 0, "„nicht bei Steam“ gilt zwei Wochen")
	check(await Media.steam_match_id({ "id": "x", "source": "pc", "title": "" }) == 0, "ohne Namen keine Suche")


func _net() -> void:
	print("Downloads")
	check(NetS.download_allowed("https://shared.steamstatic.com/a.jpg") and not NetS.download_allowed("http://example.com/a.jpg") \
		and not NetS.download_allowed("file:///C:/Windows/win.ini") and not NetS.download_allowed("ftp://x/a.png"), "nur https")
	check(NetS.IMG_MAX_BYTES > 8 * 1024 * 1024 and NetS.IMG_MAX_BYTES <= 64 * 1024 * 1024, "Bilder größenbegrenzt")
