extends "res://src/ui/layers/layer.gd"
## Mosaik einer Konsole bzw. eines Ordners (A auf PS2 in der Quellen-Zeile der Startseite, A auf
## einem Ordner): Kacheln in festen Größen auf einem Raster (je Mosaik 2 × 2 bis 10 × 10), mehrere
## Seiten mit Punkten oben – keine Überschrift, nur das Raster und auf Wunsch ein eigener Hintergrund.
## Das Raster nimmt den ganzen Bildschirm ein (kleiner gleichmäßiger Rand, Zellen = Fläche geteilt
## durch Spalten × Zeilen); Kacheln sind Scheiben aus Liquid Glass (src/ui/components/glas.gd,
## docs/DESIGN.md › Mosaik: Liquid Glass). Seitenpunkte und Tastenzeile schweben als Glaspillen darüber.
## LB/RB oder das Steuerkreuz am Rand blättern. A öffnet Spiel bzw. Ordner, Y die Optionen des
## Spiels, Menü (bzw. A lang halten) schaltet „Gestalten“ ein.
##
## Gestalten: A auf einer Kachel öffnet ihre Möglichkeiten (Bild, Ausschnitt, Schriftzug, Größe,
## Verschieben, Entfernen), X wechselt die Größe, Y hebt sie zum Verschieben an (Steuerkreuz, A
## legt ab). A auf einem leeren Feld legt etwas hin: Spiel, Ordner, Bild oder Platzhalter. B ist
## fertig. Bilder und Platzhalter sind reine Gestaltung – ohne Gestalten überspringt sie der Cursor.
## Im Menü: Raster (Steuerkreuz ändert Spalten und Zeilen mit Vorschau) und Hintergrund (Bild bzw.
## Farbe, Ausschnitt, Abdunklung). Ausschnitte wandern stufenlos mit dem Stick, LT/RT zoomen; A
## übernimmt, B bricht ab. Bilder kommen auch vom Handy (QR-Code, Seite im Heimnetz, mosaik_handy.gd).
## Die Logik (Raster, Auto-Mosaik, Speichern) steht in src/library/mosaik.gd.

const Mosaik := preload("res://src/library/mosaik.gd")
const Regal := preload("res://src/library/regal.gd")
const Kachel := preload("res://src/ui/components/mosaik_kachel.gd")
const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")

const Glas := preload("res://src/ui/components/glas.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")
const Handy := preload("res://src/ui/layers/mosaik_handy.gd")
const Einfuehrung := preload("res://src/ui/layers/mosaik_einfuehrung.gd")

const Main := preload("res://src/main.gd")
var main: Main
var quelle := ""             ## wie in der Quellen-Zeile: „ps2“, „ordner:f_123“
var label := ""
var _d := {}                 ## { eigen, kacheln, weg }
var _seite := 0
var _bearbeiten := false
var _gepackt := ""           ## Kachel, die gerade verschoben wird
var _ausschnitt := ""        ## Kachel, deren Fokuspunkt gerade wandert
var _ziel := ""              ## Fokus nach dem Neuaufbau: Kachel-ID oder „z:s:x:y“
var _zelle := Vector2(270, 238)
var _luecke := 22.0
var _raster_x := 0.0             ## linke Kante des Rasters (mittig)
var _rand := 16.0                ## Rand um das Raster (wächst und schrumpft mit den Zellen)
var _pille: Control              ## Glaspille der Seitenpunkte (mit den Pfeilen)
var _tasten: Control             ## Glaspille der Tastenzeile
var _raster: Control
var _punkte: HBoxContainer
var _modus: Control
var _modus_l: Label
var _grund: Control              ## eigener Hintergrund der Seite (Bild bzw. Farbe)
var _halt: Button                ## im Raster- und Ausschnitt-Modus: A übernimmt
var _raster_modus := false
var _vorher := {}                ## Stand vor Raster bzw. Ausschnitt (B bricht ab)
var _infos: Array = []           ## für das Auto-Mosaik (Vorschau in anderem Raster)
var _einzug := "staffel"         ## wie der nächste Aufbau kommt (siehe _bewegen)
var _pfeil_l: Control
var _pfeil_r: Control
var _spiel_ids := {}         ## Spiele, die auf diesem Mosaik gelten (gezeigt werden dürfen)
var _stale := false


static func ist_mosaik(sub_id: String) -> bool:
	if sub_id.begins_with("ordner:"):
		return true
	var sys := Config.system(sub_id)
	return not sys.is_empty() and not sub_id in ["steam", "epic", "ea", "pc"]


func _ordner_id() -> String:
	return quelle.substr(7) if quelle.begins_with("ordner:") else ""


func build() -> void:
	# Weniger abgedunkelt als andere Ebenen: Das Glas lebt vom Raum bzw. Bild dahinter.
	dim = 0.55
	_scrim.color = Color(UzTheme.col("bg"), dim)
	# Die Tastenzeile liegt als Glaspille im Bild (unten rechts), nicht als Leiste darunter.
	set_meta("uz_hints_eigen", true)
	set_meta("uz_ohne_auslauf", true)
	LibraryGrid.hide_shell(main, self)
	if main:
		closed.connect(func() -> void:
			var gs: Variant = main.sections.get("games")
			if gs is Object and (gs as Object).has_method("restore_background"):
				(gs as Object).call("restore_background")
		)
	Mosaik.sicher_geladen(Config.path(Mosaik.DATEI), Library.demo)
	var vs := U.view_size()
	_grund = Grund.new()
	U.full_rect(_grund)
	add_child(_grund)
	_grund_neu()
	# Schatten und Scheiben aller Kacheln: je ein Knoten für alle (eine Kopie des Schirms je Bild).
	for sch in [true, false]:
		var u := Unterlage.new()
		u.wurzel = self
		u.schatten = sch
		U.full_rect(u)
		add_child(u)
	_raster = Control.new()
	_raster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raster)
	if not Glas.einfach():
		# Die Pillen darüber brechen die Kacheln, nicht den leeren Raum: einmal neu kopieren.
		var bb := BackBufferCopy.new()
		bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(bb)
	_kopf(vs)
	_halt = Button.new()
	_halt.flat = true
	_halt.focus_mode = Control.FOCUS_ALL
	_halt.modulate.a = 0.0
	_halt.position = Vector2(-10, -10)
	_halt.size = Vector2(1, 1)
	_halt.visible = false
	_halt.pressed.connect(_modus_fertig)
	add_child(_halt)
	set_process(false)
	Library.changed.connect(_on_library_changed)
	Nav.focus_moved.connect(_on_focus_moved)
	_modell()
	_bauen()
	# Einmal beim ersten Mosaik: was sich alles gestalten lässt.
	if main and Einfuehrung.faellig():
		_einfuehrung.call_deferred()


func _einfuehrung() -> void:
	if not is_inside_tree() or _closing:
		return
	var e = Einfuehrung.new()
	e.los = func() -> void: _gestalten(true)
	main.open_layer(e)


## No heading at the top: only a small glass pill with the page dots (with arrows at the ends when there are
## pages before or after) and, while arranging, an accent pill on the left showing the current mode.
## Bottom right: the button hint row in a glass pill.
func _kopf(vs: Vector2) -> void:
	_modus = U.panel("accent", UzTheme.r_pill(), 0)
	_modus_l = U.label("Gestalten", "s", "bg", "bold")
	_modus_l.clip_text = false
	var mm := U.margin(14, 4, 14, 4)
	mm.add_child(_modus_l)
	_modus.add_child(mm)
	_modus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modus.position = Vector2(_rand + 18, _rand + 14)
	_modus.visible = false
	add_child(_modus)
	_pille = Pille.new()
	_pille.polster(10, 6)
	var reihe := U.hbox(8)
	reihe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pille.add_child(reihe)
	_pfeil_l = _pfeil("chevron_left", reihe)
	_punkte = U.hbox(10)
	_punkte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reihe.add_child(_punkte)
	_pfeil_r = _pfeil("chevron_right", reihe)
	_pille.position = Vector2(vs.x * 0.5, _rand + 10)
	_pille.set_meta("mz_mitte", true)
	add_child(_pille)
	# Tastenzeile (HintBar mit inside): zeigt genau dann etwas, wenn diese Ebene oben liegt.
	_tasten = Pille.new()
	_tasten.polster(20, 8)
	_tasten.anchor_left = 1.0
	_tasten.anchor_top = 1.0
	_tasten.anchor_right = 1.0
	_tasten.anchor_bottom = 1.0
	_tasten.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tasten.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tasten.offset_right = -_rand - 10
	_tasten.offset_bottom = -_rand - 10
	var hb := HintBar.new()
	hb.inside = true
	hb.gap = 22
	_tasten.add_child(hb)
	hb.sort_children.connect(func() -> void: _tasten.visible = hb.get_child_count() > 0)
	add_child(_tasten)
	hb.refresh.call_deferred(true)


func _pfeil(name: String, reihe: Control) -> Control:
	var ic := U.icon(name, 20, "muted")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reihe.add_child(ic)
	return ic


# --- Modell --------------------------------------------------------------------------------------

func _spiele() -> Array:
	var fid := _ordner_id()
	if fid != "":
		return Library.sorted(Library.in_folder(fid))
	return Library.sorted(Library.by_tab(quelle))


## Ordner, die von selbst auf das Mosaik einer Konsole kommen (nicht die, die in einem anderen
## Ordner angelegt wurden).
func _ordner() -> Array:
	if _ordner_id() != "":
		return []
	return Library.folders_for(quelle).filter(func(f: Dictionary) -> bool: return str(f.get("in", "")) == "").map(func(f: Dictionary) -> String: return str(f.id))


