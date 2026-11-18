extends RefCounted
## Oberfläche rund ums Backlog (Roadmap 2; die Regeln stehen in src/library/backlog.gd): Status,
## Sterne, Rezension, Tagebuch, Listen und Jahresziel setzen – von der Spielseite, aus den
## Optionen, aus der Zusammenfassung nach dem Spielen und vom Bereich Profil → Backlog. Alles
## lokal (R6), alles mit dem Controller; eigene Texte über die Bildschirmtastatur oder das Handy.

const U := preload("res://src/ui/u.gd")
const Backlog := preload("res://src/library/backlog.gd")
const SessionSummary := preload("res://src/core/session_summary.gd")
const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const GameFields := preload("res://src/library/game_fields.gd")
const RetroSysteme := preload("res://src/core/retro_systeme.gd")
const Main := preload("res://src/main.gd")

const NEW := "\u0001"
const GOALS := [6, 12, 24, 36, 52, 100]
const NOTES_MAX := 1000


## Alles zum Backlog eines Spiels an einem Ort (aus den Optionen und von der Spielseite): Status,
## Bewertung, Rezension, Tagebuch, Listen – bei Emulator-Spielen dazu die Notizen. done: beim Schließen.
static func open_sheet(main: Main, g: Dictionary, done := Callable()) -> void:
	var gid := str(g.get("id", ""))
	var s = preload("res://src/ui/layers/sheet.gd").new()
	s.setup("Backlog", Library.display_title(g), 760)
	s.subheading_raw = true
	s.fill_func = func(sheet) -> void:
		var game := Library.get_game(gid)
		if game.is_empty():
			game = g
		var again := func() -> void:
			if is_instance_valid(sheet):
				sheet.refill()
		var st := Backlog.status_of(game)
		var stars := Backlog.stars_of(game)
		var n_diary := Backlog.diary_of(game).size()
		var n_lists := Backlog.lists_with(Library.lists, gid).size()
		var review := Backlog.review_of(game)
		var rows: Array = [
			["status", "Status", Backlog.status_icon(st) if st != "" else "bookmark", Backlog.status_name(st) if st != "" else "Keiner",
				func() -> void: pick_status(main, game, again)],
			["stars", "Bewertung", "star", Backlog.stars_text(stars) if stars > 0 else "Keine", func() -> void: pick_stars(main, game, again)],
			["review", "Rezension", "edit", _short(review, 34) if review != "" else "Keine", func() -> void: edit_review(main, game, again)],
			["diary", "Tagebuch", "history", U.plural(n_diary, "Eintrag", "Einträge") if n_diary > 0 else "Leer", func() -> void: open_diary(main, game)],
			["lists", "Listen", "list", U.plural(n_lists, "Liste", "Listen") if n_lists > 0 else "In keiner", func() -> void: pick_lists(main, game, again)],
		]
		if RetroSysteme.is_retro_game(game):
			var note := str(game.get("notes", "")) if game.get("notes") is String else ""
			rows.append(["notes", "Notizen", "edit", _short(note, 34) if note != "" else "Keine", func() -> void: edit_notes(main, game, again)])
		for e in rows:
			var r = SettingRow.new()
			r.setup("action", str(e[1]))
			r.icon_name = str(e[2])
			r.value_text = str(e[3])
			# Eigene Worte als Wert (Rezension, Notiz): Die Zeile zeichnet ihren Wert selbst, also dort ausnehmen.
			r.value_raw = str(e[0]) in ["review", "notes"] and str(e[3]) != "Keine"
			r.set_meta("uz_key", "bl:" + str(e[0]))
			r.on_activate = e[4]
			sheet.add_row(r)
	if done.is_valid():
		s.closed.connect(done)
	main.open_layer(s)


## Notizen zu einem Emulator-Spiel (Codes, Fundorte, wo du stehst) – nur für dich; leer gespeichert
## ist die Notiz weg.
static func edit_notes(main: Main, g: Dictionary, done := Callable()) -> void:
	var gid := str(g.get("id", ""))
	var note := str(g.get("notes", "")) if g.get("notes") is String else ""
	main.open_keyboard("Notizen zu %s" % Library.display_title(g), note, func(t: String) -> void:
		Library.set_field(gid, "notes", GameFields.clean_text(t, NOTES_MAX))
		_call(done))


