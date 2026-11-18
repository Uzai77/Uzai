extends "res://src/ui/layers/modal.gd"
## Discord verbinden, Schritt für Schritt sichtbar: Discord-App erreichen → in Discord auf
## „Autorisieren“ klicken → Zugang bei discord.com holen → in der Discord-App anmelden. Hängt es,
## steht an genau diesem Schritt, was Discord geantwortet hat – nicht nur „Noch nicht freigegeben“.

const STEPS := [
	["app", "Discord-App erreichen", "Discord-App am PC starten."],
	["freigabe", "In Discord auf „Autorisieren“ klicken",
		"Maus im Guide unter System."],
	["tausch", "Zugang bei discord.com holen",
		""],
	["anmelden", "In der Discord-App anmelden", ""],
]

const Main := preload("res://src/main.gd")
var main: Main
var _rows: VBoxContainer
var _status: Label
var _btns: HBoxContainer
var _started := false
## Gleich die Freigabe anfordern (aus dem Guide oder den Freunden: der Wunsch ist schon klar).
var autostart := false
## Mit Uzais App versuchen, auch ohne Merker (langes A auf „Mit Discord verbinden“): für freigeschaltete Konten.
var uzai_app := false

## Neue Nutzer mit Uzais App: gleich der Weg zur eigenen App statt einer Freigabe, die Discord ablehnt.
const EIGENE_TEXT := "Für Sprachkanal, Freunde und Nachrichten braucht Uzai deine eigene Discord-App. Einmal einrichten, etwa 3 Minuten mit dem Handy."


## Nur den Weg zur eigenen App zeigen? (Uzais App, kein Merker, kein Zugang, nicht ausdrücklich gewünscht.)
static func nur_eigene(eingebaut_direkt: bool, ausdruecklich: bool) -> bool:
	return not eingebaut_direkt and not ausdruecklich


func fill() -> void:
	width = 1060.0
	var head := U.hbox(16)
	var ic := U.icon("discord", 34, "discord")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	head.add_child(U.label("Mit Discord verbinden", "xl", "text", "black"))
	box.add_child(head)
	if nur_eigene(Voice.uzai_app_direkt(), uzai_app):
		_eigene_zeigen()
		return
	_status = U.label("In der Discord-App freigeben.", "m", "muted",
			"regular", true)
	box.add_child(_status)
	_rows = U.vbox(14)
	box.add_child(_rows)
	box.add_child(U.spacer(0, 4, false))
	_btns = U.hbox(14)
	box.add_child(_btns)
	if not Voice.changed.is_connected(_update):
		Voice.changed.connect(_update)
	if autostart:
		_start.call_deferred()
	_update()


## Der Text und zwei Knöpfe: eigene App einrichten (discord_eigen.gd) oder später.
func _eigene_zeigen() -> void:
	box.add_child(U.label(EIGENE_TEXT, "m", "muted", "regular", true))
	box.add_child(U.spacer(0, 4, false))
	var row := U.hbox(14)
	box.add_child(row)
	var eigen := U.button("Eigene App einrichten", "discord", "primary")
	eigen.set_meta("uz_default", true)
	eigen.pressed.connect(func() -> void:
		var m := main
		close()
		if is_instance_valid(m):
			m.open_layer(load("res://src/ui/layers/discord_eigen.gd").new()))
	row.add_child(eigen)
	var later := U.button("Später", "close", "normal")
	later.pressed.connect(close)
	row.add_child(later)


func _start() -> void:
	_started = true
	Voice.error = ""
	Voice.authorize()
	_update()


