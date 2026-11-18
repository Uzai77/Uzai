extends "res://src/ui/layers/layer.gd"
## Quelle wählen – wie der Stream-Bildschirm von Nuvio TV.
##
## Links groß der Titel (Schriftzug oder Name) mit Folge bzw. Genre und Jahr, rechts die Quellen:
## oben die Filter (Alle und je Addon, mit Anzahl), darunter der Stand jeder Quelle (lädt, fertig,
## Fehler) und in einer ruhigen Fläche die Liste. Sie füllt sich, sobald eine Quelle antwortet.
## Jede Zeile zeigt als Chips Qualität, HDR, Codec, Ton, Herkunft, Größe, Sprachen und ob die Quelle
## sofort bereit ist, darunter den ganzen Dateinamen und die Beschreibung des Addons (mit Fokus
## ausgeklappt, Zeile für Zeile). Fremde Texte stehen nur als Text da (Label, ohne Übersetzung).
## A spielt ab (bei angefangenen Titeln mit der Frage „Fortsetzen oder von vorn?“), Y filtert nach
## Qualität, X nach Sprache.

const MovieBackdrop := preload("res://src/ui/components/movie_backdrop.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const NavItem := preload("res://src/ui/components/nav_item.gd")
const TabStrip := preload("res://src/ui/components/tab_strip.gd")

const GUT := 96
const LEFT := 0.38                 ## Anteil der linken Spalte (Titel)

const Main := preload("res://src/main.gd")
var main: Main
var meta: Dictionary = {}
var video_id := ""
var mode := "ask"                  ## ask: bei Fortschritt fragen · resume: fortsetzen · start: von vorn
var _streams: Array = []
var _addon := ""
var _quality := 0
var _lang := ""                    ## Filter: "" jede Sprache, "DE" …, "MULTI"
var _want := ""                    ## bevorzugte Sprache (Movies.pref_lang), leuchtet in den Chips
var _done := false
var _user_moved := false
var _meta_ready := false
var _bd: Control
var _strip: HBoxContainer
var _status_box: HBoxContainer
var _list: VBoxContainer
var _list_sc: ScrollContainer
var _msg: VBoxContainer
var _refresh_btn: Button
var _q_btn: Button
var _l_btn: Button
var _gen := 0
var _status_timer: Timer


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), 1.0)
	set_meta("uz_hint_b", "Zurück")
	set_meta("uz_hints", [["y", "Qualität"], ["x", "Sprache"]])
	_want = Movies.pref_lang()
	_bd = MovieBackdrop.new()
	_bd.layout = "streams"
	add_child(_bd)
	_bd.show_item(meta, true)
	_build_left()
	_build_right()
	_status_timer = Timer.new()
	_status_timer.wait_time = 0.3
	_status_timer.timeout.connect(_update_status)
	add_child(_status_timer)
	# Vorschau (Startseite, Weiterschauen): die vollen Angaben im Hintergrund nachladen.
	_meta_ready = meta.has("videos")
	if not _meta_ready:
		_load_meta()
	_load()


func _first_focus() -> Control:
	return _refresh_btn


func handle(cmd: String) -> bool:
	if cmd == "y":
		_pick_quality()
		return true
	if cmd == "x":
		_pick_lang()
		return true
	return false


# --- Links: Titel -------------------------------------------------------------------------------

