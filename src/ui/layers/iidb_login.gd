extends "res://src/ui/layers/modal.gd"
## iiDB verbinden (Bilder und Spielklang von iiSU), ganz mit dem Controller. Zwei Wege, beide enden
## beim eigenen Schlüssel: links ein QR-Code, der auf dem Handy nur accounts.iisu.network öffnet
## (dort legt man seinen Schlüssel an und kopiert ihn), rechts der QR-Code zu Uzais Handy-Seite zum
## Einfügen – oder „Eintippen“ mit der Bildschirmtastatur. Einen Ablauf mit Geräte-Code hat iiDB
## nicht; Uzai erfindet keinen. Der Schlüssel wird sofort geprüft (GET /me/access) und landet nur
## geprüft im Tresor, für alle Profile.

const QrView := preload("res://src/ui/components/qr_view.gd")
const Konten := preload("res://src/core/konten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Iidb := preload("res://src/core/iidb.gd")
const REQ_ID := "iidb_login"

const Main := preload("res://src/main.gd")
var main: Main
## start | busy | done | error (Tabelle gemeinsam mit den anderen Eingabe-Anmeldungen in konten.gd).
## busy endet mit der Antwort oder dem Zeitlimit der Anfrage (IidbDienst.ANFRAGE_S).
var _state := "start":
	set(neu):
		Zustand.wechsel("anmeldung.iidb", Konten.ZUSTAENDE_PRUEFEN, _state, neu)
		_state = neu
var _msg := ""
var _zugang := {}


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
	Zustand.vergessen("anmeldung.iidb")


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
			box.add_child(U.label("Bilder und Klang von iiDB", "xl", "text", "black"))
			box.add_child(_text(_msg, "l"))
		"done":
			box.add_child(U.label("iiDB verbunden", "xl", "text", "black"))
			box.add_child(_text(stufe_text(_zugang), "l"))
			box.add_child(_text("Fehlende Bilder holt „Spiele scrapen“. Der Klang kommt auf der Spielseite.", "m"))
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


## Zeile nach dem Verbinden: Stufe und Anfragen je Sekunde, so wie iiDB sie nennt (Name nur gezeigt).
static func stufe_text(z: Dictionary) -> String:
	if not bool(z.get("ok", false)):
		return ""
	var T := func(t: String) -> String: return TranslationServer.translate(t)
	var teile := PackedStringArray()
	if str(z.get("name", "")) != "":
		teile.append(str(z.name))
	if str(z.get("stufe", "")) != "":
		teile.append(T.call("Stufe %s") % str(z.stufe))
	teile.append(T.call("%d Anfragen je Sekunde") % int(z.get("rps", 1)))
	return " · ".join(teile)


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
	var phone := Remote.phone_begin(REQ_ID, "iiDB-Schlüssel", "Schlüssel einfügen und senden.", true, Iidb.KONTO_SEITE, "",
			"Schlüssel holen", "Bei iiSU anmelden und den iiDB-Schlüssel im Profil kopieren.")
	var row := U.hbox(40)
	box.add_child(row)
	row.add_child(_qr(Iidb.KONTO_SEITE, 260, "1 · Schlüssel holen"))
	if phone != "":
		row.add_child(_qr(phone, 260, "2 · Hier einfügen"))
	var col := U.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(U.label("Bilder und Klang von iiDB", "xl", "text", "black"))
	col.add_child(_text("Cover, Hintergründe, Schriftzüge, Symbole und der Klang der Spielseite aus der Datenbank von iiSU. Jeder nutzt seinen eigenen Schlüssel."))
	if phone != "":
		col.add_child(_text("1. Ersten Code scannen, bei iiSU anmelden, Schlüssel kopieren.\n2. Zweiten Code scannen, einfügen und senden.", "m", "text"))
	else:
		col.add_child(_text("Code scannen, bei iiSU anmelden, Schlüssel kopieren, dann „Eintippen“.", "m", "text"))
	if Media.iidb.verbunden():
		col.add_child(_text("Verbunden.", "s", "ok"))
	var brow := U.hbox(14)
	col.add_child(brow)
	var typed := U.button("Eintippen", "keyboard", "primary" if phone == "" else "flat")
	typed.set_meta("uz_default", true)
	typed.set_meta("uz_hint_a", "Bildschirmtastatur")
	typed.pressed.connect(func() -> void:
		if main:
			main.open_keyboard("iiDB-Schlüssel", "", _submit, true, Iidb.KONTO_SEITE)
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
	var r: Dictionary = await Media.iidb.pruefen_und_speichern(key)
	if not is_inside_tree():
		return
	if not bool(r.ok):
		_state = "error"
		_msg = str(r.error)
		_refill()
		return
	_zugang = r.get("zugang", {})
	Media.iidb_einschalten()
	Sfx.play("notify")
	Toasts.show_toast("iiDB verbunden", stufe_text(_zugang), "check", { "quiet": true })
	_state = "done"
	_refill()
