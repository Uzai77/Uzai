extends "res://src/ui/sections/medien_bereich.gd"
## Videos (YouTube ohne Werbung).
##
## Für dich: die Bühne (medien_buehne.gd) zeigt das Video, auf dem man steht – großes Bild oben
## rechts im Raum, unten links Grund, Titel, Kanal und die Tasten als Pillen –, darunter die Reihen
## (medien_reihen.gd): Weiterschauen zuerst, dann die Startseite von YouTube bzw. Empfohlen, Neu von
## deinen Abos, Angesagt, Merkliste. Die Reihen rasten beim Blättern unter der Bühne ein.
## Neu: alles Neue deiner Abos, nach Tagen sortiert. Shorts: die Hochkant-Videos deiner Abos als
## hohe Karten, A spielt sie nacheinander (im Player hoch/runter blättern). Abos: Kanäle als runde
## Bilder. Dazu Suche, Merkliste, Verlauf und – mit Google-Konto – Playlists.

const VideoCard := preload("res://src/ui/components/video_card.gd")
const ChannelTile := preload("res://src/ui/components/channel_tile.gd")
const MedienBuehne := preload("res://src/ui/components/medien_buehne.gd")
const MedienReihen := preload("res://src/ui/components/medien_reihen.gd")
const Ladezeit := preload("res://src/core/ladezeit.gd")

const CARD_W := 320.0          ## alte Kartenbreite (für Aufrufer von außen)
const ROW_W := 352.0           ## Karten in den Reihen unter der Bühne
const GRID_W := 408.0          ## Karten in Rastern: vier Spalten
const GRID_GAP := 32
const SHORT_W := 261.0         ## Shorts: sechs hohe Karten in derselben Breite wie vier breite

var _results: Array = []
var _live_results: Array = []   ## Suche: was zum Suchwort gerade live ist (eine Reihe über den Ergebnissen)
var _query := ""
var _searching := false
var _setup_label: Label
var _setup_bar = null
var _bg_key := ""
var _stale_what := {}          ## Änderungen, die kamen, während etwas darüber lag
# Für dich
var _buehne = null             ## medien_buehne.gd
var _weights := {}
var _tv_rows_n := 0            ## Reihen der YouTube-Startseite, die schon stehen
var _tv_end := 0               ## Stelle hinter der letzten Reihe der Startseite (dort kommen weitere hin)


func _init() -> void:
	super()
	id = "videos"
	title = "Videos"
	icon_name = "video"
	YouTube.changed.connect(_on_changed)
	YouTube.tools_progress.connect(_on_tools_progress)
	keep_built = true
	stale_keys = PackedStringArray(["youtube.", "accounts."])
	# Nur der Ladezustand (ohne neue Videos) macht die Seite nicht alt: sonst baute jeder
	# Besuch von Videos alles neu, sobald im Hintergrund ein Abruf startet oder endet.
	YouTube.changed.connect(func(w: String) -> void:
		if not w.ends_with("_loading") or _wants_rebuild(w):
			mark_stale()
	)
	YouTube.tools_progress.connect(mark_stale)
	Nav.focus_moved.connect(_on_nav_focus)


