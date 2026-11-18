extends "res://src/ui/layers/layer.gd"
## Alle Titel eines Künstlers (von der Künstlerseite, im Musik-Reiter wie über dem Guide im Spiel).
## Links Bild, Name, Anzahl und Knöpfe („Abspielen“, Gastauftritte an/aus), rechts die Titel aus
## allen Alben und Singles/EPs, jeder einmal, neueste Veröffentlichung zuerst, mit Album und Jahr.
## Die Liste lädt in Runden (Music.artist_catalog → src/core/artist_catalog.gd): die erste kommt
## schnell, weitere beim Blättern ans Ende. Geladenes bleibt für die Sitzung.
## A spielt den Titel in seinem Album (danach läuft das Album weiter), X als Nächstes, Y
## Lieblingssong. B zurück zur Künstlerseite, an die Stelle, von der man kam.

const TrackPage := preload("res://src/ui/components/track_page.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")
const Bits := preload("res://src/ui/components/music_bits.gd")

const GUTTER := 96
const PIC := 260.0
const LEFT_W := 420.0
const NEAR_END := 10            ## so viele Zeilen vor dem Ende lädt Uzai die nächste Runde
const FILL := 16                ## so viele Zeilen sollen mindestens stehen (sonst gleich weiter)

var artist: Dictionary = {}     ## { id, name, art?, art_big? }
const Main := preload("res://src/main.gd")
var main: Main
var guest := false              ## auch Gastauftritte
var _cat: RefCounted
var _rows: VBoxContainer
var _foot: VBoxContainer
var _sc: ScrollContainer
var _meta: Label
var _note: Label
var _guest_btn: Button
var _shown: Array = []          ## URIs der gezeigten Zeilen (in Reihenfolge)
var _foot_state := ""
var _play_btn: Button
var _moved := false             ## Auswahl schon einmal auf den ersten Titel gesetzt


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Zurück")
	var h := float(absi(str(artist.get("name", "")).hash()) % 1000) / 1000.0
	var glow := TextureRect.new()
	glow.texture = MusicTile.glow_tex()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = Vector2(-520, -620)
	glow.size = Vector2(1700, 1400)
	glow.modulate = Color(Color.from_hsv(h, 0.5, 0.6), 0.16)
	add_child(glow)
	var m := U.margin(GUTTER, 64, GUTTER, 24)
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(76)
	m.add_child(row)
	row.add_child(_left(h))
	var right := U.vbox(0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var mask := TrackPage.fade_mask(right)
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.follow_focus = false
	_sc.set_meta("uz_pad_v", 150.0)
	U.full_rect(_sc)
	mask.add_child(_sc)
	var inner := U.vbox(0)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(inner)
	_rows = U.vbox(2)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.set_meta("uz_group", "artist:alle")
	_rows.set_meta("uz_mem", true)
	inner.add_child(_rows)
	_foot = U.vbox(0)
	_foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_foot)
	inner.add_child(U.spacer(0, 160, false))
	# Mit der Maus/dem Rad ans Ende gerollt: nächste Runde.
	_sc.get_v_scroll_bar().value_changed.connect(func(v: float) -> void:
		var bar := _sc.get_v_scroll_bar()
		if v + bar.page >= bar.max_value - 600.0:
			_more()
	)
	_bind()


