extends Control
## „Dein Zimmer“ in der Einrichtung (setup_wizard_show.gd): ein echtes, kleines 3D-Zimmer
## (src/room/zimmer_welt.gd) in einer eigenen Ansicht. Gezeigt wird ein gemütliches Retro-Zimmer am
## Abend (retro_raum): Röhrenfernseher mit laufendem Spiel (_Spiel, eigenes Spiel im Stil der Zeit), die
## Konsolen der eigenen Systeme im Lowboard, Regale mit den eigenen Hüllen, Plattenspieler, Sofa,
## warme Lampen und eine Lichterkette. Drei Menschen aus dem PSX-Paket (figur/avatar.gd) sitzen
## zusammen auf dem Sofa, den Controller in der Hand, und spielen: Sie atmen, wippen leicht, schauen
## auf das Bild und ab und zu zueinander. Die Kamera gleitet ganz langsam. Mit einer Vorlage
## (vorlage, zimmer/vorlagen.gd) steht stattdessen deren Raum da, die Figuren auf dem ersten Sofa.
##
## Leistung: Gebaut wird erst, wenn die Szene im Baum ist; Bild und Fernseher rechnen höchstens FPS
## Bilder je Sekunde (sonst steht die Ansicht), die Ansicht rechnet in SKALA der Größe, Lampen ohne
## Schatten (Stufe „mittel“). Leichter Modus: Stufe „leicht“ und ein stilles Bild. Unsichtbar (Seite
## weg, Guide darüber) rechnet nichts; mit der Seite geht alles (queue_free, eigene Welt).

const U := preload("res://src/ui/u.gd")
const Welt := preload("res://src/room/zimmer_welt.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const G := preload("res://src/room/gestalt.gd")
const Avatar := preload("res://src/room/figur/avatar.gd")
const Bewohner := preload("res://src/room/figur/bewohner.gd")
const Leicht := preload("res://src/core/leicht.gd")

const FPS := 30.0
## Die Ansicht rechnet in diesem Anteil der Größe (das Bild wird weich hochgezogen).
const SKALA := 0.75
## Wer auf dem Sofa sitzt (figur_daten.gd PERSONEN): zwei Frauen und ein Mann.
const FIGUREN := ["mia", "noah", "zoe"]
## Sitzplätze auf dem Sofa (x im Möbel, Meter).
const PLAETZE := [-0.62, 0.0, 0.62]
## Sitzmöbel für je eine Figur (ohne Sofa im Raum).
const SITZE := ["sessel", "sessel_samt", "ohrensessel", "sitzsack", "pouf", "gamingstuhl"]

var vorlage := ""                 ## "" = das Retro-Zimmer (retro_raum)
var _vp: SubViewport
var _welt: Welt
var _figuren: Array = []
var _spiel: Control
var _t := 0.0
var _takt := 0.0
var _r := 18
var _blick: Array = []            ## je Figur: [Ziel (0 Fernseher, ±1 Nachbar), bis wann]
var _kam_ziel := Vector3.ZERO
var _kam_ort := Vector3.ZERO


func setup(v: String) -> Control:
	vorlage = v
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_r = maxi(8, UzTheme.r_panel() - 4)
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(Color("#0c0b10"), 0 if Leicht.active else _r))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(clip)
	add_child(clip)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.stretch_shrink = 1
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(svc)
	clip.add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.audio_listener_enable_3d = false
	_vp.positional_shadow_atlas_size = 0
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_vp.scaling_3d_scale = SKALA
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	svc.add_child(_vp)
	_bauen()
	# Ein ruhiger Schleier unten und oben: Titel und Kapitel darüber bleiben lesbar.
	var schleier := _Schleier.new()
	U.full_rect(schleier)
	clip.add_child(schleier)


