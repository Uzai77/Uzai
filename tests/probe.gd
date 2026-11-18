extends Node
## Schnelle Bildschirmfotos von Startseite und Guide beim Gestalten (--uzai-probe=<ordner>).

var out := ""
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-probe="):
			out = a.substr(13)
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String, wait := 0.5) -> void:
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
	await get_tree().create_timer(1.5).timeout
	await shot("a_home", 1.0)
	await press("right", 2)
	await shot("b_home_right", 0.8)
	await press("up")
	await shot("c_home_up", 0.5)
	await press("up")
	await shot("d_home_up2", 0.5)
	await press("right", 2)
	await press("a")
	await shot("d2_heart", 0.6)
	await press("down", 2)
	await press("rb")
	await shot("e_ps2", 0.9)
	main.toggle_guide()
	await shot("f_guide", 1.2)
	await press("a")
	await shot("f2_person_menu", 0.8)
	await press("down")
	await press("right", 2)
	await shot("f3_person_volume", 0.4)
	await press("b")
	await press("x")
	await shot("f4_local_mute", 0.4)
	await press("left")
	await press("a")
	await shot("f5_me_menu", 0.6)
	await press("b")
	for i in 4:
		await press("rb")
		await shot("g_guide_tab%d" % i, 0.8)
	get_tree().quit()
