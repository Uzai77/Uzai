extends "res://src/room/zimmer_foto.gd"
## Dein Zimmer, Schicht über zimmer_foto.gd: Ansehen – Regal, Schrank und Plattenregal, ein Spiel
## aus dem Regal in die Konsole, das laufende Spiel im Fernseher (Stufe 2; eingelegt fährt die Kamera
## hinein und das Spiel liegt vorn, fernsehspiel.gd), Platte auflegen, und aus dem Ansehen heraus
## anpassen oder umräumen.

const Inhalt := preload("res://src/room/inhalt.gd")
const F := preload("res://src/room/formen.gd")
const Konsolen := preload("res://src/room/konsolen.gd")

var _zeit := 0.0

var _auszug := {}              ## Platz (Index in _ans_plaetze) → Auszug 0..1

var _schwarz: ColorRect

var _vor_modus := "laufen"     ## woher Anpassen, Rad und Baukasten kamen

var _spiel_voll: TextureRect    ## Spielbild bildschirmfüllend (Übergang Zimmer ↔ Spiel)
var _start_farbe := Color("#e7c27d")   ## Licht und Titel des Fernsehers, während das Spiel startet
var _start_titel := ""

## Platz vor dem Fernseher, solange das Spiel startet: Der Bildschirm füllt so viel der Bildbreite – ein
## schmaler Rand Zimmer bleibt drumherum, gleich geht es hinein (fernsehspiel.gd).
const TV_ANTEIL := 0.78
const TV_FOV := 50.0


# --- Ansehen: Regal, Schrank, Plattenregal --------------------------------------------------------

func _ansehen(i: int) -> void:
	_ans = i
	_ans_plaetze = (welt.plaetze.get(i, []) as Array).duplicate()
	_ans_plaetze.sort_custom(_platz_vor)
	# Ohne gemerkte Stelle: das Wichtigste zuerst (zuletzt gespielt, Platin, erste Platte).
	var erst := 0
	for k in _ans_plaetze.size():
		if int(_ans_plaetze[k].get("nr", 0)) < int(_ans_plaetze[erst].get("nr", 0)):
			erst = k
	_ans_sel = clampi(int(_ans_merk.get(i, erst)), 0, maxi(0, _ans_plaetze.size() - 1))
	_auszug.clear()
	modus = "ansehen"
	_rate = 3.2
	_glimmen_setzen(null)
	_ziel_zeigen()
	_platz_zeigen()
	_hinweise_auffrischen()


func _ansehen_schritt(cmd: String) -> void:
	if _ans_plaetze.is_empty():
		Sfx.play("bump")
		return
	var p := _platz()
	var neu := _ans_sel
	if cmd in ["left", "right"]:
		var d := -1 if cmd == "left" else 1
		var n := _ans_sel + d
		neu = n if n >= 0 and n < _ans_plaetze.size() and absf(float(_ans_plaetze[n].y) - float(p.y)) < 0.05 else _ans_sel
	else:
		# Nächstes Fach darüber bzw. darunter, an der x-Stelle, die am nächsten liegt.
		var best := -1
		var best_dy := 99.0
		var best_dx := 99.0
		for i in _ans_plaetze.size():
			var q: Dictionary = _ans_plaetze[i]
			var dy := float(q.y) - float(p.y)
			if (cmd == "up" and dy > 0.05) or (cmd == "down" and dy < -0.05):
				var ady := absf(dy)
				var dx := absf(float(q.x) - float(p.x)) + (float(q.get("tief", 0)) * 0.001)
				if ady < best_dy - 0.05 or (absf(ady - best_dy) <= 0.05 and dx < best_dx):
					best_dy = ady
					best_dx = dx
					best = i
		if best >= 0:
			neu = best
	if neu == _ans_sel:
		Sfx.play("bump")
		return
	_ans_sel = neu
	Sfx.play("move")
	_platz_zeigen()


func _ansehen_taste(cmd: String) -> bool:
	match cmd:
		"b":
			Sfx.play("back")
			_ansehen_ende()
			return true
		"a":
			var p := _platz()
			if p.is_empty():
				Sfx.play("bump")
				return true
			match str(p.art):
				"spiel":
					Sfx.play("select")
					_einlegen(p)
				"pokal":
					Sfx.play("select")
					main.open_game_achievements((p.daten as Dictionary).spiel)
				"platte":
					Sfx.play("select")
					_auflegen(p)
			return true
		"y":
			var p2 := _platz()
			if str(p2.get("art", "")) == "spiel":
				Sfx.play("open")
				main.open_game(p2.daten)
			return true
		"x":
			# Regal, Schrank oder Plattenregal einrichten: Seitenleiste neben dem Möbel.
			var i := _ans
			_ansehen_ende()
			_anpassen_auf(_seiten.seite_regal(i), i)
			return true
		"menu":
			# Spieleregal: ein- und ausräumen (dein Raster mit Covern).
			if _ans >= 0 and str(raum.moebel[_ans].t) == "spieleregal":
				var j := _ans
				_ansehen_ende()
				call("regal_einraeumen", j)
			return true
	return false


# --- Beim Laufen: Regal direkt (ohne eigenen Modus) ---------------------------------------------------

var _bp_raus: Array = []         ## [[Möbel, Platz, Auszug]] – was gerade heraus- bzw. zurückgleitet


