extends "res://src/ui/layers/layer.gd"
## Musik suchen – als Ebene, damit es auch im Spiel über dem Guide geht (der Bereich Musik läge
## dort hinter dem Spiel). Eingabe über Uzais Tastatur (Controller oder Handy), Treffer über die
## Spotify-Suche: Künstler (A öffnet die Künstlerseite), Titel (A spielt ab, X als Nächstes,
## Y Lieblingssong), Alben und Playlists (A öffnet, Y spielt). B zurück.

const Bits := preload("res://src/ui/components/music_bits.gd")

const GUTTER := 96

var query := ""
const Main := preload("res://src/main.gd")
var main: Main
var _body: VBoxContainer
var _ask_btn: Button
var _res := {}
var _gen := 0


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Zurück")
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 170.0)
	U.full_rect(sc)
	add_child(sc)
	var col := U.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(col)
	var head := U.margin(GUTTER, 70, GUTTER, 26)
	var hc := U.vbox(6)
	head.add_child(hc)
	var k := U.label("Musik", "xs", "music", "medium")
	k.clip_text = false
	hc.add_child(k)
	hc.add_child(U.label("Suchen", "xxl", "text", "black"))
	hc.add_child(U.spacer(0, 14, false))
	var row := U.hbox(12)
	row.set_meta("uz_group", "msearch:kopf")
	hc.add_child(row)
	_ask_btn = U.button("", "search", "primary")
	_ask_btn.set_meta("uz_default", true)
	_ask_btn.set_meta("uz_key", "msearch:ask")
	_ask_btn.set_meta("uz_hint_a", "Suchwort eingeben")
	_ask_btn.pressed.connect(_ask)
	row.add_child(_ask_btn)
	var a := Music.artist_of_now()
	if not a.is_empty():
		var cur := U.button("Läuft gerade: " + str(a.name), "user", "flat")
		cur.set_meta("uz_key", "msearch:artist")
		cur.set_meta("uz_hint_a", "Zum Künstler")
		cur.pressed.connect(func() -> void: Bits.open_artist(main, a))
		row.add_child(cur)
	col.add_child(head)
	_body = U.vbox(0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	col.add_child(U.spacer(0, 120, false))
	_update_ask()
	if query != "":
		run(query)
	else:
		_hint()
		_ask_soon()


## Ohne Suchwort gleich die Tastatur öffnen (erst, wenn die Ebene steht).
func _ask_soon() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and not _closing:
		_ask()


func _ask() -> void:
	main.open_keyboard("Musik suchen", query, func(q: String) -> void: run(q))


func _update_ask() -> void:
	if is_instance_valid(_ask_btn):
		_ask_btn.text = ("„%s“ – neue Suche" % query) if query != "" else "Titel, Künstler oder Album suchen"


func _hint() -> void:
	U.clear(_body)
	var m := U.margin(GUTTER, 6, GUTTER, 0)
	m.add_child(U.label("Mit A ein Suchwort eingeben – am Controller oder auf dem Handy.", "l", "muted", "regular", true))
	_body.add_child(m)


func run(q: String) -> void:
	query = q.strip_edges()
	_update_ask()
	if query == "":
		_hint()
		return
	_gen += 1
	var my := _gen
	U.clear(_body)
	var lm := U.margin(GUTTER, 6, GUTTER, 0)
	lm.add_child(U.label("Sucht …", "l", "muted"))
	_body.add_child(lm)
	_res = await Music.search(query)
	if my != _gen or not is_inside_tree():
		return
	_show()
	# Nach der Suche steht die Auswahl auf dem ersten Treffer (nicht wieder auf der Suche). Zwei
	# Bilder warten: Kommt die Antwort sofort (Vorführung), legt open() die Ebene erst danach auf
	# den Stapel und setzte sonst die Auswahl zurück auf „Suchen“.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var first := Nav.default_in(_body)
	if first:
		Nav.focus(first, true)


func _show() -> void:
	U.clear(_body)
	var artists: Array = _res.get("artists", [])
	var tracks: Array = _res.get("tracks", [])
	var albums: Array = _res.get("albums", [])
	var pls: Array = _res.get("playlists", [])
	if artists.is_empty() and tracks.is_empty() and albums.is_empty() and pls.is_empty():
		var m := U.margin(GUTTER, 6, GUTTER, 0)
		var err := str(_res.get("error", ""))
		m.add_child(U.label(err if err != "" else "Nichts gefunden. Anders schreiben oder nur den Künstler suchen.", "l", "muted", "regular", true))
		_body.add_child(m)
		return
	var first := true
	if not artists.is_empty():
		_body.add_child(Bits.title("Künstler"))
		var sh := Bits.shelf(artists, "msearch:kuenstler", main)
		_mark_first(sh, first)
		first = false
		_body.add_child(sh)
	if not tracks.is_empty():
		_body.add_child(Bits.title("Titel", U.plural(tracks.size(), "Treffer", "Treffer")))
		var grid := Bits.track_grid(tracks, "msearch:titel", false)
		_mark_first(grid, first)
		first = false
		_body.add_child(grid)
	if not albums.is_empty():
		_body.add_child(Bits.title("Alben"))
		var sa := Bits.shelf(albums, "msearch:alben", main)
		_mark_first(sa, first)
		first = false
		_body.add_child(sa)
	if not pls.is_empty():
		_body.add_child(Bits.title("Playlists"))
		var sp := Bits.shelf(pls, "msearch:playlists", main)
		_mark_first(sp, first)
		_body.add_child(sp)


## Der erste Treffer der ersten Reihe wird die Auswahl nach der Suche (Titel und Kacheln melden
## sich mit „chosen“; fokussierbar werden sie erst im Baum).
static func _mark_first(c: Node, on: bool) -> bool:
	if not on:
		return false
	for ch in c.get_children():
		if ch.has_signal("chosen"):
			ch.set_meta("uz_default", true)
			return true
		if _mark_first(ch, true):
			return true
	return false
