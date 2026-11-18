extends "res://src/ui/layers/layer.gd"
## „Was ist neu“ (Punkt 141): eine ruhige Karte unten über der Startseite – wie die kurze Tour –
## mit den wichtigsten Neuerungen in zwei Spalten, je ein Zeichen, Titel und ein Satz (in der
## Listen-Sprache: Zeichen leise wie in den Einstellungen, keine Scheiben). A oder B schließt.
## Fläche vor Schrift: die Karte steht sofort und steigt um W_ORT auf, ihre Schrift kommt kurz
## danach, die Punkte gestaffelt (höchstens vier Glieder). Kommt nach einem Update einmal von selbst (offer), sonst unter Einstellungen → System.
## Die Punkte stehen in data/neu.json (src/core/whats_new.gd), nie aus dem Netz.

const WN := preload("res://src/core/whats_new.gd")
const SELF := "res://src/ui/layers/whats_new.gd"
const WIDTH := 1180.0
const COL_W := 500.0

const Main := preload("res://src/main.gd")
var main: Main
var items: Array = []           ## [{ version, icon, title, text }] (WN.items)
var _panel: PanelContainer
var _ok: Button


static func _lang() -> String:
	return TranslationServer.get_locale().left(2)


## Beim Start (main._after_boot): nach einem Update einmal die Karte. fresh: allererster Start
## (Einrichtung) – dann merkt sich Uzai nur die Fassung. Liegt gerade etwas offen oder läuft ein
## Spiel, kommt sie beim nächsten Start.
static func offer(m: Main, fresh: bool, delay := 1.4) -> void:
	if Library.demo:
		return
	var seen := str(Config.get_value("system.seen_version", ""))
	var entries := WN.load_entries()
	if not WN.due(seen, Config.VERSION, fresh, entries):
		if seen != Config.VERSION:
			Config.set_value("system.seen_version", Config.VERSION)
		return
	await m.get_tree().create_timer(delay).timeout
	if not is_instance_valid(m) or Launcher.in_game or Nav.top_layer() != null:
		return
	open_for(m, WN.items(entries, seen, Config.VERSION, _lang()))
	Config.set_value("system.seen_version", Config.VERSION)


## Karte zeigen. Ohne Punkte (aus den Einstellungen): die der aktuellen Fassung, sonst die der
## neuesten davor.
static func open_for(m: Main, list: Array = []) -> Control:
	if list.is_empty():
		var entries := WN.load_entries()
		list = WN.items(entries, "", Config.VERSION, _lang())
		if list.is_empty():
			var older: Array = entries.keys().filter(func(v: String) -> bool: return WN.compare(v, Config.VERSION) < 0)
			older.sort_custom(func(a: String, b: String) -> bool: return WN.compare(a, b) > 0)
			if not older.is_empty():
				list = WN.items(entries, "", str(older[0]), _lang())
	var l = load(SELF).new()
	l.items = list
	m.open_layer(l)
	return l


func build() -> void:
	# Die Startseite bleibt dahinter zu sehen, ruhig abgedunkelt.
	dim = 0.55
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Schließen")
	_panel = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.content_margin_left = 52
	sb.content_margin_right = 52
	sb.content_margin_top = 44
	sb.content_margin_bottom = 40
	UzTheme.lift(sb, 3)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -WIDTH * 0.5
	_panel.offset_right = WIDTH * 0.5
	_panel.offset_bottom = -130
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	var col := U.vbox(30)
	_panel.add_child(col)
	# Eine Überschrift: „Neu in Uzai 0.16“ und darunter „Was ist neu“ sagten dasselbe zweimal.
	var ver := str(items[0].version) if not items.is_empty() else Config.VERSION
	col.add_child(U.label("Neu in Uzai %s" % ver, "xl", "text", "black"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 56)
	grid.add_theme_constant_override("v_separation", 26)
	col.add_child(grid)
	for it in items:
		grid.add_child(_item(it))
	if items.is_empty():
		grid.add_child(U.label("Zu dieser Fassung gibt es keine Liste.", "m", "muted"))
	var foot := U.hbox(14)
	col.add_child(foot)
	foot.add_child(U.label("Später wieder: Einstellungen → System → „Was ist neu“", "s", "faint", "regular"))
	foot.add_child(U.spacer())
	_ok = U.button("OK", "check", "primary")
	_ok.custom_minimum_size = Vector2(220, 56)
	_ok.set_meta("uz_default", true)
	_ok.set_meta("uz_hint_a", "OK")
	_ok.pressed.connect(close)
	foot.add_child(_ok)
	# Die Punkte folgen gestaffelt (U.staffel), nach der Schrift der Karte.
	var i := 0
	for c in grid.get_children():
		(c as Control).modulate.a = 0.0
		U.ankommen(c, U.T_ORT, "uz_punkt").tween_property(c, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_FLAECHE + U.staffel(i))
		i += 1


## Fläche vor Schrift (layer.gd): die Karte.
func flaeche() -> Control:
	return _panel


## Steigt um W_ORT von unten auf (Kurve „Ankommen“, T_RAUM).
func _enter_motion(fl: Control) -> void:
	var w := U.weg_px(U.W_ORT)
	if w == 0.0:
		return
	U.ankommen(fl, U.T_RAUM, "uz_karte").tween_property(fl, "offset_bottom", -130.0, U.T_RAUM).from(-130.0 + w)


## Zeichen leise (wie in den Einstellungen), daneben Titel und Satz.
func _item(it: Dictionary) -> Control:
	var row := U.hbox(20)
	row.custom_minimum_size = Vector2(COL_W, 0)
	var ic := U.icon(str(it.get("icon", "spark")), 26, "muted")
	ic.custom_minimum_size = Vector2(26, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var tc := U.vbox(4)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tc)
	tc.add_child(U.label(str(it.get("title", "")), "m", "text", "bold"))
	var t := U.label(str(it.get("text", "")), "s", "muted", "regular", true)
	t.custom_minimum_size = Vector2(COL_W - 46.0, 0)
	tc.add_child(t)
	return row


func _first_focus() -> Control:
	return _ok


func _exit_motion(tw: Tween) -> void:
	if is_instance_valid(_panel):
		U.stop(_panel, "uz_karte")
		tw.set_parallel(true)
		tw.tween_property(_panel, "position:y", _panel.position.y + U.weg_px(U.W_ORT), U.T_WEG)
