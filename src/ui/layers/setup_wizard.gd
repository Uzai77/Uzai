extends "res://src/ui/layers/setup_wizard_show.gd"
## Einrichtung beim ersten Start, wie bei einer neuen Konsole: wenige ganzseitige Momente, A geht
## durch alle („Weiter“ ist gewählt). Willkommen (das Licht geht an, das Zeichen erscheint groß,
## Sprache), Spiele (der Höhepunkt: der Zähler läuft hoch, die eigenen Cover fliegen gestaffelt in
## die Tiefe der Bühne und glänzen beim Landen, je Quelle ein Schild), die Vorstellung der starken
## Funktionen (Emulatoren, Die Guide-Taste – die echte Taste öffnet ihn zum Ausprobieren –, Dein
## Zimmer, Schauen & Hören; je eine große Animation, setup_wizard_show.gd), Konten (alle Dienste
## nach Bereichen, Steam und Discord groß zuerst, alles freiwillig) und Bereit – „Los“ löst die Bühne in die Startseite
## auf: Licht und Raum gehen, die Startseite baut sich vor den Augen auf, und jedes Cover landet auf
## seinem Gegenstück. Der Controller wird still erkannt (kein eigener Schritt; Koppeln und Test
## unter Einstellungen → Controller). Freiwillig („Mehr einrichten“ am Ende, dann vor „Bereit“
## eingereiht): Aussehen und Extras. Hinter allem die
## Bühne (einrichtung_buehne.gd). Jeder Schritt weiter klingt eine Stufe höher (setup_step,
## Klang.stufe_ton), Gefundenes mit setup_found, Bereit mit setup_done.
## A geht weiter, B geht zurück; oben zeigen Punkte, wo man steht. Ein „Überspringen“ gibt es
## nicht: Wo ein Schritt freiwillig ist, geht „Weiter“ auch ohne ihn. Nie ein Windows-Dialog: Ordner wählt Uzais eigener Dateiauswahl, Koppeln läuft über den
## Helfer (pad_pair.gd).
## Der Stand wird bei jedem Schritt gespeichert (einrichtung.step): Nach einem Neustart geht es
## dort weiter (Schritte älterer Folgen: E.resume_index). Kommt bei neuen Nutzern von selbst, wer sie
## nie abgeschlossen hat, bekommt sie mit „Abbrechen“ angeboten (Regeln: src/core/einrichtung.gd);
## sonst über Einstellungen → System → „Einrichtung erneut starten“. Start, Schritte und Ende stehen
## in logs/einrichtung.log. Danach kommt einmal die kurze Tour (tour.gd).
## Farbschema und Akzent bauen ganz Uzai neu (auch diese Ebene): Die Einrichtung öffnet sich danach
## sofort wieder an derselben Stelle – so ist die Wahl gleich überall zu sehen.
##
## Hier stehen Aufbau, Schrittfolge, Weiter/Zurück und Fertig; Bausteine und die übrigen Schritte
## liegen in den Schichten darunter (setup_wizard_bausteine.gd bis setup_wizard_show.gd).

const Logdatei := preload("res://src/core/logdatei.gd")
const Welcome := preload("res://src/ui/layers/welcome.gd")
const Klang := preload("res://src/core/klang.gd")
const SELF := "res://src/ui/layers/setup_wizard.gd"


var _stage: Control
var _fit: Control                 ## zwischen Bühne und Seiten: verkleinert, wenn ein Schritt nicht passt
var _halter: Control              ## hält die Seite; ein Schritt ist ein Ortswechsel (U.abgang/U.ankunft)
var _dots: _Dots
var _licht: TextureRect           ## der Schein oben (geht beim Auflösen mit)
var _poll: Timer
var _focus_cb: Callable
var _groesse_cb: Callable        ## Fenstergröße geändert: die Seite neu einpassen
var _chain: Array = []           ## Darstellung: [Menüklänge, Größe, Weiter] – runter/hoch in dieser Folge