func _build_left() -> void:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.anchor_right = LEFT
	host.anchor_bottom = 1.0
	host.offset_left = GUT
	host.offset_right = -24
	add_child(host)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(center)
	host.add_child(center)
	var col := U.vbox(12)
	col.custom_minimum_size = Vector2(560, 0)
	center.add_child(col)
	var name_ := str(meta.get("name", ""))
	var title := U.label(name_, "xxl", "text", "title", true)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Films bzw. der Serie
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(560, 0)
	title.max_lines_visible = 3
	U.shadow(title, 0.5)
	var logo_url := str(meta.get("logo", ""))
	if logo_url != "":
		var logo := TextureRect.new()
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(560, 200)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(logo)
		title.visible = false
		Art.load_image(logo_url, 560, func(t: Texture2D) -> void:
			if not is_instance_valid(logo):
				return
			if t:
				logo.texture = t
			else:
				logo.visible = false
				title.visible = true
		)
	col.add_child(title)
	var ep := _episode()
	if not ep.is_empty():
		var el := U.label(Art.episode_code(int(ep.get("season", 0)), int(ep.get("episode", 0)), true), "l", "muted", "medium")
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(el)
		var et := str(ep.get("title", ""))
		if et != "":
			var tl := U.label(et, "m", "text", "regular", true)
			tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Titel der Folge
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tl.custom_minimum_size = Vector2(560, 0)
			col.add_child(tl)
	else:
		var parts := PackedStringArray()
		var g: Array = meta.get("genres", []) if meta.get("genres") is Array else []
		if not g.is_empty():
			parts.append(", ".join(PackedStringArray(g.slice(0, 2))))
		if str(meta.get("year", "")) != "":
			parts.append(str(meta.year))
		var rt := Art.runtime_text(meta.get("runtime", ""))
		if rt != "":
			parts.append(rt)
		var il := U.label(Art.SEP.join(parts), "m", "muted", "medium")
		il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(il)
	var p: Dictionary = Movies.progress(str(meta.get("id", "")), video_id)
	if Art.can_resume(float(p.get("position", 0.0)), float(p.get("duration", 0.0))):
		var rl := U.label("Angefangen: %s von %s" % [Art.clock(float(p.position)), Art.clock(float(p.duration))], "s", "accent", "medium")
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(rl)


## Die Folge zu video_id (leer bei Filmen oder solange die Folgen fehlen).
func _episode() -> Dictionary:
	for v in (meta.get("videos", []) if meta.get("videos") is Array else []):
		if str(v.get("id", "")) == video_id:
			return v
	if meta.has("episode") and str(meta.get("video_id", "")) == video_id and int(meta.get("episode", 0)) > 0:
		return { "season": meta.get("season", 0), "episode": meta.episode, "title": meta.get("episode_title", "") }
	return {}


# --- Rechts: Filter und Liste ---------------------------------------------------------------------

func _build_right() -> void:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.anchor_left = LEFT
	host.anchor_right = 1.0
	host.anchor_bottom = 1.0
	host.offset_top = 64
	host.offset_right = -GUT
	host.offset_bottom = -96
	add_child(host)
	var col := U.vbox(14)
	U.full_rect(col)
	host.add_child(col)
	var top := U.hbox(12)
	top.set_meta("uz_group", "quellen-kopf")
	col.add_child(top)
	_refresh_btn = U.button("", "refresh", "icon")
	_refresh_btn.set_meta("uz_key", "quellen:neu")
	_refresh_btn.set_meta("uz_hint_a", "Neu suchen")
	_refresh_btn.pressed.connect(func() -> void: _load())
	top.add_child(_refresh_btn)
	_q_btn = U.button("Jede Qualität", "quality", "flat")
	_q_btn.custom_minimum_size.y = 56
	_q_btn.set_meta("uz_key", "quellen:qualitaet")
	_q_btn.set_meta("uz_hint_a", "Qualität wählen")
	_q_btn.pressed.connect(_pick_quality)
	top.add_child(_q_btn)
	_l_btn = U.button("Jede Sprache", "chat", "flat")
	_l_btn.custom_minimum_size.y = 56
	_l_btn.set_meta("uz_key", "quellen:sprache")
	_l_btn.set_meta("uz_hint_a", "Sprache wählen")
	_l_btn.pressed.connect(_pick_lang)
	top.add_child(_l_btn)
	# Viele Addons: die Filter laufen unter den Knöpfen weiter, statt die Spalte zu verbreitern.
	var sm := ScrollContainer.new()
	sm.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sm.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sm.follow_focus = true
	sm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip = TabStrip.new()
	_strip.style = "chip"
	_strip.set_meta("uz_group", "quellen-filter")
	_strip.set_meta("uz_enter", "sel")
	sm.add_child(_strip)
	top.add_child(sm)
	_status_box = U.hbox(22)
	var stm := U.margin(8, 0, 0, 0)
	stm.add_child(_status_box)
	col.add_child(stm)
	var panel := PanelContainer.new()
	var sb := UzTheme.box(Color(UzTheme.col("surface"), 0.72), UzTheme.r_panel())
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(panel)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inner)
	_list_sc = ScrollContainer.new()
	_list_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_list_sc.follow_focus = false
	_list_sc.set_meta("uz_pad_v", 110.0)
	U.full_rect(_list_sc)
	inner.add_child(_list_sc)
	_list = U.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.set_meta("uz_group", "quellen")
	_list.set_meta("uz_mem", true)
	_list_sc.add_child(_list)
	_msg = U.vbox(14)
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.alignment = BoxContainer.ALIGNMENT_CENTER
	U.full_rect(_msg)
	inner.add_child(_msg)


