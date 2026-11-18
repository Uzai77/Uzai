extends "res://src/ui/layers/layer.gd"
## Suche über alles (Punkt 105): rechten Stick drücken (R3), F oder die Lupe oben rechts – von
## überall in Uzai. Unten steht die Tastatur, darüber laufen beim Tippen die besten Treffer mit.
## Start („Fertig“) zeigt alle Treffer nach Gruppen: zuerst die eigenen Spiele, dann Einstellungen
## (A springt zur Zeile) und Freunde – das alles sofort und nur auf diesem PC, tolerant gegenüber
## Tippfehlern, Umlauten und Teilwörtern (src/core/search.gd). Erst wenn man kurz nicht tippt,
## fragen Shop, Musik, Streams und Filme ihre eigene Suche; Y (oder Einstellungen → System)
## schaltet das ab, dann geht nichts ins Netz. YouTube sucht nur auf Wunsch (yt-dlp braucht lange
## und merkt sich die Suche). Ändert sich das Suchwort, zählen ältere Antworten nicht mehr.
## A öffnet die Seite, zu der ein Treffer gehört; X ändert das Suchwort, B schließt.

const Search := preload("res://src/core/search.gd")
const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")
const ChatView := preload("res://src/ui/layers/chat_view.gd")
const People := preload("res://src/ui/components/guide_people.gd")
const MusicBits := preload("res://src/ui/components/music_bits.gd")

const COL_W := 1164.0         ## so breit wie die Tastatur darunter
const PAUSE_S := 0.7          ## so lange nicht tippen, dann fragt die Suche auch im Netz
const NET_MIN := 3            ## kürzere Suchwörter gehen nie ins Netz
const LIVE_ROWS := 4
const KEEP_QUERIES := 8       ## so viele Antworten aus dem Netz bleiben gemerkt (zurück tippen)
const NET_NAMES := { "shop": "Shop", "music": "Musik", "streams": "Streams", "movies": "Filme" }
const ALL_TEXT := { "shop": "Alle Treffer im Shop", "music": "Alle Treffer in Musik", "streams": "Alle Treffer in Streams",
	"movies": "Alle Treffer in Filmen und Serien" }

const Main := preload("res://src/main.gd")
var main: Main
var query := ""
var _online := true
var _sources: Array = []      ## Quellen im Netz, die hier eingerichtet sind (Reihenfolge der Gruppen)
var _games_idx: Array = []
var _friends_idx: Array = []
var _settings_idx: Array = []
var _settings_ready := false
var _net := {}                ## Suchwort → { Quelle → Antwort } (fehlt = läuft noch)
var _net_order: Array = []
var _pause: Timer
var _kb: Control
var _kb_done := false
var _kb_from_full := ""       ## Suchwort der Trefferliste, aus der X die Tastatur öffnete
var _full := false
var _live: VBoxContainer
var _live_head: Label
var _live_rows: VBoxContainer
var _live_net: Label
var _live_keys := {}
var _live_due := false
var _sc: ScrollContainer
var _body: VBoxContainer
var _title: Label
var _sub: Label
var _net_btn: Button
var _groups := {}             ## Quelle → Platz ihrer Gruppe in der Trefferliste


