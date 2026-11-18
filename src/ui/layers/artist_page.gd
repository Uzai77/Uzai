extends "res://src/ui/layers/layer.gd"
## Künstlerseite: oben rund das Bild, Name und „Abspielen“, darunter die beliebtesten Titel und
## Reihen mit Alben und Singles; „Alle Titel“ (Knopf oben und unter den beliebten Titeln) öffnet
## jeden Titel aus allen Alben und Singles (artist_tracks.gd). A auf einem Titel spielt ab diesem Titel (die Liste läuft weiter),
## X stellt ihn in die Warteschlange, Y macht ihn zum Lieblingssong; A auf einem Album öffnet es,
## Y spielt es. „Suchen“ sucht mehr von diesem Künstler. B zurück.
## Daten über die offizielle Web-API (Music.artist_page); was Spotify eigenen Apps nicht gibt
## (Top-Titel, Bild), ersetzt Uzai durch Suchtreffer bzw. ein gemaltes Bild.

const Skeleton := preload("res://src/ui/components/skeleton.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")
const Bits := preload("res://src/ui/components/music_bits.gd")
const Lang := preload("res://src/core/lang.gd")

const GUTTER := 96
const PIC := 300.0

var artist: Dictionary = {}       ## { id, name } (ID darf fehlen: dann sucht Uzai den Namen)
const Main := preload("res://src/main.gd")
var main: Main
var _page: Dictionary = {}
var _col: VBoxContainer
var _sc: ScrollContainer
var _body: VBoxContainer
var _meta: Label
var _pic: TextureRect
var _ph: TextureRect
var _glow: TextureRect


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Zurück")
	var h := _hue()
	_glow = TextureRect.new()
	_glow.texture = MusicTile.glow_tex()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.position = Vector2(-520, -620)
	_glow.size = Vector2(1700, 1400)
	_glow.modulate = Color(Color.from_hsv(h, 0.5, 0.6), 0.18)
	add_child(_glow)
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.follow_focus = false
	_sc.set_meta("uz_pad_v", 170.0)
	U.full_rect(_sc)
	add_child(_sc)
	_col = U.vbox(0)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(_col)
	_col.add_child(_header(h))
	_body = U.vbox(0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_child(_body)
	# Laden: Titelzeilen als ruhige Platzhalter (die Form der kommenden Liste), kein Text.
	var wait := U.margin(GUTTER, 20, GUTTER, 0)
	wait.add_child(Skeleton.track_rows(5))
	_body.add_child(wait)
	_col.add_child(U.spacer(0, 120, false))
	_load()


func _hue() -> float:
	return float(absi(str(artist.get("name", "")).hash()) % 1000) / 1000.0


## Kopf: rundes Bild mit Schatten, daneben Name, Angaben und die Knöpfe.
func _header(h: float) -> Control:
	var m := U.margin(GUTTER, 76, GUTTER, 40)
	var row := U.hbox(56)
	m.add_child(row)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(PIC, PIC)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	# Schatten auf eigener Fläche (nie auf dem zuschneidenden Rahmen, DESIGN.md › Schatten).
	var shade := Panel.new()
	shade.size = Vector2(PIC, PIC)
	var ssb := UzTheme.box(UzTheme.col("surface_hi"), int(PIC / 2.0))
	ssb.shadow_color = Color(0, 0, 0, 0.45)
	ssb.shadow_size = 36
	ssb.shadow_offset = Vector2(0, 16)
	shade.add_theme_stylebox_override("panel", ssb)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(shade)
	var frame := Panel.new()
	frame.size = Vector2(PIC, PIC)
	frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), int(PIC / 2.0)))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	_ph = TextureRect.new()
	_ph.texture = MusicTile.tonal(h)
	_ph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ph.stretch_mode = TextureRect.STRETCH_SCALE
	_ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_ph)
	frame.add_child(_ph)
	var ic := U.icon("user", 110, "text")
	ic.modulate = Color(1, 1, 1, 0.5)
	ic.size = Vector2(110, 110)
	ic.position = (Vector2(PIC, PIC) - Vector2(110, 110)) * 0.5
	frame.add_child(ic)
	_pic = TextureRect.new()
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_pic)
	frame.add_child(_pic)
	var info := U.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var k := U.label("Künstler", "xs", "music", "medium")
	k.clip_text = false
	info.add_child(k)
	var nm := str(artist.get("name", ""))
	var nl := U.label(nm, "xxl" if nm.length() > 18 else "hero", "text", "black", true)
	nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Künstlers: nie übersetzen
	nl.max_lines_visible = 2
	nl.add_theme_constant_override("line_spacing", -8)
	U.shadow(nl)
	info.add_child(nl)
	_meta = U.label("", "m", "muted", "medium", true)
	info.add_child(_meta)
	info.add_child(U.spacer(0, 18, false))
	var btns := U.hbox(12)
	btns.set_meta("uz_group", "artist:knoepfe")
	info.add_child(btns)
	var play := U.button("Abspielen", "play", "primary")
	play.set_meta("uz_default", true)
	play.set_meta("uz_entry", true)
	play.set_meta("uz_key", "ap:play")
	play.set_meta("uz_hint_a", "Beliebte Titel abspielen")
	play.pressed.connect(_play_all)
	btns.add_child(play)
	var all := U.button("Alle Titel", "list", "flat")
	all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	all.set_meta("uz_key", "ap:alle")
	all.set_meta("uz_hint_a", "Öffnen")
	all.pressed.connect(_open_all)
	btns.add_child(all)
	var srch := U.button("Mehr suchen", "search", "flat")
	srch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srch.set_meta("uz_key", "ap:search")
	srch.set_meta("uz_hint_a", "Titel, Alben und Playlists zu „%s“" % nm)
	srch.pressed.connect(func() -> void: Bits.open_search(main, str(artist.get("name", ""))))
	btns.add_child(srch)
	return m


