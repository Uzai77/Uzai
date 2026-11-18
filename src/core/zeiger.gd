extends Node
## Maus und Touch (Punkt 64). Hängt an Nav und bedient nur über Nav: Tippen ist A, langes Tippen
## und Rechtsklick sind „Optionen“, Wischen und Ziehen rollen Reihen und Listen mit Schwung, das
## Mausrad rollt weich, die Maustaste „Zurück“ und eine Wischgeste vom linken Rand sind B. Eine
## eigene Fokus-Logik gibt es nicht: Was getroffen wird, bekommt den Fokus über Nav.focus, Klicks
## gehen an die Elemente wie bisher (gui_input), Schritte in Reihen über Nav._fire.
##
## Ziele: ScrollContainer, die wirklich rollen können, und Reihen, die selbst dem Fokus folgen
## (Methode zeiger_schritt(): Pixel je Schritt, zeiger_achse(): "x"/"y").
##
## Ein Mausklick in einer rollbaren Fläche wartet aufs Loslassen (sonst ginge Ziehen nicht);
## ohne Ziehen kommt er unverändert an. Überall sonst kommt er sofort. Touch geht ganz hier
## durch: Godots nachgebildete Mausereignisse fallen weg, ein Tippen setzt erst den Fokus und
## klickt dann – ein Tippen öffnet also, wie A. Daneben tippen zählt (Touch): das nächste
## wählbare Element in TREFFER, sofern unter dem Finger nichts Eigenes reagiert.

const SLOP_MAUS := 8.0           ## logische Pixel, ab denen aus Klicken Ziehen wird
const SLOP_TOUCH := 14.0
const HALTEN_MS := 520           ## langes Tippen
const RAND := 28.0               ## Zurück-Geste: Start so nah am linken Rand …
const GESTE := 110.0             ## … und so weit nach rechts
const REIBUNG := 3.4             ## Schwung: Abbremsen je Sekunde (Geschwindigkeit · e^(−k·t))
const SCHWUNG_MIN := 240.0       ## px/s; langsamer losgelassen gleitet nichts nach
const SCHWUNG_STOP := 18.0
const SCHRITTE_MAX := 12         ## Reihen mit Schritten: so viele höchstens aus einem Wurf
const RAD := 120.0               ## eine Rastung des Mausrads in Pixeln
const RAD_SCHRITT_MS := 160      ## Reihen per Schritt: höchstens ein Schritt so oft mit dem Rad
const TREFFER := 0.035           ## Anteil der Bildhöhe um ein Ziel, der beim Tippen noch zählt
const MAUS_WEG := 40.0           ## so viel echte Bewegung, bis die Hinweise auf Tastatur wechseln
const META := "uz_zeiger"        ## eigene, nachgestellte Klicks (gehen unverändert durch)

var nav: Node
var _p := {}                     ## Zeiger (Touch-Index, Maus = -1) → Zustand
var _fling: Array = []
var _rad_rest := 0.0
var _rad_ms := -100000
var _loslassen_schlucken := false   ## der erste Klick auf einen Reiter oben hat nur gewählt: sein Loslassen geht nirgends hin
var _weg := 0.0
var _weg_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## true: das Ereignis ist erledigt (nichts weiter damit).
func input(e: InputEvent) -> bool:
	if e.has_meta(META):
		return false
	if not (e is InputEventMouse or e is InputEventScreenTouch or e is InputEventScreenDrag or e is InputEventPanGesture):
		return false
	# Maus-Modus mit dem Controller (main.set_mouse_mode) und im Spiel: nicht eingreifen.
	if nav.passthrough or (nav.game_mode and nav.layers.is_empty()):
		return false
	# Godot bildet Touch als Maus nach – Touch geht hier selbst durch.
	if e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION:
		return true
	if e is InputEventScreenTouch:
		return _touch(e as InputEventScreenTouch)
	if e is InputEventScreenDrag:
		return _touch_drag(e as InputEventScreenDrag)
	if e is InputEventPanGesture:
		return _pan(e as InputEventPanGesture)
	if e is InputEventMouseButton:
		return _maus_knopf(e as InputEventMouseButton)
	if e is InputEventMouseMotion:
		return _maus_weg(e as InputEventMouseMotion)
	return false


## Zieht gerade eine Maus (dann wählt der Zeiger unterwegs nichts aus).
func zieht() -> bool:
	var st: Dictionary = _p.get(-1, {})
	return bool(st.get("drag", false))


