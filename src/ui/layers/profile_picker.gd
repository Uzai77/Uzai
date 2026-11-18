extends "res://src/ui/layers/layer.gd"
## „Wer spielt?“ (Roadmap 109): die Profile groß nebeneinander, wie auf einer Konsole. Dahinter ein
## weiches Licht in der Farbe des gewählten Profils, das beim Blättern mitwandert. A wählt (mit PIN
## erst das Ziffernfeld), Y bearbeitet, die letzte Karte legt ein neues Profil an.
##
## mode:
##   start   beim Einschalten (nur mit mehr als einem Profil, src/main.gd): nicht schließbar
##   switch  Guide → Profil wechseln, Einstellungen → Konten: B schließt
##   manage  Einstellungen → Profile verwalten: A bearbeitet
## Gewählt: chosen(id). Ein anderes Profil startet Uzai neu (main.switch_profile) – vorher löst
## sich alles bis auf das gewählte Bild auf, das zur Mitte gleitet; das neue Uzai nimmt es dort auf
## (welcome) und blendet in die Startseite über. So sieht der Wechsel wie eine Bewegung aus.

signal chosen(id: String)

const Profiles := preload("res://src/core/profiles.gd")
const ProfileAvatar := preload("res://src/ui/components/profile_avatar.gd")
const ProfilePin := preload("res://src/ui/layers/profile_pin.gd")
const ProfileEdit := preload("res://src/ui/layers/profile_edit.gd")

const AV := 172                    ## Profilbild auf den Karten
const CARD_W := 236.0
const CARD_GAP := 36.0
const WELCOME_AV := 208            ## Profilbild beim Wechsel in der Mitte

const Main := preload("res://src/main.gd")
var main: Main
var mode := "start"
var _row: HBoxContainer
var _cards: Array = []
var _glow: Control
var _title: Label
var _sub: Label
var _leaving := false


func build() -> void:
	dim = 1.0
	depth = false
	closable = mode != "start"
	_scrim.color = UzTheme.col("bg")
	set_meta("uz_hint_b", "Zurück" if closable else "—")
	set_meta("uz_hints_center", true)
	_glow = _Glow.new()
	U.full_rect(_glow)
	add_child(_glow)
	var col := U.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	U.full_rect(col)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_title = U.label("Profile verwalten" if mode == "manage" else "Wer spielt?", "xxl", "text", "title")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	col.add_child(U.spacer(0, 10, false))
	var sub_text := "Wähle dein Profil"
	if mode == "manage":
		sub_text = "Name, Bild, Farbe, PIN und Kinderprofil."
	_sub = U.label(sub_text, "m", "muted", "regular")
	if mode == "switch":
		# Mit dem Namen des Profils: von Hand übersetzt, der Name bleibt, wie er ist.
		_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_sub.text = tr("Gerade: %s") % str(Config.profile().get("name", ""))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)
	col.add_child(U.spacer(0, 64, false))
	_row = U.hbox(int(CARD_GAP))
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.set_meta("uz_row", true)
	col.add_child(_row)
	col.add_child(U.spacer(0, 120, false))
	_fill()
	_enter_motion()
	Config.profiles_changed.connect(_refresh)


func _fill() -> void:
	U.clear(_row)
	_cards.clear()
	for p in Config.profile_list():
		var c := _Card.new()
		c.profile = p
		c.current = str(p.id) == Config.profile_id and mode != "start"
		c.set_meta("uz_key", "profil:" + str(p.id))
		c.set_meta("uz_hint_a", "Bearbeiten" if mode == "manage" else "Auswählen")
		if mode != "manage":
			c.set_meta("uz_hint_y", "Bearbeiten")
			c.set_meta("uz_on_y", func() -> void: _edit(str(p.id)))
		if str(p.id) == Config.profile_id:
			c.set_meta("uz_default", true)
		c.picked.connect(func() -> void: _pick(str(p.id)))
		c.focus_entered.connect(func() -> void: _glow.aim(Profiles.color_of(p), c))
		_row.add_child(c)
		_cards.append(c)
	if Config.profile_list().size() < Profiles.MAX_PROFILES:
		var add := _Card.new()
		add.adder = true
		add.set_meta("uz_key", "profil:neu")
		add.set_meta("uz_hint_a", "Profil hinzufügen")
		add.picked.connect(_add)
		add.focus_entered.connect(func() -> void: _glow.aim(UzTheme.col("text", 0.5), add))
		_row.add_child(add)
		_cards.append(add)


