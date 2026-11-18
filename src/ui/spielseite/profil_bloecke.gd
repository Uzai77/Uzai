extends RefCounted
## Blöcke des Konsolen-Profils (profile_page.gd, friend_profile.gd): „Deine Woche“ als breite
## Karte mit Zahl und sieben Säulen, die Zahlenzeile (große Zahlen nebeneinander statt Kacheln),
## ein Cover aus der Bibliothek mit zwei Zeilen darunter, Freunde als Kacheln mit Gesicht und
## der Vergleich mit einem Freund (zwei Balken je Zeile). Alles ruhige Flächen der Marke: ein
## Cursor, ein Akzent, Säulen und Balken füllen sich einmal beim Erscheinen (T_RAUM).

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Buehne := preload("res://src/ui/spielseite/buehne.gd")
const BuehneKarte := preload("res://src/ui/spielseite/buehne_karte.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")

const G := 96
const COVER := Vector2(176, 236)
const WOCHE_H := 132.0          ## klein: die Spielzeit ist Beiwerk im Profil, kein Blickfang
const FREUND := Vector2(236, 212)
const SHELF_PAD := 30


## „Deine Woche“: links die Zeit dieser Woche groß, rechts die sieben Tage als Säulen; darunter
## leise, an wie vielen Tagen und wie viel insgesamt. A ruft on_pick (die Seite Spielzeit).
static func woche(sessions: Array, total_secs: int, games_n: int, now: int, bias: int, key: String, on_pick: Callable) -> Control:
	var w := Buehne.woche(sessions, "", now, bias)
	var bits: Array = []
	if int(w.gespielt) > 0:
		bits.append("an %s gespielt" % U.plural(int(w.gespielt), "Tag", "Tagen"))
	else:
		bits.append("diese Woche noch nicht gespielt")
	if total_secs > 0:
		bits.append("%s insgesamt" % Buehne.zeit_kurz(total_secs) + (" in %s" % U.plural(games_n, "Spiel", "Spielen") if games_n > 0 else ""))
	var m := U.margin(G, 0, G, 0)
	var k = BuehneKarte.new().setup_card("clock", "Diese Woche", Buehne.zeit_kurz(int(w.gesamt)), " · ".join(PackedStringArray(bits)),
		Vector2(U.room_w(G), WOCHE_H))
	k.week = w.tage
	k.week_labels = w.labels
	k.set_meta("uz_key", key)
	k.set_meta("uz_hint_a", "Spielzeit")
	if on_pick.is_valid():
		k.chosen.connect(func() -> void: on_pick.call())
	m.add_child(k)
	return m


## Zahlenzeile: große Zahlen nebeneinander, darunter leise, was sie sind – eine wählbare Zeile
## (Cursor der Listen-Sprache), A ruft on_pick. items: [[wert, bezeichnung], …]; „…“ zählt noch.
static func zahlen(items: Array, key: String, hint: String, on_pick: Callable) -> Zahlen:
	var z := Zahlen.new()
	z.items = items
	z.set_meta("uz_key", key)
	z.set_meta("uz_hint_a", hint)
	if on_pick.is_valid():
		z.chosen.connect(func() -> void: on_pick.call())
	return z


## Reihe für Cover (cover_game): Luft fürs Anheben, links bündig mit dem Seitenrand.
static func cover_shelf(group: String) -> ScrollContainer:
	var shelf = Shelf.new().setup(group, 28, true, 22, G)
	shelf.custom_minimum_size.y = COVER.y + 110
	return shelf


## Ein Spiel der Bibliothek (jede Quelle) als Cover mit zwei Zeilen darunter; A ruft on_pick.
static func cover_game(g: Dictionary, line1: String, line2: String, key: String, hint: String, entry: bool, on_pick: Callable) -> Control:
	var v := U.vbox(12)
	var cc = CoverCard.new().setup(g, false, COVER)
	cc.set_meta("uz_key", key)
	cc.set_meta("uz_hint_a", hint)
	if entry:
		cc.set_meta("uz_entry", true)
	cc.chosen.connect(func(_x: Dictionary) -> void: on_pick.call())
	v.add_child(cc)
	var cap := U.vbox(2)
	cap.custom_minimum_size.x = COVER.x
	var t := U.label(Library.display_title(g), "s", "text", "ui_bold")
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.custom_minimum_size.x = COVER.x
	cap.add_child(t)
	if line1 != "":
		cap.add_child(U.label(line1, "16", "muted", "regular"))
	if line2 != "":
		cap.add_child(U.label(line2, "16", "faint", "regular"))
	v.add_child(cap)
	return v


