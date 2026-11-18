extends Node
## Netz-Probe „Retro ohne Einrichtung“ (Roadmap 19, 104) mit nachgebauten Quellen
## (tests/fake_retro.py, nur 127.0.0.1): Angebot aus der GitHub-API, Weiterleitung zum Dateiserver,
## Laden mit Prüfsumme, Entpacken in Uzais Ordner, Grundeinstellungen, Update ohne Verlust eigener
## Dateien – und die Abbrüche: falsche Prüfsumme, Zip-Slip, fremde Weiterleitung, zu groß,
## Abbrechen mitten im Laden, falsche CRC eines Kerns. Kein echter Download, nichts wird ausgeführt.
## Aufruf: UZAI_DATA=<ordner> godot --headless --path . res://tests/net_retroauto.tscn

const RA := preload("res://src/core/retro_auto.gd")
const Laden := preload("res://src/core/retro_laden.gd")
const PORT := 18786

var fails := 0
var _srv := 0
var L: Node


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	OS.set_environment("UZAI_TEST_LOOPBACK", "1")
	OS.set_environment("UZAI_RETRO_FAKE", "http://127.0.0.1:%d" % PORT)
	_srv = OS.create_process("python3", PackedStringArray([ProjectSettings.globalize_path("res://tests/fake_retro.py"), str(PORT)]))
	# Warten, bis der nachgebaute Server antwortet (das Erzeugen der Pakete dauert einen Moment).
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if bool((await Net.request("http://127.0.0.1:%d/__set?mode=gut" % PORT)).ok):
			break
	L = Laden.inst()
	await _run()
	if _srv > 0:
		OS.kill(_srv)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _mode(m: String) -> void:
	await Net.request("http://127.0.0.1:%d/__set?mode=%s" % [PORT, m])
	L._angebote.clear()
	L._index = ""


func _warte(key: String, sec := 60.0) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		var a: Dictionary = L.auftraege.get(key, {})
		if not a.is_empty() and not (str(a.phase) in ["wartet", "laeuft"]) and not L.beschaeftigt():
			return a
		await get_tree().process_frame
	return L.auftraege.get(key, {})


func _rest_frei() -> bool:
	var laden: String = L.ordner().path_join(".laden")
	var leer := not DirAccess.dir_exists_absolute(laden) or (DirAccess.get_files_at(laden).is_empty() and DirAccess.get_directories_at(laden).is_empty())
	var staging := not DirAccess.dir_exists_absolute(L.ordner().path_join(".neu_duckstation"))
	return leer and staging