func _modell() -> void:
	var spiele := _spiele()
	_spiel_ids.clear()
	if _ordner_id() != "":
		for g in spiele:
			_spiel_ids[str(g.id)] = true
	var d := Mosaik.holen(quelle)
	_infos.clear()
	if d.is_empty():
		for g in spiele:
			_infos.append({ "id": str(g.id), "fav": bool(g.get("favorite", false)), "zeit": Library.playtime(g),
				"zuletzt": Library.last_played(g), "breit": _breit(g) })
		var ra := Mosaik.raster(quelle)
		_d = { "eigen": false, "cols": ra.x, "rows": ra.y, "kacheln": Mosaik.auto(_infos, _ordner(), ra), "weg": [] }
	else:
		_d = d
		if Mosaik.abgleichen(_d, spiele.map(func(g: Dictionary) -> String: return str(g.id)), _ordner()):
			Mosaik.ablegen(quelle, _d)


## Hat das Spiel ein breites Bild (Hintergrund)? Steam & Co. bringen eins mit, Emulator-Spiele nur
## mit eigenem bzw. geladenem Bild.
static func _breit(g: Dictionary) -> bool:
	var imgs: Variant = g.get("images", {})
	if imgs is Dictionary and str((imgs as Dictionary).get("hero", "")) != "":
		return true
	if str(g.get("source", "")) != "rom":
		return true
	return Media.local_path(g, "hero") != ""


## Gibt es das Spiel bzw. den Ordner einer Kachel gerade (sonst wird sie nicht gezeigt)?
func _ist_da(k: Dictionary) -> bool:
	match str(k.get("art", "")):
		"spiel":
			var g := Library.get_game(str(k.ref))
			if g.is_empty() or not Library.is_visible(g):
				return false
			return _ordner_id() == "" or _spiel_ids.has(str(k.ref))
		"ordner":
			var fid := str(k.ref)
			if fid.begins_with("auto:"):
				return not Library.in_folder(fid).is_empty()
			return not Library.folder(fid).is_empty()
	return true


func _fehlt(k: Dictionary) -> bool:
	return not _ist_da(k)


func _sichtbar() -> Array:
	return Mosaik.sichtbar(_d.kacheln, _ist_da)


func _seiten() -> int:
	var n := Mosaik.seiten(_sichtbar())
	# Im Gestalten gibt es hinten immer eine leere Seite zum Weiterbauen.
	if _bearbeiten and not _sichtbar().filter(func(k: Dictionary) -> bool: return int(k.s) == n - 1).is_empty():
		n += 1
	return mini(n, Mosaik.MAX_SEITEN)


func _ra() -> Vector2i:
	return Mosaik.raster_von(_d)


## Erste Änderung: aus dem Auto-Mosaik wird das eigene (Ausgangspunkt bleibt, was zu sehen war).
func _aendern() -> void:
	_d["eigen"] = true
	Mosaik.ablegen(quelle, _d)


# --- Aufbau --------------------------------------------------------------------------------------

func _bauen() -> void:
	var fokus_war := _ziel
	if fokus_war == "":
		var f := Nav.focused()
		if f and _raster.is_ancestor_of(f):
			fokus_war = str(f.get_meta("mz_id", ""))
	_ziel = ""
	# Bewegung (docs/DESIGN.md › Bewegung): Wo jede Kachel eben stand, um von dort weich an den neuen
	# Platz zu morphen (Lage und Größe) – auch, wenn das Raster selbst seine Größe ändert.
	var einzug := _einzug
	_einzug = ""
	var alt := {}
	# Kacheln, die sich nicht geändert haben, bleiben dieselben Knoten (nur Lage und Größe ändern
	# sich): Ein Umbau einer vollen 10 × 10-Seite baut so nicht 100 Kacheln neu (kein Ruckeln).
	var alte := {}
	for c in _raster.get_children():
		if c is Control and c.has_meta("mz_id") and not c.is_queued_for_deletion():
			alte[str(c.get_meta("mz_id"))] = c
			if einzug == "":
				alt[str(c.get_meta("mz_id"))] = Rect2((c as Control).position + _raster.position, (c as Control).size)
		elif not c.has_meta("mz_id"):
			_raster.remove_child(c)
			c.queue_free()
	if einzug == "staffel":
		for c in alte.values():
			_raster.remove_child(c)
			c.queue_free()
		alte.clear()
	_geometrie()
	var ra := _ra()
	var vis := _sichtbar()
	var n := _seiten()
	_seite = clampi(_seite, 0, n - 1)
	var nimm: Control = null
	var belegt := {}
	for k in vis:
		if int(k.s) != _seite:
			continue
		var c := _kachel_wieder(alte, k)
		for yy in int(k.h):
			for xx in int(k.w):
				belegt[(int(k.y) + yy) * ra.x + int(k.x) + xx] = true
		if str(k.id) == fokus_war:
			nimm = c
	if _bearbeiten:
		for y in ra.y:
			for x in ra.x:
				if belegt.has(y * ra.x + x):
					continue
				var zid := "z:%d:%d:%d" % [_seite, x, y]
				var z: Control = alte.get(zid)
				if z:
					alte.erase(zid)
				else:
					z = _zelle_leer(x, y)
					z.set_meta("mz_sig", "zelle")
					_raster.add_child(z)
				if str(z.get_meta("mz_id")) == fokus_war:
					nimm = z
	for c in alte.values():
		_raster.remove_child(c)
		c.queue_free()
	_bewegen(einzug, alt)
	_kopf_neu(vis, n)
	if _raster_modus or _ausschnitt != "":
		# Raster bzw. Ausschnitt einstellen: A gehört dem unsichtbaren Halt (übernehmen).
		for c in _raster.get_children():
			(c as Control).focus_mode = Control.FOCUS_NONE
		_halt.visible = true
		_halt.set_meta("uz_hint_a", "Übernehmen")
		Nav.focus(_halt, true)
		Nav.focus_moved.emit(_halt)
		return
	_halt.visible = false
	for c in _raster.get_children():
		if "waehlbar" in c:
			(c as Control).focus_mode = Control.FOCUS_ALL if bool(c.get("waehlbar")) else Control.FOCUS_NONE
	if nimm == null:
		nimm = _erstes()
	if nimm:
		# Die gewählte Kachel rückt in der Reihenfolge nach hinten (Kachel._fokus); was die Ebene beim
		# Öffnen wählt (Nav.default_in), sagt darum uz_default.
		for c in _raster.get_children():
			c.remove_meta("uz_default")
		nimm.set_meta("uz_default", true)
		Nav.focus(nimm, true)
		Nav.focus_moved.emit(nimm)
	else:
		_leer_halt()


## Zellen für das Raster: Es füllt den ganzen Bildschirm (schirm) bis auf einen schmalen, gleichmäßigen
## Rand; jede Zelle ist die Fläche geteilt durch Spalten × Zeilen – in 21:9 also breiter, in 16:10
## höher, 2 × 2 groß, 10 × 10 klein. Abstand und Rand wachsen und schrumpfen mit der Zellgröße.
static func zellen_mass(ra: Vector2i, schirm: Vector2) -> Dictionary:
	var grob := minf(schirm.x / ra.x, schirm.y / ra.y)
	var luecke := roundf(clampf(grob * 0.07, 6.0, 22.0))
	# Some space to the screen edge, but not much: twice the gap, clamped to 32–48.
	var rand := clampf(luecke * 2.0, 32.0, 48.0)
	var fl := schirm - Vector2(rand, rand) * 2.0
	var w := floorf((fl.x - luecke * (ra.x - 1)) / ra.x)
	var h := floorf((fl.y - luecke * (ra.y - 1)) / ra.y)
	return { "zelle": Vector2(w, h), "luecke": luecke, "rand": rand }


func _geometrie() -> void:
	var vs := U.view_size()
	var ra := _ra()
	var m := zellen_mass(ra, vs)
	_zelle = m.zelle
	_luecke = float(m.luecke)
	_rand = float(m.rand)
	_raster.size = Vector2(_zelle.x * ra.x + _luecke * (ra.x - 1), _zelle.y * ra.y + _luecke * (ra.y - 1))
	# Was beim Abrunden auf ganze Punkte übrig bleibt, verteilt sich auf beide Seiten.
	_raster_x = roundf((vs.x - _raster.size.x) * 0.5)
	_raster.position = Vector2(_raster_x, roundf((vs.y - _raster.size.y) * 0.5))
	if is_instance_valid(_modus):
		_modus.position = Vector2(_rand + 18, _rand + 14)
		_tasten.offset_right = -_rand - 10
		_tasten.offset_bottom = -_rand - 10


