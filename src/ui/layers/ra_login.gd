extends "res://src/ui/layers/modal.gd"
## RetroAchievements verbinden (Punkt 49), ganz mit dem Controller: Ein QR-Code führt auf Uzais
## Handy-Seite mit zwei Feldern – Benutzername und Web-API-Schlüssel. „Schlüssel holen“ öffnet
## dort die eigenen Einstellungen bei retroachievements.org. Uzai prüft beides sofort bei
## RetroAchievements und speichert nur, was passt (der Schlüssel liegt im Tresor). Das Passwort
## braucht es nie. Ohne Heimnetz geht dasselbe über die Bildschirmtastatur.

const QrView := preload("res://src/ui/components/qr_view.gd")
const Konten := preload("res://src/core/konten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const REQ_ID := "ra_login"
const KEY_PAGE := "https://retroachievements.org/settings"

const Main := preload("res://src/main.gd")
var main: Main
## start | busy | done | error (Tabelle gemeinsam mit den anderen Eingabe-Anmeldungen in konten.gd).
var _state := "start":
	set(neu):
		Zustand.wechsel("anmeldung.ra", Konten.ZUSTAENDE_PRUEFEN, _state, neu)
		_state = neu
var _msg := ""
var _phone_url := ""
var _name := ""
var _points := 0


func build() -> void:
	width = 1320.0
	set_meta("uz_hint_b", "Schließen")
	super()
	if not Remote.phone_form.is_connected(_on_phone_form):
		Remote.phone_form.connect(_on_phone_form)


func _exit_tree() -> void:
	Remote.phone_end(REQ_ID)
	if Remote.phone_form.is_connected(_on_phone_form):
		Remote.phone_form.disconnect(_on_phone_form)
	Zustand.vergessen("anmeldung.ra")


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
	frame.add_child(QrView.new().setup(url, px))
	return frame


func _step(n: String, text: String) -> Control:
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
	t.custom_minimum_size = Vector2(720, 0)
	r.add_child(t)
	return r


func _text(text: String, size := "m", color := "muted") -> Label:
	var t := U.label(text, size, color, "regular", true)
	t.custom_minimum_size = Vector2(760, 0)
	return t


func _fill_start() -> void:
	# Neue Handy-Eingabe (eine alte gilt nach dem Senden nicht mehr).
	Remote.phone_end(REQ_ID)
	_phone_url = Remote.phone_form_begin(REQ_ID, "RetroAchievements", [
		{ "name": "user", "label": "Benutzername" },
		{ "name": "key", "label": "Web-API-Schlüssel", "secret": true },
	], "Auf retroachievements.org unter Einstellungen → Keys.", KEY_PAGE,
		"Schlüssel holen",
			"Unter „Keys“ den Web-API-Schlüssel kopieren und hier einfügen.")
	var row := U.hbox(52)
	box.add_child(row)
	var left := U.vbox(12)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left.add_child(_qr(_phone_url if _phone_url != "" else KEY_PAGE, 360))
	var cap := U.label(_phone_url.replace("http://", "") if _phone_url != "" else "retroachievements.org/settings", "s", "muted", "medium")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(cap)
	row.add_child(left)
	var col := U.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(U.label("RetroAchievements verbinden", "xl", "text", "black"))
	col.add_child(_text("Benutzername und Web-API-Schlüssel."))
	var cur := str(Config.get_value("accounts.ra_user", ""))
	if cur != "":
		col.add_child(_text("Verbunden als %s." % cur, "s", "ok"))
	if _phone_url != "":
		col.add_child(_step("1", "Code scannen."))
		col.add_child(_step("2", "„Schlüssel holen“ tippen und den Web-API-Schlüssel kopieren."))
		col.add_child(_step("3", "Benutzername und Schlüssel einfügen und senden."))
	else:
		col.add_child(_step("1", "retroachievements.org öffnen und anmelden."))
		col.add_child(_step("2", "Einstellungen → Keys öffnen."))
		col.add_child(_step("3", "Benutzername und Schlüssel eintippen."))
	var brow := U.hbox(14)
	col.add_child(brow)
	var typed := U.button("Eintippen", "keyboard", "primary" if _phone_url == "" else "flat")
	typed.set_meta("uz_default", true)
	typed.set_meta("uz_hint_a", "Bildschirmtastatur")
	typed.pressed.connect(_type_in)
	brow.add_child(typed)
	if cur != "":
		var off := U.button("Abmelden", "leave")
		off.pressed.connect(func() -> void:
			Config.set_value("accounts.ra_user", "")
			Config.set_value("accounts.ra_key", "")
			Toasts.show_toast("RetroAchievements abgemeldet", "Benutzername und Schlüssel sind gelöscht.", "check", { "quiet": true })
			close()
		)
		brow.add_child(off)
	var close_b := U.button("Abbrechen", "close")
	close_b.pressed.connect(close)
	brow.add_child(close_b)


## Ohne Handy: erst der Name, dann der Schlüssel auf der Bildschirmtastatur.
func _type_in() -> void:
	if main == null:
		return
	main.open_keyboard("Benutzername bei RetroAchievements", str(Config.get_value("accounts.ra_user", "")), func(user: String) -> void:
		if user.strip_edges() == "":
			return
		main.open_keyboard("Web-API-Schlüssel", "", func(key: String) -> void: _submit(user, key), true, KEY_PAGE)
	)


func _fill_busy() -> void:
	box.add_child(U.label("RetroAchievements verbinden", "xl", "text", "black"))
	box.add_child(_text(_msg, "l"))


func _fill_done() -> void:
	box.add_child(U.label("Verbunden als %s" % _name, "xl", "text", "black"))
	box.add_child(_text("%s bei RetroAchievements." % U.plural(_points, "Punkt", "Punkte"), "l"))
	var b := U.button("Fertig", "check", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(close)
	box.add_child(b)


func _fill_error() -> void:
	box.add_child(U.label("Anmeldung hat nicht geklappt", "xl", "text", "black"))
	box.add_child(_text(_msg, "l"))
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


func _on_phone_form(id: String, values: Dictionary) -> void:
	if id == REQ_ID:
		_submit(str(values.get("user", "")), str(values.get("key", "")))


## Erst prüfen, dann speichern: Ein falscher Schlüssel landet nie in den Einstellungen.
func _submit(user: String, key: String) -> void:
	if _state == "busy" or not is_inside_tree():
		return
	_state = "busy"
	_msg = "Wird geprüft …"
	_refill()
	var r: Dictionary = await Achievements.check_ra(user.strip_edges(), key.strip_edges())
	if not is_inside_tree():
		return
	if not bool(r.ok):
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_name = str(r.name)
	_points = int(r.points)
	Config.set_value("accounts.ra_user", _name)
	Config.set_value("accounts.ra_key", key.strip_edges())
	Achievements.refresh_overview()
	Sfx.play("notify")
	_state = "done"
	_refill()
