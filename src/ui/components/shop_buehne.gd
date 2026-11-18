extends Control
## Die Bühne des Shops (oben in „Entdecken“): ein Spiel groß – Bild randvoll, links unten ein
## leises Versalien-Etikett mit dem Grund („Angebot · endet in 5 Std.“, „Mira spielt gerade“), der
## Schriftzug des Spiels (sonst der Titel in Plex Condensed), der Preis groß mit altem Preis und
## Rabatt, dazu die zwei Knöpfe „Ansehen“ und „Wunschliste“ (nur Wort) (kein eigener Halt, der
## Cursor bleibt auf der Bühne). Rechts unten eine Spur kleiner Bilder der anderen Spiele; links/
## rechts blättert, alle 7 Sekunden wechselt die Bühne von selbst – nie, solange sie gewählt ist.
## Die Auswahl ist der Kachel-Cursor der Marke (feine Lichtkante, Akzent-Schein), kein Rahmen.
## Welche Spiele auf die Bühne kommen und welcher Grund dort steht: store_reihen.gd.

const U := preload("res://src/ui/u.gd")
const ArtC := preload("res://src/ui/components/shop_art.gd")
const PicC := preload("res://src/ui/components/shop_pic.gd")
const Reihen := preload("res://src/core/store_reihen.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const H := 470.0
const H_MIN := 340.0
const TAKT_S := 7.0
const X0 := 60.0                    ## linker Rand der Angaben
const LOGO_MAX := Vector2(520, 150)
const SPUR := Vector2(104, 60)      ## ein Bild der Spur (Kapsel 616 × 353)
const SPUR_GAP := 10.0

var items: Array = []
var view                            ## der Shop-Bereich (öffnet Seiten, ändert die Wunschliste)
var neu_ids := {}                   ## App-IDs der Liste „Neu“ (für den Grund)
var idx := 0
var _frame: Panel
var _art: Control
var _imgs: Array = []
var _front := 0
var _info: Control
var _info_host: Control
var _spur: Control
var _timer: Timer
var _ring: Control
var _sofort := false
const LOGOS_MAX := 32
var _logos := {}                    ## Schlüssel → Texture2D (Schriftzug), null: keiner da


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, U.by_room(H, H_MIN))
	set_meta("uz_key", "shop:hero")
	set_meta("uz_hint_a", "Ansehen")
	set_meta("uz_on_y", _wunsch)
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_panel()))
	_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_frame)
	add_child(_frame)
	_art = ArtC.new().setup(0, "", false)
	U.full_rect(_art)
	_frame.add_child(_art)
	for i in 2:
		# Großes Bild randvoll; gibt es nur die Kapsel, steht sie rechts, links bleibt Platz für die Angaben.
		var t := PicC.new()
		t.align = Vector2(0.94, 0.5)
		t.fill = Vector2(0.6, 1.6)
		U.full_rect(t)
		t.modulate.a = 0.0
		_frame.add_child(t)
		_imgs.append(t)
	var shade := _Shade.new()
	U.full_rect(shade)
	_frame.add_child(shade)
	_info_host = Control.new()
	_info_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_host.set_meta("uz_titel", true)
	U.full_rect(_info_host)
	_frame.add_child(_info_host)
	_info = _neue_info()
	_spur = _Spur.new()
	_spur.buehne = self
	_frame.add_child(_spur)
	_ring = _Ring.new()
	_ring.buehne = self
	U.full_rect(_ring)
	add_child(_ring)
	_timer = Timer.new()
	_timer.wait_time = TAKT_S
	_timer.one_shot = true
	# Nur sichtbar und nicht gewählt weiterblättern (unsichtbar vorgebaut lief es sonst weiter).
	_timer.timeout.connect(func() -> void:
		if is_visible_in_tree() and not has_focus():
			show_item(idx + 1, 0))
	visibility_changed.connect(_neu_zaehlen)
	add_child(_timer)
	focus_entered.connect(func() -> void:
		U.focus_anim(self, true)
		_timer.stop())
	focus_exited.connect(func() -> void:
		U.focus_anim(self, false)
		_neu_zaehlen())
	gui_input.connect(_klick)
	Store.wishlist_changed.connect(_on_wish)
	resized.connect(func() -> void:
		if is_instance_valid(_spur):
			_spur.call("lege"))
	show_item(idx, 0, true)


