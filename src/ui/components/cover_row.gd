extends Control
## Das Regal der Startseite: Cover in einer Reihe, die dem Fokus weich folgt. Das gewählte
## Cover steht links an der Kante – bündig mit dem Text darüber –, wächst nach rechts oben,
## und die Nachbarn rücken federnd mit, statt überdeckt zu werden. Was links an der Kante
## vorbeizieht, blendet aus. Gleiche Aufrufe wie das alte Regal (shelf.gd): setup, add, items.
##
## Die Reihe ist kein ScrollContainer: Sie setzt die Lage ihrer Elemente selbst, jedes Bild
## neu, solange sich etwas bewegt, und schläft danach.

## Die Reihe folgt ihrem Ziel mit einer kritisch gedämpften Feder (wie der gleitende Rahmen, beim
## Halten die weichere U.SPRING_HOLD): ein neues Ziel übernimmt das laufende Tempo, statt bei jedem Schritt
## neu anzufahren. Beim Halten gleitet zudem das Ziel selbst im Takt des Haltens (Nav.halten_takt)
## von Cover zu Cover – so fährt das Regal gleichmäßig, statt zu rucken.
const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Raster := preload("res://src/core/raster.gd")
## Gewählt wächst ein Element hier nicht, ohne Nachfedern oder Lichtstreif (Wunsch: auf der
## Startseite wandern und zoomen die Bilder nicht; die Auswahl zeigt allein der Cursor).
## Früher 1,12 mit Schwung, dann 1,03.
const FOCUS_SCALE := 1.0

var gutter := 96.0
var gap := 34.0
var pad_top := 82.0
var pad_bottom := 46.0
var track: Control
var _off := 0.0
var _vel := 0.0
## Gleitendes Ziel: von _z0 nach _z1 in _zd Sekunden (_zt ist die Zeit seit dem Schritt).
var _z0 := 0.0
var _z1 := 0.0
var _zt := 0.0
var _zd := 0.0
var _hmax := 0.0
var _focus: Control = null
var _snap := true
var _last_sum := -1.0


func setup(group: String, gap_px := 34, _anchor := true, pad_v := 82, side := 96, pad_b := -1) -> Control:
	gutter = float(side)
	gap = float(gap_px)
	pad_top = float(pad_v)
	pad_bottom = float(pad_v if pad_b < 0 else pad_b)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_meta("uz_group", group)
	set_meta("uz_mem", true)
	# Die Reihe gleitet mit der Auswahl; die Maus wählt (wie überall) nur per Klick (schweben.gd).
	# Ziehen und Wischen gehen Schritt für Schritt.
	track = Control.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.set_meta("uz_bump_host", true)
	add_child(track)
	resized.connect(func() -> void: _layout(true))
	set_process(false)
	return self


func add(item: Control) -> Control:
	if "focus_scale" in item:
		item.set("focus_scale", FOCUS_SCALE)
	if "calm" in item:
		item.set("calm", true)
	track.add_child(item)
	item.focus_entered.connect(_on_item_focus.bind(item))
	_hmax = maxf(_hmax, item.get_combined_minimum_size().y)
	custom_minimum_size.y = pad_top + _hmax + pad_bottom
	_layout(true)
	return item


## Aufbau der Startseite (startseite_aufbau.gd): ein Element kommt an seinen Platz – v (0…1) ist
## seine Deckkraft, px (ganze Pixel) steht es noch unter seiner Ruhelage. v = 1, px = 0: wie sonst.
func einblenden(item: Control, v: float, px := 0.0) -> void:
	if not is_instance_valid(item):
		return
	if v >= 1.0 and px == 0.0:
		item.remove_meta("uz_ein")
		item.remove_meta("uz_ein_px")
	else:
		item.set_meta("uz_ein", v)
		item.set_meta("uz_ein_px", px)
	_layout(true)


## Luft über der Reihe ändern (die Startseite rückt die Quellenleiste so näher an die Cover).
func set_pad_top(v: float) -> void:
	pad_top = v
	custom_minimum_size.y = pad_top + _hmax + pad_bottom
	_layout(true)


## Maus und Touch (zeiger.gd): ein Schritt je Cover beim Ziehen und Wischen.
func zeiger_schritt() -> float:
	var list := items()
	return ((list[0] as Control).size.x if not list.is_empty() else 200.0) + gap


func zeiger_achse() -> String:
	return "x"


