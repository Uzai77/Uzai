extends "res://tests/probe_base.gd"
## Eigene Apps (src/core/apps_extern.gd): Symbole oben mit Store-App und Programm, „+“ (App hinzufügen), langes A,
## Rückfrage beim ersten Start eines Programms, Guide während einer App. Ausgabe „AP ok/FAIL …“.

const A := preload("res://src/core/apps_extern.gd")
const L := preload("res://src/core/leiste_oben.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("AP %s %s" % ["ok  " if cond else "FAIL", what])


func _logo() -> String:
	# Schlichtes Probe-Logo (kein echtes Markenzeichen): ein Kreis im Quadrat.
	var img := Image.create(150, 150, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 150:
		for x in 150:
			if Vector2(x - 75, y - 75).length() < 52:
				img.set_pixel(x, y, Color(0.9, 0.12, 0.15))
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.3)


func run() -> void:
	Config.set_value(A.KEY, [])
	var n := A.add_store("4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "Netflix")
	A.add_store("Disney.37853FC22B2CE_6rarf9sa4v8jt!App", "Disney+")
	var k := A.add_prog("C:\\Program Files\\Kodi\\kodi.exe", "Kodi")
	_ck(bool(n.ok) and bool(k.ok), "zwei Store-Apps und ein Programm")
	A.save_logo(str(n.id), _logo())
	main.show_app_soon(str(n.id))
	await wait(2.0)
	var f := Nav.focused()
	_ck(main.current == str(n.id) and f != null and str(f.get_meta("uz_key", "")) == "tab:" + str(n.id), "neue App: ihr Symbol oben, Cursor darauf")
	_ck(main.app_kids.has(str(k.id)), "Programm in der Leiste")
	await shot("01_symbol_store_app", 0.8)
	var plus: Control = null
	for c in main.tabs_box.get_children():
		if str(c.get_meta("uz_key", "")) == "tab:" + L.ADD:
			plus = c
	_ck(plus != null, "„+“ hinter den App-Symbolen")
	if plus:
		Nav.focus(plus, true)
		await shot("03_plus", 0.4)
	main.open_add_app()
	await wait(1.4)
	await shot("04_plus_app_liste", 0.4)
	await _close_all()
	# Langes A auf dem Programm
	main._gruppe.call("menu", str(k.id), "Kodi")
	await wait(0.9)
	await shot("05_langes_a", 0.3)
	await _close_all()
	# Erster Start eines Programms: Rückfrage
	main.start_app(str(k.id))
	await wait(0.9)
	_ck(Nav.top_layer() != null, "Programm fragt beim ersten Start")
	await shot("06_rueckfrage", 0.3)
	await _close_all()
	# Guide während einer App
	Launcher.in_game = true
	Launcher.current = A.launch_game(A.get_entry(str(n.id)))
	main.toggle_guide("spiel")
	await wait(1.6)
	await shot("07_guide_app", 0.5)
	await _close_all()
	Launcher.in_game = false
	Launcher.current = {}
	Config.set_value(A.KEY, [])
	print("AP Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
