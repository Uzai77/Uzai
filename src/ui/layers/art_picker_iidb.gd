extends "res://src/ui/layers/art_picker.gd"
## Bildwahl für ein Spiel aus iiDB (iiSU): Reiter Cover, iiSU-Cover, Banner, Hero, Logo, Symbol
## (Iidb.WAHL) – Banner (16:9) und Hero (breit) getrennt, beide werden Uzais Hintergrund. Jede Bildart
## ist eine Galerie, die seitenweise nachlädt („Mehr laden“ am Ende, Cursor von iiDB). Kennt iiDB
## mehrere Spiele mit dem Namen, wählt der Nutzer („Welches Spiel?“); X sucht ein anderes Spiel.
## Ohne Schlüssel führt eine Karte zur Anmeldeseite.

const Iidb := preload("res://src/core/iidb.gd")
const TILE_IIDB := { "boxart": Vector2(220, 300), "iisu_boxart": Vector2(240, 240), "banner": Vector2(400, 225),
	"hero": Vector2(520, 168), "logo": Vector2(400, 180), "icon": Vector2(168, 168), "soundbite": Vector2(260, 150) }
const GANZ := ["boxart", "iisu_boxart", "logo", "icon"]      ## ganz zeigen statt zuschneiden
## Last tab: the game page's sound (soundbite), so it can be chosen among the artwork instead of taking
## the first one iiDB returns.
const KLANG := ["soundbite", "Klang", "klang"]

var _id := 0                 ## Kennung des Spiels bei iiDB
var _seiten := {}            ## Asset-Art → { items, weiter, mehr } (geladene Seiten der Galerie)
var _laedt_mehr := false
var _hoeren: AudioStreamPlayer


## Die Reiter: Bildarten von iiDB, dahinter der Klang.
func _w() -> Array:
	return (Iidb.WAHL + [KLANG])[clampi(_kind, 0, Iidb.WAHL.size())]


func _kinds() -> Array:
	return (Iidb.WAHL + [KLANG]).map(func(w: Array) -> Array: return [w[0], w[1]])


func _bildart() -> String:
	return str(_w()[2])


func _quelle_name() -> String:
	return "iiDB"


func _anfangen() -> void:
	quelle = "iidb"
	if not Media.iidb.verbunden():
		_ohne_schluessel()
		return
	_connected()
	_suchen()


## Ohne Schlüssel (oder nach einer Ablehnung): eine ruhige Karte mit dem Weg zur Anmeldeseite.
func _ohne_schluessel(note := "") -> void:
	_tabs.visible = false
	_status.visible = false
	set_meta("uz_hints", [])
	if is_instance_valid(_setup_box):
		_setup_box.queue_free()
	var card := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.set_content_margin_all(40)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var col := U.vbox(16)
	col.custom_minimum_size = Vector2(820, 0)
	card.add_child(col)
	col.add_child(U.label("Einmal verbinden", "xl", "text", "bold"))
	if note != "":
		col.add_child(U.label(note, "m", "warn", "medium", true))
	col.add_child(U.label("iiDB braucht deinen eigenen Schlüssel von accounts.iisu.network.", "m", "muted", "regular", true))
	var b := U.button("Verbinden", "link", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func() -> void:
		var l: Control = load("res://src/ui/layers/iidb_login.gd").new()
		l.main = main
		main.open_layer(l)
		l.closed.connect(func() -> void:
			if is_inside_tree() and Media.iidb.verbunden():
				card.queue_free()
				_setup_box = null
				_connected()
				_suchen()
		, CONNECT_DEFERRED)
	)
	col.add_child(b)
	_setup_box = card
	_grid.get_parent().add_child(card)
	_grid.get_parent().move_child(card, 1)
	await get_tree().process_frame
	if is_instance_valid(b):
		Nav.focus(b, true)