# --- Touch ----------------------------------------------------------------------------------

func _touch(t: InputEventScreenTouch) -> bool:
	nav.set_device("touch")
	if t.pressed:
		var st := _start(t.position, true)
		_p[t.index] = st
		# Bildschirmtastatur: jede Taste gleich beim Aufsetzen (schnelles Tippen mit zwei Daumen).
		var top: Control = nav.top_layer()
		if top and top.has_meta("uz_tippen_sofort"):
			st["fertig"] = true
			_tippen(t.position)
		return true
	var st2: Dictionary = _p.get(t.index, {})
	_p.erase(t.index)
	if st2.is_empty() or bool(st2.get("fertig", false)) or bool(st2.get("weg", false)) or bool(st2.get("lang", false)):
		return true
	if bool(st2.get("drag", false)):
		_loslassen(st2)
	else:
		_tippen(st2.start)
	return true


func _touch_drag(d: InputEventScreenDrag) -> bool:
	var st: Dictionary = _p.get(d.index, {})
	if st.is_empty() or bool(st.get("fertig", false)):
		return true
	_bewegen(st, d.position, SLOP_TOUCH)
	return true


# --- Maus -----------------------------------------------------------------------------------

func _maus_knopf(m: InputEventMouseButton) -> bool:
	if m.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		if not m.pressed:
			return false
		nav.set_device("mouse")
		return _rad(m)
	if not m.pressed and m.button_index != MOUSE_BUTTON_LEFT:
		return m.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_XBUTTON1]
	if m.pressed:
		nav.set_device("mouse")
	match m.button_index:
		MOUSE_BUTTON_XBUTTON1:
			if m.pressed:
				nav._fire("b")
			return true
		MOUSE_BUTTON_RIGHT:
			_optionen(m.position)
			return true
		MOUSE_BUTTON_LEFT:
			return _maus_links(m)
	return false


func _maus_links(m: InputEventMouseButton) -> bool:
	# Header tabs (uz_klick_waehlt_nur): a click only shows the section, and so does a second click – the browser, the
	# room and own apps open through their tile inside the section, so clicking a tab twice never launches them.
	# Godot gives focus on press, before Nav.klick sees it – so select here and swallow the press and the release.
	if m.pressed:
		var reiter := fokus_an(m.position, false)
		if reiter and reiter.has_meta("uz_klick_waehlt_nur"):
			if reiter != nav.focused():
				nav.focus(reiter, true)
			_loslassen_schlucken = true
			return true
	elif _loslassen_schlucken:
		_loslassen_schlucken = false
		return true
	if m.pressed:
		var hit := control_at(m.position)
		var st := _start(m.position, false)
		st["press"] = m.duplicate()
		var h: Dictionary = st.hosts
		if (h.has("x") or h.has("y")) and not _eigenes_ziehen(hit):
			_p[-1] = st
			return true
		# Ein Klick auf unsichtbare Teile geht ins Leere.
		var hov: Control = get_viewport().gui_get_hovered_control()
		if hov and _alpha(hov) < 0.05:
			return true
		_vorher_fokus(m.position, false)
		return false
	var st2: Dictionary = _p.get(-1, {})
	_p.erase(-1)
	if st2.is_empty():
		return false
	if bool(st2.get("drag", false)):
		_loslassen(st2)
		return true
	# Nicht gezogen: der Klick kommt wie gedrückt an (Fokus vorher, wo die Maus nichts wählt).
	_vorher_fokus(st2.start, false)
	_klick(st2.start, st2.press as InputEventMouseButton)
	return true


func _maus_weg(mm: InputEventMouseMotion) -> bool:
	# Echte Bewegung wechselt die Hinweise auf Tastatur (Windows meldet auch Scheinbewegungen).
	if mm.relative.length() > 0.5:
		var now := Time.get_ticks_msec()
		_weg = (_weg if now - _weg_ms < 400 else 0.0) + mm.relative.length()
		_weg_ms = now
		if _weg >= MAUS_WEG and nav.device != "mouse":
			nav.set_device("mouse")
	var st: Dictionary = _p.get(-1, {})
	if st.is_empty():
		return false
	_bewegen(st, mm.position, SLOP_MAUS)
	return bool(st.get("drag", false))


