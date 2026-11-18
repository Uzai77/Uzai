extends "res://src/ui/layers/layer.gd"
## Addons und Plugins verwalten – als Seite über dem Bereich Filme (früher eigene Reiter dort).
## Oben der Titel und zwei Reiter (Addons, Plugins; LB/RB wechselt), darunter die Verwaltung aus
## movie_manage.gd. Ändert sich etwas (Schalter, Reihenfolge, Installieren), baut sich die Seite
## neu und die Auswahl bleibt, wo sie war. B schließt.

const Manage := preload("res://src/ui/components/movie_manage.gd")

const HEAD_H := 236.0

const Main := preload("res://src/main.gd")
var main: Main
var page := "addons"               ## "addons" oder "plugins"
var _body: Control
var _line: HBoxContainer
var _queued := false


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Zurück")
	var hm := U.margin(UzTheme.GUTTER, 58, UzTheme.GUTTER, 0)
	hm.anchor_right = 1.0
	add_child(hm)
	var hv := U.vbox(16)
	hm.add_child(hv)
	hv.add_child(U.label("Addons und Plugins", "xxl", "text", "title"))
	_line = U.hbox(14)
	_line.set_meta("uz_group", "addons-reiter")
	hv.add_child(_line)
	_fill()
	Movies.changed.connect(_on_changed)


func _first_focus() -> Control:
	var d := Nav.default_in(_body) if is_instance_valid(_body) else null
	return d if d else Nav.default_in(self)


## Seite wechseln (auch von außen: main.goto("movies", "plugins") bei offener Seite).
func show_page(p: String, keep_tab := false) -> void:
	if p != "addons" and p != "plugins":
		return
	if p == page and is_instance_valid(_body):
		return
	page = p
	Sfx.play("tab")
	_fill()
	if not is_inside_tree() or _closing:
		return
	# Gleich neu wählen: der alte Knoten ist schon weg (ein Druck im nächsten Bild ginge ins Leere).
	if keep_tab:
		for b in _line.get_children():
			if str((b as Control).get_meta("uz_key", "")) == "verwalten:" + page:
				Nav.focus(b as Control, true)
	else:
		var d := Nav.default_in(_body)
		if d:
			Nav.focus(d, true)


func handle(cmd: String) -> bool:
	if cmd == "lb" or cmd == "rb":
		show_page("plugins" if page == "addons" else "addons")
		return true
	return false


## Reiter und Verwaltung (neu) aufbauen.
func _fill() -> void:
	U.clear(_line)
	var on := 0
	for a in Movies.addons:
		if bool(a.get("enabled", true)):
			on += 1
	for p in [["addons", "Addons" + (" (%d)" % on if on > 0 else ""), "grid"], ["plugins", "Plugins", "chip"]]:
		var b := U.button(str(p[1]), str(p[2]), "primary" if p[0] == page else "flat")
		b.custom_minimum_size.y = 56
		b.set_meta("uz_key", "verwalten:" + str(p[0]))
		b.set_meta("uz_hint_a", "Anzeigen")
		var pid := str(p[0])
		b.pressed.connect(func() -> void: show_page(pid, true))
		_line.add_child(b)
	if is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	var m = Manage.new()
	m.main = main
	m.page = page
	_body = m
	U.full_rect(_body)
	_body.offset_top = HEAD_H
	add_child(_body)


## Movies hat sich geändert: neu aufbauen (einmal je Bild), die Auswahl per Schlüssel behalten.
func _on_changed() -> void:
	if _queued or _closing:
		return
	_queued = true
	await get_tree().process_frame
	_queued = false
	if not is_inside_tree() or _closing:
		return
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if f and is_ancestor_of(f) else ""
	_fill()
	if key == "":
		return
	for c in Nav.focusables(self):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return
	var d := Nav.default_in(_body)
	if d:
		Nav.focus(d, true)
