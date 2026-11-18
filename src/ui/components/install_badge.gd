extends Control
## Auf dem Cover eines Spiels, das Uzai gerade installiert: unten ein Balken, oben links die
## Prozentzahl (bzw. „Pausiert“, „Wartet“) – oben, damit sie nie auf dem Titel des Ersatz-Covers
## liegt. Folgt Installs live und verschwindet, wenn der Download endet.

const U := preload("res://src/ui/u.gd")

var game_id := ""
var _label: Label
var _pill: PanelContainer
var _frac := -1.0
var _phase := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(self)
	_pill = U.panel("bg", 999, 0, 0.78)
	var m := U.margin(10, 3, 12, 4)
	var row := U.hbox(6)
	row.add_child(U.icon("download", 16, "accent"))
	_label = U.label("", "cap", "text", "ui_bold")
	_label.clip_text = false
	row.add_child(_label)
	m.add_child(row)
	_pill.add_child(m)
	add_child(_pill)
	Installs.changed.connect(_on_changed)
	resized.connect(_place)
	_on_changed(game_id)


func _place() -> void:
	if is_instance_valid(_pill):
		# Unter dem Systemschild, wenn das Raster eines zeigt.
		var tag := get_parent().get_node_or_null("SysTag") if get_parent() else null
		_pill.position = Vector2(10, 48 if tag != null else 10)


func _on_changed(id: String) -> void:
	if id != game_id:
		return
	var e := Installs.entry(game_id)
	if e.is_empty() or not Installs.busy(game_id):
		queue_free()
		return
	_phase = str(e.phase)
	_frac = float(e.get("frac", -1.0))
	match _phase:
		"paused": _label.text = "Pausiert"
		"dialog", "ask", "start": _label.text = "Startet …"
		"queued": _label.text = "Wartet"
		"installing": _label.text = "Installiert …"
		_: _label.text = ("%d %%" % int(_frac * 100.0)) if _frac >= 0.0 else "Lädt …"
	_place.call_deferred()
	queue_redraw()


func _draw() -> void:
	# Deckend über dem Erfolgsbalken des Covers (sonst zwei Balken übereinander).
	var h := 6.0
	var r := Rect2(0, size.y - h, size.x, h)
	draw_rect(r, Color(0.05, 0.05, 0.06, 0.92))
	if _frac > 0.0:
		draw_rect(Rect2(r.position, Vector2(size.x * _frac, h)), UzTheme.col("muted") if _phase == "paused" else UzTheme.col("accent"))