func build() -> void:
	dim = 0.84
	_scrim.color = Color(UzTheme.col("bg"), dim)
	LibraryGrid.hide_shell(main, self)
	set_meta("uz_hint_b", "Schließen")
	_online = bool(Config.get_value("system.search_online", true))
	_sources = _net_sources()
	_pause = Timer.new()
	_pause.one_shot = true
	_pause.wait_time = PAUSE_S
	_pause.timeout.connect(_on_pause)
	add_child(_pause)
	var side := maxf(UzTheme.GUTTER, (get_viewport_rect().size.x - COL_W) * 0.5)
	# Beim Tippen: die besten Treffer oben, die Tastatur (eigene Ebene) steht darunter.
	_live = U.vbox(10)
	_live.anchor_right = 1.0
	_live.offset_left = side
	_live.offset_right = -side
	_live.offset_top = 64
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_live)
	var lh := U.hbox(14)
	_live_head = U.label("", "xs", "accent", "medium")       # „Suche“ steht schon über dem Eingabefeld
	_live_head.clip_text = false
	lh.add_child(_live_head)
	lh.add_child(U.spacer())
	_live_net = U.label("", "s", "faint", "medium")
	_live_net.clip_text = false
	lh.add_child(_live_net)
	_live.add_child(lh)
	_live_rows = U.vbox(4)
	_live.add_child(_live_rows)
	# Nach „Fertig“: alle Treffer nach Gruppen, zum Blättern.
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.follow_focus = false
	_sc.set_meta("uz_pad_v", 170.0)
	U.full_rect(_sc)
	_sc.visible = false
	add_child(_sc)
	var pad := U.margin(int(side), 64, int(side), 170)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(pad)
	var col := U.vbox(0)
	pad.add_child(col)
	var head := U.vbox(6)
	var k2 := U.label("Suche", "xs", "accent", "medium")
	k2.clip_text = false
	head.add_child(k2)
	_title = U.ellipsis(U.label("", "xxl", "text", "black"))
	head.add_child(_title)
	_sub = U.label("", "m", "muted", "medium", true)
	head.add_child(_sub)
	head.add_child(U.spacer(0, 10, false))
	var row := U.hbox(12)
	row.set_meta("uz_group", "gsuche:kopf")
	var again := U.button("Suchwort ändern", "keyboard", "flat")
	again.set_meta("uz_key", "gs:ask")
	again.set_meta("uz_hint_a", "Ändern")
	# Auf dem Knopf selbst steht derselbe Hinweis nicht noch einmal für X bzw. Y (hint_bar.gd „—“).
	again.set_meta("uz_hint_x", "—")
	again.pressed.connect(_ask)
	row.add_child(again)
	_net_btn = U.button("", "link", "flat")
	_net_btn.set_meta("uz_key", "gs:net")
	_net_btn.set_meta("uz_hint_a", "Umschalten")
	_net_btn.set_meta("uz_hint_y", "—")
	_net_btn.pressed.connect(_toggle_online)
	row.add_child(_net_btn)
	head.add_child(row)
	col.add_child(head)
	_body = U.vbox(0)
	col.add_child(_body)
	_games_idx = Search.prepare(Library.visible_games(), func(g: Dictionary) -> String: return Library.display_title(g),
		func(g: Dictionary) -> float: return float(Library.last_played(g)))
	_friends_idx = Search.prepare(_friends(), func(f: Dictionary) -> String: return str(f.get("name", "")),
		func(f: Dictionary) -> float: return 0.0 if str(f.get("state", "")) in ["", "offline"] else 1.0)
	_update_hints()
	_show_live()
	_ask_soon()
	# Die Einstellungen schon einlesen, solange man den ersten Buchstaben sucht (über ein paar Bilder
	# verteilt); tippt man schneller, beginnt es beim ersten Buchstaben.
	var pre := Timer.new()
	pre.one_shot = true
	pre.wait_time = 0.5
	pre.timeout.connect(func() -> void: _settings())
	add_child(pre)
	pre.start()


## Die Tastatur erst öffnen, wenn diese Ebene steht (sonst läge sie im Stapel darunter).
func _ask_soon() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and not _closing:
		_ask()


func _ask() -> void:
	if is_instance_valid(_kb):
		return
	_kb_from_full = query if _full else ""
	_kb_done = false
	_set_full(false)
	var kb = main._rare("keyboard").new()
	kb.heading = "Suche"
	kb.text = query
	kb.see_through = true
	kb.edited.connect(_on_edit)
	kb.done.connect(func(t: String) -> void:
		_kb_done = true
		_on_done(t)
	)
	kb.closed.connect(_on_kb_closed)
	_kb = kb
	main.open_layer(kb)


## B auf der Tastatur: aus der Trefferliste heraus geöffnet zurück zu ihr, sonst Suche zu.
func _on_kb_closed() -> void:
	_kb = null
	if _kb_done or _closing:
		return
	if _kb_from_full != "":
		_on_edit(_kb_from_full)
		_on_done(_kb_from_full)
	else:
		close()


func _on_edit(t: String) -> void:
	query = t
	# Mehrere Änderungen in einem Bild (Einfügen, schnelles Tippen): einmal neu suchen.
	if not _live_due:
		_live_due = true
		_show_live.call_deferred()
	_pause.stop()
	var q := _q()
	if _online and q.length() >= NET_MIN and not _sources.is_empty() and not _net.has(q):
		_pause.start()


