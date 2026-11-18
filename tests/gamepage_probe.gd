extends Node
## Bildschirmfotos der Spielseite mit Beispielinhalten (nur mit --uzai-gamepage=<ordner>).
## Bild, Schriftzug, Screenshots, Store-Angaben und Erfolge werden hier vorgegeben, weil der
## Rundgang ohne Internet läuft.

var out := ""
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-gamepage="):
			out = a.substr(16)
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String, wait := 0.6) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("Bild: ", name)


func _run() -> void:
	main = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var src := OS.get_environment("UZAI_DEMO_ART")
	var g := Library.get_game("steam:1245620")
	g["images"] = { "hero": src.path_join("hero.jpg"), "logo": src.path_join("logo.png") }
	Media.forget(g)
	var shots: Array = []
	for i in 6:
		shots.append("https://demo.uzai/shot%d.jpg" % i)
	Store._details[1245620] = {
		"about": "Erhebe dich, Befleckter, und lass dich von der Gnade leiten, um die Macht des Eldenrings zu nutzen und ein Eldenfürst im Zwischenland zu werden. Eine weite Welt voller Gefahren, offen erkundbar, mit gewaltigen Dungeons und Gegnern, die dich alles abverlangen.",
		"genres": PackedStringArray(["Action", "Rollenspiel"]), "developer": "FromSoftware", "release": "25. Feb. 2022",
		"my_lang": true, "metacritic": 94, "screens": shots,
	}
	var list: Array = []
	var names := ["Eldenfürst", "Zeitalter der Sterne", "Herr des Frenzied Flame", "Schild-Großmeister", "Leyndell erreicht", "Malenia besiegt", "Rennala besiegt",
			"Radahn besiegt", "Godrick besiegt", "Morgott besiegt", "Mohg besiegt", "Rykard besiegt"]
	for i in names.size():
		list.append(
				{ "id": str(i), "title": names[i], "desc": "Beispielerfolg %d" % (i + 1), "icon": "", "icon_locked": "", "unlocked": i < 8, "rarity": 10.0 + i * 5 })
	Achievements._games["steam:1245620"] = { "source": "steam", "total": 42, "unlocked": 29, "list": list }
	await shot("00_start", 0.2)
	main.open_game(g)
	await shot("01_spielseite_oben", 2.5)
	Nav._fire("down")
	await shot("02_spielseite_bilder", 1.2)
	Nav._fire("down")
	await shot("03_spielseite_erfolge", 1.0)
	Nav._fire("down")
	await shot("04_spielseite_freunde", 1.0)
	Nav._fire("down")
	Nav._fire("down")
	await shot("05_spielseite_unten", 1.2)
	Nav._fire("b")
	await get_tree().create_timer(0.6).timeout
	await _rom(src)
	print("Spielseite fertig")
	get_tree().quit()


## Ein Emulator-Spiel: Bilder aus Libretro (vorab in den Cache gelegt, wie nach dem ersten Laden)
## und ein Beispieltext an der Stelle, wo sonst die deutsche Wikipedia-Einleitung steht.
func _rom(src: String) -> void:
	var g := Library.get_game("ps2:74a8e64542ec02")
	if g.is_empty() or not DirAccess.dir_exists_absolute(src.path_join("rom")):
		return
	var h := str(g.id).md5_text().substr(0, 16)
	for kind in ["snap", "title", "cover"]:
		var dest := Config.path("cache/img/libretro/%s_%s.png" % [h, kind])
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		DirAccess.copy_absolute(src.path_join("rom/%s.png" % kind), dest)
	Config.write_json(Config.path("cache/wiki/%s.json" % str(g.id).md5_text()), {
		"t": int(Time.get_unix_time_from_system()), "page": "Shadow of the Colossus", "page_de": "Shadow of the Colossus", "shots": [],
		"about": "(Beispieltext für den Rundgang) Ein junger Krieger reitet in ein verbotenes Land, um sechzehn riesige Kolosse zu bezwingen. Jeder Koloss ist ein eigenes Rätsel: erklettern, Schwachstelle finden, festhalten.",
	})
	Media.forget(g)
	main.open_game(g)
	await shot("06_emulator_oben", 2.5)
	Nav._fire("down")
	await shot("07_emulator_bilder", 1.2)
	Nav._fire("down")
	Nav._fire("down")
	await shot("08_emulator_text", 1.2)
