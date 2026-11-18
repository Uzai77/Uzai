extends Control
## Ein Spiel im Shop, wie im Konsolen-Store: Bild mit runden Ecken und weichem Schatten, darunter
## der Name und eine Preiszeile (Preis, alter Preis durchgestrichen – oder „In deiner Bibliothek“,
## „Gratis bis 30. Okt.“, „Bald erhältlich“). Ein Rabatt steht klein oben links auf dem Bild, kein
## Glas-Schild mit Preis mehr. Steht das Spiel auf deiner Wunschliste, sitzt oben rechts ein
## kleines Herz. Gewählt hebt sich die Karte und trägt den Kachel-Cursor der Marke (feine
## Lichtkante, Akzent-Schein). Bis das Bild da ist (oder wenn es keins gibt), zeigt die Karte
## einen Verlauf in der Farbe des Spiels mit dem Namen.
## Das Bild kommt unter seinem echten Namen aus dem Store (neue Spiele: Ordner mit Prüfsumme);
## gibt es nur ein Querformat-Bild, wird es nicht verzerrt (siehe shop_pic.gd). Gratis-Spiele
## von Epic haben keine Steam-ID: Sie bringen ihre Bildadressen selbst mit.

signal chosen(item: Dictionary)

const U := preload("res://src/ui/u.gd")
const ShopArt := preload("res://src/ui/components/shop_art.gd")
const ShopPic := preload("res://src/ui/components/shop_pic.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")

var item: Dictionary = {}
var big := false
var card_w := 340.0
var show_wish := true             ## Herz für „auf der Wunschliste“ (nicht auf der Wunschliste selbst)
var portrait := true              ## Hochformat wie eine Spielhülle (Erweiterungen: quer)
var owned := false                ## schon da, auch wenn Store.owned_item es nicht weiß (installierte Erweiterungen)
var _frame: Panel
var _img: Control
var _art: Control                 ## Ersatzbild mit Titel; der Titel geht aus, sobald das Bild deckt
var _im_bau := false              ## Bild kommt noch im Aufbau (aus dem Speicher): steht sofort
## So lange gewählt, dann holt die Karte das große Bild ihrer Seite vorab (nicht beim Blättern).
const HERO_VORAB := 0.35
var _over: Control
var _ring: Control
var _owned := false


func setup(it: Dictionary, w := 340.0, is_big := false) -> Control:
	item = it
	card_w = w
	big = is_big
	return self


## Hochformat wie eine Spielhülle (Steams 600 × 900); quer im Format des Kapselbilds.
func img_h() -> float:
	return roundf(card_w * (1.5 if portrait else 353.0 / 616.0))


