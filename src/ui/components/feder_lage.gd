extends Node
## Feder für die senkrechte Lage eines Elements (Reihen unter einem festen Kopf in Filmen und
## Videos, die Spalte der Musik): statt eines Tweens, der bei jedem Schritt wieder bei Tempo 0
## beginnt, übernimmt die Feder das Tempo des laufenden Wegs. Ein Schritt so straff wie der
## gleitende Rahmen (Liste.GLEITEN), beim Halten weicher (U.SPRING_HOLD) hinter einem Ziel, das im
## Takt des Haltens mitgleitet (wie cover_row.gd). In ganzen Pixeln ohne Treppe am Ende
## (Liste.feder_px). Verstellt jemand anderes die Lage (Neuaufbau, Maus), gibt die Feder nach.

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Raster := preload("res://src/core/raster.gd")

const META := "uz_feder_lage"

var _c: Control
var _pos := 0.0
var _vel := 0.0
var _gesetzt := 0.0
var _z0 := 0.0
var _z1 := 0.0
var _zt := 0.0
var _zd := 0.0
var _halten := false


## c gleitet nach ziel (position.y). sofort: gleich dort (und eine laufende Feder hält an).
static func zu(c: Control, ziel: float, sofort := false) -> void:
	if not is_instance_valid(c):
		return
	var f: Variant = c.get_meta(META) if c.has_meta(META) else null
	if sofort or U.reduziert() or not c.is_inside_tree():
		if f is Node and is_instance_valid(f):
			(f as Node).set_process(false)
		c.position.y = ziel
		return
	if not (f is Node and is_instance_valid(f)):
		var neu: Node = load("res://src/ui/components/feder_lage.gd").new()
		neu.name = "UzFederLage"
		# Intern: zählt nicht zu den Kindern (Layout und Schleifen über die Reihen bleiben gleich).
		c.add_child(neu, false, Node.INTERNAL_MODE_BACK)
		c.set_meta(META, neu)
		f = neu
	f.call("_neues_ziel", c, ziel)


## Eine laufende Feder anhalten (die Lage bleibt, wo sie ist).
static func halt(c: Control) -> void:
	var f: Variant = c.get_meta(META) if is_instance_valid(c) and c.has_meta(META) else null
	if f is Node and is_instance_valid(f):
		(f as Node).set_process(false)


## Läuft die Feder gerade (für Tests und Proben)?
static func laeuft(c: Control) -> bool:
	var f: Variant = c.get_meta(META) if is_instance_valid(c) and c.has_meta(META) else null
	return f is Node and is_instance_valid(f) and (f as Node).is_processing()


func _neues_ziel(c: Control, ziel: float) -> void:
	_c = c
	var jetzt := c.position.y
	if not is_processing() or absf(jetzt - _gesetzt) > 2.0:
		# Neu, oder von außen verstellt: von dort aus, ohne Tempo.
		_pos = jetzt
		_vel = 0.0
		_z1 = jetzt
		_zd = 0.0
	var takt := Nav.halten_takt()
	_halten = takt > 0.0
	if _halten:
		_z0 = _ziel_jetzt()
		_zt = 0.0
		_zd = takt
	else:
		_zd = 0.0
	_z1 = ziel
	_gesetzt = jetzt
	set_process(true)


func _ziel_jetzt() -> float:
	if _zd <= 0.0 or _zt >= _zd:
		return _z1
	return lerpf(_z0, _z1, _zt / _zd)


func _ready() -> void:
	set_process(false)


func _process(dt: float) -> void:
	if not is_instance_valid(_c):
		set_process(false)
		return
	if absf(_c.position.y - _gesetzt) > 2.0:
		set_process(false)
		return
	dt = minf(dt, 0.1)
	_zt += dt
	var ziel := _ziel_jetzt()
	var st := Liste.feder_px(_pos, _vel, ziel, dt, U.SPRING_HOLD if _halten else Liste.GLEITEN)
	_pos = st.x
	_vel = st.y
	var da := _zd <= 0.0 or _zt >= _zd
	if da and absf(_pos - ziel) < Raster.schritt * 0.5 and absf(_vel) < 4.0:
		_pos = ziel
		_vel = 0.0
		set_process(false)
	_c.position.y = Raster.rund(_pos)
	_gesetzt = _c.position.y
