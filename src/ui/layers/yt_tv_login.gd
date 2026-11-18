extends "res://src/ui/layers/yt_login.gd"
## Anmeldung wie YouTube auf dem Fernseher (SmartTube-Weg, nicht offiziell von Google
## unterstützt): QR-Code mit dem Handy scannen oder youtube.com/activate öffnen, den Code eingeben,
## fertig. Braucht – anders als die offizielle Anmeldung – keinen eigenen Google-Zugang.
## Der Ablauf (warten, langsamer fragen, abgelaufen, abgelehnt) steht in youtube_tv_parse.gd.

const TvParse := preload("res://src/core/youtube_tv_parse.gd")
const GeraeteCode := preload("res://src/core/geraete_code.gd")

var _flow: Dictionary = {}


func _start() -> void:
	_begin()


func _fill_wait() -> void:
	var err := _state == "error"
	box.add_child(_badge("warning" if err else "qr", "warn" if err else "accent"))
	box.add_child(U.label("Anmeldung hat nicht geklappt" if err else "Mit YouTube anmelden", "xl", "text", "black"))
	var t := U.label(_msg if _msg != "" else "Code wird bei YouTube angefordert …", "l", "muted", "regular", true)
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
	col.add_child(U.label("Mit YouTube anmelden", "xl", "text", "black"))
	col.add_child(_step("1", "Code scannen oder %s öffnen" % str(_info.url).replace("https://", "").replace("www.", "")))
	col.add_child(_step("2", "Diesen Code eingeben:"))
	col.add_child(_code_box(str(_info.user_code)))
	col.add_child(_step("3", "Konto wählen und „Zulassen“ tippen."))
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
	var who: String = YouTube.tv.account_name()
	box.add_child(U.label("Angemeldet als %s" % who if who != "" else "Angemeldet", "xl", "text", "black"))
	var t := U.label("Deine YouTube-Startseite steht unter Videos.", "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var b := U.button("Fertig", "check", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(close)
	box.add_child(b)


func _begin() -> void:
	_state = "wait"
	_msg = ""
	_refill()
	var r: Dictionary = await YouTube.tv.login_start()
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
			st = await YouTube.tv.login_poll(str(_info.device_code))
		if not is_inside_tree() or _state != "code":
			break
		_flow = TvParse.flow_step(_flow, st, Time.get_unix_time_from_system(), str(YouTube.tv.last_error))
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