func _left(h: float) -> Control:
	var left := U.vbox(0)
	left.custom_minimum_size = Vector2(LEFT_W, 0)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(PIC, PIC)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(holder)
	var shade := Panel.new()
	shade.size = Vector2(PIC, PIC)
	var ssb := UzTheme.box(UzTheme.col("surface_hi"), int(PIC / 2.0))
	ssb.shadow_color = Color(0, 0, 0, 0.45)
	ssb.shadow_size = 30
	ssb.shadow_offset = Vector2(0, 14)
	shade.add_theme_stylebox_override("panel", ssb)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(shade)
	var frame := Panel.new()
	frame.size = Vector2(PIC, PIC)
	frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), int(PIC / 2.0)))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	var ph := TextureRect.new()
	ph.texture = MusicTile.tonal(h)
	ph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ph.stretch_mode = TextureRect.STRETCH_SCALE
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(ph)
	frame.add_child(ph)
	var ic := U.icon("user", 96, "text")
	ic.modulate = Color(1, 1, 1, 0.5)
	ic.size = Vector2(96, 96)
	ic.position = (Vector2(PIC, PIC) - Vector2(96, 96)) * 0.5
	frame.add_child(ic)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(pic)
	frame.add_child(pic)
	var url := str(artist.get("art_big", artist.get("art", "")))
	if url != "":
		Music.load_art(url, 600, func(t: Texture2D) -> void:
			if is_instance_valid(pic) and t:
				pic.texture = t
		)
	left.add_child(U.spacer(0, 30, false))
	var k := U.label("Alle Titel", "xs", "music", "medium")
	k.clip_text = false
	left.add_child(k)
	left.add_child(U.spacer(0, 6, false))
	var nm := str(artist.get("name", ""))
	var nl := U.label(nm, "xl" if nm.length() > 18 else "xxl", "text", "black", true)
	nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Künstlers: nie übersetzen
	nl.max_lines_visible = 3
	nl.add_theme_constant_override("line_spacing", -6)
	left.add_child(nl)
	left.add_child(U.spacer(0, 8, false))
	_meta = U.label("", "m", "muted", "medium", true)
	left.add_child(_meta)
	left.add_child(U.spacer(0, 6, false))
	_note = U.label("", "s", "faint", "regular", true)
	_note.max_lines_visible = 5
	_note.visible = false
	left.add_child(_note)
	left.add_child(U.spacer(0, 24, false))
	var btns := U.vbox(12)
	btns.set_meta("uz_group", "artist:alle:knoepfe")
	left.add_child(btns)
	var play := U.button("Abspielen", "play", "primary")
	play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	play.set_meta("uz_hint_a", "Abspielen")
	play.set_meta("uz_key", "at:play")
	play.set_meta("uz_default", true)
	play.set_meta("uz_entry", true)
	_play_btn = play
	play.pressed.connect(func() -> void: _play(0))
	btns.add_child(play)
	_guest_btn = U.button("", "friends", "flat")
	_guest_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_guest_btn.set_meta("uz_key", "at:gast")
	_guest_btn.pressed.connect(_toggle_guest)
	btns.add_child(_guest_btn)
	_guest_label()
	return left


func _guest_label() -> void:
	_guest_btn.text = "Gastauftritte: an" if guest else "Gastauftritte: aus"
	_guest_btn.set_meta("uz_hint_a", "Ausschalten" if guest else "Einschalten")


## Erste Zeile wählen, sobald es eine gibt; bis dahin „Abspielen“.
func _first_focus() -> Control:
	return _rows.get_child(0) as Control if _rows.get_child_count() > 0 else Nav.default_in(self)


## Liste (mit oder ohne Gastauftritte) anbinden und, wenn nötig, die erste Runde laden.
func _bind() -> void:
	if _cat and _cat.changed.is_connected(_sync):
		_cat.changed.disconnect(_sync)
	_cat = Music.artist_catalog(artist, guest)
	_cat.changed.connect(_sync)
	_shown.clear()
	U.clear(_rows)
	_foot_state = ""
	_sync()
	if (_cat.tracks as Array).is_empty() and not bool(_cat.done):
		_more()


func _more() -> void:
	if not _cat or bool(_cat.done) or bool(_cat.loading) or str(_cat.error) != "":
		return
	await _cat.more()


func _toggle_guest() -> void:
	guest = not guest
	_guest_label()
	Toasts.show_toast("Mit Gastauftritten" if guest else "Ohne Gastauftritte", str(artist.get("name", "")), "music", { "ms": 1300, "quiet": true })
	_bind()


## Stand der Liste übernehmen: neue Zeilen anhängen; hat sich Gezeigtes geändert (bessere Fassung
## eines Titels gefunden), neu aufbauen und die Auswahl auf demselben Titel lassen.
func _sync() -> void:
	if not is_instance_valid(_rows):
		return
	var list: Array = _cat.tracks
	var same_start := list.size() >= _shown.size()
	if same_start:
		for i in _shown.size():
			if str(list[i].uri) != str(_shown[i]):
				same_start = false
				break
	if not same_start:
		var f := Nav.focused()
		var keep := str((f as Object).get("track").get("uri", "")) if f and f.get_parent() == _rows and f.get("track") is Dictionary else ""
		U.clear(_rows)
		_shown.clear()
		_append(list, 0)
		if keep != "":
			for r in _rows.get_children():
				if str(r.get("track").get("uri", "")) == keep:
					Nav.focus.call_deferred(r as Control, true)
					break
	else:
		_append(list, _shown.size())
	_meta.text = meta_text(list.size(), _cat.mode, int(_cat.total), int(_cat.loaded), bool(_cat.done))
	var n := str(_cat.waiting) if str(_cat.waiting) != "" else str(_cat.note)
	_note.text = n
	_note.visible = n != ""
	_footer()
	# Zu wenig für den Bildschirm: gleich die nächste Runde.
	if not bool(_cat.loading) and not bool(_cat.done) and str(_cat.error) == "" and list.size() < FILL and _cat.mode != "":
		_more.call_deferred()


