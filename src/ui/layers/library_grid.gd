extends "res://src/ui/layers/layer.gd"
## Alle Spiele eines Bereichs als Raster. Y öffnet „Ordnen und filtern“ (Sortierung, Abschnitte,
## Filter, gespeicherte Ansichten), X sucht (Bildschirmtastatur), LB/RB wechseln die Ansicht.
## „Mehrere Spiele auswählen“ (im Ordnen) schaltet den Auswahlmodus ein: A hakt an, X wählt alle
## oder keine, Y bearbeitet die Auswahl auf einmal (Tags, Kategorie, Favorit, Ordner …), B beendet.
## Oben links der Bereich mit Anzahl, Sortierung und Filter, oben rechts das gewählte Spiel (Titel,
## System, Spielzeit) – so braucht kein Cover einen Aufkleber, der auf dem Banner der Hülle läge.
## Hinter dem Raster leuchtet leise die Farbe des gewählten Spiels.

const CoverCard := preload("res://src/ui/components/cover_card.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const GameFilter := preload("res://src/library/game_filter.gd")
const GameFields := preload("res://src/library/game_fields.gd")
const Backlog := preload("res://src/library/backlog.gd")
const QuellenS := preload("res://src/ui/sections/quellen_ordnung.gd")

const SORTS := [["recent", "Zuletzt gespielt"], ["title", "A bis Z"], ["playtime", "Meiste Spielzeit"], ["added", "Neu hinzugefügt"]]
const GUT := 96
## Ein Abschnitt steht in mehreren Gittern untereinander (Blöcke), je höchstens so viele Reihen. Zwei Gründe:
## Godot braucht für das Entfernen von Knoten aus dem Baum Zeit im Quadrat der Geschwister (gemessen: 2500
## Karten in einem Gitter 0,19 s, 5000 schon 1 s, 10.000 über 7 s – in Blöcken 11, 27 und 88 ms); das traf jedes
## Neufüllen (Sortieren, Suchen, Filtern) und das Schließen. Und ein Block legt seine Karten erst an, wenn er in
## Sichtweite kommt (_block_fuellen) – bis dahin hält er nur seinen Platz. Vorher entstanden beim Öffnen alle
## Karten auf einmal (2450 Spiele: 0,36 s, jedes Neufüllen 0,4 bis 0,8 s).
const BLOCK_REIHEN := 16
const REIHEN_ABSTAND := 36
const SOFORT_REIHEN := 10        ## so viele Reihen stehen gleich nach dem Füllen (gut zwei Bildschirme)
const KARTEN_JE_BILD := 160      ## mehr legt die Sichtprüfung in einem Bild nicht neu an
## Abstand über einer Abschnitts-Überschrift (ab dem zweiten Abschnitt).
const GROUP_GAP := 46

var sub_id := ""
var label := ""
var pick_folder := ""        ## Auswahlmodus: Spiele für diesen Ordner an- und abhaken
var pick_all := false         ## dabei Spiele aller Systeme anbieten (Sammlungen im Mosaik mischen)
## Auswahlmodus „Regal einräumen“ (Zimmer, src/room/zimmer_einrichten.gd): A räumt ein bzw. aus, neue
## kommen hinten dazu; beim Schließen (B „Fertig“) bekommt pick_fertig die Liste der Spiel-IDs.
var pick_liste: Array = []
var pick_fertig: Callable
const Main := preload("res://src/main.gd")
var main: Main
var _sort := ""
var _query := ""
var _filter := {}            ## siehe game_filter.gd
var _eff := {}               ## was davon hier gilt (siehe _games)
var _group := ""
var _body: VBoxContainer
var _grids: Array = []       ## ein Gitter je Abschnitt (ohne Abschnitte genau eins)
var _cards: Array = []       ## die Karten, die es schon gibt (Blöcke in Sichtweite)
var _folge: Array = []       ## alle Spiele in der Reihenfolge des Rasters (über die Abschnitte hinweg)
var _bloecke: Array = []     ## je Gitter (wie _grids): { ab: Platz des ersten Spiels in _folge, n, voll }
var _leer := 0               ## Blöcke, die noch keine Karten haben
var _cols := 2
var _hsep := 30
var _count: Label
var _sort_l: Label
var _view_l: Label
var _query_l: Label
var _cur_title: Label
var _cur_sub: Label
var _empty: Control
var _empty_t: Label
var _empty_d: Label
var _sc: ScrollContainer
var _vis_due := false
var _last_gid := ""
var _redo: Timer             ## füllt das Raster kurz nach der letzten Änderung im Filter neu
var _sheet: Control          ## offenes „Ordnen und filtern“
var _live_l: Label
var _reset_row: Control
var _meta_row: Control
var _select := false         ## Auswahlmodus: mehrere Spiele anhaken und gemeinsam bearbeiten
var _picked := {}            ## Spiel-ID → true (im Auswahlmodus)
var _shown: Array = []       ## die Spiele, die das Raster gerade zeigt (gefiltert, sortiert)
var _gefuellt := false       ## das Raster ist schon einmal gefüllt (danach blendet ein Neufüllen)
var _stale := false          ## die Bibliothek hat sich geändert, während eine Ebene darüber lag
var _bild_stand := -1        ## Media.bilder_stand beim letzten Füllen (neue Bilder: neu füllen)
var _basis: Array = []       ## die Spiele des Bereichs (gemerkt, bis sich die Bibliothek ändert)
var _basis_da := false
var _nur_wenn_anders := false  ## das anstehende Neufüllen kommt nur von der Bibliothek: erst nachsehen


func build() -> void:
	dim = 0.84
	_scrim.color = Color(UzTheme.col("bg"), dim)
	# Die Startseite tritt ganz zurück, damit nichts durchscheint; der Raum mit der Farbe des
	# Spiels bleibt (gedämpft) sichtbar.
	hide_shell(main, self)
	if main:
		closed.connect(func() -> void:
			# Zurück auf der Startseite gehört der Raum wieder dem, was dort gewählt ist.
			var gs: Variant = main.sections.get("games")
			if gs is Object and (gs as Object).has_method("restore_background"):
				(gs as Object).call("restore_background")
		)
	_sort = str(Config.get_value("library.sort", "recent"))
	_filter = GameFilter.clean(Config.get_value("library.filter", {}))
	_group = GameFilter.clean_group(Config.get_value("library.group", ""))
	if pick_folder != "" or pick_fertig.is_valid():
		set_meta("uz_hint_b", "Fertig")
	if pick_fertig.is_valid():
		closed.connect(func() -> void: pick_fertig.call(pick_liste.duplicate()))
	# Das Raster läuft über die ganze Fläche und gleitet beim Blättern unter dem Kopf weg (dort
	# ein weicher Verlauf); so wird kein Ring an einer Kante abgeschnitten.
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 214.0)
	U.full_rect(sc)
	add_child(sc)
	_sc = sc
	sc.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _vis_due = true)
	add_child(_top_fade())
	var m := U.margin(GUT, 50, GUT, 0)
	m.anchor_right = 1.0
	add_child(m)
	var col := U.vbox(10)
	m.add_child(col)
	var head := U.hbox(40)
	col.add_child(head)
	var titles := U.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(U.label(label, "xxl", "text", "black"))
	var sub_row := U.hbox(18)
	_count = U.label("", "m", "muted", "medium")
	_count.clip_text = false
	sub_row.add_child(_count)
	_sort_l = U.label("", "m", "faint", "medium")
	_sort_l.clip_text = false
	sub_row.add_child(_sort_l)
	_query_l = U.label("", "m", "accent", "medium")
	_query_l.clip_text = false
	sub_row.add_child(_query_l)
	# Abschnitte und Filter (oder der Name der Ansicht): darf gekürzt werden, der Rest nicht.
	_view_l = U.ellipsis(U.label("", "m", "accent", "medium"))
	sub_row.add_child(_view_l)
	titles.add_child(sub_row)
	head.add_child(titles)
	# Das gewählte Spiel, rechtsbündig und unten auf der Linie des Titels.
	var cur := U.vbox(2)
	cur.custom_minimum_size = Vector2(620, 0)
	cur.alignment = BoxContainer.ALIGNMENT_END
	_cur_title = U.ellipsis(U.label("", "l", "text", "bold"))
	_cur_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cur.add_child(_cur_title)
	_cur_sub = U.ellipsis(U.label("", "s", "muted", "medium"))
	_cur_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cur.add_child(_cur_sub)
	head.add_child(cur)
	# Oben Platz für den Kopf, seitlich die Ränder der Seite, unten Platz, damit auch die
	# letzte Reihe ganz über den Hinweisen stehen kann.
	var pad := U.margin(GUT, 210, GUT, 190)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(pad)
	var cs := UzTheme.cover_size()
	var width := U.view_size().x - GUT * 2
	_cols = maxi(2, int((width + 30.0) / (cs.x + 30.0)))
	# Spalten so verteilen, dass das Raster genau unter Titel und rechter Kante steht.
	_hsep = clampi(int(floor((width - _cols * cs.x) / float(_cols - 1))), 24, 64)
	var stack := U.vbox(0)
	pad.add_child(stack)
	_body = U.vbox(0)
	stack.add_child(_body)
	_empty = U.vbox(10)
	_empty.visible = false
	_empty_t = U.label("Nichts gefunden", "xl", "text", "bold")
	_empty.add_child(_empty_t)
	_empty_d = U.label("", "m", "muted")
	_empty.add_child(_empty_d)
	stack.add_child(_empty)
	add_child(_bottom_fade())
	_redo = Timer.new()
	_redo.one_shot = true
	_redo.wait_time = 0.3
	_redo.timeout.connect(_refill_faellig)
	add_child(_redo)
	Library.meta_progress.connect(_on_meta_progress)
	# Ein Spiel ausgeblendet, gelöscht oder umgezogen (etwa über „Optionen“ auf einer Karte):
	# Das Raster zieht nach, sobald es wieder oben liegt – sonst stünde das Spiel weiter da.
	Library.changed.connect(_on_library_changed)
	Nav.focus_moved.connect(_on_focus_moved)
	_fill()


