extends "res://src/ui/layers/layer.gd"
## Bilder für ein Spiel aussuchen – aus SteamGridDB oder (quelle = "ss", jedes Spiel, auch Steam/PC)
## ScreenScraper, mit dem Controller. LB/RB: Cover, Hintergrund, Logo, Symbol (ScreenScraper: Rücken
## statt Symbol; je Bildart alle Regionen und Varianten) · A übernimmt · X anderes Spiel suchen ·
## Y eigenes Bild wieder entfernen · B zurück. ScreenScraper-Kandidaten merkt Media je Spiel
## (ss_kandidaten), die Vorschauen kommen klein und nacheinander – das schont das Tageskontingent.
## Fürs Mosaik (mosaik_seite.gd): mit ziel geht das gewählte Bild nicht ans Spiel, sondern als Datei
## an ziel(pfad); ohne Spiel (game leer) sucht die Bildwahl nach stichwort (Artwork für Ordner und
## Bild-Kacheln, das zu keinem einzelnen Spiel gehört).

const KINDS := [["cover", "Cover"], ["hero", "Hintergrund"], ["logo", "Logo"], ["icon", "Symbol"]]
const KINDS_SS := [["cover", "Cover"], ["hero", "Hintergrund"], ["logo", "Logo"], ["ruecken", "Rücken"]]
const SS_ETIKETT := { "wor": "Welt", "ss": "SS", "box-3D": "3D", "fanart": "Fanart", "ss_typ": "Szene", "sstitle": "Titelbild",
	"wheel-hd": "HD", "wheel-carbon": "Carbon", "wheel-steel": "Stahl" }
const API := "https://www.steamgriddb.com/api/v2"
const KEY_PAGE := "https://www.steamgriddb.com/profile/preferences/api"
const TILE := { "cover": Vector2(200, 300), "hero": Vector2(520, 168), "logo": Vector2(400, 180), "icon": Vector2(168, 168), "ruecken": Vector2(84, 340) }
const QrView := preload("res://src/ui/components/qr_view.gd")
const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")
const Fremd := preload("res://src/core/fremd.gd")

var game: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var ziel: Callable           ## Mosaik: gewähltes Bild als Datei hierher, statt es dem Spiel zu geben
var stichwort := ""          ## Mosaik: ohne Spiel nach diesem Wort suchen
var quelle := "sgdb"         ## "sgdb" oder "ss" (ScreenScraper, nur mit Spiel)
var _ss := {}                ## Kandidaten von ScreenScraper (Media.ss_kandidaten)
var _kind := 0
var _sgdb_id := ""
var _sgdb_name := ""
var _tabs: HBoxContainer
var _grid: GridContainer
var _status: Label
var _match_l: Label
var _loading := false
var _cache := {}
var _setup_box: Control
var _req_id := ""
var phone_ip := ""          ## nur für Proben: feste Adresse statt der echten im Heimnetz


func build() -> void:
	dim = 0.96
	_scrim.color = Color(UzTheme.col("bg"), dim)
	# Die Startseite tritt ganz zurück, damit nichts durchscheint.
	LibraryGrid.hide_shell(main, self)
	var m := U.margin(96, 50, 96, 40)
	U.full_rect(m)
	add_child(m)
	var col := U.vbox(18)
	m.add_child(col)
	var head := U.hbox(24)
	col.add_child(head)
	var titles := U.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var titel := U.ellipsis(U.label(Library.display_title(game) if not game.is_empty() else stichwort, "xxl", "text", "black"))
	titel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels bzw. das eigene Stichwort
	titles.add_child(titel)
	if game.is_empty():
		quelle = "sgdb"
	_match_l = U.label(_quelle_name(), "m", "muted")
	_match_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Quelle · gefundenes Spiel: Namen
	titles.add_child(_match_l)
	head.add_child(titles)
	_tabs = U.hbox(6)
	col.add_child(_tabs)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 140.0)
	col.add_child(sc)
	var pad := U.margin(10, 14, 10, 30)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(pad)
	var inner := U.vbox(14)
	pad.add_child(inner)
	_status = U.label("", "l", "muted", "regular", true)
	inner.add_child(_status)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 22)
	inner.add_child(_grid)
	var hold := Control.new()
	hold.focus_mode = Control.FOCUS_ALL
	hold.custom_minimum_size = Vector2(1, 1)
	hold.set_meta("uz_hint_a", "—")
	hold.name = "Hold"
	inner.add_child(hold)
	_draw_tabs()
	_anfangen()