## Neu gebaute Kacheln bewegen: „staffel“ – gestaffelt aufbauen (Öffnen), „seite“ – nichts einzeln
## (die ganze Seite gleitet, _blaettern), sonst morphen alte Kacheln von ihrem alten Platz und ihrer
## alten Größe her, neue wachsen kurz auf. Alles über den Takt (U.ankommen, T_ORT), im ersten Bild.
func _bewegen(einzug: String, alt: Dictionary) -> void:
	if einzug == "seite":
		return
	var ra := _ra()
	for c in _raster.get_children():
		var kc := c as Control
		if kc == null or not kc.has_meta("mz_rect"):
			continue
		var r: Rect2i = kc.get_meta("mz_rect")
		var id := str(kc.get_meta("mz_id", ""))
		if einzug == "staffel":
			# Von links oben nach rechts unten, höchstens vier Gruppen (U.staffel).
			var gruppe := clampi(floori((r.position.x + r.position.y) * 4.0 / maxf(1.0, ra.x + ra.y - 1)), 0, 3)
			var ziel := kc.position
			kc.modulate.a = 0.0
			kc.position.y += U.weg_px(U.W_ANSTOSS * 2.0)
			var tw := U.ankommen(kc, U.T_ORT, "mz_auf").set_parallel(true)
			tw.tween_property(kc, "modulate:a", 1.0, U.T_ORT).set_delay(U.staffel(gruppe))
			tw.tween_property(kc, "position", ziel, U.T_ORT).set_delay(U.staffel(gruppe))
		elif alt.has(id):
			var von: Rect2 = alt[id]
			von.position -= _raster.position
			var nach := Rect2(kc.position, kc.size)
			if von.is_equal_approx(nach) or U.reduziert():
				continue
			kc.position = von.position
			kc.size = von.size
			var tw2 := U.ankommen(kc, U.T_ORT, "mz_morph").set_parallel(true)
			tw2.tween_property(kc, "position", nach.position, U.T_ORT)
			tw2.tween_property(kc, "size", nach.size, U.T_ORT)
		elif not alt.is_empty() and not id.begins_with("z:"):
			# Neu dazugekommen (Hinzufügen, Umbau): wächst kurz auf.
			kc.modulate.a = 0.0
			kc.scale = Vector2.ONE * U.wachsen(0.92)
			var tw3 := U.ankommen(kc, U.T_ORT, "mz_neu").set_parallel(true)
			tw3.tween_property(kc, "modulate:a", 1.0, U.T_ORT)
			tw3.tween_property(kc, "scale", Vector2.ONE, U.T_ORT)


## Was eine Kachel ausmacht (ohne Lage): Gleich bleibende Kacheln werden wiederverwendet.
func _sig(k: Dictionary) -> String:
	var bits := [k.art, k.get("ref", ""), k.get("bild", {}), k.get("logo", false), _bearbeiten, str(k.id) == _gepackt, str(k.id) == _ausschnitt]
	if str(k.art) == "ordner":
		# Mit dem Raster: Vorschau, Name und Anzahl richten sich nach der Größe der Kachel.
		bits.append_array([Library.folder(str(k.ref)).get("name", ""), Library.in_folder(str(k.ref)).size(), Mosaik.ordner_bild(str(k.ref)), _ra()])
	return JSON.stringify(bits)


func _kachel_wieder(alte: Dictionary, k: Dictionary) -> Control:
	var id := str(k.id)
	var sig := _sig(k)
	var c: Control = alte.get(id)
	if c and str(c.get_meta("mz_sig", "")) == sig:
		alte.erase(id)
		var r := _rect(int(k.x), int(k.y), int(k.w), int(k.h))
		c.position = r.position
		c.size = r.size
		c.set_meta("mz_rect", Rect2i(int(k.x), int(k.y), int(k.w), int(k.h)))
		return c
	c = _kachel(k)
	c.set_meta("mz_sig", sig)
	_raster.add_child(c)
	return c


func _rect(x: int, y: int, w: int, h: int) -> Rect2:
	return Rect2(Vector2(x * (_zelle.x + _luecke), y * (_zelle.y + _luecke)),
		Vector2(w * _zelle.x + (w - 1) * _luecke, h * _zelle.y + (h - 1) * _luecke))


func _kachel(k: Dictionary) -> Control:
	var r := _rect(int(k.x), int(k.y), int(k.w), int(k.h))
	var w := { "art": str(k.art), "bild": k.get("bild", {}), "logo": bool(k.get("logo", false)) }
	var g := {}
	match str(k.art):
		"spiel":
			g = Library.get_game(str(k.ref))
			w["spiel"] = g
		"ordner":
			var fid := str(k.ref)
			var f := Library.folder(fid)
			var inhalt := Library.in_folder(fid)
			w["name"] = str(f.get("name", ""))
			w["unter"] = U.plural(inhalt.size(), "Spiel", "Spiele")
			# Ohne eigenes Bild: reines Glas mit den ersten Spielen als Vorschau. Beim Ausschnitt (und
			# danach als Ordner-Bild gemerkt) zeigt der Ordner das erste Spiel (Cover bzw. in breiten
			# Kacheln sein Hintergrund) im Fenster.
			var ob := Mosaik.ordner_bild(fid)
			w["bild"] = ob
			var sortiert := Library.sorted(inhalt)
			if not inhalt.is_empty():
				var erst: Dictionary = sortiert[0]
				w["ersatz"] = erst
				if ob.is_empty():
					w["bild"] = { "art": "hero" if r.size.x > r.size.y * 1.4 and _breit(erst) else "cover", "fx": 0.5, "fy": 0.3 }
			if ob.is_empty() and str(k.id) != _ausschnitt:
				w["vorschau"] = sortiert.slice(0, 4)
	var c = Kachel.new().setup(w, r.size)
	c.position = r.position
	c.bearbeiten = _bearbeiten
	c.gepackt = str(k.id) == _gepackt
	c.ausschnitt = str(k.id) == _ausschnitt
	c.set_meta("mz_id", str(k.id))
	c.set_meta("mz_rect", Rect2i(int(k.x), int(k.y), int(k.w), int(k.h)))
	c.set_meta("uz_grid_nav", _nav)
	c.set_meta("uz_key", "mz:" + str(k.id))
	var kid := str(k.id)
	if not _bearbeiten:
		if not Mosaik.waehlbar(k):
			c.waehlbar = false
			return c
		c.set_meta("uz_on_hold_a", func() -> void: _gestalten(true, kid))
		if str(k.art) == "spiel":
			c.set_meta("uz_hint_a", "Spielen" if not main or not main.game_page_on() else "Öffnen")
			c.set_meta("uz_hint_y", "Optionen")
			c.set_meta("uz_on_y", func() -> void:
				var gg := Library.get_game(str(k.ref))
				if not gg.is_empty() and main:
					main.open_game_options(gg)
			)
			c.gewaehlt.connect(func() -> void:
				var gg := Library.get_game(str(k.ref))
				if not gg.is_empty() and main:
					main.open_game(gg)
			)
		else:
			c.set_meta("uz_hint_a", "Ordner öffnen")
			c.set_meta("uz_hint_y", "Optionen")
			c.set_meta("uz_on_y", func() -> void:
				var f := Library.folder(str(k.ref))
				if not f.is_empty() and main:
					main.open_folder_options(f)
			)
			c.gewaehlt.connect(func() -> void: _ordner_oeffnen(str(k.ref)))
		c.focus_entered.connect(_zeigen.bind(k))
		return c
	# Gestalten
	if kid == _gepackt:
		c.set_meta("uz_hint_a", "Ablegen")
		c.gewaehlt.connect(_ablegen)
	elif kid == _ausschnitt:
		c.set_meta("uz_hint_a", "Fertig")
		c.gewaehlt.connect(_modus_fertig)
	else:
		c.set_meta("uz_hint_a", "Bearbeiten")
		c.set_meta("uz_hint_x", "Größe")
		c.set_meta("uz_hint_y", "Verschieben")
		c.set_meta("uz_on_x", func() -> void: _groesse_weiter(kid))
		c.set_meta("uz_on_y", func() -> void: _packen(kid))
		c.gewaehlt.connect(func() -> void: _kachel_menue(kid))
	c.focus_entered.connect(_zeigen.bind(k))
	return c


func _zelle_leer(x: int, y: int) -> Control:
	var r := _rect(x, y, 1, 1)
	var c = Kachel.new().setup({ "art": "zelle" }, r.size)
	c.position = r.position
	var zid := "z:%d:%d:%d" % [_seite, x, y]
	c.set_meta("mz_id", zid)
	c.set_meta("mz_rect", Rect2i(x, y, 1, 1))
	c.set_meta("uz_grid_nav", _nav)
	c.set_meta("uz_key", "mz:" + zid)
	c.set_meta("uz_hint_a", "Hinzufügen")
	c.gewaehlt.connect(func() -> void: _hinzufuegen(_seite, x, y))
	return c


## Ohne wählbare Kachel (nur Bilder, leere Seite): ein unsichtbarer Halt, damit B und Menü gehen.
func _leer_halt() -> void:
	var hold := Control.new()
	hold.focus_mode = Control.FOCUS_ALL
	hold.custom_minimum_size = Vector2(1, 1)
	hold.set_meta("uz_hint_a", "—")
	hold.set_meta("mz_rect", Rect2i(0, 0, 1, 1))
	hold.set_meta("uz_grid_nav", _nav)
	_raster.add_child(hold)
	Nav.focus(hold, true)


func _erstes() -> Control:
	var best: Control = null
	var bk := INF
	for c in _waehlbare():
		var r: Rect2i = c.get_meta("mz_rect")
		var key := r.position.y * _ra().x + r.position.x
		if key < bk:
			bk = key
			best = c
	return best


func _waehlbare() -> Array:
	return _raster.get_children().filter(func(c: Node) -> bool:
		return c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and (c as Control).has_meta("mz_rect") and not (c as Control).is_queued_for_deletion())


