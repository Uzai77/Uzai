extends Node
## Rückgängig (Roadmap 95) ohne Bildschirm: jede angebundene Änderung tun, zurücknehmen und
## vergleichen; vorgemerkte Dateien bleiben, bis die Zeit um ist, und gelöscht wird nur, was Uzai
## selbst angelegt hat, wo es hingehört – nie über Verknüpfungen.
## Aufruf: godot --headless --path . res://tests/logic_rueckgaengig.tscn
##
## Aufnahmen werden hier nie endgültig gelöscht (das ginge in den Papierkorb des Systems): Der Test
## nimmt sie immer zurück und prüft das Löschen an den Sicherungen im eigenen Datenordner.

const Backup := preload("res://src/core/backup.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Bibliothek als Text (Spiele in Reihenfolge, Ordner): gleich heißt genau gleich.
func _state() -> String:
	return JSON.stringify({ "games": Library.games, "folders": Library.folders }, "", true)


func _write(path: String, text := "x") -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _ready() -> void:
	Library.load_demo()
	var vis := Library.visible_games()
	var a := str(vis[0].id)
	var b := str(vis[1].id)
	var c := str(vis[2].id)

	print("Spiel ausblenden")
	var before := _state()
	var snap := Library.snapshot([a])
	Library.set_field(a, "hidden", true)
	check(not Library.is_visible(Library.get_game(a)), "ausgeblendet")
	var n := Undo.offer_games("Ausgeblendet", "x", "eye_off", snap)
	check(Undo.pending() == n and n > 0, "Rückgängig steht bereit")
	var obj := Library.get_game(a)
	check(Undo.take(), "zurückgenommen")
	check(_state() == before and Library.is_visible(Library.get_game(a)), "genau der Stand davor")
	check(is_same(Library.get_game(a), obj), "dasselbe Spiel-Objekt (offene Seiten sehen es gleich)")
	check(Undo.pending() == 0 and not Undo.take(), "danach nichts mehr zurückzunehmen")

	print("Aus Uzai entfernen")
	before = _state()
	var at := Library.games.find(Library.get_game(b))
	snap = Library.snapshot([b])
	Library.remove(b)
	check(Library.get_game(b).is_empty(), "entfernt")
	Undo.offer_games("Aus Uzai entfernt", "x", "trash", snap)
	Undo.take()
	check(_state() == before and Library.games.find(Library.get_game(b)) == at, "wieder da, am alten Platz (%d)" % at)

	print("Mehrere Spiele auf einmal, mit neuem Ordner")
	before = _state()
	snap = Library.snapshot([a, b, c], true)
	var fid := Library.create_folder("Neu für Rückgängig", "")
	Library.update_many([a, b, c], "folder_add", Library.folder(fid))
	Library.update_many([a, b, c], "tag_add", "Koop")
	Library.update_many([a, b], "hidden", true)
	check(_state() != before, "geändert")
	Undo.offer_games("3 Spiele geändert", "", "check", snap)
	Undo.take()
	check(_state() == before and Library.folder(fid).is_empty(), "Spiele und Ordner wie vorher, neuer Ordner wieder weg")

	print("Ordner löschen")
	var fold := Library.create_folder("Lieblinge", "")
	Library.set_in_folder(a, fold, true)
	Library.set_in_folder(c, fold, true)
	before = _state()
	var ids: Array = Library.games.filter(func(g): return fold in g.get("folders", [])).map(func(g): return str(g.get("id", "")))
	snap = Library.snapshot(ids, true)
	Library.delete_folder(fold)
	check(Library.folder(fold).is_empty() and not Library.is_in_folder(Library.get_game(a), fold), "gelöscht")
	Undo.offer_games("Ordner gelöscht", "Lieblinge", "trash", snap)
	Undo.take()
	check(_state() == before and Library.is_in_folder(Library.get_game(c), fold), "Ordner samt Spielen zurück")

	print("Eigene Bilder, Link, Favorit")
	Library.set_field(a, "images", { "cover": "res://icon.svg" })
	Library.set_field(a, "links", [{ "name": "Wiki", "url": "https://example.org/wiki" }])
	before = _state()
	snap = Library.snapshot([a])
	Library.set_field(a, "images", null)
	Library.set_field(a, "links", null)
	Library.toggle_favorite(a)
	Undo.offer_games("Eigene Bilder entfernt", "", "image", snap)
	Undo.take()
	check(_state() == before, "Bilder, Link und Favorit wie vorher")

	print("Immer nur die jüngste Änderung")
	var log: Array = []
	Undo.offer("Erste", "", "info", func() -> void: log.append("u1"), func() -> void: log.append("d1"))
	Undo.offer("Zweite", "", "info", func() -> void: log.append("u2"), func() -> void: log.append("d2"))
	check(log == ["d1"], "die neue macht die vorige endgültig (%s)" % str(log))
	Undo.take()
	check(log == ["d1", "u2"], "zurück nimmt nur die jüngste")
	Undo.offer("Dritte", "", "info", func() -> void: log.append("u3"), func() -> void: log.append("d3"))
	Undo.settle()
	check(log == ["d1", "u2", "d3"] and not Undo.take(), "Zeit um: endgültig, danach kein Zurück mehr")
	var gone := Node.new()
	add_child(gone)
	var dead := Callable(gone, "queue_free")
	gone.free()
	Undo.offer("Vierte", "", "info", dead)
	check(not Undo.take() and Undo.pending() == 0, "ein Rückweg, den es nicht mehr gibt, tut nichts (und sagt es)")

	print("Einstellungen")
	Config.set_value("library.presets", [{ "name": "Couch", "filter": {}, "group": "", "sort": "" }])
	var old: Array = (Config.get_value("library.presets", []) as Array).duplicate(true)
	Config.set_value("library.presets", [])
	Undo.offer_setting("Ansicht gelöscht", "Couch", "trash", "library.presets", old)
	Undo.take()
	check(JSON.stringify(Config.get_value("library.presets", [])) == JSON.stringify(old), "gespeicherte Ansicht zurück")
	Config.set_value("library.pc_dirs", ["/spiele/a", "/spiele/b"])
	var dirs: Array = (Config.get_value("library.pc_dirs", []) as Array).duplicate()
	Config.set_value("library.pc_dirs", ["/spiele/b"])
	Undo.offer_calls("Ordner entfernt", "a", "folder", [Config.set_value.bind("library.pc_dirs", dirs)])
	Undo.take()
	check(Config.get_value("library.pc_dirs", []) == ["/spiele/a", "/spiele/b"], "PC-Spiele-Ordner zurück, in alter Reihenfolge")
	var sys := str(Config.systems()[0].id)
	var eid := Config.add_emulator("Mein Emulator")
	Config.set_value("emulators.%s.args" % eid, "-x \"{rom}\"")
	Config.set_system(sys, "emulator", eid)
	var emu_before := JSON.stringify(Config.emulator(eid))
	var back := Config.emulator_backup(eid)
	Config.delete_emulator(eid)
	check(Config.emulator(eid).is_empty() and str(Config.system(sys).get("emulator", "")) == "", "Emulator gelöscht, System ohne")
	Undo.offer_calls("Emulator gelöscht", "", "trash", [Config.restore_emulator.bind(back)])
	Undo.take()
	check(JSON.stringify(Config.emulator(eid)) == emu_before and str(Config.system(sys).get("emulator", "")) == eid, "eigener Emulator samt Zuordnung zurück")

	print("YouTube-Verlauf")
	YouTube.data.history = [{ "id": "dQw4w9WgXcQ", "t": 12 }, { "id": "aaaaaaaaaaa", "t": 0 }]
	var hist: Array = (YouTube.data.history as Array).duplicate(true)
	YouTube.clear_history()
	check((YouTube.data.history as Array).is_empty(), "geleert")
	Undo.offer_calls("Verlauf gelöscht", "", "history", [YouTube.restore_history.bind(hist)])
	Undo.take()
	check(JSON.stringify(YouTube.data.history) == JSON.stringify(hist), "Verlauf zurück")

	print("Sicherungen: erst nach der Zeit gelöscht, nur im eigenen Ordner")
	var dd := Config.data_dir
	var bdir := Backup.dir_of(dd)
	DirAccess.make_dir_recursive_absolute(bdir)
	var zip := bdir.path_join("uzai-sicherung-2026-10-22-hand.zip")
	_write(zip)
	var n0 := Backup.list(dd).size()
	Undo.offer_files("Sicherung gelöscht", "", "trash", [zip], "backup")
	check(Undo.hides(zip) and FileAccess.file_exists(zip), "vorgemerkt: ausgeblendet, aber noch da")
	check(Backup.list(dd).filter(func(x): return not Undo.hides(str(x.path))).size() == n0 - 1, "die Liste zeigt sie nicht mehr")
	Undo.take()
	check(not Undo.hides(zip) and FileAccess.file_exists(zip), "zurückgenommen: bleibt")
	Undo.offer_files("Sicherung gelöscht", "", "trash", [zip], "backup")
	Undo.settle()
	check(not FileAccess.file_exists(zip), "Zeit um: gelöscht")
	var outside := dd.path_join("uzai-sicherung-fremd.zip")
	_write(outside)
	var wrong := bdir.path_join("einstellungen.json")
	_write(wrong)
	check(not Backup.remove(dd, outside) and FileAccess.file_exists(outside), "außerhalb des Ordners der Sicherungen: nie")
	check(not Backup.remove(dd, bdir.path_join("../uzai-sicherung-fremd.zip")) and FileAccess.file_exists(outside), "auch nicht über „..“")
	check(not Backup.remove(dd, wrong) and FileAccess.file_exists(wrong), "nur echte Sicherungsdateien")
	var target := dd.path_join("wichtig.txt")
	_write(target, "bleibt")
	var link := bdir.path_join("uzai-sicherung-link.zip")
	var linked := DirAccess.open(bdir).create_link(target, link) == OK
	if linked:
		check(not Backup.remove(dd, link) and FileAccess.file_exists(target) and FileAccess.file_exists(link),
				"eine Verknüpfung wird nicht gelöscht, ihr Ziel schon gar nicht")
	else:
		print("    (Verknüpfungen gehen hier nicht – übersprungen)")

	print("Aufnahmen: ausgeblendet, bis die Zeit um ist")
	var clips := dd.path_join("clips_test")
	DirAccess.make_dir_recursive_absolute(clips)
	Config.set_value("capture.folder", clips)
	var clip := clips.path_join("Elden Ring 2026-10-22 18-30-00.mp4")
	_write(clip)
	var has_clip := func() -> bool: return Capture.list_items().any(func(x): return str(x.path) == clip)
	check(has_clip.call(), "Clip in der Liste")
	check(Capture.is_own_file(clip), "eigene Aufnahme erkannt")
	check(not Capture.is_own_file(dd.path_join("x.mp4")) and not Capture.is_own_file(clips.path_join("../x.mp4")), "außerhalb des Clip-Ordners: nicht eigene")
	check(not Capture.is_own_file(clips.path_join("notiz.txt")), "keine Aufnahme (Endung): nicht eigene")
	if linked:
		var clink := clips.path_join("verknuepft.mp4")
		DirAccess.open(clips).create_link(target, clink)
		check(not Capture.is_own_file(clink), "Verknüpfung im Clip-Ordner: nicht eigene")
	Undo.offer_files("In den Papierkorb gelegt", "", "trash", [clip], "capture")
	check(not has_clip.call() and FileAccess.file_exists(clip), "sofort aus der Liste, Datei noch da")
	Undo.take()
	check(has_clip.call(), "zurückgenommen: wieder in der Liste")
	check(Undo.pending() == 0, "am Ende ist nichts mehr vorgemerkt")

	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)