func _bauen() -> void:
	var raum := Vorlagen.raum(vorlage) if vorlage != "" else Daten.pruefe_raum(retro_raum())
	if raum.is_empty():
		raum = Daten.pruefe_raum(retro_raum())
	var daten := Daten.laden()
	Katalog.eigene_setzen(daten.get("eigene", []))
	_welt = Welt.new()
	_welt.huellen = daten.get("huellen", {})
	_vp.add_child(_welt)
	_welt.bauen(raum, "leicht" if Leicht.active else "mittel")
	_fernseher()
	_sofa_besetzen()
	_kamera_lage()
	_kamera(0.0)
	_bild(0.0)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if Leicht.active or U.reduziert():
		# Still: einmal nach dem Einschwingen der Posen (und dem Laden der Hüllen) ein Bild.
		set_process(false)
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if is_instance_valid(_vp):
				_bild(0.0)
				_vp.render_target_update_mode = SubViewport.UPDATE_ONCE)


## Das Retro-Zimmer: Holzpaneel und gestreifte Tapete, Teppichboden, Röhrenfernseher auf Kufen mit
## Lichterkette darüber, links und rechts die Spieleregale, Plattenspieler, Sofa mit Teppich davor,
## Steh- und Tischlampe, Pflanzen und Bilder; Abendlicht, warm.
static func retro_raum() -> Dictionary:
	var m := func(t: String, x: int, z: int, r := 0, v := "", extra := {}) -> Dictionary:
		var it := { "t": t, "x": x, "z": z, "r": r, "v": v if v != "" else Katalog.std_variante(t), "an": true }
		it.merge(extra, true)
		return it
	var r := G.std_raum()
	var w := {}
	for s in G.SEITEN:
		w[s] = { "m": "tapete", "f": "#56715f", "mu": "streifen", "mf": "#617d6a" }
	w["hinten"] = { "m": "paneel", "f": "#c9b48a", "mu": "", "mf": "#7a4a2e" }
	r.merge({
		"id": "einrichtung", "name": "Retro-Zimmer", "w": 11, "d": 10,
		"waende": w,
		"boden": { "a": "teppichboden", "f": "#7d4b3a", "f2": "" },
		"sockel": { "a": "hoch", "f": "#6b432c" },
		"decke": { "a": "balken", "f": "#d9ccb4" },
		"fenster": { "a": "sprossen", "g": 1, "v": "kurz", "vf": "#a8552f", "rf": "#efe6d6" },
		"tuer": { "a": "kassette", "f": "#7a4a2e", "p": "vorn", "gf": "messing" },
		"licht": { "z": "abend", "we": "klar", "st": "", "k": 2400, "h": 90, "lf": "", "fa": "#e7c27d" },
		"moebel": [
			m.call("teppich_rund", 3, 2, 0, "senf", { "mu": "karo", "mf": "#b0603c" }),
			m.call("medienwand", 3, 0, 0, "roehre", { "m": "kirsche", "be": "kufen" }),
			m.call("lichterkette", 3, 0, 0, "bunt"),
			m.call("spieleregal", 0, 0, 0, "walnuss", { "rg": { "da": "gemischt", "ab": true, "de": "viel" } }),
			m.call("spieleregal", 8, 0, 0, "walnuss", { "rg": { "da": "gemischt", "ab": true, "de": "viel" } }),
			m.call("pflanze", 10, 0, 0, "monstera"),
			m.call("plattenregal", 0, 3, 1, "kirsche"),
			m.call("plattenspieler", 0, 3, 1, "kirsche"),
			m.call("sofa", 3, 5, 2, "senf", { "m": "cord", "f": "#b9853a" }),
			m.call("beistelltisch", 2, 5, 0, "walnuss"),
			m.call("tischlampe", 2, 5, 0, "senf"),
			m.call("snackschale", 2, 4, 0),
			m.call("stehlampe", 10, 3, 0, "terrakotta"),
			m.call("sitzsack", 8, 2, 3, "terrakotta", { "mu": "punkte", "mf": "#f0e3a0" }),
			m.call("poster", 0, 6, 1, "wellen"),
			m.call("bild", 10, 4, 3, "sonne"),
			m.call("wanduhr", 9, 0, 0, "schwarz"),
			m.call("topfpflanze", 0, 4, 1, "kaktus"),
		],
	}, true)
	return r


