extends RefCounted
## Reiter „Bild in Bild“ im Guide (nur solange es läuft, als erster Reiter; src/core/pip.gd). Die
## Guide-Taste öffnet ihn gleich – wie „Video“ beim Vollbild: die Videosteuerung zuerst, der Rest
## des Guides (Start, Freunde, Chat …) einen Reiter weiter. Im Spiel gehört der Controller dem Spiel –
## hier steuerst du das kleine Video:
## - Block: Vorschaubild, Titel, Stand mit Balken; Vollbild (ohne Spiel, vorgewählt) · Pause/Weiter
##   · Schließen. Im Spiel steht Pause vorn.
## - Zeilen: −10 s · +10 s · Verschieben · Größe (Klein/Mittel/Groß) · Deckkraft.
## - Darunter: wo das Bild liegt (kleiner Bildschirm), die vier Ecken, die Lautstärke (LT/RT).
## Verschieben: Der Guide tritt zurück, das Bild liegt obenauf; linker Stick (oder Steuerkreuz)
## schiebt es weich über den Bildschirm, LT/RT ändern die Größe, A lässt es dort (nah am Rand rastet
## es ein), B setzt es zurück. Die Guide-Taste schließt und behält die neue Stelle.
## Dazu im Reiter Spiel (im Spiel, ohne Video): „Bild in Bild“ startet ein Video aus „Weiterschauen“
## gleich klein in der Ecke; „Lösungshilfe“ sucht Videos zum Spiel (src/ui/layers/walkthrough_sheet.gd).

const U := preload("res://src/ui/u.gd")
const ProgressBarUz := preload("res://src/ui/components/progress_bar.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")
const Pip := preload("res://src/core/pip.gd")
const WalkthroughSheet := preload("res://src/ui/layers/walkthrough_sheet.gd")

const MOVE_HINTS := [["lt", ""], ["rt", "Größe"]]

## Aus dem Schnellmenü („Bild verschieben“): Der Reiter beginnt gleich mit dem Verschieben.
static var sofort_bewegen := false


## Reiter des Guides: „Bild in Bild“ als erster, solange es läuft (der Guide geht dort auf).
static func tabs(base: Array, main: Node) -> Array:
	var t := base.duplicate()
	if main != null and main.get("pip") != null and main.pip.active():
		t.insert(0, ["pip", "Bild in Bild"])
	return t


## Knöpfe oben im Reiter, in dieser Reihenfolge: [Kennung, Hauptaktion?]. Ohne Spiel zuerst
## Vollbild (vorgewählt, ein Druck auf A), dann Pause und Schließen; im Spiel geht Vollbild nicht –
## dort ist Pause vorn. Aus der Lösungshilfe kommt „Andere Videos“ dazu.
static func pill_ids(in_game: bool, help: bool) -> Array:
	if not in_game:
		return [["full", true], ["play", false], ["close", false]]
	var out: Array = [["play", true]]
	if help:
		out.append(["help", false])
	out.append(["close", false])
	return out


## Bild in Bild geschlossen, der Guide bleibt offen: den Reiter aus der Leiste nehmen.
static func drop_tab(g: Control) -> void:
	if is_instance_valid(g._tabs_row):
		g._fill_tabs()


