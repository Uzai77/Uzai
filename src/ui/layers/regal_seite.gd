extends "res://src/ui/layers/layer.gd"
## Regal einer Konsole (A auf PS2 in der Quellen-Zeile der Startseite): die Spiele als echte Hüllen
## auf einem Brett in einem ruhigen, dunklen Raum (3D, src/room/regal_welt.gd; Logik in
## src/library/regal.gd). Links/rechts fährt die Kamera am Regal entlang, die gewählte Hülle zieht
## sich heraus und zeigt ihr Cover; gehalten wird es schneller, LB/RB (und hoch/runter) springen
## zum nächsten Abschnitt (A–Z bzw. nach der Sortierung). A öffnet die Spielseite, X merkt das
## Spiel als Favorit, Y öffnet die Optionen (Spieloptionen, Sortierung). Maus: Rad blättert, Klick wählt bzw. öffnet.
##
## Unten links steht leise, was gewählt ist (Titel, Spielzeit, zuletzt), oben links die Quelle,
## oben rechts die Abschnitte. Die Tastenzeile liegt als matte Pille unten rechts im Bild.
## Konsolen gehen immer als Regal auf (Regal.ist_regal) – Raster und Liste gibt es für sie nicht mehr.

const Regal := preload("res://src/library/regal.gd")
const Welt := preload("res://src/room/regal_welt.gd")
const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")
const Leicht := preload("res://src/core/leicht.gd")

const HELL := Color("#f3f2ef")
const LEISE := Color("#a9a8ae")
const FAST_AUS := Color("#6f6e75")

const Main := preload("res://src/main.gd")
var main: Main
var quelle := ""            ## wie in der Quellen-Zeile: „ps2“
var label := ""
var welt: Welt
var svc: SubViewportContainer
var vp: SubViewport

var _spiele: Array = []
var _abs: Array = []
var _i := 0
var _halt: Button
var _fang: Control
var _hud: Control
var _info: VBoxContainer
var _ort_l: Label
var _titel_l: Label
var _zeile_l: Label
var _stern: TextureRect
var _abs_reihe: HBoxContainer
var _leer_l: Label
var _tasten: Control
var _wiederholt := 0
var _letzter_ms := 0
var _eilig := false
var _stale := false
var _bild_stand := -1        ## Media.bilder_stand beim letzten Laden (neue Bilder: Regal neu)
var _versteckt := false


func build() -> void:
	dim = 1.0
	_scrim.color = Color("#060607")
	set_meta("uz_hints_eigen", true)
	set_meta("uz_ohne_auslauf", true)
	set_meta("uz_hints", [["lb", ""], ["rb", "Abschnitt"]])
	LibraryGrid.hide_shell(main, self)
	if main:
		closed.connect(func() -> void:
			_oberflaeche_zeigen()
			var gs: Variant = main.sections.get("games")
			if gs is Object and (gs as Object).has_method("restore_background"):
				(gs as Object).call("restore_background")
		)
	var leicht := bool(Leicht.active)
	svc = SubViewportContainer.new()
	svc.stretch = false
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.audio_listener_enable_3d = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var forward := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	vp.msaa_3d = Viewport.MSAA_DISABLED if leicht else Viewport.MSAA_4X
	vp.use_debanding = forward and not leicht
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = 0 if leicht else 2048
	svc.add_child(vp)
	welt = Welt.new()
	vp.add_child(welt)
	welt.bauen(leicht, U.reduziert())
	welt.cover_da.connect(_cover_da)
	_groesse()
	get_viewport().size_changed.connect(_groesse)
	_fang = Control.new()
	U.full_rect(_fang)
	_fang.mouse_filter = Control.MOUSE_FILTER_STOP
	_fang.gui_input.connect(_maus)
	add_child(_fang)
	_hud_bauen()
	_halt = Button.new()
	_halt.flat = true
	_halt.focus_mode = Control.FOCUS_ALL
	_halt.modulate.a = 0.0
	_halt.position = Vector2(-10, -10)
	_halt.size = Vector2(1, 1)
	_halt.pressed.connect(_oeffnen)
	_halt.set_meta("uz_hint_a", "Öffnen" if main == null or bool(main.game_page_on()) else "Spielen")
	_halt.set_meta("uz_hint_y", "Optionen")
	_halt.set_meta("uz_on_y", _menue)
	_halt.set_meta("uz_on_x", _favorit)
	add_child(_halt)
	Library.changed.connect(_on_library_changed)
	Nav.focus_moved.connect(_on_focus_moved)
	_laden("")
	welt.einziehen()
	# Ganz verdeckt: die Startseite dahinter nicht weiter zeichnen (spart die Hälfte der Arbeit).
	get_tree().create_timer(U.T_RAUM + 0.1).timeout.connect(_oberflaeche_verstecken)