func items() -> Array:
	var out: Array = []
	if track:
		out.append_array(track.get_children())
	return out


## Ein Element schon vor dem Fokus an die Kante stellen (gemerktes Spiel nach dem Neubau),
## damit die Reihe nicht springt, wenn man hineingeht.
func show_item(item: Control) -> void:
	_focus = item
	_layout(true)


func _on_item_focus(item: Control) -> void:
	_focus = item
	if _snap:
		_snap = false
		_layout(true)
	_last_sum = -1.0
	set_process(true)


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		set_process(false)
		return
	_layout(false, dt)


## Ziel der Verschiebung: das gewählte Element an der linken Kante. Am Ende hält die Reihe an,
## sobald das letzte Element rechts an der Kante steht – kein leeres Band hinter dem Regal.
## Passt die ganze Reihe ins Bild, bleibt sie stehen.
func _target() -> float:
	var list := items()
	var fi := list.find(_focus) if is_instance_valid(_focus) else -1
	if fi <= 0:
		return 0.0
	var before := 0.0
	var total := 0.0
	for i in list.size():
		var w: float = (list[i] as Control).size.x
		if i < fi:
			before += w + gap
		total += w + gap
	total += _focus.size.x * 0.14 - gap
	return clampf(before, 0.0, maxf(0.0, total - (size.x - gutter * 2.0)))


func _layout(instant: bool, dt := 0.0) -> void:
	var list := items()
	if list.is_empty():
		return
	var t := _target()
	if instant or U.reduziert():
		_off = t
		_vel = 0.0
		_z0 = t
		_z1 = t
		_zd = 0.0
	else:
		if t != _z1:
			# Neues Ziel: beim Halten gleitet das Ziel dorthin, sonst gilt es sofort.
			_z0 = ziel_jetzt(_z0, _z1, _zt, _zd)
			_z1 = t
			_zt = 0.0
			_zd = _nav_takt()
		_zt += dt * U.tempo()
		var st := folgen(_off, _vel, ziel_jetzt(_z0, _z1, _zt, _zd), dt * U.tempo(), _zd > 0.0)
		_off = st.x
		_vel = st.y
		if _zt >= _zd and absf(_off - t) < Raster.schritt * 0.4 and absf(_vel) < 4.0:
			_off = t
			_vel = 0.0
	var x := gutter - _off
	var sum := _off
	for it in list:
		var c := it as Control
		var w := c.size.x
		# Aufbau der Startseite (einblenden): noch unter seinem Platz und durchsichtig.
		var ein := float(c.get_meta("uz_ein", 1.0))
		c.position = Vector2(Raster.rund(x), pad_top + _hmax - c.size.y + float(c.get_meta("uz_ein_px", 0.0)))
		# Was links an der Kante vorbeizieht, blendet aus (bleibt aber erreichbar).
		var a := 1.0
		if x < gutter - 1.0:
			a = clampf(1.0 - (gutter - x) / (w * 0.8), 0.0, 1.0)
		c.modulate.a = a * ein
		x += w * c.scale.x + gap
		sum += x
	# Schlafen, sobald sich nichts mehr bewegt (Verschiebung am Ziel, Größen ruhen).
	if not instant and _off == t and _vel == 0.0 and absf(sum - _last_sum) < 0.01:
		set_process(false)
	_last_sum = sum


## Ziel jetzt: auf dem Weg von z0 nach z1 (zt von zd Sekunden vorbei); ohne Takt (zd = 0) gleich z1.
static func ziel_jetzt(z0: float, z1: float, zt: float, zd: float) -> float:
	if zd <= 0.0 or zt >= zd:
		return z1
	return lerpf(z0, z1, zt / zd)


## Ein Schritt der Feder zum Ziel: ein einzelner Schritt so straff wie der gleitende Rahmen
## (Liste.GLEITEN, nach gut 250 ms ruhig), beim Halten weicher (U.SPRING_HOLD) hinter dem gleitenden
## Ziel. In ganzen Pixeln ohne Treppe am Ende (Liste.feder_px).
static func folgen(off: float, vel: float, ziel: float, dt: float, halten: bool) -> Vector2:
	return Liste.feder_px(off, vel, ziel, minf(dt, 0.1), U.SPRING_HOLD if halten else Liste.GLEITEN)


func _nav_takt() -> float:
	return Nav.halten_takt()