## Die Startseite hinter einer Vollbild-Ebene ausblenden und erst wieder zeigen, wenn keine
## solche Ebene mehr offen ist (Bibliothek und Bildwahl können übereinanderliegen).
static func hide_shell(main_node: Node, layer: Node) -> void:
	if main_node == null:
		return
	var shv: Variant = main_node.get("shell")
	if not (shv is Control) or not is_instance_valid(shv):
		return
	var sh: Control = shv
	sh.set_meta("uz_hidden_by", int(sh.get_meta("uz_hidden_by", 0)) + 1)
	# Kreuzen: Die Startseite hält ein Bild und geht dann sanft (Kurve „Kreuzen“), die Ebene kommt
	# im selben Bild (U.NACH_WEG, _auf) – zusammen decken beide immer. Beim Schließen umgekehrt: die
	# Ebene kreuzt (Meta uz_verdeckt, Layer.close), die Startseite kommt sofort.
	layer.set_meta("uz_verdeckt", true)
	U.kreuz_aus(U.weg(sh, "uz_shell"), sh)
	layer.connect("closed", func() -> void:
		if not is_instance_valid(sh):
			return
		var left := maxi(0, int(sh.get_meta("uz_hidden_by", 1)) - 1)
		sh.set_meta("uz_hidden_by", left)
		if left == 0:
			# Sofort und so schnell, wie die Ebene geht: sonst läge kurz nur die Abdunklung da.
			U.ankommen(sh, U.T_WEG, "uz_shell").tween_property(sh, "modulate:a", 1.0, U.T_WEG)
	)


## Schließen: die Abdunklung geht zuerst (T_ANTWORT), damit die Startseite, die gleichzeitig
## zurückkommt, nicht unter ihr im Dunkeln auftaucht; das Raster blendet mit der Ebene (T_WEG).
func _exit_motion(tw: Tween) -> void:
	if is_instance_valid(_scrim):
		tw.set_parallel(true)
		tw.tween_property(_scrim, "color", Color(_scrim.color, 0.0), U.T_ANTWORT)


## Ein-Bewegung der Bibliothek: Die Startseite geht (hide_shell), die Abdunklung kommt, der
## Inhalt blendet gleich danach (U.NACH_WEG) in T_ORT ein, das Raster gleitet dabei W_ORT von
## unten nach (ruhig: ohne Weg). So liegen beide Seiten nur kurz übereinander, ohne Loch.
func _auf() -> void:
	modulate.a = 1.0
	var tw := U.ankommen(self, U.T_ORT, "uz_layer").set_parallel(true)
	var verz := U.NACH_WEG
	for ch in get_children():
		if not (ch is CanvasItem) or not (ch as CanvasItem).visible:
			continue
		if ch == _scrim:
			var ziel := _scrim.color
			_scrim.color = Color(ziel, 0.0)
			# Die Abdunklung liegt über der Startseite: erst wenn diese weitgehend gegangen ist,
			# sonst taucht sie im Dunkeln ab (gemessen: ein Helligkeitsloch).
			tw.tween_property(_scrim, "color", ziel, U.T_ORT).set_delay(U.T_WEG * 0.5)
			continue
		(ch as CanvasItem).modulate.a = 0.0
		tw.tween_property(ch, "modulate:a", 1.0, U.T_ORT).set_delay(verz)
	var w := U.weg_px(U.W_ORT)
	if w != 0.0 and is_instance_valid(_sc):
		_sc.offset_top = w
		_sc.offset_bottom = w
		# In ganzen Pixeln mit sauberem Schluss (U.px_schluss): kein spätes Nachrucken.
		var sc := _sc
		U.px_weg(U.ankommen(_sc, U.T_RAUM, "uz_auf"), _sc, "uz_px_auf", w, U.T_RAUM, func(p: float) -> void:
			sc.offset_top = p
			sc.offset_bottom = p
		).set_delay(verz)