## Das Spiel bei iiDB finden (gemerkt: ohne Anfrage). Mehrere Kandidaten: der Nutzer wählt.
func _suchen() -> void:
	_status.visible = true
	_status.text = "Spiel wird gesucht …"
	U.clear(_grid)
	_id = 0
	_sgdb_id = ""
	Media.iidb.pause_aus()
	var r: Dictionary = await Media.iidb.spiel_finden(game)
	if not is_inside_tree():
		return
	match str(r.get("status", "")):
		"matched":
			_gefunden(int(r.id), str(r.get("name", "")))
		"needs_choice":
			_status.text = "iiDB kennt mehrere Spiele mit diesem Namen."
			_focus_hold()
			_waehlen(r.get("kandidaten", []))
		"not_found":
			_status.text = Iidb.grund_text("fehlt")
			_focus_hold()
		_:
			if str(r.get("grund", "")) == "zugang":
				_ohne_schluessel("Schlüssel abgelehnt. Neu verbinden.")
				return
			_status.text = Iidb.grund_text(str(r.get("grund", "")))
			_focus_hold()


func _gefunden(id: int, name: String) -> void:
	_id = id
	_sgdb_id = "iidb:%d" % id          # die Reiter (LB/RB) gehen erst mit einem Spiel
	_seiten.clear()
	_match_l.text = "iiDB · " + (name if name != "" else tr("Spiel %s") % str(id))
	_load_kind()


func _waehlen(kandidaten: Array) -> void:
	if kandidaten.is_empty():
		return
	var opts: Array = kandidaten.map(func(k: Dictionary) -> Array: return [str(int(k.id)), Iidb.kandidat_text(k)])
	main.open_choice("Welches Spiel?", opts, "", func(v: Variant) -> void:
		for k in kandidaten:
			if str(int(k.id)) == str(v):
				Media.iidb.zuweisen(game, int(k.id), str(k.name))
				game = Library.get_game(str(game.id)) if not Library.get_game(str(game.id)).is_empty() else game
				_kind = 0
				_draw_tabs()
				_gefunden(int(k.id), str(k.name))
	)


## Die Galerie der gewählten Bildart: erste Seite laden (einmal je Bildart), Kacheln zeigen.
func _load_kind() -> void:
	var art := str(_w()[0])
	U.clear(_grid)
	_status.visible = true
	if _id <= 0:
		return
	if not _seiten.has(art):
		_loading = true
		_status.text = "%s werden geladen …" % str(_w()[1])
		var g: Dictionary = await Media.iidb.galerie(_id, art)
		_loading = false
		if not is_inside_tree():
			return
		if not bool(g.ok):
			if str(g.grund) == "zugang":
				_ohne_schluessel("Schlüssel abgelehnt. Neu verbinden.")
				return
			if str(_w()[0]) == art:
				_status.text = Iidb.grund_text(str(g.grund)) if str(g.grund) != "fehlt" else ("Kein Klang." if art == "soundbite" else "Keine Bilder.")
				_focus_hold()
			return
		_seiten[art] = { "items": g.items, "weiter": g.weiter, "mehr": g.mehr }
	if str(_w()[0]) != art:
		return
	var seite: Dictionary = _seiten[art]
	var tile: Vector2 = TILE_IIDB[art]
	_grid.columns = maxi(1, int(1700.0 / (tile.x + 22)))
	var current := str(game.get("images", {}).get(_bildart(), ""))
	var klang_id := int((Iidb.gemerkt(Library.get_game(str(game.get("id", "")))).get("klang", {}) as Dictionary).get("id", 0))
	for a in seite.items:
		if art == "soundbite":
			if Iidb.klang_grund(a) == "":
				_grid.add_child(_klang_kachel(a, tile, int(a.id) == klang_id))
			continue
		_grid.add_child(_kachel(a, art, tile, current))
	if bool(seite.mehr):
		_grid.add_child(_mehr_kachel(art, tile))
	_status.text = "" if _grid.get_child_count() > 0 else ("Kein passender Klang (höchstens 30 s)." if art == "soundbite" else "Keine Bilder.")
	_status.visible = _status.text != ""
	var first := Nav.default_in(_grid)
	if first:
		var hold := find_child("Hold", true, false)
		Nav.focus(first, true)
		if hold:
			hold.visible = false
	else:
		_focus_hold()