func _refresh() -> void:
	if _leaving or not is_inside_tree():
		return
	var keep := Nav.focused()
	var key := str(keep.get_meta("uz_key", "")) if keep else ""
	_fill()
	await get_tree().process_frame
	for c in _cards:
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return
	if not _cards.is_empty() and Nav.top_layer() == self:
		Nav.focus(_cards[0], true)


## Titel und Karten erscheinen nacheinander und steigen leicht auf.
func _enter_motion() -> void:
	for l in [_title, _sub]:
		l.modulate.a = 0.0
		create_tween().tween_property(l, "modulate:a", 1.0, U.T_ENTER).set_delay(0.04)
	var i := 0
	for c in _cards:
		c.modulate.a = 0.0
		c.set_meta("uz_rise", 26.0)
		var tw: Tween = (c as Control).create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, U.T_ENTER).set_delay(0.08 + i * U.STAGGER)
		tw.tween_method(c.set_rise, 26.0, 0.0, U.T_ENTER + 0.1).set_delay(0.08 + i * U.STAGGER)
		i += 1


func _pick(id: String) -> void:
	if _leaving:
		return
	if mode == "manage":
		_edit(id)
		return
	var p := Profiles.find(Config.profiles, id)
	if p.is_empty():
		return
	# Schon im Spiel (Guide → Profil wechseln): das Spiel endet beim Wechsel – vorher fragen.
	if id != Config.profile_id and mode != "start" and Launcher.in_game and main:
		main.open_dialog("Profil wechseln?",
				"„%s“ läuft noch und wird beendet. Uzai startet danach mit dem anderen Profil neu." % str(Launcher.current.get("title", "Das Spiel")), [
			["Wechseln", func() -> void: _unlock(p)],
			["Abbrechen", func() -> void: pass],
		], "user", "warn")
		return
	_unlock(p)


## Mit PIN erst das Ziffernfeld; das gerade aktive Profil (aus dem Guide) braucht keine.
func _unlock(p: Dictionary) -> void:
	var id := str(p.id)
	if not p.has("pin") or (id == Config.profile_id and mode != "start"):
		_go(id)
		return
	var pin = ProfilePin.new()
	pin.mode = "check"
	pin.target = p
	pin.passed.connect(func() -> void: _go(id))
	main.open_layer(pin)


func _go(id: String) -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("select")
	if id == Config.profile_id:
		# Dasselbe Profil: die Auswahl tritt zur Seite und gibt die Startseite frei.
		_leave_soft()
		chosen.emit(id)
		return
	await _leave_to_center(id)
	chosen.emit(id)


func _leave_soft() -> void:
	Nav.release_hold(self)
	closable = true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	pivot_offset = size * 0.5
	tw.tween_property(self, "scale", Vector2.ONE * 1.035, U.T_MOVE)
	await get_tree().process_frame
	close()


## Alles außer dem gewählten Bild löst sich auf; das Bild gleitet zur Mitte und wächst auf die
## Größe, mit der das neue Uzai begrüßt.
func _leave_to_center(id: String) -> void:
	var card: Control = null
	for c in _cards:
		if not c.adder and str(c.profile.get("id", "")) == id:
			card = c
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	for l in [_title, _sub]:
		tw.tween_property(l, "modulate:a", 0.0, U.T_EXIT)
	# Alle Karten gehen (auch der Ring der gewählten); nur das Bild fliegt als Kopie weiter.
	for c in _cards:
		tw.tween_property(c, "modulate:a", 0.0, U.T_EXIT)
	if card:
		card.hide_text()
		var av: Control = card.avatar()
		var from := av.get_global_rect()
		var ghost = ProfileAvatar.new().setup(card.profile, WELCOME_AV)
		ghost.size = Vector2(WELCOME_AV, WELCOME_AV)
		ghost.pivot_offset = ghost.size * 0.5
		var vs := U.view_size()
		var target := welcome_rect(vs)
		ghost.position = from.get_center() - ghost.size * 0.5
		ghost.scale = Vector2.ONE * (from.size.x / WELCOME_AV)
		add_child(ghost)
		av.visible = false
		tw.tween_property(ghost, "position", target.position, 0.52)
		tw.tween_property(ghost, "scale", Vector2.ONE, 0.52)
		_glow.aim(Profiles.color_of(card.profile), null, target.get_center(), 1.35)
	await get_tree().create_timer(0.62).timeout


