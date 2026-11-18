extends Control
## Die Reihen unter der Bühne – eine Mechanik für Videos, Filme und Streams (docs/PLAN_MEDIEN.md).
##
## Reihen aus Karten liegen in einer Spalte unter einem festen Kopf. Die gewählte Reihe gleitet mit
## der Feder (FederLage) nach oben an den Kopf; Reihen darüber sind verdeckt und für die Steuerung
## aus (uz_skip). Jede Reihe merkt sich ihre Karte, hoch/runter wechselt die Reihe, aus der ersten
## geht es hinauf (zu den Unterreitern), unter der letzten stößt es an. Welche Karte gerade gewählt
## ist, meldet row_focused – die Bühne darüber zeigt sie. Beim Neuaufbau (instant) steht alles
## sofort. Laden: skeleton() liefert Platzhalter in derselben Form (Überschrift, Karten), damit
## nichts springt, wenn die echten Reihen kommen.
##
## Karten brauchen nur focus_entered (jedes Control) und, wenn sie es haben, die Eigenschaft
## nav_ud_cb (Hoch/Runter an die Reihen abgeben) – mehr nicht.

signal row_focused(row: int, card: Control, item: Dictionary, dir: int)

const U := preload("res://src/ui/u.gd")
const FederLage := preload("res://src/ui/components/feder_lage.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")

const GUTTER := 96
## Luft über und unter den Karten einer Reihe (das gewählte Bild wächst nach oben in die Luft).
const PAD_TOP := 28
const PAD_BOTTOM := 22
## Abstand der Karten in einer Reihe.
const GAP := 28
## Bilder laden nur Karten in der Nähe der Auswahl: die Reihe darüber, die gewählte und so viele
## darunter, je Reihe bis so viele Karten rechts der gemerkten. Die übrigen (Karten mit „lazy“ und
## wake(), video_card.gd, movie_card.gd) holen ihr Bild, wenn man hinkommt – früher lud eine
## Startseite mit 300 Karten alle Bilder auf einmal, und das Bild der Bühne stand dahinter an.
const VORAUS_REIHEN := 2
const VORAUS_KARTEN := 8
## Aufbau oben zuerst: Karten der Reihen ab so vielen unter der gewählten kommen erst in den
## nächsten Bildern in die Reihe (eine Reihe je Bild, _drain). Gemessen kostete eine Startseite
## mit zwölf Reihen à 30 Karten sonst gut 190 ms in einem Bild – bei jedem Neuaufbau.
const SOFORT_REIHEN := 4
## So lange blendet eine Reihe unten aus bzw. ein, wenn sie (nicht mehr) ganz Platz hat.
const UNTEN_T := 0.18
## So viel einer Reihe muss unter der gewählten Platz haben, damit sie angeschnitten zu sehen ist.
const ANRISS := 110.0
const ANRISS_A := 0.5

var rows: Array = []              ## { box, shelf, group, items } von oben nach unten
var instant := false              ## Neuaufbau: ohne Bewegung einrasten
var _box: VBoxContainer
var _mem := {}                    ## Reihe (box) → zuletzt gewählte Karte
var _cur := 0
var _last: Control
var _items := {}                  ## Karte → Eintrag (für row_focused)
var _pending := {}                ## Reihe (box) → Karten, die noch nicht in der Reihe stehen
var _draining := false


## top: wo die Reihen beginnen (Unterkante der Bühne).
func setup(top: float) -> Control:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_top = top
	_box = U.vbox(4)
	_box.position = Vector2.ZERO
	add_child(_box)
	_box.size = Vector2(size.x, 0)
	resized.connect(func() -> void:
		if is_instance_valid(_box):
			_box.size.x = size.x
			_unten(_cur, true)
	)
	# Reihen bekommen ihre Höhe erst im Layout (und Karten kommen nach): dann neu entscheiden.
	_box.resized.connect(func() -> void: _unten(_cur, true))
	return self


