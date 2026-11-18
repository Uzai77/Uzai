extends RefCounted
## Profil → Backlog (Roadmap 2): dein eigener Backlog wie bei Backloggd, nur lokal. Oben „Was
## spiele ich heute?“ – ein Vorschlag aus dem eigenen Backlog mit dem Grund dazu (Würfeln holt
## einen anderen), darunter das Jahresziel, die Spiele nach Status, deine Listen und das Tagebuch.
## Die Regeln stehen in src/library/backlog.gd, das Setzen in src/ui/backlog_flow.gd.

const U := preload("res://src/ui/u.gd")
const Backlog := preload("res://src/library/backlog.gd")
const BacklogFlow := preload("res://src/ui/backlog_flow.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const ListItem := preload("res://src/ui/components/list_item.gd")
const ProgressBarUz := preload("res://src/ui/components/progress_bar.gd")
const StarRow := preload("res://src/ui/components/star_row.gd")
const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const Main := preload("res://src/main.gd")

const SHELF_STATUSES := ["spiele", "will", "pausiert"]
const DIARY_SHOWN := 8

var view: Control
var gutter := 96
var _games: Array = []
var _today_slot: Control
## Würfeln: schon gezeigte Vorschläge (kommen erst wieder, wenn alle dran waren).
static var _rolled: Array = []
static var _roll := 0


func build(v: Control, col: VBoxContainer) -> void:
	view = v
	# Gekaufte, nie installierte Epic-Spiele gehören nicht in den Backlog-Vorschlag.
	_games = Library.visible_games().filter(func(g): return not Library.owned_only(g))
	_today_slot = U.vbox(0)
	col.add_child(_today_slot)
	_fill_today()
	col.add_child(_goal())
	var any := false
	for s in SHELF_STATUSES:
		any = _status_shelf(col, s) or any
	var year := Backlog.year_of(int(Time.get_unix_time_from_system()), _bias())
	var done := Backlog.done_in(_games, year, _bias())
	if not done.is_empty():
		any = true
		col.add_child(view.section_title("Durchgespielt %d" % year, U.plural(done.size(), "Spiel", "Spiele")))
		var shelf = Shelf.new().setup("bl:done", 30, true, 18, gutter)
		col.add_child(shelf)
		for g in done.slice(0, 30):
			shelf.add(_cover_item(g, Backlog.status_name(Backlog.status_of(g))))
	_lists(col)
	_diary(col)
	if not any and Library.lists.is_empty():
		col.add_child(_hint())


static func _bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


# --- Was spiele ich heute? --------------------------------------------------------------------

## Vorschlag des Tages: gleich, solange sich nichts ändert und nicht gewürfelt wird.
func _fill_today() -> void:
	U.clear(_today_slot)
	var now := int(Time.get_unix_time_from_system())
	# Erst nur die Spiele mit Status: Gibt es dort einen Kandidaten, kommt der Vorschlag ohnehin nur aus
	# ihnen (Backlog.candidates), und Spielzeit und „zuletzt“ braucht Uzai dann nicht für die ganze
	# Bibliothek auszurechnen (dieselbe Rechnung kostete auf der Startseite bei 3000 Spielen 32 ms).
	var mit: Array = _games.filter(func(g: Dictionary) -> bool: return Backlog.status_of(g) != "")
	var cands := Backlog.candidates(mit, _info(mit), now)
	if cands.is_empty():
		cands = Backlog.candidates(_games, _info(_games), now)
	var day := floori(float(now + _bias()) / 86400.0)
	var pick := Backlog.pick_today(cands, day * 31 + _roll, _rolled)
	if pick.is_empty():
		_today_slot.add_child(_today_empty())
		return
	var gid := str((pick.game as Dictionary).get("id", ""))
	if not _rolled.has(gid):
		_rolled.append(gid)
	if _rolled.size() >= cands.size():
		_rolled = [gid]
	_today_slot.add_child(_today_card(pick, cands.size() > 1))


static func _info(list: Array) -> Dictionary:
	var info := {}
	for g in list:
		info[str(g.get("id", ""))] = { "playtime": Library.playtime(g), "last": Library.last_played(g), "installed": Library.is_installed(g) }
	return info


func _today_card(pick: Dictionary, can_roll: bool) -> Control:
	var g: Dictionary = pick.game
	var card := Control.new()
	card.custom_minimum_size = Vector2(0, 380)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_panel()))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(clip)
	card.add_child(clip)
	# Das große Bild des Spiels leise dahinter, nach links in die Fläche auslaufend.
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(art)
	art.modulate.a = 0.0
	clip.add_child(art)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	var bg := UzTheme.col("surface_hi")
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(bg, 0.97), Color(bg, 0.82), Color(bg, 0.5)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(shade)
	clip.add_child(shade)
	var wart: WeakRef = weakref(art)
	Media.game_texture(g, "hero", func(t: Texture2D) -> void:
		var a: TextureRect = wart.get_ref()
		if a and t:
			a.texture = t
			a.create_tween().tween_property(a, "modulate:a", 1.0, 0.5)
	)
	var m := U.margin(48, 40, 56, 40)
	U.full_rect(m)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var row := U.hbox(48)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	row.add_child(PlaytimePage.cover_clip(g, Vector2(225, 300), UzTheme.r_cover()))
	var text := U.vbox(6)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(U.label("Was spiele ich heute?", "m", "accent", "bold"))
	var name_l := U.ellipsis(U.label(Library.display_title(g), "xxl", "text", "black"))
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels: nie übersetzen
	text.add_child(name_l)
	var why := U.label(str(pick.why), "l", "muted", "regular", true)
	text.add_child(why)
	var facts := U.hbox(14)
	var s := Backlog.status_of(g)
	if s != "":
		facts.add_child(U.icon(Backlog.status_icon(s), 22, "muted"))
		facts.add_child(U.label(Backlog.status_name(s), "m", "text", "medium"))
	if Library.playtime(g) > 0:
		facts.add_child(U.label(("·  " if s != "" else "") + PlaytimePage.dur(Library.playtime(g)), "m", "muted", "medium"))
	if Backlog.stars_of(g) > 0:
		facts.add_child(StarRow.new().setup(Backlog.stars_of(g), 22))
	text.add_child(facts)
	text.add_child(U.spacer(0, 18, false))
	var brow := U.hbox(14)
	var inst := Library.is_installed(g)
	var play := U.button("Spielen" if inst else "Zum Spiel", "play" if inst else "games", "primary")
	play.set_meta("uz_default", true)
	play.set_meta("uz_key", "bl:today:play")
	var gd := g
	play.pressed.connect(func() -> void:
		if inst:
			view.main.launch(gd)
		else:
			view.main.open_game(gd)
	)
	brow.add_child(play)
	if can_roll:
		var roll := U.button("Würfeln", "shuffle", "normal")
		roll.set_meta("uz_key", "bl:today:roll")
		roll.set_meta("uz_hint_a", "Anderer Vorschlag")
		roll.pressed.connect(_reroll)
		brow.add_child(roll)
	if inst:
		var page := U.button("Zum Spiel", "", "flat")
		page.set_meta("uz_key", "bl:today:page")
		page.pressed.connect(func() -> void: view.main.open_game(gd))
		brow.add_child(page)
	text.add_child(brow)
	var wrap := U.margin(gutter, 0, gutter, 0)
	wrap.add_child(card)
	return wrap


