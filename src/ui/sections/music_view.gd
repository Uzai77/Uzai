extends "res://src/ui/sections/section.gd"
## Musik. Mit Spotify: „Für dich“ (Mixe von Spotify und aus deinen Hördaten, Neues von deinen
## Künstlern, deine Alben und Playlists), „Läuft gerade“ (groß, mit Warteschlange), Playlists,
## Lieblingssongs, Zuletzt gehört und Suche. Ohne Spotify zeigt Uzai, was Spotify oder ein
## Musik-Player über Windows abspielt (mit Cover; nie Browser, Videos, Spiele – Music.MUSIC_APPS),
## und steuert es über dessen Mediensitzung. Mit eigener Musik (Musikquelle „lokal“): Läuft gerade,
## Alben, Interpreten und Titel aus dem Musikordner (src/core/music_local.gd, src/ui/local_music_ui.gd).
## Spotify mit Musikordner: die Spotify-Reiter und dazu „Eigene Musik“; es spielt, was zuletzt startet.

const FederLage := preload("res://src/ui/components/feder_lage.gd")
const TrackRow := preload("res://src/ui/components/track_row.gd")
const TrackList := preload("res://src/ui/layers/track_list.gd")
const TrackPage := preload("res://src/ui/components/track_page.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")
const SpotifyCheck := preload("res://src/ui/layers/spotify_check.gd")
const SpotifyAnmelden := preload("res://src/ui/layers/spotify_anmelden.gd")
const LyricsPanel := preload("res://src/ui/components/lyrics_panel.gd")
const JetztLaeuft := preload("res://src/ui/layers/jetzt_laeuft.gd")
const Bits := preload("res://src/ui/components/music_bits.gd")
const LocalUi := preload("res://src/ui/local_music_ui.gd")
const LocalMusic := preload("res://src/core/music_local.gd")
const Verlauf := preload("res://src/core/spotify_verlauf.gd")

## Albumbild: so groß, dass „Läuft gerade“ unter den Reitern ganz zu sehen ist (früher 500).
const COVER := 400.0
const EIGENE_MAX := 60             ## so viele Alben bzw. Interpreten je Reihe in „Eigene Musik“
const MIX_W := 268.0
const TILE_W := 212.0
const GRID_W := 256.0
const KACHELN_SOFORT := 24      ## Raster mit vielen Kacheln (Playlists, Alben, Interpreten): so viele sofort …
const KACHELN_JE_BILD := 30     ## … der Rest in Scheiben über die nächsten Bilder (U.in_scheiben)
const VOL_W := 300.0
const VOL_STEP := 5

var _art: TextureRect
var _ph: TextureRect
var _glow
var _t: Label
var _a: Label
var _album: Label
var _state: Label
var _eq
var _bar = null
var _times: Control
var _time: Label
var _left: Label
var _play: Button
var _like: Button
var _shuffle: Button
var _repeat: Button
var _device: Button
var _vol_bar = null
var _vol_label: Label
var _vol_btn: Button
var _note: Label
var _queue_box: VBoxContainer
var _queue_head: Label
var _queue_title: Label
var _together: Label
var _artist_btn: Button
var _art_url := ""
var _search_q := ""
var _search_res := {}
var _searched: Array = []          ## zuletzt gesucht (diese Sitzung)
var _asked := {}                   ## je Besuch nur einmal nachladen (kein Kreislauf bei Fehlern)
var _rebuild_gen := 0
var _listen_gebaut := 0         ## _listen_sig() beim letzten Aufbau: gleiche Daten bauen nicht neu
var _halte := {}                ## während eines Neuaufbaus: { key, group } der Auswahl, die wieder stehen soll
var _bg_key := ""
var _snap_root: Control
var _snap_col: Control
var _snap_pad := 76.0
var _snap_fresh := false
static var _bg_cache := {}


func _init() -> void:
	super()
	id = "music"
	title = "Musik"
	icon_name = "music"
	Music.updated.connect(_refresh)
	Music.lists_changed.connect(_on_lists)
	Music.together_changed.connect(_refresh_together)
	# Für das Vorbauen (section.prebuild): neue Listen machen die vorgebaute Seite alt. Was gerade
	# läuft, zieht reenter nach (_refresh wirkt nur, solange der Bereich zu sehen ist).
	Music.lists_changed.connect(mark_stale)
	Music.local.library_changed.connect(_on_local_library)
	Music.quelle_changed.connect(_on_quelle)
	Nav.focus_moved.connect(_on_focus_moved)


func _spotify() -> bool:
	return Music.mode() == "spotify" and Music.has_spotify()


func subtabs() -> Array:
	if Music.lokal_da() and not _spotify():
		if LocalMusic.root() == "":
			# Noch kein Ordner: ein Bild mit der Ordnerwahl. Vier Reiter zeigten alle dasselbe, und
			# „Läuft gerade“ einen Spieler, der nichts spielen kann.
			return [{ "id": "alben", "label": "Musik" }]
		var lm: Node = Music.local
		# Wie ein Musik-Player: vorn die eigene Sammlung, „Läuft gerade“ zuletzt.
		return [
			{ "id": "alben", "label": "Alben", "count": (lm.albums as Array).size() if not (lm.albums as Array).is_empty() else -1 },
			{ "id": "interpreten", "label": "Interpreten", "count": (lm.artists as Array).size() if not (lm.artists as Array).is_empty() else -1 },
			{ "id": "titel", "label": "Titel", "count": (lm.tracks as Array).size() if not (lm.tracks as Array).is_empty() else -1 },
			{ "id": "jetzt", "label": "Läuft gerade" },
		]
	if _spotify() and Music.grundmodus():
		# Grundmodus (ohne eigene Spotify-App): vorn die Bibliothek aus Spotify am PC und dem eigenen
		# Verlauf (früher stand vorn „Läuft gerade“ – zu sehen war nur ein Lied), dann die Fernbedienung.
		return [
			{ "id": "verlauf", "label": "Bibliothek" },
		] + _eigene_tab() + [
			{ "id": "jetzt", "label": "Läuft gerade" },
		]
	if _spotify():
		return [
			{ "id": "fuerdich", "label": "Für dich" },
			{ "id": "jetzt", "label": "Läuft gerade" },
			{ "id": "playlists", "label": "Playlists", "count": Music.playlists.size() if not Music.playlists.is_empty() else -1 },
			{ "id": "lieblinge", "label": "Lieblingssongs", "count": Music.liked_list.size() if not Music.liked_list.is_empty() else -1 },
			{ "id": "zuletzt", "label": "Zuletzt gehört" },
		] + _eigene_tab() + [
			{ "id": "suche", "label": "Suche" },
		]
	return [{ "id": "jetzt", "label": "Musik" }] + _eigene_tab()


## Neben Spotify ein Reiter für die ganze eigene Sammlung (Alben, Interpreten, Titel) statt drei.
## Noch ohne Musikordner (Spotify oder Musik-Apps über Windows): derselbe Reiter mit der Ordnerwahl.
func _eigene_tab() -> Array:
	if not Music.beide():
		return [{ "id": "eigene", "label": "Eigene Musik" }] if Music.mode() in ["spotify", "tasten"] and LocalMusic.root() == "" else []
	var n := (Music.local.albums as Array).size()
	return [{ "id": "eigene", "label": "Eigene Musik", "count": n if n > 0 else -1 }]


func on_enter() -> void:
	_asked = {}
	if Music.beide():
		Music.lokal_laden()
	if Music.has_spotify():
		Music.poll()
		Music.load_queue()
		Music.pc_lib_refresh()
		if Music.playlists.is_empty():
			Music.load_playlists()
		if Music.liked_list.is_empty():
			Music.load_liked()
	if _spotify():
		Music.load_for_you()


## Beim Start (main._prebuild): dieselben Listen wie beim Betreten, ohne Abfrage des Players.
func prefetch() -> void:
	if Music.has_spotify():
		Music.load_queue()
		if Music.playlists.is_empty():
			Music.load_playlists()
		if Music.liked_list.is_empty():
			Music.load_liked()
	if _spotify():
		Music.load_for_you()


func data_ready() -> bool:
	return not (_spotify() and Music.for_you_loading())


## Vorgebaut, jetzt zum ersten Mal zu sehen: Titel, Bild und Hintergrund zum laufenden Lied.
func reenter() -> void:
	# Wie build(): "-" statt "" – ohne Bild-Adresse (Medientasten, kein Spotify) lief der Zweig
	# für Platzhalter und Hintergrund sonst nie, der Raum blieb beim ersten Besuch leer.
	_art_url = "-"
	_refresh()


## Einmal je Besuch nachladen (scheitert es, nicht gleich wieder – sonst lädt die Seite im Kreis).
func _ask(what: String, f: Callable) -> void:
	if _asked.has(what):
		return
	_asked[what] = true
	f.call()


func _on_lists(what: String) -> void:
	if not visible or not is_inside_tree():
		return
	if Nav.top_layer() == null:
		var need := false
		match what:
			"queue":
				if sub == "jetzt":
					_fill_queue()
			"playlists": need = sub in ["playlists", "fuerdich"]
			"liked": need = sub in ["lieblinge", "playlists"]
			"recent": need = sub in ["zuletzt", "fuerdich"]
			"fuerdich": need = sub == "fuerdich"
			"verlauf", "pc":
				if sub == "jetzt":
					_fill_queue()
				else:
					need = sub == "verlauf"
			"problem": need = true
		if need:
			_rebuild_soon()
	if main:
		main.refresh_chips()


## Mehrere Meldungen kurz hintereinander (Für dich lädt in Teilen) nur einmal umsetzen.
func _rebuild_soon() -> void:
	_rebuild_gen += 1
	var my := _rebuild_gen
	await get_tree().create_timer(0.25).timeout
	if my != _rebuild_gen or not visible or not is_inside_tree() or Nav.top_layer() != null:
		return
	# Same data as the last build: do nothing. On entering, the page queries Spotify again; otherwise every
	# response would rebuild it even without changes - the selected first album would be replaced and grow
	# again, so it would visibly jump.
	if _listen_sig() == _listen_gebaut:
		return
	_rebuild_keep()


## Was die Listen dieser Seite gerade zeigen (und ob noch etwas lädt), als eine Zahl.
func _listen_sig() -> int:
	return hash([sub, Music.mode(), Music.playlists, Music.liked_list.size(), Music.liked_list.slice(0, 40), Music.recent_list,
		Music.saved_albums, Music.spotify_mixes, Music.new_releases, Music.top_tracks, Music.verlauf.size(), Music.verlauf.slice(0, 40),
		Music.pc_lib, Music.pc_state, Music.pc_reading, Music.problem, Music.error, Music.list_error, Music.playlists_state,
		Music.for_you_parts, Music.need_login, Music.starting])


## Neu aufbauen und die Auswahl halten: dasselbe Element, sonst dieselbe Stelle in derselben
## Gruppe (verschwindet ein Titel aus der Liste, bleibt die Auswahl in der Liste).
func _rebuild_keep() -> void:
	var f := Nav.focused()
	var key := ""
	var group := ""
	var idx := -1
	if f and is_ancestor_of(f):
		key = str(f.get_meta("uz_key", ""))
		var g := _group_of(f)
		if g:
			group = str(g.get_meta("uz_group"))
			idx = Nav.focusables(g).find(f)
	_halte = { "key": key, "group": group }
	build()
	_halte = {}
	if key == "" and group == "":
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for c in Nav.focusables(self):
		if key != "" and str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return
	if group != "":
		var g2 := _find_group(self, group)
		if g2:
			var items := Nav.focusables(g2)
			if not items.is_empty():
				Nav.focus(items[clampi(idx, 0, items.size() - 1)], true)
				return
	focus_default()


