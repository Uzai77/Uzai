extends Control
## Möbel-Baukasten (Punkt 131 b): eigene Möbel aus eingebauten Bauteilen – Platten, Kästen,
## Kissen, Zylinder, Kugeln, Beine, Stangen, Lampenschirme, Leuchtkugeln, Griffe und Bögen. Links
## eine ruhige Bühne mit Drehteller und der Grundfläche im Raster (je 0,5 m), rechts die
## Seitenleiste (anpassen_ui.gd) mit den Teilen. Alles sind Daten (gestalt.gd, pruefe_eigenes):
## Kennungen, Zentimeter, Farben – keine fremden Modelldateien, darum sicher teilbar.
##
## Bedienung: Steuerkreuz wählt und ändert, LB/RB große Schritte, A öffnet, X Rückgängig,
## rechter Stick dreht die Bühne, B zurück (auf der ersten Seite: speichern und fertig).

signal fertig(def: Dictionary)
signal verworfen

const U := preload("res://src/ui/u.gd")
const G := preload("res://src/room/gestalt.gd")
const Moebel := preload("res://src/room/moebel.gd")
const S := preload("res://src/room/stoffe.gd")
const F := preload("res://src/room/formen.gd")
const AnpassenUi := preload("res://src/room/anpassen_ui.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Zimmer := preload("res://src/room/zimmer.gd")

const MAX_RUECK := 60

var zimmer: Zimmer
var def := {}
var ui: AnpassenUi
var _rueck: Array = []
var _schritt_offen := true      ## nächste Änderung beginnt einen neuen Rückgängig-Schritt
var _sel_teil := -1
var _svc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _modell: Node3D
var _feld: Node3D
var _dreh := 0.7
var _dreh_soll := 0.7
var _neigung := 0.42
var _abstand := 2.6
var _abstand_soll := 2.6
var _mitte := Vector3(0, 0.4, 0)
var _rahmen: PanelContainer
var _offen := false
var _zeit := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(self)
	visible = false
	_rahmen = PanelContainer.new()
	_rahmen.add_theme_stylebox_override("panel", UzTheme.lift(UzTheme.box(Color("#121316"), UzTheme.r_panel()), 2))
	_rahmen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rahmen)
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.clip_round(_rahmen)
	_rahmen.add_child(_svc)
	ui = AnpassenUi.new()
	ui.rueckgaengig = rueckgaengig
	add_child(ui)
	ui.schritt_neu.connect(func() -> void: _schritt_offen = true)
	ui.geschlossen.connect(_ui_zu)
	resized.connect(_lage)


func _lage() -> void:
	var s := size if size.x > 0 else U.view_size()
	_rahmen.position = Vector2(48, 48)
	_rahmen.size = Vector2(s.x - AnpassenUi.BREITE - 48.0 * 3.0, s.y - 48.0 - 112.0)


func ist_offen() -> bool:
	return _offen


## Neues Möbel (d leer) oder ein vorhandenes bearbeiten.
func oeffnen(d: Dictionary) -> void:
	def = d.duplicate(true) if not d.is_empty() else neues()
	ui.eigene_farben = Callable(zimmer, "eigene_farben") if zimmer else Callable()
	ui.farbe_merken = Callable(zimmer, "farbe_merken") if zimmer else Callable()
	_rueck.clear()
	_schritt_offen = true
	_sel_teil = -1
	_offen = true
	visible = true
	_lage()
	_buehne_bauen()
	_neu_bauen()
	_kamera_fit(true)
	modulate.a = 0.0
	_rahmen.scale = Vector2(0.98, 0.98)
	var tw := U.tw(self, "uz_baukasten", Tween.TRANS_QUART)
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_rahmen, "scale", Vector2.ONE, U.T_MOVE)
	ui.oeffnen(seite_haupt())


func schliessen() -> void:
	_offen = false
	var tw := U.tw(self, "uz_baukasten", Tween.TRANS_CUBIC, Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, U.T_FAST)
	tw.tween_callback(func() -> void:
		visible = false
		if is_instance_valid(_vp):
			_vp.queue_free()
			_vp = null)


## Der Ausgangspunkt für ein neues Möbel: ein kleiner Tisch mit vier Beinen.
static func neues() -> Dictionary:
	var teile: Array = [{ "a": "platte", "x": 0, "y": 42, "z": 0, "b": 80, "h": 3, "t": 50, "r": 0 }]
	for x in [-35, 35]:
		for zz in [-20, 20]:
			teile.append({ "a": "bein", "x": x, "y": 0, "z": zz, "b": 4, "h": 42, "t": 4, "r": 0 })
	return { "id": "", "name": "Mein Möbel", "ebene": "boden", "w": 2, "d": 1, "teile": teile }


func _ui_zu() -> void:
	if _offen:
		speichern()


