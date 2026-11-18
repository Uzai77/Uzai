extends "res://src/ui/sections/section.gd"
## Spiele (Startseite): oben links das gewählte Spiel groß, darunter die Quellen (PS2, Steam, …)
## als Reiter und unten das Regal mit den Covern. „Für dich“ liegt hinter der Start-Taste als
## Seitenleiste von rechts (fuer_dich_leiste.gd); die Karten dafür mischt die Startseite vorab.
## Was A, X, Y und Start auf dem gewählten Cover tun, steht in der Tastenzeile (Y „Optionen“,
## Start „Für dich“); der Cursor bleibt auf dem Cover (ein Druck).
## Unterbereiche: Zuletzt, Favoriten, Aufnahmen (eigene Clips und Bildschirmfotos), je System,
## Steam, PC, Ordner, Alle.
##
## Steuerkreuz senkrecht in einer festen Reihenfolge: Regal ↔ Quellen ↔ Bereiche.

const FolderTile := preload("res://src/ui/components/folder_tile.gd")
const CoverRow := preload("res://src/ui/components/cover_row.gd")
const BG := preload("res://src/ui/components/background.gd")
const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")
const Kacheln := preload("res://src/core/kacheln.gd")
const Logos := preload("res://src/core/badge_logos.gd")
const Quellen := preload("res://src/ui/sections/quellen_ordnung.gd")
const MosaikSeite := preload("res://src/ui/layers/mosaik_seite.gd")
const RegalSeite := preload("res://src/ui/layers/regal_seite.gd")
const Regal := preload("res://src/library/regal.gd")
const FuerDichLeiste := preload("res://src/ui/layers/fuer_dich_leiste.gd")
const Aufbau := preload("res://src/ui/sections/startseite_aufbau.gd")

var _shelf = null
var _col: VBoxContainer          ## Spalte der Seite (Regal wird darin getauscht)
var _hero_box: VBoxContainer
var _title_l: Label
var _logo: TextureRect
var _meta: HBoxContainer
var _tag: Label
var _faces: HBoxContainer        ## Freunde, die das gewählte Spiel gerade spielen (hinter der Zeile)
var _count_l: Label
var _selected: Dictionary = {}
var _last_by_sub := {}
var _hero_tw: Tween
var _hero_geist: Control        ## Abbild des alten Kopfs, das beim Wechsel ausblendet
var _hero_ms := 0
var _hero_id := ""
var _hero_idx := -1
var _hero_dir := 1             ## zuletzt geblättert: 1 nach rechts, -1 nach links


func _init() -> void:
	super()
	id = "games"
	title = "Spiele"
	icon_name = "games"
	chip_counts = false


## Luft über dem Regal: Ein gewähltes Cover wächst nach oben (ruhig, 3 %) und trägt den Rahmen
## des Cursors. Steht die Auswahl anderswo (Quellen, Reiter), rückt die Quellenleiste etwas
## näher an die Cover. Früher 82 bzw. 40 – für Cover, die um 12 % wuchsen.
const SHELF_TOP := 40
## Covers on the home screen are 20 % larger than the chosen cover size, but at most so tall that
## header, sources and shelf still fit on top of each other at 1080p.
const SHELF_SCALE := 1.2
const SHELF_MAX_H := 360.0
const SHELF_TOP_REST := 26
## Mit großer Oberfläche (weniger Höhe) wird die Luft knapper (U.by_room), damit das Regal über
## der Tastenleiste bleibt: oben genug fürs wachsende Cover, unten nur ein Rest der Spiegelung.
var _shelf_top := float(SHELF_TOP)
var _shelf_rest := float(SHELF_TOP_REST)
var _lift_tw: Tween
var _lift_at := -1.0
var _chips_m: MarginContainer


func _shelf_has_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return f != null and is_instance_valid(_shelf) and _shelf.is_ancestor_of(f)


## Beim (Neu-)Aufbau des Regals: Landet der Fokus gleich darin? Ja, außer er steht auf den
## Quellen oder oben auf den Reitern. Früher galt hier „hat das neue Regal schon
## den Fokus?“ – das ist beim Aufbau nie so: Mit LB/RB im Regal und beim Zurückkehren auf die
## Startseite sprang die Quellenleiste erst 42 px nach unten und glitt dann zurück.
func _shelf_will_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f == null or not f.is_visible_in_tree():
		return true
	if is_instance_valid(chips_slot) and chips_slot.is_ancestor_of(f):
		return false
	# Nach Schlüssel auch für Knoten der alten Seite (Neuaufbau, der Fokus kehrt per Schlüssel zurück).
	var k := str(f.get_meta("uz_key", ""))
	return not (k.begins_with("tab:") or k.begins_with("chip:") or k.begins_with("fy:"))


