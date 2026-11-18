extends "res://src/ui/layers/layer.gd"
## Spieleseite im Shop, untere Schicht: die gezeichneten Teile der Seite – Hülle, Punkte, Preis-
## Strich, Karten, Trailer und Bilder mit Vollbild, Leser für lange Texte, Bezahlen und Auswahl.
## store_game.gd erbt davon; andere Ebenen nutzen einzelne Teile (etwa den Leser).

const ShopCard := preload("res://src/ui/components/shop_card.gd")
const Liste := preload("res://src/ui/components/liste.gd")


# --- Bausteine ------------------------------------------------------------------------------------

## Farbiger Punkt (Bewertung).
## Die Hülle im Kopf: Bild mit runden Ecken und weichem Schatten (wie die Shop-Karte).
class _Huelle extends Control:
	var pic: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_tex(t: Texture2D) -> void:
		if not is_instance_valid(pic):
			return
		var had: bool = pic.get("texture") != null
		pic.set("texture", t)
		if had or not is_inside_tree():
			pic.modulate.a = 1.0
		else:
			create_tween().tween_property(pic, "modulate:a", 1.0, 0.25)

	## Geteilte Elemente: was die Hülle zeigt (flug.gd) …
	func flug_bild() -> Dictionary:
		return ShopCard.pic_bild(pic)

	## … und das Bild, das von der Karte herfliegt – es ist schon geladen, die Hülle nimmt es gleich.
	func flug_bild_da(t: Texture2D) -> void:
		if is_instance_valid(pic) and pic.get("texture") == null and t:
			set_tex(t)

	func _draw() -> void:
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0)
		sh.set_corner_radius_all(UzTheme.r_cover())
		sh.shadow_color = Color(0, 0, 0, 0.42)
		sh.shadow_size = 20
		sh.shadow_offset = Vector2(0, 12)
		draw_style_box(sh, Rect2(4, 6, size.x - 8, size.y - 8))


class _Dot extends Control:
	var color := Color.WHITE

	func _ready() -> void:
		custom_minimum_size = Vector2(12, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, 5.5, color)


## Alter Preis, durchgestrichen.
class _Strike extends Control:
	var text := ""
	var px := 21

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var f := UzTheme.font("medium")
		custom_minimum_size = f.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, px) + Vector2(2, 6)

	func _draw() -> void:
		var f := UzTheme.font("medium")
		var y := size.y * 0.5 + px * 0.34
		var col := UzTheme.col("muted")
		draw_string(f, Vector2(0, y + 1), tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.35))
		draw_string(f, Vector2(0, y), tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		var w := f.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_line(Vector2(0, y - px * 0.32), Vector2(w, y - px * 0.32), col, 1.6)


## Eine Kachel mit Inhalt (Bewertung, Neuigkeit, Edition, Anforderungen): Glasfläche, gewählt
## mit Ring und leicht angehoben.
class _Card extends Control:
	signal chosen
	const UU := preload("res://src/ui/u.gd")
	var body: VBoxContainer
	var _m: MarginContainer

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		_m = UU.margin(28, 24, 28, 24)
		UU.full_rect(_m)
		add_child(_m)
		body = UU.vbox(12)
		_m.add_child(body)

	func _ready() -> void:
		focus_entered.connect(func() -> void: UU.focus_anim(self, true))
		focus_exited.connect(func() -> void: UU.focus_anim(self, false))
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func activate() -> void:
		chosen.emit()

	func _draw() -> void:
		var f := float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0
		var lift := -10.0 * f
		_m.offset_top = lift
		_m.offset_bottom = lift
		var r := Rect2(Vector2(0, lift), size)
		var rad := UzTheme.r_panel()
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0)
		sh.set_corner_radius_all(rad)
		sh.shadow_color = Color(0, 0, 0, 0.22 + 0.25 * f)
		sh.shadow_size = int(10 + 16 * f)
		sh.shadow_offset = Vector2(0, 8 + 6 * f)
		draw_style_box(sh, r)
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.055 + 0.03 * f), rad, 1, UzTheme.col("stroke")), r)
		if f > 0.01:
			draw_style_box(UzTheme.focus_ring(minf(f, 1.0), rad), r)


