extends "res://src/ui/sections/section.gd"
## Gemeinsames der Medien-Bereiche (Videos, Streams, Filme): Reihen aus medien_reihen.gd, der
## Neuaufbau, der die Auswahl behält, und die Seite mit Bildlauf und leiser Kopfzeile. Stand vorher
## dreimal fast wortgleich in videos_view.gd, streams_view.gd und movies_view.gd.

var _reihen = null             ## medien_reihen.gd
var _instant := false          ## Neuaufbau ohne Hereingleiten (die Seite stand schon)
var _halte_key := ""           ## während eines Neuaufbaus: Schlüssel der Auswahl, die wieder stehen soll (U.in_scheiben)


## Mouse and touch (zeiger.gd): the wheel and vertical dragging move row by row, like up/down, anywhere on the page,
## including over the stage, so videos, films and streams can be scrolled down. Previously the wheel found nothing
## vertical here and scrolled the row under the pointer horizontally. The row itself still scrolls horizontally:
## drag with the mouse button held, Shift + wheel, or the horizontal wheel. Pages with their own scrolling (search,
## grid) keep scrolling themselves, because their scroll area is closer to the mouse.
func zeiger_schritt() -> float:
	if _reihen != null and is_instance_valid(_reihen) and _reihen.row_count() > 0:
		var r: Dictionary = _reihen.rows[clampi(_reihen.current(), 0, _reihen.rows.size() - 1)]
		return maxf(120.0, (r.box as Control).size.y)
	return 200.0


func zeiger_achse() -> String:
	return "y"


## Überschreiben: build() läuft gerade (dann nicht in sich selbst neu bauen).
func _baut_gerade() -> bool:
	return false


## Überschreiben: Dürfen die Reihen nach dem Neuaufbau noch einmal einrasten?
func _reihen_einrasten() -> bool:
	return true


## Neu aufbauen und die Auswahl behalten (Daten kamen, während man auf der Seite steht).
func _rebuild_keep() -> void:
	if _baut_gerade():
		_rebuild_keep.call_deferred()
		return
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if f and is_ancestor_of(f) else ""
	# Gibt es die gewählte Karte danach nicht mehr (aus der Merkliste genommen, Liste erneuert), bleibt die Auswahl
	# an ihrer Stelle in derselben Gruppe statt nach oben zu springen.
	var gruppe := ""
	var stelle := -1
	if key != "":
		var g := _group_of(f)
		if g:
			gruppe = str(g.get_meta("uz_group"))
			stelle = Nav.focusables(g).find(f)
	_instant = true
	_halte_key = key
	build()
	_halte_key = ""
	if main:
		main.refresh_chips()
	if key == "":
		_instant = false
		return
	# Gleich wieder setzen: der alte Knoten ist schon aus dem Baum, und ein Druck im nächsten Bild
	# liefe sonst ins Leere (Fokus null).
	var hit := _find_key(key)
	if hit == null and _reihen != null and is_instance_valid(_reihen):
		# Die Karte steht in einer Reihe, die erst in den nächsten Bildern käme: jetzt alle.
		_reihen.flush()
		hit = _find_key(key)
	if hit == null and gruppe != "" and stelle >= 0:
		var g2 := _find_group(self, gruppe)
		var karten: Array = Nav.focusables(g2) if g2 else []
		if not karten.is_empty():
			hit = karten[clampi(stelle, 0, karten.size() - 1)] as Control
	if hit:
		Nav.focus(hit, true)
	else:
		focus_default()
	# Erst nach dem Layout stimmen die Lagen: die gewählte Reihe noch einmal einrasten lassen – und auf Seiten
	# ohne Reihen (Raster: Verlauf, Merkliste) die gewählte Karte wieder ins Bild rollen. Dort stand die Seite nach
	# dem Neuaufbau oben und die Auswahl weit unten außer Sicht.
	await get_tree().process_frame
	if _reihen != null and is_instance_valid(_reihen):
		if _reihen_einrasten():
			_reihen.resnap()
	elif hit != null and is_instance_valid(hit) and hit.is_inside_tree():
		Nav.reveal(hit, true)
	_instant = false


func _find_key(key: String) -> Control:
	for c in Nav.focusables(self):
		if str(c.get_meta("uz_key", "")) == key:
			return c
	return null


## Seite mit Bildlauf: eine Spalte, oben etwas Luft.
func _scroll_page() -> VBoxContainer:
	var col := U.vbox(16)
	var sc := scroll_v(col)
	sc.set_meta("uz_pad_v", 150.0)
	U.full_rect(sc)
	add_child(sc)
	col.add_child(U.spacer(0, 8, false))
	return col


## Leise Kopfzeile einer Seite („12 Kanäle · …“), rechts auf Wunsch ein Knopf.
func _page_head(text: String, btn: Control = null) -> Control:
	var m := U.margin(GUTTER, 4, GUTTER, 4)
	var row := U.hbox(16)
	m.add_child(row)
	var l := U.label(text, "m", "muted", "medium")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	if btn:
		row.add_child(btn)
	return m