func _quelle_name() -> String:
	return "ScreenScraper.fr" if quelle == "ss" else "SteamGridDB"


## Erste Suche nach dem Aufbau (art_picker_iidb.gd hat seinen eigenen Anfang).
func _anfangen() -> void:
	if quelle == "ss":
		_connected()
		_ss_start()
	elif str(Config.get_value("accounts.sgdb_key", "")) == "":
		_no_key()
	else:
		_connected()
		_start()


## Uzais Bildart des gewählten Reiters (cover, hero, logo, icon, ruecken).
func _bildart() -> String:
	return str(_kinds()[_kind][0])


## Mit Schlüssel: Bildarten und Tasten zeigen.
func _connected() -> void:
	_tabs.visible = true
	set_meta("uz_hints", [["lb", ""], ["rb", "Bildart"], ["x", "Anderes Spiel"]] + ([] if ziel.is_valid() else [["y", "Eigenes entfernen"]]))
	Nav.focus_moved.emit(Nav.focused())


func _kinds() -> Array:
	return KINDS_SS if quelle == "ss" else KINDS


func _draw_tabs() -> void:
	U.clear(_tabs)
	_tabs.add_child(_klickbar(U.glyph("lb", 28), func() -> void: handle("lb")))
	for i in _kinds().size():
		var on := i == _kind
		var p := U.panel("text" if on else "surface", 8, 0)
		var l := U.label(str(_kinds()[i][1]), "s", "bg" if on else "muted", "bold")
		var mm := U.margin(16, 6, 16, 6)
		mm.add_child(l)
		p.add_child(mm)
		_tabs.add_child(_klickbar(p, _reiter_klick.bind(i)))
	_tabs.add_child(_klickbar(U.glyph("rb", 28), func() -> void: handle("rb")))


## Image type by mouse: a click on the tab (cover, background, logo, ...) instead of LB/RB or Q/E.
func _reiter_klick(i: int) -> void:
	if _sgdb_id == "" or i == _kind or i >= _kinds().size():
		return
	_kind = i
	Sfx.play("tab")
	_draw_tabs()
	_load_kind()


## Mit der Maus anklickbar: Hand-Zeiger, hell beim Darüberfahren, ein Klick ruft tun.
static func _klickbar(c: Control, tun: Callable) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for k in c.find_children("*", "Control", true, false):
		(k as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.mouse_entered.connect(func() -> void: c.self_modulate = Color(1.25, 1.25, 1.25))
	c.mouse_exited.connect(func() -> void: c.self_modulate = Color.WHITE)
	c.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			c.accept_event()
			tun.call()
	)
	return c


