extends "res://src/ui/layers/modal.gd"
## Nach dem Spielen (Punkt 24): was die letzte Runde gebracht hat – Zeit, neue Erfolge, Clips und
## Bildschirmfotos, ein erreichter Meilenstein und wie weit es noch bis 100 % ist. Geht nie von
## selbst auf: über die Karte „Gerade gespielt“ unter „Für dich“ oder die Mitteilung nach dem
## Spiel. Die Zahlen rechnet src/core/session_summary.gd; abschaltbar unter Einstellungen → Spiele.

const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")
const SessionSummary := preload("res://src/core/session_summary.gd")
const Backlog := preload("res://src/library/backlog.gd")
const BacklogFlow := preload("res://src/ui/backlog_flow.gd")

const SHOWN := 3              ## so viele neue Erfolge stehen mit Namen da

const Main := preload("res://src/main.gd")
var main: Main
var game: Dictionary = {}
var data: Dictionary = {}     ## SessionSummary.make


func build() -> void:
	width = 1160.0
	set_meta("uz_hint_b", "Schließen")
	super()


func fill() -> void:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var now := int(Time.get_unix_time_from_system())
	var secs := int(data.get("secs", 0))
	var end := int(data.get("end", now))
	var h24 := bool(Config.get_value("theme.clock_24h", true))
	var head := U.hbox(36)
	head.add_child(PlaytimePage.cover_clip(game, Vector2(150, 200), UzTheme.r_cover()))
	var col := U.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(U.label("Gerade gespielt", "s", "accent", "bold"))
	var name_l := U.ellipsis(U.label(Library.display_title(game), "xxl", "text", "black"))
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels: nie übersetzen
	col.add_child(name_l)
	col.add_child(U.label("%s · %s – %s" % [SessionSummary.day_text(end - secs, bias, now), SessionSummary.clock(end - secs, bias, h24),
		SessionSummary.clock(end, bias, h24)], "m", "muted", "medium"))
	head.add_child(col)
	box.add_child(head)
	var mark := int(data.get("mark", 0))
	if mark > 0:
		box.add_child(_milestone(mark))
	box.add_child(_figures())
	var got: Array = data.get("unlocks", [])
	if int(data.get("total", 0)) > 0 or not got.is_empty():
		box.add_child(_achievements(got))
	box.add_child(U.spacer(0, 6, false))
	box.add_child(_buttons(got))


## Erreichte Stunden-Marke: ein ruhiges Band in der Akzentfarbe.
func _milestone(mark: int) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("accent", 0.12), UzTheme.radius, 1, UzTheme.col("accent", 0.35))
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", sb)
	var row := U.hbox(16)
	row.add_child(U.icon("star_f", 30, "accent"))
	var t := U.label("%s geschafft" % U.plural(mark, "Stunde", "Stunden"), "l", "text", "bold")
	t.clip_text = false
	row.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(U.label("Meilenstein", "s", "accent", "bold"))
	p.add_child(row)
	return p


## Diesmal, insgesamt, neue Erfolge, Aufnahmen – was null ist, fehlt.
func _figures() -> Control:
	var row := U.hbox(72)
	var got := (data.get("unlocks", []) as Array).size()
	var caps := int(data.get("clips", 0)) + int(data.get("shots", 0))
	var list: Array = [[PlaytimePage.dur(int(data.get("secs", 0))), "diesmal"], [PlaytimePage.dur(int(data.get("after", 0))), "insgesamt"]]
	if got > 0:
		list.append([str(got), "neuer Erfolg" if got == 1 else "neue Erfolge"])
	if caps > 0:
		list.append([str(caps), _caps_word()])
	for kv in list:
		var v := U.vbox(2)
		v.add_child(U.label(str(kv[0]), "xl", "text", "black"))
		v.add_child(U.label(str(kv[1]), "s", "muted", "medium"))
		row.add_child(v)
	return row