## Kurz nicht getippt: jetzt auch im Netz fragen.
func _on_pause() -> void:
	_fetch_net(_q())


func _on_done(t: String) -> void:
	query = t
	if _q() == "":
		close()
		return
	_pause.stop()
	if _online and _q().length() >= NET_MIN:
		_fetch_net(_q())
	_show_full()


func _q() -> String:
	return query.strip_edges()


func handle(cmd: String) -> bool:
	if not _full:
		return false
	match cmd:
		"x":
			_ask()
			return true
		"y":
			Sfx.play("select")
			_toggle_online()
			return true
	return false


func _update_hints() -> void:
	set_meta("uz_hints", [["x", "Ändern"], ["y", "Netzsuche aus" if _online else "Netzsuche an"]])
	if is_instance_valid(_net_btn):
		_net_btn.text = "Im Netz: an" if _online else "Im Netz: aus"
		_net_btn.icon = Icons.tex("link" if _online else "lock", 26)


func _toggle_online() -> void:
	_online = not _online
	Config.set_value("system.search_online", _online)
	_update_hints()
	if _online and _q().length() >= NET_MIN:
		_fetch_net(_q())
	Nav.focus_moved.emit(Nav.focused())
	if _full:
		_fill_full(true)


# --- Daten ---------------------------------------------------------------------------------------

func _friends() -> Array:
	var out: Array = []
	for f in Social.steam_friends:
		var d: Dictionary = (f as Dictionary).duplicate()
		d["_kind"] = "steam"
		out.append(d)
	for f in DiscordChat.friends:
		var d2: Dictionary = (f as Dictionary).duplicate()
		d2["_kind"] = "discord"
		out.append(d2)
	return out


## Einstellungen erst beim ersten Suchwort einlesen (die Seiten werden dafür gebaut, nicht gezeigt). Der Index
## entsteht gestreckt und kommt darum ein paar Bilder später (_settings_holen); bis dahin leer.
func _settings() -> Array:
	if not _settings_ready:
		_settings_ready = true
		_settings_holen()
	return _settings_idx


## Den Index der Einstellungen holen (settings_suche.gd: eine Kategorie je Bild, danach gemerkt – vorher baute
## jede geöffnete Suche alle Seiten in einem Bild, gemessen 0,12 bis 0,4 s Stillstand beim Tippen). Was bis dahin
## getippt ist, sucht dann auch dort; gefunden wird im Titel und in den Suchwörtern einer Zeile.
func _settings_holen() -> void:
	var sv: Variant = main.sections.get("settings")
	if not (sv is Object and (sv as Object).has_method("suche_index_gestreckt")):
		return
	var idx: Array = await (sv as Object).call("suche_index_gestreckt")
	if not is_inside_tree() or _closing or idx.is_empty():
		return
	_settings_idx = idx
	if _q() == "":
		return
	if _full:
		_fill_full(true)
	elif not _live_due:
		_live_due = true
		_show_live.call_deferred()


## Was im Netz gefragt werden darf: nur Bereiche, die da und eingerichtet sind.
func _net_sources() -> Array:
	var out: Array = []
	var secs: Dictionary = main.sections if main else {}
	if secs.has("shop"):
		out.append("shop")
	if secs.has("music") and (Music.demo() or Music.has_spotify()):
		out.append("music")
	if secs.has("streams"):
		out.append("streams")
	if secs.has("movies") and Movies.enabled():
		out.append("movies")
	return out


func _fetch_net(q: String) -> void:
	if not _online or q.length() < NET_MIN or _net.has(q):
		return
	_net[q] = {}
	_net_order.append(q)
	while _net_order.size() > KEEP_QUERIES:
		_net.erase(_net_order.pop_front())
	for kind in _sources:
		_fetch(kind, q, _got)
	_refresh_net()


## Eine Quelle über ihre eigene Suche fragen. Statisch: Ist die Suche bis zur Antwort schon zu,
## läuft die Antwort ins Leere (keine Rückkehr in eine freigegebene Ebene).
static func _fetch(kind: String, q: String, done: Callable) -> void:
	var r: Variant = null
	match kind:
		"shop": r = await Store.search(q)
		"music": r = await Music.search(q)
		"streams": r = await Twitch.search(q)
		"movies": r = await Movies.search(q)
	if done.is_valid():
		done.call(kind, q, r)


