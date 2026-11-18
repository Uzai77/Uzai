extends Node
## Rundgang durch die Neuerungen von 0.5.2 (nur mit --uzai-tour052=<ordner>).

var out := ""
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-tour052="):
			out = a.substr(15)
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String, wait := 0.6) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("Bild: ", name)


func press(cmd: String, times := 1, gap := 0.15) -> void:
	for i in times:
		Nav._fire(cmd)
		await get_tree().create_timer(gap).timeout


func _run() -> void:
	main = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	main.goto("videos", "fuerdich")
	await shot("01_videos_fuer_dich", 1.2)
	main.goto("videos", "start")
	await shot("02_videos_start", 1.0)
	main.goto("music", "jetzt")
	await shot("03_musik_jetzt", 1.0)
	await press("right", 3)
	await shot("04_musik_warteschlange", 0.6)
	main.goto("music", "playlists")
	await shot("05_musik_playlists", 1.0)
	await press("right")
	await press("a")
	await shot("06_playlist_titel", 1.2)
	await press("down", 2)
	await press("a")
	await shot("07_playlist_abspielen", 0.8)
	await press("b")
	main.goto("music", "lieblinge")
	await shot("08_lieblingssongs", 1.2)
	main.goto("shop", "entdecken")
	await shot("09_shop_entdecken", 3.0)
	await press("down")
	await shot("10_shop_reihe", 0.6)
	await press("a")
	await shot("11_shop_spiel", 2.0)
	await press("rb")
	await shot("12_shop_spiel_bild2", 0.8)
	await press("b")
	main.goto("shop", "specials")
	await shot("13_shop_angebote", 1.2)
	await press("y")
	await shot("14_shop_sortiert", 0.8)
	main.goto("shop", "genres")
	await shot("15_shop_genres", 0.8)
	await press("a")
	await shot("16_shop_genre", 1.5)
	await press("b")
	await shot("17_shop_genres_zurueck", 0.6)
	main.goto("shop", "wunschliste")
	await shot("18_shop_wunschliste", 1.0)
	main.goto("friends", "steam")
	await shot("19_freunde", 1.2)
	main.open_chat(Social.steam_friends[0] if not Social.steam_friends.is_empty() else { "id": "76561198000000011", "name": "Pixelpaul", "state": "online" })
	await shot("20_chat", 1.5)
	await press("up", 2)
	await shot("21_chat_hoch", 0.6)
	await press("b")
	main.goto("settings", "konten")
	await shot("22_einstellungen_konten", 1.0)
	main.goto("settings", "videos")
	await shot("23_einstellungen_videos", 1.0)
	main.goto("settings", "controller")
	await shot("24_einstellungen_controller", 1.0)
	main.toggle_guide()
	await shot("25_guide", 1.2)
	await press("rb", 2)
	await shot("26_guide_musik", 1.0)
	main.open_chat(Social.steam_friends[0] if not Social.steam_friends.is_empty() else { "id": "76561198000000011", "name": "Pixelpaul", "state": "online" })
	await shot("27_guide_chat", 1.5)
	main.goto("games")
	await shot("28_start", 1.5)
	await press("a")
	await shot("30_spielseite", 2.0)
	await press("down")
	await shot("31_spielseite_unten", 1.0)
	await press("b")
	main.open_layer(load("res://src/ui/layers/welcome.gd").new())
	await shot("29_willkommen", 1.0)
	await press("b")
	print("Rundgang fertig")
	get_tree().quit()
