extends RefCounted
## Oberfläche für lokale Musik (Punkt 34, Arbeit: src/core/music_local.gd): die Karte zum
## Einrichten bzw. während des Einlesens, Kacheln für Alben und Interpreten, ihre Titelliste und
## im Guide „Alben“ zum Abspielen über dem Spiel. Alles mit dem Controller.

const U := preload("res://src/ui/u.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")
const TrackList := preload("res://src/ui/layers/track_list.gd")
const LocalMusic := preload("res://src/core/music_local.gd")
const Main := preload("res://src/main.gd")


## Was gerade fehlt: "ordner" (keiner gewählt), "laden" (liest ein), "leer" (keine Dateien),
## "fehlt" (Ordner nicht erreichbar) oder "" (alles da).
static func state() -> String:
	var lm: Node = Music.local
	if LocalMusic.root() == "":
		return "ordner"
	if lm.scanning:
		return "laden"
	if str(lm.scan_error) != "":
		return "fehlt"
	if (lm.tracks as Array).is_empty():
		return "leer"
	return ""


## Musikordner wählen (Dateiauswahl von Uzai, nur Ordner).
static func pick_folder(main: Main) -> void:
	var cur := LocalMusic.root()
	main.open_file_browser("Musikordner", true, func(p: String) -> void:
		Config.set_value("music.local_dir", LocalMusic.norm(p))
	, [], cur if cur != "" else LocalMusic.suggested_root())


## Ruhige Karte für die Zustände aus state(). side: schmal (rechts neben „Läuft gerade“).
static func card(main: Main, side := false) -> Control:
	var st := state()
	var lm: Node = Music.local
	var m := U.margin(0, 6, 0, 6)
	var panel := PanelContainer.new()
	var sb := UzTheme.glass(UzTheme.r_panel())
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 36
	sb.content_margin_bottom = 38
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if side else Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.add_child(panel)
	var col := U.vbox(14)
	col.custom_minimum_size = Vector2(0 if side else 760, 0)
	panel.add_child(col)
	var ic := U.icon("music" if st != "fehlt" else "warning", 30, "accent" if st != "fehlt" else "warn")
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(ic)
	var head := ""
	var text := ""
	match st:
		"ordner":
			head = "Deine Musik in Uzai"
			text = "Ordner mit Musikdateien wählen (MP3, OGG, WAV)."
		"laden":
			head = "Musik wird eingelesen …"
			text = "Titel, Alben und Cover aus %s." % LocalMusic.root()
		"leer":
			head = "Keine Musikdateien gefunden"
			text = "In %s liegen keine MP3-, OGG- oder WAV-Dateien. FLAC und Opus kann Uzai nicht abspielen." % LocalMusic.root()
		"fehlt":
			head = "Musikordner nicht erreichbar"
			text = "%s ist gerade nicht da – vielleicht eine abgezogene Festplatte. Danach „Neu einlesen“." % LocalMusic.root()
		_:
			head = "Deine Musik"
			text = U.plural((lm.albums as Array).size(), "Album", "Alben") + " · " + U.plural((lm.tracks as Array).size(), "Titel", "Titel")
	col.add_child(U.label(head, "xl", "text", "bold", true))
	var body := U.label(text, "m", "muted", "regular", true)
	col.add_child(body)
	if st == "laden":
		var prog := U.label("", "s", "faint", "medium")
		prog.set_meta("uz_scan_label", true)
		col.add_child(prog)
		# Der Zähler läuft mit jeder Datei: Muster einmal übersetzen, die Zeile selbst nicht.
		prog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var muster := prog.tr("%d von %d Dateien")
		var sucht := prog.tr("Ordner werden durchsucht …")
		var upd := func(done: int, total: int) -> void:
			if is_instance_valid(prog):
				prog.text = (muster % [done, total]) if total > 0 else sucht
		lm.scan_progress.connect(upd)
		prog.tree_exiting.connect(func() -> void:
			if lm.scan_progress.is_connected(upd):
				lm.scan_progress.disconnect(upd)
		)
		return m
	col.add_child(U.spacer(0, 6, false))
	var btns := U.hbox(12)
	btns.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(btns)
	var pick := U.button("Musikordner wählen" if st == "ordner" else "Anderer Ordner", "folder", "primary" if st == "ordner" else "normal")
	pick.set_meta("uz_key", "local:pick")
	pick.pressed.connect(func() -> void: pick_folder(main))
	btns.add_child(pick)
	var sug := LocalMusic.suggested_root()
	if st == "ordner" and sug != "" and DirAccess.dir_exists_absolute(sug):
		var b := U.button("Ordner „%s“ nehmen" % sug.get_file(), "music")
		b.set_meta("uz_key", "local:suggest")
		b.pressed.connect(func() -> void: Config.set_value("music.local_dir", sug))
		btns.add_child(b)
	if st in ["leer", "fehlt"]:
		var again := U.button("Neu einlesen", "refresh", "primary")
		again.set_meta("uz_key", "local:rescan")
		again.set_meta("uz_default", true)
		again.pressed.connect(func() -> void: Music.local.scan(true))
		btns.add_child(again)
	else:
		pick.set_meta("uz_default", true)
	return m


