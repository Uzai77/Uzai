extends Node
## Sicherungen und Selbstreparatur (Punkte 56, 133, 140): was in eine Sicherung kommt, Zurückholen
## nur an erlaubte Orte (auch bei einer veränderten ZIP), automatische Sicherungen begrenzt, tägliche
## Kopien der Einstellungen, Reparatur einer kaputten settings.json, Sicherung vor einem Update,
## Versionsnummer der Einstellungen. Aufruf: godot --headless --path . res://tests/logic_sicherung.tscn

const Backup := preload("res://src/core/backup.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_paths()
	_create_restore()
	_snapshots()
	_config()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _tmp(name: String) -> String:
	var d := Config.data_dir.path_join("test_" + name)
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _paths() -> void:
	print("Was in eine Sicherung darf")
	for ok in ["settings.json", "library.json", "media/covers/a.png", "sounds/select.wav", "movies/plugins/p.js", "movies/movies-extra.json"]:
		check(Backup.allowed(ok), "erlaubt: " + ok)
	for bad in ["../settings.json", "/etc/passwd", "C:/Windows/x.json", "media/../settings.json", "media\\x.png", "cache/img/a.png", "tools/ffmpeg.exe",
			"logs/steam.log", "settings.json.tmp", "movies/runtime/runner.js", "aufnahmen/clip.mp4", "helper/uzai-helper.ps1", "x.exe", "", "media//a.png",
				"./settings.json"]:
		check(not Backup.allowed(bad), "nicht erlaubt: " + (bad if bad != "" else "(leer)"))


func _create_restore() -> void:
	print("Sichern und zurückholen")
	var d := _tmp("data")
	_put(d.path_join("settings.json"), '{"a": 1}')
	_put(d.path_join("library.json"), '{"games": []}')
	_put(d.path_join("media/cover.png"), "PNG")
	_put(d.path_join("movies/plugins/p.js"), "js")
	_put(d.path_join("movies/runtime/runner.js"), "runtime")
	_put(d.path_join("cache/img/x.png"), "cache")
	_put(d.path_join("tools/ffmpeg.exe"), "exe")
	_put(d.path_join("logs/steam.log"), "log")
	var files := Array(Backup.collect(d))
	files.sort()
	check(files == ["library.json", "media/cover.png", "movies/plugins/p.js", "settings.json"], "gesichert wird genau das Richtige: %s" % str(files))
	var r := Backup.create(d, "hand", 1760000000)
	check(bool(r.ok) and int(r.files) == 4 and FileAccess.file_exists(str(r.path)), "Sicherung angelegt (%d Dateien)" % int(r.get("files", 0)))
	# Großer Medienordner: Die Profile (kommen als Letztes) fehlten früher still, sobald die Grenze erreicht war.
	var gross := _tmp("gross")
	_put(gross.path_join("settings.json"), '{"a": 1}')
	_put(gross.path_join("media/riesig.png"), "x".repeat(400))
	_put(gross.path_join("profiles/testprofil12/settings.json"), '{"b": 2}')
	_put(gross.path_join("profiles/testprofil12/spieler.json"), '{"c": 3}')
	var rg := Backup.create(gross, "hand", 1760000100, 100)
	var drin := PackedStringArray()
	var zr := ZIPReader.new()
	if zr.open(str(rg.get("path", ""))) == OK:
		drin = zr.get_files()
		zr.close()
	check(bool(rg.ok) and drin.has("profiles/testprofil12/settings.json") and drin.has("profiles/testprofil12/spieler.json")
			and not drin.has("media/riesig.png") and int(rg.get("skipped", 0)) == 1, "über der Grenze: alle *.json bleiben, nur Medien fallen weg (%s)" % str(drin))
	_put(d.path_join("settings.json"), '{"a": 2}')
	DirAccess.remove_absolute(d.path_join("media/cover.png"))
	check(Backup.schedule_restore(d, str(r.path)), "Zurückholen vorgemerkt")
	check(not Backup.schedule_restore(d, "/tmp/fremd.zip"), "nur Sicherungen aus dem eigenen Ordner")
	var msg := Backup.apply_pending_restore(d)
	check(msg.contains("4 Dateien") and FileAccess.get_file_as_string(d.path_join("settings.json")) == '{"a": 1}'
			and FileAccess.file_exists(d.path_join("media/cover.png")), "beim Start zurückgeholt: %s" % msg)
	check(not FileAccess.file_exists(d.path_join(Backup.PENDING)) and Backup.apply_pending_restore(d) == "", "Vormerkung danach weg")
	check(Backup.list(d).any(func(b: Dictionary) -> bool: return str(b.name).contains("vor-wiederherstellen")), "der Stand davor wurde selbst gesichert")
	# Veränderte Sicherung mit Pfaden nach draußen: nichts außerhalb, nur Erlaubtes.
	var evil := Backup.dir_of(d).path_join("uzai-sicherung-2026-01-01-000000-hand.zip")
	var z := ZIPPacker.new()
	z.open(evil)
	for e in [["../draussen.json", "x"], ["tools/evil.exe", "x"], ["media/neu.png", "ok"]]:
		z.start_file(e[0])
		z.write_file(str(e[1]).to_utf8_buffer())
		z.close_file()
	z.close()
	var msg2 := Backup.restore_now(d, evil)
	check(not FileAccess.file_exists(d.get_base_dir().path_join("draussen.json")) and not FileAccess.file_exists(d.path_join("tools/evil.exe")),
			"nichts außerhalb oder an fremde Orte geschrieben")
	check(FileAccess.file_exists(d.path_join("media/neu.png")) and msg2.contains("2 übersprungen"), "nur das Erlaubte: %s" % msg2)
	# Größen stehen im Inhaltsverzeichnis: Uzai liest sie, ohne zu entpacken. Eine Datei, die entpackt größer wäre,
	# als Uzai je sichert (ein präpariertes Paket), wird nicht zurückgeschrieben.
	var gr: Dictionary = Backup.zip_groessen(evil)
	check(bool(gr.ok) and int(gr.dateien) == 3 and int(gr.groesste) == 2 and int(gr.gesamt) == 4, "Größen aus dem Verzeichnis gelesen: %s" % str(gr))
	check(not bool(Backup.zip_groessen(d.path_join("settings.json")).ok) and not bool(Backup.zip_groessen(d.path_join("gibt-es-nicht.zip")).ok),
			"kein ZIP: erkannt")
	# ZIP64-Locator vor dem klassischen Ende: minizip nähme das ZIP64-Verzeichnis (Größen bis 4 GB je Datei).
	var roh := FileAccess.get_file_as_bytes(evil)
	var eocd := roh.size() - 22
	var z64 := roh.slice(0, eocd)
	z64.append_array(PackedByteArray([0x50, 0x4b, 0x06, 0x07, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0]))
	z64.append_array(roh.slice(eocd))
	var zip64 := Backup.dir_of(d).path_join("uzai-sicherung-2026-01-03-000000-hand.zip")
	var fz := FileAccess.open(zip64, FileAccess.WRITE)
	fz.store_buffer(z64)
	fz.close()
	check(not bool(Backup.zip_groessen(zip64).ok) and Backup.restore_now(d, zip64).contains("nicht öffnen"), "ZIP64-Spur: abgelehnt, nichts zurückgeschrieben")
	DirAccess.remove_absolute(zip64)
	var bombe := Backup.dir_of(d).path_join("uzai-sicherung-2026-01-02-000000-hand.zip")
	z = ZIPPacker.new()
	z.open(bombe)
	z.start_file("media/riesig.png")
	var nullen := PackedByteArray()
	nullen.resize(Backup.MAX_FILE + 1)
	z.write_file(nullen)
	z.close_file()
	z.close()
	nullen = PackedByteArray()
	var klein := FileAccess.open(bombe, FileAccess.READ).get_length()
	var msg3 := Backup.restore_now(d, bombe)
	check(klein < 1024 * 1024 and msg3.contains("größer") and not FileAccess.file_exists(d.path_join("media/riesig.png")),
			"Paket von %d KB, das entpackt über 64 MB hätte: nicht zurückgeschrieben" % (klein / 1024))
	DirAccess.remove_absolute(bombe)
	# Automatische Sicherungen begrenzen, eigene bleiben.
	var e := _tmp("prune")
	_put(e.path_join("settings.json"), "{}")
	for i in 7:
		Backup.create(e, "update-0.8.%d-0.8.%d" % [i, i + 1], 1760000000 + i * 100)
	Backup.create(e, "hand", 1760001000)
	var all := Backup.list(e)
	check(all.filter(func(b: Dictionary) -> bool: return bool(b.auto)).size() == Backup.KEEP_AUTO and all.size() == Backup.KEEP_AUTO + 1,
			"automatische Sicherungen: die letzten %d, eigene bleiben (%d)" % [Backup.KEEP_AUTO, all.size()])
	check(load("res://src/ui/sections/settings_view.gd").backup_kind("uzai-sicherung-2026-10-22-0800-update-0.8.2-0.8.3.zip") == "Vor dem Update 0.8.2 → 0.8.3",
			"Art der Sicherung lesbar")


func _snapshots() -> void:
	print("Tägliche Kopien der Einstellungen")
	var d := _tmp("snap")
	_put(d.path_join("settings.json"), '{"x": 1}')
	for i in 9:
		Backup.snapshot_settings(d, 1760000000 + i * 86400)
	Backup.snapshot_settings(d, 1760000000 + 8 * 86400 + 60)
	check(Backup.snapshots(d).size() == Backup.KEEP_SNAPSHOTS, "eine je Tag, die letzten %d (%d)" % [Backup.KEEP_SNAPSHOTS, Backup.snapshots(d).size()])
	_put(d.path_join("backups").path_join(str(Backup.snapshots(d)[0])), "kaputt{")
	var latest := Backup.latest_settings(d)
	check(not latest.is_empty() and str(latest.file) == str(Backup.snapshots(d)[1]), "unlesbare Kopie übersprungen: %s" % str(latest.get("file", "")))


func _config() -> void:
	print("Einstellungen: Version, Update, Reparatur")
	var keep: Dictionary = Config.settings.duplicate(true)
	var sp := Config.path("settings.json")
	# Update erkannt: alter Stand wird gesichert, Version und Aufbau stehen danach drin.
	Config.write_json(sp, { "uzai_version": "0.8.2", "schema": 0, "theme": { "rev": 8 } })
	Config.notices.clear()
	var before := Backup.list(Config.data_dir).size()
	Config.load_settings()
	var after := Backup.list(Config.data_dir)
	check(after.size() == before + 1 and str(after[0].name).contains("update-0.8.2-" + Config.VERSION),
			"Update: vorher gesichert (%s)" % (str(after[0].name) if not after.is_empty() else "keine"))
	check(int(Config.settings.schema) == Config.SETTINGS_VERSION and str(Config.settings.uzai_version) == Config.VERSION, "Versionsnummer und Aufbau eingetragen")
	var saved: Variant = Config.read_json(sp, {})
	check(saved is Dictionary and int(saved.get("schema", -1)) == Config.SETTINGS_VERSION, "gleich gespeichert")
	Config.load_settings()
	check(Backup.list(Config.data_dir).size() == before + 1, "derselbe Stand noch einmal: keine neue Sicherung")
	# Neuere Version: bleibt, wie sie ist.
	Config.write_json(sp, { "uzai_version": Config.VERSION, "schema": 99, "zukunft": { "neu": true } })
	Config.notices.clear()
	Config.load_settings()
	check(int(Config.settings.schema) == 99 and Config.settings.has("zukunft") and Config.notices.any(func(n: String) -> bool: return n.contains("neueren")),
			"Einstellungen einer neueren Version bleiben (mit Hinweis)")
	# Kaputt samt .bak und .tmp: tägliche Kopie.
	# (Der Spielername folgt dem Profil – als Merkmal dient darum ein anderer Wert.)
	Config.write_json(sp, { "uzai_version": Config.VERSION, "schema": 1, "theme": { "preset": "Kopie" } })
	# Mit Profilen liegen die eigenen Einstellungen samt täglicher Kopie im Ordner des Profils.
	DirAccess.remove_absolute(
			Config.profile_dir.path_join("backups").path_join("settings-%s.json" % Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()))))
	Backup.snapshot_settings(Config.profile_dir)
	for f in [sp, sp + ".bak", sp + ".tmp"]:
		_put(f, "{kaputt")
	Config.notices.clear()
	Config.load_settings()
	check(str(Config.get_value("theme.preset", "")) == "Kopie" and Config.notices.any(func(n: String) -> bool: return n.contains("repariert")),
			"kaputte Einstellungen: aus der Kopie repariert, mit Hinweis")
	Config.settings = keep
	Config.save_settings()
