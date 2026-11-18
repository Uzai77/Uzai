extends HBoxContainer
## Tastenhinweise unten rechts: was A, X, Y und B gerade tun. Ändert sich nur ein Hinweis,
## blendet nur dieser kurz über – die anderen bleiben ruhig stehen. Mit Maus und Touch ist jeder
## Hinweis zugleich die Taste: Klicken bzw. Tippen löst genau das aus (Punkt 64).

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")

var _last := ""
## Eigene Leiste einer Ebene (Guide: unten in der Seitenleiste): zeigt genau dann Hinweise, wenn die
## oberste Ebene sie selbst zeigt (uz_hints_eigen) – die Leiste unten bleibt dann leer.
var inside := false
var gap := 28


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN if inside else BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", gap)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Nav.device_changed.connect(func(_k: String) -> void:
		_last = ""
		refresh(true)
	)
	Nav.focus_moved.connect(func(_c: Control) -> void: refresh())


## Welche Hinweise gerade gelten: [[taste, text], …]. Gezählt wird nur, was zur obersten Ebene
## gehört – hat eine Seitenleiste nichts zum Wählen, zeigt sie nur ihre eigenen Tasten.
## „—“ am gewählten Element (uz_hint_x, uz_hint_y) lässt den Hinweis der Ebene für diese Taste weg:
## Die Zeile tut mit A schon dasselbe (Ordnerwahl: „Diesen Ordner nehmen“).
static func collect() -> Array:
	return _sammeln().filter(func(h: Variant) -> bool: return str(h[1]) != "—")


static func _sammeln() -> Array:
	var hints: Array = []
	# Im Spiel (Ladebildschirm) wirkt nur der Guide – A/X/Y gehörten zum Cover dahinter.
	if Nav.game_mode and Nav.layers.is_empty():
		return [["guide", "Guide"]]
	var f := Nav.active()
	if f:
		var a := str(f.get_meta("uz_hint_a", "Auswählen"))
		if a != "—":
			hints.append(["a", a])
		# Was links/rechts gerade tut, wenn das Element es selbst sagt (Regler beim Einstellen).
		if f.has_meta("uz_hint_lr"):
			hints.append(["lr", str(f.get_meta("uz_hint_lr"))])
		if f.has_meta("uz_hint_x"):
			hints.append(["x", str(f.get_meta("uz_hint_x"))])
		if f.has_meta("uz_hint_y"):
			hints.append(["y", str(f.get_meta("uz_hint_y"))])
	var top := Nav.top_layer()
	if top:
		# Leerer Text: die Ebene nennt B selbst in ihren Hinweisen (eigene Reihenfolge, Dein Zimmer).
		# „—“: B tut auf dieser Ebene nichts (erster Schritt der Einrichtung).
		var hb := str(top.get_meta("uz_hint_b", "Zurück"))
		if f and f.has_meta("uz_hint_b"):
			hb = str(f.get_meta("uz_hint_b"))
		if hb != "" and hb != "—":
			hints.append(["b", hb])
		if top.has_meta("uz_hints"):
			# Was das gewählte Element selbst sagt, gilt; jede Taste nur einmal zeigen.
			for h in top.get_meta("uz_hints"):
				if not hints.any(func(e): return e[0] == h[0]):
					hints.append(h)
	else:
		# Was der Bereich für das gewählte Element dazusagt (Musik › Läuft gerade: LT/RT Lautstärke).
		hints.append_array(_section_hints(Nav.focused()))
		# Im Inhalt und in den Unterbereichen geht B eine Ebene hoch (main._on_command „b“).
		var b := _back_hint(Nav.focused())
		if f and f.has_meta("uz_hint_b") and b != "":
			b = str(f.get_meta("uz_hint_b"))
		# Select öffnet die Freunde (main.open_friends) – nur, wo Platz ist: höchstens vier Hinweise.
		if hints.size() + (1 if b != "" else 0) <= 1 and _friends_on(Nav.focused()):
			hints.append(["view", "Freunde"])
		if b != "":
			hints.append(["b", b])
		# „Guide“ steht dabei, solange die Zeile ruhig bleibt (höchstens vier). Die Taste wirkt immer;
		# in einer vollen Zeile zählt, was das gewählte Element kann.
		if hints.size() < Liste.TASTEN_MAX:
			hints.append(["guide", "Guide"])
	return hints


