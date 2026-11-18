extends "res://src/ui/layers/layer.gd"
## „Aufnahmen“ wie die Mediengalerie der PS5: Clips und Bildschirmfotos nach Spielen, neueste
## zuerst, jedes mit Vorschaubild. A spielt einen Clip ab (Uzais Videoplayer mit mpv) bzw. zeigt
## ein Bildschirmfoto groß, X teilt (ans Handy, an Discord, an den Steam-Chat), Y/Menü öffnet die
## Optionen (Bearbeiten, Umbenennen, In den Papierkorb). Alles mit dem Controller.

const VideoCard := preload("res://src/ui/components/video_card.gd")
const L := preload("res://src/core/capture_logic.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const Edit := preload("res://src/ui/layers/capture_edit.gd")
const Qr := preload("res://src/ui/layers/capture_qr.gd")
const View := preload("res://src/ui/layers/capture_view.gd")
const LeerBuehne := preload("res://src/ui/components/leer_buehne.gd")

const GUTTER := 96
const CARD_W := 408.0

const Main := preload("res://src/main.gd")
var main: Main
var focus_path := ""              ## diese Aufnahme gleich wählen (Mitteilung „Ansehen“ im Spiel)
var _sc: ScrollContainer
var _col: VBoxContainer
var _sub: Label
var _items: Array = []
var _leer: Control             ## die Bühne, solange es keine Aufnahme gibt


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.follow_focus = false
	_sc.set_meta("uz_pad_v", 140.0)
	U.full_rect(_sc)
	add_child(_sc)
	var m := U.margin(GUTTER, 88, GUTTER, 120)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(m)
	_col = U.vbox(18)
	m.add_child(_col)
	_fill()
	if not Capture.changed.is_connected(_on_changed):
		Capture.changed.connect(_on_changed)


func _on_changed(what: String) -> void:
	if what == "files" and is_inside_tree():
		_refill()


func _refill() -> void:
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if f and is_ancestor_of(f) else ""
	U.clear(_col)
	_fill()
	await get_tree().process_frame
	if not is_inside_tree() or Nav.top_layer() != self:
		return
	for c in Nav.focusables(self):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return
	var d := Nav.default_in(self)       # auch die Bühne, wenn die letzte Aufnahme gelöscht wurde
	if d:
		Nav.focus(d, true)


func _fill() -> void:
	_items = Capture.list_items()
	# Noch nichts aufgenommen: die Bühne wie in den Bereichen (Zeichen, Titel, ein Satz, Knöpfe,
	# dahinter die Form der Karten) statt einer Überschrift mit einer Textzeile darunter.
	if is_instance_valid(_leer):
		_leer.queue_free()
		_leer = null
	_sc.visible = not _items.is_empty()
	if _items.is_empty():
		var o := { "art": "video", "symbol": "video", "host": self, "titel": "Noch keine Aufnahmen.",
			"zeile": "Im Spiel: Guide → „Clip speichern“ (%d s)." % Capture.length_s(),
			"knopf": "Einstellungen", "tun": func() -> void:
				close()
				if main:
					main.goto("settings", "aufnahmen") }
		if Config.is_windows() and not Capture.has_ffmpeg():
			o["neben"] = "Eigene Aufnahme einrichten"
			o["neben_tun"] = func() -> void: ask_install(main)
		_leer = LeerBuehne.new().setup(o)
		U.full_rect(_leer)
		add_child(_leer)
		return
	var head := U.hbox(24)
	_col.add_child(head)
	var titles := U.vbox(4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(U.label("Aufnahmen", "xxl", "text", "black"))
	var clips := _items.filter(func(x) -> bool: return str(x.kind) == "clip").size()
	var shots := _items.size() - clips
	var bits := PackedStringArray([U.plural(clips, "Clip", "Clips"), U.plural(shots, "Bildschirmfoto", "Bildschirmfotos")])
	var used := Capture.folder_bytes(Capture.clips_dir())
	if used > 0:
		bits.append(L.size_text(used) + " belegt")
	_sub = U.label("  ·  ".join(bits), "m", "muted")
	titles.add_child(_sub)
	var btns := U.hbox(14)
	btns.set_meta("uz_group", "aufnahmen:knoepfe")
	btns.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(btns)
	var setb := U.button("Einstellungen", "settings")
	setb.set_meta("uz_key", "cap:settings")
	setb.pressed.connect(func() -> void:
		close()
		if main:
			main.goto("settings", "aufnahmen")
	)
	btns.add_child(setb)
	if Config.is_windows() and not Capture.has_ffmpeg():
		var fb := U.button("Eigene Aufnahme einrichten", "download", "primary")
		fb.set_meta("uz_key", "cap:ffmpeg")
		fb.pressed.connect(func() -> void: ask_install(main))
		btns.add_child(fb)
	_col.add_child(U.spacer(0, 18, false))
	var first := focus_path == "" or not _items.any(func(x) -> bool: return str(x.path) == focus_path)
	for g in L.group_by_title(_items):
		var sec := U.hbox(12)
		var gl := U.label(str(g.title), "l", "text", "bold")
		gl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels
		sec.add_child(gl)
		sec.add_child(U.label(U.plural((g["items"] as Array).size(), "Aufnahme", "Aufnahmen"), "s", "faint", "medium"))
		_col.add_child(U.margin(2, 18, 0, 4))
		_col.add_child(sec)
		var grid := GridContainer.new()
		# Vier Karten bei 1920 Breite; mit größerer Oberfläche weniger (sonst ragte die vierte über den Rand), auf
		# breiten Bildschirmen mehr.
		grid.columns = U.cols_for(4, GUTTER)
		grid.add_theme_constant_override("h_separation", 32)
		grid.add_theme_constant_override("v_separation", 36)
		grid.set_meta("uz_group", "aufnahmen:" + str(g.title))
		_col.add_child(grid)
		for it in g["items"]:
			var c := _card(it)
			if first or str(it.path) == focus_path:
				c.set_meta("uz_default", true)
				first = false
			grid.add_child(c)


func _card(it: Dictionary) -> Control:
	var c := make_card(main, it, CARD_W, _items, "cap")
	# Der Hinweis steht an der Karte, nicht an der Ebene: Auf den Knöpfen oben und ohne Aufnahmen
	# stünden sonst „Teilen“ und „Optionen“ da, und die Tasten täten nichts.
	c.set_meta("uz_hint_y", "Optionen")
	c.set_meta("uz_on_y", func() -> void: _options(it))
	return c


## Karte einer Aufnahme (Galerie, Startseite „Aufnahmen“, Spielseite, Guide): Vorschaubild mit
## Länge bzw. Kamera, darunter Zeitpunkt und Art. A spielt ab bzw. zeigt groß (view), X teilt.
## siblings: die Aufnahmen daneben (Bildschirmfotos blättern darin). Vorschaubilder fehlender
## Clips baut Capture im Hintergrund nach.
static func make_card(m: Main, it: Dictionary, w: float, siblings: Array = [], prefix := "cap") -> Control:
	var path := str(it.path)
	var clip := str(it.kind) == "clip"
	var thumb := Capture.thumb_path(path)
	var v := { "id": "cap:" + path.md5_text(), "title": _when(it), "thumb": thumb if FileAccess.file_exists(thumb) else "", "channel": str(it.title) }
	var c = VideoCard.new()
	c.setup(v, w, false)
	c.key_prefix = prefix
	c.meta_override = ("Clip" if clip else "Bildschirmfoto") + "  ·  " + L.size_text(int(it.size))
	if clip:
		c.badge_text = L.mmss(float(it.duration)) if float(it.duration) > 0.0 else ""
		c.badge_icon = "play" if float(it.duration) <= 0.0 else ""
	else:
		c.badge_icon = "camera"
	c.set_meta("uz_hint_a", "Abspielen" if clip else "Ansehen")
	c.set_meta("uz_hint_x", "Teilen")
	c.set_meta("uz_on_x", func() -> void: open_share(m, path))
	c.set_meta("uz_capture", path)
	var sib := siblings
	c.chosen.connect(func(_v: Dictionary) -> void: view(m, path, sib))
	if not FileAccess.file_exists(thumb) and clip:
		var wr: WeakRef = weakref(c)
		Capture.thumb(path, func(p: String) -> void:
			var card = wr.get_ref()
			if card == null or p == "":
				return
			Media.file_texture(p, 480, func(t: Texture2D) -> void:
				var cc = wr.get_ref()
				if cc and t:
					cc._on_tex(t)
			)
		)
	return c


static func _when(it: Dictionary) -> String:
	var s := str(it.get("stamp", ""))
	if s == "":
		return str(it.path).get_file().get_basename()
	# „2026-10-17 18:30:05“ → „17.10.2026, 18:30“
	var d := s.split(" ")[0].split("-")
	var t := s.split(" ")[1] if s.contains(" ") else ""
	return "%s.%s.%s, %s" % [d[2], d[1], d[0], t.left(5)] if d.size() == 3 else s


func handle(cmd: String) -> bool:
	if cmd == "menu":
		var f := Nav.focused()
		if f and f.has_meta("uz_on_y"):
			(f.get_meta("uz_on_y") as Callable).call()
		return true
	return false


func _open_item(it: Dictionary) -> void:
	view(main, str(it.path), _items)


## Eine Aufnahme ansehen: Clip in Uzais Videoplayer (play), Bildschirmfoto groß; links/rechts
## blättert durch die Bildschirmfotos in siblings (leer: alle).
static func view(m: Main, path: String, siblings: Array = []) -> void:
	if L.kind_of(path) == "clip":
		play(m, path, str(L.parse_name(path).title))
		return
	var list: Array = siblings if not siblings.is_empty() else Capture.list_items()
	var v = View.new()
	v.files = list.filter(func(x) -> bool: return str(x.kind) == "shot").map(func(x) -> String: return str(x.path))
	if not (v.files as Array).has(path):
		v.files = [path]
	v.index = maxi(0, (v.files as Array).find(path))
	m.open_layer(v)


## Clip im Videoplayer von Uzai (mpv). Im Spiel nicht (wie alle Videos).
static func play(m: Main, path: String, title: String) -> void:
	if Launcher.in_game:
		Toasts.show_toast("Erst das Spiel beenden", "Abspielen, wenn kein Spiel läuft.", "video")
		return
	if Config.is_windows() and not YouTube.has_mpv():
		m.open_dialog("Videoplayer einrichten?",
				"Zum Abspielen wird mpv geladen.", [
			["Einrichten", func() -> void:
				Toasts.show_toast("Videoplayer wird eingerichtet", "Das kann ein paar Minuten dauern.", "download")
				var err: String = await YouTube.setup_tools()
				Toasts.show_toast("Fertig" if err == "" else "Nicht ganz geklappt", err, "video" if err == "" else "warning")],
			["Abbrechen", func() -> void: pass],
		], "video")
		return
	var dur := Capture.duration_of(path)
	m.open_video([{ "id": "cap:" + path.md5_text(), "title": path.get_file().get_basename(), "url": Capture.win(path),
		"media_title": path.get_file().get_basename(), "channel": title, "duration": int(dur), "thumb": Capture.thumb_path(path) }], 0, { "start": 0.0 })


func _options(it: Dictionary) -> void:
	var path := str(it.path)
	var clip := str(it.kind) == "clip"
	var s = Sheet.new()
	s.setup(str(it.title), _when(it), 760)
	s.heading_raw = true         # Name des Spiels
	s.subheading_raw = true      # Zeitpunkt
	s.help_on = true
	s.fill_func = func(sheet) -> void:
		var rows: Array = [
			["Abspielen" if clip else "Ansehen", "play" if clip else "image", "", func() -> void: _open_item(it)],
			["Teilen …", "send", "Ans Handy, an Discord" + ("" if clip else " oder den Steam-Chat"), func() -> void: open_share(main, path)],
		]
		if clip:
			rows.append(["Bearbeiten", "edit", "Kürzen, Zeitlupe, Text, Ton – das Original bleibt", func() -> void:
				if not Capture.has_ffmpeg():
					ask_install(main)
					return
				var e = Edit.new()
				e.file = path
				e.main = main
				main.open_layer(e)])
		rows.append(["Umbenennen", "tag", "Titel ändern, Datum bleibt", func() -> void: _rename(path, str(it.title))])
		rows.append(["In den Papierkorb", "trash", "Landet im Papierkorb", func() -> void: _ask_delete(path)])
		for r in rows:
			var li = ListItem.new()
			li.setup(str(r[0]), str(r[2]))
			li.icon_name = str(r[1])
			var cb: Callable = r[3]
			var desc := str(r[2])
			li.focus_entered.connect(func() -> void: sheet.set_help(desc))
			li.activated.connect(func() -> void:
				sheet.close()
				cb.call()
			)
			sheet.add_row(li)
	main.open_layer(s)


func _rename(path: String, title: String) -> void:
	main.open_keyboard("Neuer Titel", title, func(v: String) -> void:
		if v.strip_edges() == "":
			return
		if Capture.rename(path, v.strip_edges()) == "":
			Toasts.show_toast("Umbenennen ging nicht", "Datei ist geöffnet. Programm schließen und erneut versuchen.", "warning")
	)


func _ask_delete(path: String) -> void:
	main.open_dialog("In den Papierkorb?", path.get_file(), [
		["In den Papierkorb", func() -> void:
			# Erst nach ein paar Sekunden wirklich in den Papierkorb (Rückgängig), bis dahin ausgeblendet.
			if Capture.is_own_file(path):
				Undo.offer_files("In den Papierkorb gelegt", path.get_file(), "trash", [path], "capture")
			elif Capture.remove(path):
				Toasts.show_toast("In den Papierkorb gelegt", path.get_file(), "trash", { "quiet": true, "sound": "select" })
			else:
				Toasts.show_toast("Löschen ging nicht", "Datei ist geöffnet. Programm schließen und erneut versuchen.",
						"warning"), "danger"],
		["Abbrechen", func() -> void: pass],
	])


## FFmpeg einrichten (einmalig, mit Fortschritt). Sagt vorher, was passiert.
## danach: nach „Laden“, sobald der Download im Hintergrund läuft (Guide im Spiel: dann zugehen).
static func ask_install(m: Main, danach := Callable()) -> void:
	if not Config.is_windows():
		Toasts.show_toast("Nur unter Windows", "FFmpeg richtet Uzai nur am Windows-PC ein.", "warning")
		return
	if Capture.installing:
		Toasts.show_toast("Eigene Aufnahme", "Wird schon eingerichtet.", "download", { "tag": "ffmpeg" })
		return
	m.open_dialog("Eigene Aufnahme einrichten", "Für Clips, Aufnahmen und Bildschirmfotos aus Vollbild-Spielen lädt Uzai einmalig FFmpeg (etwa 190 MB, freie Software unter der GPL, Build von BtbN über GitHub, auf ffmpeg.org verlinkt) in seinen Datenordner und prüft die Prüfsumme. Nichts wird in Windows installiert.", [
		["Laden", func() -> void:
			_install(m)
			if danach.is_valid():
				danach.call()],
		["Abbrechen", func() -> void: pass],
	], "download")


static func _install(_m: Node) -> void:
	var last := [-1]
	var cb := func(text: String, frac: float) -> void:
		var pct := int(frac * 100.0)
		if pct / 10 != last[0] or frac >= 1.0:
			last[0] = pct / 10
			Toasts.show_toast("Eigene Aufnahme", text, "download", { "quiet": true, "ms": 2600, "tag": "ffmpeg" })
	Capture.progress.connect(cb)
	var err: String = await Capture.install()
	Capture.progress.disconnect(cb)
	if err == "":
		Toasts.show_toast("Aufnahme bereit", "Guide → „Clip speichern“.", "video", { "sound": "select" })
	else:
		Toasts.show_toast("Einrichten ging nicht", err, "warning", { "ms": 8000 })


# --- Teilen ----------------------------------------------------------------------------------

static func open_share(m: Main, path: String) -> void:
	var clip := L.kind_of(path) == "clip"
	var s = Sheet.new()
	s.setup("Teilen", path.get_file(), 820)
	s.subheading_raw = true      # Dateiname
	s.help_on = true
	s.fill_func = func(sheet) -> void:
		var rows: Array = [
			["An Handy senden", "qr", "Per QR-Code ans Handy. Nur im Heimnetz.",
				func() -> void: share_phone(m, path)],
			["In Discord senden", "discord",
				"An einen Freund oder Kanal." + (" Clips über %s MB werden verkleinert." % str(Capture.opt("discord_mb"))
				if clip else ""), func() -> void: pick_discord(m, path)],
		]
		if not clip:
			rows.append(
					["In Steam-Chat senden", "steam",
					"Nur Bilder.",
					func() -> void: pick_steam(m, path)])
		for r in rows:
			var li = ListItem.new()
			li.setup(str(r[0]), str(r[2]))
			li.icon_name = str(r[1])
			var cb: Callable = r[3]
			var desc := str(r[2])
			li.focus_entered.connect(func() -> void: sheet.set_help(desc))
			li.activated.connect(func() -> void:
				sheet.close()
				cb.call()
			)
			sheet.add_row(li)
		sheet.add_gap()
	m.open_layer(s)


static func share_phone(m: Main, path: String) -> void:
	var url := Capture.share_link([path])
	if url == "":
		Toasts.show_toast("Kein Heimnetz gefunden", "Das Handy muss im selben WLAN sein wie der PC.", "warning")
		return
	var q = Qr.new()
	q.url = url
	q.file = path
	m.open_layer(q)


## „An wen?“: zuletzt benutzter Server-Kanal (als schnelle Wahl), ein Freund oder ein Server-Kanal.
static func pick_discord(m: Main, path: String) -> void:
	var last := last_channel()
	# Die nächste Auswahl erst nach dem Schließen dieser (sonst gäbe sie den Fokus zurück).
	m.open_choice("An wen?", L.discord_targets(last), null, func(v: Variant) -> void:
		match str(v):
			"last":
				(func() -> void: send_discord_channel(m, path, last)).call_deferred()
			"server":
				(func() -> void: pick_server(m, path)).call_deferred()
			_:
				(func() -> void: pick_friend(m, path)).call_deferred()
	, "Discord")


static func pick_friend(m: Main, path: String) -> void:
	if DiscordChat.state != "bereit" and not DiscordChat.demo:
		m.open_dialog("Discord-Nachrichten verbinden", "Discord unter Einstellungen → Konten verbinden.", [
			["An Handy senden", func() -> void: share_phone(m, path)],
			["Abbrechen", func() -> void: pass],
		], "discord")
		return
	var opts: Array = []
	for f in DiscordChat.friends:
		opts.append([str(f.id), str(f.name)])
	if opts.is_empty():
		Toasts.show_toast("Keine Discord-Freunde gefunden", "", "discord")
		return
	m.open_choice("Welcher Freund?", opts, null, func(id: Variant) -> void: send_discord(m, path, str(id)), "Discord")


## Server-Kanäle: Server und Kanäle kennt Uzai aus der Discord-Verbindung für Sprachkanäle (RPC,
## GET_GUILDS / GET_CHANNELS – dieselbe wie im Guide). Ohne sie ein ruhiger Hinweis.
const RECENT_KEY := "accounts.discord_clip_channels"


static func recent_channels() -> Array:
	var r: Variant = Config.get_value(RECENT_KEY, [])
	return (r as Array).filter(func(x) -> bool: return x is Dictionary) if r is Array else []


static func last_channel() -> Dictionary:
	var r := recent_channels()
	return r[0] if not r.is_empty() else {}


static func pick_server(m: Main, path: String) -> void:
	if not Voice.ready_() and not Voice.demo:
		m.open_dialog("Discord-Server verbinden", "Discord verbinden und die Discord-App am PC starten.", [
			["Discord verbinden", func() -> void:
				var l = load("res://src/ui/layers/discord_connect.gd").new()
				l.set("autostart", Voice.configured())
				m.open_layer(l)],
			["An Handy senden", func() -> void: share_phone(m, path)],
			["Abbrechen", func() -> void: pass],
		], "discord")
		return
	if Voice.guilds.is_empty():
		Voice.load_guilds()
		await Voice.wait_guilds(4.0)
	if Voice.guilds.is_empty():
		Toasts.show_toast("Keine Server gefunden", Voice.guilds_error if Voice.guilds_error != ""
				else "Serverliste fehlt. Erneut versuchen.", "discord", { "ms": 6000 })
		return
	var opts: Array = []
	for g in L.sort_guilds(Voice.guilds, recent_channels()):
		opts.append([str(g.id), str(g.name)])
	m.open_choice("Welcher Server?", opts, str(last_channel().get("guild_id", "")),
			func(gid: Variant) -> void: (func() -> void: pick_channel(m, path, str(gid))).call_deferred(), "Discord")


static func pick_channel(m: Main, path: String, guild_id: String) -> void:
	var gname := Voice.guild_name(guild_id)
	var raw: Array = await Voice.text_channels(guild_id, 5.0)
	var recent_ids: Array = recent_channels().map(func(x) -> String: return str(x.get("channel_id", "")))
	var list := L.discord_text_channels(raw, recent_ids)
	if list.is_empty():
		Toasts.show_toast("Keine Textkanäle in %s" % gname, Voice.guilds_error if Voice.guilds_error != "" else "Discord hat keine Kanäle zum Schreiben geschickt.",
				"discord", { "ms": 6000 })
		return
	var opts: Array = []
	var names := {}
	for c in list:
		opts.append([str(c.id), "#" + str(c.name), "zuletzt benutzt" if recent_ids.has(str(c.id)) else ""])
		names[str(c.id)] = str(c.name)
	m.open_choice("Welcher Kanal?", opts, str(last_channel().get("channel_id", "")), func(cid: Variant) -> void:
		send_discord_channel(m, path, { "guild_id": guild_id, "guild": gname, "channel_id": str(cid), "channel": str(names.get(str(cid), "")) })
	, gname)


## In einen Server-Kanal: merken (schnelle Wahl beim nächsten Mal), dann wie bei Freunden.
static func send_discord_channel(m: Main, path: String, target: Dictionary) -> void:
	if str(target.get("channel_id", "")) == "" or str(target.get("guild_id", "")) == "":
		pick_server(m, path)
		return
	Config.set_value(RECENT_KEY, L.remember_channel(recent_channels(), target))
	await _send_to_discord(m, path, L.discord_channel_url(str(target.guild_id), str(target.channel_id)), "#" + str(target.get("channel", "")))


## Datei in die Zwischenablage, Discord mit der Direktnachricht nach vorn, Strg+V, Enter.
static func send_discord(m: Main, path: String, friend_id: String) -> void:
	var name := str(DiscordChat.friend(friend_id).get("name", "Freund"))
	if not DiscordChat.dm_channels.has(friend_id):
		await DiscordChat.history(friend_id, 20, false)
	var cid := str(DiscordChat.dm_channels.get(friend_id, ""))
	if cid == "":
		Toasts.show_toast("Gespräch nicht gefunden", "Erst eine Nachricht an %s schreiben." % name, "discord", { "ms": 6000 })
		return
	await _send_to_discord(m, path, L.discord_dm_url(cid), name)


## Der gemeinsame Weg (Freund und Server-Kanal): zu große Clips verkleinern, Datei in die
## Zwischenablage, Discord über den Link nach vorn, Strg+V, Enter. Die Guide-Taste holt Uzai zurück.
static func _send_to_discord(m: Main, path: String, url: String, label: String) -> void:
	var file := path
	if L.kind_of(path) == "clip" and L.needs_shrink(Capture._file_size(path), int(str(Capture.opt("discord_mb")))):
		Toasts.show_toast("Clip wird für Discord verkleinert", "Damit er unter %s MB passt …" % str(Capture.opt("discord_mb")), "discord", { "quiet": true })
		file = await Capture.discord_version(path)
		if file == "":
			Toasts.show_toast("Verkleinern ging nicht", "Stattdessen „An Handy senden“ wählen.", "warning")
			return
	var cr := await Helper.run("clip-files", { "file": Capture.win(file) }, 8.0)
	if not cr.ok or not bool((cr.result as Dictionary).get("ok", false) if cr.result is Dictionary else false):
		Toasts.show_toast("Zwischenablage ging nicht", Helper.klartext(str(cr.get("error", ""))), "warning")
		return
	await m.alle_ebenen_zu()
	if Config.kid_stop("chats"):
		return
	m.set("_away_for_discord", true)
	OS.shell_open(url)
	var fr := await Helper.run("discord-front", { "wait_ms": 6000 }, 10.0)
	var res: Dictionary = fr.result if fr.get("result") is Dictionary else {}
	if not bool(res.get("found", false)):
		Toasts.show_toast("Discord-App nicht gefunden", "Discord-App am PC starten.", "warning", { "overlay": true })
		return
	await m.get_tree().create_timer(1.6).timeout
	var hw := int(res.get("hwnd", 0))
	await Helper.run("keys", { "hwnd": hw, "keys": "CTRL+V", "require_focus": true }, 6.0)
	# Discord zeigt den Anhang erst an (Vorschau), dann nimmt Enter ihn mit.
	await m.get_tree().create_timer(2.2).timeout
	var r := await Helper.run("keys", { "hwnd": hw, "keys": "ENTER", "require_focus": true }, 6.0)
	var sent := bool((r.result as Dictionary).get("sent", false)) if r.get("result") is Dictionary else false
	Toasts.show_toast("An %s gesendet" % label if sent else "In Discord eingefügt", "Guide-Taste bringt dich zurück." if sent
			else "In Discord mit Enter senden.", "discord", { "overlay": true, "ms": 6000 })


static func pick_steam(m: Main, path: String) -> void:
	var opts: Array = []
	for f in Social.steam_friends:
		opts.append([str(f.id), str(f.name)])
	if opts.is_empty():
		Toasts.show_toast("Keine Steam-Freunde gefunden", "Steam unter Einstellungen → Konten verbinden.", "steam")
		return
	m.open_choice("An wen?", opts, null, func(id: Variant) -> void: send_steam(m, path, str(id)), "Steam-Chat")


static func send_steam(m: Main, path: String, steam_id: String) -> void:
	# Die Kennung landet in einem steam://-Link: nur Ziffern.
	if not steam_id.is_valid_int() or steam_id.begins_with("-"):
		return
	var cr := await Helper.run("clip-files", { "file": Capture.win(path) }, 8.0)
	if not cr.ok:
		Toasts.show_toast("Zwischenablage ging nicht", Helper.klartext(str(cr.get("error", ""))), "warning")
		return
	await m.alle_ebenen_zu()
	m.set("_away_for_discord", true)
	OS.shell_open("steam://friends/message/" + steam_id)
	await m.get_tree().create_timer(2.5).timeout
	var fg := await Helper.run("fg-proc", {}, 4.0)
	var nm := str((fg.result as Dictionary).get("name", "")) if fg.get("result") is Dictionary else ""
	var fg_hw := int((fg.result as Dictionary).get("hwnd", 0)) if fg.get("result") is Dictionary else 0
	if nm.begins_with("steam") and fg_hw != 0:
		# Strg+V nur an genau dieses Steam-Fenster (der Helfer drückt nur, wenn es vorn ist).
		await Helper.run("keys", { "hwnd": fg_hw, "keys": "CTRL+V" }, 6.0)
	m.set_mouse_mode(true, false)
	Toasts.show_toast("Im Steam-Chat", "Bild eingefügt. Mit der Maus „Hochladen“ wählen."
			if nm.begins_with("steam") else "Bild liegt in der Zwischenablage.", "steam",
			{ "overlay": true, "ms": 9000 })
