extends "res://src/ui/sections/section.gd"
## Steam-Shop im Uzai-Look, wie ein Konsolen-Store: vier Unterbereiche – Entdecken, Angebote,
## Wunschliste, Suche. Entdecken ist eine Fläche: oben die Bühne (ein Spiel groß, mit Grund, Preis
## und Tasten, shop_buehne.gd), darunter kuratierte Reihen (Angebote, bei deinen Freunden, Gratis,
## für dich, Neu, Bald, Topseller, unter 10 €, kostenlos spielbar, Retro-Klassiker) und zuletzt die
## Genres als Bild-Kacheln. Längere Listen öffnet die Kachel „Alle“ am Ende einer Reihe als Ort in
## derselben Fläche (B zurück), ebenso ein Genre. Y setzt überall ein Spiel mit einem Druck auf die
## Wunschliste; in Rastern ordnet X über eine kleine Auswahl. A öffnet die Seite eines Spiels:
## Trailer, Bewertungen, Wunschliste und Warenkorb laufen dort in Uzai, nur bezahlt wird zum
## Schluss bei Steam. Gratis-Spiele von Epic öffnen Epics Seite (free_game.gd).

const ShopCard := preload("res://src/ui/components/shop_card.gd")
const ShopAlle := preload("res://src/ui/components/shop_alle.gd")
const Buehne := preload("res://src/ui/components/shop_buehne.gd")
const GenreKachel := preload("res://src/ui/components/shop_genre_kachel.gd")
const Reihen := preload("res://src/core/store_reihen.gd")
const StoreGame := preload("res://src/ui/layers/store_game.gd")
const FreeGame := preload("res://src/ui/layers/free_game.gd")
const F2P := "Free to Play"

const SORTS := [["", "Beliebt"], ["rabatt", "Höchster Rabatt"], ["preis", "Günstigste zuerst"], ["name", "Name"]]
const CARD_W := 228.0            ## Breite einer Karte in den Reihen
const REIHE_MAX := 20            ## so viele Karten zeigt eine Reihe
const ALLE_AB := 9               ## ab so vielen Spielen hat eine Reihe die Kachel „Alle“

var _sort := ""
var _hide_owned := false
var _search_q := ""
var _search_res: Array = []
var _searching := false
var _search_tags: Array = []     ## gewählte Kategorien der Suche (Nummern aus Store.SUCH_KATEGORIEN)
var _search_lauf := 0            ## zählt die Suchläufe: nur die Antwort des letzten zählt
var _genre_key := ""             ## offenes Genre (Ort in Entdecken)
var _liste_key := ""             ## offene Liste (Ort in Entdecken: top_sellers, new_releases, …)
var _because := {}               ## { title, genre, items } – „Weil du … spielst“
var _friends: Array = []         ## Shop-Einträge der Spiele, die Freunde gerade spielen
var _friends_busy := false
var _stale := false              ## Daten kamen, während eine Ebene offen war: danach neu aufbauen
var _because_busy := false       ## „Weil du …“ lädt gerade (beim Start vorgeladen, nicht doppelt)
var _f2p_at := -600000           ## „Kostenlos spielbar“ zuletzt gefragt (ms; nicht bei jedem Aufbau)
## Unter dem Cursor ändert sich nichts von selbst: build() merkt sich die Kennung dessen, was es
## zeigt (Ansicht und Daten). Gleiche Kennung, kein Neuaufbau; neue Daten, während man im Inhalt
## steht, warten, bis der Cursor oben (Reiter, Unterbereiche) ist oder man wiederkommt.
var _built_kennung := 0
var _platzhalter := false        ## zuletzt Platzhalter gebaut (Daten fehlten): Daten bauen sofort
var _spaeter := false            ## neue Daten warten auf den Cursor außerhalb des Inhalts
var _bau_n := 0                  ## Zahl der Aufbauten (für _ort: hat der Wechsel selbst gebaut?)
var _genre_von := ""             ## uz_key der Kachel, von der das Genre kam (B dorthin)
var _liste_von := ""             ## uz_key der Kachel „Alle“, von der die Liste kam (B dorthin)
var _hero_idx := 0               ## Platz auf der Bühne (bleibt beim Neuaufbau)


func _init() -> void:
	super()
	id = "shop"
	title = "Shop"
	icon_name = "shop"
	Store.updated.connect(_on_store)
	Store.wishlist_changed.connect(_on_wish_changed)
	SteamChat.changed.connect(_on_steam_login)
	Social.updated.connect(_on_social)
	Nav.focus_moved.connect(_on_focus_moved)
	# Für das Vorbauen (section.prebuild): neue Daten machen die vorgebaute Seite alt.
	Store.updated.connect(mark_stale)
	Store.wishlist_changed.connect(mark_stale)
	Library.changed.connect(mark_stale)


func _on_store() -> void:
	if not visible:
		return
	if Nav.top_layer() == null:
		_rebuild_keep()
	else:
		_stale = true


## Auf der Seite eines Spiels geändert: nur die Zahl am Reiter sofort, die Liste beim Zurückkommen.
func _on_wish_changed(_appid: int, _on: bool) -> void:
	if visible and main:
		main.refresh_chips()


func _on_focus_moved(c: Control) -> void:
	if not (visible and is_inside_tree() and Nav.top_layer() == null):
		return
	if _stale:
		# Daten kamen, während eine Ebene offen war: jetzt (sie ist zu) mit derselben Auswahl.
		_stale = false
		_rebuild_keep.call_deferred(true)
	elif _spaeter and c != null and not is_ancestor_of(c):
		# Neue Daten haben gewartet, bis der Cursor nicht mehr im Inhalt steht.
		_spaeter = false
		_rebuild_keep.call_deferred(true)


## Gerade mit der Steam-App angemeldet: die Wunschliste (jetzt auch privat) holen.
func _on_steam_login() -> void:
	if SteamChat.logged_in() and Store.wishlist_noetig():
		Store.load_wishlist()


## Freunde haben ein anderes Spiel angefangen: die Reihe „Bei deinen Freunden“ nachziehen.
func _on_social(what: String) -> void:
	if what == "steam" and (visible or prebuilt):
		_load_friends()