## Schaust du beim Laufen auf ein Regal (Schrank, Plattenregal), springt die Wahl auf die Hülle, den
## Pokal oder die Platte, auf die dein Blick fällt: sie rückt ein Stück heraus, das Schild nennt sie,
## A spielt (zeigt die Erfolge, legt auf). Ein kleiner Vorsprung für die gewählte verhindert Flattern.
func _blick_platz(dt: float) -> void:
	var neu := {}
	var m := -1
	if modus == "laufen" and _ziel >= 0 and _ziel < (raum.moebel as Array).size() \
			and Katalog.nutzen(str(raum.moebel[_ziel].t)) in ["spiele", "pokale", "platten"]:
		m = _ziel
		neu = _platz_im_blick(m)
	if modus != "laufen":
		_bp_loslassen()
	if not is_same(neu, _bp):
		_bp = neu
		_bp_m = m
		if not neu.is_empty() and not _bp_raus.any(func(e: Array) -> bool: return is_same(e[1], neu)):
			_bp_raus.append([m, neu, 0.0])
		_ziel_zeigen()
		_hinweise_auffrischen()
	# Meist ist nichts herausgerückt: dann auch keine neue Liste je Bild.
	if _bp_raus.is_empty():
		return
	for e in _bp_raus:
		var soll := 1.0 if is_same(e[1], _bp) else 0.0
		e[2] = lerpf(float(e[2]), soll, 1.0 - exp(-dt * 11.0))
		if soll == 0.0 and float(e[2]) < 0.004:
			e[2] = 0.0
		if _platz_gilt(int(e[0]), e[1]):
			_platz_auszug(e[1], float(e[2]) * 0.85)
	_bp_raus = _bp_raus.filter(func(e: Array) -> bool: return float(e[2]) > 0.0 or is_same(e[1], _bp))


## Steht der Platz noch so im Möbel (nach einem Umbau des Inhalts sind es neue)?
func _platz_gilt(m: int, p: Dictionary) -> bool:
	if not (welt.plaetze.get(m, []) as Array).any(func(q: Dictionary) -> bool: return is_same(q, p)):
		return false
	return not p.has("knoten") or is_instance_valid(p.knoten)


## Alles, was beim Laufen herausgerückt ist, sofort zurück (ausser: dieser Platz bleibt, wie er ist).
func _bp_loslassen(ausser: Variant = null) -> void:
	for e in _bp_raus:
		if not is_same(e[1], ausser) and _platz_gilt(int(e[0]), e[1]):
			_platz_auszug(e[1], 0.0)
	_bp_raus.clear()
	if not _bp.is_empty():
		_bp = {}
		_bp_m = -1
		_ziel_zeigen()
		_hinweise_auffrischen()


## Der Platz im Möbel m, der dem Blick am nächsten liegt (Winkel zur Blickrichtung), sonst {}.
func _platz_im_blick(m: int) -> Dictionary:
	var o := _augen()
	var r := _blickrichtung()
	var best := {}
	var best_w := 0.42
	var jetzt_w := INF
	for p: Dictionary in welt.plaetze.get(m, []):
		var v: Vector3 = (_platz_lage(p, m)[0] as Vector3) - o
		var t := v.dot(r)
		if t <= 0.15 or v.length() > REICHWEITE + 0.6:
			continue
		var w := (v - r * t).length() / t
		if is_same(p, _bp):
			jetzt_w = w
		if w < best_w:
			best_w = w
			best = p
	# Die gewählte bleibt, bis eine andere deutlich näher am Blick liegt.
	if jetzt_w < INF and jetzt_w < best_w * 1.25 + 0.01:
		return _bp
	return best


## A auf den Platz im Blick: spielen, Erfolge zeigen oder auflegen.
func _platz_nutzen(m: int, p: Dictionary) -> void:
	if p.is_empty() or not _platz_gilt(m, p):
		Sfx.play("bump")
		return
	_bp_loslassen(p)
	match str(p.art):
		"spiel":
			Sfx.play("select")
			_ans = m
			_einlegen(p)
			if modus == "laufen":
				_ans = -1
				_platz_auszug(p, 0.0)
		"pokal":
			Sfx.play("select")
			_platz_auszug(p, 0.0)
			main.open_game_achievements((p.daten as Dictionary).spiel)
		"platte":
			Sfx.play("select")
			_platz_auszug(p, 0.0)
			_auflegen(p)


func _ansehen_ende() -> void:
	modus = "laufen"
	_rate = 3.0
	_info_weg()
	_ans = -1
	_ziel = -2
	_ziel_suchen()
	_hinweise_auffrischen()


## Gewählte Hülle zieht ein Stück heraus, Pokale heben sich und drehen langsam, Platten kippen vor.
func _ansehen_bild(dt: float) -> void:
	for i in _ans_plaetze.size():
		var soll := 1.0 if i == _ans_sel else 0.0
		var ist := float(_auszug.get(i, 0.0))
		if soll == 0.0 and ist < 0.001:
			continue
		ist = lerpf(ist, soll, 1.0 - exp(-dt * 11.0))
		if soll == 0.0 and ist < 0.002:
			ist = 0.0
		_auszug[i] = ist
		_platz_auszug(_ans_plaetze[i], ist)