## Für die Raster, die in Scheiben bauen (U.in_scheiben): bis zur gehaltenen Auswahl ohne Pause – aber nur, wenn
## sie in dieser Gruppe lag. Sonst leer (dann stehen die ersten Reihen sofort, der Rest folgt).
func _halten_bis(group: String) -> Callable:
	var key := str(_halte.get("key", ""))
	if key == "" or str(_halte.get("group", "")) != group:
		return Callable()
	return func(c: Node) -> bool: return str(c.get_meta("uz_key", "")) == key


func build() -> void:
	_listen_gebaut = _listen_sig()
	U.clear(self)
	_snap_col = null
	_art = null
	_queue_box = null
	_bar = null
	_vol_bar = null
	_vol_btn = null
	if Music.mode() == "aus":
		# Die Bühne mit angedeuteten Alben; A schaltet gleich ein (Musik-Apps über Windows, ohne
		# Konto), daneben Spotify. Danach steht hier, was läuft.
		add_child(leer_buehne({ "art": "musik", "symbol": "music", "titel": "Musik ist aus.",
			"knopf": "Einschalten", "tun": func() -> void: Config.set_value("system.music_mode", "tasten"),
			"neben": "Mit Spotify anmelden", "neben_tun": LeerBuehne.weg(main, "spotify"),
			"fertig": func() -> bool: return Music.mode() != "aus" }))
		return
	if Music.lokal_da() and not _spotify() and (sub in ["alben", "interpreten", "titel"] or LocalMusic.root() == ""):
		_build_local(sub)
		return
	if sub == "eigene" and Music.beide():
		_build_eigene()
		return
	if sub == "eigene" and LocalMusic.root() == "":
		_build_local("alben")        # ohne Ordner: die Bühne mit der Ordnerwahl
		return
	if _spotify() and Music.grundmodus() and sub in ["verlauf", "fuerdich", "playlists", "lieblinge", "zuletzt", "suche"]:
		_build_verlauf()
		return
	match sub:
		"fuerdich": _build_foryou()
		"playlists": _build_playlists()
		"lieblinge": _build_library("liked")
		"zuletzt": _build_library("recent")
		"suche": _build_search()
		_: _build_now()


# --- Für dich ------------------------------------------------------------------------------------

## Reihen wie auf einer Konsole: oben die Mixe (von Spotify und aus deinen Hördaten), darunter
## Neues von deinen Künstlern, deine Alben und Playlists. Lädt in Teilen; was fehlt, schimmert.
func _build_foryou() -> void:
	_ask("fuerdich", func() -> void: Music.load_for_you())
	var col := _scroll_page()
	if _problem() != "":
		col.add_child(_problem_card())
	elif Music.need_login:
		col.add_child(_login_card())
	var parts: Dictionary = Music.for_you_parts
	var mixes: Array = Music.spotify_mixes + Music.own_mixes()
	var mixes_loading := str(parts.get("mixe", "")) == "laedt" or str(parts.get("top", "")) == "laedt"
	var first := true
	if not mixes.is_empty() or mixes_loading:
		var extra := "Aus deinen Hördaten"
		if not Music.spotify_mixes.is_empty():
			extra = "Mixe von Spotify und aus deinen Hördaten" if Music.mix_titles() else "Mixe von Spotify"
		col.add_child(_shelf_box("Für dich gemacht", extra, mixes, "mixe", MIX_W, mixes_loading and mixes.size() < 4, first))
		first = false
	if not Music.new_releases.is_empty() or str(parts.get("neu", "")) == "laedt":
		col.add_child(
				_shelf_box("Neu von deinen Künstlern", "Alben und Singles der letzten sechs Wochen", Music.new_releases, "neu", TILE_W, Music.new_releases.is_empty(),
				first))
		first = false
	if not Music.saved_albums.is_empty() or str(parts.get("alben", "")) == "laedt":
		col.add_child(
				_shelf_box("Deine Alben", U.plural(Music.saved_albums.size(), "Album", "Alben") if not Music.saved_albums.is_empty() else "", Music.saved_albums, "alben",
				TILE_W, Music.saved_albums.is_empty(), first))
		first = false
	var pls: Array = ([_liked_item()] if not Music.liked_list.is_empty() else []) + Music.playlists
	if not pls.is_empty():
		col.add_child(_shelf_box("Deine Playlists", "", pls, "playlists", TILE_W, false, first))
		first = false
	var eigene: Array = (Music.local.albums as Array).slice(0, 20) if Music.beide() else []
	if not eigene.is_empty():
		col.add_child(_shelf_box("Aus deinem Musikordner", U.plural((Music.local.albums as Array).size(), "Album", "Alben"), eigene, "lokal", TILE_W, false, first,
				_lokal_tile))
		first = false
	if first and not Music.for_you_loading():
		col.add_child(_empty_card())
	if not Music.lokal_da():
		col.add_child(_eigene_dazu())
	col.add_child(U.spacer(0, 40, false))


## Was Spotify gerade nicht lässt – ohne den Grundmodus („app“): der ist kein Fehler, sondern
## die Fernbedienung mit eigenem Verlauf.
func _problem() -> String:
	return "" if Music.problem == "app" else Music.problem


# --- Bibliothek (Grundmodus) ---------------------------------------------------------------------

## Grundmodus (ohne eigene Spotify-App): Reihen aus „Deine Bibliothek“ der Spotify-App am PC
## (Playlists, Künstler, Alben, Zuletzt gespielt – gelesen über die Bedienhilfe von Windows, gemerkt)
## und aus Uzais eigenem Verlauf (Zuletzt gehört, Oft gehört). Abspielen über Spotify Connect.
## Ist Spotify am PC zu und noch nichts gemerkt: ein klarer Zustand mit „Spotify starten“ (minimiert,
## ohne dass ein Fenster nach vorn kommt). Ganz unten eine ruhige Zeile zur eigenen Spotify-App.
func _build_verlauf() -> void:
	var list := Music.verlauf_list()
	var pc_any := Music.pc_has()
	var pc: Dictionary = Music.pc_lib
	var rec := Verlauf.recent(list, 20)
	if not pc_any and rec.is_empty() and not Music.demo():
		add_child(leer_buehne({ "art": "musik", "symbol": "music", "titel": _pc_titel(),
			"knopf": "Spotify starten", "tun": func() -> void: Music.pc_start(),
			"neben": "Weiter hören", "neben_tun": func() -> void: Music.play_pause(),
			"fertig": func() -> bool: return Music.pc_has() or not Verlauf.recent(Music.verlauf_list(), 1).is_empty(),
			"laeuft": func() -> bool: return Music.starting or Music.pc_reading,
			"laeuft_titel": "Spotify startet im Hintergrund …", "laeuft_knopf": "Einen Moment" }))
		return
	var col := _scroll_page()
	var first := true
	if not pc_any:
		col.add_child(_pc_zu())
		first = false
	var shelves := [["recent", "Zuletzt gespielt"], ["playlists", "Deine Playlists"], ["artists", "Künstler"], ["albums", "Alben"]]
	for part in shelves:
		var items: Array = pc.get(part[0], [])
		if items.is_empty():
			continue
		var extra := ""
		match str(part[0]):
			"playlists": extra = U.plural(items.size(), "Playlist", "Playlists")
			"artists": extra = U.plural(items.size(), "Künstler", "Künstler")
			"albums": extra = U.plural(items.size(), "Album", "Alben")
		col.add_child(_shelf_box(str(part[1]), extra, items.map(func(it: Dictionary) -> Dictionary: return it.merged({ "kind": "pc" }, true)), "pc:" + str(part[0]),
				TILE_W, false, first))
		first = false
	if not rec.is_empty():
		col.add_child(_shelf_box("Zuletzt gehört", "", rec.map(func(t: Dictionary) -> Dictionary: return t.merged({ "kind": "track" })), "zuletzt", TILE_W, false, first))
		first = false
	var oft := Verlauf.frequent(list, 20, 2)
	if oft.size() >= 3:
		col.add_child(_shelf_box("Oft gehört", "", oft.map(func(t: Dictionary) -> Dictionary: return t.merged({ "kind": "track" })), "oft", TILE_W, false, first))
		first = false
	var ctx := Verlauf.contexts(list, 12)
	if not ctx.is_empty() and (pc.get("recent", []) as Array).is_empty():
		col.add_child(_shelf_box("Deine Playlists & Alben zuletzt", "", ctx.map(func(c: Dictionary) -> Dictionary: return c.merged({ "kind": "verlauf_ctx", "ctype": c.kind }, true)), "kontexte",
				TILE_W, false, first))
		first = false
	if first:
		col.add_child(_verlauf_empty())
	var m := U.margin(GUTTER, 34, GUTTER, 0)
	var row := U.hbox(18)
	m.add_child(row)
	if pc_any and not Music.demo():
		var again := U.button("Einen Moment …" if Music.pc_reading else "Bibliothek neu lesen", "refresh", "flat")
		again.set_meta("uz_key", "verlauf:neu")
		again.disabled = Music.pc_reading
		if UzTheme.strict():
			U.ruhig(again, "flach", 15)
		again.modulate = Color(1, 1, 1, 0.72)
		again.pressed.connect(func() -> void: Music.pc_lib_refresh(true))
		row.add_child(again)
	if not Music.demo() or Music.demo_grund:
		var more := U.button("Spotify-Einstellungen", "settings", "flat")
		more.set_meta("uz_key", "verlauf:eigen")
		more.set_meta("uz_hint_a", "Einstellungen")
		if UzTheme.strict():
			U.ruhig(more, "flach", 15)
		more.modulate = Color(1, 1, 1, 0.72)
		more.pressed.connect(func() -> void: main.goto("settings", "konten"))
		row.add_child(more)
	if not Music.lokal_da():
		row.add_child(_eigene_knopf())
	col.add_child(m)
	col.add_child(U.spacer(0, 40, false))


## Titel, solange aus Spotify am PC nichts da ist.
func _pc_titel() -> String:
	match Music.pc_state:
		"zu": return "Spotify am PC ist zu."
		"leer", "aus": return "Spotify am PC zeigt gerade nichts."
	return "Deine Bibliothek kommt aus Spotify am PC."


