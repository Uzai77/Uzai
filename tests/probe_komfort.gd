extends "res://tests/probe_base.gd"
## Probe „Komfort“: Schnellmenü mit Schlaf-Timer, Nicht stören und Nur hören (Musik läuft, Timer
## gestellt), dann das Ausschalten-Menü mit Schlaf-Timer und Nur hören. Gibt „KF ok/FAIL …“ aus.

const Guide := preload("res://src/ui/layers/guide.gd")
const NichtStoeren := preload("res://src/core/nicht_stoeren.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("KF %s %s" % ["ok  " if cond else "FAIL", what])


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("system.quick_tiles", ["shot", "schlaf", "ruhe", "hoeren", "mitteilungen", "rest", "beenden", "guide"])
	Music.now["playing"] = true
	if str(Music.now.get("title", "")) == "":
		Music.now["title"] = "Midnight City"
	main.rest.schlaf.setzen("30")
	NichtStoeren.an = true
	main.toggle_guide(Guide.QUICK)
	await shot("01_schnellmenue_komfort", 1.4)
	_ck(main.rest.schlaf.text().begins_with("noch"), "Schlaf-Timer läuft (%s)" % main.rest.schlaf.text())
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.5)
	main.open_power()
	await shot("02_ausschalten_menue", 1.2)
	NichtStoeren.an = false
	main.rest.schlaf.setzen("")
	print("KF Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
