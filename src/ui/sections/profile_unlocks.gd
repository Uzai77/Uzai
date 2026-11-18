extends RefCounted
## Profil: Uzai-Punkte (aus Unlocks) – eine Reihe „Zuletzt freigeschaltet“ mit den Erfolgen,
## die Uzai während des Spielens gemeldet hat, in der Überschrift leise die Summe und das Spiel
## mit den meisten Punkten. Ohne Freischaltungen und ohne Punkte erscheint nichts.

const U := preload("res://src/ui/u.gd")
const UnlockCard := preload("res://src/ui/components/ach/unlock_card.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")

const G := 96
const SHELF_PAD := 30


## Text für die Überschrift: „1.240 Uzai-Punkte · am meisten in Hades (340)“.
static func summary(total: int, games: Dictionary) -> String:
	if total <= 0:
		return ""
	var best := ""
	var best_p := 0
	for k in games.keys():
		var p := int((games[k] as Dictionary).get("points", 0))
		if p > best_p and str(games[k].get("title", "")) != "":
			best_p = p
			best = str(games[k].title)
	var s := "%s Uzai-Punkte" % Unlocks.num_text(total)
	if best != "" and games.size() > 1:
		s += " · am meisten in %s (%s)" % [best, Unlocks.num_text(best_p)]
	return s


## Eintrag aus Unlocks.history() → Format der Erfolgskacheln (unlock_card.gd).
static func card_entry(h: Dictionary) -> Dictionary:
	var ra := str(h.get("platform", "")) == "ra"
	var key := str(h.get("game_key", ""))
	var id := int(key.get_slice(":", 1)) if key.contains(":") else 0
	return { "title": str(h.get("name", "")), "desc": str(h.get("desc", "")), "game": str(h.get("game", "")), "icon": str(h.get("icon", "")),
		"rarity": float(h.get("rarity", -1.0)), "points": int(h.get("ra_points", 0)) if ra else 0, "hardcore": bool(h.get("hardcore", false)),
		"date": int(h.get("unlocked_at", 0)), "source": "ra" if ra else "steam", "appid": 0 if ra else id, "game_id": id if ra else 0 }


static func section(view: Control, col: VBoxContainer) -> void:
	var total: int = Unlocks.total_points()
	var hist: Array = Unlocks.history(12)
	if total <= 0 and hist.is_empty():
		return
	if hist.is_empty():
		col.add_child(title("Uzai-Punkte", summary(total, Unlocks.games())))
		return
	col.add_child(title("Zuletzt freigeschaltet", summary(total, Unlocks.games())))
	var shelf = Shelf.new().setup("prof:uzai_unlocks", 24, true, SHELF_PAD, G, SHELF_PAD + 6)
	col.add_child(view._tight(shelf))
	var now := int(Time.get_unix_time_from_system())
	for i in hist.size():
		var a := card_entry(hist[i])
		var card = UnlockCard.new()
		card.a = a
		card.fresh = now - int(a.date) < 86400
		card.set_meta("uz_key", "prof:uzai_unlocks:%s:%s" % [str(hist[i].get("game_key", "")), str(hist[i].get("api", ""))])
		card.set_meta("uz_hint_a", "Erfolge des Spiels")
		if i == 0:
			card.set_meta("uz_entry", true)
		card.chosen.connect(func() -> void: view._open_unlock(a))
		shelf.add(card)


## Überschrift wie in profile_page.gd (fett, daneben leiser ein Zusatz).
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
