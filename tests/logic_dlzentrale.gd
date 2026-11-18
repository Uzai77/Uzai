extends Node
## Download-Zentrale (Punkt 107) ohne Windows: anstehende Updates aus Steams appmanifest,
## Warteschlange (einreihen, verschieben, säubern), Zeitfenster über Mitternacht, wann das Nächste
## anläuft (nie zwei auf einmal, nachts nur im Ruhemodus, nie ein Update fürs laufende Spiel),
## Platz vor dem Start, Steams Bandbreite aus config.vdf und – mit der Demo-Bibliothek – der
## Ablauf in Installs: danach, nachts, Updates, still im Ruhemodus, gemerkt über einen Neustart.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_dlzentrale.tscn → „Ergebnis: alles ok“

const Q := preload("res://src/core/dl_queue.gd")
const VDF := preload("res://src/library/vdf.gd")
const GB := 1073741824

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Updates aus dem appmanifest")
	_updates()
	print("Warteschlange")
	_queue()
	print("Zeitfenster und wer anlaufen darf")
	_window()
	print("Platz, Bandbreite, Meldung")
	_misc()
	print("Installs mit der Demo-Bibliothek")
	await _installs()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


static func _st(flags: int, total := 0, got := 0, result := 0) -> Dictionary:
	var text := "\"AppState\"\n{\n\t\"appid\"\t\t\"10\"\n\t\"StateFlags\"\t\t\"%d\"\n\t\"BytesToDownload\"\t\t\"%d\"\n\t\"BytesDownloaded\"\t\t\"%d\"\n\t\"UpdateResult\"\t\t\"%d\"\n\t\"ScheduledAutoUpdate\"\t\t\"1761000000\"\n}\n" % [flags, total, got, result]
	return VDF.get_ci(VDF.parse(text), "AppState", {})


func _updates() -> void:
	check(Q.update_state(_st(4)).is_empty(), "fertig installiert: kein Update")
	check(Q.update_state(_st(1026)).is_empty(), "noch nicht installiert (Download): kein Update, das ist ein Install")
	var u := Q.update_state(_st(6, 3 * GB, GB))
	check(str(u.phase) == "wartet" and int(u.remaining) == 2 * GB and int(u.scheduled) == 1761000000, "Update steht an: Rest 2 GB, von Steam geplant")
	check(Q.update_text(u).begins_with("Update · 2"), "Zeile: „Update · 2,0 GB“ (%s)" % Q.update_text(u))
	check(str(Q.update_state(_st(6 | 1024 | 256 | 1048576, 4 * GB, GB)).phase) == "laeuft", "Update läuft (Steam lädt)")
	check(Q.update_text(Q.update_state(_st(6 | 1048576, 4 * GB, GB))) == "Update läuft · 25 %", "Zeile beim Laden mit Prozent")
	check(str(Q.update_state(_st(6 | 512, GB)).phase) == "pausiert", "Update in Steam pausiert")
	var un := Q.update_state(_st(6))
	check(int(un.remaining) == -1 and Q.update_text(un) == "Update steht an", "Größe noch unbekannt: ehrlich ohne Zahl")
	check(Q.update_text(Q.update_state(_st(6, GB, 0, 12))).contains("Fehler 12"), "Steams Fehlercode wird genannt")