## Spotify am PC ist zu (oder zeigt nichts), der eigene Verlauf hat aber schon etwas: oben eine
## ruhige Zeile mit dem Knopf, der Spotify minimiert startet (bzw. neu liest).
func _pc_zu() -> Control:
	var m := U.margin(GUTTER, 26, GUTTER, 18)
	var c := U.vbox(14)
	m.add_child(c)
	c.add_child(U.label(_pc_titel(), "xl", "text", "bold"))
	var busy := Music.starting or Music.pc_reading
	var zu := Music.pc_state in ["zu", ""]
	var b := U.button("Einen Moment …" if busy else ("Spotify starten" if zu else "Neu lesen"), "play" if zu else "refresh", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.disabled = busy
	b.set_meta("uz_default", true)
	b.set_meta("uz_key", "verlauf:start")
	b.pressed.connect(func() -> void:
		if zu:
			Music.pc_start()
		else:
			Music.pc_lib_refresh(true)
		_rebuild_soon()
	)
	c.add_child(b)
	return m


func _verlauf_empty() -> Control:
	var m := U.margin(GUTTER, 30, GUTTER, 0)
	var c := U.vbox(16)
	m.add_child(c)
	c.add_child(U.label("Noch nichts gehört", "xl", "text", "bold"))
	var p := U.label("Nur auf diesem PC gespeichert.", "l", "muted", "regular", true)
	p.custom_minimum_size = Vector2(1000, 0)
	c.add_child(p)
	var b := U.button("Weiter hören", "play", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.set_meta("uz_key", "verlauf:weiter")
	b.pressed.connect(func() -> void: Music.play_pause())
	c.add_child(b)
	return m


## Ein Titel aus dem Verlauf: in seiner Playlist bzw. seinem Album (dann läuft die Liste weiter),
## sonst allein. Über Spotify Connect wie die Spotify-Apps.
func _play_track(t: Dictionary) -> void:
	var ctx := str(t.get("context", ""))
	if ctx != "":
		await Music.play_in(ctx, str(t.uri))
	else:
		await Music.play_list([t], 0)
	if Music.error != "":
		Toasts.show_toast(str(t.get("title", "")) + " spielt nicht", Music.error, "warning", { "ms": 4500 })
	else:
		Toasts.show_toast("Läuft: " + str(t.get("title", "")), str(t.get("artist", "")), "music", { "ms": 1600, "quiet": true })


## Seite mit Reihen, die beim Blättern nach unten oben einrasten (wie im Menü einer Konsole):
## die gewählte Reihe rückt nach oben, darüber verschwindet alles ganz – nie halbe Kacheln.
func _scroll_page(pad := 76.0) -> VBoxContainer:
	var root := Control.new()
	root.clip_contents = true
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	U.full_rect(root)
	add_child(root)
	var col := U.vbox(4)
	col.anchor_right = 1.0
	col.offset_left = 0
	col.offset_right = 0
	root.add_child(col)
	root.gui_input.connect(_on_page_wheel)
	# Die Seite rollt selbst (rastend): das Rad senkrecht gehört ihr, nicht den Reihen (zeiger.gd).
	root.set_meta("uz_rad_selbst", true)
	_snap_root = root
	_snap_col = col
	_snap_pad = pad
	_snap_fresh = true
	col.add_child(U.spacer(0, 6, false))
	return col


func _on_focus_moved(c: Control) -> void:
	if c == null or _snap_col == null or not is_instance_valid(_snap_col) or not _snap_col.is_ancestor_of(c):
		return
	var local_y := c.get_global_rect().position.y - _snap_col.get_global_rect().position.y
	if c is MusicTile:
		# Kacheln: die ganze Reihe rastet oben ein. Bei den letzten Reihen bleibt die vorige
		# sichtbar, solange beide ganz aufs Bild passen (sonst wäre unten alles leer).
		var y := local_y - _snap_pad
		var rows: Array = _snap_col.get_children().filter(func(n): return n is Control and (n as Control).has_meta("uz_row"))
		for i in rows.size():
			var box: Control = rows[i]
			if not box.is_ancestor_of(c):
				continue
			y = 0.0 if i == 0 else box.position.y - 4.0
			if i > 0 and _snap_col.size.y - box.position.y < _snap_root.size.y * 0.7:
				var prev: Control = rows[i - 1]
				if box.position.y + box.size.y - prev.position.y <= _snap_root.size.y - 10.0:
					y = prev.position.y - 4.0
		_snap_to(y, _snap_fresh, true)
	else:
		# Zeilen und Knöpfe: nur mitscrollen, wenn sie sonst aus dem Bild liefen.
		var top := -_snap_col.position.y
		var h := _snap_root.size.y
		if local_y < top + 110.0:
			_snap_to(local_y - 110.0, _snap_fresh)
		elif local_y + c.size.y > top + h - 150.0:
			_snap_to(local_y + c.size.y - h + 150.0, _snap_fresh)
	_snap_fresh = false


## loose: Kachel-Reihen dürfen bis ganz nach oben rücken (auch die letzte); sonst nur bis zum Ende.
func _snap_to(y: float, instant := false, loose := false) -> void:
	if _snap_col == null or not is_instance_valid(_snap_col):
		return
	var maxo := maxf(0.0, _snap_col.size.y - (220.0 if loose else _snap_root.size.y - 30.0))
	var target := -clampf(y, 0.0, maxo)
	# Feder statt Tween: beim Halten übernimmt jeder Schritt das Tempo des vorigen.
	FederLage.zu(_snap_col, target, instant)


func _on_page_wheel(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var d := -140.0 if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else 140.0
		_snap_to(-_snap_col.position.y + d)


## Überschrift und eine Reihe Kacheln. skeleton: am Ende schimmernde Platzhalter (lädt noch).
## make: eigene Kachel je Eintrag (sonst _tile).
func _shelf_box(head: String, extra: String, items: Array, group: String, w: float, skeleton := false, first := false, make := Callable()) -> Control:
	var box := U.vbox(0)
	box.set_meta("uz_row", true)
	box.add_child(section_title(head, extra))
	var shelf = Shelf.new().setup("mfy:" + group, 30, true, 30, GUTTER, 20)
	shelf.custom_minimum_size.y = w + MusicTile.TEXT_H + 50
	box.add_child(shelf)
	for i in items.size():
		var tile: Control = make.call(items[i], w) if make.is_valid() else _tile(items[i], w)
		if i == 0:
			tile.set_meta("uz_entry", true)
			if first:
				tile.set_meta("uz_default", true)
		shelf.add(tile)
	if skeleton:
		for i in (4 if items.is_empty() else 2):
			shelf.add(Skeleton.tile(w))
	return box


## Kachel je nach Art: Mix von Spotify (spielt direkt), eigener Mix, Album, Playlist, Lieblingssongs.
func _tile(it: Dictionary, w: float) -> Control:
	var kind := str(it.get("kind", "playlist"))
	var t = MusicTile.new()
	t.setup(it, w)
	t.set_meta("uz_key", "mt:%s:%s" % [kind, str(it.get("id", it.get("name", "")))])
	match kind:
		"artist":
			t.round_art = true
			t.icon_name = "user"
			t.art_urls = [str(it.get("art", ""))]
			t.sub_text = "Künstler"
			t.set_meta("uz_hint_a", "Künstler öffnen")
			t.chosen.connect(func(_i: Dictionary) -> void: Bits.open_artist(main, it))
		"spotify_mix":
			var has_art := str(it.get("art", "")) != ""
			t.big_name = not has_art
			t.kicker = "Spotify" if not has_art else ""
			t.hue = float(it.get("hue", 0.6))
			t.art_urls = [str(it.art)] if has_art else []
			if has_art:
				t.sub_text = str(it.get("sub", ""))
			else:
				# Der Name steht schon groß im Bild: darunter, wann er neu ist und von wem.
				t.cover_text = str(it.get("name", ""))
				t.title_text = str(it.get("sub", ""))
				t.sub_text = "Von Spotify"
			if Music.mix_titles():
				# Wie die Spotify-App: echte Titelliste wie bei jeder Playlist.
				t.set_meta("uz_hint_a", "Titel ansehen")
				t.set_meta("uz_hint_y", "Abspielen")
				t.set_meta("uz_on_y", func() -> void: _play_context(it))
				t.chosen.connect(func(_i: Dictionary) -> void: _open(it))
			else:
				t.set_meta("uz_hint_a", "Abspielen")
				t.chosen.connect(func(_i: Dictionary) -> void: _play_context(it))
		"mix":
			t.big_name = true
			t.kicker = "Mix"
			t.hue = float(it.get("hue", 0.6))
			t.art_urls = it.get("arts", [])
			t.cover_text = str(it.get("name", ""))
			t.title_text = str(it.get("sub", ""))
			t.sub_text = str(it.get("count_label", U.plural(int(it.get("count", 0)), "Titel", "Titel")))
			t.set_meta("uz_hint_a", "Titel ansehen")
			t.set_meta("uz_hint_y", "Abspielen")
			t.set_meta("uz_on_y", func() -> void: _play_mix(it))
			t.chosen.connect(func(_i: Dictionary) -> void: _open(it))
		"album":
			t.art_urls = [str(it.get("art", ""))]
			# Wie neu es ist, steht als kleines Schild im Bild (darunter ist Platz für den Künstler).
			var single := str(it.get("type", "")) == "single"
			var ago := U.ago(int(it.get("released", 0))) if int(it.get("released", 0)) > 0 else ""
			if single and ago != "":
				t.kicker = "Single · " + ago.substr(0, 1).to_lower() + ago.substr(1)
			else:
				t.kicker = "Single" if single else ago
			t.sub_text = str(it.get("artist", ""))
			t.set_meta("uz_hint_a", "Album öffnen")
			t.set_meta("uz_hint_y", "Abspielen")
			t.set_meta("uz_on_y", func() -> void: _play_context(it))
			t.chosen.connect(func(_i: Dictionary) -> void: _open(it))
		"track":
			t.art_urls = [str(it.get("art", ""))] if str(it.get("art", "")) != "" else []
			t.title_text = str(it.get("title", ""))
			t.sub_text = str(it.get("artist", "")) + (("  ·  %d×" % int(it.plays)) if int(it.get("plays", 0)) > 1 else "")
			t.set_meta("uz_key", "mt:track:%s:%s" % [str(it.get("plays", "")), str(it.get("uri", ""))])
			t.set_meta("uz_hint_a", "Abspielen")
			t.set_meta("uz_hint_x", "Als Nächstes")
			t.set_meta("uz_on_x", func() -> void:
				Music.enqueue(str(it.uri))
				Toasts.show_toast("Kommt als Nächstes", str(it.get("title", "")), "music", { "ms": 1400, "quiet": true })
			)
			t.chosen.connect(func(_i: Dictionary) -> void: _play_track(it))
		"verlauf_ctx":
			var has := str(it.get("art", "")) != ""
			t.art_urls = [str(it.art)] if has else []
			if not has:
				t.big_name = true
				t.cover_text = str(it.get("name", ""))
			var what := str({ "album": "Album", "playlist": "Playlist", "artist": "Künstler", "show": "Podcast" }.get(str(it.get("ctype", "")), ""))
			t.sub_text = tr(what) + ((" · " + str(it.artist)) if str(it.get("artist", "")) != "" else "")
			t.set_meta("uz_hint_a", "Abspielen")
			t.chosen.connect(func(_i: Dictionary) -> void: _play_context(it))
		"pc":
			# Aus Spotify am PC: Cover über oEmbed, sonst der Name groß im Bild; Künstler rund.
			var art := str(it.get("art", ""))
			var pk := str(it.get("pkind", ""))
			t.round_art = pk == "artist"
			t.art_urls = [art] if art != "" else []
			if str(it.get("uri", "")).ends_with(":collection"):
				t.icon_name = "heart_f"
				t.hue = float(Music.HUES.liked)
			var what := str(it.get("sub", ""))
			if what == "":
				what = tr(str({ "album": "Album", "playlist": "Playlist", "artist": "Künstler", "show": "Podcast" }.get(pk, "")))
			t.sub_text = what
			if art == "" and not str(it.get("uri", "")).ends_with(":collection"):
				# Noch ohne Cover (kommt über oEmbed): der Name groß im Bild, darunter nur die Art – wie bei Mixen.
				t.big_name = true
				t.cover_text = str(it.get("name", ""))
				t.icon_name = "user" if pk == "artist" else "music"
				t.title_text = what
				t.sub_text = ""
			t.set_meta("uz_hint_a", "Abspielen")
			t.chosen.connect(func(_i: Dictionary) -> void:
				var ok: bool = await Music.pc_play(it)
				if ok:
					Toasts.show_toast("Läuft: " + str(it.get("name", "")), str(it.get("sub", "")), "music", { "ms": 1800, "quiet": true })
				else:
					Toasts.show_toast(str(it.get("name", "")) + " spielt nicht", Music.error if Music.error != "" else "Nicht verfügbar. Erneut versuchen.",
						"warning", { "ms": 4000 })
			)
		"liked":
			t.icon_name = "heart_f"
			t.hue = float(Music.HUES.liked)
			t.sub_text = U.plural(int(it.get("count", 0)), "Titel", "Titel")
			t.set_meta("uz_hint_a", "Titel ansehen")
			t.set_meta("uz_hint_y", "Abspielen")
			t.set_meta("uz_on_y", func() -> void:
				Music.play_list(Music.liked_list, 0)
				Toasts.show_toast("Läuft: Lieblingssongs", "", "heart_f", { "ms": 1600, "quiet": true })
			)
			t.chosen.connect(func(_i: Dictionary) -> void: main.goto("music", "lieblinge"))
		_:
			t.art_urls = [str(it.get("art", ""))]
			var n := int(it.get("count", 0))
			var teile := PackedStringArray()
			if n >= 0:
				teile.append(U.plural(n, "Titel", "Titel"))
			if str(it.get("owner", "")) != "" and not bool(it.get("mine", true)):
				teile.append("von " + str(it.owner))
			t.sub_text = " · ".join(teile) if not teile.is_empty() else tr("Playlist")
			t.set_meta("uz_hint_a", "Titel ansehen")
			t.set_meta("uz_hint_y", "Abspielen")
			t.set_meta("uz_on_y", func() -> void: _play_context(it))
			t.chosen.connect(func(_i: Dictionary) -> void: _open(it))
	t.focused_item.connect(func(_i: Dictionary) -> void: _on_tile_focus(it, t))
	return t


func _liked_item() -> Dictionary:
	return { "kind": "liked", "id": "liked", "name": "Lieblingssongs", "count": Music.liked_list.size(), "hue": float(Music.HUES.liked) }


func _open(it: Dictionary) -> void:
	var l = TrackList.new()
	l.playlist = it
	l.main = main
	main.open_layer(l)


func _play_context(it: Dictionary) -> void:
	var name_s := str(it.get("name", ""))
	var ok: bool = await Music.play_context(str(it.get("uri", "")))
	if ok:
		Toasts.show_toast("Läuft: " + name_s, str(it.get("sub", "")), "music", { "ms": 1800, "quiet": true })
	else:
		Toasts.show_toast(name_s + " spielt nicht", Music.error, "warning", { "ms": 4500 })


func _play_mix(it: Dictionary) -> void:
	var tracks: Array = await Music.mix_tracks(str(it.get("id", "")))
	if tracks.is_empty():
		Toasts.show_toast("Gerade keine Titel", str(it.get("name", "")), "music", { "ms": 2400 })
		return
	Music.play_list(tracks, 0)
	Toasts.show_toast("Läuft: " + str(it.get("name", "")), U.plural(tracks.size(), "Titel", "Titel"), "music", { "ms": 1800, "quiet": true })


## Der Raum nimmt die Farbe der gewählten Kachel an (Bild, sonst ihr Farbton) – erst wenn die
## Auswahl kurz ruht, damit schnelles Blättern ruhig bleibt.
func _on_tile_focus(it: Dictionary, tile) -> void:
	var key := str(it.get("uri", "")) + str(it.get("id", ""))
	if key == _bg_key or main == null or main.background == null:
		return
	_bg_key = key
	await get_tree().create_timer(0.16).timeout
	if _bg_key != key or not is_instance_valid(tile) or not visible:
		return
	var tex: Texture2D = tile.texture()
	if tex == null:
		main.background.show_blurred(_hue_tex(float(tile.hue)), "mt:" + key)
	else:
		# Albumbild weich wie ein Spiel-Cover (Background.show_soft), nicht scharf hochgezogen.
		main.background.show_soft(tex, "mt:" + key)


static func _hue_tex(h: float) -> Texture2D:
	var key := int(h * 100.0)
	if _bg_cache.has(key):
		return _bg_cache[key]
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.from_hsv(h, 0.45, 0.22))
	var t := ImageTexture.create_from_image(img)
	_bg_cache[key] = t
	return t


## Alte Anmeldung ohne die nötigen Freigaben: einmal neu anmelden.
func _login_card() -> Control:
	var m := U.margin(GUTTER, 4, GUTTER, 14)
	var card := PanelContainer.new()
	var sb := UzTheme.glass(UzTheme.r_panel())
	sb.content_margin_left = 30
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(card)
	var row := U.hbox(22)
	card.add_child(row)
	var ic := U.icon("spark", 30, "accent")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var txt := U.vbox(4)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	txt.add_child(U.label("Mehr Mixe freischalten", "l", "text", "bold"))
	txt.add_child(U.label("Neue Anmeldung bei Spotify nötig.", "m", "muted", "regular", true))
	var app_b := U.button("Mit Spotify anmelden", "music")
	app_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	app_b.set_meta("uz_key", "mfy:app")
	app_b.pressed.connect(func() -> void:
		SpotifyAnmelden.start(main, func(err: String) -> void:
			if err == "" and Music.app_mode():
				Music.load_for_you(true))
	)
	row.add_child(app_b)
	var b := U.button("Neu anmelden", "link")
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_meta("uz_key", "mfy:login")
	b.pressed.connect(func() -> void:
		Toasts.show_toast("Spotify-Anmeldung", "Im Browser bestätigen.", "music", { "ms": 6000 })
		var err: String = await Music.connect_spotify()
		if err == "":
			Music.load_for_you(true)
		else:
			Toasts.show_toast("Spotify nicht verbunden", err, "music")
	)
	row.add_child(b)
	return m


## Spotify lässt Uzai nicht rein (Konto nicht in der App, Premium, abgelaufen) oder eine Liste kam
## nicht an: eine ruhige Karte mit dem Grund und den Wegen weiter. side: schmal für „Läuft gerade“.
func _problem_card(text := "", retry: Callable = Callable(), side := false) -> Control:
	var why := Music.problem
	var m := U.margin(0 if side else GUTTER, 4, 0 if side else GUTTER, 14)
	var card := PanelContainer.new()
	var sb := UzTheme.glass(UzTheme.r_panel())
	sb.content_margin_left = 36 if side else 30
	sb.content_margin_right = 36 if side else 26
	sb.content_margin_top = 30 if side else 22
	sb.content_margin_bottom = 30 if side else 22
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(card)
	var lay: BoxContainer
	if side:
		lay = U.vbox(16)
	else:
		lay = U.hbox(22)
	card.add_child(lay)
	var ic := U.icon("warning", 30, "warn")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER if not side else Control.SIZE_SHRINK_BEGIN
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lay.add_child(ic)
	var txt := U.vbox(6)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(txt)
	var heads := { "nutzer": "Spotify lässt dein Konto nicht rein", "premium": "Deine Spotify-App ist gesperrt",
		"abgelaufen": "Spotify-Anmeldung abgelaufen", "gesperrt": "Spotify lehnt dein Konto ab", "app": "Spotify-Bibliothek gerade nicht erreichbar" }
	var head: String = heads.get(why, "Das kam nicht an")
	txt.add_child(U.label(head, "xl" if side else "l", "text", "bold", true))
	var body := U.label(text if text != "" else Music.problem_text(why), "m", "muted", "regular", true)
	body.custom_minimum_size = Vector2(0 if side else 900, 0)
	txt.add_child(body)
	var btns := U.hbox(12)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lay.add_child(btns)
	if retry.is_valid():
		var again := U.button("Nochmal", "refresh", "primary")
		again.set_meta("uz_key", "mprob:again")
		again.set_meta("uz_default", true)
		again.pressed.connect(retry)
		btns.add_child(again)
	if why in ["abgelaufen", "app"]:
		var b := U.button("Neu anmelden", "link", "primary" if not retry.is_valid() else "normal")
		b.set_meta("uz_key", "mprob:login")
		b.set_meta("uz_default", not retry.is_valid())
		b.pressed.connect(func() -> void:
			# Eigene Client-ID: Browser wie bisher; sonst „Mit Spotify anmelden“.
			SpotifyAnmelden.relogin(main, func(err: String) -> void:
				if err == "":
					Music.load_for_you(true)
					Music.load_playlists()
			)
		)
		btns.add_child(b)
	var check := U.button("Verbindung prüfen", "search", "normal" if (retry.is_valid() or why in ["abgelaufen", "app"]) else "primary")
	check.set_meta("uz_key", "mprob:check")
	check.pressed.connect(func() -> void: main.open_layer(SpotifyCheck.new()))
	btns.add_child(check)
	return m


func _empty_card() -> Control:
	var m := U.margin(GUTTER, 30, GUTTER, 0)
	var col := U.vbox(16)
	m.add_child(col)
	col.add_child(U.label("Für dich ist noch leer", "xl", "text", "bold"))
	var p := U.label("Noch keine Hördaten."
			if Music.error == "" else Music.error, "l", "muted", "regular", true)
	p.custom_minimum_size = Vector2(1000, 0)
	col.add_child(p)
	var b := U.button("Neu laden", "refresh", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(func() -> void: Music.load_for_you(true))
	col.add_child(b)
	return m


# --- Läuft gerade --------------------------------------------------------------------------------

func _build_now() -> void:
	var local := Music.local_on()
	var spotify := _spotify() and not local
	var m := U.margin(GUTTER, 26, GUTTER, 96)
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(64)
	m.add_child(row)
	var left := U.vbox(0)
	left.custom_minimum_size = Vector2(1000, 0)
	row.add_child(left)
	var top := U.hbox(48)
	left.add_child(top)
	_now_cover(top)
	_now_angaben(top)
	left.add_child(U.spacer(0, 40, false))
	_now_fortschritt(left)
	left.add_child(U.spacer(0, 22, false))
	left.add_child(_controls(spotify, local))
	left.add_child(U.spacer(0, 22, false))
	var lyr_on := bool(Config.get_value("music.lyrics", false))
	_now_fuss(left, spotify, local, lyr_on)
	_now_seite(row, spotify, local, lyr_on)
	_refresh()
	Music.read_app_level()


## Albumbild mit Schatten und farbigem Schein dahinter.
func _now_cover(top: Control) -> void:
	# Albumbild mit farbigem Schein dahinter (Farbe aus dem Bild); ohne Bild ein ruhiger Farbton.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(COVER, COVER)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(holder)
	_glow = _Glow.new()
	_glow.position = Vector2(-110, -100)
	_glow.size = Vector2(COVER + 220, COVER + 220)
	holder.add_child(_glow)
	# Schatten auf eigener Fläche: auf dem zuschneidenden Rahmen zeigt der Kompatibilitäts-
	# Renderer im Schattenbereich Reste früherer Bilder (siehe DESIGN.md › Schatten).
	var shade := Panel.new()
	shade.size = Vector2(COVER, COVER)
	var fsb := UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover())
	fsb.shadow_color = Color(0, 0, 0, 0.45)
	fsb.shadow_size = 36
	fsb.shadow_offset = Vector2(0, 18)
	shade.add_theme_stylebox_override("panel", fsb)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(shade)
	var frame := Panel.new()
	frame.size = Vector2(COVER, COVER)
	frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	_ph = TextureRect.new()
	_ph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ph.stretch_mode = TextureRect.STRETCH_SCALE
	_ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_ph)
	frame.add_child(_ph)
	var ic := U.icon("music", 140, "text")
	ic.modulate = Color(1, 1, 1, 0.42)
	ic.size = Vector2(140, 140)
	ic.position = (Vector2(COVER, COVER) - Vector2(140, 140)) * 0.5
	frame.add_child(ic)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_art)
	frame.add_child(_art)
	_art_url = "-"


