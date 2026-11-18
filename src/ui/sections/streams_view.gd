extends "res://src/ui/sections/medien_bereich.gd"
## Streams (Twitch, abgespielt ohne Browser über mpv wie Videos).
##
## Startseite: die Bühne (medien_buehne.gd) zeigt den Stream, auf dem man steht – großes Bild oben
## rechts im Raum, unten links Grund, Titel, Kanal · Kategorie · Zuschauer und die Tasten als
## Pillen –, darunter die Reihen (medien_reihen.gd): Weiterschauen (angefangene Übertragungen)
## zuerst, dann Live von gefolgten Kanälen, Beliebt auf Deutsch, Kategorien, Beliebt weltweit. Die
## Reihen rasten beim Blättern unter der Bühne ein, wie bei Videos und Filmen. Ohne Anmeldung
## steht statt der gefolgten Kanäle eine ruhige Karte zum Anmelden; alles andere geht trotzdem.
## Gefolgt: alle gefolgten Kanäle, die gerade live sind. Kategorien: Spielhüllen im Raster.
## Suche: Kanäle, Live-Streams und Kategorien. Kanal und Kategorie öffnen eine eigene Seite.

const StreamCard := preload("res://src/ui/components/stream_card.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")
const ChannelTile := preload("res://src/ui/components/channel_tile.gd")
const MedienBuehne := preload("res://src/ui/components/medien_buehne.gd")
const MedienReihen := preload("res://src/ui/components/medien_reihen.gd")
const TP := preload("res://src/core/twitch_parse.gd")
const Ladezeit := preload("res://src/core/ladezeit.gd")

const ROW_W := 352.0           ## Karten in den Reihen unter der Bühne (wie Videos)
const GRID_W := 408.0          ## Karten in Rastern: vier Spalten
const BOX_W := 186.0           ## Kategorien in der Reihe
const BOX_GRID_W := 258.0      ## Kategorien im Raster: sechs Spalten
const GRID_GAP := 32

var _query := ""
var _searching := false
var _found: Dictionary = {}
var _recent: Array = []        ## letzte Suchen (nur in dieser Sitzung)
var _bg_key := ""
var _stale_what := {}
var _buehne = null             ## medien_buehne.gd


func _init() -> void:
	super()
	id = "streams"
	title = "Streams"
	icon_name = "live"
	keep_built = true
	stale_keys = PackedStringArray(["twitch.", "accounts.twitch", "youtube.quality"])
	Twitch.changed.connect(_on_changed)
	Twitch.changed.connect(func(w: String) -> void:
		if not w.ends_with("_loading") or _wants_rebuild(w):
			mark_stale()
	)
	Nav.focus_moved.connect(_on_nav_focus)


func subtabs() -> Array:
	var out: Array = [{ "id": "start", "label": "Startseite" }]
	var g := { "id": "gefolgt", "label": "Gefolgt" }
	if Twitch.logged_in() and not Twitch.followed.is_empty():
		g["count"] = Twitch.followed.size()
	out.append(g)
	out.append({ "id": "kategorien", "label": "Kategorien" })
	out.append({ "id": "suche", "label": "Suche" })
	return out


func on_enter() -> void:
	Twitch.refresh_followed()
	Twitch.refresh_top()
	Twitch.refresh_games()


## Beim Start (main._prebuild): Live-Listen und Kategorien anstoßen.
func prefetch() -> void:
	on_enter()


func data_ready() -> bool:
	return not Twitch.top_loading and not Twitch.followed_loading and not Twitch.games_loading


func _on_changed(what: String) -> void:
	if not visible or not is_inside_tree():
		return
	if Nav.top_layer() != null or Video.active:
		# Ein Menü oder der Player liegt darüber: danach nachholen (siehe _on_nav_focus).
		_stale_what[what] = true
		return
	if _wants_rebuild(what):
		_rebuild_keep()
	else:
		_refresh_cards()
	if main:
		main.refresh_chips()
	Ladezeit.pruefen(self)


