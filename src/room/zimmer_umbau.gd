extends "res://src/room/zimmer_einrichten.gd"
## Dein Zimmer, Schicht über zimmer_einrichten.gd: umbauen beim Herumlaufen, ohne die Ansicht von
## oben – wie Möbelrücken bei Animal Crossing.
##
## - A halten auf einem Möbel nimmt es: es schwebt vor dir am Raster (das Feld darunter grün: passt,
##   rot: passt nicht), du läufst frei, LB/RB dreht, Y Farbe, A setzt ab, B stellt es zurück, X räumt
##   es weg. Große Möbel: die Kamera tritt in den Schulterblick zurück. Kurz A tut, was A immer tut.
## - „Ansehen“ (Y-Liste am Möbel): die Kamera umkreist es weich, Name, Farbe und Maß im Bild; Y Farbe,
##   X wegräumen (Rückgängig), A nimmt es, LB/RB und Steuerkreuz kreisen.
## - Raumgröße im Zimmer: A halten vor einer Wand (oder im Bauen Y auf der Wand) – das Steuerkreuz zieht
##   sie nach außen oder innen, live mit Geisterwand und Bodenstreifen; was an ihr steht, rückt mit, was
##   im Weg ist, wird rot. A übernimmt, B nimmt zurück. Die Kacheln „Raumgröße“ bleiben.
## - Im Spieleregal „Umstellen“ (Y-Menü, zimmer_regal.gd): die Hülle in der Hand (Platz, Fach, oben
##   drauf, stehend, liegend, Cover nach vorn); die anderen rücken nach. Kostet nichts, solange
##   niemand umstellt.

const HALTEN := 0.45                ## Sekunden: so lange gedrückt = nehmen statt benutzen (wie Nav.A_HOLD_MS)
const GROSS := 6                    ## Felder: ab hier tritt die Kamera beim Tragen zurück
const WAND_NAH := 2.2               ## so nah (m) an einer Wand zeigt das Schild „Raum größer/kleiner“
const LAGEN := ["stehend", "liegend", "vorn"]
const LAGE_NAMEN := { "stehend": "Stehend", "liegend": "Liegend", "vorn": "Cover nach vorn" }

var _a_druck := {}                  ## A gedrückt: { t0, modus, ziel, wand, bp, bp_m }
var _takt: Node                     ## schaut nach, ob A noch gehalten wird (nur dann aktiv)
var _lauf_tragen := false           ## trägt beim Laufen
var _blick_vorher := ""             ## Ansicht vor dem Tragen (große Möbel: Schulterblick)
var _ziel_wand := ""                ## Wand vor dir (nichts anderes im Blick)
var _betr := {}                     ## Ansehen: { i, winkel, von }
var _wz := {}                       ## Wand ziehen: { seite, delta, von, plan }
var _wz_knoten: Array = []          ## Geisterwand und Bodenstreifen
var _wz_rot: StandardMaterial3D
var _hand := {}                     ## Hülle in der Hand: { m, g, id, fach, k, lage, platz }
var _hand_knoten: Array = []        ## schwebende Hülle und Einfügemarke


class _Takt extends Node:
	var z: Node

	func _process(dt: float) -> void:
		z.call("_takt_bild", dt)


# --- Haken aus zimmer.gd (nav_command, nav_dir) und zimmer_basis.gd (Hinweise) ---------------------

## Tasten, die das Umbauen selbst erledigt (true: verbraucht).
func _umbau_taste(cmd: String) -> bool:
	if not _a_druck.is_empty():
		return cmd != "guide"
	if modus == "laufen" and _lauf_tragen:
		return _tragen_taste(cmd)
	match modus:
		"betrachten":
			return _betrachten_taste(cmd)
		"wand":
			return _wand_taste(cmd)
		"ansehen":
			if not _hand.is_empty():
				return _hand_taste(cmd)
		"laufen":
			if cmd == "a" and _halten.is_empty() and _halten_moeglich():
				if _ziel >= 0 and not _ziel_tier and not _ziel_fenster:
					_druck_start({ "ziel": _ziel })
					return true
				if _ziel < 0 and not _ziel_tier and not _ziel_fenster and _ziel_wand != "":
					_druck_start({ "wand": _ziel_wand })
					return true
	return false


## Steuerkreuz in den eigenen Zuständen (true: verbraucht).
func _umbau_dir(cmd: String) -> bool:
	match modus:
		"betrachten":
			_betr.winkel = float(_betr.winkel) + (0.6 if cmd == "left" else (-0.6 if cmd == "right" else 0.0))
			if cmd in ["up", "down"]:
				_betr.nah = clampf(float(_betr.get("nah", 1.0)) + (-0.15 if cmd == "up" else 0.15), 0.6, 1.6)
			Sfx.play("move")
			return true
		"wand":
			_wand_schritt(cmd)
			return true
		"ansehen":
			if not _hand.is_empty():
				_hand_schritt(cmd)
				return true
	return false


## Tastenzeile der eigenen Zustände ([]: zimmer_basis.gd entscheidet).
func _umbau_hinweise() -> Array:
	if modus == "laufen" and _lauf_tragen and not _halten.is_empty():
		var t := str(_halten.t)
		return bau_hinweise({ "tragen": true, "farben": Katalog.varianten(t).size(), "drehbar": Katalog.ebene(t) != "wand" })
	match modus:
		"betrachten":
			var h: Array = [["a", "Verschieben"]]
			var i := int(_betr.get("i", -1))
			if i >= 0 and i < (raum.moebel as Array).size() and Katalog.varianten(str(raum.moebel[i].t)).size() > 1:
				h.append(["y", "Farbe"])
			h.append(["x", "Wegräumen"])
			h.append(["b", "Zurück"])
			h.append(["lb", ""])
			h.append(["rb", "Umkreisen"])
			return h
		"wand":
			return [["a", "Übernehmen"], ["b", "Abbrechen"]]
		"ansehen":
			if not _hand.is_empty():
				return [["a", "Hinlegen"], ["b", "Zurück"], ["lb", ""], ["rb", tr(str(LAGE_NAMEN.get(str(_hand.lage), "")))]]
	return []