## Neben dem Bild: Zustand, Titel, Interpret, Album und wer mithört.
func _now_angaben(top: Control) -> void:
	var info := U.vbox(8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(info)
	var st := U.hbox(10)
	_eq = _Eq.new()
	_eq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.add_child(_eq)
	_state = U.label("Läuft gerade", "xs", "music", "medium")
	_state.clip_text = false
	st.add_child(_state)
	info.add_child(st)
	_t = U.label("", "xxl", "text", "black", true)
	_t.max_lines_visible = 3
	_t.add_theme_constant_override("line_spacing", -6)
	U.shadow(_t)
	info.add_child(_t)
	_a = U.ellipsis(U.label("", "l", "muted", "medium"))
	info.add_child(_a)
	_album = U.ellipsis(U.label("", "m", "faint"))
	info.add_child(_album)
	# Wer mithört (Discord-Status zeigt denselben Titel) oder zum Zusammenhören eingeladen ist.
	_together = U.ellipsis(U.label("", "s", "music", "medium"))
	_together.visible = false
	info.add_child(_together)


## Fortschritt mit den beiden Zeiten darunter.
func _now_fortschritt(left: Control) -> void:
	# Fortschritt (auch ohne Spotify, wenn Windows die Länge kennt)
	_bar = ProgressBarUz.new().setup(0.0, "text", 6, 0)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_bar)
	var times := U.hbox(0)
	_times = times
	# Zeiten sind Zahlen und ändern sich jede Sekunde: nie durch die Übersetzung.
	_time = U.label("", "15", "muted", "medium")
	_time.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	times.add_child(_time)
	times.add_child(U.spacer())
	_left = U.label("", "15", "muted", "medium")
	_left.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	times.add_child(_left)
	var tm := U.margin(0, 8, 0, 0)
	tm.add_child(times)
	left.add_child(tm)


