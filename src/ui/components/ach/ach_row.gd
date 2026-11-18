extends Control
## Ein Erfolg in der Liste eines Spiels: Abzeichen, Name und Beschreibung, rechts Seltenheit
## und wann er kam (oder Punkte). Gewählt: helle Fläche, Schrift wird dunkel.
## Mit Freunden (friends_on) steht rechts unter der Seltenheit der Satz dazu: „Nur du“ in Gold,
## „Du und Mira“, bei offenen „Mira hat das gestern freigeschaltet“.

signal activated

const Ach := preload("res://src/core/achievements.gd")
const Friends := preload("res://src/core/achievements_friends.gd")
const U := preload("res://src/ui/u.gd")
const Emblem := preload("res://src/ui/components/ach/emblem.gd")
const Rarity := preload("res://src/ui/components/ach/rarity.gd")
const Liste := preload("res://src/ui/components/liste.gd")

var a: Dictionary = {}
var friend := ""             ## Vergleich mit einem Freund: sein Name (leer = kein Vergleich)
var friend_has := false
var friends_on := false      ## Freunde-Stand liegt vor: Satz, wer ihn hat
var friends_have: Array = [] ## Namen der Freunde, die ihn haben (neueste zuerst)
var friend_when := 0         ## wann ihn zuletzt ein Freund freigeschaltet hat (Unix, 0: nie)
var fresh := false           ## in den letzten 24 Stunden freigeschaltet
var _emblem: Control
var _desc: Label
var _secret := ""            ## Beschreibung eines geheimen Erfolgs (A deckt sie auf)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var on: bool = a.get("unlocked", false)
	var pct := float(a.get("rarity", -1.0))
	var tier := Ach.rarity_tier(pct)
	var m := U.margin(16, 14, 26, 14)
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(24)
	m.add_child(row)
	_emblem = Emblem.new().setup(str(a.get("icon", "")) if on else str(a.get("icon_locked", a.get("icon", ""))), on, tier, 84)
	_emblem.set("secret", not on and (a.get("hidden", false) or str(a.get("desc", "")) == "Geheimer Erfolg"))
	row.add_child(_emblem)
	var col := U.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var secret: bool = a.get("hidden", false) or str(a.get("desc", "")) == "Geheimer Erfolg"
	# Name und Beschreibung kommen von Steam bzw. RetroAchievements schon in der eingestellten Sprache.
	var tl := U.ellipsis(U.label(str(a.get("title", "")), "m", "text", "ui_bold"))
	tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(tl)
	_secret = str(a.get("secret", "")) if secret and not on else ""
	var desc := str(a.get("desc", ""))
	if secret and not on:
		desc = "Geheimer Erfolg – die Beschreibung ist verborgen." if _secret != "" else "Geheimer Erfolg – die Beschreibung zeigt sich, sobald du ihn hast."
	_desc = U.label(desc, "s", "muted", "regular", true)
	if not (secret and not on):
		_desc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_desc.max_lines_visible = 2
	_desc.custom_minimum_size = Vector2(420, 0)
	col.add_child(_desc)
	if not has_meta("uz_hint_a"):
		set_meta("uz_hint_a", "Aufdecken" if _secret != "" else "—")
	var right := U.vbox(4)
	right.custom_minimum_size = Vector2(260, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	if friends_on:
		if tier >= 0:
			right.add_child(_end(Rarity.tag(pct, "s")))
		var only_me := on and friends_have.is_empty()
		var txt := Friends.who_text(friends_have, on, Friends.when_text(friend_when) if not on else "")
		if txt == "":
			txt = "Noch offen"
		var line := U.hbox(10)
		line.alignment = BoxContainer.ALIGNMENT_END
		if fresh:
			line.add_child(_pill("Neu"))
		# Namen kommen von Steam bzw. RetroAchievements; der Satz drumherum ist ein Muster (i18n).
		var wl := U.label(txt, "s", "gold" if only_me else ("muted" if on else "faint"), "medium")
		wl.clip_text = false
		line.add_child(wl)
		right.add_child(line)
	elif friend != "":
		right.add_child(_who("Du", on))
		right.add_child(_who(friend.left(14), friend_has))
	else:
		if tier >= 0:
			right.add_child(_end(Rarity.tag(pct, "s")))
		var bits := PackedStringArray()
		if on:
			bits.append(Rarity.when(int(a.get("date", 0))))
			if a.get("hardcore", false):
				bits.append("Hardcore")
		elif tier < 0:
			bits.append("Noch offen")
		if int(a.get("points", 0)) > 0:
			bits.append("%d Punkte" % int(a.points))
		var s := PackedStringArray(Array(bits).filter(func(x): return str(x) != ""))
		if not s.is_empty() or fresh:
			var line := U.hbox(10)
			line.alignment = BoxContainer.ALIGNMENT_END
			if fresh:
				line.add_child(_pill("Neu"))
			if not s.is_empty():
				var l := U.label("  ·  ".join(s), "s", "faint" if not on else "muted", "medium")
				l.clip_text = false
				line.add_child(l)
			right.add_child(line)
	custom_minimum_size.y = maxf(112.0, m.get_combined_minimum_size().y)
	focus_entered.connect(func() -> void:
		U.etikett(self, true)
		queue_redraw()
	)
	focus_exited.connect(func() -> void:
		U.etikett(self, false)
		queue_redraw()
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## Rechtsbündig in der rechten Spalte.
func _end(c: Control) -> Control:
	var h := U.hbox(0)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(c)
	return h


## Im Vergleich: „✓ Du“ bzw. „– Mira“.
func _who(name_: String, has: bool) -> Control:
	var h := U.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_END
	var l := U.label(name_, "s", "text" if has else "faint", "medium")
	l.clip_text = false
	h.add_child(l)
	h.add_child(U.icon("check" if has else "minus", 22, "accent" if has else "faint"))
	return h


func _pill(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("accent"), 999)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := U.label(text, "xs", "on_accent", "ui_bold")
	l.clip_text = false
	p.add_child(l)
	return p


## Frisch freigeschaltet: das Abzeichen glimmt einmal auf.
func celebrate(delay := 0.25) -> void:
	if _emblem == null:
		return
	var em := _emblem
	var base: float = em.get("glow")
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(em):
			em.call("set_glow", maxf(base, sin(v * PI)))
	, 0.0, 1.0, 1.3).set_trans(Tween.TRANS_SINE)


func activate() -> void:
	if _secret != "" and is_instance_valid(_desc):
		# Geheimen Erfolg aufdecken: die Beschreibung blendet weich um.
		var text := _secret
		_secret = ""
		set_meta("uz_hint_a", "—")
		var d := _desc
		var tw := U.tw(d, "uz_reveal")
		tw.tween_property(d, "modulate:a", 0.0, U.T_FAST)
		tw.tween_callback(func() -> void:
			if is_instance_valid(d):
				d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # jetzt der Text von Steam
				d.text = text
		)
		tw.tween_property(d, "modulate:a", 1.0, U.T_BASE)
		Nav.focus_moved.emit(self)
	activated.emit()


func _draw() -> void:
	Liste.zeilen_auswahl(self)