## Ohne Schlüssel: eine ruhige Karte statt einer Textwand. Der Weg führt übers Handy und
## bleibt in Uzai: Code scannen, auf der Handy-Seite „Schlüssel holen“ (SteamGridDB, Anmelden
## geht mit Steam), Schlüssel einfügen, senden – Uzai übernimmt ihn sofort und lädt die Bilder.
## Ohne Heimnetz bleibt das Eintippen mit der Bildschirmtastatur.
func _no_key(note := "") -> void:
	_tabs.visible = false
	_status.visible = false
	set_meta("uz_hints", [])
	if is_instance_valid(_setup_box):
		_setup_box.queue_free()
	# Zum zweiten Mal hier (Schlüssel abgelehnt): die alte Anfrage ans Handy beenden, bevor die neue beginnt.
	if _req_id != "":
		Remote.phone_end(_req_id)
	var card := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.set_content_margin_all(40)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := U.hbox(48)
	card.add_child(row)
	_req_id = "sgdb%d" % Time.get_ticks_msec()
	var url := Remote.phone_begin(_req_id, "SteamGridDB-Schlüssel", "Schlüssel einfügen und senden.", true, KEY_PAGE, phone_ip)
	if url != "":
		if not Remote.phone_text.is_connected(_on_phone_key):
			Remote.phone_text.connect(_on_phone_key)
		var qf := PanelContainer.new()
		var qsb := UzTheme.box(Color.WHITE, UzTheme.radius)
		qsb.set_content_margin_all(10)
		qf.add_theme_stylebox_override("panel", qsb)
		qf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		qf.add_child(QrView.new().setup(url, 264))
		row.add_child(qf)
	var col := U.vbox(18)
	col.custom_minimum_size = Vector2(820, 0)
	row.add_child(col)
	col.add_child(U.label("Einmal verbinden", "xl", "text", "bold"))
	if note != "":
		var nl := U.label(note, "m", "warn", "medium", true)
		nl.custom_minimum_size = Vector2(820, 0)
		col.add_child(nl)
	var intro := U.label("Kostenloser Schlüssel von SteamGridDB nötig.", "m", "muted", "regular", true)
	intro.custom_minimum_size = Vector2(820, 0)
	col.add_child(intro)
	col.add_child(U.spacer(0, 4, false))
	if url != "":
		col.add_child(_step(1, "Code scannen"))
		col.add_child(_step(2, "„Schlüssel holen“, mit Steam anmelden, Schlüssel erzeugen"))
		col.add_child(_step(3, "Einfügen und senden"))
	else:
		col.add_child(_step(1, "steamgriddb.com öffnen und mit Steam anmelden"))
		col.add_child(_step(2, "Unter Einstellungen → API einen Schlüssel erzeugen"))
		col.add_child(_step(3, "„Schlüssel eintippen“ wählen"))
	col.add_child(U.spacer(0, 6, false))
	var b := U.button("Schlüssel eintippen", "keyboard", "primary" if url == "" else "flat")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_hint_a", "Bildschirmtastatur")
	b.pressed.connect(func() -> void:
		main.open_keyboard("SteamGridDB-Schlüssel", "", func(v: String) -> void:
			_take_key(v)
		, true, KEY_PAGE)
	)
	col.add_child(b)
	_setup_box = card
	_grid.get_parent().add_child(card)
	_grid.get_parent().move_child(card, 1)
	await get_tree().process_frame
	if is_instance_valid(b):
		Nav.focus(b, true)


func _step(n: int, text: String) -> Control:
	var row := U.hbox(16)
	var dot := PanelContainer.new()
	var dsb := UzTheme.box(UzTheme.col("glass_hi"), 18, 1, UzTheme.col("stroke"))
	dot.add_theme_stylebox_override("panel", dsb)
	dot.custom_minimum_size = Vector2(36, 36)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var nl := U.label(str(n), "s", "accent", "bold")
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.add_child(nl)
	row.add_child(dot)
	var t := U.label(text, "m", "text", "regular", true)
	t.custom_minimum_size = Vector2(760, 0)
	row.add_child(t)
	return row


func _on_phone_key(id: String, value: String) -> void:
	if id != _req_id:
		return
	_take_key(value)


func _take_key(v: String) -> void:
	var key := v.strip_edges()
	if key == "" or not is_inside_tree():
		return
	Config.set_value("accounts.sgdb_key", key)
	Toasts.show_toast("SteamGridDB verbunden", "Bilder werden geladen …", "check", { "sound": "select" })
	if is_instance_valid(_setup_box):
		_setup_box.queue_free()
	_setup_box = null
	_status.visible = true
	_connected()
	_start()


func _exit_tree() -> void:
	if _req_id != "":
		Remote.phone_end(_req_id)
	if Remote.phone_text.is_connected(_on_phone_key):
		Remote.phone_text.disconnect(_on_phone_key)


