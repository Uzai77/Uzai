extends RefCounted
## Quellen der Startseite (Zuletzt, Favoriten, PS2, Steam, Ordner …) und die Apps der Leiste oben
## selbst ordnen: langes A auf einer Quelle bzw. App öffnet ein kleines Menü – Verschieben,
## Ausblenden, Ausgeblendetes zurückholen (bei Spielen auch ausgeblendete Spiele). Reihenfolge und
## Ausgeblendetes merkt sich Uzai (Spiele: library.sub_order/hidden_subs, Apps: apps.order/hidden;
## der Bereich nennt sie in order_key/hidden_key); Neues erscheint an seinem gewohnten Platz.

const OrdnenLayer := preload("res://src/ui/layers/quellen_ordnen.gd")

## Liste zum Zurückholen ausgeblendeter Spiele (games.gd games_for).
const HIDDEN_GAMES := "ausgeblendet"


## Reihenfolge: selbst angeordnete Quellen in ihrer Reihenfolge, jede andere hinter ihrem
## gewohnten Vorgänger (eine neue Konsole steht dort, wo sie ohne eigene Ordnung stünde).
static func ordne(ids: Array, saved: Array) -> Array:
	var out: Array = []
	for id in saved:
		if id in ids and not out.has(id):
			out.append(id)
	for i in ids.size():
		if out.has(ids[i]):
			continue
		var j := i - 1
		while j >= 0 and not out.has(ids[j]):
			j -= 1
		out.insert(out.find(ids[j]) + 1 if j >= 0 else 0, ids[i])
	return out


## Reiter wie sie oben stehen: ohne ausgeblendete (mindestens einer bleibt), in eigener Ordnung.
static func arrange(tabs: Array, saved: Array, hidden: Array) -> Array:
	var shown := tabs.filter(func(t: Dictionary) -> bool: return not hidden.has(str(t.id)))
	if shown.is_empty():
		shown = tabs
	var by := {}
	for t in shown:
		by[str(t.id)] = t
	return ordne(shown.map(func(t: Dictionary) -> String: return str(t.id)), saved).map(func(id: String) -> Dictionary: return by[id])


## Ausgeblendete Quellen, die es gerade gibt: [{ id, label }].
static func hidden_tabs(tabs: Array, hidden: Array) -> Array:
	return tabs.filter(func(t: Dictionary) -> bool: return hidden.has(str(t.id)))


## Wo der Bereich Reihenfolge („order_key“) bzw. Ausgeblendetes („hidden_key“) merkt.
static func key(sec: Object, which: String) -> String:
	var k: Variant = sec.get(which)
	if k is String and k != "":
		return k
	return "library.sub_order" if which == "order_key" else "library.hidden_subs"


## Langes A auf einer Quelle bzw. App.
static func menu(main: Node, sec: Object, sub_id: String, label: String) -> void:
	var opts: Array = [["move", "Verschieben"]]
	if sec.subtabs().size() > 1:
		opts.append(["hide", "Ausblenden"])
	var hid_tabs := hidden_tabs(sec.call("all_subtabs"), Config.get_value(key(sec, "hidden_key"), []))
	if not hid_tabs.is_empty():
		opts.append(["subs", ("Ausgeblendete Quellen (%d)" if sec.has_method("games_for") else "Ausgeblendete Apps (%d)") % hid_tabs.size()])
	var n_games := Library.hidden_games().size() if sec.has_method("games_for") else 0
	if n_games > 0:
		opts.append(["games", "Ausgeblendete Spiele (%d)" % n_games])
	# Eigene Einträge des Bereichs (Apps: „+ App“, „Entfernen“), Wahl über menu_pick.
	if sec.has_method("menu_extra"):
		opts.append_array(sec.call("menu_extra", sub_id))
	main.open_choice(label, opts, null, _chosen.bind(main, sec, sub_id, label, hid_tabs))


static func _chosen(v: Variant, main: Node, sec: Object, sub_id: String, label: String, hid_tabs: Array) -> void:
	match str(v):
		"move": _move(main, sec, sub_id)
		"hide": hide(main, sec, sub_id, label)
		"subs": _restore_menu(main, sec, hid_tabs)
		"games": main.open_library(HIDDEN_GAMES, "Ausgeblendete Spiele")
		_:
			if sec.has_method("menu_pick"):
				sec.call("menu_pick", str(v), sub_id, label)


static func _move(main: Node, sec: Object, sub_id: String) -> void:
	var l = OrdnenLayer.new()
	l.section = sec
	l.sub_id = sub_id
	l.box = sec.call("chip_box") if sec.has_method("chip_box") else main.get("chips_box")
	var pre: Variant = sec.get("key_prefix")
	l.prefix = pre if pre is String and pre != "" else "chip:"
	main.open_layer(l)


## Eine Quelle ausblenden: weg aus der Leiste, kurz zurücknehmbar; dauerhaft zurück über
## „Ausgeblendete Quellen“ im selben Menü.
static func hide(main: Node, sec: Object, sub_id: String, label: String) -> void:
	var h: Array = (Config.get_value(key(sec, "hidden_key"), []) as Array).duplicate()
	if h.has(sub_id):
		return
	h.append(sub_id)
	_set_hidden(main, sec, h)
	Undo.offer("Ausgeblendet", label, "eye_off", func() -> void:
		var back: Array = (Config.get_value(key(sec, "hidden_key"), []) as Array).duplicate()
		back.erase(sub_id)
		_set_hidden(main, sec, back))


static func _restore_menu(main: Node, sec: Object, hid_tabs: Array) -> void:
	var opts: Array = hid_tabs.map(func(t: Dictionary) -> Array: return [str(t.id), str(t.label)])
	if hid_tabs.size() > 1:
		opts.append(["*", "Alle wieder zeigen"])
	main.open_choice("Wieder zeigen", opts, null, func(v: Variant) -> void:
		var h: Array = (Config.get_value(key(sec, "hidden_key"), []) as Array).duplicate()
		if str(v) == "*":
			h.clear()
		else:
			h.erase(str(v))
		_set_hidden(main, sec, h))


static func _set_hidden(main: Node, sec: Object, h: Array) -> void:
	Config.set_value(key(sec, "hidden_key"), h)
	if sec.has_method("quellen_changed"):
		sec.call("quellen_changed")
		return
	# Die gewählte Quelle ist weg: zur ersten, die noch da ist.
	var ids: Array = (sec.subtabs() as Array).map(func(t: Dictionary) -> String: return str(t.id))
	if not ids.has(str(sec.get("sub"))) and not ids.is_empty():
		main.call("_open_sub", sec, str(ids[0]), false)
	main.refresh_chips()


## Verschieben um einen Platz (d = −1 links, +1 rechts). Gibt den neuen Platz zurück (−1: geht nicht).
static func step(sec: Object, sub_id: String, d: int) -> int:
	var ids: Array = (sec.subtabs() as Array).map(func(t: Dictionary) -> String: return str(t.id))
	var i := ids.find(sub_id)
	var j := i + d
	if i < 0 or j < 0 or j >= ids.size():
		return -1
	ids[i] = ids[j]
	ids[j] = sub_id
	# Ausgeblendete behalten ihren Platz in der gemerkten Reihenfolge (beim Zurückholen).
	var saved: Array = Config.get_value(key(sec, "order_key"), [])
	var keep: Array = saved.filter(func(x: Variant) -> bool: return not ids.has(x))
	Config.set_value(key(sec, "order_key"), ids + keep)
	if sec.has_method("order_changed"):
		sec.call("order_changed", ids)
	return j
