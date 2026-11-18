extends "res://src/ui/layers/sheet.gd"
## Lösungshilfe (Guide → Spiel, Punkt 111; Regeln in src/core/walkthrough.gd). Erst wählen, wonach
## gesucht wird: Themen (Komplettlösung, Bosse …), die zuletzt gesuchten Wörter dieses Spiels
## (Y vergisst eins) oder „Eigenes Suchwort …“ (Bildschirmtastatur, auch per Handy). Dann die
## Treffer als ruhige Liste – A spielt das Video als Bild in Bild über dem Spiel: Guide zu, das
## Spiel bleibt vorn, gesteuert wird im Guide (Reiter „Bild in Bild“). B führt von den Treffern
## zurück zu den Themen.

const Walkthrough := preload("res://src/core/walkthrough.gd")
const Zustand := preload("res://src/core/zustand.gd")
## Lösungshilfe: Themen wählen, Treffer einer Suche (B zurück zu den Themen).
const ZUSTAENDE := { "themen": ["treffer"], "treffer": ["themen"] }

const Main := preload("res://src/main.gd")
var main: Main
var guide: Control                ## der offene Guide; geht beim Abspielen zu
var game: Dictionary
var _page := "themen":            ## "themen" oder "treffer"
	set(neu):
		Zustand.wechsel("loesungshilfe.seite", ZUSTAENDE, _page, neu)
		_page = neu
var _topic := ""
var _term := ""
var _results: Array = []
var _loading := false
var _gen := 0                     ## jede neue Suche zählt hoch; ältere Antworten fallen weg
var _back_key := ""               ## zurück zu den Themen: diese Zeile wieder wählen


static func open_for(g: Control) -> void:
	var s = load("res://src/ui/layers/walkthrough_sheet.gd").new()
	s.main = g.main
	s.guide = g
	s.game = Launcher.current
	s.setup("Lösungshilfe", "%s  ·  Videos von YouTube, klein in der Ecke" % Library.display_title(Launcher.current), 820)
	g.main.open_layer(s)


## Ebene weg: ihre Seite aus Zustand.lage() (kein alter Stand im Fehlerbericht).
func _exit_tree() -> void:
	Zustand.vergessen("loesungshilfe.seite")


func fill() -> void:
	if _page == "treffer":
		_fill_results()
	else:
		_fill_topics()


func _fill_topics() -> void:
	add_label("Suchen nach")
	for tp in Walkthrough.TOPICS:
		var id := str(tp[0])
		var r = SettingRow.new()
		r.setup("action", str(tp[1]), "")
		r.icon_name = str(tp[2])
		r.set_meta("uz_key", "wt:" + id)
		r.set_meta("uz_hint_a", "Suchen")
		r.on_activate = func() -> void: _search(id, "", "wt:" + id)
		add_row(r)
	var own = SettingRow.new()
	own.setup("action", "Eigenes Suchwort …", "")
	own.icon_name = "keyboard"
	own.subtitle = "Etwa „Boss Malenia“ – auch per Handy"
	own.set_meta("uz_key", "wt:own")
	own.set_meta("uz_hint_a", "Eingeben")
	own.on_activate = _ask_term
	add_row(own)
	var terms := Walkthrough.remembered(_gid())
	if terms.is_empty():
		return
	add_gap()
	add_label("Zuletzt gesucht")
	for t in terms:
		var term := str(t)
		var r = SettingRow.new()
		r.setup("action", term, "")
		r.icon_name = "history"
		r.set_meta("uz_key", "wt:t:" + term)
		r.set_meta("uz_hint_a", "Suchen")
		r.set_meta("uz_hint_y", "Vergessen")
		r.set_meta("uz_on_y", func() -> void: _forget(term))
		r.on_activate = func() -> void: _search("", term, "wt:t:" + term)
		add_row(r)


func _fill_results() -> void:
	var what := "„%s“" % _term if _term != "" else str(Walkthrough.topic_of(_topic)[1])
	add_label(what, "m", "muted")
	if _loading:
		var r = SettingRow.new()
		r.setup("info", "Sucht auf YouTube …", "")
		r.icon_name = "search"
		add_row(r)
		return
	if _results.is_empty():
		add_label("Nichts gefunden.", "s", "faint")
		if YouTube.error != "":
			add_label(YouTube.error, "s", "faint")
		var again = SettingRow.new()
		again.setup("action", "Anderes Suchwort …", "")
		again.icon_name = "keyboard"
		again.set_meta("uz_hint_a", "Eingeben")
		again.on_activate = _ask_term
		add_row(again)
		return
	for i in _results.size():
		var v: Dictionary = _results[i]
		var r = SettingRow.new()
		r.setup("action", str(v.get("title", "Video")), "")
		r.icon_name = "video"
		r.subtitle = Walkthrough.line_of(v)
		r.set_meta("uz_key", "wt:v:" + str(v.id))
		r.set_meta("uz_hint_a", "In der Ecke ansehen")
		var idx := i
		r.on_activate = func() -> void: _play(idx)
		add_row(r)


func _gid() -> String:
	return str(game.get("id", ""))


## Seite neu aufbauen und eine Zeile wählen (key "" = die erste).
func _show(key := "") -> void:
	U.clear(content)
	fill()
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var items := Nav.focusables(content)
	var pick: Control = items[0] if not items.is_empty() else null
	for it in items:
		if key != "" and str(it.get_meta("uz_key", "")) == key:
			pick = it
	if pick:
		Nav.focus(pick, true)
	Nav.focus_moved.emit(Nav.focused())


func _search(topic: String, term: String, from_key: String) -> void:
	_topic = topic
	_term = term
	_back_key = from_key
	if term != "":
		Walkthrough.keep(_gid(), term)
	_page = "treffer"
	_loading = true
	_results = []
	_gen += 1
	var gen := _gen
	await _show()
	var found: Array = await Walkthrough.search(Library.display_title(game), topic, term)
	if gen != _gen or _page != "treffer" or not is_inside_tree():
		return
	_loading = false
	_results = found
	await _show()


func _ask_term() -> void:
	main.open_keyboard("Suchwort für %s" % Library.display_title(game), "", func(t: String) -> void:
		var c := Walkthrough.clean_term(t)
		if c != "" and is_inside_tree():
			_search("", c, "wt:t:" + c)
	)


func _forget(term: String) -> void:
	Walkthrough.drop(_gid(), term)
	var items := Nav.focusables(content)
	var at := items.find(Nav.focused())
	U.clear(content)
	fill()
	await get_tree().process_frame
	items = Nav.focusables(content)
	if not items.is_empty():
		Nav.focus(items[clampi(at, 0, items.size() - 1)], true)


## Gewähltes Video als Bild in Bild über dem Spiel. Läuft schon eins in der Ecke: dort das neue
## (dieselbe mpv-Sitzung, Pip passt die Lage an). Läuft ein Video anders (nur Ton): erst beenden.
func _play(idx: int) -> void:
	var list := _results.duplicate()
	var pip: Node = main.pip
	close()
	if is_instance_valid(guide):
		guide.close()
	if pip.active() and Video.pip:
		Video.play(list, idx, { "pip": true })
		return
	if Video.active:
		Video.stop()
	pip.start(list, idx)


func nav_command(cmd: String) -> bool:
	if cmd == "b" and _page == "treffer":
		Sfx.play("back")
		_gen += 1
		_page = "themen"
		_loading = false
		_show(_back_key)
		return true
	return super(cmd)