func _kopf_neu(_vis: Array, n: int) -> void:
	var ra := _ra()
	_modus.visible = _bearbeiten or _raster_modus or _ausschnitt != ""
	if _raster_modus:
		_modus_l.text = tr("Raster %d × %d") % [ra.x, ra.y]
	elif _ausschnitt != "":
		_modus_l.text = tr("Ausschnitt")
	else:
		_modus_l.text = tr("Gestalten")
	_modus.reset_size()
	U.clear(_punkte)
	for i in n:
		var p := Panel.new()
		var on := i == _seite
		p.custom_minimum_size = Vector2(26 if on else 10, 10)
		p.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("accent") if on else Color(UzTheme.col("faint"), 0.8), 5))
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_punkte.add_child(p)
	var pill := _punkte.get_parent().get_parent() as Control
	pill.visible = n > 1
	pill.reset_size()
	_pille_mitte.call_deferred()
	if is_instance_valid(_pfeil_l):
		_pfeil_l.visible = _seite > 0
		_pfeil_r.visible = _seite < n - 1
	_hinweise()


func _pille_mitte() -> void:
	if not is_instance_valid(_punkte):
		return
	var pill := _punkte.get_parent().get_parent() as Control
	pill.reset_size()
	pill.position = Vector2(roundf(U.view_size().x * 0.5 - pill.size.x * 0.5), _rand + 10)


func _hinweise() -> void:
	if _raster_modus:
		set_meta("uz_hint_b", "Abbrechen")
		set_meta("uz_hints", [["lr", "Spalten"], ["ud", "Zeilen"]])
	elif _ausschnitt != "":
		# Stick verschiebt stufenlos, LT/RT zoomen, A übernimmt, B bricht ab.
		set_meta("uz_hint_b", "Abbrechen")
		set_meta("uz_hints", [["lr", "Verschieben"], ["rt", "Zoom"]])
	elif _gepackt != "":
		# A legt ab (B ebenso, ohne zweiten Hinweis); das Steuerkreuz bewegt.
		set_meta("uz_hint_b", "")
		set_meta("uz_hints", [["lr", "Verschieben"]])
	elif _bearbeiten:
		set_meta("uz_hint_b", "Fertig")
		set_meta("uz_hints", [])
	else:
		remove_meta("uz_hint_b")
		# Gestalten geht auch mit A lang auf einer Kachel – das steht mit dabei.
		set_meta("uz_hints", [["menu", "Gestalten (A halten)"]])
	Nav.focus_moved.emit(Nav.focused())


## Ohne Überschrift sagt nur der Raum etwas: dahinter leise die Farbe des gewählten Spiels (nicht,
## wenn die Seite einen eigenen Hintergrund hat – der deckt den Raum ohnehin).
func _zeigen(k: Dictionary) -> void:
	if str(k.art) == "spiel" and main and main.background and not _grund.visible:
		var g := Library.get_game(str(k.ref))
		if not g.is_empty():
			main.background.show_game(g)


# --- Steuerung -----------------------------------------------------------------------------------

## Steuerkreuz auf dem Raster: nächste wählbare Kachel in der Richtung (in Zellen gerechnet); am
## Rand links/rechts weiter auf die Seite davor bzw. dahinter.
func _nav(now: Control, dir: String) -> bool:
	if not now.has_meta("mz_rect"):
		return false
	var a: Rect2i = now.get_meta("mz_rect")
	var best: Control = null
	var best_s := INF
	for c in _waehlbare():
		if c == now:
			continue
		var b: Rect2i = c.get_meta("mz_rect")
		var haupt := 0.0
		var quer := 0.0
		match dir:
			"right":
				if b.position.x < a.end.x:
					continue
				haupt = b.position.x - a.end.x
				quer = _abstand(a.position.y, a.end.y, b.position.y, b.end.y)
			"left":
				if b.end.x > a.position.x:
					continue
				haupt = a.position.x - b.end.x
				quer = _abstand(a.position.y, a.end.y, b.position.y, b.end.y)
			"down":
				if b.position.y < a.end.y:
					continue
				haupt = b.position.y - a.end.y
				quer = _abstand(a.position.x, a.end.x, b.position.x, b.end.x)
			"up":
				if b.end.y > a.position.y:
					continue
				haupt = a.position.y - b.end.y
				quer = _abstand(a.position.x, a.end.x, b.position.x, b.end.x)
		var ca := Vector2(a.position) + Vector2(a.size) * 0.5
		var cb := Vector2(b.position) + Vector2(b.size) * 0.5
		var mitte := absf(cb.y - ca.y) if dir in ["left", "right"] else absf(cb.x - ca.x)
		var s := haupt + quer * 2.5 + mitte * 0.3
		if s < best_s:
			best_s = s
			best = c
	if best:
		Nav.focus(best)
		return true
	if dir == "left" and _seite > 0:
		_blaettern(-1, a.position.y)
		return true
	if dir == "right" and _seite < _seiten() - 1:
		_blaettern(1, a.position.y)
		return true
	return false


static func _abstand(a1: int, a2: int, b1: int, b2: int) -> float:
	return maxf(0.0, float(maxi(a1, b1) - mini(a2, b2)))


## Seite wechseln; zeile ≥ 0: vom Rand kommend die Kachel nahe dieser Zeile an der Eintrittskante.
func _blaettern(d: int, zeile := -1) -> void:
	var n := _seiten()
	var neu := clampi(_seite + d, 0, n - 1)
	if neu == _seite:
		Sfx.play("bump")
		return
	_seite = neu
	Sfx.play("tab")
	# Die alte Seite geht mit Tiefe: gleitet gegen die Richtung, wird kleiner und kreuzt aus
	# (U.abgang); die neue kommt im selben Bild aus der Tiefe nach vorn.
	var hulle := U.abgang(_raster, d, true)
	if hulle and not U.reduziert():
		hulle.pivot_offset = hulle.size * 0.5
		U.weg(hulle, "mz_tiefe").tween_property(hulle, "scale", hulle.scale * 0.96, U.T_WEG)
	_einzug = "seite"
	_bauen()
	if zeile >= 0:
		var best: Control = null
		var bs := INF
		for c in _waehlbare():
			var r: Rect2i = c.get_meta("mz_rect")
			var kante := float(r.position.x) if d > 0 else float(_ra().x - r.end.x)
			var s := kante * 4.0 + absf(r.position.y - zeile)
			if s < bs:
				bs = s
				best = c
		if best:
			Nav.focus(best, true)
	# Die neue Seite gleitet aus der Richtung herein und wächst aus der Tiefe (T_RAUM: ein Raum
	# wechselt), die Deckkraft ist schon nach T_ORT da.
	var w := U.weg_px(U.W_BEREICH) * d
	_raster.pivot_offset = _raster.size * 0.5
	_raster.position.x = _raster_x + w
	_raster.scale = Vector2.ONE * U.wachsen(0.96)
	_raster.modulate.a = 0.0
	var tw := U.ankommen(_raster, U.T_RAUM, "mz_seite").set_parallel(true)
	tw.tween_property(_raster, "position:x", _raster_x, U.T_RAUM)
	tw.tween_property(_raster, "scale", Vector2.ONE, U.T_RAUM)
	tw.tween_property(_raster, "modulate:a", 1.0, U.T_ORT).set_trans(Tween.TRANS_CUBIC)


## Richtungen gehören beim Verschieben, beim Raster und beim Ausschnitt der Seite, nicht dem Cursor.
func nav_dir(cmd: String) -> bool:
	var dv: Vector2i = { "left": Vector2i(-1, 0), "right": Vector2i(1, 0), "up": Vector2i(0, -1), "down": Vector2i(0, 1) }.get(cmd, Vector2i.ZERO)
	if _ausschnitt != "":
		# Stufenlos in _process (Stick und gehaltenes Steuerkreuz); die Schritte von Nav zählen nicht.
		return true
	if _raster_modus:
		var ra := _ra() + dv
		if ra.x < Mosaik.MIN_RASTER or ra.y < Mosaik.MIN_RASTER or ra.x > Mosaik.MAX_RASTER or ra.y > Mosaik.MAX_RASTER:
			Sfx.play("bump")
			return true
		Sfx.play("tick")
		_raster_vorschau(ra)
		return true
	if _gepackt != "":
		var s := Mosaik.verschieben(_d.kacheln, _ra(), _gepackt, dv.x, dv.y, _fehlt)
		if s < 0:
			Sfx.play("bump")
			return true
		var gewechselt := s != _seite
		_seite = s
		_aendern()
		Sfx.play("tick")
		_ziel = _gepackt
		_bauen()
		if gewechselt:
			_raster.modulate.a = 0.0
			U.ankommen(_raster, U.T_ORT, "mz_seite").tween_property(_raster, "modulate:a", 1.0, U.T_ANTWORT)
		return true
	return false


func _im_modus() -> bool:
	return _gepackt != "" or _ausschnitt != "" or _raster_modus


func handle(cmd: String) -> bool:
	match cmd:
		"lb", "rb":
			if not _im_modus():
				_blaettern(-1 if cmd == "lb" else 1)
			return true
		"lt", "rt":
			# Tastatur bzw. Druck: Zoom in Schritten (der Controller zoomt stufenlos über die Achse).
			if _ausschnitt != "":
				_ausschnitt_aendern(Vector2.ZERO, 0.1 if cmd == "rt" else -0.1)
			return true
		"menu":
			if not _im_modus():
				_menue()
			return true
	return false


func nav_command(cmd: String) -> bool:
	if cmd == "b":
		if _gepackt != "":
			Sfx.play("back")
			_ablegen()
			return true
		if _ausschnitt != "" or _raster_modus:
			Sfx.play("back")
			_modus_abbrechen()
			return true
		if _bearbeiten:
			Sfx.play("back")
			_gestalten(false)
			return true
	return super(cmd)