## Für die Ladezeit (src/core/ladezeit.gd): steht schon Inhalt, ist alles geladen?
func lade_stand() -> Dictionary:
	var laedt: bool = (sub == "start" and (Twitch.top_loading or Twitch.followed_loading)) or (sub == "gefolgt" and Twitch.followed_loading) \
			or (sub == "kategorien" and Twitch.games_loading)
	var inhalt: bool = _reihen.row_count() > 0 if _reihen != null and is_instance_valid(_reihen) else \
			find_children("*", "Control", true, false).any(func(c: Node) -> bool: return c.has_method("refresh_state"))
	return { "inhalt": inhalt, "fertig": not laedt, "quelle": "gemerkt" if laedt else "frisch" }


## Ändert sich durch diese Daten, was auf der Seite steht?
func _wants_rebuild(what: String) -> bool:
	match what:
		"followed": return sub in ["start", "gefolgt"]
		"top": return sub == "start"
		"games": return sub in ["start", "kategorien"] or (sub == "suche" and _query == "")
		"resume": return sub == "start"
		"account": return true
		# Nur der Ladezustand: neu bauen, wo die Seite sonst leer stünde.
		"top_loading": return sub == "start" and Twitch.top.is_empty() and Twitch.followed.is_empty()
		"followed_loading": return sub == "gefolgt" and Twitch.followed.is_empty()
		"games_loading": return sub == "kategorien" and Twitch.games.is_empty()
	return false


func _on_nav_focus(_c: Control) -> void:
	if _stale_what.is_empty() or not visible or not is_inside_tree() or Nav.top_layer() != null or Video.active:
		return
	var whats: Array = _stale_what.keys()
	_stale_what.clear()
	if whats.any(func(w: Variant) -> bool: return _wants_rebuild(str(w))):
		_rebuild_keep()
	else:
		_refresh_cards()
	if main:
		main.refresh_chips()


func _refresh_cards() -> void:
	for c in find_children("*", "Control", true, false):
		if c.has_method("refresh_state"):
			c.call("refresh_state")
	if _buehne != null and is_instance_valid(_buehne) and not _buehne.item.is_empty():
		var f := Nav.focused()
		_zeige(_buehne.item, 0, f if f and f.get("video") is Dictionary and str(f.get("video").get("id", "")) == str(_buehne.item.get("id", "")) else null)


## Bereich neu betreten (LT/RT): ganz nach oben, alle Reihen wieder am Anfang, die Bühne zeigt
## wieder den ersten Stream.
func reset_position() -> void:
	super()
	if _reihen == null or not is_instance_valid(_reihen):
		return
	_reihen.reset()
	var first: Control = _reihen.first_card()
	if first:
		_zeige(first.get("video") if first.get("video") is Dictionary else {}, 0, first)


func reenter() -> void:
	_bg_key = ""
	if _buehne != null and is_instance_valid(_buehne):
		_buehne.wieder()


func on_leave() -> void:
	if _buehne != null and is_instance_valid(_buehne):
		_buehne.verlassen()


func build() -> void:
	mark_built()
	U.clear(self)
	_buehne = null
	_reihen = null
	_bg_key = ""
	_stale_what.clear()
	match sub:
		"gefolgt": _build_followed()
		"kategorien": _build_games()
		"suche": _build_search()
		_: _build_start()


# --- Bausteine ---------------------------------------------------------------------------------

func _card(v: Dictionary, list: Array, idx: int, w := GRID_W, key := "") -> Control:
	var c = StreamCard.new()
	c.setup_stream(v, w)
	c.key_prefix = key
	var kind := str((v.get("twitch", {}) as Dictionary).get("kind", ""))
	var pos := Twitch.resume_pos(str(v.get("id", "")))
	c.set_meta("uz_hint_a", "Live ansehen" if kind == "live" else (("Weiterschauen ab " + YouTube.time_text(pos)) if pos > 20 else "Abspielen"))
	c.set_meta("uz_hint_y", "Optionen")
	c.set_meta("uz_on_y", func() -> void: _options(v, list, idx))
	c.chosen.connect(func(_v: Dictionary) -> void: play(list, idx))
	c.focused_video.connect(_on_focused)
	return c