func _queue() -> void:
	var q: Array = []
	q = Q.add(q, Q.entry("a", "install", "jetzt", 1))
	q = Q.add(q, Q.entry("b", "update", "nachts", 2))
	q = Q.add(q, Q.entry("c", "install", "jetzt", 3))
	check(q.size() == 3 and str(q[1].id) == "b" and str(q[1].kind) == "update", "hinten angestellt, Art und Zeitpunkt gemerkt")
	q = Q.add(q, Q.entry("a", "install", "nachts", 4))
	check(q.size() == 3 and str(q[0].when) == "nachts", "schon drin: nur der Zeitpunkt ändert sich, der Platz bleibt")
	check(str(Q.move(q, "c", -1)[1].id) == "c" and str(Q.move(q, "a", -1)[0].id) == "a" and str(Q.move(q, "c", 1)[2].id) == "c",
			"nach vorn/hinten, am Rand bleibt alles")
	check(Q.remove(q, "b").size() == 2 and Q.index_of(q, "b") == 1 and Q.index_of(q, "x") == -1, "herausnehmen und finden")
	var raw: Array = [{ "id": "a", "kind": "install" }, { "id": "a", "kind": "update" }, { "id": "", "kind": "install" },
		{ "id": "d", "kind": "rm -rf" }, "kaputt", { "id": "e", "kind": "update", "when": "irgendwann", "accept": "egal" }]
	var s := Q.sanitize(raw)
	check(s.size() == 2 and str(s[1].when) == "jetzt" and str(s[1].accept) == "ok", "aus den Einstellungen nur saubere Einträge, jede ID einmal")
	var big: Array = []
	for i in 80:
		big.append({ "id": "g%d" % i, "kind": "install" })
	check(Q.sanitize(big).size() == Q.MAX and Q.sanitize("nix").is_empty(), "höchstens %d Einträge, Unsinn ergibt nichts" % Q.MAX)


func _window() -> void:
	check(not Q.in_window(0, 1, 6) and Q.in_window(1, 1, 6) and Q.in_window(5, 1, 6) and not Q.in_window(6, 1, 6), "1 bis 6 Uhr: ab 1, bis vor 6")
	check(Q.in_window(23, 23, 6) and Q.in_window(2, 23, 6) and not Q.in_window(6, 23, 6) and not Q.in_window(12, 23, 6), "über Mitternacht: 23 bis 6")
	check(not Q.in_window(3, 3, 3), "gleiche Stunden: kein Fenster")
	var q: Array = [Q.entry("n", "install", "nachts", 1), Q.entry("p", "update", "jetzt", 2), Q.entry("j", "install", "jetzt", 3)]
	check(Q.candidates(q, { "busy": true, "night": true }).is_empty(), "lädt schon etwas: keiner läuft an (nie zwei auf einmal)")
	check(Q.candidates(q, { "busy": false, "night": false, "playing": "" }) == [1, 2], "tagsüber: die für die Nacht warten")
	check(Q.candidates(q, { "busy": false, "night": true, "playing": "p" }) == [0, 2], "nachts dürfen sie; das laufende Spiel bekommt nie ein Update")


func _misc() -> void:
	check(Q.space_hold(50 * GB, 40 * GB, "ok") == "voll" and Q.space_hold(50 * GB, 40 * GB, "voll") == "",
			"passt nicht: wartet – außer du hast es schon bestätigt")
	check(Q.space_hold(5 * GB, 12 * GB, "ok") == "knapp" and Q.space_hold(5 * GB, 12 * GB, "knapp") == "", "wird knapp: wartet, bestätigt geht es los")
	check(Q.space_hold(5 * GB, 200 * GB, "ok") == "" and Q.space_hold(5 * GB, -1, "ok") == "", "genug Platz oder unbekannt: los")
	var cfg := "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"DownloadThrottleKbps\"\t\t\"40000\"\n\t\t\t}\n\t\t}\n\t}\n}\n"
	check(Q.throttle_kbps(cfg) == 40000 and Q.throttle_text(40000).contains("4,8 MB/s") or Q.throttle_text(40000).contains("4.8 MB/s"),
			"Steams Grenze aus config.vdf (%s)" % Q.throttle_text(40000))
	check(Q.throttle_kbps(cfg.replace("40000", "0")) == 0 and Q.throttle_text(0) == "Ohne Grenze", "0 = ohne Grenze")
	check(Q.throttle_kbps("\"Steam\" { }") == -1 and Q.throttle_text(-1) == "Unbekannt", "nicht eingetragen: unbekannt")
	check(Q.summary(["A"]) == "A" and Q.summary(["A", "B"]) == "A · B" and Q.summary(["A", "B", "C", "D"]) == "A, B und 2 weitere", "Meldung nach dem Ruhemodus")


