extends "res://src/ui/layers/layer.gd"
## „Dein Status“: kleines Panel an deiner Profilkarte im Guide (Reiter Freunde), wie das Profil-
## Menü im Xbox-Guide. Oben Bild, Name und was läuft; darunter zwei Spalten – Steam (Online,
## Abwesend, Unsichtbar, Offline) und Discord (Online, Abwesend, Bitte nicht stören, Unsichtbar),
## der aktuelle Status mit Haken. Unten (nicht im Spiel) Wege zum eigenen Profil, zu Aufnahmen
## (falls Uzai eine Galerie hat) und zu Einstellungen → Konten.
## Wie Uzai den Status ändert, steht in my_status.gd: Steam am PC angemeldet → über die Steam-App
## (steam://friends/status/…, still, Uzai bleibt vorn); sonst über Uzais Verbindung. Discord über
## das Social SDK; ohne diese Verbindung steht dort, wo man sie einrichtet. B schließt.

const Avatar := preload("res://src/ui/components/avatar.gd")
const PillButton := preload("res://src/ui/components/pill_button.gd")
const MyStatus := preload("res://src/core/my_status.gd")
const PersonMenu := preload("res://src/ui/layers/person_menu.gd")
const Liste := preload("res://src/ui/components/liste.gd")

const WIDTH := 720.0
const COL_W := 330.0

var anchor := Rect2()             ## Profilkarte in Bildschirmkoordinaten
const Main := preload("res://src/main.gd")
var main: Main
var guide: Node                   ## der Guide (Lautstärke, Schließen)
var source: Control               ## die Profilkarte
var _panel: PanelContainer
var _caret: Control
var _av
var _line: Label
var _steam_col: VBoxContainer
var _discord_col: VBoxContainer
var _steam_note: Label
var _opts: Array = []             ## alle Statuszeilen (_Opt)
var _route := ""