## Inhalt des Reiters in guide._content.
static func fill(g: Control) -> void:
	var pip: Node = g.main.pip
	var c: VBoxContainer = g._content
	var v: Dictionary = Video.video
	var frac := Video.pos / Video.duration if Video.duration > 0.0 else -1.0
	var pills: Array = []
	for p in pill_ids(Launcher.in_game, bool(v.get("help", false))):
		var art := "primary" if bool(p[1]) else "flat"
		match str(p[0]):
			# Im Spiel kein Vollbild: das Video läge dann über dem Spiel, ohne dass Uzai vorn ist.
			"full":
				pills.append(["Vollbild", art, "fullscreen", "p:full", func() -> void:
					g.close()
					pip.leave(), "Vollbild"])
			"play":
				pills.append(["Weiter" if Video.paused else "Pause", art, "play" if Video.paused else "pause", "p:play", func() -> void:
					Video.toggle_pause()
					g._rebuild_keep("p:play"), "Weiter" if Video.paused else "Pause"])
			# Aus der Lösungshilfe: gleich ein anderes Video zum Spiel suchen (läuft dann an derselben Stelle).
			"help":
				pills.append(["Andere Videos", art, "bulb", "p:help", func() -> void: WalkthroughSheet.open_for(g), "Lösungshilfe"])
			"close":
				pills.append(["Schließen", "danger", "close", "p:close", func() -> void:
					pip.close()
					drop_tab(g)
					g._show_tab("spiel", true, 1), "Bild in Bild schließen"])
	var head: Control = g._head_row({}, str(v.get("title", "Video")), sub_text(), frac, pills, VideoCard.thumb_url(v))
	c.add_child(g._rv(head))
	c.add_child(g._divider(22))
	var list: VBoxContainer = g._list()
	list.set_meta("uz_group", "guide:pip")
	c.add_child(list)
	# Live-Streams (Twitch) lassen sich nicht spulen.
	if not Video.is_live():
		list.add_child(g._quick("−10 s", "rewind", func() -> void: Video.seek(-10.0), "", false, "p:back"))
		list.add_child(g._quick("+10 s", "forward", func() -> void: Video.seek(10.0), "", false, "p:fwd"))
	var mv: Control = g._quick("Verschieben", "move", func() -> void: _toggle_move(g), "Linker Stick", false, "p:move")
	mv.set_meta("uz_hint_a", "Verschieben")
	list.add_child(mv)
	if sofort_bewegen:
		sofort_bewegen = false
		(func() -> void:
			if is_instance_valid(mv) and is_instance_valid(g):
				Nav.focus(mv)
				_toggle_move(g)).call_deferred()
	list.add_child(g._quick("Größe", "pip", func() -> void:
		pip.set_size(Pip.step_size(pip.size_key(), 1) if pip.size_key() != "l" else "s")
		g._rebuild_keep("q:p:size")
	, str(Pip.SIZE_NAMES.get(pip.size_key(), "")), false, "p:size"))
	list.add_child(g._quick("Deckkraft", "eye", func() -> void:
		pip.cycle_opacity()
		g._rebuild_keep("q:p:alpha")
	, "%d %%" % pip.opacity(), false, "p:alpha"))
	c.add_child(g._divider(22))
	c.add_child(g._section("Ecke", str(Pip.CORNER_NAMES.get(pip.corner(), ""))))
	c.add_child(U.spacer(0, 8, false))
	var crow := U.hbox(16)
	c.add_child(g._rv(crow))
	var map := _Map.new()
	map.pip = pip
	crow.add_child(map)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	grid.set_meta("uz_group", "guide:pipcorner")
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crow.add_child(grid)
	for k in ["oben_links", "oben_rechts", "unten_links", "unten_rechts"]:
		var key := str(k)
		var on: bool = pip.corner() == key
		var b = g.GuideRow.new().setup(str(Pip.CORNER_NAMES[key]), "check" if on else "")
		b.icon_color = "accent"
		b.min_h = 44
		b.set_meta("uz_key", "p:c:" + key)
		b.set_meta("uz_hint_a", "Hierhin")
		b.activated.connect(func() -> void:
			pip.set_corner(key)
			g._rebuild_keep("p:c:" + key)
		)
		grid.add_child(b)
	c.add_child(g._divider(22))
	c.add_child(g._section("Lautstärke", "LT/RT"))
	var vrow := U.hbox(14)
	c.add_child(g._rv(vrow))
	var ic := U.icon("volume", 22, "muted")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vrow.add_child(ic)
	var bar = ProgressBarUz.new().setup(float(Video.volume_level()) / float(Video.VOLUME_MAX), "accent", 2, 0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vrow.add_child(bar)
	var vl := U.label("%d %%" % Video.volume_level(), "17", "text", "ui_bold")
	vl.clip_text = false
	vl.custom_minimum_size.x = 60
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vrow.add_child(vl)
	if pip.exclusive and Launcher.in_game:
		var warn := U.hbox(10)
		warn.add_child(U.icon("info", 20, "warn"))
		var wl := U.label(Pip.exclusive_hint(), "16", "muted", "medium", true)
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warn.add_child(wl)
		c.add_child(U.spacer(0, 14, false))
		c.add_child(g._rv(warn))
	# Stand und Pegel laufend nachziehen; Verschieben liest hier den Stick.
	var t := _Ticker.new()
	t.guide = g
	t.head = head
	t.bar = bar
	t.vol_l = vl
	t.map = map
	c.add_child(t)


## „Bild in Bild · Läuft · 3:12 von 10:00“
static func sub_text() -> String:
	return Pip.status_text()


## Im Reiter Spiel (im Spiel, ohne Video): ein Video gleich als Bild in Bild.
static func can_start() -> bool:
	return Launcher.in_game and not Video.active and YouTube.tools_ready() and not YouTube.continue_list().is_empty()


static func open_picker(g: Control) -> void:
	var main: Node = g.main
	var list: Array = YouTube.continue_list().slice(0, 8)
	var s = Sheet.new()
	s.setup("Bild in Bild", "Läuft klein in der Ecke weiter, das Spiel bleibt vorn", 820)
	s.fill_func = func(sheet) -> void:
		for i in list.size():
			var e: Dictionary = list[i]
			var r = SettingRow.new()
			r.setup("action", str(e.get("title", "Video")), "")
			r.icon_name = "video"
			var d := float(e.get("duration", 0))
			var bits := PackedStringArray()
			if str(e.get("channel", "")) != "":
				bits.append(str(e.channel))
			if d > 0.0:
				bits.append(VideoCard.left_text(int(d - float(e.get("pos", 0)))))
			r.subtitle = "  ·  ".join(bits)
			r.value_text = "Weiterschauen"
			var idx := i
			r.on_activate = func() -> void:
				sheet.close()
				g.close()
				main.pip.start(list, idx)
			sheet.add_row(r)
	main.open_layer(s)


# --- Verschieben -----------------------------------------------------------------------------

static func moving(g: Control) -> bool:
	return g.main != null and g.main.get("pip") != null and g.main.pip.mode == "bewegen"


static func _toggle_move(g: Control) -> void:
	var pip: Node = g.main.pip
	if pip.mode == "bewegen":
		await _end_move(g, true)
		return
	await pip.move_begin()
	if pip.mode == "bewegen":
		_fade_guide(g, true)


## Der Guide tritt beim Verschieben fast ganz zurück; oben bleibt eine kleine Leiste mit den Tasten.
static func _fade_guide(g: Control, on: bool) -> void:
	var pill: Control = g.get_meta("uz_pip_pill") if g.has_meta("uz_pip_pill") else null
	if on and not is_instance_valid(pill):
		pill = _move_pill()
		g.add_child(pill)
		g.set_meta("uz_pip_pill", pill)
	# Die Leiste weicht („Gehen“) bzw. kommt zurück („Ankommen“), die Pille kommt W_ORT von oben.
	for ch in g.get_children():
		if ch is CanvasItem and ch != pill:
			if on:
				U.weg(ch, "uz_pip_fade").tween_property(ch, "modulate:a", 0.0, U.T_WEG)
			else:
				U.ankommen(ch, U.T_ORT, "uz_pip_fade").tween_property(ch, "modulate:a", 1.0, U.T_ORT)
	if is_instance_valid(pill):
		var tw := (U.ankommen(pill, U.T_ORT, "uz_pip_fade") if on else U.weg(pill, "uz_pip_fade")).set_parallel(true)
		tw.tween_property(pill, "modulate:a", 1.0 if on else 0.0, U.T_ORT if on else U.T_WEG)
		tw.tween_property(pill, "offset_top", 40.0, U.T_ORT).from(40.0 - U.weg_px(U.W_ORT) if on else 40.0)
		if not on:
			tw.chain().tween_callback(pill.queue_free)
			g.remove_meta("uz_pip_pill")
	var f := Nav.focused()
	if f and f.has_meta("uz_key") and str(f.get_meta("uz_key")) == "q:p:move":
		f.set_meta("uz_hint_a", "Fertig" if on else "Verschieben")
	g.set_meta("uz_hint_b", "Zurück" if on else "Schließen")
	if on:
		g.set_meta("uz_pip_hints", g.get_meta("uz_hints", []))
		g.set_meta("uz_hints", MOVE_HINTS)
	elif g.has_meta("uz_pip_hints"):
		g.set_meta("uz_hints", g.get_meta("uz_pip_hints"))
		g.remove_meta("uz_pip_hints")
	Nav.focus_moved.emit(Nav.focused())


static func _move_pill() -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(Color(UzTheme.col("surface_hi"), 0.96), 999, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 24
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 22
	sb.shadow_offset = Vector2(0, 8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_top = 40
	p.modulate.a = 0.0
	var row := U.hbox(18)
	p.add_child(row)
	var ic := U.icon("move", 26, "accent")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var t := U.label("Bild in Bild verschieben", "m", "text", "ui_bold")
	t.clip_text = false
	row.add_child(t)
	# Die Tasten (A, B, LT/RT) stehen unten in der Hinweisleiste.
	var l := U.label("mit dem linken Stick oder dem Steuerkreuz", "m", "muted", "medium")
	l.clip_text = false
	row.add_child(l)
	return p


## Befehle des Guides, solange verschoben wird (true: erledigt).
static func command(g: Control, cmd: String) -> bool:
	if not moving(g):
		return false
	var pip: Node = g.main.pip
	match cmd:
		"b":
			Sfx.play("back")
			_end_move(g, false)
		"lt", "rt":
			var k: String = Pip.step_size(pip.size_key(), -1 if cmd == "lt" else 1)
			Sfx.play("tick" if k != pip.size_key() else "bump", 1.0 + (0.08 if cmd == "rt" else -0.08))
			pip.set_size(k)
		"guide":
			return false
	# Alles andere (LB/RB, X, Y) ruht, solange verschoben wird.
	return true


static func _end_move(g: Control, keep: bool) -> void:
	await g.main.pip.move_end(keep)
	_fade_guide(g, false)
	# Ecke und Größe haben sich geändert: Reiter neu, die Auswahl bleibt auf „Verschieben“.
	if is_instance_valid(g):
		g._rebuild_keep("q:p:move")


## Richtungen beim Verschieben: der Stick wirkt in _Ticker, hier nur schlucken.
static func nav_dir(g: Control, _dir: String) -> bool:
	return moving(g)


## Läuft im Reiter: Stand, Balken, Pegel, kleiner Bildschirm; beim Verschieben der Stick.
class _Ticker extends Node:
	const P := preload("res://src/core/pip.gd")
	var guide: Control
	var head: Control
	var bar: Control
	var vol_l: Label
	var map: Control
	var _t := 0.0

	func _ready() -> void:
		Video.volume_changed.connect(_on_volume)

	func _exit_tree() -> void:
		if Video.volume_changed.is_connected(_on_volume):
			Video.volume_changed.disconnect(_on_volume)

	func _on_volume(level: int) -> void:
		if is_instance_valid(bar):
			bar.call("set_value", float(level) / float(Video.VOLUME_MAX))
		if is_instance_valid(vol_l):
			vol_l.text = "%d %%" % level

	func _process(dt: float) -> void:
		var pip: Node = guide.main.pip if is_instance_valid(guide) and guide.main else null
		if pip == null:
			return
		if pip.mode == "bewegen":
			pip.move_by_stick(_axis(), dt)
		_t += dt
		if _t < 0.25:
			return
		_t = 0.0
		if is_instance_valid(map):
			map.queue_redraw()
		# Block oben: die Zeile (Stand) und der Balken unter dem Titel.
		if is_instance_valid(head):
			var sl: Variant = head.get_meta("uz_sub", null)
			if sl is Label and is_instance_valid(sl):
				(sl as Label).text = P.status_text()
			var hb: Variant = head.get_meta("uz_bar", null)
			if hb is Control and is_instance_valid(hb) and Video.duration > 0.0:
				(hb as Control).call("set_value", Video.pos / Video.duration)

	## Linker Stick (stärkster Ausschlag aller Controller), sonst Steuerkreuz bzw. Pfeiltasten.
	func _axis() -> Vector2:
		var best := Vector2.ZERO
		for d in Input.get_connected_joypads():
			var a := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
			if a.length() > best.length():
				best = a
		if best.length() >= P.DEADZONE:
			return best
		var k := Vector2(Input.get_action_strength("uz_right", true) - Input.get_action_strength("uz_left", true),
			Input.get_action_strength("uz_down", true) - Input.get_action_strength("uz_up", true))
		return k.normalized() * 0.75 if k.length() > 0.1 else Vector2.ZERO


## Kleiner Bildschirm: wo das Bild gerade liegt (Gold), in der richtigen Größe.
class _Map extends Control:
	var pip: Node

	func _ready() -> void:
		custom_minimum_size = Vector2(176, 99)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UzTheme.box(Color(UzTheme.col("text"), 0.06), 10, 2, Color(UzTheme.col("text"), 0.22)), r)
		if pip == null:
			return
		var w: Rect2i = pip.work
		if w.size.x <= 0 or w.size.y <= 0:
			return
		var pr: Rect2i = pip.rect()
		var k := Vector2(size.x / float(w.size.x), size.y / float(w.size.y))
		var p := Vector2(pr.position - w.position) * k
		var s := Vector2(pr.size) * k
		draw_style_box(UzTheme.box(UzTheme.col("accent"), 4), Rect2(p, s))