# --- Von außen ---------------------------------------------------------------------------

## Was Uzai über den Nutzer weiß (für E.is_existing_user).
static func user_state() -> Dictionary:
	var played := 0
	for g in Library.games:
		if int((g as Dictionary).get("playtime", 0)) > 0 or int((g as Dictionary).get("last_played", 0)) > 0:
			played += 1
	return {
		"first_run": bool(Config.get_value("system.first_run", true)),
		"accounts": Config.get_value("accounts", {}),
		"rom_dirs": Config.get_value("library.rom_dirs", {}),
		"pc_dirs": Config.get_value("library.pc_dirs", []),
		"last_game": str(Config.get_value("system.last_game", "")),
		"youtube_refresh": str(Config.get_value("youtube.refresh", "")),
		"nuvio": NuvioSync.connected(),
		"played": played,
	}


## "" (nicht zeigen), "neu", "weiter" oder "anbieten" (E.start_mode).
static func start_mode() -> String:
	return E.start_mode(_stand(), user_state(), Library.demo)


## Der gespeicherte Stand („einrichtung“) für E.start_mode.
static func _stand() -> Dictionary:
	var sk: Variant = Config.get_value("einrichtung.skipped", [])
	return { "done": bool(Config.get_value("einrichtung.done", false)), "step": str(Config.get_value("einrichtung.step", "")),
		"started": int(Config.get_value("einrichtung.started", 0)), "skipped": sk if sk is Array else [] }


## Beim Start: ob und warum die Einrichtung kommt, eine Zeile in logs/einrichtung.log (E.start_grund). Bisher
## stand dazu nirgends etwas – beim Freund ließ sich nicht sehen, warum sie ausblieb.
static func start_protokoll() -> void:
	protokoll("Start: " + E.start_grund(_stand(), user_state(), Library.demo))


## Eine Zeile ins Protokoll der Einrichtung (logs/einrichtung.log): Start, Schritte, Ende. Ohne Daten des Nutzers.
static func protokoll(text: String) -> void:
	if Library.demo:
		return
	Logdatei.zeile(Config.path("logs/einrichtung.log"), "%s %s" % [ProjectSettings.get_setting("application/config/version", ""), text], 100000)


## Einstellungen → System → „Einrichtung erneut starten“: von vorn, B im ersten Schritt bricht ab.
static func open_for(m: Main, from_settings := true) -> Control:
	if from_settings:
		Config.set_value("einrichtung.done", false)
		Config.set_value("einrichtung.step", "willkommen")
		Config.set_value("einrichtung.skipped", [])
		Config.set_value("einrichtung.restart", true)
		Config.set_value("einrichtung.mehr", false)
		Config.set_value("einrichtung.started", 0)
		_guide_probiert = false
	var w = load(SELF).new()
	w.restart = bool(Config.get_value("einrichtung.restart", false))
	m.open_layer(w)
	return w


# --- Aufbau ------------------------------------------------------------------------------