func _load_meta() -> void:
	var got: Variant = await Movies.meta(str(meta.get("type", "movie")), str(meta.get("id", "")))
	if not is_inside_tree():
		return
	if got is Dictionary and not (got as Dictionary).is_empty():
		var m: Dictionary = got
		for k in meta.keys():
			if not m.has(k):
				m[k] = meta[k]
		meta = m
	_meta_ready = true


func _load() -> void:
	_gen += 1
	var gen := _gen
	_done = false
	_streams = []
	_render()
	_status_timer.start()
	var got: Variant = await Movies.streams(str(meta.get("type", "movie")), video_id, func(list: Array) -> void:
		if gen == _gen and is_inside_tree():
			_streams = list
			_render()
	)
	if gen != _gen or not is_inside_tree():
		return
	if got is Array:
		_streams = got
	_done = true
	_status_timer.stop()
	_render()


func _update_status() -> void:
	if not is_instance_valid(_status_box):
		return
	U.clear(_status_box)
	var st: Array = Movies.stream_sources_status()
	for s in st:
		var state := str(s.get("state", ""))
		var row := U.hbox(8)
		var dot := _Dot.new()
		dot.state = state
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var txt := str(s.get("name", ""))
		match state:
			"lädt": txt += " …"
			"fehler":
				var e := str(s.get("error", ""))
				txt += ": " + (e.left(42) + ("…" if e.length() > 42 else "") if e != "" else tr("keine Antwort"))
			_: txt += "  %d" % int(s.get("count", 0))
		# Name des Addons, seine Fehlermeldung, eine Zahl: nichts davon übersetzen (die Zeile wird beim Laden alle
		# 0,3 s neu gebaut).
		var sl := U.label(txt, "s", "warn" if state == "fehler" else ("muted" if state == "lädt" else "text"), "medium")
		sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(sl)
		_status_box.add_child(row)
	if st.is_empty() and _done:
		_status_box.add_child(U.label("Keine Quelle gefragt", "s", "faint", "medium"))


## Punkt für den Stand einer Quelle: Gold pulsiert beim Laden, Grün fertig, Rot Fehler.
class _Dot extends Control:
	var state := ""
	var _t := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(12, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		if state == "lädt":
			_t += dt
			queue_redraw()

	func _draw() -> void:
		var c := UzTheme.col("ok")
		var a := 1.0
		if state == "lädt":
			c = UzTheme.col("accent")
			a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 5.0))
		elif state == "fehler":
			c = UzTheme.col("danger")
		draw_circle(Vector2(6, 6), 5.0, Color(c, a), true, -1.0, true)


## Filter, Liste und Hinweise neu zeichnen; die Auswahl bleibt auf derselben Quelle.
func _render() -> void:
	if not is_instance_valid(_list):
		return
	_update_status()
	var f := Nav.focused()
	var keep := ""
	if f and _list.is_ancestor_of(f):
		keep = str(f.get_meta("uz_key", ""))
		_user_moved = true
	elif f and is_ancestor_of(f) and f != _refresh_btn:
		_user_moved = true
	_build_filters()
	var shown := Art.filter_streams(_streams, _addon, _quality, _lang)
	U.clear(_list)
	U.clear(_msg)
	_msg.visible = shown.is_empty()
	if shown.is_empty():
		_empty_msg()
	var pref := Art.preferred_index(shown, str(Config.get_value("movies.quality", "auto")))
	var target: Control = null
	for i in shown.size():
		var s: Dictionary = shown[i]
		var row := _StreamRow.new()
		row.stream = s
		row.want_lang = _want
		row.set_meta("uz_key", "quelle:" + str(s.get("id", i)))
		row.set_meta("uz_hint_a", "Abspielen")
		row.activated.connect(func() -> void: _choose(s))
		if i == 0:
			row.up_cb = _to_filters
		_list.add_child(row)
		if i == pref:
			row.set_meta("uz_entry", true)
			target = row
	if keep != "":
		for c in _list.get_children():
			if str(c.get_meta("uz_key", "")) == keep:
				Nav.focus(c, true)
				return
		if target:
			Nav.focus(target, true)
		return
	# Wie in Nuvio: solange man nichts angefasst hat, steht die Auswahl auf der ersten (bevorzugten) Quelle.
	if target and not _user_moved and Nav.top_layer() == self:
		Nav.focus(target, true)