func speichern() -> void:
	var m := G.eigen_masse(def.teile)
	def.w = m.x
	def.d = m.y
	_offen = false
	fertig.emit(def.duplicate(true))
	schliessen()


func verwerfen() -> void:
	_offen = false
	ui.schliessen()
	verworfen.emit()
	schliessen()


# --- Rückgängig ------------------------------------------------------------------------------------

func _merken() -> void:
	if not _schritt_offen:
		return
	_schritt_offen = false
	_rueck.append(def.duplicate(true))
	while _rueck.size() > MAX_RUECK:
		_rueck.pop_front()


func rueckgaengig() -> void:
	if _rueck.is_empty():
		Sfx.play("bump")
		return
	def = _rueck.pop_back()
	_schritt_offen = true
	Sfx.play("back")
	_sel_teil = mini(_sel_teil, (def.teile as Array).size() - 1)
	_neu_bauen()
	_ui_neu()


## Seitenleiste neu lesen; ist das gewählte Teil weg, zurück zur Teileliste.
func _ui_neu() -> void:
	var s: Dictionary = ui.seite()
	if s.has("teil") and int(s.teil) >= (def.teile as Array).size():
		ui.zurueck()
	ui.auffrischen()


func aendern(f: Callable) -> void:
	_merken()
	f.call()
	_neu_bauen()


# --- Seiten ----------------------------------------------------------------------------------------

func seite_haupt() -> Dictionary:
	var zl: Array = [
		{ "art": "seite", "text": "Name", "roh_wert": true, "oeffnen": func() -> Dictionary:
			_name_fragen()
			return {}, "wert": func() -> String: return str(def.name) },
		{ "art": "wahl", "text": "Steht", "optionen": G.EBENEN_EIGEN, "wert": func() -> String: return str(def.ebene),
			"setzen": func(v: Variant) -> void: aendern(func() -> void: def.ebene = str(v)) },
		{ "art": "abschnitt", "text": "Teile" },
	]
	var teile: Array = def.teile
	for i in teile.size():
		var k := i
		var t: Dictionary = teile[i]
		zl.append({ "art": "seite", "text": "%d · %s" % [i + 1, tr(G.wahl_name(G.BAUTEILE, str(t.a)))], "roh": true,
			"oeffnen": func() -> Dictionary: return seite_teil(k),
			"roh_wert": true,
				"wert": func() -> String: return "%d × %d × %d cm" % [int(def.teile[k].b), int(def.teile[k].h), int(def.teile[k].t)] if k < (
				def.teile as Array).size() else "" })
	if teile.size() < G.MAX_TEILE:
		zl.append({ "art": "seite", "text": "Teil hinzufügen", "oeffnen": seite_neues_teil })
	zl.append({ "art": "abschnitt", "text": "Fertig" })
	zl.append({ "art": "aktion", "text": "Speichern und schließen", "tun": func() -> void: ui.schliessen() })
	zl.append({ "art": "aktion", "text": "Verwerfen", "gefahr": true, "tun": verwerfen })
	var m := G.eigen_masse(teile)
	return { "titel": str(def.name), "kicker": tr("Baukasten · %d × %d Felder") % [m.x, m.y], "zeilen": zl, "neu": seite_haupt, "roh": true }


func seite_neues_teil() -> Dictionary:
	var zl: Array = []
	for b in G.BAUTEILE:
		var a := str(b[0])
		zl.append({ "art": "aktion", "text": str(b[1]), "tun": func() -> void: _teil_neu(a) })
	return { "titel": "Teil hinzufügen", "kicker": "Baukasten", "zeilen": zl, "neu_teil": true }


func _teil_neu(a: String) -> void:
	var std: Array = G.BAUTEIL_STD[a]
	# Neue Teile setzen sich oben auf das Möbel (sichtbar, nicht im Boden versteckt).
	var oben := 0
	for t in def.teile:
		oben = maxi(oben, int(t.y) + int(t.h))
	if a in ["bein", "stange"]:
		oben = 0
	aendern(
			func() -> void: (def.teile as Array).append({ "a": a, "x": 0, "y": mini(oben, 200), "z": 0, "b": int(std[0]), "h": int(std[1]), "t": int(std[2]), "r": 0 }))
	if bool((ui.seite() as Dictionary).get("neu_teil", false)):
		ui.zurueck()
		ui.auffrischen()
		ui.hinein(seite_teil((def.teile as Array).size() - 1))
	else:
		ui.auffrischen()


