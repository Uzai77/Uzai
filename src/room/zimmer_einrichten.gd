extends "res://src/room/zimmer_ansehen.gd"
## Dein Zimmer, Schicht über zimmer_ansehen.gd: Einrichten, Katalog, Seitenleiste zum Anpassen,
## Stimmungs-Rad, Möbel anpassen, Raum im Ganzen, Farben und eigene Möbel.
##
## Einrichten ist direktes Anfassen im Raum (wie die Wohnungseinrichtung bei Animal Crossing): Y beim
## Laufen – was du gerade ansiehst, ist schon gewählt. Ein Feld wählt, was darauf steht; das Schild am
## Möbel sagt, was A tut (Hochheben, Absetzen, „Hier ist kein Platz“). Getragenes: A absetzen, LB/RB
## drehen, Y Farbe, X wegräumen, B zurück an seinen Platz. Auf leerem Boden öffnet A das Bau-Menü
## (RT von überall) und Y den Boden; über den Rand hinaus ist die Wand gewählt, A gestaltet sie.
## X macht rückgängig, ≡ öffnet das ganze Zimmer.
##
## Wie bei Sims: erst das Möbel wählen, dann platzieren. Im Bau-Menü (katalog_ui.gd) nimmt A ein Möbel
## an den Cursor – es hängt an der freien Stelle in der Bildmitte, das Menü tritt zurück; Stick und
## Steuerkreuz schieben es (das Feld darunter grün: passt, rot: passt nicht), LB/RB drehen, Y Farbe,
## A setzt ab und führt zurück ins Menü (dieselbe Kachel: A setzt gleich noch eins), B bzw. X legt es
## zurück ins Menü. Wände, Böden, Licht … zeigt das Menü als Probe (bau_probe): A übernimmt, B nimmt
## sie zurück – ein Rückgängig-Schritt je Probe.

const Moebel := preload("res://src/room/moebel.gd")
const FigurEditor := preload("res://src/room/figur/figur_editor.gd")
const OnlineUi := preload("res://src/room/online_ui.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")
const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")
const BauInhalt := preload("res://src/room/bau_inhalt.gd")
const RadUi := preload("res://src/room/rad_ui.gd")

var _oben_az_soll := 0.62

var _halten_vorher := {}       ## Stand vor dem Aufnehmen (Rückgängig)
var _katalog_feld := Vector2i.ZERO   ## Feld, an dem das Bau-Menü aufging (die Kamera schaut dorthin)
var _vorschau_timer: Timer      ## Bau-Menü: Probe einer Oberfläche erst, wenn die Auswahl kurz ruht
var _aus_katalog := false      ## das Getragene kam eben aus dem Bau-Menü: Absetzen, B, X führen dorthin zurück

var _katalog_wieder := false   ## Feinseite aus dem Bau-Menü geöffnet: danach zurück ins Bau-Menü
var _bau_vorher := {}          ## Bau-Menü: Stand vor der Probe { raum, schritt } (leer: keine Probe offen)
var _rad: RadUi               ## Stimmungs-Rad
var _licht_vorher := {}        ## Licht vor der Vorschau im Stimmungs-Rad


# --- Einrichten (Bau-Modus) ----------------------------------------------------------------------------

func bauen_an() -> void:
	if besuch_sperre():
		return
	var von_laufen := modus == "laufen"
	modus = "bauen"
	_wand = ""
	_oben_az_soll = yaw if blick == "ich" else _oben_az_soll
	_oben_az = lerp_angle(_oben_az, _oben_az_soll, 1.0)
	cursor = Vector2i(clampi(int(pos.x / Katalog.ZELLE), 0, int(raum.w) - 1), clampi(int(pos.z / Katalog.ZELLE), 0, int(raum.d) - 1))
	# Was du gerade ansiehst, ist schon gewählt: der Sessel, die Stelle am Boden oder die Wand.
	_wahl = -1
	if von_laufen:
		var feld: Variant = _angesehenes_feld()
		if feld is Vector2i:
			cursor = feld
			_wand = wand_an(cursor, int(raum.w), int(raum.d))
	_rate = 3.0
	_glimmen_setzen(null)
	_ziel_zeigen()
	welt.raster.visible = true
	Sfx.play("open")
	_raster_auffrischen()
	_kopf_auffrischen()
	_hinweise_auffrischen()


## Das Feld, das du beim Laufen ansiehst (null: keins). Zuerst ein Möbel – das mit dem Schild, sonst
## was im Blick steht (auch ohne eigene Handlung, z. B. ein Tisch; Teppiche und Deckenlampen nicht,
## die sieht man nur von oben) –, dann die Stelle am Boden, dann die Wand (ein Feld außerhalb).
## Von oben zählt, wo du stehst.
func _angesehenes_feld() -> Variant:
	if blick == "oben":
		return null
	var i := _ziel
	if i < 0:
		i = welt.treffer(_augen(), _blickrichtung(), 4.0, false)
		if i >= (raum.moebel as Array).size() or (i >= 0 and Katalog.ebene(str(raum.moebel[i].t)) in ["teppich", "decke"]):
			i = -1
	if i >= 0:
		# Genau das Möbel, das du ansiehst – nicht die Tasse, die auf ihm steht.
		_wahl = i
		return _naechstes_feld(i)
	return blick_feld(_augen(), _blickrichtung(), int(raum.w), int(raum.d))


## Wohin ein Blick fällt, in Feldern: auf den Boden (bis 6 m) oder an eine Wand (dann das Feld
## gleich dahinter, außerhalb des Raums). null, wenn er nichts davon trifft.
static func blick_feld(o: Vector3, r: Vector3, w: int, d: int) -> Variant:
	var z := Katalog.ZELLE
	if r.y < -0.05:
		var t := -o.y / r.y
		var p := o + r * t
		if t <= 6.0 and p.x >= 0.0 and p.z >= 0.0 and p.x < w * z and p.z < d * z:
			return Vector2i(int(p.x / z), int(p.z / z))
	var best := INF
	var out: Variant = null
	for wand in [["x", 0.0, -1], ["x", w * z, w], ["z", 0.0, -1], ["z", d * z, d]]:
		var achse: String = wand[0]
		var dir := r.x if achse == "x" else r.z
		if absf(dir) < 0.001:
			continue
		var t2 := (float(wand[1]) - (o.x if achse == "x" else o.z)) / dir
		if t2 <= 0.0 or t2 >= best:
			continue
		var p2 := o + r * t2
		if p2.y < 0.0 or p2.y > 2.7:
			continue
		if achse == "x" and p2.z >= 0.0 and p2.z < d * z:
			best = t2
			out = Vector2i(int(wand[2]), int(p2.z / z))
		elif achse == "z" and p2.x >= 0.0 and p2.x < w * z:
			best = t2
			out = Vector2i(int(p2.x / z), int(wand[2]))
	return out


## Das Feld eines Möbels, das dir am nächsten ist.
func _naechstes_feld(i: int) -> Vector2i:
	var best := Vector2i(int(raum.moebel[i].x), int(raum.moebel[i].z))
	var best_d := INF
	for f in Daten.felder(raum.moebel[i]):
		var d := Vector2((f.x + 0.5) * Katalog.ZELLE, (f.y + 0.5) * Katalog.ZELLE).distance_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best = f
	return best


func _bauen_aus() -> void:
	_aus_katalog = false
	if not _halten.is_empty():
		_ablegen_abbrechen()
	_wand = ""
	modus = "laufen"
	welt.raster.visible = false
	pos = _frei(pos)
	_rate = 3.0
	_kopf_auffrischen()
	_ziel = -2
	_ziel_suchen()
	_hinweise_auffrischen()


func _bauen_taste(cmd: String) -> bool:
	var tragen := not _halten.is_empty()
	var i := _feld_wahl()
	match cmd:
		"b":
			Sfx.play("back")
			if tragen:
				_zurueckstellen()
				_zurueck_ins_menue()
			else:
				_bauen_aus()
		"a":
			if tragen:
				_absetzen()
				# Gesetzt: zurück ins Bau-Menü (dieselbe Kachel – A nimmt gleich noch eins).
				if _halten.is_empty():
					_zurueck_ins_menue()
			elif i >= 0:
				_aufnehmen(i)
			elif _an_tuer():
				# Die Tür bleibt (Eingang); Platz und Art im Bau-Menü.
				_melden(tr("Die Tür bleibt – durch sie kommst du herein. Platz und Art wählst du hier."))
				_katalog.bereich("@fenster")
				_katalog_auf(true)
			elif _wand != "":
				wand_gestalten(_wand)
			else:
				_katalog_auf()
		"x":
			if tragen:
				_wegraeumen()
				_zurueck_ins_menue()
			else:
				rueckgaengig()
		"y":
			if tragen:
				_farbe_wechseln()
			elif i >= 0:
				_aktionen_bauen(i)
			elif _wand != "":
				call("_wand_ziehen_auf", _wand)     # zimmer_umbau.gd: die Wand ziehen
			else:
				boden_gestalten()
		"lb", "rb":
			drehen(1 if cmd == "rb" else 3)
		"rt":
			# Der Katalog geht immer auf (wie ein Lager): das Möbel steht dann neben dem Feld.
			if tragen:
				Sfx.play("bump")
			else:
				_katalog_auf()
		"lt":
			_oben_az_soll += PI * 0.5
			Sfx.play("move")
		"menu":
			_zimmer_menue()
	return true