## Gesamthöhe einer Karte (für Regale, die ihre Höhe vorher kennen müssen).
static func height_for(w: float, tall := true, is_big := false) -> float:
	return roundf(w * (1.5 if tall else 353.0 / 616.0)) + (96 if is_big else 84)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Lichtstreif nur, wo das Theme ihn will (Graphit: focus.shine = false).
	if UzTheme.focus_shine():
		set_meta("uz_shiny", true)
	custom_minimum_size = Vector2(card_w, img_h() + (96 if big else 84))
	var appid := int(item.get("appid", 0))
	set_meta("uz_key", "shop:" + (str(item.id) if str(item.get("id", "")) != "" else str(appid)))
	set_meta("uz_flug", flug_key(item))
	_owned = owned or Store.owned_item(item)
	var ih := img_h()
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	U.clip_round(_frame, CanvasItem.CLIP_CHILDREN_AND_DRAW)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size = Vector2(card_w, ih)
	add_child(_frame)
	# Ohne Steam-ID bekommt der Verlauf seinen Farbton aus der eigenen Kennung.
	var art := ShopArt.new().setup(appid if appid > 0 else absi(hash(str(item.get("id", item.get("name", ""))))) % 1000000, str(item.get("name", "")))
	U.full_rect(art)
	_frame.add_child(art)
	_art = art
	_img = ShopPic.new()
	_img.set("box", Vector2(card_w, ih))
	U.full_rect(_img)
	_img.modulate.a = 0.0
	_frame.add_child(_img)
	_over = _Over.new()
	_over.card = self
	U.full_rect(_over)
	_frame.add_child(_over)
	_ring = _Ring.new()
	_ring.card = self
	_ring.size = Vector2(card_w, ih)
	add_child(_ring)
	var wself: WeakRef = weakref(self)
	var max_w := int(card_w * 1.25)
	var it := item
	var tall := portrait
	var on_tex := func(t: Texture2D) -> void:
		var me2: Control = wself.get_ref()
		if me2:
			me2.call("_set_tex", t)
	_im_bau = true
	if appid <= 0:
		Media.url_texture_chain(Store.art_urls_from(it, {}, tall, int(max_w * Media.px_scale())), max_w, on_tex)
	else:
		# Erst die echten Bildnamen (meist schon vorab geholt), dann das erste Bild, das kommt.
		Media.with_steam_assets(appid, func(a: Dictionary) -> void:
			if wself.get_ref() == null:
				return
			var urls := Store.art_urls_from(it, a if not a.is_empty() else Store.art_assets(it), tall, int(max_w * Media.px_scale()))
			Media.url_texture_chain(urls, max_w, on_tex)
		)
	_im_bau = false
	focus_entered.connect(func() -> void:
		U.focus_anim(self, true)
		_drift(true)
		_hero_vorab()
	)
	focus_exited.connect(func() -> void:
		U.focus_anim(self, false)
		_drift(false)
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)
	Store.wishlist_changed.connect(_on_wish)


var _drift_tw: Tween


## Das Bild steht still, auch gewählt. (Früher rückte es langsam heran wie eine Kamerafahrt – das
## wirkte wie ein dauerndes Zoomen; gewählt wächst nur die Karte selbst ein wenig.)
func _drift(_on: bool) -> void:
	if not is_instance_valid(_img):
		return
	if _drift_tw and _drift_tw.is_valid():
		_drift_tw.kill()
	if _img.scale != Vector2.ONE:
		_img.pivot_offset = _img.size * 0.5
		_drift_tw = create_tween()
		_drift_tw.tween_property(_img, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)


func _exit_tree() -> void:
	if Store.wishlist_changed.is_connected(_on_wish):
		Store.wishlist_changed.disconnect(_on_wish)


func _on_wish(appid: int, on: bool) -> void:
	if appid != int(item.get("appid", 0)):
		return
	if is_instance_valid(_over):
		_over.queue_redraw()
	# Y auf der Karte (Shop): der Hinweis sagt, was der nächste Druck tut.
	if has_meta("uz_wunsch_taste") and has_meta("uz_on_y"):
		set_meta("uz_hint_y", "Von der Wunschliste" if on else "Wunschliste")
		if has_focus() and is_inside_tree():
			var m: Node = get_tree().current_scene
			if m and m.get("hint_bar") is Control:
				(m.get("hint_bar") as Control).call("refresh")


## Y auf der Karte setzt das Spiel mit einem Druck auf die Wunschliste bzw. nimmt es herunter
## (cb bekommt den Eintrag). Nur für Steam-Spiele, die nicht in der Bibliothek sind.
func wunsch_taste(cb: Callable) -> void:
	var appid := int(item.get("appid", 0))
	if appid <= 0 or _owned or owned or Store.owned_item(item):
		return
	set_meta("uz_wunsch_taste", true)
	set_meta("uz_hint_y", "Von der Wunschliste" if Store.wishlisted(appid) else "Wunschliste")
	var it := item
	set_meta("uz_on_y", func() -> void: cb.call(it))


