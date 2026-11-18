extends Node
## Probe für den Guide (--uzai-probe2=<bild.png>): öffnet ihn, schreibt die Größen seines Inhalts und speichert ein Bild.

var out := ""
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-probe2="):
			out = a.substr(14)
	_run()
func _run() -> void:
	var main = get_tree().current_scene
	await get_tree().create_timer(1.5).timeout
	main.toggle_guide()
	await get_tree().create_timer(1.5).timeout
	var g = main._guide
	var c: Control = g._content
	print("content size ", c.size, " min ", c.get_combined_minimum_size(), " pos ", c.position)
	print("holder size ", c.get_parent().size, " card ", g._card.size)
	for ch in c.get_children():
		print("  ", ch.get_class(), " ", ch.name, " size ", ch.size, " min ", ch.get_combined_minimum_size())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
