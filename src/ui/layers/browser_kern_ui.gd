extends "res://src/ui/layers/modal.gd"
## Browser-Kern einrichten (erstes Öffnen des Uzai-Browsers, docs/BROWSER_PLAN.md 2.2). Der Kern lädt von selbst
## (browser_kern_lauf.gd – meist schon seit dem Öffnen des Bereichs Browser); dieser Dialog zeigt denselben Lauf
## mit Fortschritt (Fassungen lesen, Download, Prüfsummen, Auslegen, offizieller Installer) und meldet fertig(true).
## „Im Hintergrund“ oder B: fertig(false), das Laden geht weiter (die Startbühne zeigt es). „Abbrechen“ hält es an.
## Ein Fehler steht im Klartext mit „Nochmal“ (der genaue Grund in logs/browser_kern.log). Nichts davon braucht
## Adminrechte; der Kern startet später nur mit Sandbox. Der Fokus liegt sofort auf dem ersten Knopf.

signal fertig(ok: bool)

const ProgressBarUz2 := preload("res://src/ui/components/progress_bar.gd")
const Lauf := preload("res://src/core/browser_kern_lauf.gd")

const SCHRITTE := {
	"liste": "Fassungen lesen",
	"download": "Kern laden",
	"pruefen": "Prüfsummen prüfen",
	"auslegen": "Dateien auslegen",
	"install": "Installer prüft Signatur und entpackt",
}
const TEXT := "Einmaliger Download von Chromium, rund 150 MB. Geprüft und ohne Adminrechte. Sicherheitsupdates kommen automatisch."
const TEXT_LAEUFT := "Wird eingerichtet. Läuft auch im Hintergrund weiter."

var wirt: Node                      ## nur noch für ältere Aufrufer; der Lauf hängt nicht mehr am Wirt
var gespielt := false               ## ohne Netz und Dateien (Vorführung, Proben)
var _lauf: Node
var _gemeldet := false
var _bar: ProgressBarUz2
var _schritt_l: Label
var _text_l: Label
var _knoepfe: HBoxContainer
var _fort: VBoxContainer


func fill() -> void:
	width = 920.0
	set_meta("uz_hint_b", "Im Hintergrund")
	box.add_child(U.label("Uzai Browser", "s", "accent", "medium"))
	var t := U.label("Browser-Kern einrichten", "xl", "text", "bold", true)
	t.add_theme_font_override("font", UzTheme.display())
	box.add_child(t)
	_text_l = U.label(TEXT, "m", "muted", "regular", true)
	box.add_child(_text_l)
	_fort = U.vbox(12)
	box.add_child(_fort)
	_schritt_l = U.label("", "m", "text", "medium")
	_fort.add_child(_schritt_l)
	_bar = ProgressBarUz2.new().setup(0.0, "accent", 8.0, width - 96.0)
	_fort.add_child(_bar)
	box.add_child(U.spacer(0, 6, false))
	_knoepfe = U.hbox(16)
	_knoepfe.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_knoepfe)
	# Läuft schon (von der Startbühne) oder fehlt noch: ohne extra Druck laden. Nur nach einem Fehler oder
	# Abbruch in dieser Sitzung wartet der Dialog auf „Nochmal“.
	var st := Lauf.stand()
	if Lauf.aktiv() or (not Lauf.abgebrochen and str(st.fehler) == ""):
		_starten()
	else:
		_ende_zeigen(str(st.fehler) if str(st.fehler) != "" else Lauf.ABGEBROCHEN)


func _first_focus() -> Control:
	for c in _knoepfe.get_children():
		if c.has_meta("uz_default"):
			return c
	return Nav.default_in(_knoepfe)


func _knopf(text: String, icon: String, art: String, key: String, cb: Callable, standard := false) -> Button:
	var b := U.button(text, icon, art)
	b.set_meta("uz_key", key)
	if standard:
		b.set_meta("uz_default", true)
	b.pressed.connect(cb)
	_knoepfe.add_child(b)
	return b


func _starten() -> void:
	_lauf = Lauf.starten(gespielt)
	if _lauf == null:
		_ende_zeigen("Start")
		return
	if not _lauf.is_connected("fortschritt", _fortschritt):
		_lauf.connect("fortschritt", _fortschritt)
		_lauf.connect("fertig", _fertig)
	closable = true
	set_meta("uz_hint_b", "Im Hintergrund")
	_text_l.text = TranslationServer.translate(TEXT_LAEUFT)
	_fort.visible = true
	var st := Lauf.stand()
	_fortschritt(str(st.schritt) if str(st.schritt) != "" else "liste", int(st.prozent), float(st.anteil))
	U.clear(_knoepfe)
	_knopf("Abbrechen", "close", "normal", "browser:kern:abbrechen", func() -> void:
		if is_instance_valid(_lauf):
			_lauf.call("abbrechen"))
	_knopf("Im Hintergrund", "check", "primary", "browser:kern:hintergrund", func() -> void: close(), true)
	_fokus()


## Den Fokus in den Dialog (auch, wenn er im selben Bild wie der Browser aufging).
func _fokus() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(self) and Nav.top_layer() == self:
		Nav.focus(_first_focus(), true)


func _fertig(grund: String) -> void:
	if not is_inside_tree():
		return
	if grund == "":
		_schritt_l.text = TranslationServer.translate("Fertig – der Browser startet.")
		_bar.set_value(1.0)
		await get_tree().create_timer(0.5).timeout
		_gemeldet = true
		fertig.emit(true)
		close()
		return
	_ende_zeigen(grund)


func _ende_zeigen(grund: String) -> void:
	set_meta("uz_hint_b", "Später")
	_text_l.text = TranslationServer.translate(grund)
	_schritt_l.text = TranslationServer.translate("Nichts installiert.")
	_fort.visible = true
	_bar.set_value(0.0)
	U.clear(_knoepfe)
	_knopf("Später", "", "normal", "browser:kern:spaeter", func() -> void: close())
	_knopf("Nochmal" if grund != Lauf.ABGEBROCHEN else "Laden", "download", "primary", "browser:kern:laden", _starten, true)
	_fokus()


## Fortschritt: Schrittname und Prozent (vom Lauf, auch der Installer über den Kern).
func _fortschritt(schritt: String, prozent: int, anteil := -1.0) -> void:
	if not is_instance_valid(_schritt_l):
		return
	var name := str(SCHRITTE.get(schritt, schritt))
	var st := Lauf.stand()
	if schritt == "install" and str(st.text) != "":
		name = str(st.text)
	var mit_prozent := schritt in ["download", "install"]
	_schritt_l.text = "%s · %d %%" % [TranslationServer.translate(name), clampi(prozent, 0, 100)] if mit_prozent else TranslationServer.translate(name)
	if anteil < 0.0:
		anteil = lerpf(float(Lauf.VON.get(schritt, 0.0)), float(Lauf.BIS.get(schritt, 1.0)), clampf(prozent / 100.0, 0.0, 1.0))
	_bar.set_value(anteil)


func close() -> void:
	if not _gemeldet:
		_gemeldet = true
		fertig.emit(false)
	super.close()
