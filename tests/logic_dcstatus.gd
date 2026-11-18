extends Node
## Discord-Status beim Spielen (src/core/game_presence.gd, Media.presence_image_known): welche
## Bildadressen in den Status dürfen (nur https, nur bekannte Bildserver, nie eigene Dateien),
## wie die Aktivität aussieht (Titel, Laden bzw. System · Uzai, Startzeit), dass ein Spiel sich
## ausblenden lässt und dass Uzai nie einen Beitreten-Knopf erfindet. Dazu die gemerkte Herkunft
## geladener Bilder (Media.note_url): der Status zeigt das Cover, das Uzai auch zeigt.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_dcstatus.tscn → „Ergebnis: alles ok“

const GamePresence := preload("res://src/core/game_presence.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Bildadressen")
	_images()
	print("Aktivität")
	_activity()
	print("Herkunft der Bilder")
	_origin()
	print("Cover für den Status")
	_cover()
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _images() -> void:
	for ok in [
		"https://shared.steamstatic.com/store_item_assets/steam/apps/1245620/library_600x900.jpg",
		"https://shared.steamstatic.com/store_item_assets/steam/apps/2/abc123/library_capsule_2x.jpg?t=1700000000",
		"https://cdn1.epicgames.com/offer/fn/EGS_Fortnite_1200x1600.jpg",
		"https://cdn2.steamgriddb.com/grid/0a1b2c.png",
		"https://thumbnails.libretro.com/Sony%20-%20PlayStation%202/Named_Boxarts/Okami%20(USA).png",
		"https://raw.githubusercontent.com/libretro-thumbnails/Sony_-_PlayStation_2/master/Named_Boxarts/Okami.png",
	]:
		check(GamePresence.image_ok(ok), "erlaubt: " + ok.left(60))
	for bad in [
		"http://shared.steamstatic.com/x.jpg",
		"https://evil.example/cover.jpg",
		"https://shared.steamstatic.com.evil.de/x.jpg",
		"https://evil.de/shared.steamstatic.com/x.jpg",
		"https://user:pw@shared.steamstatic.com/x.jpg",
		"https://shared.steamstatic.com@evil.de/x.jpg",
		"https://shared.steamstatic.com:8443/x.jpg",
		"https://raw.githubusercontent.com/someone/else/main/x.png",
		"https://shared.steamstatic.com",
		"https://shared.steamstatic.com/",
		"https://shared.steamstatic.com?x=1",
		"file:///C:/Users/Ich/Bilder/cover.png",
		"C:/Users/Ich/AppData/Roaming/Uzai/media/ps2/Okami.png",
		"https://shared.steamstatic.com/a b.jpg",
		"https://shared.steamstatic.com/a\"onerror.jpg",
		"https://shared.steamstatic.com/a\nb.jpg",
		"https://shared.steamstatic.com/" + "x".repeat(260) + ".jpg",
		"",
	]:
		check(not GamePresence.image_ok(bad), "abgelehnt: " + bad.c_escape().left(60))


func _activity() -> void:
	var steam := { "id": "steam:1245620", "source": "steam", "appid": 1245620, "title": "ELDEN RING" }
	var img := "https://shared.steamstatic.com/store_item_assets/steam/apps/1245620/library_600x900.jpg"
	var a := GamePresence.activity(steam, img, 1700000000)
	check(a.details == "ELDEN RING" and a.state == "Steam · Uzai" and int(a.start) == 1700000000, "Steam: Titel, „Steam · Uzai“, Startzeit")
	check(a.get("image", "") == img and a.get("large_text", "") == "ELDEN RING", "Steam: Cover mit Titel als Hinweis")
	check(int(a.get("display", -1)) == 2, "Mitgliederliste zeigt den Spieltitel („Spielt ELDEN RING“), nicht „Spielt Uzai“")
	var emu := { "id": "rom:x", "source": "rom", "system": "ps2", "title": "Ōkami" }
	var e := GamePresence.activity(emu, "C:/Uzai/media/ps2/Okami.png", 5, "PlayStation 2")
	check(e.state == "PlayStation 2 · Uzai", "Emulator: System · Uzai")
	check(not e.has("image") and not e.has("large_text"), "eigene Datei als Cover: kein Bild im Status")
	check(GamePresence.activity({ "source": "epic", "title": "Alan Wake 2" }, "", 0).state == "Epic Games · Uzai", "Epic: „Epic Games · Uzai“")
	check(GamePresence.activity({ "source": "ea", "title": "Die Sims 4" }, "", 0).state == "EA app · Uzai", "EA: „EA app · Uzai“")
	check(GamePresence.activity({ "source": "pc", "title": "Hades" }, "", 0).state == "PC · Uzai", "eigenes PC-Spiel: „PC · Uzai“")
	check(GamePresence.activity({ "source": "link", "title": "Etwas" }, "", 0).state == "Uzai", "unbekannte Herkunft: nur „Uzai“")
	check(GamePresence.activity(steam, img, -50).start == 0, "Startzeit nie negativ")
	var hidden := steam.duplicate()
	hidden["presence_hidden"] = true
	check(GamePresence.activity(hidden, img, 1).is_empty(), "je Spiel ausgeblendet: nichts")
	check(GamePresence.activity({ "source": "steam", "title": "  " }, img, 1).is_empty(), "ohne Titel: nichts")
	var long := GamePresence.activity({ "source": "pc", "title": "L".repeat(300) }, "", 0)
	check(str(long.details).length() <= GamePresence.TEXT_MAX and str(long.details).ends_with("…"), "langer Titel gekürzt auf Discords Grenze")
	check(GamePresence.activity({ "source": "pc", "title": "Q" }, "", 0).details == "„Q“", "Titel aus einem Zeichen: für Discord auf zwei gebracht")
	check(GamePresence.activity({ "source": "pc", "title": "Zwei\nZeilen" }, "", 0).details == "Zwei Zeilen", "Zeilenumbrüche fallen weg")
	# Kein Beitreten: Knöpfe dürfen nur Webadressen öffnen, Discords „Beitreten“ erreicht nur dieselbe App.
	for k in ["buttons", "secrets", "party", "instance"]:
		check(not a.has(k), "kein „%s“ im Status (kein Beitreten-Knopf)" % k)


