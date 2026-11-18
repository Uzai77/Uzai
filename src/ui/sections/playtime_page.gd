extends RefCounted
## Spielzeit wie ein Jahresrückblick einer Konsole: erzählt über die Spiele selbst statt über
## Zahlenkacheln. Oben das Spiel der Woche mit den letzten sieben Tagen und „Weiterspielen“,
## darunter „Dein Rückblick“ (die große Zahl, wo du spielst, und vier Dinge, die auffallen),
## die meistgespielten Spiele als Cover und der Verlauf nach Tagen.

const U := preload("res://src/ui/u.gd")
const Lang := preload("res://src/core/lang.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const CoverArt := preload("res://src/ui/components/cover_art.gd")
const WeekChart := preload("res://src/ui/components/week_chart.gd")
const SplitBar := preload("res://src/ui/components/split_bar.gd")
const StatTile := preload("res://src/ui/components/ach/stat_tile.gd")
const SessionSummary := preload("res://src/core/session_summary.gd")

const DAYS_SHORT := ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
const DAYS_LONG := ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
const DAYS_PLURAL := ["Sonntagen", "Montagen", "Dienstagen", "Mittwochen", "Donnerstagen", "Freitagen", "Samstagen"]

var view: Control
var gutter := 96
var _bias := 0
var _today := 0
var _days := {}           # Tag -> { Spiel-ID -> { secs, n, start, end } }
var _sessions: Array = []


func build(v: Control, col: VBoxContainer) -> void:
	view = v
	_bias = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var now := int(Time.get_unix_time_from_system())
	_today = _day(now)
	_sessions = Library.load_sessions()
	_collect(_sessions)
	# Gekaufte, nie installierte Epic-Spiele gehören nicht in die Spielzeit.
	var games: Array = Library.visible_games().filter(func(g): return not Library.owned_only(g))
	# Die Spielzeit je Spiel einmal holen (sie fragt auch die Doppelten in anderen Launchern ab), dann danach
	# ordnen – früher bei jedem Vergleich zweimal.
	var mit_zeit: Array = []
	for g in games:
		var zeit: int = Library.playtime(g)
		if zeit > 0:
			mit_zeit.append([zeit, g])
	mit_zeit.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	var top: Array = mit_zeit.map(func(e): return e[1])
	if _days.is_empty() and top.is_empty():
		col.add_child(_empty())
		return
	col.add_child(_hero(top))
	_review(col, games)
	# Bis hierher reicht der erste Bildschirm; der Rest nach dem Hereingleiten (achievements_view.gd nachbau).
	var unten: Array = []
	if not top.is_empty():
		unten.append(func() -> void:
			col.add_child(view.section_title("Meistgespielt", "seit Beginn"))
			var shelf = Shelf.new().setup("play:top", 30, true, 18, gutter)
			col.add_child(shelf)
			for g in top.slice(0, 12):
				shelf.add(_top_item(g)))
	unten.append(func() -> void: _history(col))
	if view.has_method("nachbau"):
		view.call("nachbau", col, unten)
	else:
		for s in unten:
			(s as Callable).call()


# --- Daten ------------------------------------------------------------------------------

func _day(unix: int) -> int:
	return int(floor(float(unix + _bias) / 86400.0))


func _collect(sessions: Array) -> void:
	_days.clear()
	for se in sessions:
		var end := int(se.get("at", 0))
		var secs := int(se.get("secs", 0))
		if end <= 0 or secs <= 0:
			continue
		var d := _day(end)
		var per: Dictionary = _days.get(d, {})
		var id := str(se.get("id", ""))
		var e: Dictionary = per.get(id, { "secs": 0, "n": 0, "start": end - secs, "end": end })
		e.secs = int(e.secs) + secs
		e.n = int(e.n) + 1
		e.start = mini(int(e.start), end - secs)
		e.end = maxi(int(e.end), end)
		per[id] = e
		_days[d] = per


func _day_total(d: int) -> int:
	var t := 0
	for e in _days.get(d, {}).values():
		t += int(e.secs)
	return t


func _streak() -> int:
	var d := _today if _days.has(_today) else _today - 1
	var n := 0
	while _days.has(d):
		n += 1
		d -= 1
	return n


## Längste Folge von Tagen mit Spielzeit (irgendwann).
func _best_streak() -> int:
	var keys: Array = _days.keys()
	keys.sort()
	var best := 0
	var run := 0
	var last := -10
	for d in keys:
		run = run + 1 if int(d) == last + 1 else 1
		last = int(d)
		best = maxi(best, run)
	return best


func _weekday(d: int) -> int:
	# Tag 0 (1.1.1970) war ein Donnerstag.
	return (d + 4) % 7


func _day_name(d: int) -> String:
	if d == _today:
		return "Heute"
	if d == _today - 1:
		return "Gestern"
	var dt := Time.get_date_dict_from_unix_time(d * 86400)
	return "%s, %s" % [TranslationServer.translate(DAYS_LONG[_weekday(d)]), Lang.date_text(int(dt.day), int(dt.month))]


func _short_date(unix: int) -> String:
	var dt := Time.get_date_dict_from_unix_time(unix + _bias)
	return Lang.date_text(int(dt.day), int(dt.month))


func _clock(unix: int) -> String:
	var t := Time.get_time_dict_from_unix_time(unix + _bias)
	if Config.get_value("theme.clock_24h", true):
		return "%02d:%02d" % [t.hour, t.minute]
	var h: int = int(t.hour) % 12
	return "%d:%02d %s" % [12 if h == 0 else h, t.minute, "PM" if int(t.hour) >= 12 else "AM"]


## "45 Min.", "2 Std. 5 Min.", "64 Std.", "1.284 Std."
static func dur(secs: int) -> String:
	if secs < 60:
		return "< 1 Min."
	var m := floori(secs / 60.0)
	if m < 60:
		return "%d Min." % m
	var h := floori(m / 60.0)
	if h < 10 and m % 60 > 0:
		return "%d Std. %d Min." % [h, m % 60]
	return "%s Std." % _thousands(h)


static func _thousands(n: int) -> String:
	return Lang.tausender(n)


static func _sys_name(id: String) -> String:
	var sys := Config.system(id)
	if not sys.is_empty():
		return str(sys.get("name", id))
	return Library.store_name({ "source": id }, false, "PC" if id == "" else id)


## Farbe eines Systems, auf dunklem Grund gut sichtbar.
static func _sys_color(id: String) -> Color:
	var sys := Config.system(id)
	var c: Color
	if not sys.is_empty():
		c = Color(str(sys.get("color", "#8a8f99")))
	elif id == "steam":
		c = UzTheme.col("steam")
	elif id == "epic":
		c = Color("#2f6fde")
	elif id == "ea":
		c = Color("#ff8c42")
	elif Library.Stores.is_extra(id):
		c = Color(Library.Stores.color_of(id)).lightened(0.35)
	else:
		c = UzTheme.col("muted")
	if not UzTheme.light and c.get_luminance() < 0.32:
		c = c.lerp(Color.WHITE, 0.32)
	return c


# --- Oben: das Spiel der Woche -----------------------------------------------------------

func _hero(top: Array) -> Control:
	var w := _woche(top)
	var game: Dictionary = w.game
	var weekly := int(w.total) > 0
	var card := _hero_flaeche(game)
	var m := U.margin(48, 44, 56, 44)
	U.full_rect(m)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var row := U.hbox(48)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	if not game.is_empty():
		row.add_child(_box_art(game, Vector2(234, 312)))
	_hero_text(row, game, w)
	if weekly:
		var chart = WeekChart.new().setup(w.week, w.labels)
		chart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chart)
	var wrap := U.margin(gutter, 0, gutter, 0)
	wrap.add_child(card)
	return wrap