func subtabs() -> Array:
	# Mit der Fernseher-Anmeldung (inoffiziell) ist das die echte Startseite von YouTube.
	var out: Array = [{ "id": "fuerdich", "label": "Startseite" if YouTube.tv.logged_in() else "Für dich" }]
	var neu := { "id": "start", "label": "Neu" }
	var fresh := fresh_count(YouTube.feed, int(Time.get_unix_time_from_system()), int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	if fresh > 0:
		neu["count"] = fresh
	out.append(neu)
	if Config.get_value("youtube.shorts_tab", true) and not (YouTube.data.subs as Array).is_empty():
		out.append({ "id": "shorts", "label": "Shorts" })
	out.append({ "id": "abos", "label": "Abos", "count": (YouTube.data.subs as Array).size() })
	out.append({ "id": "suche", "label": "Suche" })
	if not (YouTube.data.later as Array).is_empty():
		out.append({ "id": "merkliste", "label": "Merkliste", "count": (YouTube.data.later as Array).size() })
	if not (YouTube.data.history as Array).is_empty():
		out.append({ "id": "verlauf", "label": "Verlauf" })
	if YouTube.logged_in():
		out.append({ "id": "playlists", "label": "Playlists" })
	return out


## Wie viele Videos der Abos heute kamen (Zahl am Reiter „Neu“, passt zur Gruppe „Heute“).
static func fresh_count(feed: Array, now: int, bias := 0) -> int:
	var n := 0
	for v in feed:
		var pub := int(v.get("published", 0))
		if pub > 0 and day_group(pub, now, bias) == 0:
			n += 1
	return n


## Menü-Taste in Videos: alles neu holen (Abos, Empfehlungen, Startseite, Shorts, Abo-Liste).
func menu_taste() -> bool:
	if sub == "suche":
		return false
	YouTube.refresh_feed(true)
	YouTube.refresh_recs(true)
	YouTube.tv.refresh_home(true)
	if sub == "shorts":
		YouTube.refresh_shorts(true)
	if sub == "abos":
		YouTube.tv.refresh_subs(true)
	if sub == "playlists":
		YouTube.load_playlists()
	Toasts.show_toast("Wird neu geladen", "", "refresh", { "quiet": true, "ms": 1800 })
	return true


## Unten in der Tastenzeile: Menü lädt neu.
func extra_hints(_f: Control) -> Array:
	return [] if sub == "suche" else [["menu", "Neu laden"]]


func on_enter() -> void:
	YouTube.refresh_feed()
	YouTube.refresh_recs()
	YouTube.tv.refresh_home()
	# Abo-Feed der Fernseher-Anmeldung (höchstens alle 20 Minuten): Nur er sagt, wer gerade live ist.
	# Bisher kam er nur beim Start von Uzai – Livestreams von später fehlten, beendete blieben stehen.
	YouTube.tv.refresh_subs()
	if sub == "playlists":
		YouTube.load_playlists()


## Beim Start (main._prebuild): Abos und Empfehlungen (YouTube.start fragt sie meist schon).
func prefetch() -> void:
	YouTube.refresh_feed()
	YouTube.refresh_recs()
	YouTube.tv.refresh_home()


func data_ready() -> bool:
	return not YouTube.feed_loading and not YouTube.recs_loading and not YouTube.tv.home_loading


func _on_changed(what: String) -> void:
	if not visible or not is_inside_tree():
		return
	if Nav.top_layer() != null or Video.active:
		# Ein Menü oder der Player liegt darüber: danach nachholen (siehe _on_nav_focus).
		_stale_what[what] = true
		return
	if what == "tvhome_more":
		_append_tv_rows()
		return
	if _wants_rebuild(what):
		_rebuild_keep()
	else:
		_refresh_cards()
	Ladezeit.pruefen(self)


## Für die Ladezeit (src/core/ladezeit.gd): steht schon Inhalt, ist alles geladen? Inhalt, der
## schon steht, während noch geladen wird, kam aus dem gemerkten Stand.
func lade_stand() -> Dictionary:
	var laedt := _laedt()
	return { "inhalt": _hat_inhalt(), "fertig": not laedt, "quelle": "gemerkt" if laedt else "frisch" }


func _laedt() -> bool:
	match sub:
		"fuerdich": return YouTube.feed_loading or YouTube.recs_loading or YouTube.tv.home_loading
		"start": return YouTube.feed_loading
		# Die Shorts holt erst der Aufbau (verzögert): alt oder leer heißt, es kommt gleich noch etwas.
		"shorts": return YouTube.shorts_loading or YouTube.shorts_due()
	return false


func _hat_inhalt() -> bool:
	if _reihen != null and is_instance_valid(_reihen):
		return _reihen.row_count() > 0
	return find_children("*", "Control", true, false).any(func(c: Node) -> bool: return c.has_method("refresh_state"))


## Ändert sich durch diese Daten, was auf der Seite steht (nicht nur ein Abzeichen)?
func _wants_rebuild(what: String) -> bool:
	match what:
		"feed", "lists": return sub in ["start", "playlists", "fuerdich"]
		"recs": return sub == "fuerdich"
		# Nur der Ladezustand: neu bauen, wo er zu sehen ist („wird aktualisiert …“, leere Seite).
		"feed_loading": return sub == "start"
		"shorts": return sub == "shorts"
		"shorts_loading": return sub == "shorts" and YouTube.shorts.is_empty()
		"recs_loading": return sub == "fuerdich" and YouTube.recs.is_empty() and not YouTube.tv.active()
		"tvhome": return sub == "fuerdich"
		"tvhome_loading": return sub == "fuerdich" and YouTube.recs.is_empty() and not YouTube.tv.active()
		"subs": return sub in ["start", "abos", "fuerdich"]
		# Abos der Fernseher-Anmeldung kamen nicht (oder sind da): nur die leere Abo-Seite neu.
		"tvsubs": return sub in ["abos", "start"] and (YouTube.data.subs as Array).is_empty()
		"later": return sub == "merkliste"
		"history": return sub in ["verlauf", "fuerdich"]
		"tools", "account": return true
	return false


func _on_nav_focus(_c: Control) -> void:
	if _stale_what.is_empty() or not visible or not is_inside_tree() or Nav.top_layer() != null or Video.active:
		return
	var whats: Array = _stale_what.keys()
	_stale_what.clear()
	if "tvhome_more" in whats:
		_append_tv_rows()
	if whats.any(func(w: Variant) -> bool: return _wants_rebuild(str(w))):
		_rebuild_keep()
	else:
		_refresh_cards()
	if main:
		main.refresh_chips()


## Bereich neu betreten (LT/RT): ganz nach oben – erste Reihe unter der Bühne, alle Reihen wieder
## am Anfang, die Bühne zeigt wieder das erste Video. Ohne Neuaufbau blieb die Seite sonst an der
## alten Reihe stehen.
func reset_position() -> void:
	super()
	if _reihen == null or not is_instance_valid(_reihen):
		return
	_reihen.reset()
	var first: Control = _reihen.first_card()
	if first and first.get("video") is Dictionary:
		_zeige(first.get("video"), 0, first)


func reenter() -> void:
	_bg_key = ""      # main.goto hat das Hintergrundbild gelöscht: zur gewählten Karte neu setzen
	# Das Bild zum gezeigten Video gleich setzen (nicht erst, wenn eine Karte gewählt wird).
	if _buehne != null and is_instance_valid(_buehne):
		_buehne.wieder()


func on_leave() -> void:
	if _buehne != null and is_instance_valid(_buehne):
		_buehne.verlassen()


func build() -> void:
	mark_built()
	U.clear(self)
	_setup_label = null
	_buehne = null
	_reihen = null
	_bg_key = ""
	_tv_rows_n = 0
	_tv_end = 0
	_stale_what.clear()
	_weights = YouTube.channel_weights(YouTube.data.history, YouTube.data.later)
	match sub:
		"fuerdich": _build_foryou()
		"start": _build_new()
		"shorts": _build_shorts()
		"abos": _build_abos()
		"suche": _build_search()
		"merkliste": _build_grid(YouTube.data.later, "Noch nichts gemerkt", "X auf einem Video merkt es sich für später.")
		"verlauf": _build_grid(YouTube.data.history, "Noch nichts angesehen", "Gesehene Videos erscheinen hier.")
		"playlists": _build_playlists()
		_: _build_foryou()


# --- Bausteine ---------------------------------------------------------------------------------

func _card(v: Dictionary, list: Array, idx: int, w := GRID_W, key := "", shorts := false) -> Control:
	var c = VideoCard.new()
	c.setup(v, w, true, shorts)
	c.key_prefix = key
	_card_hints(c, v)
	var opts := { "shorts": true } if shorts else {}
	c.set_meta("uz_on_x", func() -> void: _toggle_later(v))
	c.set_meta("uz_hint_y", "Optionen")
	c.set_meta("uz_on_y", func() -> void: main.open_video_options(v, list, idx, opts))
	c.chosen.connect(func(_v: Dictionary) -> void: main.open_video(list, idx, opts))
	c.focused_video.connect(_on_focused)
	c.focused_video.connect(_vorab_bald)
	return c


## Ruht die Auswahl VORAB_S auf einem Video, löst Uzai es schon auf (Video.vorab): A spielt dann
## sofort, ohne dass mpv erst yt-dlp starten muss.
const VORAB_S := 0.7
var _vorab_id := ""


func _vorab_bald(v: Dictionary) -> void:
	var want := str(v.get("id", ""))
	_vorab_id = want
	get_tree().create_timer(VORAB_S).timeout.connect(func() -> void:
		if _vorab_id == want and visible and is_inside_tree() and not Video.active and Nav.top_layer() == null:
			Video.vorab(v)
	)


func _card_hints(c: Control, v: Dictionary) -> void:
	var resume := YouTube.resume_pos(str(v.get("id", "")))
	c.set_meta("uz_hint_a", ("Weiterschauen ab " + YouTube.time_text(resume)) if resume > 20 else "Abspielen")
	c.set_meta("uz_hint_x", "Nicht mehr merken" if YouTube.in_later(str(v.get("id", ""))) else "Merken")


## Hintergrund: der Raum nimmt die Farbe des gewählten Videos an (Raster-Seiten; auf „Für dich“
## malt die Bühne den Raum).
func _on_focused(v: Dictionary) -> void:
	var key := str(v.get("id", ""))
	if _buehne != null and is_instance_valid(_buehne):
		return
	# Unsichtbar vorgebaut (main._prebuild): den Hintergrund der Startseite nicht anfassen.
	if key == _bg_key or main == null or main.background == null or not visible:
		return
	_bg_key = key
	var poster := VideoCard.poster_texture(v)
	var url := VideoCard.thumb_url(v)
	if url == "":
		main.background.show_blurred(poster, "yt:" + key)
		return
	# Dieselbe Breite wie die Karte (VideoCard lädt 480): das Bild liegt dann schon bereit und
	# kommt sofort, statt ein zweites Mal dekodiert zu werden.
	Media.url_texture(url, 480, func(t: Texture2D) -> void:
		# Noch der gewählte Bereich? Beim Verlassen bleibt er während des Ausblendens sichtbar –
		# ein spät geladenes Vorschaubild läge sonst auf dem Hintergrund der Startseite.
		if _bg_key == key and visible and main and main.current == id and is_instance_valid(main.background):
			main.background.show_blurred(t if t else poster, "yt:" + key)
	)


func _toggle_later(v: Dictionary) -> void:
	var on := YouTube.toggle_later(v)
	Toasts.show_toast("Gemerkt" if on else "Nicht mehr gemerkt", str(v.get("title", "")), "bookmark_f" if on else "bookmark", { "sound": "select", "quiet": true })
	_refresh_cards()
	if main:
		main.refresh_chips()


## Abzeichen, Hinweise und die Bühne auf den neuesten Stand bringen (ohne Neuaufbau).
func _refresh_cards() -> void:
	for c in find_children("*", "Control", true, false):
		if c.has_method("refresh_state"):
			c.call("refresh_state")
			var v: Variant = c.get("video")
			if v is Dictionary and c.has_meta("uz_on_x"):
				_card_hints(c as Control, v)
	if _buehne != null and is_instance_valid(_buehne) and not _buehne.item.is_empty():
		var f := Nav.focused()
		_zeige(_buehne.item, 0, f if f and f.get("video") is Dictionary and str(f.get("video").get("id", "")) == str(_buehne.item.get("id", "")) else null)
	Nav.focus_moved.emit(Nav.focused())


func _grid(list: Array, group: String, start := 0, count := -1) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = U.cols_for(4)
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", 40)
	grid.set_meta("uz_group", group)
	var end := list.size() if count < 0 else mini(list.size(), start + count)
	for i in range(start, end):
		_grid_add(grid, _card(list[i], list, i, GRID_W, group + ":"))
	return grid


## Karte ins Raster: Bilder laden nur die ersten GRID_ROWS_NOW Zeilen gleich, die übrigen, wenn
## die Auswahl in ihre Nähe kommt (Shorts: bis 120 Karten – früher alle Bilder auf einmal).
const GRID_ROWS_NOW := 3
const KARTEN_SOFORT := 16       ## Verlauf und Merkliste: so viele Karten sofort (vier Reihen) …
const KARTEN_JE_BILD := 16      ## … der Rest in Scheiben (U.in_scheiben); eine Karte kostet rund 0,6 ms


func _grid_add(grid: GridContainer, c: Control) -> void:
	_grid_karte(grid, c)
	grid.add_child(c)


## Karte fürs Raster vorbereiten, ohne sie einzuhängen (sie kommt als nächste hinein).
func _grid_karte(grid: GridContainer, c: Control) -> void:
	var i := grid.get_child_count()
	var cols := maxi(1, grid.columns)
	if i >= cols * GRID_ROWS_NOW:
		c.set("lazy", true)
	c.focus_entered.connect(func() -> void:
		if not is_instance_valid(grid):
			return
		var at := c.get_index()
		for j in range(maxi(0, at - cols), mini(grid.get_child_count(), at + cols * GRID_ROWS_NOW)):
			var n := grid.get_child(j)
			if n.get("lazy") == true:
				n.call("wake")
	)


func _build_grid(list: Array, empty_head: String, empty_text: String) -> void:
	if list.is_empty():
		add_child(empty_state(empty_head, empty_text, [["Zu „Für dich“", "home", func() -> void: main.goto("videos", "fuerdich")]]))
		return
	var col := _scroll_page()
	var btn: Control = null
	if sub == "verlauf":
		btn = U.button("Verlauf löschen", "trash")
		btn.set_meta("uz_key", "verlauf:loeschen")
		(btn as Button).pressed.connect(func() -> void:
			main.open_dialog("Verlauf löschen?", "Gesehene Videos und Stellen werden gelöscht.", [
				["Löschen", func() -> void: YouTube.clear_history()],
				["Abbrechen", func() -> void: pass],
			])
		)
	var head := U.plural(list.size(), "Video", "Videos") + ("  ·  zuletzt gesehen zuerst" if sub == "verlauf" else "  ·  zuletzt gemerkt zuerst")
	col.add_child(_page_head(head, btn))
	var m := U.margin(GUTTER, 22, GUTTER, 80)
	var group := "vgrid:" + sub
	var grid := _grid([], group)
	m.add_child(grid)
	col.add_child(m)
	# Viele Karten (Verlauf bis 400, Merkliste ohne Grenze): die ersten Reihen sofort, der Rest in Scheiben – 400
	# Karten in einem Zug hielten das Bild beim Öffnen rund 240 ms an (gemessen). Nach einem Neuaufbau geht es ohne
	# Pause bis zur gewählten Karte. Mit einer Kopie der Liste: Sie kann sich ändern, solange noch gebaut wird.
	var liste: Array = list.duplicate()
	var halte := _halte_key
	var bis := Callable()
	if halte.begins_with("v:" + group + ":"):
		bis = func(c: Node) -> bool: return str(c.get_meta("uz_key", "")) == halte
	var baue := func(i: int) -> Control:
		var c := _card(liste[i], liste, i, GRID_W, group + ":")
		if i == 0:
			c.set_meta("uz_default", true)
		_grid_karte(grid, c)
		return c
	U.in_scheiben(grid, liste.size(), baue, KARTEN_SOFORT, KARTEN_JE_BILD, bis)


# --- Für dich ----------------------------------------------------------------------------------

func _build_foryou() -> void:
	if not YouTube.tools_ready():
		_build_setup()
		return
	# Mit der Fernseher-Anmeldung zuerst die echte Startseite von YouTube (ihre Reihen); klappt sie
	# nicht, bleibt alles wie ohne: Uzais Mischung, Abos, Angesagtes – mit einem kleinen Hinweis.
	var tv_on: bool = YouTube.tv.active()
	if not tv_on and YouTube.recs.is_empty():
		_build_foryou_empty()
		return
	_buehne = MedienBuehne.new().setup(self, main)
	add_child(_buehne)
	_reihen = MedienReihen.new().setup(MedienBuehne.H)
	_reihen.instant = _instant
	_reihen.row_focused.connect(_on_row_card)
	add_child(_reihen)
	# Keine Reihe „Weiterschauen“ mehr (Wunsch zu 0.16.56): YouTubes eigene Startseite steht gleich oben.
	# Angefangene Videos setzen weiter dort fort, wo sie standen (A auf der Karte), und stehen im Verlauf.
	var tv_hint := tv_hint_text(YouTube.tv.logged_in(), tv_on, str(YouTube.tv.home_error))
	if tv_on:
		var shelves: Array = YouTube.tv.shelves
		for i in shelves.size():
			_add_row(str(shelves[i].title), tv_hint if i == 0 and tv_hint != "" else ("von YouTube" if i == 0 else ""), shelves[i].items, "tv%d" % i, 30)
			_tv_rows_n += 1
			_tv_end = _reihen.row_count()
	elif not YouTube.recs.is_empty():
		var extra := "von YouTube" if YouTube.recs_source == "youtube" else ""
		_add_row("Empfohlen", tv_hint if tv_hint != "" else extra, YouTube.recs, "fuerdich", 30)
	# Livestreams der Abos in einer eigenen Reihe (sie haben kein Alter und gehören nicht unter „Neu“).
	var lives := YouTube.nur_live(YouTube.feed)
	if not lives.is_empty():
		_add_row("Gerade live", "von deinen Abos", lives, "live", 30)
	var neu := YouTube.feed.filter(func(v: Variant) -> bool: return not lives.has(v))
	if not neu.is_empty():
		_add_row("Neu von deinen Abos", U.plural((YouTube.data.subs as Array).size(), "Kanal", "Kanäle"), neu, "neu", 20)
	if not YouTube.trending.is_empty():
		_add_row("Angesagt", region_name(str(Config.get_value("youtube.region", "DE"))), YouTube.trending, "trends")
	if not (YouTube.data.later as Array).is_empty():
		_add_row("Merkliste", "", YouTube.data.later, "merk")
	var first: Control = _reihen.first_card()
	if first:
		first.set_meta("uz_default", true)
		if first.get("video") is Dictionary:
			_zeige(first.get("video"), 0, first)


## Eine Reihe unter der Bühne. at: an dieser Stelle einfügen (weitere Reihen der Startseite), sonst
## ans Ende. Die Karten fragen ihre Reihe beim Blättern nach, darum stimmt die Steuerung auch nach
## dem Einfügen.
func _add_row(head: String, extra: String, list: Array, group: String, limit := 30, at := -1) -> void:
	var row: Dictionary = _reihen.add_row(head, extra, "v:" + group, round(ROW_W * 9.0 / 16.0) + 102, MedienReihen.GAP, at)
	for i in mini(list.size(), limit):
		_reihen.add_card(row, _card(list[i], list, i, ROW_W, group + ":"), list[i])


## Weitere Reihen der Startseite kamen (Weiterblättern): hinter die letzte Reihe von YouTube.
func _append_tv_rows() -> void:
	if sub != "fuerdich" or _reihen == null or not is_instance_valid(_reihen) or _tv_rows_n == 0:
		return
	var shelves: Array = YouTube.tv.shelves
	while _tv_rows_n < shelves.size():
		_add_row(str(shelves[_tv_rows_n].title), "", shelves[_tv_rows_n].items, "tv%d" % _tv_rows_n, 30, _tv_end)
		_tv_rows_n += 1
		_tv_end += 1


## Kleiner Hinweis, wenn die Startseite von YouTube gerade nicht kommt ("" wenn alles gut ist).
static func tv_hint_text(logged_in: bool, showing: bool, error: String) -> String:
	if not logged_in or error == "":
		return ""
	if showing:
		return "Stand von vorhin – YouTube gerade nicht erreichbar"
	return "Startseite nicht verfügbar. Abos und Mix."


## Eine Karte in einer Reihe ist gewählt: die Bühne zeigt sie; unten angekommen fragt Uzai YouTube
## nach weiteren Reihen (wie beim Blättern auf YouTube).
func _on_row_card(idx: int, c: Control, v: Dictionary, dir: int) -> void:
	if _tv_end > 0 and idx >= _tv_end - 2 and idx < _tv_end and YouTube.tv.has_more():
		YouTube.tv.more_home()
	if not v.is_empty():
		_zeige(v, dir, c)


## Die Bühne zu einem Video: Grund, Titel, Kanal · Aufrufe · Alter, die Tasten der Karte; das
## große Bild (maxres, sonst hq) und die Nachbarn zum Vorladen.
func _zeige(v: Dictionary, dir: int, card: Control) -> void:
	if _buehne == null or not is_instance_valid(_buehne):
		return
	var text := { "grund": reason_for(v), "titel": str(v.get("title", "")), "zeile": buehne_zeile(v), "tasten": MedienBuehne.tasten_von(card) }
	var vid := str(v.get("id", ""))
	var bild := { "key": "yt:" + vid, "urls": big_urls(v), "ph": VideoCard.poster_texture(v), "warm": [] }
	if card != null and is_instance_valid(card) and card.get_parent():
		var i := card.get_index()
		for j in [i + 1, i - 1]:
			var n := card.get_parent().get_child(j) if j >= 0 and j < card.get_parent().get_child_count() else null
			if n and n.get("video") is Dictionary:
				var nu := big_urls(n.get("video"))
				if not nu.is_empty():
					(bild.warm as Array).append(nu)
	_buehne.zeige(v, dir, text, bild)


## Die leise Zeile der Bühne: Kanal, dann Restzeit (angefangen) oder Aufrufe und Alter.
static func buehne_zeile(v: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(v.get("channel", "")) != "":
		parts.append(str(v.channel))
	var resume := YouTube.resume_pos(str(v.get("id", "")))
	var dur := int(v.get("duration", 0))
	if resume > 20 and dur > resume:
		parts.append(VideoCard.left_text(dur - resume))
	else:
		var vt := YouTube.views_text(int(v.get("views", 0)))
		if vt != "":
			parts.append(vt)
		if int(v.get("published", 0)) > 0:
			parts.append(U.ago(int(v.published)))
	return VideoCard.SEP.join(parts)


## Große Bilder eines Videos für die Bühne, das beste zuerst: maxresdefault (nicht jedes Video hat
## es), dann hqdefault; eigene Adressen (Streams, Vorführung) wie sie sind.
static func big_urls(v: Dictionary) -> Array:
	var id := str(v.get("id", ""))
	if YouTube.demo:
		var local := VideoCard.thumb_url(v)
		return [local] if local != "" else []
	if id.length() == 11 and not id.contains(":"):
		return ["https://i.ytimg.com/vi/%s/maxresdefault.jpg" % id, YouTube.thumb_for(id, true)]
	var own := str(v.get("thumb", ""))
	return [own] if own != "" else []


## Ein echter Grund, warum dieses Video oben steht – oder keiner.
func reason_for(v: Dictionary) -> Array:
	var vid := str(v.get("id", ""))
	if bool(v.get("live", false)):
		return ["Gerade live", "live"]
	var cid := str(v.get("channel_id", ""))
	var ch := str(v.get("channel", ""))
	var pub := int(v.get("published", 0))
	var now := int(Time.get_unix_time_from_system())
	if cid != "" and YouTube.is_subscribed(cid) and pub > 0 and now - pub < 3 * 86400:
		return ["Neu von " + ch, "bell"]
	if str(v.get("src", "")) == "tv":
		return ["Empfohlen von YouTube", "spark"]
	for t in YouTube.trending:
		if str(t.get("id", "")) == vid:
			return ["Angesagt in %s" % region_name(str(Config.get_value("youtube.region", "DE"))), "bolt"]
	if cid != "" and float(_weights.get(cid, 0.0)) >= 1.0 and ch != "":
		return ["Weil du oft %s schaust" % ch, "heart"]
	if YouTube.in_later(vid):
		return ["Auf deiner Merkliste", "bookmark_f"]
	if YouTube.recs_source == "youtube":
		return ["Empfohlen von YouTube", "spark"]
	if int(v.get("views", 0)) >= 500000:
		return ["Viel gesehen", "eye"]
	return []


static func region_name(code: String) -> String:
	match code.to_upper():
		"DE": return "Deutschland"
		"AT": return "Österreich"
		"CH": return "der Schweiz"
		"US": return "den USA"
		"GB": return "Großbritannien"
	return code


func _build_foryou_empty() -> void:
	if YouTube.recs_loading or YouTube.tv.home_loading:
		# Platzhalter in der Form der Bühne und der ersten Reihen: wenn die Videos kommen, springt nichts.
		add_child(MedienReihen.skeleton(MedienBuehne.H, Vector2(ROW_W, round(ROW_W * 9.0 / 16.0) + 102), 2))
		return
	if not YouTube.logged_in() and not YouTube.tv.logged_in():
		# Nicht angemeldet: die Bühne mit angedeuteten Videos; A meldet an (QR-Code wie am
		# Fernseher). Danach kommt die Startseite von YouTube im Takt herein.
		add_child(leer_buehne({ "art": "video", "symbol": "video", "titel": "Deine YouTube-Startseite.",
			"zeile": "Per QR-Code wie am Fernseher.", "knopf": "Anmelden", "tun": LeerBuehne.weg(main, "youtube"),
			"neben": "Kanäle suchen", "neben_tun": func() -> void: main.goto("videos", "suche"),
			"fertig": func() -> bool: return YouTube.logged_in() or YouTube.tv.logged_in() }))
		return
	var btns: Array = [["Kanäle suchen", "search", func() -> void: main.goto("videos", "suche")]]
	if not YouTube.logged_in():
		btns.append(["Mit Google anmelden", "qr", func() -> void: main.open_yt_login()])
	if not YouTube.tv.logged_in():
		btns.append(["Mit TV-Code anmelden", "user", func() -> void: main.open_layer(load("res://src/ui/layers/yt_tv_login.gd").new())])
	add_child(empty_state("Noch keine Empfehlungen", "Mit Anmeldung erscheinen hier Empfehlungen.", btns))


# --- Neu ---------------------------------------------------------------------------------------

## 0 heute, 1 gestern, 2 diese Woche, 3 älter (nach Ortszeit). bias in Sekunden.
static func day_group(pub: int, now: int, bias: int) -> int:
	var midnight := floori((now + bias) / 86400.0) * 86400
	var local := pub + bias
	if local >= midnight:
		return 0
	if local >= midnight - 86400:
		return 1
	if local >= midnight - 6 * 86400:
		return 2
	return 3


## Gruppe im Reiter „Neu“: 0 gerade live (ein Livestream hat kein Alter und stand sonst unter
## „Älter“), sonst 1 + day_group.
static func neu_gruppe(v: Dictionary, now: int, bias: int) -> int:
	if bool(v.get("live", false)):
		return 0
	return 1 + day_group(int(v.get("published", 0)), now, bias)


func _build_new() -> void:
	if not YouTube.tools_ready():
		_build_setup()
		return
	if (YouTube.data.subs as Array).is_empty() and YouTube.feed.is_empty():
		add_child(_no_subs())
		return
	if YouTube.feed.is_empty():
		add_child(
				empty_state("Neue Videos werden geladen" if YouTube.feed_loading else "Gerade nichts Neues",
				"Neue Videos deiner Abos: %s." % U.plural((YouTube.data.subs as Array).size(), "Kanal", "Kanäle"), [
			["Abos ansehen", "channel", func() -> void: main.goto("videos", "abos")],
		], "laden" if YouTube.feed_loading else "leer"))
		return
	var col := _scroll_page()
	var info := "Neue Videos deiner %s" % U.plural((YouTube.data.subs as Array).size(), "Kanäle", "Kanäle")
	if (YouTube.data.subs as Array).size() == 1:
		info = "Neue Videos deines Kanals"
	if YouTube.feed_loading:
		info += "  ·  wird aktualisiert …"
	col.add_child(_page_head(info))
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var names := ["Gerade live", "Heute", "Gestern", "Diese Woche", "Älter"]
	var groups: Array = [[], [], [], [], []]
	for i in YouTube.feed.size():
		(groups[neu_gruppe(YouTube.feed[i], now, bias)] as Array).append(i)
	var first := true
	for g in names.size():
		var ids: Array = groups[g]
		if ids.is_empty():
			continue
		var tm := U.margin(0, 18 if first else 30, 0, 0)
		tm.add_child(section_title(str(names[g]), U.plural(ids.size(), "Video", "Videos")))
		col.add_child(tm)
		var grid := GridContainer.new()
		grid.columns = U.cols_for(4)
		grid.add_theme_constant_override("h_separation", GRID_GAP)
		grid.add_theme_constant_override("v_separation", 40)
		grid.set_meta("uz_group", "neu:%d" % g)
		for i in ids:
			grid.add_child(_card(YouTube.feed[int(i)], YouTube.feed, int(i), GRID_W, "neu:"))
		var m := U.margin(GUTTER, 26, GUTTER, 0)
		m.add_child(grid)
		col.add_child(m)
		if first and grid.get_child_count() > 0:
			grid.get_child(0).set_meta("uz_default", true)
		first = false
	col.add_child(U.spacer(0, 80, false))


# --- Shorts ------------------------------------------------------------------------------------

## Hohe Karten in sechs Spalten. Geholt wird erst hier (YouTube.refresh_shorts, alle 20 Minuten
## höchstens einmal) – nach dem Aufbau, damit dessen Ladesignal nicht mitten hinein baut.
func _build_shorts() -> void:
	if not YouTube.tools_ready():
		_build_setup()
		return
	if (YouTube.data.subs as Array).is_empty():
		add_child(_no_subs())
		return
	YouTube.refresh_shorts.call_deferred()
	var list: Array = YouTube.shorts
	if list.is_empty():
		add_child(
				empty_state("Shorts werden geladen" if YouTube.shorts_loading else "Keine Shorts",
				"Shorts deiner Abos. Hoch und runter blättert.", [
			["Abos ansehen", "channel", func() -> void: main.goto("videos", "abos")],
		], "laden" if YouTube.shorts_loading else "leer"))
		return
	var col := _scroll_page()
	var info := "Shorts deiner Abos  ·  neueste zuerst"
	if YouTube.shorts_loading:
		info += "  ·  wird aktualisiert …"
	col.add_child(_page_head(info))
	var grid := GridContainer.new()
	grid.columns = U.cols_for(6)
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", 40)
	grid.set_meta("uz_group", "shorts")
	for i in list.size():
		_grid_add(grid, _card(list[i], list, i, SHORT_W, "short:", true))
	var m := U.margin(GUTTER, 22, GUTTER, 80)
	m.add_child(grid)
	col.add_child(m)
	if grid.get_child_count() > 0:
		grid.get_child(0).set_meta("uz_default", true)


func _no_subs() -> Control:
	if not YouTube.logged_in() and not YouTube.tv.logged_in():
		return leer_buehne({ "art": "video", "symbol": "video", "titel": "Deine Abos von YouTube.",
			"zeile": "Ohne Konto: Kanäle suchen und hier abonnieren.", "knopf": "Anmelden", "tun": LeerBuehne.weg(main, "youtube"),
			"neben": "Kanäle suchen", "neben_tun": func() -> void: main.goto("videos", "suche"),
			"fertig": func() -> bool: return YouTube.logged_in() or YouTube.tv.logged_in() })
	var btns: Array = []
	if not YouTube.logged_in():
		btns.append(["Mit Google anmelden", "qr", func() -> void: main.open_yt_login()])
	btns.append(["Kanäle suchen", "search", func() -> void: main.goto("videos", "suche")])
	return empty_state("Noch keine Abos", "Anmelden oder Kanäle suchen.", btns)


# --- Einrichten --------------------------------------------------------------------------------

func _build_setup() -> void:
	var m := U.margin(GUTTER, 40, GUTTER, 40)
	var col := U.vbox(22)
	col.custom_minimum_size = Vector2(1100, 0)
	m.add_child(col)
	add_child(m)
	col.add_child(U.label("YouTube einrichten", "xxl", "text", "black"))
	var p := U.label("Einmaliger Download, etwa 150 MB.", "l", "muted", "regular", true)
	p.custom_minimum_size = Vector2(1100, 0)
	col.add_child(p)
	var list := U.vbox(12)
	for it in [["yt-dlp", "holt das Video von YouTube", YouTube.has_ytdlp()], ["mpv", "spielt das Video ab", YouTube.has_mpv()],
			["Deno", "damit yt-dlp alle Qualitätsstufen bekommt", YouTube.has_deno()]]:
		var row := U.hbox(18)
		var have := bool(it[2])
		var dot := U.panel("ok" if have else "glass_hi", 20, 0, 0.18 if have else 1.0)
		dot.custom_minimum_size = Vector2(40, 40)
		var ic := U.icon("check" if have else "download", 22, "ok" if have else "muted")
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_child(ic)
		row.add_child(dot)
		var nl := U.label(str(it[0]), "m", "text", "bold")
		nl.custom_minimum_size = Vector2(110, 0)
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nl)
		var dl := U.label(str(it[1]) + ("" if not have else "  ·  vorhanden"), "m", "muted")
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dl)
		list.add_child(row)
	col.add_child(list)
	_setup_label = U.label("Läuft …" if YouTube.setting_up else "", "m", "accent", "medium")
	col.add_child(_setup_label)
	_setup_bar = ProgressBarUz.new().setup(0.0, "accent", 8, 700)
	_setup_bar.visible = YouTube.setting_up
	col.add_child(_setup_bar)
	var row2 := U.hbox(16)
	row2.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(row2)
	var go := U.button("Jetzt einrichten", "download", "primary")
	go.set_meta("uz_default", true)
	go.pressed.connect(func() -> void:
		if YouTube.setting_up:
			return
		if _setup_bar != null and is_instance_valid(_setup_bar):
			_setup_bar.visible = true
		var err := await YouTube.setup_tools()
		Toasts.show_toast("YouTube ist bereit" if err == "" else "Einrichten nicht ganz geklappt", err, "video", { "sound": "select" if err == "" else "error" })
	)
	row2.add_child(go)
	var own := U.button("mpv selbst wählen", "file")
	own.pressed.connect(func() -> void:
		main.open_file_browser("mpv.exe wählen", false, func(path: String) -> void:
			Config.set_value("youtube.mpv", path)
			_rebuild_keep()
		, ["exe"])
	)
	row2.add_child(own)


