extends "res://src/ui/layers/modal.gd"
## Google-Anmeldung wie bei Fernsehern: QR-Code mit dem Handy scannen, Code eingeben, fertig.
## Fehlt noch der Google-Zugang (Client-ID), erklärt die Ebene, wie man ihn einmalig anlegt –
## mit einem QR-Code, damit man das bequem am Handy erledigen kann (am PC öffnet sich nichts).

const QrView := preload("res://src/ui/components/qr_view.gd")
const Zustand := preload("res://src/core/zustand.gd")
const CONSOLE_URL := "https://console.cloud.google.com/apis/credentials"

## Anmeldung mit Code oder QR – ein Feld für diese Ebene und alle, die davon erben (Twitch, YouTube am Fernseher,
## Plex, Jellyfin/Emby, Stremio, Nuvio), darum eine Tabelle: start → wait (Code anfordern) → code (QR zeigen,
## nachfragen; bei Twitch und YouTube am Fernseher übernimmt code das Ergebnis von geraete_code.gd: phase done oder
## error) → done, sonst error mit „Nochmal“. Dazu: setup (YouTube: eigener Zugang), notice und addons (Stremio),
## found, http und passwort (Jellyfin: Server im Heimnetz, unverschlüsselt, Name und Passwort hinter der Tastatur),
## servers, checking und http (Plex), sync (Nuvio: Abgleich nach der Anmeldung). Abschicken führt über wait.
const ZUSTAENDE_ANMELDUNG := { "start": ["setup", "wait", "notice"], "setup": ["wait"], "notice": ["wait"],
	"wait": ["error", "code", "found", "http", "done", "sync", "servers", "checking", "addons", "passwort"],
	"code": ["error", "done", "wait", "sync"], "found": ["wait"], "http": ["wait", "checking"], "sync": ["done"],
	"servers": ["checking"], "checking": ["done", "http", "error"], "addons": ["wait"],
	"error": ["wait", "setup", "servers", "passwort"], "passwort": ["wait"], "done": ["wait"] }

## Offen getypt (Node statt Main): Tests geben sich bei den Anmelde-Ebenen selbst als main aus (logic_anmeldung).
var main: Node
var _state := "start":
	set(neu):
		Zustand.wechsel("anmeldung.code", ZUSTAENDE_ANMELDUNG, _state, neu)
		_state = neu
var _info: Dictionary = {}
var _msg := ""
var _until := 0.0
var _poll_running := false
var _countdown: Label
var _left_bar = null


func build() -> void:
	width = 1260.0
	set_meta("uz_hint_b", "Schließen")
	super()
	_start()


## Ebene zu (gilt für alle, die davon erben): kein alter Anmelde-Stand im Fehlerbericht.
func _exit_tree() -> void:
	Zustand.vergessen("anmeldung.code")


func _start() -> void:
	if YouTube.has_client():
		_begin()
	else:
		_state = "setup"
		_refill()


func _refill() -> void:
	if not is_instance_valid(box):
		return
	U.clear(box)
	_countdown = null
	_left_bar = null
	fill()
	await get_tree().process_frame
	if not is_instance_valid(box):
		return
	var d := Nav.default_in(box)
	if d:
		Nav.focus(d, true)


func fill() -> void:
	match _state:
		"setup": _fill_setup()
		"code": _fill_code()
		"done": _fill_done()
		_: _fill_wait()


func _qr(url: String, px: int) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var qr = QrView.new()
	qr.setup(url, px)
	frame.add_child(qr)
	return frame


