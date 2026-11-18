extends Node
## Kurzer Rundgang für ein Video mit Ton (--uzai-reel, zusammen mit Godots --write-movie).
## Zeigt Startseite, Reiter, Bereichswechsel, Guide mit Discord, Person-Menü und Musik.

var main: Node


func _ready() -> void:
	_run()


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func press(cmd: String, times := 1, gap := 0.32) -> void:
	for i in times:
		Nav._fire(cmd)
		await wait(gap)


func _run() -> void:
	main = get_tree().current_scene
	await wait(1.6)
	await press("right", 3, 0.42)
	await wait(0.5)
	await press("up")
	await press("rb", 1, 0.9)
	await press("lb", 1, 0.9)
	await press("down")
	await press("left", 2, 0.36)
	await press("up", 2, 0.4)
	await press("right", 2, 0.3)
	await press("a", 1, 0.9)
	await press("rt", 1, 1.0)
	await press("lt", 1, 1.0)
	main.toggle_guide()
	await wait(1.4)
	await press("a", 1, 0.8)
	await press("down", 1, 0.4)
	await press("right", 3, 0.22)
	await wait(0.4)
	await press("b", 1, 0.5)
	await press("x", 1, 0.9)
	await press("x", 1, 0.7)
	await press("rb", 1, 1.4)
	await press("right", 1, 0.4)
	await press("a", 1, 0.8)
	await press("rb", 1, 0.9)
	await press("rb", 1, 0.9)
	await press("rb", 1, 1.0)
	await press("b", 1, 1.0)
	get_tree().quit()