func _control_von(id: String) -> Control:
	for c in _raster.get_children():
		if str(c.get_meta("mz_id", "")) == id:
			return c
	return null


func _on_library_changed() -> void:
	_stale = true
	_auffrischen.call_deferred()


func _on_focus_moved(_c: Control) -> void:
	if _stale:
		_auffrischen()


func _auffrischen() -> void:
	if not _stale or not is_inside_tree() or Nav.top_layer() != self:
		return
	_stale = false
	_modell()
	_bauen()


# --- Gestalten -----------------------------------------------------------------------------------

func _gestalten(an: bool, fokus := "") -> void:
	_bearbeiten = an
	_gepackt = ""
	_ausschnitt = ""
	_raster_modus = false
	set_process(false)
	if not an and bool(_d.get("eigen", false)):
		Mosaik.seiten_schliessen(_d.kacheln)
		Mosaik.ablegen(quelle, _d)
	_ziel = fokus
	Sfx.play("open" if an else "back")
	_bauen()


func _packen(id: String) -> void:
	_gepackt = id
	_ziel = id
	_bauen()
	_hinweise()


func _ablegen() -> void:
	_ziel = _gepackt
	_gepackt = ""
	_bauen()


# --- Ausschnitt (stufenlos) und Raster ----------------------------------------------------------

## Ausschnitt einer Kachel (id) bzw. des Hintergrunds („_grund“): der Stick verschiebt, LT/RT zoomen.
func _ausschnitt_start(id: String) -> void:
	var b := _bild_id(id)
	if b.is_empty():
		return
	_vorher = { "bild": b.duplicate() }
	_ausschnitt = id
	_ziel = id
	set_process(true)
	_bauen()
	_hinweise()


func _process(dt: float) -> void:
	if _ausschnitt == "":
		set_process(false)
		return
	var v := Vector2.ZERO
	var zoom := 0.0
	for dev in Input.get_connected_joypads():
		var st := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if st.length() > 0.18:
			v += st * ((st.length() - 0.18) / 0.82 / st.length())
		zoom += Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
	v += Vector2(float(Input.is_action_pressed("uz_right")) - float(Input.is_action_pressed("uz_left")),
		float(Input.is_action_pressed("uz_down")) - float(Input.is_action_pressed("uz_up")))
	if v.length() > 1.0:
		v = v.normalized()
	if absf(zoom) < 0.08:
		zoom = 0.0
	if v != Vector2.ZERO or zoom != 0.0:
		# Etwa eine halbe Bildbreite je Sekunde bei vollem Ausschlag; Zoom verdoppelt in gut einer Sekunde.
		_ausschnitt_aendern(v * dt * 0.55, zoom * dt * 1.4)


func _ausschnitt_aendern(dv: Vector2, dz: float) -> void:
	var b := _bild_id(_ausschnitt)
	if b.is_empty():
		return
	var z := clampf(float(b.get("z", 1.0)) + dz * float(b.get("z", 1.0)), 1.0, Mosaik.ZOOM_MAX)
	b["fx"] = clampf(float(b.get("fx", 0.5)) + dv.x, 0.0, 1.0)
	b["fy"] = clampf(float(b.get("fy", 0.5)) + dv.y, 0.0, 1.0)
	b["z"] = z
	_bild_id_setzen(_ausschnitt, b, false, false)
	if _ausschnitt == "_grund":
		_grund_neu()
	else:
		var c := _control_von(_ausschnitt)
		if c:
			c.call("set_fokuspunkt", float(b.fx), float(b.fy), z)


## Raster einstellen: Vorschau mit dem Steuerkreuz, A übernimmt, B bricht ab.
func _raster_start() -> void:
	_vorher = { "d": _d.duplicate(true) }
	_raster_modus = true
	_gepackt = ""
	_bauen()
	_hinweise()


## Vorschau in ra: Eine eigene Anordnung wird umgebaut (immer vom Stand vor dem Einstellen aus, damit
## Verkleinern und wieder Vergrößern nichts verschiebt), das Auto-Mosaik neu angelegt.
func _raster_vorschau(ra: Vector2i) -> void:
	var alt: Dictionary = _vorher.get("d", _d)
	var neu := alt.duplicate(true)
	neu["cols"] = ra.x
	neu["rows"] = ra.y
	if bool(alt.get("eigen", false)):
		neu["kacheln"] = Mosaik.umbauen(alt.kacheln, Mosaik.raster_von(alt), ra)
	else:
		neu["kacheln"] = Mosaik.auto(_infos, _ordner(), ra)
	_d = neu
	_seite = mini(_seite, Mosaik.seiten(_d.kacheln) - 1)
	_bauen()


## A im Raster- bzw. Ausschnitt-Modus: übernehmen und speichern.
func _modus_fertig() -> void:
	if _raster_modus:
		_raster_modus = false
		if bool(_d.get("eigen", false)):
			Mosaik.ablegen(quelle, _d)
		else:
			Mosaik.raster_setzen(quelle, _ra())
		Sfx.play("select")
	elif _ausschnitt != "":
		var id := _ausschnitt
		var b := _bild_id(id)
		_ausschnitt = ""
		set_process(false)
		_bild_id_setzen(id, b, false, true)
		_ziel = id if id != "_grund" else ""
	_vorher = {}
	_bauen()
	_hinweise()


func _modus_abbrechen() -> void:
	if _raster_modus:
		_raster_modus = false
		_d = _vorher.get("d", _d)
	elif _ausschnitt != "":
		var id := _ausschnitt
		_ausschnitt = ""
		set_process(false)
		if _vorher.has("bild"):
			_bild_id_setzen(id, _vorher.bild, false, false)
		_grund_vorschau = {}
		_ordner_vorschau.clear()
		_grund_neu()
		_ziel = id if id != "_grund" else ""
	_vorher = {}
	_bauen()
	_hinweise()


func _groesse_weiter(id: String) -> void:
	var k := Mosaik.finde(_d.kacheln, id)
	if k.is_empty():
		return
	var g := Mosaik.naechste_groesse(int(k.w), int(k.h))
	_groesse(id, int(g[0]), int(g[1]))


func _groesse(id: String, w: int, h: int) -> void:
	if Mosaik.groesse(_d.kacheln, _ra(), id, w, h, _fehlt):
		_aendern()
		_ziel = id
		_bauen()


## Was A auf einer Kachel im Gestalten anbietet.
func _kachel_menue(id: String) -> void:
	var k := Mosaik.finde(_d.kacheln, id)
	if k.is_empty() or not main:
		return
	var art := str(k.art)
	var opts: Array = []
	if art != "leer":
		opts.append(["bild", "Bild wählen"])
		if art != "ordner" or not Mosaik.ordner_bild(str(k.ref)).is_empty() or not Library.in_folder(str(k.ref)).is_empty():
			opts.append(["ausschnitt", "Ausschnitt"])
	if art == "spiel":
		opts.append(["logo", "Schriftzug ausblenden" if bool(k.get("logo", false)) else "Schriftzug zeigen"])
	opts.append(["groesse", "Größe", tr(Mosaik.groesse_name(int(k.w), int(k.h)))])
	opts.append(["packen", "Verschieben"])
	if art == "ordner":
		opts.append(["fuellen", "Spiele auswählen"])
		if not str(k.ref).begins_with("auto:"):
			opts.append(["umbenennen", "Umbenennen"])
	var weg_text := "Entfernen"
	if art == "spiel":
		weg_text = "Aus dem Ordner nehmen" if _ordner_id() != "" else "Vom Mosaik nehmen"
	elif art == "ordner":
		weg_text = "Vom Mosaik nehmen"
	opts.append(["weg", weg_text])
	main.open_choice(_name_von(k), opts, null, func(v: Variant) -> void:
		match str(v):
			"bild": _bild_quellen.call_deferred(id)
			"ausschnitt": _ausschnitt_start(id)
			"logo":
				var kk := Mosaik.finde(_d.kacheln, id)
				if bool(kk.get("logo", false)):
					kk.erase("logo")
				else:
					kk["logo"] = true
				_aendern()
				_ziel = id
				_bauen()
			"groesse": _groessen_wahl.call_deferred(id)
			"packen": _packen(id)
			"fuellen": _ordner_fuellen.call_deferred(str(k.ref))
			"umbenennen": _ordner_umbenennen.call_deferred(str(k.ref))
			"weg": _entfernen(id)
	)


func _name_von(k: Dictionary) -> String:
	match str(k.art):
		"spiel": return Library.display_title(Library.get_game(str(k.ref)))
		"ordner": return str(Library.folder(str(k.ref)).get("name", "Ordner"))
		"bild": return tr("Bild")
	return tr("Platzhalter")


func _groessen_wahl(id: String) -> void:
	var k := Mosaik.finde(_d.kacheln, id)
	if k.is_empty():
		return
	var opts: Array = []
	for g in Mosaik.GROESSEN:
		opts.append(["%d:%d" % [g[0], g[1]], str(g[2]), "%d × %d" % [g[0], g[1]]])
	main.open_choice("Größe", opts, "%d:%d" % [int(k.w), int(k.h)], func(v: Variant) -> void:
		var p := str(v).split(":")
		_groesse(id, int(p[0]), int(p[1]))
	)