## Trailer oder Bild (16:9) mit runden Ecken, Schatten, Ring und Lichtstreif. Trailer haben
## einen Abspielknopf und ihren Namen.
class _Media extends Control:
	signal chosen
	const UU := preload("res://src/ui/u.gd")
	const ArtC := preload("res://src/ui/components/shop_art.gd")
	const ShineC := preload("res://src/ui/components/shine.gd")
	const W := 448.0
	const H := 252.0
	var appid := 0
	var urls: Array = []
	var trailer := false
	var caption := ""
	var _frame: Panel
	var _img: TextureRect
	var _shine: Control
	var _small: Texture2D

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(W, H)
		_frame = Panel.new()
		_frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
		_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.size = Vector2(W, H)
		add_child(_frame)
		var art := ArtC.new().setup(appid, "", false)
		UU.full_rect(art)
		_frame.add_child(art)
		_img = TextureRect.new()
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UU.full_rect(_img)
		_img.modulate.a = 0.0
		_frame.add_child(_img)
		if trailer:
			var over := _PlayOver.new()
			over.caption = caption
			UU.full_rect(over)
			_frame.add_child(over)
		_shine = ShineC.new()
		_frame.add_child(_shine)
		_fetch(0)
		focus_entered.connect(func() -> void:
			UU.focus_anim(self, true)
			_shine.call("play")
		)
		focus_exited.connect(func() -> void: UU.focus_anim(self, false))
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	## Erstes brauchbares Bild; ein kleines Vorschaubild nur, wenn sonst nichts kommt.
	func _fetch(i: int) -> void:
		if i >= urls.size():
			if _small:
				_show(_small)
			return
		var w: WeakRef = weakref(self)
		Media.url_texture(str(urls[i]), 900, func(t: Texture2D) -> void:
			var me: Control = w.get_ref()
			if me == null:
				return
			if t and (t.get_width() >= 420 or i + 1 >= me.get("urls").size()):
				me.call("_show", t)
				return
			if t:
				me.set("_small", t)
			me.call("_fetch", i + 1)
		)

	func _show(t: Texture2D) -> void:
		if not is_instance_valid(_img):
			return
		_img.texture = t
		create_tween().tween_property(_img, "modulate:a", 1.0, 0.25)

	func activate() -> void:
		chosen.emit()

	func _draw() -> void:
		var f := float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0
		_frame.position.y = -10.0 * f
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0)
		sh.set_corner_radius_all(UzTheme.r_cover())
		sh.shadow_color = Color(0, 0, 0, 0.35 + 0.2 * f)
		sh.shadow_size = int(14 + 14 * f)
		sh.shadow_offset = Vector2(0, 10)
		draw_style_box(sh, Rect2(Vector2(4, 6 - 10.0 * f), size - Vector2(8, 8)))
		if f > 0.01:
			draw_set_transform(Vector2(0, -10.0 * f))
			draw_style_box(UzTheme.focus_ring(minf(f, 1.0), UzTheme.r_cover()), Rect2(Vector2.ZERO, size))
			draw_set_transform(Vector2.ZERO)


## Abspielknopf und Name über einem Trailer.
class _PlayOver extends Control:
	const UU := preload("res://src/ui/u.gd")
	var caption := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_texture_rect(UU.fade_texture(true, true), Rect2(0, size.y * 0.45, size.x, size.y * 0.55), false, Color(0, 0, 0, 0.62))
		var c := size * 0.5 - Vector2(0, 8)
		draw_circle(c, 36, Color(0.04, 0.045, 0.06, 0.62))
		draw_texture_rect(Icons.tex("play", 30), Rect2(c - Vector2(13, 15), Vector2(30, 30)), false, Color.WHITE)
		var f := UzTheme.font("bold")
		draw_string(f, Vector2(20, size.y - 20), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 40, 19, Color(1, 1, 1, 0.95))      # Name des Trailers


