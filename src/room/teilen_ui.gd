extends "res://src/ui/layers/modal.gd"
## Zimmer teilen (Punkt 131, Stufe 3) – ohne Upload und ohne Server (R6/R8), alles bleibt lokal:
## • als Datei nach Dokumente › Uzai › Zimmer (.uzaizimmer, atomar und geprüft geschrieben,
##   zimmer_teilen.gd schreiben) – mit Vorschaubild;
## • als QR-Code, wenn das Zimmer klein genug ist: Der Code IST das Zimmer (Base64 des Pakets).
##   Auf einem anderen PC landet er über die Zwischenablage im Zimmer (Menü › Teilen ›
##   „Zimmer-Code einführen“) und läuft dort durch denselben Prüfer wie jede Datei.
## Was mitreist, steht hier ehrlich dabei: Einrichtung, eigene Möbel, Figur und Haustier – keine
## Spiele, keine Namen, kein Spielstand.

const QrView := preload("res://src/ui/components/qr_view.gd")
const Teilen := preload("res://src/room/zimmer_teilen.gd")
const Zimmer := preload("res://src/room/zimmer.gd")

var zimmer: Zimmer
var auszug: Dictionary = {}
var vorschau: Image
var _wo: Label
var _gespeichert := ""

const BREITE_LINKS := 600.0
const QR_PX := 460


func build() -> void:
	width = 1260.0
	set_meta("uz_hint_b", "Schließen")
	super()


func fill() -> void:
	var code := Teilen.code(auszug)
	box.add_theme_constant_override("separation", 20)
	var reihe := U.hbox(44)
	box.add_child(reihe)
	# Links: was geteilt wird (Vorschau, die in der Datei mitreist), wie es weitergeht, die Knöpfe.
	var links := U.vbox(18)
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reihe.add_child(links)
	var kopf := U.vbox(4)
	kopf.add_child(U.label("Zimmer teilen", "xl", "text", "black"))
	var was := U.label("Ohne Spiele und Namen.", "s", "muted", "regular", true)
	was.custom_minimum_size = Vector2(BREITE_LINKS, 0)
	kopf.add_child(was)
	links.add_child(kopf)
	var rahmen := PanelContainer.new()
	rahmen.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.radius + 2))
	rahmen.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	rahmen.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bild := TextureRect.new()
	bild.custom_minimum_size = Vector2(BREITE_LINKS, BREITE_LINKS * 9.0 / 16.0)
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if vorschau and not vorschau.is_empty():
		bild.texture = ImageTexture.create_from_image(vorschau)
	rahmen.add_child(bild)
	links.add_child(rahmen)
	var zeile := U.label(
			"Gespeichert unter Dokumente › Uzai › Zimmer.", "m",
			"muted", "regular", true)
	zeile.custom_minimum_size = Vector2(BREITE_LINKS, 0)
	links.add_child(zeile)
	_wo = U.label("", "s", "accent", "medium", true)
	_wo.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_wo.custom_minimum_size = Vector2(BREITE_LINKS, 0)
	_wo.visible = false
	links.add_child(_wo)
	var knoepfe := U.hbox(14)
	links.add_child(knoepfe)
	var speichern := U.button("Als Datei speichern", "save", "primary")
	speichern.set_meta("uz_default", true)
	speichern.pressed.connect(_speichern)
	knoepfe.add_child(speichern)
	if code != "":
		var kopieren := U.button("Code kopieren", "link")
		kopieren.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(code)
			Toasts.show_toast("Zimmer-Code kopiert", tr("%d Zeichen in der Zwischenablage") % code.length(), "check", { "quiet": true })
		)
		knoepfe.add_child(kopieren)
	var fertig := U.button("Fertig")
	fertig.pressed.connect(close)
	knoepfe.add_child(fertig)
	# Rechts: der QR-Code groß genug, dass ein Handy ihn vom Fernseher aus liest.
	var rechts := U.vbox(14)
	rechts.custom_minimum_size = Vector2(QR_PX + 40, 0)
	reihe.add_child(rechts)
	if code != "":
		var qr_rahmen := PanelContainer.new()
		qr_rahmen.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
		qr_rahmen.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var qr = QrView.new()
		qr.setup_async(code, QR_PX)
		qr_rahmen.add_child(qr)
		rechts.add_child(qr_rahmen)
		var hinweis := U.label("Den Text im Code unter Menü › Teilen einfügen.", "s", "muted", "regular", true)
		hinweis.custom_minimum_size = Vector2(QR_PX + 40, 0)
		rechts.add_child(hinweis)
	else:
		var zu_gross := U.label("Zu groß für einen QR-Code. Als Datei teilen.", "m", "muted", "regular", true)
		zu_gross.custom_minimum_size = Vector2(QR_PX + 40, 0)
		rechts.add_child(zu_gross)
	var notiz := U.label("Kein Upload.", "s", "faint", "regular", true)
	notiz.custom_minimum_size = Vector2(QR_PX + 40, 0)
	rechts.add_child(notiz)


func _speichern() -> void:
	if _gespeichert != "":
		Toasts.show_toast("Schon gespeichert", _gespeichert.get_file(), "save", { "quiet": true, "sub_raw": true })
		return
	var ex := Teilen.export_ordner()
	var datei := Teilen.dateiname(str(ex[1]), Time.get_datetime_dict_from_system())
	var bytes := Teilen.paket(auszug, Teilen.vorschau_jpg(vorschau))
	var r := Teilen.schreiben(str(ex[0]), str(ex[1]), datei, bytes, auszug)
	if not bool(r.ok):
		Sfx.play("error")
		Toasts.show_toast("Nicht gespeichert", str(r.error), "warning")
		return
	_gespeichert = str(r.pfad)
	_wo.text = _win_pfad(_gespeichert)
	_wo.visible = true
	Sfx.play("toggle_on")
	Toasts.show_toast("Zimmer als Datei gespeichert", _gespeichert.get_file(), "save", { "sub_raw": true })


## Pfad so, wie man ihn unter Windows liest.
static func _win_pfad(p: String) -> String:
	return p.replace("/", "\\") if OS.get_name() == "Windows" else p
