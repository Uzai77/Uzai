extends Node
## Netz-Probe für Uzais eigenen Epic-Installer (wie Heroic/Legendary) gegen nachgebaute Epic-Dienste
## und Download-Server (tests/fake_epic_cdn.py): installieren mit echtem Manifest- und Chunk-Format,
## kaputter erster Server, falsche Prüfsumme (einmal und immer), Pausieren und Fortsetzen (auch
## nach einem Neustart), Abbrechen, Update, Prüfen und Reparieren, bösartige Antworten (fremder
## Server, falsche Manifest-Prüfsumme, Pfade nach außen), über die Download-Liste (Installs),
## Deinstallieren. Anmeldung nur in Epics Kopfzeile, nie bei den Download-Servern.
## Aufruf (eigener, leerer Datenordner):
##   python3 tests/fake_epic_cdn.py 18789 &
##   UZAI_DATA=<ordner> UZAI_TEST_LOOPBACK=1 UZAI_EPIC_API=http://127.0.0.1:18789 godot --headless --path . res://tests/net_epic_install.tscn

const EI := preload("res://src/core/epic_install.gd")
const M := preload("res://src/library/epic_manifest.gd")
const GOOD := "0123456789abcdef0123456789abcdef"
const APP := "Kinglet"

var fails := 0
var base := ""
var work := ""
var ei: Node
var g := { "id": "epic:Kinglet", "title": "Alan Wake 2", "source": "epic", "system": "epic", "installed": false,
	"epic": { "namespace": "ns-kinglet", "item": "item-kinglet", "app": APP } }


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	base = OS.get_environment("UZAI_EPIC_API")
	if base == "" or OS.get_environment("UZAI_TEST_LOOPBACK") != "1":
		print("UZAI_EPIC_API oder UZAI_TEST_LOOPBACK fehlt")
		get_tree().quit(1)
		return
	ei = Installs.epic
	work = Config.shared_path("probe_spiele")
	DirAccess.make_dir_recursive_absolute(work)
	await _run()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _fetch(path: String) -> Variant:
	var r := await Net.get_json(base + path)
	return r.data


func _fake(q: String) -> void:
	await Net.get_json(base + "/__set?" + q)


func _reset() -> void:
	await Net.request(base + "/__reset", PackedStringArray(), HTTPClient.METHOD_POST, "")


func _chunk_hits(log: Array, build: int) -> int:
	return log.filter(func(e): return str(e.p).begins_with("/cdn/b%d/Chunks" % build)).size()


## Chunks, die Fassung 2 für geänderte oder neue Dateien braucht (aus beiden Manifesten).
func _changed_chunks() -> int:
	var m1 := M.parse((await Net.request(base + "/cdn/b1/Kinglet.manifest")).body)
	var m2 := M.parse((await Net.request(base + "/cdn/b2/Kinglet.manifest")).body)
	if not bool(m1.ok) or not bool(m2.ok):
		return -1
	return (M.plan(m2.m, m1.m).chunks as Array).size()


func _wait(phases: Array, sec := 60.0) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		var st: Dictionary = ei.status(APP)
		if not st.is_empty() and str(st.phase) in phases:
			return st
		await get_tree().create_timer(0.1).timeout
	return ei.status(APP)


