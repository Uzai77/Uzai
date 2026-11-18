extends "res://tests/probe_base.gd"
## Probe „Grafik und Licht im Zimmer“: dieselben Ansichten wie tests/probe_zimmer.gd (Übersicht,
## Ich-Ansicht, Regal, Pokale, Platten, Fernseher, Morgen/Tag/Abend/Nacht), dazu jede
## Qualitätsstufe (Hoch, Mittel, Leicht) mit Bildzeit und Zeichenaufrufen.
##
## --stand=vorher  läuft auch auf dem alten Stand (normal und leicht über den leichten Modus);
## --stand=nachher legt zusätzlich je Ansicht ein Vergleichsbild an (links vorher, rechts nachher),
## wenn im selben Ordner schon die Vorher-Bilder liegen.
## --schnell nur die wichtigsten Ansichten, --messen nur Bildzeiten je Stufe, --profil die Effekte der
## Stufe Hoch einzeln abschalten und messen, --vorlagen „Neon-Höhle“ und „Kino-Ecke“ in Hoch und Leicht.
## Bildzeiten mit Software-Grafik (xvfb, llvmpipe) taugen nur als Vergleich untereinander – und nur
## bei gleicher Last des Rechners (vorher und nachher direkt nacheinander messen).
##
## Aufruf: A2_PROJ=<projekt> A2_TIMEOUT=1500 bash a2_run.sh res://tests/probe_zgrafik.gd zgrafik --stand=nachher

const Leicht := preload("res://src/core/leicht.gd")

var z: Control
var stand := "nachher"
var schnell := false          ## --schnell: nur die wichtigsten Ansichten (zum Abstimmen)
var nur_messen := false       ## --messen: nur die Bildzeiten je Stufe (ohne Bilder)
var profil := false           ## --profil: Stufe Hoch, Effekte nacheinander abschalten und messen
var vorlagen := false         ## --vorlagen: Vorlagen „Neon-Höhle“ und „Kino-Ecke“ in Hoch und Leicht
var _t: Array = []
var _rec := false
var _prev := 0
var _bilder: Array = []


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _rec and _prev > 0:
		_t.append((now - _prev) / 1000.0)
	_prev = now


func messen(name: String, secs := 6.0) -> String:
	await wait(0.8)
	_t.clear()
	_prev = 0
	_rec = true
	await wait(secs)
	_rec = false
	var v := _t.duplicate()
	v.sort()
	if v.is_empty():
		return ""
	var med: float = v[v.size() / 2]
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var ob := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var pr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var zeile := "MESS %-7s %-26s Median %7.1f ms, schnellstes Zehntel %7.1f ms (%d Bilder), %d Zeichenaufrufe, %d Objekte, %d Dreiecke" % [stand, name, med,
			v[v.size() / 10], v.size(), dc, ob, pr]
	print(zeile)
	return zeile


func bild(name: String, wait_s := 1.4) -> void:
	await shot(stand + "_" + name, wait_s)
	_bilder.append(name)


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
	if z.raum.get("licht") is Dictionary:
		z.raum.licht.z = t
		z._licht_neu(false)
	else:
		z.raum.licht = t
		z._licht_neu()


func ich() -> void:
	z.blick = "ich"
	z.pos = Vector3(5.0, 0, 4.35)
	z.yaw = 0.42
	z._yaw_soll = 0.42
	z.pitch = -0.1
	ziel()


func oben() -> void:
	z.blick = "oben"
	z._oben_az = 0.62
	z._oben_az_soll = 0.62
	ziel()


func oeffnen() -> void:
	main.goto("games")
	await wait(0.8)
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()


func schliessen() -> void:
	z.close()
	await wait(1.0)


## Qualitätsstufe: neu über zimmer.grafik_setzen, alt über den leichten Modus (neu öffnen).
func stufe(s: String) -> void:
	if z.has_method("grafik_setzen"):
		z.grafik_setzen(s)
		await wait(1.0)
		return
	Config.set_value("display.light", "an" if s == "leicht" else "aus")
	Leicht.refresh()
	await schliessen()
	await oeffnen()


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stand="):
			stand = a.substr(8)
		if a == "--schnell":
			schnell = true
		if a == "--messen":
			nur_messen = true
		if a == "--profil":
			profil = true
		if a == "--vorlagen":
			vorlagen = true
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("display.light", "aus")
	Leicht.refresh()
	await oeffnen()
	print("Zimmer offen: ", z != null and z.has_method("bauen_an"))
	var stufen := ["hoch", "mittel", "leicht"] if z.has_method("grafik_setzen") else ["normal", "leicht"]
	if z.has_method("grafik_setzen"):
		z.grafik_setzen("hoch")
		await wait(1.0)
	if nur_messen:
		await _stufen_messen(stufen, false)
		return
	if profil:
		await _profil()
		return
	if vorlagen and not schnell:
		await _vorlagen()
		return
	zeit("abend")
	oben()
	await bild("01_uebersicht_abend", 2.0)
	ich()
	await bild("02_ich_abend")
	if schnell:
		z._ansehen(idx("trophaeenschrank"))
		ziel()
		await wait(1.0)
		ziel()
		await bild("06_pokale")
		await press("b")
		for t in ["morgen", "tag", "nacht"]:
			zeit(t)
			ich()
			await bild("18_licht_" + t)
		oben()
		await bild("19_uebersicht_nacht")
		zeit("tag")
		oben()
		await bild("20_uebersicht_tag")
		if stand == "nachher":
			_vergleiche()
		if vorlagen:
			await _vorlagen()
		return
	vor("spieleregal", 1.3, 1.5)
	z._ansehen(idx("spieleregal"))
	ziel()
	await wait(0.8)
	ziel()
	await bild("04_regal_spiele")
	await press("b")
	z._ansehen(idx("trophaeenschrank"))
	ziel()
	await wait(1.0)
	ziel()
	await bild("06_pokale")
	await press("b")
	z._ansehen(idx("plattenregal"))
	ziel()
	await wait(1.0)
	ziel()
	await bild("08_platten")
	await press("b")
	vor("medienwand", 2.1, 1.25)
	ziel()
	await bild("10_fernseher_flach")
	for t in ["morgen", "tag", "nacht"]:
		zeit(t)
		ich()
		await bild("18_licht_" + t)
	oben()
	await bild("19_uebersicht_nacht")
	zeit("tag")
	oben()
	await bild("20_uebersicht_tag")
	await _stufen_messen(stufen, true)
	if stand == "nachher":
		_vergleiche()