func subtabs() -> Array:
	return [
		{ "id": "entdecken", "label": "Entdecken" },
		{ "id": "specials", "label": "Angebote", "count": (Store.lists.get("specials", []) as Array).size() },
		{ "id": "wunschliste", "label": "Wunschliste", "count": Store.wishlist.size() if Store.wishlist_loaded else -1 },
		{ "id": "suche", "label": "Suche" },
	]


## Alte Ziele (Gratis, Topseller, Neu, Bald, Genres) führen an ihre heutige Stelle: Gratis steht
## oben in den Angeboten, die Listen öffnen sich als Ort in Entdecken.
func resolve_sub(sub_id: String) -> String:
	var z := Reihen.ziel(sub_id)
	if str(z[1]) != "":
		_liste_key = str(z[1])
		_liste_von = ""
		_genre_key = ""
	return str(z[0])


func on_enter() -> void:
	Store.refresh()
	Store.load_free()
	Store.load_retro_classics()
	if Store.wishlist_noetig() and (Social.has_steam() or SteamChat.logged_in() or Library.demo):
		Store.load_wishlist()
	_load_friends()
	_fetch_f2p()
	if _because.is_empty() and not _because_busy:
		_because_busy = true
		await _load_because()
		_because_busy = false


## Beim Start (main._prebuild): dasselbe wie beim Betreten – Angebote, Wunschliste, Freunde, „Weil du …“.
func prefetch() -> void:
	on_enter()


func data_ready() -> bool:
	return not Store.loading and (not Store.lists.is_empty() or Store.error != "")


## Neue Daten (Store, „Weil du …“, Genre, Gratis, Freunde): nur neu aufbauen, wenn sich zeigt, was
## sich geändert hat (Kennung), und nie unter der Auswahl. Standen Platzhalter da, kommt der Inhalt
## sofort (weich, an derselben Stelle); sonst wartet der Aufbau, bis der Cursor oben ist (jetzt:
## true – die Ebene ist gerade zu, der Cursor oben). Läuft ein Übergang, wartet er dessen Ende ab.
func _rebuild_keep(jetzt := false) -> void:
	if get_child_count() > 0 and kennung() == _built_kennung:
		return
	if not is_visible_in_tree():
		build()
		return
	var f := Nav.focused()
	var im_inhalt := f != null and is_ancestor_of(f)
	if im_inhalt and not _platzhalter and not jetzt:
		_spaeter = true
		return
	if _platzhalter and im_uebergang():
		# Der Bereich kommt gerade erst herein (oder wechselt den Ort): Die Daten treten gleich an
		# die Stelle der Platzhalter – der laufende Wechsel blendet sie mit ein. Stand die Auswahl
		# nur vorläufig (Unterbereich, „Entdecken“ im Genre), geht sie auf das erste Element.
		var vorl := f == null or not is_instance_valid(f) or im_inhalt and f.has_meta("uz_vorlaeufig") \
				or str(f.get_meta("uz_key", "")) == "chip:" + sub
		build()
		if main:
			main.refresh_chips()
		if vorl and is_visible_in_tree() and Nav.top_layer() == null:
			focus_default()
		return
	while im_uebergang():
		await get_tree().process_frame
		if not is_visible_in_tree():
			return
	if get_child_count() > 0 and kennung() == _built_kennung:
		return
	# Inzwischen in den Inhalt gekommen (der Bereich war noch im Hereinkommen): dann warten.
	f = Nav.focused()
	if f != null and is_ancestor_of(f) and not _platzhalter and not jetzt:
		_spaeter = true
		return
	_spaeter = false
	var vorlaeufig := f != null and is_instance_valid(f) and f.has_meta("uz_vorlaeufig")
	_ort(0, Callable(), "", not vorlaeufig)


## Ein Ort im Shop wechselt (Liste oder Genre auf und zu, Ordnen, neue Daten): der alte Inhalt geht,
## der neue kommt aus der Richtung dir (0: nur kreuzen; U.abgang/U.ankunft) – kein harter Schnitt
## und nie ein leeres Bild. aendern() stellt den neuen Stand ein (baut es selbst, etwa über
## main.goto, wird nicht noch einmal gebaut). Danach steht die Auswahl auf fokus (uz_key), sonst
## mit behalten auf demselben Element und demselben Bildlauf, sonst vorn.
func _ort(dir: int, aendern: Callable, fokus := "", behalten := false) -> void:
	var f := Nav.focused()
	var drin := f != null and is_ancestor_of(f)
	var key := fokus
	if key == "" and behalten and drin:
		key = str(f.get_meta("uz_key", ""))
	var sc := _bildlauf()
	var y := sc.scroll_vertical if sc and behalten else 0
	var sicht := is_visible_in_tree()
	if sicht:
		U.stop(self, "uz_sec")
		U.stop(self, "uz_slide")
		modulate.a = 1.0
		offset_left = 0.0
		offset_right = 0.0
		U.abgang(self, dir)
	var n := _bau_n
	if aendern.is_valid():
		aendern.call()
	if _bau_n == n:
		build()
	if main:
		main.refresh_chips()
	if sicht:
		U.ankunft(self, dir)
	# Die Auswahl gleich wieder setzen (noch im selben Bild: kein Bild ohne Cursor). Stand der
	# Cursor oben (Reiter, Unterbereiche), bleibt er dort.
	var setzen := Nav.top_layer() == null and (drin or fokus != "" or f == null or not is_instance_valid(f) or not f.is_inside_tree())
	if setzen and not _fokus_auf(key):
		focus_default()
	# Ein Bild warten (der neue Inhalt ist darin noch unsichtbar): erst dann kennt der Bildlauf
	# seine Länge.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var sc2 := _bildlauf()
	if sc2 and behalten:
		sc2.scroll_vertical = y
	if setzen and key != "" and not (Nav.focused() and str(Nav.focused().get_meta("uz_key", "")) == key):
		_fokus_auf(key)


## Auswahl auf das Element mit diesem uz_key (true, wenn es eins gibt).
func _fokus_auf(key: String) -> bool:
	if key == "":
		return false
	for c in Nav.focusables(self):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return true
	return false


func _bildlauf() -> ScrollContainer:
	for c in get_children():
		if c is ScrollContainer:
			return c
	return null


## Nichts Wählbares im Inhalt (Platzhalter beim Laden): die Auswahl steht oben auf dem
## Unterbereich, statt im Leeren zu hängen.
func focus_default() -> void:
	var d := Nav.default_in(self)
	if d:
		Nav.focus(d, true)
		return
	if main and is_instance_valid(main.chips_box):
		for c in main.chips_box.get_children():
			if c is Control and str((c as Control).get_meta("uz_key", "")) == "chip:" + sub:
				Nav.focus(c, true)
				return


