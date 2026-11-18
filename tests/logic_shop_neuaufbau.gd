extends Node
## Shop: unter dem Cursor ändert sich nichts von selbst (Plan „Gefühl 2“, B1/P1). Die Kennung
## dessen, was der Shop zeigt (Ansicht und Daten), entscheidet, ob neu gebaut wird: gleiche Daten
## (Store meldet beim Betreten oft dasselbe noch einmal) bauen nichts neu; neue Daten ersetzen
## Platzhalter sofort, warten aber, solange der Cursor im Inhalt steht.
## Aufruf: godot --headless --path . res://tests/logic_shop_neuaufbau.tscn

const ShopView := preload("res://src/ui/sections/shop_view.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _spiel(id: int, preis: int, rabatt := 0) -> Dictionary:
	return { "appid": id, "name": "Spiel %d" % id, "price": preis, "discount": rabatt, "original": preis, "free": false }


func _ready() -> void:
	# Reine Kennung.
	var a := [_spiel(1, 999), _spiel(2, 1999, 50)]
	var b := [_spiel(1, 999), _spiel(2, 1999, 50)]
	var ansicht := ["specials", "", "", "", false]
	check(ShopView.kennung_von(ansicht, { "l": a }) == ShopView.kennung_von(ansicht, { "l": b }), "gleiche Daten (neue Objekte): gleiche Kennung")
	var c := [_spiel(1, 999), _spiel(2, 1499, 50)]
	check(ShopView.kennung_von(ansicht, { "l": a }) != ShopView.kennung_von(ansicht, { "l": c }), "anderer Preis: andere Kennung")
	check(ShopView.kennung_von(["specials", "", "", "preis", false], { "l": a }) != ShopView.kennung_von(ansicht, { "l": a }), "andere Sortierung: andere Kennung")
	var x := _spiel(3, 500)
	x["header"] = "egal"
	var y := _spiel(3, 500)
	check(ShopView.spiele_kennung([x]) == ShopView.spiele_kennung([y]), "Felder, die nichts zeigen, ändern nichts")
	# Im Baum: ein Raster (Angebote) mit Daten, dann dieselben Daten noch einmal.
	var keep_lists: Dictionary = Store.lists.duplicate(true)
	Store.lists = { "specials": a.duplicate(true) }
	var v = ShopView.new()
	v.size = Vector2(1920, 1000)
	add_child(v)
	v.sub = "specials"
	v.build()
	await get_tree().process_frame
	var seite: Node = v.get_child(0)
	Store.lists = { "specials": b.duplicate(true) }
	v._on_store()
	await get_tree().process_frame
	await get_tree().process_frame
	check(v.get_child(0) == seite, "Store meldet dieselben Daten: kein Neuaufbau")
	# Cursor im Inhalt, neue Preise: der Aufbau wartet.
	var karte: Control = null
	for k in Nav.focusables(v):
		if str(k.get_meta("uz_key", "")).begins_with("shop:"):
			karte = k
			break
	check(karte != null, "Karte im Raster")
	if karte:
		Nav.focus(karte, true)
		await get_tree().process_frame
		Store.lists = { "specials": c.duplicate(true) }
		v._on_store()
		await get_tree().process_frame
		await get_tree().process_frame
		check(v.get_child(0) == seite and bool(v._spaeter), "neue Daten, Cursor im Inhalt: nichts baut sich unter ihm neu auf")
		# Der Cursor geht nach oben (aus dem Inhalt): jetzt kommt der neue Stand.
		var oben := Button.new()
		oben.focus_mode = Control.FOCUS_ALL
		add_child(oben)
		Nav.focus(oben, true)
		Nav.focus_moved.emit(oben)
		for i in 30:
			await get_tree().process_frame
		check(v.get_child(0) != seite and not bool(v._spaeter), "Cursor oben: der neue Stand kommt")
		check(v.kennung() == v._built_kennung, "Kennung danach aktuell")
	# Platzhalter: ohne Daten gebaut, dann kommen sie – sofort, auch mit dem Cursor oben.
	Store.lists = {}
	v.build()
	check(bool(v._platzhalter), "ohne Daten: Platzhalter in der Form der Seite")
	var leer: Node = v.get_child(0)
	Store.lists = { "specials": a.duplicate(true) }
	v._on_store()
	for i in 30:
		await get_tree().process_frame
	check(v.get_child(0) != leer and not bool(v._platzhalter), "Daten kommen: Platzhalter werden ersetzt")
	# Wishlist: read as empty, the cursor rests on a button of the empty page, then the list arrives - it must
	# show up right away, not only after leaving the page.
	var wunsch_alt: Array = Store.wishlist
	var geladen_alt := Store.wishlist_loaded
	Store.wishlist = []
	Store.wishlist_loaded = true
	Store.wishlist_loading = false
	Store.wishlist_error = ""
	v.sub = "wunschliste"
	v.build()
	await get_tree().process_frame
	check(bool(v._platzhalter), "leere Wunschliste: Die Seite gilt als Platzhalter")
	var leer_w: Node = v.get_child(0)
	var knopf := Nav.default_in(v)
	check(knopf != null, "Knopf auf der leeren Seite")
	if knopf:
		Nav.focus(knopf, true)
		await get_tree().process_frame
	Store.wishlist = a.duplicate(true)
	v._on_store()
	for i in 40:
		await get_tree().process_frame
	check(v.get_child_count() > 0 and v.get_child(0) != leer_w
			and Nav.focusables(v).any(func(k: Control) -> bool: return str(k.get_meta("uz_key", "")).begins_with("shop:")),
			"die Liste kommt, während der Cursor auf dem Knopf steht: Sie steht sofort da")
	Store.wishlist = []
	Store.wishlist_loaded = false
	check(Store.wishlist_noetig(), "nie gelesen: lesen")
	Store.wishlist_loaded = true
	Store.wishlist_angemeldet = false
	check(not Store.wishlist_noetig(), "leer gelesen, nicht angemeldet: Ein zweites Lesen brächte nichts")
	Store.wishlist_loading = true
	Store.wishlist_loaded = false
	check(not Store.wishlist_noetig(), "liest gerade: nicht noch einmal")
	Store.wishlist_loading = false
	var sv := FileAccess.get_file_as_string("res://src/ui/sections/shop_view.gd")
	check(sv.contains("SteamChat.logged_in() and Store.wishlist_noetig()") and FileAccess.get_file_as_string("res://src/core/store.gd")
			.contains("wishlist.is_empty() and not wishlist_angemeldet and SteamChat.logged_in()"),
			"nach der Steam-Anmeldung liest der Shop eine leer gelesene Wunschliste noch einmal")
	Store.wishlist = wunsch_alt
	Store.wishlist_loaded = geladen_alt
	# Bühne: gewählt steht sie (kein Weiterblättern unter dem Cursor), danach volle 7 s.
	Store.lists = { "top_sellers": [_spiel(11, 999, 20), _spiel(12, 999, 30), _spiel(13, 999, 40)], "specials": [] }
	v.sub = "entdecken"
	v.build()
	await get_tree().process_frame
	var hero: Control = null
	for k in Nav.focusables(v):
		if str(k.get_meta("uz_key", "")) == "shop:hero":
			hero = k
	check(hero != null, "Bühne da")
	if hero:
		var t: Timer = hero.get("_timer")
		check(not t.is_stopped(), "nicht gewählt: blättert im Takt")
		Nav.focus(hero, true)
		await get_tree().process_frame
		check(t.is_stopped(), "gewählt: steht still")
		var i0 := int(hero.get("idx"))
		hero.call("nav_lr", 1)
		check(t.is_stopped() and int(hero.get("idx")) == posmod(i0 + 1, 3) and int(v._hero_idx) == int(hero.get("idx")), "rechts blättert, der Takt bleibt aus")
		var oben2 := Button.new()
		oben2.focus_mode = Control.FOCUS_ALL
		add_child(oben2)
		Nav.focus(oben2, true)
		await get_tree().process_frame
		check(not t.is_stopped() and t.time_left > 6.9, "abgewählt: wieder volle 7 s (%.2f)" % t.time_left)
		# Neuaufbau behält den Platz im Rampenlicht.
		var idx := int(hero.get("idx"))
		v.build()
		await get_tree().process_frame
		for k in Nav.focusables(v):
			if str(k.get_meta("uz_key", "")) == "shop:hero":
				check(int(k.get("idx")) == idx, "Neuaufbau: gleicher Platz auf der Bühne")
	Store.lists = keep_lists
	v.queue_free()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