func _hdr() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + str(Config.get_value("accounts.sgdb_key", ""))])


func _start() -> void:
	_status.text = "Spiel wird gesucht …"
	_sgdb_id = str(game.get("sgdb_id", ""))
	if game.get("source") == "steam" and _sgdb_id == "":
		_sgdb_id = "steam:%s" % str(game.get("appid", ""))
		_sgdb_name = "Steam-App " + str(game.get("appid", ""))
	if _sgdb_id == "":
		var wort := Library.display_title(game) if not game.is_empty() else stichwort
		var r := await Net.get_json("%s/search/autocomplete/%s" % [API, wort.uri_encode()], _hdr())
		if not is_inside_tree():
			return
		if r.code == 401:
			# Schlüssel abgelehnt: gleich hier neu verbinden, statt in die Einstellungen zu schicken.
			_no_key("Schlüssel abgelehnt. Neu verbinden.")
			return
		var found: Array = r.data.get("data", []) if r.ok and r.data is Dictionary else []
		if found.is_empty():
			_status.text = "Spiel nicht gefunden. „Anderes Spiel“ wählen."
			_focus_hold()
			return
		_sgdb_id = str(int(found[0].id))
		_sgdb_name = str(found[0].get("name", ""))
		if not game.is_empty():
			Library.set_field(str(game.id), "sgdb_id", _sgdb_id)
	_match_l.text = "SteamGridDB · " + (_sgdb_name if _sgdb_name != "" else tr("Spiel %s") % _sgdb_id)
	_load_kind()


## ScreenScraper: das Spiel (über Datei bzw. Namen, oder jeu: die gewählte Kennung) und seine Bilder.
func _ss_start(jeu := "") -> void:
	_status.visible = true
	_status.text = "Spiel wird gesucht …"
	U.clear(_grid)
	var k: Dictionary = {}
	if jeu != "":
		k = await Media.ss_kandidaten_id(game, jeu)
	else:
		k = await Media.ss_kandidaten(game)
	if not is_inside_tree():
		return
	if not bool(k.get("ok", false)):
		_ss = {}
		_status.text = ss_fehler(str(k.get("grund", "")))
		_focus_hold()
		return
	_ss = k
	_sgdb_id = "ss:" + str(k.get("id", ""))
	_match_l.text = "ScreenScraper.fr · " + (str(k.get("name", "")) if str(k.get("name", "")) != "" else tr("Spiel %s") % str(k.get("id", "")))
	_load_kind()


## Warum ScreenScraper nichts zeigt – kurz, mit dem nächsten Schritt.
static func ss_fehler(grund: String) -> String:
	match grund:
		"zugang": return "ScreenScraper: Zugang abgelehnt."
		"kontingent": return "ScreenScraper: Tageslimit erreicht. Morgen wieder."
		"zu": return "ScreenScraper ist gerade geschlossen."
		"fehlt": return "Spiel nicht gefunden. „Anderes Spiel“ wählen."
	return "ScreenScraper nicht erreichbar."


## Kleines Schild auf einer Kachel von ScreenScraper: Region und Variante („EU · 3D“).
static func ss_etikett(it: Dictionary) -> String:
	var teile := PackedStringArray()
	var reg := str(it.get("region", ""))
	if reg != "":
		teile.append(TranslationServer.translate(str(SS_ETIKETT.get(reg, reg.to_upper()))))
	var typ := str(it.get("typ", ""))
	var t := str(SS_ETIKETT.get("ss_typ" if typ == "ss" else typ, ""))
	if t != "":
		teile.append(TranslationServer.translate(t))
	return " · ".join(teile)


