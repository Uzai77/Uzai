extends Node
## Leistungsziele (Punkt 88): Rechenzeit in %, Ruckler im Menü, Zeilen und Kurzfassung für die
## Einstellungen. Aufruf: godot --headless --path . res://tests/logic_leistung.tscn

const Perf := preload("res://src/core/perf.gd")
const SettingsView := preload("res://src/ui/sections/settings_view.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Rechenzeit")
	check(is_equal_approx(Perf.cpu_percent(1000.0, 1600.0, 60000.0, 8), 0.125), "600 ms auf 8 Kernen in einer Minute: 0,125 %")
	check(is_equal_approx(Perf.cpu_percent(0.0, 4000.0, 1000.0, 4), 100.0), "alle Kerne voll: 100 %")
	check(Perf.cpu_percent(0.0, 10.0, 0.0, 4) < 0.0, "ohne verstrichene Zeit: unbekannt")
	print("Menü")
	var t := PackedFloat32Array()
	t.resize(200)
	t.fill(-1.0)
	check(int(Perf.frame_stats(t, 16.7).frames) == 0, "leer: nichts gemessen")
	for i in 100:
		t[i] = 16.7
	t[100] = 34.0
	t[101] = 50.0
	var s := Perf.frame_stats(t, 16.7)
	check(int(s.frames) == 102 and int(s.late) == 2, "zwei von 102 Bildern zu spät")
	check(is_equal_approx(float(s.late_pct), 200.0 / 102.0), "Anteil zu spät")
	check(is_equal_approx(float(s.p99_ms), 50.0) or is_equal_approx(float(s.p99_ms), 34.0), "langsamste 1 %")
	check(absf(float(s.fps) - 57.6) < 1.0, "Bilder je Sekunde aus der mittleren Bildzeit")
	var r120 := Perf.frame_stats(PackedFloat32Array([8.3, 8.4, 8.3, 16.7]), 8.33)
	check(int(r120.late) == 1, "120 Hz: ein ausgelassenes Bild zählt als zu spät")
	print("Einstellungen")
	var none := Perf.rows({})
	check(none.size() == 4 and none.all(func(r: Array) -> bool: return r[3] == null), "nichts gemessen: alles unbekannt")
	check(SettingsView.perf_summary(none) == "Wird gemessen", "Kurzfassung ohne Messung")
	var menu := Perf.frame_stats(t, 16.7)
	var good := Perf.rows(
			{ "start_ms": 2400, "mem_mb": 220.0, "mem_peak_mb": 260.0, "game_cpu": 0.3, "menu": { "frames": 500, "late_pct": 0.4, "p99_ms": 18.0, "fps": 60.0 } })
	check(good.all(func(r: Array) -> bool: return r[3] == true), "alles im Ziel")
	check(SettingsView.perf_summary(good) == "Im Ziel", "Kurzfassung im Ziel")
	check(str(good[0][1]) == "2,4 s" and str(good[1][1]) == "220 MB" and str(good[2][1]) == "0,3 %", "Werte lesbar")
	var bad := Perf.rows({ "start_ms": 4100, "mem_mb": 380.0, "game_cpu": 0.2, "menu": menu })
	check(bad[0][3] == false and bad[1][3] == false and bad[2][3] == true, "Start und Speicher über dem Ziel")
	check(bad[3][3] == null, "zu wenige Bilder fürs Menü: noch kein Urteil")
	check(SettingsView.perf_summary(bad) == "Start und mehr über dem Ziel", "Kurzfassung nennt das Erste")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
