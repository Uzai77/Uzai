extends "res://tests/probe_base.gd"
## Probe „Bild im Zimmer“: Ruhe, Schärfe und Helligkeit des 3D-Zimmers und das Spielbild im Fernseher.
## Je Tageszeit (Nacht, Tag): Blick auf Tür und Wand, Nahansicht, Boden, Ich-Ansicht. Dazu zwei Bilder
## direkt nacheinander bei stillstehender Kamera (Unterschied verstärkt als Bild, Mittelwert im Log:
## was sich ohne Bewegung ändert, flackert). Am Ende der Fernseher mit Spielbild (sitzend und
## stehend, mit Blick darauf): Ausschnitt neben dem Original und die mittlere Abweichung.
##
## Argumente: --stand=vorher|nachher (Präfix der Bilder), --stufe=hoch|mittel|leicht|ultra,
## --nur-groesse (nur Größen der 3D-Ansicht und ein Bild, z. B. für 3840 × 2160), --zeiten (nur die vier
## Tageszeiten in der Ich-Ansicht und vor der Tür, mit mittlerer Helligkeit – zum Abstimmen der Belichtung),
## --leistung[=ultra,hoch,…] (je Stufe: Einstellungen der 3D-Ansicht, Lichter mit Schatten, Effekte, Zeichenaufrufe,
## Objekte und Primitive der Ansicht und ihrer Schatten, Bildrate und wie oft die 3D-Ansicht in Ruhe und in
## Bewegung neu gezeichnet wird; Zeiten der Grafikkarte nur als Vergleich – xvfb rechnet mit llvmpipe),
## --bewegung (Fernseher mit Spielbild, Kamera dreht: Bilder während der Bewegung, gegen Schmieren),
## --bilder=N (vor jedem Bild mindestens N gezeichnete Bilder abwarten – FSR 2 setzt zeitlich zusammen;
## mit llvmpipe in 4K dauert ein Bild Sekunden), --kurz (nur Tür und Nahansicht nachts, Raum am Tag, Fernseher),
## --analyse (Zeichenaufrufe der Ansicht und der Schatten Bild für Bild bei stehender Kamera – rechnet
## etwas die Lampenschatten jedes Bild neu? –, dazu Dreiecke und Netze je Möbelart, mit und ohne Schatten),
## --skripte (Zeit der Skripte je Bild im Zimmer: Performance.TIME_PROCESS und je Knoten mit _process bzw.
## _physics_process, im Stand und aufgestanden mit Spielbild im Fernseher), --karten (die gebackenen
## Lichtkarten je Fläche: Werte und Bilder, nachts und am Tag), --anteile[=tag|nacht|…] (was trägt wie viel
## zum Bild bei: Umgebung, Himmelslicht, Sonne, Abprall, Lampen, Sonde – je eins aus, neu gebacken, mit
## Helligkeit und Lichtkarten), --fenster (Flackern und Blick nach draußen nach unten), --neben (der schlanke
## Weg neben einem laufenden Spiel: Bildrate, Einstellungen, Zeichenaufrufe und ein Bild ohne und mit Spiel,
## danach muss alles wieder wie vorher sein), --pipelines (wie viele Pipelines die Engine beim Betreten, beim
## Umsehen in alle Richtungen, von oben, im schlanken Weg und zurück übersetzt – „beim Zeichnen“ heißt: das
## Bild wartet darauf; Ziel 0), --brett (Fensterbank: Anteil sich ändernder Bildpunkte bei stehender Kamera und
## bei 2 mm Bewegung je Bild – Z-Fighting flimmert schon bei kleinster Bewegung –, Ultra und schlanker Weg,
## Tag und Nacht).
##
## Aufruf: xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --resolution 1920x1080 -- --demo
##   --no-boot --uzai-script=res://tests/probe_zimmerbild.gd --uzai-out=<ordner> --stand=nachher

const Leicht := preload("res://src/core/leicht.gd")
const Spielbild := preload("res://src/room/spielbild.gd")
const Z23 := preload("res://tests/probe_zstufe23.gd")