func _first_focus() -> Control:
	return _halt


## Der Viewport rechnet in echten Bildpunkten (in 4K also 4K), nicht in den 1920 × 1080 der
## Oberfläche – sonst wären Rücken und Schrift weich. Im leichten Modus in der Größe der Oberfläche.
func _groesse() -> void:
	if not is_instance_valid(vp):
		return
	var vs := U.view_size()
	var f := 1.0
	if not Leicht.active and is_inside_tree():
		f = clampf(get_tree().root.get_final_transform().get_scale().x, 1.0, 2.0)
	vp.size = Vector2i(roundi(vs.x * f), roundi(vs.y * f))
	svc.size = Vector2(vp.size)
	svc.scale = Vector2.ONE / f
	if welt:
		welt.unruhe(0.3)


# --- Daten ---------------------------------------------------------------------------------------

func sortierung() -> String:
	var s := str(Config.get_value("library.regal_sort", Regal.SORT_STANDARD))
	for e in Regal.SORTEN:
		if str(e[0]) == s:
			return s
	return Regal.SORT_STANDARD


## Spiele holen, sortieren, in Abschnitte teilen und aufs Brett stellen; die Auswahl bleibt auf
## dem Spiel mit der ID halten (sonst das erste).
func _laden(halten: String) -> void:
	_bild_stand = Media.bilder_stand
	var mode := sortierung()
	_spiele = _sortiert(mode)
	var jetzt := int(Time.get_unix_time_from_system())
	var keys: Array = []
	var dicken: Array = []
	for g in _spiele:
		keys.append(Regal.abschnitt(mode, Library.display_title(g), Library.last_played(g), Library.playtime(g), int(g.get("added", 0)), jetzt))
		dicken.append(Regal.masse(str(g.get("system", ""))).x)
	_abs = Regal.abschnitte(keys)
	var lage := Regal.anordnen(dicken, _abs)
	_i = 0
	if halten != "":
		for k in _spiele.size():
			if str(_spiele[k].get("id", "")) == halten:
				_i = k
				break
	welt.belegen(_spiele, lage, _abs, _i)
	_kopf_neu()
	_zeigen()


## Spiele der Konsole in der Sortierung (A–Z wie die Abschnitte, sonst wie die Bibliothek).
func _sortiert(mode: String) -> Array:
	var list := Library.by_system(quelle)
	if mode == "title":
		return Regal.nach_titel(list, Library.display_title)
	return Library.sorted(list, mode)


func _gewaehlt() -> Dictionary:
	return _spiele[_i] if _i >= 0 and _i < _spiele.size() else {}


func _on_library_changed() -> void:
	_stale = true
	_auffrischen.call_deferred()


func _on_focus_moved(_c: Control) -> void:
	if _stale:
		_auffrischen()


## Bibliothek geändert: Steht dieselbe Reihe da (nur Favorit, Spielzeit …), nur die Schrift neu –
## sonst das Regal neu (die Auswahl bleibt beim selben Spiel).
func _auffrischen() -> void:
	if not _stale or not is_inside_tree() or _closing or Nav.top_layer() != self:
		return
	_stale = false
	var neu := _sortiert(sortierung())
	var gleich := neu.size() == _spiele.size()
	if gleich:
		for k in neu.size():
			if str(neu[k].get("id", "")) != str(_spiele[k].get("id", "")):
				gleich = false
				break
	if gleich and _bild_stand == Media.bilder_stand:
		_spiele = neu
		welt.set("spiele", neu)
		_zeigen()
		return
	_laden(str(_gewaehlt().get("id", "")))


# --- Anzeige -------------------------------------------------------------------------------------

