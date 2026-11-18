extends "res://src/ui/layers/modal.gd"
## Bilder von SteamGridDB einrichten (empfohlen, überspringbar), ganz mit dem Controller: links
## ein QR-Code direkt zu steamgriddb.com → API (dort mit Steam anmelden, Schlüssel erzeugen und
## kopieren), rechts der QR-Code zu Uzais Handy-Seite zum Einfügen. Uzai prüft den Schlüssel sofort
## und speichert ihn für alle Profile im Tresor. Ohne Heimnetz bleibt die Bildschirmtastatur.

const QrView := preload("res://src/ui/components/qr_view.gd")
const Konten := preload("res://src/core/konten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Sgdb := preload("res://src/core/sgdb_konto.gd")
const REQ_ID := "sgdb_login"

const Main := preload("res://src/main.gd")
var main: Main
## start | busy | done | error (Tabelle gemeinsam mit den anderen Eingabe-Anmeldungen in konten.gd).
var _state := "start":
	set(neu):
		Zustand.wechsel("anmeldung.sgdb", Konten.ZUSTAENDE_PRUEFEN, _state, neu)
		_state = neu
var _msg := ""


func build() -> void:
	width = 1400.0
	set_meta("uz_hint_b", "Schließen")
	super()
	if not Remote.phone_text.is_connected(_on_phone):
		Remote.phone_text.connect(_on_phone)


func _exit_tree() -> void:
	Remote.phone_end(REQ_ID)
	if Remote.phone_text.is_connected(_on_phone):
		Remote.phone_text.disconnect(_on_phone)
	Zustand.vergessen("anmeldung.sgdb")


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
		"busy":
			box.add_child(U.label("Bilder von SteamGridDB", "xl", "text", "black"))
			box.add_child(_text(_msg, "l"))
		"done":
			box.add_child(U.label("SteamGridDB verbunden", "xl", "text", "black"))
			box.add_child(_text("Bilder werden geladen.", "l"))
			var b := U.button("Fertig", "check", "primary")
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			b.set_meta("uz_default", true)
			b.pressed.connect(close)
			box.add_child(b)
		"error":
			box.add_child(U.label("Schlüssel passt nicht", "xl", "text", "black"))
			box.add_child(_text(_msg, "l"))
			var row := U.hbox(14)
			box.add_child(row)
			var again := U.button("Nochmal", "refresh", "primary")
			again.set_meta("uz_default", true)
			again.pressed.connect(func() -> void:
				_state = "start"
				_refill()
			)
			row.add_child(again)
			var cb := U.button("Schließen", "close")
			cb.pressed.connect(close)
			row.add_child(cb)
		_:
			_fill_start()


func _qr(url: String, px: int, caption: String) -> Control:
	var col := U.vbox(10)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
	frame.add_child(QrView.new().setup(url, px))
	col.add_child(frame)
	var cap := U.label(caption, "s", "muted", "medium", true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.custom_minimum_size = Vector2(px + 20, 0)
	col.add_child(cap)
	return col


func _text(text: String, size := "m", color := "muted") -> Label:
	var t := U.label(text, size, color, "regular", true)
	t.custom_minimum_size = Vector2(620, 0)
	return t


func _fill_start() -> void:
	Remote.phone_end(REQ_ID)
	var phone := Remote.phone_begin(REQ_ID, "SteamGridDB-Schlüssel", "Schlüssel einfügen und senden.", true, Sgdb.KEY_PAGE, "",
			"Schlüssel holen", "Mit Steam anmelden, Schlüssel erzeugen und kopieren.")
	var row := U.hbox(40)
	box.add_child(row)
	row.add_child(_qr(Sgdb.KEY_PAGE, 260, "1 · Schlüssel holen"))
	if phone != "":
		row.add_child(_qr(phone, 260, "2 · Hier einfügen"))
	var col := U.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(U.label("Bilder für fast jedes Spiel", "xl", "text", "black"))
	col.add_child(_text("Cover und Hintergründe von SteamGridDB. Kostenloser Schlüssel nötig."))
	if phone != "":
		col.add_child(_text("1. Ersten Code scannen, Schlüssel erzeugen und kopieren.\n2. Zweiten Code scannen, einfügen und senden.", "m", "text"))
	else:
		col.add_child(_text("Code scannen, Schlüssel erzeugen, dann „Eintippen“.", "m", "text"))
	if Sgdb.connected():
		col.add_child(_text("Verbunden.", "s", "ok"))
	var brow := U.hbox(14)
	col.add_child(brow)
	var typed := U.button("Eintippen", "keyboard", "primary" if phone == "" else "flat")
	typed.set_meta("uz_default", true)
	typed.set_meta("uz_hint_a", "Bildschirmtastatur")
	typed.pressed.connect(func() -> void:
		if main:
			main.open_keyboard("SteamGridDB-Schlüssel", "", _submit, true, Sgdb.KEY_PAGE)
	)
	brow.add_child(typed)
	var later := U.button("Später", "close")
	later.pressed.connect(close)
	brow.add_child(later)


func _on_phone(id: String, value: String) -> void:
	if id == REQ_ID:
		_submit(value)


## Erst prüfen, dann speichern: Ein falscher Schlüssel landet nie in den Einstellungen.
func _submit(key: String) -> void:
	if _state == "busy" or not is_inside_tree():
		return
	_state = "busy"
	_msg = "Wird geprüft …"
	_refill()
	var r: Dictionary = await Sgdb.check_and_store(key)
	if not is_inside_tree():
		return
	if not bool(r.ok):
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	Sfx.play("notify")
	Toasts.show_toast("SteamGridDB verbunden", "Fehlende Bilder werden geladen …", "check", { "quiet": true })
	# Fehlende Bilder gleich im Hintergrund ergänzen (eigene, selbst gewählte bleiben).
	Media.import_sgdb_all(false)
	_state = "done"
	_refill()
