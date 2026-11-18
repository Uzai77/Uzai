extends "res://tests/probe_base.gd"
## Probe „Dein Zimmer“ (Punkt 131, Stufe 1, Demo): Übersicht, Ich-Ansicht, Regal mit Spielen,
## Trophäenschrank, Plattenregal, Fernseher in allen drei Arten, Bau-Modus mit Katalog und
## Möbel setzen, Licht am Morgen, Tag, Abend und in der Nacht, Spiel einlegen, die Kachel auf der
## Startseite und die Einstellung. Dazu Bildzeiten (Median) normal und im leichten Modus –
## mit Software-Grafik (xvfb, llvmpipe) nur als Vergleich, nicht als echte Bildrate.
##
## Aufruf: A2_PROJ=<projekt> A2_TIMEOUT=600 bash a2_run.sh res://tests/probe_zimmer.gd zimmer

const Leicht := preload("res://src/core/leicht.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")

var z: Control
var _t: Array = []
var _rec := false
var _prev := 0


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _rec and _prev > 0:
		_t.append((now - _prev) / 1000.0)
	_prev = now


func messen(name: String, secs := 4.0) -> float:
	await wait(0.6)
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
	print("MESS %-28s Median %6.1f ms, schnellstes Zehntel %6.1f ms (%d Bilder)" % [name, med, v[v.size() / 10], v.size()])
	return med


## Kamera sofort an ihr Ziel (statt die Fahrt abzuwarten – Software-Grafik ist langsam).
func ziel() -> void:
	var soll: Array = z._kamera_soll()
	z.welt.kamera.transform = soll[0]
	z.welt.kamera.fov = float(soll[1])
	z._rate = 40.0


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


func vor(t: String, abstand: float, hoehe := 1.62, seitlich := 0.0) -> void:
	var i := idx(t)
	var n: Node3D = z.welt.knoten[i]
	var vorn := n.transform.basis.z.normalized()
	var rechts := n.transform.basis.x.normalized()
	var mitte: Vector3 = (z.welt.boxen[i] as AABB).get_center()
	z.pos = Vector3(mitte.x, 0, mitte.z) + vorn * abstand + rechts * seitlich
	var dir := mitte - Vector3(z.pos.x, hoehe, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())