## Die Preiszeile unter dem Namen: { text, alt (durchgestrichen), farbe }. Ohne bekannten Preis
## steht die Zeile der Karte (Angebot endet, bald erhältlich) – nie ein erfundenes „Kostenlos“.
static func preis_zeile(it: Dictionary, is_owned: bool) -> Dictionary:
	if is_owned:
		return { "text": "In deiner Bibliothek", "alt": "", "farbe": "ok" }
	if it.get("giveaway", false):
		var alt := Store.price_text(int(it.get("original", 0))) if int(it.get("original", 0)) > 0 else ""
		return { "text": giveaway_when(it) + (" · Epic" if str(it.get("store", "")) == "epic" else ""), "alt": alt, "farbe": "sale" }
	if it.get("free", false):
		return { "text": "Kostenlos", "alt": "", "farbe": "text" }
	if int(it.get("price", 0)) > 0:
		var disc := int(it.get("discount", 0))
		var alt2 := Store.price_text(int(it.get("original", 0))) if disc > 0 and int(it.get("original", 0)) > int(it.price) else ""
		return { "text": Store.price_label(it), "alt": alt2, "farbe": "text" }
	var line := status_line(it, false)
	return { "text": line, "alt": "", "farbe": "muted" }


func _set_tex(t: Texture2D) -> void:
	if not is_instance_valid(_img) or t == null:
		return
	_img.set("texture", t)
	# Wie bei Covern: Ein Bild aus dem Speicher steht sofort (sonst blendete jede Karte bei jedem
	# Wechsel neu ein, und darunter schien der Titel des Ersatzbilds durch – Geister-Titel); ein
	# Bild aus dem Netz kommt in T_ORT. Deckt es, geht der Titel darunter aus.
	if _im_bau:
		U.stop(_img, "uz_bild")
		_img.modulate.a = 1.0
		_bild_deckt()
		return
	var tw := U.ankommen(_img, U.T_ORT, "uz_bild")
	tw.tween_property(_img, "modulate:a", 1.0, U.T_ORT)
	tw.tween_callback(_bild_deckt)


## Das Bild deckt die Karte: der Titel des Ersatzbilds darunter geht aus (schiene sonst durch,
## solange die Karte oder ihre Reihe halb durchsichtig ist).
func _bild_deckt() -> void:
	if is_instance_valid(_art) and is_instance_valid(_img) and _img.modulate.a >= 0.99 and bool(_art.get("show_title")):
		_art.set("show_title", false)
		_art.queue_redraw()


## Bleibt die Karte kurz gewählt, liegt das große Bild der Shop-Seite schon bereit (wie die
## Startseite es für Spiele tut): Die Seite hat es beim Öffnen sofort und kommt nicht erst dunkel.
func _hero_vorab() -> void:
	var appid := int(item.get("appid", 0))
	if appid <= 0 or not is_inside_tree():
		return
	await get_tree().create_timer(HERO_VORAB).timeout
	if not is_instance_valid(self) or not has_focus():
		return
	var it := item
	Media.with_steam_assets(appid, func(a: Dictionary) -> void:
		var urls := Store.hero_urls(appid, a if not a.is_empty() else Store.art_assets(it), int(1920 * Media.px_scale()))
		if not urls.is_empty():
			Media.url_texture(str(urls[0]), 1920, func(_t: Texture2D) -> void: pass)
	)


func activate() -> void:
	chosen.emit(item)


## Schlüssel für geteilte Elemente (src/ui/flug.gd): Karte und Shop-Seite desselben Spiels.
static func flug_key(it: Dictionary) -> String:
	return "shop:" + (str(it.id) if str(it.get("id", "")) != "" else str(int(it.get("appid", 0))))


## Geteilte Elemente: das Bild der Karte (randvoll wie ShopArt.draw_art, sonst ganz eingepasst).
## Solange es fliegt, ist nur das Bild verborgen (hide) – Ring, Preis und Name bleiben stehen.
func flug_bild() -> Dictionary:
	var d := pic_bild(_img)
	if not d.is_empty():
		d["hide"] = _img
	return d