## Wo das Profilbild beim Wechsel steht (hier und in der Begrüßung des neuen Uzai).
static func welcome_rect(vs: Vector2) -> Rect2:
	return Rect2(Vector2(vs.x * 0.5 - WELCOME_AV * 0.5, vs.y * 0.42 - WELCOME_AV * 0.5), Vector2(WELCOME_AV, WELCOME_AV))


func _edit(id: String) -> void:
	if _leaving:
		return
	ProfileEdit.open_for(main, id)


## Neues Profil: erst der Name (Bildschirmtastatur), dann Bild, Farbe und mehr im Bearbeiten.
func _add() -> void:
	if _leaving:
		return
	ProfileEdit.add_new(main)


func close() -> void:
	if Config.profiles_changed.is_connected(_refresh):
		Config.profiles_changed.disconnect(_refresh)
	super()


# --- Begrüßung nach dem Wechsel ---------------------------------------------------------------

## Das neue Uzai nach einem Wechsel (--profilwechsel): das Bild steht, wo es im alten verschwand,
## darunter „Hallo, Name“; dann blendet alles in die Startseite über.
static func welcome(host: Control) -> void:
	var p := Config.profile()
	if p.is_empty():
		return
	var root := Control.new()
	U.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = UzTheme.col("bg")
	U.full_rect(bg)
	root.add_child(bg)
	var glow := _Glow.new()
	U.full_rect(glow)
	root.add_child(glow)
	host.add_child(root)
	var vs := U.view_size()
	var r := welcome_rect(vs)
	glow.aim(Profiles.color_of(p), null, r.get_center(), 1.35, true)
	var av = ProfileAvatar.new().setup(p, WELCOME_AV)
	av.position = r.position
	av.size = r.size
	av.pivot_offset = r.size * 0.5
	root.add_child(av)
	var hi := U.label(host.tr("Hallo, %s") % str(p.name), "xl", "text", "bold")
	hi.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # der Name bleibt, wie er ist
	hi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hi.position = Vector2(0, r.end.y + 34)
	hi.size = Vector2(vs.x, 60)
	hi.modulate.a = 0.0
	root.add_child(hi)
	var tw := root.create_tween()
	tw.tween_property(hi, "modulate:a", 1.0, U.T_ENTER)
	tw.tween_interval(0.55)
	tw.set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(root, "modulate:a", 0.0, 0.5)
	tw.tween_property(av, "scale", Vector2.ONE * 1.08, 0.5)
	tw.chain().tween_callback(root.queue_free)


# --- Bausteine --------------------------------------------------------------------------------

## Weiches Licht in der Farbe des gewählten Profils; gleitet mit der Auswahl.
class _Glow extends Control:
	var _col := Color(0, 0, 0, 0)
	var _pos := Vector2(-1, -1)
	var _k := 1.0
	static var _tex: GradientTexture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _tex == null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.32), Color(1, 1, 1, 0)])
			_tex = GradientTexture2D.new()
			_tex.gradient = g
			_tex.fill = GradientTexture2D.FILL_RADIAL
			_tex.fill_from = Vector2(0.5, 0.5)
			_tex.fill_to = Vector2(1.0, 0.5)
			_tex.width = 256
			_tex.height = 256

	func aim(c: Color, card: Control, at := Vector2(-1, -1), k := 1.0, instant := false) -> void:
		var to := at
		if card != null and is_instance_valid(card):
			to = card.get_global_rect().get_center() - get_global_rect().position + Vector2(0, -40)
		if to.x < 0:
			to = size * 0.5
		if _pos.x < 0 or instant:
			_pos = to
			_col = Color(c, 0.0) if not instant else c
			_k = k
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: Color) -> void:
			_col = v
			queue_redraw()
		, _col, c, 0.0 if instant else U.T_AMBIENT * 0.7)
		tw.tween_method(func(v: Vector2) -> void:
			_pos = v
			queue_redraw()
		, _pos, to, 0.0 if instant else U.T_AMBIENT * 0.7)
		tw.tween_method(func(v: float) -> void:
			_k = v
			queue_redraw()
		, _k, k, 0.0 if instant else U.T_AMBIENT * 0.7)

	func _draw() -> void:
		if _tex == null or _col.a <= 0.0:
			return
		var light := UzTheme.col("bg").get_luminance() > 0.5
		# Eckig (Marke): nur ein weites, leises Raumlicht – kein heller Kern um die Auswahl (kein
		# Glimmen am Cursor; den Rahmen trägt das Bild).
		var strict := UzTheme.strict()
		var big := Vector2(1500, 1100) * _k
		draw_texture_rect(_tex, Rect2(_pos - big * 0.5, big), false, Color(_col, (0.16 if light else 0.24) * _col.a * (0.6 if strict else 1.0)))
		if strict:
			return
		var small := Vector2(620, 520) * _k
		draw_texture_rect(_tex, Rect2(_pos - small * 0.5, small), false, Color(_col, (0.12 if light else 0.2) * _col.a))