func build() -> void:
	dim = 0.3
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Zurück")
	set_meta("uz_hints_center", true)
	if is_instance_valid(source) and "hold" in source:
		source.set("hold", true)
	_panel = PanelContainer.new()
	var sb := UzTheme.box(Color(UzTheme.col("surface").lightened(0.05), 0.985), 24, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 36
	sb.shadow_offset = Vector2(0, 16)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.modulate.a = 0.0
	add_child(_panel)
	_caret = PersonMenu._Caret.new()
	_caret.color = sb.bg_color
	_caret.modulate.a = 0.0
	add_child(_caret)
	var v := U.vbox(4)
	_panel.add_child(v)
	v.add_child(_header())
	v.add_child(PersonMenu._Sep.new())
	var cols := U.hbox(20)
	var cm := U.margin(4, 4, 4, 0)
	cm.add_child(cols)
	v.add_child(cm)
	_steam_col = U.vbox(2)
	_steam_col.custom_minimum_size.x = COL_W
	cols.add_child(_steam_col)
	_discord_col = U.vbox(2)
	_discord_col.custom_minimum_size.x = COL_W
	cols.add_child(_discord_col)
	_fill_steam()
	_fill_discord()
	_shortcuts(v)
	_place.call_deferred()
	_resolve_route()
	_load_discord()
	# Dein Status laut Steam: kommt er neu, die Kopfzeile auffrischen; steht gerade eine Sitzung,
	# über sie nachfragen (nie eine eigene dafür öffnen).
	SteamCM.own_changed.connect(_update_header)
	if not MyStatus.demo():
		SteamCM.refresh_own()


func _first_focus() -> Control:
	for o in _opts:
		if is_instance_valid(o) and o.selected:
			return o
	return Nav.default_in(self)


func _header() -> Control:
	var head := U.margin(14, 10, 16, 8)
	var hr := U.hbox(16)
	head.add_child(hr)
	var p := MyStatus.profile()
	_av = Avatar.new()
	_av.setup(str(p.name), str(p.avatar), "", 64)
	_av.ring = true
	_av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(_av)
	var hc := U.vbox(2)
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.alignment = BoxContainer.ALIGNMENT_CENTER
	hr.add_child(hc)
	var name_l := U.ellipsis(U.label(str(p.name), "l", "text", "ui_bold"))
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # der eigene Name: nie übersetzen
	hc.add_child(name_l)
	_line = U.ellipsis(U.label("", "s", "muted", "regular"))
	hc.add_child(_line)
	# Uzai-Level und Abzeichen, kompakt (profile_badges.gd).
	hc.add_child(U.spacer(0, 4, false))
	hc.add_child(load("res://src/ui/sections/profile_badges.gd").compact(260.0))
	var k := U.label("DEIN STATUS", "xs", "faint", "medium")
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hr.add_child(k)
	_update_header()
	return head


func _update_header() -> void:
	var st := MyStatus.steam_now()
	var dc := MyStatus.discord_now()
	_av.status = MyStatus.overall(st if MyStatus.has_steam() else "", dc if MyStatus.has_discord() else "", Launcher.in_game)
	_av.queue_redraw()
	# Was Steam-Freunde wirklich sehen (Stand vom Chat-Server), sonst was gerade läuft.
	var seen := MyStatus.steam_seen_now()
	var pl := MyStatus.playing()
	if seen != "":
		_line.text = "Steam-Freunde sehen: %s" % seen
	else:
		_line.text = pl if pl != "" else "So sehen dich deine Freunde"


# --- Spalten ------------------------------------------------------------------------------------

func _col_head(col: VBoxContainer, icon: String, title: String) -> Label:
	var h := U.margin(14, 4, 14, 2)
	var r := U.hbox(10)
	h.add_child(r)
	var ic := U.icon(icon, 20, icon)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var t := U.label(title, "m", "text", "ui_bold")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(t)
	col.add_child(h)
	var nm := U.margin(14, 0, 14, 6)
	var note := U.label("", "xs", "faint", "regular", true)
	note.custom_minimum_size = Vector2(COL_W - 28, 0)
	nm.add_child(note)
	col.add_child(nm)
	return note


func _fill_steam() -> void:
	_drop_opts(_steam_col)
	U.clear(_steam_col)
	_steam_note = _col_head(_steam_col, "steam", "Steam")
	_steam_note.text = MyStatus.route_note(_route) if _route != "" else "…"
	if _route in ["login", "unknown"] or not MyStatus.has_steam():
		_steam_note.text = MyStatus.route_note(_route) if _route != "" else "Steam ist nicht eingerichtet."
		_steam_note.add_theme_color_override("font_color", UzTheme.col("muted"))
		if _route == "login" and _can_leave():
			_steam_col.add_child(_link("Bei Steam anmelden", "steam", _goto_accounts))
		return
	for o in MyStatus.STEAM_OPTS:
		_steam_col.add_child(_opt("steam", str(o[0]), str(o[1])))
	_mark()


func _fill_discord() -> void:
	_drop_opts(_discord_col)
	U.clear(_discord_col)
	var note := _col_head(_discord_col, "discord", "Discord")
	if not MyStatus.has_discord():
		note.text = "Nicht verbunden. Den Status ändert Uzai über die Discord-Verbindung für Nachrichten (Einstellungen → Konten) – die Sprachkanal-Verbindung kann das nicht."
		note.add_theme_color_override("font_color", UzTheme.col("muted"))
		if _can_leave():
			_discord_col.add_child(_link("Discord verbinden", "discord", _goto_accounts))
		return
	note.text = "über die Discord-Verbindung von Uzai" if not MyStatus.demo() else "Vorführung"
	for o in MyStatus.DISCORD_OPTS:
		_discord_col.add_child(_opt("discord", str(o[0]), str(o[1])))
	_mark()


func _drop_opts(col: Node) -> void:
	_opts = _opts.filter(func(o): return is_instance_valid(o) and not col.is_ancestor_of(o))


func _opt(service: String, id: String, text: String) -> Control:
	var it := _Opt.new()
	it.service = service
	it.id = id
	it.text = text
	it.set_meta("uz_key", "st:%s:%s" % [service, id])
	it.on_a = func() -> void: _pick(it)
	_opts.append(it)
	return it


## Haken an den aktuellen Status setzen.
func _mark() -> void:
	var st := MyStatus.steam_now()
	var dc := MyStatus.discord_now()
	for o in _opts:
		if is_instance_valid(o):
			o.set_selected(o.id == (st if o.service == "steam" else dc))
			o.set_hint()


func _pick(it) -> void:
	if it.pending or it.selected:
		return
	it.set_pending(true)
	var err: String
	if it.service == "steam":
		err = await MyStatus.set_steam(it.id)
	else:
		err = await MyStatus.set_discord(it.id)
	if not is_instance_valid(it):
		return
	it.set_pending(false)
	if err != "":
		Toasts.show_toast("%s-Status nicht geändert" % ("Steam" if it.service == "steam" else "Discord"), err, "warning", { "ms": 6000 })
	else:
		Sfx.play("toggle_on")
	_after_change()


func _after_change() -> void:
	if not is_inside_tree():
		return
	_mark()
	_update_header()
	if is_instance_valid(source) and source.has_method("refresh"):
		source.call("refresh")


func _resolve_route() -> void:
	if not MyStatus.has_steam():
		return
	var r := await MyStatus.steam_route_now()
	if not is_inside_tree():
		return
	var old := _route
	_route = r
	if (r in ["login", "unknown"]) != (old in ["login", "unknown"]):
		var had := Nav.focused() != null and _steam_col.is_ancestor_of(Nav.focused())
		_fill_steam()
		if had:
			await get_tree().process_frame
			var d := Nav.default_in(self)
			if d:
				Nav.focus(d, true)
		_place()
	elif is_instance_valid(_steam_note):
		_steam_note.text = MyStatus.route_note(r)


func _load_discord() -> void:
	if not MyStatus.has_discord():
		return
	await MyStatus.refresh_discord()
	_after_change()


# --- Wege ---------------------------------------------------------------------------------------

## Im Spiel oder Video läge alles Weitere hinter dem Spiel: dort nur der Status.
func _can_leave() -> bool:
	return not Launcher.in_game and not Video.active and main != null


func _shortcuts(v: VBoxContainer) -> void:
	if not _can_leave():
		return
	var row := U.hbox(10)
	row.set_meta("uz_group", "me:ways")
	if main.sections is Dictionary and (main.sections as Dictionary).has("achievements"):
		row.add_child(_pill("Mein Profil ansehen", "user", "me:profil", func() -> void: _leave(func() -> void: main.goto("achievements", "profil"))))
	# Galerie und Abzeichen legen sich über Guide und Panel: B führt zurück hierher statt aus dem
	# Guide hinaus.
	row.add_child(_pill("Aufnahmen", "camera", "me:aufnahmen", func() -> void: main.open_captures()))
	row.add_child(_pill("Abzeichen", "star_f", "me:abzeichen", func() -> void: Badges.open_page()))
	row.add_child(_pill("Konten", "settings", "me:konten", _goto_accounts))
	v.add_child(PersonMenu._Sep.new())
	var m := U.margin(10, 4, 10, 0)
	m.add_child(row)
	v.add_child(m)


func _pill(t: String, ic: String, key: String, cb: Callable) -> Control:
	var b = PillButton.new().setup(t, "", "flat", ic)
	b.set_meta("uz_key", key)
	b.pressed.connect(cb)
	return b


## Knopf unten in einer Spalte (beide Spalten auf einer Höhe: rechts/links springt hinüber).
func _link(t: String, ic: String, cb: Callable) -> Control:
	var m := U.margin(10, 4, 10, 4)
	m.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	m.add_child(_pill(t, ic, "me:link:" + ic, cb))
	return m


func _goto_accounts() -> void:
	_leave(func() -> void: main.goto("settings", "konten"))


func _leave(go: Callable) -> void:
	close()
	if is_instance_valid(guide):
		guide.close()
	go.call()


# --- Lage und Ebene ------------------------------------------------------------------------------

## Unter der Karte, rechtsbündig mit ihr; der Pfeil zeigt auf die Mitte des Profilbilds.
func _place() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var first := _panel.modulate.a < 0.01
	var ps := _panel.get_combined_minimum_size()
	var vs := get_viewport_rect().size
	var below := anchor.end.y + 14 + ps.y <= vs.y - 80
	var pos := Vector2(anchor.end.x - ps.x, anchor.end.y + 14 if below else anchor.position.y - ps.y - 14)
	pos.x = clampf(pos.x, 40, vs.x - ps.x - 40)
	pos.y = clampf(pos.y, 24, vs.y - ps.y - 24)
	_panel.position = pos
	_panel.size = ps
	var cx := clampf(anchor.position.x + 38.0, pos.x + 30, pos.x + ps.x - 30)
	_caret.down = not below
	_caret.position = Vector2(cx - 11, pos.y - 10 if below else pos.y + ps.y - 1)
	_caret.queue_redraw()
	if not first:
		return
	_panel.pivot_offset = Vector2(cx - pos.x, 0.0 if below else ps.y)
	_panel.scale = Vector2(0.96, 0.96)
	var tw := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_caret, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_panel, "scale", Vector2.ONE, U.T_MOVE)