func _origin() -> void:
	var g := { "id": "test:origin", "title": "Test" }
	var u := "https://thumbnails.libretro.com/Nintendo%20-%20GameCube/Named_Boxarts/Test.png"
	Media.note_url(g, "/daten/cache/img/libretro/a_cover.png", u)
	check(g.image_urls.get("/daten/cache/img/libretro/a_cover.png", "") == u, "Herkunft gemerkt (Pfad → Adresse)")
	Media.note_url(g, "/daten/cache/img/libretro/a_cover.png", u + "?2")
	check((g.image_urls as Dictionary).size() == 1 and str(g.image_urls.values()[0]).ends_with("?2"), "gleicher Pfad: neue Adresse ersetzt die alte")
	for i in 12:
		Media.note_url(g, "/p/%d.png" % i, "https://cdn2.steamgriddb.com/%d.png" % i)
	check((g.image_urls as Dictionary).size() == Media.URLS_MAX and not (g.image_urls as Dictionary).has("/p/0.png"),
			"höchstens %d je Spiel, die ältesten gehen" % Media.URLS_MAX)
	var none := { "title": "ohne ID" }
	Media.note_url(none, "/x.png", u)
	check(not none.has("image_urls"), "ohne Spiel-ID: nichts gemerkt")
	Media.note_url(g, "", u)
	Media.note_url(g, "/y.png", "")
	check(not (g.image_urls as Dictionary).has("") and not (g.image_urls as Dictionary).has("/y.png"), "leerer Pfad oder leere Adresse: nichts")


func _cover() -> void:
	var dir := Config.path("dcstatus-test")
	DirAccess.make_dir_recursive_absolute(dir)
	var shown := dir.path_join("libretro_cover.png")
	var own := dir.path_join("eigenes.png")
	for p in [shown, own]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("x")
		f.close()
	var lr := "https://thumbnails.libretro.com/Sony%20-%20PlayStation%202/Named_Boxarts/Okami%20(USA).png"
	var emu := { "id": "rom:okami", "source": "rom", "system": "ps2", "title": "Okami",
		"images_auto": { "cover": shown }, "image_urls": { shown: lr } }
	check(Media.presence_image_known(emu) == lr, "Emulator: Adresse des Covers, das Uzai zeigt")
	var custom := emu.duplicate(true)
	custom["images"] = { "cover": own }
	check(Media.presence_image_known(custom) == "", "eigenes Bild gewählt: dessen Datei hat keine Adresse – nie die Datei, nie die alte Adresse")
	var bad := emu.duplicate(true)
	bad["image_urls"] = { shown: "https://evil.example/x.png" }
	check(Media.presence_image_known(bad) == "", "gemerkte Adresse eines fremden Servers: nie in den Status")
	var epic := { "id": "epic:aw2", "source": "epic", "title": "Alan Wake 2", "images": { "cover": own },
		"art": { "cover": "https://cdn1.epicgames.com/offer/aw2/cover.jpg" } }
	check(Media.presence_image_known(epic) == "https://cdn1.epicgames.com/offer/aw2/cover.jpg", "Epic mit eigenem Bild: Epics Katalogbild")
	check(Media.presence_appid({ "source": "steam", "appid": "1245620" }) == 1245620, "Steam: eigene App-ID")
	check(Media.presence_appid({ "source": "ea", "steam_match": 1222670 }) == 1222670, "EA-Spiel mit gleichnamigem Steam-Spiel: dessen Bilder")
	check(Media.presence_appid({ "source": "epic", "steam_match": -1 }) == 0, "kein Steam-Treffer: keine App-ID")
	check(Media.presence_appid({ "source": "rom", "appid": 5 }) == 0, "Emulator-Spiel: nie Steam")
	Media._assets_loaded = true
	Media._assets["990001"] = { "asset_url_format": "steam/apps/990001/h4sh/${FILENAME}", "library_capsule": "library_600x900.jpg",
			"_t": int(Time.get_unix_time_from_system()) }
	var neu := { "id": "steam:990001", "source": "steam", "appid": 990001, "title": "Neu" }
	check(Media.presence_image_known(neu) == Media.STORE_ASSETS + "steam/apps/990001/h4sh/library_600x900.jpg",
			"Steam: Adresse mit Prüfsumme aus den gemerkten Shop-Angaben")
	check(Media.presence_image_known({ "id": "steam:5", "source": "steam", "appid": 5, "title": "Unbekannt" }) == "",
			"Steam ohne gemerkte Angaben: ohne Warten noch nichts (kommt nach)")