## Möbel, das beim Laufen nicht im Weg steht (getragen), sonst -1 (zimmer.gd _welt_quader).
func _quader_ohne() -> int:
	return _halten_idx if _lauf_tragen else -1


func _halten_moeglich() -> bool:
	return Input.is_action_pressed("uz_a", true) and not (_kontext and _kontext.offen())


# --- A halten: nehmen statt benutzen -----------------------------------------------------------------

func _druck_start(d: Dictionary) -> void:
	_a_druck = d
	_a_druck["t0"] = Time.get_ticks_msec()
	_a_druck["modus"] = modus
	if _takt == null:
		_takt = _Takt.new()
		_takt.z = self
		add_child(_takt)
	_takt.set_process(true)


## Je Bild, solange A gedrückt ist: losgelassen vor HALTEN – was A immer tut; gehalten – nehmen.
func _takt_bild(_dt: float) -> void:
	if _a_druck.is_empty():
		_takt.set_process(false)
		return
	var d := _a_druck
	var dauer := float(Time.get_ticks_msec() - int(d.t0)) / 1000.0
	if modus != str(d.modus):
		_a_druck = {}
		return
	if not Input.is_action_pressed("uz_a", true):
		_a_druck = {}
		if dauer < HALTEN:
			_tippen_a()
			_hinweise_auffrischen()
		return
	if dauer < HALTEN:
		return
	_a_druck = {}
	if d.has("wand"):
		_wand_ziehen_auf(str(d.wand))
	else:
		_tragen_start(int(d.ziel))
	_hinweise_auffrischen()


## A kurz gedrückt (nicht gehalten): was A beim Laufen immer tut (zimmer.gd _benutzen); das
## Spieleregal (zimmer_regal.gd) schaltet sich davor.
func _tippen_a() -> void:
	call("_benutzen")


# --- Tragen beim Laufen ------------------------------------------------------------------------------

func _tragen_start(i: int) -> void:
	if i < 0 or i >= (raum.moebel as Array).size():
		return
	_glimmen_setzen(null)
	_aufnehmen(i)
	_lauf_tragen = true
	welt.raster.visible = true
	var g := Katalog.groesse_it(_halten)
	if g.x * g.y >= GROSS and blick == "ich":
		_blick_vorher = blick
		blick = "schulter"
		_rate = 4.0
	_ziel = -1
	_tragen_folgen(true)
	_hinweise_auffrischen()


## Wo das Getragene hin soll: die Stelle am Boden unter dem Blick (nicht unter dir), sonst ein Stück
## vor dir; Wandmöbel an die Wand, auf die du schaust.
static func tragen_feld(o: Vector3, r: Vector3, p: Vector3, yaw_: float, g: Vector2i, w: int, d: int, an_wand: bool) -> Vector2i:
	var z := Katalog.ZELLE
	var vor := Vector2(-sin(yaw_), -cos(yaw_))
	var ziel := Vector2(p.x, p.z) + vor * (maxf(g.x, g.y) * z * 0.5 + 0.7)
	if an_wand:
		var f: Variant = blick_feld(o, r, w, d)
		if f is Vector2i and wand_an(f, w, d) != "":
			ziel = Vector2(((f as Vector2i).x + 0.5) * z, ((f as Vector2i).y + 0.5) * z)
	else:
		# Die Stelle am Boden, auf die du schaust: dort ist die Mitte des Möbels.
		if r.y < -0.05:
			var t := -o.y / r.y
			var h := o + r * t
			if t <= 6.0 and h.x >= 0.0 and h.z >= 0.0 and h.x < w * z and h.z < d * z:
				ziel = Vector2(h.x, h.z)
		# Nicht unter die eigenen Füße: mindestens so weit vor dir, wie das Möbel groß ist.
		var abstand := (ziel - Vector2(p.x, p.z)).dot(vor)
		var mind := maxf(g.x, g.y) * z * 0.5 + 0.35
		if abstand < mind:
			ziel += vor * (mind - abstand)
	var x := int(roundf(ziel.x / z - g.x * 0.5))
	var y := int(roundf(ziel.y / z - g.y * 0.5))
	return Vector2i(clampi(x, 0, maxi(0, w - g.x)), clampi(y, 0, maxi(0, d - g.y)))


func _tragen_folgen(sofort: bool) -> void:
	if _halten.is_empty():
		return
	var t := str(_halten.t)
	var g := Katalog.groesse_it(_halten)
	var an_wand := Katalog.ebene(t) == "wand"
	var c := tragen_feld(_augen(), _blickrichtung(), Vector3(pos.x, 0, pos.z), yaw, g, int(raum.w), int(raum.d), an_wand)
	if not sofort and c == Vector2i(int(_halten.x), int(_halten.z)):
		return
	_halten.x = c.x
	_halten.z = c.y
	cursor = c
	if an_wand:
		var rr := Daten.wand_drehung(raum, t, c.x, c.y, int(_halten.r))
		if rr >= 0:
			_halten.r = rr
	_getragen_zeigen()
	_raster_auffrischen()
	_ziel_zeigen()


func _tragen_taste(cmd: String) -> bool:
	match cmd:
		"a":
			_absetzen()
			if _halten.is_empty():
				_tragen_ende()
		"b":
			Sfx.play("back")
			_zurueckstellen()
			_tragen_ende()
		"x":
			_wegraeumen()
			_tragen_ende()
		"y":
			_farbe_wechseln()
		"lb", "rb":
			drehen(1 if cmd == "rb" else 3)
			_ziel_zeigen()
		"guide", "search":
			return false
		_:
			Sfx.play("bump")
	_hinweise_auffrischen()
	return true


func _tragen_ende() -> void:
	_lauf_tragen = false
	welt.raster.visible = false
	pos = _frei(pos)      # nie im eben Abgesetzten stehen
	if _blick_vorher != "":
		blick = _blick_vorher
		_blick_vorher = ""
	_ziel = -2
	_ziel_suchen()
	_ziel_zeigen()
	_hinweise_auffrischen()


# --- Ziel, Schild, Kamera --------------------------------------------------------------------------