## Status wählen (mit „Kein Status“). done: nach der Wahl (zum Neuzeichnen).
static func pick_status(main: Main, g: Dictionary, done := Callable()) -> void:
	var gid := str(g.get("id", ""))
	var opts: Array = Backlog.STATUSES.map(func(e): return [e[0], e[1]])
	opts.append(["", "Kein Status"])
	var cb := func(v: Variant) -> void:
		if Library.set_status(gid, str(v)) and str(v) in Backlog.DONE:
			Toasts.show_toast(Backlog.status_name(str(v)), Library.display_title(Library.get_game(gid)), Backlog.status_icon(str(v)),
					{ "sub_raw": true, "sound": "select", "ms": 2600 })
		_call(done)
	main.open_choice("Status", opts, Backlog.status_of(g), cb, Library.display_title(g))


## Bewertung in halben Sternen (0 nimmt sie weg).
static func pick_stars(main: Main, g: Dictionary, done := Callable()) -> void:
	var gid := str(g.get("id", ""))
	var opts: Array = []
	for h in range(10, 0, -1):
		opts.append([h, Backlog.stars_text(h)])
	opts.append([0, "Keine Bewertung"])
	var cb := func(v: Variant) -> void:
		Library.set_stars(gid, int(v))
		_call(done)
	main.open_choice("Bewertung", opts, Backlog.stars_of(g), cb, Library.display_title(g))


static func edit_review(main: Main, g: Dictionary, done := Callable()) -> void:
	var gid := str(g.get("id", ""))
	main.open_keyboard("Rezension zu %s" % Library.display_title(g), Backlog.review_of(g), func(t: String) -> void:
		Library.set_review(gid, t)
		_call(done))


## Neuer Eintrag ins Tagebuch. at/secs: eine Runde (aus der Zusammenfassung), sonst jetzt ohne
## Dauer. Gespeichert wird erst, wenn man den Text bestätigt – auch leer (nur „gespielt am …“).
static func write_diary(main: Main, g: Dictionary, at := 0, secs := 0, done := Callable()) -> void:
	var gid := str(g.get("id", ""))
	var when := at if at > 0 else int(Time.get_unix_time_from_system())
	main.open_keyboard("Tagebuch · %s" % Library.display_title(g), "", func(t: String) -> void:
		if Library.add_diary(gid, when, secs, t):
			Toasts.show_toast("Im Tagebuch", "%s · %s" % [Library.display_title(Library.get_game(gid)), entry_head(when, secs)], "history",
					{ "sound": "select", "ms": 2400 })
		_call(done))


## Tagebuch eines Spiels: oben „Eintrag schreiben“, darunter alle Einträge (neueste zuerst). Y löscht
## einen Eintrag – kurz zurücknehmbar.
static func open_diary(main: Main, g: Dictionary) -> void:
	var gid := str(g.get("id", ""))
	var s = preload("res://src/ui/layers/sheet.gd").new()
	s.setup("Tagebuch", Library.display_title(g), 820)
	s.subheading_raw = true
	s.fill_func = func(sheet) -> void:
		var game := Library.get_game(gid)
		var add = SettingRow.new()
		add.setup("action", "Eintrag schreiben")
		add.icon_name = "edit"
		add.value_text = "Heute"
		add.set_meta("uz_key", "diary:new")
		add.on_activate = func() -> void: write_diary(main, game, 0, 0, func() -> void:
			if is_instance_valid(sheet):
				sheet.refill())
		sheet.add_row(add)
		var list := Backlog.diary_of(game)
		if list.is_empty():
			sheet.add_gap()
			sheet.add_label("Noch keine Einträge. Nach einer Runde bietet die Zusammenfassung „Ins Tagebuch“ an – mit Datum und Spielzeit.", "s", "faint")
			return
		sheet.add_gap()
		sheet.add_label(U.plural(list.size(), "Eintrag", "Einträge"))
		for e in list:
			var r = SettingRow.new()
			r.setup("info", TranslationServer.translate(entry_head(int(e.at), int(e.get("secs", 0)))))
			r.icon_name = "history"
			if str(e.get("note", "")) != "":
				r.subtitle = str(e.note)
				# Eigener Text: nicht übersetzen (der Kopf ist schon in der richtigen Sprache).
				r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			r.set_meta("uz_key", "diary:%d" % int(e.at))
			r.set_meta("uz_hint_y", "Löschen")
			var ed: Dictionary = e
			r.set_meta("uz_on_y", func() -> void: remove_diary(game, ed, func() -> void:
				if is_instance_valid(sheet):
					sheet.refill()))
			sheet.add_row(r)
	main.open_layer(s)