var z: Control
var stand := "nachher"
var stufe := "hoch"
var nur_groesse := false
var nur_zeiten := false
var leistung: PackedStringArray = []
var bewegung := false
var min_bilder := 0
var kurz := false
var analyse := false
var skripte := false
var karten := false
var anteile := ""
var fenster := false
var neben := false
var pipelines := false
var brett := false
var _p0: Array = []


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stand="):
			stand = a.substr(8)
		elif a.begins_with("--stufe="):
			stufe = a.substr(8)
		elif a == "--nur-groesse":
			nur_groesse = true
		elif a == "--zeiten":
			nur_zeiten = true
		elif a.begins_with("--leistung"):
			leistung = PackedStringArray([stufe]) if a == "--leistung" else a.substr(11).split(",")
		elif a == "--bewegung":
			bewegung = true
		elif a.begins_with("--bilder="):
			min_bilder = int(a.substr(9))
		elif a == "--kurz":
			kurz = true
		elif a == "--analyse":
			analyse = true
		elif a == "--skripte":
			skripte = true
		elif a == "--karten":
			karten = true
		elif a == "--fenster":
			fenster = true
		elif a == "--neben":
			neben = true
		elif a == "--pipelines":
			pipelines = true
		elif a == "--brett":
			brett = true
		elif a.begins_with("--anteile"):
			anteile = "tag" if a == "--anteile" else a.substr(10)
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("display.light", "aus")
	Config.set_value("room.grafik", stufe)
	Leicht.refresh()
	main.goto("games")
	await wait(1.0)
	var spiel := await spielbild_bauen()
	_p0 = _pipes()
	main.open_room(true)
	await wait(2.8)
	z = Nav.top_layer()
	var vp: SubViewport = z.vp
	print("INFO Renderer %s, Karte %s, Fenster %s, Ansicht 3D %s, Behälter %s, MSAA %d, Skala %.2f, Stufe %s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), get_window().size,
		vp.size, z.svc.size, vp.msaa_3d, vp.scaling_3d_scale, z.stufe])
	# Dynamische Auflösung für vergleichbare Bilder fest (llvmpipe wäre immer „zu langsam“).
	var lst: Variant = z.get("leistung")
	if lst != null:
		lst.set("dynamisch", false)
	if not leistung.is_empty():
		for st in leistung:
			await leistung_messen(st)
		return
	if bewegung:
		await bewegung_bilder(spiel)
		return
	if analyse:
		await analysieren()
		return
	if skripte:
		await skripte_messen(spiel)
		return
	if anteile != "":
		await anteile_messen(anteile)
		return
	if fenster:
		await fenster_pruefen()
		return
	if neben:
		await neben_pruefen(spiel)
		return
	if pipelines:
		await pipelines_pruefen(spiel)
		return
	if brett:
		await brett_pruefen(spiel)
		return
	if karten:
		for t in ["nacht", "tag"]:
			await zeit(t)
			ich()
			await wait(3.0)
			karten_zeigen(t)
			await bild("40_karten_raum_" + t, 0.5)
		return
	if nur_groesse:
		await zeit("nacht")
		tuer(2.6, 0.0, -0.06)
		await bild("groesse")
		return
	if nur_zeiten:
		for t in ["morgen", "tag", "abend", "nacht"]:
			await zeit(t)
			ich()
			await bild("10_zeit_raum_" + t, 1.8)
			helligkeit("raum " + t)
			tuer(2.6, 0.0, -0.06)
			await bild("11_zeit_tuer_" + t, 1.6)
			helligkeit("tür " + t)
		return
	for t in ["nacht", "tag"]:
		await zeit(t)
		if kurz:
			if t == "nacht":
				tuer(2.6, 0.0, -0.06)
				await bild("01_tuer_" + t, 2.2)
				tuer(1.25, -0.55, -0.12)
				await bild("02_nah_" + t)
			else:
				ich()
				await bild("04_raum_" + t)
			continue
		var env: Environment = z.welt.huelle.env
		print("INFO %s: Belichtung %.2f, Umgebung %.2f, Kontrast %.2f, Sättigung %.2f, Tonemapper %d, Glühen %s, SSAO %s, SDFGI %s" % [t,
			env.tonemap_exposure, env.ambient_light_energy, env.adjustment_contrast, env.adjustment_saturation, env.tonemap_mode,
			env.glow_enabled, env.ssao_enabled, env.sdfgi_enabled])
		tuer(2.6, 0.0, -0.06)
		await bild("01_tuer_" + t, 2.2)
		await ruhe("01_tuer_" + t)
		tuer(1.25, -0.55, -0.12)
		await bild("02_nah_" + t)
		await ruhe("02_nah_" + t)
		tuer(2.4, 0.6, -0.62)
		await bild("03_boden_" + t)
		await ruhe("03_boden_" + t)
		ich()
		await bild("04_raum_" + t)
	# --- Fernseher mit Spielbild ---------------------------------------------------------------------------
	await zeit("nacht")
	Spielbild.demo_bild = spiel
	Spielbild.demo_titel = "Sternenfall"
	main.set("_tv", "zimmer")
	z.tv_wechsel("zimmer")
	await z._zum_fernseher(0.2)
	await wait(3.0)
	await bild("05_tv_sitzend", 0.6)
	await tv_vergleich("05_tv_sitzend", spiel)
	# Aufgestanden: das Spiel läuft weiter, du schaust aus zwei Metern auf den Fernseher (Glimmen).
	main.set("_tv", "zimmer")
	z.tv_wechsel("zimmer")
	await wait(1.6)
	vor_tv(2.3)
	await wait(1.4)
	await bild("06_tv_stehend", 0.8)
	await tv_vergleich("06_tv_stehend", spiel)
	Spielbild.demo_bild = null
	main.set("_tv", "")
	z.tv_wechsel("")
	await wait(0.6)


