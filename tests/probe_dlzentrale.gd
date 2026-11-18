extends "res://tests/probe_base.gd"
## Probe für die Download-Zentrale (Punkt 107): Downloads mit laufendem Download, Warteschlange
## (danach, heute Nacht, wartet auf Platz), anstehenden Updates und „Fertig“; die Frage „wann
## laden?“ beim Installieren, die Knöpfe einer Zeile der Warteschlange und eines Updates, die
## Einstellungen „Nachts laden“ und die stille Meldung nach dem Ruhemodus.

const Flow := preload("res://src/ui/install_flow.gd")
const Q := preload("res://src/core/dl_queue.gd")


func run() -> void:
	Config.set_value("theme.preset", "uzai")
	Config.set_value("downloads.night", true)
	Config.set_value("downloads.night_from", "1")
	Config.set_value("downloads.night_to", "6")
	for x in [["steam:9101", "Hollow Knight: Silksong", 9101], ["steam:9102", "Clair Obscur: Expedition 33", 9102],
			["steam:9103", "Hades II", 9103], ["steam:9104", "Split Fiction", 9104]]:
		Library.games.append({ "id": x[0], "title": x[1], "source": "steam", "system": "steam", "appid": x[2], "installed": false })
	Library._reindex()
	Installs.main = main
	Installs.ctx_override = { "rest": false, "night": false, "game": false, "playing": "" }
	# Einer lädt, zwei warten (danach, heute Nacht), einer wartet auf Platz.
	Installs.enqueue(Library.get_game("steam:9101"), "install", "jetzt")
	await wait(0.4)
	Installs.enqueue(Library.get_game("steam:9102"), "install", "jetzt")
	Installs.enqueue(Library.get_game("steam:9103"), "install", "nachts")
	Installs.enqueue(Library.get_game("steam:9104"), "install", "jetzt")
	Installs.queue[2]["held"] = "voll"
	Flow.open_downloads(main)
	await shot("01_zentrale", 2.4)
	await press("down", 4)
	await shot("02_updates_fokus", 0.8)
	# Knöpfe einer Zeile der Warteschlange und eines Updates.
	Flow.queue_actions(main, "steam:9103")
	await shot("03_warteschlange_knoepfe", 0.8)
	await _close_top()
	var ups: Array = Installs.pending_updates()
	if not ups.is_empty():
		Flow.update_actions(main, ups[0])
		await shot("04_update_knoepfe", 0.8)
		await _close_top()
	# Nach vorn: die Reihenfolge ändert sich sofort.
	Installs.queue_move("steam:9104", -1)
	await shot("05_nach_vorn", 0.8)
	await press("down", 12)
	await shot("06_unten_nacht_bandbreite", 0.8)
	await press("a")
	await shot("06b_bandbreite_wo", 0.8)
	await _close_top()
	await _close_all()
	# „Wann laden?“ beim Installieren, während etwas lädt.
	var g := { "id": "steam:9199", "title": "Hollow Knight", "source": "steam", "system": "steam", "appid": 9199, "installed": false }
	Library.games.append(g)
	Library._reindex()
	Flow._begin_checked(main, Library.get_game("steam:9199"))
	await shot("07_wann_laden", 0.8)
	await _close_all()
	# Einstellungen → Spiele → Installieren und Downloads.
	main.goto("settings", "spiele")
	await wait(1.0)
	var sv = main.sections["settings"]
	sv.open_more("Installieren und Downloads")
	await wait(0.6)
	await press("down", 5)
	await shot("08_einstellungen_nacht", 0.8)
	await _close_all()
	# Im Ruhemodus fertig: beim Aufwachen eine stille Meldung.
	Installs._quiet_done = ["Hades II", "Split Fiction", "Elden Ring"]
	Installs._rest_was = true
	Installs._queue_tick()
	await shot("09_meldung_nach_ruhemodus", 0.6)
	Installs.ctx_override = {}


func _close_top() -> void:
	if Nav.top_layer():
		Nav.top_layer().close()
	await wait(0.35)


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().process_frame
	await wait(0.25)