## Neu betreten: die Bühne beginnt wieder beim ersten Spiel, Orte (Liste, Genre) sind zu.
func reset_position() -> void:
	super()
	_hero_idx = 0
	_genre_von = ""
	_liste_von = ""
	_genre_key = ""
	_liste_key = ""


# --- Kennung (kein Neuaufbau ohne Änderung) -----------------------------------------------------

## Was eine Liste von Spielen zeigt: Kennung, Preis, Rabatt, Gratis (nicht Reihenfolge der Felder).
static func spiele_kennung(items: Variant) -> Array:
	var out: Array = []
	if not (items is Array):
		return out
	for it in items:
		if it is Dictionary:
			var d: Dictionary = it
			out.append([int(d.get("appid", 0)), str(d.get("id", "")), str(d.get("name", "")), int(d.get("price", 0)),
					int(d.get("discount", 0)), int(d.get("original", 0)), bool(d.get("free", false))])
	return out


## Kennung aus Ansicht (Unterbereich, Genre, Sortierung …) und Listen ({ name: Spiele }); ohne
## Fenster prüfbar (tests/logic_shop_neuaufbau.gd).
static func kennung_von(ansicht: Array, listen: Dictionary) -> int:
	var teile: Array = [ansicht]
	var keys := listen.keys()
	keys.sort()
	for k in keys:
		teile.append([str(k), spiele_kennung(listen[k])])
	return hash(teile)


## Kennung dessen, was build() jetzt zeigen würde.
func kennung() -> int:
	var listen := {}
	for k in Store.lists.keys():
		listen["l:" + str(k)] = Store.lists[k]
	listen["frei"] = Store.free_now() + Store.free_soon()
	listen["wunsch"] = Store.wishlist
	listen["retro"] = Store.retro_classics()
	listen["weil"] = _because.get("items", [])
	listen["freunde"] = _friends
	listen["suche"] = _search_res
	for gk in [_genre_key, F2P]:
		var g: Variant = Store.genre_lists.get(gk)
		if g is Dictionary:
			for t in (g as Dictionary).keys():
				listen["g:%s:%s" % [gk, t]] = (g as Dictionary)[t]
	# Ladezustände nur, wo sie das Bild ändern (sonst baute schon „Wunschliste lädt“ Entdecken neu).
	var ansicht: Array = [sub, _genre_key, _liste_key, _sort, _hide_owned, Store.error if Store.lists.is_empty() else "",
			Store.lists.is_empty(), Store.owned_ids().size(), str(_because.get("title", "")), Reihen.freunde_ids(Social.steam_friends)]
	match sub:
		"wunschliste":
			ansicht.append_array([Store.wishlist_loading and Store.wishlist.is_empty(), Store.wishlist_loaded, Store.wishlist_error, SteamChat.logged_in()])
		"suche":
			ansicht.append_array([_search_q, _searching, _search_tags])
		_:
			if _genre_key != "":
				ansicht.append(Store.genre_lists.has(_genre_key))
	return kennung_von(ansicht, listen)


func build() -> void:
	U.clear(self)
	_bau_n += 1
	_built_kennung = kennung()
	_platzhalter = false
	if sub in ["specials", "wunschliste", "suche"]:
		_genre_von = ""
		_liste_von = ""
	if Store.lists.is_empty() and not sub in ["suche", "wunschliste"]:
		if Store.error != "":
			add_child(
					empty_state("Shop nicht erreichbar", Store.error + "",
					[["Neu laden", "refresh", func() -> void: Store.refresh(true)]], "fehler"))
		else:
			# Laden: die Seite in ihrer fertigen Form, ruhig schimmernd – ohne Text.
			_platzhalter_seite(sub == "entdecken" or sub == "")
		return
	match sub:
		"specials": _build_angebote()
		"wunschliste": _build_wishlist()
		"suche": _build_search()
		_:
			if _genre_key != "":
				_build_genre_page()
			elif _liste_key != "":
				_build_liste_ort()
			else:
				_build_discover()


func _page() -> VBoxContainer:
	var col := U.vbox(10)
	var sc := scroll_v(col)
	sc.set_meta("uz_pad_v", 170.0)
	U.full_rect(sc)
	add_child(sc)
	col.add_child(U.spacer(0, 6, false))
	return col


## Platzhalter in der Form der fertigen Seite: Entdecken mit Bühne und zwei Reihen, sonst ein
## Raster aus Karten. Kein Text („wird geladen“) – die Form sagt es.
func _platzhalter_seite(entdecken: bool) -> void:
	_platzhalter = true
	var col := _page()
	if entdecken:
		var hm := U.margin(GUTTER, 4, GUTTER, 10)
		hm.add_child(Skeleton.new().setup(Vector2(U.room_w(GUTTER), U.by_room(Buehne.H, Buehne.H_MIN)), UzTheme.r_panel()))
		col.add_child(hm)
		col.add_child(_platzhalter_regale(2))
		return
	col.add_child(_platzhalter_raster(222.0, U.cols_for(7), 2))


## Regale als Platzhalter (Überschrift, eine Reihe Karten) – wie das Genre beim Laden.
func _platzhalter_regale(n: int) -> Control:
	var box := U.vbox(0)
	for i in n:
		var lm := U.margin(GUTTER, 20, GUTTER, 0)
		var lv := U.vbox(18)
		lv.add_child(Skeleton.new().setup(Vector2(260, 26), 8))
		lv.add_child(Skeleton.cards(6, Vector2(CARD_W, ShopCard.height_for(CARD_W, true)), 26))
		lm.add_child(lv)
		box.add_child(lm)
	return box


## Raster als Platzhalter: Kopfzeile und rows Reihen Karten in der Breite der Listen.
func _platzhalter_raster(w: float, cols: int, rows: int) -> Control:
	var box := U.vbox(30)
	var head := U.margin(GUTTER, 0, GUTTER, 4)
	head.add_child(Skeleton.new().setup(Vector2(180, 22), 8))
	box.add_child(head)
	var pad := U.margin(GUTTER, 14, GUTTER, 10)
	var rv := U.vbox(30)
	for r in rows:
		rv.add_child(Skeleton.cards(cols, Vector2(w, ShopCard.height_for(w, true)), 26))
	pad.add_child(rv)
	box.add_child(pad)
	return box


