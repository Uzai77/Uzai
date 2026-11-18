extends "res://src/ui/layers/modal.gd"
## Spiele scrapen: Cover, Hintergründe und Schriftzüge für alle Spiele holen (Emulator- und
## PC-Spiele; die Wahl der Quelle gilt für alle, ohne eigene Wahl bleibt bei PC-Spielen SteamGridDB
## vorn: Media.scrape_quellen_fuer) – aus der
## Einrichtung (nach den Spielen), aus „Für dich“ (Start auf der Startseite) und unter Einstellungen
## › Spiele › Bilder. Oben die Wahl der Quelle (ScreenScraper ohne Schlüssel, SteamGridDB mit, oder
## beide in wählbarer Reihenfolge; gemerkt unter library.scrape_quellen), darunter die Systeme zum
## An- und Abwählen, dann „Fehlende holen“ oder „Alles ersetzen“. Während es läuft: der
## Fortschritt und die neuen Cover, wie sie ankommen. Schließen hält nichts an – es läuft weiter,
## am Ende kommt eine Mitteilung (starten ist statisch und hängt nicht an dieser Ebene).

const Screenscraper := preload("res://src/core/screenscraper.gd")
const SetupKonten := preload("res://src/ui/layers/setup_wizard_konten.gd")
const GameProfile := preload("res://src/core/game_profile.gd")

const COVER := Vector2(84, 112)
const VORSCHAU_MAX := 7          ## so viele neue Cover stehen höchstens in der Reihe

const Main := preload("res://src/main.gd")
var main: Main
var _aus := {}                   ## abgewählte Systeme (ID → true)
var _iidb := ""                  ## iiDB beim Scrapen: "" aus, "zuerst" oder "danach"
var _bar: Control
var _zeile: Label
var _reihe: HBoxContainer


## Läuft im Hintergrund weiter, auch wenn die Ebene zu ist; am Ende eine Mitteilung – je Quelle, was
## kam oder warum nichts (Media.scrape_meldung), bei Problemen mit dem Weg zum Protokoll.
static func starten(m: Main, ersetzen: bool, systeme: Array) -> void:
	var quellen: Array = Media.scrape_wahl()
	if quellen.is_empty() or Media.sgdb_running:
		return
	var res: Dictionary = await Media.scrape_all(quellen, ersetzen, systeme)
	var msg: Array = Media.scrape_meldung(res)
	var zeile := str(msg[1])
	if Media.scrape_problem(res):
		zeile += TranslationServer.translate(" · Details: logs/scrape.log")
	Toasts.show_toast(str(msg[0]), zeile, "image", { "sound": "notify", "ms": 8000 })
	if m and is_instance_valid(m) and m.sections is Dictionary and (m.sections as Dictionary).has("games"):
		m.sections["games"].build()


## Text unter der Wahl der Quelle (kurz; die Quellenangabe von ScreenScraper bleibt sichtbar).
## pc_vorgabe: Vorgabe ohne eigene Wahl, und es gibt PC-Spiele (bei ihnen SteamGridDB zuerst).
static func wahl_text(wahl: Array, sg_schluessel: bool, pc_vorgabe := false) -> String:
	var T := func(t: String) -> String: return TranslationServer.translate(t)
	# iiDB dazu: vorn oder hinten an den Text der anderen Quellen (mit Quellenangabe).
	var ohne: Array = wahl.filter(func(q: Variant) -> bool: return str(q) != "iidb")
	if ohne.size() != wahl.size():
		if ohne.is_empty():
			return T.call("Cover, Hintergründe, Schriftzüge und Symbole. Daten: iiDB (iisu.network)")
		var rest := wahl_text(ohne, sg_schluessel, pc_vorgabe)
		return (T.call("Erst iiDB (iisu.network). ") + rest) if str(wahl[0]) == "iidb" else (rest + T.call(" · Danach iiDB (iisu.network)."))
	if pc_vorgabe and wahl == ["ss", "sgdb"]:
		return T.call("Retro erst ScreenScraper, PC erst SteamGridDB. Daten: ScreenScraper.fr") + ("" if sg_schluessel else T.call(" · SteamGridDB braucht einen Schlüssel."))
	if wahl == ["sgdb"]:
		return T.call("Bilder der Community, auch Symbole.") if sg_schluessel else T.call("Braucht einen kostenlosen Schlüssel.")
	if wahl == ["ss"]:
		return T.call("Scans der Hüllen, Schriftzüge, Rücken. Daten: ScreenScraper.fr")
	var erst := "ScreenScraper" if str(wahl[0]) == "ss" else "SteamGridDB"
	var dann := "SteamGridDB" if str(wahl[0]) == "ss" else "ScreenScraper"
	return (T.call("Erst %s, dann %s. Daten: ScreenScraper.fr") % [erst, dann]) + ("" if sg_schluessel else T.call(" · SteamGridDB braucht einen Schlüssel."))