func _on_tools_progress(text: String, frac: float) -> void:
	if is_instance_valid(_setup_label):
		_setup_label.text = text
	if _setup_bar != null and is_instance_valid(_setup_bar):
		_setup_bar.set_value(frac)


# --- Abos --------------------------------------------------------------------------------------

func _build_abos() -> void:
	var subs: Array = YouTube.data.subs
	var col := _scroll_page()
	var login: Control = null
	if not YouTube.logged_in():
		login = U.button("Mit Google anmelden", "qr")
		login.set_meta("uz_key", "abos:login")
		(login as Button).pressed.connect(func() -> void: main.open_yt_login())
	var acct := abos_kopf(YouTube.logged_in(), YouTube.account, YouTube.tv.logged_in(), subs.size())
	col.add_child(_page_head(acct, login))
	# Abos der Fernseher-Anmeldung (inoffiziell): beim Öffnen auffrischen (höchstens alle 20 Minuten).
	if YouTube.tv.logged_in():
		YouTube.tv.refresh_subs.call_deferred()
	if subs.is_empty():
		var m0 := U.margin(GUTTER, 30, GUTTER, 0)
		m0.add_child(U.label(abos_leer_text(YouTube.tv.logged_in(), YouTube.tv.subs_loading, YouTube.tv.subs_error), "l", "muted", "regular", true))
		col.add_child(m0)
		return
	var week := {}
	var now := int(Time.get_unix_time_from_system())
	for v in YouTube.feed:
		if now - int(v.get("published", 0)) < 7 * 86400:
			var cid := str(v.get("channel_id", ""))
			week[cid] = int(week.get(cid, 0)) + 1
	var grid := GridContainer.new()
	grid.columns = U.cols_for(8)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 22)
	grid.set_meta("uz_group", "abos")
	for s in subs:
		grid.add_child(_channel_tile(s, int(week.get(str(s.get("id", "")), 0))))
	# Das erste Bild steht genau an der Kante der Überschrift (Kachel 210 breit, Bild 128).
	var m := U.margin(GUTTER - 41, 24, 0, 80)
	m.add_child(grid)
	col.add_child(m)
	if grid.get_child_count() > 0:
		grid.get_child(0).set_meta("uz_default", true)