## Eine Karte: A öffnet die Seite, Y setzt das Spiel auf die Wunschliste bzw. nimmt es herunter.
func _card(it: Dictionary, w := 340.0, big := false) -> Control:
	var c = ShopCard.new().setup(it, w, big)
	c.set_meta("uz_hint_a", "Ansehen")
	c.chosen.connect(func(x: Dictionary) -> void: open_item(x))
	c.wunsch_taste(toggle_wish)
	return c


## Die Seite eines Spiels. focus_on = "media": gleich bei Trailer und Bildern (nach einem Trailer).
## Gratis-Spiele von Epic: deren Seite bei Epic (QR-Code, Launcher, Browser).
func open_item(it: Dictionary, focus_on := "") -> void:
	if str(it.get("store", "")) == "epic":
		var f = FreeGame.new()
		f.item = it
		f.main = main
		main.open_layer(f)
		return
	var l = StoreGame.new()
	l.item = it
	l.main = main
	l.view = self
	l.start_focus = focus_on
	main.open_layer(l)


## Trailer im eigenen Videoplayer. Der Player schließt dafür alle Ebenen; danach kommt die Seite
## des Spiels wieder, mit der Auswahl bei den Trailern.
func play_trailer(it: Dictionary, movies: Array, idx: int) -> void:
	if movies.is_empty() or not main:
		return
	var list: Array = []
	for mv in movies:
		list.append(Store.trailer_video(it, mv))
	await main.open_video(list, idx, { "start": 0 })
	if Video.active and str(Video.video.get("id", "")).begins_with("steam-trailer-"):
		Video.stopped.connect(_after_trailer.bind(it), CONNECT_ONE_SHOT)


func _after_trailer(it: Dictionary) -> void:
	# main.on_video_closed setzt gleich die Auswahl in den Bereich – erst danach die Seite öffnen.
	await get_tree().create_timer(0.3).timeout
	if is_inside_tree() and Nav.top_layer() == null and main and main.current == "shop":
		open_item(it, "media")


## Wunschliste mit einem Druck (Y auf Karte und Bühne): setzen oder herunternehmen – direkt über
## dein Steam-Konto. Ohne Anmeldung sagt Uzai, wie es geht.
func toggle_wish(it: Dictionary) -> void:
	var appid := int(it.get("appid", 0))
	if appid <= 0 or Store.owned_item(it):
		return
	if not Store.can_change():
		_ask_login()
		return
	var on := not Store.wishlisted(appid)
	var r: Dictionary = await Store.set_wishlisted(appid, on, it)
	if not is_inside_tree():
		return
	if r.get("ok", false):
		Toasts.show_toast("Auf der Wunschliste" if on else "Von der Wunschliste genommen", str(it.get("name", "")), "heart_f" if on else "heart",
				{ "ms": 1600, "quiet": true })
		# Auf der Wunschliste selbst geht die Karte gleich (die Auswahl bleibt, wo sie war).
		if sub == "wunschliste" and not on and visible and Nav.top_layer() == null:
			_rebuild_keep(true)
	elif r.get("login", false):
		_ask_login()
	else:
		Toasts.show_toast("Wunschliste ging nicht", str(r.get("text", "")), "warning", { "ms": 6000 })


func _ask_login() -> void:
	var m: Node = main
	main.open_dialog("Wunschliste direkt in Uzai",
			"Mit der Steam-App anmelden.", [
		["Mit Steam anmelden", func() -> void: m.open_chat({ "id": "", "name": "Steam" }, true)],
		["Abbrechen", Callable()],
	])


## Eine Reihe: Überschrift, Karten, am Ende die Kachel „Alle“ (alle: öffnet die ganze Liste; n: ihre Größe).
func _shelf(head: String, extra: String, items: Array, group: String, alle := Callable(), n := 0) -> Control:
	var box := U.vbox(0)
	box.add_child(section_title(head, extra))
	var shelf = Shelf.new().setup("shop:" + group, 26, true, 18, GUTTER)
	shelf.custom_minimum_size.y = ShopCard.height_for(CARD_W, true) + 48
	box.add_child(shelf)
	var shown := items.slice(0, REIHE_MAX)
	for i in shown.size():
		var c := _card(shown[i], CARD_W)
		if i == 0:
			c.set_meta("uz_entry", true)
		shelf.add(c)
	if alle.is_valid() and n >= ALLE_AB:
		var a = ShopAlle.new().setup(n, CARD_W)
		a.set_meta("uz_key", "alle:" + group)
		a.chosen.connect(alle)
		shelf.add(a)
	return box


# --- Entdecken ---------------------------------------------------------------------------------