## Die letzten sieben Tage: Sekunden je Tag mit Beschriftung, Summe, Tage mit Spiel und das meistgespielte Spiel
## der Woche (ohne Woche: das meistgespielte überhaupt).
func _woche(top: Array) -> Dictionary:
	var week: Array = []
	var labels: Array = []
	var week_total := 0
	var week_games := {}
	var played_days := 0
	for i in 7:
		var d := _today - 6 + i
		var t := _day_total(d)
		week.append(t)
		labels.append("Heute" if i == 6 else DAYS_SHORT[_weekday(d)])
		week_total += t
		if t > 0:
			played_days += 1
		for id in _days.get(d, {}).keys():
			week_games[id] = int(week_games.get(id, 0)) + int(_days[d][id].secs)
	var game: Dictionary = {}
	var game_secs := 0
	var ids: Array = week_games.keys()
	ids.sort_custom(func(a, b): return int(week_games[a]) > int(week_games[b]))
	for id in ids:
		game = Library.get_game(str(id))
		if not game.is_empty():
			game_secs = int(week_games[id])
			break
	if game.is_empty() and not top.is_empty():
		game = top[0]
	return { "week": week, "labels": labels, "total": week_total, "days": played_days, "game": game, "game_secs": game_secs }


## Die Fläche hinter dem Text: Licht in der Farbe des Systems, darüber das große Bild des Spiels.
func _hero_flaeche(game: Dictionary) -> Control:
	# Eine ruhige Fläche (nicht wählbar); gewählt wird der helle Knopf darin.
	var card := Control.new()
	card.custom_minimum_size = Vector2(0, 400)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rad := UzTheme.r_panel()
	# Licht in der Farbe des Systems; das große Bild legt sich darüber, sobald es da ist.
	var sys_c := _sys_color(str(game.get("system", "")))
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), rad))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(clip)
	card.add_child(clip)
	var glow := TextureRect.new()
	glow.texture = _radial()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(sys_c, 0.34)
	glow.position = Vector2(-260, -330)
	glow.size = Vector2(1060, 1060)
	clip.add_child(glow)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(art)
	art.modulate.a = 0.0
	clip.add_child(art)
	var shade := TextureRect.new()
	var g := Gradient.new()
	var bg := UzTheme.col("surface_hi")
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.66, 1.0])
	g.colors = PackedColorArray([Color(bg, 0.96), Color(bg, 0.8), Color(bg, 0.55), Color(bg, 0.88)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(shade)
	clip.add_child(shade)
	if not game.is_empty():
		var wart: WeakRef = weakref(art)
		Media.game_texture(game, "hero", func(t: Texture2D) -> void:
			var a: TextureRect = wart.get_ref()
			if a and t:
				a.texture = t
				a.create_tween().tween_property(a, "modulate:a", 1.0, 0.5)
		)
	return card


## Die Textspalte: die Woche in Zahlen (oder das meistgespielte Spiel) und die beiden Knöpfe.
func _hero_text(row: Control, game: Dictionary, w: Dictionary) -> void:
	var weekly := int(w.total) > 0
	var week_total := int(w.total)
	var game_secs := int(w.game_secs)
	var played_days := int(w.days)
	var text := U.vbox(4)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var title := Library.display_title(game) if not game.is_empty() else ""
	if weekly:
		text.add_child(U.label("Letzte 7 Tage", "m", "muted", "medium"))
		var big := U.label(dur(week_total), "hero", "text", "black")
		big.clip_text = false
		text.add_child(big)
		text.add_child(U.spacer(0, 8, false))
		if title != "":
			var line := U.hbox(10)
			line.add_child(U.label("davon", "l", "muted"))
			line.add_child(U.label(dur(game_secs), "l", "text", "bold"))
			line.add_child(U.label("mit", "l", "muted"))
			var tl := U.ellipsis(U.label(title, "l", "text", "bold"))
			tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels: nie übersetzen
			tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(tl)
			text.add_child(line)
		var st := _streak()
		var foot := U.hbox(10)
		if st >= 2:
			foot.add_child(U.icon("spark", 22, "accent"))
			foot.add_child(U.label("Seit %d Tagen jeden Tag gespielt" % st, "m", "text", "medium"))
		else:
			foot.add_child(U.label("An %d von 7 Tagen gespielt" % played_days, "m", "muted", "medium"))
		text.add_child(foot)
	else:
		text.add_child(U.label("Am meisten gespielt", "m", "muted", "medium"))
		var big2 := U.ellipsis(U.label(title, "xxl", "text", "black"))
		big2.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		text.add_child(big2)
		text.add_child(U.spacer(0, 8, false))
		var sub := dur(Library.playtime(game)) + " insgesamt"
		var last := Library.last_played(game)
		if last > 0:
			sub += "  ·  " + tr("zuletzt %s") % U.lower_first(tr(U.ago(last)))
		text.add_child(U.label(sub, "l", "muted"))
		text.add_child(U.label("Diese Woche war Pause. Zeit für eine Runde?", "m", "faint", "medium"))
	if not game.is_empty():
		text.add_child(U.spacer(0, 22, false))
		var brow := U.hbox(14)
		var play := U.button("Weiterspielen" if weekly else "Spielen", "play", "primary")
		play.set_meta("uz_default", true)
		play.set_meta("uz_key", "play:hero")
		play.set_meta("uz_hint_a", "Spielen")
		play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var gd := game
		play.pressed.connect(func() -> void: _play(gd))
		brow.add_child(play)
		var page := U.button("Zum Spiel", "", "flat")
		page.set_meta("uz_key", "play:page")
		page.set_meta("uz_hint_a", "Öffnen")
		page.pressed.connect(func() -> void: view.main.open_game(gd))
		brow.add_child(page)
		text.add_child(brow)


## Cover mit Schatten, wie eine Spielhülle.
func _box_art(game: Dictionary, sz: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = sz
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Panel.new()
	var ssb := UzTheme.card(UzTheme.col("surface"), UzTheme.r_cover())
	ssb.shadow_size = 26
	ssb.shadow_offset = Vector2(0, 10)
	ssb.shadow_color = Color(0, 0, 0, 0.5)
	sh.add_theme_stylebox_override("panel", ssb)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(sh)
	holder.add_child(sh)
	holder.add_child(cover_clip(game, Vector2.ZERO, UzTheme.r_cover()))
	return holder


## Cover in abgerundetem Rahmen (Ersatzbild, bis das echte da ist).
static func cover_clip(game: Dictionary, sz: Vector2, r := -1) -> Control:
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), r))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sz == Vector2.ZERO:
		U.full_rect(clip)
	else:
		clip.custom_minimum_size = sz
		clip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ca = CoverArt.new()
	ca.compact = sz != Vector2.ZERO and sz.x < 150
	U.full_rect(ca)
	clip.add_child(ca)
	ca.setup(game)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(tr)
	clip.add_child(tr)
	var wtr: WeakRef = weakref(tr)
	Media.game_texture(game, "cover", func(t: Texture2D) -> void:
		var rr: TextureRect = wtr.get_ref()
		if rr and t:
			rr.texture = t
	)
	return clip


