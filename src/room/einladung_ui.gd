extends "res://src/ui/layers/modal.gd"
## Freundestest, Gastgeber: die offene Einladung zum Weitergeben (freundestest.gd). Links der Code groß in
## Fünfergruppen (zum Abtippen und Vorlesen), die Restzeit und der Stand („Warte …“, „Mila klopft an“), darunter
## „In die Zwischenablage“ (du schickst ihn selbst per Messenger), „Zurückziehen“ und „Fertig“. Rechts derselbe
## Code als QR-Code – zum Abfotografieren mit dem Handy. Verschickt wird nichts; im Protokoll steht der Code nie.

const QrView := preload("res://src/ui/components/qr_view.gd")
const Einladung := preload("res://src/room/einladung.gd")

const QR_PX := 380
const BREITE_LINKS := 640.0

var ft: Node
var _rest: Label
var _stand: Label
var _uhr: Timer


func build() -> void:
	width = 1200.0
	set_meta("uz_hint_b", "Schließen")
	super()


func fill() -> void:
	var code := Einladung.code_anzeige(str(ft.einladung.get("code", "")))
	box.add_theme_constant_override("separation", 20)
	var reihe := U.hbox(44)
	box.add_child(reihe)
	var links := U.vbox(16)
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reihe.add_child(links)
	links.add_child(U.label("Einladung", "xl", "text", "black"))
	var fuer := U.label(tr("Für %s · gilt einmal") % str(ft.einladung.get("fuer", "")), "m", "muted", "regular", true)
	fuer.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	links.add_child(fuer)
	# Der Code: zwei Zeilen in fester Breite (Schrift mit gleich breiten Zeichen), gut aus 3 m zu lesen.
	var feld := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface_hi"), UzTheme.radius + 2)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	feld.add_theme_stylebox_override("panel", sb)
	var gruppen := code.split("-")
	var zeilen := U.vbox(6)
	for z in [" ".join(gruppen.slice(0, 4)), " ".join(gruppen.slice(4))]:
		var l := U.label(z, "xl", "text", "bold")
		l.add_theme_font_override("font", UzTheme.font("mono"))
		l.add_theme_font_size_override("font_size", 46)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.name = "code"
		zeilen.add_child(l)
	feld.add_child(zeilen)
	links.add_child(feld)
	_rest = U.label("", "m", "accent", "medium")
	_rest.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	links.add_child(_rest)
	_stand = U.label("", "m", "muted", "regular", true)
	_stand.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_stand.custom_minimum_size = Vector2(BREITE_LINKS, 0)
	links.add_child(_stand)
	var knoepfe := U.hbox(14)
	links.add_child(knoepfe)
	var kopieren := U.button("In die Zwischenablage", "link", "primary")
	kopieren.set_meta("uz_default", true)
	kopieren.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code)
		Sfx.play("toggle_on")
		Toasts.show_toast("Code kopiert", "Jetzt selbst an deinen Freund schicken", "check", { "quiet": true }))
	knoepfe.add_child(kopieren)
	var senden := U.button("An Freund senden", "chat")
	senden.pressed.connect(_senden)
	knoepfe.add_child(senden)
	var zurueck := U.button("Zurückziehen", "close")
	zurueck.pressed.connect(func() -> void:
		ft.zurueckziehen()
		Sfx.play("toggle_off")
		Toasts.show_toast("Einladung zurückgezogen", "Der Code gilt nicht mehr", "close")
		close())
	knoepfe.add_child(zurueck)
	var fertig := U.button("Fertig")
	fertig.pressed.connect(close)
	knoepfe.add_child(fertig)
	var rechts := U.vbox(12)
	rechts.custom_minimum_size = Vector2(QR_PX + 40, 0)
	reihe.add_child(rechts)
	var qr_rahmen := PanelContainer.new()
	qr_rahmen.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
	qr_rahmen.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var qr = QrView.new()
	qr.setup_async(code, QR_PX)
	qr_rahmen.add_child(qr)
	rechts.add_child(qr_rahmen)
	var hinweis := U.label("Mit dem Handy abfotografieren und weiterschicken.", "s", "muted", "regular", true)
	hinweis.custom_minimum_size = Vector2(QR_PX + 40, 0)
	rechts.add_child(hinweis)
	_uhr = Timer.new()
	_uhr.wait_time = 1.0
	_uhr.timeout.connect(_auffrischen)
	add_child(_uhr)
	_uhr.start()
	_auffrischen()


## Die Einladung an genau einen Freund schicken: Steam-Chat oder Discord-Direktnachricht, je nachdem, was
## verbunden ist. Gesendet wird nur ein kurzer Satz mit dem Code (Einladung.chat_text) – kein Link.
func _senden() -> void:
	var wahl: Array = []
	if SteamChat.can_send():
		for f in Social.steam_friends.slice(0, 40):
			wahl.append(["steam:" + str(f.get("id", "")), tr("%s · Steam-Freund") % str(f.get("name", ""))])
	if DiscordChat.can_send():
		for f in DiscordChat.friends.slice(0, 40):
			wahl.append(["discord:" + str(f.get("id", "")), tr("%s · Discord-Freund") % str(f.get("name", ""))])
	if wahl.is_empty():
		Toasts.show_toast("Kein Chat verbunden", "Steam oder Discord unter Konten verbinden – oder den Code selbst schicken.", "info")
		return
	var m: Node = get_tree().current_scene
	if m and m.has_method("open_choice"):
		var code := str(ft.einladung.get("code", ""))
		m.call("open_choice", "An wen?", wahl, "", func(w: Variant) -> void: _senden_an(code, str(w)), "Gesendet wird nur ein kurzer Satz mit dem Code.")


## Statisch: Wird die Einladung geschlossen, während die Nachricht noch unterwegs ist, kommt die Meldung
## trotzdem („Nicht gesendet“ ging sonst verloren, und der Freund wartete auf einen Code, der nie kam).
static func _senden_an(code: String, ziel: String) -> void:
	if code == "":
		return
	var text := Einladung.chat_text(code)
	var fehler := "?"
	if ziel.begins_with("steam:"):
		fehler = await SteamChat.send(ziel.substr(6), text)
	elif ziel.begins_with("discord:"):
		fehler = await DiscordChat.send(ziel.substr(8), text)
	if fehler == "":
		Sfx.play("toggle_on")
		Toasts.show_toast("Einladung gesendet", "Dein Freund kann jetzt anklopfen", "check", { "quiet": true })
	else:
		Toasts.show_toast("Nicht gesendet", fehler.left(120), "warning")


func _auffrischen() -> void:
	if not is_instance_valid(ft):
		close()
		return
	var r: int = ft.einladung_rest()
	_rest.text = tr("Noch %d:%02d gültig") % [r / 60, r % 60] if r > 0 else tr("Nicht mehr gültig")
	_stand.text = str(ft.stand_text())
	if r == 0 and ft.figuren().is_empty() and (ft.anklopfer as Array).is_empty() and _uhr.time_left > 0.0 and str(ft.zustand) == "ende":
		close()