## Im Fernseher läuft ein Spiel (_Spiel); er wirft sein Licht flimmernd in den Raum.
func _fernseher() -> void:
	var tvs: TextureRect = _welt.tv_spiel
	if tvs == null:
		return
	_spiel = _Spiel.new()
	_spiel.size = Vector2(640, 360)
	tvs.add_child(_spiel)
	tvs.visible = true
	tvs.modulate.a = 1.0
	_welt.tv_zeigen("", "", Color("#7fb0ff"))


## Drei Figuren auf das Sofa (je Sofa bis zu drei Plätze, sonst je Sessel oder Sitzsack einer),
## sitzend, mit Controller.
func _sofa_besetzen() -> void:
	var raum: Dictionary = _welt.raum
	var knoten: Array = _welt.knoten
	var plaetze: Array = []          ## [Knoten, x im Möbel, Art]
	for sofa in [true, false]:
		for i in mini((raum.moebel as Array).size(), knoten.size()):
			var t := str(raum.moebel[i].t)
			var ist_sofa := t.begins_with("sofa") or t == "schlafsofa"
			if ist_sofa != sofa or not (t in SITZE or ist_sofa) or not (knoten[i] as Node3D).has_meta("sitz"):
				continue
			if ist_sofa:
				var breite := float(Katalog.groesse_it(raum.moebel[i]).x) * Katalog.ZELLE
				for x in PLAETZE:
					plaetze.append([knoten[i], float(x) * clampf(breite / 2.0, 0.6, 1.3), t])
			else:
				plaetze.append([knoten[i], 0.0, t])
	for k in mini(FIGUREN.size(), plaetze.size()):
		var n: Node3D = plaetze[k][0]
		var a: Node3D = Avatar.new()
		_welt.add_child(a)
		a.call("bauen", { "person": str(FIGUREN[k]) })
		var sp: Vector3 = (n.get_meta("sitz", {}) as Dictionary).get("pos", Vector3.ZERO)
		a.global_transform = Transform3D(n.global_transform.basis.orthonormalized(), n.global_transform * Vector3(float(plaetze[k][1]), 0, sp.z - 0.07))
		a.set("sitz", true)
		a.set("spielt", true)
		a.set("sitz_hoehe", float(Bewohner.SITZ_HOEHE.get(str(plaetze[k][2]), 0.45)))
		a.set("blick_an", true)
		# Gleich sitzen (ohne Hinsetzen beim Einblenden): die Gewichte einmal einschwingen.
		for j in 6:
			a.call("bild", 0.5)
		_figuren.append(a)
		_blick.append([0, 1.5 + k * 1.7])


## Kamera: hinten seitlich über dem Sofa, der Blick über die Schultern auf den Fernseher – Bild,
## Regale und die drei im Licht des Fernsehers.
func _kamera_lage() -> void:
	var raum: Dictionary = _welt.raum
	var w := float(raum.w) * Katalog.ZELLE
	var d := float(raum.d) * Katalog.ZELLE
	var tv: int = _welt.medienwand()
	var knoten: Array = _welt.knoten
	var tv_p := Vector3(w * 0.5, 0.8, 0.4)
	if tv >= 0 and is_instance_valid(knoten[tv]):
		tv_p = (knoten[tv] as Node3D).global_transform * Vector3(0, 0.75, 0)
	var sofa_p := tv_p + Vector3(0, 0, 2.6)
	if not _figuren.is_empty():
		sofa_p = ((_figuren[0] as Node3D).global_position + (_figuren[_figuren.size() - 1] as Node3D).global_position) * 0.5
	_kam_ziel = tv_p.lerp(sofa_p, 0.3) + Vector3(0, 0.05, 0)
	_kam_ort = Vector3(clampf(sofa_p.x + 1.25, 0.4, w - 0.35), 1.95, clampf(sofa_p.z + 1.9, 0.4, d - 0.2))


func _kamera(_dt: float) -> void:
	var cam: Camera3D = _welt.kamera
	var still := Leicht.active or U.reduziert()
	# Ganz langsam: ein paar Zentimeter seitwärts und auf und ab (wie eine ruhige Hand).
	var o := _kam_ort + (Vector3(0.0, 0.0, 0.0) if still else Vector3(sin(_t * 0.21) * 0.22, sin(_t * 0.17) * 0.05, cos(_t * 0.21) * 0.08))
	cam.fov = 36.0
	cam.global_transform = Transform3D(Basis(), o).looking_at(_kam_ziel + Vector3(sin(_t * 0.13) * 0.06, 0, 0), Vector3.UP)
	_welt.schnitt(o, true)