func _entfernen(id: String) -> void:
	var k := Mosaik.finde(_d.kacheln, id)
	if k.is_empty():
		return
	var art := str(k.art)
	if art == "spiel" and _ordner_id() != "":
		Library.set_in_folder(str(k.ref), _ordner_id(), false)
	elif k.has("ref") and not (_d.weg as Array).has(str(k.ref)):
		(_d.weg as Array).append(str(k.ref))
	(_d.kacheln as Array).erase(k)
	_aendern()
	_bauen()


## A auf einem leeren Feld: was dort hinkommt.
func _hinzufuegen(s: int, x: int, y: int) -> void:
	if not main:
		return
	var opts: Array = [["spiel", "Spiel"], ["ordner", "Ordner erstellen"]]
	var frei := _freie_ordner()
	if not frei.is_empty():
		opts.append(["ordner_da", "Vorhandener Ordner"])
	opts.append(["bild", "Bild"])
	opts.append(["leer", "Platzhalter"])
	main.open_choice("Hinzufügen", opts, null, func(v: Variant) -> void:
		match str(v):
			"spiel": _spiel_wahl.call_deferred(s, x, y)
			"ordner": _ordner_neu.call_deferred(s, x, y)
			"ordner_da": _ordner_wahl.call_deferred(s, x, y)
			"bild":
				var id := _einsetzen({ "art": "bild", "w": 2, "h": 1 }, s, x, y)
				if id != "":
					_bild_quellen.call_deferred(id)
			"leer": _einsetzen({ "art": "leer", "w": 1, "h": 1 }, s, x, y)
	)


## Neue Kachel an Zelle (s, x, y); was dort nur unsichtbar lag (fehlendes Spiel), weicht.
func _einsetzen(k: Dictionary, s: int, x: int, y: int) -> String:
	var ks: Array = _d.kacheln
	for o in ks.duplicate():
		var trifft := x < int(o.x) + int(o.w) and int(o.x) < x + int(k.get("w", 1)) and y < int(o.y) + int(o.h) and int(o.y) < y + int(k.get("h", 1))
		if _fehlt(o) and int(o.s) == s and trifft:
			ks.erase(o)
	if not Mosaik.einsetzen(ks, _ra(), k, s, x, y):
		Toasts.show_toast("Kein Platz mehr", label, "warning")
		return ""
	if k.has("ref"):
		(_d.weg as Array).erase(str(k.ref))
	_aendern()
	_seite = int(k.s)
	_ziel = str(k.id)
	_bauen()
	return str(k.id)


func _spiel_wahl(s: int, x: int, y: int) -> void:
	var da := {}
	for k in _sichtbar():
		if str(k.art) == "spiel":
			da[str(k.ref)] = true
	var opts: Array = []
	# Den Titel je Spiel einmal holen, dann sortieren (nicht zweimal je Vergleich – bei Tausenden Spielen spürbar).
	var paare: Array = []
	for g in Library.visible_games():
		if not da.has(str(g.id)):
			paare.append([Library.display_title(g), g])
	paare.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]).naturalnocasecmp_to(str(b[0])) < 0)
	for p in paare:
		var g: Dictionary = p[1]
		var sys := Config.system(str(g.get("system", "")))
		opts.append([str(g.id), str(p[0]), Library.store_name(g, true, str(sys.get("short", sys.get("name", ""))))])
	if opts.is_empty():
		Toasts.show_toast("Alle Spiele liegen schon hier", label, "check")
		return
	main.open_choice("Spiel hinzufügen", opts, null, func(v: Variant) -> void:
		var gid := str(v)
		var fid := _ordner_id()
		if fid != "":
			_spiel_ids[gid] = true
			Library.set_in_folder(gid, fid, true)
		_einsetzen({ "art": "spiel", "ref": gid, "w": 1, "h": 2, "bild": { "art": "cover", "fx": 0.5, "fy": 0.5 } }, s, x, y)
	)


func _freie_ordner() -> Array:
	var da := {}
	for k in _sichtbar():
		if str(k.art) == "ordner":
			da[str(k.ref)] = true
	var eigen := _ordner_id()
	return Library.folders.filter(func(f: Dictionary) -> bool: return not da.has(str(f.id)) and str(f.id) != eigen)


func _ordner_wahl(s: int, x: int, y: int) -> void:
	var opts: Array = []
	for f in _freie_ordner():
		opts.append([str(f.id), str(f.name), U.plural(Library.in_folder(str(f.id)).size(), "Spiel", "Spiele")])
	main.open_choice("Ordner hinzufügen", opts, null, func(v: Variant) -> void:
		_einsetzen({ "art": "ordner", "ref": str(v), "w": 1, "h": 1 }, s, x, y)
	)


## Ordner erstellen: Name, dann Spiele hineinlegen, dann das Cover wählen. s < 0: hinten anfügen.
func _ordner_neu(s := -1, x := 0, y := 0) -> void:
	if not main:
		return
	main.open_keyboard("Name des Ordners", "", func(n: String) -> void:
		if n.strip_edges() == "":
			return
		var parent := _ordner_id()
		var sys := quelle if parent == "" else str(Library.folder(parent).get("system", ""))
		var fid := Library.create_folder(n, sys)
		if fid == "":
			return
		var f := Library.folder(fid)
		if parent != "" and not f.is_empty() and not f.has("in"):
			# Unterordner: gehört in diesen Ordner, nicht noch einmal aufs Mosaik der Konsole.
			f["in"] = parent
			Library.mark_dirty()
		var id := ""
		if s >= 0:
			id = _einsetzen({ "art": "ordner", "ref": fid, "w": 1, "h": 1 }, s, x, y)
		else:
			var k := { "art": "ordner", "ref": fid, "w": 1, "h": 1 }
			(_d.weg as Array).erase(fid)
			if Mosaik.anhaengen(_d.kacheln, _ra(), k):
				_aendern()
				id = str(k.id)
				_seite = int(k.s)
				_ziel = id
				_bauen()
		Toasts.show_toast("Ordner angelegt", n.strip_edges(), "folder")
		_ordner_neu_weiter.call_deferred(fid, id)
	)


## Nach dem Namen (die Tastatur ist zu): Spiele hineinlegen, danach das Cover wählen.
func _ordner_neu_weiter(fid: String, id: String) -> void:
	var l := _ordner_fuellen(fid)
	if l and id != "":
		l.closed.connect(func() -> void: _bild_quellen.call_deferred(id))


## Spiele für einen Ordner an- und abhaken – aus allen Systemen (eine Sammlung darf mischen).
func _ordner_fuellen(fid: String) -> Control:
	if not main:
		return null
	var f := Library.folder(fid)
	var l = LibraryGrid.new()
	l.sub_id = "ordner:" + fid
	l.pick_folder = fid
	l.pick_all = true
	l.label = tr("„%s“ füllen") % str(f.get("name", "Ordner"))
	main.open_layer(l)
	return l


func _ordner_umbenennen(fid: String) -> void:
	var f := Library.folder(fid)
	main.open_keyboard("Name des Ordners", str(f.get("name", "")), func(n: String) -> void:
		Library.rename_folder(fid, n)
	)


func _ordner_oeffnen(fid: String) -> void:
	if not main:
		return
	var f := Library.folder(fid)
	var l = get_script().new()
	l.quelle = "ordner:" + fid
	l.label = str(f.get("name", "Ordner"))
	l.main = main
	main.open_layer(l)


# --- Bilder --------------------------------------------------------------------------------------
# Ziel eines Bildes: eine Kachel (ihre ID) oder der Hintergrund der Seite („_grund“).

## Wirksames Bild einer Kachel (Ordner: das Ordner-Bild), als Kopie zum Ändern.
func _bild_von(k: Dictionary) -> Dictionary:
	if str(k.get("art", "")) == "ordner":
		var ob: Dictionary = _ordner_vorschau.get(str(k.ref), Mosaik.ordner_bild(str(k.ref)))
		if ob.is_empty():
			var inhalt := Library.in_folder(str(k.ref))
			ob = { "art": "cover", "fx": 0.5, "fy": 0.3 } if not inhalt.is_empty() else {}
		return ob.duplicate()
	var b: Variant = k.get("bild", {})
	return (b as Dictionary).duplicate() if b is Dictionary and not (b as Dictionary).is_empty() else { "art": "cover", "fx": 0.5, "fy": 0.5 }


func _bild_id(id: String) -> Dictionary:
	if id == "_grund":
		var h: Dictionary = _grund_daten()
		return (h.get("bild", {}) as Dictionary).duplicate()
	var k := Mosaik.finde(_d.kacheln, id)
	return _bild_von(k) if not k.is_empty() else {}


## Bild setzen; speichern: gleich in mosaik.json (beim stufenlosen Ausschnitt erst am Ende).
func _bild_id_setzen(id: String, b: Dictionary, neu_bauen := true, speichern := true) -> void:
	if id == "_grund":
		var h := _grund_daten().duplicate(true)
		var sb := Mosaik.bild_sauber(b)
		if sb.is_empty():
			h.erase("bild")
		else:
			h["bild"] = sb
		if not h.has("dunkel"):
			h["dunkel"] = 0.35
		if speichern:
			_grund_vorschau = {}
			Mosaik.hintergrund_setzen(quelle, h)
		else:
			_grund_vorschau = h
		_grund_neu()
		return
	var k := Mosaik.finde(_d.kacheln, id)
	if k.is_empty():
		return
	if str(k.art) == "ordner":
		# Das Ordner-Bild gilt überall, wo der Ordner liegt (auch auf anderen Mosaiken).
		if speichern:
			_ordner_vorschau.erase(str(k.ref))
			Mosaik.ordner_bild_setzen(str(k.ref), b)
		else:
			_ordner_vorschau[str(k.ref)] = Mosaik.bild_sauber(b)
	else:
		var sb := Mosaik.bild_sauber(b)
		if sb.is_empty():
			k.erase("bild")
		else:
			k["bild"] = sb
		if speichern:
			_aendern()
	if neu_bauen:
		_ziel = id
		_bauen()


