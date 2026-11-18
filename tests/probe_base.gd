extends Node
## Grundlage für eigene Bildschirm-Proben beim Gestalten.
##
## Aufruf (Demo-Daten, eigener Datenordner, damit parallele Läufe sich nicht stören):
##   UZAI_DATA=/tmp/uzai-a xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path <projekt> \
##     --resolution 1920x1080 -- --demo --no-boot --uzai-script=res://tests/probe_x.gd --uzai-out=<ordner>
##
## Eine Probe erweitert diese Datei und schreibt run(): main.goto(...), press("down"),
## await shot("01_name") … Am Ende beendet sich Godot von selbst.

var out := ""
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-out="):
			out = a.substr(11)
	if out == "":
		out = OS.get_user_data_dir().path_join("probe")
	DirAccess.make_dir_recursive_absolute(out)
	_start()


func _start() -> void:
	main = get_tree().current_scene
	# Startbild und erste Daten abwarten.
	await get_tree().create_timer(2.5).timeout
	await run()
	print("Probe fertig: ", out)
	get_tree().quit()


## Überschreiben: der eigentliche Rundgang.
func run() -> void:
	pass


func shot(name: String, wait := 0.6) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("Bild: ", name)


func press(cmd: String, times := 1, gap := 0.18) -> void:
	for i in times:
		Nav._fire(cmd)
		await get_tree().create_timer(gap).timeout


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