## Mittlere Helligkeit (linear, 0 … 1) der 3D-Ansicht ohne Ränder (Kopf, Tastenzeile).
func helligkeit(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var summe := 0.0
	var n := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in range(int(h * 0.14), int(h * 0.88), 4):
		for x in range(int(w * 0.16), int(w * 0.84), 4):
			var c := img.get_pixel(x, y).srgb_to_linear()
			summe += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			n += 1
	print("HELL %s %s: %.3f" % [stand, name, summe / maxf(n, 1)])


func bild(name: String, wait_s := 1.4) -> void:
	await gebacken()
	for i in min_bilder:
		await RenderingServer.frame_post_draw
	await shot(stand + "_" + name, wait_s)


## Bis das Licht der Hülle fertig gebacken ist (lichtbacken.gd; mit llvmpipe dauert ein Bild Sekunden).
func gebacken() -> void:
	var b: Variant = z.welt.get("backen") if z and z.welt else null
	if b == null:
		return
	var t0 := Time.get_ticks_msec()
	while str(b.get("_zustand")) != "ruhe" and Time.get_ticks_msec() - t0 < 120000:
		await RenderingServer.frame_post_draw
	await wait(0.6)


## Zwei Bilder direkt nacheinander: wie viel ändert sich ohne Bewegung?
func ruhe(name: String) -> void:
	await RenderingServer.frame_post_draw
	var a := get_viewport().get_texture().get_image()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var b := get_viewport().get_texture().get_image()
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var w := a.get_width()
	var h := a.get_height()
	var d := Image.create(w, h, false, Image.FORMAT_RGB8)
	var summe := 0.0
	var viele := 0
	var n := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var dd := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 * 255.0
			summe += dd
			n += 1
			if dd > 2.0:
				viele += 1
			var v := clampf(dd * 16.0 / 255.0, 0.0, 1.0)
			d.set_pixel(x, y, Color(v, v, v))
			d.set_pixel(mini(x + 1, w - 1), y, Color(v, v, v))
			d.set_pixel(x, mini(y + 1, h - 1), Color(v, v, v))
			d.set_pixel(mini(x + 1, w - 1), mini(y + 1, h - 1), Color(v, v, v))
	d.save_png(out.path_join("%s_%s_unruhe.png" % [stand, name]))
	print("RUHE %s %s: mittlere Änderung %.3f (0–255), Anteil > 2: %.2f %%" % [stand, name, summe / maxf(n, 1), 100.0 * viele / maxf(n, 1)])


## Bildschirm des Fernsehers in Fensterpixeln (leer, wenn er nicht ganz im Bild ist).
func tv_rechteck() -> Rect2i:
	var tv: int = z.welt.medienwand()
	if tv < 0 or not (z.welt.knoten[tv] as Node3D).has_meta("bildschirm"):
		return Rect2i()
	var bs: MeshInstance3D = (z.welt.knoten[tv] as Node3D).get_meta("bildschirm")
	var q := bs.mesh as QuadMesh
	var cam: Camera3D = z.welt.kamera
	var xf: Transform2D = z.get_viewport().get_screen_transform() * (z.svc as Control).get_global_transform_with_canvas()
	var skala: Vector2 = (z.svc as Control).size / Vector2(maxi(1, z.vp.size.x), maxi(1, z.vp.size.y))
	var a := Vector2(INF, INF)
	var b := Vector2(-INF, -INF)
	for e: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var p3 := bs.global_transform * Vector3(e.x * q.size.x, e.y * q.size.y, 0.0)
		if cam.is_position_behind(p3):
			return Rect2i()
		var p := xf * (cam.unproject_position(p3) * skala)
		a = a.min(p)
		b = b.max(p)
	return Rect2i(Vector2i(a.round()), Vector2i((b - a).round()))


## Ausschnitt des Fernsehers neben dem Original; mittlere Abweichung je Kanal (0–255).
func tv_vergleich(name: String, spiel: Image) -> void:
	var r: Rect2i = tv_rechteck()
	if r.size.x < 8 or r.size.y < 8:
		print("TV %s %s: nicht im Bild" % [stand, name])
		return
	await RenderingServer.frame_post_draw
	var bild_jetzt := get_viewport().get_texture().get_image()
	bild_jetzt.convert(Image.FORMAT_RGB8)
	var inset := Vector2i(roundi(r.size.x * 0.04), roundi(r.size.y * 0.04))
	var innen := r.grow_individual(-inset.x, -inset.y, -inset.x, -inset.y)
	var aus := bild_jetzt.get_region(innen)
	var orig := spiel.duplicate() as Image
	orig.convert(Image.FORMAT_RGB8)
	var ow := orig.get_width()
	var oh := orig.get_height()
	orig = orig.get_region(Rect2i(roundi(ow * 0.04), roundi(oh * 0.04), roundi(ow * 0.92), roundi(oh * 0.92)))
	orig.resize(aus.get_width(), aus.get_height(), Image.INTERPOLATE_BILINEAR)
	var sum := Vector3.ZERO
	var hell_a := 0.0
	var hell_o := 0.0
	var n := 0
	for y in range(0, aus.get_height(), 3):
		for x in range(0, aus.get_width(), 3):
			var ca := aus.get_pixel(x, y)
			var co := orig.get_pixel(x, y)
			sum += Vector3(absf(ca.r - co.r), absf(ca.g - co.g), absf(ca.b - co.b)) * 255.0
			hell_a += ca.get_luminance()
			hell_o += co.get_luminance()
			n += 1
	sum /= maxf(n, 1)
	print("TV %s %s: Abweichung R %.1f G %.1f B %.1f, Helligkeit Fernseher %.3f / Original %.3f" % [stand, name, sum.x, sum.y, sum.z,
		hell_a / maxf(n, 1), hell_o / maxf(n, 1)])
	var v := Image.create(aus.get_width() * 2 + 8, aus.get_height(), false, Image.FORMAT_RGB8)
	v.fill(Color(0.9, 0.76, 0.49))
	v.blit_rect(aus, Rect2i(Vector2i.ZERO, aus.get_size()), Vector2i.ZERO)
	v.blit_rect(orig, Rect2i(Vector2i.ZERO, orig.get_size()), Vector2i(aus.get_width() + 8, 0))
	v.save_png(out.path_join("%s_%s_vergleich.png" % [stand, name]))


func spielbild_bauen() -> Image:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.disable_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var s: Control = Z23._Spiel.new()
	s.size = Vector2(1280, 720)
	sv.add_child(s)
	add_child(sv)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	sv.queue_free()
	img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	return img


## Tageszeit setzen und warten, bis die globale Beleuchtung (SDFGI) nachgezogen hat – sie rechnet über
## viele Bilder nach; mit Software-Grafik sind das einige Sekunden.
func zeit(t: String) -> void:
	z.licht_setzen("z", t)
	z._licht_neu(false)
	for i in 50:
		await get_tree().process_frame


func ziel() -> void:
	var soll: Array = z._kamera_soll()
	z.welt.kamera.transform = soll[0]
	z.welt.kamera.fov = float(soll[1])
	z._rate = 40.0


## Vor der Tür (rechte Wand): abstand von der Wand, seitlich entlang der Wand, Neigung.
func tuer(abstand: float, seitlich: float, neigung: float) -> void:
	var h = z.welt.huelle
	var tz: float = h._tuer_z(z.raum)
	z.blick = "ich"
	z.pos = Vector3(float(h.w) - abstand, 0, tz + seitlich)
	var dir := Vector3(float(h.w), 1.1, tz) - Vector3(z.pos.x, 1.62, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = neigung
	ziel()


func ich() -> void:
	z.blick = "ich"
	z.pos = Vector3(5.0, 0, 4.35)
	z.yaw = 0.42
	z._yaw_soll = 0.42
	z.pitch = -0.1
	ziel()


func vor_tv(abstand: float) -> void:
	var tv: int = z.welt.medienwand()
	if tv < 0:
		return
	var n: Node3D = z.welt.knoten[tv]
	var vorn := n.transform.basis.z.normalized()
	var mitte: Vector3 = (z.welt.boxen[tv] as AABB).get_center()
	z.modus = "laufen"
	z.blick = "ich"
	z.pos = Vector3(mitte.x, 0, mitte.z) + vorn * abstand
	var dir := mitte - Vector3(z.pos.x, 1.62, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	ziel()


# --- Leistung ---------------------------------------------------------------------------------------

## Je Stufe: was die 3D-Ansicht rechnet (Einstellungen, Lichter mit Schatten, Effekte) und was sie zeichnet.
func leistung_messen(st: String) -> void:
	if z.stufe != st or str(Config.get_value("room.grafik", "")) != st:
		z.grafik_setzen(st)
		var lst: Variant = z.get("leistung")
		if lst != null:
			lst.set("dynamisch", false)
		await wait(1.5)
	await zeit("nacht")
	ich()
	await wait(2.5)
	var vp: SubViewport = z.vp
	var env: Environment = z.welt.huelle.env
	var modi := { Viewport.SCALING_3D_MODE_BILINEAR: "bilinear", Viewport.SCALING_3D_MODE_FSR: "FSR1", Viewport.SCALING_3D_MODE_FSR2: "FSR2" }
	var intern := Vector2i((Vector2(vp.size) * vp.scaling_3d_scale).round())
	print("LEISTUNG %s %s: Ansicht %s, intern %s (Skala %.2f, %s), MSAA %d, TAA %s, Engine.max_fps %d, Bildschirm %.0f Hz" % [stand, st,
		vp.size, intern, vp.scaling_3d_scale, modi.get(vp.scaling_3d_mode, "?"), vp.msaa_3d, vp.use_taa, Engine.max_fps,
		DisplayServer.screen_get_refresh_rate()])
	var lst: Variant = z.get("leistung")
	if lst != null:
		print("LEISTUNG %s %s: %s" % [stand, st, lst.call("text_jetzt")])
	print("LEISTUNG %s %s: SDFGI %s (Kaskaden %d, Zelle %.2f), SSAO %s, SSIL %s, SSR %s (Schritte %d), Nebel %s, Glühen %s, Sonde %s, GI halbe Auflösung %s" % [
		stand, st, env.sdfgi_enabled, env.sdfgi_cascades, env.sdfgi_min_cell_size, env.ssao_enabled, env.ssil_enabled, env.ssr_enabled,
		env.ssr_max_steps, env.volumetric_fog_enabled, env.glow_enabled, z.welt.huelle.get("_sonde") != null,
		ProjectSettings.get_setting("rendering/global_illumination/gi/use_half_resolution", false)])
	var schatten: Array = []
	var lichter := 0
	var stapel: Array[Node] = [z.welt]
	while not stapel.is_empty():
		var n: Node = stapel.pop_back()
		stapel.append_array(n.get_children())
		if n is Light3D and (n as Light3D).is_visible_in_tree():
			lichter += 1
			if (n as Light3D).shadow_enabled:
				var art := "Sonne" if n is DirectionalLight3D else ("Spot" if n is SpotLight3D else
					("Omni Würfel" if (n as OmniLight3D).omni_shadow_mode == OmniLight3D.SHADOW_CUBE else "Omni Paraboloid"))
				schatten.append(art)
	print("LEISTUNG %s %s: Lichter %d, mit Schatten %d %s, Atlas Lampen %d, Sonne %d" % [stand, st, lichter, schatten.size(), str(schatten),
		vp.positional_shadow_atlas_size, int(_stufe_werte(st).get("schatten", 0))])
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await wait(0.5)
	print("LEISTUNG %s %s: Bild: %d Zeichenaufrufe, %d Objekte, %d Primitive; Schatten: %d Zeichenaufrufe, %d Objekte, %d Primitive" % [stand, st,
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)])
	for lage in ["Ruhe", "Bewegung"]:
		var bilder := 0
		var mit_3d := 0
		var gpu := 0.0
		var gpu_n := 0
		var t0 := Time.get_ticks_msec()
		var basis := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		while Time.get_ticks_msec() - t0 < 5000:
			if lage == "Bewegung":
				z.yaw += 0.01
				z._yaw_soll = z.yaw
			await RenderingServer.frame_post_draw
			bilder += 1
			var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			if dc > maxi(40, basis / 3):
				mit_3d += 1
			var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
			if g > 0.0:
				gpu += g
				gpu_n += 1
		var s := (Time.get_ticks_msec() - t0) / 1000.0
		print("LEISTUNG %s %s %s: %.1f Bilder/s, 3D neu in %d von %d Bildern, Engine.max_fps %d, Grafikkarte 3D Ø %.1f ms (llvmpipe)" % [stand, st,
			lage, bilder / s, mit_3d, bilder, Engine.max_fps, gpu / maxf(gpu_n, 1)])
	if lst != null and lst.has_method("text_messung"):
		print("LEISTUNG %s %s Messung: %s" % [stand, st, lst.call("text_messung", 0.0)])
	await bild("20_leistung_" + st, 0.5)


static func _stufe_werte(st: String) -> Dictionary:
	return (load("res://src/room/licht.gd") as GDScript).call("werte", st)


## Fernseher mit Spielbild aus zwei Metern, die Kamera dreht langsam: Bilder mitten in der Bewegung
## (FSR 2 rechnet zeitlich – darf an Figur und Fernsehbild nicht schmieren).
func bewegung_bilder(spiel: Image) -> void:
	await zeit("nacht")
	Spielbild.demo_bild = spiel
	Spielbild.demo_titel = "Sternenfall"
	main.set("_tv", "zimmer")
	z.tv_wechsel("zimmer")
	await wait(1.6)
	vor_tv(2.3)
	await wait(2.0)
	await bild("30_tv_ruhig", 0.4)
	for i in 3:
		for k in 6:
			z.yaw += 0.006
			z._yaw_soll = z.yaw
			await RenderingServer.frame_post_draw
		await bild("31_tv_dreht_%d" % i, 0.0)
	# Bewegtes Spielbild (heller Balken wandert, 30 Bilder je Sekunde wie die Aufnahme): zieht er Schlieren?
	# Gleiches Format wie das Spielbild: der Fernseher legt neue Bilder in dieselbe Textur (ImageTexture.update).
	var lauf := Image.create(spiel.get_width(), spiel.get_height(), false, spiel.get_format())
	Spielbild.demo_bild = lauf
	for i in 40:
		lauf.fill(Color(0.08, 0.1, 0.16))
		lauf.fill_rect(Rect2i((i * 24) % 900, 60, 36, 420), Color(1.0, 0.92, 0.6))
		lauf.fill_rect(Rect2i(80, 200 + (i * 9) % 200, 300, 24), Color(0.3, 0.8, 1.0))
		z.welt.tv_live(lauf)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if i in [20, 30, 39]:
			var r: Rect2i = tv_rechteck()
			var img := get_viewport().get_texture().get_image()
			if r.size.x > 8:
				img.get_region(r.grow(12)).save_png(out.path_join("%s_34_tv_lauf_%d.png" % [stand, i]))
				var soll := lauf.duplicate() as Image
				soll.resize(r.size.x, r.size.y, Image.INTERPOLATE_BILINEAR)
				soll.save_png(out.path_join("%s_34_tv_lauf_%d_soll.png" % [stand, i]))
	ich()
	await wait(1.5)
	await bild("32_raum_ruhig", 0.3)
	for k in 6:
		z.yaw -= 0.012
		z._yaw_soll = z.yaw
		await RenderingServer.frame_post_draw
	await bild("33_raum_dreht", 0.0)
	Spielbild.demo_bild = null
	main.set("_tv", "")
	z.tv_wechsel("")
	await wait(0.6)


# --- Analyse ----------------------------------------------------------------------------------------

## Zeichenaufrufe Bild für Bild (Ansicht / Schatten) bei stehender Kamera, nachts und am Tag, und was
## an Dreiecken in der Welt steht (je Möbelart; wirft es Schatten?).
func analysieren() -> void:
	var rid: RID = z.vp.get_viewport_rid()
	for t in ["nacht", "tag"]:
		await zeit(t)
		ich()
		await wait(2.0)
		var reihe := PackedStringArray()
		for i in 10:
			await RenderingServer.frame_post_draw
			reihe.append("%d/%d" % [RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
					RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME), RenderingServer.viewport_get_render_info(rid,
					RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
		print("ANALYSE %s %s %s: Zeichenaufrufe Ansicht/Schatten je Bild: %s" % [stand, z.stufe, t, " ".join(reihe)])
	var arten := {}
	var stapel: Array[Node] = [z.welt]
	while not stapel.is_empty():
		var n: Node = stapel.pop_back()
		stapel.append_array(n.get_children())
		if not (n is MeshInstance3D) or not (n as MeshInstance3D).is_visible_in_tree() or (n as MeshInstance3D).mesh == null:
			continue
		var mi := n as MeshInstance3D
		var art := _art_von(mi)
		var dreiecke := 0
		for s in mi.mesh.get_surface_count():
			var f: Dictionary = RenderingServer.mesh_get_surface(mi.mesh.get_rid(), s)
			var k := int(f.get("index_count", 0))
			dreiecke += (k if k > 0 else int(f.get("vertex_count", 0))) / 3
		var e: Array = arten.get(art, [0, 0, 0, 0])
		var wirft := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e[0] += 1
		e[1] += dreiecke
		e[2] += 1 if wirft else 0
		e[3] += dreiecke if wirft else 0
		arten[art] = e
	var liste := arten.keys()
	liste.sort_custom(func(a: Variant, b: Variant) -> bool: return int(arten[a][1]) > int(arten[b][1]))
	for a in liste:
		var e: Array = arten[a]
		print("ANALYSE %s %s: %-22s %4d Netze, %7d Dreiecke, davon mit Schatten %4d Netze, %7d Dreiecke" % [stand, z.stufe, str(a), e[0], e[1], e[2], e[3]])


## Zu welchem Möbel (Art) oder Teil der Welt ein Netz gehört.
func _art_von(n: Node) -> String:
	var w: Node = z.welt
	var k: Array = w.get("knoten")
	var p: Node = n
	while p != null and p != w:
		var i := k.find(p)
		if i >= 0:
			return str((z.raum.moebel as Array)[i].t)
		if p == w.get("huelle"):
			return "(Hülle)"
		if z.bewohner and (p == z.bewohner.avatar or p == z.bewohner.tier):
			return "(Figur)" if p == z.bewohner.avatar else "(Haustier)"
		p = p.get_parent()
	return "(sonst)"


# --- Fensterbank ----------------------------------------------------------------------------------

## Fensterbank von schräg oben, je Lage (Ultra, schlanker Weg neben dem Spiel) und Tageszeit: wie viele
## Bildpunkte der Bank sich über fünf Bilder ändern – still und mit 2 mm Bewegung je Bild.
func brett_pruefen(spiel: Image) -> void:
	var h: Node = z.welt.huelle
	var dd := float(h.get("d"))
	var fu := float((h.get("fenster") as Dictionary).unten)
	var fb := float((h.get("fenster") as Dictionary).breite)
	for lage in ["ultra", "schlank"]:
		if lage == "schlank":
			Launcher.in_game = true
			Spielbild.demo_bild = spiel
			main.set("_tv", "zimmer")
			z.tv_wechsel("zimmer")
			await wait(1.0)
		for t in ["tag", "nacht"]:
			await zeit(t)
			await gebacken()
			z.blick = "ich"
			z.modus = "laufen"
			z.pos = Vector3(0.72, 0, dd * 0.5 + 0.35)
			var ziel_p := Vector3(0.04, fu, dd * 0.5)
			var dir := ziel_p - Vector3(z.pos.x, 1.62, z.pos.z)
			z.yaw = atan2(-dir.x, -dir.z)
			z._yaw_soll = z.yaw
			z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
			ziel()
			await wait(1.2)
			# Nur die Oberseite der Bank in der Öffnung (ohne Vorhänge, Glas und Himmel daneben).
			var cam: Camera3D = z.welt.kamera
			var vieleck := PackedVector2Array()
			for e: Vector3 in [Vector3(-0.035, fu, dd * 0.5 - fb * 0.5 + 0.06), Vector3(0.12, fu, dd * 0.5 - fb * 0.5 + 0.06),
					Vector3(0.12, fu, dd * 0.5 + fb * 0.5 - 0.06), Vector3(-0.035, fu, dd * 0.5 + fb * 0.5 - 0.06)]:
				vieleck.append(cam.unproject_position(e))
			var still := await _brett_aenderung(vieleck, 0.0, "%s_60_brett_%s_%s_still" % [stand, lage, t])
			var bewegt := await _brett_aenderung(vieleck, 0.002, "%s_61_brett_%s_%s_bewegt" % [stand, lage, t])
			print("BRETT %s %s %s: still %.2f %%, 2 mm je Bild %.2f %%" % [stand, lage, t, still, bewegt])
	Launcher.in_game = false
	Spielbild.demo_bild = null
	main.set("_tv", "")
	z.tv_wechsel("")


## Anteil der Bildpunkte der Bank, die sich über fünf Bilder um mehr als 6/255 ändern; karte: Name der
## Änderungskarte (hell = ändert sich) im Ausgabeordner.
func _brett_aenderung(vieleck: PackedVector2Array, schritt: float, karte := "") -> float:
	var r := Rect2(vieleck[0], Vector2.ZERO)
	for q in vieleck:
		r = r.expand(q)
	r = r.intersection(Rect2(Vector2.ZERO, Vector2(z.vp.size)))
	var bilder: Array[Image] = []
	for i in 5:
		if schritt > 0.0:
			z.pos.z += schritt
			ziel()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var b: Image = z.vp.get_texture().get_image()
		b.convert(Image.FORMAT_RGB8)
		bilder.append(b)
	var viele := 0
	var n := 0
	var bild := Image.create(maxi(1, int(r.size.x)), maxi(1, int(r.size.y)), false, Image.FORMAT_RGB8)
	for y in range(int(r.position.y), int(r.end.y), 2):
		for x in range(int(r.position.x), int(r.end.x), 2):
			if not Geometry2D.is_point_in_polygon(Vector2(x, y), vieleck):
				continue
			var lo := 9.0
			var hi := 0.0
			for b in bilder:
				var l := b.get_pixel(x, y).get_luminance()
				lo = minf(lo, l)
				hi = maxf(hi, l)
			n += 1
			if (hi - lo) * 255.0 > 6.0:
				viele += 1
			var v := clampf((hi - lo) * 8.0, 0.0, 1.0)
			bild.fill_rect(Rect2i(x - int(r.position.x), y - int(r.position.y), 2, 2), Color(v, v, v))
	if karte != "":
		bild.save_png(out.path_join(karte + ".png"))
	return 100.0 * viele / maxf(n, 1)


# --- Pipelines ------------------------------------------------------------------------------------

func _pipes() -> Array:
	return [int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)), int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)),
		int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)), int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS))]