func _load_kind() -> void:
	var kind: String = _kinds()[_kind][0]
	U.clear(_grid)
	_loading = true
	_status.visible = true
	_status.text = "%s werden geladen …" % _kinds()[_kind][1]
	var items: Array
	var key := "%s:%s" % [_sgdb_id, kind]
	if quelle == "ss":
		items = ((_ss.get("liste", {}) as Dictionary).get(kind, []) as Array) if _ss.get("liste") is Dictionary else []
	elif _cache.has(key):
		items = _cache[key]
	else:
		var path: String = { "cover": "grids", "hero": "heroes", "logo": "logos", "icon": "icons" }[kind]
		var target := ("steam/" + _sgdb_id.substr(6)) if _sgdb_id.begins_with("steam:") else ("game/" + _sgdb_id)
		var q := "?dimensions=600x900,342x482,660x930&types=static" if kind == "cover" else "?types=static"
		var r := await Net.get_json("%s/%s/%s%s" % [API, path, target, q], _hdr())
		if not is_inside_tree():
			return
		items = Fremd.zeilen(r.data, "data") if r.ok else []
		if not r.ok:
			Media.log_line("sgdb", "%s %s → HTTP %d %s" % [path, target, int(r.code), str(r.get("text", "")).left(160)])
			_loading = false
			_status.visible = true
			_status.text = "SteamGridDB nicht erreichbar." if int(r.code) == 0 else (
					"Schlüssel abgelehnt. Neu verbinden." if int(r.code) in [401, 403]
					else "SteamGridDB antwortet nicht. Erneut versuchen.")
			_focus_hold()
			return
		_cache[key] = items
	_loading = false
	if str(_kinds()[_kind][0]) != kind:
		return
	var tile: Vector2 = TILE[kind]
	_grid.columns = maxi(1, int(1700.0 / (tile.x + 22)))
	var current := str(game.get("images", {}).get(kind, ""))
	for it in items.slice(0, 60):
		_grid.add_child(_tile(it, kind, tile, current))
	_status.text = "" if not items.is_empty() else "Keine Bilder."
	_status.visible = _status.text != ""
	var first := Nav.default_in(_grid)
	if first:
		var hold := find_child("Hold", true, false)
		Nav.focus(first, true)
		if hold:
			hold.visible = false
	else:
		_focus_hold()


func _focus_hold() -> void:
	var hold: Control = find_child("Hold", true, false)
	if hold:
		hold.visible = true
		Nav.focus(hold, true)


func _tile(it: Dictionary, kind: String, tile: Vector2, current: String) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = tile
	var bg := UzTheme.col("surface") if kind != "logo" else Color(0.18, 0.2, 0.26)
	var sb := UzTheme.box(bg)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.clip_contents = true
	var bild := TextureRect.new()
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if kind == "logo" or kind == "icon" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bild)
	if kind == "logo":
		bild.offset_left = 16
		bild.offset_right = -16
		bild.offset_top = 12
		bild.offset_bottom = -12
	b.add_child(bild)
	# Die Vorschau blendet weich ein, sobald sie da ist (statt hart aufzutauchen); ruhig: sofort.
	var gezeigt := func(t: Variant) -> void:
		if is_instance_valid(bild) and t is Texture2D:
			bild.texture = t
			if not U.reduziert() and bild.is_inside_tree():
				bild.modulate.a = 0.0
				bild.create_tween().tween_property(bild, "modulate:a", 1.0, U.T_ORT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if quelle == "ss":
		Media.ss_vorschau(str(it.get("url", "")), int(maxf(tile.x, 160.0) * 1.2), gezeigt)
	else:
		Media.url_texture(str(it.get("thumb", it.get("url", ""))), int(tile.x * 1.2), gezeigt)
	var author := str(it.get("author", {}).get("name", "")) if it.get("author") is Dictionary else ""
	if quelle == "ss" and kind != "ruecken":
		author = ss_etikett(it)
	if author != "":
		var tag := U.panel("bg", 6, 0, 0.75)
		var l := U.label(author, "cap", "muted", "medium")
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name bzw. schon übersetztes Schild
		l.clip_text = false
		var mm := U.margin(8, 3, 8, 3)
		mm.add_child(l)
		tag.add_child(mm)
		tag.position = Vector2(8, tile.y - 34)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tag)
	var url := str(it.get("url", ""))
	if current != "" and current.get_file().begins_with(_datei_anfang(it)):
		var ok := U.panel("accent", 16, 0)
		ok.custom_minimum_size = Vector2(32, 32)
		ok.position = Vector2(tile.x - 42, 10)
		ok.add_child(U.icon("check", 20, "bg"))
		b.add_child(ok)
	# Auswahl sichtbar: Der Fokusrahmen des Knopfs lag unter dem Bild (und wurde abgeschnitten).
	# Deshalb ein eigener Ring über dem Bild, und die gewählte Kachel hebt sich ein wenig.
	var ring := Panel.new()
	var rs := UzTheme.focus_box(UzTheme.radius, 0)
	rs.set_expand_margin_all(0)
	rs.shadow_size = 0
	rs.set_border_width_all(4)
	ring.add_theme_stylebox_override("panel", rs)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(ring)
	ring.visible = false
	b.add_child(ring)
	b.pivot_offset = tile * 0.5
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_entered.connect(func() -> void:
		ring.visible = true
		b.z_index = 1
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.05, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	)
	b.focus_exited.connect(func() -> void:
		ring.visible = false
		b.z_index = 0
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_SINE)
	)
	b.set_meta("uz_hint_a", "Übernehmen")
	b.pressed.connect(func() -> void: _pick(it, kind, url))
	return b