## Würfeln: ein anderer Vorschlag, weich überblendet; die Auswahl bleibt auf „Würfeln“.
func _reroll() -> void:
	_roll += 1
	Sfx.play("select")
	var old := _today_slot.get_child(0) if _today_slot.get_child_count() > 0 else null
	if old:
		var tw := U.tw(old, "uz_roll")
		tw.tween_property(old, "modulate:a", 0.0, U.T_FAST)
		await tw.finished
	if not is_instance_valid(_today_slot):
		return
	_fill_today()
	var c := _today_slot.get_child(0) if _today_slot.get_child_count() > 0 else null
	if c:
		c.modulate.a = 0.0
		U.tw(c, "uz_roll").tween_property(c, "modulate:a", 1.0, U.T_ENTER)
		var hit := _find(c, "bl:today:roll")
		if hit:
			Nav.focus(hit, true)


func _today_empty() -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_panel())
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 40
	sb.content_margin_bottom = 40
	p.add_theme_stylebox_override("panel", sb)
	var v := U.vbox(10)
	p.add_child(v)
	v.add_child(U.label("Was spiele ich heute?", "m", "accent", "bold"))
	v.add_child(U.label("Noch kein Vorschlag", "xl", "text", "black"))
	v.add_child(
			U.label("Gib Spielen auf ihrer Seite einen Status.", "m",
			"muted", "regular", true))
	v.add_child(U.spacer(0, 10, false))
	var b := U.button("Zu den Spielen", "games", "primary")
	b.set_meta("uz_default", true)
	b.set_meta("uz_key", "bl:today:games")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func() -> void: view.main.goto("games"))
	v.add_child(b)
	var wrap := U.margin(gutter, 0, gutter, 0)
	wrap.add_child(p)
	return wrap