func _hud_bauen() -> void:
	_hud = Control.new()
	U.full_rect(_hud)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	# Unten ein weicher dunkler Verlauf, damit die Schrift über der Front immer ruhig steht.
	var verlauf := TextureRect.new()
	verlauf.texture = U.fade_texture(true, true)
	verlauf.modulate = Color(0, 0, 0, 0.55)
	verlauf.stretch_mode = TextureRect.STRETCH_SCALE
	verlauf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	verlauf.anchor_right = 1.0
	verlauf.anchor_top = 1.0
	verlauf.anchor_bottom = 1.0
	verlauf.offset_top = -300
	verlauf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(verlauf)
	var rand := 80.0
	# Unten rechts über der Tastenzeile die Abschnitte (der aktuelle hell) – oben bleibt das Regal frei.
	_abs_reihe = U.hbox(16)
	_abs_reihe.anchor_left = 1.0
	_abs_reihe.anchor_right = 1.0
	_abs_reihe.anchor_top = 1.0
	_abs_reihe.anchor_bottom = 1.0
	_abs_reihe.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_abs_reihe.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_abs_reihe.offset_right = -rand
	_abs_reihe.offset_bottom = -132
	_abs_reihe.alignment = BoxContainer.ALIGNMENT_END
	_hud.add_child(_abs_reihe)
	# Unten links: wo, was, wie lange.
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 6)
	_info.anchor_top = 1.0
	_info.anchor_bottom = 1.0
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.offset_left = rand
	_info.offset_bottom = -64
	_info.offset_right = rand + 1100
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ort_l = _schrift("", 20, LEISE, UzTheme.font("medium"))
	_titel_l = _schrift("", 58, HELL, UzTheme.display("title"))
	U.ellipsis(_titel_l)
	U.shadow(_titel_l, 0.5)
	var zeile := U.hbox(12)
	_stern = U.icon("star_f", 22, "text")
	_stern.modulate = HELL
	_stern.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zeile_l = _schrift("", 22, LEISE, UzTheme.font("regular"))
	zeile.add_child(_stern)
	zeile.add_child(_zeile_l)
	_info.add_child(_ort_l)
	_info.add_child(_titel_l)
	_info.add_child(zeile)
	# Ort, Titel und Zeile wechseln mit jedem Schritt am Regal und sind schon von Hand übersetzt (_zeigen): nie noch
	# einmal durch die Übersetzung – jede Stelle („12 von 345“) wäre dort ein neuer Text, der Titel ein fremder Name.
	for l in [_ort_l, _titel_l, _zeile_l]:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hud.add_child(_info)
	_leer_l = _schrift("Hier steht noch kein Spiel.", 28, LEISE, UzTheme.font("regular"))
	_leer_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leer_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	U.full_rect(_leer_l)
	_leer_l.visible = false
	_hud.add_child(_leer_l)
	# Tastenzeile als matte Pille unten rechts (HintBar mit inside: zeigt, wenn diese Ebene oben liegt).
	_tasten = U.panel("surface", UzTheme.r_pill(), 0, 0.82)
	var mm := U.margin(20, 8, 20, 8)
	_tasten.add_child(mm)
	_tasten.anchor_left = 1.0
	_tasten.anchor_top = 1.0
	_tasten.anchor_right = 1.0
	_tasten.anchor_bottom = 1.0
	_tasten.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tasten.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tasten.offset_right = -rand + 24
	_tasten.offset_bottom = -52
	var hb := HintBar.new()
	hb.inside = true
	hb.gap = 22
	mm.add_child(hb)
	hb.sort_children.connect(func() -> void: _tasten.visible = hb.get_child_count() > 0)
	_hud.add_child(_tasten)
	hb.refresh.call_deferred(true)