func _load() -> void:
	_page = await Music.artist_page(artist)
	if not is_inside_tree():
		return
	var a: Dictionary = _page.get("artist", {}) if _page.get("artist") is Dictionary else {}
	if not a.is_empty():
		artist = a
	_meta.text = meta_text(artist, (_page.get("albums", []) as Array).size() + (_page.get("singles", []) as Array).size())
	var url := str(artist.get("art_big", artist.get("art", "")))
	if url != "":
		Music.load_art(url, 600, func(t: Texture2D) -> void:
			if is_instance_valid(_pic) and t:
				_pic.texture = t
				_pic.modulate.a = 0.0
				_pic.create_tween().tween_property(_pic, "modulate:a", 1.0, U.T_BASE)
				var c: Variant = Media.color_of(t)
				if c is Color and is_instance_valid(_glow):
					_glow.create_tween().tween_property(_glow, "modulate", Color(c as Color, 0.2), 0.6)
		)
	_fill()


## Angaben unter dem Namen: Follower, Genres, Veröffentlichungen (was Spotify herausgibt).
static func meta_text(a: Dictionary, releases: int) -> String:
	var parts := PackedStringArray()
	var fol := int(a.get("followers", -1))
	if fol >= 0:
		parts.append(count_text(fol) + " Follower")
	var genres: Array = a.get("genres", []) if a.get("genres") is Array else []
	if not genres.is_empty():
		parts.append(", ".join(PackedStringArray(genres.slice(0, 2))))
	if releases > 0:
		parts.append(U.plural(releases, "Veröffentlichung", "Veröffentlichungen"))
	return "  ·  ".join(parts)


## 1,2 Mio. · 45 Tsd. · 812 (öffentlich für die Tests).
static func count_text(n: int) -> String:
	if n >= 1000000:
		return Lang.dec(String.num(n / 1000000.0, 1)) + " Mio."
	if n >= 10000:
		return "%d Tsd." % int(n / 1000.0)
	return str(n)


func _fill() -> void:
	U.clear(_body)
	if not bool(_page.get("ok", false)):
		var m := U.margin(GUTTER, 10, GUTTER, 0)
		var card := PanelContainer.new()
		var sb := UzTheme.glass(UzTheme.r_panel())
		sb.content_margin_left = 30
		sb.content_margin_right = 30
		sb.content_margin_top = 24
		sb.content_margin_bottom = 26
		card.add_theme_stylebox_override("panel", sb)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var col := U.vbox(10)
		card.add_child(col)
		col.add_child(U.label("Künstler nicht geladen", "l", "text", "bold"))
		var l := U.label(str(_page.get("error", "")), "m", "muted", "regular", true)
		l.custom_minimum_size = Vector2(900, 0)
		col.add_child(l)
		m.add_child(card)
		_body.add_child(m)
		return
	var top: Array = _page.get("top", [])
	if not top.is_empty():
		_body.add_child(Bits.title("Beliebte Titel", "aus der Suche bei Spotify" if str(_page.get("top_from", "")) == "suche" else ""))
		_body.add_child(Bits.track_grid(top, "artist:titel"))
	# Unter den beliebten Titeln (wie bei Spotify „Diskografie ansehen“): alle Titel.
	var am := U.margin(GUTTER - 4, 0 if not top.is_empty() else 10, GUTTER, 34)
	var more := U.button("Alle Titel von %s" % str(artist.get("name", "")), "chevron_right", "flat")
	more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	more.set_meta("uz_key", "ap:alle_unten")
	more.set_meta("uz_group", "artist:alle_titel")
	more.set_meta("uz_hint_a", "Öffnen")
	more.pressed.connect(_open_all)
	am.add_child(more)
	_body.add_child(am)
	var albums: Array = _page.get("albums", [])
	var singles: Array = _page.get("singles", [])
	if not albums.is_empty():
		_body.add_child(Bits.title("Alben", U.plural(albums.size(), "Album", "Alben")))
		_body.add_child(Bits.shelf(albums, "artist:alben", main, Bits.TILE_W, true))
	if not singles.is_empty():
		_body.add_child(Bits.title("Singles und EPs", ""))
		_body.add_child(Bits.shelf(singles, "artist:singles", main, Bits.TILE_W, true))
	if top.is_empty() and albums.is_empty() and singles.is_empty():
		var em := U.margin(GUTTER, 10, GUTTER, 0)
		em.add_child(U.label("Spotify zeigt zu diesem Künstler gerade keine Titel. „Mehr suchen“ findet vielleicht etwas.", "l", "muted", "regular", true))
		_body.add_child(em)


## Alle Titel als eigene Ebene (B kommt hierher zurück, an dieselbe Stelle).
func _open_all() -> void:
	Bits.open_artist_tracks(main, artist)


func _play_all() -> void:
	if _page.is_empty():
		return
	var ok: bool = await Music.play_artist(_page)
	if ok:
		Toasts.show_toast("Läuft: " + str(artist.get("name", "")), "Beliebte Titel", "music", { "ms": 1800, "quiet": true })
	else:
		Toasts.show_toast("Spielt nicht", Music.error if Music.error != "" else "Spotify hat keine Titel geschickt.", "warning", { "ms": 4500 })
