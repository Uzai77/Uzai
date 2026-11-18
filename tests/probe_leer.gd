extends "res://tests/probe_base.gd"
## Leere Bühnen (src/ui/components/leer_buehne.gd) ohne jedes Konto: Spiele, Freunde (Seitenleiste)
## und Erfolge. Aufruf ohne --demo mit leerem Datenordner (die Einrichtung schließt die Probe).


func run() -> void:
	await _ebenen_zu()
	main.goto("games")
	await shot("01_spiele", 2.0)
	main.goto("achievements")
	await shot("02_erfolge", 1.5)
	main.open_friends("")
	await shot("03_freunde", 1.5)


func _ebenen_zu() -> void:
	for i in 6:
		var t: Control = Nav.top_layer()
		if t == null:
			return
		if t.has_method("close"):
			t.call("close")
		else:
			t.queue_free()
		await wait(0.5)
