extends "res://src/ui/layers/modal.gd"
## Zimmer einführen (Punkt 131, Stufe 3): Uzai hat die Datei bzw. den Code schon vollständig geprüft
## (zimmer_teilen.gd) und zeigt hier, was darin ist, bevor sich etwas ändert – eine echte Vorschau,
## gerechnet aus den geprüften Daten (nicht das mitgelieferte Bild), Möbel, Größe, eigene Möbel und
## was wegfällt. Dann die Rückfrage: „Dein Zimmer ersetzen“ (Rückgängig mit X) oder „Als Vorlage
## speichern“. Figur und Haustier kommen nur mit, wenn du es einschaltest.

const Teilen := preload("res://src/room/zimmer_teilen.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Welt := preload("res://src/room/zimmer_welt.gd")
const Zimmer := preload("res://src/room/zimmer.gd")

var zimmer: Zimmer
var gelesen: Dictionary = {}
var _vorb: Dictionary = {}
var _mit_figur := false
var _welt: Node3D
var _vp: SubViewport
var _az := 0.5
var _fertig := false


func build() -> void:
	width = 1360.0
	set_meta("uz_hint_b", "Abbrechen")
	super()


func fill() -> void:
	box.add_theme_constant_override("separation", 20)
	box.add_child(U.label("Zimmer einführen", "xl", "text", "black"))
	if not bool(gelesen.get("ok", false)):
		var t := U.label(str(gelesen.get("error", "Das ist kein gültiges Uzai-Zimmer.")), "m", "muted", "regular", true)
		t.custom_minimum_size = Vector2(width - 96.0, 0)
		box.add_child(t)
		var h := U.label(
				"Nichts geändert. Erwartet: .uzaizimmer-Datei oder Code mit „UZZ1:“.", "s",
				"faint", "regular", true)
		h.custom_minimum_size = Vector2(width - 96.0, 0)
		box.add_child(h)
		var b := U.button("Schließen", "", "primary")
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(close)
		b.set_meta("uz_default", true)
		box.add_child(b)
		return
	var erreichte: Array = zimmer.bewohner.erreichte if zimmer.bewohner else []
	_vorb = Teilen.vorbereiten(gelesen, zimmer.daten.get("eigene", []), erreichte)
	var raum: Dictionary = _vorb.raum
	var reihe := U.hbox(40)
	box.add_child(reihe)
	reihe.add_child(_vorschau(raum))
	var rechts := U.vbox(10)
	rechts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reihe.add_child(rechts)
	rechts.add_child(U.label(Teilen.RAUM_NAME, "l", "text", "bold"))
	var m := func(felder: int) -> String:
		var v := felder * 0.5
		return ("%d" % int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).replace(".", ",")
	rechts.add_child(U.label(tr("%d Möbel · %s × %s m") % [int(_vorb.moebel), m.call(int(raum.w)), m.call(int(raum.d))], "m", "muted", "medium"))
	rechts.add_child(U.spacer(0, 6, false))
	rechts.add_child(_zeile("check", "Geprüft"))
	var eigene := (gelesen.get("eigene", []) as Array).size()
	if eigene > 0:
		var neu := int(_vorb.neu)
		rechts.add_child(
				_zeile("spark",
				tr("%d eigene Möbel aus dem Baukasten reisen mit") % eigene + ("" if neu == eigene else " · " + tr("%d davon hast du schon") % (eigene - neu))))
	if int(_vorb.weg_eigene) > 0:
		rechts.add_child(_zeile("warning", tr("%d eigene Möbel passen nicht mehr in deine Liste (höchstens 24)") % int(_vorb.weg_eigene)))
	if int(_vorb.weg_gesperrt) > 0:
		rechts.add_child(_zeile("lock", tr("%d Möbel sind bei dir noch nicht freigespielt und bleiben weg") % int(_vorb.weg_gesperrt)))
	rechts.add_child(U.spacer(0, 6, false))
	var figur = SettingRow.new()
	figur.setup("toggle", "Figur und Haustier übernehmen", "", false)
	figur.subtitle = "Nur das Aussehen"
	figur.compact = true
	figur.set_meta("uz_key", "zimmer:figur")
	figur.changed.connect(func(v: Variant) -> void: _mit_figur = bool(v))
	rechts.add_child(figur)
	var notiz := U.label(
			"Rückgängig mit X.", "s",
			"faint", "regular", true)
	notiz.custom_minimum_size = Vector2(width - 96.0, 0)
	box.add_child(notiz)
	var knoepfe := U.hbox(14)
	box.add_child(knoepfe)
	var ersetzen := U.button("Dein Zimmer ersetzen", "home", "primary")
	ersetzen.set_meta("uz_default", true)
	ersetzen.pressed.connect(_ersetzen)
	knoepfe.add_child(ersetzen)
	var vorlage := U.button("Als Vorlage speichern", "save")
	vorlage.pressed.connect(_als_vorlage)
	knoepfe.add_child(vorlage)
	var ab := U.button("Abbrechen")
	ab.pressed.connect(close)
	knoepfe.add_child(ab)


func _zeile(icon: String, text: String) -> Control:
	var h := U.hbox(10)
	h.add_child(U.icon(icon, 22, "muted"))
	var l := U.label(text, "s", "muted", "medium", true)
	l.custom_minimum_size = Vector2(420, 0)
	h.add_child(l)
	return h


## Echte Vorschau aus den geprüften Daten: das Zimmer in einer eigenen kleinen Ansicht, die Kamera
## kreist langsam darüber (in „Leicht“ ein stilles Bild).
func _vorschau(raum: Dictionary) -> Control:
	var rahmen := PanelContainer.new()
	rahmen.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.radius + 2))
	rahmen.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	rahmen.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(720, 405)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rahmen.add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.audio_listener_enable_3d = false
	_vp.positional_shadow_atlas_size = 0
	var leicht := bool(zimmer.leicht)
	_vp.msaa_3d = Viewport.MSAA_DISABLED if leicht else Viewport.MSAA_2X
	svc.add_child(_vp)
	# Die eigenen Möbel des Pakets kennt der Katalog nur, solange diese Vorschau offen ist.
	Katalog.eigene_setzen(_vorb.eigene)
	_welt = Welt.new()
	_welt.huellen = zimmer.daten.get("huellen", {})
	_vp.add_child(_welt)
	_welt.bauen(raum, "leicht" if leicht else "mittel")
	_welt.fokus(6.0, 20.0, 0.0)
	_kamera(0.0)
	if leicht:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		set_process(false)
	return rahmen


