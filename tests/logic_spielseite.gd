extends Node
## Spielseite der Bibliothek: „Fast geschafft“, Suchwort für den Soundtrack, installierte
## Erweiterungen aus Steams appmanifest und Patchnotes unter den Neuigkeiten (Fixtures in
## tests/fixtures/spielseite).
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_spielseite.tscn → „Ergebnis: alles ok“

const GamePage := preload("res://src/ui/layers/game_page.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const VDF := preload("res://src/library/vdf.gd")
const FIX := "res://tests/fixtures/spielseite/"
const RetroBuehne := preload("res://src/ui/components/retro_buehne.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Fast geschafft")
	var list := [
		{ "title": "Erster Schritt", "unlocked": true, "rarity": 92.0 },
		{ "title": "Selten", "unlocked": false, "rarity": 6.5 },
		{ "title": "Häufig", "unlocked": false, "rarity": 48.2 },
		{ "title": "Geheim", "unlocked": false, "rarity": 71.0, "hidden": true },
		{ "title": "Sehr häufig", "unlocked": false, "rarity": 63.0 },
		{ "title": "Grenze", "unlocked": false, "rarity": 35.0 },
		{ "title": "Knapp drunter", "unlocked": false, "rarity": 34.9 },
	]
	var al := GamePage.almost({ "total": 7, "unlocked": 1, "list": list })
	var names: Array = (al.get("list", []) as Array).map(func(a: Dictionary) -> String: return str(a.title))
	check(names == ["Sehr häufig", "Häufig", "Grenze"], "nur häufige offene, häufigste zuerst, geheime nicht (%s)" % [names])
	check(int(al.get("left", 0)) == 6 and not al.get("near", true), "noch 6 offen, nicht kurz vor 100 %")
	var many: Array = []
	for i in 9:
		many.append({ "title": "E%d" % i, "unlocked": false, "rarity": 40.0 + i })
	check((GamePage.almost({ "total": 10, "unlocked": 1, "list": many }).list as Array).size() == GamePage.ALMOST_SHOWN,
			"höchstens %d Karten" % GamePage.ALMOST_SHOWN)
	check(GamePage.almost({ "total": 9, "unlocked": 0, "list": many }).is_empty(), "noch nichts frei: nicht „fast geschafft“")
	check(GamePage.almost({ "total": 3, "unlocked": 1, "list": [{ "title": "R", "unlocked": false, "rarity": 2.0 }] }).is_empty(),
			"nur seltene, weit weg von 100 %: nichts")
	# Kurz vor 100 %: auch seltene; ohne Anteil (manche Quellen) die übrigen offenen.
	var near := GamePage.almost({ "total": 10, "unlocked": 8, "list": [
		{ "title": "A", "unlocked": true, "rarity": 80.0 }, { "title": "Ohne", "unlocked": false, "rarity": -1.0 },
		{ "title": "Selten", "unlocked": false, "rarity": 3.1 }] })
	check(near.get("near", false) and int(near.left) == 2, "80 %: kurz vor 100 %, noch 2")
	check((near.list as Array).size() == 2 and str(near.list[0].title) == "Selten", "kurz vor 100 %: seltene zuerst nach Anteil, dann ohne Anteil")
	check(GamePage.almost({ "total": 4, "unlocked": 4, "list": [] }).is_empty(), "alles geschafft: nichts")
	check(GamePage.almost({}).is_empty() and GamePage.almost({ "total": 0 }).is_empty(), "ohne Erfolge: nichts")
	check(GamePage.almost({ "total": 3, "unlocked": 1, "list": ["kaputt", null, { "title": "H", "rarity": 50.0 }] }).list.size() == 1,
			"kaputte Einträge fallen weg")

	print("Soundtrack-Suche")
	check(GamePage.soundtrack_query("ELDEN RING™") == "ELDEN RING Soundtrack", "™ fällt weg")
	check(GamePage.soundtrack_query("  Hades®  II ") == "Hades II Soundtrack", "® und doppelte Leerzeichen fallen weg")
	check(GamePage.soundtrack_query("™") == "" and GamePage.soundtrack_query("") == "", "ohne Titel: kein Suchwort")

	print("Erweiterungen aus Steams appmanifest")
	var acf := VDF.parse_file(FIX + "appmanifest_1245620.acf")
	var have := SteamScanner.installed_dlc(acf)
	check(have.has(2778580) and have.has(9990000), "dlcappid in InstalledDepots, auch anders geschrieben")
	check(have.size() == 2, "Depots ohne Erweiterung und kaputte IDs zählen nicht (%s)" % [have.keys()])
	check(SteamScanner.installed_dlc({}).is_empty() and SteamScanner.installed_dlc({ "AppState": { "InstalledDepots": "x" } }).is_empty(),
			"kaputtes appmanifest: leer")
	# Bibliotheksordner wie bei Steam: <root>/steamapps/appmanifest_<appid>.acf
	var root := Config.path("spielseite-steam")
	DirAccess.make_dir_recursive_absolute(root.path_join("steamapps"))
	var src := FileAccess.get_file_as_string(FIX + "appmanifest_1245620.acf")
	var f := FileAccess.open(root.path_join("steamapps/appmanifest_1245620.acf"), FileAccess.WRITE)
	f.store_string(src)
	f.close()
	check(SteamScanner.installed_dlc_of(root, 1245620).size() == 2, "im Bibliotheksordner gefunden")
	check(SteamScanner.installed_dlc_of(root, 367520).is_empty() and SteamScanner.installed_dlc_of("", 1245620).is_empty(), "anderes Spiel oder ohne Steam: leer")
	check(Store.dlc_installed(0).is_empty(), "ohne App-ID: leer")

	print("Neuigkeiten und Patchnotes")
	var news := Store.parse_news(JSON.parse_string(FileAccess.get_file_as_string(FIX + "news.json")), 3)
	check(news.size() == 2, "ohne Titel fällt weg")
	check(news[0].patch and not news[1].patch, "Patchnotes erkannt, kaputte Tags stören nicht")
	var t0 := str(news[0].text)
	check(not t0.contains("http") and not t0.contains("[url") and t0.contains("Mehr"), "Links nur als Text, ohne Adresse")
	check(not t0.contains("<script") and not t0.contains("STEAM_CLAN_IMAGE") and t0.contains("• Absturz beim Laden behoben."),
			"kein HTML, keine Bilder, Aufzählung bleibt")
	check(str(news[1].title) == "Shadow of the Erdtree & \"Nightreign\"" and str(news[1].text).contains("für ein Jahr <3"), "HTML-Zeichen lesbar")

	_retro()
	_eigene()

	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Eigene Screenshots stehen im eigenen Abschnitt, nicht unter „Bilder“ (Szenen aus dem Netz).
func _eigene() -> void:
	print("Eigene Screenshots getrennt von Bilder")
	var me := FileAccess.get_file_as_string("res://src/core/media.gd")
	var sc := me.substr(me.find("func screenshots("), 1600)
	check(not sc.contains("Capture.for_game"), "„Bilder“ ohne deine eigenen Bildschirmfotos")
	var gp := FileAccess.get_file_as_string("res://src/ui/layers/game_page.gd")
	var bc := gp.substr(gp.find("func _build_captures("), 1200)
	check(bc.contains("\"Deine Screenshots\"") and bc.contains("Capture.for_game(game)"), "eigener Abschnitt „Deine Screenshots“")


## Retro-Bühne: Emulator-Spiele ohne Hero zeigen die Szene ungeschnitten, ganzzahlig vergrößert.
func _retro() -> void:
	print("Retro-Bühne: ganzzahlig, ungeschnitten")
	var box := Vector2(640, 480)
	check(RetroBuehne.faktor(Vector2i(320, 240), box) == 2.0 and RetroBuehne.faktor(Vector2i(256, 224), box) == 2.0,
			"240 Zeilen (PS1, SNES) zweifach")
	check(RetroBuehne.faktor(Vector2i(160, 144), box) == 3.0 and RetroBuehne.faktor(Vector2i(100, 80), box) == 3.0,
			"Game Boy dreifach, nie mehr als dreifach")
	check(RetroBuehne.faktor(Vector2i(256, 240), Vector2(500, 470)) == 1.0, "passt es nicht zweimal: einmal (nie 1,9-fach)")
	var f := RetroBuehne.faktor(Vector2i(1280, 960), box)
	check(is_equal_approx(f, 0.5), "größer als die Fläche: stufenlos kleiner, nicht beschnitten (%s)" % f)
	check(RetroBuehne.faktor(Vector2i(320, 240), box, 2.0) == 2.0 and RetroBuehne.faktor(Vector2i(256, 224), Vector2(420, 400), 2.0) == 1.5,
			"4K: ganzzahlig in echten Bildpunkten (3 × 224 = 672 Punkte)")
	check(RetroBuehne.faktor(Vector2i(160, 144), Vector2(1200, 1000), 2.0) == 3.0, "4K: höchstens dreifach in Uzai-Punkten")
	check(RetroBuehne.faktor(Vector2i.ZERO, box) == 0.0 and RetroBuehne.faktor(Vector2i(320, 240), Vector2.ZERO) == 0.0, "nichts zu zeigen: 0")
	check(RetroBuehne.pixelbild(Vector2i(240, 160)) and RetroBuehne.pixelbild(Vector2i(512, 448)) and not RetroBuehne.pixelbild(Vector2i(640, 480)),
			"Pixelbild (hart vergrößert) bis 512")
	var r := RetroBuehne.schirm_rect(Vector2i(320, 240), Rect2(867, 28, 640, 480), 1.0, true)
	check(r == Rect2(867, 28, 640, 480), "füllt die Fläche, wenn es aufgeht (%s)" % [r])
	var r2 := RetroBuehne.schirm_rect(Vector2i(240, 160), Rect2(867, 28, 640, 480), 1.0, true)
	check(r2.size == Vector2(480, 320) and r2.end == Vector2(1507, 508), "rechts und unten bündig (%s)" % [r2])
	var r3 := RetroBuehne.schirm_rect(Vector2i(250, 200), Rect2(10.25, 0, 400, 301), 1.5)
	check(is_equal_approx(r3.position.x * 1.5, roundf(r3.position.x * 1.5)) and is_equal_approx(r3.size.x * 1.5, roundf(r3.size.x * 1.5)),
			"in ganzen Bildpunkten (%s)" % [r3])
	print("Retro-Bühne im Kopf der Spielseite")
	var cw := GamePage.cover_width(1920.0)
	var rb := GamePage.retro_box(1920.0, cw, 508.0)
	check(rb.size == Vector2(640, 480) and is_equal_approx(rb.end.y, 508.0), "640 × 480 in 1080p, unten bündig mit der Hülle (%s)" % [rb])
	check(is_equal_approx(rb.end.x, 1920.0 - GamePage.GUT - cw - GamePage.RETRO_ABSTAND), "Luft zur Hülle")
	check(GamePage.retro_text_raum(1920.0, cw) <= rb.position.x - GamePage.GUT - GamePage.RETRO_ABSTAND + 0.5
			and GamePage.retro_text_raum(1920.0, cw) >= 600.0, "Titel und Knöpfe enden vor dem Bildschirm")
	check(GamePage.retro_box(1920.0, cw, 300.0).position.y == GamePage.RETRO_OBEN, "nie höher als der obere Rand")
	check(GamePage.retro_box(1280.0, GamePage.cover_width(1280.0), 450.0).size.x == 427.0, "kleinere Oberfläche: ein Drittel")
	var gp_src := (load("res://src/ui/layers/game_page.gd") as GDScript).source_code
	check(not gp_src.contains("_set_hero(t3, t3.get_width() < 1000, 0.8)") and gp_src.contains("_retro_zeigen(t3)"),
			"kleine Szene wird nicht mehr gestreckt und beschnitten")
