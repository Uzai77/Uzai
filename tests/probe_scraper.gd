extends "res://tests/probe_base.gd"
## Probe „Spiele scrapen“: das Menü mit der Wahl der Quelle und die Bildwahl eines Spiels von
## ScreenScraper (Emulator-Spiel und Steam-Spiel). Ohne Netz: ein Probe-Programmzugang (nur in der
## Config dieses Datenordners), die Kandidaten aus der Beispielantwort (tests/fixtures/screenscraper) und farbige Vorschauen im Cache.

const SS := preload("res://src/core/screenscraper.gd")
const GID := "ps2:30fa359a43774f"


func run() -> void:
	Config.set_value("accounts.ss_devid", "probe")
	Config.set_value("accounts.ss_devpass", "probe")
	await wait(1.0)
	var l = load("res://src/ui/layers/spiele_scrapen.gd").new()
	l.main = main
	main.open_layer(l)
	await shot("scraper_menue", 1.2)
	await press("b")
	await wait(0.6)
	var g := Library.get_game(GID)
	if g.is_empty():
		for x in Library.visible_games():
			if Media.ss_bildwahl_ok(x):
				g = x
				break
	var info := SS.lesen(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/screenscraper/jeuInfos.json")), "de")
	var liste: Dictionary = info.kandidaten
	var i := 0
	for e in liste.get("cover", []):
		_vorschau(str(e.url), 240, Vector2i(240, 340), i)
		i += 1
	Media._ss_kand[str(g.id)] = { "ok": true, "grund": "", "id": "3017", "name": "Okami", "liste": liste, "t": int(Time.get_unix_time_from_system()) }
	main.open_art_picker(g, "ss")
	await shot("scraper_bildwahl", 2.5)
	await press("b")
	await wait(0.4)
	await _steam()


## Bildwahl eines Steam-Spiels mit ScreenScraper als Quelle (PC Windows, Beispielantwort jeuRecherche_pc).
func _steam() -> void:
	var g := {}
	for x in Library.visible_games():
		if str(x.get("source", "")) == "steam":
			g = x
			break
	if g.is_empty():
		return
	var treffer := SS.suche_lesen(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/screenscraper/jeuRecherche_pc.json")), "de")
	var info: Dictionary = SS.bester_treffer(treffer, "DOOM", "windows", 2016)
	var liste: Dictionary = info.kandidaten
	var i := 3
	for e in liste.get("cover", []):
		_vorschau(str(e.url), 240, Vector2i(240, 340), i)
		i += 1
	Media._ss_kand[str(g.id)] = { "ok": true, "grund": "", "id": str(info.id), "name": str(info.name), "liste": liste, "t": int(Time.get_unix_time_from_system()) }
	main.open_art_picker(g, "ss")
	await shot("scraper_bildwahl_steam", 2.5)
	await press("b")
	await wait(0.4)


## Eine farbige Fläche als Vorschau in den Cache, wo Media.ss_vorschau sie sucht.
func _vorschau(url: String, breite: int, groesse: Vector2i, n: int) -> void:
	var u := SS.mit_zugang(SS.vorschau(url, breite), SS.zugang())
	var img := Image.create(groesse.x, groesse.y, false, Image.FORMAT_RGBA8)
	var c := Color.from_hsv(fmod(0.08 + n * 0.21, 1.0), 0.55, 0.7)
	for y in groesse.y:
		var t := float(y) / groesse.y
		img.fill_rect(Rect2i(0, y, groesse.x, 1), c.darkened(t * 0.6))
	var p := Media.url_path(u)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)