## Rechtsklick (und langes Tippen): erst das Ziel wählen, dann „Optionen“.
func _optionen(pos: Vector2) -> void:
	var f := fokus_an(pos, nav.device == "touch")
	if f and f != nav.focused():
		nav.focus(f, true)
	nav.optionen()


func _rad(m: InputEventMouseButton) -> bool:
	var vert := m.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not m.shift_pressed
	var sign_ := -1.0 if m.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
	var f := m.factor if m.factor > 0.0 else 1.0
	return _rollen(m.position, vert, sign_ * f)


func _pan(p: InputEventPanGesture) -> bool:
	nav.set_device("mouse")
	var d := p.delta
	if absf(d.y) >= absf(d.x):
		return _rollen(p.position, true, d.y * 0.25)
	return _rollen(p.position, false, d.x * 0.25)


## Rad und Wischen auf dem Touchpad: senkrecht rollt die Seite – gibt es keine, die Reihe unter dem
## Zeiger (Mausrad horizontal in Reihen); mit Umschalt bzw. seitlich immer die Reihe.
## amount: Rastungen (Vorzeichen = Richtung). false: nichts zu rollen – dann geht das Rad weiter an
## die Elemente (Seiten, die selbst rollen: uz_rad_selbst).
func _rollen(pos: Vector2, vert: bool, amount: float) -> bool:
	var h := hosts(control_at(pos))
	# Unter dem Zeiger nichts, das rollt (leere Fläche, Bühne der Medien-Bereiche): dann dort, wo die Auswahl steht –
	# das Rad wirkt so überall auf dem Bild, wie der Controller.
	if h.is_empty() and nav.focused():
		h = hosts(nav.focused())
	if vert and not h.has("y") and h.has("selbst"):
		return false
	var z: Dictionary = (h.get("y", h.get("x", {})) if vert else h.get("x", h.get("y", {})))
	if z.is_empty():
		return false
	if str(z.art) == "schritt":
		_schritte_rad(z.node, str(z.achse), amount)
		return true
	_stop_fling(z.node)
	nav.scroll_by(z.node, str(z.prop), amount * RAD)
	return true


## Rows that glide step by step (media rows, tiles): at most one step per RAD_SCHRITT_MS. Previously every wheel
## notch moved one step immediately – spinning fast (or a wheel that reports many small notches) skipped several
## rows, so scrolling felt too fast. Notches arriving in between are dropped.
func _schritte_rad(node: Control, achse: String, amount: float) -> void:
	if signf(amount) != signf(_rad_rest):
		_rad_rest = 0.0
	_rad_rest += amount
	if absf(_rad_rest) < 1.0:
		return
	var d := signi(int(signf(_rad_rest)))
	_rad_rest = 0.0
	var jetzt := Time.get_ticks_msec()
	if jetzt - _rad_ms < RAD_SCHRITT_MS:
		return
	_rad_ms = jetzt
	_fokus_in(node)
	_schritt(node, achse, d)


# --- Ziehen, Wischen, Schwung -----------------------------------------------------------------

func _start(pos: Vector2, touch: bool) -> Dictionary:
	# Greift der Finger in eine gleitende Liste, hält sie nur an (kein Tippen).
	var gestoppt := _stop_fling_an(pos)
	var st := { "touch": touch, "start": pos, "pos": pos, "ms": Time.get_ticks_msec(), "drag": false,
		"lang": false, "weg": gestoppt and touch, "fertig": false, "samples": [], "hosts": hosts(control_at(pos)) }
	st["rand"] = touch and pos.x <= RAND
	return st