func _pipes_zeile(was: String) -> void:
	var p := _pipes()
	print("PIPELINES %s %s: beim Zeichnen %d, Flächen %d, Spezialisierung %d, 2D %d" % [stand, was, p[0] - _p0[0], p[1] - _p0[1], p[2] - _p0[2], p[3] - _p0[3]])
	_p0 = p


## Betreten (bis fertig gebacken), dann in jede Richtung sehen (acht Richtungen, nach oben und unten, von
## oben), den schlanken Weg an und wieder aus – je Abschnitt die neu übersetzten Pipelines.
func pipelines_pruefen(spiel: Image) -> void:
	await gebacken()
	await wait(1.0)
	_pipes_zeile("Betreten")
	await zeit("abend")
	await gebacken()
	_pipes_zeile("Abend (neu gebacken)")
	ich()
	for i in 8:
		z.yaw = 0.42 + TAU * i / 8.0
		z._yaw_soll = z.yaw
		ziel()
		for k in 4:
			await RenderingServer.frame_post_draw
	for nb in [0.9, -0.9]:
		z.pitch = nb
		ziel()
		for k in 4:
			await RenderingServer.frame_post_draw
	_pipes_zeile("Umsehen")
	z.blick = "oben"
	ziel()
	await wait(1.0)
	ich()
	await wait(0.5)
	_pipes_zeile("Von oben")
	Launcher.in_game = true
	Spielbild.demo_bild = spiel
	Spielbild.demo_titel = "Sternenfall"
	main.set("_tv", "zimmer")
	z.tv_wechsel("zimmer")
	await wait(1.5)
	for i in 8:
		z.yaw = 0.42 + TAU * i / 8.0
		z._yaw_soll = z.yaw
		ziel()
		for k in 4:
			await RenderingServer.frame_post_draw
	_pipes_zeile("Schlanker Weg, umsehen")
	Launcher.in_game = false
	Spielbild.demo_bild = null
	main.set("_tv", "")
	z.tv_wechsel("")
	z.call("_spiel_pruefen")
	await wait(1.5)
	_pipes_zeile("Zurück zur Stufe")
	print("PIPELINES %s Messung: %s" % [stand, str(z.leistung.call("text_messung", 0.0))])