func _lift_shelf(focused: bool, instant := false) -> void:
	if not is_instance_valid(_shelf) or not _shelf.has_method("set_pad_top") or not is_instance_valid(_chips_m):
		return
	var row: Control = _shelf
	var cm: MarginContainer = _chips_m
	# Was die Leiste nach unten rückt, nimmt sie dem Regal oben weg: Die Cover bleiben stehen.
	var to := 0.0 if focused else _shelf_top - _shelf_rest
	if to == _lift_at and not instant:
		return
	_lift_at = to
	if _lift_tw:
		_lift_tw.kill()
	var put := func(v: float) -> void:
		if is_instance_valid(row) and is_instance_valid(cm):
			cm.add_theme_constant_override("margin_top", int(v))
			row.call("set_pad_top", _shelf_top - float(int(v)))
	if instant:
		put.call(to)
		return
	var from := float(cm.get_theme_constant("margin_top"))
	_lift_tw = create_tween()
	_lift_tw.tween_method(put, from, to, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(func(_c: Control) -> void:
		if is_visible_in_tree():
			_lift_shelf(_shelf_has_focus())
	)
	Social.updated.connect(_on_data_updated)
	Voice.changed.connect(_queue_foryou)
	Achievements.updated.connect(_on_ach)
	Movies.changed.connect(_queue_foryou)
	Music.updated.connect(_on_music)
	Launcher.ended.connect(func(_g: Dictionary, _s: int) -> void: _fy_reshuffle = true)
	visibility_changed.connect(_on_foryou_visible)
	Discs.changed.connect(_on_disc)
	Config.changed.connect(func(path: String) -> void:
		if path.begins_with("badges"):
			Logos.forget()
			_queue_chip_logos())


# --- Logos der Quellen ---------------------------------------------------------------------

## Höhe der Logos in der Quellen-Zeile (Punkte bei 1080p) und größte Breite.
const CHIP_LOGO_H := 21.0
const CHIP_LOGO_W := 118.0


## Quelle (PS2, GameCube, Steam …) als echtes Logo, einfarbig wie die Schrift – nur wenn es da ist
## (badge_logos.gd: eigene Datei oder geladen, Einstellung „Echte Konsolen-Logos“); sonst {} und
## dort steht der Name. Fehlt es noch, lädt es im Hintergrund und die Zeile baut sich danach neu.
func chip_logo(sub_id: String) -> Dictionary:
	var key := Logos.source_key(sub_id)
	if key == "":
		return {}
	var got := Logos.line_logo(key, CHIP_LOGO_H, CHIP_LOGO_W)
	if got.is_empty() and Logos.enabled() and Logos.net:
		var l := Logos.loader()
		if l and not l.is_connected("logo_ready", _on_logo_ready):
			l.connect("logo_ready", _on_logo_ready)
	return got


func _on_logo_ready(key: String) -> void:
	if subtabs().any(func(t: Dictionary) -> bool: return Logos.source_key(str(t.id)) == key):
		_queue_chip_logos()


var _chip_logos_due := false


## Neu geladene Logos gesammelt einsetzen (mehrere kommen kurz nacheinander).
func _queue_chip_logos() -> void:
	if _chip_logos_due:
		return
	_chip_logos_due = true
	await get_tree().create_timer(0.4).timeout
	_chip_logos_due = false
	if main and main.current == id:
		main.refresh_chips()


func _on_data_updated(_what: String) -> void:
	_queue_foryou()


var _foryou_due := false


## Zur gewählten Quelle (aus dem Regal nach oben).
func _focus_chip() -> bool:
	if not is_instance_valid(chips_slot):
		return false
	var list := Nav.focusables(chips_slot)
	for c in list:
		if c.get_meta("uz_selected", false):
			Nav.focus(c)
			return true
	if not list.is_empty():
		Nav.focus(list[0])
		return true
	return false


## Quellen, wie sie oben stehen: in eigener Reihenfolge, ohne ausgeblendete (langes A auf einer
## Quelle, quellen_ordnung.gd).
func subtabs() -> Array:
	return Quellen.arrange(all_subtabs(), Config.get_value("library.sub_order", []), Config.get_value("library.hidden_subs", []))


## After the sources: add a custom game without a launcher (an .exe, a shortcut or a whole folder, item 117).
## Previously this existed only as a tile at the very end of „PC“ and „Alle“ – impossible to find among hundreds
## of games, so there was no visible way to add a non-Steam game. Such games have the same options as the others
## (game_options.gd), plus launch parameters and a working directory.
func chip_aktionen() -> Array:
	return [{ "id": "neu", "label": "Hinzufügen", "icon": "plus", "tun": func() -> void: main.open_add_game() }]


## Langes A auf einer Quelle: Verschieben, Ausblenden, Ausgeblendetes zurückholen.
func sub_menu(sub_id: String, label: String) -> void:
	Quellen.menu(main, self, sub_id, label)


## Alle Quellen mit Anzahl. Ein Durchgang über die Bibliothek zählt alles auf einmal (früher je
## System, Ordner und Favoriten ein eigener Durchgang).
func all_subtabs() -> Array:
	var vis := Library.visible_games()
	var per_sys := {}
	var per_folder := {}
	var favs := 0
	var steam_an := Library.Stores.enabled("steam")
	for g in vis:
		var sid := str(g.get("system", ""))
		per_sys[sid] = int(per_sys.get(sid, 0)) + 1
		# Dasselbe Spiel auch in einem anderen Launcher (Library.by_system zeigt es dort mit).
		if g.get("alts") is Array:
			for a in g.alts:
				var asid := str(a).get_slice(":", 0)
				if asid != sid:
					per_sys[asid] = int(per_sys.get(asid, 0)) + 1
		# Selbst hinzugefügte stehen auch unter „Steam“ (Library.by_tab).
		if steam_an and Library.eigen(g):
			per_sys["steam"] = int(per_sys.get("steam", 0)) + 1
		if bool(g.get("favorite", false)):
			favs += 1
		for fid in g.get("folders", []):
			per_folder[str(fid)] = int(per_folder.get(str(fid), 0)) + 1
	var out: Array = [{ "id": "zuletzt", "label": "Zuletzt" }]
	if favs > 0:
		out.append({ "id": "favoriten", "label": "Favoriten", "count": favs })
	for sys in Config.systems_enabled():
		var n := int(per_sys.get(str(sys.id), 0))
		if n > 0:
			out.append({ "id": str(sys.id), "label": str(sys.get("short", sys.name)), "count": n })
	for extra in [["steam", "Steam"], ["epic", "Epic"], ["ea", "EA"]] + Library.Stores.EXTRA.map(
			func(id: String) -> Array: return [id, Library.Stores.name_of(id, true)]) + [["pc", "PC"]]:
		var n2 := int(per_sys.get(extra[0], 0))
		if n2 > 0:
			out.append({ "id": extra[0], "label": extra[1], "count": n2 })
	for f in Library.global_folders():
		out.append({ "id": "ordner:" + str(f.id), "label": str(f.name), "count": int(per_folder.get(str(f.id), 0)) })
	if vis.size() > 0:
		out.append({ "id": "alle", "label": "Alle", "count": vis.size() })
	return out


func games_for(sub_id: String) -> Array:
	match sub_id:
		"zuletzt": return _with_disc(Library.recent(24))
		Quellen.HIDDEN_GAMES: return Library.sorted(Library.hidden_games(), "title")
	return Library.sorted(games_of(sub_id))


## Dieselben Spiele einer Quelle in der Reihenfolge der Bibliothek, unsortiert – für das Raster
## (library_grid.gd), das selbst sortiert. „zuletzt“ gibt es hier nicht (dort: alle sichtbaren).
func games_of(sub_id: String) -> Array:
	match sub_id:
		"favoriten": return Library.favorites()
		"alle": return Library.visible_games()
		Quellen.HIDDEN_GAMES: return Library.hidden_games()
	if sub_id.begins_with("ordner:"):
		return Library.in_folder(sub_id.substr(7))
	return Library.by_tab(sub_id)


## Eingelegte Disc: ihr Spiel ganz vorn in „Zuletzt“ (auch wenn es noch nie gespielt wurde).
## Ohne passendes Abbild steht die Disc selbst dort, mit Namen; A spielt sie vom Laufwerk.
func _with_disc(list: Array) -> Array:
	var dg := Discs.game()
	if dg.is_empty():
		var e := Discs.entry()
		return list if e.is_empty() else [e] + list.slice(0, 23)
	var did := str(dg.id)
	return [dg] + list.filter(func(g): return str(g.get("id", "")) != did).slice(0, 23)


## Disc eingelegt oder entfernt: Regal von „Zuletzt“ neu legen, die Disc vorn und gewählt.
## Auf einer anderen Seite merkt sich die Startseite das nur (nächstes Bauen zeigt es).
func _on_disc(inserted: bool) -> void:
	if inserted:
		_last_by_sub["zuletzt"] = Discs.game_id if Discs.game_id != "" else "disc:" + Discs.serial
	if not is_inside_tree() or not is_visible_in_tree() or not is_instance_valid(_shelf):
		return
	var f := Nav.focused()
	var in_shelf: bool = f == null or _shelf.is_ancestor_of(f)
	# In „Zuletzt“ rückt die Disc nach vorn, in anderen Quellen bekommt nur ihr Cover die Plakette.
	if not switch_sub():
		return
	if in_shelf and Nav.top_layer() == null and is_instance_valid(_shelf):
		var d := Nav.default_in(_shelf)
		if d:
			Nav.focus(d, true)


# --- Aufbau ------------------------------------------------------------------------------

func build() -> void:
	if main:
		main.park_chips()
	U.clear(self)
	_selected = {}
	_hero_idx = -1
	chips_slot = null
	var list := games_for(sub)
	if Library.visible_games().is_empty():
		_build_empty()
		return
	var col := U.vbox(0)
	U.full_rect(col)
	add_child(col)
	# Oben links das Spiel, unten auf der Linie direkt über den Quellen; oben bleibt Luft für den
	# Lichtschein des Spiels, rechts steht frei das große Spielbild (seit „Für dich“ hinter der
	# Start-Taste liegt). Bei größerer Oberfläche (weniger Höhe) wird die Luft knapper, damit das
	# Regal über der Tastenleiste bleibt.
	var vs := U.view_size()
	_shelf_top = U.by_room(SHELF_TOP, 42.0)
	_shelf_rest = minf(SHELF_TOP_REST, _shelf_top - 6.0)
	_hero_w = minf(HERO_W, U.room_w(GUTTER))
	_compact = U.tight() >= 0.4
	var top := U.margin(GUTTER, int(clampf(66.0 - (1080.0 - vs.y), 4.0, 66.0)), GUTTER, int(U.by_room(30.0, 8.0)))
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(top)
	top.add_child(_build_hero())
	# Quellen über dem Regal: nur die Namen, rechts die Anzahl.
	var cm := U.margin(GUTTER - 16, 0, GUTTER, 0)
	col.add_child(cm)
	_chips_m = cm
	var crow: HBoxContainer = _LINE.new()
	cm.add_child(crow)
	chips_slot = U.hbox(0)
	chips_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(chips_slot)
	_count_l = U.label("", "s", "faint", "medium")
	_count_l.clip_text = false
	_count_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crow.add_child(_count_l)
	_col = col
	_refresh_foryou()
	if main and main.current == id:
		main.place_chips(chips_slot)
	_fill_shelf(list)


## Die Startseite baut sich vor den Augen auf (nach „Los“ am Ende der Einrichtung, nicht bei jedem
## Start): Licht und Raum, Leiste, Spielbild und Titel, Quellen, Cover mit Spiegelung, Tastenzeile,
## zuletzt der Fokus (startseite_aufbau.gd). fluege: Spiel-IDs, deren Cover die Einrichtung
## herüberfliegt – sie landen genau auf ihren Plätzen (gelandet()). Gibt den Ablauf zurück (Signale
## bereit und fertig), null, wenn die Startseite gerade nicht zu sehen ist.
func aufbauen(von_einrichtung := true, fluege: Array = []) -> Node:
	if main == null or not is_inside_tree() or not is_visible_in_tree():
		return null
	var teile := {}
	if is_instance_valid(_shelf) and is_instance_valid(_hero_box):
		teile["kopf"] = [_meta, _title_l, _logo, _tag.get_parent()]
		teile["regal"] = _shelf
		if is_instance_valid(_chips_m) and _chips_m.get_child_count() > 0:
			teile["linie"] = _chips_m.get_child(0)
		var cb: Variant = main.chips_box
		if cb is Control and is_instance_valid(cb) and is_instance_valid(chips_slot) and chips_slot.is_ancestor_of(cb):
			teile["quellen"] = (cb as Control).get_children()
			teile["quellen_leiste"] = cb
		teile["anzahl"] = _count_l
	else:
		# Noch keine Spiele (oder anders gebaut): der Inhalt blendet nur auf.
		teile["inhalt"] = get_children()
	# Das Bild des gewählten Spiels steht schon (unter der Einrichtung geladen); falls nicht, jetzt
	# anstoßen, damit es mit dem Licht kommt.
	if not _selected.is_empty():
		_set_bg(_selected)
	var a: Node = Aufbau.new()
	a.set("von_einrichtung", von_einrichtung)
	main.add_child(a)
	a.call("start", main, self, teile, fluege)
	return a


## Quelle wechseln (PS2 → GameCube …), ohne die Seite neu zu bauen: Nur das Regal wird
## getauscht – das alte kreuzt an seinem Platz aus (U.abheben), das neue kommt im selben Bild
## (U.ankunft, ohne Weg: Die Spalte setzt die Lage selbst); Kopf und Quellenleiste
## bleiben stehen.
## Früher baute jeder Wechsel alles neu – das flackerte, und weil die Quellenleiste dabei kurz
## aus dem Baum fiel, sprang der Fokus aufs Regal statt auf der Leiste zu bleiben.
## false: geht so nicht (z. B. leere Bibliothek), dann baut main.gd wie bisher alles neu.
func switch_sub(_dir := 0) -> bool:
	if not is_instance_valid(_col) or not is_instance_valid(_shelf) or not is_instance_valid(chips_slot) \
			or Library.visible_games().is_empty():
		return false
	var old = _shelf
	var at: int = old.get_index()
	# Das neue Regal steht im selben Aufruf an der Stelle (die Spalte ordnet erst danach): kein
	# Bild, in dem sie zusammenrückt.
	U.abheben(old)
	_selected = {}
	_fill_shelf(games_for(sub), at)
	if is_instance_valid(_shelf):
		U.ankunft(_shelf, 0)
	return true


## Das Regal einer Quelle bauen (an Stelle at in der Spalte, -1 = ans Ende).
func _fill_shelf(list: Array, at := -1) -> void:
	var col: VBoxContainer = _col
	# Regal unten. Oben Luft für das wachsende Cover, unten für Spiegelung und Schatten.
	# Das gewählte Cover steht links bündig mit dem Text darüber; die Reihe gleitet hinterher.
	_shelf = CoverRow.new().setup("covers:" + sub, 34, true, int(_shelf_top), GUTTER, int(U.by_room(46.0, 12.0)))
	col.add_child(_shelf)
	_lift_shelf(_shelf_will_focus(), true)
	if at >= 0:
		col.move_child(_shelf, at)
	var up_to_chip := func() -> bool: return _focus_chip()
	var tiles: Array = []
	if not (sub in ["zuletzt", "favoriten", "alle"]) and not sub.begins_with("ordner:"):
		tiles = Library.folders_for(sub)
		for f in tiles:
			var ft = FolderTile.new()
			ft.setup(f)
			ft.grow_left = true
			ft.set_meta("uz_hint_y", "Ordner bearbeiten")
			ft.set_meta("uz_on_y", func() -> void: main.open_folder_options(f))
			ft.set_meta("uz_up", up_to_chip)
			ft.chosen.connect(func(fo: Dictionary) -> void: open_mosaik("ordner:" + str(fo.id), str(fo.name)))
			ft.focus_entered.connect(func() -> void: _show_folder(f))
			_shelf.add(ft)
		if Config.get_value("library.folder_hide", false) and not tiles.is_empty():
			list = list.filter(func(g): return not tiles.any(func(f): return Library.is_in_folder(g, str(f.id))))
	var limit := 40 if sub != "zuletzt" else 24
	# Ein Schild je Cover: die Plattform, nur wo die Quelle gemischt ist (Zuletzt, Favoriten,
	# Ordner, Alle) – im Regal von PS2 sagte jedes Cover dasselbe wie der Reiter darüber. Die
	# eingelegte Disc steht im Kopf, nicht als zweites Schild auf dem Cover.
	var mixed := _mixed_source()
	# Gleich gebaut wird, was man sieht (und das gemerkte Spiel samt Nachbarn); der Rest kommt in den nächsten
	# Bildern (U.nach_und_nach). Gemessen: 25 Cover kosteten im Tastendruck 12–22 ms, das Bild danach 40–57 ms.
	var merk := str(_last_by_sub.get(sub, ""))
	var sofort := REGAL_SOFORT
	for i in mini(list.size(), limit):
		if str(list[i].get("id", "")) == merk:
			sofort = maxi(sofort, i + 4)
	var shelf: CoverRow = _shelf
	var spaeter: Array = []
	for g in list.slice(sofort, limit):
		spaeter.append(func() -> void:
			if is_instance_valid(shelf):
				_regal_karte(shelf, g, mixed, up_to_chip))
	for g in list.slice(0, mini(sofort, limit)):
		_regal_karte(_shelf, g, mixed, up_to_chip)
	var ende := func() -> void:
		if is_instance_valid(shelf):
			_regal_ende(shelf, list, limit, up_to_chip)
	if spaeter.is_empty() or not is_visible_in_tree():
		for s in spaeter:
			(s as Callable).call()
		ende.call()
	else:
		spaeter.append(ende)
		U.nach_und_nach(shelf, spaeter)
	_count_l.text = _count_text(list.size())
	_regal_fokus(list, tiles)


const REGAL_SOFORT := 10        ## so viele Cover baut das Regal gleich, der Rest kommt danach (U.nach_und_nach)


## Ein Cover im Regal der Startseite.
func _regal_karte(shelf: CoverRow, g: Dictionary, mixed: bool, up_to_chip: Callable) -> void:
	var card = CoverCard.new()
	card.setup(g, mixed, shelf_cover())
	card.grow_up = true
	card.grow_left = true
	card.reflect = true
	card.live = true
	if str(g.get("source", "")) == "disc":
		# Disc ohne Abbild: A spielt sie direkt vom Laufwerk (wenn der Emulator das kann), Y
		# ordnet ihr ein Abbild zu.
		var direct := Discs.can_play()
		card.set_meta("uz_hint_a", "Von Disc spielen" if direct else "Abbild zuordnen")
		if direct:
			card.set_meta("uz_hint_y", "Abbild zuordnen")
			card.set_meta("uz_on_y", func() -> void: main.open_disc_assign())
		card.set_meta("uz_up", up_to_chip)
		card.chosen.connect(func(_game: Dictionary) -> void: main.play_disc())
		card.focused_game.connect(_on_game_focused)
		shelf.add(card)
		return
	var hint_a := "Öffnen" if main.game_page_on() else ("Spielen" if g.get("installed", true) else "Installieren")
	card.set_meta("uz_hint_a", hint_a)
	card.set_meta("uz_hint_y", "Optionen")
	card.set_meta("uz_on_y", func() -> void: main.open_game_options(g))
	# Befehl, kein Zustand: X schaltet „Favorit“ um, ob er an ist, zeigt der Stern am Cover.
	card.set_meta("uz_hint_x", "Favorit")
	card.set_meta("uz_on_x", func() -> void: _toggle_fav(g))
	card.set_meta("uz_up", up_to_chip)
	# Auch mit eingelegter Disc erst die Spielseite (wie bei allen Spielen); „Spielen“ startet
	# dort das Abbild aus der Bibliothek (schneller und leiser als das Laufwerk).
	card.chosen.connect(func(game: Dictionary) -> void: main.open_game(game))
	card.focused_game.connect(_on_game_focused)
	shelf.add(card)


## Die Kacheln am Ende des Regals (Alle, Steam-Spiele, Hinzufügen, Zimmer) – nach dem letzten Cover.
func _regal_ende(shelf: CoverRow, list: Array, limit: int, up_to_chip: Callable) -> void:
	if list.size() > limit or (sub != "zuletzt" and list.size() > 6):
		var all_tile := _all_card(list)
		all_tile.set_meta("uz_up", up_to_chip)
		shelf.add(all_tile)
	if steam_owned_offer(sub):
		var own_tile := _steam_owned_card()
		own_tile.set_meta("uz_up", up_to_chip)
		shelf.add(own_tile)
	if sub in ["pc", "alle"]:
		var add_tile := _add_card()
		add_tile.set_meta("uz_up", up_to_chip)
		shelf.add(add_tile)
	if sub == "zuletzt" and bool(Config.get_value("room.kachel", true)):
		var room_tile := _room_card()
		room_tile.set_meta("uz_up", up_to_chip)
		shelf.add(room_tile)


## Startfokus des Regals: das gemerkte Spiel, sonst der erste Ordner bzw. das erste Spiel.
func _regal_fokus(list: Array, tiles: Array) -> void:
	var remember: String = _last_by_sub.get(sub, "")
	var pick: Dictionary = {}
	for g in list:
		if str(g.id) == remember:
			pick = g
	# Gibt es Ordner und noch keine gemerkte Position, steht der Fokus auf dem ersten Ordner,
	# damit die Ordner nicht links aus dem Bild geschoben werden.
	if pick.is_empty() and not tiles.is_empty():
		var first_tile: Control = _shelf.items()[0]
		first_tile.set_meta("uz_default", true)
		first_tile.set_meta("uz_entry", true)
		_show_folder(tiles[0])
		return
	if pick.is_empty() and not list.is_empty():
		pick = list[0]
	_show(pick)
	for card in _shelf.items():
		if card.get("game") is Dictionary and str(card.game.get("id", "")) == str(pick.get("id", "")):
			# Gemerktes Spiel: Startfokus, Ziel beim Hineingehen und schon jetzt an der Kante.
			card.set_meta("uz_default", true)
			card.set_meta("uz_entry", true)
			_shelf.show_item(card)
			break


## Rechts neben den Quellen, leise: wie das Regal sortiert ist (Bibliothek → Sortieren gilt
## auch hier; „Zuletzt“ ist immer nach dem letzten Spielen geordnet) und wie viele es sind.
## Kein „›“: Die Zeile selbst ist nicht wählbar – A auf der Quelle öffnet die Bibliothek, dort
## lässt sich die Sortierung ändern.
func _count_text(n: int) -> String:
	var how := "Zuletzt gespielt"
	if sub == Quellen.HIDDEN_GAMES:
		how = "A bis Z"
	elif sub != "zuletzt":
		var mode := str(Config.get_value("library.sort", "recent"))
		for s2 in SORT_NAMES:
			if s2[0] == mode:
				how = str(s2[1])
	if sub == "zuletzt":
		return "Sortierung · %s" % how
	return "%s · Sortierung · %s" % [U.plural(n, "Spiel", "Spiele"), how]


## Namen der Sortierungen (wie im Bibliotheks-Raster, library_grid.gd).
const SORT_NAMES := [["recent", "Zuletzt gespielt"], ["title", "A bis Z"], ["playtime", "Meiste Spielzeit"], ["added", "Neu hinzugefügt"]]


## Covergröße im Regal der Startseite (siehe SHELF_SCALE).
static func shelf_cover() -> Vector2:
	var c := UzTheme.cover_size() * SHELF_SCALE
	return c * (SHELF_MAX_H / c.y) if c.y > SHELF_MAX_H else c


## Sources with games from different platforms: there every cover carries its platform badge – except
## in „Zuletzt“ (the first row stays calm).
func _mixed_source() -> bool:
	return sub in ["favoriten", "alle", Quellen.HIDDEN_GAMES] or sub.begins_with("ordner:")


## Feine Linie unter der Quellenzeile (wie ein Register).
const _LINE := preload("res://src/ui/components/rule_line.gd")


## Kopf links (Marke): oben klein Plattform-Schild und Zustand, darunter der Titel groß in Plex
## Sans Condensed (zweizeilig erlaubt), eine leise Zeile mit den Angaben und die zwei Knöpfe.
const TITLE_PX := 88.0


func _build_hero() -> Control:
	# Halter ohne eigenes Layout: darin darf der Block beim Spielwechsel leicht gleiten.
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hero := U.vbox(0)
	U.full_rect(hero)
	hero.alignment = BoxContainer.ALIGNMENT_END
	hero.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.add_child(hero)
	hero.minimum_size_changed.connect(func() -> void:
		if is_instance_valid(holder) and is_instance_valid(hero):
			holder.custom_minimum_size = Vector2(0, hero.get_combined_minimum_size().y)
	)
	_hero_box = hero
	_meta = U.hbox(10)
	hero.add_child(_meta)
	hero.add_child(U.spacer(0, int(U.by_room(14.0, 8.0)), false))
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.custom_minimum_size = Vector2(minf(640.0, _hero_w), U.by_room(150.0, 96.0))
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.visible = false
	_logo.set_meta("uz_titel", true)
	hero.add_child(_logo)
	_title_l = U.shadow(U.label("", str(int(TITLE_PX)), "text", "title", not _compact), 0.45)
	# Großer Titel: weicht beim Bereichswechsel zuerst (U.titel_weichen), statt über dem neuen zu stehen.
	_title_l.set_meta("uz_titel", true)
	_title_l.max_lines_visible = 2
	_title_l.custom_minimum_size = Vector2(_hero_w, 0)
	if _compact:
		# Knappe Höhe: eine Zeile, lange Titel enden mit „…“.
		_title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_title_l.clip_text = true
	_title_l.add_theme_constant_override("line_spacing", -16)
	hero.add_child(_title_l)
	hero.add_child(U.spacer(0, int(U.by_room(10.0, 6.0)), false))
	var info := U.hbox(14)
	# Sehr knapp (um 150 %): die Zeile unter dem Titel tritt zurück.
	info.visible = U.tight() < 0.9
	hero.add_child(info)
	_tag = U.shadow(U.label("", "m", "muted", "regular"), 0.35)
	_tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_tag)
	_faces = U.hbox(8)
	_faces.visible = false
	info.add_child(_faces)
	return holder