static var _glow_tex: GradientTexture2D


static func _radial() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 256
		_glow_tex.height = 256
	return _glow_tex


# --- Dein Rückblick ----------------------------------------------------------------------

## Die große Zahl, wo du spielst (Aufteilung nach System) und vier Dinge, die auffallen.
func _review(col: VBoxContainer, games: Array) -> void:
	var by := {}
	var total := 0
	var count := 0
	for g in games:
		var p := Library.playtime(g)
		if p <= 0:
			continue
		count += 1
		total += p
		var k := str(g.get("system", ""))
		by[k] = int(by.get(k, 0)) + p
	var tiles := _highlights()
	if total <= 0 and tiles.is_empty():
		return
	col.add_child(U.spacer(0, 6, false))
	col.add_child(view.section_title("Dein Rückblick"))
	var m := U.margin(gutter, 0, gutter, 0)
	var v := U.vbox(20)
	m.add_child(v)
	if total > 0:
		var head := U.hbox(18)
		var tl := U.label(dur(total), "hero", "text", "black")
		tl.clip_text = false
		head.add_child(tl)
		var sl := U.label("gespielt, verteilt auf %s" % U.plural(count, "Spiel", "Spiele"), "l", "muted")
		sl.clip_text = false
		var slm := U.margin(0, 0, 0, 12)
		slm.size_flags_vertical = Control.SIZE_SHRINK_END
		slm.add_child(sl)
		head.add_child(slm)
		v.add_child(head)
		var keys: Array = by.keys()
		keys.sort_custom(func(a, b): return int(by[a]) > int(by[b]))
		if keys.size() >= 2:
			var parts: Array = []
			var shown := keys.slice(0, 6)
			var rest := 0
			for k in keys.slice(6):
				rest += int(by[k])
			for k in shown:
				parts.append({ "value": by[k], "color": _sys_color(str(k)) })
			if rest > 0:
				parts.append({ "value": rest, "color": UzTheme.col("faint") })
			v.add_child(SplitBar.new().setup(parts, 16))
			var legend := HFlowContainer.new()
			legend.add_theme_constant_override("h_separation", 44)
			legend.add_theme_constant_override("v_separation", 10)
			legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for i in shown.size():
				legend.add_child(_legend_item(_sys_name(str(shown[i])), int(by[shown[i]]), total, parts[i].color))
			if rest > 0:
				legend.add_child(_legend_item("Andere", rest, total, UzTheme.col("faint")))
			v.add_child(legend)
	col.add_child(m)
	if tiles.is_empty():
		return
	var tm := U.margin(gutter, 4, gutter, 0)
	var row := U.hbox(24)
	row.set_meta("uz_group", "play:review")
	tm.add_child(row)
	for t in tiles:
		row.add_child(t)
	col.add_child(tm)