func _game_card(g: Dictionary, w: float, key := "") -> Control:
	var c = StreamCard.new()
	c.setup_stream(g, w, true)
	c.key_prefix = key
	c.set_meta("uz_hint_a", "Kategorie öffnen")
	c.chosen.connect(func(_v: Dictionary) -> void: main.open_stream_game(g))
	c.focused_video.connect(_on_focused)
	return c


## Abspielen in Uzais Player (mpv). Angefangene Übertragungen ab der gemerkten Stelle.
func play(list: Array, idx: int) -> void:
	if idx < 0 or idx >= list.size():
		return
	var pos := Twitch.resume_pos(str((list[idx] as Dictionary).get("id", "")))
	main.open_video(list, idx, { "start": pos } if pos > 20 else {})


## Y auf einer Karte: Kanal öffnen, aufs Handy, Weiterschauen vergessen.
func _options(v: Dictionary, list: Array, idx: int) -> void:
	var tw: Dictionary = v.get("twitch", {})
	var opts: Array = [["play", "Live ansehen" if str(tw.get("kind", "")) == "live" else "Abspielen"]]
	if str(tw.get("login", "")) != "":
		opts.append(["kanal", "Zum Kanal: " + str(tw.get("name", tw.login))])
	if str(tw.get("game", "")) != "" and str(tw.get("game_id", "")) != "":
		opts.append(["kategorie", "Kategorie: " + str(tw.game)])
	opts.append(["qr", "Link aufs Handy"])
	if Twitch.resume_pos(str(v.get("id", ""))) > 0:
		opts.append(["vergessen", "Aus „Weiterschauen“ entfernen"])
	main.open_choice(str(v.get("title", "")), opts, null, func(o: Variant) -> void:
		match str(o):
			"play": play(list, idx)
			"kanal": main.open_stream_channel(str(tw.login), str(tw.get("name", "")))
			"kategorie": main.open_stream_game(
					{ "id": "tw:g:" + str(tw.game_id), "game_id": str(tw.game_id), "slug": "", "title": str(tw.game), "channel": str(tw.game), "thumb": "" })
			"qr":
				var q = load("res://src/ui/layers/video_qr.gd").new()
				q.video = v
				main.open_layer(q)
			"vergessen": Twitch.forget_resume(str(v.get("id", "")))
	, str(tw.get("name", "")))


## Hintergrund: der Raum nimmt die Farbe des gewählten Streams an (Raster-Seiten; auf der
## Startseite malt die Bühne den Raum).
func _on_focused(v: Dictionary) -> void:
	var key := str(v.get("id", ""))
	if _buehne != null and is_instance_valid(_buehne):
		return
	if key == _bg_key or main == null or main.background == null or not visible:
		return
	_bg_key = key
	var poster := VideoCard.poster_texture(v)
	var url := VideoCard.thumb_url(v)
	if url == "":
		main.background.show_blurred(poster, "tw:" + key)
		return
	Media.url_texture(url, int(ROW_W * 1.1), func(t: Texture2D) -> void:
		if _bg_key == key and visible and main and main.current == id and is_instance_valid(main.background):
			main.background.show_blurred(t if t else poster, "tw:" + key)
	)


func _grid(list: Array, group: String, cols := 4) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = U.cols_for(cols)
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", 40)
	grid.set_meta("uz_group", group)
	for i in list.size():
		grid.add_child(_card(list[i], list, i, GRID_W, group + ":"))
	return grid


func _game_grid(list: Array, group: String, count := -1) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = U.cols_for(6)
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", 36)
	grid.set_meta("uz_group", group)
	for g in (list if count < 0 else list.slice(0, count)):
		grid.add_child(_game_card(g, BOX_GRID_W, group + ":"))
	return grid


func _login() -> void:
	main.open_twitch_login()


# --- Startseite ----------------------------------------------------------------------------------

## Liste für das große Bild oben: Gefolgte, sonst Beliebte.
func _first_list() -> Array:
	if Twitch.logged_in() and not Twitch.followed.is_empty():
		return Twitch.followed
	if not Twitch.top.is_empty():
		return Twitch.top
	return Twitch.top_all