func seite_teil(i: int) -> Dictionary:
	_sel_teil = i
	_markieren()
	var lese := func(k: String) -> Variant: return def.teile[i].get(k, "") if i < (def.teile as Array).size() else 0
	var setze := func(v: Variant, k: String) -> void:
		aendern(func() -> void:
			if i < (def.teile as Array).size():
				if (k in ["f", "m", "mu"]) and str(v) == "":
					(def.teile[i] as Dictionary).erase(k)
				else:
					def.teile[i][k] = v)
	var mats: Array = [["", "Passend zum Teil"]]
	for m in G.MATERIAL_REIHE:
		mats.append([m, G.material_name(str(m))])
	var zl: Array = [
		{ "art": "wahl", "text": "Bauteil", "optionen": G.BAUTEILE, "wert": lese.bind("a"), "setzen": setze.bind("a") },
		{ "art": "abschnitt", "text": "Maße" },
		_zahl("Breite", "b", 1, 400, lese, setze),
		_zahl("Höhe", "h", 1, 260, lese, setze),
		_zahl("Tiefe", "t", 1, 400, lese, setze),
		{ "art": "abschnitt", "text": "Lage" },
		_zahl("Links und rechts", "x", -200, 200, lese, setze),
		_zahl("Höhe über dem Boden", "y", 0, 260, lese, setze),
		_zahl("Vorn und hinten", "z", -200, 200, lese, setze),
		_zahl("Drehung", "r", 0, 345, lese, setze, "%d°", 15),
		{ "art": "abschnitt", "text": "Oberfläche" },
		{ "art": "wahl", "text": "Material", "optionen": mats, "wert": lese.bind("m"), "setzen": setze.bind("m"), "std": "" },
		{ "art": "farbe", "text": "Farbe", "leer": "Natur", "std": "", "wert": lese.bind("f"), "setzen": setze.bind("f") },
		{ "art": "wahl", "text": "Muster", "optionen": G.MUSTER, "wert": lese.bind("mu"), "setzen": setze.bind("mu"), "std": "", "hinweis": "Auf Stoff-Materialien" },
		{ "art": "abschnitt", "text": "Teil" },
		{ "art": "aktion", "text": "Kopieren", "tun": func() -> void:
			# Voll: nichts tun (früher sprang die Seite trotzdem zum letzten Teil, als wäre es die Kopie).
			if (def.teile as Array).size() >= G.MAX_TEILE or i >= (def.teile as Array).size():
				Sfx.play("error")
				return
			aendern(func() -> void:
				var c: Dictionary = (def.teile[i] as Dictionary).duplicate()
				c.x = clampi(int(c.x) + 10, -200, 200)
				(def.teile as Array).append(c))
			ui.zurueck()
			ui.auffrischen()
			ui.hinein(seite_teil((def.teile as Array).size() - 1)) },
		{ "art": "aktion", "text": "Entfernen", "gefahr": true, "tun": func() -> void:
			if (def.teile as Array).size() <= 1:
				Sfx.play("error")
				return
			aendern(func() -> void: (def.teile as Array).remove_at(i))
			ui.zurueck()
			ui.auffrischen() },
	]
	return { "titel": "%d · %s" % [i + 1, tr(G.wahl_name(G.BAUTEILE, str(def.teile[i].a)))], "kicker": "Teil", "zeilen": zl, "teil": i, "roh": true,
		"neu": func() -> Dictionary: return seite_teil(i), "zurueck": func() -> void:
			_sel_teil = -1
			_markieren() }


static func _zahl(text: String, k: String, lo: int, hi: int, lese: Callable, setze: Callable, einheit := "%d cm", schritt := 1) -> Dictionary:
	return { "art": "zahl", "text": text, "min": lo, "max": hi, "schritt": schritt, "einheit": einheit, "wert": lese.bind(k), "setzen": setze.bind(k) }


func _name_fragen() -> void:
	var main: Node = zimmer.main if zimmer else null
	if main == null:
		return
	main.call("open_keyboard", "Name des Möbels", str(def.name), func(t: String) -> void:
		var n := G.text(t, 40)
		if n != "":
			aendern(func() -> void: def.name = n)
			ui.auffrischen())


# --- Bühne -----------------------------------------------------------------------------------------

func _buehne_bauen() -> void:
	if is_instance_valid(_vp):
		return
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.audio_listener_enable_3d = false
	_svc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0e0f11")
	# Ein warmer Himmel nur für Licht und Spiegelungen (sonst wirkt Metall schwarz).
	var himmel := ProceduralSkyMaterial.new()
	himmel.sky_top_color = Color("#5a5650")
	himmel.sky_horizon_color = Color("#b9aa96")
	himmel.ground_horizon_color = Color("#4a4038")
	himmel.ground_bottom_color = Color("#1a1612")
	var sky := Sky.new()
	sky.sky_material = himmel
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-48, 32, 0)
	licht.light_energy = 1.25
	licht.light_color = Color("#fff1de")
	licht.shadow_enabled = true
	licht.shadow_blur = 2.0
	licht.directional_shadow_max_distance = 8.0
	_vp.add_child(licht)
	var fuell := DirectionalLight3D.new()
	fuell.rotation_degrees = Vector3(-12, -150, 0)
	fuell.light_energy = 0.45
	fuell.light_color = Color("#dfe6f2")
	_vp.add_child(fuell)
	# Drehteller: eine dunkle, weich gerundete Scheibe.
	var teller := MeshInstance3D.new()
	teller.mesh = F.walze(2.2, 0.04, 0.02, 64)
	teller.material_override = S.lack(Color("#1d1e22"), 0.7, 0.3)
	teller.position = Vector3(0, -0.04, 0)
	_vp.add_child(teller)
	_feld = Node3D.new()
	_vp.add_child(_feld)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.current = true
	_vp.add_child(_cam)


