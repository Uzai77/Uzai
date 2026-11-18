extends "res://src/ui/layers/layer.gd"
## Ein fremdes Fenster (Installationsdialog von Steam oder Epic) in Uzai bedienen – ohne Maus und
## ohne dass das Fenster nach vorn kommt: Uzai zeigt ein Bild des Fensters (PrintWindow über den
## Helfer, alle 0,7 s neu) und schickt die Tasten des Controllers als Tastatur an das Fenster
## (Helfer-Befehl window-keys: kurz das Fenster wählen, Taste, sofort zurück zu Uzai).
## Steuerkreuz ↑/↓: vorheriges/nächstes Element (Umschalt+Tab/Tab), ←/→: Pfeiltasten,
## A: Enter, X: Leertaste (Häkchen), Y: Esc an das Fenster, B: zurück zu Uzai.
## done_check: meldet true, sobald erledigt ist, worauf gewartet wird (Download läuft) – dann
## schließt die Ebene von selbst mit „ok“.
## hold_focus (Epic Games Launcher): Das Fenster bekommt die Tastatur einmal und behält sie, bis die
## Ebene zu ist; Uzai bleibt sichtbar oben und nimmt den Controller im Hintergrund an. Der Launcher
## zeichnet seinen Dialog als eingebettete Webseite: Holte Uzai nach jeder Taste den Fokus zurück,
## verlor die Seite ihr gewähltes Feld (Tab begann von vorn), und kurze Tasten kamen beim gedrosselten
## Hintergrundfenster gar nicht an. alt_text: zusätzlicher Weg auf der Start-Taste (Ergebnis „alt“).

signal finished(result: String)   ## "ok", "alt" oder "cancel"

var hwnd := 0
var heading := ""
var done_check: Callable
var _img: TextureRect
var _status: Label
var _timer: Timer
var _snap_busy := false
var _flip := 0
var _sent := false
var _result := ""
var hold_focus := false
var alt_text := ""
var done_toast := "Download läuft"   ## Mitteilung, wenn done_check erfüllt ist ("" = keine)
var weg_schliesst := false           ## Fenster verschwunden (kein Bild mehr): Ebene schließt von selbst
var _kein_bild := 0
var _pad_was := false
var _black := 0


func _init() -> void:
	super()
	# Fast deckend: Das Fenster-Bild soll allein stehen, nicht über der Startseite schweben.
	dim = 0.94


func build() -> void:
	set_meta("uz_hint_b", "Zurück zu Uzai")
	var hints: Array = [["a", "Enter"], ["x", "Leertaste"], ["y", "Esc"]]
	if alt_text != "":
		hints.append(["menu", alt_text])
	set_meta("uz_hints", hints)
	var col := U.vbox(18)
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.custom_minimum_size = Vector2(1320, 0)
	add_child(col)
	var t := U.label(heading, "xl", "text", "bold", true)
	col.add_child(t)
	col.add_child(U.label("Steuerkreuz ↑/↓: nächstes Feld · ←/→: Pfeiltasten · A: Enter · X: Leertaste · Y: Esc", "s", "muted", "regular", true))
	if hold_focus:
		_pad_was = Nav.pad_unfocused
		Nav.pad_unfocused = true
		Helper.run("window-focus", { "hwnd": hwnd }, 5.0)
	var frame := U.panel("surface", UzTheme.radius, 0)
	frame.custom_minimum_size = Vector2(1320, 742)
	col.add_child(frame)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_img.custom_minimum_size = Vector2(1300, 722)
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := U.margin(10, 10, 10, 10)
	m.add_child(_img)
	frame.add_child(m)
	_status = U.label("Bild wird geholt …", "s", "faint", "medium", true)
	col.add_child(_status)
	_timer = Timer.new()
	_timer.wait_time = 0.7
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	_tick()


func _first_focus() -> Control:
	return null


