extends Control
## Eine Zeile im Freunde-Feed: wer (Profilbild), was (Abzeichen, Name des Erfolgs), wann und in
## welchem Spiel; rechts die Seltenheit bzw. die RA-Punkte. Gewählt wie jede Zeile (Liste.cursor),
## A öffnet die Erfolge des Spiels mit dem Freunde-Stand.

signal chosen

const Ach := preload("res://src/core/achievements.gd")
const U := preload("res://src/ui/u.gd")
const Emblem := preload("res://src/ui/components/ach/emblem.gd")
const Rarity := preload("res://src/ui/components/ach/rarity.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const Liste := preload("res://src/ui/components/liste.gd")

var e: Dictionary = {}        ## Eintrag aus Achievements.friends.feed()


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pct := float(e.get("rarity", -1.0))
	var tier := Ach.rarity_tier(pct)
	var m := U.margin(16, 12, 26, 12)
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(20)
	m.add_child(row)
	var av := Avatar.new()
	av.setup(str(e.get("friend", "")), str(e.get("avatar", "")), "", 52)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	row.add_child(Emblem.new().setup(str(e.get("icon", "")), true, tier, 76))
	var col := U.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var when := Rarity.when(int(e.get("date", 0)))
	var head := U.hbox(8)
	var who := U.label(str(e.get("friend", "")), "s", "text", "ui_bold")
	who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	who.clip_text = false
	head.add_child(who)
	var bits := PackedStringArray()
	if when != "":
		# Die Zeile übersetzt sich nicht selbst (der Spielname ist fremder Text): die Zeit darum hier.
		bits.append(str(TranslationServer.translate(when)))
	if str(e.get("game", "")) != "":
		bits.append(str(e.game))
	if not bits.is_empty():
		var rest := U.ellipsis(U.label("·  " + "  ·  ".join(bits), "s", "muted", "medium"))
		rest.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		head.add_child(rest)
	col.add_child(head)
	var tl := U.ellipsis(U.label(str(e.get("title", "")), "m", "text", "ui_bold"))
	tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(tl)
	var right := U.vbox(4)
	right.custom_minimum_size = Vector2(240, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	if tier >= 0:
		var h := U.hbox(0)
		h.alignment = BoxContainer.ALIGNMENT_END
		h.add_child(Rarity.tag(pct, "s"))
		right.add_child(h)
	else:
		var parts := PackedStringArray()
		if int(e.get("points", 0)) > 0:
			parts.append("%d Punkte" % int(e.points))
		if bool(e.get("hardcore", false)):
			parts.append("Hardcore")
		if not parts.is_empty():
			var l := U.label("  ·  ".join(parts), "s", "muted", "medium")
			l.clip_text = false
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(l)
	custom_minimum_size.y = maxf(104.0, m.get_combined_minimum_size().y)
	set_meta("uz_hint_a", "Erfolge des Spiels")
	focus_entered.connect(func() -> void:
		U.etikett(self, true)
		queue_redraw()
	)
	focus_exited.connect(func() -> void:
		U.etikett(self, false)
		queue_redraw()
	)
	gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if has_focus():
				Nav.activate(self)
			else:
				grab_focus()
			accept_event()
	)


func activate() -> void:
	chosen.emit()


func _draw() -> void:
	Liste.zeilen_auswahl(self)