func _build_filters() -> void:
	if not is_instance_valid(_strip):
		return
	var counts := Art.addon_counts(_streams)
	var sig := str(counts)
	if _strip.get_meta("uz_sig", "") == sig:
		# Nur die Auswahl wechselt: Reiter bleiben stehen (der gewählte darf nicht verschwinden).
		for c in _strip.get_children():
			if c.has_method("set_selected"):
				c.set_selected(str(c.get_meta("uz_key", "")) == "qfilter:" + _addon)
		return
	var had := Nav.focused() != null and _strip.is_ancestor_of(Nav.focused())
	var had_key := str(Nav.focused().get_meta("uz_key", "")) if had else ""
	_strip.set_meta("uz_sig", sig)
	U.clear(_strip)
	if _strip.has_method("snap"):
		_strip.call("snap")
	var all: Array = [["", "Alle", _streams.size()]]
	for c in counts:
		all.append([str(c[0]), str(c[0]), int(c[1])])
	if counts.size() < 2:
		all = all.slice(0, 1)
	for a in all:
		var it = NavItem.new()
		it.setup(str(a[1]), "", "chip", str(a[0]) == _addon, int(a[2]))
		it.set_meta("uz_key", "qfilter:" + str(a[0]))
		var aid := str(a[0])
		it.picked.connect(func() -> void:
			if _addon != aid:
				_addon = aid
				_render()
		)
		it.opened.connect(func() -> void:
			var first := _first_row()
			if first:
				Nav.focus(first)
		)
		_strip.add_child(it)
		it.set_meta("uz_hint_a", "Zur Liste")
	if had_key != "":
		await get_tree().process_frame
		for c in _strip.get_children():
			if str(c.get_meta("uz_key", "")) == had_key:
				Nav.focus(c, true)


## Von der ersten Quelle nach oben: auf den gewählten Filter (wie in Nuvio), nicht irgendwohin.
func _to_filters() -> bool:
	for c in _strip.get_children():
		if c.get_meta("uz_selected", false):
			Nav.focus(c)
			return true
	return false


func _first_row() -> Control:
	for c in _list.get_children():
		if c.has_meta("uz_entry"):
			return c
	return _list.get_child(0) as Control if _list.get_child_count() > 0 else null