## Fußzeile: Gerät, Künstler, Songtext, Vollbild und ein kurzer Hinweis, wenn etwas fehlt.
func _now_fuss(left: Control, spotify: bool, local: bool, lyr_on: bool) -> void:
	# Unten: auf welchem Gerät es spielt (wählbar) und ein kurzer Hinweis, wenn etwas fehlt.
	var foot := U.hbox(18)
	left.add_child(foot)
	_device = null
	if spotify:
		_device = U.button("", "speaker", "flat")
		_device.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_device.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_device.set_meta("uz_hint_a", "Gerät wechseln")
		_device.set_meta("uz_key", "now:device")
		_device.pressed.connect(_pick_device)
		if UzTheme.strict():
			U.ruhig(_device, "flach", 16)
		foot.add_child(_device)
	# Zum Künstler: Bild, beliebte Titel, Alben (über die Spotify-Schnittstelle).
	_artist_btn = null
	if (Music.has_spotify() or Music.demo()) and not local and not Music.grundmodus():
		_artist_btn = U.button("Zum Künstler", "user", "flat")
		_artist_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_artist_btn.set_meta("uz_key", "now:artist")
		_artist_btn.pressed.connect(func() -> void: Bits.open_artist(main, Music.artist_of_now()))
		if UzTheme.strict():
			U.ruhig(_artist_btn, "flach", 16)
		foot.add_child(_artist_btn)
	# Songtext an/aus (merkt sich die Wahl); rechts erscheinen dann die mitlaufenden Zeilen.
	var lyr := U.button("Songtext", "subtitles", "primary" if lyr_on else "flat")
	lyr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lyr.set_meta("uz_hint_a", "Songtext aus" if lyr_on else "Songtext an")
	lyr.set_meta("uz_key", "now:lyrics")
	lyr.pressed.connect(func() -> void:
		Config.set_value("music.lyrics", not bool(Config.get_value("music.lyrics", false)))
		_rebuild_keep()
	)
	if UzTheme.strict():
		# Wie ein Schalter: an trägt das Zeichen den Akzent, keine gefüllte Fläche.
		U.ruhig(lyr, "flach", 16)
		if lyr_on:
			for k in ["icon_normal_color", "icon_hover_color", "icon_focus_color", "icon_pressed_color", "icon_hover_pressed_color"]:
				lyr.add_theme_color_override(k, UzTheme.col("accent"))
	foot.add_child(lyr)
	# Groß: Cover, Liedtext und Steuerung über den ganzen Schirm (jetzt_laeuft.gd).
	var gross := U.button("Vollbild", "fullscreen", "flat")
	gross.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gross.set_meta("uz_hint_a", "Groß anzeigen")
	gross.set_meta("uz_key", "now:gross")
	gross.pressed.connect(func() -> void: JetztLaeuft.zeigen(main))
	if UzTheme.strict():
		U.ruhig(gross, "flach", 16)
	foot.add_child(gross)
	_note = U.label("", "s" if spotify else "m", "faint", "medium", true)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_note)


## Rechts: Songtext, Warteschlange, die Karte der eigenen Musik oder der Hinweis auf Spotify.
func _now_seite(row: Control, spotify: bool, local: bool, lyr_on: bool) -> void:
	if lyr_on:
		var lp := LyricsPanel.new()
		lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(lp)
	elif local:
		if LocalUi.state() != "":
			row.add_child(LocalUi.card(main, true))
		else:
			_build_queue_panel(row)
	elif spotify and _problem() != "":
		var side := _problem_card("", Callable(), true)
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(side)
	elif spotify:
		_build_queue_panel(row)
	else:
		_build_spotify_hint(row)


## Steuerung: Zufall, Zurück, Abspielen (groß), Weiter, Wiederholen, Herz – rechts die Lautstärke.
func _controls(spotify: bool, local := false) -> Control:
	var ctl := U.hbox(14)
	ctl.set_meta("uz_group", "music-ctl")
	ctl.set_meta("uz_mem", true)
	if spotify or local:
		_shuffle = U.button("", "shuffle", "icon")
		_shuffle.set_meta("uz_hint_a", "Zufall")
		_shuffle.set_meta("uz_key", "now:shuffle")
		_shuffle.pressed.connect(func() -> void: Music.set_shuffle(not bool(Music.now.get("shuffle", false))))
		ctl.add_child(_shuffle)
	var prev := U.button("", "prev", "icon")
	prev.set_meta("uz_hint_a", "Zurück")
	prev.set_meta("uz_hint_x", "−15 s")
	prev.set_meta("uz_on_x", func() -> void: Music.seek(-15000))
	prev.set_meta("uz_key", "now:prev")
	prev.pressed.connect(func() -> void: Music.previous())
	ctl.add_child(prev)
	_play = U.button("Pause", "pause", "primary")
	_play.custom_minimum_size = Vector2(196, 64)
	# Eckig (Marke): dieselbe Symbol-Sprache wie im Guide-Reiter Musik – Abspielen ist ein großer
	# Symbolknopf mit Haarlinie, ohne Wort (das Wort steht unten bei A).
	if UzTheme.strict():
		_play.text = ""
		_play.custom_minimum_size = Vector2(72, 72)
		_play.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_play.set_meta("uz_hint_a", "Pause")
	_play.set_meta("uz_default", true)
	_play.set_meta("uz_entry", true)
	_play.set_meta("uz_key", "now:play")
	_play.pressed.connect(func() -> void: Music.play_pause())
	ctl.add_child(_play)
	var nxt := U.button("", "next", "icon")
	nxt.set_meta("uz_hint_a", "Nächster Titel")
	nxt.set_meta("uz_hint_x", "+15 s")
	nxt.set_meta("uz_on_x", func() -> void: Music.seek(15000))
	nxt.set_meta("uz_key", "now:next")
	nxt.pressed.connect(func() -> void: Music.next())
	ctl.add_child(nxt)
	if spotify or local:
		_repeat = U.button("", "repeat", "icon")
		_repeat.set_meta("uz_hint_a", "Wiederholen")
		_repeat.set_meta("uz_key", "now:repeat")
		_repeat.pressed.connect(func() -> void: Music.cycle_repeat())
		ctl.add_child(_repeat)
	_like = null
	if spotify and not Music.grundmodus():
		_like = U.button("", "heart", "icon")
		_like.set_meta("uz_hint_a", "Lieblingssong")
		_like.set_meta("uz_key", "now:like")
		_like.pressed.connect(func() -> void: Music.toggle_like())
		ctl.add_child(_like)
	for b in ctl.get_children():
		(b as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if Config.is_windows() or spotify or local or Music.demo():
		ctl.add_child(U.spacer())
		ctl.add_child(_vol_slider())
	return ctl


## Lautstärke der Musik als Regler am Ende der Leiste: gewählt stellen links/rechts leiser bzw.
## lauter (wie ein Regler in den Einstellungen), A schaltet stumm und wieder an. LT/RT wechseln
## hier wie überall den Bereich (nicht die Lautstärke). Nur der Musik-Player (Music.change_volume), nie die
## Gesamtlautstärke von Windows. Früher: zwei kleine Knöpfe ganz rechts, Pegel nur mit Spotify –
## und lehnte Spotify ab (kein Premium, Gerät ohne Lautstärke), passierte nichts.
func _vol_slider() -> Button:
	var b := U.button("", "", "flat")
	b.custom_minimum_size = Vector2(VOL_W, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_meta("uz_key", "now:volume")
	b.set_meta("uz_hint_a", "Stumm")
	b.set_meta("uz_grid_nav", func(_c: Control, dir: String) -> bool:
		if dir == "left" or dir == "right":
			_vol(VOL_STEP if dir == "right" else -VOL_STEP)
			return true
		return false
	)
	b.pressed.connect(_vol_mute)
	# Maus: links leiser, rechts lauter (A bzw. Klick in die Mitte: stumm).
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var x := (e as InputEventMouseButton).position.x
			if x < 64.0 or x > b.size.x - 64.0:
				_vol(VOL_STEP if x > b.size.x * 0.5 else -VOL_STEP)
				b.accept_event()
	)
	var row := U.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(row)
	row.offset_left = 20
	row.offset_right = -20
	b.add_child(row)
	var lo := U.icon("volume_down", 24, "text")
	lo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lo)
	var bar = ProgressBarUz.new().setup(0.0, "text", 6, 0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	_vol_bar = bar
	var hi := U.icon("volume", 24, "text")
	hi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hi)
	var lab := U.label("–", "15", "text", "ui_bold")
	lab.custom_minimum_size = Vector2(52, 0)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	_vol_label = lab
	# Gewählt liegt der Regler auf heller Fläche: Symbole, Balken und Zahl in der Schrift darauf.
	var paint := func(on: bool) -> void:
		var ink := UzTheme.col("on_focus") if on else UzTheme.col("text")
		lo.modulate = ink
		hi.modulate = ink
		lab.add_theme_color_override("font_color", ink)
		bar.color_name = "on_focus" if on else "text"
		bar.queue_redraw()
	b.focus_entered.connect(paint.bind(true))
	b.focus_exited.connect(paint.bind(false))
	_vol_btn = b
	return b


## Rechts: „Als Nächstes“ auf einer Glasfläche, unten weich auslaufend (nie hart abgeschnitten).
func _build_queue_panel(row: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	var sb := UzTheme.glass(UzTheme.r_panel())
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 26
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(panel)
	var col := U.vbox(8)
	panel.add_child(col)
	var hm := U.margin(18, 0, 18, 6)
	var head := U.hbox(12)
	hm.add_child(head)
	col.add_child(hm)
	var hl := U.label("Als Nächstes", "l", "text", "bold")
	hl.clip_text = false
	head.add_child(hl)
	_queue_title = hl
	head.add_child(U.spacer())
	_queue_head = U.label("", "s", "faint", "medium")
	_queue_head.clip_text = false
	_queue_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_queue_head)
	var mask := TrackPage.fade_mask(col)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 110.0)
	U.full_rect(sc)
	mask.add_child(sc)
	var inner := U.vbox(0)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	_queue_box = U.vbox(2)
	_queue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_box.set_meta("uz_group", "music-queue")
	_queue_box.set_meta("uz_mem", true)
	inner.add_child(_queue_box)
	inner.add_child(U.spacer(0, 90, false))
	_fill_queue()


