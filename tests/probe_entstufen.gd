extends "res://tests/probe_base.gd"
## Probe „Entstufen“ (Color Banding): misst Stufen in dunklen, weichen Verläufen – Startbild (Licht
## der LED auf der Wand), Willkommen der Einrichtung (Schein hinter dem Zeichen) und Startseite
## (Lichter und Abdunklung des Hintergrunds). Je Bild eine Zeile durch den Verlauf, abseits von Schrift:
## Ein gestufter Verlauf hat lange Strecken gleicher Werte (Bänder), ein entstufter nur kurze.
## Ausgabe: „Stufen <name>: Läufe … mittlere Länge … längste … Werte …“ und je ein Bild.
## Aufruf wie probe_base.gd, mit --demo.

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")


func run() -> void:
	# Startbild: Das U steht, die LED wirft Licht auf die Wand (links davon: nur Raum und Licht).
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var boot = load("res://src/ui/boot.gd").new()
	boot.preview = true
	boot.setup("voll")
	layer.add_child(boot)
	await wait(0.3)
	boot.set_process(false)
	boot._t = 2.0
	boot.queue_redraw()
	await shot("e1_start", 0.2)
	_messen("start", 540, 120, 640)
	layer.queue_free()
	await wait(0.3)
	# Startseite: Lichter und Abdunklung des Hintergrunds.
	await shot("e2_startseite", 0.6)
	_messen("startseite", 1000, 200, 1700)
	# Einrichtung: Willkommen, wenn das Licht steht.
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.restart", false)
	Config.set_value("einrichtung.tour", true)
	Config.set_value("einrichtung.step", "willkommen")
	Wizard.open_for(main, false)
	await shot("e3_willkommen", 2.6)
	_messen("willkommen", 300, 60, 700)


## Eine Zeile y von x0 bis x1 im zuletzt geschriebenen Bild: Läufe gleicher Werte (Grünkanal).
func _messen(name: String, y: int, x0: int, x1: int) -> void:
	var img := get_viewport().get_texture().get_image()
	var vals: Array = []
	for x in range(x0, x1):
		vals.append(int(round(img.get_pixel(x, y).g * 255.0)))
	var laeufe: Array = []
	var n := 1
	for i in range(1, vals.size()):
		if vals[i] == vals[i - 1]:
			n += 1
		else:
			laeufe.append(n)
			n = 1
	laeufe.append(n)
	var laengste := 0
	for l in laeufe:
		laengste = maxi(laengste, int(l))
	var werte := {}
	for v in vals:
		werte[v] = true
	print("Stufen %s: Läufe %d, mittlere Länge %.1f px, längste %d px, Werte %d (%d … %d)" % [name, laeufe.size(),
			float(vals.size()) / float(laeufe.size()), laengste, werte.size(), vals.min(), vals.max()])