func _neu_bauen() -> void:
	if not is_instance_valid(_vp):
		return
	if is_instance_valid(_modell):
		_modell.queue_free()
	_modell = Moebel.eigen_bauen(def)
	_vp.add_child(_modell)
	_feld_zeigen()
	_markieren()
	_kamera_fit(false)


## Grundfläche im Raster: so viele Felder belegt das Möbel im Zimmer.
func _feld_zeigen() -> void:
	for c in _feld.get_children():
		c.queue_free()
	var m := G.eigen_masse(def.teile)
	var z := Katalog.ZELLE
	var gold := S.leuchte(Color("#e7c27d"), 0.8)
	var fein := S.lack(Color("#3a3b40"), 0.8, 0.2)
	var w := m.x * z
	var d := m.y * z
	for i in m.x + 1:
		_linie(Vector3(-w * 0.5 + i * z, 0.002, 0), Vector3(0.006, 0.002, d), gold if i == 0 or i == m.x else fein)
	for j in m.y + 1:
		_linie(Vector3(0, 0.002, -d * 0.5 + j * z), Vector3(w, 0.002, 0.006), gold if j == 0 or j == m.y else fein)


func _linie(pos: Vector3, g: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = g
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_feld.add_child(mi)


## Gewähltes Teil glimmt warm (wie die Auswahl im Zimmer).
func _markieren() -> void:
	if not is_instance_valid(_modell):
		return
	for i in _modell.get_child_count():
		var n := _modell.get_child(i)
		_overlay(n, S.glimmen() if i == _sel_teil else null)


static func _overlay(n: Node, m: Material) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_overlay = m
		_overlay(c, m)


func _kamera_fit(sofort: bool) -> void:
	var box := AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.6, 0.6))
	if is_instance_valid(_modell):
		for c in _modell.get_children():
			box = box.merge(_box(c as Node3D))
	_mitte = box.get_center()
	_abstand_soll = clampf(box.size.length() * 1.55 + 0.6, 1.6, 9.0)
	if sofort:
		_abstand = _abstand_soll


static func _box(n: Node3D) -> AABB:
	var out := AABB(n.position, Vector3.ZERO)
	var stapel: Array = [[n, n.transform]]
	while not stapel.is_empty():
		var e: Array = stapel.pop_back()
		for c in (e[0] as Node).get_children():
			if c is Node3D:
				var t: Transform3D = (e[1] as Transform3D) * (c as Node3D).transform
				if c is MeshInstance3D and (c as MeshInstance3D).mesh:
					out = out.merge(t * (c as MeshInstance3D).get_aabb())
				stapel.append([c, t])
	return out


## Jedes Bild: Kamera weich um die Bühne (rechter Stick dreht und neigt), ohne Eingabe ein Hauch
## Bewegung, damit das Möbel lebendig wirkt.
func bild(dt: float, rs: Vector2) -> void:
	if not _offen or not is_instance_valid(_cam):
		return
	_zeit += dt
	_dreh_soll -= rs.x * dt * 1.8
	_neigung = clampf(_neigung - rs.y * dt * 0.9, 0.08, 1.15)
	if rs.length() < 0.05 and not U.reduziert():
		_dreh_soll += dt * 0.12
	_dreh = lerp_angle(_dreh, _dreh_soll, 1.0 - exp(-dt * 6.0))
	_abstand = lerpf(_abstand, _abstand_soll, 1.0 - exp(-dt * 5.0))
	var o := _mitte + Vector3(sin(_dreh) * cos(_neigung), sin(_neigung), cos(_dreh) * cos(_neigung)) * _abstand
	_cam.look_at_from_position(o, _mitte, Vector3.UP)
	S.glimmen().set_shader_parameter("staerke", 0.4 + 0.1 * sin(_zeit * 2.4) if _sel_teil >= 0 else 0.0)


func schritt(cmd: String) -> void:
	ui.schritt(cmd)


func taste(cmd: String) -> bool:
	return bool(ui.taste(cmd))


func hinweise() -> Array:
	return ui.hinweise()