func _build_discover() -> void:
	var col := _page()
	var owned := Store.owned_ids()
	var specials: Array = Store.lists.get("specials", [])
	var top: Array = Store.lists.get("top_sellers", [])
	var newr: Array = Store.lists.get("new_releases", [])
	var soon: Array = Store.lists.get("coming_soon", [])
	var free_now: Array = Store.free_now()
	var free: Array = free_now + Store.free_soon()
	var friends := Reihen.freunde_reihe(_friends, Social.steam_friends, owned)
	# Die Bühne: der größte Rabatt, ein Spiel deiner Freunde, ein Gratis-Spiel, das neueste …
	var spot := Reihen.buehne(specials, top, newr, free_now, friends, owned)
	if not spot.is_empty():
		var hm := U.margin(GUTTER, 4, GUTTER, 10)
		var b := Buehne.new()
		b.items = spot
		b.idx = posmod(_hero_idx, spot.size())
		b.view = self
		for it in newr:
			b.neu_ids[int(it.get("appid", 0))] = true
		b.set_meta("uz_default", true)
		hm.add_child(b)
		col.add_child(hm)
	var deals := Store.unique(Store.sorted(specials, "rabatt", owned))
	if not deals.is_empty():
		# „Alle“ führt in den Unterbereich Angebote (als Ortswechsel, nicht als Schnitt).
		col.add_child(_shelf("Angebote", U.plural(specials.size(), "Spiel", "Spiele"), deals, "specials",
				func() -> void: _ort(1, func() -> void: main.goto("shop", "specials", false)), specials.size()))
	if not friends.is_empty():
		col.add_child(_shelf("Bei deinen Freunden", "gerade gespielt", friends, "friends"))
	if not free.is_empty():
		col.add_child(_shelf("Gratis", "zum Behalten – bei Epic und Steam", free, "free"))
	if not _because.is_empty() and not (_because.items as Array).is_empty():
		col.add_child(_shelf("Für dich", tr("Weil du %s spielst") % str(_because.title), Store.sorted(_because.items, "", owned), "because"))
	if not newr.is_empty():
		col.add_child(_shelf("Neu", "", newr, "new", _liste_oeffnen.bind("new_releases", "alle:new"), newr.size()))
	if not soon.is_empty():
		col.add_child(_shelf("Bald", "", soon, "soon", _liste_oeffnen.bind("coming_soon", "alle:soon"), soon.size()))
	if not top.is_empty():
		col.add_child(_shelf("Topseller", "", top, "top", _liste_oeffnen.bind("top_sellers", "alle:top"), top.size()))
	var cheap := Reihen.unter_preis(Store.unique(specials + top), owned)
	if not cheap.is_empty():
		col.add_child(_shelf("Unter 10 €", "", cheap, "cheap"))
	var f2p := _f2p_items()
	if not f2p.is_empty():
		col.add_child(_shelf("Kostenlos spielbar", "Free-to-Play bei Steam", Store.sorted(f2p, "", owned), "f2p",
				_liste_oeffnen.bind("f2p", "alle:f2p"), f2p.size()))
	var retro := Store.retro_classics()
	if not retro.is_empty():
		col.add_child(_shelf("Retro-Klassiker", "offizielle Sammlungen und Neuauflagen", retro, "retro",
				_liste_oeffnen.bind("retro", "alle:retro"), retro.size()))
	col.add_child(_genre_reihe())
	col.add_child(_foot())


## Free-to-Play bei Steam: nur, was wirklich kostenlos ist (das Genre trägt auch manches Kaufspiel).
func _f2p_items() -> Array:
	return ((Store.genre_lists.get(F2P, {}) as Dictionary).get("topsellers", []) as Array).filter(
			func(x: Dictionary) -> bool: return bool(x.get("free", false)))


## Free-to-Play-Topseller nachladen; ohne Netz frühestens nach 10 Minuten wieder.
func _fetch_f2p() -> void:
	if Store.genre_lists.has(F2P) or Time.get_ticks_msec() - _f2p_at < 600000:
		return
	_f2p_at = Time.get_ticks_msec()
	await Store.genre(F2P)
	if Store.genre_lists.has(F2P):
		mark_stale()
		if visible and sub == "entdecken" and Nav.top_layer() == null:
			_rebuild_keep()


## Läufe von _load_friends, die gerade unterwegs sind (siehe dort).
var _load_friends_offen := 0


## Die Spiele, die Freunde gerade spielen, als Shop-Einträge (Store.friend_items, gemerkt).
func _load_friends() -> void:
	_load_friends_offen += 1
	await _load_friends_lauf()
	_load_friends_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _load_friends täte bis zum Neustart nichts mehr.
	if _load_friends_offen == 0 and _friends_busy:
		_friends_busy = false


func _load_friends_lauf() -> void:
	var ids := Reihen.freunde_ids(Social.steam_friends)
	if ids.is_empty():
		if not _friends.is_empty():
			_friends = []
			mark_stale()
		return
	if _friends_busy:
		return
	_friends_busy = true
	var out: Array = await Store.friend_items(ids)
	_friends_busy = false
	if spiele_kennung(out) == spiele_kennung(_friends):
		return
	_friends = out
	mark_stale()
	if visible and sub == "entdecken" and Nav.top_layer() == null:
		_rebuild_keep()


## Die Genres am Ende von Entdecken: Bild-Kacheln in einer Reihe, A öffnet das Genre als Ort.
func _genre_reihe() -> Control:
	var box := U.vbox(0)
	box.add_child(section_title("Nach Genre stöbern", ""))
	var shelf = Shelf.new().setup("shop:genres", 22, true, 18, GUTTER)
	shelf.custom_minimum_size.y = GenreKachel.H + 48
	box.add_child(shelf)
	for i in Store.GENRES.size():
		var g: Array = Store.GENRES[i]
		var key := str(g[0])
		var t = GenreKachel.new().setup(key, str(g[1]), i)
		if i == 0:
			t.set_meta("uz_entry", true)
		t.chosen.connect(func() -> void:
			_ort(1, func() -> void:
				_genre_key = key
				_genre_von = "genre:" + key
			)
			_fetch_genre(key)
		)
		shelf.add(t)
	return box


func _foot() -> Control:
	var foot := U.margin(GUTTER, 18, GUTTER, 60)
	var l := U.label("Preise aus dem deutschen Steam-Shop. Bezahlt wird bei Steam.", "s",
			"faint", "regular", true)
	l.custom_minimum_size = Vector2(minf(1200.0, U.room_w(GUTTER)), 0)
	foot.add_child(l)
	return foot


## „Weil du … spielst“: das Genre des Steam-Spiels, das du zuletzt am meisten gespielt hast.
func _load_because() -> void:
	var best: Dictionary = {}
	for g in Library.recent(12):
		if str(g.get("source", "")) == "steam":
			best = g
			break
	if best.is_empty():
		return
	var d := await Store.details(int(best.get("appid", 0)))
	var genres: PackedStringArray = d.get("genres", PackedStringArray())
	if genres.is_empty():
		return
	var key := ""
	var label := ""
	for gname in genres:
		for gen in Store.GENRES:
			if str(gen[1]).to_lower() == str(gname).to_lower() or str(gen[0]).to_lower() == str(gname).to_lower():
				key = str(gen[0])
				label = str(gen[1])
				break
		if key != "":
			break
	if key == "":
		return
	var res := await Store.genre(key)
	var items: Array = res.get("topsellers", [])
	items = items.filter(func(x): return int(x.appid) != int(best.get("appid", 0)))
	_because = { "title": Library.display_title(best), "genre": label, "items": items }
	mark_stale()
	if visible and sub == "entdecken" and Nav.top_layer() == null:
		_rebuild_keep()


# --- Listen (Angebote, Wunschliste, Orte aus den Reihen) --------------------------------------------