## Kopfzeile der Abos: wer angemeldet ist (die Fernseher-Anmeldung als inoffiziell gekennzeichnet).
static func abos_kopf(google: bool, account: String, tv: bool, n: int) -> String:
	if google:
		return "Angemeldet als %s  ·  %s" % [account, U.plural(n, "Abo", "Abos")]
	if tv:
		return TranslationServer.translate("Angemeldet") + "  ·  " + U.plural(n, "Abo", "Abos")
	return "Nicht mit Google angemeldet – deine Abos liegen nur in Uzai."


## Text der leeren Abo-Seite: lädt gerade, kam nicht (mit dem Grund) oder wirklich keine.
static func abos_leer_text(tv: bool, loading: bool, error: String) -> String:
	if tv and loading:
		return "Deine Abos werden von YouTube geholt …"
	if tv and error != "":
		return error
	return "Noch keine Abos. Y auf einem Video: „Kanal abonnieren“."


func _channel_tile(s: Dictionary, fresh: int) -> Control:
	var t = ChannelTile.new()
	t.setup(s, fresh, 128)
	t.set_meta("uz_hint_a", "Kanal öffnen")
	t.set_meta("uz_hint_y", "Abo beenden")
	t.set_meta("uz_on_y", func() -> void:
		main.open_dialog("Abo beenden?",
				"„%s“ verschwindet aus deinen Abos in Uzai.%s" % [s.title, " Bei YouTube selbst bleibt das Abo bestehen." if s.get("source") in ["google", "tv"] else ""], [
			["Abo beenden", func() -> void: YouTube.unsubscribe(str(s.id))],
			["Abbrechen", func() -> void: pass],
		])
	)
	t.chosen.connect(func(_c: Dictionary) -> void: main.open_channel(str(s.id), str(s.title)))
	return t


