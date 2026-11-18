extends RefCounted
## Texteingabe in einer eigenen App mit dem Controller (src/core/app_steuerung.gd, „Textfeld“): Uzais
## Bildschirmtastatur (src/ui/layers/keyboard.gd, mit „Handy“ und „Einfügen“) liegt durchsichtig über der
## App wie der Guide. Fertig: Uzai gibt die App zurück nach vorn, und der Helfer schreibt den Text als
## Zeichen in ihr Textfeld („app-text“: nur genau dieses Fenster, nur wenn es vorn ist und dort ein
## Textfeld den Fokus hat, docs/SECURITY.md „Eingaben an Fenster“). Abbrechen (B): zurück in die App.
## Wege dorthin: Y im Textfeld bzw. das Textfeld gleich nach A (Helfer meldet „app-tastatur“), im Guide
## „Tastatur“; bekommt ein Textfeld ohne eigenen Druck den Fokus, steht nur kurz „Y Tastatur“.

const AppSteuerung := preload("res://src/core/app_steuerung.gd")
const Main := preload("res://src/main.gd")

## Nach dem Schließen der Tastatur so lange keinen Hinweis „Y Tastatur“ (das Feld hat dann wieder den Fokus).
const STILL_MS := 3000
const HINWEIS_ABSTAND_MS := 8000

static var _zu_ms := -100000
static var _hinweis_ms := -100000
static var _offen := false


## Läuft gerade eine eigene App mit bekanntem Fenster?
static func app_laeuft() -> bool:
	return Launcher.in_game and Launcher.is_app(Launcher.current) and _fenster() != 0


## Das Fenster der App (im Vollbild übernommen, sonst das gefundene).
static func _fenster() -> int:
	return Launcher.app_fenster if Launcher.app_fenster != 0 else Launcher.game_hwnd()


## Meldung des Helfers: „app-tastatur“ (Tastatur auf) oder „app-textfeld“ (nur der Hinweis).
static func melden(m: Main, kind: String) -> void:
	if not app_laeuft() or _offen or m._guide != null or bool(m._overlay_mode):
		return
	if kind == "app-tastatur":
		oeffnen(m)
		return
	var now := Time.get_ticks_msec()
	if now - _zu_ms < STILL_MS or now - _hinweis_ms < HINWEIS_ABSTAND_MS:
		return
	_hinweis_ms = now
	m.app_hinweis(AppSteuerung.hinweis_textfeld())


## Tastatur über der App: Uzai legt sich durchsichtig darüber (wie der Guide), danach gibt es die App
## zurück und schickt den Text.
static func oeffnen(m: Main) -> void:
	if _offen or not app_laeuft():
		return
	_offen = true
	var e: Dictionary = (Launcher.current.get("app", {}) as Dictionary).duplicate()
	var hwnd := _fenster()
	m._enter_overlay()
	var l = load("res://src/ui/layers/keyboard.gd").new()
	l.heading = str(e.get("name", Launcher.current.get("title", "")))
	l.text = ""
	l.phone_ok = true
	var ergebnis := [""]
	l.done.connect(func(t: String) -> void: ergebnis[0] = t)
	l.closed.connect(func() -> void: _zu(m, e, hwnd, str(ergebnis[0])))
	m.open_layer(l)


## Über dem Guide (Guide › Tastatur): die Tastatur liegt über dem Guide; fertig schließt beides, der
## Guide gibt die App wie immer zurück, danach geht der Text an sie.
static func ueber_guide(m: Main, guide: Node) -> void:
	if _offen or not app_laeuft():
		return
	_offen = true
	var e: Dictionary = (Launcher.current.get("app", {}) as Dictionary).duplicate()
	var hwnd := _fenster()
	var l = load("res://src/ui/layers/keyboard.gd").new()
	l.heading = str(e.get("name", Launcher.current.get("title", "")))
	l.text = ""
	l.done.connect(func(t: String) -> void:
		_offen = false
		_zu_ms = Time.get_ticks_msec()
		if is_instance_valid(guide) and guide.has_method("close"):
			guide.call("close")
		senden(e, hwnd, t))
	l.closed.connect(func() -> void:
		_offen = false
		_zu_ms = Time.get_ticks_msec())
	m.open_layer(l)


static func _zu(m: Main, e: Dictionary, hwnd: int, text: String) -> void:
	_offen = false
	_zu_ms = Time.get_ticks_msec()
	if is_instance_valid(m) and bool(m._overlay_mode) and m._guide == null:
		m._leave_overlay()
	senden(e, hwnd, text)


## Text an das Textfeld der App (sobald sie wieder vorn ist; der Helfer wartet darauf höchstens 2,5 s).
static func senden(e: Dictionary, hwnd: int, text: String) -> void:
	var req := AppSteuerung.text_auftrag(e, hwnd, text)
	if req.is_empty() or not Config.is_windows() or not Helper.available:
		return
	var r := await Helper.run("app-text", req, 8.0)
	var res: Dictionary = r.result if r.ok and r.result is Dictionary else {}
	if not bool(res.get("done", false)):
		var why := str(res.get("why", ""))
		Toasts.show_toast("Text kam nicht an", "Kein Textfeld in der App gewählt." if why == "kein Textfeld" else "Die App lag nicht vorn.",
				"keyboard", { "ms": 3500, "quiet": true })
