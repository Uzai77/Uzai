extends "res://src/ui/layers/modal.gd"
## Spotify-Verbindung Schritt für Schritt prüfen: Anmeldung, Konto, Läuft gerade, Geräte, Playlists …
## Jede Zeile sagt, was Spotify geantwortet hat. Lässt Spotify das Konto nicht in die eigene App
## (oder fehlt dem Besitzer Premium), steht daneben ein QR-Code zum Spotify-Dashboard fürs Handy.

const QrView := preload("res://src/ui/components/qr_view.gd")
const DASHBOARD := "https://developer.spotify.com/dashboard"
const SpotifyAnmelden := preload("res://src/ui/layers/spotify_anmelden.gd")

var _rows: VBoxContainer
var _side: VBoxContainer
var _status: Label
var _again: Button
var _relogin: Button
var _busy := false
const Main := preload("res://src/main.gd")
var main: Main


func fill() -> void:
	width = 1180.0
	var head := U.hbox(16)
	var ic := U.icon("music", 34, "music")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	head.add_child(U.label("Spotify-Verbindung", "xl", "text", "black"))
	box.add_child(head)
	_status = U.label("", "m", "muted", "regular", true)
	box.add_child(_status)
	var row := U.hbox(44)
	box.add_child(row)
	_rows = U.vbox(12)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.custom_minimum_size = Vector2(640, 0)
	row.add_child(_rows)
	_side = U.vbox(14)
	_side.visible = false
	_side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_side)
	box.add_child(U.spacer(0, 6, false))
	var foot := U.hbox(14)
	box.add_child(foot)
	_again = U.button("Nochmal prüfen", "refresh", "primary")
	_again.set_meta("uz_default", true)
	_again.pressed.connect(_run)
	foot.add_child(_again)
	_relogin = U.button("Neu verbinden", "link", "normal")
	_relogin.pressed.connect(_reconnect)
	foot.add_child(_relogin)
	var done := U.button("Schließen", "close", "normal")
	done.pressed.connect(close)
	foot.add_child(done)
	_run()


## Läufe von _run, die gerade unterwegs sind (siehe dort).
var _run_offen := 0


func _run() -> void:
	_run_offen += 1
	await _run_lauf()
	_run_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _run täte bis zum Neustart nichts mehr.
	if _run_offen == 0 and _busy:
		_busy = false


func _run_lauf() -> void:
	if _busy:
		return
	_busy = true
	U.clear(_rows)
	_side.visible = false
	_status.text = "Wird geprüft …"
	for n in ["Anmeldung", "Konto", "Läuft gerade", "Geräte", "Playlists", "Lieblingssongs", "Zuletzt gehört", "Top-Titel", "Gefolgte Künstler"] + (
			["Mixe (Startseite)", "Bibliothek (intern)", "Spotify Connect", "Mixe für dich"] if Music.app_mode() else []):
		_rows.add_child(_row(n, "", -1))
	var res: Array = await Music.diagnose()
	_busy = false
	if not is_inside_tree():
		return
	show_results(res)


## Ergebnis zeigen (je Schritt { name, ok, text }); öffentlich für Proben.
func show_results(res: Array) -> void:
	U.clear(_rows)
	var bad := 0
	var account := ""
	# Der lange Grund steht oben; in den Zeilen reicht die Kurzfassung.
	var short := { "nutzer": "Abgelehnt – dein Konto steht nicht in deiner Spotify-App", "premium": "Abgelehnt – die App ist gesperrt (Premium fehlt)",
		"abgelaufen": "Abgelehnt – Anmeldung abgelaufen", "gesperrt": "Abgelehnt (Fehler 403) – siehe oben" }
	var long_text := Music.problem_text(Music.problem) if Music.problem != "" else ""
	for r in res:
		var d: Dictionary = r
		var t := str(d.get("text", ""))
		if long_text != "" and t == long_text:
			t = str(short.get(Music.problem, t))
		_rows.add_child(_row(str(d.get("name", "")), t, 1 if bool(d.get("ok", false)) else 0))
		if not bool(d.get("ok", false)):
			bad += 1
	if Music.problem in ["nutzer", "premium", "gesperrt"]:
		account = Music.problem
	if bad == 0 and Music.grundmodus():
		_status.text = "Läuft gerade, Steuern, Geräte und Verlauf gehen. Bibliothek und Suche gerade nicht erreichbar."
	elif bad == 0:
		_status.text = "Alles in Ordnung."
	elif account != "":
		_status.text = Music.problem_text(account)
	else:
		_status.text = "Spotify lehnt etwas ab. Details im Protokoll."
	_build_side(account)


## Eine Zeile: Zeichen (läuft/gut/abgelehnt), Name, Antwort von Spotify.
func _row(name: String, text: String, state: int) -> Control:
	var r := U.hbox(16)
	var icon_name := "clock" if state < 0 else ("check" if state == 1 else "warning")
	var tone := "faint" if state < 0 else ("ok" if state == 1 else "warn")
	var ic := U.icon(icon_name, 24, tone)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(ic)
	var n := U.label(name, "m", "text", "bold")
	n.custom_minimum_size = Vector2(210, 0)
	n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(n)
	var t := U.label(text if state >= 0 else "…", "m", "muted" if state != 0 else "text", "regular", true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(t)
	return r


## Konto nicht in der App oder ohne Premium: das Dashboard aufs Handy (dort lässt es sich ändern).
func _build_side(account: String) -> void:
	U.clear(_side)
	if account == "":
		return
	_side.visible = true
	var frame := PanelContainer.new()
	var sb := UzTheme.box(Color.WHITE, UzTheme.radius + 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	frame.add_theme_stylebox_override("panel", sb)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(frame)
	var qr = QrView.new()
	qr.setup(DASHBOARD, 240)
	frame.add_child(qr)
	var t := U.label("Im Spotify-Dashboard unter „User Management“ eintragen." if account == "nutzer"
			else ("Im Spotify-Dashboard User Management und „Web API“ prüfen." if account == "gesperrt"
			else "Im Spotify-Dashboard prüfen, ob die App gesperrt ist."), "s", "faint", "regular", true)
	t.custom_minimum_size = Vector2(260, 0)
	_side.add_child(t)


func _reconnect() -> void:
	# Eigene Client-ID: Browser wie bisher; sonst „Mit Spotify anmelden“.
	SpotifyAnmelden.relogin(main, func(_err: String) -> void:
		if is_inside_tree():
			_run()
	)