func _process(dt: float) -> void:
	if not is_instance_valid(_welt) or not is_visible_in_tree():
		return
	_takt += dt
	if _takt < 1.0 / FPS:
		return
	var schritt := minf(_takt, 0.1)
	_takt = 0.0
	_t += schritt
	_kamera(schritt)
	_bild(schritt)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Ein Bild der Figuren und des Fernsehers. Blicke: meist auf das Bild, ab und zu kurz zum Nachbarn.
func _bild(dt: float) -> void:
	var tv: int = _welt.medienwand()
	var knoten: Array = _welt.knoten
	var tv_p := Vector3.ZERO
	if tv >= 0 and is_instance_valid(knoten[tv]):
		tv_p = (knoten[tv] as Node3D).global_transform * Vector3(0, 0.78, 0)
	for k in _figuren.size():
		var a: Node3D = _figuren[k]
		var b: Array = _blick[k]
		if _t > float(b[1]):
			# Nach dem Blick zum Nachbarn wieder lange auf das Bild.
			var zum_nachbarn := int(b[0]) == 0 and absi(hash(Vector2i(k, int(_t)))) % 3 == 0
			b[0] = (1 if k == 0 else -1) if zum_nachbarn else 0
			b[1] = _t + (1.1 if zum_nachbarn else 3.5 + float(absi(hash(Vector2i(k, int(_t * 7.0)))) % 30) * 0.1)
		var ziel := tv_p
		var nb := k + int(b[0])
		if int(b[0]) != 0 and nb >= 0 and nb < _figuren.size():
			ziel = (_figuren[nb] as Node3D).call("kopf_mitte")
		a.set("blick_auf", ziel)
		a.call("bild", dt)
	if is_instance_valid(_spiel):
		_spiel.set("t", _t)
		_spiel.queue_redraw()
		var tvv: SubViewport = _welt.tv_vp
		if tvv:
			tvv.render_target_update_mode = SubViewport.UPDATE_ONCE
		# Das Licht des Fernsehers flimmert mit dem Bild.
		_welt.tv_flimmern(0.86 + 0.14 * absf(sin(_t * 2.3) * sin(_t * 5.1 + 1.0)))


## Leiser Schleier oben (unter den Kapiteln) und unten: im Akzent kaum, sonst Tiefe.
class _Schleier extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var dunkel := Color(0.03, 0.025, 0.04)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h * 0.22), Vector2(0, h * 0.22)]),
				PackedColorArray([Color(dunkel, 0.55), Color(dunkel, 0.35), Color(dunkel, 0.0), Color(dunkel, 0.0)]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.72), Vector2(w, h * 0.72), Vector2(w, h), Vector2(0, h)]),
				PackedColorArray([Color(dunkel, 0.0), Color(dunkel, 0.0), Color(dunkel, 0.45), Color(dunkel, 0.45)]))