func _got(kind: String, q: String, r: Variant) -> void:
	if _closing or not _net.has(q):
		return
	(_net[q] as Dictionary)[kind] = r
	# Antworten zu einem älteren Suchwort bleiben gemerkt, zeigen sich aber nicht.
	if q == _q():
		_refresh_net(kind)


func _refresh_net(kind := "") -> void:
	if _full:
		if kind == "":
			for k in _sources:
				_fill_net(k)
		else:
			_fill_net(kind)
	else:
		_live_net.text = _net_line()


# --- Beim Tippen -------------------------------------------------------------------------------

## Oben die besten Treffer: Spiele zuerst, darunter das Beste aus Einstellungen und Freunden.
func _show_live() -> void:
	_live_due = false
	if not is_instance_valid(_live_rows) or _full:
		return
	var q := _q()
	_live_net.text = _net_line()
	var rows: Array = []
	if q != "":
		var others: Array = []
		for s in Search.rank(_settings(), q, LIVE_ROWS):
			others.append(["set", s])
		for f in Search.rank(_friends_idx, q, LIVE_ROWS):
			others.append(["friend", f])
		for g in Search.rank(_games_idx, q, LIVE_ROWS - (1 if not others.is_empty() else 0)):
			rows.append(["game", g])
		for o in others:
			if rows.size() < LIVE_ROWS:
				rows.append(o)
	U.clear(_live_rows)
	var seen := {}
	for r in rows:
		var it := _row(str(r[0]), r[1], true)
		_live_rows.add_child(it)
		it.focus_mode = Control.FOCUS_NONE
		var key := str(it.get_meta("uz_key", ""))
		seen[key] = true
		# Neu dazugekommene Treffer blenden weich ein, gebliebene stehen still.
		if not _live_keys.has(key):
			it.modulate.a = 0.0
			U.tw(it, "uz_live").tween_property(it, "modulate:a", 1.0, U.T_BASE)
	_live_keys = seen
	_live_head.text = "" if rows.is_empty() else "Beste Treffer"
	if rows.is_empty():
		var l := U.label("Spiele, Einstellungen und Freunde – schon beim Tippen." if q == "" else "Auf diesem PC nichts zu „%s“." % q, "m", "muted")
		_live_rows.add_child(l)


## Zeile oben rechts: was im Netz gerade passiert.
func _net_line() -> String:
	if _sources.is_empty():
		return ""
	if not _online:
		return "Nur auf diesem PC"
	var q := _q()
	if q.length() < NET_MIN:
		return ""
	if not _net.has(q):
		return "Im Netz nach kurzer Pause"
	var got: Dictionary = _net[q]
	if got.size() < _sources.size():
		return "Sucht im Netz …"
	var bits := PackedStringArray()
	for k in _sources:
		var n := _net_count(k, got.get(k))
		if n > 0:
			bits.append("%s (%d)" % [TranslationServer.translate(NET_NAMES[k]), n])
	return ("Im Netz: " + "  ·  ".join(bits)) if not bits.is_empty() else "Im Netz nichts gefunden"


# --- Alle Treffer -------------------------------------------------------------------------------

func _set_full(on: bool) -> void:
	if on == _full:
		return
	_full = on
	var show_c: Control = _live
	var hide_c: Control = _sc
	if on:
		show_c = _sc
		hide_c = _live
	var tw := U.tw(hide_c, "uz_mode")
	tw.tween_property(hide_c, "modulate:a", 0.0, U.T_FAST)
	tw.tween_callback(func() -> void:
		if is_instance_valid(hide_c) and _full != (hide_c == _sc):
			hide_c.visible = false
	)
	show_c.visible = true
	show_c.modulate.a = 0.0
	U.tw(show_c, "uz_mode").tween_property(show_c, "modulate:a", 1.0, U.T_BASE).set_delay(0.04)


func _show_full() -> void:
	_set_full(true)
	_live_keys = {}
	_fill_full(false)
	# Die Gruppen erscheinen nacheinander, wie Seiten sonst auch.
	var i := 0
	for ch in _body.get_children().slice(0, 10):
		var c := ch as Control
		c.modulate.a = 0.0
		U.tw(c, "uz_casc").tween_property(c, "modulate:a", 1.0, U.T_ENTER - 0.06).set_delay(0.06 + i * U.STAGGER)
		i += 1
	# Erst wenn die Tastatur weg ist (sie gibt den Fokus beim Schließen zurück).
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _closing or not _full:
		return
	var first := Nav.default_in(_body)
	Nav.focus(first if first else Nav.default_in(self), true)