## Hauptmenü mit der Seitenleiste „Freunde“ auf Select (main.open_friends)?
static func _friends_on(f: Control) -> bool:
	if f == null or not f.is_inside_tree():
		return false
	var m: Node = f.get_tree().current_scene
	return m != null and m.has_method("open_friends") and not Launcher.in_game


static func _section_hints(f: Control) -> Array:
	if f == null or not f.is_inside_tree():
		return []
	var m: Node = f.get_tree().current_scene
	if m == null or not ("sections" in m) or not ("view_host" in m):
		return []
	var vh: Variant = m.get("view_host")
	var secs: Variant = m.get("sections")
	var cur := str(m.get("current"))
	if not (vh is Control and (vh as Control).is_ancestor_of(f)) or not (secs is Dictionary) or not (secs as Dictionary).has(cur):
		return []
	var sec: Object = (secs as Dictionary)[cur]
	if not sec.has_method("extra_hints"):
		return []
	var out: Variant = sec.call("extra_hints", f)
	return out if out is Array else []


static func _back_hint(f: Control) -> String:
	if f == null or not f.is_inside_tree():
		return ""
	var m: Node = f.get_tree().current_scene
	if m == null or not ("view_host" in m) or not ("chips_box" in m):
		return ""
	var vh: Variant = m.get("view_host")
	var cb: Variant = m.get("chips_box")
	if cb is Control and (cb as Control).is_ancestor_of(f):
		return "Nach oben"
	if vh is Control and (vh as Control).is_ancestor_of(f):
		var secs: Variant = m.get("sections")
		var cur := str(m.get("current"))
		if secs is Dictionary and (secs as Dictionary).has(cur) and (secs as Dictionary)[cur].has_method("back_hint"):
			return str((secs as Dictionary)[cur].back_hint())
		return "Nach oben"
	return ""


## Zeigt die oberste Ebene ihre Hinweise selbst (Dein Zimmer: ins Bild gelegt, tasten_ui.gd)? Dann
## bleibt die Leiste leer – collect() gilt trotzdem (Rechtsklick „Optionen“, Zurück-Knopf für Touch).
static func eigene() -> bool:
	var top := Nav.top_layer()
	return top != null and top.has_meta("uz_hints_eigen")


## In der eigenen Leiste und auf jeder Ebene steht B (Schließen, Zurück) immer zuletzt – wie auf
## einer Konsole. Die Bereiche selbst (ohne Ebene) behalten ihre Reihe; „Guide“ steht am Ende, wo
## Platz ist (collect).
func _order(hints: Array) -> Array:
	if not inside and Nav.top_layer() == null:
		return hints
	var b: Array = hints.filter(func(h): return str(h[0]) == "b")
	return hints.filter(func(h): return str(h[0]) != "b") + b