func _legend_item(name_: String, secs: int, total: int, c: Color) -> Control:
	var h := U.hbox(10)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", UzTheme.box(c, 6))
	h.add_child(dot)
	h.add_child(U.label(name_, "s", "text", "medium"))
	var share := int(round(100.0 * float(secs) / maxf(1.0, float(total))))
	h.add_child(U.label("%s · %d %%" % [dur(secs), share] if share >= 1 else dur(secs), "s", "muted"))
	return h


## Vier Kacheln aus den eigenen Runden: längste Runde, Lieblingstag, Tageszeit, längste Serie.
func _highlights() -> Array:
	var out: Array = []
	var valid: Array = []
	for se in _sessions:
		if int(se.get("secs", 0)) > 0 and int(se.get("at", 0)) > 0 and not Library.get_game(str(se.get("id", ""))).is_empty():
			valid.append(se)
	if valid.size() < 3:
		return out
	# Längste Runde
	var best: Dictionary = valid[0]
	for se in valid:
		if int(se.secs) > int(best.secs):
			best = se
	var bg := Library.get_game(str(best.id))
	var t1 = StatTile.new().setup("clock", "Längste Runde", dur(int(best.secs)),
		"%s, am %s" % [Library.display_title(bg), _short_date(int(best.at))])
	t1.set_meta("uz_key", "play:hl:longest")
	t1.set_meta("uz_hint_a", "Öffnen")
	t1.chosen.connect(func() -> void: view.main.open_game(bg))
	out.append(t1)
	# Lieblingstag: an welchem Wochentag im Schnitt am meisten
	var sum := [0, 0, 0, 0, 0, 0, 0]
	var seen := [0, 0, 0, 0, 0, 0, 0]
	for d in _days.keys():
		var wd := _weekday(int(d))
		sum[wd] += _day_total(int(d))
		seen[wd] += 1
	var wbest := 0
	var wavg := 0.0
	for wd in 7:
		if int(seen[wd]) > 0 and float(sum[wd]) / int(seen[wd]) > wavg:
			wavg = float(sum[wd]) / int(seen[wd])
			wbest = wd
	out.append(_info_tile("history", "Lieblingstag", str(DAYS_LONG[wbest]),
		"An %s spielst du im Schnitt %s" % [DAYS_PLURAL[wbest], dur(int(wavg))], "day"))
	# Tageszeit: wann die meisten Runden beginnen
	var peak := SessionSummary.peak_hour(valid, _bias)
	var part := SessionSummary.daypart(peak)
	out.append(_info_tile(str(part[1]), "Tageszeit", str(part[0]), "Die meisten Runden beginnen gegen %d Uhr." % peak, "time"))
	# Längste Serie
	var bs := _best_streak()
	var avg := 0
	for se in valid:
		avg += int(se.secs)
	avg = floori(float(avg) / valid.size())
	if bs >= 2:
		out.append(_info_tile("bolt", "Längste Serie", "%d Tage" % bs, "am Stück gespielt – im Schnitt %s pro Runde." % dur(avg), "streak"))
	else:
		out.append(_info_tile("games", "Runden", str(valid.size()), "im Schnitt %s pro Runde." % dur(avg), "rounds"))
	return out