func _schrift(text: String, px: int, farbe: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", farbe)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _kopf_neu() -> void:
	U.clear(_abs_reihe)
	# Viele Abschnitte (A–Z): nur Buchstaben; wenige: die Namen.
	for a in _abs:
		var l := _schrift(str(a.name), 20, FAST_AUS, UzTheme.font("medium"))
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS if sortierung() != "title" else Node.AUTO_TRANSLATE_MODE_DISABLED
		_abs_reihe.add_child(l)
	_abs_reihe.visible = _abs.size() > 1
	_leer_l.visible = _spiele.is_empty()
	_info.visible = not _spiele.is_empty()


## Schrift und Licht zur Auswahl.
func _zeigen() -> void:
	var g := _gewaehlt()
	if g.is_empty():
		return
	var a := Regal.abschnitt_an(_abs, _i)
	for k in _abs_reihe.get_child_count():
		var l := _abs_reihe.get_child(k) as Label
		l.add_theme_color_override("font_color", HELL if k == a else FAST_AUS)
	_ort_l.text = "%s  ·  %s" % [tr(label), tr("%d von %d") % [_i + 1, _spiele.size()]]
	_titel_l.text = Library.display_title(g)
	var teile: Array = [tr(U.playtime(Library.playtime(g)))]
	var lp := Library.last_played(g)
	if lp > 0:
		teile.append(tr("Zuletzt %s") % U.lower_first(tr(U.ago(lp))))
	_zeile_l.text = "  ·  ".join(PackedStringArray(teile))
	_stern.visible = bool(g.get("favorite", false))
	if not _eilig and not U.reduziert():
		_info.modulate.a = 0.55
		U.ankommen(_info, U.T_ORT, "rg_info").tween_property(_info, "modulate:a", 1.0, U.T_ANTWORT)
	_stimmen()


func _stimmen() -> void:
	var g := _gewaehlt()
	if g.is_empty():
		return
	var c: Variant = welt.farbe_von(g)
	welt.stimmung(c if c is Color else (welt.ruecken_von(g) as Color))


func _cover_da(id: String) -> void:
	if id == str(_gewaehlt().get("id", "")):
		_stimmen()


# --- Steuerung -----------------------------------------------------------------------------------

func _process(_dt: float) -> void:
	# Nach dem schnellen Blättern zieht sich die gewählte Hülle ganz heraus.
	if _eilig and Time.get_ticks_msec() - _letzter_ms > 190:
		_eilig = false
		welt.set("zieh_ziel", 1.0)
		_zeigen()


func nav_dir(cmd: String) -> bool:
	if _spiele.is_empty():
		return true
	match cmd:
		"left", "right":
			var gehalten := Nav.halten_takt() > 0.0
			_wiederholt = _wiederholt + 1 if gehalten else 0
			_gehe(Regal.schritt(_i, (-1 if cmd == "left" else 1) * Regal.schritt_weite(_wiederholt), _spiele.size()), gehalten, "move")
		"up", "down":
			_springen(-1 if cmd == "up" else 1)
	return true


func handle(cmd: String) -> bool:
	match cmd:
		"lb", "rb":
			_springen(-1 if cmd == "lb" else 1)
			return true
		"menu":
			_menue()
			return true
	return false


func _springen(d: int) -> void:
	_gehe(Regal.sprung(_abs, _i, d), false, "tab")


func _gehe(i: int, eilig: bool, klang: String) -> void:
	if i == _i:
		Sfx.play("bump")
		return
	_i = i
	_letzter_ms = Time.get_ticks_msec()
	_eilig = eilig
	welt.set("zieh_ziel", 0.3 if eilig else 1.0)
	welt.waehlen(_i)
	Sfx.play(klang)
	_zeigen()


func _oeffnen() -> void:
	var g := _gewaehlt()
	if g.is_empty() or main == null:
		return
	main.open_game(g)


func _favorit() -> void:
	var g := _gewaehlt()
	if g.is_empty():
		return
	var an := Library.toggle_favorite(str(g.get("id", "")))
	Sfx.play("toggle_on" if an else "toggle_off")
	g["favorite"] = an
	_stern.visible = an


func _menue() -> void:
	var g := _gewaehlt()
	if main == null:
		return
	var opts: Array = []
	if not g.is_empty():
		opts.append(["optionen", "Spieloptionen"])
		opts.append(["favorit", "Kein Favorit mehr" if bool(g.get("favorite", false)) else "Favorit"])
	var name := ""
	for e in Regal.SORTEN:
		if str(e[0]) == sortierung():
			name = str(e[1])
	opts.append(["sortierung", "Sortierung", name])
	# Keine andere Ansicht mehr (Raster, Liste): Konsolen sind ihr Regal (Regal.ist_regal).
	main.open_choice(label, opts, null, func(v: Variant) -> void:
		match str(v):
			"optionen": (func() -> void: main.open_game_options(g)).call_deferred()
			"favorit": _favorit()
			"sortierung": _sortierung_waehlen.call_deferred()
	)


func _sortierung_waehlen() -> void:
	main.open_choice("Sortierung", Regal.SORTEN, sortierung(), func(v: Variant) -> void:
		if str(v) == sortierung():
			return
		Config.set_value("library.regal_sort", str(v))
		_laden(str(_gewaehlt().get("id", "")))
		welt.einziehen()
	)


## Maus: Rad blättert, Klick wählt eine Hülle, Klick auf die gewählte öffnet sie.
func _maus(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or _spiele.is_empty():
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			_gehe(Regal.schritt(_i, -1, _spiele.size()), false, "move")
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			_gehe(Regal.schritt(_i, 1, _spiele.size()), false, "move")
		MOUSE_BUTTON_LEFT:
			var k := _unter_maus(mb.position)
			if k < 0:
				return
			if k == _i:
				Sfx.play("select")
				_oeffnen()
			else:
				_gehe(k, false, "move")
	accept_event()


func _unter_maus(p: Vector2) -> int:
	var f := svc.scale.x
	var best := -1
	var best_d := INF
	for k in welt.sichtbare_indizes():
		var lp: Variant = welt.bildlage(int(k))
		if not (lp is Vector2):
			continue
		var d := absf((lp as Vector2).x * f - p.x)
		if d < best_d:
			best_d = d
			best = int(k)
	return best if best_d < 90.0 else -1


# --- Oberfläche dahinter -------------------------------------------------------------------------

func _oberflaeche_verstecken() -> void:
	if _closing or not is_inside_tree() or main == null or not ("shell" in main):
		return
	_versteckt = true
	main.shell.visible = false
	main.background.visible = false


func _oberflaeche_zeigen() -> void:
	if not _versteckt or main == null:
		return
	_versteckt = false
	if is_instance_valid(main.shell) and not main._parked and not main._overlay_mode:
		main.shell.visible = true
		main.background.visible = true


func _notification(what: int) -> void:
	# Die Grundlage (layer.gd) bekommt die Meldung von selbst auch (jede Klasse der Kette).
	if what == NOTIFICATION_EXIT_TREE:
		_oberflaeche_zeigen()