func _build_start() -> void:
	var first := _first_list()
	if first.is_empty():
		_build_start_empty()
		return
	_buehne = MedienBuehne.new().setup(self, main)
	add_child(_buehne)
	_reihen = MedienReihen.new().setup(MedienBuehne.H)
	_reihen.instant = _instant
	_reihen.row_focused.connect(_on_row_card)
	add_child(_reihen)
	# Weiterschauen zuerst (wie überall in den Medien), dann die gefolgten Kanäle.
	var cont := Twitch.continue_list()
	if not cont.is_empty():
		_add_row("Weiterschauen", "", cont, "weiter")
	var nobody := ""
	if not Twitch.logged_in():
		_add_prompt_row()
	elif not Twitch.followed.is_empty():
		_add_row("Live – Gefolgt", followed_hint(Twitch.followed.size(), str(Twitch.followed_error)), Twitch.followed, "gefolgt")
	else:
		nobody = "von deinen Kanälen ist gerade niemand live" if Twitch.followed_error == "" else str(Twitch.followed_error)
	var lang_name := Twitch.lang_name(Twitch.lang())
	if not Twitch.top.is_empty():
		_add_row("Beliebt auf " + lang_name, nobody if nobody != "" else top_hint(str(Twitch.top_error)), Twitch.top, "beliebt")
		nobody = ""
	if not Twitch.games.is_empty():
		_add_game_row()
	if not Twitch.top_all.is_empty():
		_add_row("Beliebt weltweit", nobody, Twitch.top_all, "weltweit")
	var fc: Control = _reihen.first_card()
	if fc:
		fc.set_meta("uz_default", true)
		_zeige(fc.get("video") if fc.get("video") is Dictionary else {}, 0, fc)


## Kleiner Hinweis neben „Live – Gefolgt“.
static func followed_hint(n: int, error: String) -> String:
	if error != "":
		return "Stand von vorhin – Twitch gerade nicht erreichbar"
	return U.plural(n, "Kanal", "Kanäle") + " live"


static func top_hint(error: String) -> String:
	return "Stand von vorhin – Twitch gerade nicht erreichbar" if error != "" else ""


func _build_start_empty() -> void:
	if Twitch.top_loading or Twitch.followed_loading:
		# Platzhalter in der Form der Bühne und der ersten Reihen: wenn die Streams kommen, springt nichts.
		add_child(MedienReihen.skeleton(MedienBuehne.H, Vector2(ROW_W, round(ROW_W * 9.0 / 16.0) + 102), 2))
		return
	var btns: Array = [["Neu laden", "refresh", func() -> void:
		Twitch.refresh_top(true)
		Twitch.refresh_followed(true)
		Twitch.refresh_games(true)]]
	if not Twitch.logged_in():
		btns.append(["Mit Twitch anmelden", "qr", _login])
	add_child(
			empty_state("Twitch gerade nicht erreichbar", str(Twitch.top_error) if Twitch.top_error != ""
			else "Keine Liste von Twitch erhalten. Später erneut versuchen.", btns,
			"fehler"))


## Ohne Anmeldung: eine ruhige Karte in der Reihe der gefolgten Kanäle.
func _add_prompt_row() -> void:
	var row: Dictionary = _reihen.add_row("Live – Gefolgt", "nach der Anmeldung", "s:gefolgt", round(ROW_W * 9.0 / 16.0) + 102)
	var p := _PromptCard.new()
	p.setup(ROW_W * 2.0 + 28.0, round(ROW_W * 9.0 / 16.0), "Mit Twitch anmelden", "Gefolgte Kanäle, die gerade live sind.")
	p.set_meta("uz_key", "s:anmelden")
	p.set_meta("uz_hint_a", "Anmelden")
	p.chosen.connect(_login)
	_reihen.add_card(row, p, { "id": "s:anmelden", "title": "Mit Twitch anmelden", "_prompt": true })


## Eine Reihe unter der Bühne.
func _add_row(head: String, extra: String, list: Array, group: String, limit := 30) -> void:
	var row: Dictionary = _reihen.add_row(head, extra, "s:" + group, round(ROW_W * 9.0 / 16.0) + 102)
	for i in mini(list.size(), limit):
		_reihen.add_card(row, _card(list[i], list, i, ROW_W, group + ":"), list[i])