## Eintrag löschen – kurz zurücknehmbar (Undo).
static func remove_diary(g: Dictionary, e: Dictionary, done := Callable()) -> void:
	var gid := str(g.get("id", ""))
	var snap := Library.snapshot([gid])
	if Library.remove_diary(gid, int(e.get("at", 0))):
		Undo.offer_games("Eintrag gelöscht", Library.display_title(g), "trash", snap, done)
		_call(done)


## „12. März · 1 Std. 20 Min.“ – Kopf eines Tagebuch-Eintrags.
static func entry_head(at: int, secs: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var day := SessionSummary.day_text(at, bias, int(Time.get_unix_time_from_system()))
	return ("%s · %s" % [day, PlaytimePage.dur(secs)]) if secs > 0 else day


## In Listen legen oder herausnehmen: Auswahl aller Listen (Zusatz „Drin“, wo es schon drin ist) und
## „Neue Liste …“.
static func pick_lists(main: Main, g: Dictionary, done := Callable()) -> void:
	var gid := str(g.get("id", ""))
	var opts: Array = [[NEW, "Neue Liste …"]]
	for l in Library.lists:
		var inside := (l.get("games", []) as Array).has(gid)
		opts.append([str(l.id), str(l.name), "Drin – A nimmt es heraus" if inside else U.plural((l.games as Array).size(), "Spiel", "Spiele")])
	var cb := func(v: Variant) -> void:
		if str(v) == NEW:
			main.open_keyboard("Neue Liste", "", func(t: String) -> void:
				var nl := Library.new_list(t, gid)
				if not nl.is_empty():
					Toasts.show_toast("Neue Liste", "„%s“ · %s" % [str(nl.name), Library.display_title(g)], "list", { "sound": "select", "ms": 2400 })
				_call(done))
			return
		var l := Library.list_by_id(str(v))
		if l.is_empty():
			return
		var on := not (l.get("games", []) as Array).has(gid)
		Library.list_toggle(str(v), gid, on)
		Toasts.show_toast(("In „%s“" if on else "Aus „%s“ genommen") % str(l.name), Library.display_title(g), "list", { "sub_raw": true, "ms": 2200, "quiet": true })
		_call(done)
	main.open_choice("Listen", opts, null, cb, Library.display_title(g))


## Jahresziel: feste Zahlen, eigene Zahl über die Tastatur oder kein Ziel.
static func pick_goal(main: Main, year: int, done := Callable()) -> void:
	var cur := int(Library.goals.get(str(year), 0))
	var opts: Array = []
	for n in GOALS:
		opts.append([n, U.plural(n, "Spiel", "Spiele")])
	opts.append([-1, "Eigene Zahl …"])
	opts.append([0, "Kein Ziel"])
	var own := func(t: String) -> void:
		var n := t.strip_edges()
		if n.is_valid_int() and int(n) > 0:
			Library.set_goal(year, int(n))
			_call(done)
	var cb := func(v: Variant) -> void:
		if int(v) >= 0:
			Library.set_goal(year, int(v))
			_call(done)
			return
		main.open_keyboard("Wie viele Spiele %d durchspielen?" % year, str(cur) if cur > 0 else "", own)
	main.open_choice("Ziel für %d" % year, opts, cur if cur in GOALS or cur == 0 else -1, cb, "Durchgespielt und 100 % zählen")


## Eigener Text als kurzer Wert in einer Zeile: eine Zeile, höchstens n Zeichen.
static func _short(t: String, n: int) -> String:
	var one := t.replace("\n", " ").strip_edges()
	return one if one.length() <= n else one.left(n - 1).strip_edges() + "…"


static func _call(c: Callable) -> void:
	if c.is_valid():
		c.call()
