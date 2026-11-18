extends "res://src/ui/layers/yt_login.gd"
## Stremio-Konto verbinden – nur auf ausdrücklichen Wunsch und nach einem klaren Hinweis (R1, R3):
## Die Anbindung ist inoffiziell, Uzai bringt keine Addons mit und empfiehlt keine. Angemeldet wird
## mit einem Code auf link.stremio.com (QR-Code), nie mit Passwort in Uzai. Danach kann Uzai auf
## Wunsch die Addons übernehmen, die du selbst in Stremio installiert hast (page = "addons").

var page := ""                     ## "addons": gleich die eigenen Addons zeigen (schon verbunden)
var _addons: Array = []
var _pick := {}                    ## Adresse → übernehmen ja/nein
## Was „Nochmal versuchen“ wiederholt: „anmelden“ (Code von vorn) oder „addons“ – ging nur das Laden der Addons
## nicht (Netz, Server stumm), gilt die Anmeldung noch, dann wird nur neu geladen.
var _nochmal := "anmelden"


func _start() -> void:
	if page == "addons" and Quellen.connected("stremio"):
		_load_addons()
	else:
		_state = "notice"
		_refill()


func fill() -> void:
	match _state:
		"notice": _fill_notice()
		"code": _fill_code()
		"done": _fill_done()
		"addons": _fill_addons()
		_: _fill_wait()


func _fill_notice() -> void:
	box.add_child(_badge("bookmark", "accent"))
	box.add_child(U.label("Stremio-Konto verbinden", "xl", "text", "black"))
	var t := U.label("Bibliothek und Weiterschauen aus Stremio.", "l",
			"muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(
			_note("Quellen",
			"Keine Addons enthalten. Für deine Quellen bist du verantwortlich."))
	var row := U.hbox(14)
	box.add_child(row)
	var go := U.button("Weiter", "check", "primary")
	go.set_meta("uz_default", true)
	go.pressed.connect(_begin)
	row.add_child(go)
	var close_b := U.button("Abbrechen", "close")
	close_b.pressed.connect(close)
	row.add_child(close_b)


func _note(head: String, text: String) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel())
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", sb)
	var col := U.vbox(4)
	p.add_child(col)
	col.add_child(U.label(head, "s", "accent", "bold"))
	var l := U.label(text, "m", "text", "regular", true)
	l.custom_minimum_size = Vector2(width - 150, 0)
	col.add_child(l)
	return p


