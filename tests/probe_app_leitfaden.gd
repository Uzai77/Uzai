extends "res://tests/probe_base.gd"
## Eigene Apps (src/core/app_steuerung.gd): Y auf dem App-Symbol öffnet die Optionen mit „Entfernen“
## (geprüft), dazu Bilder des Leitfadens (app_leitfaden.gd) für Xbox- und PlayStation-Form mit der
## Belegung von Netflix – im Hauptfenster gezeichnet (das eigene Fenster über der App gibt es nur unter Windows).

const A := preload("res://src/core/apps_extern.gd")
const S := preload("res://src/core/app_steuerung.gd")
const Leitfaden := preload("res://src/ui/app_leitfaden.gd")


func run() -> void:
	Config.set_value(A.KEY, [])
	var nf := A.add_store("4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "Netflix")
	main._rebuild()
	await wait(1.6)
	var id := str(nf.id)
	Nav.focus(main._tab_items[id], true)
	await wait(0.5)
	await press("y")
	await wait(0.6)
	var top = Nav.top_layer()
	var opts: Array = top.get("options") if top else []
	print("Y-Optionen: ", opts)
	await shot("apps5_optionen_y", 0.3)
	if top:
		top.picked.emit("remove")
		top.close()
	await wait(1.0)
	print("Entfernt über Y: ", A.get_entry(id).is_empty() and not main._tab_items.has(id))
	for fam in ["xbox", "ps"]:
		var layer := CanvasLayer.new()
		layer.layer = 120
		get_tree().root.add_child(layer)
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.06, 0.08)
		bg.size = Vector2(1920, 1080)
		layer.add_child(bg)
		var b = Leitfaden.Bild.new()
		b.familie = fam
		b.belegung = S.belegung({ "id": id, "kind": "store", "name": "Netflix", "aumid": "4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App" })
		b.titel = "Netflix"
		b.position = Vector2(340, 220)
		b.size = Vector2(1240, 640)
		layer.add_child(b)
		await shot("apps5_leitfaden_" + fam, 0.5)
		layer.queue_free()
	Config.set_value(A.KEY, [])