# --- Jahresziel -------------------------------------------------------------------------------

func _goal() -> Control:
	var now := int(Time.get_unix_time_from_system())
	var year := Backlog.year_of(now, _bias())
	var target := int(Library.goals.get(str(year), 0))
	var st := Backlog.goal_state(_games, year, target, now, _bias())
	var box := U.vbox(16)
	box.add_child(view.section_title("Jahresziel %d" % year, "durchgespielt und 100 %"))
	var m := U.margin(gutter, 0, gutter, 0)
	var v := U.vbox(14)
	m.add_child(v)
	var row := U.hbox(24)
	var big := U.label("%d von %d" % [int(st.done), target] if target > 0 else U.plural(int(st.done), "Spiel", "Spiele"), "xl", "text", "black")
	big.clip_text = false
	row.add_child(big)
	var line := U.label(Backlog.goal_text(st) if target > 0 else "Ohne Ziel gezählt. Wie viele sollen es dieses Jahr werden?", "m", "muted", "regular")
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	var b := U.button("Ziel ändern" if target > 0 else "Ziel setzen", "edit", "normal")
	b.set_meta("uz_key", "bl:goal")
	b.pressed.connect(func() -> void: BacklogFlow.pick_goal(view.main, year))
	row.add_child(b)
	v.add_child(row)
	if target > 0:
		var bar = ProgressBarUz.new().setup(0.0, "gold" if int(st.done) >= target else "accent", 10)
		v.add_child(bar)
		bar.create_tween().tween_method(Callable(bar, "set_value"), 0.0, float(st.frac), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.2)
	box.add_child(m)
	return box


# --- Nach Status -------------------------------------------------------------------------------

func _status_shelf(col: VBoxContainer, s: String) -> bool:
	var list: Array = _games.filter(func(g): return Backlog.status_of(g) == s)
	if list.is_empty():
		return false
	# Zuletzt geändert bzw. gespielt zuerst.
	list.sort_custom(func(a, b): return maxi(int(a.get("status_at", 0)), Library.last_played(a)) > maxi(int(b.get("status_at", 0)), Library.last_played(b)))
	col.add_child(view.section_title(Backlog.status_name(s), U.plural(list.size(), "Spiel", "Spiele")))
	var shelf = Shelf.new().setup("bl:" + s, 30, true, 18, gutter)
	col.add_child(shelf)
	for g in list.slice(0, 30):
		var sub := PlaytimePage.dur(Library.playtime(g)) if Library.playtime(g) > 0 else "Noch nie gespielt"
		shelf.add(_cover_item(g, sub))
	return true


func _cover_item(g: Dictionary, sub: String) -> Control:
	var v := U.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card = CoverCard.new().setup(g)
	var gd := g
	card.chosen.connect(func(_x: Dictionary) -> void: view.main.open_game(gd))
	v.add_child(card)
	v.add_child(U.spacer(0, 14, false))
	var h := Backlog.stars_of(g)
	if h > 0:
		v.add_child(StarRow.new().setup(h, 20))
	var sl := U.ellipsis(U.label(sub, "s", "muted"))
	sl.custom_minimum_size = Vector2(UzTheme.cover_size().x, 0)
	v.add_child(sl)
	return v


# --- Listen -----------------------------------------------------------------------------------

