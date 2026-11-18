extends "res://src/ui/layers/store_game_teile.gd"
## Ein Spiel im Shop, wie eine Shopseite auf der Konsole: oben groß das Bild des Spiels mit
## Schriftzug, Bewertung, Preis und „Kaufen“. Darunter Trailer und Bilder, Über das Spiel,
## Editionen, Erweiterungen, Bewertungen, Neuigkeiten und Systemanforderungen.
##
## Alles läuft in Uzai: Trailer spielt der eigene Videoplayer, die Wunschliste ändert Uzai über
## dein Steam-Konto, und „Kaufen“ legt das Spiel in deinen Steam-Warenkorb. Nur das Bezahlen
## selbst geht nicht ohne Steam (dafür gibt es keine Schnittstelle): Uzai fragt vorher mit Preis
## nach und öffnet erst ganz zum Schluss den Warenkorb im Steam-Client.
##
## Die gezeichneten Teile (Hülle, Karten, Trailer, Leser, Bezahlen) stehen in store_game_teile.gd,
## von dem diese Ebene erbt.

const Shelf := preload("res://src/ui/components/shelf.gd")
const ShopArt := preload("res://src/ui/components/shop_art.gd")
const ShopPic := preload("res://src/ui/components/shop_pic.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const Reihen := preload("res://src/core/store_reihen.gd")
const Lang := preload("res://src/core/lang.gd")
const Storage := preload("res://src/core/storage.gd")
const StorageFlow := preload("res://src/ui/storage_flow.gd")
const BrowserDaten := preload("res://src/core/browser_daten.gd")
const GUTTER := 96
const HUELLE_W := 270.0           ## Hülle rechts im Kopf (wie auf der Spielseite)
const KEY_REQ := ["Betriebssystem", "Prozessor", "Arbeitsspeicher", "Grafik", "Speicherplatz", "DirectX"]

var item: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var view: Node                    ## der Shop-Bereich (spielt Trailer und öffnet die Seite danach wieder)
var start_focus := ""             ## "media": nach einem Trailer gleich wieder bei Trailer und Bildern

var _d: Dictionary = {}           ## Angaben aus dem Store (appdetails)
var _rv: Dictionary = {}          ## Bewertungen (Zusammenfassung)
var _appid := 0
var _art: Control
var _hero: TextureRect
var _shade: Control
var _logo: TextureRect
var _title: Label
var _meta: HBoxContainer
var _people: HBoxContainer        ## Freunde, die das Spiel gerade spielen (Gesichter und Satz)
var _price: HBoxContainer
var _buttons: HBoxContainer
var _wish: Button
var _col: VBoxContainer
var _slots := {}
var _media_first: Control
var _mode := ""
var _buttons_sig := ""
var _hero_in := 0.0
var _hero_par := 1.0
var _hero_failed := false
var _wish_busy := false
var _huelle: Control              ## Ziel des Bilds, das von der Shop-Karte herfliegt (flug.gd)
var _sc: ScrollContainer          ## Bildlauf mit Titel, Knöpfen und Abschnitten (Schrift der Seite)
var _im_bau := false              ## Bilder kommen noch im Aufbau (aus dem Speicher): stehen sofort


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), 1.0)
	_appid = int(item.get("appid", 0))
	set_meta("uz_flug", ShopCard.flug_key(item))
	set_meta("uz_hint_b", "Zurück")
	if not Store.owned(_appid):
		set_meta("uz_hints", [["y", "Wunschliste"]])
	# Oben das Bild des Spiels; bis es da ist, ein Verlauf in der Farbe des Spiels.
	_art = ShopArt.new().setup(_appid, "", false)
	_art.anchor_right = 1.0
	_art.offset_bottom = 760
	_art.modulate.a = 0.85
	add_child(_art)
	_hero = TextureRect.new()
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.anchor_right = 1.0
	_hero.offset_bottom = 760
	_hero.modulate.a = 0.0
	add_child(_hero)
	_shade = _Shade.new()
	_shade.anchor_right = 1.0
	_shade.offset_bottom = 830
	add_child(_shade)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 220.0)
	U.full_rect(sc)
	add_child(sc)
	_sc = sc
	# Das Bild wandert beim Blättern halb so schnell mit (Tiefe) und blendet aus.
	sc.get_v_scroll_bar().value_changed.connect(_on_scroll)
	_col = U.vbox(44)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_col)
	_col.add_child(U.spacer(0, 150, false))
	_build_head()
	for key in ["media", "about", "editions", "dlc", "reviews", "news", "req"]:
		var slot := U.vbox(0)
		_col.add_child(slot)
		_slots[key] = slot
	_col.add_child(_foot())
	# Die Wunschliste kann noch laden, wenn die Seite aufgeht: Herz dann nachziehen.
	Store.updated.connect(_on_store_updated)
	Social.updated.connect(_on_social)
	# Bilder aus dem Speicher (vorab geholt) stehen sofort: Die Seite trägt sie herein.
	_im_bau = true
	_load_art()
	_im_bau = false
	_load()


## Seite (layer.gd): Sie selbst ist die deckende Fläche, der Bildlauf mit Titel und Knöpfen ihre
## Schrift – der Grund kommt beim Öffnen zuerst, die Schrift danach (nie Titel über Titel).
func flaeche() -> Control:
	return self


func schrift() -> Array:
	return [_sc] if is_instance_valid(_sc) else []


func _on_store_updated() -> void:
	if not _wish_busy:
		_wish_look(Store.wishlisted(_appid))


func _on_social(what: String) -> void:
	if what == "steam" and is_instance_valid(_people):
		_fill_people()


## Geteilte Elemente: Das Bild der Shop-Karte landet auf der Hülle im Kopf.
func flug_ziel() -> Control:
	return _huelle


func _first_focus() -> Control:
	if start_focus == "media" and is_instance_valid(_media_first):
		return _media_first
	return Nav.default_in(_buttons)


func _on_scroll(v: float) -> void:
	var y := -v * 0.5
	for n in [_art, _hero, _shade]:
		(n as Control).position.y = y
	_hero_par = clampf(1.0 - v / 900.0, 0.0, 1.0)
	_hero.modulate.a = _hero_in * _hero_par
	_art.modulate.a = 0.85 * _hero_par


# --- Bilder oben ------------------------------------------------------------------------------