## Beim Laufen: das Getragene folgt dem Blick; sonst wie immer, dazu die Wand vor dir.
func _ziel_suchen() -> void:
	if _lauf_tragen:
		_tragen_folgen(false)
		return
	super._ziel_suchen()
	var wand := ""
	if modus == "laufen" and blick != "oben" and _ziel < 0 and not _ziel_tier and not _ziel_fenster:
		wand = wand_vor(_augen(), _blickrichtung(), Vector3(pos.x, 0, pos.z), int(raum.w), int(raum.d))
	if wand != _ziel_wand:
		_ziel_wand = wand
		_ziel_zeigen()
		_hinweise_auffrischen()


## Die Wand, auf die du nah genug schaust („“: keine).
static func wand_vor(o: Vector3, r: Vector3, p: Vector3, w: int, d: int) -> String:
	var f: Variant = blick_feld(o, r, w, d)
	if not (f is Vector2i):
		return ""
	var seite := wand_an(f, w, d)
	var z := Katalog.ZELLE
	var abstand: float = { "hinten": p.z, "vorn": d * z - p.z, "links": p.x, "rechts": w * z - p.x }.get(seite, 99.0)
	return seite if seite != "" and abstand <= WAND_NAH else ""


func _schild_aktion() -> Array:
	if _kontext and _kontext.offen():
		return ["", "", false]
	match modus:
		"laufen":
			if _lauf_tragen and not _halten.is_empty():
				var t := str(_halten.t)
				if not Daten.passt(raum, _halten, _halten_idx):
					return [_moebel_name(t), tr("Hier ist kein Platz"), true]
				return [_moebel_name(t), "Absetzen", false]
			var s := super._schild_aktion()
			if _ziel >= 0 and not _ziel_tier and not _ziel_fenster and _ziel < (raum.moebel as Array).size():
				var halten := tr("Halten: Verschieben")
				if str(s[1]) == "":
					return [_moebel_name(str(raum.moebel[_ziel].t)), halten, false]
				return [s[0], tr(str(s[1])) + " · " + halten, s[2]]
			if _ziel < 0 and _ziel_wand != "":
				return [tr(str(G.SEITEN_NAMEN.get(_ziel_wand, ""))), tr("Halten: Raum größer/kleiner"), false]
			return s
		"betrachten", "wand":
			return ["", "", false]
		"ansehen":
			if not _hand.is_empty():
				return ["", "", false]
	return super._schild_aktion()


## Beim Tragen steht das Schild über dem Getragenen (Schulterblick; in der Ich-Ansicht wie immer
## unter dem Punkt in der Mitte).
func _schild_punkt() -> Variant:
	if _lauf_tragen and is_instance_valid(_halten_knoten):
		var b := welt.box_von(_halten_knoten)
		b.position += _halten_knoten.get_parent().global_position if _halten_knoten.get_parent() is Node3D else Vector3.ZERO
		return Vector3(b.get_center().x, b.end.y + 0.12, b.get_center().z)
	return super._schild_punkt()


func _kamera_soll() -> Array:
	match modus:
		"betrachten":
			return _betrachten_kamera()
		"wand":
			if str(_wz.get("von", "")) == "bauen":
				return _oben_kamera(_wand_mitte(str(_wz.seite), int(_wz.delta)), 0.6)
			return _wand_kamera()
		"ansehen":
			if not _hand.is_empty() and _hand.has("kamera"):
				return _hand.kamera
	return super._kamera_soll()


# --- Aktionen am Möbel (Y-Liste): Verschieben und Ansehen vorn --------------------------------------

func _aktionen_laufen() -> void:
	if _ziel < 0 and _ziel_wand != "" and not _ziel_tier and not _ziel_fenster:
		var seite := _ziel_wand
		_kontext_auf(tr(str(G.SEITEN_NAMEN.get(seite, ""))), [
			{ "text": "Raum größer/kleiner", "tun": func() -> void: _wand_ziehen_auf(seite) },
			{ "text": "Wand gestalten", "tun": func() -> void: _wand_gestalten_auf(seite) },
		], null)
		return
	super._aktionen_laufen()


func _wand_gestalten_auf(seite: String) -> void:
	bauen_an()
	wand_gestalten(seite)


## Einträge für die Liste am Möbel (zimmer_einrichten.gd _aktionen_laufen).
func _aktionen_vorn(i: int) -> Array:
	var e: Array = []
	e.append({ "text": "Verschieben", "tun": func() -> void: _tragen_start(i) })
	e.append({ "text": "Ansehen", "tun": func() -> void: betrachten(i) })
	return e


## Die Hülle in der Hand bleibt an ihrem alten Platz unsichtbar (nicht herausgleiten).
func _platz_auszug(p: Dictionary, v: float) -> void:
	if not _hand.is_empty() and str(p.get("art", "")) == "spiel" and str((p.daten as Dictionary).get("id", "")) == str(_hand.id):
		return
	super._platz_auszug(p, v)


# --- Ansehen: ein Möbel von nahem ------------------------------------------------------------------

func betrachten(i: int) -> void:
	if i < 0 or i >= welt.boxen.size():
		Sfx.play("bump")
		return
	var c := (welt.boxen[i] as AABB).get_center()
	var cam := welt.kamera.global_position
	_betr = { "i": i, "winkel": atan2(cam.x - c.x, cam.z - c.z), "nah": 1.0, "von": modus }
	modus = "betrachten"
	_rate = 2.6
	_glimmen_setzen(null)
	Sfx.play("open")
	_ziel_zeigen()
	_betrachten_info()
	_hinweise_auffrischen()


func _betrachten_info() -> void:
	var i := int(_betr.i)
	var it: Dictionary = raum.moebel[i]
	var t := str(it.t)
	var kat := str(Katalog.info(t).get("kat", ""))
	var kname := ""
	for k in Katalog.KATEGORIEN:
		if str(k[0]) == kat:
			kname = tr(str(k[1]))
	var g := Katalog.groesse_it(it)
	var teile: Array = []
	if Katalog.varianten(t).size() > 1:
		teile.append(tr(Katalog.variante_name(t, str(it.v))))
	teile.append("%s × %s m" % [_meter_text(g.x), _meter_text(g.y)])
	var st := Katalog.stufen(t)
	if not st.is_empty():
		teile.append(tr(str(st[Katalog.stufe_von(it)].name)))
	_info_zeigen(kname, _moebel_name(t), " · ".join(teile))


