extends "res://src/ui/layers/guide_basis.gd"
## Guide, Schicht über guide_basis.gd: der Reiter Start – oben das laufende Spiel (sonst das
## zuletzt gespielte oder das Video, das gerade läuft) mit seiner Hauptaktion, darunter eine Liste.
## Was alle Lagen teilen (Musik, Freunde, schnelle Regler), hängt guide.gd über _start_tail an.

const RemotePlay := preload("res://src/core/remote_play.gd")
const CoverArt := preload("res://src/ui/components/cover_art.gd")
const People := preload("res://src/ui/components/guide_people.gd")
const QuickResumeG := preload("res://src/core/quick_resume.gd")
const GuideGame := preload("res://src/ui/components/guide_game.gd")
const ListItemG := preload("res://src/ui/components/list_item.gd")
const GuideStartS := preload("res://src/ui/components/guide_start.gd")
const LeerBuehneG := preload("res://src/ui/components/leer_buehne.gd")

const ART := Vector2(110, 150)       ## Cover im Spielblock (hochkant)
const THUMB := Vector2(176, 99)      ## Vorschaubild eines Videos im Spielblock

const Main := preload("res://src/main.gd")
var main: Main
var _ach_asked := ""
var _session_l: Label             ## „PlayStation 2 · Sitzung 0:12:40“ – läuft mit
var _time_l: Label                ## „Heute 1,2 Std. · Insgesamt 120 Std.“ unter dem Balken – läuft mit
var _today_before := 0            ## heute vor dieser Sitzung gespielt (Sekunden), einmal je Aufbau gerechnet
var _start_list: VBoxContainer    ## die Zeilen unter dem Block; „Mehr …“ hängt sich unten an
var _start_more: Array = []       ## was unter „Mehr …“ aufklappt (Lage zuerst; guide.gd hängt „Alle Aktionen“ an)


# --- Start ---------------------------------------------------------------------------------

## Reiter „Start“: im Spiel das Spiel, beim Video das Video, sonst das zuletzt gespielte – immer
## oben ein Block mit Bild und Hauptaktion, darunter wenige Zeilen, die in dieser Lage am
## häufigsten zählen, dann „Mehr …“, das an Ort und Stelle aufklappt (Seltenes), und nur wenn es
## etwas zu sehen gibt: Kontext, Neues, Musik, wer mitspielt, zuletzt die Schnellleiste (_start_tail).
func _tab_game() -> void:
	_session_l = null
	_time_l = null
	_start_list = null
	_start_more = []
	_today_before = 0
	if Launcher.in_game:
		_today_before = GuideStartS.today_secs(Library.load_sessions(), str(Launcher.current.get("id", "")), int(Time.get_unix_time_from_system()),
				int(Time.get_time_zone_from_system().get("bias", 0)))
	if Video.watching():
		_game_video()
	elif Launcher.in_game and Launcher.is_app(Launcher.current):
		GuideGame.fill_app(self, Launcher.current)
	elif Launcher.in_game:
		_game_running(Launcher.current)
	else:
		_game_start()
	_start_tail()


## Unten im Reiter Start (guide.gd): Musik, Freunde und die schnellen Regler.
func _start_tail() -> void:
	pass


## Name des Reiters: „Start“ (im Spiel und ohne), „Video“, solange eins läuft.
static func game_tab_label() -> String:
	if Video.watching():
		return "Video"
	# „Start“ heißt hier Startseite; im Englischen „Home“, nicht „Startup“.
	return TranslationServer.translate("Start", "tab")


