extends "res://src/ui/layers/modal.gd"
## Epic-Anmeldung für den Controller, wie bei Heroic/Legendary (inoffiziell, von Epic nicht
## unterstützt): Ein QR-Code führt auf Uzais Handy-Seite. Dort öffnet „Bei Epic anmelden“ Epics
## eigene Anmeldeseite; danach zeigt Epic eine Textseite mit dem Code (authorizationCode). Den
## kopiert man zurück auf die Handy-Seite – oder tippt ihn auf der Bildschirmtastatur ein. Uzai
## sieht das Passwort nie.

const QrView := preload("res://src/ui/components/qr_view.gd")
const Konten := preload("res://src/core/konten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const EpicOnline := preload("res://src/library/epic_online.gd")
const REQ_ID := "epic_login"

const Main := preload("res://src/main.gd")
var main: Main
## start | busy | done | error (Tabelle gemeinsam mit den anderen Eingabe-Anmeldungen in konten.gd).
var _state := "start":
	set(neu):
		Zustand.wechsel("anmeldung.epic", Konten.ZUSTAENDE_PRUEFEN, _state, neu)
		_state = neu
var _msg := ""
var _phone_url := ""
var _synced := false


func build() -> void:
	width = 1320.0
	set_meta("uz_hint_b", "Schließen")
	super()
	if not Remote.phone_text.is_connected(_on_phone_text):
		Remote.phone_text.connect(_on_phone_text)


func _exit_tree() -> void:
	Remote.phone_end(REQ_ID)
	if Remote.phone_text.is_connected(_on_phone_text):
		Remote.phone_text.disconnect(_on_phone_text)
	Zustand.vergessen("anmeldung.epic")


func _refill() -> void:
	if not is_instance_valid(box):
		return
	U.clear(box)
	fill()
	await get_tree().process_frame
	if not is_instance_valid(box):
		return
	var d := Nav.default_in(box)
	if d:
		Nav.focus(d, true)


func fill() -> void:
	match _state:
		"busy": _fill_busy()
		"done": _fill_done()
		"error": _fill_error()
		_: _fill_start()


func _qr(url: String, px: int) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var qr = QrView.new()
	qr.setup(url, px)
	frame.add_child(qr)
	return frame


func _step(n: String, text: String, w := 720.0) -> Control:
	var r := U.hbox(14)
	var badge := U.panel("accent", 17, 0)
	badge.custom_minimum_size = Vector2(34, 34)
	var l := U.label(n, "s", "bg", "black")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(l)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(badge)
	var t := U.label(text, "m", "text", "medium", true)
	t.custom_minimum_size = Vector2(w, 0)
	r.add_child(t)
	return r


func _fill_start() -> void:
	# Neue Handy-Eingabe (eine alte gilt nach dem Senden nicht mehr).
	Remote.phone_end(REQ_ID)
	_phone_url = Remote.phone_begin(REQ_ID, "Code von der Epic-Seite",
		"Text der Epic-Seite einfügen.", false,
		EpicOnline.LOGIN_URL, "", "Bei Epic anmelden",
		"Anmelden, Textseite kopieren, hier einfügen.")
	var row := U.hbox(52)
	box.add_child(row)
	var left := U.vbox(12)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left.add_child(_qr(_phone_url if _phone_url != "" else EpicOnline.LOGIN_URL, 360))
	var cap := U.label(_phone_url.replace("http://", "") if _phone_url != "" else "epicgames.com/id/login", "s", "muted", "medium")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(cap)
	row.add_child(left)
	var col := U.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(U.label("Mit Epic Games anmelden", "xl", "text", "black"))
	if _phone_url != "":
		col.add_child(_step("1", "Code scannen."))
		col.add_child(_step("2", "„Bei Epic anmelden“ tippen und anmelden."))
		col.add_child(_step("3", "Textseite kopieren, einfügen und senden."))
	else:
		col.add_child(_step("1", "Code scannen und bei Epic anmelden."))
		col.add_child(
				_step("2",
				"Wert hinter „authorizationCode“ über „Code eintippen“ eingeben."))
	var brow := U.hbox(14)
	col.add_child(brow)
	var typed := U.button("Code eintippen", "keyboard", "primary")
	typed.set_meta("uz_default", true)
	typed.pressed.connect(func() -> void:
		if main == null:
			return
		main.open_keyboard("Code von der Epic-Seite", "", func(v: String) -> void: _submit(v), false, EpicOnline.LOGIN_URL)
	)
	brow.add_child(typed)
	var pc := U.button("Im Browser am PC", "link")
	pc.pressed.connect(func() -> void:
		if Config.kid_stop("browser"):
			return
		OS.shell_open(EpicOnline.LOGIN_URL)
		Toasts.show_toast("Epic-Anmeldung im Browser", "Textseite kopieren, dann „Code eintippen“.", "link", { "ms": 6000 })
	)
	brow.add_child(pc)
	var close_b := U.button("Abbrechen", "close")
	close_b.pressed.connect(close)
	brow.add_child(close_b)


func _fill_busy() -> void:
	box.add_child(U.label("Mit Epic Games anmelden", "xl", "text", "black"))
	var t := U.label(_msg, "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)


func _fill_done() -> void:
	var acc = Library.epic_account
	box.add_child(U.label("Angemeldet als %s" % acc.account_name(), "xl", "text", "black"))
	var text := ""
	if _synced:
		var n: int = acc.owned_count()
		text = "%s aus deinem Epic-Konto." % U.plural(maxi(n, 0),
				"Spiel", "Spiele")
	else:
		text = "Spieleliste nicht geladen: %s" % acc.last_error
	var t := U.label(text, "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var b := U.button("Fertig", "check", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(close)
	box.add_child(b)


func _fill_error() -> void:
	box.add_child(U.label("Anmeldung hat nicht geklappt", "xl", "text", "black"))
	var t := U.label(_msg, "l", "muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	var row := U.hbox(14)
	box.add_child(row)
	var again := U.button("Nochmal versuchen", "refresh", "primary")
	again.set_meta("uz_default", true)
	again.pressed.connect(func() -> void:
		_state = "start"
		_refill()
	)
	row.add_child(again)
	var close_b := U.button("Schließen", "close")
	close_b.pressed.connect(close)
	row.add_child(close_b)


func _on_phone_text(id: String, value: String) -> void:
	if id == REQ_ID:
		_submit(value)


func _submit(text: String) -> void:
	if _state == "busy":
		return
	var c := EpicOnline.extract_code(text)
	if str(c.code) == "":
		_state = "error"
		_msg = str(c.error)
		_refill()
		return
	_state = "busy"
	_msg = "Anmeldung läuft …"
	_refill()
	var r: Dictionary = await Library.epic_account.login_with_code(str(c.code))
	if not is_inside_tree():
		return
	if not bool(r.ok):
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_msg = "Spiele werden geladen …"
	_refill()
	_synced = await Library.epic_account.sync()
	# Bibliothek gleich auffrischen (nach einem laufenden Einlesen).
	while Library.scanning:
		await Library.get_tree().process_frame
	Library.refresh_epic()
	if not is_inside_tree():
		return
	Sfx.play("notify")
	_state = "done"
	_refill()

