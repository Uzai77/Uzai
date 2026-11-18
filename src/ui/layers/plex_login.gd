extends "res://src/ui/layers/yt_login.gd"
## Plex verbinden wie an Fernsehern: QR-Code zu plex.tv/link (oder die Adresse abtippen), dort den
## Code eingeben – fertig, ohne Passwort in Uzai. Danach den Server wählen (eigene und geteilte);
## Uzai prüft jede Verbindung, bevor sie den Zugangsschlüssel bekommt. Ist ein Server nur
## unverschlüsselt im Heimnetz erreichbar, fragt Uzai vorher.

var servers_only := false          ## schon angemeldet: gleich den Server wählen („Anderen Server wählen“)
var _servers: Array = []
var _pick: Dictionary = {}
## Was „Nochmal versuchen“ wiederholt: „anmelden“ (Code von vorn, oder die Serverliste, wenn es eine gibt) oder
## „server“ – ging nur das Laden der Server nicht (Netz, plex.tv stumm), gilt die Anmeldung noch.
var _nochmal := "anmelden"


func _start() -> void:
	if servers_only and (Quellen.demo or str(Config.get_value("plex.token", "")) != ""):
		_load_servers()
	else:
		_begin()


func fill() -> void:
	match _state:
		"code": _fill_code()
		"servers": _fill_servers()
		"http": _fill_http()
		"done": _fill_done()
		_: _fill_wait()