## Eine Liste als Ort in Entdecken (aus der Kachel „Alle“ einer Reihe): Rückweg, Überschrift, Raster.
func _build_liste_ort() -> void:
	var key := _liste_key
	_build_list(_liste_items(key), "liste:" + key, str(Reihen.LISTEN.get(key, key)))


func _liste_items(key: String) -> Array:
	match key:
		"top_sellers", "new_releases", "coming_soon": return Store.lists.get(key, [])
		"f2p": return _f2p_items()
		"retro": return Store.retro_classics()
	return []


## Von der Kachel „Alle“ in die ganze Liste (von rechts); B führt zurück auf die Kachel.
func _liste_oeffnen(key: String, von: String) -> void:
	_ort(1, func() -> void:
		_liste_key = key
		_liste_von = von
		_genre_key = ""
	)


func _liste_zurueck() -> void:
	var von := _liste_von
	_liste_von = ""
	_ort(-1, func() -> void: _liste_key = "", von)


## Angebote: oben die Gratis-Spiele (Epic und Steam), darunter alle Angebote als Raster.
func _build_angebote() -> void:
	var items: Array = Store.lists.get("specials", [])
	var free: Array = Store.free_now() + Store.free_soon()
	var shown := Store.sorted(items, _sort, Store.owned_ids() if _hide_owned else {})
	var col := _page()
	col.add_child(_list_head(shown.size(), "specials", 0))
	if not free.is_empty():
		var sh := _shelf("Gratis", "zum Behalten – bei Epic und Steam", free, "free")
		var f := Nav.default_in(sh)
		if f:
			f.set_meta("uz_default", true)
		col.add_child(sh)
	col.add_child(_grid(shown, "specials", free.is_empty()))
	col.add_child(_foot())


## Leise Zeile über einem Raster: wie viele Spiele, wie geordnet (X ordnet).
func _list_head(n: int, group: String, reduced := 0) -> Control:
	var m := U.margin(GUTTER, 0, GUTTER, 4)
	var hb := U.hbox(24)
	m.add_child(hb)
	var t := U.plural(n, "Spiel", "Spiele")
	if reduced > 0:
		t += "  ·  " + tr("%d im Angebot") % reduced
	hb.add_child(U.label(t, "m", "faint", "medium"))
	hb.add_child(U.spacer())
	var wie := PackedStringArray()
	for s in SORTS:
		if s[0] == _sort and s[0] != "":
			wie.append(tr(str(s[1])))
	if _hide_owned and group != "wunschliste":
		wie.append(tr("ohne Gekaufte"))
	if not wie.is_empty():
		var w := U.label(" · ".join(wie), "s", "faint", "medium")
		w.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(w)
	return m


## Raster aus Karten (Angebote, Wunschliste, Listen). erste_default: die erste Karte ist der
## Einstieg der Seite.
func _grid(shown: Array, group: String, erste_default := true) -> Control:
	var grid := GridContainer.new()
	grid.columns = U.cols_for(7)
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 30)
	grid.set_meta("uz_group", "shop:" + group)
	grid.set_meta("uz_mem", true)
	var pad := U.margin(GUTTER, 14, GUTTER, 10)
	pad.add_child(grid)
	for i in shown.size():
		var c := _card(shown[i], 222.0)
		c.set("show_wish", group != "wunschliste")
		_list_keys(c, group)
		if i == 0 and erste_default:
			c.set_meta("uz_default", true)
		grid.add_child(c)
	if shown.is_empty():
		grid.add_child(U.label("Hier ist gerade nichts.", "l", "muted"))
	return pad


## Eine Liste als Seite: auf Wunsch mit Rückweg und Überschrift (Ort aus einer Reihe), Zeile,
## Raster, Fußnote.
func _build_list(items: Array, group: String, head := "") -> void:
	var wunsch := group == "wunschliste"
	var shown := Store.sorted(items, _sort, Store.owned_ids() if _hide_owned and not wunsch else {})
	var col := _page()
	if head != "":
		var hm := U.margin(GUTTER, 0, GUTTER, 4)
		var hb := U.hbox(16)
		hm.add_child(hb)
		var back := U.button("Entdecken", "chevron_left")
		back.set_meta("uz_key", "shop:liste_zurueck")
		back.pressed.connect(_liste_zurueck)
		hb.add_child(back)
		hb.add_child(U.label(head, "xl", "text", "black"))
		hb.add_child(U.spacer())
		col.add_child(hm)
	var reduced := shown.filter(func(x): return int(x.get("discount", 0)) > 0).size() if wunsch else 0
	col.add_child(_list_head(shown.size(), group, reduced))
	col.add_child(_grid(shown, group))
	col.add_child(_foot())


## X ordnet das Raster über eine kleine Auswahl (Sortierung, Gekaufte aus); Y ist die Wunschliste
## (ShopCard.wunsch_taste).
func _list_keys(c: Control, group: String) -> void:
	c.set_meta("uz_hint_x", "Ordnen")
	c.set_meta("uz_on_x", func() -> void: _ordnen(group))


func _ordnen(group: String) -> void:
	var opts: Array = []
	for s in SORTS:
		opts.append([str(s[0]), str(s[1])])
	if group != "wunschliste":
		opts.append(["owned", "Gekaufte einblenden" if _hide_owned else "Gekaufte ausblenden", U.plural(Store.owned_ids().size(), "Spiel", "Spiele")])
	main.open_choice("Ordnen", opts, _sort, func(v: Variant) -> void:
		if str(v) != "owned" and str(v) == _sort:
			return
		# Erst geht die Auswahl zu (die Karte hat den Cursor wieder), dann kreuzt das Raster – die
		# Auswahl bleibt auf demselben Spiel.
		for i in 60:
			if Nav.top_layer() == null:
				break
			await get_tree().process_frame
		if not is_inside_tree():
			return
		if str(v) == "owned":
			_ort(0, func() -> void: _hide_owned = not _hide_owned, "", true)
		else:
			_ort(0, func() -> void: _sort = str(v), "", true)
	)


# --- Genres ------------------------------------------------------------------------------------

## Die Listen eines Genres holen. Kommen sie, tritt der Inhalt weich an die Stelle der
## Platzhalter; die Auswahl bleibt, wo man inzwischen ist (nur vom vorläufigen Platz „Entdecken“
## geht sie auf das erste Spiel).
func _fetch_genre(key: String) -> void:
	await Store.genre(key)
	if visible and sub == "entdecken" and _genre_key == key and Nav.top_layer() == null:
		_rebuild_keep()