## Bilder groß, LB/RB oder links/rechts blättern.
class _Viewer extends "res://src/ui/layers/layer.gd":
	var urls: Array = []
	var idx := 0
	var _img: TextureRect
	var _count: Label
	var _pad: Control

	func build() -> void:
		dim = 0.96
		_scrim.color = Color(0, 0, 0, dim)
		set_meta("uz_hint_b", "Zurück")
		set_meta("uz_hints", [["lb", ""], ["rb", "Blättern"]])
		_img = TextureRect.new()
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		U.full_rect(_img)
		_img.offset_left = 80
		_img.offset_right = -80
		_img.offset_top = 60
		_img.offset_bottom = -110
		add_child(_img)
		_count = U.label("", "m", "muted", "medium")
		_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # nur Zahlen
		_count.position = Vector2(96, 1000)
		add_child(_count)
		_pad = _StepPad.new()
		_pad.set("target", self)
		_pad.focus_mode = Control.FOCUS_ALL
		_pad.custom_minimum_size = Vector2(1, 1)
		_pad.set_meta("uz_hint_a", "—")
		add_child(_pad)
		_show(idx)

	func _first_focus() -> Control:
		return _pad

	func _show(i: int) -> void:
		if urls.is_empty():
			return
		idx = posmod(i, urls.size())
		_count.text = "%d / %d" % [idx + 1, urls.size()]
		var url := str(urls[idx])
		var w: WeakRef = weakref(self)
		Media.url_texture(url, 1920, func(t: Texture2D) -> void:
			var me: Node = w.get_ref()
			if me and t and str(me.get("urls")[me.get("idx")]) == url:
				me.call("_put", t)
		)

	func step(d: int) -> void:
		_show(idx + d)
		Sfx.play("tick")

	func _put(t: Texture2D) -> void:
		_img.texture = t
		_img.modulate.a = 0.3
		create_tween().tween_property(_img, "modulate:a", 1.0, 0.25)

	func handle(cmd: String) -> bool:
		match cmd:
			"lb":
				step(-1)
				return true
			"rb":
				step(1)
				return true
		return false


## Unsichtbares Steuerelement im Bildbetrachter: links/rechts blättert.
class _StepPad extends Control:
	var target: Node

	func nav_lr(d: int) -> bool:
		target.call("step", d)
		return true

	func nav_ud(_d: int) -> bool:
		return true


## Zum Lesen: Text in einer ruhigen Spalte, ↑/↓ blättert, LB/RB seitenweise.
class _Reader extends "res://src/ui/layers/layer.gd":
	var heading := ""
	var sub := ""
	var heading_raw := false       ## Überschrift ist ein Name oder fremder Titel (Spiel, Neuigkeit): nie übersetzen
	var paragraphs: Array = []     ## Text oder [Bezeichnung, Wert]
	var _sc: ScrollContainer
	var _pad: Control

	func build() -> void:
		dim = 0.9
		_scrim.color = Color(UzTheme.col("bg"), dim)
		set_meta("uz_hint_b", "Zurück")
		set_meta("uz_hints", [["lb", ""], ["rb", "Seitenweise"]])
		var panel := PanelContainer.new()
		var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
		sb.content_margin_left = 64
		sb.content_margin_right = 64
		sb.content_margin_top = 52
		sb.content_margin_bottom = 44
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 40
		panel.add_theme_stylebox_override("panel", sb)
		panel.anchor_left = 0.5
		panel.anchor_right = 0.5
		panel.anchor_bottom = 1.0
		panel.offset_left = -620
		panel.offset_right = 620
		panel.offset_top = 64
		panel.offset_bottom = -116
		add_child(panel)
		var col := U.vbox(14)
		panel.add_child(col)
		var h := U.label(heading, "xl", "text", "bold", true)
		if heading_raw:
			h.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		h.max_lines_visible = 2
		col.add_child(h)
		if sub != "":
			col.add_child(U.label(sub, "m", "muted", "medium", true))
		col.add_child(U.spacer(0, 8, false))
		_sc = ScrollContainer.new()
		_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_sc.follow_focus = false
		col.add_child(_sc)
		var body := U.vbox(16)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sc.add_child(body)
		for p in paragraphs:
			if p is Array:
				var r := U.hbox(18)
				if str(p[0]) != "":
					var k := U.label(str(p[0]), "m", "faint", "medium")
					k.custom_minimum_size = Vector2(240, 0)
					r.add_child(k)
				var v := U.label(str(p[1]), "m", "text" if str(p[0]) != "" else "muted", "medium", true)
				v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				r.add_child(v)
				body.add_child(r)
			elif str(p).strip_edges() != "":
				var t := U.label(str(p).strip_edges(), "m", "text", "regular", true)
				# Ganze Absätze sind fremder Text (Beschreibung, Bewertung, Neuigkeit): nie durch die Übersetzung –
				# sie suchte in jedem langen Absatz nach Bruchstücken und ersetzte, was zufällig passte.
				t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				t.add_theme_constant_override("line_spacing", 6)
				t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				body.add_child(t)
		body.add_child(U.spacer(0, 30, false))
		_pad = _ReaderPad.new()
		_pad.set("reader", self)
		_pad.focus_mode = Control.FOCUS_ALL
		_pad.custom_minimum_size = Vector2(1, 1)
		_pad.set_meta("uz_hint_a", "—")
		add_child(_pad)

	func _first_focus() -> Control:
		return _pad

	## Weich weiterblättern; am Ende ein kurzer Anschlag.
	func scroll_by(dy: float) -> void:
		var maxv := maxf(0.0, _sc.get_v_scroll_bar().max_value - _sc.size.y)
		var target := clampf(float(_sc.scroll_vertical) + dy, 0.0, maxv)
		if absf(target - float(_sc.scroll_vertical)) < 1.0:
			Sfx.play("bump")
			return
		Sfx.play("move")
		U.tw(_sc, "uz_read").tween_property(_sc, "scroll_vertical", int(target), U.T_MOVE)

	func handle(cmd: String) -> bool:
		match cmd:
			"lb":
				scroll_by(-_sc.size.y * 0.85)
				return true
			"rb":
				scroll_by(_sc.size.y * 0.85)
				return true
		return false