func _installs() -> void:
	Library.load_demo()
	for x in [["steam:9001", "Testspiel Eins"], ["steam:9002", "Testspiel Zwei"], ["steam:9003", "Testspiel Drei"]]:
		Library.games.append({ "id": x[0], "title": x[1], "source": "steam", "system": "steam", "appid": int(str(x[0]).split(":")[1]), "installed": false })
	Library._reindex()
	Installs.queue = []
	Installs.ctx_override = { "rest": false, "night": false, "game": false, "playing": "" }
	var a := Library.get_game("steam:9001")
	var b := Library.get_game("steam:9002")
	var c := Library.get_game("steam:9003")
	Installs.enqueue(a, "install", "jetzt")
	await get_tree().process_frame
	check(Installs.busy("steam:9001") and not Installs.queued("steam:9001"), "nichts lädt: das erste startet gleich")
	Installs.enqueue(b, "install", "jetzt")
	Installs.enqueue(c, "install", "nachts")
	Installs._queue_tick()
	check(Installs.queued("steam:9002") and not Installs.busy("steam:9002"), "lädt schon etwas: das zweite wartet")
	var saved: Variant = Config.get_value("downloads.queue", [])
	check(saved is Array and (saved as Array).size() == 2 and not str(saved).contains("held"), "Warteschlange in den Einstellungen gemerkt (ohne Zwischenstände)")
	await Installs.cancel("steam:9001")
	Installs._queue_tick()
	await get_tree().process_frame
	check(Installs.busy("steam:9002") and not Installs.queued("steam:9002"), "voriges fertig/abgebrochen: das nächste startet")
	check(Installs.queued("steam:9003"), "das für die Nacht wartet weiter")
	await Installs.cancel("steam:9002")
	Installs._queue_tick()
	check(Installs.queued("steam:9003") and not Installs.busy("steam:9003"), "tagsüber startet nichts für die Nacht, auch wenn frei")
	Installs.ctx_override.night = true
	Installs._queue_tick()
	await get_tree().process_frame
	check(Installs.busy("steam:9003"), "nachts im Ruhemodus: startet")
	await Installs.cancel("steam:9003")
	# Updates: die appmanifests liest eine reine Funktion (läuft im Betrieb im Hilfsfaden, Installs.updates_auffrischen).
	var lib := OS.get_cache_dir().path_join("uzai-dlz-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(lib.path_join("steamapps"))
	for paar in [["100", "6", "1000", "250"], ["200", "4", "0", "0"], ["300", "1030", "500", "0"]]:
		var mf := FileAccess.open(lib.path_join("steamapps/appmanifest_%s.acf" % paar[0]), FileAccess.WRITE)
		mf.store_string('"AppState"\n{\n"appid" "%s"\n"StateFlags" "%s"\n"BytesToDownload" "%s"\n"BytesDownloaded" "%s"\n}\n' % paar)
		mf.close()
	var kein := FileAccess.open(lib.path_join("steamapps/notizen.txt"), FileAccess.WRITE)
	kein.store_string("kein Manifest")
	kein.close()
	var roh: Array = Installs._manifeste_lesen([lib, lib.path_join("gibt-es-nicht")])
	roh.sort_custom(func(a, b) -> bool: return str(a.appid) < str(b.appid))
	check(roh.size() == 2 and str(roh[0].appid) == "100" and int(roh[0].u.remaining) == 750 and str(roh[0].u.phase) == "wartet"
			and str(roh[1].appid) == "300", "appmanifests gelesen: nur, wo ein Update ansteht (%s)" % str(roh).left(160))
	check(Installs._updates_aus(roh).is_empty(), "Spiele, die nicht in der Bibliothek sind, stehen nicht an")
	check(not Installs._updates_liest and Installs.updates_stand() is Array, "Stand ohne Lesen abrufbar")
	# Der ganze Weg über den Hilfsfaden: liest dieselben Dateien, danach gilt der Stand als frisch.
	var demo_war: bool = Library.demo
	Library.demo = false
	Installs._libs = [lib]
	Installs._libs_at = Time.get_ticks_msec()
	Installs._updates_at = -1000000
	var vorher_ms := Time.get_ticks_msec()
	await Installs.updates_auffrischen()
	check(not Installs._updates_liest and Installs._updates_at >= vorher_ms, "updates_auffrischen: gelesen im Hilfsfaden, Stand frisch")
	var nochmal := Installs._updates_at
	await Installs.updates_auffrischen()
	check(Installs._updates_at == nochmal, "gleich danach wird nicht noch einmal gelesen")
	Library.demo = demo_war
	Installs._libs_at = -1000000
	Installs._updates_at = -1000000
	Installs.demo_fill()
	var ups: Array = Installs.pending_updates()
	check(ups.size() == 2 and int(ups[0].u.remaining) > int(ups[1].u.remaining), "Demo: zwei anstehende Updates, größtes zuerst")
	var er := str(ups[0].id)
	Installs.ctx_override = { "rest": true, "night": true, "game": true, "playing": er }
	Config.set_value("downloads.night_updates", true)
	Installs._queue_tick()
	check(Installs.queued(er), "nachts: anstehende Updates werden eingereiht")
	check(not Installs.busy(er), "das laufende Spiel bekommt kein Update")
	var other := str(ups[1].id)
	await get_tree().process_frame
	check(Installs.busy(other) and str(Installs.entry(other).kind) == "update", "das andere Update läuft an (eins nach dem anderen)")
	# Im Ruhemodus fertig: still gesammelt, Meldung beim Aufwachen.
	Installs.items[other]["phase"] = "downloading"
	Installs._end(other, "done", "Aktualisiert")
	check(Installs._quiet_done.size() == 1, "im Ruhemodus fertig: keine Meldung, still gemerkt")
	Installs.ctx_override.rest = false
	Installs._rest_was = true
	Installs._queue_tick()
	check(Installs._quiet_done.is_empty(), "beim Aufwachen eine Meldung, dann leer")
	check(not Installs.busy(other) and Installs.pending_updates().all(func(x: Dictionary) -> bool: return str(x.id) != other),
			"erledigtes Update steht nicht mehr an und läuft nicht neu an")
	# Nicht mehr nötig: fällt heraus.
	Installs.queue = Q.add(Installs.queue, Q.entry("steam:404", "install", "jetzt", 1))
	Installs.ctx_override = { "rest": false, "night": false, "game": false, "playing": "" }
	Installs._queue_tick()
	check(not Installs.queued("steam:404"), "Spiel nicht mehr in der Bibliothek: fällt aus der Warteschlange")
	# Unbeaufsichtigt (nachts, im Spiel): nie ein Dialog – lieber „nicht geladen“.
	var u := Library.get_game("steam:9002")
	Installs.items.erase("steam:9002")
	Installs.items["steam:9002"] = Installs._new_entry(u)
	await Installs._steam_start("steam:9002", u, { "unattended": true })
	check(str(Installs.entry("steam:9002").phase) == "failed" and str(Installs.entry("steam:9002").how) == "",
			"unbeaufsichtigt ohne Fern-Auftrag: kein Dialog, ehrlich gescheitert")
	# Nach einem Neustart: Warteschlange aus den Einstellungen.
	var kept := Q.sanitize(Config.get_value("downloads.queue", []))
	check(kept.size() == Installs.queue.size(), "über einen Neustart: dieselbe Warteschlange")
	Installs.ctx_override = {}