## Anfang des Dateinamens eines gewählten Bilds (Haken auf der Kachel, die gerade gilt).
func _datei_anfang(it: Dictionary) -> String:
	if quelle == "ss":
		return "ss_%s_" % str(it.get("url", "")).md5_text().substr(0, 10)
	return "sgdb_%s_" % str(int(it.get("id", 0)))


func _pick(it: Dictionary, kind: String, url: String) -> void:
	if url == "":
		return
	var ext := url.get_extension().get_slice("?", 0).to_lower()
	if quelle == "ss":
		ext = str(it.get("fmt", ""))
	if not ext in ["png", "jpg", "jpeg", "webp"]:
		ext = "png"
	var art_name := str(_kinds()[_kind][1])      # jetzt merken: Beim Laden kann LB/RB die Bildart schon gewechselt haben
	var wer := str(game.get("id", stichwort)).md5_text().substr(0, 10)
	var dest := ""
	if quelle == "ss":
		# Eigene Wahl: in den Medienordner (wie bei SteamGridDB), nie die Adresse mit Zugangsdaten.
		dest = Config.media_dir().path_join("screenscraper").path_join("%s%s_%s.%s" % [_datei_anfang(it), wer, kind, ext])
	else:
		dest = Config.media_dir().path_join("sgdb").path_join("%s_%s_%s.%s" % [wer, kind, str(int(it.get("id", 0))), ext])
		dest = dest.get_base_dir().path_join("sgdb_%s_%s" % [str(int(it.get("id", 0))), dest.get_file()])
	Toasts.show_toast("Wird geladen …", art_name, "download", { "ms": 1200 })
	var got := ""
	if quelle == "ss":
		got = await Media.ss_datei(url, ext, dest)
	else:
		got = await Net.download(url, dest)
	if got == "":
		Toasts.show_toast("Bild ließ sich nicht laden", "Nicht geladen. Erneut versuchen.", "warning")
		return
	if ziel.is_valid():
		ziel.call(got)
		if is_inside_tree():
			close()
		return
	var imgs: Dictionary = (game.get("images", {}) as Dictionary).duplicate()
	imgs[kind] = got
	Library.set_field(str(game.id), "images", imgs)
	game = Library.get_game(str(game.id))
	# Herkunft merken: der Discord-Status zeigt dann genau dieses Bild (über seine Adresse). Bei
	# ScreenScraper nie: Die Adresse geht nur mit Zugangsdaten.
	if quelle != "ss":
		Media.note_url(game, got, url)
	Media.bilder_stand += 1
	Toasts.show_toast("%s übernommen" % art_name, Library.display_title(game), "check", { "sub_raw": true, "sound": "select" })
	if is_inside_tree():
		_load_kind()


