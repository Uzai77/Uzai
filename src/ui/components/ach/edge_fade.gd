extends Node
## Weiche Kanten für rollende Seiten: Reihen, die oben unter die Reiter oder unten aus dem Bild
## rutschen, blenden aus, statt mitten durch eine Textzeile abgeschnitten zu werden. Arbeitet
## nur mit der Deckkraft der Reihen (keine Maske – die würde die runden Cover-Masken stören).

const U := preload("res://src/ui/u.gd")

var scroll: ScrollContainer
var content: Control


## An eine rollende Fläche hängen; content ist die Liste der Reihen darin.
static func attach(sc: ScrollContainer, col: Control) -> Node:
	var f = load("res://src/ui/components/ach/edge_fade.gd").new()
	f.scroll = sc
	f.content = col
	sc.add_child(f)
	return f


func _ready() -> void:
	if is_instance_valid(scroll):
		scroll.get_v_scroll_bar().value_changed.connect(_update)
	# Erst wenn die Reihen nacheinander eingeblendet sind (U.cascade), sanft nachziehen.
	var wr: WeakRef = weakref(self)
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		var me: Node = wr.get_ref()
		if me:
			me.call("_update", 0.0, true)
	)


func _update(_v: float, soft := false) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(content):
		return
	var top := scroll.global_position.y
	var bottom := top + scroll.size.y
	for c in _units():
		# Oben wie unten: wie viel von der Reihe gerade hinter dem Rand liegt.
		var cut := maxf(top - c.global_position.y, c.global_position.y + c.size.y - bottom)
		if cut <= 0.0 or c.size.y <= 0.0:
			if c.has_meta("uz_edge"):
				c.remove_meta("uz_edge")
				_set_alpha(c, 1.0, soft)
			continue
		# Schon halb verdeckt: ganz weg. Dünne Zeilen (Überschrift, Legende) gehen schneller.
		c.set_meta("uz_edge", true)
		_set_alpha(c, clampf(1.0 - cut / maxf(10.0, c.size.y * 0.5), 0.0, 1.0), soft)


func _set_alpha(c: Control, a: float, soft: bool) -> void:
	if soft:
		U.tw(c, "uz_edge_tw").tween_property(c, "modulate:a", a, U.T_BASE)
		return
	var old: Variant = c.get_meta("uz_edge_tw") if c.has_meta("uz_edge_tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	c.modulate.a = a


## Was einzeln ausblendet: die Reihen der Liste – ein Raster darin aber Kachel für Kachel, und
## eine senkrechte Liste mit Meta „uz_edge_rows“ Zeile für Zeile (sonst verschwände die ganze
## Liste, sobald ihr Ende unter dem Rand liegt).
func _units() -> Array[Control]:
	var out: Array[Control] = []
	for ch in content.get_children():
		if not (ch is Control) or not (ch as Control).visible:
			continue
		var grid: Control = null
		if ch is GridContainer or ch.has_meta("uz_edge_rows"):
			grid = ch as Control
		elif ch.get_child_count() == 1 and (ch.get_child(0) is GridContainer or ch.get_child(0).has_meta("uz_edge_rows")):
			grid = ch.get_child(0) as Control
		if grid:
			for t in grid.get_children():
				if t is Control and (t as Control).visible:
					out.append(t as Control)
		else:
			out.append(ch as Control)
	return out