var _grund_vorschau := {}       ## Hintergrund, solange sein Ausschnitt noch wandert
var _ordner_vorschau := {}      ## Ordner-Bilder, solange ihr Ausschnitt noch wandert


## Woher das Bild kommt: Bilder des Spiels, SteamGridDB (Spiel bzw. Stichwort), eigene Datei, Handy.
func _bild_quellen(id: String) -> void:
	if not main:
		return
	var k := {} if id == "_grund" else Mosaik.finde(_d.kacheln, id)
	if id != "_grund" and k.is_empty():
		return
	var art := "grund" if id == "_grund" else str(k.art)
	var opts: Array = []
	var cur := str(_bild_id(id).get("art", ""))
	if art == "spiel":
		opts.append_array([["cover", "Cover"], ["hero", "Hintergrund"], ["logo", "Schriftzug"]])
	elif art == "ordner":
		opts.append(["auto", "Wie das erste Spiel"])
	else:
		opts.append(["spiel", "Bild eines Spiels"])
	opts.append(["sgdb", "SteamGridDB", "Suchen"])
	opts.append(["handy", "Vom Handy", "Suchen und hochladen"])
	opts.append(["datei", "Eigene Datei", "Medienordner"])
	main.open_choice("Bild wählen", opts, cur, func(v: Variant) -> void:
		match str(v):
			"cover", "hero", "logo":
				var b := _bild_id(id)
				b["art"] = str(v)
				b.erase("pfad")
				_bild_id_setzen(id, b)
			"auto":
				Mosaik.ordner_bild_setzen(str(k.ref), {})
				_ziel = id
				_bauen()
			"sgdb": _sgdb.call_deferred(id)
			"handy": _handy.call_deferred(id)
			"datei": _datei.call_deferred(id)
			"spiel": _bild_aus_spiel.call_deferred(id)
	)


func _datei_nehmen(id: String, pfad: String) -> void:
	if not Mosaik.pfad_ok(pfad) or not FileAccess.file_exists(pfad):
		Toasts.show_toast("Bild ließ sich nicht öffnen", "Eine PNG-, JPG- oder WebP-Datei wählen.", "warning")
		return
	# Nur den Kopf prüfen (Format nach den ersten Bytes, Größe); dekodiert wird später im
	# Hintergrund über Media (Image.load_*_from_buffer mit denselben Grenzen), nie als Ressource.
	var f := FileAccess.open(pfad, FileAccess.READ)
	var dims := Media.image_dims(f.get_buffer(mini(f.get_length(), 1 << 20))) if f else Vector2i(-1, -1)
	if dims.x <= 0 or dims.y <= 0 or dims.x > Media.IMG_MAX_SIDE or dims.y > Media.IMG_MAX_SIDE or dims.x * dims.y > Media.IMG_MAX_PIXELS:
		Toasts.show_toast("Bild ließ sich nicht öffnen", "Ein PNG, JPG oder WebP bis 8192 Punkte wählen.", "warning")
		return
	_bild_id_setzen(id, { "art": "datei", "pfad": pfad, "fx": 0.5, "fy": 0.5 })


func _datei(id: String) -> void:
	main.open_file_browser("Bild wählen", false, func(p: String) -> void: _datei_nehmen(id, p), Mosaik.ENDUNGEN, Config.media_dir())


## Bild vom Handy: QR-Code, auf dem Handy selbst suchen (Link zur Bildersuche) und hochladen. Uzai
## speichert es neu kodiert im Medienordner (mosaik_handy.gd, Mosaik.bild_aus_bytes).
func _handy(id: String) -> void:
	var l = Handy.new()
	l.stichwort = _stichwort(id)
	l.fertig.connect(func(p: String) -> void: _datei_nehmen(id, p))
	main.open_layer(l)


## Name für die Suche: Spiel, Ordner bzw. diese Seite.
func _stichwort(id: String) -> String:
	var k := {} if id == "_grund" else Mosaik.finde(_d.kacheln, id)
	match str(k.get("art", "")):
		"spiel": return Library.display_title(Library.get_game(str(k.ref)))
		"ordner": return str(Library.folder(str(k.ref)).get("name", ""))
	return label


## SteamGridDB über die bestehende Bildwahl (art_picker.gd): für ein Spiel dessen Bilder, für
## Ordner, Bilder und den Hintergrund nach Stichwort. Das gewählte Bild landet im Medienordner.
func _sgdb(id: String) -> void:
	var k := {} if id == "_grund" else Mosaik.finde(_d.kacheln, id)
	var oeffnen := func(g: Dictionary, wort: String, quelle := "sgdb") -> void:
		var l = main._rare("art_picker").new()
		l.game = g
		l.stichwort = wort
		l.quelle = quelle
		l.ziel = func(p: String) -> void: _datei_nehmen(id, p)
		main.open_layer(l)
	if str(k.get("art", "")) == "spiel":
		var g := Library.get_game(str(k.ref))
		if Media.ss_bildwahl_ok(g):
			# Auch ScreenScraper (Scans, Schriftzüge, Szenen) zur Wahl – Emulator- und PC-Spiele.
			main.open_choice("Bild von", [["sgdb", "SteamGridDB"], ["ss", "ScreenScraper"]], "", func(v: Variant) -> void:
				oeffnen.call(g, "", str(v))
			)
			return
		oeffnen.call(g, "")
		return
	main.open_keyboard("Stichwort für SteamGridDB", _stichwort(id), func(t: String) -> void:
		if t.strip_edges() != "":
			oeffnen.call({}, t.strip_edges())
	)


## Bild eines Spiels für eine Bild-Kachel bzw. den Hintergrund: Spiel, dann Art; gemerkt wird die Datei.
func _bild_aus_spiel(id: String) -> void:
	var opts: Array = []
	var liste := _spiele() if not _spiele().is_empty() else Library.visible_games()
	for g in liste:
		opts.append([str(g.id), Library.display_title(g)])
	main.open_choice("Bild eines Spiels", opts, null, func(v: Variant) -> void:
		var g := Library.get_game(str(v))
		(func() -> void:
			main.open_choice("Bild wählen", [["cover", "Cover"], ["hero", "Hintergrund"], ["logo", "Schriftzug"]], null, func(kind: Variant) -> void:
				Media.game_file(g, str(kind), func(p: String) -> void:
					if p == "":
						Toasts.show_toast("Kein Bild gefunden", Library.display_title(g), "image", { "sub_raw": true })
					else:
						_datei_nehmen(id, p)
				)
			)).call_deferred()
	)


# --- Hintergrund der Seite -----------------------------------------------------------------------

func _grund_daten() -> Dictionary:
	return _grund_vorschau if not _grund_vorschau.is_empty() else Mosaik.hintergrund(quelle)


## Eigenen Hintergrund zeigen (oder den üblichen Raum, wenn keiner gesetzt ist). Ein Wechsel (anderes
## Bild, andere Farbe, an oder aus) kreuzt weich in T_LICHT – nur der Ausschnitt folgt dem Stick sofort.
func _grund_neu() -> void:
	if not is_instance_valid(_grund):
		return
	var h := _grund_daten()
	var b: Dictionary = h.get("bild", {})
	var pfad := str(b.get("pfad", ""))
	var farbe := Color(str(h.get("farbe", "#000000"))) if h.has("farbe") else UzTheme.col("bg")
	var an := not h.is_empty()
	var live := _ausschnitt == "_grund"
	var wechsel: bool = not live and (pfad != str(_grund.get("pfad")) or farbe != _grund.get("farbe") or an != _grund.visible)
	if wechsel and _grund.visible and an:
		_grund.call("merken")
	_grund.set("farbe", farbe)
	_grund.set("dunkel", float(h.get("dunkel", 0.35)))
	_grund.set("fx", float(b.get("fx", 0.5)))
	_grund.set("fy", float(b.get("fy", 0.5)))
	_grund.set("z", float(b.get("z", 1.0)))
	if pfad != str(_grund.get("pfad")):
		_grund.set("pfad", pfad)
		_grund.set("tex", null)
		if pfad != "":
			var g := _grund
			Media.file_texture(pfad, 1920, func(t: Texture2D) -> void:
				if is_instance_valid(g) and str(g.get("pfad")) == pfad:
					g.set("tex", t)
					g.queue_redraw()
			)
	if wechsel:
		var tw := U.kreuzen(_grund, "mz_grund")
		if an and not _grund.visible:
			# Kommt neu: blendet über den üblichen Raum ein.
			_grund.visible = true
			_grund.modulate.a = 0.0
			tw.tween_property(_grund, "modulate:a", 1.0, U.T_LICHT)
		elif not an:
			tw.tween_property(_grund, "modulate:a", 0.0, U.T_LICHT)
			tw.tween_callback(func() -> void: _grund.visible = false)
		else:
			_grund.modulate.a = 1.0
			_grund.set("mix", 0.0)
			tw.tween_property(_grund, "mix", 1.0, U.T_LICHT)
	else:
		_grund.visible = an
	_grund.queue_redraw()