class _ReaderPad extends Control:
	var reader: Node

	func nav_ud(d: int) -> bool:
		reader.call("scroll_by", d * 150.0)
		return true

	func nav_lr(_d: int) -> bool:
		return true


## Kaufen bestätigen: Edition wählen, Preis sehen, dann „Bei Steam bezahlen“.
class _Checkout extends "res://src/ui/layers/modal.gd":
	signal confirmed(edition: Dictionary)
	const ArtC := preload("res://src/ui/components/shop_art.gd")
	var item: Dictionary = {}
	var details: Dictionary = {}
	var editions: Array = []
	var pick := 0
	var price := 0
	var original := 0
	var discount := 0
	var cart := false
	var _rows: Array = []
	var _total: HBoxContainer

	func _init() -> void:
		super()
		width = 900.0

	func fill() -> void:
		set_meta("uz_hint_b", "Abbrechen")
		var appid := int(item.get("appid", 0))
		var head := U.hbox(26)
		box.add_child(head)
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(300, 140)
		frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
		frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(frame)
		var art := ArtC.new().setup(appid, str(item.get("name", "")))
		art.title_px = 22
		U.full_rect(art)
		frame.add_child(art)
		var img := TextureRect.new()
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		U.full_rect(img)
		frame.add_child(img)
		var wi: WeakRef = weakref(img)
		Media.url_texture(str(item.get("header", "")), 400, func(t: Texture2D) -> void:
			var ir: TextureRect = wi.get_ref()
			if ir and t:
				ir.texture = t
		)
		var tv := U.vbox(6)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		head.add_child(tv)
		var name_l := U.label(str(item.get("name", "")), "xl", "text", "bold", true)
		name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels
		name_l.max_lines_visible = 2
		tv.add_child(name_l)
		var by := str(details.get("developer", ""))
		if by != "":
			var by_l := U.ellipsis(U.label(by, "m", "muted", "medium"))
			by_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Entwicklers
			tv.add_child(by_l)
		box.add_child(U.spacer(0, 6, false))
		if editions.size() > 1:
			box.add_child(U.label("Edition", "s", "faint", "medium"))
			var list := U.vbox(8)
			list.set_meta("uz_group", "co:eds")
			box.add_child(list)
			for i in editions.size():
				var ed: Dictionary = editions[i]
				var row := _Choice.new()
				row.title = str(ed.get("name", ""))
				row.price = Store.price_text(int(ed.get("price", 0)))
				row.selected = i == pick
				row.set_meta("uz_hint_a", "Auswählen")
				var idx := i
				row.chosen.connect(func() -> void: _select(idx))
				list.add_child(row)
				_rows.append(row)
		_total = U.hbox(14)
		box.add_child(_total)
		_fill_total()
		var line := ColorRect.new()
		line.color = UzTheme.col("stroke")
		line.custom_minimum_size = Vector2(0, 1)
		box.add_child(line)
		var how := "Das Spiel kommt in den Steam-Warenkorb. Bezahlt wird bei Steam." if cart \
			else "Steam öffnet die Seite des Spiels. Dort „In den Warenkorb“ wählen und bezahlen."
		var hl := U.label(how, "m", "text", "regular", true)
		hl.custom_minimum_size = Vector2(width - 96, 0)
		box.add_child(hl)
		box.add_child(U.spacer(0, 4, false))
		var buttons := U.hbox(14)
		box.add_child(buttons)
		var pay := U.button("Bei Steam bezahlen", "shop", "primary")
		pay.set_meta("uz_default", true)
		pay.pressed.connect(func() -> void:
			var ed: Dictionary = editions[pick] if pick < editions.size() else {}
			close()
			confirmed.emit(ed)
		)
		buttons.add_child(pay)
		var cancel := U.button("Abbrechen")
		cancel.pressed.connect(close)
		buttons.add_child(cancel)

	func _first_focus() -> Control:
		return Nav.default_in(self)

	func _select(i: int) -> void:
		pick = i
		for k in _rows.size():
			(_rows[k] as Control).call("set_selected", k == i)
		_fill_total()

	func _fill_total() -> void:
		U.clear(_total)
		var p := price
		var o := original
		var dsc := discount
		if pick < editions.size():
			var ed: Dictionary = editions[pick]
			p = int(ed.get("price", p))
			o = int(ed.get("original", p))
			dsc = int(ed.get("discount", 0))
		var lab := U.label("Preis", "m", "muted", "medium")
		lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_total.add_child(lab)
		if dsc > 0 and o > p:
			var tag := U.panel("sale", 10, 0)
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var tm := U.margin(10, 2, 10, 3)
			var tl := U.label("−%d %%" % dsc, "s", "text", "bold")
			tl.add_theme_color_override("font_color", UzTheme.text_on(UzTheme.col("sale")))
			tm.add_child(tl)
			tag.add_child(tm)
			_total.add_child(tag)
			var old := U.label(Store.price_text(o), "m", "faint", "medium")
			old.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_total.add_child(old)
		var pl := U.label(Store.price_text(p) if p > 0 else "–", "xl", "text", "black")
		pl.clip_text = false
		_total.add_child(pl)