func _build_genre_page() -> void:
	var col := _page()
	var label := _genre_key
	for g in Store.GENRES:
		if g[0] == _genre_key:
			label = str(g[1])
	var head := U.margin(GUTTER, 0, GUTTER, 4)
	var hb := U.hbox(16)
	head.add_child(hb)
	var back := U.button("Entdecken", "chevron_left")
	back.set_meta("uz_key", "shop:genre_zurueck")
	back.pressed.connect(_genre_zurueck)
	hb.add_child(back)
	hb.add_child(U.label(label, "xl", "text", "black"))
	hb.add_child(U.spacer())
	col.add_child(head)
	var data: Dictionary = Store.genre_lists.get(_genre_key, {})
	if data.is_empty():
		col.add_child(_platzhalter_regale(2))
		back.set_meta("uz_default", true)
		back.set_meta("uz_vorlaeufig", true)
		_platzhalter = true
		return
	var tabs := [["topsellers", "Topseller"], ["newreleases", "Neu"], ["specials", "Angebote"], ["comingsoon", "Bald"]]
	var first := true
	for t in tabs:
		var items: Array = data.get(t[0], [])
		if items.is_empty():
			continue
		var sh := _shelf(str(t[1]), "", items, "g:" + str(t[0]))
		col.add_child(sh)
		if first:
			var f := Nav.default_in(sh)
			if f:
				f.set_meta("uz_default", true)
			first = false
	col.add_child(_foot())


func back_hint() -> String:
	return "Zurück" if _im_ort() else "Nach oben"


func handle_back() -> bool:
	if not _im_ort():
		return false
	if _genre_key != "":
		_genre_zurueck()
	else:
		_liste_zurueck()
	return true


## Steht Entdecken gerade auf einem Ort (Genre oder Liste aus einer Reihe)?
func _im_ort() -> bool:
	return (sub == "entdecken" or sub == "") and (_genre_key != "" or _liste_key != "")


## Zurück aus einem Genre auf seine Kachel in der Reihe; der Abschnitt gleitet von links zurück.
func _genre_zurueck() -> void:
	var von := _genre_von if _genre_von != "" else "genre:" + _genre_key
	_genre_von = ""
	_ort(-1, func() -> void: _genre_key = "", von)


# --- Wunschliste und Suche ---------------------------------------------------------------------

func _build_wishlist() -> void:
	if not Store.wishlist.is_empty():
		_build_list(Store.wishlist, "wunschliste")
		return
	if Store.wishlist_loading:
		_platzhalter_seite(false)
		return
	# Empty, error, sign-in: nothing here needs to stay fixed under the selection. When the list arrives it takes
	# this place right away (_rebuild_keep); otherwise the page stayed empty after „Neu laden“ until it was left,
	# because the cursor was on the button and the shop never rebuilds under the selection.
	_platzhalter = true
	var login := func() -> void: main.open_chat({ "id": "", "name": "Steam" }, true)
	if not SteamChat.logged_in() and not Social.has_steam():
		# Die Bühne mit angedeuteten Covern; A meldet per QR-Code an. Danach lädt die Wunschliste
		# (_on_steam_login) und kommt im Takt herein.
		add_child(leer_buehne({ "art": "cover", "symbol": "steam", "titel": "Deine Wunschliste von Steam.",
			"zeile": "Per QR-Code mit der Steam-App.", "knopf": "Steam verbinden", "tun": login,
			"fertig": func() -> bool: return SteamChat.logged_in() or Social.has_steam(),
			"neu": func() -> void:
				if not Store.wishlist_loaded and not Store.wishlist_loading:
					Store.load_wishlist()
				build() }))
		return
	if Store.wishlist_error != "":
		var why := Store.wishlist_error + (" Mit Steam-Anmeldung lesbar." if not SteamChat.logged_in()
				else " Gleich noch einmal versuchen.")
		var btns: Array = [["Neu laden", "refresh", func() -> void: Store.load_wishlist()]]
		if not SteamChat.logged_in():
			btns.push_front(["Mit Steam anmelden", "steam", login])
		add_child(empty_state("Wunschliste nicht lesbar", why, btns, "fehler"))
		return
	add_child(
			empty_state("Deine Wunschliste ist leer",
			"Mit Y auf der Spielseite hinzufügen.",
			[["Im Shop stöbern", "shop", func() -> void: main.goto("shop", "entdecken")], ["Neu laden", "refresh", func() -> void: Store.load_wishlist()]]))


func _build_search() -> void:
	var col := _page()
	var top := U.margin(GUTTER, 0, GUTTER, 6)
	var bar := _SearchBar.new()
	bar.query = _search_q
	bar.set_meta("uz_key", "shop:searchbar")
	bar.set_meta("uz_hint_a", "Suchen")
	bar.pressed_cb = _ask_search
	top.add_child(bar)
	col.add_child(top)
	col.add_child(_such_kategorien())
	var recent := Store.recent_searches()
	if not recent.is_empty():
		var rm := U.margin(GUTTER, 6, GUTTER, 4)
		var rr := U.hbox(12)
		rr.set_meta("uz_group", "shop:recent")
		rm.add_child(rr)
		var rl := U.label("Zuletzt", "s", "faint", "medium")
		rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rr.add_child(rl)
		for term in recent.slice(0, 6):
			var b := U.button(str(term), "history", "flat")
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.custom_minimum_size.y = 48
			b.set_meta("uz_key", "shop:recent:" + str(term))
			var q := str(term)
			b.pressed.connect(func() -> void: _run_search(q))
			rr.add_child(b)
		col.add_child(rm)
	if _searching:
		# Die Treffer kommen als Raster: bis dahin dessen Form, ohne Text.
		_platzhalter = true
		col.add_child(U.spacer(0, 14, false))
		col.add_child(_platzhalter_raster(222.0, U.cols_for(7), 1))
		bar.set_meta("uz_default", true)
		bar.set_meta("uz_vorlaeufig", true)
		return
	var in_kat := Store.such_tag_namen(_search_tags)
	if not _search_res.is_empty():
		var hm := U.margin(GUTTER, 14, GUTTER, 0)
		var kopf := U.label(such_kopf(_search_res.size(), _search_q, in_kat), "m", "faint", "medium")
		kopf.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # schon übersetzt (Suchwort und Kategorien eingesetzt)
		hm.add_child(kopf)
		col.add_child(hm)
		col.add_child(_grid(_search_res, "suche"))
		return
	bar.set_meta("uz_default", true)
	if _search_q != "" or in_kat != "":
		var nm := U.margin(GUTTER, 18, GUTTER, 0)
		var leer := U.label(such_kopf(0, _search_q, in_kat), "l", "muted", "regular", true)
		leer.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		nm.add_child(leer)
		col.add_child(nm)
	# Damit die Seite nie leer ist: was gerade gefragt ist.
	var top_list: Array = Store.lists.get("top_sellers", [])
	if not top_list.is_empty():
		col.add_child(U.spacer(0, 14, false))
		col.add_child(_shelf("Beliebt gerade", "", top_list.slice(0, 12), "search_top"))
	var deals: Array = Store.lists.get("specials", [])
	if not deals.is_empty():
		col.add_child(_shelf("Im Angebot", "", deals.slice(0, 12), "search_deals"))