func _update() -> void:
	if not is_instance_valid(_rows):
		return
	var cur := _current()
	var failed := _started and Voice.state in ["getrennt", "fehler"] and Voice.error != "" and cur != "fertig"
	U.clear(_rows)
	for st in STEPS:
		var key := str(st[0])
		var state := 0            # 0 offen, 1 läuft, 2 erledigt, 3 gescheitert
		if not _started and not Voice.ready_():
			state = 0
		elif cur == "fertig" or _done(key, cur):
			state = 2
		elif key == cur:
			state = 3 if failed else 1
		_rows.add_child(_row(str(st[1]), str(st[2]) if state in [1, 3] or not _started else "", state))
	if failed:
		_status.text = Voice.error + "  (Einzelheiten stehen im Protokoll im Datenordner.)"
		_status.add_theme_color_override("font_color", UzTheme.col("warn"))
	elif cur == "fertig":
		_status.text = "Verbunden. Sprachkanal im Guide unter „Discord“."
		_status.add_theme_color_override("font_color", UzTheme.col("ok"))
	elif _started:
		_status.text = "Läuft …" if cur != "freigabe" else "In der Discord-App „Autorisieren“ klicken."
		_status.add_theme_color_override("font_color", UzTheme.col("muted"))
	_buttons(failed, cur == "fertig")


## Welcher Schritt gerade dran ist (aus dem Zustand der Discord-Verbindung).
func _current() -> String:
	if Voice.ready_():
		return "fertig"
	if Voice.state in ["aus", "verbinde"] or (Voice.state == "fehler" and Voice.step == ""):
		return "app"
	if Voice.state == "anmelden" or Voice.step in ["freigabe", "tausch", "anmelden"]:
		return Voice.step if Voice.step != "" else "freigabe"
	return "freigabe"


func _done(key: String, cur: String) -> bool:
	var order := ["app", "freigabe", "tausch", "anmelden"]
	return order.find(key) < order.find(cur)


func _row(title: String, sub: String, state: int) -> Control:
	var r := U.hbox(16)
	var icon_name: String = ["clock", "clock", "check", "warning"][state]
	var tone: String = ["faint", "accent", "ok", "warn"][state]
	var ic := U.icon(icon_name, 26, tone)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(ic)
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(col)
	col.add_child(U.label(title, "m", "text" if state > 0 else "muted", "bold" if state == 1 else "medium", true))
	if sub != "":
		col.add_child(U.label(sub, "s", "faint", "regular", true))
	return r


func _buttons(failed: bool, done: bool) -> void:
	U.clear(_btns)
	if done:
		var ok := U.button("Fertig", "check", "primary")
		ok.set_meta("uz_default", true)
		ok.pressed.connect(close)
		_btns.add_child(ok)
	elif failed and Voice.tester_fehlt and Voice.builtin():
		# Uzais App ist für dieses Konto nicht freigeschaltet: Nochmal hilft nicht, die eigene App schon.
		var eigen := U.button("Eigene App einrichten", "discord", "primary")
		eigen.set_meta("uz_default", true)
		eigen.pressed.connect(func() -> void:
			var m := main
			close()
			if is_instance_valid(m):
				m.open_layer(load("res://src/ui/layers/discord_eigen.gd").new()))
		_btns.add_child(eigen)
		var zu := U.button("Schließen", "close", "normal")
		zu.pressed.connect(close)
		_btns.add_child(zu)
	elif not _started or failed:
		var go := U.button("Nochmal versuchen" if failed else "Freigabe anfordern", "refresh" if failed else "discord", "primary")
		go.set_meta("uz_default", true)
		go.pressed.connect(_start)
		_btns.add_child(go)
		var later := U.button("Später" if not failed else "Schließen", "close", "normal")
		later.pressed.connect(close)
		_btns.add_child(later)
	else:
		var hide := U.button("Im Hintergrund weiter", "close", "normal")
		hide.set_meta("uz_default", true)
		hide.pressed.connect(close)
		_btns.add_child(hide)
	await get_tree().process_frame
	if is_inside_tree() and _btns.get_child_count() > 0:
		Nav.focus(_btns.get_child(0) as Control, true)


func _exit_tree() -> void:
	if Voice.changed.is_connected(_update):
		Voice.changed.disconnect(_update)