static func _meter_text(felder: int) -> String:
	var m := felder * Katalog.ZELLE
	return ("%d" % int(m)) if is_equal_approx(m, roundf(m)) else ("%.1f" % m).replace(".", ",")


## Die Kamera umkreist das Möbel weich (von selbst langsam, Steuerkreuz und LB/RB schneller), bleibt
## im Raum und unter der Decke.
func _betrachten_kamera() -> Array:
	var i := int(_betr.i)
	if i < 0 or i >= welt.boxen.size():
		return super._kamera_soll()
	var b: AABB = welt.boxen[i]
	var c := b.get_center()
	var r := maxf(maxf(b.size.x, b.size.z), b.size.y * 0.8) * 0.5
	_betr.winkel = float(_betr.winkel) + get_process_delta_time() * 0.16
	var dist := clampf(r * 2.6 + 0.6, 1.0, 4.2) * float(_betr.get("nah", 1.0))
	var o := c + Vector3(sin(float(_betr.winkel)), 0.0, cos(float(_betr.winkel))) * dist
	o.y = clampf(c.y + 0.3 + r * 0.45, 0.5, 2.45)
	var rand := 0.18
	o.x = clampf(o.x, rand, float(raum.w) * Katalog.ZELLE - rand)
	o.z = clampf(o.z, rand, float(raum.d) * Katalog.ZELLE - rand)
	return [Transform3D(Basis(), o).looking_at(c, Vector3.UP), 50.0, o.distance_to(c)]


func _betrachten_taste(cmd: String) -> bool:
	var i := int(_betr.i)
	match cmd:
		"b":
			Sfx.play("back")
			_betrachten_ende()
		"a":
			_betrachten_ende()
			_tragen_start(i)
		"y":
			var vs := Katalog.varianten(str(raum.moebel[i].t))
			if vs.size() < 2:
				Sfx.play("bump")
			else:
				var ids: Array = vs.map(func(p: Array) -> String: return str(p[0]))
				call("_variante_setzen", i, str(ids[(ids.find(str(raum.moebel[i].v)) + 1) % ids.size()]), true)
				Sfx.play("move")
				_betrachten_info()
		"x":
			_betrachten_ende()
			entfernen(i)
		"lb", "rb":
			_betr.winkel = float(_betr.winkel) + (0.8 if cmd == "lb" else -0.8)
			Sfx.play("move")
		"guide":
			return false
		_:
			Sfx.play("bump")
	return true


func _betrachten_ende() -> void:
	modus = "laufen"
	_rate = 3.0
	_info_weg()
	_betr = {}
	_ziel = -2
	_ziel_suchen()
	_hinweise_auffrischen()


# --- Raumgröße: eine Wand ziehen -----------------------------------------------------------------------

## Neue Raumgröße, wenn die Wand seite um delta Felder nach außen (+) bzw. innen (−) wandert: was an
## dieser Wand steht (und was darauf steht), wandert mit; bei der linken und hinteren Wand rückt der
## Rest in den Koordinaten nach. { raum, ok, blockiert: [Index], mit: [Index], w, d }.
static func wand_plan(r: Dictionary, seite: String, delta: int) -> Dictionary:
	var w := int(r.w)
	var d := int(r.d)
	var nw := w + (delta if seite in ["links", "rechts"] else 0)
	var nd := d + (delta if seite in ["hinten", "vorn"] else 0)
	var aus := { "ok": false, "blockiert": [], "mit": [], "w": nw, "d": nd, "raum": {} }
	if nw < Daten.MIN_FELDER or nw > Daten.MAX_FELDER or nd < Daten.MIN_FELDER or nd > Daten.MAX_FELDER:
		return aus
	var alt: Array = r.moebel
	var traeger := {}
	for i in alt.size():
		for j in Daten.darauf(r, i):
			traeger[j] = i
	var neu := r.duplicate(true)
	neu.w = nw
	neu.d = nd
	var liste: Array = []
	var mit: Array = []
	for i in alt.size():
		var q: int = traeger.get(i, i)
		var tr_: Dictionary = alt[q]
		var g := Katalog.groesse_it(tr_)
		var an := false
		match seite:
			"rechts": an = int(tr_.x) + g.x == w
			"vorn": an = int(tr_.z) + g.y == d
			"links": an = int(tr_.x) == 0
			"hinten": an = int(tr_.z) == 0
		var it: Dictionary = (alt[i] as Dictionary).duplicate(true)
		match seite:
			"rechts":
				if an:
					it.x = int(it.x) + delta
			"vorn":
				if an:
					it.z = int(it.z) + delta
			"links":
				if not an:
					it.x = int(it.x) + delta
			"hinten":
				if not an:
					it.z = int(it.z) + delta
		if an:
			mit.append(i)
		liste.append(it)
	neu.moebel = liste
	var blockiert: Array = []
	for i in liste.size():
		var it: Dictionary = liste[i]
		var g2 := Katalog.groesse_it(it)
		if int(it.x) < 0 or int(it.z) < 0 or int(it.x) + g2.x > nw or int(it.z) + g2.y > nd:
			blockiert.append(i)
			continue
		if Katalog.ebene(str(it.t)) == "wand":
			var rr := Daten.wand_drehung(neu, str(it.t), int(it.x), int(it.z), int(it.r), Katalog.stufe_von(it))
			if rr < 0:
				blockiert.append(i)
				continue
			it.r = rr
		if not Daten.passt(neu, it, i):
			blockiert.append(i)
	aus.ok = blockiert.is_empty()
	aus.blockiert = blockiert
	aus.mit = mit
	aus.raum = neu
	return aus