## Von der globalen Suche: gleich mit diesem Suchwort suchen (der Bereich steht schon auf „Suche“).
func search_for(q: String) -> void:
	_search_tags = []      # die globale Suche kennt keine Kategorien: nicht still nach den zuletzt gewählten filtern
	_run_search(q)


func _ask_search() -> void:
	main.open_keyboard("Im Steam-Shop suchen", _search_q, func(q: String) -> void: _run_search(q))


func _run_search(q: String) -> void:
	_search_q = q.strip_edges()
	if _search_q == "" and _search_tags.is_empty():
		return
	_suche_starten("shop:searchbar")


## Suchen mit dem Suchwort und den gewählten Kategorien; fokus: wo die Auswahl dabei steht (Suchfeld oder die
## eben geschaltete Kategorie). Ohne Suchwort und ohne Kategorie: wieder die leere Seite.
func _suche_starten(fokus: String) -> void:
	_search_lauf += 1
	var lauf := _search_lauf
	var term := _search_q
	var tags := _search_tags.duplicate()
	_search_res = []
	_searching = term != "" or not tags.is_empty()
	if visible and sub == "suche":
		_ort(0, Callable(), fokus)
	if not _searching:
		return
	var res := await Store.search(term, tags)
	if lauf != _search_lauf:
		return
	_search_res = res
	_searching = false
	if term != "":
		Store.remember_search(term)
	if visible and sub == "suche" and Nav.top_layer() == null:
		_rebuild_keep()


## Categories below the search field, to filter the Steam search: A toggles one on or off, several narrow it further
## (at most Store.SUCH_TAGS_MAX, the oldest gives way). With a search term: only results from these categories;
## without one: what is currently popular there.
func _such_kategorien() -> Control:
	var shelf = Shelf.new().setup("shop:kat", 10, false, 8, GUTTER)
	var wahl: Array = [[0, "Alle"]]
	wahl.append_array(Store.SUCH_KATEGORIEN)
	for k in wahl:
		var nr := int(k[0])
		var an := _search_tags.is_empty() if nr == 0 else _search_tags.has(nr)
		var b := U.button(str(k[1]), "check" if an else "", "flat")
		b.custom_minimum_size.y = 48
		b.set_meta("uz_key", "shop:kat:%d" % nr)
		b.set_meta("uz_hint_a", "Abwählen" if an and nr != 0 else "Wählen")
		b.pressed.connect(func() -> void: _kategorie(nr))
		shelf.add(b)
	return shelf


func _kategorie(nr: int) -> void:
	var neu: Array = kategorien_nach(_search_tags, nr)
	if neu == _search_tags:
		return
	_search_tags = neu
	_suche_starten("shop:kat:%d" % nr)


## Die Auswahl nach einem Druck auf die Kategorie nr (0: „Alle“ – nichts gewählt). Ohne Fenster prüfbar.
static func kategorien_nach(tags: Array, nr: int) -> Array:
	var out := tags.duplicate()
	if nr <= 0:
		return []
	if out.has(nr):
		out.erase(nr)
		return out
	out.append(nr)
	while out.size() > Store.SUCH_TAGS_MAX:
		out.pop_front()
	return out


## Zeile über den Treffern bzw. statt ihrer: „12 Treffer für „portal“ in Action, Koop“, „Beliebt in Action“,
## „Keine Treffer für „x““ … – in der Sprache der Oberfläche.
static func such_kopf(n: int, q: String, in_kat: String) -> String:
	if n <= 0:
		if q != "" and in_kat != "":
			return TranslationServer.translate("Keine Treffer für „%s“ in %s.") % [q, in_kat]
		if q != "":
			return TranslationServer.translate("Keine Treffer für „%s“.") % q
		return TranslationServer.translate("Keine Treffer in %s.") % in_kat
	if q == "":
		return TranslationServer.translate("Beliebt in %s") % in_kat
	var treffer := U.plural(n, "Treffer", "Treffer")
	if in_kat != "":
		return TranslationServer.translate("%s für „%s“ in %s") % [treffer, q, in_kat]
	return TranslationServer.translate("%s für „%s“") % [treffer, q]


## Suchfeld als große Leiste: A öffnet die Tastatur.
class _SearchBar extends Control:
	const UU := preload("res://src/ui/u.gd")
	var query := ""
	var pressed_cb: Callable

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(minf(980.0, UU.room_w()), 66)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var m := UU.margin(26, 0, 26, 0)
		UU.full_rect(m)
		add_child(m)
		var row := UU.hbox(16)
		m.add_child(row)
		var ic := UU.icon("search", 26, "muted")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var t := UU.ellipsis(UU.label(query if query != "" else "Spiel im Steam-Shop suchen", "m", "text" if query != "" else "muted", "medium"))
		if query != "":
			t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Eingetipptes: nie übersetzen
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
		focus_entered.connect(func() -> void: UU.etikett(self, true))
		focus_exited.connect(func() -> void: UU.etikett(self, false))
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func activate() -> void:
		if pressed_cb.is_valid():
			pressed_cb.call()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UzTheme.box(UzTheme.col("glass_hi"), int(size.y * 0.5) - 1, 1, UzTheme.col("stroke")), r)
		UU.draw_focus(self, int(size.y * 0.5) - 1)