## Spielblock und Aktionen: links das Bild (mit Glimmen in der Spielfarbe), daneben der Titel
## groß (zweizeilig erlaubt) und eine kompakte Zeile, optional mit Balken; darunter die Aktionen
## [text, art, symbol, uz_key, aktion, hinweis A]: art „primary“ ist die eine Hauptaktion (A-Kreis,
## hervorgehoben), alle anderen stehen leise als Text daneben. Die Hauptaktion ist der Standard.
## Meta „uz_sub“ und „uz_bar“: die Zeile und der Balken (Bild in Bild und Video-Ton ziehen sie nach).
func _head_row(game: Dictionary, title: String, sub: String, frac: float, pills: Array, thumb := "") -> Control:
	var box := U.vbox(22)
	box.set_meta("uz_group", "guide:head")
	var row := U.hbox(22)
	box.add_child(row)
	row.add_child(_small_art(game, thumb))
	var col := U.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	# Lange Spiel- und Videotitel dürfen zweizeilig stehen, statt mitten im Wort abzubrechen.
	var tl := U.label(title, "l", "text", "title", true)
	tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tl.max_lines_visible = 2
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.add_theme_font_size_override("font_size", 32)
	tl.add_theme_constant_override("line_spacing", -6)
	# Mit Umbruch und „…“ meldet das Label nur 1 px Höhe: die Zeilen ausdrücklich.
	var tf := tl.get_theme_font("font")
	var room := PANEL_W - PAD_X * 2.0 - (THUMB.x if thumb != "" or game.is_empty() else ART.x) - 22.0
	var two := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x > room
	tl.custom_minimum_size = Vector2(0, tf.get_height(32) * (2.0 if two else 1.0) - (6.0 if two else 0.0))
	col.add_child(tl)
	var sl := U.ellipsis(U.label(sub, "s", "muted", "medium"))
	sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sl.visible = sub != ""
	col.add_child(sl)
	box.set_meta("uz_sub", sl)
	if frac >= 0.0:
		col.add_child(U.spacer(0, 4, false))
		var bar = ProgressBarUz.new().setup(clampf(frac, 0.0, 1.0), "accent", 3, 0)
		col.add_child(bar)
		box.set_meta("uz_bar", bar)
	if not pills.is_empty():
		box.add_child(_actions(pills))
	return box


## Aktionen unter dem Block: die Hauptaktion klar hervorgehoben, die anderen leise daneben.
func _actions(pills: Array) -> Control:
	var acts := U.hbox(8)
	acts.set_meta("uz_row", true)
	for p in pills:
		var a := _Action.new()
		a.text = str(p[0])
		a.primary = str(p[1]) == "primary"
		a.set_meta("uz_key", str(p[3]))
		if str(p[5]) != "":
			a.set_meta("uz_hint_a", str(p[5]))
		a.activated.connect(p[4])
		if a.primary:
			a.set_meta("uz_default", true)
		acts.add_child(a)
	return acts


## Bild im Block: Cover hochkant (110 × 150) oder Vorschaubild eines Videos (176 × 99), dahinter
## ein weiches Glimmen in der Farbe des Spiels.
func _small_art(game: Dictionary, url := "") -> Control:
	var app := str(game.get("source", "")) == "app"
	if app:
		url = str((game.get("images", {}) as Dictionary).get("logo", "")) if game.get("images") is Dictionary else ""
	var wide := url != "" or game.is_empty() or app
	var sz := THUMB if wide else ART
	var holder := Control.new()
	holder.custom_minimum_size = sz
	holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := TextureRect.new()
	glow.texture = _glow_tex()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = -sz * 0.9
	glow.size = sz * 2.8
	glow.modulate = Color(UzTheme.col("accent"), 0.0)
	holder.add_child(glow)
	if not game.is_empty() and not app:
		var wg: WeakRef = weakref(glow)
		Media.game_tint(game, func(c: Variant) -> void:
			var gl: TextureRect = wg.get_ref()
			if gl and c is Color:
				# Licht in der Farbe des Spiels: nur Hintergrund, langsam (T_LICHT).
				U.ankommen(gl, U.T_RAUM, "uz_glow").tween_property(gl, "modulate", Color(c as Color, 0.5), U.T_LICHT)
		)
	else:
		glow.modulate.a = 0.25
	var p := Panel.new()
	U.full_rect(p)
	p.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), 2))
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(p)
	if app:
		var ac := CenterContainer.new()
		U.full_rect(ac)
		ac.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ac.add_child(U.icon("desktop" if str((game.get("app", {}) as Dictionary).get("kind", "")) == "prog" else "tv", 40, "faint"))
		p.add_child(ac)
	elif not game.is_empty():
		var art := CoverArt.new()
		art.compact = true
		art.show_title = false
		U.full_rect(art)
		p.add_child(art)
		art.setup(game)
	else:
		var c := CenterContainer.new()
		U.full_rect(c)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(U.icon("video" if Video.active else "games", 40, "faint"))
		p.add_child(c)
	var tr_ := TextureRect.new()
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(tr_)
	tr_.modulate.a = 0.0
	p.add_child(tr_)
	var wt: WeakRef = weakref(tr_)
	var put := func(t: Texture2D) -> void:
		var r: TextureRect = wt.get_ref()
		if r and t:
			r.texture = t
			U.ankommen(r, U.T_ORT, "uz_tex").tween_property(r, "modulate:a", 1.0, U.T_ORT)
	if app:
		tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if url != "":
			Media.file_texture(url, 120, put)
	elif url != "":
		Media.url_texture(url, 360, put)
	elif not game.is_empty():
		Media.game_texture(game, "cover", put)
	return holder