## Ein Hinweis ohne Text gehört zum nächsten: „LB RB Bereich“ statt eines einsamen „LB“. Tun A und
## B dasselbe (Regler beim Einstellen: „Fertig“), stehen sie als ein Hinweis „A B Fertig“.
## Ergebnis: [[[tasten…], text], …]
static func merge(hints: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < hints.size():
		var h: Array = hints[i]
		if str(h[1]) == "" and i + 1 < hints.size():
			var nx: Array = hints[i + 1]
			out.append([[str(h[0]), str(nx[0])], str(nx[1])])
			i += 2
			continue
		out.append([[str(h[0])], str(h[1])])
		i += 1
	var ia := out.find_custom(func(e: Array) -> bool: return e[0] == ["a"])
	var ib := out.find_custom(func(e: Array) -> bool: return e[0] == ["b"])
	if ia >= 0 and ib >= 0 and str(out[ia][1]) == str(out[ib][1]):
		out[ib] = [["a", "b"], str(out[ib][1])]
		out.remove_at(ia)
	return out


func refresh(force := false) -> void:
	var top := Nav.top_layer()
	# Im Guide (und Menüs darin) stehen die Hinweise mittig, wie im Entwurf.
	if not inside:
		alignment = BoxContainer.ALIGNMENT_CENTER if top and top.has_meta("uz_hints_center") else BoxContainer.ALIGNMENT_END
	var items := merge(_order(collect())) if eigene() == inside else []
	# Auf Ebenen eine ruhige Tastenzeile (liste.gd): höchstens vier, B zuletzt. Was darüber hinaus
	# geht, wirkt weiter (LB/RB stehen ohnehin an den Enden der Reiterleisten).
	if top != null:
		items = Liste.tasten_ordnen(items)
	var key := str(items) + Nav.glyph_set()
	if key == _last and not force:
		return
	_last = key
	var old := {}
	for ch in get_children():
		old[str(ch.get_meta("uz_hint_key", ""))] = ch
	var i := 0
	for it in items:
		var cmds: Array = it[0]
		var text: String = it[1]
		var k := ",".join(PackedStringArray(cmds))
		var node: Control = old.get(k) if not force else null
		if node and is_instance_valid(node):
			old.erase(k)
			var lab: Label = node.get_meta("uz_label")
			if is_instance_valid(lab) and lab.text != text:
				lab.text = text
				_fade(lab, 0.25)
		else:
			node = _make(cmds, text)
			add_child(node)
			_fade(node, 0.0)
		move_child(node, i)
		i += 1
	for k in old.keys():
		var n: Node = old[k]
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()


func _make(cmds: Array, text: String) -> Control:
	var h := U.hbox(10)
	for c in cmds:
		h.add_child(U.glyph(str(c), 27))
	var l := U.label(text, "s", "muted", "medium")
	l.clip_text = false
	h.add_child(l)
	h.set_meta("uz_hint_key", ",".join(PackedStringArray(cmds)))
	h.set_meta("uz_label", l)
	if cmds.any(func(c: Variant) -> bool: return not (str(c) in ["ud", "lr"])):
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		h.mouse_entered.connect(func() -> void: _hover(l, true))
		h.mouse_exited.connect(func() -> void: _hover(l, false))
		h.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				h.accept_event()
				tippen(_cmd_at(h, cmds, (e as InputEventMouseButton).position.x))
		)
	return h


## Bei zwei Tasten in einem Hinweis („LB RB Bereich“) zählt die, über der der Zeiger steht.
static func _cmd_at(h: Control, cmds: Array, x: float) -> String:
	var best := str(cmds[0])
	var near := INF
	for i in mini(cmds.size(), h.get_child_count()):
		var g := h.get_child(i) as Control
		var d := absf(g.position.x + g.size.x * 0.5 - x)
		if d < near:
			near = d
			best = str(cmds[i])
	return best


## Ein Hinweis angeklickt bzw. angetippt: dieselbe Taste wie am Controller.
static func tippen(cmd: String) -> void:
	if cmd in ["ud", "lr", ""]:
		return
	Nav._fire(cmd)


func _hover(l: Label, on: bool) -> void:
	l.add_theme_color_override("font_color", UzTheme.col("text" if on else "muted"))


## Hinweis-Tausch im Cursor-Takt (T_ANTWORT). Hält jemand eine Richtung, wechseln die Worte
## ohne Aufblenden – sonst flackerte die Tastenzeile bei jedem Schritt.
func _fade(n: CanvasItem, from: float) -> void:
	if Nav.halten_takt() > 0.0 and from > 0.0:
		U.stop(n, "uz_hint")
		n.modulate.a = 1.0
		return
	n.modulate.a = from
	U.tw(n, "uz_hint").tween_property(n, "modulate:a", 1.0, U.T_ANTWORT)