## Eine Profilkarte: großes rundes Bild, darunter der Name (nie übersetzt) und eine leise Zeile
## (Kinderprofil, PIN, aktiv). Gewählt wächst das Bild, ein heller Ring legt sich darum, die
## anderen treten leicht zurück. adder: die Karte „Profil hinzufügen“.
class _Card extends Control:
	signal picked
	const UU := preload("res://src/ui/u.gd")
	const PA := preload("res://src/ui/components/profile_avatar.gd")
	const AVS := 172
	var profile: Dictionary = {}
	var adder := false
	var current := false
	var _av: Control
	var _name: Label
	var _line: Label
	var _rise := 0.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(236, AVS + 132)
		if adder:
			_av = _Plus.new()
			_av.custom_minimum_size = Vector2(AVS, AVS)
			_av.size = Vector2(AVS, AVS)
		else:
			_av = PA.new().setup(profile, AVS, true)
			_av.size = Vector2(AVS, AVS)
		_av.pivot_offset = Vector2(AVS, AVS) * 0.5
		add_child(_av)
		_name = UU.label("Profil hinzufügen" if adder else str(profile.get("name", "")), "l", "muted", "bold")
		if not adder:
			_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.clip_text = true
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(_name)
		var bits: Array = []
		if current:
			bits.append("Aktiv")
		if bool(profile.get("kid", false)):
			bits.append("Kinderprofil")
		_line = UU.label(" · ".join(PackedStringArray(bits)), "s", "faint", "medium")
		_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_line)
		resized.connect(_place)
		_place()
		modulate = Color(1, 1, 1, modulate.a)
		focus_entered.connect(func() -> void:
			UU.focus_anim(self, true)
			_tint(true))
		focus_exited.connect(func() -> void:
			UU.focus_anim(self, false)
			_tint(false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				grab_focus()
				Nav.activate(self)
				accept_event()
		)

	func avatar() -> Control:
		return _av

	func hide_text() -> void:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_name, "modulate:a", 0.0, UU.T_EXIT)
		tw.tween_property(_line, "modulate:a", 0.0, UU.T_EXIT)

	func set_rise(v: float) -> void:
		_rise = v
		_place()

	func _place() -> void:
		var x := (size.x - AVS) * 0.5
		_av.position = Vector2(x, 14 + _rise)
		_name.position = Vector2(0, AVS + 46 + _rise)
		_name.size = Vector2(size.x, 36)
		_line.position = Vector2(0, AVS + 84 + _rise)
		_line.size = Vector2(size.x, 26)
		queue_redraw()

	func _tint(on: bool) -> void:
		UU.set_label_color(_name, "text" if on else "muted")
		var tw := UU.tw(_av, "uz_card")
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_av, "scale", Vector2.ONE * (1.08 if on else 1.0), UU.T_FOCUS if on else UU.T_BASE)

	func activate() -> void:
		picked.emit()

	func _process(_dt: float) -> void:
		# Der Ring folgt dem wachsenden Bild.
		if has_meta("uz_f") and float(get_meta("uz_f", 0.0)) > 0.0:
			queue_redraw()

	func _draw() -> void:
		var f: float = get_meta("uz_f", 0.0)
		if f <= 0.01 or _av == null:
			return
		var s := _av.scale.x
		var r := Rect2(_av.position + _av.pivot_offset * (1.0 - s), Vector2(AVS, AVS) * s)
		UzTheme.draw_tile_focus(self, r.grow(4), int(r.size.x * 0.5) + 4, f)


## Leere Karte „Profil hinzufügen“: Glas mit einem Plus.
class _Plus extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		draw_circle(c, r, UzTheme.col("text", 0.06), true, -1.0, true)
		draw_arc(c, r - 1.0, 0.0, TAU, 96, UzTheme.col("text", 0.12), 2.0, true)
		var ip := int(size.x * 0.36)
		draw_texture_rect(Icons.tex("plus", ip), Rect2(c - Vector2(ip, ip) * 0.5, Vector2(ip, ip)), false, UzTheme.col("muted"))