static var _glow_t: GradientTexture2D


## Weicher, runder Lichtfleck (hinter Cover und Musik).
static func _glow_tex() -> GradientTexture2D:
	if _glow_t:
		return _glow_t
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	_glow_t = GradientTexture2D.new()
	_glow_t.gradient = g
	_glow_t.fill = GradientTexture2D.FILL_RADIAL
	_glow_t.fill_from = Vector2(0.5, 0.5)
	_glow_t.fill_to = Vector2(1.0, 0.5)
	_glow_t.width = 128
	_glow_t.height = 128
	return _glow_t


## Eine Schnellaktion als Zeile (rechts ihr Zustand); on: Symbol im Akzent (läuft gerade).
func _quick(t: String, ic: String, cb: Callable, st := "", on := false, key := "") -> Control:
	var q = GuideRow.new().setup(t, ic, "", st)
	q.icon_color = "accent" if on else "muted"
	q.set_meta("uz_key", "q:" + (key if key != "" else t))
	q.activated.connect(cb)
	return _rv(q)


static func _source_name(g: Dictionary) -> String:
	match str(g.get("source", "")):
		"app": return "Programm" if str((g.get("app", {}) as Dictionary).get("kind", "")) == "prog" else "Store-App"
		"steam": return "Steam"
		"epic": return "Epic Games"
		"ea": return "EA app"
		"pc": return "PC"
	return Library.store_name(g, false, str(Config.system(str(g.get("system", ""))).get("name", "Emulator")))


## Tastenkürzel des Emulators für Speichern/Laden („F1“), zur Anzeige in der Zeile.
static func _key_text(action: String) -> String:
	var g: Dictionary = Launcher.current
	var emu := Config.emulator(str(g.get("emulator", Config.system(str(g.get("system", ""))).get("emulator", ""))))
	return str((emu.get("keys", {}) as Dictionary).get(action, "")).to_upper() if emu.get("keys") is Dictionary else ""


## Sitzung als Uhr: „0:12:40“.
static func session_clock(secs: int) -> String:
	var s := maxi(0, secs)
	return "%d:%02d:%02d" % [floori(s / 3600.0), floori((s % 3600) / 60.0), s % 60]


## Zeile unter dem Titel im Spiel: „PlayStation 2 · Sitzung 0:12:40 · Disc · Heute 1,2 Std.“
## (läuft mit; die Spielzeit zuletzt – sie fällt als Erstes weg, wenn es eng wird).
func session_line(g: Dictionary) -> String:
	var bits := PackedStringArray()
	if Launcher.hung:
		bits.append(tr("Antwortet nicht"))
	bits.append(tr(_source_name(g)))
	bits.append(tr("Sitzung %s") % session_clock(Launcher.elapsed()))
	if Discs.is_disc_game(g):
		bits.append(tr("Disc"))
	if Lossless.active:
		bits.append(tr("Bildrate ×2"))
	return "  ·  ".join(bits)


## Zeile unter dem Balken im Spiel: „Heute 1,2 Std.  ·  Insgesamt 120 Std.“ (läuft mit; "" ohne
## beides, bei Apps immer "").
func time_line(g: Dictionary) -> String:
	if Launcher.is_app(g):
		return ""
	return GuideStartS.time_bit(_today_before, Launcher.elapsed(), Library.playtime(g))


## Läuft im Guide mit (_process): die Sitzungszeit und die Spielzeit heute.
func _tick_session() -> void:
	if not Launcher.in_game:
		return
	if is_instance_valid(_session_l):
		_session_l.text = session_line(Launcher.current)
	if is_instance_valid(_time_l):
		_time_l.text = time_line(Launcher.current)