func _empty_msg() -> void:
	if not _done:
		var l := U.label("Quellen werden gefragt …", "l", "muted", "medium")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_msg.add_child(l)
		return
	var h := U.label("Keine Quellen gefunden" if _streams.is_empty() else "Nichts in dieser Auswahl", "xl", "text", "bold")
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_child(h)
	var server := Quellen.owner_of(video_id) != ""
	var tip := "Andere Qualität, Sprache oder „Alle“ wählen." if not _streams.is_empty() else \
		"Keine Quellen gefunden." + \
		(" P2P-Quellen sind ausgeblendet (Einstellungen → Filme)." if bool(Config.get_value("movies.no_p2p", true)) else "")
	if server and _streams.is_empty():
		tip = Movies.error if Movies.error != "" else "Keine abspielbare Datei."
	var t := U.label(tip, "m", "muted", "regular", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.custom_minimum_size = Vector2(760, 0)
	_msg.add_child(t)
	if _streams.is_empty() and not server:
		var c := CenterContainer.new()
		var b := U.button("Addons verwalten", "grid")
		b.set_meta("uz_key", "quellen:addons")
		b.pressed.connect(func() -> void:
			close()
			main.goto("movies", "addons")
		)
		c.add_child(b)
		_msg.add_child(c)


func _pick_quality() -> void:
	var opts := [[0, "Jede Qualität"], [2160, "4K"], [1440, "1440p"], [1080, "1080p"], [720, "720p"], [480, "SD (unter 720p)"]]
	main.open_choice("Qualität", opts, _quality, func(v: Variant) -> void:
		_quality = int(v)
		_q_btn.text = "Jede Qualität" if _quality == 0 else ("SD" if _quality == 480 else Art.quality_label(_quality))
		_render()
	)


func _pick_lang() -> void:
	var opts := [["", "Jede Sprache"]]
	for c in Art.lang_counts(_streams, _want):
		opts.append([str(c[0]), Art.lang_name(str(c[0])), U.plural(int(c[1]), "Quelle", "Quellen")])
	if _lang != "" and not opts.any(func(o: Array) -> bool: return str(o[0]) == _lang):
		opts.append([_lang, Art.lang_name(_lang), U.plural(0, "Quelle", "Quellen")])
	main.open_choice("Sprache", opts, _lang, func(v: Variant) -> void:
		_lang = str(v)
		_l_btn.text = "Jede Sprache" if _lang == "" else Art.lang_name(_lang)
		_render()
	)


# --- Abspielen ----------------------------------------------------------------------------------

func _choose(s: Dictionary) -> void:
	var p: Dictionary = Movies.progress(str(meta.get("id", "")), video_id)
	var pos := float(p.get("position", 0.0))
	var dur := float(p.get("duration", 0.0))
	if mode == "ask" and Art.can_resume(pos, dur):
		main.open_dialog("Weiterschauen?", "Du warst bei %s von %s." % [Art.clock(pos), Art.clock(dur)], [
			["Fortsetzen ab " + Art.clock(pos), func() -> void: _start(s, true)],
			["Von vorn", func() -> void: _start(s, false)],
		], "history")
		return
	_start(s, mode == "resume" and Art.can_resume(pos, dur))


func _start(s: Dictionary, resume: bool) -> void:
	if not _meta_ready:
		Toasts.show_toast("Einen Moment", "Die Angaben werden noch geladen.", "clock", { "quiet": true })
		while not _meta_ready and is_inside_tree():
			await get_tree().process_frame
		if not is_inside_tree():
			return
	var title := str(meta.get("name", ""))
	var ep := _episode()
	if not ep.is_empty():
		title += " – " + Art.episode_code(int(ep.get("season", 0)), int(ep.get("episode", 0)))
		if str(ep.get("title", "")) != "":
			title += " „%s“" % str(ep.title)
	var err: Variant = await Movies.play(meta, video_id, s, { "resume": resume, "title": title })
	if not is_inside_tree():
		return
	if str(err) != "":
		Toasts.show_toast("Spielt nicht ab", str(err), "warning", { "sound": "error", "ms": 6000 })
		return
	main.open_movie_player()


## Eine Quelle in der Liste: Chips, ganzer Dateiname (sonst der Name), Beschreibung des Addons;
## rechts Addon, Name der Quelle und Untertitel. Mit Fokus klappt die Zeile auf: Dateiname ganz,
## Beschreibung Zeile für Zeile wie vom Addon geschickt. Ohne Fokus steht sie in zwei Zeilen.
class _StreamRow extends Control:
	signal activated
	const U2 := preload("res://src/ui/u.gd")
	const Art2 := preload("res://src/ui/components/movie_art.gd")
	const Q2 := preload("res://src/core/movies_quelle.gd")
	const W := 760.0                 ## Breite der Textspalte (Liste rechts, 1080p-Maß), passt sich an
	const RIGHT_W := 220.0           ## Spalte rechts: Addon, Name der Quelle, Untertitel
	var stream: Dictionary = {}
	var want_lang := ""
	var up_cb: Callable              ## erste Zeile: nach oben auf den Filter
	var _badges: Array = []          ## [PanelContainer, Ton]
	var _m: MarginContainer
	var _head: Label
	var _desc: Label
	var _long := ""
	var _open := false
	var _w := W

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_m = U2.margin(22, 16, 22, 16)
		_m.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_m)
		var row := U2.hbox(24)
		_m.add_child(row)
		var col := U2.vbox(8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var bl := Art2.stream_badges(stream, want_lang)
		if not bl.is_empty():
			var br := HFlowContainer.new()
			br.mouse_filter = Control.MOUSE_FILTER_IGNORE
			br.add_theme_constant_override("h_separation", 8)
			br.add_theme_constant_override("v_separation", 6)
			for b in bl:
				var p := PanelContainer.new()
				p.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var tone := str(b[1])
				p.add_child(U2.label(str(b[0]), "xs", _ink(tone), "ui_bold"))
				br.add_child(p)
				_badges.append([p, tone])
			col.add_child(br)
		var file := Art2.stream_file(stream)
		var name_ := Art2.stream_name(stream)
		# Dateiname immer ganz (umbrechend; fremder Text, darum ohne Übersetzung).
		_head = U2.label(Q2.breakable(file if file != "" else name_), "m", "text", "ui_bold", true)
		_head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		col.add_child(_head)
		_long = Art2.stream_desc(stream)
		if _long != "":
			_desc = U2.label("", "s", "muted", "regular", true)
			_desc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			col.add_child(_desc)
		var right := U2.vbox(4)
		right.custom_minimum_size = Vector2(RIGHT_W, 0)
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		var addon := str(stream.get("addon_name", ""))
		var an := U2.label(addon, "s", "text", "medium", true)
		an.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		an.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(an)
		if file != "" and name_ != addon and name_ != "":
			var nl := Art2.fit_lines(U2.label(name_, "xs", "muted", "medium", true), RIGHT_W, 3)
			nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(nl)
		col.resized.connect(func() -> void:
			if col.size.x > 100.0 and absf(col.size.x - _w) > 4.0:
				_w = col.size.x
				_set_open(_open)
		)
		var subs: Array = stream.get("subtitles", []) if stream.get("subtitles") is Array else []
		if not subs.is_empty():
			var sl := U2.label(U2.plural(subs.size(), "Untertitel", "Untertitel"), "xs", "faint", "medium")
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(sl)
		row.add_child(right)
		_set_open(false)
		focus_entered.connect(func() -> void:
			U2.etikett(self, true)
			_set_open(true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			U2.etikett(self, false)
			_set_open(false)
			queue_redraw()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)
		_m.minimum_size_changed.connect(_fit)
		_fit.call_deferred()

	## Zu: Beschreibung in zwei Zeilen mit „·“ statt Umbruch. Auf: Zeile für Zeile, ganz.
	func _set_open(on: bool) -> void:
		_open = on
		if _desc:
			_desc.text = _long if on else _long.replace("\n", Art2.SEP)
			Art2.fit_lines(_desc, _w, Q2.LINES_MAX if on else 2)
			_desc.custom_minimum_size.x = 0.0
		_style_badges(on)

	func _fit() -> void:
		custom_minimum_size.y = _m.get_combined_minimum_size().y

	## Chips: ruhig getönt; auf der hellen Auswahl leicht dunkel, damit die Schrift lesbar bleibt.
	## Sprachen mit Rand, die gewünschte in der Akzentfarbe.
	static func _ink(tone: String) -> String:
		if tone in ["gold", "lang_on"]:
			return "accent"
		if tone in ["ok", "warn"]:
			return tone
		return "text" if tone in ["text", "lang"] else "muted"

	func _style_badges(on: bool) -> void:
		for b in _badges:
			var p: PanelContainer = b[0]
			var tone := str(b[1])
			var bg := Color(0, 0, 0, 0.08) if on else (Color(UzTheme.col("accent"), 0.16) if tone in ["gold", "lang_on"]
					else (Color(UzTheme.col("ok"), 0.14) if tone == "ok" else UzTheme.col("glass_hi")))
			var sb := UzTheme.box(bg, 8)
			if tone in ["lang", "lang_on"]:
				sb.bg_color = Color(bg, bg.a * 0.5)
				sb.border_color = Color(0, 0, 0, 0.22) if on else Color(UzTheme.col(_ink(tone)), 0.55)
				sb.set_border_width_all(2)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 2
			sb.content_margin_bottom = 3
			p.add_theme_stylebox_override("panel", sb)

	func activate() -> void:
		activated.emit()

	func nav_ud(d: int) -> bool:
		return d < 0 and up_cb.is_valid() and bool(up_cb.call())

	func _draw() -> void:
		var f: float = get_meta("uz_f", 1.0 if has_focus() else 0.0)
		if f < 0.99:
			draw_style_box(UzTheme.box(UzTheme.col("text", 0.045), UzTheme.r_panel() - 10), Rect2(Vector2.ZERO, size))
		U2.draw_focus(self, UzTheme.r_panel() - 10)