## Großes Bild und Schriftzug unter ihren echten Namen aus dem Store (neue Spiele haben dafür
## Ordner mit Prüfsumme; die alten festen Adressen gibt es dort nicht).
func _load_art() -> void:
	var w: WeakRef = weakref(self)
	Media.with_steam_assets(_appid, func(a: Dictionary) -> void:
		var me: Node = w.get_ref()
		if me == null:
			return
		var aa: Dictionary = a if not a.is_empty() else Store.art_assets(item)
		me.call("_hero_from", Store.hero_urls(_appid, aa, int(1920 * Media.px_scale())), true)
		Media.url_texture_chain(Store.logo_urls(_appid, aa), 1000, func(t: Texture2D) -> void:
			var me2: Node = w.get_ref()
			if me2 and t:
				me2.call("_set_logo", t)
		)
	)


## Erstes Bild aus der Liste, das lädt. first: das große Bild; schlägt es fehl, kommen die
## Ersatzbilder dran, sobald die Angaben da sind.
func _hero_from(urls: Array, first := false) -> void:
	if urls.is_empty():
		if first:
			_hero_failed = true
			_hero_fallback()
		return
	var w: WeakRef = weakref(self)
	Media.url_texture(str(urls[0]), 1920, func(t: Texture2D) -> void:
		var me: Node = w.get_ref()
		if me == null:
			return
		if t:
			me.call("_set_hero", t)
		else:
			me.call("_hero_from", urls.slice(1), first)
	)


func _hero_fallback() -> void:
	if not _hero_failed or _d.is_empty() or _hero.texture != null:
		return
	var urls: Array = []
	var shots: Array = _d.get("screens", [])
	if not shots.is_empty():
		urls.append(shots[0])
	for u in [str(_d.get("background", "")), str(item.get("capsule", "")), str(item.get("header", ""))]:
		if u != "":
			urls.append(u)
	_hero_from(urls)


func _set_hero(t: Texture2D) -> void:
	if not is_instance_valid(_hero):
		return
	_hero.texture = t
	_hero.pivot_offset = Vector2(960, 0)
	# Steht still: das frühere langsame Heranfahren (12 s) ruckelte sichtbar.
	_hero.scale = Vector2.ONE
	if _im_bau:
		_hero_in = 1.0
		_hero.modulate.a = _hero_par
	else:
		U.ankommen(_hero, U.T_ORT, "uz_hero").tween_method(func(a: float) -> void:
			_hero_in = a
			if is_instance_valid(_hero):
				_hero.modulate.a = _hero_in * _hero_par
		, _hero_in, 1.0, U.T_ORT)
	# Lichtschein in der Farbe des Bildes hinter dem Titel.
	var c: Variant = Media.color_of(t)
	var col: Color = c if c is Color else ShopArt.tint_of(_appid)
	var sh: Control = _shade
	create_tween().tween_method(func(a: float) -> void:
		if is_instance_valid(sh):
			sh.set("tint", Color(col, a))
			sh.queue_redraw()
	, 0.0, 1.0, U.T_LICHT).set_trans(Tween.TRANS_SINE)


func _set_logo(t: Texture2D) -> void:
	if not is_instance_valid(_logo) or t.get_width() < 8 or t.get_height() < 8:
		return
	# Größe nach dem Seitenverhältnis: höchstens 640 × 180, links unten bündig.
	var ratio := float(t.get_width()) / float(t.get_height())
	var h := minf(180.0, 640.0 / ratio)
	_logo.custom_minimum_size = Vector2(roundf(h * ratio), roundf(h))
	_logo.texture = t
	_logo.visible = true
	_title.visible = false
	if _im_bau:
		_logo.modulate.a = 1.0
		return
	_logo.modulate.a = 0.0
	U.ankommen(_logo, U.T_ORT, "uz_logo").tween_property(_logo, "modulate:a", 1.0, U.T_ORT)


# --- Kopf: Titel, Angaben, Preis, Knöpfe ---------------------------------------------------------

