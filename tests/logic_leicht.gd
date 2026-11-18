extends Node
## Leichter Modus (Punkt 65): Bildrate, Erkennung schwacher PCs, einmal vorschlagen und was der
## Modus an den Bauteilen ändert. Aufruf: godot --headless --path . res://tests/logic_leicht.tscn

const Leicht := preload("res://src/core/leicht.gd")
const Perf := preload("res://src/core/perf.gd")
const U := preload("res://src/ui/u.gd")
const BG := preload("res://src/ui/components/background.gd")
const GlasWerte := preload("res://tests/glas_werte.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Bildrate")
	check(Leicht.menu_fps(60.0) == 0 and Leicht.menu_fps(50.0) == 0, "60 Hz und weniger: keine Grenze")
	check(Leicht.menu_fps(120.0) == 60 and Leicht.menu_fps(240.0) == 60, "120/240 Hz: 60, jedes Bild gleich lange")
	check(Leicht.menu_fps(144.0) == 48 and Leicht.menu_fps(165.0) == 55, "144 Hz: 48 (drei Wechsel je Bild), 165 Hz: 55")
	check(Leicht.menu_fps(NAN) == 0 and Leicht.menu_fps(-1.0) == 0, "unbekannte Rate: wie 60 Hz")
	check(Leicht.idle_fps(60.0) == 30 and Leicht.idle_fps(120.0) == 30, "ruhend: 30 bei 60 und 120 Hz")
	check(Leicht.idle_fps(NAN) == 30, "ruhend ohne bekannte Rate: 30")
	for hz in [100.0, 120.0, 144.0, 165.0, 240.0]:
		var f := Leicht.menu_fps(hz)
		check(f > 0 and f <= Leicht.MENU_FPS_MAX and absf(hz / f - roundf(hz / f)) < 0.05, "%d Hz: %d Bilder/s, jedes Bild gleich viele Wechsel" % [hz, f])

	print("Erkennung")
	var good := { "frames": 4000, "late_pct": 0.5 }
	var jerky := { "frames": 4000, "late_pct": 14.0 }
	var slight := { "frames": 4000, "late_pct": 4.0 }
	var short := { "frames": 600, "late_pct": 30.0 }
	var fast_pc := { "adapter": "NVIDIA GeForce RTX 3060", "cores": 12, "ram_mb": 16384 }
	var igpu := { "adapter": "Intel(R) UHD Graphics 620", "cores": 8, "ram_mb": 8192 }
	var old := { "adapter": "Intel(R) HD Graphics 4000", "cores": 2, "ram_mb": 4096 }
	check(Leicht.reasons({ "adapter": "llvmpipe (LLVM 20.1.2, 256 bits)", "cores": 8 }, {}) == ["software"], "Software-Grafik (Mesa) sofort erkannt")
	check(Leicht.reasons({ "adapter": "Microsoft Basic Render Driver" }, {}) == ["software"], "Windows ohne Grafiktreiber erkannt")
	check(Leicht.reasons(fast_pc, good).is_empty() and Leicht.reasons(igpu, good).is_empty(), "flüssiges Menü: kein Grund, auch nicht mit integrierter Grafik")
	check(Leicht.reasons(fast_pc, short).is_empty(), "zu wenig gemessen: noch kein Urteil")
	check(Leicht.reasons(igpu, jerky) == ["ruckelt"], "deutlich ruckelndes Menü: Grund")
	check(Leicht.reasons(igpu, slight).is_empty(), "leichtes Ruckeln mit guter Ausstattung: kein Grund")
	check(Leicht.reasons(old, slight) == ["schwach"], "leichtes Ruckeln mit 2 Kernen und 4 GB: Grund")
	var dev := Leicht.device()
	check(dev.has("adapter") and int(dev.cores) >= 1, "Gerätedaten lesbar (%s, %d Kerne, %d MB)" % [str(dev.adapter), int(dev.cores), int(dev.ram_mb)])

	print("Vorschlag")
	check(Leicht.should_suggest("auto", false, ["ruckelt"]), "Automatisch, noch nie gefragt, mit Grund: vorschlagen")
	check(not Leicht.should_suggest("auto", true, ["ruckelt"]), "schon einmal gefragt: nie wieder")
	check(not Leicht.should_suggest("aus", false, ["software"]) and not Leicht.should_suggest("an", false, ["software"]), "Aus oder schon an: nichts vorschlagen")
	check(not Leicht.should_suggest("auto", false, []), "ohne Grund: nichts")
	check(Leicht.reason_text(["software"], {}).contains("Software-Grafik"), "Grund in Worten: Software-Grafik")
	check(Leicht.reason_text(["ruckelt"], { "late_pct": 14.0 }) == "Das Menü ruckelt hier: 14 % der Bilder kamen zu spät.", "Grund in Worten: Ruckeln mit Anteil")
	check(str(Config.get_value("display.light")) == "auto" and Config.get_value("display.light_asked") == false, "Standard: Automatisch, noch nicht gefragt")

	print("Was der Modus ändert")
	# Geprüft mit den Werten des früheren Glas-Aussehens (runde Ecken, Glimmen, volle Schatten):
	# das eckige, flache Graphit der Marke hätte nichts zum Halbieren.
	UzTheme.grund = GlasWerte.werte()
	Config.set_value("display.light", "an")
	UzTheme.apply()
	check(Leicht.active, "an: aktiv (über das Theme gelesen)")
	check(UzTheme.r_cover() <= Leicht.COVER_RADIUS, "Cover-Ecken schlicht (%d px)" % UzTheme.r_cover())
	var sb := UzTheme.lift(StyleBoxFlat.new(), 3)
	check(sb.shadow_size == int(round(56 * Leicht.SHADOW_K)), "Schatten halb so weit (%d px)" % sb.shadow_size)
	check(UzTheme.with_glow(StyleBoxFlat.new()).shadow_size == int(round(18 * Leicht.SHADOW_K)), "Glimmen halb so weit")
	check(BG.blur_taps() == Leicht.BLUR_TAPS, "Weichzeichner mit %d Proben" % Leicht.BLUR_TAPS)
	var p := Panel.new()
	U.clip_round(p)
	check(p.clip_contents and p.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED, "Cover schneiden eckig zu, ohne eigenen Puffer")
	p.free()
	check(Media.px_scale() <= 1.0, "Bilder in der Größe für 1080p")
	var fl := PanelContainer.new()
	check(UzTheme.kernlicht(fl) == null and fl.material == null, "Flächen ohne Material „Kernlicht“ (schlicht)")
	fl.free()
	var tw := U.tw(self)
	check(tw.is_valid(), "Animationen laufen weiter (nur kürzer)")
	tw.kill()
	var perf := Perf.new()
	add_child(perf)
	perf.start_ms = 1
	Leicht.idle = true
	check(not perf._counting(), "ruhendes Menü zählt nicht als Ruckeln")
	Leicht.idle = false
	perf._ft[0] = 50.0
	perf.reset_frames()
	check(int(perf.menu_stats().frames) == 0, "nach dem Umschalten misst Uzai neu")
	var rows := Perf.rows({ "light": "an" })
	check(rows.size() == 5 and str(rows[4][0]) == "Leichter Modus" and str(rows[4][1]) == "An", "Seite Leistung zeigt den Modus")
	perf.queue_free()

	Config.set_value("display.light", "aus")
	UzTheme.apply()
	check(not Leicht.active, "aus: nicht aktiv")
	check(UzTheme.r_cover() > Leicht.COVER_RADIUS and BG.blur_taps() == 12, "aus: Ecken und Weichzeichner wie immer")
	var p2 := Panel.new()
	U.clip_round(p2, CanvasItem.CLIP_CHILDREN_AND_DRAW)
	check(p2.clip_children == CanvasItem.CLIP_CHILDREN_AND_DRAW and not p2.clip_contents, "aus: runder Zuschnitt wie immer")
	var fl2 := PanelContainer.new()
	var km := UzTheme.kernlicht(fl2)
	check(km != null and fl2.material == km and km.shader == UzTheme.KERNLICHT, "aus: Flächen im Material „Kernlicht“")
	fl2.free()
	p2.free()
	Config.set_value("display.light", "auto")
	UzTheme.grund = GlasWerte.Aussehen.werte()
	UzTheme.apply()
	check(not Leicht.active, "Automatisch schaltet nie still um")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
