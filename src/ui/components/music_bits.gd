extends RefCounted
## Bausteine für Musikseiten über dem Bereich oder dem Guide (Künstlerseite, Suche): Titelzeilen
## mit A/X/Y, Kacheln für Künstler, Alben und Playlists, Reihen und Überschriften. Alles öffnet sich
## als Ebene (main.open_layer), so geht es auch im Spiel über dem Guide.

const U := preload("res://src/ui/u.gd")
const TrackRow := preload("res://src/ui/components/track_row.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")
const Main := preload("res://src/main.gd")

const GUTTER := 96
const TILE_W := 212.0


## Überschrift einer Reihe, rechts daneben leise eine Angabe.
static func title(text: String, extra := "") -> Control:
	var m := U.margin(GUTTER, 12, GUTTER, 0)
	var row := U.hbox(14)
	m.add_child(row)
	var l := U.label(text, "l", "text", "bold")
	l.clip_text = false
	row.add_child(l)
	if extra != "":
		var e := U.label(extra, "m", "faint", "medium")
		e.clip_text = false
		e.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(e)
	return m


## Ein Titel: A spielt ab hier (die Liste läuft weiter), X als Nächstes, Y Lieblingssong.
## play: eigenes Abspielen (bekommt i), etwa im Album des Titels.
static func track_row(list: Array, i: int, numbered := true, play := Callable()) -> Control:
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
	if play.is_valid():
		r.chosen.connect(func(_t: Dictionary) -> void: play.call(i))
	else:
		r.chosen.connect(func(_t: Dictionary) -> void: Music.play_list(list, i))
	return r


## Titel in zwei Spalten, von oben nach unten gezählt (1–5 links, 6–10 rechts).
static func track_grid(list: Array, group: String, numbered := true) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 2)
	grid.set_meta("uz_group", group)
	grid.set_meta("uz_mem", true)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gm := U.margin(GUTTER - 16, 10, GUTTER - 16, 30)
	gm.add_child(grid)
	var half := ceili(list.size() / 2.0)
	for r in half:
		for c in 2:
			var i := r + c * half
			if i < list.size():
				grid.add_child(track_row(list, i, numbered))
			else:
				var gap := Control.new()
				gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(gap)
	return gm


## Eine Reihe Kacheln (Künstler, Alben, Playlists gemischt möglich).
## by_year: Alben mit Art und Jahr statt Künstler (auf der Künstlerseite).
static func shelf(items: Array, group: String, main: Main, w := TILE_W, by_year := false) -> Control:
	var sh = Shelf.new().setup(group, 30, true, 26, GUTTER, 20)
	sh.custom_minimum_size.y = w + MusicTile.TEXT_H + 46
	for i in items.size():
		var t := tile(items[i], main, w, by_year)
		if i == 0:
			t.set_meta("uz_entry", true)
		sh.add(t)
	return sh


## Kachel je nach Art: Künstler (rund, A öffnet die Künstlerseite), Album oder Playlist (A öffnet
## die Titelliste, Y spielt ab).
static func tile(it: Dictionary, main: Main, w := TILE_W, by_year := false) -> Control:
	var kind := str(it.get("kind", "playlist"))
	var t = MusicTile.new()
	t.setup(it, w)
	t.set_meta("uz_key", "mb:%s:%s" % [kind, str(it.get("id", it.get("name", "")))])
	t.art_urls = [str(it.get("art", ""))]
	match kind:
		"artist":
			t.round_art = true
			t.icon_name = "user"
			t.sub_text = "Künstler"
			t.set_meta("uz_hint_a", "Künstler öffnen")
			t.chosen.connect(func(_i: Dictionary) -> void: open_artist(main, it))
		"album":
			var year := str(it.get("date", "")).get_slice("-", 0)
			var single := str(it.get("type", "")) == "single"
			if by_year or str(it.get("artist", "")) == "":
				t.sub_text = ("Single" if single else "Album") + ((" · " + year) if year != "" else "")
			else:
				t.sub_text = str(it.get("artist", ""))
			t.set_meta("uz_hint_a", "Album öffnen")
			t.set_meta("uz_hint_y", "Abspielen")
			t.set_meta("uz_on_y", func() -> void: play_context(it))
			t.chosen.connect(func(_i: Dictionary) -> void: open_list(main, it))
		_:
			var n := int(it.get("count", 0))
			var teile := PackedStringArray()
			if n >= 0:
				teile.append(U.plural(n, "Titel", "Titel"))
			if str(it.get("owner", "")) != "" and not bool(it.get("mine", true)):
				teile.append("von " + str(it.owner))
			t.sub_text = " · ".join(teile) if not teile.is_empty() else TranslationServer.translate("Playlist")
			t.set_meta("uz_hint_a", "Titel ansehen")
			t.set_meta("uz_hint_y", "Abspielen")
			t.set_meta("uz_on_y", func() -> void: play_context(it))
			t.chosen.connect(func(_i: Dictionary) -> void: open_list(main, it))
	return t


static func open_list(main: Main, it: Dictionary) -> void:
	var l = load("res://src/ui/layers/track_list.gd").new()
	l.playlist = it
	l.main = main
	main.open_layer(l)


## Künstlerseite öffnen ({ id, name }; ohne ID sucht Uzai den Namen).
static func open_artist(main: Main, a: Dictionary) -> void:
	if a.is_empty() or str(a.get("name", "")) == "":
		Toasts.show_toast("Kein Künstler bekannt", "Gerade läuft nichts." if Music.now.is_empty() else "Die App nennt zu diesem Titel keinen Künstler.", "music",
				{ "ms": 1600 })
		return
	var l = load("res://src/ui/layers/artist_page.gd").new()
	l.artist = a
	l.main = main
	main.open_layer(l)


## Alle Titel eines Künstlers als Ebene ({ id, name }).
static func open_artist_tracks(main: Main, a: Dictionary) -> void:
	if a.is_empty() or str(a.get("name", "")) == "":
		return
	var l = load("res://src/ui/layers/artist_tracks.gd").new()
	l.artist = a
	l.main = main
	main.open_layer(l)


## Musiksuche als Ebene öffnen (auch über dem Guide). Ohne Suchwort öffnet sich gleich die Tastatur.
static func open_search(main: Main, q := "") -> void:
	var l = load("res://src/ui/layers/music_search.gd").new()
	l.query = q
	l.main = main
	main.open_layer(l)


static func play_context(it: Dictionary) -> void:
	var ok: bool = await Music.play_context(str(it.get("uri", "")))
	if ok:
		Toasts.show_toast("Läuft: " + str(it.get("name", "")), str(it.get("artist", "")), "music", { "ms": 1800, "quiet": true })
	else:
		Toasts.show_toast(str(it.get("name", "")) + " spielt nicht", Music.error, "warning", { "ms": 4500 })