## Eine Kachel der Galerie: die Kachel der anderen Quellen, mit Vorschau und Region von iiDB.
func _kachel(a: Dictionary, art: String, tile: Vector2, current: String) -> Control:
	var it := { "url": str(a.url), "thumb": str(a.vorschau) if str(a.vorschau) != "" else str(a.url), "asset": a,
		"author": { "name": str(a.region) if str(a.region) != "" else str(a.name) } }
	var b := _tile(it, "logo" if art == "logo" else "cover", tile, current)
	if art in GANZ:
		for c in b.get_children():
			if c is TextureRect:
				(c as TextureRect).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	b.set_meta("uz_iidb", int(a.id))
	return b


## Ein Klang als Kachel: Note, Name bzw. Region, Länge; der gewählte trägt „Gewählt“. A wählt ihn und spielt ihn an.
func _klang_kachel(a: Dictionary, tile: Vector2, gewaehlt: bool) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = tile
	var sb := UzTheme.box(Color(UzTheme.col("surface"), 0.7), UzTheme.radius, 2 if gewaehlt else 1,
			UzTheme.col("accent") if gewaehlt else UzTheme.col("stroke"))
	for zustand in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(zustand, sb)
	var rs := UzTheme.focus_box(UzTheme.radius, 0)
	rs.set_expand_margin_all(0)
	rs.shadow_size = 0
	rs.set_border_width_all(4)
	b.add_theme_stylebox_override("focus", rs)
	var mitte := U.vbox(6)
	mitte.alignment = BoxContainer.ALIGNMENT_CENTER
	mitte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(mitte)
	var zeichen := U.icon("check" if gewaehlt else "music", 30, "accent" if gewaehlt else "muted")
	zeichen.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mitte.add_child(zeichen)
	var name := str(a.get("name", "")) if str(a.get("name", "")) != "" else str(a.get("region", ""))
	var zeile := name if name != "" else tr("Klang %d") % int(a.id)
	if int(a.get("ms", -1)) > 0:
		zeile += "  ·  %.0f s" % (int(a.ms) / 1000.0)
	var wort := U.label(zeile, "s", "text" if gewaehlt else "muted", "medium")
	wort.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name von iiDB
	wort.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wort.clip_text = true
	wort.custom_minimum_size.x = tile.x - 24
	mitte.add_child(wort)
	if gewaehlt:
		var schild := U.label("Gewählt", "cap", "accent", "bold")
		schild.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mitte.add_child(schild)
	b.add_child(mitte)
	b.set_meta("uz_hint_a", "Wählen und anhören")
	b.pressed.connect(func() -> void: _klang_waehlen(a))
	return b


func _klang_waehlen(a: Dictionary) -> void:
	Toasts.show_toast("Wird geladen …", "Klang", "download", { "ms": 1200 })
	var pfad: String = await Media.iidb.klang_waehlen(game, a)
	if not is_inside_tree():
		return
	if pfad == "":
		Toasts.show_toast("Klang ließ sich nicht laden", "Nicht geladen oder Format geht nicht. Einen anderen versuchen.", "warning")
		return
	game = Library.get_game(str(game.id))
	_anhoeren(pfad)
	Toasts.show_toast("Klang übernommen", Library.display_title(game), "check", { "sub_raw": true })
	var i := _grid.get_children().find(Nav.focused())
	_load_kind()
	await get_tree().process_frame
	if is_inside_tree() and i >= 0 and i < _grid.get_child_count():
		Nav.focus(_grid.get_child(i), true)