func _wand_ziehen_auf(seite: String) -> void:
	if seite == "":
		return
	_wz = { "seite": seite, "delta": 0, "von": modus, "plan": wand_plan(raum, seite, 0) }
	if modus == "bauen":
		_wand = ""
	modus = "wand"
	_glimmen_setzen(null)
	Sfx.play("open")
	_wand_geist()
	_wand_vorschau()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Außen-Richtung einer Wand (in Feldern).
static func wand_aussen(seite: String) -> Vector2i:
	return { "hinten": Vector2i(0, -1), "vorn": Vector2i(0, 1), "links": Vector2i(-1, 0), "rechts": Vector2i(1, 0) }.get(seite, Vector2i.ZERO)


## Steuerkreuz → nach außen (+1) oder innen (−1), so wie es auf dem Bildschirm aussieht.
func _wand_schritt(cmd: String) -> void:
	var az := _oben_az if str(_wz.von) == "bauen" or blick == "oben" else yaw
	var vor := Vector2(-sin(az), -cos(az))
	var re := Vector2(-vor.y, vor.x)
	var dvec: Vector2 = { "up": vor, "down": -vor, "left": -re, "right": re }.get(cmd, Vector2.ZERO)
	var aussen := Vector2(wand_aussen(str(_wz.seite)))
	var s := dvec.dot(aussen)
	if absf(s) < 0.4:
		Sfx.play("bump")
		return
	var neu := int(_wz.delta) + (1 if s > 0.0 else -1)
	var plan := wand_plan(raum, str(_wz.seite), neu)
	if (plan.raum as Dictionary).is_empty():
		Sfx.play("bump")
		return
	_wz.delta = neu
	_wz.plan = plan
	Sfx.play("move")
	_wand_vorschau()


func _wand_taste(cmd: String) -> bool:
	match cmd:
		"a":
			var plan: Dictionary = _wz.plan
			if int(_wz.delta) == 0:
				_wand_ende()
			elif not bool(plan.ok):
				Sfx.play("error")
				var im_weg: Array = (plan.blockiert as Array).map(func(i: int) -> String: return _moebel_name(str(raum.moebel[i].t)))
				_melden(tr("Im Weg: %s") % ", ".join(im_weg.slice(0, 3)))
			else:
				_wand_uebernehmen()
		"b":
			Sfx.play("back")
			_wand_ende()
		"guide":
			return false
		_:
			Sfx.play("bump")
	return true


func _wand_uebernehmen() -> void:
	var plan: Dictionary = _wz.plan
	var seite := str(_wz.seite)
	var delta := int(_wz.delta)
	var von := str(_wz.von)
	_wand_aufraeumen()
	_merken(true)
	var neu: Dictionary = plan.raum
	raum.w = int(neu.w)
	raum.d = int(neu.d)
	raum.moebel = neu.moebel
	# Links bzw. hinten wächst der Raum in den Koordinaten: du bleibst, wo du warst.
	var z := Katalog.ZELLE
	if seite == "links":
		pos.x += delta * z
		cursor.x += delta
	elif seite == "hinten":
		pos.z += delta * z
		cursor.y += delta
	_wz = {}
	modus = von if von in ["laufen", "bauen"] else "laufen"
	_welt_neu()
	pos = _frei(pos)
	Sfx.play("toggle_on")
	_melden(tr("Raum: %s × %s m") % [_meter_text(int(raum.w)), _meter_text(int(raum.d))])
	_geaendert()
	_nach_wand()


func _wand_ende() -> void:
	_wand_aufraeumen()
	var von := str(_wz.get("von", "laufen"))
	_wz = {}
	modus = von if von in ["laufen", "bauen"] else "laufen"
	_nach_wand()


func _nach_wand() -> void:
	_info_weg()
	welt.raster.visible = modus == "bauen"
	if modus == "bauen":
		_raster_auffrischen()
	else:
		_ziel = -2
		_ziel_suchen()
	_ziel_zeigen()
	_kopf_auffrischen()
	_hinweise_auffrischen()


func _wand_aufraeumen() -> void:
	for n in _wz_knoten:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_wz_knoten.clear()
	_echte_wand(true)
	# Möbel zurück an ihren Platz, ohne Rot.
	for i in welt.knoten.size():
		var n: Node3D = welt.knoten[i]
		if is_instance_valid(n) and i < (raum.moebel as Array).size():
			welt.setze_ort(n, raum.moebel[i], i)
			_overlay(n, null)


## Die echte Wand weg (nach außen gezogen: der Blick geht bis zur neuen Wand) bzw. wieder da – so,
## wie es die Ansicht von oben macht (nur Schatten); zurück stellt die Welt beim nächsten Bild.
func _echte_wand(da: bool) -> void:
	if da:
		welt.set("_schnitt_lage", -1)
		return
	var h: Variant = welt.get("huelle")
	var w: Variant = (h as Object).get("_waende") if h is Object else null
	if not (w is Dictionary):
		return
	for mi in (w as Dictionary).get(str(_wz.seite), []):
		if is_instance_valid(mi) and mi is GeometryInstance3D:
			if (mi as Node).has_meta("uz_backschatten"):
				(mi as Node3D).visible = false
			else:
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## Geisterwand (halb durchsichtig) und der Bodenstreifen, der dazukommt bzw. wegfällt.
func _wand_geist() -> void:
	_wand_aufraeumen()
	if _wz_rot == null:
		_wz_rot = StandardMaterial3D.new()
		_wz_rot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wz_rot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wz_rot.albedo_color = Color(0.95, 0.25, 0.22, 0.45)
		_wz_rot.no_depth_test = false
	for k in 2:
		var m := MeshInstance3D.new()
		m.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		welt.add_child(m)
		_wz_knoten.append(m)