## Im Spiel: Block, Aktionen und die Liste (Bildschirmfoto, Aufnahme, Bildmodus, Overlay, Mehr …).
func _game_running(g: Dictionary) -> void:
	GuideGame.fill_running(self, g)
	if Achievements.has_ra() or Achievements.has_steam():
		_ask_achievements(g)


## Freund ins laufende Spiel einladen (Steam) bzw. zu Remote Play.
func _invite_picker(g: Dictionary) -> void:
	main.open_friend_picker("Wen einladen?", func(_kind: String, f: Dictionary) -> void:
		if str(g.get("source", "")) == "steam":
			main.invite_friend(f)
		else:
			RemotePlay.invite(f)
	, true)


func _ask_quit() -> void:
	var title := str(Launcher.current.get("title", "Spiel"))
	# Beenden läuft schon, und es schließt sich nicht: Der zweite Druck („Sofort beenden“) beendet
	# gleich hart – ohne neue Rückfrage, die gab es eben.
	if Launcher.quitting:
		close()
		Launcher.quit_game(true)
		return
	# Hängt das Spiel (oder ging Beenden eben nicht), hilft höfliches Schließen nicht mehr (und ein
	# Spielstand lässt sich nicht sichern): hart beenden, nur nach Rückfrage. Die Auswahl steht auf
	# „Weiter warten“.
	if Launcher.hung or Launcher.quit_haengt:
		main.open_dialog(("%s antwortet nicht" if Launcher.hung else "%s läuft noch") % title, "Nicht gespeicherter Fortschritt geht verloren.", [
			["Sofort beenden", func() -> void:
				close()
				Launcher.quit_game(true), "danger"],
			["Weiter warten", func() -> void: pass],
		], "warning", "warn")
		return
	# „Beenden“ als gefährlich markiert: die Auswahl steht auf „Abbrechen“ – zweimal A beendet
	# das Spiel nicht mehr aus Versehen ohne Speichern.
	main.open_dialog("%s beenden?" % title, "Nicht gespeicherter Fortschritt geht verloren.", [
		["Beenden", func() -> void:
			close()
			Launcher.quit_game(), "danger"],
		["Abbrechen", func() -> void: pass],
	])


## Spielzeit der letzten sieben Tage: [Säulen (klein, für eine Zeile), Summe in Sekunden].
func _week_bars(gid: String) -> Array:
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var vals := People.week(Library.load_sessions(), gid, now, bias)
	if Launcher.in_game and (gid == "" or gid == str(Launcher.current.get("id", ""))):
		vals[6] = int(vals[6]) + Launcher.elapsed()
	var total := People.sum(vals)
	if total <= 0:
		return [null, 0]
	var bars := _WeekBars.new()
	bars.values = vals
	return [bars, total]