## Ein Freund als Kachel: Gesicht mit Statusring, Name, was er gerade tut. A ruft on_pick.
static func freund(f: Dictionary, key: String, hint: String, on_pick: Callable) -> Control:
	var k := FreundKachel.new()
	k.friend = f
	k.tile_size = FREUND
	k.set_meta("uz_key", key)
	k.set_meta("uz_hint_a", hint)
	if on_pick.is_valid():
		k.chosen.connect(func() -> void: on_pick.call())
	return k


## Vergleich mit einem Freund: je Zeile zwei Balken (du im Akzent, der Freund leise) mit Werten
## rechts. rows: [{ label, a, b, a_text, b_text }] – a, b als Anteile 0…1 (Buehne.anteile).
static func vergleich(rows: Array, names: Array, key: String, hint: String, on_pick: Callable) -> Control:
	var m := U.margin(G, 0, G, 0)
	var v := Vergleich.new()
	v.rows = rows
	v.names = names
	v.tile_size = Vector2(U.room_w(G), 72.0 + rows.size() * 58.0)
	v.set_meta("uz_key", key)
	v.set_meta("uz_hint_a", hint)
	if on_pick.is_valid():
		v.chosen.connect(func() -> void: on_pick.call())
	m.add_child(v)
	return m


## Überschrift einer Reihe wie in allen Bereichen: fett, daneben leiser ein Zusatz.
static func title(text: String, extra := "") -> Control:
	var m := U.margin(G, 0, G, 0)
	var row := U.hbox(14)
	m.add_child(row)
	var l := U.label(text, "l", "text", "bold")
	l.clip_text = false
	row.add_child(l)
	if extra != "":
		var e := U.label(extra, "m", "faint", "medium")
		e.clip_text = false
		row.add_child(e)
	return m


## Zahlenzeile (siehe zahlen()).
class Zahlen extends Control:
	signal chosen
	const UU := preload("res://src/ui/u.gd")
	const ListeC := preload("res://src/ui/components/liste.gd")
	const PAD := 28
	var items: Array = []
	var _werte: Array = []

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		var m := UU.margin(G + PAD, 18, G + PAD, 20)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var row := UU.hbox(72)
		m.add_child(row)
		for it in items:
			var col := UU.vbox(0)
			var w := UU.label(str(it[0]), "xxl", "faint" if str(it[0]) in ["…", "–"] else "text", "black")
			w.clip_text = false
			col.add_child(w)
			_werte.append(w)
			var l := UU.label(str(it[1]), "s", "muted", "medium")
			l.clip_text = false
			col.add_child(l)
			row.add_child(col)
		custom_minimum_size = Vector2(0, m.get_combined_minimum_size().y)
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		focus_entered.connect(func() -> void:
			UU.etikett(self, true)
			queue_redraw())
		focus_exited.connect(func() -> void:
			UU.etikett(self, false)
			queue_redraw())
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event())

	## Eine Zahl nachträglich setzen (Zählung läuft): Text kreuzt im Cursor-Takt.
	func set_wert(i: int, text: String, sub := "") -> void:
		if i < 0 or i >= _werte.size():
			return
		var w: Label = _werte[i]
		w.text = text
		UU.set_label_color(w, "faint" if text in ["…", "–"] else "text")
		w.modulate.a = 0.3
		UU.ankommen(w, UU.T_ANTWORT, "uz_tausch").tween_property(w, "modulate:a", 1.0, UU.T_ANTWORT)
		if sub != "" and w.get_parent().get_child_count() > 1:
			(w.get_parent().get_child(1) as Label).text = sub

	func activate() -> void:
		chosen.emit()

	func _draw() -> void:
		# Der Zeilen-Cursor der Listen-Sprache, mit dem Seitenrand der Seite.
		ListeC.zeilen_auswahl(self, -1, Rect2(Vector2(G, 0), Vector2(size.x - 2 * G, size.y)))