func _fill_code() -> void:
	var row := U.hbox(56)
	box.add_child(row)
	row.add_child(_qr(str(_info.url), 380))
	var col := U.vbox(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(U.label("Stremio-Konto verbinden", "xl", "text", "black"))
	col.add_child(_step("1", "Code scannen oder link.stremio.com öffnen"))
	col.add_child(_step("2", "Diesen Code eingeben:"))
	col.add_child(_code_box(str(_info.code)))
	var wait := U.hbox(14)
	_left_bar = ProgressBarUz.new().setup(1.0, "accent", 4, 200)
	_left_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wait.add_child(_left_bar)
	_countdown = U.label("", "s", "muted", "medium")
	wait.add_child(_countdown)
	col.add_child(wait)
	var b := U.button("Abbrechen", "close")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(close)
	col.add_child(b)


func _fill_done() -> void:
	box.add_child(_badge("check", "ok"))
	box.add_child(U.label("Stremio-Konto verbunden", "xl", "text", "black"))
	var t := U.label("Bibliothek und Weiterschauen stehen unter Filme. Zum Abspielen sind Addons nötig.", "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var row := U.hbox(14)
	box.add_child(row)
	var done := U.button("Fertig", "check", "primary")
	done.set_meta("uz_default", true)
	done.pressed.connect(close)
	row.add_child(done)
	var ad := U.button("Eigene Addons ansehen", "download")
	ad.pressed.connect(_load_addons)
	row.add_child(ad)


## Die eigenen Addons aus Stremio: jedes einzeln wählbar, nichts ist vorausgewählt.
func _fill_addons() -> void:
	box.add_child(U.label("Deine Addons aus Stremio", "xl", "text", "black"))
	var t := U.label("Aus deinem Stremio-Konto. Für deine Quellen bist du verantwortlich.", "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var list := U.vbox(6)
	list.set_meta("uz_group", "stremio-addons")
	box.add_child(list)
	var first := true
	for a in _addons:
		var url := str(a.url)
		var r = SettingRow.new()
		r.setup("toggle", str(a.name), "", bool(_pick.get(url, false)) or bool(a.have))
		r.subtitle = "Schon in Uzai" if bool(a.have) else url.get_base_dir().trim_prefix("https://").left(60)
		r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		r.set_meta("uz_key", "stremio-addon:" + url.md5_text())
		if bool(a.have):
			r.kind = "info"
			r.value_text = "Installiert"
		else:
			r.changed.connect(func(v: Variant) -> void: _pick[url] = bool(v))
			if first:
				r.set_meta("uz_default", true)
				first = false
		list.add_child(r)
	if _addons.is_empty():
		list.add_child(U.label("In deinem Stremio-Konto sind keine Addons mit https-Adresse installiert.", "m", "faint", "regular", true))
	var row := U.hbox(14)
	box.add_child(row)
	var take := U.button("Ausgewählte übernehmen", "download", "primary")
	if first:
		take.set_meta("uz_default", true)
	take.pressed.connect(_import)
	row.add_child(take)
	var close_b := U.button("Schließen", "close")
	close_b.pressed.connect(close)
	row.add_child(close_b)


func _fill_wait() -> void:
	var err := _state == "error"
	box.add_child(_badge("warning" if err else "bookmark", "warn" if err else "accent"))
	box.add_child(U.label("Das hat nicht geklappt" if err else "Stremio-Konto", "xl", "text", "black"))
	var t := U.label(_msg if _msg != "" else "Code wird bei Stremio angefordert …", "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	if err:
		var row := U.hbox(14)
		box.add_child(row)
		var again := U.button("Nochmal versuchen", "refresh", "primary")
		again.set_meta("uz_default", true)
		again.pressed.connect(_load_addons if _nochmal == "addons" else _begin)
		row.add_child(again)
		var close_b := U.button("Schließen", "close")
		close_b.pressed.connect(close)
		row.add_child(close_b)


func _begin() -> void:
	_nochmal = "anmelden"
	_state = "wait"
	_msg = ""
	_refill()
	var r: Dictionary = await Quellen.stremio_link_start()
	if not is_inside_tree():
		return
	if not bool(r.ok):
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_info = { "code": str(r.code), "url": str(r.url), "expires": 600 }
	_until = Time.get_unix_time_from_system() + 600.0
	_state = "code"
	_refill()
	_poll_loop()


func _poll_loop() -> void:
	if _poll_running:
		return
	_poll_running = true
	while is_inside_tree() and _state == "code":
		await get_tree().create_timer(3.0).timeout
		if not is_inside_tree() or _state != "code":
			break
		if Time.get_unix_time_from_system() > _until:
			_state = "error"
			_msg = "Code abgelaufen."
			_refill()
			break
		var st: String = await Quellen.stremio_link_poll(str(_info.code))
		if st == "ok" and is_inside_tree() and _state == "code":
			Sfx.play("notify")
			_state = "done"
			_refill()
	_poll_running = false


func _load_addons() -> void:
	_state = "wait"
	_msg = "Addons werden geladen …"
	_refill()
	var r: Dictionary = await Quellen.stremio_addons()
	if is_inside_tree():
		_addons_da(r)


## Antwort auf das Laden der Addons. Fehler: neu anmelden nur, wenn Stremio die Anmeldung nicht mehr annimmt.
func _addons_da(r: Dictionary) -> void:
	if not bool(r.ok):
		_nochmal = "anmelden" if bool(r.get("anmelden", false)) else "addons"
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_addons = r.addons
	_state = "addons"
	_refill()


func _import() -> void:
	var list := _addons.filter(func(a: Dictionary) -> bool: return not bool(a.have) and bool(_pick.get(str(a.url), false)))
	if list.is_empty():
		Toasts.show_toast("Nichts ausgewählt", "Addon mit A wählen.", "info", { "quiet": true })
		return
	_state = "wait"
	_msg = "Addons werden übernommen …"
	_refill()
	var res: Dictionary = await Quellen.stremio_import(list)
	if not is_inside_tree():
		return
	var failed: Array = res.failed
	Toasts.show_toast("%d übernommen" % int(res.added) if failed.is_empty() else "%d übernommen, %d nicht" % [int(res.added), failed.size()],
		", ".join(PackedStringArray(failed)) if not failed.is_empty() else "", "check" if failed.is_empty() else "warning")
	close()