## Ohne Spiel: das zuletzt gespielte oben mit „Spielen“, darunter die Wege (zuletzt gespielt,
## Bibliothek, Aufnahmen, Erfolge und Spielzeit, Shop) als Zeilen.
func _game_start() -> void:
	var recent := Library.recent(5).filter(func(x): return Library.last_played(x) > 0)
	if recent.is_empty():
		recent = Library.recent(5)
	# Eingelegte Disc: ihr Spiel vorn (A startet das Abbild aus der Bibliothek).
	var dg := Discs.game()
	if not dg.is_empty():
		recent = [dg] + recent.filter(func(x): return str(x.get("id", "")) != str(dg.id)).slice(0, 4)
	# Stelle gemerkt (Spielstände): das jüngste Spiel damit vorn, außer eine Disc liegt ein.
	var qr: Dictionary = QuickResumeG.latest() if dg.is_empty() else {}
	if not qr.is_empty():
		var qg: Dictionary = qr.game
		recent = [qg] + recent.filter(func(x): return str(x.get("id", "")) != str(qg.id)).slice(0, 4)
	if recent.is_empty():
		# Noch keine Spiele: die schmale Bühne mit angedeuteten Covern; A sucht gleich (Steam, Epic,
		# EA und die Spieleordner), daneben die Spieleordner.
		var empty := U.vbox(18)
		var sucht := Library.scanning
		empty.add_child(LeerBuehneG.new().setup({ "art": "cover", "symbol": "games", "schmal": true,
			"titel": "Spiele werden gesucht …" if sucht else "Deine Spiele erscheinen hier." }))
		empty.add_child(_actions([["Spiele suchen", "primary", "search", "g:scan", func() -> void:
			LeerBuehneG.weg(main, "spiele").call()
			_show_tab("spiel", true), ""],
			["Ordner wählen", "", "folder", "g:folders", func() -> void:
			close()
			main.goto("settings", "emulation"), ""]]))
		_content.add_child(_rv(empty))
		_content.add_child(_divider(22))
		_start_list = _ways([])
		_content.add_child(_start_list)
		return
	var r: Dictionary = recent[0]
	var secs := Library.playtime(r)
	# „Gestern · 14 Std.“: wann zuletzt und wie viel – „Zuletzt gespielt“ heißt die Liste darunter.
	var head_sub := tr("Disc eingelegt") + ("  ·  " + People.dur(secs) if secs > 0 else "") if Discs.is_disc_game(r) \
			else GuideStartS.stage_sub(Library.last_played(r), secs)
	if not qr.is_empty() and str(r.get("id", "")) == str((qr.game as Dictionary).get("id", "")):
		var rec: Dictionary = qr.rec
		_content.add_child(
				_rv(_head_row(r, Library.display_title(r), tr("Stelle gemerkt") + "  ·  " + tr(QuickResumeG.ago_short(int(Time.get_unix_time_from_system()) - int(rec.get("at", 0)))),
				-1.0, [
			[QuickResumeG.RESUME_TEXT, "primary", "play", "g:art", func() -> void:
				close()
				var rg := QuickResumeG.resume_game(r, rec)
				main.launch(rg if not rg.is_empty() else r), "Weiterspielen"],
			["Neu starten", "flat", "restart", "g:fresh", func() -> void:
				close()
				main.launch(r), "Ohne gemerkte Stelle starten"],
		])))
	else:
		_content.add_child(_rv(_head_row(r, Library.display_title(r), head_sub, -1.0, [
			["Spielen", "primary", "play", "g:art", func() -> void:
				close()
				main.launch(r), "Spielen"],
		])))
	_content.add_child(_divider(22))
	_start_list = _ways(recent.slice(1, 5))
	_content.add_child(_start_list)


## Wege ohne Spiel: weitere zuletzt gespielte (A: Liste zum Starten), Bibliothek, Erfolge und
## Spielzeit (mit der Woche als kleinen Säulen), die neueste Aufnahme, wenn sie von heute ist;
## sonst stehen Aufnahmen und Shop unter „Mehr …“.
func _ways(more: Array) -> VBoxContainer:
	var list := _list()
	if not more.is_empty():
		var covers := U.hbox(-14)
		covers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for x in more:
			covers.add_child(_mini_cover(x))
		var rr = GuideRow.new().setup(tr("Zuletzt gespielt"), "history", Library.display_title(more[0]))
		rr.own_text = true
		rr.trail = covers
		rr.chevron = true
		rr.set_meta("uz_key", "g:recent")
		rr.set_meta("uz_hint_a", "Auswählen")
		rr.activated.connect(func() -> void: _recent_sheet(more))
		list.add_child(_rv(rr))
	list.add_child(_rv(_act("Bibliothek", "games", func() -> void:
		close()
		main.goto("games", "alle"))))
	var cap := GuideGame.newest({})
	var fresh := GuideStartS.fresh(cap, int(Time.get_unix_time_from_system()))
	if not fresh:
		_start_more.append(_act("Aufnahmen", "video", func() -> void: main.open_captures(), GuideGame.capture_line(cap)))
	var wk := _week_bars("")
	var ach = GuideRow.new().setup("Erfolge und Spielzeit", "trophy", (People.dur(int(wk[1])) + " " + tr("diese Woche")) if int(wk[1]) > 0 else "")
	ach.chevron = true
	if wk[0] != null:
		ach.trail = wk[0]
	ach.set_meta("uz_key", "g:ach")
	ach.activated.connect(func() -> void:
		close()
		main.goto("achievements", "uebersicht"))
	list.add_child(_rv(ach))
	# Heute aufgenommen: die Aufnahme steht in der Liste (mit Vorschaubild), sonst unter „Mehr …“.
	if fresh:
		list.add_child(_rv(GuideStartS.capture_row(self, cap)))
	if main.sections.has("shop"):
		_start_more.append(_act("Shop", "shop", func() -> void:
			close()
			main.goto("shop")))
	return list