## Beim Laufen: von der anderen Seite des Raums, etwas erhöht, der Blick auf die wandernde Wand –
## die ganze Wand und der Streifen Boden davor im Bild, ohne Ansicht von oben.
func _wand_kamera() -> Array:
	var seite := str(_wz.seite)
	var neu := _wand_mitte(seite, int(_wz.delta))
	neu.y = 0.8
	var alt := _wand_mitte(seite, 0)
	var aussen := Vector3(wand_aussen(seite).x, 0, wand_aussen(seite).y)
	var tiefe := float(raum.d if seite in ["hinten", "vorn"] else raum.w) * Katalog.ZELLE
	var o := alt - aussen * clampf(tiefe * 0.8, 2.2, 4.6)
	o.y = 2.3
	o.x = clampf(o.x, 0.25, float(raum.w) * Katalog.ZELLE - 0.25)
	o.z = clampf(o.z, 0.25, float(raum.d) * Katalog.ZELLE - 0.25)
	return [Transform3D(Basis(), o).looking_at(neu, Vector3.UP), 66.0, o.distance_to(neu)]


func _wand_mitte(seite: String, delta: int) -> Vector3:
	var z := Katalog.ZELLE
	var w := float(raum.w) * z
	var d := float(raum.d) * z
	var a := float(delta) * z
	match seite:
		"hinten": return Vector3(w * 0.5, 0.3, -a)
		"vorn": return Vector3(w * 0.5, 0.3, d + a)
		"links": return Vector3(-a, 0.3, d * 0.5)
		"rechts": return Vector3(w + a, 0.3, d * 0.5)
	return Vector3(w * 0.5, 0.3, d * 0.5)


func _wand_vorschau() -> void:
	if _wz_knoten.size() < 2:
		return
	var seite := str(_wz.seite)
	var delta := int(_wz.delta)
	var plan: Dictionary = _wz.plan
	var ok := bool(plan.get("ok", false))
	var z := Katalog.ZELLE
	var w := float(raum.w) * z
	var d := float(raum.d) * z
	var a := float(delta) * z
	var quer := seite in ["links", "rechts"]
	var laenge := d if quer else w
	var mitte := _wand_mitte(seite, delta)
	var akzent: Color = UzTheme.col("accent")
	# Geisterwand.
	var wand: MeshInstance3D = _wz_knoten[0]
	(wand.mesh as BoxMesh).size = Vector3(0.06, 2.6, laenge) if quer else Vector3(laenge, 2.6, 0.06)
	wand.position = Vector3(mitte.x, 1.3, mitte.z)
	# Nach außen: die echte Wand tritt zur Seite, die neue steht hell und fast fest da.
	var raus := delta > 0
	var hell := Color(0.94, 0.92, 0.88).lerp(akzent, 0.18)
	(wand.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.36, 0.3, 0.5) if not ok and delta != 0 \
			else (Color(hell, 0.82) if raus else Color(akzent, 0.3))
	wand.visible = delta != 0
	if raus:
		_echte_wand(false)
	else:
		_echte_wand(true)
	# Bodenstreifen zwischen alter und neuer Wand.
	var streifen: MeshInstance3D = _wz_knoten[1]
	var breite := absf(a)
	(streifen.mesh as BoxMesh).size = Vector3(breite, 0.01, laenge) if quer else Vector3(laenge, 0.01, breite)
	var alt := _wand_mitte(seite, 0)
	streifen.position = Vector3((alt.x + mitte.x) * 0.5, 0.012, (alt.z + mitte.z) * 0.5)
	var farbe := Color(0.4, 0.9, 0.55, 0.55) if delta > 0 else Color(1, 1, 1, 0.22)
	if not ok and delta != 0:
		farbe = Color(1.0, 0.36, 0.3, 0.3)
	(streifen.material_override as StandardMaterial3D).albedo_color = farbe
	streifen.visible = delta != 0
	# Was mitwandert, steht schon dort; was im Weg ist, wird rot.
	var schub := Vector3(wand_aussen(seite).x, 0, wand_aussen(seite).y) * a
	for i in welt.knoten.size():
		var n: Node3D = welt.knoten[i]
		if not is_instance_valid(n) or i >= (raum.moebel as Array).size():
			continue
		welt.setze_ort(n, raum.moebel[i], i)
		if i in (plan.get("mit", []) as Array):
			n.position += schub
		_overlay(n, _wz_rot if i in (plan.get("blockiert", []) as Array) else null)
	var nw := int(plan.get("w", raum.w))
	var nd := int(plan.get("d", raum.d))
	var meta := tr("Steuerkreuz: größer oder kleiner")
	if not ok and delta != 0:
		meta = tr("Etwas ist im Weg")
	elif not (plan.get("mit", []) as Array).is_empty() and delta != 0:
		meta = tr("%d Möbel rücken mit") % (plan.mit as Array).size()
	_info_zeigen(tr(str(G.SEITEN_NAMEN.get(seite, ""))), "%s × %s m" % [_meter_text(nw), _meter_text(nd)], meta)


# --- Regal: eine Hülle von Hand umstellen --------------------------------------------------------

## Fächer eines Regals von oben nach unten, dazu oben drauf (-1): [[Index, Fach], …].
func _hand_faecher(m: int) -> Array:
	var regal: Node3D = welt.knoten[m]
	var faecher: Array = regal.get_meta("faecher", [])
	var out: Array = []
	out.append([-1, Inhalt.oben_fach(faecher)])
	var idx: Array = range(faecher.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return float(faecher[a].pos.y) > float(faecher[b].pos.y))
	for i in idx:
		out.append([int(i), faecher[i]])
	return out


func _hand_start(m: int, p: Dictionary) -> void:
	if p.is_empty() or str(p.get("art", "")) != "spiel":
		Sfx.play("bump")
		return
	var g: Dictionary = p.daten
	var rg: Dictionary = raum.moebel[m].get("rg", G.std_regal("spieleregal"))
	var lage := str((rg.get("lg", {}) as Dictionary).get(str(g.get("id", "")), "stehend"))
	_hand = { "m": m, "g": g, "id": str(g.get("id", "")), "fach": int(p.get("fach", 0)), "k": 0, "lage": lage, "platz": p }
	# Die Hülle verlässt ihren Platz (unsichtbar dort), in der Hand schwebt sie mit dem Cover zu dir.
	_platz_verstecken(p, true)
	var lst := _hand_liste(int(_hand.fach))
	var k := 0
	for q in lst:
		if float(q.x) < float(p.x):
			k += 1
	_hand.k = k
	Sfx.play("select")
	_hand_zeigen()
	_hinweise_auffrischen()