## Überschrift einer Reihe: wie section_title der Bereiche (Titel fett, leiser Zusatz).
static func titel(text: String, extra := "") -> Control:
	var m := U.margin(GUTTER, 0, GUTTER, 0)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := U.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var l := U.label(text, "l", "text", "bold")
	l.clip_text = false
	row.add_child(l)
	if extra != "":
		var e := U.label(extra, "m", "faint", "medium")
		e.clip_text = false
		e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(e)
	return m


## Eine Reihe anlegen. card_h: Höhe der Karten (die Reihe ist so hoch plus Luft). gap: Abstand
## der Karten. at: an dieser Stelle einfügen (weitere Reihen kommen nach), sonst ans Ende.
## Gibt die Reihe zurück; Karten dann mit add_card hinein.
func add_row(head: String, extra: String, group: String, card_h: float, gap := GAP, at := -1) -> Dictionary:
	var box := U.vbox(0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(titel(head, extra))
	var shelf = Shelf.new().setup("mrow:" + group, gap, true, PAD_TOP, GUTTER, PAD_BOTTOM)
	shelf.custom_minimum_size.y = card_h + PAD_TOP + PAD_BOTTOM
	box.add_child(shelf)
	_box.add_child(box)
	var row := { "box": box, "shelf": shelf, "group": group, "items": [] }
	if at >= 0 and at < rows.size():
		_box.move_child(box, at)
		rows.insert(at, row)
	else:
		rows.append(row)
	return row


## Karte in eine Reihe: Hoch/Runter geht an die Reihen, die Auswahl meldet sich bei der Bühne.
## item: der Eintrag dazu (für row_focused; leer erlaubt).
func add_card(row: Dictionary, card: Control, item: Dictionary = {}) -> Control:
	var box: Control = row.box
	var shelf: ScrollContainer = row.shelf
	var wait: Array = _pending.get(box, [])
	var n: int = shelf.row.get_child_count() + wait.size()
	if n == 0:
		card.set_meta("uz_entry", true)
	var idx := _index_of(box)
	if "lazy" in card and not bild_jetzt(idx, n, _cur, 0):
		card.set("lazy", true)
	card.set("nav_ud_cb", func(d: int) -> bool: return _step_from(box, d))
	_items[card] = item
	card.focus_entered.connect(func() -> void: _on_card(box, card))
	(row.items as Array).append(item)
	if idx >= _cur + SOFORT_REIHEN or not wait.is_empty():
		wait.append(card)
		_pending[box] = wait
		if not _draining:
			_draining = true
			_drain.call_deferred()
	else:
		shelf.add(card)
	return card


## Wartende Karten der Reihe mit box jetzt in die Reihe.
func _fill(box: Control) -> void:
	var wait: Array = _pending.get(box, [])
	if wait.is_empty():
		return
	_pending.erase(box)
	for r in rows:
		if r.box == box:
			for c in wait:
				if is_instance_valid(c):
					(r.shelf as ScrollContainer).call("add", c)
			return


## Alle Karten sofort (etwa um eine gemerkte Karte weit unten wieder zu wählen).
func flush() -> void:
	for r in rows:
		_fill(r.box)


## Je Bild eine Reihe mit wartenden Karten auffüllen, die oberste zuerst.
func _drain() -> void:
	while is_inside_tree() and not _pending.is_empty():
		for r in rows:
			if _pending.has(r.box):
				_fill(r.box)
				break
		await get_tree().process_frame
	_draining = false


func _notification(what: int) -> void:
	# Nie in eine Reihe gekommene Karten mit freigeben (Neuaufbau, bevor alles stand).
	if what == NOTIFICATION_PREDELETE:
		for wait in _pending.values():
			for c in wait:
				if is_instance_valid(c) and c.get_parent() == null:
					c.free()
		_pending.clear()


func row_count() -> int:
	return rows.size()


func current() -> int:
	return _cur


## Steht die Seite nicht mehr oben (tiefere Reihe gewählt)?
func scrolled() -> bool:
	return _cur > 0


func first_card() -> Control:
	for r in rows:
		_fill(r.box)
		var items: Array = (r.shelf as ScrollContainer).row.get_children()
		if not items.is_empty():
			return items[0]
	return null


## Karte, die in Reihe idx gewählt war (sonst die erste).
func card_in(idx: int) -> Control:
	if idx < 0 or idx >= rows.size():
		return null
	_fill(rows[idx].box)
	var m: Variant = _mem.get(rows[idx].box)
	if is_instance_valid(m) and m is Control:
		return m
	var items: Array = (rows[idx].shelf as ScrollContainer).row.get_children()
	return items[0] if not items.is_empty() else null


## Ganz nach oben: alle Reihen am Anfang, keine verdeckt, Gedächtnis leer (Bereich neu betreten).
func reset() -> void:
	_cur = 0
	_last = null
	_mem.clear()
	if not is_instance_valid(_box):
		return
	FederLage.halt(_box)
	for r in rows:
		var b: Control = r.box
		if b.has_meta("uz_skip"):
			b.remove_meta("uz_skip")
		var sh: Variant = r.shelf
		if sh is ScrollContainer and is_instance_valid(sh):
			(sh as ScrollContainer).scroll_horizontal = 0
	_box.position.y = -(rows[0].box as Control).position.y if not rows.is_empty() else 0.0
	_wake(0)
	_unten(0, true)


## Die gewählte Reihe noch einmal einrasten lassen (nach dem Layout eines Neuaufbaus).
func resnap() -> void:
	snap(_cur)


func _on_card(box: Control, card: Control) -> void:
	var dir := 0
	if is_instance_valid(_last) and _last.get_parent() == card.get_parent():
		dir = 1 if card.get_index() > _last.get_index() else -1
	_last = card
	_mem[box] = card
	var idx := _index_of(box)
	snap(idx)
	row_focused.emit(idx, card, _items.get(card, {}), dir)


func _index_of(box: Control) -> int:
	for i in rows.size():
		if rows[i].box == box:
			return i
	return 0


## Hoch/Runter von der Reihe mit box: zur Nachbarreihe, dort zur gemerkten Karte. Oberhalb der
## ersten Reihe false (Nav geht zu den Unterreitern), unter der letzten anstoßen.
func _step_from(box: Control, d: int) -> bool:
	return step(_index_of(box), d)


func step(idx: int, d: int) -> bool:
	var to := idx + d
	if to < 0:
		return false
	if to >= rows.size():
		var c := card_in(idx)
		if c:
			Nav._bump(c, "down")
		return true
	var target := card_in(to)
	if target == null:
		return false
	Nav.focus(target)
	return true


## Reihe idx gleitet an den Kopf; Reihen darüber sind verdeckt und für die Steuerung aus.
func snap(idx: int) -> void:
	if not is_instance_valid(_box) or rows.is_empty():
		return
	idx = clampi(idx, 0, rows.size() - 1)
	_cur = idx
	for i in rows.size():
		var b: Control = rows[i].box
		if i < idx:
			b.set_meta("uz_skip", true)
		elif b.has_meta("uz_skip"):
			b.remove_meta("uz_skip")
	_wake(idx)
	var target := -(rows[idx].box as Control).position.y
	# Feder statt Tween: beim Halten übernimmt jeder Schritt das Tempo des vorigen.
	FederLage.zu(_box, target, instant)
	_unten(idx, instant)


## Reihen unter der gewählten: nur, wenn sie ganz auf den Schirm passen. Eine angeschnittene
## Überschrift am unteren Rand („Neuerscheinungen – Serien“ halb zu sehen) wirkte wie ein Fehler im
## Abstand – in jeder Auflösung anders. Sie blendet weich aus und kommt, sobald sie ganz Platz hat.
func _unten(idx: int, sofort: bool) -> void:
	if not is_instance_valid(_box) or rows.is_empty() or size.y <= 0.0:
		return
	idx = clampi(idx, 0, rows.size() - 1)
	# Lage aus den Mindesthöhen gerechnet, nicht aus position: Beim Aufbau ist die Spalte oft noch
	# nicht einsortiert (alle Reihen stünden bei 0 und passten scheinbar).
	var sep := float(_box.get_theme_constant("separation"))
	var y := 0.0
	for i in rows.size():
		var b: Control = rows[i].box
		var h := b.get_combined_minimum_size().y
		if i == idx:
			y = 0.0
		# Ganz zu sehen: voll da. Nur angeschnitten: leiser, damit die gewählte Reihe vorn bleibt.
		var ziel := 0.0
		if i <= idx or y + h <= size.y + 0.5:
			ziel = 1.0
		elif anriss_sichtbar(y, h, size.y):
			ziel = ANRISS_A
		y += h + sep
		var tw: Variant = b.get_meta("uz_unten_tw") if b.has_meta("uz_unten_tw") else null
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		if sofort or not is_inside_tree():
			b.modulate.a = ziel
		elif not is_equal_approx(b.modulate.a, ziel):
			var t2 := b.create_tween()
			t2.tween_property(b, "modulate:a", ziel, UNTEN_T)
			b.set_meta("uz_unten_tw", t2)


## Is a row (top at y, height h, measured from the selected row) visible within the height hoehe?
## Requiring the whole row to fit often left a third of the screen empty below it. A partial view is enough:
## the heading and a strip of the cards; the rest runs into the fade at the bottom edge (main._hint_fade),
## where the button hints sit.
static func anriss_sichtbar(y: float, h: float, hoehe: float) -> bool:
	return h > 0.0 and y + minf(h, ANRISS) <= hoehe + 0.5


## Soll die Karte k der Reihe r ihr Bild jetzt laden, wenn Reihe cur_r (dort Karte cur_k) gewählt ist?
static func bild_jetzt(r: int, k: int, cur_r: int, cur_k: int) -> bool:
	return r >= cur_r - 1 and r <= cur_r + VORAUS_REIHEN and k <= cur_k + VORAUS_KARTEN


## Karten in der Nähe von Reihe idx ihre Bilder laden lassen (siehe VORAUS_REIHEN).
func _wake(idx: int) -> void:
	for r in range(maxi(0, idx - 1), mini(rows.size(), idx + VORAUS_REIHEN + 1)):
		_fill(rows[r].box)
		var m: Variant = _mem.get(rows[r].box)
		var cur_k: int = (m as Control).get_index() if is_instance_valid(m) and m is Control else 0
		for c in (rows[r].shelf as ScrollContainer).row.get_children():
			if c.get("lazy") == true and bild_jetzt(r, c.get_index(), r, cur_k):
				c.call("wake")


## Welche Reihe liegt unter der Reihe idx verdeckt (für Tests): true, wenn sie für die Steuerung aus ist.
static func hidden_above(cur: int, idx: int) -> bool:
	return idx < cur


# --- Laden -------------------------------------------------------------------------------------

## Platzhalter in der Form der Bühne und der Reihen: Grundzeile, Titel und Zeile unten links,
## darunter n Reihen mit Überschrift und Karten in card-Größe. Alles ein Platzhalter (eine Welle).
static func skeleton(top: float, card: Vector2, n := 2, gap := GAP) -> Control:
	var s = Skeleton.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.anchor_right = 1.0
	s.anchor_bottom = 1.0
	var g := float(GUTTER)
	var y := top - 30.0
	s.shapes = [
		{ "r": Rect2(g, y - 160.0, 220.0, 16.0), "rad": 6, "a": 0.7 },
		{ "r": Rect2(g, y - 126.0, 620.0, 44.0), "rad": 8 },
		{ "r": Rect2(g, y - 64.0, 360.0, 16.0), "rad": 6, "a": 0.7 },
	]
	for i in n:
		var ry := top + i * (card.y + PAD_TOP + PAD_BOTTOM + 40.0)
		(s.shapes as Array).append({ "r": Rect2(g, ry + 8.0, 260.0, 20.0), "rad": 6 })
		for k in 6:
			(s.shapes as Array).append({ "r": Rect2(g + k * (card.x + gap), ry + 40.0 + PAD_TOP, card.x, card.y), "a": 1.0 - k * 0.12 })
	return s