## Alle Gruppen neu. keep: die Auswahl bleibt auf derselben Zeile (Netz an/aus).
func _fill_full(keep: bool) -> void:
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if keep and f else ""
	var q := _q()
	_title.text = "„%s“" % q
	_sub.text = _sub_text()
	U.clear(_body)
	_groups.clear()
	var games := Search.rank(_games_idx, q, 0)
	var sets := Search.rank(_settings(), q, 6)
	var friends := Search.rank(_friends_idx, q, 6)
	if not games.is_empty():
		_group_head("Spiele", U.plural(games.size(), "Treffer", "Treffer"))
		for g in games.slice(0, 12):
			_body.add_child(_row("game", g, false))
	if not sets.is_empty():
		_group_head("Einstellungen", "")
		for s in sets:
			_body.add_child(_row("set", s, false))
	if not friends.is_empty():
		_group_head("Freunde", "")
		for fr in friends:
			_body.add_child(_row("friend", fr, false))
	var any_local := not (games.is_empty() and sets.is_empty() and friends.is_empty())
	if not any_local:
		var m := U.margin(14, 26, 14, 0)
		var box := U.vbox(6)
		box.add_child(U.label("Auf diesem PC nichts gefunden", "xl", "text", "bold"))
		box.add_child(
				U.label("Weniger Buchstaben oder ein anderes Wort helfen oft." if _online or _sources.is_empty()
				else "Weniger Buchstaben helfen oft – oder Y sucht auch im Netz.", "m", "muted", "regular", true))
		m.add_child(box)
		_body.add_child(m)
	for kind in _sources:
		if kind == "music" or kind == "shop":
			_net_group(kind)
	if main.sections.has("videos"):
		_group_head("Videos", "")
		_body.add_child(_link_row("videos", "„%s“ bei YouTube suchen" % q, "Die Videosuche fragt YouTube erst jetzt.", "video"))
	for kind in _sources:
		if kind == "streams" or kind == "movies":
			_net_group(kind)
	_body.add_child(U.spacer(0, 40, false))
	var first := Nav.default_in(_body)
	if first:
		first.set_meta("uz_default", true)
	if key != "":
		await get_tree().process_frame
		for c in Nav.focusables(self):
			if str(c.get_meta("uz_key", "")) == key:
				Nav.focus(c, true)
				return


func _sub_text() -> String:
	if _sources.is_empty() or not _online:
		return "Nur auf diesem PC"
	return "Auf diesem PC – nach einer kurzen Pause beim Tippen auch im Netz"


func _group_head(text: String, extra: String) -> Control:
	var m := U.margin(14, 30, 14, 10)
	var row := U.hbox(14)
	m.add_child(row)
	var l := U.label(text, "l", "text", "bold")
	l.clip_text = false
	row.add_child(l)
	var e := U.label(extra, "m", "faint", "medium")
	e.clip_text = false
	e.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(e)
	_body.add_child(m)
	return e


## Platz einer Gruppe aus dem Netz; wird gefüllt, sobald die Antwort da ist.
func _net_group(kind: String) -> void:
	if not _online:
		return
	var extra := _group_head("Filme und Serien" if kind == "movies" else str(NET_NAMES[kind]), "")
	var box := U.vbox(0)
	box.set_meta("uz_extra", extra)
	_body.add_child(box)
	_groups[kind] = box
	_fill_net(kind)


