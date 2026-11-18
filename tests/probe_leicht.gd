extends "res://tests/probe_base.gd"
## Probe „Leichter Modus“ (Demo): Bildzeiten der Startseite und des Guides ohne Bildratengrenze,
## erst normal, dann leicht – mit Software-Grafik (xvfb, Mesa llvmpipe) ein guter Stellvertreter
## für einen schwachen PC. Dazu Bilder zum Vergleich, die Zeile in den Einstellungen, der
## Vorschlag und die Seite „Leistung“.

const Leicht := preload("res://src/core/leicht.gd")

var _t: Array = []
var _rec := false
var _prev := 0


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _rec and _prev > 0:
		_t.append((now - _prev) / 1000.0)
	_prev = now


## Bildzeit (ms) über secs Sekunden: der Median – weniger anfällig für andere Last auf dem Rechner
## als der Mittelwert; das schnellste Zehntel steht daneben.
func measure(name: String, secs := 4.0) -> float:
	await wait(1.0)
	_t.clear()
	_prev = 0
	_rec = true
	await wait(secs)
	_rec = false
	var v := _t.duplicate()
	v.sort()
	if v.is_empty():
		return 0.0
	var med: float = v[v.size() / 2]
	print("MESS %-22s Median %6.1f ms, schnellstes Zehntel %6.1f ms  (%d Bilder)" % [name, med, v[v.size() / 10], v.size()])
	return med


func _set_light(v: String) -> void:
	Config.set_value("display.light", v)
	await wait(2.0)
	main.goto("games")
	await wait(1.5)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.5)
	# Abwechselnd messen (aus, an, aus, an): Andere Last auf dem Rechner trifft beide gleich.
	var sum := { "aus_start": 0.0, "an_start": 0.0, "aus_guide": 0.0, "an_guide": 0.0 }
	for round in 2:
		for mode in ["aus", "an"]:
			await _set_light(mode)
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			sum[mode + "_start"] += await measure("Startseite " + mode) / 2.0
			if round == 0:
				await shot("%s_startseite" % mode, 0.2)
			main.toggle_guide()
			await wait(1.2)
			sum[mode + "_guide"] += await measure("Guide " + mode) / 2.0
			if round == 0:
				await shot("%s_guide" % mode, 0.2)
			main.toggle_guide()
			await wait(1.0)
	print("ERGEBNIS Startseite %.1f → %.1f ms, Guide %.1f → %.1f ms" % [sum.aus_start, sum.an_start, sum.aus_guide, sum.an_guide])
	# Bildrate im Menü (main._menu_fps): leicht höchstens 60; ruht das Menü 20 s, höchstens 30,
	# und die nächste Taste holt die volle Rate zurück.
	main.set_idle(false)
	var awake := Engine.max_fps
	await wait(float(Leicht.IDLE_MS) / 1000.0 + 2.0)
	var resting := Engine.max_fps
	press("right")
	await wait(0.3)
	print("Menü-Bildrate leicht: %d (0 = wie der Bildschirm), ruhend %d, nach Tastendruck %d, ruht: %s" % [awake, resting, Engine.max_fps, str(Leicht.idle)])
	press("left")
	# Weitere Bereiche im leichten Modus: Kacheln mit eckigem Zuschnitt.
	for sid in ["shop", "videos", "music"]:
		main.goto(sid)
		await shot("an_" + sid, 2.5)
	main.goto("games")
	await wait(1.0)
	main.open_setting("aussehen", "set:aussehen:Mehr:Leichter Modus", "Mehr")
	await shot("einstellung", 1.5)
	main.goto("games")
	await wait(1.0)
	main.suggest_light(["ruckelt"], { "late_pct": 14.0 })
	await shot("vorschlag", 0.8)
	print("gefragt: %s" % str(Config.get_value("display.light_asked")))
	main.open_setting("system", "", "Leistung")
	await shot("leistung", 1.5)