func _caps_word() -> String:
	var clips := int(data.get("clips", 0))
	var shots := int(data.get("shots", 0))
	if shots == 0:
		return "Clip" if clips == 1 else "Clips"
	if clips == 0:
		return "Bildschirmfoto" if shots == 1 else "Bildschirmfotos"
	return "Aufnahmen"


## Fortschritt bis 100 % (der Balken wächst von vor der Runde auf jetzt) und die neuen Erfolge.
func _achievements(got: Array) -> Control:
	var v := U.vbox(12)
	var total := int(data.get("total", 0))
	var have := int(data.get("have", 0))
	if total > 0:
		var row := U.hbox(14)
		var t := U.label("Erfolge", "m", "text", "bold")
		t.clip_text = false
		row.add_child(t)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		var pct := floori(100.0 * have / total)
		var right := U.label("Alle geschafft" if have >= total else "%d von %d · %d %%" % [have, total, pct], "m", "accent" if have >= total else "muted", "medium")
		right.clip_text = false
		row.add_child(right)
		v.add_child(row)
		var bar = ProgressBarUz.new().setup(float(maxi(0, have - got.size())) / total, "gold" if have >= total else "accent", 8)
		v.add_child(bar)
		var to := float(have) / total
		create_tween().tween_method(Callable(bar, "set_value"), float(bar.value), to, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.35)
	for e in got.slice(0, SHOWN):
		var r := U.hbox(14)
		r.add_child(U.icon("trophy", 24, "accent"))
		# Name und Beschreibung des Erfolgs kommen vom Dienst, in dessen Sprache: nie übersetzen.
		var n := U.label(str(e.get("name", "")), "m", "text", "medium")
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.clip_text = false
		r.add_child(n)
		if str(e.get("desc", "")) != "":
			var dl := U.ellipsis(U.label(str(e.desc), "s", "muted", "regular"))
			dl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			r.add_child(dl)
		v.add_child(r)
	if got.size() > SHOWN:
		v.add_child(U.label("und %d weitere" % (got.size() - SHOWN), "s", "faint", "medium"))
	return v


## Erfolge und Aufnahmen öffnen sich über der Zusammenfassung (B führt zurück hierher).
func _buttons(got: Array) -> Control:
	var row := U.hbox(14)
	row.set_meta("uz_row", true)
	var g := game
	var list: Array = []
	if int(data.get("total", 0)) > 0 or not got.is_empty():
		list.append(["Erfolge ansehen", "trophy", func() -> void: main.open_game_achievements(g)])
	var newest := str(data.get("newest", ""))
	if newest != "":
		list.append(["Aufnahmen ansehen", "image", func() -> void: main.open_captures(newest)])
	# Tagebuch (Roadmap 2): nur ein Angebot – gespeichert wird erst, wenn du den Text bestätigst.
	var secs := int(data.get("secs", 0))
	var end := int(data.get("end", 0))
	if secs >= Backlog.DIARY_MIN_SECS and end > 0 and not Backlog.has_entry(Library.get_game(str(g.get("id", ""))), end):
		list.append(["Ins Tagebuch", "history", func() -> void: BacklogFlow.write_diary(main, g, end, secs, _refresh)])
	list.append(["Zum Spiel", "games", func() -> void: main.open_game(g)])
	list.append(["Schließen", "close", close])
	for i in list.size():
		var b := U.button(str(list[i][0]), str(list[i][1]), "primary" if i == 0 else "normal")
		b.pressed.connect(list[i][2] as Callable)
		if i == 0:
			b.set_meta("uz_default", true)
		row.add_child(b)
	return row


## Nach dem Eintrag ins Tagebuch: Knöpfe neu (der Knopf fällt weg), die Auswahl steht wieder vorn.
func _refresh() -> void:
	if not is_instance_valid(box):
		return
	U.clear(box)
	fill()
	await get_tree().process_frame
	var d := Nav.default_in(self)
	if d:
		Nav.focus(d, true)