func _wait_got(sec := 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		var st: Dictionary = ei.status(APP)
		if not st.is_empty() and str(st.phase) == "run" and float(st.got) > 0.0:
			return
		await get_tree().create_timer(0.05).timeout


## Alle Dateien eines Ordners (relativ), rekursiv.
func _list(root: String, rel := "") -> PackedStringArray:
	var out := PackedStringArray()
	var p := root.path_join(rel) if rel != "" else root
	if not DirAccess.dir_exists_absolute(p):
		return out
	for f in DirAccess.get_files_at(p):
		out.append(rel.path_join(f) if rel != "" else f)
	for d in DirAccess.get_directories_at(p):
		out.append_array(_list(root, rel.path_join(d) if rel != "" else d))
	return out


func _same_files(root: String) -> bool:
	var want: Variant = await _fetch("/__files")
	if not (want is Dictionary):
		return false
	for n in want.keys():
		if EI.file_sha1(root.path_join(str(n))) != str(want[n]):
			print("    abweichend: ", n)
			return false
	return _list(root).size() == (want as Dictionary).size()


func _run() -> void:
	print("Anmelden (vorhandene Epic-Anmeldung)")
	var lr: Dictionary = await Library.epic_account.login_with_code(GOOD)
	check(bool(lr.ok) and EI.can_install(g), "angemeldet, Spiel ist mit Uzai installierbar")

	print("Installieren")
	await _reset()
	var w1 := work.path_join("eins")
	DirAccess.make_dir_recursive_absolute(w1)
	check(ei.start(g, w1, "install") == "", "Start angenommen")
	var st := await _wait(["done", "failed"])
	check(str(st.get("phase", "")) == "done", "fertig (%s)" % str(st.get("text", "")))
	var root := w1.path_join("Alan Wake 2")
	check(await _same_files(root), "alle Dateien da, SHA-1 wie bei Epic (auch Unicode-Name, Leerzeichen, leere Datei)")
	check(not "\n".join(_list(w1)).contains(EI.TEMP), "keine Zwischendateien übrig")
	var rec: Dictionary = EI.records().get(APP, {})
	check(str(rec.get("dir", "")) == root and str(rec.get("exe", "")) == "Game/Binaries/Win64/Kinglet.exe" and str(rec.get("build", "")) == "1.0.1",
			"Uzais Angaben: Ordner, Programmdatei, Fassung")
	check(not ei.has_saved(APP), "Stand nach dem Ende gelöscht")
	var log: Array = await _fetch("/__log")
	var api: Array = log.filter(func(e): return str(e.p).begins_with("/launcher/"))
	check(api.size() == 1 and str(api[0].auth) == "Bearer a1", "Epics Dienst mit der Anmeldung in der Kopfzeile gefragt")
	var cdn: Array = log.filter(func(e): return str(e.p).begins_with("/cdn"))
	check(not cdn.is_empty() and cdn.all(func(e): return str(e.auth) == ""), "Download-Server nie mit Anmeldung (%d Anfragen)" % cdn.size())
	check(log.any(func(e): return str(e.p) == "/cdnbad/b1/Kinglet.manifest") and log.any(func(e): return str(e.p) == "/cdn/b1/Kinglet.manifest" and str(e.q) == "f_token=abc123"),
			"kaputter erster Server übersprungen, Manifest mit queryParams")
	var n_chunks := _chunk_hits(log, 1)
	check(n_chunks > 10, "Chunks einzeln geladen (%d)" % n_chunks)
	var line := " ".join(EI.launch_argv(Library.get_game(str(g.id)) if not Library.get_game(str(g.id)).is_empty() else g))
	check(line.contains("-SaveToUserDir") and line.contains("-epicapp=Kinglet") and line.contains("-epicuserid=acc1") and not line.contains("a1") and not line.contains("r1"),
			"Startzeile mit Epics Parametern, ohne Anmeldung („%s“)" % line.left(90))
	var ilog := FileAccess.get_file_as_string(Config.path("logs/installs.log"))
	check(ilog.contains("Kinglet") and not ilog.contains("Bearer") and not ilog.contains("a1 ") and not ilog.contains("f_token"), "Protokoll ohne Anmeldung und Schlüssel")

	print("Falsche Prüfsumme")
	await _reset()
	await _fake("corrupt=3")
	var w2 := work.path_join("zwei")
	DirAccess.make_dir_recursive_absolute(w2)
	ei.start(g, w2, "install")
	st = await _wait(["done", "failed"])
	check(str(st.get("phase", "")) == "done" and await _same_files(w2.path_join("Alan Wake 2")), "dreimal verfälscht: neu geladen, am Ende alles richtig")
	await _reset()
	await _fake("corrupt_all=1")
	var w3 := work.path_join("drei")
	DirAccess.make_dir_recursive_absolute(w3)
	ei.start(g, w3, "install")
	st = await _wait(["done", "failed"], 90.0)
	check(str(st.get("phase", "")) == "failed" and str(st.get("text", "")).contains("Prüfsumme"), "immer verfälscht: gescheitert („%s“)" % str(st.get("text", "")).left(60))
	var written := Array(_list(w3))
	check(written.all(func(f): return str(f).ends_with(EI.TEMP) and FileAccess.get_size(w3.path_join(str(f))) == 0), "nichts Verfälschtes geschrieben")
	await ei.cancel(APP)
	check(not DirAccess.dir_exists_absolute(w3.path_join("Alan Wake 2")) and not ei.has_saved(APP), "Abbrechen danach räumt auf")

	print("Pausieren und Fortsetzen (auch nach Neustart)")
	await _reset()
	await _fake("slow=400")
	var w4 := work.path_join("vier")
	DirAccess.make_dir_recursive_absolute(w4)
	ei.start(g, w4, "install")
	await _wait_got()
	ei.pause(APP)
	st = await _wait(["paused", "done", "failed"])
	check(str(st.get("phase", "")) == "paused" and float(st.got) > 0.0 and float(st.got) < float(st.total), "pausiert mittendrin (%d von %d Bytes)" % [int(st.get("got", 0)), int(st.get("total", 0))])
	check(ei.has_saved(APP), "Stand gesichert")
	ei.resume(g)
	await _wait_got()
	await get_tree().create_timer(0.2).timeout
	ei.pause(APP)
	await _wait(["paused", "done", "failed"])
	# Wie nach einem Neustart von Uzai: nichts mehr im Speicher, nur der gesicherte Stand.
	ei.jobs.erase(APP)
	await _fake("slow=0")
	check(ei.resume(g) == "", "nach „Neustart“ fortgesetzt")
	st = await _wait(["done", "failed"])
	log = await _fetch("/__log")
	var hits := _chunk_hits(log, 1)
	check(str(st.get("phase", "")) == "done" and await _same_files(w4.path_join("Alan Wake 2")), "fertig und richtig")
	check(hits <= n_chunks + 2, "Fertiges nicht nochmal geladen (%d Chunk-Anfragen, %d Chunks)" % [hits, n_chunks])

	print("Abbrechen")
	await _reset()
	await _fake("slow=120")
	var w5 := work.path_join("fuenf")
	DirAccess.make_dir_recursive_absolute(w5)
	ei.start(g, w5, "install")
	await _wait_got()
	ei.cancel(APP)
	st = await _wait(["cancelled", "done", "failed"])
	check(str(st.get("phase", "")) == "cancelled", "abgebrochen")
	check(not DirAccess.dir_exists_absolute(w5.path_join("Alan Wake 2")) and _list(w5).is_empty() and not ei.has_saved(APP), "Spielordner und Stand weg")
	await _fake("slow=0")

	print("Abbrechen über einem fertig installierten Spiel")
	# Noch einmal „Installieren“ in den Ordner, in dem das Spiel schon fertig liegt, und dann abbrechen: Das Spiel bleibt
	# (früher löschte das Abbrechen alle Dateien laut Dateiliste, und in Uzais Angaben stand es weiter als installiert).
	await _reset()
	await _fake("slow=120")
	var da := str(EI.records()[APP].dir)
	check(da == w4.path_join("Alan Wake 2"), "Uzais Angaben zeigen auf das fertig installierte Spiel")
	ei.start(g, w4, "install")
	await _wait_got()
	ei.cancel(APP)
	st = await _wait(["cancelled", "done", "failed"])
	check(str(st.get("phase", "")) == "cancelled" and await _same_files(da), "abgebrochen: das installierte Spiel ist heil (%s)" % str(st.get("phase", "")))
	check(not "\n".join(_list(w4)).contains(EI.TEMP) and not ei.has_saved(APP), "Zwischendateien und Stand sind weg")
	await _fake("slow=0")

	print("Update und Prüfen")
	await _reset()
	root = str(EI.records()[APP].dir)
	var exe_before := FileAccess.get_modified_time(root.path_join("Game/Binaries/Win64/Kinglet.exe"))
	await _fake("build=2")
	check(ei.start(g, "", "check") == "", "„Prüfen und aktualisieren“ angenommen")
	st = await _wait(["done", "failed"])
	check(str(st.get("phase", "")) == "done" and str(st.get("text", "")) == "Aktualisiert", "neue Fassung geladen")
	check(await _same_files(root) and not FileAccess.file_exists(root.path_join("Game/readme.txt")) and FileAccess.file_exists(root.path_join("Game/neu.txt")),
			"Dateien wie Fassung 2, weggefallene gelöscht")
	check(FileAccess.get_modified_time(root.path_join("Game/Binaries/Win64/Kinglet.exe")) == exe_before, "unveränderte Programmdatei nicht angefasst")
	log = await _fetch("/__log")
	var need := await _changed_chunks()
	check(need > 0 and _chunk_hits(log, 2) == need, "nur Chunks geänderter Dateien (%d von %d)" % [_chunk_hits(log, 2), need])
	check(str(EI.records()[APP].build) == "1.0.2", "Fassung gemerkt")
	await _reset()
	await _fake("build=2")
	ei.start(g, "", "check")
	st = await _wait(["done", "failed"])
	log = await _fetch("/__log")
	check(str(st.get("text", "")) == "Alle Dateien in Ordnung" and _chunk_hits(log, 2) == 0, "gleiche Fassung, alles heil: nichts geladen")
	var pak := root.path_join("Game/Content/Paks/data.pak")
	var f := FileAccess.open(pak, FileAccess.READ_WRITE)
	f.seek(1000)
	f.store_buffer("kaputt".to_utf8_buffer())
	f.close()
	await _reset()
	await _fake("build=2")
	ei.start(g, "", "check")
	st = await _wait(["done", "failed"])
	log = await _fetch("/__log")
	check(str(st.get("phase", "")) == "done" and await _same_files(root), "kaputte Datei erkannt und repariert")
	check(_chunk_hits(log, 2) > 0 and _chunk_hits(log, 2) < 20, "nur ihre Chunks neu (%d)" % _chunk_hits(log, 2))

	print("Bösartige Antworten")
	var w6 := work.path_join("sechs")
	DirAccess.make_dir_recursive_absolute(w6)
	for bad in [["evilcdn=1", "Download-Server"], ["badhash=1", "Dateiliste"], ["evil=dotdot", "unsichere Pfade"], ["evil=laufwerk", "unsichere Pfade"]]:
		await _reset()
		await _fake(str(bad[0]))
		ei.start(g, w6, "install")
		st = await _wait(["done", "failed"])
		check(str(st.get("phase", "")) == "failed" and str(st.get("text", "")).contains(str(bad[1])), "%s: abgelehnt („%s“)" % [bad[0], str(st.get("text", "")).left(70)])
		log = await _fetch("/__log")
		check(_chunk_hits(log, 1) == 0 and _list(w6).is_empty(), "%s: nichts geladen, nichts geschrieben" % bad[0])
	check(not FileAccess.file_exists(work.path_join("ausserhalb.txt")) and not FileAccess.file_exists(w6.path_join("ausserhalb.txt")), "nichts außerhalb des Ordners")

	print("Über die Download-Liste (Installs)")
	await _reset()
	await _fake("slow=1500")
	var w7 := work.path_join("sieben")
	DirAccess.make_dir_recursive_absolute(w7)
	Installs.start(g, { "uzai": true, "dir": w7 })
	var id := str(g.id)
	check(Installs.can_control(id), "Pausieren und Abbrechen aus Uzai möglich")
	await _wait_got()
	await get_tree().create_timer(1.6).timeout
	check(str(Installs.entry(id).phase) == "downloading" and str(Installs.entry(id).text).contains("Wird geladen"), "Liste zeigt „Wird geladen“ mit Fortschritt")
	check(await Installs.pause(id) == "", "Pausieren")
	await _wait(["paused"])
	await get_tree().create_timer(1.6).timeout
	check(str(Installs.entry(id).phase) == "paused", "Liste zeigt „Pausiert“")
	await _fake("slow=0")
	check(await Installs.resume(id) == "", "Fortsetzen")
	await _wait(["done", "failed"])
	await get_tree().create_timer(1.6).timeout
	check(str(Installs.entry(id).phase) == "done" and float(Installs.entry(id).frac) == 1.0, "Liste: fertig")

	print("Deinstallieren")
	root = str(EI.records()[APP].dir)
	check(await ei.uninstall(g) == "" and not DirAccess.dir_exists_absolute(root) and not EI.records().has(APP), "Spielordner und Angaben weg")
	check(DirAccess.dir_exists_absolute(w4.path_join("Alan Wake 2")), "andere Ordner unberührt")