func _lists(col: VBoxContainer) -> void:
	col.add_child(view.section_title("Deine Listen", U.plural(Library.lists.size(), "Liste", "Listen") if not Library.lists.is_empty() else ""))
	var m := U.margin(gutter, 0, gutter, 0)
	var v := U.vbox(8)
	m.add_child(v)
	for l in Library.lists:
		var games := Library.list_games(str(l.id))
		var names := PackedStringArray()
		for g in games.slice(0, 3):
			names.append(Library.display_title(g))
		var it = ListItem.new().setup(str(l.name), U.plural(games.size(), "Spiel", "Spiele") + (("  ·  " + ", ".join(names)) if not names.is_empty() else ""), "")
		it.icon_name = "list"
		# Eigene Namen: nie übersetzen (der Untertitel ist schon in der richtigen Sprache).
		it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		it.set_meta("uz_key", "bl:list:" + str(l.id))
		it.set_meta("uz_hint_a", "Öffnen")
		var lid := str(l.id)
		it.activated.connect(func() -> void: open_list(view.main, lid))
		v.add_child(it)
	var add := U.button("Neue Liste", "plus", "normal")
	add.set_meta("uz_key", "bl:list:new")
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func() -> void:
		view.main.open_keyboard("Neue Liste", "", func(t: String) -> void:
			var l := Library.new_list(t)
			if not l.is_empty():
				open_list(view.main, str(l.id))
		)
	)
	v.add_child(add)
	col.add_child(m)


## Eine Liste: Spiele in ihrer Reihenfolge. A öffnet die Auswahl (Spielseite, nach oben, nach
## unten, herausnehmen), X schiebt nach oben. Dazu Spiel hinzufügen, umbenennen, löschen.
static func open_list(main: Main, lid: String) -> void:
	var s = preload("res://src/ui/layers/sheet.gd").new()
	var l := Library.list_by_id(lid)
	if l.is_empty():
		return
	s.setup(str(l.name), "Deine Liste", 820)
	s.heading_raw = true
	s.fill_func = func(sheet) -> void:
		var list := Library.list_by_id(lid)
		if list.is_empty():
			sheet.close()
			return
		var games := Library.list_games(lid)
		var add = SettingRow.new()
		add.setup("action", "Spiel hinzufügen")
		add.icon_name = "plus"
		add.set_meta("uz_key", "list:add")
		add.on_activate = func() -> void: _add_to_list(main, lid, sheet)
		sheet.add_row(add)
		if games.is_empty():
			sheet.add_gap()
			sheet.add_label("Noch leer. Spiele kommen auch über die Spielseite (Dein Backlog → In Liste) hinein.", "s", "faint")
		else:
			sheet.add_gap()
			sheet.add_label(U.plural(games.size(), "Spiel", "Spiele"))
		for i in games.size():
			var g: Dictionary = games[i]
			var gid := str(g.get("id", ""))
			var r = SettingRow.new()
			r.setup("action", "%d.  %s" % [i + 1, Library.display_title(g)])
			r.icon_name = Backlog.status_icon(Backlog.status_of(g)) if Backlog.status_of(g) != "" else "games"
			r.value_text = Backlog.summary(g)
			r.set_meta("uz_key", "list:g:" + gid)
			r.set_meta("uz_hint_x", "Nach oben")
			r.set_meta("uz_on_x", func() -> void:
				if Library.list_move(lid, gid, -1):
					sheet.refill())
			r.on_activate = func() -> void: _game_menu(main, lid, g, sheet)
			sheet.add_row(r)
		sheet.add_gap()
		var ren = SettingRow.new()
		ren.setup("action", "Umbenennen")
		ren.icon_name = "edit"
		ren.on_activate = func() -> void:
			main.open_keyboard("Name der Liste", str(Library.list_by_id(lid).get("name", "")), func(t: String) -> void:
				Library.rename_list(lid, t)
				# Die Überschrift steht fest im Kopf: neu öffnen, damit der neue Name oben steht.
				if is_instance_valid(sheet):
					sheet.close()
				open_list(main, lid)
			)
		sheet.add_row(ren)
		var del = SettingRow.new()
		del.setup("action", "Liste löschen")
		del.icon_name = "trash"
		del.on_activate = func() -> void:
			var name_ := str(Library.list_by_id(lid).get("name", ""))
			var gone := Library.delete_list(lid)
			sheet.close()
			if not gone.is_empty():
				Undo.offer_calls("Liste gelöscht", "„%s“ – die Spiele bleiben" % name_, "trash", [Library.put_list.bind(gone[0], gone[1])])
		sheet.add_row(del)
	main.open_layer(s)