func _bewegen(st: Dictionary, pos: Vector2, slop: float) -> void:
	st.pos = pos
	var d: Vector2 = pos - (st.start as Vector2)
	if not bool(st.drag):
		if d.length() < slop or bool(st.weg) or bool(st.lang):
			return
		# Vom linken Rand nach rechts: Zurück (wie die Geste an Konsolen-Handhelds).
		if bool(st.rand) and d.x > 0.0 and absf(d.x) > absf(d.y) * 1.4:
			if d.x >= GESTE:
				st.fertig = true
				st.weg = true
				nav._fire("b")
			return
		var achse := "x" if absf(d.x) >= absf(d.y) else "y"
		var z: Dictionary = (st.hosts as Dictionary).get(achse, {})
		# Seiten, die selbst rasten (Musik): senkrecht wischen geht Reihe für Reihe.
		if z.is_empty() and achse == "y" and (st.hosts as Dictionary).has("selbst"):
			z = { "art": "schritt", "node": st.hosts.selbst, "achse": "y", "px": 160.0 }
		if z.is_empty():
			# Nichts zu rollen in diese Richtung: aus dem Tippen wird nichts.
			st.weg = true
			return
		st.drag = true
		st.ziel = z
		st.start = pos
		st.base = _wert(z)
		st.done = 0
		if str(z.art) == "schritt":
			_fokus_in(z.node)
		return
	var z2: Dictionary = st.ziel
	var along := -(d.x if str(z2.achse) == "x" else d.y)
	var now := Time.get_ticks_msec()
	(st.samples as Array).append([now, along])
	while (st.samples as Array).size() > 2 and now - int(st.samples[0][0]) > 90:
		(st.samples as Array).pop_front()
	_anwenden(st, float(st.base) + along)


func _loslassen(st: Dictionary) -> void:
	var s: Array = st.samples
	var v := 0.0
	if s.size() >= 2 and Time.get_ticks_msec() - int(s[s.size() - 1][0]) < 70:
		var dt := float(int(s[s.size() - 1][0]) - int(s[0][0])) / 1000.0
		if dt > 0.005:
			v = (float(s[s.size() - 1][1]) - float(s[0][1])) / dt
	if absf(v) < SCHWUNG_MIN:
		return
	var pos := float(st.base) + float(s[s.size() - 1][1])
	_fling.append({ "st": st, "v": v, "pos": pos, "start_done": int(st.get("done", 0)) })


func _process(dt: float) -> void:
	_halten()
	if _fling.is_empty():
		return
	dt = minf(dt, 0.05)
	for f in _fling.duplicate():
		var st: Dictionary = f.st
		var z: Dictionary = st.ziel
		if not is_instance_valid(z.node) or not (z.node as Control).is_inside_tree():
			_fling.erase(f)
			continue
		f.v = float(f.v) * exp(-REIBUNG * dt)
		f.pos = float(f.pos) + float(f.v) * dt
		var am_rand := _anwenden(st, float(f.pos))
		if str(z.art) == "schritt" and absi(int(st.done) - int(f.start_done)) >= SCHRITTE_MAX:
			am_rand = true
		if absf(float(f.v)) < SCHWUNG_STOP or am_rand:
			_fling.erase(f)


## Setzt die Fläche auf value (Pixel entlang der Achse). true am Rand.
func _anwenden(st: Dictionary, value: float) -> bool:
	var z: Dictionary = st.ziel
	# Die Fläche ist inzwischen weg (Ebene mit dem Controller geschlossen, während die Maus zog): nichts mehr zu
	# bewegen. Sonst meldete jede weitere Mausbewegung bis zum Loslassen einen Fehler.
	if not is_instance_valid(z.node) or not (z.node as Control).is_inside_tree():
		return true
	if str(z.art) == "scroll":
		var sc := z.node as ScrollContainer
		var prop := str(z.prop)
		var bar: ScrollBar = sc.get_h_scroll_bar() if prop == "scroll_horizontal" else sc.get_v_scroll_bar()
		var maxv := maxf(0.0, bar.max_value - (sc.size.x if prop == "scroll_horizontal" else sc.size.y))
		var v := clampf(value, 0.0, maxv)
		nav.stop_scroll(sc, prop)
		sc.set(prop, int(round(v)))
		return v != value
	# Reihen, die dem Fokus folgen: ein Schritt je zeiger_schritt Pixel.
	var px := maxf(24.0, float(z.px))
	var want := int(round((value - float(st.base)) / px))
	var moved := true
	while int(st.done) != want and moved:
		var d := signi(want - int(st.done))
		var before: Control = nav.focused()
		_schritt(z.node, str(z.achse), d)
		moved = nav.focused() != before
		st.done = int(st.done) + d
	return not moved


func _wert(z: Dictionary) -> float:
	if str(z.art) == "scroll":
		return float((z.node as ScrollContainer).get(str(z.prop)))
	return 0.0


## Ein Schritt in einer Reihe, die dem Fokus folgt (Nav.move bzw. die Liste des Layouts).
func _schritt(_node: Control, achse: String, d: int) -> void:
	if achse == "x":
		nav._fire("right" if d > 0 else "left")
	else:
		nav._fire("down" if d > 0 else "up")


