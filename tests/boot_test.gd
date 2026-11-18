extends Control
## Bilder der Startanimation zu festen Zeitpunkten (für die Kontrolle des Designs).
## Aufruf: godot --path . res://tests/boot_test.tscn -- --out=<ordner>

const Boot := preload("res://src/ui/boot.gd")


func _ready() -> void:
	var out := "/tmp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var b = Boot.new().setup("voll")
	add_child(b)
	b.set_process(false)
	for t in [0.4, 0.9, 1.4, 1.9, 2.1, 2.5, 2.8, 3.3, 3.9, 4.6]:
		b.seek(t)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("boot_%04d.png" % int(t * 1000)))
	get_tree().quit()