func _platz_auszug(p: Dictionary, v: float) -> void:
	match str(p.art):
		"spiel":
			if p.has("mm"):
				var t: Transform3D = p.basis
				(p.mm as MultiMesh).set_instance_transform(int(p.index), Transform3D(t.basis, t.origin + Vector3(0, 0.006 * v, 0.06 * v)))
				if p.has("schild") and is_instance_valid(p.schild):
					var st: Transform3D = p.schild_basis
					(p.schild as Node3D).transform = Transform3D(st.basis, st.origin + Vector3(0, 0.006 * v, 0.06 * v))
			else:
				(p.knoten as Node3D).transform = (p.basis as Transform3D).translated_local(Vector3(0, 0.01 * v, 0.07 * v))
		"pokal":
			var b: Transform3D = p.basis
			(p.knoten as Node3D).transform = Transform3D(b.basis * Basis(Vector3.UP, sin(_zeit * 0.9) * 0.5 * v), b.origin + Vector3(0, 0.02 * v, 0.04 * v))
		"platte":
			if p.has("ruecken"):
				var b3: Transform3D = p.basis
				(p.knoten as Node3D).transform = Transform3D(b3.basis, b3.origin + Vector3(0, 0.01 * v, 0.12 * v))
				return
			# Kippt um ihre Unterkante nach vorn, wie beim Blättern in einer Kiste.
			var b2: Transform3D = p.basis
			(p.knoten as Node3D).transform = Transform3D(b2.basis * Basis(Vector3.RIGHT, 0.5 * v), b2.origin + Vector3(0, 0.0, 0.05 * v))


# --- Spielen: aus dem Regal in die Konsole -----------------------------------------------------------