## Die leise Zeile unter dem Titel. Passt sie nicht, fallen hintere Angaben ganz weg (statt
## mitten im Wort abzubrechen); nur eine einzelne zu lange Angabe endet mit „…“.
## people: Freunde, die das Spiel gerade spielen (Gesichter dahinter, ohne Namen im Text).
func _set_info(parts: Array, people: Array = []) -> void:
	var out := PackedStringArray()
	for t in parts:
		if str(t) != "":
			out.append(str(t))
	U.clear(_faces)
	_faces.visible = not people.is_empty()
	var room := minf(900.0, _hero_w)
	if not people.is_empty():
		var avs := U.hbox(-8)
		for f in people.slice(0, 5):
			var av := Avatar.new()
			av.setup(str(f.get("name", "")), str(f.get("avatar", "")), "", 30)
			avs.add_child(av)
		_faces.add_child(avs)
		var l := U.shadow(U.label("spielt gerade" if people.size() == 1 else "spielen gerade", "m", "muted", "regular"), 0.35)
		l.clip_text = false
		_faces.add_child(l)
		room -= _faces.get_combined_minimum_size().x + 14.0
	var fnt := _tag.get_theme_font("font")
	var fs := _tag.get_theme_font_size("font_size")
	_tag.text = " · ".join(out)
	var w := fnt.get_string_size(tr(_tag.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0
	while w > room and out.size() > 1:
		out.remove_at(out.size() - 1)
		_tag.text = " · ".join(out)
		w = fnt.get_string_size(tr(_tag.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0
	_tag.clip_text = w > room
	_tag.custom_minimum_size = Vector2(minf(w, maxf(room, 120.0)), 0)
	_tag.visible = _tag.text != ""


## Am Ende des Regals: alle Spiele dieser Quelle als Raster – gebaut wie ein Ordner, mit einem
## kleinen Fächer der ersten Cover.
func _all_card(list: Array) -> Control:
	var t = FolderTile.new()
	t.setup({ "id": "_alle:" + sub, "name": "Alle anzeigen", "_games": list.slice(0, 3),
		"_sub": U.plural(list.size(), "Spiel", "Spiele"), "_icon": "grid" })
	t.grow_left = true
	t.set_meta("uz_hint_a", "Bibliothek öffnen")
	t.chosen.connect(func(_f: Dictionary) -> void: main.open_library(sub, _source_name()))
	t.focus_entered.connect(func() -> void: _show_all(list))
	return t


## Im Steam-Reiter: Kachel „Alle Steam-Spiele“, solange nur installierte zu sehen sind.
static func steam_owned_offer(sub_id: String) -> bool:
	return sub_id == "steam" and bool(Config.get_value("library.steam_enabled", true)) and not bool(Config.get_value("library.steam_owned", false))


func _steam_owned_card() -> Control:
	var t = FolderTile.new()
	t.setup({ "id": "_steam_alle", "name": "Alle Steam-Spiele", "_games": [], "_sub": "auch nicht installierte", "_icon": "steam" })
	t.grow_left = true
	t.set_meta("uz_hint_a", "Einschalten")
	t.chosen.connect(func(_f: Dictionary) -> void: _enable_steam_owned())
	t.focus_entered.connect(_show_steam_owned)
	return t


func _show_steam_owned() -> void:
	if _title_l == null:
		return
	_selected = {}
	_hero_change("f:_steam_alle")
	_fit_title("Alle Steam-Spiele")
	_set_meta_row(["Auch nicht installierte"], "Steam")
	_set_info(["Auch nicht installierte Spiele." if Social.has_steam() \
		else "Steam-Anmeldung nötig."])


## Einschalten (Library holt die Liste gleich und meldet sich). Ohne Steam-Anmeldung erst dahin.
func _enable_steam_owned() -> void:
	if Social.has_steam():
		Config.set_value("library.steam_owned", true)
		return
	main.open_dialog("Alle Steam-Spiele zeigen", "Code mit der Steam-App scannen.", [
		["Mit Steam anmelden", func() -> void:
			# Eingeschaltet wird erst nach der Anmeldung (sonst käme gleich „nicht geladen“).
			SteamChat.changed.connect(func() -> void:
				if SteamChat.logged_in():
					Config.set_value("library.steam_owned", true)
			, CONNECT_ONE_SHOT)
			main.open_chat({ "id": "", "name": "Steam" }, true)],
		["Später", func() -> void: pass],
	], "steam")


## Am Ende von „Zuletzt“: Dein Zimmer (Punkt 131) – dieselbe Startseite als begehbares 3D-Zimmer.
func _room_card() -> Control:
	var t = FolderTile.new()
	t.setup({ "id": "_zimmer", "name": "Dein Zimmer", "_games": [], "_sub": "in 3D betreten", "_icon": "home" })
	t.grow_left = true
	t.set_meta("uz_hint_a", "Betreten")
	t.chosen.connect(func(_f: Dictionary) -> void: main.open_room())
	t.focus_entered.connect(func() -> void:
		if _title_l == null:
			return
		_selected = {}
		_hero_change("f:_zimmer")
		_fit_title("Dein Zimmer")
		_set_meta_row(["Spiele, Pokale, Platten"], "3D")
		_set_info(["Spiele im 3D-Zimmer."]))
	return t


## Am Ende von PC und Alle: eigenes Spiel ohne Launcher hinzufügen (Punkt 117).
func _add_card() -> Control:
	var t = FolderTile.new()
	t.setup({ "id": "_neu", "name": "Hinzufügen", "_games": [], "_sub": "Spiel ohne Launcher", "_icon": "plus" })
	t.grow_left = true
	t.set_meta("uz_hint_a", "Hinzufügen")
	t.chosen.connect(func(_f: Dictionary) -> void: main.open_add_game())
	t.focus_entered.connect(_show_add)
	return t


func _show_add() -> void:
	if _title_l == null:
		return
	_selected = {}
	_hero_change("f:_neu")
	_fit_title("Spiel hinzufügen")
	_set_meta_row(["Ohne Launcher"], "PC")
	_set_info(["Eine .exe oder einen Ordner wählen."])


func _sub_label() -> String:
	for t in subtabs():
		if t.id == sub:
			return str(t.label)
	return "Spiele"


# --- Das gewählte Spiel ------------------------------------------------------------------

## Meta line above the title: with a disc inserted, a badge in the accent color, then the state in a quiet
## tone („Noch nicht gespielt“, „nicht installiert“ …). No platform badge anymore („PS2“, „Steam“): the
## source row already shows where you are. pill_text stays for callers.
func _set_meta_row(parts: Array, _pill_text: String, disc := false) -> void:
	U.clear(_meta)
	if disc:
		# Die Disc liegt im Laufwerk: Zeichen und Wort im Akzent (das eine farbige Element).
		var dr := U.hbox(7)
		dr.add_child(U.icon("disc", 18, "accent_ink"))
		dr.add_child(U.label("Disc eingelegt", "s", "accent_ink", "ui_bold"))
		_meta.add_child(_schild(dr))
	var n := 0
	for t in parts:
		if str(t) == "":
			continue
		if n > 0:
			_meta.add_child(_Dot.new())
		n += 1
		var l2 := U.shadow(U.label(str(t), "s", "muted", "medium"), 0.35)
		l2.clip_text = false
		_meta.add_child(l2)
	_meta.visible = _meta.get_child_count() > 0


func _schild(inner: Control) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("glass_hi", 0.92), 8, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l in [inner] + inner.get_children():
		if l is Label:
			(l as Label).clip_text = false
	p.add_child(inner)
	return p


## Eine Angabe für die Zeile unter dem Titel („Bild: CRT, 480 Zeilen“). Ein „ · “ im Wert wird
## zum Komma, sonst läse es sich wie zwei Angaben.
static func _stat(key: String, value: String) -> String:
	return (key + ": %s") % value.replace(" · ", ", ")


func _show_folder(f: Dictionary) -> void:
	if _title_l == null:
		return
	_selected = {}
	_hero_change("f:" + str(f.get("id", "")))
	var games: Array = Library.in_folder(str(f.get("id", "")))
	var sysname := str(Config.system(str(f.get("system", ""))).get("name", "Alle Systeme")) if str(f.get("system", "")) != "" else "Alle Systeme"
	_fit_title(str(f.get("name", "")), true)
	var total := 0
	for g in games:
		total += Library.playtime(g)
	_set_meta_row([sysname, U.plural(games.size(), "Spiel", "Spiele")], "Ordner")
	# Statt die Anzahl zu wiederholen: was drinliegt, dann wie lange gespielt und woher.
	var names := PackedStringArray()
	for g in games.slice(0, 3):
		names.append(Library.display_title(g))
	_set_info([", ".join(names) + (" …" if games.size() > 3 else "") if not names.is_empty() else "Leer",
		_stat("Gespielt", PlaytimePage.dur(total) if total > 0 else "noch nicht"),
		"Unterordner" if f.get("auto", false) else "eigener Ordner"])
	if not games.is_empty():
		_set_bg(games[0])


func _on_game_focused(g: Dictionary) -> void:
	_last_by_sub[sub] = str(g.get("id", ""))
	_show(g)


## Room color and glow for the selected entry; stored so that a layer on top (the library tints the
## room for its game) can restore it on close.
## The game's background image stays clearly visible behind it, darkened by the room's gradient; it is
## blurred only when „Hintergrund weichzeichnen“ is on under Darstellung → Raum (and the theme is matte).
## It stays still (no zoom, no drift).
var _bg_game: Dictionary = {}


static func soft_bg() -> bool:
	return UzTheme.matt() and bool(Config.get_value("theme.bg_soft", false))


func _set_bg(g: Dictionary) -> void:
	_bg_game = g
	if main and main.background:
		main.background.show_game(g, soft_bg(), true)


## Bilder der Nachbarn im Regal vorab laden: zwei in Blätterrichtung, einer zurück. Ein
## Wechsel dorthin zeigt das Bild dann sofort, ohne Warten und ohne Hochladen im selben Bild.
func _prefetch_around() -> void:
	if _shelf == null or _hero_idx < 0 or not (main and main.background and main.background.has_method("prefetch")):
		return
	var list: Array = _shelf.items()
	var out: Array = []
	for off in [_hero_dir, _hero_dir * 2, -_hero_dir]:
		var j: int = _hero_idx + off
		if j >= 0 and j < list.size():
			var gm: Variant = (list[j] as Control).get("game")
			if gm is Dictionary and not (gm as Dictionary).is_empty():
				out.append(gm)
	main.background.prefetch(out, soft_bg())
	for gm in out:
		if not _logos.has(str((gm as Dictionary).get("id", ""))):
			_lade_logo(gm, func(_t: Texture2D) -> void: pass)


## Logos der zuletzt gewählten Spiele (Spiel-ID -> Textur), unabhängig vom großen Bildspeicher in
## Media: ein Raster mit hunderten Covern verdrängt sie dort, und beim Zurückblättern lüden sie neu.
const LOGOS_MAX := 48
var _logos := {}


## Logo laden und merken; cb(Texture2D oder null).
func _lade_logo(g: Dictionary, cb: Callable) -> void:
	var gid := str(g.get("id", ""))
	Media.game_texture(g, "logo", func(t: Texture2D) -> void:
		if t and gid != "":
			_logos.erase(gid)
			_logos[gid] = t
			while _logos.size() > LOGOS_MAX:
				_logos.erase(_logos.keys()[0])
		cb.call(t)
	)


func _zeige_logo(t: Texture2D) -> void:
	_logo.texture = t
	_logo.visible = true
	_title_l.visible = false


## Ruht die Auswahl kurz, das große Bild der Spielseite vorab laden: A öffnet die Seite dann
## mit Bild, statt es erst zu laden. Nicht beim Blättern (nur das zuletzt gewählte Spiel).
func _prefetch_page(g: Dictionary, gid: String) -> void:
	if not (main and main.game_page_on()):
		return
	await get_tree().create_timer(0.7).timeout
	if str(_selected.get("id", "")) != gid or not is_visible_in_tree():
		return
	var hp := Media.local_path(g, "hero")
	if hp != "":
		Media.fit_texture(hp, BG.page_hero_area(get_viewport_rect().size), func(_t: Texture2D) -> void: pass)


func restore_background() -> void:
	if not _bg_game.is_empty() and main and main.background and main.current == id:
		main.background.show_game(_bg_game, soft_bg(), true)


## Stelle eines Elements im Regal (über seinen Schlüssel "g:<id>" bzw. "f:<id>"), sonst -1.
func _shelf_index(key: String) -> int:
	if _shelf == null:
		return -1
	var list: Array = _shelf.items()
	for i in list.size():
		if str((list[i] as Control).get_meta("uz_key", "")) == key:
			return i
	return -1


## Beim Wechsel überblendet der Kopf: Titel, Logo und Angaben des alten Spiels bleiben als stilles
## Abbild liegen und gehen in T_ANTWORT; der neue Kopf kommt nach einem Drittel davon in T_ORT und
## gleitet W_ORT aus der Richtung, in die man im Regal geht (erst gehen, dann kommen – nie leer,
## kaum doppelt). Beim schnellen Blättern (Halten) nur ein kurzes Aufhellen, damit nichts flimmert.
func _hero_change(key: String) -> void:
	if key == _hero_id:
		return
	_hero_id = key
	var idx := _shelf_index(key)
	var dir := 0
	if _hero_idx >= 0 and idx >= 0 and idx != _hero_idx:
		dir = 1 if idx > _hero_idx else -1
		_hero_dir = dir
	_hero_idx = idx
	if _hero_tw:
		_hero_tw.kill()
	# Schnell geblättert oder gehalten: der Kopf hellt nur kurz auf, statt bei jedem Schritt zu blenden.
	var quick := Time.get_ticks_msec() - _hero_ms < 180 or Nav.halten_takt() > 0.0
	_hero_ms = Time.get_ticks_msec()
	var teile: Array = [_meta, _title_l, _logo, _tag.get_parent()]
	_geist_weg()
	if not quick:
		_hero_geist = _abbild(teile)
	_hero_tw = U.ankommen(self, U.T_ORT, "uz_hero").set_parallel(true)
	for n in teile:
		var c := n as Control
		c.modulate.a = minf(c.modulate.a, 0.55) if quick else 0.0
		_hero_tw.tween_property(c, "modulate:a", 1.0, U.T_ANTWORT if quick else U.T_ORT).set_delay(0.0 if quick else U.T_ANTWORT / 3.0)
	if dir != 0 and not quick and is_instance_valid(_hero_box):
		U.slide_x(_hero_box, U.weg_px(U.W_ORT) * dir, U.T_ORT)


## Stilles Abbild der sichtbaren Teile des Kopfs (ohne Skripte), an ihrer Lage hinter dem Kopf;
## es blendet in T_ANTWORT aus und gibt sich frei.
func _abbild(teile: Array) -> Control:
	var holder := _hero_box.get_parent() as Control if is_instance_valid(_hero_box) else null
	if holder == null or not holder.is_visible_in_tree():
		return null
	var g := Control.new()
	g.name = "KopfAlt"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_meta("uz_skip", true)
	holder.add_child(g)
	holder.move_child(g, 0)
	var n_teile := 0
	for n in teile:
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or c.modulate.a < 0.05 or c.size.x < 1.0:
			continue
		var d := c.duplicate(0) as Control
		g.add_child(d)
		d.position = c.global_position - holder.global_position
		d.size = c.size
		d.modulate = c.modulate
		n_teile += 1
	if n_teile == 0:
		g.queue_free()
		return null
	var tw := U.weg(g, "uz_geist")
	tw.tween_property(g, "modulate:a", 0.0, U.T_ANTWORT)
	tw.tween_callback(g.queue_free)
	return g


func _geist_weg() -> void:
	if is_instance_valid(_hero_geist):
		_hero_geist.queue_free()
	_hero_geist = null


## Titel setzen; lange Titel etwas kleiner, damit sie in eine Zeile passen und die Quellen
## nicht bedrängen. Das Logo weicht, bis ein neues geladen ist. fremd: der Name eines Spiels oder Ordners –
## er wird nicht übersetzt (der Katalog kennt ihn nicht, träfe ihn mit einem Muster aber zufällig).
func _fit_title(text: String, fremd := false) -> void:
	_title_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if fremd else Node.AUTO_TRANSLATE_MODE_INHERIT
	_title_l.text = text
	var fs := int(U.by_room(80.0, 60.0))
	var fnt := UzTheme.display("title")
	var gezeigt := text if fremd else tr(text)
	while fs > 56 and fnt.get_string_size(gezeigt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > _hero_w + 20.0:
		fs -= 4
	_title_l.add_theme_font_size_override("font_size", fs)
	_title_l.visible = true
	_logo.visible = false


## A auf einer Quelle (Zuletzt, Steam, PS2 …): alle Spiele daraus als Raster – die ganze
## Steam-Bibliothek ohne Blättern bis ans Ende des Regals. Konsolen öffnen immer ihr Regal mit echten
## Hüllen (src/ui/layers/regal_seite.gd), Ordner ihr Mosaik (selbst gestaltbar, src/ui/layers/mosaik_seite.gd).
func open_source(sub_id: String) -> bool:
	if sub_id == "":
		return false
	if sub != sub_id:
		main._open_sub(self, sub_id, false)
	if Regal.ist_regal(sub_id):
		open_regal(sub_id, _source_name())
	elif MosaikSeite.ist_mosaik(sub_id):
		open_mosaik(sub_id, _source_name())
	else:
		main.open_library(sub_id, _source_name())
	return true


func open_mosaik(sub_id: String, label: String) -> void:
	var l = MosaikSeite.new()
	l.quelle = sub_id
	l.label = label
	main.open_layer(l)


func open_regal(sub_id: String, label: String) -> void:
	var l = RegalSeite.new()
	l.quelle = sub_id
	l.label = label
	main.open_layer(l)


## Name der gewählten Quelle, ausgeschrieben (für „Alle anzeigen“).
func _source_name() -> String:
	match sub:
		"zuletzt": return "Zuletzt gespielt"
		"favoriten": return "Favoriten"
		"alle": return "Alle Spiele"
		"steam": return "Steam"
		"epic": return "Epic Games"
		"ea": return "EA app"
		"pc": return "PC-Spiele"
	if Library.Stores.is_extra(sub):
		return Library.Stores.name_of(sub)
	if sub.begins_with("ordner:"):
		return str(Library.folder(sub.substr(7)).get("name", "Ordner"))
	return str(Config.system(sub).get("name", _sub_label()))


## „Alle anzeigen“ gewählt: oben steht die Quelle selbst – wie viele Spiele, wie lange
## gespielt, was zuletzt lief.
func _show_all(list: Array) -> void:
	if _title_l == null:
		return
	_selected = {}
	_hero_change("f:_alle:" + sub)
	_fit_title(_source_name())
	var total := 0
	var newest := 0
	var newest_title := ""
	for g in list:
		total += Library.playtime(g)
		var lp := Library.last_played(g)
		if lp > newest:
			newest = lp
			newest_title = Library.display_title(g)
	_set_meta_row([U.plural(list.size(), "Spiel", "Spiele")], "Bibliothek")
	_set_info(["Alle als Raster, sortiert und durchsuchbar", _stat("Gespielt", PlaytimePage.dur(total) if total > 0 else "noch nicht"),
		_stat("Zuletzt", newest_title) if newest_title != "" else ""])
	if not list.is_empty():
		_set_bg(list[0])


func _show(g: Dictionary) -> void:
	if g.is_empty() or _title_l == null:
		return
	_selected = g
	_hero_change("g:" + str(g.get("id", "")))
	var sys := Config.system(str(g.get("system", "")))
	var pill := ""
	match str(g.get("source", "")):
		"steam": pill = "Steam"
		"epic": pill = "Epic"
		"ea": pill = "EA"
		"pc": pill = "PC"
		_: pill = Library.store_name(g, true, str(sys.get("short", sys.get("name", ""))))
	if str(g.get("source", "")) == "disc":
		_show_disc(g, pill)
		return
	# Oben nur der Zustand. Spielzeit und wann zuletzt stehen auf der Spielseite, nicht hier.
	var parts: Array = []
	if not Library.is_installed(g):
		parts.append("nicht installiert")
	# Stelle gemerkt (src/core/quick_resume.gd): „gemerkt vor 2 Std.“
	var paused_txt: String = load("res://src/core/quick_resume.gd").label_for(g)
	if paused_txt != "":
		parts.append(paused_txt)
	_set_meta_row(parts, pill, Discs.is_disc_game(g))
	_fit_title(Library.display_title(g), true)
	# Das echte Logo des Spiels statt Text, sobald es eins gibt (Steam, SteamGridDB, eigenes).
	# Schon gezeigte Logos kommen sofort aus _logos; liegt eins auf der Platte, bleibt der Titel
	# bis zum Laden weg (sonst blitzt bei jedem Wechsel erst der Text auf).
	var gid := str(g.get("id", ""))
	var schon: Texture2D = _logos.get(gid)
	if schon:
		_zeige_logo(schon)
	else:
		if Media.local_path(g, "logo") != "":
			_title_l.visible = false
		_lade_logo(g, func(t: Texture2D) -> void:
			if not is_instance_valid(_logo) or str(_selected.get("id", "")) != gid:
				return
			if t:
				_zeige_logo(t)
			else:
				_title_l.visible = true
		)
	_fill_info(g)
	if g.get("source") == "steam" and int(g.get("appid", 0)) > 0 and Store.cached(int(g.appid)).is_empty():
		_load_tag(g, gid)
	_set_bg(g)
	_prefetch_around()
	_prefetch_page(g, gid)
	var have := Achievements.cached(g)
	if have.is_empty() and ((g.get("source") == "steam" and Achievements.has_steam()) or (g.get("source") == "rom" and Achievements.has_ra())):
		_load_ach(g, gid)


## Kopf für eine eingelegte Disc ohne Abbild: Name, Seriennummer, was A tut.
func _show_disc(g: Dictionary, pill: String) -> void:
	_set_meta_row(["spielt vom Laufwerk" if Discs.can_play() else "noch kein Abbild"], pill, true)
	_fit_title(str(g.get("title", "")), true)
	_logo.visible = false
	_title_l.visible = true
	var sys := Config.system(str(g.get("system", "")))
	# Was A und Y tun, sagen die Knöpfe darunter („Von Disc spielen“, „Abbild zuordnen“).
	_set_info([str(sys.get("name", "")), str(g.get("serial", ""))])
	_set_bg(g)


## Die ruhige Zeile unter dem Titel: Genre und Studio (Steam) bzw. System, Emulator und Bild
## („PlayStation 2 · PCSX2 · Bild: CRT, 480 Zeilen“), dann Erfolge und Ordner; dahinter die
## Gesichter der Steam-Freunde, die es gerade spielen.
func _info_parts(g: Dictionary) -> Array:
	var parts: Array = []
	if g.get("source") == "steam" and int(g.get("appid", 0)) > 0:
		var d := Store.cached(int(g.appid))
		var gen: PackedStringArray = d.get("genres", PackedStringArray())
		if not gen.is_empty():
			parts.append(" · ".join(gen.slice(0, 2)))
		if str(d.get("developer", "")) != "":
			parts.append(str(d.developer))
	elif g.get("source") == "rom":
		# Der volle Systemname erklärt das Kürzel im Schild darüber („PS2“).
		var sys := Config.system(str(g.get("system", "")))
		parts.append(str(sys.get("name", "")))
		var emu := Config.emulator(str(g.get("emulator", sys.get("emulator", ""))))
		parts.append(str(emu.get("name", "")))
		var flt := Config.filter(Launcher.active_filter_id(g))
		if not flt.is_empty():
			# Erst übersetzen, dann umformen (_stat): „CRT, 480 Zeilen“ steht in keinem Katalog, „CRT · 480 Zeilen“ schon.
			parts.append(_stat("Bild", tr(str(flt.get("name", "")))))
	var res := Achievements.cached(g)
	if not res.is_empty() and int(res.get("total", 0)) > 0:
		parts.append(_stat("Erfolge", "%d / %d" % [int(res.unlocked), int(res.total)]))
	var folders: Array = Library.folders_for_game(g).filter(func(f): return Library.is_in_folder(g, str(f.id)))
	if not folders.is_empty():
		parts.append(_stat("Ordner", str(folders[0].get("name", ""))))
	if parts.is_empty() and Library.playtime(g) <= 0 and int(g.get("added", 0)) > 0:
		# Sonst leer: seit wann es da ist.
		parts.append(_stat("Hinzugefügt", U.date(int(g.get("added", 0)))))
	return parts


func _fill_info(g: Dictionary) -> void:
	var people: Array = Social.playing(int(g.get("appid", 0))) if g.get("source") == "steam" else []
	_set_info(_info_parts(g), people)


func _load_tag(g: Dictionary, gid: String) -> void:
	# Kurz warten: beim schnellen Blättern nicht für jedes Cover den Store fragen.
	await get_tree().create_timer(0.6).timeout
	if str(_selected.get("id", "")) != gid or not is_instance_valid(_tag):
		return
	await Store.details(int(g.appid))
	if str(_selected.get("id", "")) == gid and is_instance_valid(_tag):
		_fill_info(g)


func _load_ach(g: Dictionary, gid: String) -> void:
	await Achievements.for_game(g)
	if str(_selected.get("id", "")) == gid and is_instance_valid(_tag):
		_fill_info(g)


# --- Für dich ------------------------------------------------------------------------------
# Hinter der Start-Taste (menu_taste) als Seitenleiste von rechts (fuer_dich_leiste.gd): oben groß
# der „Weiter“-Moment, darunter Abschnitte in der Listen-Sprache (ForYou.ordnen). Die große Karte
# mischt for_you.gd gewichtet aus allem, was es gerade gibt (Weiterspielen, Freunde, Sprachkanal,
# Wiederentdecken, Neu, Neuigkeiten, Erfolge, Woche, Filme/Musik). Die Startseite mischt vorab,
# solange sie zu sehen ist (Daten, Neuigkeiten, Bilder), damit die Leiste sofort gefüllt aufgeht.
# Neu gemischt wird beim Betreten der Startseite, nach einem Spiel und nach 20 Minuten; dazwischen
# bleiben die Karten stehen, und solange die Leiste offen ist, ändert sich nichts unter dem Cursor.

const ForYou := preload("res://src/ui/components/for_you.gd")
const ForYouCard := preload("res://src/ui/components/for_you_card.gd")
const HERO_W := 980.0            ## Breite des Spieltitels oben links (wie gebaut)
const FY_SLOTS := 4              ## so viele Karten in der Leiste (eine große, drei darunter)
var _hero_w := HERO_W
var _compact := false            ## knappe Höhe: Titel einzeilig, ohne Kennzahlen

var _fy_seed := 0
var _fy_keep: Array = []         ## Schlüssel der gemischten Karten (Platz 0 = große Karte)
var _fy_sigs: Array = []         ## Inhalt je Platz (card_sig): Bilder nur für Neues vorladen
var _fy_plan: Dictionary = {}    ## die gemischten Karten (ForYou.pick) für die Leiste
var _fy_cands: Array = []        ## alle Kandidaten dazu (ForYou.gather): die Abschnitte der Leiste
var _fy_mixed_ms := -100000000
var _fy_reshuffle := true
var _fy_queued := false
var _fy_music := ""


func on_leave() -> void:
	_fy_reshuffle = true


## Start (Menü) auf der Startseite: „Für dich“ als Seitenleiste (main.gd, Zweig „menu“). Y bleibt
## „Optionen“ des Spiels. Ohne Spiele (leere Bühne) nicht – dann gilt die Taste wie überall.
func menu_taste() -> bool:
	if Library.visible_games().is_empty() or main == null:
		return false
	open_fuer_dich()
	return true


## Unten in der Tastenzeile: Start öffnet „Für dich“.
func extra_hints(_f: Control) -> Array:
	return [] if Library.visible_games().is_empty() else [["menu", "Für dich"]]


## Die Leiste mit den gerade gemischten Karten öffnen (vorher noch einmal frisch nachrechnen).
func open_fuer_dich() -> Control:
	_refresh_foryou()
	var l = FuerDichLeiste.new()
	l.plan = _fy_plan
	l.cands = _fy_cands
	l.main = main
	l.closed.connect(_queue_foryou)
	return main.open_layer(l)


static func _fy_leiste_offen() -> bool:
	for l in Nav.layers:
		if is_instance_valid(l) and l is FuerDichLeiste:
			return true
	return false


## Viele Meldungen kurz hintereinander (Freunde, Sprachkanal, Filme) nur einmal umsetzen.
func _queue_foryou() -> void:
	if _fy_queued or not is_inside_tree():
		return
	_fy_queued = true
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		_fy_queued = false
		_refresh_foryou()
	)


## Musik meldet sich jede Sekunde (Fortschritt): nur ein anderer Titel oder Pause zählt.
func _on_music() -> void:
	var m: Dictionary = Music.now
	var k := "%s|%s" % [m.get("title", ""), m.get("playing", false)]
	if k != _fy_music:
		_fy_music = k
		_queue_foryou()


## Erfolge: Lädt die Startseite oben die Erfolge des gewählten Spiels, betrifft das „Für dich“
## meist nicht (sonst rechnete jeder Schritt im Regal „Für dich“ neu).
func _on_ach(what: String) -> void:
	if what.begins_with("game:") and not ForYou.ach_ids.has(what.substr(5)):
		return
	_queue_foryou()


## Karten mischen bzw. nachrechnen (_fy_plan) und ihre Bilder vorab holen.
func _refresh_foryou() -> void:
	if not is_inside_tree() or Library.visible_games().is_empty():
		return
	# Versteckt (anderer Bereich) oder im Spiel: nur vormerken, beim nächsten Zeigen nachrechnen.
	if not is_visible_in_tree() or Launcher.in_game:
		_foryou_due = true
		return
	var vis := Library.visible_games()
	ForYou.load_news(vis, _on_news)
	_live_sources(vis)
	# Leiste offen: nichts unter dem Cursor ändern – nach dem Schließen nachholen.
	if _fy_leiste_offen():
		_foryou_due = true
		return
	_foryou_due = false
	var now := Time.get_ticks_msec()
	if _fy_reshuffle or now - _fy_mixed_ms > ForYou.SHUFFLE_MS:
		_fy_reshuffle = false
		_fy_seed = randi()
		_fy_keep = []
		_fy_mixed_ms = now
	# Kurz nach dem Mischen darf noch Nachkommendes mitmischen (Freunde, Erfolge laden erst).
	var keep := _fy_keep if now - _fy_mixed_ms > ForYou.SETTLE_MS else []
	_fy_cands = ForYou.gather(main, _fy_seed)
	var plan := ForYou.pick(_fy_cands, _fy_seed, keep, FY_SLOTS)
	_fy_keep = ForYou.keys_of(plan)
	_fy_plan = plan
	var cards: Array = [plan.big] + plan.small
	var sigs: Array = cards.map(func(c: Dictionary) -> String: return ForYou.card_sig(c))
	if sigs == _fy_sigs:
		return
	for i in cards.size():
		var c: Dictionary = cards[i]
		if not c.is_empty() and (i >= _fy_sigs.size() or str(_fy_sigs[i]) != str(sigs[i])):
			ForYouCard.vorladen(c, i == 0)
	_fy_sigs = sigs


# --- Lebendige Kacheln --------------------------------------------------------------------------
# Die Cover im Regal zeigen, was an ihrem Spiel los ist (kachel_zustand.gd, kacheln.gd). Die
# meisten Quellen melden sich selbst; was nur sparsam geholt wird (Statusseite, anstehende
# Updates aus Steams appmanifests, Neuigkeiten), stößt die Startseite an, solange sie zu sehen ist.

var _live_upd_sig := ""
var _live_upd_busy := false


func _on_news() -> void:
	_queue_foryou()
	_poke_live()


func _live_sources(vis: Array) -> void:
	if not Kacheln.on():
		return
	Kacheln.load_status(vis, _poke_live)
	if not _live_upd_busy:
		_live_updates()


## Anstehende Updates: Installs liest sie höchstens einmal je Minute; erst kurz nach dem Aufbau,
## damit das Lesen der Dateien nie das Öffnen der Startseite bremst.
func _live_updates() -> void:
	_live_upd_busy = true
	await get_tree().create_timer(1.0).timeout
	_live_upd_busy = false
	if not is_visible_in_tree() or Launcher.in_game:
		return
	# Die Dateien liest der Hilfsfaden; hier nur noch der fertige Stand.
	await Installs.updates_auffrischen()
	if not is_visible_in_tree():
		return
	var sig := ",".join(Installs.pending_updates().map(func(u: Dictionary) -> String: return "%s:%s" % [u.id, u.u.get("phase", "")]))
	Kacheln.flush()
	if sig != _live_upd_sig:
		_live_upd_sig = sig
		_poke_live()


## Alle Kacheln im Regal fragen nach ihrem Zustand.
func _poke_live() -> void:
	if not is_instance_valid(_shelf):
		return
	for c in _shelf.items():
		if c.has_method("refresh_live"):
			c.refresh_live()


func _on_foryou_visible() -> void:
	if _foryou_due and is_visible_in_tree():
		_queue_foryou()


## Kleiner Punkt zwischen den Angaben der Meta-Zeile.
class _Dot extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(4, 4)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, 2.0, UzTheme.col("faint"))


func _toggle_fav(g: Dictionary) -> void:
	var keep := str(g.id)
	var snap := Library.snapshot([keep])
	var on := Library.toggle_favorite(keep)
	# Unter „Favoriten“ verschwindet das Spiel dabei: kurz zurücknehmbar.
	if on:
		Toasts.show_toast("Favorit", Library.display_title(g), "heart_f", { "sub_raw": true, "sound": "select" })
	else:
		var was := sub
		# Zurück: main baut den Bereich bei Library.changed selbst neu und stellt einen Frame später
		# den alten Fokus her; danach steht er wieder auf dem Spiel – nur, wenn man noch hier ist.
		Undo.offer_games("Kein Favorit mehr", Library.display_title(g), "heart", snap, func() -> void:
			_last_by_sub[was] = keep
			await get_tree().process_frame
			await get_tree().process_frame
			if sub == was and is_visible_in_tree() and Nav.top_layer() == null:
				_focus_game(keep)
		)
	_last_by_sub[sub] = keep
	build()
	if main:
		main.refresh_chips()
	_focus_game(keep)


func _focus_game(gid: String) -> void:
	if _shelf == null:
		return
	for card in _shelf.items():
		if card.get("game") is Dictionary and str(card.game.get("id", "")) == gid:
			Nav.focus(card, true)
			return


## Noch keine Spiele: die Bühne mit angedeuteten Covern; A sucht gleich (Steam, Epic, EA und die
## Spieleordner). Fand die Suche nichts, führt A zu den Spieleordnern. Kommen Spiele, baut main den
## Bereich neu (Library.changed) und das Regal kommt im Takt herein.
func _build_empty() -> void:
	var gesucht := not Library.last_scan.is_empty()
	var suchen := LeerBuehne.weg(main, "spiele")
	var ordner := func() -> void: main.goto("settings", "emulation")
	add_child(leer_buehne({ "art": "cover", "symbol": "games",
		"titel": "Keine Spiele gefunden." if gesucht else "Deine Spiele erscheinen hier.",
		"zeile": "Emulator-Spiele: ein Ordner je System." if gesucht else "",
		"knopf": "Ordner wählen" if gesucht else "Spiele suchen", "tun": ordner if gesucht else suchen,
		"neben": "Noch einmal suchen" if gesucht else "Spiel hinzufügen",
		"neben_tun": suchen if gesucht else func() -> void: main.open_add_game(),
		"fertig": func() -> bool: return not Library.visible_games().is_empty(),
		"laeuft": func() -> bool: return Library.scanning,
		"laeuft_titel": "Spiele werden gesucht …", "laeuft_knopf": "Sucht …" }))


func focus_default() -> void:
	if _shelf:
		for card in _shelf.items():
			if card.has_meta("uz_default"):
				Nav.focus(card, true)
				return
	super()