# --- Suche -------------------------------------------------------------------------------------

func _build_search() -> void:
	var col := _scroll_page()
	var top := U.margin(GUTTER, 0, GUTTER, 8)
	var row := U.hbox(14)
	row.set_meta("uz_group", "suche-kopf")
	top.add_child(row)
	var btn := U.button(_query if _query != "" else "Videos und Kanäle suchen", "search")
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
	btn.set_meta("uz_key", "suche:knopf")
	btn.set_meta("uz_hint_a", "Bildschirmtastatur" if _query == "" else "Neu suchen")
	btn.pressed.connect(_ask_search)
	row.add_child(btn)
	for q in (YouTube.data.searches as Array).slice(0, 5):
		if str(q) == _query:
			continue
		var chip := U.button(str(q), "history")
		chip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		chip.custom_minimum_size.y = 64
		chip.set_meta("uz_key", "suche:" + str(q))
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
	elif _query != "" and _results.is_empty() and _live_results.is_empty():
		var m2 := U.margin(GUTTER, 34, GUTTER, 0)
		var box := U.vbox(10)
		m2.add_child(box)
		box.add_child(U.label("Nichts gefunden", "xl", "text", "bold"))
		box.add_child(
				U.label(YouTube.error if YouTube.error != "" else "Keine Videos für „%s“." % _query, "l", "muted",
				"regular", true))
		col.add_child(m2)
	elif _query != "":
		if not _live_results.is_empty():
			# Livestreams zum Suchwort zuerst: In der normalen Suche stehen sie fast nie vorn.
			var tl := U.margin(0, 22, 0, 0)
			tl.add_child(section_title("Gerade live", "zu „%s“" % _query))
			col.add_child(tl)
			var ml := U.margin(GUTTER, 26, GUTTER, 40 if not _results.is_empty() else 80)
			var lgrid := _grid(_live_results, "vgrid:suche-live")
			ml.add_child(lgrid)
			col.add_child(ml)
			if lgrid.get_child_count() > 0:
				first = lgrid.get_child(0)
		if not _results.is_empty():
			var tm := U.margin(0, 22, 0, 0)
			tm.add_child(section_title("Ergebnisse", U.plural(_results.size(), "Video", "Videos") + " zu „%s“" % _query))
			col.add_child(tm)
			var m3 := U.margin(GUTTER, 26, GUTTER, 80)
			var grid := _grid(_results, "vgrid:suche")
			m3.add_child(grid)
			col.add_child(m3)
			if first == null and grid.get_child_count() > 0:
				first = grid.get_child(0)
	if _query == "" and not _searching:
		# Leere Suche: statt einer leeren Fläche, was gerade beliebt ist.
		var ideas: Array = YouTube.trending if not YouTube.trending.is_empty() else YouTube.recs.slice(0, 8)
		if not ideas.is_empty():
			var tm2 := U.margin(0, 30, 0, 0)
			tm2.add_child(section_title("Gerade beliebt", "zum Stöbern"))
			col.add_child(tm2)
			var m4 := U.margin(GUTTER, 26, GUTTER, 80)
			m4.add_child(_grid(ideas, "vgrid:ideen", 0, 8))
			col.add_child(m4)
	if first:
		first.set_meta("uz_default", true)
	else:
		btn.set_meta("uz_default", true)