## Ohne Spotify: rechts ruhig erklären, was mit Spotify dazukäme (freiwillig).
func _build_spotify_hint(row: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	var sb := UzTheme.glass(UzTheme.r_panel())
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 36
	sb.content_margin_bottom = 38
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(panel)
	var col := U.vbox(14)
	panel.add_child(col)
	var sp := U.icon("spark", 30, "accent")
	sp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(sp)
	col.add_child(U.label("Mehr mit Spotify", "xl", "text", "bold"))
	col.add_child(U.label("Mit deinem Spotify-Konto kommen dazu:", "m", "muted", "regular", true))
	for line in [["spark", "Für dich: Mixe aus deinen Hördaten und Neues von deinen Künstlern"],
			["list", "Playlists, Lieblingssongs und die Warteschlange"],
			["speaker", "Abspielen auf PC, Handy oder Lautsprecher"]]:
		var hb := U.hbox(14)
		var ic := U.icon(str(line[0]), 22, "muted")
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		hb.add_child(ic)
		var l := U.label(str(line[1]), "m", "text", "regular", true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		col.add_child(hb)
	col.add_child(U.spacer(0, 6, false))
	var b := U.button("In den Einstellungen verbinden", "settings")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_key", "now:connect")
	b.pressed.connect(func() -> void: main.goto("settings", "konten"))
	col.add_child(b)
	col.add_child(U.label("Optional.", "s", "faint", "medium", true))


var _vol_pending := 0
var _vol_busy := false
var _vol_before_mute := -1


## Läufe von _vol, die gerade unterwegs sind (siehe dort).
var _vol_offen := 0


## Lautstärke der Musik um delta Prozentpunkte (Regler). Schnelle Schritte werden
## gesammelt und nacheinander geschickt; der Regler zeigt den echten Pegel.
func _vol(delta: int) -> void:
	_vol_offen += 1
	await _vol_lauf(delta)
	_vol_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _vol täte bis zum Neustart nichts mehr.
	if _vol_offen == 0 and _vol_busy:
		_vol_busy = false


func _vol_lauf(delta: int) -> void:
	_vol_pending += delta
	Sfx.play("tick", 1.0 + 0.08 * signf(delta))
	if _vol_busy:
		return
	_vol_busy = true
	while _vol_pending != 0:
		var step := clampi(_vol_pending, -100, 100)
		_vol_pending -= step
		var r: Dictionary = await Music.change_volume(step)
		if not is_inside_tree():
			break
		if not bool(r.get("ok", false)):
			_vol_pending = 0
			Toasts.show_toast(vol_fail_text(str(r.get("why", "")), str(Music.now.get("device", ""))), "", "volume", { "ms": 1600, "quiet": true })
		_refresh_volume()
	_vol_busy = false


## A auf dem Regler: stumm bzw. wieder auf den Pegel davor.
func _vol_mute() -> void:
	var cur := Music.shown_volume()
	if cur < 0:
		# Pegel der App noch unbekannt: erst lesen.
		await Music.read_app_level()
		if not is_inside_tree():
			return
		cur = Music.shown_volume()
	if cur > 0:
		_vol_before_mute = cur
		_vol(-cur)
	elif cur == 0:
		_vol(_vol_before_mute if _vol_before_mute > 0 else 40)
	else:
		Toasts.show_toast(vol_fail_text("kein_ton" if not Music.now.is_empty() else "keine_musik", str(Music.now.get("device", ""))), "", "volume",
				{ "ms": 1600, "quiet": true })


## Warum sich die Lautstärke nicht ändern ließ (Hinweis unten).
static func vol_fail_text(why: String, device: String) -> String:
	match why:
		"keine_musik":
			return "Gerade läuft keine Musik"
		"spotify_fest":
			return ("%s lässt sich hier nicht leiser stellen" % device) if device != "" else "Lautstärke hier nicht änderbar"
		"fehler":
			return "Lautstärke gerade nicht erreichbar"
	return "Kein Ton von %s gefunden" % (device if device != "" else "der Musik-App")


func _refresh_volume() -> void:
	if _vol_bar == null or not is_instance_valid(_vol_bar):
		return
	var vol := Music.shown_volume()
	_vol_bar.set_value(float(maxi(vol, 0)) / 100.0)
	_vol_label.text = ("%d %%" % vol) if vol >= 0 else "–"
	if is_instance_valid(_vol_btn):
		_vol_btn.set_meta("uz_hint_a", "Ton an" if vol == 0 else "Stumm")


func _fill_queue() -> void:
	if _queue_box == null or not is_instance_valid(_queue_box):
		return
	var keep := Nav.focused()
	var had_focus := keep != null and _queue_box.is_ancestor_of(keep)
	U.clear(_queue_box)
	var list: Array = Music.queue_list
	if is_instance_valid(_queue_head):
		var ctx := _context_name()
		_queue_head.text = ("aus " + ctx) if ctx != "" else (U.plural(list.size(), "Titel", "Titel") if not list.is_empty() else "")
	# Grundmodus ohne Warteschlange (Spotify Connect nennt die Titel nicht): rechts der eigene Verlauf.
	var hist := Music.grundmodus() and list.is_empty() and not Music.local_on()
	if is_instance_valid(_queue_title):
		_queue_title.text = "Zuletzt gehört" if hist else "Als Nächstes"
	if hist:
		var rec := Verlauf.recent(Music.verlauf_list(), 12).filter(func(t: Dictionary) -> bool: return str(t.uri) != str(Music.now.get("uri", "")))
		if is_instance_valid(_queue_head):
			_queue_head.text = "nur auf diesem PC" if not rec.is_empty() else ""
		if rec.is_empty():
			var mh := U.margin(18, 16, 18, 0)
			var lh := U.label("Noch kein Verlauf.", "m", "faint", "regular", true)
			lh.custom_minimum_size = Vector2(480, 0)
			mh.add_child(lh)
			_queue_box.add_child(mh)
			return
		for i in rec.size():
			var th: Dictionary = rec[i]
			var rh = TrackRow.new().setup(th)
			rh.show_album = false
			rh.set_meta("uz_hint_a", "Abspielen")
			if i == 0:
				rh.set_meta("uz_entry", true)
			rh.chosen.connect(func(_t: Dictionary) -> void: _play_track(th))
			_queue_box.add_child(rh)
		if had_focus:
			var fh := Nav.default_in(_queue_box)
			if fh:
				Nav.focus(fh, true)
		return
	if list.is_empty():
		var m := U.margin(18, 16, 18, 0)
		var col := U.vbox(10)
		m.add_child(col)
		col.add_child(U.label("Die Warteschlange ist leer", "m", "text", "bold"))
		var hint := "Warteschlange leer." if Music.local_on() \
			else "Warteschlange leer."
		var l := U.label(hint, "m", "faint", "regular", true)
		l.custom_minimum_size = Vector2(480, 0)
		col.add_child(l)
		_queue_box.add_child(m)
		return
	for i in list.size():
		var t: Dictionary = list[i]
		var r = TrackRow.new().setup(t)
		r.show_album = false
		r.set_meta("uz_hint_a", "Jetzt spielen")
		if i == 0:
			r.set_meta("uz_entry", true)
		var skip := i
		r.chosen.connect(func(_t: Dictionary) -> void: _skip_to(skip))
		_queue_box.add_child(r)
	if had_focus:
		var first := Nav.default_in(_queue_box)
		if first:
			Nav.focus(first, true)


## Name der laufenden Liste (Playlist, Album, Mix), wenn Uzai sie kennt.
func _context_name() -> String:
	var ctx := str(Music.now.get("context", ""))
	if Music.local_on():
		return str(Music.local.context_name)
	if ctx == "":
		return ""
	for list in [Music.playlists, Music.spotify_mixes, Music.saved_albums, Music.new_releases]:
		for p in list:
			if p is Dictionary and str(p.get("uri", "")) == ctx:
				return str(p.get("name", ""))
	return ""


## In der Warteschlange springen: Spotify kennt nur „Weiter“, also so oft weiter wie nötig.
func _skip_to(idx: int) -> void:
	if Music.local_on():
		Music.local.skip_to(idx)
		return
	for i in mini(idx + 1, 20):
		await Music._control(HTTPClient.METHOD_POST, "/me/player/next")
	Music._later_poll(true)


func _pick_device() -> void:
	var list := await Music.devices()
	var opts: Array = []
	for d in list:
		opts.append([str(d.id), str(d.name) + ("  ·  läuft" if d.active else ("  ·  nicht steuerbar" if bool(d.get("restricted", false)) else ""))])
	if Config.is_windows() and not Music.pc_dabei(list, OS.get_environment("COMPUTERNAME")):
		opts.append(["__start", "Dieser PC"])
	if opts.is_empty():
		Toasts.show_toast("Kein Gerät gefunden", "Keine Geräte.", "speaker")
		return
	main.open_choice("Abspielen auf", opts, "", func(dev_id: Variant) -> void:
		if str(dev_id) == "__start":
			var dev := await Music.start_here()
			if dev != "":
				Music.switch_to(dev)
			return
		Music.switch_to(str(dev_id))
	)


# --- Playlists, Lieblingssongs, Zuletzt gehört ---------------------------------------------------

func _build_playlists() -> void:
	var col := _scroll_page(40.0)
	var grid := GridContainer.new()
	grid.columns = U.cols_for(6)
	grid.add_theme_constant_override("h_separation", int((1728.0 - GRID_W * 6.0) / 5.0))
	grid.add_theme_constant_override("v_separation", 40)
	grid.set_meta("uz_group", "playlists")
	grid.set_meta("uz_mem", true)
	var pad := U.margin(GUTTER, 34, GUTTER, 60)
	pad.add_child(grid)
	if Music.problem != "" and not (Music.playlists.is_empty() and Music.liked_list.is_empty()):
		col.add_child(_problem_card())
	col.add_child(pad)
	if Music.playlists.is_empty() and Music.liked_list.is_empty():
		# Kamen die Playlists nicht an, steht dort der Grund – nicht für immer graue Platzhalter.
		if Music.playlists_state == "fehler" or Music.problem != "":
			pad.queue_free()
			col.add_child(_problem_card(Music.list_error if Music.problem == "" else "", func() -> void:
				_asked.erase("playlists")
				Music.load_playlists()
				_rebuild_soon()))
			return
		_ask("playlists", func() -> void: Music.load_playlists())
		for i in 6:
			grid.add_child(Skeleton.tile(GRID_W))
		return
	var items: Array = [_liked_item()] + Music.playlists
	var baue := func(i: int) -> Control:
		var tile := _tile(items[i], GRID_W)
		if i == 0:
			tile.set_meta("uz_default", true)
			tile.set_meta("uz_entry", true)
		return tile
	U.in_scheiben(grid, items.size(), baue, KACHELN_SOFORT, KACHELN_JE_BILD, _halten_bis("playlists"))


## Lieblingssongs und Zuletzt gehört: großer Kopf links, Titel rechts (wie eine Playlist).
func _build_library(kind: String) -> void:
	var liked := kind == "liked"
	var list: Array = Music.liked_list if liked else Music.recent_list
	var info := {
		"kind": kind, "id": kind, "name": "Lieblingssongs" if liked else "Zuletzt gehört",
		"kicker": "Deine Bibliothek" if liked else "Deine letzten Titel", "icon": "heart_f" if liked else "history",
		"hue": float(Music.HUES.liked) if liked else float(Music.HUES["mix:zuletzt"]),
		"count": list.size(), "tracks": list,
		"empty_text": "Mit Y hinzufügen." if liked else "Noch nichts gehört.",
	}
	var page = TrackPage.new()
	page.info = info
	page.cover = 340.0
	page.margins = [GUTTER, 26, GUTTER, 8]
	page.group = "tracks:" + kind
	page.loader = func() -> Array:
		if not _asked.has(kind):
			_asked[kind] = true
			if liked:
				await Music.load_liked()
			else:
				await Music.load_recent()
		return Music.liked_list if liked else Music.recent_list
	U.full_rect(page)
	add_child(page)


# --- Suche ---------------------------------------------------------------------------------------

func _build_search() -> void:
	var col := _scroll_page()
	var top := U.margin(GUTTER, 4, GUTTER, 26)
	var hb := U.hbox(14)
	top.add_child(hb)
	var b := U.button(("„%s“ – neue Suche" % _search_q) if _search_q != "" else "Titel, Künstler oder Album suchen", "search", "primary" if _search_q == ""
			else "normal")
	b.set_meta("uz_default", true)
	b.set_meta("uz_key", "ms:suche")
	b.pressed.connect(func() -> void: main.open_keyboard("Musik suchen", _search_q, _run_search))
	hb.add_child(b)
	col.add_child(top)
	if _search_res.get("loading", false):
		var lm := U.margin(GUTTER, 6, GUTTER, 0)
		lm.add_child(U.label("Sucht …", "l", "muted"))
		col.add_child(lm)
		return
	if _search_q == "":
		_suggestions(col)
		return
	var tracks: Array = _search_res.get("tracks", [])
	var artists: Array = _search_res.get("artists", [])
	var albums: Array = _search_res.get("albums", [])
	var pls: Array = _search_res.get("playlists", [])
	if tracks.is_empty() and albums.is_empty() and pls.is_empty() and artists.is_empty():
		var m2 := U.margin(GUTTER, 10, GUTTER, 6)
		var err := str(_search_res.get("error", ""))
		m2.add_child(U.label(err if err != "" else "Keine Treffer.", "l", "muted", "regular", true))
		col.add_child(m2)
		return
	if not artists.is_empty():
		col.add_child(_shelf_box("Künstler", "", artists, "s-kuenstler", TILE_W))
	if not tracks.is_empty():
		col.add_child(section_title("Titel", U.plural(tracks.size(), "Treffer", "Treffer")))
		var rows := U.vbox(2)
		var rm := U.margin(GUTTER - 16, 8, GUTTER - 16, 18)
		rm.add_child(rows)
		col.add_child(rm)
		_track_rows(rows, tracks, "suche")
	if not albums.is_empty():
		col.add_child(_shelf_box("Alben", "", albums, "s-alben", TILE_W))
	if not pls.is_empty():
		col.add_child(_shelf_box("Playlists", "", pls, "s-playlists", TILE_W))
	col.add_child(U.spacer(0, 40, false))


func _run_search(q: String) -> void:
	_search_q = q.strip_edges()
	if _search_q == "":
		return
	_searched.erase(_search_q)
	_searched.push_front(_search_q)
	_searched = _searched.slice(0, 6)
	_search_res = { "loading": true }
	_rebuild_keep()
	var term := _search_q
	var res: Dictionary = await Music.search(term)
	# Inzwischen neu gesucht: Die ältere Antwort gehört nicht unter das neue Suchwort (und die neue Suche läuft noch).
	if term != _search_q:
		return
	_search_res = res
	if visible and sub == "suche":
		_rebuild_keep()


## Vor der ersten Suche: zuletzt Gesuchtes und deine Künstler als Vorschläge (ein Druck sucht).
func _suggestions(col: VBoxContainer) -> void:
	var artists: Array = []
	for list in [Music.top_tracks, Music.recent_list, Music.liked_list]:
		for t in list:
			var a := str(t.get("artist", "")).get_slice(",", 0).strip_edges() if t is Dictionary else ""
			if a != "" and not artists.has(a):
				artists.append(a)
	# Läuft gerade etwas: gleich zum Künstler (Bild, beliebte Titel, Alben).
	var cur := Music.artist_of_now()
	if not cur.is_empty():
		col.add_child(section_title("Läuft gerade"))
		var cm := U.margin(GUTTER, 10, GUTTER, 22)
		var cb := U.button("Zum Künstler: " + str(cur.name), "user", "flat")
		cb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cb.set_meta("uz_key", "msugg:artist")
		cb.set_meta("uz_hint_a", "Künstlerseite öffnen")
		cb.pressed.connect(func() -> void: Bits.open_artist(main, Music.artist_of_now()))
		cm.add_child(cb)
		col.add_child(cm)
	for group in [["Zuletzt gesucht", _searched, "history"], ["Deine Künstler", artists.slice(0, 10), "user"]]:
		var words: Array = group[1]
		if words.is_empty():
			continue
		col.add_child(section_title(str(group[0])))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		flow.set_meta("uz_group", "msugg:" + str(group[0]))
		var fm := U.margin(GUTTER, 10, GUTTER, 22)
		fm.add_child(flow)
		col.add_child(fm)
		for w in words:
			var pb := U.button(str(w), str(group[2]), "flat")
			pb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Eingetipptes und Namen: nie übersetzen
			pb.set_meta("uz_hint_a", "Suchen")
			pb.set_meta("uz_key", "msugg:" + str(w))
			var q := str(w)
			pb.pressed.connect(func() -> void: _run_search(q))
			flow.add_child(pb)


func _track_rows(into: Control, list: Array, group: String, numbered := false) -> void:
	into.set_meta("uz_group", "tracks:" + group)
	into.set_meta("uz_mem", true)
	for i in list.size():
		var t: Dictionary = list[i]
		var r = TrackRow.new().setup(t, i + 1 if numbered else 0)
		r.set_meta("uz_hint_a", "Abspielen")
		r.set_meta("uz_hint_x", "Als Nächstes")
		r.set_meta("uz_on_x", func() -> void:
			Music.enqueue(str(t.uri))
			Toasts.show_toast("Kommt als Nächstes", str(t.title), "music", { "ms": 1400, "quiet": true })
		)
		var liked := Music.is_liked(str(t.id))
		r.set_meta("uz_hint_y", "Kein Lieblingssong mehr" if liked else "Lieblingssong")
		r.set_meta("uz_on_y", func() -> void:
			var was := Music.is_liked(str(t.id))
			Music.toggle_like(str(t.id))
			r.set_meta("uz_hint_y", "Lieblingssong" if was else "Kein Lieblingssong mehr")
			Toasts.show_toast("Aus Lieblingssongs entfernt" if was else "Zu Lieblingssongs", str(t.title), "heart" if was else "heart_f", { "ms": 1400, "quiet": true })
		)
		if i == 0:
			r.set_meta("uz_entry", true)
		var idx := i
		r.chosen.connect(func(_t: Dictionary) -> void: Music.play_list(list, idx))
		into.add_child(r)


# --- Eigene Musik (Musikquelle „lokal“) ------------------------------------------------------------

## Alben und Interpreten als Raster, Titel als Liste. Fehlt noch etwas (kein Ordner, liest ein,
## leer), steht dort die Karte zum Einrichten.
func _build_local(kind: String) -> void:
	var lm: Node = Music.local
	if LocalUi.state() == "ordner":
		# Noch kein Ordner: die Bühne mit angedeuteten Alben statt einer Textkarte. A nimmt gleich den
		# Windows-Ordner „Musik“ (wenn es ihn gibt), daneben ein anderer Ordner und – ohne Konto –
		# Spotify verbinden. Mit Spotify zeigt der Bereich danach beide Quellen.
		var sug := LocalMusic.suggested_root()
		var hat_sug := sug != "" and DirAccess.dir_exists_absolute(sug)
		var o := { "art": "musik", "symbol": "music", "titel": "Deine Musik in Uzai.",
			"zeile": "Ordner wählen – Alben, Interpreten und Cover kommen von selbst.",
			"fertig": func() -> bool: return LocalUi.state() != "ordner" }
		if hat_sug:
			o["knopf"] = "Ordner „%s“ nehmen" % sug.get_file()
			o["tun"] = func() -> void: Config.set_value("music.local_dir", sug)
			o["neben"] = "Anderer Ordner"
			o["neben_tun"] = func() -> void: LocalUi.pick_folder(main)
		else:
			o["knopf"] = "Musikordner wählen"
			o["tun"] = func() -> void: LocalUi.pick_folder(main)
		if not Music.has_spotify():
			o[("dritte" if hat_sug else "neben")] = "Mit Spotify anmelden"
			o[("dritte_tun" if hat_sug else "neben_tun")] = LeerBuehne.weg(main, "spotify")
		add_child(leer_buehne(o))
		return
	if LocalUi.state() in ["leer", "fehlt"]:
		# Ordner gewählt, aber nichts Spielbares da (oder nicht erreichbar): dieselbe Bühne wie ohne
		# Ordner – links die eigene Musik (anderer Ordner, neu einlesen), rechts Spotify verbinden.
		var leer := LocalUi.state() == "leer"
		var ordner := LocalMusic.root().get_file()
		add_child(leer_buehne({ "art": "musik", "symbol": "music",
			"titel": "Keine Musik gefunden." if leer else "Musikordner nicht erreichbar.",
			"zeile": ("In „%s“ liegen keine MP3-, OGG- oder WAV-Dateien." % ordner) if leer
				else ("„%s“ ist gerade nicht da – vielleicht eine abgezogene Festplatte." % ordner),
			"knopf": "Anderer Ordner", "tun": func() -> void: LocalUi.pick_folder(main),
			"neben": "Zu Spotify wechseln" if Music.has_spotify() else "Mit Spotify anmelden",
			"neben_tun": (func() -> void: Config.set_value("system.music_mode", "spotify")) if Music.has_spotify()
				else LeerBuehne.weg(main, "spotify"),
			"dritte": "Neu einlesen", "dritte_tun": func() -> void: Music.local.scan(true),
			"fertig": func() -> bool: return not (LocalUi.state() in ["leer", "fehlt"]) or Music.mode() != "lokal" }))
		return
	if LocalUi.state() != "":
		var col := _scroll_page(40.0)
		var pad := U.margin(GUTTER, 30, GUTTER, 40)
		pad.add_child(LocalUi.card(main))
		col.add_child(pad)
		return
	if kind == "titel":
		var list: Array = (lm.tracks as Array).slice(0, 2000)
		var page = TrackPage.new()
		page.info = { "kind": "lokal_titel", "id": "lokal:titel", "name": "Alle Titel", "kicker": "Eigene Musik", "icon": "music",
			"hue": 0.58, "count": (lm.tracks as Array).size(), "tracks": list,
			"empty_text": "Keine Titel im Musikordner." }
		page.cover = 340.0
		page.margins = [GUTTER, 26, GUTTER, 8]
		page.group = "tracks:lokal"
		U.full_rect(page)
		add_child(page)
		return
	var items: Array = lm.albums if kind == "alben" else lm.artists
	var col := _scroll_page(40.0)
	var grid := GridContainer.new()
	grid.columns = U.cols_for(6)      # wie die Playlists: bei großer Oberfläche weniger Spalten statt über den Rand
	grid.add_theme_constant_override("h_separation", int((1728.0 - GRID_W * 6.0) / 5.0))
	grid.add_theme_constant_override("v_separation", 40)
	grid.set_meta("uz_group", "lokal:" + kind)
	grid.set_meta("uz_mem", true)
	if not Music.has_spotify():
		col.add_child(_spotify_rand())
	var pad := U.margin(GUTTER, 34, GUTTER, 60)
	pad.add_child(grid)
	col.add_child(pad)
	var baue := func(i: int) -> Control:
		var it: Dictionary = items[i]
		var tile := LocalUi.tile(main, it, GRID_W)
		tile.focused_item.connect(func(_i: Dictionary) -> void: _on_tile_focus(it, tile))
		if i == 0:
			tile.set_meta("uz_default", true)
			tile.set_meta("uz_entry", true)
		return tile
	U.in_scheiben(grid, items.size(), baue, KACHELN_SOFORT, KACHELN_JE_BILD, _halten_bis("lokal:" + kind))


## Eigene Musik ohne Spotify: rechts oben am Rand, leise, „Spotify verbinden“ – kein Kasten mitten
## in der Sammlung. Mit Spotify kommen dessen Reiter dazu.
func _spotify_rand() -> Control:
	var m := U.margin(GUTTER, 22, GUTTER, 0)
	var row := U.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_END
	m.add_child(row)
	var b := U.button("Mit Spotify anmelden", "link")
	b.set_meta("uz_key", "lokal:spotify")
	b.pressed.connect(LeerBuehne.weg(main, "spotify"))
	row.add_child(b)
	return m


## Neben Spotify: die eigene Sammlung in einem Reiter. Alben und Interpreten als Reihen, darüber
## alle Titel, alles zufällig und der Ordner.
func _build_eigene() -> void:
	var lm: Node = Music.local
	var col := _scroll_page()
	if LocalUi.state() != "":
		var pad := U.margin(GUTTER, 30, GUTTER, 40)
		pad.add_child(LocalUi.card(main))
		col.add_child(pad)
		return
	var m := U.margin(GUTTER, 18, GUTTER, 4)
	var row := U.hbox(18)
	row.set_meta("uz_group", "lokal:wege")
	m.add_child(row)
	col.add_child(m)
	var alle := U.button("Alle Titel", "list", "flat")
	alle.set_meta("uz_key", "lokal:titel")
	alle.set_meta("uz_hint_a", "Titel ansehen")
	alle.pressed.connect(func() -> void:
		var l = TrackList.new()
		l.playlist = { "kind": "lokal_titel", "local": true, "id": "lokal:titel", "name": "Alle Titel", "icon": "music", "hue": 0.58,
			"count": (lm.tracks as Array).size(), "tracks": (lm.tracks as Array).slice(0, 2000) }
		l.main = main
		main.open_layer(l)
	)
	row.add_child(alle)
	var zufall := U.button("Alles zufällig", "shuffle", "flat")
	zufall.set_meta("uz_key", "lokal:zufall")
	zufall.set_meta("uz_hint_a", "Abspielen")
	zufall.pressed.connect(func() -> void:
		lm.set_shuffle(true)
		lm.play_tracks(lm.tracks, randi() % maxi(1, (lm.tracks as Array).size()), "", "Alle Titel")
	)
	row.add_child(zufall)
	var ordner := U.button("Anderer Ordner", "folder", "flat")
	ordner.set_meta("uz_key", "lokal:pick")
	ordner.pressed.connect(func() -> void: LocalUi.pick_folder(main))
	row.add_child(ordner)
	if (lm.albums as Array).size() > EIGENE_MAX:
		var mehr := U.button("Alle Alben", "music", "flat")
		mehr.set_meta("uz_key", "lokal:alben")
		mehr.pressed.connect(func() -> void: LocalUi.open_albums_sheet(main))
		row.add_child(mehr)
	for b in row.get_children():
		if UzTheme.strict():
			U.ruhig(b, "flach", 15)
	col.add_child(_shelf_box("Alben", U.plural((lm.albums as Array).size(), "Album", "Alben"), (lm.albums as Array).slice(0, EIGENE_MAX), "lokal:alben",
			TILE_W, false, true, _lokal_tile))
	if not (lm.artists as Array).is_empty():
		col.add_child(_shelf_box("Interpreten", U.plural((lm.artists as Array).size(), "Interpret", "Interpreten"), (lm.artists as Array).slice(0, EIGENE_MAX),
				"lokal:interpreten", TILE_W, false, false, _lokal_tile))
	col.add_child(U.spacer(0, 40, false))


func _lokal_tile(it: Dictionary, w: float) -> Control:
	var tile := LocalUi.tile(main, it, w)
	tile.focused_item.connect(func(_i: Dictionary) -> void: _on_tile_focus(it, tile))
	return tile


## Spotify ohne Musikordner: unten leise „Eigene Musik hinzufügen“.
func _eigene_dazu() -> Control:
	var m := U.margin(GUTTER, 34, GUTTER, 0)
	m.add_child(_eigene_knopf())
	return m


func _eigene_knopf() -> Button:
	var b := U.button("Eigene Musik hinzufügen", "folder", "flat")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_key", "lokal:dazu")
	b.set_meta("uz_hint_a", "Musikordner wählen")
	if UzTheme.strict():
		U.ruhig(b, "flach", 15)
	b.modulate = Color(1, 1, 1, 0.72)
	b.pressed.connect(func() -> void: LocalUi.pick_folder(main))
	return b


## Die spielende Quelle hat gewechselt: Läuft gerade passt Steuerung, Gerät und Liste an.
func _on_quelle() -> void:
	mark_stale()
	if visible and is_inside_tree() and sub == "jetzt" and Nav.top_layer() == null:
		_rebuild_soon()


## Neu eingelesen: Reiter (Anzahl) und die offene Seite neu.
func _on_local_library() -> void:
	if not Music.lokal_da() or not visible or not is_inside_tree():
		return
	if main:
		main.refresh_chips()
	if Nav.top_layer() == null:
		_rebuild_soon()


# --- Aktualisieren -------------------------------------------------------------------------------

func _refresh() -> void:
	if not visible or _art == null or not is_instance_valid(_art):
		return
	var now: Dictionary = Music.now
	var local := Music.local_on()
	var spotify := _spotify() and not local
	# Titel, Künstler und Album sind fremder Text und werden nie übersetzt (ein Lied „Heute“ hieße sonst „Today“,
	# und Zeilen mit „ · “ übersetzt der Katalog Stück für Stück). Die Sätze ohne Musik schon.
	var a_roh := not now.is_empty()
	if now.is_empty():
		_t.text = "Gerade läuft nichts"
		_a.text = "Wähle ein Album oder einen Titel." if local else ("Starte etwas aus „Für dich“." if spotify
				else "Starte Musik in Spotify oder deinem Musik-Player.")
		_album.text = ""
		if spotify and Music.grundmodus():
			var last := Verlauf.last(Music.verlauf_list())
			a_roh = not last.is_empty()      # von Hand übersetzt, mit Titel und Künstler darin
			_a.text = (tr("Zuletzt: %s · %s") % [str(last.t), str(last.a)]) if not last.is_empty() else "Starte etwas in Spotify oder aus deinem Verlauf."
	for l in [_t, _album]:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT if now.is_empty() else Node.AUTO_TRANSLATE_MODE_DISABLED
	_a.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if a_roh else Node.AUTO_TRANSLATE_MODE_INHERIT
	if not now.is_empty():
		_t.text = str(now.get("title", ""))
		_a.text = str(now.get("artist", ""))
		_album.text = str(now.get("album", ""))
	if is_instance_valid(_artist_btn):
		_artist_btn.visible = not Music.artist_of_now().is_empty()
	_refresh_together()
	var url := str(now.get("art", ""))
	if url != _art_url:
		_art_url = url
		_art.texture = null
		# Ohne Bild (oder bis es da ist): ein ruhiger Farbton aus dem Album, der Schein passt dazu.
		var h := float(absi(str(now.get("album", now.get("title", "uzai"))).hash()) % 1000) / 1000.0
		_ph.texture = MusicTile.tonal(h)
		if is_instance_valid(_glow):
			_glow.set_color(Color.from_hsv(h, 0.55, 0.75))
		if url == "" and main and main.background and not now.is_empty():
			main.background.show_blurred(_hue_tex(h), "music:ph%d" % int(h * 100.0))
		if url != "":
			Music.load_art(url, 640, func(t: Texture2D) -> void:
				if is_instance_valid(_art) and _art_url == url and t:
					_art.texture = t
					if is_instance_valid(_glow):
						var vc: Variant = Media.color_of(t)
						_glow.set_color(vc if vc is Color else UzTheme.col("accent"))
					if main and main.background:
						main.background.show_soft(t, "music:" + url)
			)
	var playing := bool(now.get("playing", false)) and not now.is_empty()
	if is_instance_valid(_state):
		_state.text = ("Läuft gerade" if playing else "Pausiert") if not now.is_empty() else ("Spotify" if spotify else ("Eigene Musik" if local else "Musik"))
	if _eq:
		_eq.playing = playing
	if is_instance_valid(_play):
		if UzTheme.strict():
			_play.set_meta("uz_hint_a", "Pause" if playing else "Abspielen")
			_play.icon = Icons.tex("pause" if playing else "play", 30)
		else:
			_play.text = "Pause" if playing else "Abspielen"
			_play.icon = Icons.tex("pause" if playing else "play", 26)
	if is_instance_valid(_like):
		_like.icon = Icons.tex("heart_f" if now.get("liked", false) else "heart", 26)
		_like.set_meta("uz_hint_a", "Kein Lieblingssong mehr" if now.get("liked", false) else "Lieblingssong")
	if is_instance_valid(_shuffle):
		_shuffle.modulate = Color.WHITE if now.get("shuffle", false) else Color(1, 1, 1, 0.5)
		_shuffle.set_meta("uz_hint_a", "Zufall: an" if now.get("shuffle", false) else "Zufall: aus")
	if is_instance_valid(_repeat):
		var rep := str(now.get("repeat", "off"))
		_repeat.modulate = Color(1, 1, 1, 0.5) if rep == "off" else Color.WHITE
		_repeat.set_meta("uz_hint_a", { "off": "Wiederholen: aus", "context": "Wiederholen: Liste", "track": "Wiederholen: Titel" }.get(rep, "Wiederholen"))
	if is_instance_valid(_device):
		var dev := str(now.get("device", ""))
		_device.text = ("Spielt auf " + dev) if dev != "" else "Gerät wählen"
	var dur := int(now.get("duration", 0))
	if _bar != null and is_instance_valid(_bar):
		_bar.visible = dur > 0
		_times.visible = dur > 0
		_tick_time()
	_refresh_volume()
	if is_instance_valid(_note):
		var note := ""
		if local:
			note = ("Aus deinem Musikordner · %s" % str(Music.local.context_name)) if str(Music.local.context_name) != "" and not now.is_empty() else ""
		elif Music.starting:
			note = "Spotify startet im Hintergrund …"
		elif spotify:
			if Music.error != "":
				note = Music.error
			elif now.is_empty() and Music.grundmodus():
				note = "„Abspielen“ macht weiter, wo du zuletzt warst."
			elif now.is_empty():
				note = ""
		elif now.is_empty():
			note = "Keine Wiedergabe."
		else:
			note = "Spielt auf %s. Gesteuert über die Medientasten." % str(now.get("device", "Windows"))
		_note.text = note


func _refresh_together() -> void:
	if not visible or _together == null or not is_instance_valid(_together):
		return
	var line := Music.together_line(Music.listeners, Music.waiting()) if not Music.now.is_empty() else ""
	_together.text = line
	_together.visible = line != ""


var _tick_at := 0


func _process(_dt: float) -> void:
	if not visible or _bar == null or not is_instance_valid(_bar) or Music.now.is_empty():
		return
	var d := float(Music.now.get("duration", 1))
	_bar.set_value(float(Music.progress_ms()) / maxf(d, 1.0))
	if Time.get_ticks_msec() - _tick_at > 250:
		_tick_time()


## Zeiten unter dem Balken (vergangen, verbleibend).
func _tick_time() -> void:
	_tick_at = Time.get_ticks_msec()
	if not is_instance_valid(_time) or Music.now.is_empty():
		return
	var d := float(Music.now.get("duration", 0))
	var p := float(Music.progress_ms())
	_time.text = _fmt(p)
	_left.text = "−" + _fmt(maxf(0.0, d - p))


static func _fmt(ms: float) -> String:
	var s := int(ms / 1000.0)
	return "%d:%02d" % [int(s / 60.0), s % 60]


## Weicher, farbiger Schein hinter dem Albumbild; atmet ganz leicht, solange Musik läuft.
class _Glow extends Control:
	var color := Color(0.4, 0.5, 0.9)
	var _t := 0.0
	var _lief := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		color = UzTheme.col("accent")

	func set_color(c: Color) -> void:
		var tw := create_tween()
		tw.tween_method(func(v: Color) -> void:
			color = v
			queue_redraw()
		, color, c, 0.6)

	## Der Schein atmet nur, solange Musik läuft. Pausiert steht er still und zeichnet nicht neu (früher jedes
	## zweite Bild, auch ohne Musik).
	func _process(dt: float) -> void:
		if not bool(Music.now.get("playing", false)):
			if _lief:
				_lief = false
				queue_redraw()      # einmal zurück in die Ruhelage
			return
		_lief = true
		_t += dt
		if Engine.get_process_frames() % 2 == 0:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var breathe := 1.0 + 0.04 * sin(_t * 1.3) if bool(Music.now.get("playing", false)) else 1.0
		var rad := size.x * 0.5 * breathe
		draw_texture_rect(preload("res://src/ui/components/music_tile.gd").glow_tex(), Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false,
				Color(color, 0.42))


## Drei kleine Pegel neben „Läuft gerade“ (stehen still, wenn pausiert).
class _Eq extends Control:
	var playing := false
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(20, 18)

	func _process(dt: float) -> void:
		if playing:
			_t += dt
			queue_redraw()

	func _draw() -> void:
		var col := UzTheme.col("music")
		for i in 3:
			var h := (6.0 + absf(sin(_t * (4.2 + i * 1.6) + i * 1.3)) * 12.0) if playing else 4.0 + i * 2.0
			draw_rect(Rect2(i * 7.0, size.y - h, 4.0, h), col)