func _run() -> void:
	print("Ohne Fake-Umleitung im Betrieb")
	OS.set_environment("UZAI_TEST_LOOPBACK", "0")
	check(Laden._netz("https://api.github.com/x") == "https://api.github.com/x", "UZAI_RETRO_FAKE wirkt nur in Proben")
	OS.set_environment("UZAI_TEST_LOOPBACK", "1")
	check(Laden._netz("https://api.github.com/x") == "http://127.0.0.1:%d/api.github.com/x" % PORT, "in Proben: zum nachgebauten Server")

	print("Angebot")
	await _mode("gut")
	var a: Dictionary = await L.angebot("duckstation")
	check(bool(a.get("ok", false)) and str(a.fassung) == "Fassung vom 12.10.2026" and int(a.groesse) > 10 * RA.MB,
			"Angebot aus der GitHub-API (%s)" % a.get("error", ""))
	check(str(a.get("datei", "")) == "duckstation-windows-x64-release.zip" and str(a.get("lizenz", "")) == "CC-BY-NC-ND-4.0",
			"nur das portable Paket, Lizenz genannt")
	var f: Dictionary = await L.angebot("retroarch")
	check(bool(f.get("ok", false)) and str(f.get("fassung", "")) == "1.22.2" and str(f.get("pruefung", "")).contains("fest"),
			"RetroArch: feste Fassung mit SHA-256 aus Uzai")

	print("Laden, Prüfen, Einrichten")
	L.einrichten(["duckstation"], [], { "duckstation": ["ps1"] })
	var j := await _warte("duckstation")
	check(str(j.get("phase", "")) == "fertig", "DuckStation eingerichtet (%s)" % j.get("text", ""))
	var dir: String = L.emu_dir("duckstation")
	var exe := dir.path_join("duckstation-qt-x64-ReleaseLTCG.exe")
	check(FileAccess.file_exists(exe) and FileAccess.get_file_as_string(exe).begins_with("MZ nur Text"), "Programmdatei liegt in Uzais Ordner")
	check(str(Config.emulator("duckstation").get("exe", "")) == exe and str(Config.system("ps1").get("emulator", "")) == "duckstation",
			"Pfad eingetragen, PS1 nutzt DuckStation")
	check(FileAccess.file_exists(dir.path_join("portable.txt"))
			and FileAccess.get_file_as_string(dir.path_join("settings.ini")).contains("StartFullscreen = true"), "tragbar, Vollbild in den eigenen Einstellungen")
	check(DirAccess.dir_exists_absolute(dir.path_join("bios")) and DirAccess.get_files_at(dir.path_join("bios")).is_empty(),
			"leerer Ordner fürs eigene BIOS – Uzai legt keins hinein")
	check(str(L.installiert("duckstation").get("kennung", "")) == str(a.get("kennung", "-")), "Fassung und Prüfsumme gemerkt")
	check(_rest_frei(), "kein Download und kein Zwischenordner liegen geblieben")
	check(FileAccess.file_exists(dir.path_join("resources/big.bin")) and FileAccess.get_size(dir.path_join("resources/big.bin")) == 11 * 1024 * 1024,
			"große Datei vollständig")

	print("Update behält deine Dateien")
	var mine := dir.path_join("bios/meine_konsole.bin")
	var fb := FileAccess.open(mine, FileAccess.WRITE)
	fb.store_string("eigenes BIOS")
	fb.close()
	var fs := FileAccess.open(dir.path_join("settings.ini"), FileAccess.WRITE)
	fs.store_string("[Main]\nEigene = ja\n")
	fs.close()
	await _mode("neu")
	var up: Array = await L.updates()
	var duck: Array = up.filter(func(r: Dictionary) -> bool: return str(r.id) == "duckstation")
	check(duck.size() == 1 and str(duck[0].neu) == "Fassung vom 20.10.2026" and bool((duck[0].angebot as Dictionary).get("ok", false)), "neue Fassung erkannt")
	L.einrichten(["duckstation"], [], {})
	j = await _warte("duckstation")
	check(str(j.phase) == "fertig" and FileAccess.get_file_as_string(exe).contains("neue Fassung"), "aktualisiert")
	check(FileAccess.get_file_as_string(mine) == "eigenes BIOS" and FileAccess.get_file_as_string(dir.path_join("settings.ini")).contains("Eigene = ja"),
			"eigenes BIOS und eigene Einstellungen bleiben")
	check(FileAccess.file_exists(dir.path_join("resources/gamecontrollerdb.txt")), "alte Dateien, die das Paket nicht mehr hat, bleiben")

	print("Abbrüche")
	var before := FileAccess.get_file_as_string(exe)
	await _mode("falsch")
	L.einrichten(["duckstation"], [], {})
	j = await _warte("duckstation")
	check(str(j.phase) == "fehler" and str(j.text).contains("Prüfsumme"), "falsche Prüfsumme: Abbruch (%s)" % j.text)
	check(FileAccess.get_file_as_string(exe) == before and _rest_frei(), "nichts entpackt, nichts liegen geblieben")
	await _mode("slip")
	L.einrichten(["duckstation"], [], {})
	j = await _warte("duckstation")
	check(str(j.phase) == "fehler" and str(j.text).contains("nicht erlaubt"), "Zip-Slip: Abbruch (%s)" % j.text)
	check(not FileAccess.file_exists(L.ordner().path_join("evil.txt")) and not FileAccess.file_exists(L.ordner().get_base_dir().path_join("evil.txt"))
			and not FileAccess.file_exists(dir.get_base_dir().path_join("evil.txt")), "nichts außerhalb geschrieben")
	check(FileAccess.get_file_as_string(exe) == before and _rest_frei(), "eingerichteter Emulator unverändert")
	await _mode("boese")
	L.einrichten(["duckstation"], [], {})
	j = await _warte("duckstation")
	check(str(j.phase) == "fehler" and str(j.text).contains("weiter"), "Weiterleitung zu fremdem Host: Abbruch (%s)" % j.text)
	await _mode("gross")
	L.einrichten(["duckstation"], [], {})
	j = await _warte("duckstation")
	check(str(j.phase) == "fehler" and _rest_frei(), "mehr Bytes als angekündigt: Abbruch (%s)" % j.text)
	await _mode("langsam")
	L.einrichten(["duckstation"], [], {})
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and int(L.auftraege.duckstation.got) <= 0:
		await get_tree().process_frame
	check(int(L.auftraege.duckstation.got) > 0 and str(L.auftraege.duckstation.phase) == "laeuft",
			"Fortschritt sichtbar (%d Bytes)" % int(L.auftraege.duckstation.got))
	L.abbrechen("duckstation")
	j = await _warte("duckstation", 10.0)
	check(str(j.phase) == "abgebrochen", "Abbrechen mitten im Laden")
	check(_rest_frei() and FileAccess.get_file_as_string(exe) == before, "nach dem Abbrechen nichts liegen geblieben")

	print("Kerne vom Buildbot")
	await _mode("gut")
	L.einrichten([], ["mgba"], { "retroarch": ["gba"] })
	j = await _warte("kern:mgba")
	check(str(j.phase) == "fehler" and str(j.text).contains("eigenes RetroArch"), "ohne Uzais RetroArch: kein Kern (%s)" % j.text)
	var ra: String = L.emu_dir("retroarch")
	DirAccess.make_dir_recursive_absolute(ra)
	var fr := FileAccess.open(ra.path_join("retroarch.exe"), FileAccess.WRITE)
	fr.store_string("MZ nur Text")
	fr.close()
	Config.set_emulator("retroarch", "exe", ra.path_join("retroarch.exe"))
	await _mode("kern_falsch")
	L.einrichten([], ["mgba"], { "retroarch": ["gba"] })
	j = await _warte("kern:mgba")
	check(str(j.phase) == "fehler" and str(j.text).contains("Prüfsumme") and not FileAccess.file_exists(ra.path_join("cores/mgba_libretro.dll")),
			"falsche CRC des Kerns: nicht übernommen")
	await _mode("gut")
	L.einrichten([], ["mgba"], { "retroarch": ["gba"] })
	j = await _warte("kern:mgba")
	check(str(j.phase) == "fertig" and FileAccess.file_exists(ra.path_join("cores/mgba_libretro.dll")), "Kern mGBA in cores (%s)" % j.text)
	check(str(Config.system("gba").get("emulator", "")) == "retroarch" and str(Config.system("gba").get("core", "")) == "mgba",
			"GBA startet über RetroArch mit mGBA")
	check(L.kern_da(Config.emulator("retroarch"), "mgba"), "Kern gilt als bereit")
	var lage: Array = RA.erkennen({ "gba": 2 }, Config.systems(), func(id: String) -> Dictionary: return Config.emulator(id), L.exe_da, L.kern_da, L.ordner())
	check(not lage.is_empty() and bool(lage[0].bereit), "GBA danach bereit")