## Von der globalen Suche: gleich mit diesem Suchwort suchen (der Bereich steht schon auf „Suche“).
func search_for(q: String) -> void:
	_run_search(q)


func _ask_search() -> void:
	main.open_keyboard("YouTube durchsuchen", _query, func(t: String) -> void:
		if t.strip_edges() != "":
			_run_search(t)
	)


func _run_search(q: String) -> void:
	_query = q.strip_edges()
	_searching = true
	_results = []
	_live_results = []
	build()
	var got: Dictionary = await YouTube.search_mit_live(_query, U.cols_for(4))
	# Inzwischen neu gesucht: Die ältere Antwort gehört nicht unter das neue Suchwort (und die neue Suche läuft noch).
	if q.strip_edges() != _query:
		return
	_results = got.videos
	_live_results = got.live
	_searching = false
	if visible and sub == "suche":
		build()
		await get_tree().process_frame
		focus_default()


# --- Playlists ---------------------------------------------------------------------------------

func _build_playlists() -> void:
	var col := _scroll_page()
	col.add_child(
			_page_head("Deine Playlists bei YouTube" + ("" if YouTube.playlists.is_empty() else "  ·  " + U.plural(YouTube.playlists.size() + 1, "Liste", "Listen"))))
	var grid := GridContainer.new()
	grid.columns = U.cols_for(4)
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", 44)
	grid.set_meta("uz_group", "playlists")
	grid.add_child(_playlist_tile({ "id": "liked", "title": "Mag ich", "count": -1, "thumb": "" }, "heart_f"))
	for p in YouTube.playlists:
		grid.add_child(_playlist_tile(p, "list"))
	var m := U.margin(GUTTER, 30, GUTTER, 80)
	m.add_child(grid)
	col.add_child(m)
	grid.get_child(0).set_meta("uz_default", true)
	if YouTube.playlists.is_empty():
		var l := U.margin(GUTTER, 0, GUTTER, 0)
		l.add_child(U.label("Deine eigenen Playlists werden geladen …", "m", "faint"))
		col.add_child(l)


func _playlist_tile(p: Dictionary, icon: String) -> Control:
	var pid := str(p.get("id", ""))
	var ptitle := str(p.get("title", ""))
	var count := int(p.get("count", -1))
	var c = VideoCard.new()
	c.setup({ "id": "pl-" + pid, "title": ptitle, "channel": ptitle, "thumb": str(p.get("thumb", "")) }, GRID_W, false)
	c.stacked = true
	c.badge_text = str(count) if count >= 0 else ""
	c.badge_icon = icon
	c.meta_override = U.plural(count, "Video", "Videos") if count >= 0 else "Videos, die du magst"
	c.set_meta("uz_hint_a", "Öffnen")
	c.chosen.connect(func(_v: Dictionary) -> void:
		main.open_video_grid(ptitle, "Playlist", func() -> Array: return await YouTube.playlist_videos(pid))
	)
	return c


func focus_default() -> void:
	var d := Nav.default_in(self)
	if d:
		Nav.focus(d, true)
