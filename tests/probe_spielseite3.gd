extends "res://tests/probe_base.gd"
## Spielseite (Kopf mit Knöpfen und Pillen) und Profil als Konsolen-Profil (Demo): Steam-Spiel mit Erfolgen und
## Freunden, Emulator-Spiel mit Spielstand, nicht installiertes Spiel, eigenes Profil (A auf dem
## Bild: Status; Woche, Vitrine), Profil eines Freundes mit Vergleich. Ausgabe „SP ok/FAIL …“.

const FriendProfile := preload("res://src/ui/layers/friend_profile.gd")
const QuickResume := preload("res://src/core/quick_resume.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("SP %s %s" % ["ok  " if cond else "FAIL", what])


func _top() -> Control:
	return Nav.layers.back() if not Nav.layers.is_empty() else null


func _top_name() -> String:
	var t := _top()
	if t == null:
		return ""
	var s: Script = t.get_script()
	return s.resource_path.get_file() if s else ""


func _close_all() -> void:
	while _top():
		_top().close()
		await wait(0.3)


func _key(key: String) -> Control:
	for c in get_tree().root.find_children("*", "", true, false):
		if c is Control and str(c.get_meta("uz_key", "")) == key and (c as Control).is_visible_in_tree():
			return c
	return null


## Ein Spielstand für das PS2-Spiel, damit die Pille „Spielstände“ zu sehen ist (Datei und Bild
## im Datenordner der Probe).
func _spielstand(gid: String) -> void:
	var dir := Config.path("probe_staende")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("stand.p2s"), FileAccess.WRITE)
	f.store_string("probe")
	f.close()
	var img := Image.create(320, 180, false, Image.FORMAT_RGB8)
	img.fill(Color(0.35, 0.42, 0.55))
	img.save_png(dir.path_join("stand.png"))
	QuickResume.add(gid, { "emulator": QuickResume.emulator_id(Library.get_game(gid)), "file": dir.path_join("stand.p2s"),
		"shot": dir.path_join("stand.png"), "at": int(Time.get_unix_time_from_system()) - 7200 }, "auto")


func run() -> void:
	# Steam-Spiel mit Erfolgen, Freunden und Runden.
	main.open_game(Library.get_game("steam:1245620"))
	await wait(1.6)
	_ck(_key("gp:k:zeit") != null and _key("gp:k:erfolge") != null and _key("gp:k:freunde") != null, "Pillen: Spielzeit, Erfolge, Freunde")
	_ck(_key("gp:opts") != null and _key("gp:fav") != null, "Knöpfe im Kopf: Optionen und Favorit")
	var pille := _key("gp:k:erfolge")
	_ck(pille != null and pille.size.y <= 60.0, "Pillen sind klein (%s)" % str(pille.size if pille else Vector2.ZERO))
	_ck(pille != null and pille.get_global_rect().end.y <= _key("gp:play").get_global_rect().end.y + 90.0, "Pillen direkt unter den Knöpfen")
	await shot("01_steam", 0.6)
	await press("down")
	_ck(str(Nav.focused().get_meta("uz_key", "")).begins_with("gp:k:"), "runter: eine Pille")
	await press("down")
	await wait(0.4)
	_ck(str(Nav.focused().get_meta("uz_key", "")).begins_with("gp:ach:"), "weiter runter: die Erfolge-Reihe (%s)" % str(Nav.focused().get_meta("uz_key", "")))
	await press("up", 2)
	await wait(0.3)
	_ck(str(Nav.focused().get_meta("uz_key", "")) == "gp:play", "zweimal hoch: wieder Spielen (%s)" % str(Nav.focused().get_meta("uz_key", "")))
	Nav.focus(_key("gp:fav"), true)
	var vorher := bool(Library.get_game("steam:1245620").get("favorite", false))
	await press("a")
	await wait(0.2)
	_ck(bool(Library.get_game("steam:1245620").get("favorite", false)) != vorher, "Herz: Favorit an/aus")
	await press("a")
	await wait(0.2)
	Nav.focus(_key("gp:k:erfolge"), true)
	await press("a")
	await wait(0.9)
	_ck(_top_name() == "game_achievements.gd", "A auf Erfolge: alle Erfolge des Spiels (%s)" % _top_name())
	await _close_all()
	# Emulator-Spiel (PS2) mit Spielstand.
	var ps2 := "ps2:74a8e64542ec02"
	_spielstand(ps2)
	main.open_game(Library.get_game(ps2))
	await wait(1.6)
	_ck(_key("gp:k:stand") != null, "Emulator-Spiel: Pille Spielstände")
	await shot("02_emulator", 0.5)
	await _close_all()
	# Nicht installiert (Epic).
	main.open_game(Library.get_game("epic:DemoControl"))
	await shot("03_nicht_installiert", 1.6)
	_ck(str(Nav.focused().get_meta("uz_key", "")) == "gp:play", "Fokus auf der Haupthandlung")
	await _close_all()
	# Eigenes Profil: Kopf wählbar (A: Status), Woche, Vitrine.
	main.goto("achievements", "profil")
	await wait(2.4)
	_ck(_key("prof:kopf") != null and _key("prof:woche") != null and _key("g:ps2:74a8e64542ec02") != null, "Profil: Kopf, Woche, Vitrine")
	await shot("04_profil", 0.4)
	Nav.focus(_key("prof:kopf"), true)
	await press("a")
	await wait(0.9)
	_ck(_top_name() == "my_profile.gd", "A auf dem Bild: Dein Status (%s)" % _top_name())
	await press("b")
	await wait(0.6)
	await press("down", 2)
	await shot("05_profil_vitrine", 0.8)
	# Freund: Vergleich, Reihen.
	var l = FriendProfile.new()
	l.friend = Social.steam_friends[0]
	l.main = main
	main.open_layer(l)
	await wait(3.0)
	_ck(_key("fp:vergleich") != null and _key("fp:zahlen") != null, "Freund: Vergleich und Zahlenzeile")
	await shot("06_freund", 0.3)
	await _close_all()
	print("SP Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