func _append(list: Array, from: int) -> void:
	for i in range(from, list.size()):
		var t: Dictionary = list[i]
		var r: Control = Bits.track_row(list, i, true, _play)
		var idx := i
		r.focus_entered.connect(func() -> void:
			if idx >= _cat.tracks.size() - NEAR_END:
				_more()
		)
		_rows.add_child(r)
		_shown.append(str(t.uri))
	# Die ersten Titel sind da und noch steht die Auswahl auf „Abspielen“ (wo sie beim Öffnen
	# stand): auf den ersten Titel.
	if from == 0 and not _moved and _rows.get_child_count() > 0 and Nav.focused() == _play_btn:
		_moved = true
		Nav.focus.call_deferred(_rows.get_child(0) as Control, true)


## Fuß der Liste: lädt, Fehler mit „Nochmal“, leer, oder „Das sind alle“.
func _footer() -> void:
	var st := "laedt" if bool(_cat.loading) else ("fehler" if str(_cat.error) != "" else ("ende" if bool(_cat.done) else "mehr"))
	var key := st + str((_cat.tracks as Array).size()) + str(_cat.error)
	if key == _foot_state:
		return
	_foot_state = key
	var had_focus := Nav.focused() != null and _foot.is_ancestor_of(Nav.focused())
	U.clear(_foot)
	var empty := (_cat.tracks as Array).is_empty()
	match st:
		"laedt":
			if empty:
				_foot.add_child(preload("res://src/ui/components/skeleton.gd").track_rows())
			else:
				# Weitere Titel kommen: zwei Zeilen in ihrer Form, kein Text.
				_foot.add_child(preload("res://src/ui/components/skeleton.gd").track_rows(2))
		"fehler":
			var card := PanelContainer.new()
			var sb := UzTheme.glass(UzTheme.r_panel())
			sb.content_margin_left = 30
			sb.content_margin_right = 30
			sb.content_margin_top = 24
			sb.content_margin_bottom = 26
			card.add_theme_stylebox_override("panel", sb)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var col := U.vbox(12)
			card.add_child(col)
			col.add_child(U.label("Titel nicht geladen" if empty else "Weitere Titel nicht geladen", "l", "text", "bold"))
			var l := U.label(str(_cat.error), "m", "muted", "regular", true)
			l.custom_minimum_size = Vector2(620, 0)
			col.add_child(l)
			var again := U.button("Nochmal versuchen", "refresh", "flat")
			again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			again.set_meta("uz_key", "at:nochmal")
			again.set_meta("uz_group", "artist:alle:fuss")
			again.pressed.connect(func() -> void:
				_cat.error = ""
				_more()
			)
			col.add_child(again)
			var m := U.margin(0, 14, 0, 0)
			m.add_child(card)
			_foot.add_child(m)
			if had_focus or empty:
				Nav.focus.call_deferred(again, true)
		"ende":
			var m := U.margin(62, 18, 0, 0)
			if empty:
				m.add_child(U.label("Spotify zeigt zu diesem Künstler keine Titel.", "m", "muted", "regular", true))
			else:
				m.add_child(U.label("Das sind alle %s." % U.plural((_cat.tracks as Array).size(), "Titel", "Titel"), "m", "faint", "medium"))
			_foot.add_child(m)


## Angaben unter dem Namen (öffentlich für die Tests).
static func meta_text(n: int, mode: String, total: int, loaded: int, done: bool) -> String:
	if n == 0 and not done:
		return ""
	var parts := PackedStringArray([U.plural(n, "Titel", "Titel")])
	if mode == "suche":
		parts.append("aus der Suche" + ("" if done else ", lädt beim Blättern weiter"))
	elif total > 0:
		if done or loaded >= total:
			parts.append("aus " + U.plural(total, "Veröffentlichung", "Veröffentlichungen"))
		else:
			parts.append("%d von %d Veröffentlichungen" % [loaded, total])
	return "  ·  ".join(parts)


## Titel i abspielen: in seinem Album, damit es danach weiterläuft; sonst ab hier die Liste.
func _play(i: int) -> void:
	var list: Array = _cat.tracks
	if i < 0 or i >= list.size():
		return
	var t: Dictionary = list[i]
	var ctx := str(t.get("album_uri", ""))
	if ctx != "" and not ctx.contains(":demo") and not Music.demo():
		Music.play_in(ctx, str(t.uri))
	else:
		Music.play_list(list, i)