func _info_tile(icon: String, label: String, value: String, sub: String, key: String) -> Control:
	var t = StatTile.new().setup(icon, label, value, sub)
	t.set_meta("uz_key", "play:hl:" + key)
	t.set_meta("uz_hint_a", "—")
	return t


# --- Meistgespielt -----------------------------------------------------------------------

func _top_item(g: Dictionary) -> Control:
	var v := U.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card = CoverCard.new().setup(g)
	var gd := g
	# Wie überall: A öffnet die Seite des Spiels, gestartet wird dort.
	card.chosen.connect(func(_x: Dictionary) -> void: view.main.open_game(gd))
	v.add_child(card)
	v.add_child(U.spacer(0, 16, false))
	var h := U.label(dur(Library.playtime(g)), "m", "text", "bold")
	v.add_child(h)
	var last := Library.last_played(g)
	var sub := U.ago(last) if last > 0 else _sys_name(str(g.get("system", "")))
	var sl := U.ellipsis(U.label(sub, "s", "muted"))
	sl.custom_minimum_size = Vector2(UzTheme.cover_size().x, 0)
	v.add_child(sl)
	return v


# --- Verlauf -----------------------------------------------------------------------------

func _history(col: VBoxContainer) -> void:
	var days: Array = _days.keys()
	days.sort()
	days.reverse()
	var items: Array = []
	for d in days.slice(0, 14):
		var per: Dictionary = _days[d]
		var ids: Array = per.keys().filter(func(id): return not Library.get_game(str(id)).is_empty())
		ids.sort_custom(func(a, b): return int(per[a].end) > int(per[b].end))
		for i in ids.size():
			items.append({ "d": int(d), "id": str(ids[i]), "e": per[ids[i]], "first": i == 0 })
		if items.size() >= 30:
			break
	if items.is_empty():
		return
	col.add_child(U.spacer(0, 8, false))
	col.add_child(view.section_title("Verlauf", "die letzten zwei Wochen"))
	# Eine Zeitleiste von heute nach hinten: jeder Tag beginnt mit Punkt und Namen.
	var shelf = Shelf.new().setup("play:history", HISTORY_GAP, true, 18, gutter)
	col.add_child(shelf)
	for i in items.size():
		var it: Dictionary = items[i]
		var v := U.vbox(16)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := TimelineHead.new()
		if it.first:
			head.day = _day_name(int(it.d))
			head.total = dur(_day_total(int(it.d)))
			head.today = int(it.d) == _today
		head.tail = HISTORY_GAP if i < items.size() - 1 else 0
		v.add_child(head)
		v.add_child(_session_card(Library.get_game(str(it.id)), it.e))
		shelf.add(v)
	col.add_child(U.spacer(0, 40, false))