## Eine Zeile zur Auswahl (Edition) mit Haken und Preis.
class _Choice extends Control:
	signal chosen
	const UU := preload("res://src/ui/u.gd")
	var title := ""
	var price := ""
	var selected := false
	var _check: TextureRect

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 64)
		var m := UU.margin(18, 0, 22, 0)
		UU.full_rect(m)
		add_child(m)
		var row := UU.hbox(14)
		m.add_child(row)
		# Der Haken hat immer seinen Platz, damit die Namen untereinander stehen.
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(24, 24)
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot)
		_check = UU.icon("check", 24, "accent")
		_check.visible = selected
		slot.add_child(_check)
		var t := UU.ellipsis(UU.label(title, "m", "text", "medium"))
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name der Edition
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
		var p := UU.label(price, "m", "text", "bold")
		p.clip_text = false
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(p)
		focus_entered.connect(func() -> void: UU.etikett(self, true))
		focus_exited.connect(func() -> void: UU.etikett(self, false))

	func activate() -> void:
		chosen.emit()

	func set_selected(on: bool) -> void:
		selected = on
		if is_instance_valid(_check):
			_check.visible = on
		queue_redraw()

	func _draw() -> void:
		# Marke: gerundetes Feld mit Haarlinie (gewählt etwas heller), der Cursor wie in jeder Liste.
		if UzTheme.strict():
			UzTheme.draw_hairline(self, Rect2(Vector2.ZERO, size), 16, UzTheme.col("text", 0.06) if selected else Color(0, 0, 0, 0))
		else:
			draw_style_box(UzTheme.box(UzTheme.col("text", 0.1 if selected else 0.045), 16), Rect2(Vector2.ZERO, size))
		Liste.zeilen_auswahl(self, 16)


## Das Bild läuft nach unten und links in den Raum aus; dazu ein Lichtschein in seiner Farbe.
class _Shade extends Control:
	const UU := preload("res://src/ui/u.gd")
	const ArtC := preload("res://src/ui/components/shop_art.gd")
	var tint := Color(0, 0, 0, 0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var bg := UzTheme.col("bg")
		draw_rect(Rect2(Vector2.ZERO, size), Color(bg, 0.22))
		draw_texture_rect(UU.fade_texture(true, true), Rect2(0, size.y * 0.28, size.x, size.y * 0.72), false, bg)
		draw_texture_rect(UU.fade_texture(false), Rect2(0, 0, size.x * 0.62, size.y), false, Color(bg, 0.78))
		if tint.a > 0.0:
			draw_texture_rect(ArtC.glow(), Rect2(-420, size.y * 0.35, 1500, 900), false, Color(tint, tint.a * 0.2))
			draw_texture_rect(ArtC.glow(), Rect2(size.x - 760, 60, 900, 760), false, Color(tint, tint.a * 0.14))