func _einlegen(p: Dictionary) -> void:
	var g: Dictionary = p.daten
	if not Library.is_installed(g) or Launcher.in_game:
		main.launch(g)
		return
	modus = "fahrt"
	_info_weg()
	_hinweise_auffrischen()
	var cam: Camera3D = welt.kamera
	var tv := welt.medienwand()
	# Die Hülle (bzw. das Modul) als eigenes Stück, das aus dem Regal kommt.
	var stueck := MeshInstance3D.new()
	stueck.mesh = F.kiste(Inhalt.mass_von(g, welt.huellen), 0.0025, false, 2)
	stueck.material_override = S.lack(S.huellen_farbe(g), 0.35, 0.5)
	welt.add_child(stueck)
	if p.has("mm") or p.has("knoten"):
		var l := _platz_lage(p)
		stueck.global_transform = Transform3D(Basis.looking_at(-(l[1] as Vector3), Vector3.UP), l[0])
		if p.has("mm"):
			(p.mm as MultiMesh).set_instance_transform(int(p.index), Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			if p.has("schild") and is_instance_valid(p.schild):
				(p.schild as Node3D).visible = false
		elif p.has("knoten"):
			(p.knoten as Node3D).visible = false
	else:
		stueck.global_transform = cam.global_transform.translated_local(Vector3(0.0, -0.25, -0.6))
	welt.tv_zeigen(tr("Startet …"), Library.display_title(g), S.huellen_farbe(g).lightened(0.3))
	# Der Fernseher schaltet sich ein, während die Hülle zur Konsole fliegt.
	welt.tv_einschalten(0.7)
	# Ein Klang, eine Bedeutung: „launch“ (mit Impuls) gehört dem echten Spielstart, der danach kommt.
	Sfx.play("open")
	var tw := create_tween().set_parallel(true)
	if tv >= 0:
		var n: Node3D = welt.knoten[tv]
		# Läuft das Spiel auf einer Konsole im Lowboard (konsolen.gd), fliegt die Hülle dorthin; dort
		# geht der Deckel bzw. die Lade auf, Disc oder Modul hinein, zu, die LED an.
		var konsole := welt.konsole_fuer(g)
		var ziel: Vector3 = (n.get_meta("schlitz") as Node3D).global_position if n.has_meta("schlitz") else n.global_transform * Vector3(0, 0.3, 0.1)
		var start := Transform3D()
		if konsole != null:
			start = Konsolen.start_ort(konsole)
			ziel = start.origin
		var vorn := n.global_transform.basis.z.normalized()
		# Kamera schaut auf die Konsole, die Hülle fliegt hinüber und gleitet in den Schlitz.
		var blick_o := ziel + vorn * (0.8 if konsole != null else 1.05) + Vector3(0, 0.42 if konsole != null else 0.55, 0)
		tw.tween_property(cam, "global_transform", Transform3D(Basis(), blick_o).looking_at(ziel + Vector3(0, 0.06 if konsole != null else 0.2, 0), Vector3.UP),
				0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(cam, "fov", 52.0, 0.85).set_trans(Tween.TRANS_CUBIC)
		var ueber := ziel + Vector3(0, 0.11, 0)
		tw.tween_method(func(t: float) -> void:
			var a := stueck.global_position
			stueck.global_position = a.lerp(ueber, t * t)
			stueck.global_transform.basis = stueck.global_transform.basis.slerp(Basis(n.global_transform.basis.get_rotation_quaternion()), t).orthonormalized()
		, 0.0, 1.0, 0.85).set_trans(Tween.TRANS_SINE)
		if konsole != null:
			Konsolen.oeffnen(self, konsole, 0.85 - U.T_RAUM)
			tw.chain().tween_property(stueck, "scale", Vector3(0.2, 0.2, 0.2), U.T_ORT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			await tw.finished
			if not is_inside_tree():
				return
			stueck.visible = false
			var medium := Konsolen.medium_bauen(konsole, S.huellen_farbe(g))
			if medium != null:
				welt.add_child(medium)
				medium.global_transform = start
			await Konsolen.einlegen(self, konsole, medium).finished
		else:
			tw.chain().tween_property(stueck, "global_position", ziel - Vector3(0, 0.06, 0), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(stueck, "scale", Vector3(1, 0.3, 1), 0.32)
			if n.has_meta("konsole_licht"):
				var licht: StandardMaterial3D = n.get_meta("konsole_licht")
				tw.chain().tween_property(licht, "emission_energy_multiplier", 6.0, 0.16)
				tw.chain().tween_property(licht, "emission_energy_multiplier", 1.4, 0.3)
			await tw.finished
		if not is_inside_tree():
			return
		stueck.visible = false
		if Config.is_windows() or Library.demo:
			await _einlegen_fernseher(g, stueck)
			return
		# In den Fernseher hinein: die Kamera fährt an den Bildschirm, das Bild wird hell, dann schwarz.
		var bs: MeshInstance3D = n.get_meta("bildschirm")
		var bmitte := bs.global_position
		var bvorn := bs.global_transform.basis.z.normalized()
		var tw2 := create_tween().set_parallel(true)
		tw2.tween_property(cam, "global_transform", Transform3D(Basis(), bmitte + bvorn * 0.42).looking_at(bmitte, Vector3.UP), 1.0).set_trans(
				Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		tw2.tween_property(cam, "fov", 38.0, 1.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		tw2.tween_method(func(h: float) -> void: (bs.material_override as ShaderMaterial).set_shader_parameter("hell", h), 1.0, 2.4, 1.0)
		tw2.tween_property(_schwarz, "color:a", 1.0, 0.45).set_delay(0.6)
		await tw2.finished
	else:
		var tw3 := create_tween().set_parallel(true)
		tw3.tween_property(stueck, "global_position", cam.global_position + cam.global_transform.basis * Vector3(0, -0.1, -0.35), 0.6)
		tw3.tween_property(_schwarz, "color:a", 1.0, 0.5).set_delay(0.3)
		await tw3.finished
	if not is_inside_tree():
		return
	main.set_meta("zimmer_zurueck", true)
	# Hat der Launcher nicht übernommen (Spiel läuft schon), geht es danach im Zimmer weiter. Über
	# eine Verbindung statt await: beim Spielstart schließt main das Zimmer (dann fällt sie weg).
	get_tree().create_timer(0.8).timeout.connect(_nicht_gestartet.bind(stueck))
	main.launch(g)


## Eingelegt: Die Kamera setzt sich vor den Fernseher, das Spiel startet; ist sein Fenster da, fährt
## sie hinein und das Spiel liegt vorn (ins_spiel, fernsehspiel.gd).
func _einlegen_fernseher(g: Dictionary, stueck: Node3D) -> void:
	_start_farbe = S.huellen_farbe(g).lightened(0.3)
	_start_titel = Library.display_title(g)
	await _zum_fernseher(0.9)
	if not is_inside_tree() or _closing:
		return
	await main.launch(g, true)
	if not is_inside_tree() or _closing:
		return
	if str(main.tv_zustand()) == "" and not Launcher.in_game:
		_nicht_gestartet(stueck)
	elif is_instance_valid(stueck):
		stueck.queue_free()


func _nicht_gestartet(stueck: Node3D) -> void:
	if not is_inside_tree() or _closing:
		return
	main.remove_meta("zimmer_zurueck")
	if is_instance_valid(stueck):
		stueck.queue_free()
	welt.inhalt_fuellen()
	welt.konsolen_strom()
	U.tw(_schwarz, "uz_zimmer_ein").tween_property(_schwarz, "color:a", 0.0, 0.4)
	if modus == "fernsehen":
		_fernsehen_ende()
	welt.tv_auffrischen()
	modus = "laufen"
	_ans = -1
	_rate = 3.0
	_hinweise_auffrischen()


# --- Stufe 2: das laufende Spiel im Fernseher -----------------------------------------------------

## Ist der Fernseher gerade zu sehen? Nur dann holt spielbild.gd neue Bilder (spart Arbeit im Spiel) –
## nie, solange das Zimmer hinter dem Spiel wartet (ruhen).
func _tv_im_bild() -> bool:
	if not is_inside_tree() or _closing or not visible or (Nav.top_layer() != self and modus != "fahrt"):
		return false
	var tv := welt.medienwand()
	if tv < 0 or not (welt.knoten[tv] as Node3D).has_meta("bildschirm"):
		return false
	var bs: MeshInstance3D = (welt.knoten[tv] as Node3D).get_meta("bildschirm")
	var cam := welt.kamera
	var m := bs.global_position
	return cam.is_position_in_frustum(m) and (cam.global_position - m).dot(bs.global_transform.basis.z) > 0.0


## Wo du den Ton hörst (raumton.gd): beim Blick von oben am Kopf der Figur (in ihre Richtung), sonst
## an der Kamera.
func _hoerer() -> Transform3D:
	if blick == "oben" and modus in ["laufen", "ansehen", "sitzen"]:
		return Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, AUGEN, 0))
	return welt.kamera.global_transform


## Woher der Ton kommt: der Bildschirm des Fernsehers in diesem Raum (null: keiner da).
func _ton_quelle() -> Variant:
	var tv := welt.medienwand()
	if tv < 0 or not is_instance_valid(welt.knoten[tv]):
		return null
	var k := welt.knoten[tv] as Node3D
	if k.has_meta("bildschirm") and is_instance_valid(k.get_meta("bildschirm")):
		return (k.get_meta("bildschirm") as Node3D).global_position
	return (welt.boxen[tv] as AABB).get_center()


## Spiel zu Ende, während das Zimmer offen ist: wieder das Uzai-Bild im Fernseher.
func _spiel_pruefen() -> void:
	var laeuft := Spielbild.spiel_laeuft()
	if laeuft == _spiel_lief:
		return
	_spiel_lief = laeuft
	welt.laeuft_titel = Spielbild.titel() if laeuft else ""
	welt.konsolen_strom()
	if laeuft:
		welt.tv_auffrischen()
		_spar_lage(_spiel_lage)
	else:
		welt.tv_live_aus()
		_spar_lage("")
		_spar_gemeldet = false
		# main holt die Startseite zurück, wenn das Spiel endet; das Zimmer liegt weiter darüber.
		_verstecke_shell(true)
	_kopf_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Kamera, bei der der Bildschirm des Fernsehers das ganze Bild füllt: [Transform3D, Blickwinkel,
## Ort kurz davor (für den Bogen der Fahrt)].
func _tv_voll(tv: int) -> Array:
	var bs: MeshInstance3D = (welt.knoten[tv] as Node3D).get_meta("bildschirm")
	var q := bs.mesh as QuadMesh
	var gt := bs.global_transform
	var bw := q.size.x * gt.basis.x.length()
	var bh := q.size.y * gt.basis.y.length()
	var vorn := gt.basis.z.normalized()
	var mitte := gt.origin
	var fov := 46.0
	var s := size if size.x > 0 else U.view_size()
	var asp := s.x / maxf(1.0, s.y)
	var t := tan(deg_to_rad(fov) * 0.5)
	# Füllen (nicht einpassen): genau so nah, dass der Bildschirm das Bild füllt – wie das Spielbild, das
	# darüber einblendet (kein Doppelbild beim Überblenden).
	var d := minf((bh * 0.5) / t, (bw * 0.5) / (t * asp))
	var ziel := Transform3D(Basis(), mitte + vorn * d).looking_at(mitte, Vector3.UP)
	var vor := mitte + vorn * clampf(d * 3.2, 1.3, 2.2) + Vector3(0, 0.08, 0)
	return [ziel, fov, vor]


## Eine Fahrt auf einem weichen Bogen (von → über „vor“ → nach): Ort als Bézier-Kurve, Blick und
## Blickwinkel gleiten mit. hinein: die Richtung dreht sich früh zum Ziel (beim Herausfahren spät).
func _bogen(von: Transform3D, von_fov: float, nach: Transform3D, nach_fov: float, vor: Vector3, dauer: float, hinein: bool, verzug := 0.0) -> Tween:
	var cam := welt.kamera
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var a := von.origin.lerp(vor, t)
		var b := vor.lerp(nach.origin, t)
		var dreh := smoothstep(0.0, 0.7, t) if hinein else smoothstep(0.3, 1.0, t)
		cam.global_transform = Transform3D(von.basis.slerp(nach.basis, dreh).orthonormalized(), a.lerp(b, t))
		cam.fov = lerpf(von_fov, nach_fov, t * t if hinein else 1.0 - (1.0 - t) * (1.0 - t))
	, 0.0, 1.0, dauer).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(verzug)
	return tw


## Hinein ins Spiel (A am Fernseher, Guide › Zum Spiel, eingelegt: ins_spiel): Die Kamera fährt in den
## Bildschirm, am Ende liegt das Spielbild bildschirmfüllend darüber – dann holt main das Spiel randlos
## nach vorn (zimmer_zum_spiel), genau an derselben Stelle: kein Schnitt.
func zum_spiel() -> void:
	if modus == "fahrt" or _closing:
		return
	if modus == "foto":
		_foto_aus()
	if not _halten.is_empty():
		_ablegen_abbrechen()
	welt.raster.visible = false
	if modus == "anpassen":
		_ui.schliessen(true)
	modus = "fahrt"
	_info_weg()
	_glimmen_setzen(null)
	_ziel_zeigen()
	_kopf_auffrischen()
	_hinweise_auffrischen()
	spielbild.sofort(true)
	Sfx.play("select")
	var tv := welt.medienwand()
	var cam := welt.kamera
	var hat_bild := spielbild.letztes != null
	_spiel_voll.modulate.a = 0.0
	_spiel_voll.visible = hat_bild
	if tv >= 0:
		var v := _tv_voll(tv)
		welt.fokus(3.0, 8.0, 0.0)
		var tw := _bogen(cam.global_transform, cam.fov, v[0], float(v[1]), v[2], 1.25, true)
		var deck := create_tween()
		deck.tween_interval(1.08)
		if hat_bild:
			# Erst jetzt das Bild nehmen: Unterwegs kam meist schon das große, frische.
			deck.tween_callback(func() -> void:
				if spielbild.letztes:
					_spiel_voll.texture = ImageTexture.create_from_image(spielbild.letztes))
			deck.tween_property(_spiel_voll, "modulate:a", 1.0, 0.17).set_trans(Tween.TRANS_SINE)
		else:
			deck.tween_property(_schwarz, "color:a", 1.0, 0.3)
		await tw.finished
		if deck.is_running():
			await deck.finished
	else:
		if hat_bild:
			_spiel_voll.texture = ImageTexture.create_from_image(spielbild.letztes)
		var tw2 := create_tween()
		tw2.tween_property(_spiel_voll if hat_bild else _schwarz, "modulate:a" if hat_bild else "color:a", 1.0, 0.4)
		await tw2.finished
	if not is_inside_tree() or _closing:
		return
	main.zimmer_zum_spiel(self)


## Das Spielfenster ist da (im Zimmer eingelegt, main_fenster.gd _tv_einsteigen): Erst zeigt der
## Fernseher das Spiel (höchstens 1 s aufs erste Bild warten), dann fährt die Kamera hinein (zum_spiel).
func ins_spiel() -> void:
	while modus == "fahrt" and is_inside_tree() and not _closing:
		await get_tree().process_frame
	if not is_inside_tree() or _closing:
		return
	spielbild.sofort(true)
	var t0 := Time.get_ticks_msec()
	while spielbild.letztes == null and Time.get_ticks_msec() - t0 < 1000 and is_inside_tree():
		await get_tree().process_frame
	if is_inside_tree() and not _closing:
		zum_spiel()


## Zurück aus dem Spiel (Guide-Taste im Vollbild, Guide › Dein Zimmer, Spielende): die Rückfahrt von
## zum_spiel. Die Kamera beginnt im Fernseher und fährt heraus an deinen Platz. Bis das erste frische
## Bild des Spiels da ist (höchstens 0,8 s), bleibt die 3D-Ansicht durchsichtig – dahinter liegt das
## Spiel selbst (Uzai durchsichtig darüber), kein Schwarz; dann deckt das Bild genau, was eben zu sehen
## war, und geht in den Fernseher über. Kam keins, blendet das Zimmer weich über.
func aus_dem_spiel() -> void:
	var tv := welt.medienwand()
	ruhen(false)
	if modus in ["spiel", "fahrt", "fernsehen"]:
		modus = "laufen"
	var soll := _kamera_soll()
	modus = "fahrt"
	_info_weg()
	_kopf_auffrischen()
	_hinweise_auffrischen()
	_schwarz.color.a = 0.0
	_spiel_voll.visible = false
	svc.modulate.a = 0.0
	if tv < 0:
		welt.kamera.global_transform = soll[0]
		welt.kamera.fov = float(soll[1])
		await U.tw(svc, "uz_zimmer_ein").tween_property(svc, "modulate:a", 1.0, U.T_RAUM).finished
	else:
		var v := _tv_voll(tv)
		welt.kamera.global_transform = v[0]
		welt.kamera.fov = float(v[1])
		welt.fokus(3.0, 8.0, 0.0)
		spielbild.letztes = null
		spielbild.sofort(true)
		var t0 := Time.get_ticks_msec()
		while Spielbild.spiel_laeuft() and spielbild.letztes == null and Time.get_ticks_msec() - t0 < 800 and is_inside_tree():
			await get_tree().process_frame
		if not is_inside_tree() or _closing:
			return
		var tw_bild := create_tween()
		if spielbild.letztes:
			welt.tv_live(spielbild.letztes, true)
			_spiel_voll.texture = ImageTexture.create_from_image(spielbild.letztes)
			_spiel_voll.modulate.a = 1.0
			_spiel_voll.visible = true
			svc.modulate.a = 1.0
			tw_bild.tween_interval(0.12)
			tw_bild.tween_property(_spiel_voll, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_SINE)
			tw_bild.tween_callback(func() -> void: _spiel_voll.visible = false)
		else:
			tw_bild.tween_property(svc, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
		await _bogen(v[0], float(v[1]), soll[0], float(soll[1]), v[2], 1.4, false, 0.4).finished
	if not is_inside_tree() or _closing:
		return
	modus = "laufen"
	_rate = 30.0
	_ziel = -2
	_ziel_suchen()
	_kopf_auffrischen()
	_hinweise_auffrischen()


# --- Spiel im Fernseher (fernsehspiel.gd) -------------------------------------------------------------

## Platz vor dem Fernseher, genau von vorn (während das Spiel startet; von dort geht es gerade hinein):
## [Transform3D, Blickwinkel, Ort kurz davor].
func _tv_sitz(tv: int) -> Array:
	if tv < 0:
		var k := _kamera_soll()
		return [k[0], k[1], (k[0] as Transform3D).origin]
	var bs: MeshInstance3D = (welt.knoten[tv] as Node3D).get_meta("bildschirm")
	var s := size if size.x > 0 else U.view_size()
	return sitz_vor(bs.global_transform, (bs.mesh as QuadMesh).size, float(raum.w) * Katalog.ZELLE, float(raum.d) * Katalog.ZELLE,
			s.x / maxf(1.0, s.y))


## Rechnung dazu: gt und q beschreiben den Bildschirm (Mitte, Ausrichtung, Größe), w × tiefe den Raum.
## Abstand so, dass der Bildschirm TV_ANTEIL der Bildbreite füllt (höchstens 80 % der Höhe) – nie
## hinter der Wand gegenüber (dann eben näher).
static func sitz_vor(gt: Transform3D, q: Vector2, w: float, tiefe: float, asp: float) -> Array:
	var bw := q.x * gt.basis.x.length()
	var bh := q.y * gt.basis.y.length()
	var vorn := Vector3(gt.basis.z.x, 0.0, gt.basis.z.z).normalized()
	var t := tan(deg_to_rad(TV_FOV) * 0.5)
	var d := maxf(bw / (2.0 * TV_ANTEIL * t * asp), bh / (2.0 * 0.8 * t))
	var m := gt.origin
	var frei := 99.0
	if absf(vorn.x) > 0.01:
		frei = minf(frei, ((w - 0.15 if vorn.x > 0.0 else 0.15) - m.x) / vorn.x)
	if absf(vorn.z) > 0.01:
		frei = minf(frei, ((tiefe - 0.15 if vorn.z > 0.0 else 0.15) - m.z) / vorn.z)
	d = clampf(d, 0.6, maxf(0.6, frei))
	var o := m + vorn * d
	return [Transform3D(Basis(), o).looking_at(m, Vector3.UP), TV_FOV, m + vorn * (d + 0.5) + Vector3(0, 0.12, 0)]


## Kamera auf einem Bogen an den Platz vor dem Fernseher.
func _zum_fernseher(dauer := 1.0) -> void:
	var tv := welt.medienwand()
	if tv < 0:
		return
	modus = "fahrt"
	_info_weg()
	_glimmen_setzen(null)
	_ziel_zeigen()
	_kopf_auffrischen()
	_hinweise_auffrischen()
	var cam := welt.kamera
	var v := _tv_sitz(tv)
	var vor: Vector3 = (cam.global_position + (v[0] as Transform3D).origin) * 0.5 + Vector3(0, 0.12, 0)
	await _bogen(cam.global_transform, cam.fov, v[0], float(v[1]), vor, dauer, false).finished
	if is_inside_tree() and not _closing and modus == "fahrt":
		_nach_fahrt_fernsehen()


## Am Platz angekommen: „Startet …“ im Fernseher, bis das Spielfenster da ist (dann ins_spiel).
func _nach_fahrt_fernsehen() -> void:
	modus = "fernsehen"
	_kopf_auffrischen()
	_hinweise_auffrischen()


## main meldet jeden Wechsel (fernsehspiel.gd): Kamera, Hinweise und Live-Bild folgen.
func tv_wechsel(z: String) -> void:
	if not is_inside_tree() or _closing:
		return
	# Solange das Spiel läuft: schlanker Weg, Uzai nimmt sich zurück. Bildzeiten je Lage ins Log.
	_spar_lage(z)
	match z:
		"startet":
			if modus not in ["fahrt", "fernsehen"]:
				_zum_fernseher(1.0)
			welt.tv_zeigen(tr("Startet …"), _start_titel, _start_farbe)
		"zimmer":
			# Im Zimmer (zurück aus dem Spiel, Guide › Dein Zimmer): das Spiel läuft weiter, der Fernseher
			# zeigt es live (spielbild.gd), der Controller steuert die Figur.
			if modus == "fernsehen":
				_fernsehen_ende()
			spielbild.sofort()
			# Wie Uzais Fenster über dem Spiel liegt (nie genau bildschirmfüllend, siehe main_fenster.gd see_through).
			var fw := get_window()
			Launcher.log_launch("Fernseher: im Zimmer – das Spiel läuft weiter, der Controller steuert die Figur (Uzai: Fenster %d×%d über Bildschirm %d×%d, %s%s)"
					% [fw.size.x, fw.size.y, DisplayServer.screen_get_size(fw.current_screen).x, DisplayServer.screen_get_size(fw.current_screen).y,
					"durchsichtig" if fw.transparent else "deckend", ", immer oben" if fw.always_on_top else ""])
			_kopf_auffrischen()
			_hinweise_auffrischen()
			_mitlesen_hinweis()
		"":
			# Spiel aus, während das Zimmer dahinter wartete: Uzai kommt zurück, die Kamera aus dem Fernseher.
			if modus == "spiel":
				aus_dem_spiel()
				return
			if modus == "fernsehen":
				_fernsehen_ende()
			_kopf_auffrischen()
			_hinweise_auffrischen()


## Je Spiel einmal ehrlich: Im Zimmer hat Uzai den Fokus, aber XInput liest jedes Programm auch im
## Hintergrund – ein PC-Spiel, das das tut, sieht deine Schritte mit (fernsehspiel.gd). Emulatoren stellt
## Uzai dafür selbst ein (emu_hintergrund.gd), dort kein Hinweis – außer der Emulator kann das Mitlesen
## nicht abschalten und hält deshalb an, bis du wieder spielst.
static var _mitlesen_gezeigt := {}


func _mitlesen_hinweis() -> void:
	if not Launcher.in_game:
		return
	var id := str(Launcher.current.get("id", ""))
	if _mitlesen_gezeigt.has(id):
		return
	if Launcher.hintergrund_anhalten:
		_mitlesen_gezeigt[id] = true
		Launcher.log_launch("Fernseher: im Zimmer – %s wartet, bis du wieder spielst (liest den Controller auch im Hintergrund)"
				% str(Launcher.current.get("title", "das Spiel")))
		Toasts.show_toast("Spiel pausiert", "Es läuft weiter, sobald du wieder spielst.", "pause", { "ms": 4500, "quiet": true })
		return
	if str(Launcher.current.get("source", "")) == "rom":
		return
	_mitlesen_gezeigt[id] = true
	Toasts.show_toast("Du steuerst jetzt die Figur", "Manche PC-Spiele hören trotzdem mit. Zum Spielen: A am Fernseher.", "move", { "ms": 4500, "quiet": true })


## Was der Fernseher im Kontextmenü anbietet: läuft ein Spiel, hinein ins Spiel; sonst Weiterspielen;
## dazu die Art des Fernsehers zum Durchblättern.
func _tv_eintraege(i: int) -> Array:
	var e: Array = []
	if _spiel_lief:
		e.append({ "text": "Zum Spiel", "tun": zum_spiel, "hinweis": "Spielen" })
	else:
		var g := Library.get_game(str(Config.get_value("system.last_game", "")))
		if not g.is_empty():
			e.append({ "text": tr("Weiterspielen: %s") % Library.display_title(g), "roh": true, "hinweis": "Spielen",
				"tun": func() -> void: _einlegen({ "art": "spiel", "daten": g }) })
	var t := str(raum.moebel[i].t)
	var vs := Katalog.varianten(t)
	if vs.size() > 1:
		var ids: Array = vs.map(func(v: Array) -> String: return str(v[0]))
		var blaettern := func(d: int) -> void:
			call("_variante_setzen", i, str(ids[posmod(ids.find(str(raum.moebel[i].v)) + d, ids.size())]), true)
			Sfx.play("move")
		e.append({ "text": "Fernseher", "wert": func() -> String: return tr(Katalog.variante_name(t, str(raum.moebel[i].v))),
			"blaettern": blaettern })
	return e


## Zustandszeile des Starts (Launcher.state) im Fernseher.
func tv_status(text: String) -> void:
	welt.tv_zeigen(text, _start_titel, _start_farbe)


## Spiel aus (oder Start ging nicht): aufstehen, einen Schritt zurück, mit Blick auf den Fernseher.
func _fernsehen_ende() -> void:
	var cam := welt.kamera
	var tv := welt.medienwand()
	pos = _frei(Vector3(cam.global_position.x, 0.0, cam.global_position.z))
	pitch = -0.08
	if tv >= 0:
		var mitte := (welt.boxen[tv] as AABB).get_center()
		var weg := Vector3(pos.x - mitte.x, 0.0, pos.z - mitte.z)
		if weg.length() > 0.01:
			pos = _frei(Vector3(mitte.x, 0.0, mitte.z) + weg.normalized() * maxf(weg.length(), 2.3))
		var dir := mitte - pos
		yaw = atan2(-dir.x, -dir.z)
		pitch = clampf(atan2(mitte.y - AUGEN, Vector2(dir.x, dir.z).length()), -0.6, 0.2)
	_yaw_soll = yaw
	blick = "ich"
	modus = "laufen"
	_rate = 3.0
	_ziel = -2
	_ziel_suchen()
	_kopf_auffrischen()
	_hinweise_auffrischen()


# --- Platte auflegen ---------------------------------------------------------------------------------

func _auflegen(p: Dictionary) -> void:
	var e: Dictionary = p.daten
	var ps := welt.plattenspieler()
	if ps >= 0:
		var n: Node3D = welt.knoten[ps]
		var platte := MeshInstance3D.new()
		platte.mesh = F.walze(0.148, 0.004, 0.0015, 48)
		platte.material_override = S.lack(Color("#0f0f10"), 0.25, 0.55)
		welt.add_child(platte)
		var von := (p.knoten as Node3D).global_position + Vector3(0, 0.2, 0.05)
		platte.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), von)
		var teller: Node3D = n.get_meta("teller")
		var ziel := teller.global_position + Vector3(0, 0.03, 0)
		(n.get_meta("etikett") as MeshInstance3D).material_override = S.lack(e.farbe, 0.6, 0.3)
		var tw := create_tween().set_parallel(true)
		tw.tween_method(func(t: float) -> void:
			var bogen := von.lerp(ziel, t) + Vector3(0, sin(t * PI) * 0.35, 0)
			platte.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * (1.0 - t)), bogen)
		, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.chain().tween_callback(platte.queue_free)
	if (e.spielen as Callable).is_valid():
		e.spielen.call()
	_melden(tr("Läuft: %s") % str(e.name))


# --- Aus dem Ansehen heraus: anpassen und umräumen -----------------------------------------------

## Seitenleiste mit einer Seite öffnen; moebel: Index des Möbels, das die Kamera zeigt (-1 Raum).
func _anpassen_auf(seite: Dictionary, moebel: int) -> void:
	if besuch_sperre():
		return
	if seite.is_empty():
		Sfx.play("bump")
		return
	if modus != "anpassen":
		_vor_modus = modus if modus in ["laufen", "bauen"] else "laufen"
	modus = "anpassen"
	_anp_moebel = moebel
	_schritt_offen = true
	_rate = 3.0
	_glimmen_setzen(null)
	_ziel_zeigen()
	_info_weg()
	welt.raster.visible = false
	_ui.oeffnen(seite)
	Sfx.play("open")
	_kopf_auffrischen()
	_hinweise_auffrischen()