const HISTORY_GAP := 22


## Kopf über einer Karte im Verlauf: durchgehende Linie, am Tagesanfang Punkt und Tag.
class TimelineHead extends Control:
	var day := ""
	var total := ""
	var today := false
	var tail := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 30)

	func _draw() -> void:
		var y := 15.0
		var x := 0.0
		var line := UzTheme.col("line")
		if day != "":
			var dot := UzTheme.col("accent") if today else UzTheme.col("muted")
			draw_circle(Vector2(7, y), 7.0, dot)
			var fb := UzTheme.font("bold")
			var fm := UzTheme.font("regular")
			var fs := UzTheme.size("m")
			var base := y + fb.get_ascent(fs) * 0.5 - 2
			x = 28.0
			draw_string(fb, Vector2(x, base), tr(day), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))
			x += fb.get_string_size(tr(day), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12
			draw_string(fm, Vector2(x, base), tr(total), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("muted"))
			x += fm.get_string_size(tr(total), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18
		var end := size.x + tail
		if end > x:
			draw_line(Vector2(x, y), Vector2(end, y), line, 2.0)


func _session_card(g: Dictionary, e: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(440, 156)
	var sb := UzTheme.card(UzTheme.col("surface", 0.94))
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", UzTheme.focus_box(-1, 6))
	b.set_meta("uz_hint_a", "Spielen")
	b.set_meta("uz_key", "play:s:%s:%d" % [g.id, int(e.start)])
	var gd := g
	b.pressed.connect(func() -> void: _play(gd))
	var m := U.margin(14, 14, 20, 14)
	U.full_rect(m)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var row := U.hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	row.add_child(cover_clip(g, Vector2(96, 128), maxi(4, UzTheme.radius - 2)))
	var v := U.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var name_l := U.ellipsis(U.label(Library.display_title(g), "m", "text", "bold"))
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(name_l)
	v.add_child(U.label(dur(int(e.secs)), "l", "accent", "bold"))
	var when := "%s – %s" % [_clock(int(e.start)), _clock(int(e.end))]
	if int(e.n) > 1:
		when = "%d Sitzungen, ab %s" % [int(e.n), _clock(int(e.start))]
	v.add_child(U.label(when, "s", "muted"))
	return b


## Spielen – außer das Spiel ist nicht installiert: dann erst seine Seite (dort steht, wie es
## weitergeht), statt ohne Vorwarnung den Steam-Client zu öffnen.
func _play(g: Dictionary) -> void:
	if not Library.is_installed(g):
		view.main.open_game(g)
	else:
		view.main.launch(g)


# --- Noch nichts gespielt ----------------------------------------------------------------

## Leere Seite mit einem Bild der Woche, wie sie bald aussieht (nur Umrisse, keine Werte).
func _empty() -> Control:
	var m := U.margin(gutter, 190, gutter, 40)
	var row := U.hbox(80)
	m.add_child(row)
	var col := U.vbox(22)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(U.label("Noch keine Spielzeit", "xxl", "text", "black", true))
	var p := U.label("Spiel etwas, dann steht hier dein Rückblick.", "l", "muted", "regular", true)
	p.custom_minimum_size = Vector2(820, 0)
	col.add_child(p)
	col.add_child(U.spacer(0, 10, false))
	var brow := U.hbox(16)
	col.add_child(brow)
	var go := U.button("Zu den Spielen", "games", "primary")
	go.set_meta("uz_default", true)
	go.pressed.connect(func() -> void: view.main.goto("games"))
	brow.add_child(go)
	var chart = WeekChart.new().setup([0, 0, 0, 0, 0, 0, 0], ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
	chart.ghost = true
	chart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chart)
	return m
