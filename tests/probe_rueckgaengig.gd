extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Rückgängig (Roadmap 95) – Spiel ausblenden, Favorit weg, Aufnahme in den
## Papierkorb, Ordner löschen; jeweils die Mitteilung mit „Rückgängig“ und der Stand danach.
## Aufnahmen werden hier nie wirklich gelöscht: jede wird zurückgenommen.
## Aufruf siehe probe_base.gd.


func run() -> void:
	var all := Library.visible_games()
	var g: Dictionary = all[0]
	var gid := str(g.id)

	# 1. Ausblenden in den Spieloptionen, dann View.
	main.open_game_options(g)
	await wait(0.8)
	await _focus("opt:Ausblenden")
	await press("a")
	await shot("01_ausgeblendet_rueckgaengig", 0.9)
	_check(not Library.is_visible(Library.get_game(gid)) and Undo.pending() > 0, "ausgeblendet, Rückgängig steht")
	await press("view")
	await shot("02_zurueckgenommen", 0.9)
	_check(Library.is_visible(Library.get_game(gid)) and Undo.pending() == 0, "wieder zu sehen")
	await press("b")
	await wait(0.6)

	# 2. Favorit weg unter „Favoriten“.
	var fav: Dictionary = Library.favorites()[0] if not Library.favorites().is_empty() else g
	if not bool(fav.get("favorite", false)):
		Library.set_field(str(fav.id), "favorite", true)
	main.goto("games", "favoriten")
	await wait(1.2)
	main.sections["games"].call("_toggle_fav", fav)
	await shot("03_kein_favorit_mehr", 0.9)
	_check(not bool(Library.get_game(str(fav.id)).get("favorite", false)), "kein Favorit mehr")
	await press("view")
	await shot("04_favorit_zurueck", 1.0)
	_check(bool(Library.get_game(str(fav.id)).get("favorite", false)), "Favorit wieder da")
	var foc: Control = Nav.focused()
	_check(foc != null and foc.get("game") is Dictionary and str(foc.game.get("id", "")) == str(fav.id), "Fokus wieder auf dem Spiel")

	# 3. Aufnahme in den Papierkorb (eigener Ordner im Datenordner der Probe).
	var dir := Config.path("probe_clips")
	DirAccess.make_dir_recursive_absolute(dir)
	Config.set_value("capture.folder", dir)
	for i in 3:
		var img := Image.create(320, 180, false, Image.FORMAT_RGB8)
		img.fill(Color.from_hsv(0.08 + i * 0.25, 0.5, 0.6))
		img.save_png(dir.path_join("Elden Ring 2026-10-22 18-3%d-00.png" % i))
	Capture.changed.emit("files")
	main.open_captures()
	await wait(1.2)
	var victim := dir.path_join("Elden Ring 2026-10-22 18-32-00.png")
	var cap: Node = Nav.top_layer()
	cap.call("_ask_delete", victim)
	await wait(0.5)
	await shot("05_papierkorb_frage", 0.3)
	await press("left")
	await press("a")
	await shot("06_papierkorb_rueckgaengig", 1.0)
	_check(Undo.hides(victim) and FileAccess.file_exists(victim), "ausgeblendet, Datei noch da")
	await press("view")
	await shot("07_aufnahme_zurueck", 1.0)
	_check(not Undo.hides(victim) and FileAccess.file_exists(victim), "zurück in der Liste")
	await press("b")
	await wait(0.6)

	# 4. Ordner löschen (Spiele bleiben, der Ordner kommt mit Rückgängig zurück).
	var fid := Library.create_folder("Couch-Abende", "")
	for x in all.slice(0, 3):
		Library.set_in_folder(str(x.id), fid, true)
	var name_ := str(Library.folder(fid).name)
	var ids: Array = all.slice(0, 3).map(func(x): return str(x.id))
	var snap := Library.snapshot(ids, true)
	Library.delete_folder(fid)
	Undo.offer_games("Ordner gelöscht", name_, "trash", snap)
	await shot("08_ordner_geloescht", 0.9)
	await press("view")
	await wait(0.6)
	_check(not Library.folder(fid).is_empty() and Library.in_folder(fid).size() == 3, "Ordner samt drei Spielen zurück")

	# Nie etwas vorgemerkt lassen (Aufnahmen gingen sonst beim Beenden in den Papierkorb).
	if Undo.pending() > 0:
		Undo.take()


func _check(cond: bool, what: String) -> void:
	print("Probe ", "ok   " if cond else "FAIL ", what)


func _focus(key: String) -> void:
	var c := _find(Nav.top_layer(), func(n: Node) -> bool: return str(n.get_meta("uz_key", "")) == key)
	if c:
		Nav.focus(c)
	else:
		print("Probe: nicht gefunden: ", key)
	await wait(0.35)


func _find(n: Node, f: Callable) -> Control:
	if n == null:
		return null
	if n is Control and f.call(n):
		return n
	for ch in n.get_children():
		var r := _find(ch, f)
		if r:
			return r
	return null