## Kategorien als Reihe von Spielhüllen.
func _add_game_row() -> void:
	var row: Dictionary = _reihen.add_row("Kategorien", "meiste Zuschauer zuerst", "s:kategorien", round(BOX_W * 4.0 / 3.0) + 102, 24)
	for g in Twitch.games.slice(0, 20):
		_reihen.add_card(row, _game_card(g, BOX_W, "kat:"), g)


## Eine Karte in einer Reihe ist gewählt: die Bühne zeigt sie.
func _on_row_card(_idx: int, c: Control, v: Dictionary, dir: int) -> void:
	_zeige(v, dir, c)


## Die Bühne zu einem Stream, einer Übertragung, einer Kategorie oder der Anmelde-Karte: Grund,
## Titel, Kanal · Kategorie · Zuschauer · live seit, die Tasten der Karte; das Bild in 1280 × 720
## (Twitch liefert jede Größe), Kategorien mit ihrem Farbfeld.
func _zeige(v: Dictionary, dir: int, card: Control) -> void:
	if _buehne == null or not is_instance_valid(_buehne) or v.is_empty():
		return
	var tasten := MedienBuehne.tasten_von(card)
	var vid := str(v.get("id", ""))
	if bool(v.get("_prompt", false)):
		_buehne.zeige(v, dir, { "grund": [], "titel": str(v.get("title", "")), "zeile": "Per QR-Code mit dem Handy", "tasten": tasten },
			{ "key": "tw:anmelden", "urls": [], "ph": VideoCard.poster_for("Twitch") })
		return
	var tw: Variant = v.get("twitch")
	var text := { "grund": reason_for(v), "titel": str(v.get("title", "")), "zeile": buehne_zeile(v, int(Time.get_unix_time_from_system())), "tasten": tasten }
	var own := VideoCard.thumb_url(v)
	var urls: Array = []
	if own != "" and tw is Dictionary:
		urls = [TP.bigger(own)]
		if urls[0] != own:
			urls.append(own)
	var bild := { "key": "tw:" + vid, "urls": urls, "ph": VideoCard.poster_texture(v), "warm": [] }
	if card != null and is_instance_valid(card) and card.get_parent() and tw is Dictionary:
		var i := card.get_index()
		for j in [i + 1, i - 1]:
			var n := card.get_parent().get_child(j) if j >= 0 and j < card.get_parent().get_child_count() else null
			if n and n.get("video") is Dictionary:
				var nu := VideoCard.thumb_url(n.get("video"))
				if nu != "":
					(bild.warm as Array).append(TP.bigger(nu))
	_buehne.zeige(v, dir, text, bild)


## Die leise Zeile der Bühne: live Kanal · Kategorie · Zuschauer · seit; Übertragung Kanal ·
## Restzeit bzw. Alter; Kategorie nur die Zuschauer.
static func buehne_zeile(v: Dictionary, now: int) -> String:
	var tw: Variant = v.get("twitch")
	var parts := PackedStringArray()
	if not (tw is Dictionary):
		var vt := TP.viewers_text(int(v.get("viewers", 0)))
		if vt != "":
			parts.append(vt)
		return VideoCard.SEP.join(parts)
	if str(v.get("channel", "")) != "":
		parts.append(str(v.channel))
	if str(tw.get("kind", "")) == "live":
		for p in [str(tw.get("game", "")), TP.viewers_text(int(tw.get("viewers", 0))), TP.uptime_text(int(tw.get("started", 0)), now)]:
			if p != "":
				parts.append(p)
	else:
		var resume := Twitch.resume_pos(str(v.get("id", "")))
		var dur := int(v.get("duration", 0))
		if resume > 20 and dur > resume:
			parts.append(VideoCard.left_text(int(dur - resume)))
		elif int(v.get("published", 0)) > 0:
			parts.append(U.ago(int(v.published)))
	return VideoCard.SEP.join(parts)