## Systeme der Spiele mit Anzahl, die meisten zuerst: [[ID, Name, Anzahl]]. PC-Spiele nach ihrer
## Quelle (Steam, Epic …).
static func systeme() -> Array:
	var n := {}
	for g in Media.scrape_spiele():
		var s := str(g.get("system", ""))
		if s != "":
			n[s] = int(n.get(s, 0)) + 1
	var out: Array = []
	for s in n.keys():
		var name := str(Config.system(s).get("name", GameProfile.SOURCE_NAMES.get(s, ""))) if s != "" else ""
		out.append([s, name if name != "" else s.to_upper(), int(n[s])])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]) or (int(a[2]) == int(b[2]) and str(a[1]) < str(b[1])))
	return out


func build() -> void:
	width = 1080.0
	set_meta("uz_hint_b", "Schließen")
	super()
	Media.sgdb_progress.connect(_on_progress)
	Media.scrape_bild.connect(_on_bild)


func _exit_tree() -> void:
	if Media.sgdb_progress.is_connected(_on_progress):
		Media.sgdb_progress.disconnect(_on_progress)
	if Media.scrape_bild.is_connected(_on_bild):
		Media.scrape_bild.disconnect(_on_bild)


## Neu aufbauen; der Fokus bleibt beim Knopf mit diesem Schlüssel (Quelle, System), sonst Standard.
func _neu(behalten := "") -> void:
	if not is_instance_valid(box):
		return
	U.clear(box)
	fill()
	await get_tree().process_frame
	if not is_instance_valid(box):
		return
	if behalten != "":
		for n in box.find_children("*", "Control", true, false):
			if str(n.get_meta("uz_key", "")) == behalten and (n as Control).visible:
				Nav.focus(n, true)
				return
	var d := Nav.default_in(box)
	if d:
		Nav.focus(d, true)


func fill() -> void:
	if Media.sgdb_running:
		_fill_laeuft()
	else:
		_fill_start()