func build() -> void:
	dim = 1.0
	closable = false
	depth = false
	restart = restart or bool(Config.get_value("einrichtung.restart", false))
	if not resume.is_empty():
		set_meta("uz_silent", true)
	_scrim.color = UzTheme.col("bg") if UzTheme.light else UzTheme.col("bg").darkened(0.35)
	var glow := TextureRect.new()
	glow.texture = Welcome._glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(UzTheme.col("accent"), 0.09)
	# Weicher Schein auf dunklem Grund: entstuft (U.entstuft), sonst stünden Ringe im Licht.
	glow.material = U.entstuft()
	glow.anchor_left = 0.5
	glow.anchor_right = 0.5
	glow.offset_left = -1000
	glow.offset_right = 1000
	glow.offset_top = -520
	glow.offset_bottom = 860
	add_child(glow)
	_licht = glow
	_buehne = Buehne.new()
	U.full_rect(_buehne)
	add_child(_buehne)
	var top := U.vbox(10)
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -400
	top.offset_right = 400
	top.offset_top = 44
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_steps = E.steps_for(features(), bool(Config.get_value("einrichtung.mehr", false)))
	if int(Config.get_value("einrichtung.started", 0)) <= 0:
		Config.set_value("einrichtung.started", int(Time.get_unix_time_from_system()))
	_dots = _Dots.new()
	_dots.count = _steps.size()
	_dots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_dots)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_stage)
	_stage.offset_top = 128
	_stage.offset_bottom = -118
	add_child(_stage)
	_fit = Control.new()
	_fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_fit)
	_halter = Control.new()
	_halter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_halter)
	_fit.add_child(_halter)
	_focus_cb = func(c: Control) -> void:
		if is_instance_valid(c) and is_ancestor_of(c) and c.has_meta("uz_key"):
			_last_key = str(c.get_meta("uz_key"))
	get_viewport().gui_focus_changed.connect(_focus_cb)
	# Gleich nach dem Start wechselt das Fenster oft noch seine Größe (Vollbild, anderer Bildschirm,
	# Auflösung): dann neu einpassen – sonst bliebe die Seite in der Größe des ersten Bildes stehen.
	_groesse_cb = func() -> void: _fit_page()
	get_viewport().size_changed.connect(_groesse_cb)
	_poll = Timer.new()
	_poll.wait_time = 0.5
	_poll.autostart = true
	_poll.timeout.connect(_tick)
	add_child(_poll)
	var start := E.resume_index(str(Config.get_value("einrichtung.step", "")), _steps)
	if resume.has("index"):
		start = clampi(int(resume.index), 0, _steps.size() - 1)
	_show_step(start, 0, not resume.is_empty())


func _first_focus() -> Control:
	var key := str(resume.get("key", ""))
	if key != "":
		for c in Nav.focusables(_page):
			if str(c.get_meta("uz_key", "")) == key:
				return c
	return _default if is_instance_valid(_default) else Nav.default_in(_page)


# --- Schritte ------------------------------------------------------------------------------

func _show_step(i: int, dir: int, instant := false) -> void:
	_idx = i
	var id := str(_steps[i])
	if str(Config.get_value("einrichtung.step", "")) != id or resume.is_empty():
		protokoll("Schritt: " + id)
	Config.set_value("einrichtung.step", id)
	Config.save_settings()
	# Der Schritt steht in den Einstellungen (einrichtung.step), nicht in einem eigenen Feld: nur melden.
	Zustand.melden("einrichtung.schritt", id)
	_live.clear()
	_zahl = null
	_chain = []
	_aside_t = null
	_aside_d = null
	_zimmer_box = null
	_probier = null
	_default = null
	_buehne.regal(null)
	_buehne.fokus(null)
	_buehne.zaehler(null)
	var old := _page
	# Schritt vor/zurück ist ein Ortswechsel (Takt): der alte Schritt geht W_ORT gegen die
	# Richtung der Taste (U.abgang), der neue kommt aus ihr (U.ankunft, T_ORT) – nie ease-in auf
	# der Deckkraft, nie ein leeres Bild.
	if is_instance_valid(old) and not instant:
		U.abgang(_halter, dir)
	elif is_instance_valid(old):
		old.queue_free()
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_page)
	_halter.add_child(_page)
	match id:
		"willkommen": _willkommen()
		"du": _du()
		"darstellung": _darstellung()
		"spiele": _spiele()
		"emulatoren": _szene_emulatoren()
		"guide": _szene_guide()
		"zimmer": _szene_zimmer()
		"medien": _szene_medien()
		"konten": _konten()
		"extras": _extras()
		"fertig": _fertig()
	if id in ["spiele", "fertig"]:
		# Erst die Spiele der Startseite auf die Bühne: Am Ende landet jedes Cover auf seinem Gegenstück.
		_buehne.reihe(_startseite_cover().map(func(c: Array) -> String: return str(c[1])))
	_buehne.set_mode(id)
	_fit_page()
	_dots.count = _steps.size()
	_dots.set_cur(i, not instant)
	# Willkommen und Bereit sind Momente, keine Schritte: ohne Punkte.
	var punkte := 0.0 if id in ["willkommen", "fertig"] else 1.0
	if instant:
		_dots.modulate.a = punkte
	else:
		U.ankommen(_dots, U.T_ORT, "uz_punkte_a").tween_property(_dots, "modulate:a", punkte, U.T_ORT)
	set_meta("uz_hint_b", _b_text())
	if not instant:
		U.ankunft(_halter, dir, U.T_ORT, U.NACH_WEG if old else 0.0)
	_tick()
	if old and Nav.top_layer() == self:
		Nav.focus(_default if is_instance_valid(_default) else Nav.default_in(_page), true)
		Nav.focus_moved.emit(Nav.focused())