func _exit_tree() -> void:
	if Store.wishlist_changed.is_connected(_on_wish):
		Store.wishlist_changed.disconnect(_on_wish)


func _on_wish(_appid: int, _on: bool) -> void:
	_tasten()
	if is_instance_valid(_info):
		_info.queue_redraw()


## Maus: auf einer Tasten-Pille löst sie aus, auf der Spur blättert sie, sonst wählt der Klick.
func _klick(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	var p: Vector2 = (e as InputEventMouseButton).position
	if is_instance_valid(_info):
		var hit := str(_info.call("taste_bei", p))
		if hit == "a":
			Nav.focus(self, true)
			Nav.activate(self)
			return
		if hit == "y":
			Nav.focus(self, true)
			_wunsch()
			return
	var k := int(_spur.call("bei", p - _spur.position)) if is_instance_valid(_spur) else -1
	if k >= 0:
		Nav.focus(self, true)
		show_item(k, signi(k - idx))
		return
	if has_focus():
		Nav.activate(self)
	else:
		grab_focus()


## Volle Zeit bis zum nächsten Bild – nur, wenn die Bühne zu sehen und nicht gewählt ist.
func _neu_zaehlen() -> void:
	if not is_instance_valid(_timer) or not _timer.is_inside_tree():
		return
	if is_visible_in_tree() and not has_focus():
		_timer.start(TAKT_S)
	else:
		_timer.stop()


func _neue_info() -> Control:
	var inf := _Info.new()
	inf.buehne = self
	inf.at = idx
	U.full_rect(inf)
	_info_host.add_child(inf)
	return inf


func item() -> Dictionary:
	return items[clampi(idx, 0, items.size() - 1)] if not items.is_empty() else {}


## Der Grund, warum das Spiel hier steht (Versalien-Etikett).
func grund_von(it: Dictionary) -> Array:
	var id := int(it.get("appid", 0))
	return Reihen.grund(it, { "owned": Store.owned_item(it), "freunde": Reihen.freunde_namen(Social.steam_friends, id),
		"neu": neu_ids.has(id), "wunsch": Store.wishlisted(id), "now": int(Time.get_unix_time_from_system()) })


## Y setzt das Spiel mit einem Druck auf die Wunschliste (bzw. nimmt es herunter).
func _wunsch() -> void:
	var it := item()
	if it.is_empty() or view == null or not is_instance_valid(view):
		return
	if int(it.get("appid", 0)) <= 0 or Store.owned_item(it):
		Sfx.play("bump")
		return
	view.call("toggle_wish", it)


## Tastenhinweise zum gezeigten Spiel: Y nur, wo die Wunschliste geht (Steam, nicht in der Bibliothek).
func _tasten() -> void:
	var it := item()
	var id := int(it.get("appid", 0))
	if id > 0 and not Store.owned_item(it):
		set_meta("uz_hint_y", "Von der Wunschliste" if Store.wishlisted(id) else "Wunschliste")
	elif has_meta("uz_hint_y"):
		remove_meta("uz_hint_y")
	if has_focus() and is_inside_tree():
		var m: Node = get_tree().current_scene
		if m and m.get("hint_bar") is Control:
			(m.get("hint_bar") as Control).call("refresh")


## Spiel i zeigen. dir: Richtung der Taste (0: Selbstlauf, nur kreuzen); erst: Aufbau (ohne Wechsel).
func show_item(i: int, dir := 0, erst := false) -> void:
	if items.is_empty():
		return
	var neu := posmod(i, items.size())
	var wechsel := neu != idx and not erst
	idx = neu
	if view != null and is_instance_valid(view):
		view.set("_hero_idx", idx)
	_neu_zaehlen()
	var it: Dictionary = items[idx]
	var id := int(it.get("appid", 0))
	var key := idx
	_art.set("appid", id if id > 0 else absi(hash(Reihen.key_of(it))) % 1000000)
	_art.queue_redraw()
	_tasten()
	if wechsel and is_inside_tree():
		# Die alten Angaben gehen (Kreuzen), die neuen kommen gestaffelt: Etikett, Schriftzug,
		# Preis, Tasten – jedes Glied ein paar Bilder nach dem vorigen, aus der Richtung der Taste.
		U.abgang(_info_host, dir)
		_info = _neue_info()
		_info.call("enthuellen", dir)
	elif is_instance_valid(_info):
		_info.at = idx
		_info.queue_redraw()
	if is_instance_valid(_spur):
		_spur.queue_redraw()
	queue_redraw()
	_sofort = erst
	var w: WeakRef = weakref(self)
	if id <= 0:
		# Gratis-Spiel von Epic: es bringt seine Bilder selbst mit (quer).
		Media.url_texture_chain(Store.art_urls_from(it, {}, false, int(1280 * Media.px_scale())), 1280, func(t: Texture2D) -> void:
			var me: Control = w.get_ref()
			if me:
				me.call("_fade", t, key)
		)
		_sofort = false
		return
	# Großes Bild unter seinem echten Namen (neue Spiele: Ordner mit Prüfsumme), sonst die Kapsel;
	# der Schriftzug dazu. Liegt alles im Speicher, kommt die Antwort noch in diesem Aufruf.
	Media.with_steam_assets(id, func(a: Dictionary) -> void:
		if w.get_ref() == null:
			return
		var aa: Dictionary = a if not a.is_empty() else Store.art_assets(it)
		Media.url_texture_chain(Store.hero_urls(id, aa, int(1920 * Media.px_scale())), 1920, func(t: Texture2D) -> void:
			var me: Control = w.get_ref()
			if me == null:
				return
			if t:
				me.call("_fade", t, key)
			else:
				Media.url_texture_chain(Store.art_urls_from(it, aa, false), 1280, func(t2: Texture2D) -> void:
					var me2: Control = w.get_ref()
					if me2:
						me2.call("_fade", t2, key)
				)
		)
		var lk := Reihen.key_of(it)
		if not _logos.has(lk):
			Media.url_texture_chain(Store.logo_urls(id, aa), 1000, func(t: Texture2D) -> void:
				var me3: Control = w.get_ref()
				if me3:
					me3.call("_logo_da", lk, t)
			)
	)
	_sofort = false
	_vorladen()


## Das nächste Bild liegt schon bereit, wenn die Bühne weiterblättert (nur sichtbar, nie vorgebaut).
func _vorladen() -> void:
	if items.size() < 2 or not is_visible_in_tree():
		return
	var nx: Dictionary = items[posmod(idx + 1, items.size())]
	var id := int(nx.get("appid", 0))
	if id <= 0:
		return
	Media.with_steam_assets(id, func(a: Dictionary) -> void:
		var urls := Store.hero_urls(id, a if not a.is_empty() else Store.art_assets(nx), int(1920 * Media.px_scale()))
		if not urls.is_empty():
			Media.url_texture(str(urls[0]), 1920, func(_t: Texture2D) -> void: pass)
	)


func _logo_da(key: String, t: Texture2D) -> void:
	_logos[key] = t if t != null and t.get_width() >= 8 and t.get_height() >= 8 else null
	# Die Bühne lebt, solange der Shop offen ist: nur die letzten Schriftzüge halten (sonst käme mit jedem Spiel
	# ein Bild dazu). Ein älteres Spiel fragt seinen beim nächsten Zeigen neu – er liegt dann im Bildspeicher.
	Config.cap(_logos, LOGOS_MAX)
	if is_instance_valid(_info):
		_info.queue_redraw()


## Neues Bild oben darüber, das alte geht erst, wenn es ganz bedeckt ist; gibt es keins, bleibt
## der Verlauf in der Farbe des Spiels.
func _fade(t: Texture2D, key: int) -> void:
	if key != idx:
		return
	if t == null:
		for img in _imgs:
			U.tw(img, "uz_hero", Tween.TRANS_SINE, Tween.EASE_IN_OUT).tween_property(img, "modulate:a", 0.0, U.T_ORT)
		return
	var nxt: Control = _imgs[1 - _front]
	var old: Control = _imgs[_front]
	_front = 1 - _front
	nxt.set("texture", t)
	if nxt.get_index() < old.get_index():
		_frame.move_child(nxt, old.get_index())
	if _sofort:
		U.stop(nxt, "uz_hero")
		U.stop(old, "uz_hero")
		nxt.modulate.a = 1.0
		old.modulate.a = 0.0
		return
	U.tw(nxt, "uz_hero", Tween.TRANS_SINE, Tween.EASE_IN_OUT).tween_property(nxt, "modulate:a", 1.0, U.T_RAUM)
	U.tw(old, "uz_hero", Tween.TRANS_SINE, Tween.EASE_IN_OUT).tween_property(old, "modulate:a", 0.0, U.T_WEG).set_delay(U.T_RAUM)


func activate() -> void:
	if not items.is_empty() and view != null and is_instance_valid(view):
		view.call("open_item", items[idx])


func nav_lr(d: int) -> bool:
	if items.size() < 2:
		return false
	show_item(idx + d, d)
	Sfx.play("tick")
	return true


func f() -> float:
	return float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0


func _draw() -> void:
	var k := f()
	if is_instance_valid(_info):
		_info.queue_redraw()
	if _ring:
		_ring.queue_redraw()
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.set_corner_radius_all(UzTheme.r_panel())
	sh.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(0.45 + 0.15 * k))
	sh.shadow_size = int(26 + 12 * k)
	sh.shadow_offset = Vector2(0, 16)
	draw_style_box(sh, Rect2(Vector2(8, 10), size - Vector2(16, 16)))