func _platz_verstecken(p: Dictionary, weg: bool) -> void:
	if p.has("mm"):
		var mm: MultiMesh = p.mm
		var t: Transform3D = p.basis
		mm.set_instance_transform(int(p.index), t.scaled_local(Vector3(0.001, 0.001, 0.001)) if weg else t)
		if p.has("schild") and is_instance_valid(p.schild):
			(p.schild as Node3D).visible = not weg
	elif p.has("knoten") and is_instance_valid(p.knoten):
		(p.knoten as Node3D).visible = not weg


## Hüllen eines Fachs (ohne die in der Hand), nach x.
func _hand_liste(fach: int) -> Array:
	var out: Array = []
	for q in welt.plaetze.get(int(_hand.m), []):
		if int(q.get("fach", -9)) == fach and str(q.daten.get("id", "")) != str(_hand.id):
			out.append(q)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x) < float(b.x))
	return out


## Breite der Hülle in einer Lage (Meter entlang des Fachs).
func _hand_breite(g: Dictionary, lage: String) -> float:
	var mass := Inhalt.mass_von(g, welt.huellen)
	match lage:
		"liegend": return float(mass[1])
		"vorn": return float(mass[2]) + 0.012
	return float(mass[0]) + 0.0015


## Passt die Hülle in der gewählten Lage noch ins Fach? (Die Reihe mit ihr an der Lücke, liegende
## stapeln sich wie im Regal.)
func _hand_passt() -> bool:
	var f: Dictionary = _hand_fach()
	var reihe: Array = _hand_liste(int(_hand.fach)).map(func(q: Dictionary) -> Array: return [q.daten, str(q.get("lage", "stehend"))])
	reihe.insert(clampi(int(_hand.k), 0, reihe.size()), [_hand.g, str(_hand.lage)])
	return Inhalt.reihe_breite(reihe, welt.huellen, float(f.hoehe)) <= float(f.breite) - 0.008 + 0.0005


func _hand_fach() -> Dictionary:
	for e in _hand_faecher(int(_hand.m)):
		if int(e[0]) == int(_hand.fach):
			return e[1]
	return {}


func _hand_schritt(cmd: String) -> void:
	var lst := _hand_liste(int(_hand.fach))
	match cmd:
		"left", "right":
			var k := int(_hand.k) + (-1 if cmd == "left" else 1)
			if k < 0 or k > lst.size():
				Sfx.play("bump")
				return
			_hand.k = k
		"up", "down":
			var fl := _hand_faecher(int(_hand.m))
			var jetzt := 0
			for j in fl.size():
				if int(fl[j][0]) == int(_hand.fach):
					jetzt = j
			var n := jetzt + (-1 if cmd == "up" else 1)
			if n < 0 or n >= fl.size():
				Sfx.play("bump")
				return
			# An der Stelle bleiben, so gut es geht: die Lücke mit dem nächsten x.
			var x := _hand_x()
			_hand.fach = int(fl[n][0])
			if int(_hand.fach) == -1 and str(_hand.lage) == "stehend":
				_hand.lage = "liegend"
			var neu := _hand_liste(int(_hand.fach))
			var k2 := 0
			for q in neu:
				if float(q.x) < x:
					k2 += 1
			_hand.k = k2
	Sfx.play("move")
	_hand_zeigen()


## x der Einfügestelle (lokal im Regal).
func _hand_x() -> float:
	var f := _hand_fach()
	var lst := _hand_liste(int(_hand.fach))
	var k := int(_hand.k)
	var links := float(f.pos.x) - float(f.breite) * 0.5
	if lst.is_empty():
		return links + _hand_breite(_hand.g, str(_hand.lage)) * 0.5 + 0.01
	if k <= 0:
		return float(lst[0].x) - _hand_breite(lst[0].daten, str(lst[0].get("lage", "stehend"))) * 0.5 - 0.004
	if k >= lst.size():
		var l: Dictionary = lst[lst.size() - 1]
		return float(l.x) + _hand_breite(l.daten, str(l.get("lage", "stehend"))) * 0.5 + 0.004
	return (float(lst[k - 1].x) + float(lst[k].x)) * 0.5


## Die Hülle schwebt vor der Lücke, eine helle Marke zeigt, wo sie hinkommt; rot, wenn kein Platz ist.
func _hand_zeigen() -> void:
	for n in _hand_knoten:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_hand_knoten.clear()
	var m := int(_hand.m)
	var regal: Node3D = welt.knoten[m]
	var f := _hand_fach()
	var x := _hand_x()
	var ok := _hand_passt()
	var mass := Inhalt.mass_von(_hand.g, welt.huellen)
	var vorn_z := float(f.pos.z) + float(f.tiefe) * 0.5
	var y := float(f.pos.y)
	# In der Hand: ein Stück vor dem Fach und etwas höher, das Cover zu dir.
	var schwebe := Inhalt._cover_huelle(regal, _hand.g, Vector3(x, y + 0.07, vorn_z + 0.2), self, welt.huellen)
	schwebe.rotation_degrees = Vector3(6, 0, 0)
	if str(_hand.lage) == "liegend":
		schwebe.rotation_degrees = Vector3(-58, 0, 0)
	_hand_knoten.append(schwebe)
	var marke := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.006, minf(float(mass[1]), float(f.hoehe) - 0.01), 0.02)
	marke.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = UzTheme.col("accent") if ok else Color(1.0, 0.36, 0.3)
	marke.material_override = mat
	marke.position = Vector3(x, y + bm.size.y * 0.5, vorn_z - 0.01)
	regal.add_child(marke)
	_hand_knoten.append(marke)
	# Kamera: vor das Fach, die schwebende Hülle in der Mitte.
	var wpos := regal.global_transform * Vector3(x, y + 0.12, vorn_z + 0.12)
	var vor := regal.global_transform.basis.z.normalized()
	var o := wpos + vor * 0.95 + Vector3(0, 0.12, 0)
	_hand["kamera"] = [Transform3D(Basis(), o).looking_at(wpos, Vector3.UP), 50.0, o.distance_to(wpos)]
	var fname := tr("Oben auf dem Regal") if int(_hand.fach) == -1 else tr("Fach %d") % (_hand_fach_nr() + 1)
	_info_zeigen(fname, Library.display_title(_hand.g), tr(str(LAGE_NAMEN.get(str(_hand.lage), ""))) + ("" if ok else " · " + tr("Kein Platz")))


