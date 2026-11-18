extends "res://src/ui/sections/settings_unterseiten.gd"
## Einstellungen, Schicht über settings_unterseiten.gd: die Kategorien Aussehen, Spiele und
## Emulation (samt Epic-Konto, das unter Konten steht).

const LauncherSites := preload("res://src/library/launcher_sites.gd")
const InstallFlowS := preload("res://src/ui/install_flow.gd")
const DlQueueS := preload("res://src/core/dl_queue.gd")

const DisplayFit := preload("res://src/core/display_fit.gd")
const Bildschirm := preload("res://src/core/bildschirm.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Klang := preload("res://src/core/klang.gd")
const Screenscraper := preload("res://src/core/screenscraper.gd")
const LeisteOben := preload("res://src/core/leiste_oben.gd")
const SystemIntro := preload("res://src/ui/components/system_intro.gd")
const QuellenOrdnung := preload("res://src/ui/sections/quellen_ordnung.gd")

## Systeme nach Familien – feste Reihenfolge, damit beim Umschalten nichts springt.
const FAMILIES := [
	["PlayStation", ["ps1", "ps2", "ps3", "psp"]],
	["Nintendo", ["nes", "snes", "n64", "gc", "wii", "wiiu", "switch", "gb", "gbc", "gba", "nds", "3ds"]],
	["Sega", ["mastersystem", "megadrive", "saturn", "dreamcast", "gamegear"]],
]


## Text zu einem Wert aus einer Auswahlliste [[wert, "Text"], …] (für den Wert an „…“-Zeilen).
static func _option_text(options: Array, value: Variant) -> String:
	for o in options:
		if o[0] == value:
			return str(o[1])
	return ""


# --- Aussehen ---------------------------------------------------------------------

func _aussehen() -> void:
	_head("Stil")
	# Mit den Farben im Kleinen: Die Auswahlliste liegt über der Vorschau rechts, Namen allein
	# („Glut“, „Tiefsee“) sagen nicht, wie es aussieht.
	var presets: Array = [["theme", "Standard", "", { "farben": UzTheme.grund.colors }]]
	for k in UzTheme.PRESETS.keys():
		presets.append([k, UzTheme.PRESETS[k].name, "", { "farben": UzTheme.PRESETS[k] }])
	_choice("theme.preset", "Farbschema", "", presets,
		func() -> Control: return Preview.themes(str(Config.get_value("theme.preset", "theme")))).set_meta("uz_such", "Theme Farbe Dunkel Hell Aussehen")
	var acc := str(Config.get_value("theme.accent", ""))
	var pick_accent := func() -> void:
		main.open_color_picker("Akzentfarbe", UzTheme.col("accent"), func(c: Color) -> void: Config.set_value("theme.accent", "#" + c.to_html(false)))
	var r = _action("Akzentfarbe", "", "Eigene Farbe" if acc != "" else "Vom Farbschema", pick_accent, "palette", "",
			func() -> Control: return Preview.accent(UzTheme.col("accent")))
	r.swatch = UzTheme.col("accent")
	if acc != "":
		r.set_meta("uz_hint_y", "Zurücksetzen")
		r.set_meta("uz_on_y", func() -> void: Config.set_value("theme.accent", ""))
	_choice("theme.background", "Hintergrund", "",
		[["theme", "Standard"], ["game", "Bild des Spiels"], ["nebel", "Lichtpunkte"], ["farbe", "Nur Farbe"], ["bild", "Eigenes Bild"]])
	if str(Config.get_value("theme.background", "theme")) == "bild":
		_path("theme.background_image", "Eigenes Bild", "PNG, JPG oder WebP.", false, ["png", "jpg", "jpeg", "webp"])
	_choice("theme.corners", "Ecken", "",
			[["theme", "Standard"], ["eckig", "Eckig"], ["leicht", "Leicht gerundet"], ["rund", "Rund"]],
		func() -> Control: return Preview.shapes("corners", str(Config.get_value("theme.corners", "theme"))))
	_head("Schrift und Größe")
	_choice("theme.font", "Schrift", "",
		[["theme", "Standard"], ["plex", "IBM Plex Sans"], ["hanken", "Hanken Grotesk"], ["atkinson", "Atkinson Hyperlegible"], ["system", "Systemschrift"],
			["datei", "Eigene Schriftdatei"]],
			func() -> Control: return Preview.font_sample())
	if str(Config.get_value("theme.font", "theme")) == "datei":
		_path("theme.font_file", "Schriftdatei", "TTF oder OTF.", false, ["ttf", "otf"])
	_slider("theme.ui_scale", "Größe der Oberfläche", "", 0.8, UzTheme.SCALE_MAX, 0.05).set_meta("uz_such", "Zoom Skalierung Schriftgröße")
	_action("Größe automatisch einstellen", "Nach Bildschirm: Fernseher, Monitor oder Laptop.",
		DisplayFit.summary(Config.get_value("display.seen", {}), true), _auto_fit, "tv")
	_bildschirm_zeile()
	_choice("theme.clock_24h", "Uhr", "", [[true, "24 Stunden"], [false, "12 Stunden"]],
			func() -> Control: return Preview.clock())
	_head("Cover")
	_choice("theme.cover_shape", "Cover-Form", "",
			[["theme", "Standard"], ["hoch", "Hochformat"], ["quer", "Querformat"], ["quadrat", "Quadrat"]],
		func() -> Control: return Preview.shapes("cover_shape", UzTheme.cover_shape()))
	_choice("theme.cover_size", "Cover-Größe", "", [["theme", "Standard"], ["s", "Klein"], ["m", "Mittel"], ["l", "Groß"]],
		func() -> Control: return Preview.shapes("cover_size", str(Config.get_value("theme.cover_size", "theme"))
			if str(Config.get_value("theme.cover_size", "theme")) != "theme" else str(UzTheme.grund.layout.cover_size)))
	_head("Bewegung")
	_choice("theme.boot", "Startanimation", "Jede Taste überspringt sie.",
			[["theme", "Standard"], ["voll", "Konsole"], ["kurz", "Konsole, kurz"], ["roehre", "Röhrenfernseher"], ["aus", "Aus"]],
		func() -> Control: return Preview.boot(UzTheme.boot_mode()))
	_choice("theme.system_intro", "Startanimation je System", "", SystemIntro.MODES, func() -> Control: return Preview.system_intro())
	_toggle("theme.reduce_motion", "Animationen reduzieren", "")
	_head("Startseite")
	_choice("room.start", "Art der Startseite", "Dein Zimmer braucht mehr Grafikleistung.", [["klassisch", "Klassisch (2D)"], ["zimmer", "Dein Zimmer (3D)"]])
	_toggle("room.kachel", "Dein Zimmer als Kachel", "Am Ende von „Zuletzt“.")
	_more("Leiste oben", "", "Symbole" if str(Config.get_value("theme.tabs", "auto")) == "symbole" else "Wörter", "grid", _leiste)
	_mehr(_aussehen_mehr)


## Aussehen › Mehr: Seltenes – Raum, Feinheiten, Leistung.
func _aussehen_mehr() -> void:
	_head("Raum")
	_slider("theme.aurora", "Farbverläufe", "", 0.0, 1.0, 0.1)
	_slider("theme.dim", "Abdunklung", "", 0.0, 0.9, 0.05)
	_toggle("theme.tint", "Raum in Spielfarbe", "")
	_toggle("theme.bg_soft", "Hintergrund weichzeichnen", "")
	_toggle("theme.motes", "Schwebende Lichtpunkte", "Aus spart Leistung.")
	_head("Feinheiten")
	_choice("theme.display", "Schrift für Titel", "",
		[["theme", "Standard"], ["plex_condensed", "IBM Plex Sans Condensed"], ["hanken", "Hanken Grotesk"], ["saira", "Saira"], ["gleich", "Wie die Schrift"]])
	var hz := DisplayServer.screen_get_refresh_rate(get_window().current_screen)
	if hz > DisplayFit.FULL_RATE_MAX_HZ:
		_choice("display.menu_fps", "Bildrate im Menü", "Spiele betrifft das nicht.",
			[["auto", "%d Bilder/s" % DisplayFit.menu_fps(hz, "auto")], ["voll", "%d Bilder/s" % roundi(hz)]])
	# Uzai empfiehlt ihn auf diesem PC: steht als Zustand an der Zeile, nicht als eigene Zeile.
	var why_t := ""
	if str(Config.get_value("display.light", "auto")) == "auto":
		var menu: Dictionary = main.perf.menu_stats() if main and "perf" in main and main.perf else {}
		var why := Leicht.reasons(Leicht.device(), menu)
		if not why.is_empty():
			why_t = Leicht.reason_text(why, menu)
	var lm := _choice("display.light", "Leichter Modus", why_t if why_t != "" else "Weniger Effekte, gleiche Bedienung.", Leicht.MODES)
	if why_t != "":
		lm.set("subtitle", "Uzai empfiehlt ihn hier")


## Menüklänge als eine Zeile (Klang): 0 % ist aus. Schreibt weiter beide Werte (an/aus und
## Lautstärke), damit ältere Einstellungen und der Klang-Dienst unverändert bleiben.
func _sound_row() -> void:
	var on := bool(Config.get_value("theme.sounds", true))
	var r = SettingRow.new()
	r.setup("slider", "Menüklänge", "", float(Config.get_value("theme.sound_volume", 0.6)) if on else 0.0)
	r.set_meta("uz_path", "theme.sound_volume")
	r.set_meta("uz_such", "Lautstärke Ton Sound")
	r.min_v = 0.0
	r.max_v = 1.0
	r.step = 0.1
	r.changed.connect(func(v: Variant) -> void:
		var f := float(v)
		Config.set_value("theme.sounds", f > 0.001)
		if f > 0.001:
			Config.set_value("theme.sound_volume", f)
	)
	_add(r, "")


## Mit mehreren Bildschirmen: auf welchem Uzai läuft (src/core/bildschirm.gd). Ein gewählter, der gerade
## nicht angeschlossen ist, bleibt in der Liste stehen – bis dahin gilt „Automatisch“.
func _bildschirm_zeile() -> void:
	var anzahl := DisplayServer.get_screen_count()
	var wahl := str(Config.get_value("display.screen", Bildschirm.AUTO))
	if anzahl < 2 and wahl == Bildschirm.AUTO:
		return
	var groessen: Array = []
	for i in anzahl:
		groessen.append(DisplayServer.screen_get_size(i))
	var liste := Bildschirm.wahl_liste(groessen, DisplayServer.get_primary_screen(), tr("Automatisch"), tr("Hauptbildschirm"))
	if wahl != Bildschirm.AUTO and Bildschirm.index(wahl, anzahl) < 0:
		liste.append([wahl, tr("%s  ·  nicht angeschlossen") % wahl])
	# Spiele öffnet Windows auf seinem Hauptbildschirm: Läuft Uzai auf einem anderen, sieht man dort beim
	# Spielstart den Desktop – das sagt die Zeile, statt es zu verschweigen.
	var hier := Bildschirm.index(wahl, anzahl)
	if hier < 0:
		hier = get_window().current_screen
	var text := "Hier öffnet sich Uzai." if hier == DisplayServer.get_primary_screen() \
			else "Spiele öffnen sich auf dem Hauptbildschirm von Windows."
	_choice("display.screen", "Bildschirm", text, liste).set_meta("uz_such", "Monitor Fernseher Anzeige Display zweiter")


## Den Bildschirm neu erkennen und die Größe der Oberfläche danach setzen (display_fit.gd).
func _auto_fit() -> void:
	var seen: Dictionary = await DisplayFit.detect(get_window())
	var kind := DisplayFit.apply(seen, false)
	if kind == "":
		Toasts.show_toast("Bildschirm nicht erkannt", "Größe unter Einstellungen → Aussehen.", "tv")
	else:
		Toasts.show_toast(DisplayFit.KIND_DONE[kind], "Größe der Oberfläche %d %%" % roundi(UzTheme.ui_scale() * 100.0), "tv")
	_rebuild_keep()


## Unterseite „Leiste oben“: Wörter oder Symbole, welche Bereiche und Apps oben stehen.
func _leiste() -> void:
	_choice("theme.tabs", "Darstellung", "", [["auto", "Wörter"], ["symbole", "Symbole"]])
	_head("Bereiche")
	var in_bar: Array = _section_order()
	for sid in in_bar:
		_hide_toggle("theme.hidden_sections", sid, str(SECTION_NAMES[sid]))
	# Apps: dieselben Schalter wie langes A → Ausblenden auf ihrem Symbol oben.
	_head("Apps")
	var apps := LeisteOben.all_apps()
	if not Movies.enabled():
		apps.insert(mini(2, apps.size()), { "id": "movies", "label": "Filme" })   # zum Wiedereinschalten
	for app in apps:
		_hide_toggle("apps.hidden", str(app.id), str(app.label))
	if LeisteOben.extern_allowed():
		_action("App hinzufügen", "Store-App oder Programm als eigenes Symbol oben.", "", func() -> void: main.open_add_app(), "add")
	# Die App-Symbole stehen immer hinter den Wörtern: nach vorn holen gibt es nur für Bereiche.
	var opts: Array = []
	for sid2 in in_bar:
		if sid2 != "apps":
			opts.append([sid2, SECTION_NAMES[sid2]])
	_action("Bereich nach vorne holen", "", "", func() -> void:
		main.open_choice("Welcher Bereich soll nach vorne?", opts, null, func(v: Variant) -> void:
			var order: Array = Config.get_value("theme.sections", []).duplicate()
			order.erase(v)
			order.push_front(v)
			Config.set_value("theme.sections", order)
		)
	, "sort")


# --- Spiele ---------------------------------------------------------------------------

## Schalter „zeigen“ für einen Reiter bzw. eine App (key: Liste der ausgeblendeten). „Filme“ ist
## ein Schalter mit dem Bereich selbst (movies.enabled; früher gab es dafür zwei Schalter).
func _hide_toggle(key: String, id: String, label: String) -> void:
	var hidden: Array = Config.get_value(key, [])
	var row = SettingRow.new()
	var shown := not hidden.has(id) and (id != "movies" or bool(Config.get_value("movies.enabled", true)))
	row.setup("toggle", label, "", shown)
	row.set_meta("uz_path", key)
	row.changed.connect(func(v: Variant) -> void:
		var h: Array = Config.get_value(key, []).duplicate()
		if v:
			h.erase(id)
		elif not h.has(id) and id != "movies":
			h.append(id)
		if id == "movies":
			h.erase(id)
			Config.set_value("movies.enabled", bool(v))
		Config.set_value(key, h)
	)
	_add(row, "", "Bereich „%s“" % label)


## Fehlt der Launcher (Punkt 115): die offizielle Seite anbieten, nur wenn Uzai es sicher weiß.
func _launcher_row(id: String) -> void:
	if not Library.launcher_missing(id) or not bool(Config.get_value("library.%s_enabled" % id, true)):
		return
	var s := LauncherSites.site(id)
	_action("%s fehlt" % str(s.name), "", "Offizielle Seite", func() -> void: main.open_launcher_offer(id), "download", "accent")


func _spiele() -> void:
	_head("Quellen")
	_toggle("library.steam_enabled", "Steam-Spiele", "")
	_launcher_row("steam")
	_toggle("library.steam_owned", "Auch nicht installierte Steam-Spiele", "Braucht die Steam-Anmeldung." if not Social.has_steam() else "")
	if not Social.has_steam():
		_action("Bei Steam anmelden", "Per QR-Code mit der Steam-App.", "QR-Code", func() -> void: main.open_chat({ "id": "", "name": "Steam" }, true), "steam", "accent")
	_toggle("library.epic_enabled", "Epic-Spiele", "")
	_launcher_row("epic")
	if Config.get_value("library.epic_enabled", true):
		var own_note := ""
		if Library.epic_catalog == 0 and not Library.epic_account.logged_in():
			own_note = "Nicht verfügbar. Epic Games Launcher einmal öffnen."
		elif not Library.epic_account.logged_in():
			own_note = "Braucht das Epic-Konto."
		_toggle_def("library.epic_owned", "Auch nicht installierte Epic-Spiele", own_note, true)
	_toggle("library.ea_enabled", "EA-Spiele", "")
	_launcher_row("ea")
	var n_on := Library.Stores.EXTRA.filter(func(id: String) -> bool: return Library.Stores.enabled(id)).size()
	_more("Weitere Launcher", "", "%d von %d an" % [n_on, Library.Stores.EXTRA.size()], "games", _weitere_launcher)
	var pc_dirs: Array = Config.get_value("library.pc_dirs", [])
	_more("PC-Spiele", "", U.plural(pc_dirs.size(), "Ordner", "Ordner") if not pc_dirs.is_empty() else "", "desktop", _pc_spiele)
	_head("Installieren")
	var n_dl := Installs.active_count()
	_more("Installieren und Downloads", "", ("%d aktiv" % n_dl) if n_dl > 0 else "", "download", _installieren)
	_head("Anzeige")
	_toggle("system.game_page", "Spielseite vor dem Start", "Aus: A startet sofort.")
	_more("Ordner in Uzai", "", U.plural(Library.folders.size(), "Ordner", "Ordner") if not Library.folders.is_empty() else "", "folder", _uzai_ordner)
	var missing := Media.sgdb_missing()
	_more("Bilder", "", (tr("%d ohne Cover") % missing) if missing > 0 and not Media.sgdb_games().is_empty() else "", "image", _bilder)
	_rescan_row()
	_mehr(_spiele_mehr)


## Spiele › Mehr: Seltenes – Anzeige, Einlesen, Pfade.
func _spiele_mehr() -> void:
	_toggle("system.round_summary", "Zusammenfassung nach dem Spielen", "")
	_toggle("system.live_tiles", "Lebendige Kacheln", "Kleine Hinweise auf den Covern.")
	# Ausgeblendete Spiele stehen nur in ihrer eigenen Liste (zum Zurückholen).
	var n_hid := Library.hidden_games().size()
	if n_hid > 0:
		_action("Ausgeblendete Spiele", "", str(n_hid), func() -> void:
			if main:
				main.open_library(QuellenOrdnung.HIDDEN_GAMES, "Ausgeblendete Spiele"), "eye_off")
	else:
		_info_row("Ausgeblendete Spiele", "", "0", "eye_off")
	_toggle("library.scan_on_start", "Beim Start neu einlesen", "")
	_path("library.steam_dir", "Steam-Ordner", "Nur, wenn Steam nicht gefunden wird.", true, [], Callable(),
			"Leer: Uzai sucht Steam selbst." if str(Config.get_value("library.steam_dir", "")) == "" else "")


## Unterseite „Bilder“: woher Cover, Szenen und Logos kommen, und der eigene Medienordner.
func _bilder() -> void:
	_cover_row()
	_toggle("library.steam_images", "Bilder von Steam", "")
	_toggle("library.libretro_images", "Bilder aus der Libretro-Sammlung", "Cover, Schriftzüge und Szenen für Emulator-Spiele.")
	_toggle("library.web_info", "Szenen und Text aus Wikipedia", "")
	_toggle_def("badges.real_logos", "Echte Konsolen-Logos", "Aus dem Netz, von Wikimedia Commons.", true)
	_path("library.media_dir", "Medienordner", "Eigene Cover, z. B. media/ps2/Okami.png.", true, [], Callable(),
		"Leer: der Ordner „media“ im Datenordner." if str(Config.get_value("library.media_dir", "")) == "" else "")


## Unterseite „Installieren und Downloads“ (Installs, InstallFlow).
func _installieren() -> void:
	var n := Installs.list().size()
	var dl := _action("Downloads", "", U.plural(n, "Eintrag", "Einträge") if n > 0 else "keine", func() -> void: InstallFlowS.open_downloads(main), "download")
	# Die Bandbreite stellt nur Steam ein; Uzai liest sie aus und zeigt sie an der Zeile.
	if not _indexing:
		dl.set("subtitle", tr("Bandbreite (Steam): %s") % DlQueueS.throttle_text(Installs.steam_throttle()))
	_choice("library.steam_install_lib", "Speicherort neuer Steam-Spiele", "Ein anderer Ordner: Steam startet kurz neu.",
		InstallFlowS.steam_lib_options())
	var tg := _toggle("library.epic_uzai", "Epic-Spiele ohne Launcher installieren", "")
	tg.connect("changed", func(_v: Variant) -> void: Config.set_value("library.epic_uzai_asked", true))
	var ud := str(Config.get_value("library.epic_uzai_dir", ""))
	_action("Ordner für Epic-Spiele ohne Launcher", "", ud.replace("/", "\\") if ud != "" else "Beim ersten Mal wählen",
		func() -> void: InstallFlowS.pick_uzai_dir(main, func(_p: String) -> void: _rebuild_keep()), "folder").set_meta("uz_path", "library.epic_uzai_dir")
	_toggle("library.install_auto", "Dialoge selbst bestätigen", "Lizenzen nie.")
	_head("Nachts laden")
	_toggle("downloads.night", "Nachts laden", "Nur bei eingeschaltetem PC.")
	var hours: Array = []
	for hh in 24:
		hours.append([str(hh), "%d Uhr" % hh])
	_choice("downloads.night_from", "Ab", "", hours)
	_choice("downloads.night_to", "Bis", "", hours)
	_toggle("downloads.night_updates", "Updates nachts", "Das laufende Spiel nie.")


## Weitere Launcher (Punkt 6, src/library/stores.gd): je Launcher ein Schalter, fehlt er (und gibt
## es Spiele von ihm), die offizielle Seite.
const STORE_TITLES := {
	"gog": "GOG-Spiele", "ubisoft": "Ubisoft-Spiele", "battlenet": "Battle.net-Spiele",
	"xboxpc": "Xbox- und Game-Pass-Spiele", "amazon": "Amazon-Games-Spiele", "itch": "itch.io-Spiele",
	"riot": "Riot-Spiele",
}
const STORE_TEXTS := {
	"gog": "Mit oder ohne GOG Galaxy.",
	"ubisoft": "Gestartet über Ubisoft Connect.",
	"battlenet": "Gestartet über Battle.net.",
	"xboxpc": "Nur Spiele, keine anderen Apps.",
	"amazon": "Gestartet über Amazon Games.",
	"itch": "Gestartet wie in der itch-App.",
	"riot": "Gestartet über den Riot Client.",
}


func _weitere_launcher() -> void:
	for id in Library.Stores.EXTRA:
		_toggle("library.%s_enabled" % id, str(STORE_TITLES.get(id, id)), str(STORE_TEXTS.get(id, "")))
		_launcher_row(id)
		if id == "gog" and Config.get_value("library.gog_enabled", true):
			_toggle("library.gog_galaxy", "GOG-Spiele über GOG Galaxy starten", "Aus: direkt die Programmdatei.")


func _pc_spiele() -> void:
	_action("PC-Spiel hinzufügen", "", "", _add_pc_game, "plus")
	var pc_dirs: Array = Config.get_value("library.pc_dirs", [])
	for i in pc_dirs.size():
		var d := str(pc_dirs[i])
		var row := _action("PC-Spiele-Ordner", "A entfernt den Ordner aus Uzai.", d, func() -> void:
			main.open_dialog("Ordner entfernen?", "Die Spiele aus „%s“ werden ausgeblendet. Dateien bleiben." % d.get_file(), [
				["Entfernen", func() -> void:
					var old: Array = (Config.get_value("library.pc_dirs", []) as Array).duplicate()
					var cur := old.duplicate()
					cur.erase(d)
					Config.set_value("library.pc_dirs", cur)
					_rebuild_keep()
					Library.scan()
					Undo.offer_calls("Ordner entfernt", d.get_file(), "folder", [Config.set_value.bind("library.pc_dirs", old), Library.scan], _rebuild_keep), "danger"],
				["Behalten", func() -> void: pass],
			])
		, "folder", "", func() -> Control: return Preview.path_box(d))
		row.set_meta("uz_key", "pcdir:" + d)
		row.set_meta("uz_path", "library.pc_dirs")
	_action("PC-Spiele-Ordner hinzufügen", "Alles darin erscheint unter Spiele → PC.", "",
			func() -> void:
		main.open_file_browser("Ordner mit PC-Spielen", true, func(p: String) -> void:
			var cur: Array = (Config.get_value("library.pc_dirs", []) as Array).duplicate()
			if not cur.has(p):
				cur.append(p)
			Config.set_value("library.pc_dirs", cur)
			_rebuild_keep()
			Library.scan()
		)
	, "plus").set_meta("uz_path", "library.pc_dirs")


func _uzai_ordner() -> void:
	for f in Library.folders:
		var fo: Dictionary = f
		var sysn := "Alle Systeme" if str(fo.get("system", "")) == "" else str(
				Config.system(str(fo.system)).get("name", Library.store_name({ "source": str(fo.system) }, false, str(fo.system))))
		var fr = _action(str(fo.name), "",
				U.plural(Library.in_folder(str(fo.id)).size(), "Spiel", "Spiele"), func() -> void: main.open_folder_options(fo), "folder")
		fr.subtitle = sysn
		fr.set_meta("uz_key", "folder:" + str(fo.id))
	_action("Neuer Ordner", "Für ein System oder für alle.", "", _new_folder, "plus")
	_toggle("library.folder_hide", "Spiele in Ordnern nur im Ordner zeigen", "")


# --- Emulation ------------------------------------------------------------------------

func _emulation() -> void:
	var on: Array = Config.systems_enabled()
	_head("Deine Systeme", "%d an" % on.size())
	for sys in on:
		_my_system_row(sys)
	_more("Systeme ein- und ausschalten", "",
		"%d von %d an" % [on.size(), Config.systems().size()], "plus", _systeme)
	var used := {}
	var enabled := {}
	for sys in on:
		used[str(sys.get("emulator", ""))] = true
		enabled[str(sys.id)] = true
	var emus: Array = Config.emulators()
	var mine: Array = emus.filter(func(e): return used.has(str(e.id)))
	_head("Emulatoren", _ready_count(mine))
	_retro_row()
	for e in mine:
		_emu_row(e)
	var rest := emus.size() - mine.size()
	_more("Weitere Emulatoren", "", U.plural(rest, "Vorlage", "Vorlagen") if rest > 0 else "", "chip", func() -> void: _more_emus(used, enabled))
	_head("Bildfilter")
	_toggle("shaderglass.enabled", "Bildfilter verwenden", "Bild blau oder flackert: Windows-HDR ausschalten.")
	var sg := str(Config.get_value("shaderglass.exe", ""))
	var sg_row := _path("shaderglass.exe", "ShaderGlass-Programm", "", false, ["exe"])
	sg_row.set("value_text", ("Gefunden" if FileAccess.file_exists(sg) else "Datei fehlt") if sg != "" else "Nicht festgelegt")
	sg_row.set("tone", ("ok" if FileAccess.file_exists(sg) else "warn") if sg != "" else "faint")
	_more("Filter-Profile", "",
		U.plural(Config.filters().size(), "Profil", "Profile"), "tv", func() -> void:
			for f in Config.filters():
				var fid := str(f.id)
				var own := str(f.get("sgp", ""))
				_action(str(f.name), str(f.get("note", "")), own.get_file() if own != "" else "Werte von Uzai", func() -> void: _filter_sheet(fid), "tv").set_meta("uz_key",
						"filter:" + fid)
	)


## Cover für alle Spiele holen (Spiele › Bilder; ohne Spiele keine Zeile): das Menü
## „Spiele scrapen“ (spiele_scrapen.gd) mit ScreenScraper und SteamGridDB.
func _cover_row() -> void:
	var total := Media.scrape_spiele().size()
	if total == 0:
		return
	var missing := Media.scrape_fehlt()
	var val := "Läuft …" if Media.sgdb_running else (tr("%d ohne Cover") % missing if missing > 0 else tr("Alle da"))
	var row = _action("Spiele scrapen", "Cover, Hintergründe und Schriftzüge für alle Spiele.", val, func() -> void:
		var l = load("res://src/ui/layers/spiele_scrapen.gd").new()
		l.main = main
		main.open_layer(l)
	, "image")
	row.set_meta("uz_key", "sgdb_all")
	if Screenscraper.zugang().has("devid"):
		_toggle("library.screenscraper", "Bilder von ScreenScraper", "Ohne Schlüssel. Nacheinander, mit Tageslimit. Daten: ScreenScraper.fr")
		_ss_konto_row()
	# iiDB (iiSU): eigener Schlüssel unter Konten; hier der Schalter für den Klang der Spielseite.
	if Media.iidb.verbunden():
		_toggle("library.spielklang", "Spielklang auf der Spielseite", "Der Klang des Spiels läuft, solange die Spielseite offen ist. Daten: iiDB (iisu.network)")


## Freiwilliges ScreenScraper-Konto: hebt nur das eigene Tageskontingent. Name und Passwort über die
## Bildschirmtastatur (Passwort verdeckt, im Tresor), beide geprüft wie im Baustein (screenscraper.gd).
func _ss_konto_row() -> void:
	var user := str(Config.get_value("accounts.ss_user", ""))
	_action("ScreenScraper-Konto", "Freiwillig: mehr Bilder am Tag.", user if user != "" else "Nicht verbunden", func() -> void:
		if user != "":
			main.open_dialog("ScreenScraper-Konto", "Angemeldet als %s." % user, [
				["Anderes Konto", func() -> void: _ss_konto_eingeben()],
				["Abmelden", func() -> void:
					Config.set_value("accounts.ss_user", "")
					Config.set_value("accounts.ss_pass", "")
					_rebuild_keep()],
				["Abbrechen", func() -> void: pass],
			], "image")
		else:
			_ss_konto_eingeben()
	, "user")


func _ss_konto_eingeben() -> void:
	main.open_keyboard("ScreenScraper-Name", "", func(nm_roh: String) -> void:
		var nm := nm_roh.strip_edges()
		if not Screenscraper.wert_ok(nm):
			Toasts.show_toast("Name passt nicht", "Bitte noch einmal eingeben: ohne Leerzeichen, höchstens 64 Zeichen.", "warning")
			return
		main.open_keyboard("ScreenScraper-Passwort", "", func(pw: String) -> void:
			if not Screenscraper.wert_ok(pw):
				Toasts.show_toast("Passwort passt nicht", "Bitte noch einmal eingeben: ohne Leerzeichen, höchstens 64 Zeichen.", "warning")
				return
			Config.set_value("accounts.ss_user", nm)
			Config.set_value("accounts.ss_pass", pw)
			Toasts.show_toast("ScreenScraper-Konto gespeichert", nm, "check", { "quiet": true })
			_rebuild_keep()
		, true)
	)


## Ein eingeschaltetes System: Emulator, Bildfilter und Spiele auf einen Blick; A öffnet alles
## für dieses System an einer Stelle (Spieleordner, Emulator, Filter, Farbe, Endungen).
func _my_system_row(sys: Dictionary) -> void:
	var sid := str(sys.id)
	var dir := Config.rom_dir(sid)
	var n := Library.count_by_system(sid)
	var emu := str(Config.emulator(str(sys.get("emulator", ""))).get("name", ""))
	var flt := str(Config.filter(str(sys.get("filter", ""))).get("name", "")) if str(sys.get("filter", "")) != "" else ""
	var parts := PackedStringArray()
	parts.append(emu if emu != "" else "Kein Emulator")
	if flt != "":
		parts.append(flt)
	var r = _action(str(sys.name), "",
		("Ordner fehlt" if dir == "" else U.plural(n, "Spiel", "Spiele")), func() -> void: _system_sheet(sid), "", "warn" if dir == "" else "",
		func() -> Control:
			return Preview.table([
				["Spieleordner", dir if dir != "" else "Noch nicht gewählt"],
				["Spiele", str(n)],
				["Emulator", emu if emu != "" else "Keiner"],
				["Bildfilter", flt if flt != "" else "Aus"],
			]))
	r.dot = _system_color(sys)
	r.subtitle = " · ".join(parts)
	r.set_meta("uz_key", "sys:" + sid)


## Spiele neu einlesen (Spiele): Neues kommt dazu, Einträge ohne Datei, leere und unvollständige
## (.cue ohne Spur, .m3u ohne Disc) verschwinden. Spielzeit und Bilder bleiben am Eintrag gemerkt.
func _rescan_row() -> void:
	var r: Dictionary = Library.last_scan
	var val := "Läuft …" if Library.scanning else (Library.scan_text(r).get_slice("  ·  ", 1) if not r.is_empty()
			else U.plural(Library.visible_games().size(), "Spiel", "Spiele"))
	var row = _action("Spiele neu einlesen", "Spielzeit und Bilder bleiben.",
		val, func() -> void:
			if Library.scanning:
				Toasts.show_toast("Wird schon eingelesen", "", "refresh", { "quiet": true })
				return
			Library.scan(true, true), "refresh")
	row.set_meta("uz_key", "emu:rescan")
	row.set_meta("uz_such", "Scan Aktualisieren Bibliothek")


## Retro ohne Einrichtung (src/ui/layers/retro_einrichten.gd): was fehlt und Laden von der
## offiziellen Quelle, mit Zustimmung.
func _retro_row() -> void:
	var lage: Array = load("res://src/core/retro_laden.gd").inst().lage()
	var fehlt := RetroAuto.fehlt_text(lage)
	_action("Emulatoren einrichten", "Von der offiziellen Quelle. Nie BIOS oder Spiele.",
		fehlt if fehlt != "" else ("Alles bereit" if not lage.is_empty() else ""), func() -> void:
			var l: Control = load("res://src/ui/layers/retro_einrichten.gd").open_for(main)
			l.closed.connect(_rebuild_keep), "download", "warn" if fehlt != "" else "")


func _more_emus(used: Dictionary, enabled: Dictionary) -> void:
	_action("Eigenen Emulator hinzufügen", "", "", _new_emulator, "plus")
	var emus: Array = Config.emulators()
	var own: Array = emus.filter(func(e): return e.get("custom", false) and not used.has(str(e.id)))
	if not own.is_empty():
		_head("Eigene")
		for e in own:
			_emu_row(e)
	var fitting: Array = emus.filter(
			func(e): return not used.has(str(e.id)) and not e.get("custom", false) and (e.get("systems", []) as Array).any(func(s): return enabled.has(str(s))))
	var others: Array = emus.filter(func(e): return not used.has(str(e.id)) and not e.get("custom", false) and not fitting.has(e))
	if not fitting.is_empty():
		_head("Auch passend")
		for e in fitting:
			_emu_row(e)
	if not others.is_empty():
		_head("Für Systeme, die gerade aus sind")
		for e in others:
			_emu_row(e)


func _systeme() -> void:
	var all: Array = Config.systems()
	var placed := {}
	var groups: Array = []
	for fam in FAMILIES:
		var members: Array = []
		for want in fam[1]:
			for sys in all:
				if str(sys.id) == str(want):
					members.append(sys)
					placed[str(sys.id)] = true
		groups.append([fam[0], members])
	var rest: Array = all.filter(func(s): return not placed.has(str(s.id)))
	groups.append(["Weitere", rest])
	for gr in groups:
		var members2: Array = gr[1]
		if members2.is_empty():
			continue
		var on := members2.filter(func(s): return bool(s.get("enabled", false))).size()
		_head(str(gr[0]), "%d von %d an" % [on, members2.size()])
		for sys in members2:
			_system_row(sys)


# --- Epic-Konto (unter Konten) ----------------------------------------------------------------

## Epic-Konto: inoffizielle Anmeldung wie Heroic/Legendary, alle gekauften Spiele.
func _epic_page() -> void:
	var acc = Library.epic_account
	if acc.logged_in():
		var desc := ""
		if str(acc.last_error) != "":
			desc = "Zuletzt: " + str(acc.last_error)
		_action("Von Epic abmelden", desc, acc.status_text(), func() -> void:
			_abmelden_fragen("Epic", func() -> void:
				acc.logout()
				Library.refresh_epic()
				_rebuild_keep())
		, "user", _epic_tone())
		_action("Spiele jetzt abgleichen", "", _epic_when(int(acc.last_sync())), func() -> void:
			Toasts.show_toast("Epic-Spiele werden geholt …", "", "games", { "quiet": true })
			var ok: bool = await acc.sync()
			while Library.scanning:
				await Library.get_tree().process_frame
			Library.refresh_epic()
			if ok:
				Toasts.show_toast("Epic-Spiele abgeglichen", U.plural(maxi(int(acc.owned_count()), 0), "Spiel", "Spiele") + " aus deinem Konto.", "check")
			else:
				Toasts.show_toast("Epic-Spiele nicht abgeglichen", str(acc.last_error), "warning", { "ms": 6000 })
			if is_inside_tree():
				_rebuild_keep()
		, "refresh")
		_head("Freiwillig")
		_toggle("accounts.epic_game_login", "Anmeldung an Spiele weitergeben", "Einmal-Code beim Spielstart.")
	else:
		var desc2 := "Per QR-Code."
		if acc.state == "abgelaufen":
			desc2 = "Abgelaufen: einmal neu anmelden."
		_action("Mit Epic anmelden", desc2, acc.status_text() if acc.state == "abgelaufen" else "QR-Code", func() -> void:
			main.open_layer(load("res://src/ui/layers/epic_login.gd").new())
		, "qr", "warn" if acc.state == "abgelaufen" else "accent")
	if not bool(Config.get_value("library.epic_enabled", true)):
		_info_row("Epic-Spiele sind aus", "Unter Spiele → Quellen.", "Aus", "warning")


func _epic_tone() -> String:
	var acc = Library.epic_account
	match str(acc.state):
		"bereit": return "ok"
		"fehler", "abgelaufen": return "warn"
	return ""


static func _epic_when(t: int) -> String:
	if t <= 0:
		return "Noch nie"
	var mins := int((Time.get_unix_time_from_system() - t) / 60.0)
	if mins < 1:
		return "Gerade eben"
	if mins < 60:
		return "Vor %d Min." % mins
	if mins < 48 * 60:
		return "Vor %d Std." % int(mins / 60.0)
	return "Vor %d Tagen" % int(mins / 1440.0)