## Ein echter Grund, warum dieser Stream oben steht – oder keiner.
func reason_for(v: Dictionary) -> Array:
	var tw: Variant = v.get("twitch")
	if not (tw is Dictionary):
		return []
	var vid := str(v.get("id", ""))
	if Twitch.resume_pos(vid) > 20:
		return ["Weiterschauen ab " + YouTube.time_text(Twitch.resume_pos(vid)), "history"]
	if str(tw.get("kind", "")) != "live":
		return []
	for f in Twitch.followed:
		if str(f.get("id", "")) == vid:
			return ["Live – du folgst " + str(tw.get("name", "")), "live"]
	for i in mini(3, Twitch.top.size()):
		if str(Twitch.top[i].get("id", "")) == vid:
			return ["Gerade beliebt auf " + Twitch.lang_name(Twitch.lang()), "bolt"]
	return ["Gerade live", "live"]


# --- Gefolgt -------------------------------------------------------------------------------------

func _build_followed() -> void:
	if not Twitch.logged_in():
		# Die Bühne mit angedeuteten Streams; A meldet per QR-Code an (wie die Twitch-App am
		# Fernseher). Danach kommen deine Kanäle, die live sind, im Takt herein.
		var abgelaufen: bool = Twitch.state == "abgelaufen"
		add_child(leer_buehne({ "art": "video", "symbol": "live",
			"titel": "Twitch-Anmeldung abgelaufen." if abgelaufen else "Deine Kanäle, die gerade live sind.",
			"zeile": "Per QR-Code wie am Fernseher.", "knopf": "Anmelden", "tun": _login,
			"neben": "Beliebte Streams", "neben_tun": func() -> void: main.goto("streams", "start"),
			"fertig": func() -> bool: return Twitch.logged_in() }))
		return
	if Twitch.followed.is_empty():
		var loading: bool = Twitch.followed_loading
		var err := str(Twitch.followed_error)
		add_child(empty_state("Gefolgte Kanäle werden geladen" if loading else ("Twitch gerade nicht erreichbar" if err != "" else "Gerade ist niemand live"),
			err if err != "" and not loading else "Gefolgte Kanäle erscheinen, sobald sie live gehen.", [
			["Beliebte Streams", "live", func() -> void: main.goto("streams", "start")],
			["Neu laden", "refresh", func() -> void: Twitch.refresh_followed(true)],
		], "laden" if loading else ("fehler" if err != "" else "leer")))
		return
	var col := _scroll_page()
	var info := "%s live  ·  Angemeldet als %s" % [U.plural(Twitch.followed.size(), "Kanal", "Kanäle"), Twitch.account_name()]
	if Twitch.followed_error != "":
		info += "  ·  Stand von vorhin"
	col.add_child(_page_head(info))
	var m := U.margin(GUTTER, 22, GUTTER, 80)
	var grid := _grid(Twitch.followed, "sgrid:gefolgt")
	m.add_child(grid)
	col.add_child(m)
	if grid.get_child_count() > 0:
		grid.get_child(0).set_meta("uz_default", true)


# --- Kategorien ----------------------------------------------------------------------------------

func _build_games() -> void:
	if Twitch.games.is_empty():
		var loading: bool = Twitch.games_loading
		add_child(empty_state("Kategorien werden geladen" if loading else "Gerade keine Kategorien", "Spiele und Themen, in denen gerade am meisten los ist.", [
			["Neu laden", "refresh", func() -> void: Twitch.refresh_games(true)],
		], "laden" if loading else "fehler"))
		return
	var col := _scroll_page()
	col.add_child(_page_head("%s  ·  meiste Zuschauer zuerst" % U.plural(Twitch.games.size(), "Kategorie", "Kategorien")))
	var m := U.margin(GUTTER, 22, GUTTER, 80)
	var grid := _game_grid(Twitch.games, "sgrid:kategorien")
	m.add_child(grid)
	col.add_child(m)
	if grid.get_child_count() > 0:
		grid.get_child(0).set_meta("uz_default", true)


# --- Suche ---------------------------------------------------------------------------------------