## Das Spiel im Fernseher: ein eigenes kleines Jump-’n’-Run im Stil der Zeit (Bildpunkte, wenige
## Farben, keine Vorlage): Himmel in Bändern, Berge und Wolken im Gegenlauf, ein Weg aus Blöcken, drei
## kleine Helden in den Farben der Figuren laufen und springen über Lücken, Münzen blitzen, oben die
## Anzeige 1P 2P 3P. Gezeichnet in 160 × 90 Bildpunkten, vierfach groß (640 × 360).
class _Spiel extends Control:
	const PX := 4.0
	const W := 160
	const H := 90
	const HIMMEL := ["#2b1d52", "#3d2a6b", "#5a3a7e", "#8a4f86", "#c46a7c", "#ee9a6c"]
	const HELDEN := ["#ff6f91", "#5fd3ff", "#ffd36b"]
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _px(x: float, y: float, w: float, h: float, c: Color) -> void:
		draw_rect(Rect2(floorf(x), floorf(y), w, h), c)

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(PX, PX))
		# Himmel in Bändern (wie mit wenigen Farben gemalt).
		var bh := 9.0
		for i in HIMMEL.size():
			_px(0, i * bh, W, bh + 1, Color(str(HIMMEL[i])))
		_px(0, HIMMEL.size() * bh, W, H, Color("#ee9a6c"))
		# Sonne, halb hinter den Bergen.
		for i in 10:
			var dy := 9.0 - i
			var hw := sqrt(maxf(0.0, 81.0 - dy * dy))
			_px(118 - hw, 31 + i, hw * 2.0, 1, Color("#ffe3a3"))
		# Berge (langsam) und Hügel (schneller), darunter Wiese bis zum Weg.
		var fern := fposmod(t * 4.0, 64.0)
		for k in 4:
			var bx := k * 64.0 - fern
			for s in 17:
				_px(bx + 32 - s * 2, 40 + s, s * 4 + 2, 1, Color("#4a2f6e"))
		_px(0, 57, W, 13, Color("#4a2f6e"))
		var nah := fposmod(t * 10.0, 40.0)
		for k in 6:
			var hx := k * 40.0 - nah
			for s in 8:
				_px(hx + 20 - s * 3, 55 + s, s * 6 + 2, 1, Color("#2f5d5a"))
		_px(0, 62, W, 8, Color("#2f5d5a"))
		# Wolken.
		for k in 3:
			var wx := fposmod(k * 61.0 - t * 6.0, W + 30.0) - 20.0
			_px(wx, 14 + k * 7, 18, 3, Color(1, 1, 1, 0.85))
			_px(wx + 4, 11 + k * 7, 9, 3, Color(1, 1, 1, 0.85))
		# Weg aus Blöcken mit Lücken (alle 12 Blöcke eine).
		var lauf := t * 26.0
		var off := fposmod(lauf, 8.0)
		var erst := int(floorf(lauf / 8.0))
		for k in 22:
			var nr := erst + k
			if nr % 12 == 7:
				continue
			var gx := k * 8.0 - off
			_px(gx, 70, 8, 20, Color("#7b4a2e"))
			_px(gx, 70, 8, 2, Color("#7ccf5a"))
			_px(gx + 1, 74, 2, 2, Color("#5a321f"))
			_px(gx + 5, 80, 2, 2, Color("#5a321f"))
		# Münzen über den Lücken.
		for k in 22:
			var nr := erst + k
			if nr % 12 == 7:
				var cx := k * 8.0 - off + 2.0
				var blink := 0.6 + 0.4 * sin(t * 9.0 + nr)
				_px(cx, 50, 3, 4, Color(1.0, 0.85, 0.3, blink))
		# Drei Helden laufen, über jeder Lücke springen sie (nacheinander).
		for h in 3:
			var x := 34.0 + h * 15.0
			var welt_x := lauf + x + 3.0
			var bis := fposmod(welt_x / 8.0 - 7.0 + 1.6, 12.0)
			var y := 62.0
			if bis < 3.2:
				y -= sin(bis / 3.2 * PI) * 16.0
			var schritt := int(t * 10.0 + h) % 2
			var c := Color(str(HELDEN[h]))
			_px(x, y - 8, 6, 6, c)
			_px(x + 1, y - 10, 4, 2, c.darkened(0.3))
			_px(x + 4, y - 6, 1, 1, Color("#1a1028"))
			_px(x + (0 if schritt == 0 else 1), y - 2, 2, 2, Color("#1a1028"))
			_px(x + (4 if schritt == 0 else 3), y - 2, 2, 2, Color("#1a1028"))
		# Anzeige oben: 1P 2P 3P mit Herzen, rechts die Punkte.
		var f := ThemeDB.fallback_font
		for h in 3:
			var hx := 4.0 + h * 30.0
			draw_string(f, Vector2(hx, 8), "%dP" % (h + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(str(HELDEN[h])))
			for q in 3:
				_px(hx + 12 + q * 4, 3, 3, 3, Color("#ff5d78") if q < 3 - (h % 2) else Color(1, 1, 1, 0.3))
		draw_string(f, Vector2(118, 8), "%06d" % (int(t * 37.0) * 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 0.92))
		draw_set_transform(Vector2.ZERO)
