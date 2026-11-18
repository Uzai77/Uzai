extends "res://tests/probe_base.gd"
## Messprobe „Untermenüs“ (Demo, ohne Bilder): Wie lange steht ein Bild, wenn eine Ebene aufgeht –
## Guide und seine Reiter, Ausschalten, Einstellungen (Kategorien und Unterseiten), Seitenleisten.
## Je Schritt: block = so lange hing der Aufruf selbst (ms), bild = längstes Bild ab dem Bild des
## Aufrufs bis 0,8 s danach. Headless laufen lassen (ohne Grafik zählt nur die Rechenzeit):
##   godot --headless --path . -- --demo --no-boot --uzai-script=res://tests/probe_untermenues.gd
## Ausgabe „UM …“, am Ende die drei teuersten und wie viele Schritte ein Bild über 25 ms hatten.

var _rows: Array = []


## Jeder Bildanfang (als erste Verbindung an process_frame, also vor allem anderen in dem Bild):
## Abstand zweier Anfänge = ein ganzes Bild samt Aufbau, Layout und Zeichnen.
var _anfaenge: Array = []


func _ready() -> void:
	get_tree().process_frame.connect(func() -> void: _anfaenge.append(Time.get_ticks_usec()))
	super._ready()


func _messen(name: String, tat: Callable) -> void:
	await wait(0.5)
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var ab := _anfaenge.size() - 1
	await tat.call()
	var block := (Time.get_ticks_usec() - t0) / 1000.0
	await wait(0.8)
	var bild := 0.0
	for i in range(ab + 1, _anfaenge.size()):
		bild = maxf(bild, (int(_anfaenge[i]) - int(_anfaenge[i - 1])) / 1000.0)
	_anfaenge = _anfaenge.slice(_anfaenge.size() - 1)
	_rows.append([name, block, bild])
	print("UM %-34s block %6.1f ms  bild %6.1f ms" % [name, block, bild])


func _zu() -> void:
	var n := 0
	while Nav.top_layer() and n < 6:
		Nav.top_layer().close()
		n += 1
		await wait(0.35)


func run() -> void:
	await wait(2.0)
	await _messen("leerlauf", func() -> void: pass)
	# Guide und Reiter
	await _messen("guide", func() -> void: main.toggle_guide())
	var g: Control = main._guide
	if g:
		for id in g.call("_tabs"):
			var tid := str(id[0]) if id is Array else str(id)
			await _messen("guide_reiter_" + tid, func() -> void: g.call("_show_tab", tid, true, 1))
	await _messen("ausschalten", func() -> void: main.open_power())
	await _zu()
	# Seitenleisten
	await _messen("leiste_freunde", func() -> void: main.open_friend_picker("Freunde", func(_k, _f) -> void: pass))
	await _zu()
	var opts: Array = []
	for i in 12:
		opts.append([str(i), "Wahl %d" % i])
	await _messen("leiste_auswahl", func() -> void: main.open_choice("Auswahl", opts, "3", func(_v) -> void: pass))
	await _zu()
	var spiele: Array = Library.games
	if not spiele.is_empty():
		await _messen("spieloptionen", func() -> void: main.open_game_options(spiele[0]))
		await _zu()
	# Einstellungen: jede Kategorie, dann ihre Unterseiten
	main.goto("settings")
	await wait(1.5)
	var s: Node = main.sections.get("settings")
	if s:
		var cats: Array = []
		var sc: Script = s.get_script()
		while sc and cats.is_empty():
			cats = sc.get_script_constant_map().get("CATS", [])
			sc = sc.get_base_script()
		for c in cats:
			var cat := str(c[0])
			await _messen("einst_" + cat, func() -> void:
				s.call("_show_cat", cat))
			await wait(0.6)
			var mores: Dictionary = s.get("_mores")
			for t in mores.keys():
				var tt := str(t)
				# Schließen baut die Kategorie mitunter neu (andere Unterseiten-Liste): dann neu wählen.
				if not (s.get("_mores") as Dictionary).has(tt):
					s.call("_show_cat", cat)
					await wait(0.4)
				if not (s.get("_mores") as Dictionary).has(tt):
					continue
				await _messen("einst_%s_%s" % [cat, tt.left(18)], func() -> void: s.call("open_more", tt))
				await _zu()
	_rows.sort_custom(func(a, b) -> bool: return a[2] > b[2])
	for r in _rows.slice(0, 3):
		print("UM teuerst %s: block %.1f ms, bild %.1f ms" % [r[0], r[1], r[2]])
	var ueber := _rows.filter(func(r) -> bool: return float(r[2]) > 25.0).size()
	print("UM Bilder über 25 ms: %d von %d Schritten" % [ueber, _rows.size()])