func _build_search() -> void:
	var col := _scroll_page()
	var top := U.margin(GUTTER, 0, GUTTER, 8)
	var row := U.hbox(14)
	row.set_meta("uz_group", "ssuche-kopf")
	top.add_child(row)
	var btn := U.button(_query if _query != "" else "Kanäle, Streams und Kategorien suchen", "search")
	if _query != "":
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Eingetipptes: nie übersetzen
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(720, 64)
	var sb := UzTheme.box(UzTheme.col("glass_hi"), 999, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 26
	sb.content_margin_right = 30
	btn.add_theme_stylebox_override("normal", sb)
	var fb := UzTheme.focus_fill(999)
	fb.content_margin_left = 26
	fb.content_margin_right = 30
	btn.add_theme_stylebox_override("focus", fb)
	btn.add_theme_font_override("font", UzTheme.font("medium"))
	if _query == "":
		btn.add_theme_color_override("font_color", UzTheme.col("muted"))
	btn.set_meta("uz_key", "ssuche:knopf")
	btn.set_meta("uz_hint_a", "Bildschirmtastatur" if _query == "" else "Neu suchen")
	btn.pressed.connect(_ask_search)
	row.add_child(btn)
	for q in _recent.slice(0, 5):
		if str(q) == _query:
			continue
		var chip := U.button(str(q), "history")
		chip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		chip.custom_minimum_size.y = 64
		chip.set_meta("uz_key", "ssuche:" + str(q))
		chip.set_meta("uz_hint_a", "Suchen")
		var qq := str(q)
		chip.pressed.connect(func() -> void: _run_search(qq))
		row.add_child(chip)
	col.add_child(top)
	var first: Control = null
	if _searching:
		var m := U.margin(GUTTER, 34, GUTTER, 0)
		m.add_child(U.label("Suche nach „%s“ …" % _query, "l", "muted"))
		col.add_child(m)
	elif _query != "":
		var chans: Array = _found.get("channels", [])
		var streams: Array = _found.get("streams", [])
		var games: Array = _found.get("games", [])
		if chans.is_empty() and streams.is_empty() and games.is_empty():
			var m2 := U.margin(GUTTER, 34, GUTTER, 0)
			var box := U.vbox(10)
			m2.add_child(box)
			box.add_child(U.label("Nichts gefunden", "xl", "text", "bold"))
			box.add_child(
					U.label(str(_found.get("error", "")) if str(_found.get("error", "")) != ""
					else "Für „%s“ gibt es keine Kanäle oder Kategorien. Ein anderes Wort oder weniger Wörter helfen oft." % _query, "l", "muted", "regular", true))
			col.add_child(m2)
		if not chans.is_empty():
			var tm := U.margin(0, 22, 0, 0)
			tm.add_child(section_title("Kanäle", U.plural(chans.size(), "Kanal", "Kanäle")))
			col.add_child(tm)
			var grid := GridContainer.new()
			grid.columns = U.cols_for(8)
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 22)
			grid.set_meta("uz_group", "ssuche:kanaele")
			for ch in chans:
				grid.add_child(_channel_tile(ch))
			var m3 := U.margin(GUTTER - 41, 18, 0, 10)
			m3.add_child(grid)
			col.add_child(m3)
			first = grid.get_child(0)
		if not streams.is_empty():
			var tm2 := U.margin(0, 26, 0, 0)
			tm2.add_child(section_title("Gerade live", U.plural(streams.size(), "Stream", "Streams")))
			col.add_child(tm2)
			var m4 := U.margin(GUTTER, 26, GUTTER, 10)
			var sg := _grid(streams, "sgrid:suche")
			m4.add_child(sg)
			col.add_child(m4)
			if first == null:
				first = sg.get_child(0)
		if not games.is_empty():
			var tm3 := U.margin(0, 26, 0, 0)
			tm3.add_child(section_title("Kategorien", U.plural(games.size(), "Kategorie", "Kategorien")))
			col.add_child(tm3)
			var m5 := U.margin(GUTTER, 26, GUTTER, 80)
			var gg := _game_grid(games, "sgrid:suche-kat")
			m5.add_child(gg)
			col.add_child(m5)
			if first == null:
				first = gg.get_child(0)
	elif not Twitch.games.is_empty():
		# Leere Suche: statt einer leeren Fläche die beliebtesten Kategorien.
		var tm4 := U.margin(0, 30, 0, 0)
		tm4.add_child(section_title("Zum Stöbern", "beliebte Kategorien"))
		col.add_child(tm4)
		var m6 := U.margin(GUTTER, 26, GUTTER, 80)
		m6.add_child(_game_grid(Twitch.games, "sgrid:ideen", 12))
		col.add_child(m6)
	if first:
		first.set_meta("uz_default", true)
	else:
		btn.set_meta("uz_default", true)