## Jede Stufe: Bilder (mit_bildern) und Bildzeiten, ohne Bildratengrenze.
func _stufen_messen(stufen: Array, mit_bildern: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var zeilen: Array = []
	for s in stufen:
		await stufe(s)
		zeit("abend")
		ich()
		if mit_bildern:
			await bild("30_stufe_%s_ich_abend" % s)
		zeilen.append(await messen("%s Ich-Ansicht" % s))
		oben()
		if mit_bildern:
			await bild("31_stufe_%s_oben_abend" % s)
		zeilen.append(await messen("%s von oben" % s))
		if mit_bildern:
			zeit("nacht")
			ich()
			await bild("32_stufe_%s_ich_nacht" % s)
	for l in zeilen:
		print("ERGEBNIS ", l)
	Config.set_value("display.light", "aus")
	Leicht.refresh()


## Je Ansicht ein Bild: links vorher, rechts nachher (halbe Größe).
func _vergleiche() -> void:
	for name in _bilder:
		var a := out.path_join("vorher_" + name + ".png")
		var b := out.path_join("nachher_" + name + ".png")
		if name.begins_with("3") or not FileAccess.file_exists(a) or not FileAccess.file_exists(b):
			continue
		var ia := Image.load_from_file(a)
		var ib := Image.load_from_file(b)
		if ia == null or ib == null:
			continue
		ia.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		ib.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		var v := Image.create(1924, 540, false, Image.FORMAT_RGB8)
		v.fill(Color(0.9, 0.76, 0.49))
		v.blit_rect(_rgb(ia), Rect2i(0, 0, 960, 540), Vector2i(0, 0))
		v.blit_rect(_rgb(ib), Rect2i(0, 0, 960, 540), Vector2i(964, 0))
		v.save_png(out.path_join("vergleich_" + name + ".png"))
		print("Vergleich: ", name)


func _rgb(i: Image) -> Image:
	var c := i.duplicate() as Image
	if c.get_format() != Image.FORMAT_RGB8:
		c.convert(Image.FORMAT_RGB8)
	return c


## Was kostet was? Stufe Hoch, Abend, Ich-Ansicht; die Effekte nacheinander (kumulativ) aus.
func _profil() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	zeit("abend")
	ich()
	var w = z.welt
	var h = w.huelle
	await messen("alles (hoch)", 2.5)
	h._strahl.visible = false
	await messen("ohne Lichtstrahl", 2.5)
	var stapel: Array = [w]
	while not stapel.is_empty():
		var n: Node = stapel.pop_back()
		for c in n.get_children():
			stapel.append(c)
			if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial \
					and ((c as MeshInstance3D).material_override as ShaderMaterial).shader == preload("res://src/room/shaders/schein.gdshader"):
				(c as MeshInstance3D).visible = false
	await messen("ohne Lichtscheine", 2.5)
	for m in h.huellen_mats + w._teppich_mats:
		m.set_shader_parameter("lampen_n", 0)
	await messen("ohne Hüllenlicht", 2.5)
	h.env.glow_enabled = false
	await messen("ohne Glühen", 2.5)
	h.env.adjustment_enabled = false
	await messen("ohne Farbkorrektur", 2.5)
	w._vignette.visible = false
	await messen("ohne Vignette", 2.5)
	for c in w.kamera.get_children():
		if c is MeshInstance3D:
			c.visible = false
	await messen("ohne Nachbearbeitung", 2.5)
	z.vp.msaa_3d = Viewport.MSAA_DISABLED
	await messen("ohne MSAA", 2.5)
	h.sonne.shadow_enabled = false
	await messen("ohne Sonnenschatten", 2.5)


## Vorlagen der Anpassung in der neuen Lichtqualität: von oben und in der Ich-Ansicht, Hoch und Leicht.
func _vorlagen() -> void:
	for st in ["hoch", "leicht"]:
		z.grafik_setzen(st)
		await wait(1.0)
		for id in ["retro", "loft"]:
			z.vorlage_uebernehmen(id)
			z._licht_neu(false)
			await wait(0.5)
			oben()
			await bild("40_vorlage_%s_%s_oben" % [id, st], 1.6)
			z.blick = "ich"
			z.pos = z._frei(Vector3(float(z.raum.w) * 0.42, 0, float(z.raum.d) * 0.4))
			var tv := idx("medienwand")
			var ziel_p: Vector3 = (z.welt.boxen[tv] as AABB).get_center() if tv >= 0 else Vector3(float(z.raum.w) * 0.25, 1.2, 0.0)
			var dir := ziel_p - Vector3(z.pos.x, 1.62, z.pos.z)
			z.yaw = atan2(-dir.x, -dir.z) + 0.35
			z._yaw_soll = z.yaw
			z.pitch = -0.08
			ziel()
			await bild("41_vorlage_%s_%s_ich" % [id, st], 1.6)