func nav_dir(dir: String) -> bool:
	var keys := { "up": "SHIFT+TAB", "down": "TAB", "left": "LEFT", "right": "RIGHT" }
	_send(str(keys.get(dir, "")))
	return true


func handle(cmd: String) -> bool:
	match cmd:
		"a":
			_send("ENTER")
			return true
		"x":
			_send("SPACE")
			return true
		"y":
			_send("ESC")
			return true
		"lb":
			_send("UP")
			return true
		"rb":
			_send("DOWN")
			return true
	return false


func nav_command(cmd: String) -> bool:
	if cmd == "menu" and alt_text != "":
		Sfx.play("select")
		_finish("alt")
		return true
	if cmd == "b":
		Sfx.play("back")
		_finish("ok" if done_check.is_valid() and bool(done_check.call()) else "cancel")
		return true
	return handle(cmd)


func _send(keys: String) -> void:
	if keys == "" or hwnd == 0:
		return
	Sfx.play("move")
	_sent = true
	var args := { "hwnd": hwnd, "keys": keys, "back_pid": OS.get_process_id() }
	if hold_focus:
		args["stay"] = true
	var r := await Helper.run("window-keys", args, 5.0)
	if not r.ok and is_instance_valid(_status):
		_status.text = "Taste ging nicht an das Fenster: %s" % str(r.get("error", ""))
	# Gleich ein neues Bild, damit man sieht, was passiert ist.
	await get_tree().create_timer(0.25).timeout
	_tick()


func _tick() -> void:
	if not is_inside_tree() or _result != "":
		return
	if done_check.is_valid() and bool(done_check.call()):
		if done_toast != "":
			Toasts.show_toast(done_toast, "", "download", { "sound": "select", "quiet": true })
		_finish("ok")
		return
	if _snap_busy or hwnd == 0:
		return
	_snap_busy = true
	_flip = 1 - _flip
	var path := Config.path("cache/window_remote_%d.png" % _flip)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var r := await Helper.run("window-snap", { "hwnd": hwnd, "path": path.replace("/", "\\") if Config.is_windows() else path, "max_w": 1300 }, 5.0)
	_snap_busy = false
	if not is_inside_tree():
		return
	var how := str((r.result as Dictionary).get("result", "")) if r.ok and r.get("result") is Dictionary else str(r.get("error", "kein Helfer"))
	if how != "ok":
		_kein_bild += 1
		if weg_schliesst and _kein_bild >= 3:
			_finish("cancel")
			return
		_status.text = "Kein Bild vom Fenster (%s). Die Tasten gehen trotzdem an das Fenster." % how
		return
	_kein_bild = 0
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return
	_img.texture = ImageTexture.create_from_image(img)
	_black = _black + 1 if dark(img) else 0
	if _black >= 3 and alt_text != "":
		_status.text = "Das Fenster liefert kein Bild. Start: %s" % alt_text
		return
	_status.text = "Live-Bild des Fensters" + (" · Taste gesendet" if _sent else "")


## Fast nur Schwarz? (Manche Fenster liefern im Hintergrund kein Bild.) Stichproben im Raster.
static func dark(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h / 10, h, maxi(1, h / 10)):
		for x in range(w / 10, w, maxi(1, w / 10)):
			if img.get_pixel(x, y).get_luminance() > 0.06:
				return false
	return true


func _finish(r: String) -> void:
	if _result != "":
		return
	_result = r
	_give_back()
	if _timer:
		_timer.stop()
	finished.emit(r)
	close()


func _notification(what: int) -> void:
	super(what)
	if what == NOTIFICATION_EXIT_TREE and _result == "":
		_result = "cancel"
		_give_back()
		finished.emit("cancel")


## Tastatur und Controller wieder an Uzai.
func _give_back() -> void:
	if not hold_focus:
		return
	Nav.pad_unfocused = _pad_was
	Helper.run("focus", { "pid": OS.get_process_id() })