func _grund_menue() -> void:
	var h := Mosaik.hintergrund(quelle)
	var opts: Array = [["bild", "Bild wählen"], ["farbe", "Farbe"]]
	if h.has("bild"):
		opts.append(["ausschnitt", "Ausschnitt"])
	if not h.is_empty():
		opts.append(["dunkel", "Abdunklung", "%d %%" % roundi(float(h.get("dunkel", 0.35)) * 100.0)])
		opts.append(["weg", "Kein eigener Hintergrund"])
	main.open_choice("Hintergrund", opts, null, func(v: Variant) -> void:
		match str(v):
			"bild": _bild_quellen.call_deferred("_grund")
			"farbe": _grund_farbe.call_deferred()
			"ausschnitt": _ausschnitt_start("_grund")
			"dunkel": _grund_dunkel.call_deferred()
			"weg":
				Mosaik.hintergrund_setzen(quelle, {})
				_grund_neu()
	)


func _grund_farbe() -> void:
	var h := Mosaik.hintergrund(quelle)
	main.open_color_picker("Farbe des Hintergrunds", Color(str(h.get("farbe", "#1c1c21"))), func(c: Color) -> void:
		var neu := Mosaik.hintergrund(quelle)
		neu["farbe"] = "#" + c.to_html(false)
		if not neu.has("dunkel"):
			neu["dunkel"] = 0.0
		Mosaik.hintergrund_setzen(quelle, neu)
		_grund_neu()
	)


func _grund_dunkel() -> void:
	var h := Mosaik.hintergrund(quelle)
	var opts: Array = []
	for p in [0, 20, 35, 50, 70, 85]:
		opts.append([p, "%d %%" % p])
	main.open_choice("Abdunklung", opts, roundi(float(h.get("dunkel", 0.35)) * 20.0) * 5, func(v: Variant) -> void:
		var neu := Mosaik.hintergrund(quelle)
		neu["dunkel"] = float(v) / 100.0
		Mosaik.hintergrund_setzen(quelle, neu)
		_grund_neu()
	)


## Hintergrund der ganzen Seite: Farbe bzw. Bild (füllend, mit Ausschnitt und Zoom), darüber die
## Abdunklung, damit die Kacheln lesbar bleiben.
class Grund extends Control:
	var farbe := Color.BLACK
	var tex: Texture2D
	var pfad := ""
	var fx := 0.5
	var fy := 0.5
	var z := 1.0
	var dunkel := 0.35
	var mix := 1.0:            ## 0 → 1: der alte Stand kreuzt in den neuen (Hintergrundwechsel)
		set(v):
			mix = v
			queue_redraw()
	var _alt := {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	## Den jetzigen Stand als „alt“ merken; danach kreuzt mix von 0 nach 1.
	func merken() -> void:
		_alt = { "farbe": farbe, "tex": tex, "fx": fx, "fy": fy, "z": z, "dunkel": dunkel }

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if mix < 1.0 and not _alt.is_empty():
			_schicht(r, _alt.farbe, _alt.tex, _alt.fx, _alt.fy, _alt.z, _alt.dunkel, 1.0)
			_schicht(r, farbe, tex, fx, fy, z, dunkel, mix)
		else:
			_schicht(r, farbe, tex, fx, fy, z, dunkel, 1.0)

	func _schicht(r: Rect2, f: Color, t: Texture2D, x: float, y: float, zz: float, d: float, a: float) -> void:
		draw_rect(r, Color(f, a))
		if t:
			var ts := t.get_size()
			if ts.x > 0.0 and ts.y > 0.0:
				var sc := maxf(size.x / ts.x, size.y / ts.y) * maxf(zz, 1.0)
				var src := size / sc
				var pos := Vector2((ts.x - src.x) * x, (ts.y - src.y) * y)
				draw_texture_rect_region(t, r, Rect2(pos, src), Color(1, 1, 1, a))
		if d > 0.0:
			draw_rect(r, Color(0, 0, 0, d * a))


# --- Menü ----------------------------------------------------------------------------------------

func _menue() -> void:
	if not main:
		return
	var opts: Array = []
	if _bearbeiten:
		opts.append(["fertig", "Fertig gestalten"])
	else:
		opts.append(["gestalten", "Gestalten"])
	opts.append(["raster", "Raster", "%d × %d" % [_ra().x, _ra().y]])
	opts.append(["hintergrund", "Hintergrund"])
	opts.append(["ordner", "Ordner erstellen"])
	if _ordner_id() != "":
		opts.append(["fuellen", "Spiele auswählen"])
	opts.append(["liste", "Als Liste", "Sortieren, suchen"])
	if Regal.ist_konsole(quelle):
		opts.append(["regal", "Als Regal", "Hüllen im Regal"])
	if not (_d.weg as Array).is_empty():
		opts.append(["zurueck", "Abgenommene zurückholen", str((_d.weg as Array).size())])
	if bool(_d.get("eigen", false)):
		opts.append(["auto", "Automatisch neu anlegen"])
	main.open_choice(label, opts, null, func(v: Variant) -> void:
		match str(v):
			"gestalten": _gestalten(true, str(Nav.focused().get_meta("mz_id", "")) if Nav.focused() else "")
			"fertig": _gestalten(false)
			"raster": _raster_start()
			"hintergrund": _grund_menue.call_deferred()
			"ordner": _ordner_neu.call_deferred()
			"fuellen": _ordner_fuellen.call_deferred(_ordner_id())
			"liste": (func() -> void: main.open_library(quelle, label)).call_deferred()
			"regal": _als_regal.call_deferred()
			"zurueck":
				_d.weg = []
				_aendern()
				_modell()
				_bauen()
			"auto": _neu_anlegen.call_deferred()
	)


## Zum Regal (Konsolen gehen ohnehin als Regal auf – das Mosaik kommt nur noch aus alten Wegen hierher).
func _als_regal() -> void:
	var gs: Variant = main.sections.get("games") if main else null
	close()
	if gs is Object and (gs as Object).has_method("open_regal"):
		(gs as Object).call("open_regal", quelle, label)


func _neu_anlegen() -> void:
	main.open_dialog("Automatisch neu anlegen?", "Deine Anordnung und eigenen Bilder auf diesem Mosaik gehen verloren. Ordner und Spiele bleiben.", [
		["Neu anlegen", func() -> void:
			Mosaik.ablegen(quelle, {})
			_seite = 0
			_modell()
			_bauen(), "danger"],
		["Abbrechen", func() -> void: pass],
	])


# --- Glas ----------------------------------------------------------------------------------------

## Zeichnet Schatten (schatten) bzw. Scheiben aller Glaskacheln dieser Ebene (wurzel) – in der Lage,
## Größe, Skalierung und Deckkraft, die sie gerade haben (Aufbau, Blättern samt der gehenden Seite,
## Morph, Fokus). Zwei Knoten für alle Kacheln: jeder Schatten liegt unter allen Scheiben, und die
## Scheiben teilen sich ein Material und eine Kopie des Schirms (Glas.scheibe()).
class Unterlage extends Control:
	var wurzel: Node
	var schatten := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not schatten:
			material = Glas.scheibe()

	func _process(_dt: float) -> void:
		queue_redraw()

	func _kacheln() -> Array:
		var out: Array = []
		if wurzel == null or not is_inside_tree():
			return out
		for n in get_tree().get_nodes_in_group(Glas.GRUPPE):
			var k := n as Control
			if k != null and k.is_visible_in_tree() and wurzel.is_ancestor_of(k) and not k.is_queued_for_deletion():
				out.append(k)
		# Gewählte bzw. angehobene Kacheln liegen oben (wie ihre Kachel, siehe Kachel._fokus).
		out.sort_custom(func(a: Control, b: Control) -> bool: return a.call("lage_rang") < b.call("lage_rang"))
		return out

	## Deckkraft der Kachel samt ihrer Eltern bis zur Ebene.
	func _deckkraft(k: Control) -> float:
		var a := 1.0
		var n: Node = k
		while n != null and n != wurzel:
			if n is CanvasItem:
				a *= (n as CanvasItem).modulate.a
			n = n.get_parent()
		return a

	func _draw() -> void:
		var innen := get_global_transform_with_canvas().affine_inverse()
		for k in _kacheln():
			var a := _deckkraft(k)
			if a <= 0.004 or k.size.x < 2.0 or k.size.y < 2.0:
				continue
			draw_set_transform_matrix(innen * k.get_global_transform_with_canvas())
			var r := Rect2(Vector2.ZERO, k.size)
			if schatten:
				k.call("schatten_zeichnen", self, r, a)
			else:
				draw_rect(r, Glas.farbe(float(k.get("_t")), float(k.call("radius")), k.size, 0.0, a))
		draw_set_transform_matrix(Transform2D.IDENTITY)


## Glaspille für Bedienelemente über dem Raster (Seitenpunkte, Tastenzeile): Scheibe, darauf der
## Inhalt. Liegt über den Kacheln – die Ebene kopiert den Schirm davor einmal neu (BackBufferCopy),
## damit die Pille die Kacheln darunter bricht und nicht den leeren Raum.
class Pille extends MarginContainer:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		material = Glas.scheibe()
		resized.connect(queue_redraw)

	func polster(h: int, v: int) -> void:
		for seite in ["margin_left", "margin_right"]:
			add_theme_constant_override(seite, h)
		for seite in ["margin_top", "margin_bottom"]:
			add_theme_constant_override(seite, v)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Glas.farbe(0.0, minf(size.x, size.y) * 0.5, size, 1.0, 1.0))