## Was ein ShopPic zeigt, für flug.gd (auch die Hülle der Shop-Seite).
static func pic_bild(pic: Control) -> Dictionary:
	if pic == null or not is_instance_valid(pic):
		return {}
	var t: Texture2D = pic.get("texture")
	if t == null:
		return {}
	var area: Vector2 = pic.call("area")
	var d := { "node": pic, "tex": t, "tint": Zuschnitt.tone_of(t), "radius": UzTheme.r_cover() }
	if bool(pic.call("fitted")):
		d["fit"] = true
	else:
		var src := ShopArt.cover_src(t.get_size(), area)
		if t.has_meta("uz_look"):
			src = Zuschnitt.window(t.get_meta("uz_look"), t.get_size(), src.size)
		d["src"] = src
	return d


func _f() -> float:
	return float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0


## Die kleine Zeile unter dem Namen.
static func status_line(it: Dictionary, is_owned: bool) -> String:
	if is_owned:
		return "In deiner Bibliothek"
	var until := int(it.get("until", 0))
	var left := until - int(Time.get_unix_time_from_system())
	if it.get("giveaway", false):
		return giveaway_when(it) + (" · Epic" if str(it.get("store", "")) == "epic" else "")
	if int(it.get("discount", 0)) > 0 and Store.sale_new.has(int(it.get("appid", 0))):
		return "Neu im Angebot" + ((" · bis %s" % day_text(until)) if until > 0 and left > 0 else "")
	if until > 0 and int(it.get("discount", 0)) > 0 and left > 0:
		return ("Angebot endet in %d Std." % maxi(1, int(left / 3600.0))) if left < 86400 * 2 else ("Angebot bis " + U.date(until))
	if it.get("coming", false):
		return "Bald erhältlich"
	# Nur bei echtem is_free – Preis 0 heißt oft nur „Steam hat keinen Preis mitgeschickt“.
	if it.get("free", false):
		return "Kostenlos spielbar"
	return ""


## Wann eine Gratis-Aktion gilt: „Gratis bis 30. Okt.“, „Gratis noch 5 Std.“, „Ab 30. Okt. gratis“.
static func giveaway_when(it: Dictionary) -> String:
	if it.get("upcoming", false):
		return "Ab %s gratis" % day_text(int(it.get("from", 0)))
	var until := int(it.get("until", 0))
	var left := until - int(Time.get_unix_time_from_system())
	if until > 0 and left > 0 and left < 86400:
		return "Gratis noch %d Std." % maxi(1, int(left / 3600.0))
	return "Gratis bis %s" % day_text(until) if until > 0 else "Gratis"


