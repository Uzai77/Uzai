extends "res://src/ui/layers/yt_login.gd"
## Nuvio-Anmeldung wie in der Nuvio-TV-App: QR-Code mit dem Handy scannen (nuvio.tv/link), dort
## anmelden und bestätigen – fertig. Alternativ E-Mail und Passwort über die Bildschirmtastatur.
## Danach holt Uzai Profile, Addons, Plugins, Bibliothek, Weiterschauen und das Layout.

var _nonce := ""


func _start() -> void:
	_begin()


func fill() -> void:
	match _state:
		"code": _fill_code()
		"done": _fill_done()
		"sync": _fill_sync()
		_: _fill_wait()


func _fill_wait() -> void:
	var err := _state == "error"
	box.add_child(_badge("warning" if err else "qr", "warn" if err else "accent"))
	box.add_child(U.label("Anmeldung hat nicht geklappt" if err else "Mit Nuvio anmelden", "xl", "text", "black"))
	var t := U.label(_msg if _msg != "" else "Code wird bei Nuvio angefordert …", "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var row := U.hbox(14)
	box.add_child(row)
	if err:
		var again := U.button("Nochmal versuchen", "refresh", "primary")
		again.set_meta("uz_default", true)
		again.pressed.connect(_begin)
		row.add_child(again)
	var mail := U.button("Mit E-Mail und Passwort", "keyboard")
	mail.pressed.connect(_ask_mail)
	row.add_child(mail)
	var close_b := U.button("Schließen", "close")
	close_b.pressed.connect(close)
	row.add_child(close_b)


func _fill_code() -> void:
	var row := U.hbox(56)
	box.add_child(row)
	row.add_child(_qr(str(_info.url), 380))
	var col := U.vbox(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(U.label("Mit Nuvio anmelden", "xl", "text", "black"))
	col.add_child(_step("1", "Code scannen oder nuvio.tv/link öffnen"))
	col.add_child(_step("2", "Anmelden und bestätigen. Code:"))
	col.add_child(_code_box(str(_info.user_code)))
	col.add_child(U.spacer(0, 2, false))
	var wait := U.hbox(14)
	_left_bar = ProgressBarUz.new().setup(1.0, "accent", 4, 200)
	_left_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wait.add_child(_left_bar)
	_countdown = U.label("", "s", "muted", "medium")
	wait.add_child(_countdown)
	col.add_child(wait)
	var brow := U.hbox(14)
	col.add_child(brow)
	var b := U.button("Abbrechen", "close")
	b.set_meta("uz_default", true)
	b.pressed.connect(close)
	brow.add_child(b)
	var mail := U.button("E-Mail und Passwort", "keyboard")
	mail.pressed.connect(_ask_mail)
	brow.add_child(mail)


func _fill_sync() -> void:
	box.add_child(_badge("refresh", "accent"))
	box.add_child(U.label("Daten werden geladen …", "xl", "text", "black"))
	var t := U.label("Addons, Bibliothek und Weiterschauen.",
			"l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)


func _fill_done() -> void:
	box.add_child(_badge("check" if NuvioSync.last_error == "" else "warning", "ok" if NuvioSync.last_error == "" else "warn"))
	var who := NuvioSync.email() if NuvioSync.email() != "" else "Nuvio-Konto"
	box.add_child(U.label("Angemeldet als %s" % who, "xl", "text", "black"))
	var text := ""
	if NuvioSync.last_error != "":
		text = "Abgleich fehlgeschlagen: %s" % NuvioSync.last_error
	else:
		var parts := PackedStringArray(
				[U.plural(Movies.addons.size(), "Addon", "Addons"), U.plural(Movies.plugin_repos.size(), "Plugin-Verzeichnis", "Plugin-Verzeichnisse"),
			U.plural(Movies.library_items().size(), "Titel in der Bibliothek", "Titel in der Bibliothek")])
		text = "Übernommen: %s." % ", ".join(parts)
		if NuvioSync.profiles().size() > 1:
			text += " Profil: %s." % NuvioSync.profile_name()
	var t := U.label(text, "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var b := U.button("Fertig", "check", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(func() -> void:
		close()
		if main:
			main.goto("movies", "start")
	)
	box.add_child(b)


func _begin() -> void:
	_state = "wait"
	_msg = ""
	_refill()
	var r := await NuvioSync.login_start()
	if not is_inside_tree():
		return
	if not r.ok:
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_info = r
	_nonce = str(r.nonce)
	_until = Time.get_unix_time_from_system() + float(r.expires)
	_state = "code"
	_refill()
	_poll_loop()


func _poll_loop() -> void:
	if _poll_running:
		return
	_poll_running = true
	var wait := float(_info.get("interval", 3))
	while is_inside_tree() and _state == "code":
		await get_tree().create_timer(wait).timeout
		if not is_inside_tree() or _state != "code":
			break
		if Time.get_unix_time_from_system() > _until:
			_state = "error"
			_msg = "Code abgelaufen."
			_refill()
			break
		var st := await NuvioSync.login_poll(str(_info.code), _nonce)
		if not is_inside_tree():
			break
		match st:
			"ok":
				await _finish()
			"denied":
				_state = "error"
				_msg = "Anmeldung abgebrochen."
				_refill()
			"expired":
				_state = "error"
				_msg = "Code abgelaufen."
				_refill()
			"error":
				_state = "error"
				_msg = NuvioSync.last_error
				_refill()
	_poll_running = false


func _finish() -> void:
	_state = "sync"
	Sfx.play("notify")
	_refill()
	if NuvioSync.busy:
		await NuvioSync.synced
	if not is_inside_tree():
		return
	_state = "done"
	_refill()


## E-Mail und Passwort statt QR-Code. Der Code gilt weiter, bis das Passwort abgeschickt ist: Wer die Tastatur nur
## schließt, kann wie vorher scannen (früher hielt ein eigener Zustand „mail“ die Abfrage gleich an – der QR-Code
## stand danach tot da, die Zeit lief nicht mehr).
func _ask_mail() -> void:
	main.open_keyboard("E-Mail deines Nuvio-Kontos", NuvioSync.email(), func(mail: String) -> void:
		if mail.strip_edges() == "":
			return
		main.open_keyboard("Passwort", "", func(pw: String) -> void:
			if pw == "":
				return
			_state = "wait"
			_msg = "Anmelden …"
			_refill()
			var err := await NuvioSync.login_password(mail, pw)
			if not is_inside_tree():
				return
			if err != "":
				_state = "error"
				_msg = err
				_refill()
				return
			await _finish()
		, true)
	)
