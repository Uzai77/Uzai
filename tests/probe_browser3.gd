extends "res://tests/probe_base.gd"
## Browser-Kern einrichten und Controller koppeln im Vorführmodus: Fortschritt auf der Startbühne (von selbst, X bricht
## ab), Dialog über dem Browser mit Fokus (auch wenn er im selben Bild wie der Browser aufgeht – der Fehler aus 0.16.15),
## Koppeln mit neuen, gekoppelten und verbundenen Controllern. Ausgabe „B3 ok/FAIL …“, Bilder 01–03.

const Lauf := preload("res://src/core/browser_kern_lauf.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("B3 %s %s" % ["ok  " if cond else "FAIL", what])


func run() -> void:
	main.goto("browser")
	await wait(1.2)
	Lauf.starten(true)
	await wait(2.4)
	var f: Control = Nav.focused()
	_ck(f != null and str(f.get_meta("uz_key", "")) == "browser:oeffnen" and f.has_meta("uz_on_x"), "Startbühne: Fortschritt, X bricht ab")
	await shot("browser3_fortschritt_buehne", 0.2)
	await Lauf.jetzt.fertig
	await wait(0.6)
	_ck(not Nav.focused().has_meta("uz_on_x"), "fertig: Bühne wieder normal")
	# Der Fehler aus 0.16.15: Der Dialog kommt, während der Browser selbst noch aufgeht.
	Lauf.starten(true)
	main.open_browser("", 0, false, {})
	var b: Control = null
	for l in Nav.layers:
		if is_instance_valid(l) and str(l.get_script().resource_path).ends_with("layers/browser.gd"):
			b = l
	if b == null:
		b = main.layer_host.get_child(main.layer_host.get_child_count() - 1)
	b.call("_kern_anbieten")
	await wait(1.4)
	var top := Nav.top_layer()
	_ck(top != null and str(top.get_script().resource_path).ends_with("browser_kern_ui.gd"), "Dialog liegt oben (über dem Browser)")
	var fo := Nav.focused()
	_ck(fo != null and top != null and top.is_ancestor_of(fo) and str(fo.get_meta("uz_key", "")) == "browser:kern:hintergrund", "Fokus sofort im Dialog („Im Hintergrund“)")
	await shot("browser3_kern_dialog", 0.2)
	press("left")
	await wait(0.3)
	_ck(str(Nav.focused().get_meta("uz_key", "")) == "browser:kern:abbrechen", "Steuerkreuz erreicht „Abbrechen“")
	await Lauf.jetzt.fertig
	await wait(1.6)
	var nach := Nav.top_layer()
	_ck(nach != null and str(nach.get_script().resource_path).ends_with("layers/browser.gd"), "fertig: Dialog zu, Browser vorn")
	press("b")
	await wait(1.2)
	# Koppeln
	load("res://src/ui/layers/pad_pair.gd").open_for(main)
	await wait(3.4)
	var pp := Nav.top_layer()
	_ck(pp != null and str(pp.get_script().resource_path).ends_with("pad_pair.gd"), "Koppeln offen")
	press("a")
	await wait(2.8)
	await shot("browser3_koppeln", 0.2)
	_ck(str(pp.get("_results")).contains("gekoppelt"), "erster Controller gekoppelt, Suche läuft weiter")
	print("B3 Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