func _fill_start() -> void:
	var alle := Media.scrape_spiele().size()
	var fehlt := Media.scrape_fehlt()
	box.add_child(U.label("Spiele scrapen", "xl", "text", "black"))
	box.add_child(_text(tr("%s · %d ohne Cover") % [U.plural(alle, "Spiel", "Spiele"), fehlt] if alle > 0 else "Noch keine Spiele."))
	if alle == 0:
		box.add_child(_knopf("Schließen", "close", "primary", close, true))
		return
	# Quelle: ScreenScraper, SteamGridDB oder beide (A auf „Beide“ tauscht die Reihenfolge).
	var ss_da := Screenscraper.zugang().has("devid")
	var sg := str(Config.get_value("accounts.sgdb_key", "")) != ""
	# iiDB steht vor oder hinter den anderen Quellen (oder ist aus); wahl meint ab hier nur die anderen.
	var roh: Array = Media.scrape_wahl_roh()
	var ii: bool = Media.iidb.verbunden()
	_iidb = ("zuerst" if roh[0] == "iidb" else "danach") if ii and roh.has("iidb") else ""
	var wahl: Array = roh.filter(func(q: Variant) -> bool: return str(q) != "iidb")
	if not ss_da and (wahl.has("ss") or (wahl.is_empty() and _iidb == "")):
		wahl = ["sgdb"]
	var qrow := U.hbox(10)
	qrow.set_meta("uz_group", "scrapen:quelle")
	box.add_child(qrow)
	if ss_da:
		qrow.add_child(_wahl_knopf("ScreenScraper", "ss", wahl == ["ss"], "Wählen", func() -> void: _waehlen(["ss"])))
	if sg:
		qrow.add_child(_wahl_knopf("SteamGridDB", "sgdb", wahl == ["sgdb"], "Wählen", func() -> void: _waehlen(["sgdb"])))
	else:
		var k := _wahl_knopf("SteamGridDB", "sgdb", wahl == ["sgdb"], "Schlüssel hinterlegen", func() -> void:
			close()
			SetupKonten.open_sgdb(main)
		)
		k.icon = Icons.tex("link", 26)
		qrow.add_child(k)
	if ss_da:
		var beide := wahl.size() == 2
		qrow.add_child(_wahl_knopf("Beide", "beide", beide, "Reihenfolge tauschen" if beide else "Wählen", func() -> void:
			_waehlen([wahl[1], wahl[0]] if beide else ["ss", "sgdb"])
		))
	# iiDB: A schaltet weiter – danach, zuerst, aus. Ohne Schlüssel führt der Knopf zur Anmeldung.
	if ii:
		var name := "iiDB" if _iidb == "" else ("iiDB zuerst" if _iidb == "zuerst" else "iiDB danach")
		qrow.add_child(_wahl_knopf(name, "iidb", _iidb != "", "Umschalten", func() -> void:
			_iidb = { "": "danach", "danach": "zuerst", "zuerst": "" }[_iidb]
			_waehlen(wahl if not (wahl.is_empty() and _iidb == "") else (["ss", "sgdb"] if ss_da else ["sgdb"]), "iidb")
		))
	else:
		var ik := _wahl_knopf("iiDB", "iidb", false, "Verbinden", func() -> void:
			close()
			SetupKonten.open_iidb(main)
		)
		ik.icon = Icons.tex("link", 26)
		qrow.add_child(ik)
	var pc_da := Media.scrape_spiele().any(func(g: Dictionary) -> bool: return Screenscraper.ist_pc(g))
	box.add_child(_text(wahl_text(_mit_iidb(wahl), sg, ss_da and pc_da and not Media.scrape_wahl_gesetzt()), "s"))
	# Systeme: A schaltet um, alle sind zuerst an.
	var sys := systeme()
	if sys.size() > 1:
		box.add_child(U.spacer(0, 4, false))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		flow.set_meta("uz_group", "scrapen:systeme")
		box.add_child(flow)
		for e in sys:
			var sid := str(e[0])
			var b := U.button("%s  %d" % [str(e[1]), int(e[2])], "check" if not _aus.has(sid) else "", "normal")
			b.set_meta("uz_key", "scrapen:sys:" + sid)
			b.set_meta("uz_hint_a", "Abwählen" if not _aus.has(sid) else "Auswählen")
			b.modulate.a = 1.0 if not _aus.has(sid) else 0.55
			b.pressed.connect(func() -> void:
				if _aus.has(sid):
					_aus.erase(sid)
				else:
					_aus[sid] = true
				_neu("scrapen:sys:" + sid)
			)
			flow.add_child(b)
	box.add_child(U.spacer(0, 6, false))
	var row := U.hbox(14)
	box.add_child(row)
	if Media.scrape_wahl().is_empty():
		# Die Wahl geht so nicht: SteamGridDB ohne Schlüssel (der Weg dorthin) bzw. ScreenScraper
		# in den Einstellungen ausgeschaltet (gleich hier wieder an).
		if (wahl.has("ss") or wahl.is_empty()) and ss_da:
			row.add_child(_knopf("ScreenScraper einschalten", "check", "primary", func() -> void:
				Config.set_value("library.screenscraper", true)
				_neu()
			, true))
		else:
			row.add_child(_knopf("Schlüssel hinterlegen", "link", "primary", func() -> void:
				close()
				SetupKonten.open_sgdb(main)
			, true))
		row.add_child(_knopf("Später", "close", "normal", close))
		return
	var welche: Array = sys.map(func(e: Array) -> String: return str(e[0])).filter(func(s: String) -> bool: return not _aus.has(s))
	var los := func(ersetzen: bool) -> void:
		if welche.is_empty():
			return
		starten(main, ersetzen, welche if not _aus.is_empty() else [])
		_neu()
	row.add_child(_knopf("Fehlende holen", "download", "primary", los.bind(false), true))
	row.add_child(_knopf("Alles ersetzen", "refresh", "normal", los.bind(true)))