## Steht der Fokus nicht in der Reihe, zuerst hinein (sonst liefe ein Schritt woanders hin).
func _fokus_in(node: Control) -> void:
	if not is_instance_valid(node):
		return
	var f: Control = nav.focused()
	if f and node.is_ancestor_of(f):
		return
	var d: Control = nav.default_in(node)
	if d:
		nav.focus(d, true)


func _stop_fling(node: Control) -> void:
	for f in _fling.duplicate():
		if (f.st.ziel as Dictionary).get("node") == node:
			_fling.erase(f)


func _stop_fling_an(pos: Vector2) -> bool:
	var hit := false
	for f in _fling.duplicate():
		var n: Variant = (f.st.ziel as Dictionary).get("node")
		if not is_instance_valid(n) or _rect(n as Control).has_point(pos):
			_fling.erase(f)
			hit = hit or is_instance_valid(n)
	return hit


## Langes Tippen: nach HALTEN_MS ohne Bewegung „Optionen“ (nicht auf der Bildschirmtastatur).
func _halten() -> void:
	if _p.is_empty():
		return
	var now := Time.get_ticks_msec()
	for k in _p.keys():
		var st: Dictionary = _p[k]
		if not bool(st.touch) or bool(st.drag) or bool(st.weg) or bool(st.lang) or bool(st.fertig):
			continue
		if now - int(st.ms) >= HALTEN_MS:
			st.lang = true
			var f := fokus_an(st.start, true)
			if f:
				nav._press(f)
			_optionen(st.start)


# --- Tippen -----------------------------------------------------------------------------------

## Tippen (Touch): Fokus aufs Ziel, dann ein Klick dorthin – öffnet also gleich, wie A.
func _tippen(pos: Vector2) -> void:
	var f := fokus_an(pos, true)
	var at := pos
	if f:
		if not _rect(f).has_point(pos):
			at = _rect(f).get_center()
		if f != nav.focused():
			nav.focus(f, true)
	_klick(at)


## Ein Klick an pos, wie ihn die Elemente kennen (gui_input). press: der zurückgehaltene Klick.
func _klick(pos: Vector2, press: InputEventMouseButton = null) -> void:
	var p := press if press else InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.pressed = true
	p.position = pos
	p.global_position = pos
	p.set_meta(META, true)
	get_viewport().push_input(p, true)
	var r := p.duplicate() as InputEventMouseButton
	r.pressed = false
	r.set_meta(META, true)
	get_viewport().push_input(r, true)


## Klick-Modus (schweben.gd): Die Maus wählt beim Darüberfahren nichts – darum Fokus vor jedem Klick, damit ein Klick
## wählt und öffnet in einem Schritt (Reiter, Kategorien, Kacheln, Zeilen gleich).
## (Reiter der Kopfleiste fängt _maus_links vorher ab: dort wählt der erste Klick nur.)
func _vorher_fokus(pos: Vector2, touch: bool) -> void:
	var f := fokus_an(pos, touch)
	if f and f != nav.focused():
		nav.focus(f, true)


# --- Suchen ---------------------------------------------------------------------------------

## Das Element unter pos, wie Godot es für die Maus fände (sichtbar, nicht durchsichtig, nicht
## weggeschnitten, Mausfilter beachtet) – auch für Touch, wo Godot keinen Zeiger kennt.
func control_at(pos: Vector2) -> Control:
	var roots := _wurzeln()
	for i in range(roots.size() - 1, -1, -1):
		var hit := _suche(roots[i][2], pos, 1.0)
		if hit:
			return hit
	return null


## Oberste Controls in Zeichenreihenfolge: [Ebene, Reihenfolge, Control] (auch unter CanvasLayern
## und unter einfachen Knoten wie den Autoloads).
func _wurzeln() -> Array:
	var out: Array = []
	_wurzeln_in(get_tree().root, 0, out)
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) if int(a[0]) != int(b[0]) else int(a[1]) < int(b[1]))
	return out


func _wurzeln_in(n: Node, layer: int, out: Array) -> void:
	for ch in n.get_children():
		if ch is Control:
			out.append([layer, out.size(), ch])
		elif ch is CanvasLayer:
			if (ch as CanvasLayer).visible:
				_wurzeln_in(ch, (ch as CanvasLayer).layer, out)
		elif not (ch is CanvasItem) and not (ch is Window):
			_wurzeln_in(ch, layer, out)