func zeit(t: String) -> void:
	z.raum.licht["z"] = t
	z._licht_neu()


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.5)
	# Startseite: Kachel „Dein Zimmer“ am Ende von „Zuletzt“.
	var s = main.sections["games"]
	var shelf = s.get("_shelf")
	if shelf:
		var items: Array = shelf.items()
		Nav.focus(items[items.size() - 1])
		await wait(1.2)
		await shot("16_startseite_kachel", 0.6)
	main.goto("games")
	await wait(0.8)
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()
	print("Zimmer offen: ", z != null and z.has_method("bauen_an"))
	zeit("abend")
	# Übersicht von oben.
	z.blick = "oben"
	z._oben_az = 0.62
	z._oben_az_soll = 0.62
	ziel()
	await shot("01_uebersicht_abend", 2.0)
	# Ich-Ansicht mit Blick auf Fernseher und Sofa.
	z.blick = "ich"
	z.pos = Vector3(5.0, 0, 4.35)
	z.yaw = 0.42
	z._yaw_soll = 0.42
	z.pitch = -0.1
	ziel()
	await wait(0.6)
	z._ziel = -2
	z._ziel_suchen()
	ziel()
	await shot("02_ich_abend", 1.5)
	# Regal mit Spielen: davor stellen, A drückt „Spiel aussuchen“.
	vor("spieleregal", 1.3, 1.5)
	ziel()
	await wait(0.5)
	z._ziel = -2
	z._ziel_suchen()
	await shot("03_vor_regal", 1.0)
	z._ansehen(idx("spieleregal"))
	ziel()
	await wait(0.8)
	ziel()
	await shot("04_regal_spiele", 1.2)
	await press("right", 3, 0.25)
	ziel()
	await wait(1.0)
	ziel()
	await shot("05_regal_gewaehlt", 0.8)
	await press("b")
	# Trophäenschrank.
	z._ansehen(idx("trophaeenschrank"))
	ziel()
	await wait(1.0)
	ziel()
	await shot("06_pokale", 1.2)
	await press("down")
	ziel()
	await wait(0.9)
	ziel()
	await shot("07_pokal_gewaehlt", 0.8)
	await press("b")
	# Plattenregal.
	z._ansehen(idx("plattenregal"))
	ziel()
	await wait(1.0)
	ziel()
	await shot("08_platten", 1.2)
	await press("right")
	ziel()
	await wait(0.9)
	await press("a")
	await wait(1.4)
	ziel()
	await shot("09_platte_aufgelegt", 0.6)
	await press("b")
	# Fernseher in allen drei Arten.
	var tv := idx("medienwand")
	for art in ["flach", "roehre", "beamer"]:
		z._variante_setzen(tv, art, false)
		await wait(0.6)
		vor("medienwand", 2.1 if art != "beamer" else 2.3, 1.25)
		z.pitch += 0.12 if art == "beamer" else 0.0
		ziel()
		await shot("10_fernseher_" + art, 1.4)
	z._variante_setzen(tv, "flach", false)
	await wait(0.4)
	# Bau-Modus: Raster, Katalog, Möbel setzen.
	z.pos = Vector3(4.2, 0, 3.6)
	await press("view")
	z._oben_az_soll = 0.62
	z._oben_az = 0.62
	z.cursor = Vector2i(9, 6)
	z._raster_auffrischen()
	ziel()
	await shot("11_bau_modus", 1.5)
	await press("a")
	await wait(0.4)
	z._katalog.call("bereich", "regale")
	await wait(4.0)
	ziel()
	await shot("12_katalog", 1.0)
	z._katalog.call("bereich", "sitzen")
	await wait(2.5)
	await press("right")
	await wait(0.5)
	await shot("13_katalog_sitzen", 0.6)
	await press("a")
	await wait(0.8)
	ziel()
	await shot("14_moebel_tragen", 1.0)
	await press("left", 2, 0.25)
	await wait(0.6)
	await shot("15_moebel_blockiert", 0.8)
	await press("right", 2, 0.25)
	await press("lb")
	await wait(0.6)
	await shot("15_moebel_gedreht", 0.8)
	print("Getragen passt: ", Daten.passt(z.raum, z._halten, z._halten_idx))
	await press("a")
	await wait(1.0)
	ziel()
	await shot("16_moebel_gesetzt", 0.8)
	print("Möbel nach dem Setzen: %d" % (z.raum.moebel as Array).size())
	await press("x")
	await wait(1.0)
	print("Möbel nach Rückgängig: %d" % (z.raum.moebel as Array).size())
	await shot("17_rueckgaengig", 0.8)
	while z.modus != "laufen":
		await press("b")
		await wait(0.4)
	# Licht: Morgen, Tag, Nacht (Abend ist oben).
	z.blick = "ich"
	z.pos = Vector3(5.0, 0, 4.35)
	z.yaw = 0.42
	z._yaw_soll = 0.42
	z.pitch = -0.1
	for t in ["morgen", "tag", "nacht"]:
		zeit(t)
		ziel()
		await shot("18_licht_" + t, 1.4)
	z.blick = "oben"
	ziel()
	await shot("19_uebersicht_nacht", 1.4)
	zeit("tag")
	ziel()
	await shot("20_uebersicht_tag", 1.4)
	# Einrichten von oben mit anderer Wand und anderem Boden.
	z.wand_werte("", { "m": "anstrich", "f": "#a9b49b" })
	z.raum_werte("boden", { "a": "dielen", "f": "#5d4030", "f2": "" })
	zeit("abend")
	ziel()
	await shot("21_salbei_walnuss", 1.4)
	z.rueckgaengig()
	z.rueckgaengig()
	await wait(0.6)
	# Leistung: Ich-Ansicht und von oben, normal und leicht (ohne Bildratengrenze).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	z.blick = "ich"
	ziel()
	var n_ich := await messen("Zimmer Ich-Ansicht normal")
	z.blick = "oben"
	ziel()
	var n_oben := await messen("Zimmer von oben normal")
	z.close()
	await wait(1.0)
	main.goto("games")
	var n_start := await messen("Startseite 2D (Vergleich)")
	Config.set_value("display.light", "an")
	Leicht.refresh()
	await wait(0.6)
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()
	z.blick = "ich"
	ziel()
	await shot("22_leicht_ich", 1.0)
	var l_ich := await messen("Zimmer Ich-Ansicht leicht")
	z.blick = "oben"
	ziel()
	var l_oben := await messen("Zimmer von oben leicht")
	print("ERGEBNIS Zimmer ich %.1f → leicht %.1f ms, oben %.1f → %.1f ms, Startseite 2D %.1f ms" % [n_ich, l_ich, n_oben, l_oben, n_start])
	Config.set_value("display.light", "aus")
	Leicht.refresh()
	z.blick = "ich"
	z._ans = -1
	# Spiel einlegen: Fahrt aus dem Regal über die Konsole in den Fernseher (Start abgefangen).
	z.close()
	await wait(0.8)
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()
	zeit("abend")
	vor("spieleregal", 1.3, 1.5)
	z._ansehen(idx("spieleregal"))
	ziel()
	await wait(1.0)
	var platz: Dictionary = z._platz()
	Launcher.set("in_game", false)
	var g: Dictionary = platz.daten
	print("Einlegen: ", Library.display_title(g))
	z.call("_einlegen", platz)
	await shot("23_einlegen_hinueber", 0.55)
	await shot("24_einlegen_konsole", 0.55)
	await shot("25_in_den_fernseher", 0.9)
	await wait(3.0)
	print("Nach dem Einlegen: Zimmer zu %s, Spiel läuft %s" % [not is_instance_valid(z) or not z.is_inside_tree(), str(Launcher.in_game)])
	# Einstellung „Art der Startseite“.
	main.open_setting("system", "set:system:Art der Startseite")
	await shot("26_einstellung", 1.5)
