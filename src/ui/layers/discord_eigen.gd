extends "res://src/ui/layers/modal.gd"
## „Volle Discord-Steuerung“: in etwa drei Minuten eine eigene Discord-App anlegen – mit dem Handy.
##
## Uzais eigene App bekommt den Sprachkanal von Discord nur für freigeschaltete Konten (Voice.TESTER_TEXT); eine neue
## Freischaltung vergibt Discord nicht mehr. Wer seine eigene App hat, ist dort Inhaber, und alles geht wie bei Uzais
## Entwickler: Sprachkanäle, wer spricht, Stumm und Taub, Streams. Die Discord-Bibliothek im Paket gilt für jede App.
##
## Am Fernseher steht nur der QR-Code und drei Zeilen. Die Anleitung steht auf dem Handy – dort legt man die App an –
## samt der zwei Adressen zum Kopieren (Remote.phone_form_begin mit steps). Das Feld dort nimmt nur eine echte App-ID
## (17–20 Ziffern). Kommt sie an, trägt Uzai sie ein und verbindet gleich (discord_connect mit autostart).

const QrView := preload("res://src/ui/components/qr_view.gd")
const PORTAL := "https://discord.com/developers/applications"
const REDIRECTS := ["http://localhost", "http://127.0.0.1/callback"]

## Die Anleitung auf dem Handy. Die Namen der Knöpfe auf Discords Entwicklerseite bleiben englisch – so stehen sie dort.
const SCHRITTE := [
	{ "text": "Oben „Discord-Entwicklerseite öffnen“ tippen, mit deinem Discord-Konto anmelden, dann „New Application“. Name: Uzai, Haken setzen, „Create“." },
	{ "text": "Links „OAuth2“ öffnen. Bei „Redirects“ zweimal „Add Redirect“ und diese zwei Adressen einfügen:", "copy": REDIRECTS },
	{ "text": "Darunter „Public Client“ einschalten und unten „Save Changes“ tippen." },
	{ "text": "Links „General Information“: bei „Application ID“ auf „Copy“ tippen, zurück zu diesem Tab und unten einfügen." },
	{ "text": "Nur für Discord-Nachrichten in Uzai (geht auch später): links unter „Discord Social SDK“ auf „Getting Started“, Formular ausfüllen, „Submit“." },
]

const Main := preload("res://src/main.gd")
var main: Main
var _req_id := ""
var _status: Label
var _btns: HBoxContainer


func fill() -> void:
	width = 1180.0
	var head := U.hbox(16)
	var ic := U.icon("discord", 34, "discord")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	head.add_child(U.label("Volle Discord-Steuerung", "xl", "text", "black"))
	box.add_child(head)
	box.add_child(U.label("Sprachkanäle, Stummschalten und Streams im Guide. Dafür legst du einmal deine eigene Discord-App an – etwa 3 Minuten mit dem Handy, kostenlos.",
		"m", "muted", "regular", true))
	var row := U.hbox(40)
	box.add_child(row)
	_req_id = "dce%d" % Time.get_ticks_msec()
	var url := Remote.phone_form_begin(_req_id, "Application ID hier einfügen",
		[{ "name": "id", "label": "Application ID", "pattern": "[0-9]{17,20}", "inputmode": "numeric" }],
		"Uzai trägt sie ein und verbindet sich gleich mit Discord.", PORTAL, "Discord-Entwicklerseite öffnen",
		"Öffnet sich in einem neuen Tab. Danach hierher zurück.", "", SCHRITTE)
	if url != "":
		if not Remote.phone_form.is_connected(_on_phone):
			Remote.phone_form.connect(_on_phone)
		var qf := PanelContainer.new()
		var qsb := UzTheme.box(Color.WHITE, UzTheme.radius + 4)
		qsb.set_content_margin_all(8)
		qf.add_theme_stylebox_override("panel", qsb)
		qf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		qf.add_child(QrView.new().setup(url, 300))
		row.add_child(qf)
	var col := U.vbox(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var zeilen := ["Code mit der Kamera des Handys scannen.", "Der kurzen Anleitung auf dem Handy folgen.",
		"„An Uzai senden“ – Uzai verbindet sich von selbst."] if url != "" else [tr("Auf dem PC oder Handy: ") + PORTAL.trim_prefix("https://"),
		tr("„New Application“, unter OAuth2 die Redirects %s und „Public Client“.") % " · ".join(PackedStringArray(REDIRECTS)),
		"„Application ID“ kopieren und hier mit „Am Fernseher eintippen“ eintragen."]
	for i in zeilen.size():
		col.add_child(_zeile(i + 1, str(zeilen[i])))
	if url != "":
		col.add_child(U.label(tr("Handy und PC im selben WLAN · ") + url.replace("http://", ""), "s", "faint", "medium"))
	_status = U.label("Warte aufs Handy …" if url != "" else "Kein Heimnetz gefunden – die App-ID geht auch über die Tastatur.", "m", "muted", "regular", true)
	box.add_child(_status)
	_btns = U.hbox(14)
	box.add_child(_btns)
	var tippen := U.button("Am Fernseher eintippen", "keyboard", "primary" if url == "" else "normal")
	tippen.pressed.connect(_tippen)
	_btns.add_child(tippen)
	var spaeter := U.button("Später", "close", "normal")
	spaeter.pressed.connect(close)
	_btns.add_child(spaeter)
	_fokus.call_deferred()


func _fokus() -> void:
	if is_inside_tree() and _btns.get_child_count() > 0:
		Nav.focus(_btns.get_child(0) as Control, true)


## Eine nummerierte Zeile: Ziffer im Kreis, daneben der Satz.
func _zeile(n: int, text: String) -> Control:
	var r := U.hbox(16)
	var zahl := U.label(str(n), "m", "accent", "black")
	zahl.custom_minimum_size = Vector2(28, 0)
	zahl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zahl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(zahl)
	var l := U.label(text, "m", "text", "regular", true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	return r


func _tippen() -> void:
	main.open_keyboard("Application ID", str(Config.get_value("accounts.discord_client_id", "")), func(v: String) -> void:
		_uebernehmen(v)
	, false, PORTAL)


func _on_phone(id: String, values: Dictionary) -> void:
	if id != _req_id:
		return
	_req_id = ""
	_uebernehmen(str(values.get("id", "")))


## App-ID übernehmen: prüfen, eintragen, gleich verbinden. Passt sie nicht, bleibt der Dialog mit einem neuen Code offen.
func _uebernehmen(v: String) -> void:
	var fehler: String = Voice.eigene_app_setzen(v)
	if fehler != "":
		if is_instance_valid(_status):
			_status.text = fehler
			_status.add_theme_color_override("font_color", UzTheme.col("warn"))
		return
	DiscordChat.restart()
	Toasts.show_toast("Eigene Discord-App eingetragen", "In Discord einmal „Autorisieren“ klicken.", "discord", { "quiet": true })
	var dc = load("res://src/ui/layers/discord_connect.gd").new()
	dc.autostart = true
	var m := main
	close()
	if is_instance_valid(m):
		m.open_layer(dc)


func _exit_tree() -> void:
	if _req_id != "":
		Remote.phone_end(_req_id)
	if Remote.phone_form.is_connected(_on_phone):
		Remote.phone_form.disconnect(_on_phone)