## B beim Tragen: ein neues Möbel verschwindet wieder, ein vorhandenes gleitet zurück an seinen Platz.
func _zurueckstellen() -> void:
	if _halten_idx < 0:
		_vorschau_weg()
		_raster_auffrischen()
		_ziel_zeigen()
		_hinweise_auffrischen()
		return
	var knoten: Array = [welt.knoten[_halten_idx]]
	for d in _halten_dabei:
		knoten.append(welt.knoten[int(d.idx)])
	var von: Array = knoten.map(func(k: Node3D) -> Transform3D: return k.transform)
	_ablegen_abbrechen()
	for k in knoten.size():
		var nk: Node3D = knoten[k]
		var ziel: Transform3D = nk.transform
		nk.transform = von[k]
		U.tw(nk, "uz_tragen").tween_property(nk, "transform", ziel, U.T_MOVE).set_trans(Tween.TRANS_QUART)
	_ziel_zeigen()


## Steuerkreuz bewegt das Feld so, wie es auf dem Bildschirm aussieht (Kamera kann sich drehen).
func _cursor_schritt(cmd: String) -> void:
	var vor := Vector2(-sin(_oben_az), -cos(_oben_az))
	var re := Vector2(-vor.y, vor.x)
	var d: Vector2 = { "up": vor, "down": -vor, "left": -re, "right": re }[cmd]
	var schritt := Vector2i(int(signf(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, int(signf(d.y)))
	cursor_setzen(cursor + schritt)


## Feld wählen (Steuerkreuz, Maus): Getragenes bleibt ganz im Raum; ohne etwas in der Hand darf das
## Feld eine Reihe über den Rand hinaus – dort ist die Wand gewählt.
func cursor_setzen(neu: Vector2i, laut := true) -> void:
	var tragen := not _halten.is_empty()
	if tragen:
		var g := Katalog.groesse_it(_halten)
		neu.x = clampi(neu.x, 0, int(raum.w) - g.x)
		neu.y = clampi(neu.y, 0, int(raum.d) - g.y)
	else:
		neu = feld_im_rahmen(cursor, neu, int(raum.w), int(raum.d))
	if neu == cursor:
		if laut:
			Sfx.play("bump")
		return
	cursor = neu
	_wahl = -1
	_wand = "" if tragen else wand_an(cursor, int(raum.w), int(raum.d))
	if laut:
		Sfx.play("move")
	if tragen:
		_halten.x = cursor.x
		_halten.z = cursor.y
		if Katalog.ebene(str(_halten.t)) == "wand":
			var r := Daten.wand_drehung(raum, str(_halten.t), cursor.x, cursor.y, int(_halten.r))
			if r >= 0:
				_halten.r = r
		_getragen_zeigen()
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Ein Feld im Raum oder eine Reihe außerhalb (die Wand) – Ecken gibt es nicht: dort bleibt es beim
## alten Feld.
static func feld_im_rahmen(alt: Vector2i, neu: Vector2i, w: int, d: int) -> Vector2i:
	neu.x = clampi(neu.x, -1, w)
	neu.y = clampi(neu.y, -1, d)
	if (neu.x < 0 or neu.x >= w) and (neu.y < 0 or neu.y >= d):
		return alt
	return neu


## Welche Wand ein Feld außerhalb des Raums meint („“ im Raum).
static func wand_an(c: Vector2i, w: int, d: int) -> String:
	if c.y < 0:
		return "hinten"
	if c.y >= d:
		return "vorn"
	if c.x < 0:
		return "links"
	if c.x >= w:
		return "rechts"
	return ""


func _aufnehmen(i: int) -> void:
	_aus_katalog = false
	_halten_vorher = Daten.schnappschuss(raum)
	_halten = (raum.moebel[i] as Dictionary).duplicate()
	_halten_idx = i
	_halten_knoten = welt.knoten[i]
	_halten_dabei = []
	for j in Daten.darauf(raum, i):
		var m: Dictionary = raum.moebel[j]
		_halten_dabei.append({ "idx": j, "dx": int(m.x) - int(_halten.x), "dz": int(m.z) - int(_halten.z) })
	cursor = Vector2i(int(_halten.x), int(_halten.z))
	_wand = ""
	_glimmen_setzen(null)
	Sfx.play("select")
	_getragen_zeigen()
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Das getragene Möbel schwebt etwas über seinem Feld und folgt; was darauf steht, kommt mit.
func _getragen_zeigen() -> void:
	if not is_instance_valid(_halten_knoten):
		return
	var t := welt.lage(_halten, _halten_idx)
	t.origin.y += 0.08
	var tw := U.tw(_halten_knoten, "uz_tragen")
	tw.tween_property(_halten_knoten, "transform", t, U.T_ORT)
	for d in _halten_dabei:
		var j := int(d.idx)
		var m: Dictionary = (raum.moebel[j] as Dictionary).duplicate()
		var rel := _dabei_lage(d)
		m.x = rel.x
		m.z = rel.y
		m.r = (int(m.r) + int(_halten.r) - int(raum.moebel[_halten_idx].r if _halten_idx >= 0 else _halten.r) + 4) % 4
		var tt := welt.lage(m, j)
		tt.origin.y = t.origin.y + Katalog.flaeche(str(_halten.t))
		U.ankommen(welt.knoten[j], U.T_ORT, "uz_tragen").tween_property(welt.knoten[j], "transform", tt, U.T_ORT)


## Lage von Kleinem auf dem getragenen Möbel nach dessen Drehung (in Feldern).
func _dabei_lage(d: Dictionary) -> Vector2i:
	if _halten_idx < 0:
		return Vector2i(int(_halten.x) + int(d.dx), int(_halten.z) + int(d.dz))
	var alt: Dictionary = raum.moebel[_halten_idx]
	var schritte := (int(_halten.r) - int(alt.r) + 4) % 4
	var ga := Katalog.groesse_it(alt)
	var c := Vector2(float(d.dx) + 0.5 - ga.x * 0.5, float(d.dz) + 0.5 - ga.y * 0.5)
	for s in schritte:
		c = Vector2(c.y, -c.x)
	var gn := Katalog.groesse_it(_halten)
	var p := c + Vector2(gn.x * 0.5, gn.y * 0.5) - Vector2(0.5, 0.5)
	return Vector2i(int(_halten.x) + int(roundf(p.x)), int(_halten.z) + int(roundf(p.y)))


func _absetzen() -> void:
	if not Daten.passt(raum, _halten, _halten_idx):
		# Das Schild am Möbel sagt es schon; hier nur der Ton und ein kurzes Rütteln.
		Sfx.play("error")
		_ruetteln()
		return
	_rueck.append(_halten_vorher if _halten_idx >= 0 else Daten.schnappschuss(raum))
	while _rueck.size() > Daten.MAX_SCHRITTE:
		_rueck.pop_front()
	var gesetzt := _halten_idx
	var mit: Array = _halten_dabei.map(func(d: Dictionary) -> int: return int(d.idx))
	if _halten_idx >= 0:
		for d in _halten_dabei:
			var p := _dabei_lage(d)
			var m: Dictionary = raum.moebel[int(d.idx)]
			m.r = (int(m.r) + int(_halten.r) - int(raum.moebel[_halten_idx].r) + 4) % 4
			m.x = p.x
			m.z = p.y
		raum.moebel[_halten_idx] = _halten.duplicate()
	else:
		raum.moebel.append(_halten.duplicate())
		_halten_knoten.queue_free()
		gesetzt = (raum.moebel as Array).size() - 1
	var war_neu := _halten_idx < 0
	_halten = {}
	_halten_idx = -1
	_halten_knoten = null
	_halten_dabei = []
	_wahl = gesetzt
	Sfx.play("toggle_on")
	# Nur, was sich geändert hat: Ein neues Möbel bekommt seinen Knoten, ein getragenes (und was darauf steht)
	# seinen neuen Ort – alle Möbel neu zu bauen ließ bei jedem Absetzen das Bild stehen (zimmer_welt.gd).
	if war_neu:
		welt.moebel_dazu()
	else:
		for j in [gesetzt] + mit:
			if int(j) >= 0 and int(j) < welt.knoten.size():
				U.stop(welt.knoten[int(j)], "uz_tragen")
		welt.moebel_versetzt([gesetzt] + mit)
	# Es setzt sich: aus der Tragehöhe weich auf den Boden, mit einem kleinen Nachfedern.
	for j in [gesetzt] + mit:
		if int(j) >= 0 and int(j) < welt.knoten.size():
			var n: Node3D = welt.knoten[int(j)]
			var t := n.transform
			n.transform = Transform3D(t.basis, t.origin + Vector3(0, 0.08, 0))
			U.ankommen(n, U.T_ORT, "uz_absetzen").tween_property(n, "transform", t, U.T_ORT)
	_speichern_bald()
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Kein Platz: das Getragene schüttelt kurz den Kopf (seitlich hin und her, dann zurück).
func _ruetteln() -> void:
	if not is_instance_valid(_halten_knoten):
		return
	var t := welt.lage(_halten, _halten_idx)
	t.origin.y += 0.08
	var re := t.basis.x.normalized() * 0.05
	var tw := U.tw(_halten_knoten, "uz_tragen")
	for k in [1.0, -0.8, 0.5, 0.0]:
		tw.tween_property(_halten_knoten, "transform", Transform3D(t.basis, t.origin + re * k), 0.06)


## Was du trägst, wegräumen: ein neues Möbel geht zurück in den Katalog, ein vorhandenes (samt dem,
## was darauf steht) verlässt das Zimmer – X (Rückgängig) holt es zurück.
func _wegraeumen() -> void:
	if _halten.is_empty():
		return
	var i := _halten_idx
	if i < 0:
		_vorschau_weg()
		Sfx.play("toggle_off")
	else:
		_halten = {}
		_halten_idx = -1
		_halten_knoten = null
		_halten_dabei = []
		entfernen(i)
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Drehen um 90° (schritte 1 = im Uhrzeigersinn von oben, 3 = dagegen): beim Tragen das
## Getragene, sonst das Möbel unter dem Feld (wenn es gedreht noch passt).
func drehen(schritte: int) -> void:
	if not _halten.is_empty():
		if Katalog.ebene(str(_halten.t)) == "wand":
			Sfx.play("bump")
			return
		_halten.r = (int(_halten.r) + schritte) % 4
		var g := Katalog.groesse_it(_halten)
		_halten.x = clampi(int(_halten.x), 0, int(raum.w) - g.x)
		_halten.z = clampi(int(_halten.z), 0, int(raum.d) - g.y)
		cursor = Vector2i(int(_halten.x), int(_halten.z))
		Sfx.play("move")
		_getragen_zeigen()
		_raster_auffrischen()
		return
	_drehen_idx(_feld_wahl(), schritte)


## Ein Möbel (Index) drehen, wenn es gedreht noch passt.
func _drehen_idx(i: int, schritte: int) -> void:
	if i < 0 or Katalog.ebene(str(raum.moebel[i].t)) == "wand" or not Daten.darauf(raum, i).is_empty():
		Sfx.play("bump")
		return
	var neu: Dictionary = (raum.moebel[i] as Dictionary).duplicate()
	neu.r = (int(neu.r) + schritte) % 4
	if not Daten.passt(raum, neu, i):
		Sfx.play("error")
		_melden(tr("Gedreht passt es hier nicht"))
		return
	Daten.merke(_rueck, raum)
	raum.moebel[i] = neu
	Sfx.play("move")
	welt.moebel_versetzt([i])
	_speichern_bald()
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


func entfernen(i: int) -> void:
	Daten.merke(_rueck, raum)
	var weg: Array = Daten.darauf(raum, i)
	weg.append(i)
	weg.sort()
	weg.reverse()
	var t := str(raum.moebel[i].t)
	var name_ := Katalog.name_of(t) if Katalog.ist_eigen(t) else tr(Katalog.name_of(t))
	_wahl = -1
	for j in weg:
		# Das Möbel verschwindet weich, statt einfach weg zu sein (die Welt baut gleich neu).
		if int(j) < welt.knoten.size():
			_verschwinden(welt.knoten[int(j)])
			welt.knoten[int(j)] = Node3D.new()
		raum.moebel.remove_at(int(j))
	Sfx.play("toggle_off")
	_glimmen_setzen(null)
	welt.alle_moebel()
	_speichern_bald()
	_melden(tr("%s entfernt") % name_)
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Ein Möbel wird kleiner und ist weg (Wegräumen, Entfernen, Vorschau im Katalog).
func _verschwinden(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	# Es verlässt den Raum ganz: Weg ease-in (ohne Ausholen).
	var tw := U.tw(n, "uz_weg", Tween.TRANS_CUBIC, Tween.EASE_IN)
	tw.tween_property(n, "scale", Vector3.ONE * 0.02, U.T_WEG)
	tw.tween_callback(n.queue_free)


func rueckgaengig() -> void:
	if _rueck.is_empty():
		Sfx.play("bump")
		return
	# Eine offene Probe im Bau-Menü ist damit zurückgenommen (ihr Schritt ist der letzte).
	_bau_vorher = {}
	var alt: Dictionary = _rueck.pop_back()
	var form_alt := [int(raum.w), int(raum.d)]
	for k in alt.keys():
		if k != "_extra":
			raum[k] = alt[k]
	var eigene_neu := false
	var figur_neu := false
	if alt.has("_extra"):
		var ex: Dictionary = alt._extra
		eigene_neu = ex.get("eigene", []) != daten.get("eigene", [])
		figur_neu = ex.has("figur") and (ex.get("figur") != daten.get("figur") or ex.get("tier") != daten.get("tier"))
		for k in ex.keys():
			daten[k] = ex[k]
		Katalog.eigene_setzen(daten.eigene)
		welt.huellen = daten.huellen
	Sfx.play("back")
	_glimmen_setzen(null)
	_schritt_offen = true
	_wahl = -1
	if figur_neu:
		bewohner.neu_laden()
	if form_alt != [int(raum.w), int(raum.d)] or eigene_neu:
		_welt_neu()
	else:
		(welt.huelle as Node).call("anpassen", raum, true)
		welt.alle_moebel()
		_licht_neu()
	_speichern_bald()
	_melden(tr("Rückgängig"))
	if modus == "anpassen":
		_ui.auffrischen()
	elif modus == "bauen":
		_raster_auffrischen()
		_ziel_zeigen()
	elif modus == "katalog":
		_katalog.auffrischen()
	_hinweise_auffrischen()


func _farbe_wechseln() -> void:
	var vs := Katalog.varianten(str(_halten.t))
	if vs.size() < 2:
		Sfx.play("bump")
		return
	var ids: Array = vs.map(func(p: Array) -> String: return str(p[0]))
	_halten_variante(ids[(ids.find(str(_halten.v)) + 1) % ids.size()])
	if _aus_katalog:
		# Das Bau-Menü merkt sich die Farbe (die Kachel zeigt sie, das nächste ist gleich so).
		_katalog.variante_merken(str(_halten.t), str(_halten.v))
	Sfx.play("move")
	_melden(tr(Katalog.variante_name(str(_halten.t), str(_halten.v))))


## Getragenes in einer anderen Variante neu bauen (gleicher Ort, Licht wie vorher).
func _halten_variante(v: String) -> void:
	if _halten.is_empty() or str(_halten.get("v", "")) == v or not Katalog.variante_gueltig(str(_halten.t), v):
		return
	_halten.v = v
	var alt := _halten_knoten
	_halten_knoten = Moebel.bauen_it(_halten)
	alt.get_parent().add_child(_halten_knoten)
	_halten_knoten.transform = alt.transform
	if _halten_idx >= 0:
		welt.knoten[_halten_idx] = _halten_knoten
	if _halten_knoten.has_meta("bildschirm"):
		((_halten_knoten.get_meta("bildschirm") as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("bild", welt.tv_vp.get_texture())
	alt.queue_free()
	var hl := Welt.licht_von(raum, _halten)
	Moebel.schalten(_halten_knoten, bool(_halten.an), welt.huelle.lampen_faktor, hl[0], hl[1], hl[2])


# --- Katalog ---------------------------------------------------------------------------------------

## Bau-Menü auf: die Tafel kommt von unten. Möbel kommen erst mit A ins Zimmer (_platzieren).
## behalten: Bereich und gewählte Wand bleiben (Wand bzw. Boden gewählt, zurück aus der Feinseite
## oder vom Platzieren).
func _katalog_auf(behalten := false) -> void:
	modus = "katalog"
	_wand = ""
	_katalog_feld = Vector2i(clampi(cursor.x, 0, int(raum.w) - 1), clampi(cursor.y, 0, int(raum.d) - 1))
	if _vorschau_timer == null:
		_vorschau_timer = Timer.new()
		_vorschau_timer.one_shot = true
		_vorschau_timer.wait_time = 0.12
		_vorschau_timer.timeout.connect(_katalog_vorschau)
		add_child(_vorschau_timer)
		_katalog.connect("gewechselt", func(_id: String) -> void:
			_hinweise_auffrischen()
			_vorschau_timer.start())
	_katalog.visible = true
	_katalog.oeffnen(behalten)
	Sfx.play("open")
	_glimmen_setzen(null)
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Im Bau-Menü steht eine Oberfläche, Stimmung … als Probe im Zimmer, sobald man im Bereich wählt.
## Ein Möbel nicht: es kommt erst mit A an den Cursor (_platzieren) – Wählen und Platzieren getrennt.
func _katalog_vorschau() -> void:
	if modus != "katalog":
		return
	var id := str(_katalog.gewaehlt())
	if KatalogUi.ist_raum(id):
		var k: Dictionary = _katalog.kachel()
		if bool(k.get("sofort", false)) and bool(_katalog.angefasst()):
			bau_probe(k, "", str(_katalog.wand_ziel))
	_hinweise_auffrischen()


## A auf einem Möbel im Bau-Menü: Das Menü tritt zurück, das Möbel hängt am Cursor – an der freien
## Stelle in der Bildmitte (dorthin schaut die Kamera im Bauen), in der gewählten Farbe. Weiter wie
## mit allem, was man trägt; Absetzen, B und X führen zurück ins Menü (_zurueck_ins_menue).
func _platzieren(id: String) -> void:
	_vorschau_timer.stop()
	_katalog_zu()
	cursor = start_feld(cursor, int(raum.w), int(raum.d))
	nehmen(id)
	_halten_variante(str(_katalog.variante(id)))
	_aus_katalog = true
	_raster_auffrischen()
	_hinweise_auffrischen()


## Wo ein Möbel aus dem Menü erscheint: das Feld in der Bildmitte, im Raum (eine Wand-Zeile außerhalb
## zählt als das Feld davor).
static func start_feld(c: Vector2i, w: int, d: int) -> Vector2i:
	return Vector2i(clampi(c.x, 0, w - 1), clampi(c.y, 0, d - 1))


## Kam das Getragene eben aus dem Bau-Menü und ist nicht mehr in der Hand: zurück ins Menü.
func _zurueck_ins_menue() -> void:
	if not _aus_katalog or not _halten.is_empty() or modus != "bauen":
		return
	_aus_katalog = false
	_katalog_auf(true)


## Neues, noch nicht abgesetztes Möbel wieder weg (weich).
func _vorschau_weg() -> void:
	if _halten.is_empty() or _halten_idx >= 0:
		return
	_verschwinden(_halten_knoten)
	_halten = {}
	_halten_knoten = null
	_halten_dabei = []


func _katalog_taste(cmd: String) -> bool:
	# Oberflächen, Farbe (Y), Rückgängig (X): das Bau-Menü selbst.
	if bool(_katalog.taste(cmd)):
		_hinweise_auffrischen()
		return true
	match cmd:
		"b":
			Sfx.play("back")
			_vorschau_weg()
			cursor = _katalog_feld
			_katalog_zu()
		"a":
			var id := str(_katalog.gewaehlt())
			if id == "":
				return true
			if gesperrt(id) != "":
				Sfx.play("error")
				_melden(tr("Freischalten: %s") % tr(gesperrt(id)))
				return true
			if Daten.noch_erlaubt(raum, id) == 0:
				Sfx.play("error")
				_melden(tr("%s gibt es nur einmal im Zimmer") % tr(Katalog.name_of(id)))
				return true
			if id == KatalogUi.NEU:
				_vorschau_weg()
				_katalog_zu()
				baukasten_oeffnen("")
				return true
			_platzieren(id)
		"lb", "rb":
			_katalog.kategorie(-1 if cmd == "lb" else 1)
		"rt":
			Sfx.play("back")
			_vorschau_weg()
			cursor = _katalog_feld
			_katalog_zu()
		"lt":
			_oben_az_soll += PI * 0.5
			Sfx.play("move")
	return true


## X im Bau-Menü: die Probe im Zimmer zuerst weg, dann einen Schritt zurück.
func katalog_rueckgaengig() -> void:
	_vorschau_weg()
	cursor = _katalog_feld
	rueckgaengig()
	if modus == "katalog":
		_vorschau_timer.start()


func _katalog_zu() -> void:
	modus = "bauen"
	_katalog.schliessen()
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Neues Möbel aus dem Katalog in die Hand: steht an der nächsten freien Stelle beim Feld.
func nehmen(id: String, laut := true) -> void:
	var c := Vector2i(clampi(cursor.x, 0, int(raum.w) - 1), clampi(cursor.y, 0, int(raum.d) - 1))
	_wand = ""
	var it: Variant = Daten.freie_stelle(raum, id, c.x, c.y)
	if it == null:
		it = { "t": id, "x": c.x, "z": c.y, "r": 0, "v": Katalog.std_variante(id), "an": true }
		if Katalog.ebene(id) == "wand":
			it.r = maxi(0, Daten.wand_drehung(raum, id, c.x, c.y))
	_halten = it
	_halten_idx = -1
	_halten_vorher = {}
	_halten_dabei = []
	var g := Katalog.groesse_it(_halten)
	_halten.x = clampi(int(_halten.x), 0, int(raum.w) - g.x)
	_halten.z = clampi(int(_halten.z), 0, int(raum.d) - g.y)
	cursor = Vector2i(int(_halten.x), int(_halten.z))
	_halten_knoten = Moebel.bauen_it(_halten)
	welt.get_node("moebel").add_child(_halten_knoten)
	if _halten_knoten.has_meta("bildschirm"):
		((_halten_knoten.get_meta("bildschirm") as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("bild", welt.tv_vp.get_texture())
	var hl := Welt.licht_von(raum, _halten)
	Moebel.schalten(_halten_knoten, true, welt.huelle.lampen_faktor, hl[0], hl[1], hl[2])
	var t := welt.lage(_halten)
	_halten_knoten.transform = Transform3D(t.basis, t.origin + Vector3(0, 0.5, 0))
	if laut:
		Sfx.play("select")
	_getragen_zeigen()
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()


## Katalog bei einer Kategorie öffnen (Maus auf der Kategorienleiste im Bauen).
func katalog_bei(k: int) -> void:
	if modus != "bauen" or not _halten.is_empty():
		return
	_katalog.kategorie_setzen(k)
	_katalog_auf()


# --- Bau-Menü: Raum als Probe -----------------------------------------------------------------------

## Eine Kachel (bau_inhalt.gd) bzw. eine Farbe dafür zur Probe ins Zimmer – wie ein Möbel aus dem
## Katalog: weich gezeigt, bau_uebernehmen behält sie, bau_verwerfen nimmt sie zurück. Die erste Probe
## merkt den Stand davor (ein Rückgängig-Schritt), alle weiteren ändern nur das Bild.
func bau_probe(k: Dictionary, farbe := "", wand := "") -> void:
	if _bau_vorher.is_empty():
		_schritt_offen = true
		_merken()
		_bau_vorher = { "raum": Daten.schnappschuss(raum), "schritt": _rueck.back() if not _rueck.is_empty() else null,
			"huellen": (daten.get("huellen", {}) as Dictionary).duplicate() }
	_schritt_offen = false
	if farbe != "":
		BauInhalt.farbe_setzen(k, self, farbe, wand)
	else:
		BauInhalt.anwenden(k, self, wand)
	_schritt_offen = false


func bau_offen() -> bool:
	return not _bau_vorher.is_empty()


## Zimmer zu, während eine Probe steht: sie war nicht übernommen – zurück (gespeichert wird beim Gehen).
func close() -> void:
	if not _closing and not _bau_vorher.is_empty():
		bau_verwerfen()
	super()


## Stand ohne die offene Probe (Häkchen „im Zimmer“ im Bau-Menü).
func bau_stand() -> Dictionary:
	return _bau_vorher.raum if not _bau_vorher.is_empty() else raum


## Hüllen je System ohne die offene Probe (Regal einrichten).
func bau_huellen() -> Dictionary:
	return _bau_vorher.huellen if not _bau_vorher.is_empty() else daten.get("huellen", {})


func bau_uebernehmen() -> void:
	_bau_vorher = {}
	_schritt_offen = true


func bau_verwerfen() -> void:
	if _bau_vorher.is_empty():
		return
	var alt: Dictionary = _bau_vorher.raum
	var flaechen := false
	for k in ["waende", "boden", "sockel", "decke", "fenster", "tuer", "licht"]:
		if raum[k] != alt[k]:
			flaechen = true
			raum[k] = alt[k]
	# Regale (Auswahl, Sortierung, Darstellung …) und Hüllen je System wie vorher.
	var regale := false
	var ml: Array = raum.moebel
	var al: Array = alt.get("moebel", [])
	for j in mini(ml.size(), al.size()):
		var vorher: Variant = (al[j] as Dictionary).get("rg")
		if (ml[j] as Dictionary).get("rg") != vorher:
			regale = true
			if vorher == null:
				(ml[j] as Dictionary).erase("rg")
			else:
				ml[j]["rg"] = vorher
	if daten.get("huellen", {}) != _bau_vorher.huellen:
		regale = true
		daten.huellen = _bau_vorher.huellen
		welt.huellen = daten.huellen
	if not _rueck.is_empty() and is_same(_rueck.back(), _bau_vorher.schritt):
		_rueck.pop_back()
	_bau_vorher = {}
	_schritt_offen = true
	if flaechen:
		(welt.huelle as Node).call("anpassen", raum, true)
		_licht_neu()
	if regale:
		welt.inhalt_fuellen()
	_geaendert()


## Raumgröße, Vorlage: gleich übernehmen (eigener Rückgängig-Schritt, das Zimmer baut sich neu).
func bau_tun(k: Dictionary) -> void:
	bau_uebernehmen()
	BauInhalt.anwenden(k, self)


## Feinseite aus dem Bau-Menü (Anpassen.seite_fuer); B dort führt zurück ins Bau-Menü.
func bau_seite(kennung: String) -> void:
	var seite: Dictionary = _seiten.seite_fuer(kennung) if _seiten else {}
	if seite.is_empty():
		Sfx.play("bump")
		return
	bau_uebernehmen()
	_vorschau_weg()
	cursor = _katalog_feld
	_katalog_zu()
	_katalog_wieder = true
	_anpassen_auf(seite, -1)


## Eigene Farbe mischen: Feinseite und dort gleich das Farbrad zur Zeile zeile.
func bau_farbrad(kennung: String, zeile: String) -> void:
	bau_seite(kennung)
	if modus == "anpassen":
		_ui.farbrad_auf(zeile)
		_hinweise_auffrischen()


## Mehrere Felder einer Wand (seite) oder aller Wände („“) auf einmal, weich gezeigt.
func wand_werte(seite: String, werte: Dictionary) -> void:
	_merken()
	for s in G.SEITEN:
		if seite == "" or s == seite:
			for k in werte.keys():
				raum.waende[s][k] = str(werte[k])
			raum.waende[s] = G.pruefe_wand(raum.waende[s])
	(welt.huelle as Node).call("anpassen", raum, true)
	_geaendert()


## Mehrere Felder von Boden, Sockel, Decke, Fenster oder Tür auf einmal (ein Umbau statt mehrerer).
func raum_werte(bereich: String, werte: Dictionary) -> void:
	_merken()
	for k in werte.keys():
		raum[bereich][k] = werte[k]
	raum[bereich] = G.pruefe_raum_gestalt(raum)[bereich]
	(welt.huelle as Node).call("anpassen", raum, true)
	_geaendert()


## Für den Katalog: Bedingung, solange ein Möbel noch nicht freigespielt ist (sonst „“).
func gesperrt(id: String) -> String:
	return bewohner.gesperrt(id) if bewohner else ""


## Figur- bzw. Haustier-Editor (tab „figur“ oder „tier“); danach baut das Zimmer beide neu.
func figur_editor(tab := "figur") -> Control:
	var l := FigurEditor.new()
	l.zimmer = self
	l.tab = tab
	l.erreichte = bewohner.erreichte
	l.fertig.connect(func() -> void:
		if is_instance_valid(bewohner):
			bewohner.neu_laden())
	main.open_layer(l)
	return l


## Jackenständer (A): Die Kamera tritt vor deine Figur (wie bei einem Emote, bewohner.gd vor_figur), unten
## die Leiste des Kleiderständers (figur/garderobe.gd) – ←/→ zieht gleich im Zimmer die nächste Figur an,
## A behält sie, B nimmt sie zurück. Kein Menü dazwischen; den ganzen Editor gibt es dort mit Y.
func _figur_wechseln() -> void:
	if bewohner:
		bewohner.garderobe_auf()


## Für den Katalog: wie viele davon noch ins Zimmer dürfen (-1 beliebig viele).
func noch_frei(id: String) -> int:
	return Daten.noch_erlaubt(raum, id)


# --- Modus-Leiste und Kontextmenü am Objekt ------------------------------------------------------

## Leben, Bauen oder Foto (View-Taste reihum, Maus auf der Modus-Leiste): erst das Laufende sauber
## beenden (Getragenes zurück, Katalog zu, vom Sofa aufstehen), dann den neuen Modus.
func modus_wechseln(ziel: String) -> void:
	var jetzt := modus_gruppe(modus)
	if ziel == jetzt or modus in ["fahrt", "fernsehen", "anpassen", "rad", "baukasten"]:
		return
	if _kontext.offen():
		_kontext.schliessen()
	if modus == "katalog":
		_vorschau_weg()
		cursor = _katalog_feld
		_katalog_zu()
	if modus == "foto":
		_foto_aus()
	if modus == "sitzen":
		_aufstehen()
	if modus == "ansehen":
		_ansehen_ende()
	match ziel:
		"leben":
			if modus == "bauen":
				Sfx.play("back")
				_bauen_aus()
		"bauen":
			bauen_an()
		"foto":
			if modus == "bauen":
				_bauen_aus()
			fotomodus()
	_hinweise_auffrischen()


## Kontextmenü am Objekt öffnen; punkt: Ort im Raum, an dem es hängt (es wandert mit der Kamera).
func _kontext_auf(titel: String, eintraege: Array, punkt: Variant) -> void:
	if eintraege.is_empty():
		Sfx.play("bump")
		return
	_kontext_punkt = punkt
	_kontext.oeffnen(titel, eintraege, _kontext_anker)
	Sfx.play("open")
	_ziel_zeigen()
	_hinweise_auffrischen()


## Wo das Kontextmenü auf dem Schirm hängt (null: das Ding ist gerade nicht im Bild).
func _kontext_anker() -> Variant:
	if not (_kontext_punkt is Vector3):
		return null
	var cam: Camera3D = welt.kamera
	if cam.is_position_behind(_kontext_punkt):
		return null
	return cam.unproject_position(_kontext_punkt)


## Mitte eines Möbels im Raum (für das Kontextmenü), etwas über halber Höhe.
func _moebel_punkt(i: int) -> Variant:
	if i < 0 or i >= welt.boxen.size():
		return null
	var b: AABB = welt.boxen[i]
	return b.get_center() + Vector3(0, b.size.y * 0.15, 0)


## Bauen, Y auf einem Möbel: Hochheben, Drehen, Farbe (←/→ gleich am Möbel), Anpassen, Wegräumen.
func _aktionen_bauen(i: int) -> void:
	var t := str(raum.moebel[i].t)
	var e: Array = [{ "text": "Hochheben", "tun": func() -> void: _aufnehmen(i) }]
	if Katalog.ebene(t) != "wand":
		e.append({ "id": "drehen", "text": "Drehen", "tun": func() -> void: _drehen_idx(i, 1) })
	var vs := Katalog.varianten(t)
	if vs.size() > 1:
		var ids: Array = vs.map(func(v: Array) -> String: return str(v[0]))
		var blaettern := func(d: int) -> void:
			call("_variante_setzen", i, str(ids[posmod(ids.find(str(raum.moebel[i].v)) + d, ids.size())]), true)
			Sfx.play("move")
		e.append({ "id": "farbe", "text": Anpassen._varianten_name(t), "blaettern": blaettern,
			"wert": func() -> String: return tr(Katalog.variante_name(t, str(raum.moebel[i].v))) })
	if t == "spieleregal":
		e.append({ "id": "spiele", "text": "Spiele einräumen", "tun": func() -> void: regal_einraeumen(i) })
	# Was sonst auf dem Feld liegt (der Tisch unter der Tasse, das Bild über der Kommode, der Teppich)
	# lässt sich hier wählen – dann gelten A, Y und Drehen dafür. Am Rand: die Wand, an der es hängt.
	var mehr: Array = []
	if _wand == "":
		for j in Daten.alle_an_feld(raum, cursor.x, cursor.y):
			var jj := int(j)
			if jj != i and mehr.size() < 3:
				mehr.append({ "text": tr("%s wählen") % _moebel_name(str(raum.moebel[jj].t)), "roh": true, "tun": func() -> void: _waehlen(jj) })
	else:
		var seite := _wand
		mehr.append({ "text": "Wand gestalten", "tun": func() -> void: wand_gestalten(seite) })
		mehr.append({ "text": "Raum größer/kleiner", "tun": func() -> void: call("_wand_ziehen_auf", seite) })
	e.append_array(mehr)
	e.append({ "id": "anpassen", "text": "Anpassen", "tun": func() -> void: _anpassen_auf(_seiten.seite_moebel(i), i) })
	e.append({ "text": "Wegräumen", "gefahr": true, "tun": func() -> void: entfernen(i) })
	_kontext_auf(_moebel_name(t), kuerzen(e), _moebel_punkt(i))


## Höchstens sechs Zeilen (kontext_ui.gd): zuerst fällt, was auch eine Taste kann (Drehen: LB/RB),
## dann Spiele einräumen (am Regal selbst), die Farbe (Anpassen) und Anpassen – Hochheben, Wählen und
## Wegräumen bleiben immer.
static func kuerzen(e: Array) -> Array:
	var out := e.duplicate()
	for weg in ["drehen", "spiele", "farbe", "anpassen"]:
		if out.size() <= 6:
			break
		out = out.filter(func(x: Dictionary) -> bool: return str(x.get("id", "")) != weg)
	return out


## Ein anderes Möbel auf demselben Feld wählen (Y-Liste): es glimmt, das Schild zeigt es, seine Liste geht auf.
func _waehlen(i: int) -> void:
	if i < 0 or i >= (raum.moebel as Array).size():
		return
	_wahl = i
	Sfx.play("move")
	_raster_auffrischen()
	_ziel_zeigen()
	_hinweise_auffrischen()
	_aktionen_bauen.call_deferred(i)


## Leben, Y auf einem Möbel: was es kann, direkt am Möbel – beim Regal das Spiel im Blick, Spielseite,
## Durchsehen und Einrichten; beim Fernseher spielen und Vollbild; dazu immer Anpassen und Umstellen.
func _aktionen_laufen() -> void:
	if _ziel < 0 or _ziel_tier or _ziel_fenster:
		Sfx.play("bump")
		return
	var i := _ziel
	var it: Dictionary = raum.moebel[i]
	var t := str(it.t)
	var n := Katalog.nutzen(t)
	var e: Array = []
	var punkt: Variant = _moebel_punkt(i)
	match n:
		"spiele", "pokale", "platten":
			if not _bp.is_empty():
				var p := _bp
				punkt = _platz_lage(p, i)[0]
				e.append({ "text": _ziel_handlung(), "tun": func() -> void: _platz_nutzen(i, p) })
				if str(p.art) == "spiel":
					e.append({ "text": "Spielseite", "tun": func() -> void: main.open_game(p.daten) })
			if t == "spieleregal":
				e.append({ "text": "Spiele einräumen", "tun": func() -> void: regal_einraeumen(i) })
				if not regal_ids(i).is_empty():
					e.append({ "text": "Regal durchsehen", "tun": func() -> void: _ansehen(i) })
					e.append({ "text": "Alle ausräumen", "gefahr": true, "tun": func() -> void: regal_ausraeumen(i) })
			else:
				e.append({ "text": { "pokale": "Pokale ansehen", "platten": "Platten durchsehen" }.get(n, "Regal durchsehen"),
					"tun": func() -> void: _ansehen(i) })
			e.append({ "text": "Schrank einrichten" if t == "trophaeenschrank" else "Regal einrichten",
				"tun": func() -> void: _anpassen_auf(_seiten.seite_regal(i), i) })
		"fernseher":
			e.append_array(_tv_eintraege(i))
		"lampe":
			e.append({ "text": _ziel_handlung(), "tun": func() -> void: call("_benutzen") })
			e.append({ "text": "Licht einstellen", "tun": func() -> void: _anpassen_auf(_seiten.seite_lampe(i), i) })
		"musik":
			# Plattenspieler: Wiedergabe steuern, sonst der Weg zur Musik.
			if not Music.now.is_empty():
				e.append({ "text": _ziel_handlung(), "tun": func() -> void: Music.play_pause() })
				e.append({ "text": "Nächster Titel", "tun": func() -> void: Music.next() })
				e.append({ "text": "Vorheriger Titel", "tun": func() -> void: Music.previous() })
			e.append({ "text": "Musik öffnen", "tun": func() -> void: call("musik_oeffnen") })
		_:
			var a := _ziel_handlung()
			if a != "":
				e.append({ "text": a, "tun": func() -> void: call("_benutzen") })
	e.append_array(call("_aktionen_vorn", i))     # zimmer_umbau.gd: Verschieben, Ansehen
	e.append({ "text": "Anpassen", "tun": func() -> void: _anpassen_auf(_seiten.seite_moebel(i), i) })
	e.append({ "text": "Umstellen", "tun": func() -> void: bauen_an() })
	e.append({ "text": "Wegräumen", "gefahr": true, "tun": func() -> void:
		entfernen(i)
		_ziel = -2
		_ziel_suchen() })
	_kontext_auf(_moebel_name(t), e, punkt)


# --- Anpassen: Seitenleiste ----------------------------------------------------------------------

## Menü: das ganze Zimmer gestalten (Seitenleiste, Wände bis Stimmung).
func _zimmer_menue() -> void:
	if besuch:
		main.open_layer(OnlineUi.new())     # beim Besuch: nur „Zimmer online“ (Besuch verlassen)
		return
	_anpassen_auf(_seiten.seite_zimmer(), -1)


## Seitenleiste zu (B auf der ersten Seite): zurück, wo man herkam.
func _anpassen_zu() -> void:
	if modus != "anpassen":
		return
	_anp_moebel = -1
	if _vor_modus == "bauen":
		modus = "bauen"
		welt.raster.visible = true
		_raster_auffrischen()
		if _katalog_wieder:
			_katalog_wieder = false
			_katalog_auf(true)
	else:
		modus = "laufen"
		pos = _frei(pos)
		_ziel = -2
		_ziel_suchen()
	_rate = 3.0
	_kopf_auffrischen()
	_hinweise_auffrischen()


## Eine Wand direkt gestalten (im Einrichten einen Schritt über den Rand gewählt): das Bau-Menü bei
## „Wände und Tapeten“, nur für diese Wand; B führt zurück ins Einrichten.
func wand_gestalten(seite: String) -> void:
	_katalog.bereich("@waende", seite)
	_katalog_auf(true)


## Den Boden direkt gestalten (Y auf einem leeren Feld): das Bau-Menü bei „Böden“.
func boden_gestalten() -> void:
	_katalog.bereich("@boden")
	_katalog_auf(true)


## Aus der Seitenleiste: Online-Seite (Einladen, Gäste, Sperrliste) über dem Zimmer öffnen.
func online_oeffnen() -> void:
	_ui.schliessen()
	main.open_layer(OnlineUi.new())


## Wand: eine Seite oder alle („“), Feld m/f/mu/mf.
func wand_setzen(seite: String, k: String, v: Variant) -> void:
	wand_werte(seite, { k: v })


func wand_uebertragen(seite: String) -> void:
	_merken(true)
	for s in G.SEITEN:
		raum.waende[s] = (raum.waende[seite] as Dictionary).duplicate()
	(welt.huelle as Node).call("anpassen", raum, true)
	_melden(tr("Für alle Wände übernommen"))
	_geaendert()


## Boden, Sockel, Decke, Fenster, Tür: ein Feld setzen, weich zeigen.
func raum_setzen(bereich: String, k: String, v: Variant) -> void:
	raum_werte(bereich, { k: v })


## Licht des Raums: Tageszeit, Wetter, Farbtemperatur, Helligkeit, Lampen- und LED-Farbe. Eine
## eigene Änderung macht aus der Stimmung „eigene Einstellung“.
func licht_setzen(k: String, v: Variant) -> void:
	_merken()
	raum.licht[k] = v
	raum.licht.st = ""
	raum.licht = G.pruefe_licht(raum.licht)
	_licht_neu()
	_geaendert()


func stimmung_anwenden(id: String, merken := true) -> void:
	var l := G.stimmung(id)
	if l.is_empty():
		for s in daten.get("stimmungen", []):
			if str(s.id) == id:
				l = s.licht
	if l.is_empty():
		return
	if merken:
		_merken(true)
	var neu: Dictionary = raum.licht.duplicate()
	neu.merge(l, true)
	neu.st = id
	raum.licht = G.pruefe_licht(neu)
	_licht_neu()
	_geaendert()


func stimmung_speichern_fragen() -> void:
	if (daten.get("stimmungen", []) as Array).size() >= G.MAX_STIMMUNGEN:
		Sfx.play("error")
		_melden(tr("Höchstens %d eigene Stimmungen") % G.MAX_STIMMUNGEN)
		return
	main.open_keyboard("Name der Stimmung", "", func(t: String) -> void:
		var name_ := G.text(t, 30)
		if name_ == "":
			return
		_merken(true)
		var id := _neue_kennung("s_", (daten.stimmungen as Array).map(func(s: Dictionary) -> String: return str(s.id)))
		var l: Dictionary = raum.licht.duplicate()
		l.st = ""
		daten.stimmungen.append({ "id": id, "name": name_, "licht": l })
		raum.licht.st = id
		_melden(tr("Stimmung „%s“ gespeichert") % name_)
		_geaendert()
		_ui.auffrischen())


func stimmung_ueberschreiben(id: String) -> void:
	_merken(true)
	for s in daten.stimmungen:
		if str(s.id) == id:
			var l: Dictionary = raum.licht.duplicate()
			l.st = ""
			s.licht = l
	raum.licht.st = id
	_melden(tr("Stimmung gespeichert"))
	_geaendert()


func stimmung_loeschen(id: String) -> void:
	_merken(true)
	daten.stimmungen = (daten.stimmungen as Array).filter(func(s: Dictionary) -> bool: return str(s.id) != id)
	if str(raum.licht.st) == id:
		raum.licht.st = ""
	_ui.zurueck()
	_ui.auffrischen()
	_melden(tr("Stimmung gelöscht"))
	_geaendert()


static func _neue_kennung(praefix: String, vorhanden: Array) -> String:
	var zeichen := "abcdefghijklmnopqrstuvwxyz0123456789"
	for _v in 200:
		var id := praefix
		for _i in 6:
			id += zeichen[randi() % zeichen.length()]
		if not (id in vorhanden):
			return id
	return praefix + str(Time.get_ticks_usec() % 100000000)


# --- Stimmungs-Rad (LT) ---------------------------------------------------------------------------

func _rad_auf() -> void:
	var liste: Array = []
	var farben := { "gemuetlich": Color("#e7a35a"), "kino": Color("#34425e"), "neon": Color("#ff4fa3"),
		"morgen": Color("#f0d9a0"), "tag": Color("#8fb6d9"), "winter": Color("#c9d6e4") }
	for s in G.STIMMUNGEN:
		liste.append([s[0], s[1], farben.get(str(s[0]), Color("#e7c27d"))])
	for s in daten.get("stimmungen", []):
		var lf := str(s.licht.get("lf", ""))
		liste.append([str(s.id), str(s.name), Color(lf) if lf != "" else G.kelvin_farbe(float(s.licht.get("k", 2700))), true])
	_licht_vorher = raum.licht.duplicate()
	_vor_modus = modus
	modus = "rad"
	_glimmen_setzen(null)
	_ziel_zeigen()
	_rad.oeffnen("Stimmung", liste.slice(0, 12), str(raum.licht.get("st", "")))
	Sfx.play("open")
	_hinweise_auffrischen()


## Beim Drehen am Rad: Licht schon zeigen (ohne Rückgängig-Schritt).
func _stimmung_vorschau(id: String) -> void:
	var l := G.stimmung(id)
	if l.is_empty():
		for s in daten.get("stimmungen", []):
			if str(s.id) == id:
				l = s.licht
	var neu: Dictionary = _licht_vorher.duplicate()
	neu.merge(l, true)
	neu.st = id
	raum.licht = G.pruefe_licht(neu)
	_licht_neu()


func _stimmung_gewaehlt(id: String) -> void:
	# Rückgängig führt zum Licht vor dem Rad zurück.
	var jetzt: Dictionary = raum.licht
	raum.licht = _licht_vorher
	_merken(true)
	raum.licht = jetzt
	stimmung_anwenden(id, false)
	_rad_zu()
	_melden(tr("Stimmung: %s") % str(_seiten.call("_stimmung_name")))


func _stimmung_abgebrochen() -> void:
	raum.licht = _licht_vorher
	_licht_neu()
	_rad_zu()


func _rad_zu() -> void:
	modus = "laufen" if _vor_modus != "bauen" else "bauen"
	_ziel = -2
	if modus == "laufen":
		_ziel_suchen()
	_kopf_auffrischen()
	_hinweise_auffrischen()
	_speichern_bald()


# --- Möbel anpassen -------------------------------------------------------------------------------

## Ein Feld eines Möbels ändern (Farbe, Material, Muster, Größe, Beine, Griffe, Variante, an):
## leer heißt „wie im Katalog“. Neue Größe nur, wenn sie hier Platz hat.
func moebel_setzen(i: int, k: String, v: Variant) -> void:
	if i < 0 or i >= (raum.moebel as Array).size():
		return
	var it: Dictionary = raum.moebel[i]
	var neu := it.duplicate(true)
	if (v is String and v == "") or v == null:
		neu.erase(k)
	else:
		neu[k] = v
	var sauber := Daten.pruefe_moebel(neu)
	if sauber.is_empty():
		Sfx.play("error")
		return
	if k == "s" and not Daten.passt(raum, sauber, i):
		Sfx.play("error")
		_melden(tr("In dieser Größe ist hier kein Platz"))
		return
	_merken()
	raum.moebel[i] = sauber
	# Nur eine neue Größe ändert, wo etwas steht (Abstellfläche, Felder): dann alles neu. Farbe, Material,
	# Muster, Beine und Griffe bauen nur dieses Möbel neu – auch wenn etwas darauf steht (das sind eigene
	# Knoten; vorher baute jeder Schritt beim Durchblättern der Farben eines gedeckten Tischs alle Möbel neu).
	if k == "s":
		welt.alle_moebel()
	else:
		welt.moebel_neu(i)
	_geaendert()


## Licht einer Lampe: k Farbtemperatur (0 = wie das Zimmer), c Farbe, h Helligkeit, w Reichweite.
func lampe_setzen(i: int, k: String, v: Variant) -> void:
	if i < 0 or i >= (raum.moebel as Array).size():
		return
	_merken()
	var it: Dictionary = raum.moebel[i]
	var l: Dictionary = (it.get("l", {}) as Dictionary).duplicate()
	var std := { "k": 0, "c": "", "h": 100, "w": 100 }
	if v == std.get(k) or (v is String and v == ""):
		l.erase(k)
	else:
		l[k] = v
	l = G.pruefe_lampe(l)
	if l.is_empty():
		it.erase("l")
	else:
		it["l"] = l
	welt.lampen_auffrischen()
	_geaendert()


## Regal, Pokalschrank, Plattenregal: Auswahl, Sortierung, Darstellung …
func regal_setzen(i: int, k: String, v: Variant) -> void:
	if i < 0 or i >= (raum.moebel as Array).size():
		return
	_merken()
	var it: Dictionary = raum.moebel[i]
	var t := str(it.t)
	var rg: Dictionary = (it.get("rg", G.std_regal(t)) as Dictionary).duplicate(true)
	rg[k] = v
	if k == "so" and v == "manuell" and not rg.has("ma"):
		# Eigene Reihenfolge beginnt mit dem, was gerade im Regal steht.
		var jetzt := Inhalt.spiele(it.get("rg", {}))
		rg["ma"] = jetzt.slice(0, G.MAX_REIHE).map(func(g: Dictionary) -> String: return str(g.get("id", "")))
	rg = G.pruefe_regal(rg, t)
	if rg == G.std_regal(t):
		it.erase("rg")
	else:
		it["rg"] = rg
	welt.inhalt_fuellen()
	_geaendert()


# --- Spiele ein- und ausräumen ------------------------------------------------------------------------

## Was im Spieleregal i steht, als Spiel-IDs in seiner Reihenfolge.
func regal_ids(i: int) -> Array:
	if i < 0 or i >= (raum.moebel as Array).size():
		return []
	var it: Dictionary = raum.moebel[i]
	return Inhalt.spiele(it.get("rg", G.std_regal("spieleregal"))).map(func(g: Dictionary) -> String: return str(g.get("id", "")))


## Spiele einräumen bzw. ausräumen: das Raster deiner Bibliothek mit Covern (library_grid.gd,
## Auswahlmodus) – A räumt ein oder aus, neue kommen hinten dazu, X sucht, Y ordnet und filtert, B ist
## fertig. Danach steht im Regal genau das Angehakte (Auswahl „eigene“); die Reihenfolge änderst du
## beim Durchsehen mit LB/RB. Hatte das Regal eine andere Auswahl, beginnt die Liste mit dem, was drin stand.
func regal_einraeumen(i: int) -> void:
	if besuch_sperre():
		return
	if i < 0 or i >= (raum.moebel as Array).size() or str(raum.moebel[i].t) != "spieleregal" or main == null:
		Sfx.play("bump")
		return
	Sfx.play("open")
	var l = LibraryGrid.new()
	l.main = main
	l.sub_id = "zuletzt"
	l.label = tr("Regal einräumen")
	l.pick_liste = regal_ids(i).slice(0, G.MAX_REIHE)
	var vorher: Array = l.pick_liste.duplicate()
	var knoten_vorher := raum.moebel[i] as Dictionary
	l.pick_fertig = func(ids: Array) -> void:
		# Das Regal steht noch da (nicht inzwischen weggeräumt oder Raum gewechselt)?
		var j := (raum.moebel as Array).find(knoten_vorher)
		if not is_inside_tree() or _closing or j < 0 or ids == vorher:
			return
		regal_fuellen(j, ids)
	main.open_layer(l)


## Regal i enthält jetzt genau diese Spiele (IDs, in dieser Reihenfolge) – mit Rückgängig.
func regal_fuellen(i: int, ids: Array) -> void:
	if i < 0 or i >= (raum.moebel as Array).size() or str(raum.moebel[i].t) != "spieleregal":
		return
	_merken(true)
	var it: Dictionary = raum.moebel[i]
	var rg: Dictionary = (it.get("rg", G.std_regal("spieleregal")) as Dictionary).duplicate(true)
	if str(rg.get("fi", "")) != "eigene":
		rg["so"] = "manuell"
	rg["fi"] = "eigene"
	rg["ma"] = ids.slice(0, G.MAX_REIHE)
	rg = G.pruefe_regal(rg, "spieleregal")
	if rg == G.std_regal("spieleregal"):
		it.erase("rg")
	else:
		it["rg"] = rg
	welt.inhalt_fuellen()
	var n := regal_ids(i).size()
	_melden(tr("Regal leer") if n == 0 else (tr("1 Spiel im Regal") if n == 1 else tr("%d Spiele im Regal") % n))
	_geaendert()
	if modus == "laufen":
		_ziel = -2
		_ziel_suchen()
	elif modus == "anpassen":
		_ui.auffrischen()
	_hinweise_auffrischen()


## Alle Spiele aus dem Regal (Rückgängig mit X im Bauen bzw. in der Seitenleiste).
func regal_ausraeumen(i: int) -> void:
	Sfx.play("toggle_off")
	regal_fuellen(i, [])


func moebel_drehen(i: int) -> void:
	if i < 0 or i >= (raum.moebel as Array).size():
		return
	_drehen_idx(i, 1)
	_schritt_offen = true
	_ui.auffrischen()


func moebel_zuruecksetzen(i: int) -> void:
	if i < 0 or i >= (raum.moebel as Array).size():
		return
	var it: Dictionary = raum.moebel[i]
	var neu := { "t": it.t, "x": it.x, "z": it.z, "r": it.r, "v": Katalog.std_variante(str(it.t)), "an": true }
	if not Daten.passt(raum, neu, i):
		neu["s"] = it.get("s")
	_merken(true)
	raum.moebel[i] = Daten.pruefe_moebel(neu)
	welt.alle_moebel()
	_melden(tr("Wie im Katalog"))
	_geaendert()
	_ui.auffrischen()


func moebel_entfernen(i: int) -> void:
	_ui.schliessen()
	entfernen(i)


# --- Raum im Ganzen: Größe, Vorlagen, Hüllen ------------------------------------------------------

## Neue Raumgröße: Möbel an der rechten und vorderen Wand wandern mit, was nicht mehr passt, rückt
## an den nächsten freien Platz (sonst fällt es weg – Rückgängig holt alles zurück).
func groesse_setzen(w: int, d: int) -> void:
	w = clampi(w, Daten.MIN_FELDER, Daten.MAX_FELDER)
	d = clampi(d, Daten.MIN_FELDER, Daten.MAX_FELDER)
	if w == int(raum.w) and d == int(raum.d):
		return
	_merken(true)
	var weg := umziehen(raum, w, d)
	_welt_neu()
	if weg > 0:
		_melden(tr("%d Möbel hatten keinen Platz mehr") % weg)
	_geaendert()


## Möbel für eine neue Raumgröße umsetzen; gibt zurück, wie viele keinen Platz mehr fanden.
static func umziehen(r: Dictionary, w: int, d: int) -> int:
	var dw := w - int(r.w)
	var dd := d - int(r.d)
	var alt: Array = r.moebel
	# Was auf etwas steht, wandert mit seinem Träger.
	var traeger := {}
	for i in alt.size():
		for j in Daten.darauf(r, i):
			traeger[j] = i
	var verschiebung := {}
	for i in alt.size():
		var it: Dictionary = alt[i]
		var g := Katalog.groesse_it(it)
		var v := Vector2i.ZERO
		if int(it.x) + g.x == int(r.w):
			v.x = dw
		if int(it.z) + g.y == int(r.d):
			v.y = dd
		verschiebung[i] = v
	r.w = w
	r.d = d
	r.moebel = []
	var weg := 0
	# Erst alles, was auf dem Boden steht oder hängt, dann das Kleine darauf.
	var reihe: Array = range(alt.size())
	reihe.sort_custom(func(a: int, b: int) -> bool: return int(traeger.has(a)) < int(traeger.has(b)))
	for i in reihe:
		var it: Dictionary = (alt[i] as Dictionary).duplicate(true)
		var v: Vector2i = verschiebung[traeger.get(i, i)]
		it.x = int(it.x) + v.x
		it.z = int(it.z) + v.y
		var g := Katalog.groesse_it(it)
		it.x = clampi(int(it.x), 0, w - g.x)
		it.z = clampi(int(it.z), 0, d - g.y)
		if Katalog.ebene(str(it.t)) == "wand":
			var rr := Daten.wand_drehung(r, str(it.t), int(it.x), int(it.z), int(it.r), Katalog.stufe_von(it))
			if rr >= 0:
				it.r = rr
		if not Daten.passt(r, it):
			var frei: Variant = Daten.freie_stelle(r, str(it.t), int(it.x), int(it.z), int(it.r))
			if frei == null:
				weg += 1
				continue
			var f: Dictionary = frei
			it.x = f.x
			it.z = f.z
			it.r = f.r
			if not Daten.passt(r, it):
				weg += 1
				continue
		(r.moebel as Array).append(it)
	return weg


func vorlage_uebernehmen(id: String) -> void:
	var neu := Vorlagen.raum(id, str(raum.id), str(raum.name))
	var name_ := tr(Vorlagen.name_of(id))
	# Eigene Vorlage (z. B. ein geteiltes Zimmer): derselbe Prüfer wie jeder Raum.
	if neu.is_empty() and id.begins_with(Daten.VORLAGE_PRAEFIX):
		for v in daten.get("vorlagen", []):
			if str(v.id) == id:
				var r: Dictionary = (v.raum as Dictionary).duplicate(true)
				r.id = str(raum.id)
				r.name = str(raum.name)
				neu = Daten.pruefe_raum(r)
				name_ = str(v.name)
	if neu.is_empty():
		return
	_merken(true)
	for k in raum.keys():
		if not neu.has(k):
			raum.erase(k)
	for k in neu.keys():
		raum[k] = neu[k]
	_welt_neu()
	_melden(tr("Vorlage „%s“ – Rückgängig mit X") % name_)
	_geaendert()
	_ui.auffrischen()


func huelle_setzen(sid: String, art: String) -> void:
	_merken()
	if art == "auto":
		(daten.huellen as Dictionary).erase(sid)
	else:
		daten.huellen[sid] = art
	daten.huellen = G.pruefe_huellen(daten.huellen)
	welt.huellen = daten.huellen
	welt.inhalt_fuellen()
	_geaendert()


# --- Farben und eigene Möbel ------------------------------------------------------------------------

func eigene_farben() -> Array:
	return daten.get("farben", [])


## Eine selbst gemischte Farbe merken (vorn in der Liste, höchstens 16).
func farbe_merken(hex: String) -> void:
	var c := G.farbe(hex)
	if c == "":
		return
	var liste: Array = (daten.get("farben", []) as Array).filter(func(x: String) -> bool: return x != c)
	liste.push_front(c)
	daten.farben = liste.slice(0, G.MAX_EIGENE_FARBEN)
	_speichern_bald()


func baukasten_oeffnen(id: String) -> void:
	var d: Dictionary = Katalog.eigen(id).duplicate(true) if id != "" else {}
	if modus == "anpassen":
		_vor_modus = _vor_modus if _vor_modus in ["bauen", "laufen"] else "laufen"
		_ui.schliessen(true)
	elif modus != "baukasten":
		_vor_modus = modus if modus in ["bauen", "laufen"] else "laufen"
	modus = "baukasten"
	_glimmen_setzen(null)
	_ziel_zeigen()
	_baukasten.oeffnen(d)
	Sfx.play("open")
	_kopf_auffrischen()
	_hinweise_auffrischen()


## Fertig gebaut: geprüft speichern, Katalog und Zimmer auffrischen; ein neues Möbel kommt gleich
## in die Hand (im Einrichten).
func _baukasten_fertig(def: Dictionary) -> void:
	var neu := str(def.get("id", "")) == ""
	if neu:
		def.id = _neue_kennung(G.EIGEN_PRAEFIX, (daten.eigene as Array).map(func(e: Dictionary) -> String: return str(e.id)))
	var sauber := G.pruefe_eigenes(def)
	if sauber.is_empty():
		Sfx.play("error")
		_baukasten_zu()
		return
	_merken(true)
	var liste: Array = daten.eigene
	var gefunden := false
	for k in liste.size():
		if str(liste[k].id) == str(sauber.id):
			liste[k] = sauber
			gefunden = true
	if not gefunden:
		if liste.size() >= G.MAX_EIGENE:
			Sfx.play("error")
			_melden(tr("Höchstens %d eigene Möbel") % G.MAX_EIGENE)
			_baukasten_zu()
			return
		liste.append(sauber)
	Katalog.eigene_setzen(liste)
	KatalogUi.vergessen(str(sauber.id))
	# Größer geworden? Was nicht mehr passt, rückt weiter.
	var weg := umziehen(raum, int(raum.w), int(raum.d))
	_welt_neu()
	_speichern_bald()
	_melden(tr("„%s“ gespeichert") % str(sauber.name) + ("" if weg == 0 else " · " + tr("%d Möbel hatten keinen Platz mehr") % weg))
	_baukasten_zu()
	if neu:
		eigenes_hinstellen(str(sauber.id))


func _baukasten_zu() -> void:
	if modus != "baukasten":
		return
	modus = _vor_modus if _vor_modus in ["bauen", "laufen"] else "laufen"
	if modus == "bauen":
		welt.raster.visible = true
		_raster_auffrischen()
	_rate = 3.0
	_kopf_auffrischen()
	_hinweise_auffrischen()


func eigenes_hinstellen(id: String) -> void:
	if modus == "anpassen":
		_vor_modus = "bauen"
		_ui.schliessen()
	if modus != "bauen":
		bauen_an()
	nehmen(id)


func eigenes_kopieren(id: String) -> void:
	var e := Katalog.eigen(id)
	if e.is_empty() or (daten.eigene as Array).size() >= G.MAX_EIGENE:
		Sfx.play("error")
		return
	_merken(true)
	var c: Dictionary = e.duplicate(true)
	c.id = _neue_kennung(G.EIGEN_PRAEFIX, (daten.eigene as Array).map(func(x: Dictionary) -> String: return str(x.id)))
	c.name = G.text(tr("%s (Kopie)") % str(e.name), 40)
	daten.eigene.append(G.pruefe_eigenes(c))
	Katalog.eigene_setzen(daten.eigene)
	_melden(tr("Kopiert"))
	_ui.zurueck()
	_ui.auffrischen()
	_geaendert()


func eigenes_loeschen(id: String) -> void:
	_merken(true)
	daten.eigene = (daten.eigene as Array).filter(func(e: Dictionary) -> bool: return str(e.id) != id)
	raum.moebel = (raum.moebel as Array).filter(func(m: Dictionary) -> bool: return str(m.t) != id)
	Katalog.eigene_setzen(daten.eigene)
	KatalogUi.vergessen(id)
	_welt_neu()
	_melden(tr("Gelöscht – Rückgängig mit X"))
	_ui.zurueck()
	_ui.auffrischen()
	_geaendert()