## Kachel für ein Album oder einen Interpreten der lokalen Musik.
static func tile(main: Main, it: Dictionary, w: float) -> Control:
	var t = MusicTile.new()
	t.setup(it, w)
	t.art_urls = [str(it.get("art", ""))]
	t.set_meta("uz_key", "lt:%s" % str(it.get("id", "")))
	t.set_meta("uz_hint_y", "Abspielen")
	t.set_meta("uz_on_y", func() -> void: play(it))
	if str(it.get("kind", "")) == "artist":
		t.round_art = true
		t.icon_name = "user"
		t.sub_text = U.plural((it.get("albums", []) as Array).size(), "Album", "Alben")
		t.set_meta("uz_hint_a", "Titel ansehen")
	else:
		var year := int(it.get("year", 0))
		t.sub_text = str(it.get("artist", "")) + (("  ·  %d" % year) if year > 0 else "")
		t.set_meta("uz_hint_a", "Album öffnen")
	t.chosen.connect(func(_i: Dictionary) -> void: open(main, it))
	return t


## Album bzw. Interpret als Titelliste (wie eine Playlist).
static func open(main: Main, it: Dictionary) -> void:
	var p := it.duplicate()
	if str(it.get("kind", "")) == "artist":
		p["kind"] = "lokal_interpret"
	var l = TrackList.new()
	l.playlist = p
	l.main = main
	main.open_layer(l)


## Ganz abspielen (Album von vorn, Interpret der Reihe nach).
static func play(it: Dictionary) -> void:
	var list: Array = it.get("tracks", [])
	if list.is_empty():
		return
	var album := str(it.get("kind", "")) == "album"
	Music.local.play_tracks(list, 0, str(it.get("akey", "")) if album else "", str(it.get("name", "")))
	Toasts.show_toast("Läuft: " + str(it.get("name", "")), U.plural(list.size(), "Titel", "Titel"), "music", { "ms": 1600, "quiet": true })


## Im Guide (auch über dem Spiel): Alben zum Abspielen und „Alles zufällig“.
static func open_albums_sheet(main: Main) -> void:
	var lm: Node = Music.local
	var s = preload("res://src/ui/layers/sheet.gd").new()
	s.setup("Alben", "Eigene Musik", 760)
	s.fill_func = func(sheet) -> void:
		if (lm.tracks as Array).is_empty():
			sheet.add_label("Noch keine Musik eingelesen – unter Medien → Musik einen Ordner wählen.", "m", "muted")
			return
		var all = preload("res://src/ui/components/list_item.gd").new()
		all.setup("Alles zufällig", U.plural((lm.tracks as Array).size(), "Titel", "Titel"))
		all.icon_name = "shuffle"
		all.set_meta("uz_hint_a", "Abspielen")
		all.activated.connect(func() -> void:
			lm.set_shuffle(true)
			lm.play_tracks(lm.tracks, randi() % maxi(1, (lm.tracks as Array).size()), "", "Alle Titel")
			sheet.close()
		)
		sheet.add_row(all)
		for a in lm.albums:
			var it = preload("res://src/ui/components/list_item.gd").new()
			it.setup(str(a.name), str(a.artist))
			it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # Namen aus den Dateien
			it.image_url = str(a.art)
			it.set_meta("uz_hint_a", "Abspielen")
			var al: Dictionary = a
			it.activated.connect(func() -> void:
				play(al)
				sheet.close()
			)
			sheet.add_row(it)
	main.open_layer(s)
