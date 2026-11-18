extends Node
## Bildschirmfotos aller Bereiche mit Controller-Tastensymbolen (nur mit --uzai-tabs=<ordner>).
## Zeigt, wie Uzai aussieht, wenn ein Controller benutzt wird: A/B/X/Y, LB/RB, LT/RT.

var out := ""
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-tabs="):
			out = a.substr(12)
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String, wait := 0.8) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("Bild: ", name)


func pad(set_name: String, pad_name: String) -> void:
	Config.set_value("controller.glyphs", set_name)
	Nav.device = "pad"
	Nav.pad_name = pad_name
	Nav.device_changed.emit("pad")


func _run() -> void:
	main = get_tree().current_scene
	Config.set_value("theme.preset", "uzai")
	Config.set_value("theme.corners", "rund")
	Config.set_value("theme.cover_shape", "hoch")
	await get_tree().create_timer(5.0).timeout
	pad("xbox", "Xbox Wireless Controller")
	# Beispieldaten für Erfolge, damit die Übersicht gefüllt ist.
	var now := int(Time.get_unix_time_from_system())
	for k in ["ra_user", "ra_key", "steam_key", "steam_id"]:
		Config.set_value("accounts." + k, "demo")
	Achievements.ra_profile = { "points": 12340, "rank": 4512 }
	Achievements.ra_progress = [
		{ "title": "Ōkami", "source": "ra", "ra_id": 1, "console": 21, "console_name": "PlayStation 2", "unlocked": 44, "total": 52, "icon": "" },
		{ "title": "Shadow of the Colossus", "source": "ra", "ra_id": 2, "console": 21, "console_name": "PlayStation 2", "unlocked": 26, "total": 26, "icon": "" },
	]
	Achievements.steam_progress = [{ "title": "Elden Ring", "source": "steam", "appid": 1245620, "unlocked": 31, "total": 42, "icon": "" }]
	Achievements.recent_unlocks = [
		{ "title": "Wolkenwanderer", "game": "Ōkami", "date": now - 3600, "points": 10, "source": "ra", "icon": "" },
		{ "title": "Elden Lord", "game": "Elden Ring", "date": now - 90000, "source": "steam", "icon": "" },
	]
	var n := 1
	for sid in main.order:
		main.goto(sid)
		await shot("%02d_%s" % [n, sid], 1.0)
		n += 1
	main.goto("achievements", "statistik")
	await shot("%02d_achievements_spielzeit" % n, 1.0)
	n += 1
	main.goto("games", "zuletzt")
	await get_tree().create_timer(0.5).timeout
	main.toggle_guide()
	await shot("%02d_guide" % n, 1.2)
	n += 1
	main.toggle_guide()
	await get_tree().create_timer(0.8).timeout
	# Dasselbe mit PlayStation- und Nintendo-Symbolen (gezeichnet, ohne Herstellerlogos).
	pad("ps", "DualSense Wireless Controller")
	main.goto("games", "zuletzt")
	await shot("%02d_games_playstation" % n, 1.0)
	n += 1
	pad("nintendo", "Pro Controller")
	await shot("%02d_games_nintendo" % n, 0.6)
	for k in ["ra_user", "ra_key", "steam_key", "steam_id"]:
		Config.set_value("accounts." + k, "")
	Config.set_value("controller.glyphs", "auto")
	print("Rundgang fertig")
	get_tree().quit()
