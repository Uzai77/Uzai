extends "res://src/ui/components/ach/tile.gd"
## Ein Platz in einer Rangliste unter Freunden: Platznummer, Profilbild, Name und eine Zeile mit
## der Zahl („12 Erfolge“, „18.420 Punkte“). Du selbst stehst auf einer helleren Platte mit einem
## schmalen Akzentstreifen links; der erste Platz trägt seine Nummer in Gold.
## Plätze verschieben sich sichtbar: Wer gegenüber dem letzten Stand (memory, je Gruppe) den Platz
## gewechselt hat, rückt von seinem alten Platz herüber (T_RAUM); Neue kommen gestaffelt von unten.

const Avatar := preload("res://src/ui/components/avatar.gd")

static var memory := {}        ## Gruppe -> { id: Platz-Index } vom letzten Aufbau

var row: Dictionary = {}       ## { rank, name, avatar, state, count, me, … }
var caption := ""              ## die Zeile unter dem Namen
var gap := 20.0                ## Abstand in der Reihe (für den Weg zwischen Plätzen)
var index := -1                ## Platz-Index in der Reihe (-1: ohne Bewegung)
var group := ""                ## Gruppe für memory


func setup(r: Dictionary, cap: String, sz := Vector2(414, 124)) -> Control:
	row = r
	caption = cap
	tile_size = sz
	if bool(r.get("me", false)):
		bg = "surface_hi"
	return self


## Platz i in der Reihe grp: merkt sich den alten Platz, bewegt sich beim Erscheinen passend.
func place(grp: String, i: int, gap_px := 20.0) -> Control:
	group = grp
	index = i
	gap = gap_px
	return self


## Der Weg vom alten Platz (Index) zum neuen: Versatz in Pixeln (rein, getestet).
static func shift_for(old_index: int, new_index: int, width: float, gap_px: float) -> float:
	if old_index < 0 or old_index == new_index:
		return 0.0
	return float(old_index - new_index) * (width + gap_px)


func _ready() -> void:
	super()
	if index < 0 or group == "":
		return
	var mem: Dictionary = memory.get(group, {})
	var id := str(row.get("id", ""))
	var old := int(mem.get(id, -1))
	var dx := shift_for(old, index, tile_size.x, gap)
	if old < 0:
		arrive_from(Vector2(0, 14), U.T_ORT, U.staffel(index), true)
	elif dx != 0.0:
		arrive_from(Vector2(dx, 0), U.T_RAUM)


## Nach dem Aufbau einer Reihe: die Plätze merken (ids in Reihenfolge).
static func remember(grp: String, ids: Array) -> void:
	var m := {}
	for i in ids.size():
		m[str(ids[i])] = i
	memory[grp] = m


func build_body() -> void:
	var m := U.margin(22, 18, 22, 18)
	U.full_rect(m)
	body.add_child(m)
	var h := U.hbox(18)
	m.add_child(h)
	var rank := int(row.get("rank", 0))
	var nr := U.label(str(rank) if rank > 0 else "–", "xl", "gold" if rank == 1 else ("text" if rank <= 3 else "muted"), "black")
	nr.custom_minimum_size.x = 44
	nr.clip_text = false
	nr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nr)
	var av := Avatar.new()
	av.setup(str(row.get("name", "")), str(row.get("avatar", "")), str(row.get("state", "")), 56)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var v := U.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var me := bool(row.get("me", false))
	var nm := U.ellipsis(U.label("Du" if me else str(row.get("name", "")), "m", "text", "ui_bold"))
	if not me:
		nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(nm)
	var cl := U.ellipsis(U.label(caption, "s", "muted", "medium"))
	v.add_child(cl)


func _draw_extra(r: Rect2, _f: float) -> void:
	if not bool(row.get("me", false)):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = UzTheme.col("accent", 0.9)
	sb.set_corner_radius_all(3)
	draw_style_box(sb, Rect2(r.position + Vector2(10, 22), Vector2(4, r.size.y - 44)))
