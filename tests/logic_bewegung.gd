extends Node
## Laufen im Zimmer wie in Source/HL2 (src/room/bewegung.gd) ohne Bildschirm: Reibung mit
## stopspeed, Beschleunigung bis genau zum Höchsttempo, wenig Luftkontrolle, Sprunghöhe, Wände
## (Gleiten), Stufen, Ducken, gleiches Ergebnis bei verschiedenem Takt; dazu die Ego-Kamera ohne
## Interpolation und die Figuren (Modelle mit Skelett, zwei Teile, Proportionen).
## Aufruf: godot --headless --path . res://tests/logic_bewegung.tscn

const Bew := preload("res://src/room/bewegung.gd")
const Zimmer := preload("res://src/room/zimmer.gd")
const FP := preload("res://src/room/figur/figur_psx.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const Avatar := preload("res://src/room/figur/avatar.gd")

const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _fn(src: String, kopf: String) -> String:
	var a := src.find(kopf)
	if a < 0:
		return ""
	var b := src.find("\nfunc ", a + 5)
	return src.substr(a, (b if b > 0 else src.length()) - a)


## Leeres Zimmer 6 × 5 m, dazu Möbel [[x0, z0, x1, z1, h], …].
func _welt(moebel: Array = []) -> Array:
	return Bew.welt_aus(6.0, 5.0, 2.7, moebel)


func _laufe(k: Dictionary, wunsch: Vector3, tempo: float, sek: float, welt: Array, dt := DT, springen := false, ducken := false) -> void:
	for i in int(round(sek / dt)):
		Bew.schritt(k, wunsch, tempo, springen, ducken, welt, dt)


func _flach(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _ready() -> void:
	var w := _welt()
	print("Reibung und Beschleunigung (Source)")
	var v := Bew.reibung(Vector3(2.0, 0, 0), 0.1)
	check(is_equal_approx(v.x, 2.0 - 2.0 * Bew.REIBUNG * 0.1), "Reibung über stopspeed: proportional (%.3f m/s)" % v.x)
	var langsam := Bew.reibung(Vector3(0.5, 0, 0), 0.05)
	check(is_equal_approx(langsam.x, 0.5 - Bew.STOPP * Bew.REIBUNG * 0.05), "unter stopspeed: feste Bremsrate (%.3f m/s)" % langsam.x)
	check(Bew.reibung(Vector3(0.05, 0, 0), 0.1).x == 0.0, "Reibung kehrt nie um, sie hält an")
	var a := Bew.beschleunigen(Vector3.ZERO, Vector3(1, 0, 0), Bew.GEHEN, Bew.BESCHL, DT)
	check(is_equal_approx(a.x, Bew.BESCHL * DT * Bew.GEHEN), "Beschleunigung: accel · dt · Wunschtempo")
	check(Bew.beschleunigen(Vector3(Bew.GEHEN, 0, 0), Vector3(1, 0, 0), Bew.GEHEN, Bew.BESCHL, DT).x == Bew.GEHEN, "am Ziel: nichts mehr dazu")
	var k := Bew.neu(Vector3(1, 0, 2.5))
	_laufe(k, Vector3(1, 0, 0), Bew.GEHEN, 0.25, w)
	var t25 := _flach(k.vel)
	_laufe(k, Vector3(1, 0, 0), Bew.GEHEN, 0.75, w)
	check(t25 > Bew.GEHEN * 0.85, "nach 0,25 s fast volles Tempo (%.2f von %.2f m/s) – knackig, nicht schwammig" % [t25, Bew.GEHEN])
	check(absf(_flach(k.vel) - Bew.GEHEN) < 0.002, "Höchsttempo genau erreicht, nicht überschritten (%.3f m/s)" % _flach(k.vel))
	var weg0: Vector3 = k.pos
	var halt := 0.0
	while _flach(k.vel) > 0.0 and halt < 2.0:
		Bew.schritt(k, Vector3.ZERO, Bew.GEHEN, false, false, w, DT)
		halt += DT
	var rutsch: float = (k.pos as Vector3).distance_to(weg0)
	check(halt < 0.45 and rutsch < 0.5, "loslassen: steht nach %.2f s, %.2f m (Reibung 4, stopspeed)" % [halt, rutsch])
	var kd := Bew.neu(Vector3(1, 0, 1))
	_laufe(kd, Vector3(1, 0, 1).normalized() * 1.4, Bew.GEHEN, 1.0, w)
	check(_flach(kd.vel) <= Bew.GEHEN + 0.002, "schräg nicht schneller (%.2f m/s)" % _flach(kd.vel))
	var kr := Bew.neu(Vector3(0.5, 0, 2.5))
	_laufe(kr, Vector3(1, 0, 0), Bew.RENNEN, 1.0, w)
	check(absf(_flach(kr.vel) - Bew.RENNEN) < 0.002, "Rennen: %.1f m/s (HL2-Sprint 320 u/s im Zimmer-Maßstab)" % _flach(kr.vel))
	check(Bew.GEHEN > 2.2 and Bew.GEHEN < 2.6 and Bew.RENNEN > 3.6 and Bew.RENNEN < 4.4, "Tempi im Zimmer: Gehen %.2f, Rennen %.2f m/s" % [Bew.GEHEN, Bew.RENNEN])
	var kh := Bew.neu(Vector3(1, 0, 2.5))
	_laufe(kh, Vector3(0.5, 0, 0), Bew.GEHEN, 1.0, w)
	check(absf(_flach(kh.vel) - Bew.GEHEN * 0.5) < 0.002, "halber Stick: halbes Tempo (analog)")

	print("Springen und Luft")
	var ks := Bew.neu(Vector3(3, 0, 2.5))
	var hoch := 0.0
	var luft := 0.0
	Bew.schritt(ks, Vector3.ZERO, Bew.GEHEN, true, false, w, 1.0 / 240.0)
	while not bool(ks.boden) and luft < 2.0:
		Bew.schritt(ks, Vector3.ZERO, Bew.GEHEN, true, false, w, 1.0 / 240.0)
		hoch = maxf(hoch, (ks.pos as Vector3).y)
		luft += 1.0 / 240.0
	check(absf(hoch - Bew.SPRUNG_HOEHE) < 0.02, "Sprung %.2f m hoch (HL2 21 u)" % hoch)
	check(absf(luft - 2.0 * Bew.SPRUNG / Bew.SCHWERE) < 0.03 and (ks.pos as Vector3).y < 0.01, "landet wieder (%.2f s in der Luft)" % luft)
	_laufe(ks, Vector3.ZERO, Bew.GEHEN, 0.3, w, DT, true)
	check((ks.pos as Vector3).y < 0.01 and bool(ks.boden), "gehaltene Taste: kein Dauerhüpfen")
	var kl := Bew.neu(Vector3(3, 0, 2.5))
	Bew.schritt(kl, Vector3.ZERO, Bew.GEHEN, true, false, w, DT)
	_laufe(kl, Vector3(1, 0, 0), Bew.GEHEN, 0.25, w)
	check(_flach(kl.vel) <= Bew.LUFT_MAX + 0.001 and _flach(kl.vel) > 0.0, "in der Luft kaum Steuern (%.2f m/s, höchstens 30 u/s)" % _flach(kl.vel))
	var kf := Bew.neu(Vector3(1, 0, 2.5))
	_laufe(kf, Vector3(1, 0, 0), Bew.GEHEN, 0.6, w)
	var vor: float = _flach(kf.vel)
	Bew.schritt(kf, Vector3.ZERO, Bew.GEHEN, true, false, w, DT)
	_laufe(kf, Vector3.ZERO, Bew.GEHEN, 0.2, w)
	check(absf(_flach(kf.vel) - vor) < 0.01, "im Sprung keine Bodenreibung: der Schwung bleibt")

	print("Wände, Möbel, Stufen")
	var kw := Bew.neu(Vector3(5.0, 0, 2.5))
	_laufe(kw, Vector3(1, 0, 0), Bew.GEHEN, 1.0, w)
	check(absf((kw.pos as Vector3).x - (6.0 - Bew.BREITE)) < 0.01, "an der Wand Schluss (x %.3f)" % (kw.pos as Vector3).x)
	var kg := Bew.neu(Vector3(5.0, 0, 1.0))
	_laufe(kg, Vector3(1, 0, 1).normalized(), Bew.GEHEN, 0.6, w)
	check((kg.pos as Vector3).z > 1.0 + 0.6 and absf((kg.vel as Vector3).x) < 0.001, "schräg an der Wand: gleitet entlang (z %.2f)" % (kg.pos as Vector3).z)
	var tisch := _welt([[2.0, 2.0, 3.0, 3.0, 0.42]])
	var kt := Bew.neu(Vector3(1.0, 0, 2.5))
	_laufe(kt, Vector3(1, 0, 0), Bew.GEHEN, 1.0, tisch)
	check(absf((kt.pos as Vector3).x - (2.0 - Bew.BREITE)) < 0.01 and (kt.pos as Vector3).y < 0.01, "Möbel höher als eine Stufe: davor Schluss")
	var stufe := _welt([[2.0, 2.0, 3.0, 3.0, 0.2]])
	var ku := Bew.neu(Vector3(1.0, 0, 2.5))
	_laufe(ku, Vector3(1, 0, 0), Bew.GEHEN, 0.75, stufe)
	check(absf((ku.pos as Vector3).y - 0.2) < 0.01 and (ku.pos as Vector3).x > 2.2, "niedrige Stufe (0,2 m): einfach hinauf (y %.2f)" % (ku.pos as Vector3).y)
	_laufe(ku, Vector3(1, 0, 0), Bew.GEHEN, 0.75, stufe)
	check((ku.pos as Vector3).y < 0.01 and bool(ku.boden), "und wieder hinab, ohne zu fallen")
	check(absf(Bew.STUFE - 18.0 * Bew.U) < 0.0001, "Stufenhöhe 18 u (%.2f m)" % Bew.STUFE)
	var kb := Bew.neu(Vector3(1.2, 0, 2.5))
	_laufe(kb, Vector3(1, 0, 0), Bew.GEHEN, 0.3, tisch)
	Bew.schritt(kb, Vector3(1, 0, 0), Bew.GEHEN, true, false, tisch, DT)
	_laufe(kb, Vector3(1, 0, 0), Bew.GEHEN, 0.8, tisch)
	check((kb.pos as Vector3).y < 0.01, "auf 0,42 m springt man nicht (Sprung 0,4 m)")

	print("Ducken")
	var kk := Bew.neu(Vector3(1, 0, 2.5))
	_laufe(kk, Vector3(1, 0, 0), Bew.GEHEN, 1.0, w, DT, false, true)
	check(absf(_flach(kk.vel) - Bew.GEHEN * Bew.DUCK_TEMPO) < 0.005 and is_equal_approx(float(kk.duck_t), 1.0), "geduckt ein Drittel Tempo")
	var dach := _welt()
	dach.append(AABB(Vector3(0.0, 1.3, 0.0), Vector3(6.0, 2.0, 5.0)))
	var kd2 := Bew.neu(Vector3(1, 0, 2.5))
	_laufe(kd2, Vector3.ZERO, Bew.GEHEN, 0.3, dach, DT, false, true)
	_laufe(kd2, Vector3.ZERO, Bew.GEHEN, 0.3, dach, DT, false, false)
	check(bool(kd2.duck), "unter niedriger Decke: geduckt bleiben")

	print("Takt")
	var k60 := Bew.neu(Vector3(1, 0, 2.5))
	var k144 := Bew.neu(Vector3(1, 0, 2.5))
	_laufe(k60, Vector3(1, 0, 0), Bew.GEHEN, 1.0, w, 1.0 / 60.0)
	_laufe(k144, Vector3(1, 0, 0), Bew.GEHEN, 1.0, w, 1.0 / 144.0)
	check((k60.pos as Vector3).distance_to(k144.pos) < 0.05, "60 und 144 Takte: fast gleicher Weg (%.3f m)" % (k60.pos as Vector3).distance_to(k144.pos))

	print("Ego-Kamera")
	var src := FileAccess.get_file_as_string("res://src/room/zimmer.gd")
	var mb := _fn(src, "func _maus_blick(")
	check(mb.contains("yaw -= r.x * k") and not mb.contains("lerp"), "Maus roh im Ereignis, ohne Interpolation")
	var lf := _fn(src, "func _laufen(")
	var ego := lf.substr(lf.find("\telse:"))
	check(ego.contains("yaw -= rs.x * DREH") and not ego.contains("lerp"), "Stick: Drehung direkt, keine Interpolation im Ego-Blick")
	check(not _fn(src, "func _physics_process(").contains("yaw ="), "Laufen im Physik-Takt dreht den Blick nie")
	check(absf(rad_to_deg(Zimmer.NEIGUNG) - 89.0) < 0.01 and mb.contains("NEIGUNG"), "Blick nach oben und unten bis 89°")
	check(is_equal_approx(Zimmer.KURVE_BLICK, 1.0) and Zimmer.TOTZONE_BLICK <= 0.12, "Stick linear, kleine Totzone")
	check(_fn(src, "func _darstellen(").contains("get_physics_interpolation_fraction"), "gezeigt zwischen zwei Physik-Takten (kein Ruckeln bei 144 Hz)")

	print("Figur")
	for e in (FD.PERSONEN if FP.vorhanden() else []):
		var md := FP.daten(str(e[0]))
		var hoehe: float = FP.HOEHE[str(e[2])]
		var netze: Array = md.netze
		var gut := netze.size() == 2 and (md.haut as Skin).get_bind_count() == (md.namen as Array).size() and md.textur is Texture2D
		var kr2: Vector3 = md.kopf_r
		var kopf_h := kr2.y * 2.0
		var km: Vector3 = md.kopf_mitte
		var hu := float(md.huefte) / hoehe
		var namen: Array = md.namen
		var knochen := true
		for kn: String in Avatar.KNOCHEN.values():
			knochen = knochen and namen.has(kn)
		check(gut and knochen and kopf_h > 0.14 and kopf_h < 0.26 and absf(km.x) < 0.01 and km.y > hoehe * 0.85 and km.y < hoehe and hu > 0.45 and hu < 0.62,
				"%s: Skelett (%d Knochen), zwei Teile, Textur, Kopf %.0f cm (Gelenk bis Scheitel), Hüfte auf %.0f %%"
				% [e[0], namen.size(), kopf_h * 100.0, hu * 100.0])
	var av := Avatar.new()
	add_child(av)
	av.bauen({})
	if not FP.vorhanden():
		# Build aus dem öffentlichen Quelltext (ohne die PSX-Modelle): leere Figur, die trotzdem bewegt werden kann.
		av.tempo = 2.4
		for i in 5:
			av.bild(DT)
		check(av.skelett == null and av.ebenen_alle().is_empty() and av.kopf_mitte().y > 1.0, "ohne Modelle: leere Figur, Kopfhöhe für die Kamera")
		av.queue_free()
		print("")
		print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
		get_tree().quit(1 if fails > 0 else 0)
		return
	var oben: MeshInstance3D = av.skelett.get_node("koerper_oben")
	var unten: MeshInstance3D = av.skelett.get_node("koerper_unten")
	check(oben.layers == Avatar.EBENE_KOERPER and unten.layers == Avatar.EBENE_BEINE and oben.material_override == unten.material_override,
			"Ich-Ansicht: Oberkörper ausblendbar, Beine bleiben; ein Material")
	var skala_ok := true
	for mi in av.ebenen_alle():
		var aabb: AABB = (mi as MeshInstance3D).get_aabb()
		if aabb.size.y > FP.HOEHE.m * 1.1 or aabb.position.y < -0.05:
			skala_ok = false
	check(skala_ok, "kein Teil ragt unter den Boden oder über die Größe hinaus")
	var fuss0 := av.skelett.get_bone_global_pose(av.skelett.find_bone("LeftFoot")).origin
	av.tempo = 2.4
	for i in 20:
		av.bild(DT)
	var fuss1 := av.skelett.get_bone_global_pose(av.skelett.find_bone("LeftFoot")).origin
	check(fuss0.distance_to(fuss1) > 0.05, "Gehen bewegt die Beine (Skelett)")
	av.queue_free()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