## Oben hinter dem Kopf: Was nach oben weggleitet, taucht weich unter Titel und Angaben ab.
func _top_fade() -> Control:
	var g := Gradient.new()
	var bg := UzTheme.col("bg")
	g.offsets = PackedFloat32Array([0.0, 0.78, 1.0])
	g.colors = PackedColorArray([Color(bg, 1.0), Color(bg, 1.0), Color(bg, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	var f := TextureRect.new()
	f.texture = gt
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_SCALE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.anchor_right = 1.0
	f.offset_bottom = 200
	return f


## Unten läuft das Raster in den Raum aus: Was unter die Hinweise rutscht, verschwindet.
func _bottom_fade() -> Control:
	var g := Gradient.new()
	var bg := UzTheme.col("bg")
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.72, 1.0])
	g.colors = PackedColorArray([Color(bg, 0.0), Color(bg, 0.8), Color(bg, 1.0), Color(bg, 1.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	var f := TextureRect.new()
	f.texture = gt
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_SCALE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.anchor_top = 1.0
	f.anchor_bottom = 1.0
	f.anchor_right = 1.0
	f.offset_top = -190
	return f


## Alle Spiele des Bereichs, noch ohne Suche, Filter und Sortierung (daraus kommt auch die Auswahl im Filter).
## Gemerkt, bis sich die Bibliothek ändert: Die Filterleiste fragt bei jedem Schritt danach. Vorher kam die Liste
## fertig sortiert von der Startseite und wurde hier noch einmal sortiert (gemessen bei 2450 Spielen: 75 bis 90 ms
## je Füllen, dasselbe bei jedem Schritt in der Filterleiste).
func _base() -> Array:
	if not _basis_da:
		_basis_da = true
		_basis = _base_neu()
	return _basis


func _base_neu() -> Array:
	if pick_fertig.is_valid():
		return Library.visible_games().filter(func(g: Dictionary) -> bool: return str(g.get("source", "")) != "disc")
	if pick_folder != "":
		var f := Library.folder(pick_folder)
		var sys := str(f.get("system", ""))
		return Library.visible_games() if sys == "" or pick_all else Library.by_system(sys)
	if sub_id == "zuletzt" or not (main and main.sections.has("games")):
		return Library.visible_games()
	var gs: Object = main.sections["games"]
	# Ausgeblendete: nach Titel vorsortiert wie bisher (gleich lange Gespieltes bleibt so nach Titel geordnet).
	return gs.games_for(sub_id) if sub_id == QuellenS.HIDDEN_GAMES else gs.games_of(sub_id)


## Gefiltert, gesucht und sortiert. Der Filter gilt für jedes Raster; ein System oder Laden, das
## es hier gar nicht gibt (PS2 gewählt, das Raster zeigt Steam), bleibt außen vor – sonst stünde
## der Bereich leer da, ohne dass die Auswahl dafür überhaupt angeboten wird.
func _games(base: Array = []) -> Array:
	return Library.sorted(_gefiltert(base), _sort)


## Dasselbe ohne Sortierung (die Filterleiste braucht nur die Zahl).
func _gefiltert(base: Array = []) -> Array:
	var list := base if not base.is_empty() else _base()
	_eff = _filter.duplicate()
	if _eff.has("platform") and not list.any(func(g): return GameFilter.platform_of(g) == str(_eff.platform)):
		_eff.erase("platform")
	if _query != "":
		var q := _query.to_lower()
		list = list.filter(func(g): return Library.display_title(g).to_lower().contains(q))
	return GameFilter.apply(list, _eff, _ach_map(list) if _eff.has("ach") else {})


## Was Uzai über die Erfolge der Spiele schon weiß (ohne zu fragen): Spiel-ID → [frei, gesamt].
func _ach_map(list: Array) -> Dictionary:
	var out := {}
	for g in list:
		var a: Array = Achievements.known(g)
		if not a.is_empty():
			out[str(g.get("id", ""))] = a
	return out


func _count_text(list: Array) -> String:
	if pick_fertig.is_valid():
		return TranslationServer.translate("%d im Regal") % pick_liste.size()
	if pick_folder != "":
		var n_in := list.filter(func(g): return Library.is_in_folder(g, pick_folder)).size()
		return "%d von %d ausgewählt" % [n_in, list.size()]
	if _select:
		return "%d von %d ausgewählt" % [list.filter(func(g): return _picked.has(str(g.get("id", "")))).size(), list.size()]
	return U.plural(list.size(), "Spiel", "Spiele")


func _fill() -> void:
	U.clear(_body)
	_grids.clear()
	_cards.clear()
	_bloecke.clear()
	_folge = []
	_leer = 0
	# Die Grundliste je Füllen frisch (billig, seit sie unsortiert kommt): Sie gilt dann, bis wieder gefüllt wird
	# oder die Bibliothek sich meldet – auch für die Filterleiste dazwischen.
	_basis_da = false
	var list := _games()
	_shown = list
	_bild_stand = Media.bilder_stand
	_count.text = _count_text(list)
	_update_head()
	var parts := GameFilter.groups(list, _group)
	var je_block := BLOCK_REIHEN * _cols
	var cs := UzTheme.cover_size()
	for i in parts.size():
		var p: Dictionary = parts[i]
		var spiele: Array = p.games
		if str(p.title) != "":
			_body.add_child(_heading(str(p.title), spiele.size(), bool(p.unknown), i == 0))
		# Der Abschnitt: Gitter in Blöcken untereinander, im Abstand der Reihen – es sieht aus wie eines
		# (alle Karten sind gleich groß), und _grid_move geht von Block zu Block wie von Abschnitt zu Abschnitt.
		var abschnitt := U.vbox(REIHEN_ABSTAND)
		_body.add_child(abschnitt)
		var ab := _folge.size()
		_folge.append_array(spiele)
		var k := 0
		while k < spiele.size():
			var n := mini(je_block, spiele.size() - k)
			var grid := GridContainer.new()
			grid.columns = _cols
			grid.add_theme_constant_override("h_separation", _hsep)
			grid.add_theme_constant_override("v_separation", REIHEN_ABSTAND)
			# Der Block hält seinen Platz, solange er leer ist: so breit und hoch, wie er gefüllt sein wird.
			var reihen := ceili(float(n) / _cols)
			var spalten := mini(n, _cols)
			grid.custom_minimum_size = Vector2(spalten * cs.x + (spalten - 1) * _hsep, reihen * cs.y + (reihen - 1) * REIHEN_ABSTAND)
			abschnitt.add_child(grid)
			_grids.append(grid)
			_bloecke.append({ "ab": ab + k, "n": n, "voll": false })
			_leer += 1
			k += n
	# Was gleich zu sehen ist, steht sofort; der Rest kommt mit dem Blättern (_process).
	var nr := 0
	while nr < _bloecke.size() and _cards.size() < SOFORT_REIHEN * _cols:
		_block_fuellen(nr)
		nr += 1
	# Mit Abschnitten bleibt beim Blättern mehr Luft oben, damit die Überschrift über der ersten
	# Reihe eines Abschnitts nicht unter dem Kopf verschwindet.
	_sc.set_meta("uz_pad_v", 214.0 if _group == "" else 282.0)
	# Erst nach dem Anordnen nachsehen, was zu sehen ist: vorher stünden alle Karten oben links
	# und würden sich alle aufbauen.
	set_deferred("_vis_due", true)
	_empty.visible = list.is_empty()
	if list.is_empty():
		var by_filter := _query == "" and not _eff.is_empty()
		_empty_t.text = "Nichts passt zum Filter" if by_filter else "Nichts gefunden"
		_empty_d.text = "Mit Y den Filter lockern oder zurücksetzen." if by_filter else ""
		_cur_title.text = ""
		_cur_sub.text = ""
	# Neu gefüllt: weich einblenden statt hart umzuspringen (nicht beim ersten Mal – da kommt die
	# ganze Ebene herein, siehe _auf).
	if _gefuellt:
		_body.modulate.a = 0.0
		U.ankommen(_body, U.T_ORT, "uz_fill").tween_property(_body, "modulate:a", 1.0, U.T_ORT)
	_gefuellt = true


## Die Karten eines Blocks anlegen (einmal).
func _block_fuellen(nr: int) -> void:
	if nr < 0 or nr >= _bloecke.size():
		return
	var b: Dictionary = _bloecke[nr]
	if bool(b.voll):
		return
	b.voll = true
	_leer -= 1
	var grid: GridContainer = _grids[nr]
	for i in int(b.n):
		var card := _card(_folge[int(b.ab) + i])
		grid.add_child(card)
		_cards.append(card)
	# Erst nach dem Anordnen nachsehen, welche Karten zu sehen sind (siehe _fill).
	set_deferred("_vis_due", true)


## Platz eines Spiels im Raster (in _folge), -1 wenn es nicht dabei ist.
func _platz_von(gid: String) -> int:
	if gid == "":
		return -1
	for i in _folge.size():
		if str((_folge[i] as Dictionary).get("id", "")) == gid:
			return i
	return -1


## Der Block, in dem der Platz liegt (-1: keiner).
func _block_von(platz: int) -> int:
	for nr in _bloecke.size():
		var b: Dictionary = _bloecke[nr]
		if platz >= int(b.ab) and platz < int(b.ab) + int(b.n):
			return nr
	return -1


## Die Karte an einem Platz; ihr Block entsteht dafür, wenn es ihn noch nicht gibt.
func _karte_an(platz: int) -> Control:
	var nr := _block_von(platz)
	if nr < 0:
		return null
	_block_fuellen(nr)
	return _grids[nr].get_child(platz - int(_bloecke[nr].ab)) as Control


func _card(g: Dictionary) -> Control:
	var card = CoverCard.new()
	card.setup(g, false)
	card.lazy = true
	card.live = true
	card.set_meta("uz_grid_nav", _grid_move)
	card.set_meta("uz_hint_y", "Bearbeiten" if _select else "Ordnen")
	card.set_meta("uz_hint_x", "Alle oder keine" if _select else "Suchen")
	card.set_meta("uz_on_y", _on_y)
	card.set_meta("uz_on_x", _on_x)
	card.focused_game.connect(_on_focus_game)
	if _select:
		var on := _picked.has(str(g.get("id", "")))
		card.checked = 1 if on else 0
		card.set_meta("uz_hint_a", "Abwählen" if on else "Auswählen")
		card.chosen.connect(func(game: Dictionary) -> void: _toggle_pick(str(game.get("id", "")), card))
	elif pick_fertig.is_valid():
		card.checked = 1 if str(g.get("id", "")) in pick_liste else 0
		card.set_meta("uz_hint_a", "Ausräumen" if card.checked == 1 else "Einräumen")
		card.chosen.connect(func(game: Dictionary) -> void:
			var gid := str(game.get("id", ""))
			var on := not (gid in pick_liste)
			if on:
				pick_liste.append(gid)
			else:
				pick_liste.erase(gid)
			card.set_checked(on)
			card.set_meta("uz_hint_a", "Ausräumen" if on else "Einräumen")
			Nav.focus_moved.emit(card)
			_count.text = _count_text(_shown)
		)
	elif pick_folder != "":
		card.checked = 1 if Library.is_in_folder(g, pick_folder) else 0
		card.set_meta("uz_hint_a", "Abhaken" if card.checked == 1 else "Anhaken")
		card.chosen.connect(func(game: Dictionary) -> void:
			var on := not Library.is_in_folder(game, pick_folder)
			Library.set_in_folder(str(game.id), pick_folder, on)
			card.set_checked(on)
			card.set_meta("uz_hint_a", "Abhaken" if on else "Anhaken")
			Nav.focus_moved.emit(card)
			_count.text = _count_text(_games())
		)
	else:
		card.chosen.connect(func(game: Dictionary) -> void:
			# Die Bibliothek geht vorher zu: Das Cover fliegt trotzdem von hier (src/ui/flug.gd).
			Flug.merke(card)
			close()
			main.open_game(game)
		)
	return card


## Überschrift eines Abschnitts mit Anzahl; „Unbekannt“ und „Einzelne Spiele“ etwas leiser.
func _heading(title: String, n: int, unknown: bool, first: bool) -> Control:
	var m := U.margin(0, 0 if first else GROUP_GAP, 0, 20)
	var row := U.hbox(14)
	m.add_child(row)
	var t := U.label(title, "l", "muted" if unknown else "text", "bold")
	t.size_flags_vertical = Control.SIZE_SHRINK_END
	# Eigene Tags, Kategorien und Spielreihen bleiben, wie sie sind („Tag“ ist kein „day“).
	if not unknown and _group in ["tag", "category", "series"]:
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(t)
	var c := U.label(str(n), "m", "faint", "medium")
	c.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(c)
	return m


## Kopfzeile: Sortierung, Suche und – gekürzt, wenn es eng wird – Abschnitte und Filter oder
## der Name der gespeicherten Ansicht. Dazu die Tastenhinweise.
func _update_head() -> void:
	for s in SORTS:
		if s[0] == _sort:
			_sort_l.text = "·  Sortiert: " + str(s[1])
	_query_l.text = ("·  Suche: „%s“" % _query) if _query != "" else ""
	var bits := PackedStringArray()
	var p := _active_preset()
	if p >= 0:
		bits.append("Ansicht: " + str(_presets()[p].name))
	else:
		if _group != "":
			bits.append(GameFilter.group_name(_group))
		if not _eff.is_empty():
			bits.append(GameFilter.summary(_eff))
	_view_l.text = ("·  " + "  ·  ".join(bits)) if not bits.is_empty() else ""
	# Leere Angaben ganz weg, sonst stünde zwischen den übrigen eine doppelte Lücke.
	_query_l.visible = _query != ""
	_view_l.visible = not bits.is_empty()
	var hints: Array = [["y", "Ordnen"], ["x", "Suchen"]]
	if not _presets().is_empty():
		hints.append_array([["lb", ""], ["rb", "Ansicht"]])
	if _select:
		hints = [["y", "Bearbeiten"], ["x", "Alle oder keine"]]
	set_meta("uz_hints", hints)


## Oben rechts steht, was gerade gewählt ist; dahinter wechselt leise die Farbe des Raums.
func _on_focus_game(g: Dictionary) -> void:
	if not is_instance_valid(_cur_title):
		return
	_last_gid = str(g.get("id", ""))
	_cur_title.text = Library.display_title(g)
	var bits := PackedStringArray()
	var sys := Config.system(str(g.get("system", "")))
	match str(g.get("source", "")):
		"steam": bits.append("Steam")
		"epic": bits.append("Epic Games")
		"ea": bits.append("EA app")
		"pc": bits.append("PC")
		_: bits.append(Library.store_name(g, false, str(sys.get("name", ""))))
	var secs := Library.playtime(g)
	# Gekauft, aber nicht installiert: das zuerst sagen statt „Noch nicht gespielt“.
	if not Library.is_installed(g):
		bits.append("Nicht installiert")
	if secs > 0 or Library.is_installed(g):
		bits.append(U.playtime(secs))
	if g.get("favorite", false):
		bits.append("Favorit")
	_cur_sub.text = "  ·  ".join(bits)
	# Beim Halten wechselt der Titel ohne Abblenden (man liest ruhig mit statt einem Blinken im
	# Takt der Schritte); ein einzelner Schritt blendet weich nach.
	if Nav.halten_takt() > 0.0:
		U.stop(_cur_title, "uz_cur")
		_cur_title.modulate.a = 1.0
	else:
		var tw := U.tw(_cur_title, "uz_cur")
		_cur_title.modulate.a = 0.4
		tw.tween_property(_cur_title, "modulate:a", 1.0, U.T_ORT)
	if main and main.background:
		main.background.show_game(g)


## Neu füllen und die Auswahl halten: das zuletzt gewählte Spiel, wenn es noch dabei ist, sonst
## das erste. Liegt „Ordnen und filtern“ noch offen, bekommt das Raster den Fokus beim Schließen.
## Zeigt das Raster noch genau diese Spiele (gleiche IDs in gleicher Reihenfolge)?
static func same_games(shown: Array, now: Array) -> bool:
	if shown.size() != now.size():
		return false
	for i in shown.size():
		if str((shown[i] as Dictionary).get("id", "")) != str((now[i] as Dictionary).get("id", "")):
			return false
	return true


func _on_library_changed() -> void:
	_basis_da = false
	# Im Auswahlmodus bleibt die Liste stehen (die Mehrfachbearbeitung füllt selbst neu).
	if _select or not is_inside_tree() or _redo == null:
		return
	# Ob sich hier wirklich etwas geändert hat, sieht erst _refill_faellig nach – einmal je Schub: Vorher
	# filterte und sortierte jede Meldung der Bibliothek sofort alles (beim Scrapen kommt je Spiel eine).
	if not _stale:
		_nur_wenn_anders = true
	_stale = true
	if Nav.top_layer() == self:
		_redo.start()


func _on_focus_moved(_c: Control) -> void:
	if _stale and not _select and Nav.top_layer() == self and _redo.is_stopped():
		_redo.start()


## Die Uhr ist abgelaufen. Kam der Anstoß nur von der Bibliothek, erst nachsehen: Dieselben Spiele und dieselben
## Bilder (Spiele scrapen und die Bildwahl zählen als neu) heißen, es bleibt, wie es ist.
func _refill_faellig() -> void:
	if _nur_wenn_anders and same_games(_shown, _games()) and _bild_stand == Media.bilder_stand:
		_nur_wenn_anders = false
		_stale = false
		return
	_refill()


func _refill() -> void:
	_redo.stop()
	_stale = false
	_nur_wenn_anders = false
	# Fällt das gewählte Spiel weg (ausgeblendet), rückt der Fokus auf die Stelle, an der es stand.
	var at := _platz_von(_last_gid)
	_fill()
	# Der Block des gewählten Spiels (bzw. der Stelle, an der es stand) entsteht schon jetzt: Im nächsten Bild
	# steht seine Karte dann an ihrem Platz, und die Ansicht rollt richtig dorthin.
	var jetzt := _platz_von(_last_gid)
	if jetzt >= 0:
		_block_fuellen(_block_von(jetzt))
	elif at >= 0 and not _folge.is_empty():
		_block_fuellen(_block_von(mini(at, _folge.size() - 1)))
	await get_tree().process_frame
	if not is_instance_valid(_body):
		return
	if jetzt >= 0:
		Nav.focus(_karte_an(jetzt), true)
		return
	if at >= 0 and not _folge.is_empty() and Nav.top_layer() == self:
		Nav.focus(_karte_an(mini(at, _folge.size() - 1)), true)
		return
	var d := Nav.default_in(_body)
	if d:
		Nav.focus(d, true)
	else:
		# Nichts mehr zu wählen: die Hinweise unten bieten kein „Öffnen“ mehr an.
		Nav.focus_moved.emit(null)


func _search() -> void:
	main.open_keyboard("Spiel suchen", _query, func(t: String) -> void:
		_query = t.strip_edges()
		_refill()
	)


func handle(cmd: String) -> bool:
	if cmd == "y":
		_on_y()
		return true
	if cmd == "x":
		_on_x()
		return true
	if cmd == "lb" or cmd == "rb":
		# Beim Auswählen bleibt die Liste stehen – sonst wüsste man nicht mehr, was angehakt ist.
		if not _select:
			_step_preset(-1 if cmd == "lb" else 1)
		return true
	if cmd == "menu":
		if _select:
			_open_bulk()
			return true
		var f := Nav.focused()
		if f and f.get("game") is Dictionary:
			main.open_game_options(f.get("game"))
		return true
	return false


## B beendet zuerst den Auswahlmodus, erst dann schließt das Raster.
func nav_command(cmd: String) -> bool:
	if cmd == "b" and _select:
		Sfx.play("back")
		_set_select(false)
		return true
	return super(cmd)


func _on_y() -> void:
	if _select:
		_open_bulk()
	else:
		_open_order()


func _on_x() -> void:
	if _select:
		_pick_all()
	else:
		_search()


# --- Ordnen und filtern ----------------------------------------------------------------------
# Eine Seitenleiste: links/rechts wechselt den Wert, das Raster dahinter folgt kurz danach. Die
# Auswahl zeigt nur, was die Spiele des Bereichs hergeben (mit Anzahl).

func _open_order() -> void:
	if is_instance_valid(_sheet):
		return
	var s = Sheet.new()
	s.setup("Ordnen und filtern", label, 780)
	s.fill_func = _fill_order
	s.closed.connect(func() -> void:
		_sheet = null
		if not _redo.is_stopped():
			_refill()
	)
	_sheet = s
	main.open_layer(s)


func _fill_order(sheet) -> void:
	var base := _base()
	var fc := GameFilter.facets(base)
	_order_kopf(sheet, fc)
	_order_aktionen(sheet)
	_order_filter(sheet, base, fc)
	_order_ansichten(sheet)
	_live_text()


## Oben im Blatt: Sortierung und Abschnitte (Abschnitte aus eigenen Angaben nur, wenn es sie bei diesen Spielen gibt).
func _order_kopf(sheet, fc: Dictionary) -> void:
	var srt = _choice("Sortieren", "sort", _sort, SORTS)
	srt.icon_name = "sort"
	srt.changed.connect(func(v: Variant) -> void:
		_sort = str(v)
		Config.set_value("library.sort", _sort)
		_changed()
	)
	sheet.add_row(srt)
	var plats: Dictionary = fc.platform
	# Abschnitte aus eigenen Angaben nur, wenn es sie bei diesen Spielen auch gibt.
	var groups: Array = GameFilter.GROUPS.filter(func(e) -> bool:
		if e[0] == "platform":
			return plats.size() > 1
		return not (e[0] in GameFilter.OWN_GROUPS) or not (fc[e[0]] as Dictionary).is_empty()
	)
	var grp = _choice("Abschnitte", "group", _group if groups.any(func(e): return e[0] == _group) else "", groups)
	grp.icon_name = "grid"
	grp.changed.connect(func(v: Variant) -> void:
		_group = str(v)
		Config.set_value("library.group", _group)
		_changed()
	)
	sheet.add_row(grp)


## Mehrere auswählen, neu einlesen, scrapen – nicht im Auswahlmodus (Ordner füllen, Regal einräumen).
func _order_aktionen(sheet) -> void:
	if pick_folder == "" and not pick_fertig.is_valid():
		var sel = SettingRow.new()
		sel.setup("action", "Mehrere Spiele auswählen")
		sel.icon_name = "check"
		sel.value_text = "Tags, Ordner, Favoriten …"
		sel.set_meta("uz_key", "lib:select")
		sel.on_activate = func() -> void:
			sheet.close()
			_set_select(true)
		sheet.add_row(sel)
		# Spiele, die angeblich kaputt sind (Datei weg, leer, unvollständig): einmal neu einlesen.
		var scan = SettingRow.new()
		scan.setup("action", "Spiele neu einlesen")
		scan.icon_name = "refresh"
		scan.value_text = "Läuft …" if Library.scanning else "Ordner neu durchsuchen"
		scan.set_meta("uz_key", "lib:rescan")
		scan.on_activate = func() -> void:
			sheet.close()
			Library.scan(false, true)
		sheet.add_row(scan)
		# Cover und Bilder für alle Spiele holen (spiele_scrapen.gd).
		if not Media.scrape_spiele().is_empty():
			var scr = SettingRow.new()
			scr.setup("action", "Spiele scrapen")
			scr.icon_name = "image"
			var fehlt := Media.scrape_fehlt()
			scr.value_text = tr("Läuft …") if Media.sgdb_running else (tr("%d ohne Cover") % fehlt if fehlt > 0 else tr("Alle da"))
			scr.set_meta("uz_key", "lib:scrapen")
			scr.on_activate = func() -> void:
				sheet.close()
				var l = load("res://src/ui/layers/spiele_scrapen.gd").new()
				l.main = main
				main.open_layer(l)
			sheet.add_row(scr)


## Die Filter: nur Zeilen, die bei diesen Spielen etwas trennen; darunter „Zurücksetzen“ und die Angaben von Steam.
func _order_filter(sheet, base: Array, fc: Dictionary) -> void:
	var plats: Dictionary = fc.platform
	sheet.add_gap()
	sheet.add_label("Filter")
	_live_l = sheet.add_label("", "s", "muted")
	if plats.size() > 1:
		var keys: Array = plats.keys()
		keys.sort_custom(func(a, b): return GameFilter.platform_name(a).naturalnocasecmp_to(GameFilter.platform_name(b)) < 0)
		var opts: Array = [["", "Alle"]]
		for k in keys:
			opts.append([k, "%s  (%d)" % [GameFilter.platform_name(k), plats[k]]])
		sheet.add_row(_filter_row("System oder Laden", "platform", "controller", opts))
	if int(fc.installed) > 0 and int(fc.missing) > 0:
		sheet.add_row(_filter_row("Installiert", "installed", "download",
			[["", "Alle"], ["ja", "Installiert  (%d)" % fc.installed], ["nein", "Nicht installiert  (%d)" % fc.missing]]))
	sheet.add_row(_filter_row("Gespielt", "played", "play", [["", "Alle"], ["ja", "Schon gespielt"], ["nein", "Nie gespielt"]]))
	var fav = SettingRow.new()
	fav.setup("toggle", "Nur Favoriten", "", bool(_filter.get("fav", false)))
	fav.icon_name = "heart"
	fav.set_meta("uz_key", "lib:fav")
	fav.changed.connect(func(v: Variant) -> void: _set_filter("fav", true if v else null))
	sheet.add_row(fav)
	var gens: Dictionary = fc.genre
	if not gens.is_empty():
		var names: Array = gens.keys()
		names.sort_custom(func(a, b): return int(gens[a]) > int(gens[b]) if gens[a] != gens[b] else str(a).naturalnocasecmp_to(str(b)) < 0)
		var opts2: Array = [["", "Alle"]]
		for n in names:
			opts2.append([n, "%s  (%d)" % [n, gens[n]]])
		if int(fc.no_genre) > 0:
			opts2.append(["?", "Unbekannt  (%d)" % fc.no_genre])
		sheet.add_row(_filter_row("Genre", "genre", "tag", opts2))
	var decs: Dictionary = fc.decade
	if not decs.is_empty():
		var ds: Array = decs.keys()
		ds.sort()
		ds.reverse()
		var opts3: Array = [["", "Alle"]]
		for d in ds:
			opts3.append([str(d), "%s  (%d)" % [GameFilter.group_title(d, "decade"), decs[d]]])
		if int(fc.no_year) > 0:
			opts3.append(["-1", "Unbekannt  (%d)" % fc.no_year])
		sheet.add_row(_filter_row("Erschienen", "decade", "history", opts3))
	_own_filter_rows(sheet, fc)
	sheet.add_row(_filter_row("Spielzeit", "time", "clock", [["", "Alle"]] + GameFilter.TIMES))
	if not _ach_map(base).is_empty():
		sheet.add_row(_filter_row("Erfolge", "ach", "trophy", [["", "Alle"]] + GameFilter.ACH))
	var reset = SettingRow.new()
	reset.setup("action", "Filter zurücksetzen")
	reset.icon_name = "refresh"
	reset.on_activate = func() -> void:
		_filter = {}
		Config.set_value("library.filter", {})
		_changed()
		sheet.refill()
	_reset_row = sheet.add_row(reset)
	_meta_row = null
	var lacking := Library.lacks_store_meta(base).size()
	if lacking > 0 or Library.meta_running:
		var mr = SettingRow.new()
		mr.setup("action", "Genre und Jahr von Steam holen")
		mr.icon_name = "steam"
		mr.on_activate = func() -> void:
			if Library.meta_running:
				Library.stop_store_meta()
			else:
				Library.fetch_store_meta(_base())
			_meta_text()
		_meta_row = sheet.add_row(mr)
		_meta_text(lacking)
	sheet.add_label("Angaben aus dem Steam-Shop.", "s", "faint")


## Gespeicherte Ansichten (Filter, Abschnitte, Sortierung): speichern, anwenden, mit Y löschen.
func _order_ansichten(sheet) -> void:
	sheet.add_gap()
	sheet.add_label("Ansichten")
	var save = SettingRow.new()
	save.setup("action", "Als Ansicht speichern")
	save.icon_name = "save"
	save.value_text = "Filter, Abschnitte, Sortierung"
	save.on_activate = func() -> void: _save_preset(sheet)
	sheet.add_row(save)
	var active := _active_preset()
	var list := _presets()
	for i in list.size():
		var p: Dictionary = list[i]
		var r = SettingRow.new()
		r.setup("action", str(p.name))
		r.icon_name = "bookmark_f" if i == active else "bookmark"
		r.value_text = _preset_text(p)
		r.set_meta("uz_key", "lib:preset:" + str(p.name))
		r.set_meta("uz_hint_a", "Anwenden")
		r.set_meta("uz_hint_y", "Löschen")
		r.set_meta("uz_on_y", func() -> void: _delete_preset(str(p.name), sheet))
		r.on_activate = func() -> void:
			_apply_preset(p)
			sheet.refill()
		sheet.add_row(r)


## Filter nach eigenen Angaben (Tag, Kategorie, Altersfreigabe, Region) – nur, wo es welche gibt.
func _own_filter_rows(sheet, fc: Dictionary) -> void:
	var tags: Dictionary = fc.tag
	if not tags.is_empty():
		var opts: Array = [["", "Alle"]]
		for t in GameFields.by_count(tags):
			opts.append([t, "%s  (%d)" % [t, tags[t]]])
		if int(fc.no_tag) > 0:
			opts.append(["?", "%s  (%d)" % [GameFilter.NO_TAG, fc.no_tag]])
		sheet.add_row(_filter_row("Tags", "tag", "tag", opts))
	var cats: Dictionary = fc.category
	if not cats.is_empty():
		var opts: Array = [["", "Alle"]]
		for c in GameFields.by_count(cats):
			opts.append([c, "%s  (%d)" % [c, cats[c]]])
		if int(fc.no_category) > 0:
			opts.append(["?", "%s  (%d)" % [GameFilter.NO_CATEGORY, fc.no_category]])
		sheet.add_row(_filter_row("Kategorie", "category", "bookmark", opts))
	for e in [["age", "Altersfreigabe", "lock", GameFields.AGES], ["region", "Region", "tv", GameFields.REGIONS]]:
		var counts: Dictionary = fc[e[0]]
		if counts.is_empty():
			continue
		var opts: Array = [["", "Alle"]]
		var n := 0
		for k in e[3]:
			if counts.has(k[0]):
				opts.append([k[0], "%s  (%d)" % [k[1], counts[k[0]]]])
				n += int(counts[k[0]])
		opts.append(["?", "Ohne Angabe  (%d)" % (int(fc.installed) + int(fc.missing) - n)])
		sheet.add_row(_filter_row(e[1], e[0], e[2], opts))
	# Backlog (Roadmap 2): Status und Bewertung – nur, wo es welche gibt.
	var st: Dictionary = fc.status
	if not st.is_empty():
		var opts: Array = [["", "Alle"]]
		var n := 0
		for e in Backlog.STATUSES:
			if st.has(e[0]):
				opts.append([e[0], "%s  (%d)" % [e[1], st[e[0]]]])
				n += int(st[e[0]])
		opts.append(["?", "%s  (%d)" % [Backlog.NO_STATUS, int(fc.installed) + int(fc.missing) - n]])
		sheet.add_row(_filter_row("Backlog", "status", "bookmark", opts))
	var sr: Dictionary = fc.stars
	if not sr.is_empty():
		var opts: Array = [["", "Alle"]]
		for e in Backlog.STAR_FILTERS:
			if sr.has(e[0]):
				opts.append([e[0], "%s  (%d)" % [e[1], sr[e[0]]]])
		opts.append(["?", Backlog.NO_STARS])
		sheet.add_row(_filter_row("Bewertung", "stars", "star", opts))


func _choice(t: String, key: String, v: Variant, opts: Array) -> Control:
	var r = SettingRow.new()
	r.setup("choice", t, "", v)
	r.options = opts
	r.set_meta("uz_key", "lib:" + key)
	return r


## Eine Zeile je Filter: "" heißt „Alle“ (das Feld fällt weg). Werte als Text, das Jahrzehnt
## wird beim Setzen wieder zur Zahl.
func _filter_row(t: String, key: String, icon: String, opts: Array) -> Control:
	var cur := str(_filter.get(key, ""))
	var known: bool = opts.any(func(o): return str(o[0]) == cur)
	var r = _choice(t, key, cur if known else "", opts)
	r.icon_name = icon
	r.changed.connect(func(v: Variant) -> void:
		var s := str(v)
		_set_filter(key, null if s == "" else (int(s) if key == "decade" else s))
	)
	return r


func _set_filter(key: String, v: Variant) -> void:
	if v == null:
		_filter.erase(key)
	else:
		_filter[key] = v
	Config.set_value("library.filter", _filter.duplicate())
	_changed()


## Etwas im Ordnen geändert: Kopf und Zahl sofort, das Raster kurz nach dem letzten Druck (beim
## Durchblättern der Werte baut es sich so nicht bei jedem Schritt neu auf).
func _changed() -> void:
	_nur_wenn_anders = false
	_live_text()
	_update_head()
	_redo.start()


func _live_text() -> void:
	if is_instance_valid(_live_l):
		var base := _base()
		var n := _gefiltert(base).size()
		_live_l.text = ("Zeigt %d von %d Spielen" % [n, base.size()]) if n != base.size() else "Zeigt alle Spiele"
	if is_instance_valid(_reset_row):
		_reset_row.visible = not _filter.is_empty()


func _meta_text(lacking := -1) -> void:
	if not is_instance_valid(_meta_row):
		return
	if lacking < 0:
		lacking = Library.lacks_store_meta(_base()).size()
	_meta_row.set_meta("uz_hint_a", "Anhalten" if Library.meta_running else "Holen")
	var t := ("Läuft … noch %d" % lacking) if Library.meta_running else (U.plural(lacking, "Spiel", "Spiele") if lacking > 0 else "Alles da")
	_meta_row.set("value_text", t)
	Nav.focus_moved.emit(Nav.focused())


## Fortschritt beim Holen: die Zeile zählt herunter; zum Schluss ordnet sich das Raster neu, wenn
## es nach Genre oder Jahr geht.
func _on_meta_progress(done: int, _total: int) -> void:
	_meta_text()
	if done >= 0:
		return
	if _group in ["genre", "decade", "year"] or _filter.has("genre") or _filter.has("decade"):
		_nur_wenn_anders = false
		_redo.start()
	if is_instance_valid(_sheet):
		_sheet.call("refill")


# --- Mehrere Spiele auf einmal (Roadmap 42) --------------------------------------------------
# Angehakt wird im Raster selbst (wie beim Füllen eines Ordners). Jede Änderung fragt vorher nach
# und sagt, wie viele Spiele sie wirklich trifft; gerechnet wird in game_fields.gd.

## Wert, den kein Name haben kann (Steuerzeichen fallen beim Säubern weg): „Neu …“ in Auswahlen.
const NEW := "\u0001"


func _set_select(on: bool) -> void:
	_select = on
	_picked.clear()
	if on:
		set_meta("uz_hint_b", "Fertig")
	elif pick_folder == "":
		remove_meta("uz_hint_b")
	_refill()
	if on:
		Toasts.show_toast("Mehrere Spiele auswählen", "A hakt an, Y bearbeitet die Auswahl, B beendet.", "check", { "ms": 3500, "quiet": true })


## A im Auswahlmodus: an- oder abhaken (nach Tag kann dasselbe Spiel mehrmals im Raster stehen).
func _toggle_pick(gid: String, card: Control) -> void:
	if _picked.has(gid):
		_picked.erase(gid)
	else:
		_picked[gid] = true
	_mark_cards()
	Nav.focus_moved.emit(card)


## X im Auswahlmodus: alle, die das Raster zeigt – oder, wenn das schon so ist, keine.
func _pick_all() -> void:
	if not _shown.is_empty() and _shown.all(func(g): return _picked.has(str(g.get("id", "")))):
		_picked.clear()
	else:
		for g in _shown:
			_picked[str(g.get("id", ""))] = true
	_mark_cards()
	Nav.focus_moved.emit(Nav.focused())


func _mark_cards() -> void:
	for c in _cards:
		if not is_instance_valid(c):
			continue
		var on := _picked.has(str((c.get("game") as Dictionary).get("id", "")))
		if (int(c.get("checked")) == 1) != on:
			c.call("set_checked", on)
		c.set_meta("uz_hint_a", "Abwählen" if on else "Auswählen")
	_count.text = _count_text(_shown)


## Angehakt und im Raster zu sehen (was ein Filter inzwischen ausblendet, bleibt außen vor).
func _picked_games() -> Array:
	return _shown.filter(func(g): return _picked.has(str(g.get("id", ""))))


func _open_bulk() -> void:
	var list := _picked_games()
	if list.is_empty():
		Toasts.show_toast("Noch nichts ausgewählt", "Mit A Spiele anhaken, dann Y.", "info", { "ms": 2500, "quiet": true })
		return
	if is_instance_valid(_sheet):
		return
	var s = Sheet.new()
	s.setup("Auswahl bearbeiten", _names(list), 780)
	s.fill_func = _fill_bulk
	s.closed.connect(func() -> void:
		_sheet = null
		if not _redo.is_stopped():
			_refill()
	)
	_sheet = s
	main.open_layer(s)


## „Elden Ring, Hades und 3 weitere“
static func _names(list: Array) -> String:
	var t := PackedStringArray(list.slice(0, 2).map(func(g): return Library.display_title(g)))
	if list.size() <= 2:
		return ", ".join(t)
	return "%s und %d weitere" % [", ".join(t), list.size() - 2]


func _fill_bulk(sheet) -> void:
	var list := _picked_games()
	var n := list.size()
	sheet.add_label("Gilt für %s" % U.plural(n, "Spiel", "Spiele"), "s", "muted")
	sheet.add_gap(4)
	var favs := list.filter(func(g): return bool(g.get("favorite", false))).size()
	_bulk_row(sheet, "Favorit", "heart", "%d von %d" % [favs, n], func() -> void:
		main.open_choice("Favorit", [[true, "Als Favorit markieren"], [false, "Kein Favorit"]], null, func(v: Variant) -> void: _bulk_confirm(sheet, "fav", bool(v)))
	)
	_bulk_row(sheet, "Status", "bookmark", _common(list, func(g): return Backlog.status_name(Backlog.status_of(g))), func() -> void:
		var opts: Array = Backlog.STATUSES.map(func(e): return [e[0], e[1]])
		opts.append(["", "Kein Status"])
		main.open_choice("Status", opts, null, func(v: Variant) -> void: _bulk_confirm(sheet, "status", str(v)))
	)
	_bulk_row(sheet, "Ordner", "folder", "Hinein oder heraus", func() -> void: _bulk_folder(sheet))
	# Tags, Kategorie, Altersfreigabe und Region eine Ebene tiefer (wie in den Spiel-Optionen).
	_bulk_row(sheet, "Eigene Angaben", "tag", "Tags, Kategorie, Altersfreigabe …", func() -> void: _open_bulk_own(sheet))
	sheet.add_gap()
	var hid := list.filter(func(g): return bool(g.get("hidden", false))).size()
	_bulk_row(sheet, "Ausblenden", "eye_off", ("%d von %d ausgeblendet" % [hid, n]) if hid > 0 else "", func() -> void:
		main.open_choice("Ausblenden", [[true, "Ausblenden"], [false, "Wieder zeigen"]], null, func(v: Variant) -> void: _bulk_confirm(sheet, "hidden", bool(v)))
	)
	sheet.add_gap()


## Eigene Angaben für die ganze Auswahl: Tags hinzufügen oder entfernen, Kategorie, Altersfreigabe, Region.
func _open_bulk_own(parent) -> void:
	var s = Sheet.new()
	s.setup("Eigene Angaben", _names(_picked_games()), 780)
	s.fill_func = _fill_bulk_own
	s.closed.connect(func() -> void:
		if is_instance_valid(parent):
			parent.refill())
	main.open_layer(s)


func _fill_bulk_own(sheet) -> void:
	var list := _picked_games()
	_bulk_row(sheet, "Tag hinzufügen", "tag", "", func() -> void: _bulk_tag_add(sheet))
	var present := GameFields.all_tags(list)
	if not present.is_empty():
		_bulk_row(sheet, "Tag entfernen", "minus", ", ".join(PackedStringArray(GameFields.by_count(present).slice(0, 4))), func() -> void:
			var opts: Array = []
			for t in GameFields.by_count(present):
				opts.append([t, "%s  (%d)" % [t, present[t]]])
			main.open_choice("Tag entfernen", opts, null, func(v: Variant) -> void: _bulk_confirm(sheet, "tag_remove", str(v)))
		)
	_bulk_row(sheet, "Kategorie", "bookmark", _common(list, func(g): return GameFields.category_of(g)), func() -> void: _bulk_category(sheet))
	_bulk_row(sheet, "Altersfreigabe", "lock", _common(list, func(g): return GameFields.age_label(str(g.get("age", "")))), func() -> void:
		main.open_choice("Altersfreigabe", GameFields.AGES + [["", "Keine Angabe"]], null, func(v: Variant) -> void: _bulk_confirm(sheet, "age", str(v)))
	)
	_bulk_row(sheet, "Region", "tv", _common(list, func(g): return GameFields.region_label(str(g.get("region", "")))), func() -> void:
		main.open_choice("Region", GameFields.REGIONS + [["", "Keine Angabe"]], null, func(v: Variant) -> void: _bulk_confirm(sheet, "region", str(v)))
	)


func _bulk_row(sheet, t: String, icon: String, v: String, cb: Callable) -> Control:
	var r = SettingRow.new()
	r.setup("action", t)
	r.icon_name = icon
	r.value_text = v
	r.set_meta("uz_key", "bulk:" + t)
	r.on_activate = cb
	return sheet.add_row(r)


## Gemeinsamer Wert der Auswahl: der Wert, wenn alle ihn haben, sonst „Verschieden“ bzw. „Keine“.
static func _common(list: Array, f: Callable) -> String:
	var seen := {}
	for g in list:
		seen[str(f.call(g))] = true
	if seen.size() > 1:
		return "Verschieden"
	var v := str(seen.keys()[0]) if not seen.is_empty() else ""
	return v if v != "" else "Keine"


func _bulk_tag_add(sheet) -> void:
	var all := GameFields.all_tags(Library.games)
	var opts: Array = [[NEW, "Neuer Tag …"]]
	for t in GameFields.by_count(all).slice(0, 40):
		opts.append([t, "%s  (%d)" % [t, all[t]]])
	main.open_choice("Tag hinzufügen", opts, null, func(v: Variant) -> void:
		if str(v) != NEW:
			_bulk_confirm(sheet, "tag_add", str(v))
			return
		main.open_keyboard("Neuer Tag", "", func(t: String) -> void:
			var c := GameFields.clean_text(t, GameFields.TAG_MAX)
			if c != "":
				_bulk_confirm(sheet, "tag_add", c)
		)
	)


func _bulk_category(sheet) -> void:
	var opts: Array = [[NEW, "Neue Kategorie …"]]
	for c in GameFields.by_count(GameFields.categories(Library.games)):
		opts.append([c, c])
	opts.append(["", "Keine Kategorie"])
	main.open_choice("Kategorie", opts, null, func(v: Variant) -> void:
		if str(v) != NEW:
			_bulk_confirm(sheet, "category", str(v))
			return
		main.open_keyboard("Neue Kategorie", "", func(t: String) -> void:
			var c := GameFields.clean_text(t, GameFields.CATEGORY_MAX)
			if c != "":
				_bulk_confirm(sheet, "category", c)
		)
	)


## Ordner: nur die, in die mindestens eins der Spiele passt (Ordner für alle Systeme oder das
## eigene). Ein neuer Ordner gilt für alle Systeme und entsteht erst beim Übernehmen.
func _bulk_folder(sheet) -> void:
	var list := _picked_games()
	var opts: Array = [[NEW, "Neuer Ordner …"]]
	for f in Library.folders:
		if list.any(func(g): return GameFields.folder_fits(g, f)):
			var sys := str(f.get("system", ""))
			opts.append([str(f.id), str(f.name), str(Config.system(sys).get("short", "")) if sys != "" else ""])
	main.open_choice("Ordner", opts, null, func(v: Variant) -> void:
		if str(v) == NEW:
			main.open_keyboard("Neuer Ordner", "", func(t: String) -> void:
				var name := GameFields.clean_text(t, GameFields.CATEGORY_MAX)
				if name != "":
					_bulk_confirm(sheet, "folder_add", { "id": "", "name": name, "system": "" })
			)
			return
		var f := Library.folder(str(v))
		if f.is_empty():
			return
		main.open_choice(str(f.name), [["add", "In den Ordner legen"], ["remove", "Aus dem Ordner nehmen"]], null, func(w: Variant) -> void:
			_bulk_confirm(sheet, "folder_add" if str(w) == "add" else "folder_remove", f)
		)
	)


## Rückfrage mit der Zahl der Spiele, die sich wirklich ändern. Ändert sich nichts: nur ein Hinweis.
func _bulk_confirm(sheet, op: String, value: Variant) -> void:
	var list := _picked_games()
	var known: Variant = []
	if op == "tag_add":
		known = GameFields.all_tags(Library.games).keys()
	elif op == "category":
		known = GameFields.categories(Library.games).keys()
	var probe: Variant = value
	if op == "folder_add" and str(value.id) == "":
		probe = { "id": NEW, "system": "" }
	var n := Backlog.op_count(list, op, probe) if op in Backlog.OPS else GameFields.op_count(list, op, probe, known)
	if n == 0:
		Toasts.show_toast("Schon so", "Schon bei allen ausgewählten Spielen.", "check", { "ms": 2500, "quiet": true })
		return
	var text := "Betrifft %s." % U.plural(n, "Spiel", "Spiele")
	if n < list.size():
		text = ("Betrifft %d von %d ausgewählten Spielen." if op == "folder_add"
			else "Betrifft %d von %d ausgewählten Spielen.") % [n, list.size()]
	if op == "hidden" and bool(value):
		text += "\n\nZurückholen: A lange auf einer Quelle → Ausgeblendete Spiele."
	main.open_dialog(_op_text(op, value), text, [
		["Übernehmen", func() -> void: _bulk_apply(sheet, op, value)],
		["Abbrechen", func() -> void: pass],
	], "edit")


func _bulk_apply(sheet, op: String, value: Variant) -> void:
	var ids: Array = _picked_games().map(func(g): return str(g.get("id", "")))
	# Vorher merken (auch die Ordner, falls hier einer neu entsteht): kurz zurücknehmbar.
	var snap := Library.snapshot(ids, op == "folder_add")
	var v: Variant = value
	if op == "folder_add" and str(value.id) == "":
		var fid := Library.create_folder(str(value.name), "")
		if fid == "":
			return
		v = Library.folder(fid)
	var done := Library.update_many(ids, op, v)
	Undo.offer_games("%s geändert" % U.plural(done, "Spiel", "Spiele"), _op_done(op, v), "check", snap, func() -> void:
		if is_instance_valid(sheet):
			sheet.refill()
		_nur_wenn_anders = false
		_redo.start()
	)
	if is_instance_valid(sheet):
		sheet.refill()
	_nur_wenn_anders = false
	_redo.start()


static func _op_text(op: String, v: Variant) -> String:
	match op:
		"tag_add": return "Tag „%s“ hinzufügen?" % v
		"tag_remove": return "Tag „%s“ entfernen?" % v
		"category": return "Kategorie entfernen?" if str(v) == "" else "Kategorie „%s“ setzen?" % v
		"age": return "Altersfreigabe entfernen?" if str(v) == "" else "Altersfreigabe %s setzen?" % GameFields.age_label(str(v))
		"region": return "Region entfernen?" if str(v) == "" else "Region %s setzen?" % GameFields.region_label(str(v))
		"fav": return "Als Favorit markieren?" if v else "Favorit entfernen?"
		"hidden": return "Ausblenden?" if v else "Wieder zeigen?"
		"folder_add": return "In „%s“ legen?" % str(v.name)
		"folder_remove": return "Aus „%s“ nehmen?" % str(v.name)
		"status": return "Status entfernen?" if str(v) == "" else "Status „%s“ setzen?" % Backlog.status_name(str(v))
	return ""


static func _op_done(op: String, v: Variant) -> String:
	match op:
		"tag_add": return "Tag „%s“" % v
		"tag_remove": return "Tag „%s“ entfernt" % v
		"category": return "Ohne Kategorie" if str(v) == "" else "Kategorie „%s“" % v
		"age": return "Ohne Altersfreigabe" if str(v) == "" else GameFields.age_label(str(v))
		"region": return "Ohne Region" if str(v) == "" else GameFields.region_label(str(v))
		"fav": return "Favoriten" if v else "Keine Favoriten mehr"
		"hidden": return "Ausgeblendet" if v else "Wieder zu sehen"
		"folder_add": return "Im Ordner „%s“" % str(v.name)
		"folder_remove": return "Aus „%s“ genommen" % str(v.name)
		"status": return "Ohne Status" if str(v) == "" else Backlog.status_name(str(v))
	return ""


# --- Gespeicherte Ansichten ------------------------------------------------------------------

func _presets() -> Array:
	return GameFilter.clean_presets(Config.get_value("library.presets", []), SORTS)


## Welche gespeicherte Ansicht gerade gilt (Filter und Abschnitte gleich, Sortierung gleich oder
## egal), sonst -1.
func _active_preset() -> int:
	var list := _presets()
	for i in list.size():
		var p: Dictionary = list[i]
		if p.filter == _filter and str(p.group) == _group and (str(p.sort) == "" or str(p.sort) == _sort):
			return i
	return -1


func _preset_text(p: Dictionary) -> String:
	var bits := PackedStringArray()
	if str(p.group) != "":
		bits.append(GameFilter.group_name(str(p.group)))
	var f := GameFilter.summary(p.filter)
	if f != "":
		bits.append(f)
	return " · ".join(bits) if not bits.is_empty() else "Alle Spiele"


func _save_preset(sheet) -> void:
	var a := _active_preset()
	main.open_keyboard("Name der Ansicht", str(_presets()[a].name) if a >= 0 else "", func(t: String) -> void:
		var n := t.strip_edges().left(GameFilter.NAME_MAX)
		if n == "":
			return
		var list := _presets()
		var entry := { "name": n, "filter": _filter.duplicate(), "group": _group, "sort": _sort }
		var at := -1
		for i in list.size():
			if str(list[i].name).to_lower() == n.to_lower():
				at = i
		if at >= 0:
			list[at] = entry
		elif list.size() >= GameFilter.PRESETS_MAX:
			Toasts.show_toast("Nicht gespeichert", "Höchstens %d Ansichten." % GameFilter.PRESETS_MAX, "info")
			return
		else:
			list.append(entry)
		Config.set_value("library.presets", list)
		_update_head()
		if is_instance_valid(sheet):
			sheet.refill()
	)


func _delete_preset(n: String, sheet) -> void:
	main.open_dialog("Ansicht löschen?", "„%s“ wird entfernt. Die Spiele bleiben." % n, [
		["Löschen", func() -> void:
			var old: Array = (Config.get_value("library.presets", []) as Array).duplicate(true)
			Config.set_value("library.presets", _presets().filter(func(p): return str(p.name) != n))
			_update_head()
			if is_instance_valid(sheet):
				sheet.refill()
			Undo.offer_setting("Ansicht gelöscht", n, "trash", "library.presets", old, func() -> void:
				_update_head()
				if is_instance_valid(sheet):
					sheet.refill()
			), "danger"],
		["Abbrechen", func() -> void: pass],
	])


func _apply_preset(p: Dictionary) -> void:
	_filter = (p.filter as Dictionary).duplicate()
	_group = str(p.group)
	if str(p.sort) != "":
		_sort = str(p.sort)
		Config.set_value("library.sort", _sort)
	Config.set_value("library.filter", _filter.duplicate())
	Config.set_value("library.group", _group)
	_changed()


## LB/RB: durch „Alle Spiele“ und die gespeicherten Ansichten blättern (Sortierung bleibt bei
## „Alle Spiele“, wie sie ist).
func _step_preset(d: int) -> void:
	var list := _presets()
	if list.is_empty():
		return
	var i := _active_preset() + 1
	var n := list.size() + 1
	i = (i + d + n) % n
	if i == 0:
		_apply_preset({ "filter": {}, "group": "", "sort": "" })
	else:
		_apply_preset(list[i - 1])
	Sfx.play("tick")
	var tw := U.tw(_view_l, "uz_view")
	_view_l.modulate.a = 0.3
	tw.tween_property(_view_l, "modulate:a", 1.0, U.T_ORT)
	_refill()


# --- Viele Spiele: nur laden, was zu sehen ist ------------------------------------------------

## Blöcke in Sichtweite (plus gut eine Bildschirmhöhe Vorlauf) legen ihre Karten an; Karten in Sichtweite laden
## ihr Cover, weit entfernte geben es frei. Geprüft wird nur, wenn sich die Lage geändert hat (Scrollen, neu
## gefüllt).
func _process(_dt: float) -> void:
	if not _vis_due or not is_instance_valid(_body):
		return
	_vis_due = false
	var view := get_viewport_rect()
	var near := view.grow(view.size.y * 0.8)
	var far := view.grow(view.size.y * 2.5)
	if _leer > 0:
		var neu := 0
		for nr in _bloecke.size():
			if bool(_bloecke[nr].voll) or not near.intersects((_grids[nr] as Control).get_global_rect()):
				continue
			if neu > 0 and neu + int(_bloecke[nr].n) > KARTEN_JE_BILD:
				break
			neu += int(_bloecke[nr].n)
			_block_fuellen(nr)
		if neu > 0:
			# Die neuen Karten stehen erst im nächsten Bild an ihrem Platz: dann weiter (auch mit dem Rest).
			set_deferred("_vis_due", true)
			return
	for c in _cards:
		if not is_instance_valid(c):
			continue
		var r: Rect2 = (c as Control).get_global_rect()
		if near.intersects(r):
			c.call("load_image")
		elif not far.intersects(r) and c.call("image_requested"):
			c.call("unload_image")


## Steuerkreuz im Raster über die Lage im Gitter statt räumlicher Suche über alle Karten
## (bei 342 Spielen kostete jeder Schritt bis 29 ms). Am oberen oder unteren Rand eines
## Abschnitts geht es in derselben Spalte in den nächsten. false: Nav sucht wie sonst.
func _grid_move(card: Control, dir: String) -> bool:
	var grid := card.get_parent() as GridContainer
	var gi := _grids.find(grid)
	if gi < 0:
		return false
	var i := card.get_index()
	var to := grid_target(i, grid.get_child_count(), _cols, dir)
	if to >= 0:
		Nav.focus(grid.get_child(to) as Control)
		return true
	var col := i % _cols
	if dir == "down" and gi + 1 < _grids.size():
		_block_fuellen(gi + 1)
		var nxt: GridContainer = _grids[gi + 1]
		Nav.focus(nxt.get_child(mini(col, nxt.get_child_count() - 1)) as Control)
		return true
	if dir == "up" and gi > 0:
		_block_fuellen(gi - 1)
		var prev: GridContainer = _grids[gi - 1]
		var n := prev.get_child_count()
		Nav.focus(prev.get_child(mini((n - 1) - (n - 1) % _cols + col, n - 1)) as Control)
		return true
	return false


## Ziel im Gitter (Index) oder -1, wenn es in dieser Richtung keine Karte mehr gibt.
static func grid_target(i: int, n: int, cols: int, dir: String) -> int:
	match dir:
		"left":
			return i - 1 if i % cols > 0 else -1
		"right":
			return i + 1 if i % cols < cols - 1 and i + 1 < n else -1
		"up":
			return i - cols if i - cols >= 0 else -1
		"down":
			if i + cols < n:
				return i + cols
			# Letzte, kürzere Reihe: auf ihre letzte Karte.
			return n - 1 if floori(i / float(cols)) < floori((n - 1) / float(cols)) else -1
	return -1
