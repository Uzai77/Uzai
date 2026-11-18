extends "res://tests/probe_base.gd"
## Probe für die lebendigen Kacheln (Roadmap 101 → 124): Startseite mit allen Zuständen,
## Nahaufnahmen der einzelnen Kacheln (ruhend und wach), das Aufwachen als Bildfolge, eine
## Übersicht aller Zustände nebeneinander, Leichter Modus, Bibliothek, ausgeschaltet, helles Schema.
## Demo-Daten werden hier gesetzt (Freunde, Updates, Wunschliste, Erfolge, Patch, Statusseite).
## UZAI_KACHELN_ART=<ordner>: Probe-Cover (<quelle>_<id>.png), UZAI_DEMO_ART=<ordner>: Bild und
## Cover aus der Spielseiten-Probe. Ohne beides: Ersatz-Cover.

const Kacheln := preload("res://src/core/kacheln.gd")
const ForYou := preload("res://src/ui/components/for_you.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const Leicht := preload("res://src/core/leicht.gd")
const U := preload("res://src/ui/u.gd")

## Reihenfolge in „Zuletzt“: Kacheln mit und ohne Zustand gemischt.
const ORDER := ["steam:1245620", "ps2:74a8e64542ec02", "steam:1145360", "ps2:30fa359a43774f", "steam:1091500",
	"epic:DemoFortnite", "steam:413150", "steam:1086940", "steam:2379780", "steam:367520", "ps2:47af91016b6b94",
	"ps2:5e1005d21bcb60", "epic:DemoKinglet"]


func run() -> void:
	Config.set_value("theme.preset", "uzai")
	Config.set_value("theme.corners", "rund")
	Config.set_value("theme.cover_shape", "hoch")
	await wait(1.0)
	await _demo()
	main.goto("games", "zuletzt")
	await wait(0.8)
	# Die Demo legt eine Disc ein (Shadow of the Colossus gewählt): einen Schritt nach links.
	await press("left", 1, 0.05)
	# Aufwachen als Bildfolge (Elden Ring hat den Fokus: Freunde spielen gerade).
	var c: Control = Nav.focused()
	var at := 0.05
	for step in [[0.25, "a_0.3s_ruhend"], [0.75, "b_0.8s"], [0.95, "c_1.0s"], [1.15, "d_1.2s_wach"], [3.0, "e_3s"], [7.0, "f_7s_zoom"]]:
		await wait(float(step[0]) - at)
		at = float(step[0])
		await crop("20_aufwachen_" + str(step[1]), c)
	await shot("01_startseite_gesamt", 0.1)
	# Jede Kachel einmal gewählt und wach.
	var names := ["freunde", "ohne", "update_wartet", "ohne_okami", "rabatt_dlc", "server_gestoert", "neue_erfolge", "patch_heute", "update_laeuft",
			"freunde_einer"]
	for i in names.size():
		if i > 0:
			await press("right", 1, 0.05)
		await wait(1.5)
		await crop("1%d_%s" % [i, names[i]], Nav.focused())
		if names[i] == "rabatt_dlc":
			await shot("02_startseite_rabatt_gewaehlt", 0.1)
		if names[i] == "update_laeuft":
			# Fortschritt wandert live weiter.
			_set_update(0.81)
			await crop("1%da_%s_spaeter" % [i, names[i]], Nav.focused(), 0.3)
	await shot("03_startseite_weiter", 0.2)
	await _gallery()
	await _light()
	await _library()
	await _off()
	await _paper()


## Ausschnitt um eine Kachel (mit Spiegelung und etwas Raum drumherum).
func crop(name: String, c: Control, wait_s := 0.0) -> void:
	if wait_s > 0.0:
		await wait(wait_s)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var r := c.get_global_rect()
	var box := Rect2i(Vector2i(int(r.position.x) - 50, int(r.position.y) - 70), Vector2i(int(r.size.x) + 110, int(r.size.y) + 150))
	box = box.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var part := img.get_region(box)
	part.save_png(out.path_join(name + ".png"))
	print("Bild: ", name)


func _demo() -> void:
	var now := int(Time.get_unix_time_from_system())
	var art := OS.get_environment("UZAI_KACHELN_ART")
	var demo_art := OS.get_environment("UZAI_DEMO_ART")
	for i in ORDER.size():
		var g := Library.get_game(ORDER[i])
		if g.is_empty():
			continue
		g["last_played"] = now - 3600 * (i + 1)
		var imgs: Dictionary = g.get("images", {}) if g.get("images") is Dictionary else {}
		var f := art.path_join(str(ORDER[i]).replace(":", "_") + ".png") if art != "" else ""
		if f != "" and FileAccess.file_exists(f):
			imgs["cover"] = f
		if demo_art != "" and ORDER[i] == "ps2:74a8e64542ec02":
			imgs["cover"] = demo_art.path_join("rom/cover.png")
		if demo_art != "" and ORDER[i] == "steam:1245620":
			imgs["hero"] = demo_art.path_join("hero.jpg")
		g["images"] = imgs
		Media.forget(g)
	Library.forget_visible()
	# Freunde: Mira und Sana in Elden Ring, Jonas in Hollow Knight; Noor gerade ohne Spiel.
	for f in Social.steam_friends:
		if str(f.get("name", "")) == "Noor":
			f["state"] = "online"
			f["game"] = ""
			f["game_id"] = ""
	Social.steam_friends.append(
			{ "id": "76561190000000099", "name": "Sana", "avatar": "", "state": "game", "game": "ELDEN RING", "game_id": "1245620", "last": 0, "lobby": "", "server": "",
			"since": 0 })
	# Anstehende Updates (Elden Ring 2,4 GB, Hades 0,6 GB) und eins, das gerade über Uzai lädt.
	Installs.demo_fill()
	_set_update(0.46)
	# Wunschliste: das große DLC zu Cyberpunk 2077 im Angebot.
	if not Store.wishlist_loaded and not Store.wishlist_loading:
		Store.load_wishlist()
	for i in 40:
		if Store.wishlist_loaded:
			break
		await wait(0.1)
	Store.wishlist.append({ "appid": 2138330, "name": "Cyberpunk 2077: Phantom Liberty", "discount": 30, "price": 2099, "original": 2999, "parent": 1091500 })
	# Neue Erfolge: Stardew Valley hatte 40, jetzt 44 (nach einem Update).
	Kacheln._ach_loaded = true
	Kacheln._ach["steam:413150"] = { "n": 40, "plus": 0, "at": 0 }
	Achievements._games["steam:413150"] = { "source": "steam", "total": 44, "unlocked": 40, "list": [] }
	# Patch von heute für Baldur's Gate 3 (als Patchnotes markiert).
	ForYou._news_load()
	ForYou._news_cache["1086940"] = { "at": now, "ok": true,
			"items": [{ "title": "Hotfix 34: Feinschliff für Akt 3", "date": now - 2 * 3600, "text": "", "author": "", "patch": true }] }
	# Statusseite: Fortnite gestört (Matchmaking).
	Kacheln.set_status({ "at": now, "ok": true, "names": ["fortnite", "rocket league", "fall guys"], "bad": { "fortnite": "partial_outage" } })


func _set_update(frac: float) -> void:
	var id := "steam:2379780"
	Installs.items[id] = { "id": id, "store": "steam", "appid": 2379780, "title": "Balatro", "kind": "update", "phase": "downloading",
		"frac": frac, "text": "noch %d Min. · 38 MB/s" % int((1.0 - frac) * 6.0 + 1.0), "started": int(Time.get_unix_time_from_system()), "demo": true }
	Installs.changed.emit(id)


## Alle Zustände nebeneinander, erst ruhend, dann wach (wie beim Ruhen der Auswahl).
func _gallery() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = UzTheme.col("bg")
	U.full_rect(bg)
	layer.add_child(bg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.position = Vector2(96, 300)
	layer.add_child(row)
	var picks := [["steam:1245620", "Freunde spielen"], ["steam:2379780", "Update lädt"], ["epic:DemoFortnite", "Server gestört"],
		["steam:1145360", "Update wartet"], ["steam:1091500", "Rabatt (DLC)"], ["steam:413150", "Neue Erfolge"], ["steam:1086940", "Patch heute"]]
	var cards: Array = []
	for p in picks:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 18)
		var card = CoverCard.new().setup(Library.get_game(p[0]), false, Vector2(216, 288))
		card.live = true
		card.focus_mode = Control.FOCUS_NONE
		col.add_child(card)
		var l := U.label(str(p[1]), "s", "muted", "medium")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		row.add_child(col)
		cards.append(card)
	var head := U.label("Lebendige Kacheln – je Cover höchstens ein Zustand", "l", "text", "ui_bold")
	head.position = Vector2(96, 200)
	layer.add_child(head)
	await shot("04_uebersicht_ruhend", 1.5)
	for c in cards:
		c._live._wake()
	await shot("05_uebersicht_wach", 1.2)
	await shot("06_uebersicht_wach_zoom", 5.0)
	layer.queue_free()
	await wait(0.3)


## Leichter Modus: das Abzeichen steht still, kein Aufwachen, kein Zoom.
func _light() -> void:
	Leicht.active = true
	main.goto("games", "zuletzt")
	await wait(0.6)
	await _to_start()
	await press("right", 4, 0.1)
	await shot("07_leichter_modus_ruhend_2s", 2.0)
	await crop("07a_leicht_rabatt", Nav.focused())
	Leicht.active = false


func _library() -> void:
	main.open_library("alle", "Alle Spiele")
	await shot("08_bibliothek", 1.8)
	await press("right", 1, 0.1)
	await shot("08a_bibliothek_wach", 1.6)
	await press("b")
	await wait(0.6)


func _off() -> void:
	Config.set_value("system.live_tiles", false)
	main.goto("games", "zuletzt")
	await wait(0.6)
	await _to_start()
	await shot("09_ausgeschaltet", 1.4)
	Config.set_value("system.live_tiles", true)
	await wait(0.4)


func _paper() -> void:
	Config.set_value("theme.preset", "papier")
	await wait(1.2)
	# Das Farbschema baut alles neu (auch die Demo-Bibliothek): Bilder und Reihenfolge wieder setzen.
	await _demo()
	main.goto("games", "zuletzt")
	await wait(0.6)
	await _to_start()
	await press("right", 4, 0.1)
	await shot("10_papier_hell", 1.8)
	Config.set_value("theme.preset", "uzai")
	await wait(0.8)


## Startseite merkt sich die Stelle im Regal: zurück an den Anfang.
func _to_start() -> void:
	await press("left", 14, 0.06)
	await wait(0.4)