## Große Oberfläche (oder kleiner Bildschirm): Passt ein Schritt nicht auf die Bühne, wird er als
## Ganzes kleiner, statt links und rechts über den Rand und unten unter die Tastenleiste zu laufen.
## Die Seiten selbst bleiben, wie sie sind (sie gleiten weiter in _fit hin und her). Gemessen wird
## nach dem ersten Ordnen: Umbrechende Texte kennen ihre Höhe erst, wenn ihre Breite feststeht.
## Ändert sich die Fenstergröße (gleich nach dem Start, Vollbild, anderer Bildschirm), neu.
func _fit_page() -> void:
	var page := _page
	await get_tree().process_frame
	if not is_instance_valid(page) or page != _page:
		return
	var room := U.view_size() - Vector2(0.0, 128.0 + 118.0)
	var need := Vector2(PAGE_W, 0.0)
	for c in page.get_children():
		if c is Control:
			need = need.max((c as Control).get_combined_minimum_size())
	var k := minf(1.0, minf(room.x / maxf(need.x, 1.0), room.y / maxf(need.y, 1.0)))
	if k > 0.98:
		k = 1.0
	_fit.position = Vector2.ZERO
	_fit.size = room / k
	_fit.scale = Vector2(k, k)


## how: "weiter" (A) oder "zurück" (B).
func _go(how: String) -> void:
	if _finished:
		return
	if how == "zurück" and _idx == 0:
		_back_at_start()
		return
	if how == "weiter" and str(_steps[_idx]) == "spiele":
		_apply_found()
	var st := E.advance({ "skipped": Config.get_value("einrichtung.skipped", []) }, _steps, _idx, how)
	Config.set_value("einrichtung.skipped", st.skipped)
	if int(st.index) == _idx:
		return
	if how == "weiter":
		# Jeder Schritt weiter eine Stufe höher (E-Dur pentatonisch): Die Einrichtung steigt hörbar an.
		Sfx.play("setup_step", Klang.stufe_ton(int(st.index) - 1))
	else:
		Sfx.play("back" if how == "zurück" else "tab")
	_show_step(int(st.index), -1 if how == "zurück" else 1)


## „Fertig“ → Konten oder Extras: die freiwilligen Schritte einreihen und dorthin gehen.
func _go_mehr(id: String) -> void:
	if _finished:
		return
	Config.set_value("einrichtung.mehr", true)
	_steps = E.steps_for(features(), true)
	var i := _steps.find(id)
	if i < 0:
		return
	Sfx.play("tab")
	_show_step(i, 1)


func handle(cmd: String) -> bool:
	match cmd:
		"guide":
			# Die Guide-Taste gehört weiter dem Guide (er öffnet sich über der Einrichtung); im Schritt
			# „Die Guide-Taste“ zählt der Druck als ausprobiert.
			if str(_steps[_idx]) == "guide":
				_guide_gedrueckt()
			return false
		"b":
			_go("zurück")
			return true
	return false