func handle(cmd: String) -> bool:
	match cmd:
		"lb", "rb":
			if _sgdb_id == "":
				return true
			_kind = (_kind + (1 if cmd == "rb" else -1) + _kinds().size()) % _kinds().size()
			Sfx.play("tab")
			_draw_tabs()
			_load_kind()
			return true
		"x":
			if quelle == "ss":
				main.open_keyboard("Spiel auf ScreenScraper suchen", Library.display_title(game), func(t: String) -> void:
					if t.strip_edges() != "":
						_ss_other(t.strip_edges())
				)
				return true
			main.open_keyboard("Spiel auf SteamGridDB suchen", Library.display_title(game) if not game.is_empty() else stichwort, func(t: String) -> void:
				if t.strip_edges() != "":
					_search_other(t.strip_edges())
			)
			return true
		"y":
			if ziel.is_valid() or game.is_empty():
				return true
			var kind := _bildart()
			var imgs: Dictionary = (game.get("images", {}) as Dictionary).duplicate()
			if imgs.has(kind):
				var snap := Library.snapshot([str(game.id)])
				imgs.erase(kind)
				Library.set_field(str(game.id), "images", imgs if not imgs.is_empty() else null)
				game = Library.get_game(str(game.id))
				Undo.offer_games("Eigenes Bild entfernt", str(_kinds()[_kind][1]), "image", snap, _load_kind)
				_load_kind()
			return true
	return false


func _ss_other(term: String) -> void:
	_status.visible = true
	_status.text = "Spiel wird gesucht …"
	var opts: Array = await Media.ss_suche(game, term)
	if not is_inside_tree():
		return
	if opts.is_empty():
		_status.text = ss_fehler(Media.ss_grund()) if Media.ss_grund() != "" else ""
		_status.visible = _status.text != ""
		Toasts.show_toast("Nichts gefunden", term, "search")
		return
	main.open_choice("Welches Spiel?", opts, "", func(v: Variant) -> void:
		_kind = 0
		_draw_tabs()
		_ss_start(str(v))
	)


func _search_other(term: String) -> void:
	if str(Config.get_value("accounts.sgdb_key", "")) == "":
		return
	var r := await Net.get_json("%s/search/autocomplete/%s" % [API, term.uri_encode()], _hdr())
	if not is_inside_tree():
		return
	if not r.ok:
		# Keine Antwort ist kein „Nichts gefunden“.
		Toasts.show_toast("SteamGridDB nicht erreichbar", "Verbindung prüfen und erneut versuchen.", "warning")
		return
	# Nur Treffer mit Nummer und Namen (beides braucht die Auswahl).
	var found := (Fremd.zeilen(r.data, "data") if r.ok else []).filter(func(f: Dictionary) -> bool:
		return Fremd.zahl(f.get("id")) > 0 and Fremd.text(f.get("name")) != "")
	if found.is_empty():
		Toasts.show_toast("Nichts gefunden", term, "search")
		return
	var opts: Array = []
	for f in found.slice(0, 12):
		var year := ""
		if Fremd.zahl(f.get("release_date")) > 0:
			year = " (%s)" % Time.get_datetime_string_from_unix_time(Fremd.zahl(f.get("release_date"))).substr(0, 4)
		opts.append([str(Fremd.zahl(f.id)), str(f.name) + year])
	main.open_choice("Welches Spiel?", opts, "", func(v: Variant) -> void:
		_sgdb_id = str(v)
		for f in found:
			if str(Fremd.zahl(f.id)) == _sgdb_id:
				_sgdb_name = str(f.name)
		if not game.is_empty():
			Library.set_field(str(game.id), "sgdb_id", _sgdb_id)
		_match_l.text = "SteamGridDB · " + _sgdb_name
		_cache.clear()
		_load_kind()
	)