## Kleines Cover für die Zeile „Zuletzt gespielt“ (überlappend, wie die Freunde).
func _mini_cover(g: Dictionary) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(34, 46)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := UzTheme.box(UzTheme.col("surface_hi"), 2)
	sb.border_color = UzTheme.col("bg")
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := CoverArt.new()
	art.compact = true
	art.show_title = false
	U.full_rect(art)
	p.add_child(art)
	art.setup(g)
	var tr_ := TextureRect.new()
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(tr_)
	p.add_child(tr_)
	var wt: WeakRef = weakref(tr_)
	Media.game_texture(g, "cover", func(t: Texture2D) -> void:
		var r: TextureRect = wt.get_ref()
		if r and t:
			r.texture = t
	)
	return p


## Die weiteren zuletzt gespielten Spiele als Liste über dem Guide: A startet.
func _recent_sheet(more: Array) -> void:
	var s = load("res://src/ui/layers/sheet.gd").new()
	s.setup("Zuletzt gespielt", "", 640)
	s.fill_func = func(sheet) -> void:
		for x in more:
			var xg: Dictionary = x
			var it = ListItemG.new()
			# Titel des Spiels: Die Zeile übersetzt nichts von selbst, Quelle und Spielzeit von Hand.
			it.setup(Library.display_title(xg), tr(_source_name(xg)), tr(People.dur(Library.playtime(xg))) if Library.playtime(xg) > 0 else "")
			it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			it.image_url = ""
			it.icon_name = "games"
			it.set_meta("uz_hint_a", "Spielen")
			it.activated.connect(func() -> void:
				sheet.close()
				close()
				main.launch(xg)
			)
			sheet.add_row(it)
	main.open_layer(s)


## Video läuft: Block mit Vorschaubild und Stand, Weiterschauen · Pause/Weiter · Video beenden,
## darunter Bildschirmfoto (X), Übertragen und „Als Nächstes“. Der Guide hält das Video nicht an;
## angehalten wird nur hier mit „Pause“ (oder im Player mit A).
func _game_video() -> void:
	var v: Dictionary = Video.video
	var sub := str(v.get("channel", ""))
	var frac := -1.0
	if Video.duration > 0.0:
		sub = tr("Angehalten bei %s von %s" if Video.paused else "Läuft  ·  %s von %s") % [_mmss(int(Video.pos * 1000.0)), _mmss(int(Video.duration * 1000.0))]
		frac = Video.pos / Video.duration
	var thumb := str(v.get("thumb", v.get("thumbnail", "")))
	_content.add_child(_rv(_head_row({}, str(v.get("title", "Video")), sub, frac, [
		["Weiterschauen", "primary", "play", "g:art", close, "Weiterschauen"],
		["Weiter" if Video.paused else "Pause", "flat", "play" if Video.paused else "pause", "g:video_pause", func() -> void:
			Video.toggle_pause()
			_rebuild_keep("g:video_pause"), "Weiter" if Video.paused else "Pause"],
		["Video beenden", "flat", "close", "g:video_stop", func() -> void:
			close()
			Video.stop(), "Beenden"],
	], thumb)))
	var list := _list()
	if _can_screenshot():
		var shot = GuideRow.new().setup("Bildschirmfoto", "camera")
		shot.key_cmd = "x"
		shot.set_meta("uz_key", "q:shot")
		shot.activated.connect(func() -> void: main.take_screenshot())
		list.add_child(_rv(shot))
	# Im Sprachkanal: das Video mit einem Druck an Discord übertragen (wie ein Spiel).
	if (Voice.in_channel() and main.live_source() == "video") or main.discord_live:
		var lv: bool = main.discord_live
		var gl := _quick("Stream beenden" if lv else "Übertragen", "live", func() -> void: main.discord_go_live(), "live" if lv else "", lv, "live")
		gl.set_meta("uz_hint_a", "Beenden" if lv else "Video übertragen")
		list.add_child(gl)
	if Video.has_next():
		var nv: Dictionary = Video.queue[Video.index + 1] if Video.queue[Video.index + 1] is Dictionary else {}
		# Der Zusatz ist der Titel des Videos: Die Zeile übersetzt nichts von selbst, die Überschrift von Hand.
		var nx = GuideRow.new().setup(tr("Als Nächstes"), "play", str(nv.get("title", "")))
		nx.own_text = true
		nx.chevron = true
		nx.set_meta("uz_key", "q:next")
		nx.set_meta("uz_hint_a", "Jetzt ansehen")
		nx.activated.connect(func() -> void:
			close()
			Video.next()
		)
		list.add_child(_rv(nx))
	_content.add_child(_divider(22))
	_content.add_child(list)
	_start_list = list