## Darstellung: Die Größe liegt rechts unter der Vorschau. Runter von „Menüklänge“ führt dorthin
## und weiter zu „Weiter“, hoch zurück – sonst erreichte man sie nur über das Ende der Farbreihe.
func nav_dir(cmd: String) -> bool:
	if (cmd == "up" or cmd == "down") and _chain.all(func(c: Variant) -> bool: return is_instance_valid(c)):
		# Von „Weiter“ aus bleibt hoch, wie es ist (zur Zeile darüber).
		var i := _chain.find(Nav.focused())
		var j := i + (1 if cmd == "down" else -1)
		if i in [0, 1] and j >= 0:
			Nav.focus(_chain[j])
			return true
	return false


func _process(dt: float) -> void:
	if is_instance_valid(_zahl):
		_spiele_tick(dt)


## Zweimal je Sekunde: Anzeigen auffrischen und den Controller still erkennen.
func _tick() -> void:
	_erkennen()
	super._tick()


## Ebene weg (fertig, geschlossen oder Neuaufbau): der Schritt aus Zustand.lage(); öffnet sie wieder, meldet
## _show_step ihn neu.
func _exit_tree() -> void:
	Zustand.vergessen("einrichtung.schritt")


## Neuaufbau der Oberfläche (Farbschema, Akzent …) nimmt die Ebene mit: gleich wieder öffnen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _focus_cb.is_valid() and get_viewport() and get_viewport().gui_focus_changed.is_connected(_focus_cb):
		get_viewport().gui_focus_changed.disconnect(_focus_cb)
	if what == NOTIFICATION_EXIT_TREE and _groesse_cb.is_valid() and get_viewport() and get_viewport().size_changed.is_connected(_groesse_cb):
		get_viewport().size_changed.disconnect(_groesse_cb)
	if what == NOTIFICATION_EXIT_TREE and not _closing and not _finished and is_instance_valid(main):
		_reopen(main, { "index": _idx, "key": _last_key }, restart, main.layer_host)
	# Von außen geschlossen (Spielstart, Profilwechsel, Beenden …), nicht fertig: Der Schritt bleibt gespeichert,
	# beim nächsten Start geht es dort weiter (E.start_mode).
	if what == NOTIFICATION_EXIT_TREE and _closing and not _finished and not _steps.is_empty():
		protokoll("Unterbrochen bei „%s“ – geht beim nächsten Start weiter" % str(_steps[clampi(_idx, 0, _steps.size() - 1)]))


static func _reopen(m: Main, st: Dictionary, was_restart: bool, old_host: Variant) -> void:
	for i in 8:
		if not is_instance_valid(m) or not m.is_inside_tree():
			return
		await m.get_tree().process_frame
		if not is_instance_valid(m):
			return
		var host: Variant = m.layer_host
		if host != old_host and host is Control and is_instance_valid(host) and (host as Control).is_inside_tree():
			break
	if not is_instance_valid(m):
		return
	var w = load(SELF).new()
	w.resume = st
	w.restart = was_restart
	m.open_layer(w)
	U.stop(w, "uz_layer")
	w.modulate.a = 1.0


# --- Bereit -------------------------------------------------------------------------------