func _channel_tile(ch: Dictionary) -> Control:
	var t = ChannelTile.new()
	t.setup({ "id": "tw:" + str(ch.login), "title": str(ch.title), "thumb": str(ch.get("thumb", "")) }, 0, 128)
	t.set_meta("uz_hint_a", "Kanal öffnen")
	t.chosen.connect(func(_c: Dictionary) -> void: main.open_stream_channel(str(ch.login), str(ch.title)))
	return t


## Von der globalen Suche: gleich mit diesem Suchwort suchen (der Bereich steht schon auf „Suche“).
func search_for(q: String) -> void:
	_run_search(q)


func _ask_search() -> void:
	main.open_keyboard("Twitch durchsuchen", _query, func(t: String) -> void:
		if t.strip_edges() != "":
			_run_search(t)
	)


func _run_search(q: String) -> void:
	_query = q.strip_edges()
	_recent.erase(_query)
	_recent.push_front(_query)
	_searching = true
	_found = {}
	build()
	var found: Dictionary = await Twitch.search(_query)
	# Inzwischen neu gesucht: Die ältere Antwort gehört nicht unter das neue Suchwort (und die neue Suche läuft noch).
	if q.strip_edges() != _query:
		return
	_found = found
	_searching = false
	if visible and sub == "suche":
		build()
		await get_tree().process_frame
		focus_default()


## Karte zum Anmelden (ohne Anmeldung in der Reihe der gefolgten Kanäle): ruhige Glasfläche mit
## QR-Zeichen, Überschrift und Satz. Gewählt wie die Karten daneben: der eine Cursor der Kacheln.
class _PromptCard extends Control:
	signal chosen
	const Liste := preload("res://src/ui/components/liste.gd")
	var nav_ud_cb: Callable
	var _w := 0.0
	var _h := 0.0
	var _head := ""
	var _text := ""
	var _focus_t := 0.0
	var _tw: Tween

	func setup(w: float, h: float, head: String, text: String) -> void:
		_w = w
		_h = h
		_head = head
		_text = text

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(_w, _h + 102)
		var row := U.hbox(30)
		row.position = Vector2(40, 0)
		row.size = Vector2(_w - 80, _h)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var disc := PanelContainer.new()
		disc.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("accent", 0.16), 999))
		disc.custom_minimum_size = Vector2(96, 96)
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(U.icon("qr", 44, "accent"))
		disc.add_child(cc)
		row.add_child(disc)
		var col := U.vbox(8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		col.add_child(U.label(_head, "l", "text", "bold"))
		var t := U.label(_text, "m", "muted", "regular", true)
		t.custom_minimum_size = Vector2(_w - 80 - 126, 0)
		col.add_child(t)
		focus_entered.connect(_on_focus.bind(true))
		focus_exited.connect(_on_focus.bind(false))

	## Cursor-Takt wie jede Kachel (Liste.takt: im ersten Bild 70 %, dann gesetzt).
	func _on_focus(on: bool) -> void:
		Liste.takt(self, _focus_t, on, func(v: float) -> void:
			_focus_t = v
			queue_redraw())

	func press_feedback() -> void:
		_focus_t = 1.0
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(0, 0, _w, _h)
		# Matte Fläche mit Lichtkante oben (UzTheme.flaeche) – keine Kontur rundherum.
		draw_style_box(UzTheme.flaeche(UzTheme.col("glass_hi"), UzTheme.r_cover()), r)
		if _focus_t <= 0.01:
			return
		UzTheme.draw_tile_focus(self, r, UzTheme.r_cover(), clampf(_focus_t, 0.0, 1.0))

	func nav_ud(d: int) -> bool:
		return bool(nav_ud_cb.call(d)) if nav_ud_cb.is_valid() else false

	func nav_lr(d: int) -> bool:
		Nav._bump(self, "left" if d < 0 else "right")
		return true

	func activate() -> void:
		chosen.emit()

	func _gui_input(e: InputEvent) -> void:
		Nav.klick(self, e)