## Großes, rundes Zeichen oben (Haken, Warnung, Warten).
func _badge(icon: String, color: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(88, 88)
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.draw.connect(func() -> void:
		var m := c.size * 0.5
		c.draw_circle(m, 44, Color(UzTheme.col(color), 0.2))
	)
	var ic := U.icon(icon, 40, color)
	ic.position = Vector2(24, 24)
	c.add_child(ic)
	return c


func _fill_wait() -> void:
	var err := _state == "error"
	box.add_child(_badge("warning" if err else "qr", "warn" if err else "accent"))
	box.add_child(U.label("Anmeldung hat nicht geklappt" if err else "Mit Google anmelden", "xl", "text", "black"))
	var t := U.label(_msg if _msg != "" else "Code wird bei Google angefordert …", "l", "muted", "regular", true)
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
		var setup := U.button("Zugang ändern", "settings")
		setup.pressed.connect(func() -> void:
			_state = "setup"
			_refill()
		)
		row.add_child(setup)
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
	col.add_child(U.label("Mit Google anmelden", "xl", "text", "black"))
	col.add_child(_step("1", "Code scannen oder %s öffnen" % str(_info.url).replace("https://", "")))
	col.add_child(_step("2", "Diesen Code eingeben:"))
	col.add_child(_code_box(str(_info.user_code)))
	col.add_child(_step("3", "Konto wählen und „Zulassen“ tippen."))
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


## Der Code zum Eintippen: groß, mit Luft zwischen den Zeichen, auf einer ruhigen Fläche.
func _code_box(code: String) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("glass_hi"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 10
	sb.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := U.label(code.replace("-", " – "), "hero", "text", "black")
	var fv := FontVariation.new()
	fv.base_font = UzTheme.display("black")
	fv.spacing_glyph = 7
	l.add_theme_font_override("font", fv)
	l.clip_text = false
	p.add_child(l)
	return p


func _step(n: String, text: String, w := 640.0, fsize := "l") -> Control:
	var r := U.hbox(14)
	var badge := U.panel("accent", 17, 0)
	badge.custom_minimum_size = Vector2(34, 34)
	var l := U.label(n, "s", "bg", "black")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(l)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(badge)
	var t := U.label(text, fsize, "text", "medium", true)
	t.custom_minimum_size = Vector2(w, 0)
	r.add_child(t)
	return r


func _fill_done() -> void:
	box.add_child(_badge("check", "ok"))
	box.add_child(U.label("Angemeldet als %s" % YouTube.account if YouTube.account != "" else "Angemeldet", "xl", "text", "black"))
	var n := (YouTube.data.subs as Array).size()
	var t := U.label(
			"%s übernommen." % U.plural(n, "Abo", "Abos"), "l",
			"muted", "regular", true)
	t.custom_minimum_size = Vector2(width - 100, 0)
	box.add_child(t)
	box.add_child(U.spacer(0, 6, false))
	var b := U.button("Fertig", "check", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	b.pressed.connect(close)
	box.add_child(b)


func _fill_setup() -> void:
	var row := U.hbox(52)
	box.add_child(row)
	var left := U.vbox(14)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left.add_child(_qr(CONSOLE_URL, 280))
	var cap := U.label("Am Handy weitermachen", "s", "muted", "medium")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(cap)
	row.add_child(left)
	var col := U.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(U.label("Google-Zugang anlegen", "xl", "text", "black"))
	var t := U.label(
			"Nötig für die Anmeldung. Dauert etwa fünf Minuten.",
			"m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(780, 0)
	col.add_child(t)
	var steps := [
		"console.cloud.google.com öffnen und oben ein neues Projekt „Uzai“ anlegen.",
		"Unter „APIs und Dienste → Bibliothek“ die „YouTube Data API v3“ aktivieren.",
		"„OAuth-Zustimmungsbildschirm“: extern, App-Name „Uzai“, deine E-Mail. Danach „App veröffentlichen“, sonst endet die Anmeldung nach 7 Tagen.",
		"„Anmeldedaten → Anmeldedaten erstellen → OAuth-Client-ID“, Typ „Fernseher und Geräte mit begrenzter Eingabe“.",
		"Die JSON-Datei hier auswählen – oder Client-ID und Clientschlüssel eintippen.",
	]
	for i in steps.size():
		col.add_child(_step(str(i + 1), steps[i], 740.0, "m"))
	var brow := U.hbox(14)
	col.add_child(U.spacer(0, 4, false))
	col.add_child(brow)
	var pick := U.button("JSON-Datei wählen", "file", "primary")
	pick.set_meta("uz_default", true)
	pick.pressed.connect(func() -> void:
		var start := OS.get_environment("USERPROFILE").path_join("Downloads") if Config.is_windows() else ""
		main.open_file_browser("Google-Zugang (JSON)", false, func(path: String) -> void:
			var err := YouTube.load_client_file(path)
			if err != "":
				Toasts.show_toast("Datei passt nicht", err, "warning")
			else:
				_begin()
		, ["json"], start)
	)
	brow.add_child(pick)
	var typed := U.button("Eintippen", "keyboard")
	typed.pressed.connect(func() -> void:
		main.open_keyboard("Client-ID", str(Config.get_value("youtube.client_id", "")), func(id: String) -> void:
			Config.set_value("youtube.client_id", id.strip_edges())
			main.open_keyboard("Clientschlüssel", "", func(sec: String) -> void:
				Config.set_value("youtube.client_secret", sec.strip_edges())
				if YouTube.has_client():
					_begin()
			, true)
		)
	)
	brow.add_child(typed)
	var close_b := U.button("Später", "close")
	close_b.pressed.connect(close)
	brow.add_child(close_b)


func _begin() -> void:
	_state = "wait"
	_msg = ""
	_refill()
	var r := await YouTube.login_start()
	if not is_inside_tree():
		return
	if not r.ok:
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_info = r
	_until = Time.get_unix_time_from_system() + float(r.expires)
	_state = "code"
	_refill()
	_poll_loop()


func _poll_loop() -> void:
	if _poll_running:
		return
	_poll_running = true
	var wait := float(_info.get("interval", 5))
	while is_inside_tree() and _state == "code":
		await get_tree().create_timer(wait).timeout
		if not is_inside_tree() or _state != "code":
			break
		if Time.get_unix_time_from_system() > _until:
			_state = "error"
			_msg = "Code abgelaufen."
			_refill()
			break
		var st := await YouTube.login_poll(str(_info.device_code))
		if not is_inside_tree():
			break
		match st:
			"ok":
				_state = "done"
				Sfx.play("notify")
				_refill()
			"slow":
				wait += 5.0
			"denied":
				_state = "error"
				_msg = "Anmeldung abgelehnt."
				_refill()
			"expired":
				_state = "error"
				_msg = "Code abgelaufen."
				_refill()
	_poll_running = false


func _process(_dt: float) -> void:
	if _state == "code" and is_instance_valid(_countdown):
		var left := int(_until - Time.get_unix_time_from_system())
		var total := maxf(1.0, float(_info.get("expires", 1800)))
		_countdown.text = "Noch %d:%02d Min. gültig" % [floori(maxi(left, 0) / 60.0), maxi(left, 0) % 60]
		if _left_bar != null and is_instance_valid(_left_bar):
			_left_bar.set_value(clampf(float(left) / total, 0.0, 1.0))