## Das Ende ist ein Moment, keine Zusammenfassung: groß „Alles bereit“, darunter eine Zeile mit dem,
## was Uzai jetzt kennt (E.bilanz), die eigenen Cover steigen wieder ins Regal, ein ruhiger
## Lichtschein. „Los“ löst die Bühne in die Startseite auf (_ausklang); „Mehr einrichten“ reiht
## die freiwilligen Schritte (Aussehen, Extras) ein.
func _fertig() -> void:
	var cc := CenterContainer.new()
	U.full_rect(cc)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(cc)
	var col := U.vbox(0)
	col.custom_minimum_size = Vector2(PAGE_W, 0)
	cc.add_child(col)
	var title := Label.new()
	# Mit Namen, wenn du einen gewählt hast (Schritt „Wer spielt?“): Die Konsole kennt dich.
	title.text = E.fertig_titel(str(Config.profile().get("name", "")), tr)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_override("font", UzTheme.display("title"))
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_color", UzTheme.col("text"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.set_meta("uz_titel", true)
	col.add_child(title)
	col.add_child(U.spacer(0, 10, false))
	var st := _summary_state()
	var line := E.bilanz(st, tr)
	if line == "":
		# Nichts gefunden, nichts verbunden: kein leerer Platz unter dem Titel.
		line = tr("Spiele und Konten kannst du jederzeit hinzufügen.")
	var sub := U.label(line, "l", "muted", "regular")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Schon übersetzt (Muster), Namen bleiben, wie sie sind.
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(sub)
	col.add_child(U.spacer(0, 48, false))
	var regal := Control.new()
	regal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ohne Spiele keine leere Reihe (die Bühne hat dann keine Cover).
	regal.custom_minimum_size = Vector2(PAGE_W, 196 if not Library.visible_games().is_empty() else 0)
	col.add_child(regal)
	_buehne.regal(regal, title)
	_buehne.zeigen(999)
	col.add_child(U.spacer(0, 56, false))
	var row := U.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var go := _knopf("Los")
	go.custom_minimum_size = Vector2(300, 64)
	go.set_meta("uz_hint_a", "Los")
	go.set_meta("uz_key", "su:los")
	go.pressed.connect(func() -> void: _finish())
	row.add_child(go)
	# Freiwillig: die übrigen Schritte, solange sie nicht schon eingereiht sind.
	var all_steps := E.steps_for(features(), true)
	var mehr: Array = E.MEHR.filter(func(m: String) -> bool: return all_steps.has(m) and not _steps.has(m))
	if not mehr.is_empty():
		var more := _knopf("Mehr einrichten")
		more.custom_minimum_size = Vector2(0, 64)
		more.set_meta("uz_key", "su:mehr")
		more.set_meta("uz_hint_a", "Einrichten")
		var first := str(mehr[0])
		more.pressed.connect(func() -> void: _go_mehr(first))
		row.add_child(more)
	_default = go
	if resume.is_empty():
		_steigen([title, sub, row], U.T_ORT)
		_feier(title)
		Sfx.play("setup_done")


## Ein ruhiger Lichtschein hinter dem Titel, sobald er steht (Bühne).
func _feier(at_node: Control) -> void:
	await get_tree().create_timer(U.T_ORT + U.T_RAUM).timeout
	if not is_instance_valid(at_node) or not is_instance_valid(_buehne) or not at_node.is_inside_tree():
		return
	var at: Vector2 = _buehne.get_global_transform().affine_inverse() * at_node.get_global_rect().get_center()
	_buehne.feiern(at)


