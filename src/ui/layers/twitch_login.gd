extends "res://src/ui/layers/yt_login.gd"
## Anmeldung bei Twitch wie die Twitch-App am Fernseher (inoffiziell, nicht von Twitch für fremde
## Apps gedacht): QR-Code mit dem Handy scannen oder twitch.tv/activate öffnen, den Code eingeben,
## „Aktivieren“ tippen, fertig. Braucht keine eigene Entwickler-App. Mit eigener Client-ID
## (Einstellungen → Konten → Twitch) läuft derselbe Ablauf offiziell.
## Der Ablauf (warten, langsamer fragen, abgelaufen, abgelehnt) steht in twitch_parse.gd.

const TP := preload("res://src/core/twitch_parse.gd")
const GeraeteCode := preload("res://src/core/geraete_code.gd")

var _flow: Dictionary = {}


func _start() -> void:
	_begin()


func _fill_wait() -> void:
	var err := _state == "error"
	box.add_child(_badge("warning" if err else "qr", "warn" if err else "accent"))
	box.add_child(U.label("Anmeldung hat nicht geklappt" if err else "Bei Twitch anmelden", "xl", "text", "black"))
	var t := U.label(_msg if _msg != "" else "Code wird bei Twitch angefordert …", "l", "muted", "regular", true)
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
		var own := U.button("Eigene Client-ID", "keyboard")
		own.pressed.connect(_ask_client)
		row.add_child(own)
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
	col.add_child(U.label("Bei Twitch anmelden", "xl", "text", "black"))
	col.add_child(_step("1", "Code scannen oder %s öffnen" % str(_info.get("short", "twitch.tv/activate"))))
	col.add_child(_step("2", "Code:"))
	col.add_child(_code_box(str(_info.user_code)))
	col.add_child(_step("3", "„Aktivieren“ und „Autorisieren“ tippen."))
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


func _fill_done() -> void:
	box.add_child(_badge("check", "ok"))
	var who: String = Twitch.account_name()
	box.add_child(U.label("Angemeldet als %s" % who if who != "" else "Angemeldet", "xl", "text", "black"))
	var t := U.label("Live-Kanäle stehen unter Streams.", "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var b := U.button("Fertig", "check", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(close)
	box.add_child(b)


## Eigene Client-ID (dev.twitch.tv, Typ „Öffentlich“, Geräte-Anmeldung erlaubt) eintippen.
func _ask_client() -> void:
	main.open_keyboard("Twitch-Client-ID", Twitch.own_client(), func(cid: String) -> void:
		Config.set_value("accounts.twitch_client_id", cid.strip_edges())
		Config.set_value("accounts.twitch_mode", "eigen" if cid.strip_edges() != "" else "")
		_begin()
	, false, "https://dev.twitch.tv/console/apps")


func _begin() -> void:
	_state = "wait"
	_msg = ""
	_refill()
	var r: Dictionary = await Twitch.login_start()
	if not is_inside_tree():
		return
	if not r.ok:
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_info = r
	_until = Time.get_unix_time_from_system() + float(r.expires)
	_flow = GeraeteCode.neu(r, Time.get_unix_time_from_system())
	_state = "code"
	_refill()
	_poll_loop()


func _poll_loop() -> void:
	if _poll_running:
		return
	_poll_running = true
	while is_inside_tree() and _state == "code":
		await get_tree().create_timer(float(_flow.get("wait", 5.0))).timeout
		if not is_inside_tree() or _state != "code":
			break
		var st: String = "pending"
		if str(_info.device_code) != "demo":
			st = await Twitch.login_poll(str(_info.device_code), str(_info.get("client", "")))
		if not is_inside_tree() or _state != "code":
			break
		_flow = TP.flow_step(_flow, st, Time.get_unix_time_from_system(), str(Twitch.last_error))
		match str(_flow.phase):
			"done":
				_state = "done"
				Sfx.play("notify")
				_refill()
			"error":
				_state = "error"
				_msg = str(_flow.msg)
				_refill()
	_poll_running = false