func _suche(c: Control, pos: Vector2, a: float) -> Control:
	if not c.visible:
		return null
	a *= c.modulate.a
	if a < 0.05:
		return null
	var lp := c.get_global_transform_with_canvas().affine_inverse() * pos
	var inside := Rect2(Vector2.ZERO, c.size).has_point(lp)
	if c.clip_contents and not inside:
		return null
	for j in range(c.get_child_count() - 1, -1, -1):
		var ch := c.get_child(j) as Control
		if ch:
			var h := _suche(ch, pos, a)
			if h:
				return h
	if inside and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return c
	return null


## Das wählbare Element unter pos (oder darüber in der Hierarchie). weit (Touch): sonst das
## nächste in TREFFER – außer unter dem Finger reagiert etwas Eigenes (Knopf, Reiter im Guide).
func fokus_an(pos: Vector2, weit: bool) -> Control:
	var hit := control_at(pos)
	var scope: Control = nav.scope_root()
	var n: Node = hit
	while n is Control:
		if _waehlbar(n as Control, scope):
			return n
		n = n.get_parent()
	if not weit:
		return null
	if hit and not hit.has_meta("uz_scrim") and (hit is BaseButton or hit.gui_input.get_connections().size() > 0):
		return null
	var r: float = TREFFER * get_viewport().get_visible_rect().size.y
	var best: Control = null
	var best_d := r
	for c in nav.focusables(scope):
		if _alpha(c) < 0.05 or not _sichtbar(c):
			continue
		var rc := _rect(c)
		var d := Vector2(maxf(0.0, maxf(rc.position.x - pos.x, pos.x - rc.end.x)), maxf(0.0, maxf(rc.position.y - pos.y, pos.y - rc.end.y))).length()
		if d < best_d:
			best_d = d
			best = c
	return best


func _waehlbar(c: Control, scope: Control) -> bool:
	if c.focus_mode != Control.FOCUS_ALL or not c.is_visible_in_tree() or c.has_meta("uz_skip"):
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	return scope == null or scope == c or scope.is_ancestor_of(c)


## Nicht aus einer rollenden Fläche hinausgerollt.
func _sichtbar(c: Control) -> bool:
	var rc := _rect(c)
	var n := c.get_parent()
	while n:
		if n is Control and (n as Control).clip_contents and not _rect(n as Control).intersects(rc):
			return false
		n = n.get_parent()
	return true


func _rect(c: Control) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	return Rect2(xf.origin, c.size * xf.get_scale())


static func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


## Rollbare Flächen um c: { "x": Ziel, "y": Ziel } – je Achse die innerste, die wirklich rollen
## kann. Ziel: { art: "scroll", node, prop, achse } bzw. { art: "schritt", node, achse, px }.
## „selbst“: eine Seite darum rollt selbst senkrecht (eigenes Rad, uz_rad_selbst).
func hosts(c: Control) -> Dictionary:
	var out := {}
	var n: Node = c
	while n:
		if n is ScrollContainer:
			var sc := n as ScrollContainer
			if not out.has("x") and sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and sc.get_h_scroll_bar().max_value > sc.size.x + 1.0:
				out["x"] = { "art": "scroll", "node": sc, "prop": "scroll_horizontal", "achse": "x" }
			if not out.has("y") and sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and sc.get_v_scroll_bar().max_value > sc.size.y + 1.0:
				out["y"] = { "art": "scroll", "node": sc, "prop": "scroll_vertical", "achse": "y" }
		if n is Control and (n as Control).has_meta("uz_rad_selbst") and not out.has("y"):
			out["selbst"] = n
		if n is Control and n.has_method("zeiger_schritt"):
			var ax := str(n.call("zeiger_achse")) if n.has_method("zeiger_achse") else "x"
			if not out.has(ax):
				out[ax] = { "art": "schritt", "node": n, "achse": ax, "px": float(n.call("zeiger_schritt")) }
		n = n.get_parent()
	return out


## Zieht dieses Element selbst (Textfeld, Schieber, Bildlaufleiste)? Dann nie zurückhalten.
func _eigenes_ziehen(c: Control) -> bool:
	var n: Node = c
	while n is Control:
		if n is LineEdit or n is TextEdit or n is Range or (n as Control).has_meta("uz_eigenes_ziehen"):
			return true
		n = n.get_parent()
	return false