func _fill_net(kind: String) -> void:
	var box: VBoxContainer = _groups.get(kind)
	if box == null or not is_instance_valid(box):
		return
	var q := _q()
	var got: Variant = (_net.get(q, {}) as Dictionary).get(kind) if _net.has(q) else null
	var waiting := _net.has(q) and not (_net[q] as Dictionary).has(kind)
	var extra: Label = box.get_meta("uz_extra")
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if f and box.is_ancestor_of(f) else ""
	U.clear(box)
	if q.length() < NET_MIN:
		extra.text = "ab %d Buchstaben" % NET_MIN
		return
	if waiting or not _net.has(q):
		extra.text = "sucht …"
		return
	var rows := _net_rows(kind, got)
	var n := _net_count(kind, got)
	extra.text = U.plural(n, "Treffer", "Treffer") if n > 0 else ""
	if rows.is_empty():
		var why := _net_error(kind, got)
		var m := U.margin(14, 0, 14, 0)
		m.add_child(U.label(why if why != "" else "Nichts gefunden", "m", "muted", "regular", true))
		box.add_child(m)
		return
	for r in rows:
		box.add_child(r)
	box.add_child(_link_row(kind, str(ALL_TEXT[kind]), "", "search"))
	if key != "":
		for c in Nav.focusables(box):
			if str(c.get_meta("uz_key", "")) == key:
				Nav.focus(c, true)
				break
	# Eine Antwort kommt erst nach dem Blättern: weich einblenden statt springen.
	box.modulate.a = 0.0
	U.tw(box, "uz_net").tween_property(box, "modulate:a", 1.0, U.T_BASE)


static func _net_count(kind: String, got: Variant) -> int:
	match kind:
		"shop":
			return (got as Array).size() if got is Array else 0
		"movies":
			var n := 0
			for row in (got as Array) if got is Array else []:
				n += (row.get("items", []) as Array).size() if row is Dictionary else 0
			return n
		"music":
			return ((got as Dictionary).get("tracks", []) as Array).size() + ((got as Dictionary).get("artists", []) as Array).size() if got is Dictionary else 0
		"streams":
			return ((got as Dictionary).get("channels", []) as Array).size() + ((got as Dictionary).get("games", []) as Array).size() if got is Dictionary else 0
	return 0


static func _net_error(kind: String, got: Variant) -> String:
	if got is Dictionary:
		return str((got as Dictionary).get("error", ""))
	if kind == "movies":
		return str(Movies.error)
	return ""


func _net_rows(kind: String, got: Variant) -> Array:
	var out: Array = []
	match kind:
		"shop":
			for it in (got as Array).slice(0, 5) if got is Array else []:
				out.append(
						_item("shop:" + str(it.get("appid", "")), str(it.get("name", "")), "Steam-Shop", Store.price_label(it), str(it.get("header", "")), "shop", "Ansehen",
					func() -> void: main.sections["shop"].open_item(it)))
		"music":
			var d: Dictionary = got if got is Dictionary else {}
			var tracks: Array = d.get("tracks", [])
			for i in mini(3, tracks.size()):
				var t: Dictionary = tracks[i]
				out.append(
						_item("track:" + str(t.get("id", i)), str(t.get("title", "")), "%s · %s" % [TranslationServer.translate("Titel", "musik"), str(t.get("artist", ""))], "",
						str(t.get("art", "")), "music", "Abspielen",
					func() -> void: Music.play_list(tracks, i)))
			for a in (d.get("artists", []) as Array).slice(0, 2):
				var ad: Dictionary = a
				out.append(_item("artist:" + str(ad.get("id", "")), str(ad.get("name", "")), "Künstler", "", str(ad.get("art", "")), "user", "Künstlerseite",
					func() -> void: MusicBits.open_artist(main, ad)))
		"streams":
			var d2: Dictionary = got if got is Dictionary else {}
			for c in (d2.get("channels", []) as Array).slice(0, 3):
				var cd: Dictionary = c
				out.append(
						_item("chan:" + str(cd.get("login", "")), str(cd.get("title", "")), "Live" if bool(cd.get("live", false)) else "Kanal", "", str(cd.get("thumb", "")),
						"channel", "Kanal öffnen",
					func() -> void: main.open_stream_channel(str(cd.get("login", "")), str(cd.get("title", "")))))
			for g in (d2.get("games", []) as Array).slice(0, 2):
				var gd: Dictionary = g
				out.append(_item("cat:" + str(gd.get("id", "")), str(gd.get("title", "")), "Kategorie", "", "", "live", "Öffnen",
					func() -> void: main.open_stream_game(gd)))
		"movies":
			var items: Array = []
			for row in (got as Array) if got is Array else []:
				if row is Dictionary:
					items.append_array(row.get("items", []))
			for m in items.slice(0, 5):
				var md: Dictionary = m
				var bits := PackedStringArray([Movies.type_label(str(md.get("type", "")), false)])
				if str(md.get("year", "")) != "":
					bits.append(str(md.get("year", "")))
				out.append(_item("movie:" + str(md.get("id", "")), str(md.get("name", "")), "  ·  ".join(bits), "", str(md.get("poster", "")), "video", "Öffnen",
					func() -> void: main.open_movie(md)))
	return out