func _process(dt: float) -> void:
	if _welt == null or not is_instance_valid(_welt):
		return
	_kamera(dt)


func _kamera(dt: float) -> void:
	_az += dt * 0.12
	var r: Dictionary = _welt.raum
	var w := float(r.w) * Katalog.ZELLE
	var d := float(r.d) * Katalog.ZELLE
	var mitte := Vector3(w * 0.5, 0.45, d * 0.5)
	var hoehe := 0.78
	var dist := 9.6 * maxf(w, d) / 6.0
	var o := mitte + Vector3(sin(_az) * cos(hoehe), sin(hoehe), cos(_az) * cos(hoehe)) * dist
	_welt.kamera.fov = 34.0
	_welt.kamera.global_transform = Transform3D(Basis(), o).looking_at(mitte, Vector3.UP)
	_welt.schnitt(o, true)


func _ersetzen() -> void:
	if _fertig:
		return
	_fertig = true
	var f: Dictionary = gelesen.get("figur", {}) if _mit_figur else {}
	var t: Dictionary = gelesen.get("tier", {}) if _mit_figur else {}
	zimmer.zimmer_ersetzen(_vorb, f, t)
	close()


func _als_vorlage() -> void:
	if _fertig:
		return
	var main: Node = get_tree().current_scene
	main.open_keyboard("Name der Vorlage", tr(Teilen.RAUM_NAME), func(text: String) -> void:
		var name_ := text.strip_edges()
		if name_ == "" or _fertig or not is_inside_tree():
			return
		_fertig = true
		zimmer.vorlage_speichern(_vorb, name_)
		close())


func _notification(what: int) -> void:
	super(what)
	# Ohne Übernahme gilt im Katalog wieder genau die eigene Liste.
	if what == NOTIFICATION_EXIT_TREE and is_instance_valid(zimmer):
		Katalog.eigene_setzen(zimmer.daten.get("eigene", []))
