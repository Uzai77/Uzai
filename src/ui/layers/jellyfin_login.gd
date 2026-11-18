extends "res://src/ui/layers/yt_login.gd"
## Jellyfin oder Emby verbinden (kind). Erst der Server: Adresse eingeben (Bildschirmtastatur oder
## vom Handy) oder auf Wunsch im Heimnetz suchen. Dann anmelden – bei Jellyfin am liebsten mit
## Quick Connect (Uzai zeigt einen Code, du bestätigst ihn in Jellyfin auf Handy oder PC), sonst
## mit Name und Passwort. Das Passwort geht nur einmal an den Server und wird nie gespeichert.
## Unverschlüsselte Server (http) nur im Heimnetz und erst nach einem klaren Hinweis.

var kind := "jellyfin"
var _found: Array = []
var _server: Dictionary = {}


func _start() -> void:
	_state = "start"
	_refill()


func _name() -> String:
	return "Emby" if kind == "emby" else "Jellyfin"


func fill() -> void:
	match _state:
		"start": _fill_start()
		"found": _fill_found()
		"http": _fill_http()
		"code": _fill_code()
		"passwort": _fill_passwort()
		"done": _fill_done()
		_: _fill_wait()


func _fill_start() -> void:
	box.add_child(_badge("drive", "accent"))
	box.add_child(U.label("%s verbinden" % _name(), "xl", "text", "black"))
	# Ohne „% _name()“: Der Satz hat keinen Platzhalter mehr – jedes Öffnen schrieb sonst einen Formatfehler ins Protokoll.
	var t := U.label("Server im Heimnetz suchen oder Adresse eingeben.", "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var row := U.hbox(14)
	box.add_child(row)
	var find := U.button("Im Heimnetz suchen", "search", "primary")
	find.set_meta("uz_default", true)
	find.set_meta("uz_hint_a", "Suchen")
	find.pressed.connect(_discover)
	row.add_child(find)
	var typed := U.button("Adresse eingeben", "keyboard")
	typed.pressed.connect(_ask_address)
	row.add_child(typed)
	var close_b := U.button("Schließen", "close")
	close_b.pressed.connect(close)
	row.add_child(close_b)


func _fill_found() -> void:
	box.add_child(U.label("Gefunden im Heimnetz" if not _found.is_empty() else "Kein Server gefunden", "xl", "text", "black"))
	var t := U.label("Wähle deinen Server." if not _found.is_empty()
			else "Kein %s-Server im Heimnetz gefunden." % _name(), "m", "muted",
			"regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var list := U.vbox(10)
	list.set_meta("uz_group", "jf-server")
	box.add_child(list)
	for i in _found.size():
		var s: Dictionary = _found[i]
		var it = ListItem.new()
		it.setup(str(s.name), str(s.address), "")
		it.icon_name = "drive"
		it.set_meta("uz_key", "jf-server:" + str(s.id))
		it.set_meta("uz_hint_a", "Verbinden")
		if i == 0:
			it.set_meta("uz_default", true)
		it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var addr := str(s.address)
		it.activated.connect(func() -> void: _check(addr))
		list.add_child(it)
	var row := U.hbox(14)
	box.add_child(row)
	var typed := U.button("Adresse eingeben", "keyboard", "flat" if not _found.is_empty() else "primary")
	if _found.is_empty():
		typed.set_meta("uz_default", true)
	typed.pressed.connect(_ask_address)
	row.add_child(typed)
	var again := U.button("Nochmal suchen", "refresh")
	again.pressed.connect(_discover)
	row.add_child(again)


func _fill_http() -> void:
	box.add_child(_badge("warning", "warn"))
	box.add_child(U.label("Unverschlüsselte Verbindung", "xl", "text", "black"))
	var t := U.label("„%s“ ist nur per http erreichbar. Nur im eigenen Heimnetz verbinden." % str(_server.get("name", "")), "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var row := U.hbox(14)
	box.add_child(row)
	var ok := U.button("Unverschlüsselt verbinden", "link")
	ok.pressed.connect(_login)
	row.add_child(ok)
	var no := U.button("Abbrechen", "close", "primary")
	no.set_meta("uz_default", true)
	no.pressed.connect(close)
	row.add_child(no)


func _fill_code() -> void:
	var col := U.vbox(16)
	box.add_child(col)
	col.add_child(U.label("Mit Quick Connect anmelden", "xl", "text", "black"))
	col.add_child(_step("1", "In Jellyfin: Einstellungen → Quick Connect", width - 160))
	col.add_child(_step("2", "Code eingeben:", width - 160))
	col.add_child(_code_box(str(_info.code)))
	var wait := U.hbox(14)
	_left_bar = ProgressBarUz.new().setup(1.0, "accent", 4, 200)
	_left_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wait.add_child(_left_bar)
	_countdown = U.label("", "s", "muted", "medium")
	wait.add_child(_countdown)
	col.add_child(wait)
	var row := U.hbox(14)
	col.add_child(row)
	var b := U.button("Abbrechen", "close")
	b.set_meta("uz_default", true)
	b.pressed.connect(close)
	row.add_child(b)
	var pw := U.button("Mit Name und Passwort", "keyboard")
	pw.pressed.connect(_ask_password)
	row.add_child(pw)


## Hinter der Tastatur für Name und Passwort: Wer sie schließt, kann sie wieder öffnen (früher stand hier eine
## Seite ohne Knöpfe, nur B schloss sie).
func _fill_passwort() -> void:
	box.add_child(_badge("drive", "accent"))
	box.add_child(U.label("%s verbinden" % _name(), "xl", "text", "black"))
	var t := U.label("Name und Passwort für „%s“ eingeben." % str(_server.get("name", "")), "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var row := U.hbox(14)
	box.add_child(row)
	var pw := U.button("Anmelden", "keyboard", "primary")
	pw.set_meta("uz_default", true)
	pw.pressed.connect(_ask_password)
	row.add_child(pw)
	var other := U.button("Andere Adresse", "keyboard")
	other.pressed.connect(_ask_address)
	row.add_child(other)
	var close_b := U.button("Schließen", "close")
	close_b.pressed.connect(close)
	row.add_child(close_b)


func _fill_done() -> void:
	box.add_child(_badge("check", "ok"))
	box.add_child(U.label("Verbunden mit „%s“" % str(_server.get("name", _name())), "xl", "text", "black"))
	var t := U.label("Bibliotheken stehen unter Filme.", "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var b := U.button("Fertig", "check", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(func() -> void:
		close()
		if main and Nav.top_layer() == null:
			main.goto("movies", "start")
	)
	box.add_child(b)


func _fill_wait() -> void:
	var err := _state == "error"
	box.add_child(_badge("warning" if err else "drive", "warn" if err else "accent"))
	box.add_child(U.label("Verbinden hat nicht geklappt" if err else "%s verbinden" % _name(), "xl", "text", "black"))
	var t := U.label(_msg, "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	if not err:
		return
	var row := U.hbox(14)
	box.add_child(row)
	var again := U.button("Andere Adresse", "keyboard", "primary")
	again.set_meta("uz_default", true)
	again.pressed.connect(_ask_address)
	row.add_child(again)
	if not _server.is_empty():
		var pw := U.button("Mit Name und Passwort", "keyboard")
		pw.pressed.connect(_ask_password)
		row.add_child(pw)
	var close_b := U.button("Schließen", "close")
	close_b.pressed.connect(close)
	row.add_child(close_b)


# --- Ablauf --------------------------------------------------------------------------------------

func _wait(text: String) -> void:
	_state = "wait"
	_msg = text
	_refill()


func _discover() -> void:
	_wait("Suche %s-Server …" % _name())
	_found = await Quellen.discover(kind)
	if not is_inside_tree():
		return
	_state = "found"
	_refill()


func _ask_address() -> void:
	main.open_keyboard("Adresse deines %s-Servers" % _name(), str(Quellen.server_info(kind).get("base", "")), func(t: String) -> void:
		if t.strip_edges() != "":
			_check(t)
	)


func _check(address: String) -> void:
	_wait("Uzai prüft den Server …")
	var r: Dictionary = await Quellen.server_check(kind, address)
	if not is_inside_tree():
		return
	if not bool(r.ok):
		_server = {}
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_server = r
	if bool(r.http):
		_state = "http"
		_refill()
		return
	_login()


func _login() -> void:
	_wait("Anmelden bei „%s“ …" % str(_server.get("name", "")))
	if await Quellen.quick_available(kind, _server):
		var q: Dictionary = await Quellen.quick_start(kind, _server)
		if not is_inside_tree():
			return
		if bool(q.ok):
			_info = { "code": str(q.code), "secret": str(q.secret), "expires": 600 }
			_until = Time.get_unix_time_from_system() + 600.0
			_state = "code"
			_refill()
			_poll_loop()
			return
	if is_inside_tree():
		_ask_password()


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
		var st: String = await Quellen.quick_poll(kind, _server, str(_info.secret))
		if not is_inside_tree() or _state != "code":
			break
		if st == "ok":
			Sfx.play("notify")
			_state = "done"
			_refill()
		elif st == "error":
			_state = "error"
			_msg = "Quick Connect abgelehnt oder abgelaufen."
			_refill()
	_poll_running = false


## Name und Passwort über die Bildschirmtastatur (oder vom Handy); das Passwort bleibt nur in
## dieser Funktion und geht einmal an den Server. Vom Quick-Connect-Code aus gilt der Code weiter, bis das
## Passwort abgeschickt ist (wie bei Nuvio); sonst steht hinter der Tastatur „passwort“ mit Knopf zum Wiederöffnen.
func _ask_password() -> void:
	if _state != "code":
		_state = "passwort"
		_refill()
	main.open_keyboard("Benutzername bei %s" % _name(), str(Quellen.server_user(kind)), func(user: String) -> void:
		if user.strip_edges() == "":
			return
		main.open_keyboard("Passwort", "", func(pw: String) -> void:
			_wait("Anmelden …")
			var err: String = await Quellen.login_password(kind, _server, user, pw)
			if not is_inside_tree():
				return
			if err != "":
				_state = "error"
				_msg = err
			else:
				Sfx.play("notify")
				_state = "done"
			_refill()
		, true)
	)