func _fill_wait() -> void:
	var err := _state == "error"
	box.add_child(_badge("warning" if err else "drive", "warn" if err else "accent"))
	var head := "Plex verbinden"
	if err:
		head = "Verbinden hat nicht geklappt"
	elif _state == "checking":
		head = "Verbinde mit „%s“ …" % str(_pick.get("name", "Plex"))
	box.add_child(U.label(head, "xl", "text", "black"))
	var t := U.label(_msg if _msg != "" else "Code wird bei plex.tv angefordert …", "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var row := U.hbox(14)
	box.add_child(row)
	if err:
		var again := U.button("Nochmal versuchen", "refresh", "primary")
		again.set_meta("uz_default", true)
		again.pressed.connect(func() -> void:
			if _nochmal == "server":
				_load_servers()
			elif str(Config.get_value("plex.token", "")) != "" and not _servers.is_empty():
				_state = "servers"
				_refill()
			else:
				_begin()
		)
		row.add_child(again)
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
	col.add_child(U.label("Plex verbinden", "xl", "text", "black"))
	col.add_child(_step("1", "Code scannen oder plex.tv/link öffnen"))
	col.add_child(_step("2", "Diesen Code eingeben:"))
	col.add_child(_code_box(str(_info.code)))
	col.add_child(U.spacer(0, 2, false))
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
	b.set_meta("uz_hint_a", "Abbrechen")
	b.pressed.connect(close)
	col.add_child(b)


## Server zur Auswahl: Name, eigener oder geteilter, und wie er erreichbar ist.
func _fill_servers() -> void:
	box.add_child(U.label("Welcher Server?", "xl", "text", "black"))
	var t := U.label(
			"Eigene und geteilte Server.", "m",
			"muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var list := U.vbox(10)
	list.set_meta("uz_group", "plex-server")
	box.add_child(list)
	var cur := str(Quellen.server_info("plex").get("id", ""))
	for i in _servers.size():
		var s: Dictionary = _servers[i]
		var conns: Array = s.get("conns", [])
		var how := "Heimnetz" if conns.any(func(c): return bool(c.local) and not bool(c.http)) else ("über Plex-Relay" if conns.all(func(c): return bool(c.relay))
				else "Internet")
		if conns.all(func(c): return bool(c.http)):
			how = "nur unverschlüsselt im Heimnetz"
		var it = ListItem.new()
		it.setup(str(s.name), ("Eigener Server" if bool(s.owned) else "Geteilt") + "  ·  " + how + ("" if bool(s.get("online", true)) else "  ·  gerade offline"),
				"Gewählt" if str(s.id) == cur else "")
		it.icon_name = "drive"
		it.set_meta("uz_key", "plex-server:" + str(s.id))
		it.set_meta("uz_hint_a", "Auswählen")
		if i == 0:
			it.set_meta("uz_default", true)
		var sv := s
		it.activated.connect(func() -> void: _choose(sv, false))
		list.add_child(it)
	var close_b := U.button("Abbrechen", "close")
	close_b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close_b.pressed.connect(close)
	box.add_child(close_b)


func _fill_http() -> void:
	box.add_child(_badge("warning", "warn"))
	box.add_child(U.label("Nur unverschlüsselt erreichbar", "xl", "text", "black"))
	var t := U.label("„%s“ ist nur per http erreichbar. Nur im eigenen Heimnetz verbinden." % str(_pick.get("name", "")), "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var row := U.hbox(14)
	box.add_child(row)
	var ok := U.button("Unverschlüsselt verbinden", "link")
	ok.pressed.connect(func() -> void: _choose(_pick, true))
	row.add_child(ok)
	var no := U.button("Abbrechen", "close", "primary")
	no.set_meta("uz_default", true)
	no.pressed.connect(close)
	row.add_child(no)


func _fill_done() -> void:
	box.add_child(_badge("check", "ok"))
	box.add_child(U.label("Verbunden mit „%s“" % str(_pick.get("name", "Plex")), "xl", "text", "black"))
	var t := U.label(
			"Bibliotheken stehen unter Filme.",
			"l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var b := U.button("Fertig", "check", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(func() -> void:
		close()
		if main and Nav.top_layer() == null:
			main.goto("movies", "start")
	)
	box.add_child(b)


func _begin() -> void:
	_nochmal = "anmelden"
	_state = "wait"
	_msg = ""
	_refill()
	var r: Dictionary = await Quellen.plex_pin_start()
	if not is_inside_tree():
		return
	if not bool(r.ok):
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_info = r
	_info["interval"] = 2
	_until = Time.get_unix_time_from_system() + float(r.expires)
	_state = "code"
	_refill()
	_poll_loop()


func _poll_loop() -> void:
	if _poll_running:
		return
	_poll_running = true
	while is_inside_tree() and _state == "code":
		await get_tree().create_timer(2.0).timeout
		if not is_inside_tree() or _state != "code":
			break
		if Time.get_unix_time_from_system() > _until:
			_state = "error"
			_msg = "Code abgelaufen."
			_refill()
			break
		var st: String = await Quellen.plex_pin_poll(int(_info.id))
		if not is_inside_tree():
			break
		match st:
			"ok":
				Sfx.play("notify")
				await _load_servers()
			"expired":
				_state = "error"
				_msg = "Code abgelaufen."
				_refill()
	_poll_running = false


func _load_servers() -> void:
	_state = "wait"
	_msg = "Server werden geladen …"
	_refill()
	var r: Dictionary = await Quellen.plex_servers()
	if is_inside_tree():
		_server_da(r)


## Antwort auf das Laden der Server. Kein Server im Konto: wie bisher von vorn (vielleicht ein anderes Konto).
## Fehler: neu anmelden nur, wenn plex.tv die Anmeldung nicht mehr annimmt.
func _server_da(r: Dictionary) -> void:
	_servers = r.get("servers", [])
	_nochmal = "server" if not bool(r.ok) and not bool(r.get("anmelden", false)) else "anmelden"
	if not bool(r.ok) or _servers.is_empty():
		_state = "error"
		_msg = str(r.get("error", "")) if not bool(r.ok) else "Kein Plex-Server gefunden."
		_refill()
		return
	if _servers.size() == 1:
		_choose(_servers[0], false)
		return
	_state = "servers"
	_refill()


func _choose(s: Dictionary, allow_http: bool) -> void:
	_pick = s
	_state = "checking"
	_msg = "Verbindung wird geprüft …"
	_refill()
	var r: Dictionary = await Quellen.plex_pick(s, allow_http)
	if not is_inside_tree():
		return
	if bool(r.ok):
		Sfx.play("notify")
		_state = "done"
	elif bool(r.get("http_needed", false)):
		_state = "http"
	else:
		_state = "error"
		_msg = str(r.error)
	_refill()