## „30. Okt.“ (Ortszeit, in der Sprache von Uzai).
static func day_text(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_date_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return U.Lang.date_text(int(d.day), int(d.month), 0, true)


func _draw() -> void:
	var f := _f()
	var lift := -10.0 * f
	_frame.position.y = lift
	_ring.position.y = lift
	_frame.scale = Vector2.ONE * (1.0 + 0.025 * f)
	_frame.pivot_offset = _frame.size * Vector2(0.5, 1.0)
	_ring.scale = _frame.scale
	_ring.pivot_offset = _frame.pivot_offset
	_over.queue_redraw()
	_ring.queue_redraw()
	var ih := img_h()
	# Schatten unter dem Bild (wächst mit der Auswahl)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.set_corner_radius_all(UzTheme.r_cover())
	sh.shadow_color = Color(0, 0, 0, 0.35 + 0.25 * f)
	sh.shadow_size = int(14 + 18 * f)
	sh.shadow_offset = Vector2(0, 10 + 8 * f)
	draw_style_box(sh, Rect2(4, lift + 6, card_w - 8, ih - 8))
	var bold := UzTheme.font("bold")
	var med := UzTheme.font("medium")
	var y := ih + 30
	var name_fs := 21 if big else 18
	# Der Name eines Spiels wird nie übersetzt (kein tr()).
	draw_string(bold, Vector2(2, y), _fit_name(str(item.get("name", "")), card_w - 4, bold, name_fs), HORIZONTAL_ALIGNMENT_LEFT, card_w - 4, name_fs,
			UzTheme.col("text"), TextServer.JUSTIFICATION_NONE)
	y += 27
	# Preiszeile: Preis (oder Zustand), daneben der alte Preis durchgestrichen.
	var pz := preis_zeile(item, _owned)
	var text := str(pz.text)
	if text == "":
		return
	var fs2 := 17 if big else 16
	var col := UzTheme.col(str(pz.farbe))
	# „Neu im Angebot“ auf der Wunschliste: die Zeile sagt es in der Bedeutungsfarbe.
	if str(pz.farbe) == "text" and int(item.get("discount", 0)) > 0 and Store.sale_new.has(int(item.get("appid", 0))):
		col = UzTheme.col("sale")
	var tf := bold if str(pz.farbe) == "text" else med
	draw_string(tf, Vector2(2, y), tr(text), HORIZONTAL_ALIGNMENT_LEFT, card_w - 4, fs2, col)
	var alt := str(pz.alt)
	if alt != "":
		var tx := tf.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x + 12.0
		var aw := med.get_string_size(tr(alt), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if tx + aw <= card_w - 4:
			var ac := UzTheme.col("muted")
			draw_string(med, Vector2(2 + tx, y), tr(alt), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ac)
			draw_line(Vector2(2 + tx, y - 5), Vector2(2 + tx + aw, y - 5), ac, 1.4)


## Langer Name: mit „…“ gekürzt statt hart abgeschnitten (einmal gerechnet, nicht je Bild).
var _fit_key := ""
var _fit_txt := ""


func _fit_name(t: String, w: float, f: Font, fs: int) -> String:
	var key := "%s|%d|%d" % [t, int(w), fs]
	if key != _fit_key:
		_fit_key = key
		_fit_txt = t
		if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
			var out := t
			while out.length() > 1 and f.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
				out = out.substr(0, out.length() - 1)
			_fit_txt = out.strip_edges() + "…"
	return _fit_txt


## Auf dem Bild: ein kleines Rabatt-Schild unten links, das Herz der Wunschliste oben rechts,
## Lichtstreif. Preis und Zustand stehen unter dem Bild (preis_zeile).
class _Over extends Control:
	var card

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var it: Dictionary = card.item
		# Rabatt nur mit echtem Preis (Gratis-Aktionen sagen es in der Zeile darunter).
		var disc := int(it.get("discount", 0)) if int(it.get("price", 0)) > 0 and not it.get("free", false) else 0
		if not card._owned and disc > 0:
			var bold := UzTheme.font("bold")
			var fs := 16 if not card.big else 18
			var dt := "−%d %%" % disc
			var dw := bold.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			# Unten links: oben links steht auf dem Ersatzbild der Name, oben rechts das Herz.
			var h := 30.0 if not card.big else 34.0
			var pr := Rect2(12, r.size.y - h - 12, dw + 22, h)
			draw_style_box(UzTheme.box(Color(0.04, 0.045, 0.06, 0.78), int(h * 0.5)), pr)
			draw_string(bold, Vector2(pr.position.x + 11, pr.position.y + h * 0.5 + fs * 0.36), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("sale"))
		if card.show_wish and not card._owned and Store.wishlisted(int(it.get("appid", 0))):
			var c := Vector2(r.size.x - 26, 26)
			draw_circle(c, 17, Color(0.04, 0.045, 0.06, 0.78))
			draw_texture_rect(Icons.tex("heart_f", 20), Rect2(c - Vector2(10, 9.5), Vector2(20, 20)), false, UzTheme.col("text"))
		_shine()

	func _shine() -> void:
		var c: Control = card
		if c.has_meta("uz_shine") and UzTheme.focus_shine():
			set_meta("uz_shine", c.get_meta("uz_shine"))
			U.draw_shine(self, Rect2(Vector2.ZERO, size))


## Der Kachel-Cursor der Marke über dem Bild (außerhalb der Bildmaske, damit der Schein zu sehen ist).
class _Ring extends Control:
	var card

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f: float = card._f()
		UzTheme.draw_tile_focus(self, Rect2(Vector2.ZERO, size), UzTheme.r_cover(), minf(f, 1.0))