func _ask_achievements(g: Dictionary) -> void:
	var gid := str(g.get("id", ""))
	if Library.demo or gid == "" or _ach_asked == gid or not Achievements.cached(g).is_empty():
		return
	_ach_asked = gid
	Achievements.for_game(g)


func _hotkey(action: String, done_text: String) -> void:
	close()
	# Läuft im Hauptbildschirm weiter, der Guide ist gleich weg.
	main.guide_hotkey(action, done_text)


# --- Zeichnen: Aktionen, Spielzeit der Woche ---------------------------------------------------

## Eine Aktion unter dem Spielblock. primary: die Hauptaktion – eine helle, deckende Fläche mit
## A-Kreis und fetter dunkler Schrift; sonst leiser Text ohne Fläche (Beenden ist nie so laut wie
## Weiterspielen). Gewählt tragen beide denselben Cursor wie jede Zeile.
class _Action extends Control:
	signal activated
	const UU := preload("res://src/ui/u.gd")
	const Row := preload("res://src/ui/components/guide_row.gd")
	var text := ""
	var primary := false
	var _l: Label
	var _f := 0.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Equal padding left and right so the word is centered in the cursor (the uneven margins belonged to the
		# button glyph on the disc, which no longer exists since 0.16.75).
		var m := UU.margin(16, 0, 16, 0)
		UU.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var row := UU.hbox(12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(row)
		# The main action looks like the others, such as „Beenden“ (no bright plate any more: the selection disappeared
		# on it); it is only set in bold and preselected (uz_default).
		_l = UU.label(text, "20", "muted", "ui_bold" if primary else "ui")
		_l.clip_text = false
		_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_l)
		custom_minimum_size = Vector2(m.get_combined_minimum_size().x, 52)
		focus_entered.connect(_focus_to.bind(true))
		focus_exited.connect(_focus_to.bind(false))
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	## Der eine Cursor-Takt (Liste.takt): im ersten Bild zu 70 % da, gesetzt in T_ANTWORT.
	func _focus_to(on: bool) -> void:
		if _l:
			UU.set_label_color(_l, "text" if on else "muted")
		Row.Liste.takt(self, _f, on, func(v: float) -> void:
			_f = v
			queue_redraw())

	func activate() -> void:
		activated.emit()

	## Maus darüber (schweben.gd): der Cursor halb, ohne zu wählen.
	var _h := 0.0

	func zeiger_schweben(an: bool) -> void:
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			_h = v
			queue_redraw(), _h, 1.0 if an else 0.0, UU.T_ANTWORT)

	func _draw() -> void:
		Row.draw_cursor(self, Rect2(Vector2.ZERO, size), maxf(_f, _h * 0.45))


## Sieben kleine Säulen in einer Zeile: Spielzeit der letzten sieben Tage, heute im Akzent.
class _WeekBars extends Control:
	var values: Array = []
	var _t := 0.0

	## Die Säulen wachsen nach der Fläche (NACH_FLAECHE) in T_RAUM mit „Ankommen“ hoch.
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(62, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		U.ankommen(self, U.T_RAUM, "uz_bars").tween_method(func(v: float) -> void:
			_t = v
			queue_redraw()
		, 0.0, 1.0, U.T_RAUM).set_delay(U.NACH_FLAECHE)

	func _draw() -> void:
		var n := values.size()
		if n == 0:
			return
		var maxv := 1
		for v in values:
			maxv = maxi(maxv, int(v))
		var col_w := size.x / n
		var bar_w := maxf(3.0, col_w - 4.0)
		for i in n:
			var today := i == n - 1
			var x := col_w * i + (col_w - bar_w) * 0.5
			var v := int(values[i])
			var c := UzTheme.col("accent") if today else UzTheme.col("text", 0.3)
			var h := maxf(2.0, size.y * float(v) / maxv) * _t if v > 0 else 2.0
			draw_rect(Rect2(x, size.y - h, bar_w, h), c if v > 0 else UzTheme.col("faint", 0.6))
