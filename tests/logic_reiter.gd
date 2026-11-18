extends Node
## Leiste oben: alte Einstellungen werden umgestellt (die Schlüssel bleiben; die Leiste selbst mit
## App-Symbolen und Freunden auf Select prüft tests/logic_leiste.gd), „Aufnahmen“
## ist keine Quelle der Spiele mehr (Galerie über den Guide), Regal der Startseite ruhig, Quellen
## ordnen und ausblenden (langes A). Bedienung: tests/probe_reiter.gd, tests/probe_quellen.gd.
## Aufruf: godot --headless --path . res://tests/logic_reiter.tscn

const Games := preload("res://src/ui/sections/games.gd")
const FriendsView := preload("res://src/ui/sections/friends_view.gd")
const RoomView := preload("res://src/ui/sections/room_view.gd")
const LeisteOben := preload("res://src/core/leiste_oben.gd")
const CoverRow := preload("res://src/ui/components/cover_row.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const FolderTile := preload("res://src/ui/components/folder_tile.gd")
const Quellen := preload("res://src/ui/sections/quellen_ordnung.gd")
const CapL := preload("res://src/core/capture_logic.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	var keep: Dictionary = Config.settings.duplicate(true)
	_config()
	await _games()
	_ruhig()
	_quellen()
	await _langes_a()
	Config.settings = keep
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _config() -> void:
	print("Einstellungen")
	var want := ["games", "shop", "friends", "achievements", "apps", "settings"]
	check(Config.DEFAULTS.theme.sections == want and not Config.DEFAULTS.theme.has("group_media"),
			"theme.sections wie bisher (Freunde und Apps werden in main.gd verteilt) – kein „Medien zusammenfassen“ mehr")
	var sp := Config.path("settings.json")
	# Bisheriger Stand (Medien zusammengefasst), eigene Reihenfolge und ausgeblendete Bereiche.
	var mine := ["games", "friends", "music", "videos", "movies", "streams", "shop", "achievements", "settings"]
	Config.write_json(sp, { "uzai_version": Config.VERSION, "schema": Config.SETTINGS_VERSION,
		"theme": { "rev": 9, "group_media": true, "sections": mine, "hidden_sections": ["streams", "shop"], "tabs": "symbole" } })
	Config.load_settings()
	check(Config.get_value("theme.sections", []) == want, "alter Stand: die neue Leiste")
	check(not (Config.settings.theme as Dictionary).has("group_media"), "„Medien zusammenfassen“ fällt still weg")
	check(Config.get_value("theme.hidden_sections", []) == ["shop"] and Config.get_value("apps.hidden", []) == ["streams"],
			"ausgeblendet bleibt ausgeblendet (Streams jetzt unter Apps)")
	check(str(Config.get_value("theme.tabs", "")) == "symbole" and int(Config.get_value("theme.rev", 0)) == int(Config.DEFAULTS.theme.rev),
			"andere Werte bleiben, Stand eingetragen")
	# Danach selbst geändert: bleibt.
	var later := ["shop", "games", "friends", "achievements", "apps", "settings"]
	Config.write_json(sp, { "uzai_version": Config.VERSION, "schema": Config.SETTINGS_VERSION,
		"theme": { "rev": int(Config.DEFAULTS.theme.rev), "sections": later }, "apps": { "order": ["room", "music"], "last": "videos" } })
	Config.load_settings()
	check(Config.get_value("theme.sections", []) == later and Config.get_value("apps.order", []) == ["room", "music"], "danach selbst geändert: bleibt")
	check(LeisteOben.all_apps().map(func(t): return t.id) == ["music", "videos", "movies", "streams", "room"], "Apps: Musik, Videos, Filme, Streams, Zimmer")
	print("Namen")
	var fv = FriendsView.new()
	var rv = RoomView.new()
	check(str(fv.title) == "Freunde" and str(rv.title) == "Zimmer", "„Freunde“ (Seitenleiste) und „Zimmer“ (App)")
	fv.free()
	rv.free()
	# Bereich Zimmer: die ganze Fläche ist eine Tür; dahinter liegt schon das echte Zimmer, seine Kamera tritt
	# durch die eigene Tür herein.
	var rs := FileAccess.get_file_as_string("res://src/ui/sections/room_view.gd")
	var ts := FileAccess.get_file_as_string("res://src/ui/components/zimmer_tuer.gd")
	var me := FileAccess.get_file_as_string("res://src/main_ebenen.gd")
	check(rs.contains("ZimmerTuer.new()") and rs.contains("\"room:betreten\"") and rs.contains("main.open_room()"), "Zimmer: die Tür betritt das Zimmer")
	check(ts.contains("zimmer_vorladen") and ts.contains("U.reduziert() or Leicht.active") and ts.contains("WARTEN_S"),
			"Tür: lädt vorab, ruhig ohne Fahrt, wartet höchstens kurz")
	var zs := FileAccess.get_file_as_string("res://src/room/zimmer.gd")
	check(rs.contains("U.full_rect(t)") and not rs.contains("Shelf.new()"), "die ganze Fläche ist die Tür (keine Karte mit Bild)")
	check(ts.contains("set_meta(\"uz_tuer_fahrt\", true)") and me.contains("z.set_meta(\"uz_tuer\", true)") and zs.contains("func tuer_hinein("),
			"durch die Tür: das Zimmer liegt schon dahinter und übernimmt die Kamerafahrt")
	check(ts.find("get_viewport().get_texture().get_image()") < ts.find("chosen.emit(\"room\")\n\tremove_meta")
			and ts.find("while ruhig < RUHIG_N") > 0 and ts.find("while ruhig < RUHIG_N") < ts.find("\"hand\", v)"), "Aufbau unter einem stillen Bild, Bewegung erst bei ruhigen Bildern (kein Ruckeln)")


func _games() -> void:
	print("Spiele: keine Quelle „Aufnahmen“")
	Library.load_demo()
	var d := Config.path("probe_aufnahmen")
	DirAccess.make_dir_recursive_absolute(d)
	var f := FileAccess.open(d.path_join(CapL.capture_name("Hades", Time.get_datetime_dict_from_system(), "mp4")), FileAccess.WRITE)
	f.store_string("x")
	f.close()
	Config.set_value("capture.folder", d)
	await get_tree().create_timer(3.2).timeout    # Liste der Aufnahmen ist kurz gemerkt
	check(Capture.latest(0).size() == 1, "eine Aufnahme da")
	var g = Games.new()
	var ids: Array = (g.subtabs() as Array).map(func(t): return str(t.id))
	check(not ids.has("aufnahmen") and ids.has("zuletzt") and ids.has("alle"), "Quellen ohne „Aufnahmen“: %s" % str(ids.slice(0, 4)))
	g.free()


func _ruhig() -> void:
	print("Startseite: ruhig gewählt")
	var row = CoverRow.new().setup("t", 34, true, 82, 96)
	var c = CoverCard.new()
	c.focus_scale = 1.12
	var f = FolderTile.new()
	f.focus_scale = 1.12
	row.add(c)
	row.add(f)
	check(CoverRow.FOCUS_SCALE <= 1.04 and is_equal_approx(c.focus_scale, CoverRow.FOCUS_SCALE) and is_equal_approx(f.focus_scale, CoverRow.FOCUS_SCALE),
			"Regal: kaum wachsen (%.2f statt 1,12)" % CoverRow.FOCUS_SCALE)
	check(c.calm and f.calm, "Regal: ohne Nachfedern und Lichtstreif")
	var other = CoverCard.new()
	check(not other.calm, "anderswo (Bibliothek, Profil …) unverändert")
	other.free()
	row.free()


func _quellen() -> void:
	print("Quellen ordnen und ausblenden")
	check(Quellen.ordne(["a", "b", "c", "d"], []) == ["a", "b", "c", "d"], "ohne eigene Ordnung: wie gewohnt")
	check(Quellen.ordne(["a", "b", "c", "d"], ["c", "a"]) == ["c", "d", "a", "b"], "eigene Ordnung, neue hinter ihrem Vorgänger")
	check(Quellen.ordne(["a", "b"], ["x", "b", "a"]) == ["b", "a"], "verschwundene Quellen fallen weg")
	var tabs := [{ "id": "zuletzt", "label": "Zuletzt" }, { "id": "ps2", "label": "PS2" }, { "id": "steam", "label": "Steam" }]
	var got: Array = Quellen.arrange(tabs, ["steam", "ps2", "zuletzt"], ["ps2"]).map(func(t): return t.id)
	check(got == ["steam", "zuletzt"], "ausgeblendet fehlt, Reihenfolge gilt: %s" % str(got))
	check(Quellen.arrange(tabs, [], ["zuletzt", "ps2", "steam"]).size() == 3, "alles ausgeblendet: lieber alle zeigen als keine")
	check(Quellen.hidden_tabs(tabs, ["ps2"]).map(func(t): return t.label) == ["PS2"], "Liste zum Zurückholen")
	var g: Dictionary = Library.visible_games()[0]
	var gid := str(g.id)
	Library.set_field(gid, "hidden", true)
	check(not Library.visible_games().any(func(x): return str(x.id) == gid) and Library.hidden_games().any(func(x): return str(x.id) == gid),
			"ausgeblendetes Spiel: weg aus den Listen, in „Ausgeblendete Spiele“")
	var gs = Games.new()
	check(gs.games_for(Quellen.HIDDEN_GAMES).any(func(x): return str(x.id) == gid), "Raster „Ausgeblendete Spiele“ zeigt es")
	gs.free()
	Library.set_field(gid, "hidden", null)
	check(Library.visible_games().any(func(x): return str(x.id) == gid) and Library.hidden_games().is_empty(), "wieder zeigen: zurück")


func _langes_a() -> void:
	print("Langes A")
	var b := Button.new()
	add_child(b)
	b.grab_focus()
	var got := { "kurz": 0, "lang": 0 }
	b.pressed.connect(func() -> void: got.kurz += 1)
	b.set_meta("uz_on_hold_a", func() -> void: got.lang += 1)
	Input.action_press("uz_a")
	Nav._fire("a")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("uz_a")
	await get_tree().create_timer(0.1).timeout
	check(got.kurz == 1 and got.lang == 0, "kurz gedrückt: wie immer (beim Loslassen)")
	Input.action_press("uz_a")
	Nav._fire("a")
	await get_tree().create_timer(0.7).timeout
	Input.action_release("uz_a")
	await get_tree().create_timer(0.1).timeout
	check(got.kurz == 1 and got.lang == 1, "lang gedrückt: das Menü, kein Auslösen")
	Nav._fire("a")
	await get_tree().process_frame
	check(got.kurz == 2, "ohne gedrückte Taste (Maus, Probe): sofort")
	b.free()