func handle(cmd: String) -> bool:
	match cmd:
		"lt", "rt":
			if is_instance_valid(guide) and guide.has_method("volume_step"):
				guide.call("volume_step", -1 if cmd == "lt" else 1)
			return true
		"lb", "rb", "x", "y":
			return true
		"guide":
			close()
			return false
	return false


func close() -> void:
	if is_instance_valid(source) and "hold" in source:
		source.set("hold", false)
	super()


func _exit_motion(tw: Tween) -> void:
	if is_instance_valid(_panel):
		tw.set_parallel(true)
		tw.tween_property(_panel, "scale", Vector2(0.97, 0.97), U.T_FAST)


## Eine Statuszeile: Punkt in der Farbe des Status, Name, rechts ein Haken beim aktuellen.
class _Opt extends Control:
	const UU := preload("res://src/ui/u.gd")
	const Dot := preload("res://src/ui/components/my_card.gd")
	const ROW := 54
	var service := ""
	var id := ""
	var text := ""
	var selected := false
	var pending := false
	var on_a: Callable
	var _check: TextureRect
	var _wait: Label

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(COL_W, ROW)
		var m := UU.margin(16, 0, 16, 0)
		UU.full_rect(m)
		add_child(m)
		var row := UU.hbox(14)
		m.add_child(row)
		var d := Dot.StatusDot.new()
		d.id = id
		d.px = 14.0
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(d)
		var l := UU.label(text, "m", "text", "ui_bold")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(l)
		_wait = UU.label("ändert …", "xs", "muted", "medium")
		_wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_wait.visible = pending
		row.add_child(_wait)
		_check = UU.icon("check", 22, "accent")
		_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_check.visible = selected and not pending
		row.add_child(_check)
		focus_entered.connect(func() -> void:
			UU.etikett(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			UU.etikett(self, false)
			queue_redraw()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func set_selected(on: bool) -> void:
		selected = on
		if _check:
			_check.visible = on and not pending

	func set_pending(on: bool) -> void:
		pending = on
		if _wait:
			_wait.visible = on
		if _check:
			_check.visible = selected and not on

	func set_hint() -> void:
		set_meta("uz_hint_a", "Aktuell" if selected else ("%s: %s" % ["Steam" if service == "steam" else "Discord", text]))

	func activate() -> void:
		if on_a.is_valid():
			on_a.call()

	## Schon gewählt oder noch dabei: nur ein leises Anstoßen statt Bestätigen.
	func activate_sound() -> String:
		return "bump" if selected or pending else "select"

	func _draw() -> void:
		Liste.zeilen_auswahl(self, 16)