## Wahl der Quelle merken (w: ScreenScraper und SteamGridDB; iiDB kommt nach seinem Schalter davor
## oder dahinter). ScreenScraper zu wählen schaltet es auch ein (Einstellungen › Bilder). Mit iiDB
## an hebt ein zweites A auf die gewählte einzelne Quelle sie auf: dann holt nur iiDB.
func _waehlen(w: Array, fokus := "") -> void:
	var alt: Array = Media.scrape_wahl_roh().filter(func(q: Variant) -> bool: return str(q) != "iidb")
	var key := "ss" if w == ["ss"] else ("sgdb" if w == ["sgdb"] else "beide")
	if fokus == "" and _iidb != "" and w.size() == 1 and w == alt:
		w = []
	Config.set_value("library.scrape_quellen", _mit_iidb(w))
	Config.set_value("library.scrape_quellen_eigen", true)
	if w.has("ss"):
		Config.set_value("library.screenscraper", true)
	_neu("scrapen:quelle:" + (fokus if fokus != "" else key))


## Die Wahl aus ScreenScraper und SteamGridDB mit iiDB davor oder dahinter (je nach Schalter).
func _mit_iidb(w: Array) -> Array:
	if _iidb == "zuerst":
		return ["iidb"] + w
	return (w + ["iidb"]) if _iidb == "danach" else w


## Ein Knopf der Quellenwahl: gewählt mit Haken, sonst leiser (wie die Systeme darunter).
func _wahl_knopf(text: String, key: String, an: bool, hinweis: String, cb: Callable) -> Button:
	var b := U.button(text, "check" if an else "", "normal")
	b.set_meta("uz_key", "scrapen:quelle:" + key)
	b.set_meta("uz_hint_a", hinweis)
	b.modulate.a = 1.0 if an else 0.6
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	return b


func _fill_laeuft() -> void:
	box.add_child(U.label("Bilder werden geholt", "xl", "text", "black"))
	# Die Zeile trägt gleich den Namen des Spiels („3 / 40 · Titel“): von Hand übersetzt, nie von selbst – der Katalog
	# übersetzt Zeilen mit „ · “ Stück für Stück und träfe dabei den Titel.
	_zeile = _text(tr("Startet …"))
	_zeile.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(_zeile)
	_bar = ProgressBarUz.new().setup(0.0, "accent", 6.0, 0.0)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_bar)
	_reihe = U.hbox(12)
	_reihe.custom_minimum_size = Vector2(0, COVER.y)
	_reihe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_reihe)
	var row := U.hbox(14)
	box.add_child(row)
	row.add_child(_knopf("Im Hintergrund", "check", "primary", close, true))
	row.add_child(_knopf("Anhalten", "pause", "normal", func() -> void:
		Media.stop_sgdb()
		if is_instance_valid(_zeile):
			_zeile.text = tr("Wird angehalten …")
	))


func _on_progress(done: int, total: int, title: String) -> void:
	if not is_inside_tree():
		return
	if done >= total:
		# Fertig: zurück zum Anfang (mit den neuen Zahlen); die Mitteilung kommt von starten().
		_neu.call_deferred()
		return
	if not is_instance_valid(_bar):
		_neu()
		return
	_bar.call("set_value", float(done) / maxf(float(total), 1.0))
	_zeile.text = "%d / %d · %s" % [done, total, title]


## Ein neues Cover kam an: vorn in die Reihe, weich herein; ältere rutschen hinten raus.
func _on_bild(_gid: String, kind: String, path: String) -> void:
	if kind != "cover" or not is_instance_valid(_reihe):
		return
	var tr_ := TextureRect.new()
	tr_.custom_minimum_size = COVER
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_.modulate.a = 0.0
	_reihe.add_child(tr_)
	_reihe.move_child(tr_, 0)
	while _reihe.get_child_count() > VORSCHAU_MAX:
		var alt := _reihe.get_child(_reihe.get_child_count() - 1)
		_reihe.remove_child(alt)
		alt.queue_free()
	Media.file_texture(path, int(COVER.x * 2), func(t: Texture2D) -> void:
		if is_instance_valid(tr_) and t:
			tr_.texture = t
			U.ankommen(tr_, U.T_ORT, "uz_in").tween_property(tr_, "modulate:a", 1.0, U.T_ORT)
	)


func _knopf(text: String, icon: String, kind: String, cb: Callable, standard := false) -> Button:
	var b := U.button(text, icon, kind)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	if standard:
		b.set_meta("uz_default", true)
	return b


func _text(text: String, size := "m", color := "muted") -> Label:
	var t := U.label(text, size, color, "regular", true)
	t.custom_minimum_size = Vector2(900, 0)
	return t