func _build_head() -> void:
	var m := U.margin(GUTTER, 0, GUTTER, 0)
	var hb := U.hbox(40)
	m.add_child(hb)
	var v := U.vbox(16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_END
	hb.add_child(v)
	hb.add_child(_build_huelle())
	_col.add_child(m)
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.visible = false
	v.add_child(_logo)
	_title = U.shadow(U.label(str(item.get("name", "")), "hero", "text", "title", true), 0.5)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels
	# Höchstens so breit, dass Titel und Hülle nebeneinander passen (auch mit größerer Oberfläche).
	_title.custom_minimum_size = Vector2(minf(1150.0, U.view_size().x - GUTTER * 2.0 - 40.0 - HUELLE_W), 0)
	_title.max_lines_visible = 2
	v.add_child(_title)
	_meta = U.hbox(12)
	v.add_child(_meta)
	_fill_meta()
	_people = U.hbox(10)
	v.add_child(_people)
	_fill_people()
	v.add_child(U.spacer(0, 2, false))
	_price = U.hbox(16)
	v.add_child(_price)
	_fill_price()
	v.add_child(U.spacer(0, 4, false))
	_buttons = U.hbox(14)
	_buttons.set_meta("uz_group", "sg:buttons")
	v.add_child(_buttons)
	_fill_buttons()


## Rechts im Kopf die Hülle des Spiels, wie auf der Spielseite. Beim Öffnen aus dem Shop fliegt
## das Bild der Karte hierher (flug.gd) und bleibt: dasselbe, schon geladene Bild.
func _build_huelle() -> Control:
	var h := _Huelle.new()
	var sz := Vector2(HUELLE_W, roundf(HUELLE_W * 1.5))
	h.custom_minimum_size = sz
	h.size_flags_vertical = Control.SIZE_SHRINK_END
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	U.clip_round(frame, CanvasItem.CLIP_CHILDREN_AND_DRAW)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(frame)
	h.add_child(frame)
	var art := ShopArt.new().setup(_appid if _appid > 0 else absi(hash(str(item.get("id", item.get("name", ""))))) % 1000000, str(item.get("name", "")))
	U.full_rect(art)
	frame.add_child(art)
	var pic := ShopPic.new()
	pic.set("box", sz)
	U.full_rect(pic)
	pic.modulate.a = 0.0
	frame.add_child(pic)
	h.pic = pic
	_huelle = h
	var wh: WeakRef = weakref(h)
	var max_w := int(HUELLE_W * 1.25)
	var it := item
	var on_tex := func(t: Texture2D) -> void:
		var me: Control = wh.get_ref()
		if me and t:
			me.call("set_tex", t)
	if _appid <= 0:
		Media.url_texture_chain(Store.art_urls_from(it, {}, true, int(max_w * Media.px_scale())), max_w, on_tex)
	else:
		Media.with_steam_assets(_appid, func(a: Dictionary) -> void:
			if wh.get_ref() == null:
				return
			Media.url_texture_chain(Store.art_urls_from(it, a if not a.is_empty() else Store.art_assets(it), true, int(max_w * Media.px_scale())), max_w, on_tex)
		)
	return h


## Kleine Zeile unter dem Titel: Bewertung, Genres, Jahr – oder solange nichts da ist, was die
## Karte im Shop schon wusste (Angebot endet, bald erhältlich). Leer bleibt sie unsichtbar.
func _fill_meta() -> void:
	U.clear(_meta)
	if int(_rv.get("total", 0)) > 0:
		var pill := U.panel("glass_hi", 999, 0)
		var pm := U.margin(14, 5, 16, 6)
		var ph := U.hbox(10)
		pm.add_child(ph)
		pill.add_child(pm)
		var dot := _Dot.new()
		dot.color = UzTheme.col(_review_color(int(_rv.percent)))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.add_child(dot)
		ph.add_child(U.label("%s · %d %%" % [str(_rv.label), int(_rv.percent)], "s", "text", "bold"))
		_meta.add_child(pill)
	var parts := PackedStringArray()
	var full: Dictionary = _d.get("fullgame", {})
	if str(_d.get("type", "")) == "dlc" and str(full.get("name", "")) != "":
		parts.append("Erweiterung für " + str(full.name))
	var gen := PackedStringArray()
	for g in _d.get("genres", PackedStringArray()):
		# „Kostenlos spielbar“ steht schon groß beim Preis.
		if not str(g).to_lower() in ["kostenlos spielbar", "free to play"]:
			gen.append(str(g))
	if not gen.is_empty():
		parts.append(" · ".join(gen.slice(0, 3)))
	var year := _year(str(_d.get("release", "")))
	if year != "" and not _d.get("coming", false):
		parts.append(year)
	if parts.is_empty():
		var line := ShopCard.status_line(item, false) if not Store.owned(_appid) else ""
		if line != "":
			parts.append(line)
	if not parts.is_empty():
		var l := U.shadow(U.label("   ·   ".join(parts), "m", "text", "medium"), 0.4)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_meta.add_child(l)
	_meta.visible = _meta.get_child_count() > 0


## Freunde, die das Spiel gerade spielen: ihre Gesichter und ein Satz („Mira und Noor spielen
## gerade“). Leer bleibt die Zeile unsichtbar.
func _fill_people() -> void:
	U.clear(_people)
	var people: Array = Social.playing(_appid)
	_people.visible = not people.is_empty()
	if people.is_empty():
		return
	var avs := U.hbox(-8)
	avs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for f in people.slice(0, 5):
		avs.add_child(Avatar.new().setup(str(f.get("name", "")), str(f.get("avatar", "")), "", 34))
	_people.add_child(avs)
	var namen: Array = people.map(func(f: Dictionary) -> String: return str(f.get("name", "")))
	var l := U.shadow(U.label(Reihen.freunde_text(namen), "m", "text", "medium"), 0.4)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # schon übersetzt (store_reihen)
	l.clip_text = false
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_people.add_child(l)


static func _year(release: String) -> String:
	var m := RegEx.create_from_string("(19|20)\\d\\d").search(release)
	return m.get_string(0) if m else ""


static func _review_color(pct: int) -> String:
	return "ok" if pct >= 70 else ("warn" if pct >= 40 else "danger")


func _price_now() -> int:
	return int(_d.get("price", 0)) if int(_d.get("price", 0)) > 0 else int(item.get("price", 0))


func _original() -> int:
	return int(_d.get("original", 0)) if int(_d.get("price", 0)) > 0 else int(item.get("original", 0))


func _discount() -> int:
	return int(_d.get("discount", 0)) if int(_d.get("price", 0)) > 0 else int(item.get("discount", 0))


func _coming() -> bool:
	return bool(_d.get("coming", false)) if not _d.is_empty() else bool(item.get("coming", false))


func _free() -> bool:
	if not _d.is_empty():
		return bool(_d.get("free", false))
	return bool(item.get("free", false))


## owned, free, soon (noch nicht kaufbar), buy
func _buy_mode() -> String:
	if Store.owned(_appid):
		return "owned"
	if _free():
		return "free"
	if _coming() and _price_now() <= 0 and (_d.get("editions", []) as Array).is_empty():
		return "soon"
	return "buy"


func _fill_price() -> void:
	U.clear(_price)
	match _buy_mode():
		"owned":
			_price.add_child(_tag("In deiner Bibliothek", "ok"))
			var secs := Library.playtime(Library.get_game("steam:%d" % _appid))
			if secs > 0:
				_price.add_child(_shadowed(U.label(U.playtime(secs), "m", "text", "medium")))
		"free":
			_price.add_child(_shadowed(U.label("Kostenlos spielbar", "xl", "text", "black")))
		"soon":
			var rel := str(_d.get("release", ""))
			_price.add_child(_shadowed(U.label(("Erscheint: " + rel) if rel != "" else "Bald erhältlich", "xl", "text", "black")))
		_:
			var p := _price_now()
			if p <= 0:
				_price.visible = false
				return
			var disc := _discount()
			if disc > 0:
				_price.add_child(_tag("−%d %%" % disc, "sale"))
				var old := _Strike.new()
				old.text = Store.price_text(_original())
				old.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				_price.add_child(old)
			_price.add_child(_shadowed(U.label(Store.price_text(p), "xl", "text", "black")))
			var until := int(item.get("until", 0))
			var left := until - int(Time.get_unix_time_from_system())
			if until > 0 and disc > 0 and left > 0:
				var lt := U.label(("Angebot endet in %d Std." % maxi(1, int(left / 3600.0))) if left < 86400 * 2 else ("Angebot bis " + U.date(until)), "s", "muted",
						"medium")
				lt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				_price.add_child(_shadowed(lt))
	_price.visible = _price.get_child_count() > 0


static func _shadowed(l: Label) -> Label:
	l.clip_text = false
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return U.shadow(l, 0.45)


## Leises Schild mit Wort (Rabatt, „In deiner Bibliothek“): die Bedeutungsfarbe als Schrift auf
## einer zart getönten Fläche – kein grell gefülltes Schild.
static func _tag(text: String, col: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UzTheme.box(Color(UzTheme.col(col), 0.16), 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var m := U.margin(14, 4, 14, 5)
	var l := U.label(text, "l", col, "bold")
	l.clip_text = false
	m.add_child(l)
	p.add_child(m)
	return p


func _fill_buttons() -> void:
	# Kommen die Angaben, ändert sich oft nichts an den Knöpfen: dann nicht neu bauen (kein Flackern).
	var sig := "%s:%d" % [_buy_mode(), _movies().size()]
	if sig == _buttons_sig and _buttons.get_child_count() > 0:
		return
	_buttons_sig = sig
	var keep := ""
	var f := Nav.focused()
	if f and _buttons.is_ancestor_of(f):
		keep = str(f.get_meta("uz_key", ""))
	U.clear(_buttons)
	_wish = null
	_mode = _buy_mode()
	var primary: Button
	match _mode:
		"owned":
			primary = U.button("Spielen", "play", "primary")
			primary.set_meta("uz_hint_a", "Starten")
			primary.pressed.connect(func() -> void:
				var g := Library.get_game("steam:%d" % _appid)
				close()
				main.launch(g)
			)
		"free":
			primary = U.button("Kostenlos installieren", "download", "primary")
			primary.pressed.connect(_install_free)
			primary.set_meta("uz_haupt", true)
			primary.set_meta("uz_hint_a", "Installieren")
		"soon":
			primary = U.button("", "heart", "primary")
			primary.pressed.connect(_toggle_wish)
			_wish = primary
		_:
			primary = U.button("Kaufen", "shop", "primary")
			primary.pressed.connect(func() -> void: _checkout(0))
			primary.set_meta("uz_haupt", true)
			primary.set_meta("uz_hint_a", "Kaufen")
	primary.custom_minimum_size.x = 300
	primary.set_meta("uz_default", true)
	primary.set_meta("uz_key", "sg:primary")
	_buttons.add_child(primary)
	if _mode in ["buy", "free"]:
		_wish = U.button("", "heart")
		_wish.set_meta("uz_key", "sg:wish")
		_wish.pressed.connect(_toggle_wish)
		_buttons.add_child(_wish)
	if _wish:
		_wish_look(Store.wishlisted(_appid))
	var movies := _movies()
	if not movies.is_empty():
		var tb := U.button("Trailer", "video")
		tb.set_meta("uz_key", "sg:trailer")
		tb.set_meta("uz_hint_a", "Abspielen")
		tb.pressed.connect(func() -> void: _play(0))
		_buttons.add_child(tb)
	# Papierflieger statt Sprechblase: die steht überall sonst für „Chat“.
	var share := U.button("", "send", "icon")
	share.set_meta("uz_key", "sg:share")
	share.set_meta("uz_hint_a", "Einem Freund schicken")
	share.pressed.connect(func() -> void:
		main.open_friend_picker("Spiel schicken an", func(kind: String, fr: Dictionary) -> void:
			main.send_message(kind, fr, "Schau mal: %s https://store.steampowered.com/app/%d" % [str(item.get("name", "")), _appid])
		)
	)
	_buttons.add_child(share)
	if keep != "":
		for c in _buttons.get_children():
			if str((c as Control).get_meta("uz_key", "")) == keep:
				Nav.focus(c as Control, true)
				return
		Nav.focus(primary, true)


func _wish_look(on: bool) -> void:
	if not is_instance_valid(_wish):
		return
	_wish.text = ("Auf der Wunschliste" if on else ("Auf die Wunschliste" if _mode == "soon" else "Wunschliste"))
	_wish.icon = Icons.tex("heart_f" if on else "heart", 26)
	_wish.set_meta("uz_hint_a", "Von der Wunschliste nehmen" if on else "Auf die Wunschliste")
	if _wish.has_focus() and main and main.hint_bar:
		main.hint_bar.refresh()


func _movies() -> Array:
	return _d.get("movies", []) as Array


# --- Laden ---------------------------------------------------------------------------------

func _load() -> void:
	_load_reviews()
	var d: Dictionary = await Store.details(_appid)
	if not is_inside_tree():
		return
	_d = d
	if _d.is_empty():
		_build_offline()
		return
	if str(item.get("name", "")).strip_edges() == "" and str(_d.get("name", "")) != "":
		item["name"] = str(_d.name)
		_title.text = str(_d.name)
	_hero_fallback()
	_fill_meta()
	_fill_price()
	_fill_buttons()
	_build_media()
	_build_about()
	_build_editions()
	_build_requirements()
	_load_dlc()
	_load_news()
	if start_focus == "media" and is_instance_valid(_media_first):
		Nav.focus(_media_first, true)


## Keine Angaben (kein Netz, Spiel nicht im deutschen Shop): ehrlich sagen, Rest bleibt nutzbar.
func _build_offline() -> void:
	var m := U.margin(GUTTER, 0, GUTTER, 0)
	var l := U.label(tr("Keine weiteren Angaben verfügbar."), "m", "muted", "regular",
			true)
	l.custom_minimum_size = Vector2(980, 0)
	m.add_child(l)
	_put("about", m)


## Abschnitt an seinen festen Platz setzen; was nachgeladen wird, blendet weich ein.
func _put(slot: String, c: Control) -> void:
	(_slots[slot] as Control).add_child(c)
	c.modulate.a = 0.0
	U.tw(c, "uz_in").tween_property(c, "modulate:a", 1.0, U.T_ENTER)


func _section(title: String, extra := "") -> VBoxContainer:
	var box := U.vbox(8)
	var m := U.margin(GUTTER, 0, GUTTER, 0)
	var hb := U.hbox(14)
	m.add_child(hb)
	var t := U.label(title, "l", "text", "bold")
	t.clip_text = false
	hb.add_child(t)
	if extra != "":
		var e := U.label(extra, "m", "faint", "medium")
		e.clip_text = false
		hb.add_child(e)
	box.add_child(m)
	return box


# --- Trailer und Bilder ------------------------------------------------------------------------

func _build_media() -> void:
	var movies := _movies()
	var shots: Array = _d.get("screens", [])
	if movies.is_empty() and shots.is_empty():
		return
	var parts := PackedStringArray()
	if not movies.is_empty():
		parts.append(U.plural(movies.size(), "Trailer", "Trailer"))
	if not shots.is_empty():
		parts.append(U.plural(shots.size(), "Bild", "Bilder"))
	var box := _section("Trailer und Bilder" if not movies.is_empty() else "Bilder", " · ".join(parts))
	var shelf = Shelf.new().setup("sg:media", 22, true, 20, GUTTER)
	shelf.custom_minimum_size.y = _Media.H + 48
	for i in movies.size():
		var mv: Dictionary = movies[i]
		var t := _Media.new()
		t.appid = _appid
		t.trailer = true
		t.caption = str(mv.get("name", "")) if str(mv.get("name", "")) != "" else "Trailer"
		# Vorschaubild des Trailers; ist es klein, lieber ein großes Bild aus dem Spiel.
		t.urls = [str(mv.get("thumb", ""))]
		if not shots.is_empty():
			t.urls.append(str(shots[i % shots.size()]))
		t.set_meta("uz_hint_a", "Abspielen")
		t.set_meta("uz_key", "sg:mv:%d" % i)
		var idx := i
		t.chosen.connect(func() -> void: _play(idx))
		shelf.add(t)
	for i in shots.size():
		var t := _Media.new()
		t.appid = _appid
		t.urls = [str(shots[i])]
		t.set_meta("uz_hint_a", "Groß ansehen")
		t.set_meta("uz_key", "sg:shot:%d" % i)
		var idx := i
		t.chosen.connect(func() -> void: _view_shot(idx))
		shelf.add(t)
	var first: Control = shelf.items()[0]
	first.set_meta("uz_entry", true)
	_media_first = first
	box.add_child(shelf)
	_put("media", box)


func _play(i: int) -> void:
	var movies := _movies()
	if movies.is_empty():
		return
	if not Library.demo and not YouTube.tools_ready():
		Toasts.show_toast("Trailer brauchen den Videoplayer", "Einrichten unter Videos.",
				"video", { "ms": 6000 })
		return
	var v: Node = view if view else (main.sections.get("shop") if main else null)
	if v and v.has_method("play_trailer"):
		v.call("play_trailer", item, movies, clampi(i, 0, movies.size() - 1))


func _view_shot(i: int) -> void:
	var l := _Viewer.new()
	l.urls = _d.get("screens", [])
	l.idx = i
	main.open_layer(l)


# --- Über das Spiel ---------------------------------------------------------------------------

func _build_about() -> void:
	var about := str(_d.get("about", ""))
	var long := str(_d.get("long", ""))
	var facts := _facts()
	var seiten := steam_seiten_zeile(main, _appid, "sg", bool(_d.get("workshop", false)))
	if about == "" and long == "" and facts.is_empty():
		if seiten != null:
			var nur := _section("Mehr auf Steam")
			var nm := U.margin(GUTTER, 10, GUTTER, 0)
			nm.add_child(seiten)
			nur.add_child(nm)
			_put("about", nur)
		return
	var box := _section("Über das Spiel")
	var m := U.margin(GUTTER, 10, GUTTER, 0)
	var hb := U.hbox(84)
	m.add_child(hb)
	var left := U.vbox(20)
	left.custom_minimum_size = Vector2(960, 0)
	hb.add_child(left)
	var text := U.label(about if about != "" else long.left(420), "m", "text", "regular", true)
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Text des Shops, kommt schon in der Sprache
	text.add_theme_constant_override("line_spacing", 5)
	text.custom_minimum_size = Vector2(960, 0)
	left.add_child(text)
	var feats: PackedStringArray = _d.get("features", PackedStringArray())
	if not feats.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		flow.custom_minimum_size = Vector2(960, 0)
		for ft in feats:
			flow.add_child(_chip(str(ft)))
		left.add_child(flow)
	if long.length() > about.length() + 60:
		var more := U.button("Mehr lesen", "list", "flat")
		more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		more.set_meta("uz_key", "sg:more")
		more.pressed.connect(func() -> void:
			read(main, str(item.get("name", "")), "Über das Spiel", [long], true)
		)
		left.add_child(more)
	var right := U.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	for kv in facts:
		var r := U.hbox(16)
		var k := U.label(str(kv[0]), "s", "faint", "medium")
		k.custom_minimum_size = Vector2(170, 0)
		r.add_child(k)
		var val := U.label(str(kv[1]), "s", "text", "medium", true)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.max_lines_visible = 2
		r.add_child(val)
		right.add_child(r)
	box.add_child(m)
	if seiten != null:
		var sm := U.margin(GUTTER, 22, GUTTER, 0)
		var sv := U.vbox(10)
		sv.add_child(U.label("Mehr auf Steam", "s", "faint", "medium"))
		sv.add_child(seiten)
		sm.add_child(sv)
		box.add_child(sm)
	_put("about", box)


## Die anderen Seiten des Spiels bei Steam als Knopfzeile (Store.steam_seiten): Diskussionen, Guides, Artworks …
## A öffnet die Seite in Uzais Browser. null, wo es den Browser nicht gibt (Kinderprofil, sicherer Modus) – dann
## steht dort nichts. Auch auf der Spielseite der Bibliothek.
static func steam_seiten_zeile(main: Main, appid: int, pre: String, workshop := false) -> Control:
	var seiten: Array = Store.steam_seiten(appid, workshop)
	if seiten.is_empty() or main == null or not BrowserDaten.verfuegbar():
		return null
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.set_meta("uz_group", pre + ":seiten")
	flow.set_meta("uz_row", "fest")
	for s in seiten:
		var b := U.button(str(s.name), str(s.icon), "flat")
		b.set_meta("uz_key", "%s:seite:%s" % [pre, str(s.id)])
		b.set_meta("uz_hint_a", "Öffnen")
		var url := str(s.url)
		b.pressed.connect(func() -> void: main.open_browser(url))
		flow.add_child(b)
	return flow


func _facts() -> Array:
	var out: Array = []
	var dev := str(_d.get("developer", ""))
	var pub := str(_d.get("publisher", ""))
	if dev != "":
		out.append(["Entwickler", dev])
	if pub != "" and pub != dev:
		out.append(["Publisher", pub])
	if str(_d.get("release", "")) != "":
		out.append(["Erscheint" if _d.get("coming", false) else "Erschienen", str(_d.release)])
	var gen: PackedStringArray = _d.get("genres", PackedStringArray())
	if not gen.is_empty():
		out.append(["Genre", ", ".join(gen)])
	match str(_d.get("controller", "")):
		"full": out.append(["Controller", "Volle Unterstützung"])
		"partial": out.append(["Controller", "Teilweise unterstützt"])
	if _d.get("my_lang_audio", false):
		out.append(["Sprache", "Deutsch (Texte und Sprachausgabe)"])
	elif _d.get("my_lang", false):
		out.append(["Sprache", "Deutsch (Texte)"])
	else:
		out.append(["Sprache", "nicht auf Deutsch"])
	if int(_d.get("age", 0)) > 0:
		out.append(["Freigabe", "ab %d Jahren" % int(_d.age)])
	if int(_d.get("achievements", 0)) > 0:
		out.append(["Erfolge", "%d bei Steam" % int(_d.achievements)])
	if int(_d.get("metacritic", 0)) > 0:
		out.append(["Metacritic", str(int(_d.metacritic))])
	var size_text := _disk_size()
	if size_text != "":
		out.append(["Speicherplatz", size_text])
	return out


## Platzbedarf aus den Systemanforderungen und – vor dem Installieren wichtig – wie viel auf dem
## Laufwerk für neue Steam-Spiele frei ist: „ca. 45,0 GB · 210,3 GB frei auf D:“.
func _disk_size() -> String:
	var need := Storage.size_from_requirements(_d.get("req_min", []))
	if need <= 0:
		return ""
	var dir := StorageFlow.target_dir({ "source": "steam" })
	return Storage.note(need, StorageFlow.free_at(dir), Storage.drive_of(dir))


static func _chip(t: String) -> Control:
	var p := U.panel("glass_hi", 999, 0)
	var m := U.margin(16, 6, 16, 7)
	m.add_child(U.label(t, "s", "muted", "medium"))
	p.add_child(m)
	return p


# --- Editionen ------------------------------------------------------------------------------

func _build_editions() -> void:
	var eds: Array = _d.get("editions", [])
	if eds.size() < 2 or _buy_mode() == "owned":
		return
	var box := _section("Editionen", U.plural(eds.size(), "Kaufoption", "Kaufoptionen"))
	var m := U.margin(GUTTER, 16, GUTTER, 0)
	var row := U.hbox(22)
	row.set_meta("uz_group", "sg:eds")
	m.add_child(row)
	for i in mini(eds.size(), 4):
		var ed: Dictionary = eds[i]
		var c := _Card.new()
		c.custom_minimum_size = Vector2(410, 150)
		c.set_meta("uz_hint_a", "Kaufen")
		c.set_meta("uz_key", "sg:ed:%d" % i)
		var nm := U.label(str(ed.get("name", "")), "m", "text", "bold", true)
		nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name der Edition
		nm.max_lines_visible = 2
		c.body.add_child(nm)
		c.body.add_child(U.spacer())
		var pr := U.hbox(12)
		if int(ed.get("discount", 0)) > 0:
			pr.add_child(_small_tag("−%d %%" % int(ed.discount), "sale"))
			var old := _Strike.new()
			old.text = Store.price_text(int(ed.get("original", 0)))
			old.px = 17
			old.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pr.add_child(old)
		var p := U.label(Store.price_text(int(ed.get("price", 0))), "l", "text", "bold")
		p.clip_text = false
		pr.add_child(p)
		c.body.add_child(pr)
		var idx := i
		c.chosen.connect(func() -> void: _checkout(idx))
		row.add_child(c)
	box.add_child(m)
	_put("editions", box)


static func _small_tag(text: String, col: String) -> Control:
	var p := U.panel(col, 10, 0)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var m := U.margin(10, 2, 10, 3)
	var l := U.label(text, "s", "text", "bold")
	l.add_theme_color_override("font_color", UzTheme.text_on(UzTheme.col(col)))
	m.add_child(l)
	p.add_child(m)
	return p


# --- Erweiterungen ------------------------------------------------------------------------------

func _load_dlc() -> void:
	if (_d.get("dlc_ids", []) as Array).is_empty():
		return
	var list: Array = await Store.dlc_items(_appid)
	if not is_inside_tree() or list.is_empty():
		return
	var box := _section("Erweiterungen", U.plural(list.size(), "Inhalt", "Inhalte"))
	box.add_child(dlc_shelf(list, "sg:dlc", Store.dlc_installed(_appid), _open_other))
	_put("dlc", box)


## Erweiterungen als Regal (quer). have: App-IDs, die schon da sind (Store.dlc_installed) – dazu
## zählt, was Store.owned_item kennt. pick: was A mit einer Erweiterung macht. Auch auf der
## Spielseite der Bibliothek.
static func dlc_shelf(list: Array, key: String, have: Dictionary, pick: Callable) -> Control:
	var shelf = Shelf.new().setup(key, 26, true, 22, GUTTER)
	shelf.custom_minimum_size.y = ShopCard.height_for(320.0, false) + 48
	for i in list.size():
		var c = ShopCard.new().setup(list[i], 320.0)
		c.portrait = false
		c.owned = have.has(int((list[i] as Dictionary).get("appid", 0)))
		c.set_meta("uz_hint_a", "Ansehen")
		if i == 0:
			c.set_meta("uz_entry", true)
		c.chosen.connect(func(x: Dictionary) -> void: pick.call(x))
		shelf.add(c)
	return shelf


func _open_other(it: Dictionary) -> void:
	var l = get_script().new()
	l.item = it
	l.main = main
	l.view = view
	main.open_layer(l)


# --- Bewertungen ------------------------------------------------------------------------------

func _load_reviews() -> void:
	_rv = await Store.reviews(_appid)
	if not is_inside_tree():
		return
	_fill_meta()
	if int(_rv.get("total", 0)) <= 0:
		return
	var texts: Array = await Store.review_texts(_appid)
	if not is_inside_tree():
		return
	_build_reviews(texts)


func _build_reviews(texts: Array) -> void:
	var box := _section("Bewertungen", "von Spielern auf Steam")
	var m := U.margin(GUTTER, 16, GUTTER, 0)
	m.add_child(reviews_row(main, _rv, texts, "sg"))
	box.add_child(m)
	_put("reviews", box)


## Bewertungen als Reihe: Zusammenfassung (Anteil, Einstufung, Balken), daneben bis zu drei
## Stimmen; A liest. rv: Store.reviews, texts: Store.review_texts, pre: Vorsilbe der Fokus-
## Schlüssel. Auch auf der Spielseite der Bibliothek.
static func reviews_row(main: Main, rv: Dictionary, texts: Array, pre: String) -> Control:
	var total := int(rv.get("total", 0))
	var pct := int(rv.get("percent", 0))
	var row := U.hbox(22)
	row.set_meta("uz_group", pre + ":reviews")
	# Zusammenfassung: großer Anteil, Einstufung, Balken
	var sum := _Card.new()
	sum.custom_minimum_size = Vector2(340, 260)
	sum.set_meta("uz_key", pre + ":rv")
	sum.set_meta("uz_hint_a", "Bewertungen lesen" if not texts.is_empty() else "—")
	var big := U.label("%d %%" % pct, "hero", "text", "title")
	big.clip_text = false
	sum.body.add_child(big)
	var lab := U.label(str(rv.get("label", "")), "l", _review_color(pct), "bold")
	lab.clip_text = false
	sum.body.add_child(lab)
	sum.body.add_child(U.label("%s Bewertungen" % Store.num_text(total), "s", "muted", "medium"))
	sum.body.add_child(U.spacer())
	var bar = ProgressBarUz.new().setup(pct / 100.0, _review_color(pct), 6, 280)
	sum.body.add_child(bar)
	if not texts.is_empty():
		sum.chosen.connect(func() -> void: _read_reviews(main, rv, texts))
	row.add_child(sum)
	for i in mini(texts.size(), 3):
		var one: Dictionary = texts[i]
		var c := _Card.new()
		c.custom_minimum_size = Vector2(436, 260)
		c.set_meta("uz_hint_a", "Lesen")
		c.set_meta("uz_key", "%s:rt:%d" % [pre, i])
		var head := U.hbox(10)
		var up: bool = one.get("up", true)
		head.add_child(U.icon("check" if up else "close", 22, "ok" if up else "danger_text"))
		var hl := U.label("Empfohlen" if up else "Nicht empfohlen", "s", "text", "bold")
		hl.clip_text = false
		head.add_child(hl)
		if float(one.get("hours", 0.0)) > 0.0:
			head.add_child(U.label("· " + _hours(float(one.hours)), "s", "muted", "medium"))
		c.body.add_child(head)
		var tx := U.label(_short(str(one.get("text", "")).replace("\n", " "), 200), "s", "text", "regular", true)
		tx.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Bewertung eines Spielers: fremder Text
		tx.max_lines_visible = 5
		tx.add_theme_constant_override("line_spacing", 3)
		c.body.add_child(tx)
		c.chosen.connect(func() -> void: _read_reviews(main, rv, [one]))
		row.add_child(c)
	return row


## Text auf höchstens n Zeichen kürzen, am Wortende, mit Auslassung (für Kacheln mit Umbruch;
## Godot kürzt umbrochene Zeilen nicht selbst).
static func _short(text: String, n: int) -> String:
	var t := text.strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	if t.length() <= n:
		return t
	var cut := t.left(n).rfind(" ")
	return t.left(cut if cut > n * 0.6 else n).strip_edges().trim_suffix(",").trim_suffix(".") + " …"


static func _hours(h: float) -> String:
	if h < 1.0:
		return "unter 1 Std. gespielt"
	if h < 10.0:
		return Lang.dec("%.1f" % h) + " Std. gespielt"
	return "%d Std. gespielt" % int(h)


static func _read_reviews(main: Main, rv: Dictionary, list: Array) -> void:
	var paras: Array = []
	for one in list:
		var up: bool = one.get("up", true)
		var head := ("Empfohlen" if up else "Nicht empfohlen") + ("  ·  " + _hours(float(one.get("hours", 0.0))) if float(one.get("hours", 0.0)) > 0.0 else "")
		if int(one.get("date", 0)) > 0:
			head += "  ·  " + U.date(int(one.date))
		paras.append(["", head])
		paras.append(str(one.get("text", "")))
	var sub := "%s · %d %% von %s Bewertungen" % [str(rv.get("label", "")), int(rv.get("percent", 0)), Store.num_text(int(rv.get("total", 0)))]
	read(main, "Bewertungen", sub, paras)


# --- Neuigkeiten --------------------------------------------------------------------------------

func _load_news() -> void:
	var list: Array = await Store.news(_appid)
	if not is_inside_tree() or list.is_empty():
		return
	var box := _section("Neuigkeiten", "von den Entwicklern")
	var m := U.margin(GUTTER, 16, GUTTER, 0)
	m.add_child(news_row(main, list, "sg"))
	box.add_child(m)
	_put("news", box)


## Neuigkeiten als Reihe: bis zu drei Karten (wann, Titel, Anfang), Patchnotes als solche
## erkennbar; A liest den ganzen Text. Nur Text – Bilder und Links nimmt Store.clean_text heraus.
## Auch auf der Spielseite der Bibliothek.
static func news_row(main: Main, list: Array, pre: String) -> Control:
	var row := U.hbox(21)
	row.set_meta("uz_group", pre + ":news")
	for i in mini(list.size(), 3):
		var one: Dictionary = list[i]
		var c := _Card.new()
		c.custom_minimum_size = Vector2(562, 236)
		c.set_meta("uz_hint_a", "Lesen")
		c.set_meta("uz_key", "%s:news:%d" % [pre, i])
		var when := PackedStringArray()
		if one.get("patch", false):
			when.append("Patchnotes")
		if int(one.get("date", 0)) > 0:
			when.append(U.ago(int(one.date)))
		c.body.add_child(U.label("  ·  ".join(when), "s", "faint", "medium"))
		var t := U.label(_short(str(one.get("title", "")), 76), "m", "text", "bold", true)
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Titel und Anfang der Neuigkeit: fremder Text
		t.max_lines_visible = 2
		c.body.add_child(t)
		var ex := U.label(_short(str(one.get("text", "")).replace("\n", " ").replace("• ", ""), 150), "s", "muted", "regular", true)
		ex.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		ex.max_lines_visible = 3
		c.body.add_child(ex)
		c.chosen.connect(func() -> void:
			read(main, str(one.get("title", "")), U.date(int(one.get("date", 0))), str(one.get("text", "")).split("\n\n"), true)
		)
		row.add_child(c)
	return row


# --- Systemanforderungen ------------------------------------------------------------------------

func _build_requirements() -> void:
	var mn: Array = _d.get("req_min", [])
	var rc: Array = _d.get("req_rec", [])
	if mn.is_empty() and rc.is_empty():
		return
	var box := _section("Systemanforderungen", "für Windows")
	var m := U.margin(GUTTER, 16, GUTTER, 0)
	var row := U.hbox(22)
	row.set_meta("uz_group", "sg:req")
	m.add_child(row)
	var cols: Array = []
	if not mn.is_empty():
		cols.append(["Mindestens", mn])
	if not rc.is_empty():
		cols.append(["Empfohlen", rc])
	var main_rows := 0
	for cdef in cols:
		main_rows = maxi(main_rows, _req_main(cdef[1]).size())
	for cdef in cols:
		var c := _Card.new()
		c.custom_minimum_size = Vector2(853 if cols.size() > 1 else 1100, 92 + main_rows * 36)
		c.set_meta("uz_hint_a", "Alle Angaben")
		c.set_meta("uz_key", "sg:req:" + str(cdef[0]))
		var hl := U.label(str(cdef[0]), "m", "text", "bold")
		c.body.add_child(hl)
		for kv in _req_main(cdef[1]):
			var r := U.hbox(16)
			var k := U.label(str(kv[0]), "s", "faint", "medium")
			k.custom_minimum_size = Vector2(190, 0)
			r.add_child(k)
			var vl := U.ellipsis(U.label(str(kv[1]), "s", "text", "medium"))
			vl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Angabe des Shops
			r.add_child(vl)
			c.body.add_child(r)
		var all_rows: Array = cdef[1]
		var head := str(cdef[0])
		c.chosen.connect(func() -> void: read(main, "Systemanforderungen", head, all_rows))
		row.add_child(c)
	box.add_child(m)
	_put("req", box)


## Die wichtigsten Zeilen in fester Reihenfolge (höchstens sechs).
static func _req_main(rows: Array) -> Array:
	var out: Array = []
	for key in KEY_REQ:
		for kv in rows:
			if str(kv[0]).to_lower() == str(key).to_lower():
				out.append(kv)
				break
	if out.is_empty():
		out = rows.filter(func(kv): return str(kv[0]) != "")
	return out.slice(0, 6)


func _foot() -> Control:
	var foot := U.margin(GUTTER, 6, GUTTER, 90)
	var l := U.label(tr("Preise aus dem deutschen Steam-Shop. Bezahlt wird bei Steam."), "s",
			"faint", "regular", true)
	l.custom_minimum_size = Vector2(1200, 0)
	foot.add_child(l)
	return foot


# --- Handlungen ----------------------------------------------------------------------------------

func handle(cmd: String) -> bool:
	if cmd == "y" and not Store.owned(_appid):
		_toggle_wish()
		return true
	return false


func _toggle_wish() -> void:
	if _wish_busy or Store.owned(_appid):
		return
	if not Store.can_change():
		_ask_login("Wunschliste direkt in Uzai", "Mit der Steam-App anmelden.")
		return
	var on := not Store.wishlisted(_appid)
	_wish_busy = true
	_wish_look(on)
	var r: Dictionary = await Store.set_wishlisted(_appid, on, item)
	if not is_inside_tree():
		return
	_wish_busy = false
	if r.get("ok", false):
		Toasts.show_toast("Auf der Wunschliste" if on else "Von der Wunschliste genommen", str(item.get("name", "")), "heart_f" if on else "heart",
				{ "ms": 1600, "quiet": true })
		return
	_wish_look(not on)
	if r.get("login", false):
		_ask_login("Steam-Anmeldung nötig", str(r.get("text", "")) + " Neu mit der Steam-App anmelden.")
	else:
		Toasts.show_toast("Wunschliste ging nicht", str(r.get("text", "")), "warning", { "ms": 6000 })


func _ask_login(head: String, text: String) -> void:
	var m: Node = main
	main.open_dialog(head, text, [
		["Mit Steam anmelden", func() -> void: m.open_chat({ "id": "", "name": "Steam" }, true)],
		["Abbrechen", Callable()],
	])


func _install_free() -> void:
	# Ohne Steam auf dem PC ginge der Auftrag ins Leere: erst zeigen, wo es Steam gibt.
	if Library.launcher_missing("steam"):
		main.open_launcher_offer("steam")
		return
	# Vorher den Platz prüfen: passt es nicht oder wird es knapp, fragt Uzai nach.
	StorageFlow.check_install(main, { "source": "steam", "appid": _appid, "title": str(item.get("name", "")) }, _install_free_go)


func _install_free_go() -> void:
	Store.install_free(_appid)
	if Library.demo:
		Toasts.show_toast("Demo: Steam würde jetzt installieren", str(item.get("name", "")), "download", { "ms": 3000 })
	else:
		Toasts.show_toast("Steam installiert " + str(item.get("name", "")), "Kostenlos. Danach unter Spiele.", "download", { "ms": 5000 })


## Kaufen: erst in Uzai bestätigen (Edition, Preis, was passiert), dann den Warenkorb in Steam.
func _checkout(pick: int) -> void:
	if _d.is_empty():
		# Angaben (mit den Kaufoptionen) sind noch unterwegs: kurz darauf warten.
		var d: Dictionary = await Store.details(_appid)
		if not is_inside_tree() or Nav.top_layer() != self:
			return
		if not d.is_empty():
			_d = d
	var c := _Checkout.new()
	c.item = item
	c.details = _d
	c.editions = (_d.get("editions", []) as Array).duplicate()
	c.pick = clampi(pick, 0, maxi(0, c.editions.size() - 1))
	c.price = _price_now()
	c.original = _original()
	c.discount = _discount()
	c.cart = Store.can_change() and not c.editions.is_empty()
	c.confirmed.connect(_pay)
	main.open_layer(c)


func _pay(ed: Dictionary) -> void:
	_bezahlen(_appid, str(item.get("name", "")), ed)


## In den Warenkorb und den Warenkorb öffnen. Statisch: Die Seite kann zugehen, während Steam antwortet – an ihr
## hängend läge das Spiel dann im Warenkorb, ohne dass er aufgeht oder Uzai etwas dazu sagt.
static func _bezahlen(appid: int, nm: String, ed: Dictionary) -> void:
	if Store.can_change() and int(ed.get("packageid", 0)) > 0:
		Toasts.show_toast("Wird in den Warenkorb gelegt …", nm, "shop", { "ms": 1500, "quiet": true })
		var r: Dictionary = await Store.add_to_cart(int(ed.packageid))
		if r.get("ok", false):
			Store.open_cart()
			if Library.demo:
				Toasts.show_toast("Demo: Im Steam-Warenkorb", "Hier würde Steam jetzt den Warenkorb zum Bezahlen öffnen.", "check", { "ms": 4000, "sound": "select" })
			else:
				Toasts.show_toast("Im Steam-Warenkorb: " + nm, "Im Steam-Warenkorb bezahlen. Maus im Guide.",
						"check", { "ms": 7000, "sound": "select" })
			return
		Toasts.show_toast("Warenkorb ging nicht", str(r.get("text", "")) + " Steam öffnet stattdessen die Seite des Spiels.", "warning", { "ms": 7000 })
	Store.open_in_steam(appid)
	if not Library.demo:
		Toasts.show_toast("Steam öffnet " + nm, "„In den Warenkorb“ wählen und bezahlen. Maus im Guide.", "shop",
				{ "ms": 7000 })


## Längeren Text in Ruhe lesen (Beschreibung, Bewertungen, Neuigkeiten, Anforderungen). kopf_fremd: Die Überschrift
## ist ein Name oder fremder Titel (Spiel, Neuigkeit).
static func read(main: Main, head: String, sub: String, paras: Variant, kopf_fremd := false) -> void:
	var r := _Reader.new()
	r.heading = head
	r.heading_raw = kopf_fremd
	r.sub = sub
	r.paragraphs = Array(paras) if paras is PackedStringArray else (paras as Array)
	main.open_layer(r)