## Freund als Kachel (siehe freund()).
class FreundKachel extends "res://src/ui/components/ach/tile.gd":
	const AvatarC := preload("res://src/ui/components/avatar.gd")
	const ChatViewC := preload("res://src/ui/layers/chat_view.gd")
	var friend: Dictionary = {}

	func build_body() -> void:
		var m := U.margin(20, 22, 20, 18)
		U.full_rect(m)
		body.add_child(m)
		var col := U.vbox(6)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		m.add_child(col)
		var av := AvatarC.new()
		av.setup(str(friend.get("name", "")), str(friend.get("avatar", "")), str(friend.get("state", "")), 92)
		av.ring = true
		av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(av)
		col.add_child(U.spacer(0, 6, false))
		var n := U.label(str(friend.get("name", "")), "m", "text", "ui_bold")
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(n)
		var st := str(friend.get("state", ""))
		var line := ChatViewC.status_line(friend)
		var s := U.label(line, "xs", "ok" if st in ["game", "online"] else "muted", "medium")
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.clip_text = true
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(s)


## Vergleich (siehe vergleich()): Zeilen mit zwei Balken, die sich einmal füllen.
class Vergleich extends "res://src/ui/components/ach/tile.gd":
	var rows: Array = []
	var names: Array = ["Du", ""]
	var _t := 0.0

	func build_body() -> void:
		var m := U.margin(28, 22, 28, 0)
		m.set_anchors_preset(Control.PRESET_TOP_WIDE)
		body.add_child(m)
		var head := U.hbox(12)
		var ic := U.icon("friends", 24, "accent")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ic)
		var l := U.label("Im Vergleich", "s", "muted", "medium")
		l.clip_text = false
		head.add_child(l)
		m.add_child(head)
		if U.reduziert():
			_t = 1.0
			return
		var wr: WeakRef = weakref(self)
		U.ankommen(self, U.T_RAUM, "uz_fill").tween_method(func(v: float) -> void:
			var me: Control = wr.get_ref()
			if me:
				me.set("_t", v)
				me.queue_redraw()
		, 0.0, 1.0, U.T_RAUM).set_delay(U.T_ANTWORT)

	func _draw_extra(r: Rect2, _f: float) -> void:
		var font := UzTheme.font("medium")
		var font_b := UzTheme.font("bold")
		var fs := UzTheme.size("s")
		var fm := UzTheme.size("m")
		var left := r.position.x + 28.0
		var label_w := 220.0
		var val_w := 190.0
		var bar_x := left + label_w
		var bar_w := maxf(80.0, r.size.x - 56.0 - label_w - val_w * 2.0 - 24.0)
		var y := r.position.y + 72.0
		for row in rows:
			var rd: Dictionary = row
			draw_string(font_b, Vector2(left, y + 20.0), tr(str(rd.get("label", ""))), HORIZONTAL_ALIGNMENT_LEFT, label_w - 12.0, fm, UzTheme.col("text"))
			var h := 10.0
			var a := float(rd.get("a", 0.0)) * _t
			var b := float(rd.get("b", 0.0)) * _t
			# Du im Akzent oben, der Freund leise darunter; beide auf derselben Spur.
			_bar(Rect2(bar_x, y + 6.0, bar_w, h), a, UzTheme.col("accent"))
			_bar(Rect2(bar_x, y + 24.0, bar_w, h), b, UzTheme.col("text", 0.34))
			var vx := bar_x + bar_w + 24.0
			draw_string(font, Vector2(vx, y + 14.0), tr(str(names[0])) + "  " + tr(str(rd.get("a_text", ""))), HORIZONTAL_ALIGNMENT_LEFT, val_w * 2.0, fs, UzTheme.col("text"))
			draw_string(font, Vector2(vx, y + 34.0), str(names[1]) + "  " + tr(str(rd.get("b_text", ""))), HORIZONTAL_ALIGNMENT_LEFT, val_w * 2.0, fs, UzTheme.col("muted"))
			y += 58.0

	func _bar(track: Rect2, v: float, col: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UzTheme.col("text", 0.08)
		sb.set_corner_radius_all(int(track.size.y * 0.5))
		sb.anti_aliasing = true
		draw_style_box(sb, track)
		if v > 0.001:
			var fill := StyleBoxFlat.new()
			fill.bg_color = col
			fill.set_corner_radius_all(int(track.size.y * 0.5))
			fill.anti_aliasing = true
			draw_style_box(fill, Rect2(track.position, Vector2(maxf(track.size.y, track.size.x * clampf(v, 0.0, 1.0)), track.size.y)))