# --- Neben dem Spiel ------------------------------------------------------------------------------

## Der schlanke Weg neben einem laufenden Spiel: ohne Spiel (Stufe wie gewählt), aufgestanden mit Spiel
## im Fernseher (Kappe, Rahmen, Effekte, Lampenschatten, Spiegel, Zeichenaufrufe, Bild), danach wieder
## ohne – alles wie vorher?
func neben_pruefen(spiel: Image) -> void:
	await zeit("abend")
	ich()
	await wait(2.0)
	var vorher := _neben_stand("ohne Spiel")
	await bild("50_ohne_spiel", 1.0)
	Launcher.in_game = true
	Spielbild.demo_bild = spiel
	Spielbild.demo_titel = "Sternenfall"
	main.set("_tv", "zimmer")
	z.tv_wechsel("zimmer")
	await wait(2.4)
	var mit := _neben_stand("neben dem Spiel")
	print("NEBEN Bildrate %d (Engine.max_fps; hinter dem Spiel: %d, Bildschirm %.0f Hz)" % [Engine.max_fps, int(z.call("ruhe_fps")),
		float(z.leistung.hz)])
	print("NEBEN %s" % str(z.leistung.call("text_jetzt")))
	print("NEBEN Messung: %s" % str(z.leistung.call("text_messung", 0.0)))
	print("NEBEN Bildzeiten: %s" % str(z.bildzeit.call("zusammenfassung", z.bildzeit.get("_dts"), z.bildzeit.get("_ablaeufe"), 0.0, 0.0, 0.0,
			Engine.max_fps, str(z.bildzeit.get("_laengster")))))
	await bild("51_neben_dem_spiel", 1.0)
	# Was das Flimmern des Fernsehers kostet: alle Lampen neu (vorher) gegen nur sein Licht (jetzt).
	var t0 := Time.get_ticks_usec()
	for i in 20:
		z.welt.lampen_auffrischen(false)
	var t1 := Time.get_ticks_usec()
	for i in 20:
		z.welt.tv_flimmern(0.9 + 0.01 * i)
	var t2 := Time.get_ticks_usec()
	print("NEBEN Flimmern: alle Lampen neu %.3f ms, nur das Licht des Fernsehers %.3f ms (je Aufruf)" % [(t1 - t0) / 20000.0, (t2 - t1) / 20000.0])
	for e in mit.keys():
		if mit[e] != vorher[e]:
			print("NEBEN geändert: %s %s → %s" % [e, str(vorher[e]), str(mit[e])])
	Launcher.in_game = false
	Spielbild.demo_bild = null
	main.set("_tv", "")
	z.tv_wechsel("")
	z.call("_spiel_pruefen")
	await wait(1.2)
	var nachher := _neben_stand("wieder ohne")
	var gleich := true
	for e in vorher.keys():
		if e in ["Zeichenaufrufe"]:
			continue
		if nachher[e] != vorher[e]:
			gleich = false
			print("NEBEN FEHLER: %s nicht zurück (%s statt %s)" % [e, str(nachher[e]), str(vorher[e])])
	print("NEBEN zurück: %s" % ("alles wie vorher" if gleich else "nicht alles"))