## Den gewählten Klang einmal anspielen (die Spielseite spielt ihn ab dem nächsten Öffnen).
func _anhoeren(pfad: String) -> void:
	var strom := Iidb.klang_strom(pfad)
	if strom == null:
		return
	if _hoeren == null:
		_hoeren = AudioStreamPlayer.new()
		add_child(_hoeren)
	if strom is AudioStreamOggVorbis:
		(strom as AudioStreamOggVorbis).loop = false
	elif strom is AudioStreamMP3:
		(strom as AudioStreamMP3).loop = false
	elif strom is AudioStreamWAV:
		(strom as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_hoeren.stream = strom
	_hoeren.play()


## Letzte Kachel: die nächste Seite der Galerie (A lädt nach; der Fokus geht aufs erste neue Bild).
func _mehr_kachel(art: String, tile: Vector2) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = tile
	var sb := UzTheme.box(Color(UzTheme.col("surface"), 0.55), UzTheme.radius, 1, UzTheme.col("stroke"))
	for zustand in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(zustand, sb)
	var rs := UzTheme.focus_box(UzTheme.radius, 0)
	rs.set_expand_margin_all(0)
	rs.shadow_size = 0
	rs.set_border_width_all(4)
	b.add_theme_stylebox_override("focus", rs)
	var mitte := U.vbox(8)
	mitte.alignment = BoxContainer.ALIGNMENT_CENTER
	mitte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(mitte)
	var zeichen := U.icon("plus", 30, "muted")
	zeichen.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mitte.add_child(zeichen)
	var wort := U.label("Mehr laden", "s", "muted", "medium")
	wort.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mitte.add_child(wort)
	b.add_child(mitte)
	b.set_meta("uz_hint_a", "Mehr laden")
	b.pressed.connect(func() -> void: _mehr(art))
	return b


func _mehr(art: String) -> void:
	if _laedt_mehr or not _seiten.has(art) or _id <= 0:
		return
	var seite: Dictionary = _seiten[art]
	if not bool(seite.mehr):
		return
	_laedt_mehr = true
	var g: Dictionary = await Media.iidb.galerie(_id, art, str(seite.weiter))
	_laedt_mehr = false
	if not is_inside_tree():
		return
	if not bool(g.ok):
		Toasts.show_toast("Nicht geladen", Iidb.grund_text(str(g.grund)), "warning")
		return
	# Doppelte auslassen: Die Galerie kann sich ändern, während man blättert.
	var da := {}
	for a in seite.items:
		da[int(a.id)] = true
	var neu: Array = (g.items as Array).filter(func(a: Dictionary) -> bool: return not da.has(int(a.id)))
	(seite.items as Array).append_array(neu)
	seite.weiter = g.weiter
	seite.mehr = bool(g.mehr) and not neu.is_empty()
	if str(_w()[0]) != art:
		return
	var erstes := (seite.items as Array).size() - neu.size()
	_load_kind()
	await get_tree().process_frame
	if is_inside_tree() and erstes < _grid.get_child_count():
		Nav.focus(_grid.get_child(erstes), true)


func _datei_anfang(it: Dictionary) -> String:
	return Iidb.datei_anfang(it.get("asset", {}))


## Gewähltes Bild in den Medienordner laden (ohne Schlüssel) und dem Spiel geben.
func _pick(it: Dictionary, _kind_kachel: String, _url: String) -> void:
	var a: Dictionary = it.get("asset", {})
	if a.is_empty():
		return
	var kind := _bildart()
	Toasts.show_toast("Wird geladen …", str(_w()[1]), "download", { "ms": 1200 })
	var got: String = await Media.iidb.asset_laden(a, game, kind, Config.media_dir().path_join("iidb"))
	if got == "":
		Toasts.show_toast("Bild ließ sich nicht laden", "Nicht geladen. Erneut versuchen.", "warning")
		return
	var imgs: Dictionary = (game.get("images", {}) as Dictionary).duplicate()
	imgs[kind] = got
	Library.set_field(str(game.id), "images", imgs)
	game = Library.get_game(str(game.id))
	Media.note_url(game, got, str(a.url))
	Media.bilder_stand += 1
	Toasts.show_toast("%s übernommen" % str(_w()[1]), Library.display_title(game), "check", { "sub_raw": true, "sound": "select" })
	if is_inside_tree():
		_load_kind()


func handle(cmd: String) -> bool:
	if cmd == "x":
		if not Media.iidb.verbunden():
			return true
		main.open_keyboard("Spiel bei iiDB suchen", Library.display_title(game), func(t: String) -> void:
			if t.strip_edges() != "":
				_anderes(t.strip_edges())
		)
		return true
	return super(cmd)


func _anderes(wort: String) -> void:
	var r: Dictionary = await Media.iidb.suche(wort)
	if not is_inside_tree():
		return
	if not bool(r.ok):
		Toasts.show_toast("Suche ging nicht", Iidb.grund_text(str(r.grund)), "warning")
		return
	if (r.liste as Array).is_empty():
		Toasts.show_toast("Nichts gefunden", wort, "search")
		return
	_waehlen(r.liste)