## „Los“: Die Bühne wird zur Startseite, und die baut sich vor den Augen auf (games.gd aufbauen,
## startseite_aufbau.gd). Die Seite geht (Schrift zuerst, T_WEG), Raum und Licht der Einrichtung
## gehen in T_LICHT, während Licht und Raum der Startseite aufgehen; Leiste, Spielbild und Titel,
## Quellen folgen. Die Cover im Regal warten, bis ihre Zeit kommt, und fliegen dann gestaffelt auf
## ihr Gegenstück (flug_bild der Karte, Meta uz_flug „g:<id>“); beim Landen steht ab dem Bild das
## echte Cover dort (gelandet), die Spiegelung kommt zuletzt. Ist die Startseite bereit (oder
## beendet eine Eingabe den Aufbau), geht die Ebene, und der Fokus kommt auf die Startseite.
## Neu eingerichtet aus den Einstellungen: erst unter der Bühne auf die Startseite wechseln, damit
## auch dann der Übergang ins Hauptmenü kommt (früher landete man wieder in den Einstellungen).
## Geht das nicht (keine Startseite), wie früher: Die Cover landen, Raum und Licht gehen in T_RAUM.
func _ausklang() -> void:
	if is_instance_valid(main) and str(main.current) != "games":
		main.goto("games", "", false)
		await get_tree().process_frame
	# Die Handschrift der Marke zum Schluss: An „Los“ zündet der Kern, ein Lichtring läuft über den
	# Schirm, hinter ihm baut sich die Startseite auf.
	var los := Nav.focused()
	if is_instance_valid(_buehne):
		var at := get_viewport_rect().size * 0.5
		if los and is_ancestor_of(los):
			at = los.get_global_rect().get_center()
		_buehne.welle(_buehne.get_global_transform().affine_inverse() * at)
	var ziele: Dictionary = _buehne.fliegbar(_cover_ziele()) if is_instance_valid(_buehne) else {}
	var sec: Variant = (main.sections as Dictionary).get("games") if is_instance_valid(main) and main.sections is Dictionary else null
	var aufbau: Node = null
	if sec is Node and is_instance_valid(sec) and (sec as Node).has_method("aufbauen"):
		aufbau = (sec as Node).call("aufbauen", true, ziele.keys())
	if is_instance_valid(_page):
		U.weg(_page, "uz_aus").tween_property(_page, "modulate:a", 0.0, U.T_WEG)
	U.weg(_dots, "uz_punkte_a").tween_property(_dots, "modulate:a", 0.0, U.T_WEG)
	if aufbau == null:
		var n: int = _buehne.aufloesen(ziele)
		_raum_aus(U.T_RAUM)
		await get_tree().create_timer(U.T_RAUM + (U.T_ORT if n > 0 and not U.reduziert() else 0.0)).timeout
		return
	# Kurz (reduziert, leicht): nichts fliegt, die Cover der Bühne gehen, die echten blenden auf.
	var flug := not bool(aufbau.get("kurz"))
	var abflug := {}
	if flug:
		for id in ziele:
			abflug[id] = float(aufbau.call("flug_ab", str(id)))
	_buehne.connect("gelandet", func(id: String) -> void:
		if is_instance_valid(aufbau):
			aufbau.call("gelandet", id))
	_buehne.aufloesen(ziele if flug else {}, abflug)
	_raum_aus(U.T_LICHT if flug else U.T_RAUM)
	if bool(aufbau.call("laeuft")):
		await aufbau.bereit
	# Was noch flog (eine Eingabe beendet den Aufbau), steht jetzt auf der Startseite.
	if is_instance_valid(_buehne):
		_buehne.visible = false


## Raum (Abdunklung) und Lichtschein der Einrichtung gehen in dauer („Gehen“).
func _raum_aus(dauer: float) -> void:
	var tw := U.weg(self, "uz_raum").set_parallel(true)
	if is_instance_valid(_scrim):
		tw.tween_property(_scrim, "color", Color(_scrim.color, 0.0), dauer).set_delay(U.T_ANTWORT)
	if is_instance_valid(_licht):
		tw.tween_property(_licht, "modulate:a", 0.0, dauer)


## Wo die Cover der Startseite gerade stehen: Spiel-ID → Rechteck auf dem Schirm (nur ganz sichtbare).
func _cover_ziele() -> Dictionary:
	var out := {}
	var view := get_viewport_rect()
	for c in _startseite_cover():
		var r: Rect2 = c[0]
		if view.encloses(r) and r.size.x > 8.0:
			out[str(c[1])] = r
	return out