static func _game_menu(main: Main, lid: String, g: Dictionary, sheet) -> void:
	var gid := str(g.get("id", ""))
	main.open_choice(Library.display_title(g), [["page", "Zur Spielseite"], ["up", "Nach oben"], ["down", "Nach unten"], ["out", "Aus der Liste nehmen"]], null,
			func(v: Variant) -> void:
		match str(v):
			"page":
				main.open_game(g)
			"up", "down":
				Library.list_move(lid, gid, -1 if str(v) == "up" else 1)
			"out":
				var before: Array = (Library.list_by_id(lid).get("games", []) as Array).duplicate()
				if Library.list_toggle(lid, gid, false):
					Undo.offer_calls("Aus der Liste genommen", Library.display_title(g), "list", [Library.set_list_games.bind(lid, before)])
		if is_instance_valid(sheet):
			sheet.refill()
	)


## Spiel hinzufügen: zuerst die aus dem Backlog und die zuletzt gespielten, „Suchen …“ für alle.
static func _add_to_list(main: Main, lid: String, sheet) -> void:
	var have: Array = Library.list_by_id(lid).get("games", [])
	var pool: Array = Library.visible_games().filter(func(g): return not have.has(str(g.get("id", ""))))
	var first: Array = pool.filter(func(g): return Backlog.status_of(g) != "")
	for g in Library.recent(20):
		if not first.has(g) and not have.has(str(g.get("id", ""))):
			first.append(g)
	var opts: Array = [["?", "Suchen …"]]
	for g in first.slice(0, 40):
		opts.append([str(g.id), Library.display_title(g), Backlog.status_name(Backlog.status_of(g))])
	var put := func(gid: String) -> void:
		if Library.list_toggle(lid, gid, true) and is_instance_valid(sheet):
			sheet.refill()
	main.open_choice("Spiel hinzufügen", opts, null, func(v: Variant) -> void:
		if str(v) != "?":
			put.call(str(v))
			return
		main.open_keyboard("Spiel suchen", "", func(t: String) -> void:
			var q := t.strip_edges().to_lower()
			if q == "":
				return
			var hits: Array = pool.filter(func(g): return Library.display_title(g).to_lower().contains(q)).slice(0, 40)
			if hits.is_empty():
				Toasts.show_toast("Nichts gefunden", "„%s“" % t.strip_edges(), "search", { "ms": 2400, "quiet": true })
				return
			main.open_choice("Treffer", hits.map(func(g): return [str(g.id), Library.display_title(g)]), null, func(w: Variant) -> void: put.call(str(w)))
		)
	)


# --- Tagebuch ---------------------------------------------------------------------------------

func _diary(col: VBoxContainer) -> void:
	var all: Array = []
	for g in _games:
		for e in Backlog.diary_of(g):
			all.append({ "game": g, "e": e })
	if all.is_empty():
		return
	all.sort_custom(func(a, b): return int(a.e.at) > int(b.e.at))
	col.add_child(view.section_title("Tagebuch", "zuletzt"))
	var m := U.margin(gutter, 0, gutter, 0)
	var v := U.vbox(8)
	m.add_child(v)
	for x in all.slice(0, DIARY_SHOWN):
		var g: Dictionary = x.game
		var e: Dictionary = x.e
		var head := BacklogFlow.entry_head(int(e.at), int(e.get("secs", 0)))
		var note := str(e.get("note", ""))
		# Eigene Notiz: nicht übersetzen – den Kopf (Datum, Dauer) schon vorher.
		var it = ListItem.new().setup(Library.display_title(g), TranslationServer.translate(head) + (("  ·  " + note) if note != "" else ""), "")
		it.icon_name = "history"
		it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		it.set_meta("uz_key", "bl:diary:%s:%d" % [str(g.get("id", "")), int(e.at)])
		it.set_meta("uz_hint_a", "Tagebuch")
		var gd := g
		it.activated.connect(func() -> void: BacklogFlow.open_diary(view.main, gd))
		v.add_child(it)
	col.add_child(m)


func _hint() -> Control:
	var m := U.margin(gutter, 0, gutter, 0)
	m.add_child(U.label("Status, Sterne und Tagebuch: auf der Spielseite unter „Dein Backlog“, mehrere auf einmal im Raster „Alle Spiele“ (Y). Alles bleibt auf diesem PC.", "s", "faint", "medium", true))
	return m


static func _find(n: Node, key: String) -> Control:
	for c in n.get_children():
		if c is Control and str(c.get_meta("uz_key", "")) == key:
			return c
		var r := _find(c, key)
		if r:
			return r
	return null