func _neben_stand(lage: String) -> Dictionary:
	var vp: SubViewport = z.vp
	var env: Environment = z.welt.huelle.get("env")
	var lampen := 0
	for i in (z.welt.knoten as Array).size():
		var n: Variant = z.welt.knoten[i]
		if is_instance_valid(n):
			for e in (n as Node3D).get_meta("lampen", []):
				if (e.licht as Light3D).shadow_enabled:
					lampen += 1
	var d := {
		"MSAA": vp.msaa_3d, "Kantenglättung": vp.screen_space_aa, "Skala": snappedf(vp.scaling_3d_scale, 0.01), "Modus": vp.scaling_3d_mode,
		"SSAO": env.ssao_enabled, "Glühen": env.glow_enabled, "SSR": env.ssr_enabled, "Nebel": env.volumetric_fog_enabled,
		"Lichtstrahl": (z.welt.huelle.get("_strahl") as Node3D).visible, "Lampenschatten": lampen,
		"Zeichenaufrufe": RenderingServer.viewport_get_render_info(vp.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
	}
	print("NEBEN %s: %s" % [lage, str(d)])
	return d


# --- Skripte ----------------------------------------------------------------------------------------

## Zeit der Skripte je Bild: Mittel von Performance.TIME_PROCESS über 30 Bilder, dazu je Knoten mit
## Skript und _process/_physics_process die Zeit eines Aufrufs (je 6-mal direkt aufgerufen, Mittel).
func skripte_messen(spiel: Image) -> void:
	await zeit("nacht")
	ich()
	await wait(2.0)
	await _skripte_lage("Stand")
	Spielbild.demo_bild = spiel
	Spielbild.demo_titel = "Sternenfall"
	main.set("_tv", "zimmer")
	z.tv_wechsel("zimmer")
	await wait(1.6)
	vor_tv(2.3)
	await wait(2.0)
	await _skripte_lage("Spielbild")
	Spielbild.demo_bild = null
	main.set("_tv", "")
	z.tv_wechsel("")
	await wait(0.6)


func _skripte_lage(lage: String) -> void:
	var summe := 0.0
	var phys := 0.0
	var lst := load("res://src/room/leistung.gd") as GDScript
	if lst.has_method("skript_text"):
		lst.call("_abschnitte_leeren")
	for i in 30:
		await RenderingServer.frame_post_draw
		summe += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if lst.has_method("skript_text"):
		print("SKRIPTE %s %s: Abschnitte je Bild: %s; Skripte je Bild Ø %.2f ms" % [stand, lage, lst.call("skript_text", 12), float(z.leistung.get("skript_ms"))])
	print("SKRIPTE %s %s: TIME_PROCESS Ø %.2f ms, TIME_PHYSICS_PROCESS Ø %.2f ms, Knoten %d" % [stand, lage, summe / 30.0, phys / 30.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var zeiten: Array = []
	var stapel: Array[Node] = [get_tree().root]
	while not stapel.is_empty():
		var n: Node = stapel.pop_back()
		stapel.append_array(n.get_children())
		if n == self or n.get_script() == null:
			continue
		for m in ["_process", "_physics_process"]:
			var an := n.is_processing() if m == "_process" else n.is_physics_processing()
			if not an or not n.has_method(m):
				continue
			var t0 := Time.get_ticks_usec()
			for k in 6:
				n.call(m, 1.0 / 60.0)
			zeiten.append([(Time.get_ticks_usec() - t0) / 6000.0, "%s %s (%s)" % [m, str(n.get_path()).right(70), (n.get_script() as Script).resource_path.get_file()]])
	zeiten.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var gesamt := 0.0
	for e in zeiten:
		gesamt += float(e[0])
	print("SKRIPTE %s %s: Summe der Aufrufe %.2f ms in %d Knoten" % [stand, lage, gesamt, zeiten.size()])
	for e in zeiten.slice(0, 15):
		print("SKRIPTE %s %s: %6.3f ms  %s" % [stand, lage, float(e[0]), str(e[1])])


# --- Gebackenes Licht -------------------------------------------------------------------------------

## Was trägt wie viel zum Bild bei (Tageszeit tz, Ich-Ansicht): je ein Licht aus (Umgebung,
## Himmelslicht, Sonne, Abprall, Lampen), neu gebacken, Helligkeit und Lichtkarten; dann alles aus und
## zuletzt die Reflexionssonde aus.
func anteile_messen(tz: String) -> void:
	await zeit(tz)
	ich()
	await bild("70_%s_alles" % tz, 1.0)
	await helligkeit("alles")
	await karten_zeigen("alles")
	var h: Node = z.welt.huelle
	var b: Node = z.welt.get("backen")
	var env: Environment = h.get("env")
	var teile := [["umgebung", env, "ambient_light_sky_contribution"], ["himmelslicht", h.get("himmelslicht"), "light_energy"],
		["sonne", h.get("sonne"), "light_energy"], ["fuell", h.get("fuell"), "light_energy"]]
	print("ANTEILE %s: Umgebung (Himmel) %.3f, Belichtung %.3f, Himmelslicht %.3f, Sonne %.3f, Abprall %.3f" % [tz,
		env.ambient_light_sky_contribution, env.tonemap_exposure, (h.get("himmelslicht") as Light3D).light_energy,
		(h.get("sonne") as Light3D).light_energy, (h.get("fuell") as Light3D).light_energy])
	var i := 0
	for e: Array in teile:
		i += 1
		var o: Object = e[1]
		var vorher: float = o.get(e[2])
		o.set(e[2], 0.0)
		b.call("anstossen")
		await RenderingServer.frame_post_draw
		await bild("7%d_%s_ohne_%s" % [i, tz, e[0]], 1.0)
		await helligkeit("ohne %s (%.3f)" % [e[0], vorher])
		await karten_zeigen("ohne_" + str(e[0]))
		o.set(e[2], vorher)
	var lampen: Array = []
	for k in z.welt.get("knoten"):
		for l in (k as Node).find_children("*", "Light3D", true, false):
			lampen.append([l, (l as Light3D).light_energy])
			(l as Light3D).light_energy = 0.0
	b.call("anstossen")
	await RenderingServer.frame_post_draw
	await bild("76_%s_ohne_lampen" % tz, 1.0)
	await helligkeit("ohne Lampen (%d)" % lampen.size())
	await karten_zeigen("ohne_lampen")
	for e: Array in teile:
		(e[1] as Object).set(e[2], 0.0)
	b.call("anstossen")
	await RenderingServer.frame_post_draw
	await bild("77_%s_ohne_alles" % tz, 1.0)
	await helligkeit("ohne alles")
	await karten_zeigen("ohne_alles")
	(h.get("_sonde") as Node3D).visible = false
	await bild("78_%s_ohne_alles_und_sonde" % tz, 1.0)
	await helligkeit("ohne alles und Sonde")


## Das Fenster: aus zwei Metern (Flackern: fünf Bilder bei stehender Kamera, größte Änderung je Punkt)
## und ganz nah mit Blick nach unten (was liegt draußen unter dem Bild?), am Tag und nachts; dazu das
## Schild am Fernseher aus zwei Metern.
func fenster_pruefen() -> void:
	var dd := float(z.welt.huelle.get("d"))
	for t in ["tag", "nacht"]:
		await zeit(t)
		z.blick = "ich"
		z.modus = "laufen"
		z.pos = Vector3(2.0, 0, dd * 0.5 + 0.2)
		z.yaw = PI * 0.5
		z._yaw_soll = z.yaw
		z.pitch = -0.05
		ziel()
		await bild("50_fenster_" + t, 1.4)
		var bilder: Array[Image] = []
		for i in 5:
			await RenderingServer.frame_post_draw
			var b := get_viewport().get_texture().get_image()
			b.convert(Image.FORMAT_RGB8)
			bilder.append(b)
		var w := bilder[0].get_width()
		var h := bilder[0].get_height()
		var karte := Image.create(w, h, false, Image.FORMAT_RGB8)
		var viele := 0
		var n := 0
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var lo := 9.0
				var hi := 0.0
				for b in bilder:
					var l := b.get_pixel(x, y).get_luminance()
					lo = minf(lo, l)
					hi = maxf(hi, l)
				var dl := (hi - lo) * 255.0
				n += 1
				if dl > 3.0:
					viele += 1
				var v := clampf(dl * 12.0 / 255.0, 0.0, 1.0)
				karte.fill_rect(Rect2i(x, y, 2, 2), Color(v, v, v))
		karte.save_png(out.path_join("%s_51_fenster_%s_flackern.png" % [stand, t]))
		print("FENSTER %s %s: Punkte mit Änderung > 3 über fünf Bilder: %.2f %%" % [stand, t, 100.0 * viele / maxf(n, 1)])
		z.pos = Vector3(0.55, 0, dd * 0.5 + 0.3)
		z.pitch = -0.55
		ziel()
		await bild("52_fenster_nah_" + t, 1.4)
	# Schild am Fernseher: unter dem Bild, nie darauf.
	vor_tv(2.3)
	await bild("53_tv_schild", 1.6)


## Die Lichtkarten des sichtbaren Satzes: Mittel, kleinster und größter Wert, Deckkraft; als Bild
## (Reinhard, sRGB) neben die Probe.
func karten_zeigen(name: String) -> void:
	var b: Node = z.welt.get("backen")
	if b == null:
		print("KARTEN %s: kein Lichtbacken (Kompatibilität?)" % name)
		return
	var satz := int(b.get("_satz"))
	print("KARTEN %s %s: gebacken %d-mal, zuletzt %.0f ms, Satz %d" % [stand, name, int(b.get("gebacken")), float(b.get("letzte_ms")), satz])
	if satz < 0:
		return
	for e: Dictionary in (b.get("_saetze") as Array)[satz]:
		var img := (e.vp as SubViewport).get_texture().get_image()
		var summe := Vector3.ZERO
		var lo := 1e9
		var hi := 0.0
		var alpha := 0.0
		var n := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y)
				summe += Vector3(c.r, c.g, c.b)
				var l := c.get_luminance()
				lo = minf(lo, l)
				hi = maxf(hi, l)
				alpha += c.a
				n += 1
		print("KARTEN %s %s %s: %s Punkte, Ø %s, Helligkeit %.3f … %.3f, Deckkraft Ø %.2f, Format %d" % [stand, name, e.name, str(img.get_size()),
				str(summe / maxf(n, 1)), lo, hi, alpha / maxf(n, 1), img.get_format()])
		var vis := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var m := Color(c.r / (1.0 + c.r), c.g / (1.0 + c.g), c.b / (1.0 + c.b)).linear_to_srgb()
				vis.set_pixel(x, y, m)
		vis.save_png(out.path_join("%s_41_karte_%s_%s.png" % [stand, name, e.name]))