func _hand_fach_nr() -> int:
	var fl := _hand_faecher(int(_hand.m))
	for j in fl.size():
		if int(fl[j][0]) == int(_hand.fach):
			return j - 1
	return 0


func _hand_taste(cmd: String) -> bool:
	match cmd:
		"a":
			if not _hand_passt():
				Sfx.play("error")
				_melden(tr("Hier ist kein Platz"))
				return true
			_hand_ablegen()
		"b":
			Sfx.play("back")
			_hand_ende(true)
		"lb", "rb":
			var i := LAGEN.find(str(_hand.lage))
			var lage := str(LAGEN[posmod(i + (1 if cmd == "rb" else -1), LAGEN.size())])
			if int(_hand.fach) == -1 and lage == "stehend":
				lage = str(LAGEN[posmod(LAGEN.find(lage) + (1 if cmd == "rb" else -1), LAGEN.size())])
			_hand.lage = lage
			Sfx.play("move")
			_hand_zeigen()
		"guide":
			return false
		_:
			Sfx.play("bump")
	_hinweise_auffrischen()
	return true


## Ablegen: die eigene Ordnung des Regals gilt ab jetzt (Fach und Lage je Spiel, Reihenfolge).
func _hand_ablegen() -> void:
	var m := int(_hand.m)
	var it: Dictionary = raum.moebel[m]
	var rg: Dictionary = (it.get("rg", G.std_regal("spieleregal")) as Dictionary).duplicate(true)
	var neu := hand_ordnung(rg, welt.plaetze.get(m, []), str(_hand.id), int(_hand.fach), _hand_liste(int(_hand.fach)), int(_hand.k), str(_hand.lage),
		Inhalt.spiele(rg).map(func(g: Dictionary) -> String: return str(g.get("id", ""))))
	var gid := str(_hand.id)
	_hand_ende(false)
	_merken(true)
	it["rg"] = G.pruefe_regal(neu, "spieleregal")
	welt.inhalt_fuellen()
	_ansehen(m)
	for k in _ans_plaetze.size():
		if str((_ans_plaetze[k] as Dictionary).daten.get("id", "")) == gid:
			_ans_sel = k
	_platz_zeigen()
	Sfx.play("toggle_on")
	_geaendert()


## Neue Regal-Einstellungen nach dem Ablegen (rein, testbar): ab jetzt eigene Ordnung („manuell“),
## beim ersten Mal steht jede Hülle fest in ihrem Fach (pl), die Hand-Hülle kommt vor die k-te Hülle
## des Ziel-Fachs (sonst hinter dessen letzte), ihre Lage gilt (lg; stehend ohne Eintrag).
static func hand_ordnung(rg: Dictionary, plaetze: Array, gid: String, fach: int, ziel_liste: Array, k: int, lage: String, ids: Array) -> Dictionary:
	var neu := rg.duplicate(true)
	var pl: Dictionary = (neu.get("pl", {}) as Dictionary).duplicate()
	var lg: Dictionary = (neu.get("lg", {}) as Dictionary).duplicate()
	var alle: Array = ids
	if pl.is_empty() or str(neu.get("so", "")) != "manuell":
		# Das erste Mal: alles bleibt, wo es steht – Fach, Lage und Reihenfolge wie gerade im Regal.
		pl = {}
		lg = {}
		var da: Array = plaetze.filter(func(q: Dictionary) -> bool: return str(q.get("art", "")) == "spiel")
		da.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.x) < float(b.x) if int(a.fach) == int(b.fach) else int(a.fach) < int(b.fach))
		alle = []
		for q in da:
			var qid := str(q.daten.get("id", ""))
			pl[qid] = int(q.get("fach", 0))
			var ql := str(q.get("lage", "vorn" if q.has("knoten") else "stehend"))
			if ql != "stehend":
				lg[qid] = ql
			alle.append(qid)
		for x in ids:
			if not pl.has(str(x)):
				alle.append(str(x))
	neu["so"] = "manuell"
	var reihe: Array = alle.filter(func(x: String) -> bool: return x != gid)
	var pos := reihe.size()
	if k < ziel_liste.size():
		pos = maxi(0, reihe.find(str(ziel_liste[k].daten.get("id", ""))))
	elif not ziel_liste.is_empty():
		pos = reihe.find(str(ziel_liste[ziel_liste.size() - 1].daten.get("id", ""))) + 1
	reihe.insert(clampi(pos, 0, reihe.size()), gid)
	neu["ma"] = reihe.slice(0, G.MAX_REIHE)
	pl[gid] = fach
	neu["pl"] = pl
	if lage == "stehend":
		lg.erase(gid)
	else:
		lg[gid] = lage
	neu["lg"] = lg
	return neu


## Regal-Tafel „Sortierung zurücksetzen“: die Ordnung von Hand weg, wieder automatisch (zuletzt
## gespielt); was eingeräumt ist, bleibt.
func regal_hand_weg(i: int) -> void:
	if i < 0 or i >= (raum.moebel as Array).size():
		return
	var it: Dictionary = raum.moebel[i]
	var rg: Dictionary = (it.get("rg", G.std_regal(str(it.t))) as Dictionary).duplicate(true)
	if (rg.get("pl", {}) as Dictionary).is_empty():
		return
	_merken(true)
	rg.erase("pl")
	rg.erase("lg")
	rg["so"] = "zuletzt"
	it["rg"] = G.pruefe_regal(rg, str(it.t))
	welt.inhalt_fuellen()
	_geaendert()


func _hand_ende(zurueck: bool) -> void:
	for n in _hand_knoten:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_hand_knoten.clear()
	if zurueck and _hand.has("platz"):
		_platz_verstecken(_hand.platz, false)
	_hand = {}
	if modus == "ansehen":
		_platz_zeigen()
	_hinweise_auffrischen()