## Der ruhige Verlauf unter den Angaben (links dunkel, unten dunkel).
class _Shade extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_texture_rect(U.fade_texture(false), Rect2(0, 0, r.size.x * 0.7, r.size.y), false, Color(0.02, 0.02, 0.03, 0.88))
		draw_texture_rect(U.fade_texture(true, true), Rect2(0, r.size.y * 0.45, r.size.x, r.size.y * 0.55), false, Color(0, 0, 0, 0.55))


## Die Angaben links unten: Etikett, Schriftzug bzw. Titel, Preis, Tasten-Pillen.
class _Info extends Control:
	const KEY_H := 54.0
	const KEY_PAD_R := 26.0
	const GLIEDER := 4         ## Etikett, Schriftzug, Preis, Tasten
	var buehne
	var at := 0                ## welches Spiel diese Angaben zeigen (gehende behalten ihres)
	var _rect_a := Rect2()
	var _rect_y := Rect2()
	var _fit_key := ""
	var _fit_txt := ""
	var _reveal := 1.0         ## 0 … 1: wie weit die Staffel ist (1: alles steht)
	var _dir := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Gestaffelt erscheinen (Takt: Ankommen in T_ORT, Glieder im Abstand U.STAFFEL, Weg W_ORT aus
	## der Richtung dir; ruhig: nur blenden, ohne Staffel).
	func enthuellen(dir: int) -> void:
		_dir = dir
		_reveal = 0.0
		queue_redraw()
		var dauer := U.T_ORT + U.staffel(GLIEDER - 1)
		U.ankommen(self, dauer, "uz_reveal").tween_method(func(v: float) -> void:
			_reveal = v
			queue_redraw()
		, 0.0, 1.0, dauer).set_trans(Tween.TRANS_LINEAR)

	## Stand des i-ten Glieds (0 … 1) mit der Kurve „Ankommen“.
	func _k(i: int) -> float:
		if _reveal >= 1.0:
			return 1.0
		var dauer := U.T_ORT + U.staffel(GLIEDER - 1)
		var x := (_reveal * dauer - U.staffel(i)) / U.T_ORT
		return U.kurve("ankommen", clampf(x, 0.0, 1.0))

	## Versatz eines Glieds auf seinem Weg (aus der Richtung der Taste, im ruhigen Modus 0).
	func _dx(k: float) -> float:
		return (1.0 - k) * U.weg_px(U.W_ORT) * float(_dir if _dir != 0 else 1) * 0.5

	## Welche Tasten-Pille unter dem Punkt liegt ("a", "y" oder "").
	func taste_bei(p: Vector2) -> String:
		if _rect_a.has_point(p):
			return "a"
		if _rect_y.size.x > 0.0 and _rect_y.has_point(p):
			return "y"
		return ""

	func _fit(t: String, w: float, f: Font, fs: int) -> String:
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

	func _draw() -> void:
		if not is_instance_valid(buehne):
			return
		var list: Array = buehne.items
		if list.is_empty():
			return
		var it: Dictionary = list[clampi(at, 0, list.size() - 1)]
		var id := int(it.get("appid", 0))
		var x := X0
		var w := size.x
		var h := size.y
		var knapp := h < 400.0
		var tw := w * 0.56
		var bold := UzTheme.font("bold")
		var med := UzTheme.font("medium")
		# Staffel: Etikett (0), Schriftzug (1), Preis (2), Tasten (3) – jedes Glied mit eigenem Stand.
		var k0 := _k(0)
		var k1 := _k(1)
		var k2 := _k(2)
		var k3 := _k(3)
		# Tasten unten, darüber Preis, Schriftzug und Etikett.
		var y_keys := h - 46.0 - KEY_H
		_rect_a = Rect2()
		_rect_y = Rect2()
		var owned := Store.owned_item(it)
		# Die Pillen zeichnen auch gehende Angaben (sie kreuzen mit); die Maus trifft nur die aktuellen.
		var ra := _taste(Vector2(x + _dx(k3), y_keys), "a", tr("Ansehen"), true, k3)
		var ry := Rect2()
		if id > 0 and not owned:
			var y_text := tr("Von der Wunschliste") if Store.wishlisted(id) else tr("Wunschliste")
			ry = _taste(Vector2(ra.end.x + 12.0, y_keys), "y", y_text, false, k3)
		if at == buehne.idx:
			_rect_a = ra
			_rect_y = ry
		var y := y_keys - 26.0
		# Preis: groß, alter Preis durchgestrichen, Rabatt klein in der Bedeutungsfarbe.
		var disc := int(it.get("discount", 0))
		var px := x + _dx(k2)
		var preis_h := 0.0
		var weiss := Color(1, 1, 1, k2)
		if owned:
			draw_string(bold, Vector2(px, y), tr("In deiner Bibliothek"), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UzTheme.col("ok", k2))
			preis_h = 40.0
		elif bool(it.get("giveaway", false)):
			draw_string(bold, Vector2(px, y), tr("Gratis"), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, weiss)
			px += bold.get_string_size(tr("Gratis"), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 16.0
			if int(it.get("original", 0)) > 0:
				_alt(med, Vector2(px, y), Store.price_text(int(it.original)), k2)
			preis_h = 50.0
		elif int(it.get("price", 0)) > 0:
			var pt := Store.price_label(it)
			draw_string(bold, Vector2(px, y), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, weiss)
			px += bold.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 16.0
			if disc > 0 and int(it.get("original", 0)) > int(it.price):
				px += _alt(med, Vector2(px, y), Store.price_text(int(it.original)), k2) + 14.0
				draw_string(bold, Vector2(px, y), "−%d %%" % disc, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UzTheme.col("sale", k2))
			preis_h = 50.0
		elif bool(it.get("free", false)):
			draw_string(bold, Vector2(px, y), tr("Kostenlos spielbar"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.92 * k2))
			preis_h = 42.0
		elif bool(it.get("coming", false)):
			draw_string(bold, Vector2(px, y), tr("Bald erhältlich"), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.8 * k2))
			preis_h = 40.0
		y -= preis_h + (8.0 if knapp else 14.0)
		# Schriftzug des Spiels, sonst der Titel.
		var logo: Variant = buehne._logos.get(Reihen.key_of(it))
		var block_h := 0.0
		var lx := x + _dx(k1)
		if logo is Texture2D:
			var t: Texture2D = logo
			var mx := LOGO_MAX * (0.75 if knapp else 1.0)
			var sc := minf(mx.x / t.get_width(), mx.y / t.get_height())
			var sz := t.get_size() * sc
			draw_texture_rect(t, Rect2(Vector2(lx, y - sz.y), sz), false, Color(1, 1, 1, k1))
			block_h = sz.y
		else:
			var black := UzTheme.display("black")
			var name := str(it.get("name", ""))
			var fs := (56 if name.length() < 22 else 44) if not knapp else (44 if name.length() < 22 else 36)
			var txt := _fit(name, tw, black, fs)
			draw_string(black, Vector2(lx + 2, y + 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5 * k1))
			draw_string(black, Vector2(lx, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, k1))
			block_h = fs * 0.78
		y -= block_h + (14.0 if knapp else 22.0)
		# Etikett in Versalien: der Grund, warum das Spiel hier steht.
		var teile: Array = buehne.call("grund_von", it)
		if not teile.is_empty():
			var caps := Liste.caps_font()
			var cx := x + _dx(k0)
			for i in teile.size():
				var t_text := str(teile[i]).to_upper()
				var col := UzTheme.col("accent", k0) if i == 0 else Color(1, 1, 1, 0.7 * k0)
				draw_string(caps, Vector2(cx, y), t_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
				cx += caps.get_string_size(t_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
				if i < teile.size() - 1:
					draw_string(caps, Vector2(cx + 10.0, y), "·", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.45 * k0))
					cx += 28.0

	## Alter Preis, durchgestrichen; gibt die Breite zurück.
	func _alt(f: Font, at_: Vector2, text: String, a := 1.0) -> float:
		var ow := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, Vector2(at_.x, at_.y - 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.55 * a))
		draw_line(Vector2(at_.x, at_.y - 8.0), Vector2(at_.x + ow, at_.y - 8.0), Color(1, 1, 1, 0.55 * a), 1.5)
		return ow

	## Eine Tasten-Pille wie der ruhige Knopf: Haupthandlung im Akzent mit dunkler Schrift, sonst
	## getönter Graphit; vorn die Taste, dann das Wort. a: Deckkraft (Staffel). Gibt ihre Fläche zurück.
	## Knopf wie überall seit dem Premium-Durchgang: nur das Wort auf ruhiger, deckender Fläche mit
	## Lichtkante; die Taste dazu steht in der Tastenzeile (cmd bleibt für Aufrufer gleich).
	func _taste(at_: Vector2, _cmd: String, text: String, primary: bool, a := 1.0) -> Rect2:
		var f := U.knopf_farben("primary" if primary else "")
		var fnt := UzTheme.font("ui_bold")
		var fs := UzTheme.size("m")
		var tw := fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(at_, Vector2(ceilf(KEY_PAD_R * 2.0 + tw), KEY_H))
		var rest: Color = f.rest
		draw_style_box(UzTheme.box(Color(rest, rest.a * a), 999), r)
		var ty := at_.y + (KEY_H - fnt.get_height(fs)) * 0.5 + fnt.get_ascent(fs)
		var ink: Color = f.ink
		draw_string(fnt, Vector2(at_.x + KEY_PAD_R, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, ink.a * a))
		return r

## Die Spur rechts unten: kleine Bilder aller Spiele der Bühne, das gezeigte hell mit Lichtkante,
## die anderen leise. Klick auf ein Bild blättert dorthin.
class _Spur extends Control:
	var buehne
	var _thumbs: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var list: Array = buehne.items
		for i in mini(list.size(), 6):
			var it: Dictionary = list[i]
			var tr_ := U.rounded_image(8.0)
			tr_.size = SPUR
			tr_.material.set_shader_parameter("size", SPUR)
			tr_.modulate.a = 0.0
			add_child(tr_)
			_thumbs.append(tr_)
			var w: WeakRef = weakref(tr_)
			var id := int(it.get("appid", 0))
			var holen := func(a: Dictionary) -> void:
				if w.get_ref() == null:
					return
				var urls := Store.art_urls_from(it, a if not a.is_empty() else Store.art_assets(it), false, int(SPUR.x * 2.0 * Media.px_scale()))
				Media.url_texture_chain(urls, int(SPUR.x * 2.0), func(t: Texture2D) -> void:
					var me: TextureRect = w.get_ref()
					if me and t:
						me.texture = t
						U.ankommen(me, U.T_ORT, "uz_spur").tween_property(me, "modulate:a", 1.0, U.T_ORT)
				)
			if id > 0:
				Media.with_steam_assets(id, holen)
			else:
				holen.call({})
		lege()

	## Die Bilder nebeneinander, rechts unten in der Bühne.
	func lege() -> void:
		var n := _thumbs.size()
		if n == 0 or not is_instance_valid(buehne):
			return
		var total := n * SPUR.x + (n - 1) * SPUR_GAP
		var bw: float = buehne.size.x
		var bh: float = buehne.size.y
		size = Vector2(total, SPUR.y)
		position = Vector2(bw - X0 - total, bh - 46.0 - SPUR.y)
		for i in n:
			(_thumbs[i] as Control).position = Vector2(i * (SPUR.x + SPUR_GAP), 0)
		queue_redraw()

	## Welches Bild unter dem Punkt (in Spur-Koordinaten) liegt, sonst −1.
	func bei(p: Vector2) -> int:
		for i in _thumbs.size():
			if Rect2((_thumbs[i] as Control).position, SPUR).grow(4.0).has_point(p):
				return i
		return -1

	func _draw() -> void:
		if not is_instance_valid(buehne):
			return
		var cur: int = buehne.idx
		for i in _thumbs.size():
			var t := _thumbs[i] as Control
			var on := i == cur
			# Leise, wenn nicht gezeigt; das gezeigte Bild voll und mit feiner Lichtkante.
			var ziel := 1.0 if on else 0.45
			if t.get("texture") != null and absf(t.modulate.a - ziel) > 0.01:
				U.tw(t, "uz_spur_a").tween_property(t, "modulate:a", ziel, U.T_ANTWORT)
			var r := Rect2(t.position, SPUR)
			if t.get("texture") == null:
				# Noch kein Bild: eine ruhige Fläche in der Farbe des Spiels (wie das Ersatzbild der Karten).
				var it: Dictionary = buehne.items[i] if i < (buehne.items as Array).size() else {}
				var id := int(it.get("appid", 0))
				var tint := ArtC.tint_of(id if id > 0 else absi(hash(Reihen.key_of(it))) % 1000000)
				draw_style_box(UzTheme.box(Color(tint.darkened(0.45), 1.0 if on else 0.55), 8), r)
			if on:
				var sb := StyleBoxFlat.new()
				sb.draw_center = false
				sb.set_border_width_all(2)
				sb.border_color = Color(UzTheme.frame_color(), 0.85)
				sb.set_corner_radius_all(9)
				sb.anti_aliasing = true
				draw_style_box(sb, r.grow(1.0))


## Der Kachel-Cursor der Marke um die Bühne (außerhalb der Bildmaske, damit der Schein zu sehen ist).
class _Ring extends Control:
	var buehne

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k: float = buehne.call("f")
		UzTheme.draw_tile_focus(self, Rect2(Vector2.ZERO, size), UzTheme.r_panel(), minf(k, 1.0))