## Die Cover der Startseite (Karten mit Meta uz_flug „g:<id>“ und flug_bild): [[Rechteck, ID]],
## von oben nach unten und links nach rechts.
func _startseite_cover() -> Array:
	var out: Array = []
	if not is_instance_valid(main):
		return out
	var shell: Variant = main.shell
	var stack: Array = [shell if shell is Node else main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == self or not is_instance_valid(n):
			continue
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		if n is Control and str(n.get_meta("uz_flug", "")).begins_with("g:") and n.has_method("flug_bild"):
			var fb: Dictionary = n.call("flug_bild")
			var node: Variant = fb.get("node")
			var c: Control = node if node is Control else n as Control
			out.append([c.get_global_rect(), str(n.get_meta("uz_flug")).substr(2)])
			continue
		for ch in n.get_children():
			stack.append(ch)
	# Lesereihenfolge: erst nach oben/links eindeutig ordnen, dann Zeilen bilden (bis 4 px unter dem ersten der
	# Zeile) und je Zeile nach links. Der frühere Vergleich mit Spielraum war paarweise nicht widerspruchsfrei.
	out.sort_custom(func(x: Array, y: Array) -> bool:
		var px := (x[0] as Rect2).position
		var py := (y[0] as Rect2).position
		return px.y < py.y or (px.y == py.y and px.x < py.x))
	var geordnet: Array = []
	var zeile: Array = []
	for e in out:
		if not zeile.is_empty() and (e[0] as Rect2).position.y - (zeile[0][0] as Rect2).position.y > 4.0:
			zeile.sort_custom(func(x: Array, y: Array) -> bool: return (x[0] as Rect2).position.x < (y[0] as Rect2).position.x)
			geordnet.append_array(zeile)
			zeile = []
		zeile.append(e)
	zeile.sort_custom(func(x: Array, y: Array) -> bool: return (x[0] as Rect2).position.x < (y[0] as Rect2).position.x)
	geordnet.append_array(zeile)
	return geordnet


func _summary_state() -> Dictionary:
	var c := _game_counts()
	var acc: Array = []
	for a in _accounts():
		if bool((a.status as Callable).call()[2]) and not probe_no_accounts:
			acc.append(str(a.title))
	var ex: Array = []
	var feats: Array = features().extras
	var auto := str(Config.get_value("lossless.auto", "aus"))
	if feats.has("lossless") and auto != "aus" and str(Lossless.exe_path()) != "":
		ex.append("Bildrate ×2")
	if feats.has("background_wake") and bool(Config.get_value("system.background_wake", true)):
		ex.append("Guide weckt Uzai")
	if feats.has("autostart") and bool(Config.get_value("system.autostart", false)):
		ex.append("Start mit Windows")
	if feats.has("steam_guide") and bool(Config.get_value("controller.steam_guide_aus", false)):
		ex.append("Guide nur für Uzai")
	if feats.has("ruhemodus") and str(Config.get_value("controller.guide_hold", "menu")) != "aus":
		ex.append("Schnellmenü" if str(Config.get_value("controller.guide_hold", "menu")) == "menu" else "Ruhemodus")
	if feats.has("clips") and Config.DEFAULTS.has("capture"):
		ex.append("Clips über " + str({ "uzai": "Uzai", "gamebar": "Game Bar", "nvidia": "NVIDIA" }.get(str(Config.get_value("capture.via", "uzai")), "Uzai")))
	elif feats.has("clips"):
		var ck := str(Config.get_value("system.clip_keys", "WIN+ALT+G"))
		for o in CLIP_KEYS:
			if o[0] == ck:
				ex.append("Clips über " + str(o[1]))
	var det := _detected if _detected != "" else str(Config.get_value("einrichtung.pad", ""))
	var pad := det if det != "Tastatur" else ""
	if pad == "" and Nav.device == "pad" and Nav.pad_name != "":
		pad = Nav.pad_name
	return {
		"pad": pad,
		"preset": str(UzTheme.PRESETS.get(str(Config.get_value("theme.preset", "theme")), {}).get("name", "")),
		"accent_own": str(Config.get_value("theme.accent", "")) != "",
		"games": _summary_games(c),
		"accounts": acc,
		"extras": ex,
		"has_extras": not feats.is_empty(),
		"skipped": Config.get_value("einrichtung.skipped", []),
	}