# --- Zeilen -------------------------------------------------------------------------------------

## Ein Treffer von diesem PC: game, set (Einstellung) oder friend. live: Anzeige beim Tippen.
func _row(kind: String, v: Dictionary, live: bool) -> Control:
	var it := ListItem.new()
	if live:
		it.min_h = 64
	match kind:
		"game":
			it.setup(Library.display_title(v), _game_line(v), "Spiel" if live else "")
			var cover := Media.local_path(v, "cover")
			if cover != "":
				it.image_url = cover
			else:
				it.icon_name = "games"
			it.set_meta("uz_key", "gs:game:" + str(v.get("id", "")))
			it.set_meta("uz_hint_a", "Spielseite" if main.game_page_on() else "Spielen")
			it.activated.connect(func() -> void:
				# Ohne Spielseite startet das Spiel gleich: dann die Suche nicht offen lassen.
				if not main.game_page_on():
					close()
				main.open_game(v)
			)
		"set":
			it.setup(str(v.title), str(v.cat_name) + ((" › " + str(v.more)) if str(v.more) != "" else ""), "Einstellung" if live else "")
			it.icon_name = "settings"
			it.set_meta("uz_key", "gs:set:" + str(v.key))
			it.set_meta("uz_hint_a", "Zur Einstellung")
			it.activated.connect(func() -> void:
				close()
				main.open_setting(str(v.cat), str(v.key), str(v.more))
			)
		"friend":
			var steam := str(v.get("_kind", "")) == "steam"
			var line := ChatView.status_line(v) if steam else (str(v.get("game", "")) if str(v.get("game", "")) != ""
					else str(People.STATE_TEXT.get(str(v.get("state", "")), "Online")))
			it.setup(str(v.get("name", "")), ("Steam · " if steam else "Discord · ") + line, "Freund" if live else "")
			it.avatar = true
			it.image_url = str(v.get("avatar", ""))
			it.status = str(v.get("state", ""))
			it.set_meta("uz_key", "gs:friend:%s:%s" % [v.get("_kind", ""), v.get("id", "")])
			it.set_meta("uz_hint_a", "Optionen" if steam else "Chat")
			var f := v.duplicate()
			f.erase("_kind")
			it.activated.connect(func() -> void:
				if steam:
					main.open_friend(f, "steam")
				else:
					main.open_discord_chat(f)
			)
	return it


func _game_line(g: Dictionary) -> String:
	var bits := PackedStringArray()
	match str(g.get("source", "")):
		"steam": bits.append("Steam")
		"epic": bits.append("Epic Games")
		"ea": bits.append("EA app")
		"pc": bits.append("PC")
		_: bits.append(Library.store_name(g, false, str(Config.system(str(g.get("system", ""))).get("name", ""))))
	if not Library.is_installed(g):
		bits.append("Nicht installiert")
	elif Library.playtime(g) > 0:
		bits.append(U.playtime(Library.playtime(g)))
	return "  ·  ".join(bits)


## Ein Treffer aus dem Netz: öffnet die Seite des Bereichs über der Suche (B kommt zurück).
func _item(key: String, title: String, sub: String, trail: String, image: String, icon: String, hint: String, act: Callable) -> Control:
	var it := ListItem.new()
	it.setup(title, sub, trail)
	if image.begins_with("https://"):
		it.image_url = image
	else:
		it.icon_name = icon
	it.set_meta("uz_key", "gs:" + key)
	it.set_meta("uz_hint_a", hint)
	it.activated.connect(act)
	return it


## „Alle Treffer …“: zum Bereich und dort mit demselben Wort weitersuchen.
func _link_row(sid: String, title: String, sub: String, icon: String) -> Control:
	var it := ListItem.new()
	it.setup(title, sub)
	it.icon_name = icon
	it.min_h = 64
	it.set_meta("uz_key", "gs:all:" + sid)
	it.set_meta("uz_hint_a", "Suchen")
	var q := _q()
	it.activated.connect(func() -> void:
		# Musik sucht als Ebene (darüber, B kommt zurück); die anderen Bereiche liegen unter der Suche.
		if sid != "music":
			close()
		main.search_in(sid, q)
	)
	return it
