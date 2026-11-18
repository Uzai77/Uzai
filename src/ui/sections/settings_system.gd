extends "res://src/ui/sections/settings_medien.gd"
## Einstellungen, Schicht über settings_medien.gd: die Kategorie System – Sprache, Start mit
## Windows, Ruhemodus, Windows, Daten, Sicherungen, Speicher, Hilfe, Leistung, Über Uzai.

const PowerOff := preload("res://src/ui/power_off.gd")
const StorageFlow := preload("res://src/ui/storage_flow.gd")
const Storage := preload("res://src/core/storage.gd")
const P := preload("res://src/core/install_parse.gd")

const Backup := preload("res://src/core/backup.gd")
const Perf := preload("res://src/core/perf.gd")
const Trouble := preload("res://src/core/trouble.gd")
const Doktor := preload("res://src/core/doktor.gd")
const DoktorLage := preload("res://src/core/doktor_lage.gd")
const WinEinst := preload("res://src/core/win_einst.gd")
const Saver := preload("res://src/core/saver.gd")
const UpdateP := preload("res://src/core/update_pruefung.gd")


# --- System ---------------------------------------------------------------------------------

func _system() -> void:
	if Config.safe_mode:
		_head("Sicherer Modus ist an")
		_action("Normal neu starten", "Uzai läuft gerade mit dem Nötigsten.", "", func() -> void: main.restart_uzai(), "warning", "accent")
	_head("Allgemein")
	var lang = _choice("system.language", "Sprache", "Gilt nach einem Neustart.", Config.Lang.LANGS)
	lang.changed.connect(func(_v: Variant) -> void:
		main.open_dialog("Jetzt neu starten?", "Gilt nach dem Neustart.", [
			["Neu starten", func() -> void: main.restart_uzai()],
			["Später", func() -> void: pass],
		], "refresh"))
	# Land für Preise und Angebote: von selbst nach Sprache und Windows, oder fest gewählt.
	var auto_land := Config.Lang.land_fuer("auto", TranslationServer.get_locale(), OS.get_locale())
	var auto_name := auto_land
	for l in Config.Lang.LAENDER:
		if str(l[0]) == auto_land:
			auto_name = tr(str(l[1]))
	var laender: Array = [["auto", tr("Automatisch (%s)") % auto_name]]
	laender.append_array(Config.Lang.LAENDER)
	_choice("system.country", "Land", "Für Preise und Angebote im Shop.", laender).set_meta("uz_such", "Währung Preise Region Shop Euro Dollar")
	_choice("system.on_start", "Beim Einschalten", "", [["home", "Startseite"], ["letztes", "Letztes Spiel fortsetzen"]])
	var grafik = _choice("system.grafik", "Grafik", "Schwarze Flächen oder Abstürze: „Kompatibel“.",
		[["realistisch", "Realistisch"], ["kompatibel", "Kompatibel"]])
	grafik.changed.connect(func(_v: Variant) -> void:
		main.open_dialog("Jetzt neu starten?", "Gilt nach dem Neustart.", [
			["Neu starten", func() -> void: main.restart_uzai()],
			["Später", func() -> void: pass],
		], "refresh"))
	var auto = _toggle("system.autostart", "Mit Windows starten", "")
	auto.changed.connect(func(v: Variant) -> void:
		Helper.run("autostart", { "enable": bool(v), "exe": OS.get_executable_path().replace("/", "\\") })
	)
	_updates()
	_more("Ruhemodus", "Ruhebildschirm, Ruhemodus, Weiterspielen.",
		_option_text(Saver.MINUTES, str(Config.get_value("rest.saver", "10"))), "moon", _rest_page)
	if Config.is_windows() or Library.demo:
		_more("Windows", "WLAN, Bluetooth, Energie, Bild & Ton.", "", "desktop", _windows_page)
	_head("Daten")
	_action("Datenordner", "Ein Ordner „uzai-daten“ neben Uzai.exe macht Uzai portabel.", "Portabel" if Config.portable else Config.data_dir, _data_sheet,
			"folder", "",
			func() -> Control: return Preview.path_box(Config.data_dir)).set_meta("uz_such", "Speicherort Pfad Portabel")
	_more("Speicher", "", StorageFlow.summary(), "drive", _speicher_page).set_meta("uz_such", "Festplatte Platz Speicherort Laufwerk")
	if not _indexing:
		# Vorab im Hintergrund: Wer „Speicher“ öffnet, sieht die Spiele dann gleich.
		StorageFlow.games_auffrischen()
	var backups := Backup.list(Config.data_dir).filter(func(b: Dictionary) -> bool: return not Undo.hides(str(b.path)))
	_more("Sicherungen", "Vor jedem Update sichert Uzai selbst.",
			U.plural(backups.size(), "Sicherung", "Sicherungen") if not backups.is_empty() else "Keine", "folder", _backup_page)
	_head("Hilfe")
	var dk := Doktor.summary(Doktor.cards(DoktorLage.cached()))
	_action("Uzai-Doktor", "", str(dk.text), func() -> void: main.open_doktor(), "pulse", "accent" if int(dk.wichtig) > 0 else "")
	_more("Erste Hilfe", "Die zehn häufigsten Probleme.", "", "info", _erste_hilfe)
	_more("Leistung", "", perf_summary(Perf.rows(_perf_values())), "speed", _perf_page)
	_action("Kurze Tour", "", "", func() -> void: load("res://src/ui/layers/tour.gd").open_for(main), "controller")
	_action("Was ist neu", "", "Version " + Config.VERSION, func() -> void: load("res://src/ui/layers/whats_new.gd").open_for(main), "spark")
	_more("Über Uzai", "", "Version " + Config.VERSION, "info", _info)
	_mehr(_system_mehr)


## Selbst-Update (src/core/updater.gd): wie oft, und je nach Stand „suchen“ oder „einspielen“.
func _updates() -> void:
	_choice("system.updates", "Updates", "Automatisch: lädt im Hintergrund, kommt beim Schließen.",
		[["auto", "Automatisch"], ["melden", "Nur melden"], ["aus", "Aus"]])
	var up: Node = main.updater
	if up == null:
		return
	var bf: String = up.bereit_fassung()
	if bf != "":
		_action("Update einspielen", "Uzai startet dafür neu.", bf, func() -> void: up.jetzt_einspielen(main), "refresh", "accent")
		return
	_action("Nach Updates suchen", update_text(up.zustand, bool(up.laeuft), Config.VERSION), "", func() -> void:
		await up.pruefen(true)
		_rebuild_keep()
	, "refresh")


## Zeile unter „Nach Updates suchen“: was der letzte Blick ergab.
static func update_text(z: Dictionary, laeuft: bool, fassung: String) -> String:
	if laeuft:
		return "Sucht …"
	if str(z.get("fehler", "")) != "":
		return "Zuletzt ging es nicht."
	var neu := str(z.get("neueste", ""))
	if neu != "" and UpdateP.neuer(neu, fassung):
		return "Uzai %s ist da." % neu
	if int(z.get("geprueft", 0)) > 0:
		return "Aktuell."
	return ""


## System › Mehr: Seltenes – Netzsuche, Hinweise, Online-Zimmer, Notfall-Wege, Ausschalten.
func _system_mehr() -> void:
	_toggle("system.search_online", "Suche auch im Netz", "Aus: alles bleibt auf dem PC.")
	_toggle_def("system.doktor_hint", "Hinweis bei Problemen", "Einmal, leise.", true)
	# Der echte Stand (wie online_ui.gd _normal): eingeschaltet und der Hinweis zur IP-Adresse bestätigt.
	var online := bool(Config.get_value("room.online", false)) and bool(Config.get_value("room.online_hinweis", false))
	_action("Zimmer online", "Freunde live in deinem Zimmer", "An" if online else "Aus",
			func() -> void: main.open_layer(load("res://src/room/online_ui.gd").new()), "lock")
	_head("Notfall")
	_action("Fehlerbericht", "QR-Code ohne Namen und Pfade.", "Nach Absturz" if not Config.last_crash.is_empty() else "",
			func() -> void: main.open_crash_report(), "warning")
	if not Config.safe_mode:
		_action("Im Sicheren Modus neu starten", "Mit dem Nötigsten. Deine Einstellungen bleiben.", "", func() -> void: main.restart_uzai(true), "warning")
	_action("Einrichtung erneut starten", "Eingerichtetes bleibt.", "", func() -> void:
		load("res://src/ui/layers/setup_wizard.gd").open_for(main, true), "spark")
	_head("Ausschalten")
	_action("Ausschalten", "", "", func() -> void: main.open_power(), "power")
	_toggle("system.background_wake", "Im Hintergrund bereit bleiben", "Guide-Taste startet Uzai nach dem Schließen.")
	# Rechts die Vorschau wie bei der Startanimation (beim Kürzen der Erklärtexte mit weggefallen).
	_toggle("system.power_off", "Ausschalt-Animation", "",
			func() -> Control: return PowerOff.preview_box(bool(Config.get_value("system.power_off", true))))


## Unterseite „Windows“ (Roadmap 4/16): die Seiten für Bild & Ton, WLAN, Bluetooth und Energie.
## Der Stand rechts ist der zuletzt gelesene (WinEinst.lage), nie eine neue Abfrage beim Aufbau.
func _windows_page() -> void:
	var wl: Dictionary = WinEinst.lage.get("wlan", {})
	var bt: Dictionary = WinEinst.lage.get("bt", {})
	_action("Bild & Ton", "Tonausgabe, Auflösung, Bildrate, HDR.", "", func() -> void: main.open_bild_ton(), "monitor")
	_action("WLAN", "Das Passwort geht direkt an Windows.", ("Verbunden" if str(wl.get("connected", "")) != "" else "Nicht verbunden") if not wl.is_empty()
			else "", func() -> void:
		load("res://src/ui/layers/win_wlan.gd").open_for(main), "wifi")
	_action("Bluetooth", "",
			("An" if str(bt.get("radio", "")) == "an" else "Aus") if not bt.is_empty() else "", func() -> void:
		load("res://src/ui/layers/win_bt.gd").open_for(main), "bluetooth")
	_action("Energie", "Energiesparplan, Bildschirm aus, Schlafen.", "", func() -> void:
		load("res://src/ui/layers/win_energie.gd").open_for(main), "bolt")


## Unterseite „Erste Hilfe“ (Punkt 116, Liste in src/core/trouble.gd): A zeigt die Schritte und
## Knöpfe zu dem, was es dafür in Uzai schon gibt.
func _erste_hilfe() -> void:
	for p in Trouble.FIRST_AID:
		var pd: Dictionary = p
		_action(str(pd.title), str(pd.desc), "", func() -> void: _first_aid(pd), str(pd.icon)).set_meta("uz_key", "hilfe:" + str(pd.title))


func _first_aid(p: Dictionary) -> void:
	var steps := PackedStringArray()
	for i in (p.steps as Array).size():
		steps.append("%d.  %s" % [i + 1, tr(str(p.steps[i]))])
	var buttons: Array = []
	for a in p.actions:
		buttons.append([str(a[0]), _first_aid_go.bind(str(a[1]))])
	buttons.append(["Schließen", func() -> void: pass])
	main.open_dialog(str(p.title), "\n".join(steps), buttons, str(p.icon))


## Knopf aus „Erste Hilfe“: Controller-Test und Tonausgabe legen sich darüber (B kommt zurück);
## Stellen in den Einstellungen schließen die Hilfe und öffnen die Kategorie bzw. Unterseite.
func _first_aid_go(id: String) -> void:
	match id:
		"pad_test":
			main.open_layer(load("res://src/ui/layers/pad_test.gd").new())
		"pad_help":
			load("res://src/ui/layers/pad_help.gd").open_for(main)
		"audio":
			main.open_audio_devices()
		"scan":
			Library.scan(true)
			Toasts.show_toast("Bibliothek wird neu eingelesen", "Neue Spiele erscheinen von selbst.", "refresh")
		"tools":
			_setup_tools()
		"safe":
			main.restart_uzai(true)
		_:
			if not id.begins_with("seite:"):
				return
			var target := id.trim_prefix("seite:")
			var sh = _open_sheet.get_ref() if _open_sheet != null else null
			if sh and is_instance_valid(sh):
				sh.close()
			await get_tree().process_frame
			_show_cat(resolve_sub(target.get_slice("/", 0).get_slice("#", 0)))
			if target.contains("/"):
				# „kategorie/Unterseite#Zeile“: die Unterseite auf und gleich die Zeile darin wählen.
				var more := target.get_slice("/", 1).get_slice("#", 0)
				open_more(more, ("set:%s:%s:%s" % [sub, more, target.get_slice("#", 1)]) if target.contains("#") else "")
			elif target.contains("#"):
				# Erst nach dem Aufbau stehen die Zeilen an ihrem Platz – sonst rollt die Liste nicht hin.
				await get_tree().process_frame
				await get_tree().process_frame
				focus_row("set:%s:%s" % [sub, target.get_slice("#", 1)])
			else:
				var d := Nav.default_in(_list)
				if d:
					Nav.focus(d, true)


## Emulator-Seite von außen öffnen (Karte nach einem Absturz, main._trouble_action).
func open_emulator(eid: String) -> void:
	if not Config.emulator(eid).is_empty():
		_emu_sheet(eid)


## Unterseite „Sicherungen“ (src/core/backup.gd): jetzt sichern, vor Updates sichern, zurückholen.
func _backup_page() -> void:
	_head("Sichern")
	_action("Jetzt sichern", "Enthält Anmeldungen. Nicht weitergeben.", "", func() -> void:
		var r: Dictionary = Backup.create(Config.data_dir, "hand")
		if bool(r.ok):
			Toasts.show_toast("Gesichert", "%s · %s" % [U.plural(int(r.files), "Datei", "Dateien"), Backup.size_text(int(r.bytes))], "check", { "sound": "select" })
		else:
			Toasts.show_toast("Sichern ging nicht", str(r.error), "warning")
		_rebuild_keep()
	, "save", "accent")
	_toggle_def("system.backup_before_update", "Vor jedem Update sichern", "Die letzten %d bleiben." % Backup.KEEP_AUTO, true)
	_head("Zurückholen")
	var list := Backup.list(Config.data_dir).filter(func(b: Dictionary) -> bool: return not Undo.hides(str(b.path)))
	for b in list.slice(0, 12):
		var bd: Dictionary = b
		var when := U.date(int(bd.at)) + ", " + Time.get_time_string_from_unix_time(int(bd.at) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60).left(5)
		var kind := backup_kind(str(bd.name))
		_action(when, kind + " · " + Backup.size_text(int(bd.size)), "Vor Update" if bool(bd.auto) else ("Von Hand" if kind == "Von Hand" else "Automatisch"),
				func() -> void: _backup_options(bd), "clock")


## Unterseite „Speicher“ (src/core/storage.gd, src/ui/storage_flow.gd): Laufwerke mit Belegung,
## installierte Spiele nach Größe, Uzais eigene Daten aufräumen. Spieldateien löscht und verschiebt
## Uzai nie selbst – A auf einem Spiel sagt, wie es der Launcher macht.
func _speicher_page() -> void:
	# Für die Suche nur die festen Zeilen (keine Spiele, keine Arbeit im Hintergrund).
	var games: Array = [] if _indexing else StorageFlow.games_stand()
	if not _indexing:
		# Die Manifeste liest der Hilfsfaden; ist die Liste danach anders, füllt die Seite neu.
		var blatt = _sheet
		StorageFlow.games_auffrischen(func() -> void:
			if blatt != null and is_instance_valid(blatt) and blatt.is_inside_tree() and not blatt.get("_closing"):
				blatt.refill()
		)
		_head("Laufwerke")
		var card := U.vbox(0)
		card.add_child(StorageFlow.drive_card(StorageFlow.drives(games)))
		_container().add_child(card)
		var cr: WeakRef = weakref(card)
		StorageFlow.refresh_drives(func() -> void:
			var c = cr.get_ref()
			if c:
				U.clear(c)
				c.add_child(StorageFlow.drive_card(StorageFlow.drives(games)))
		)
		var known := 0
		for e in games:
			known += maxi(0, int(e.bytes))
		_head("Spiele nach Größe", ("%s zusammen" % P.gb(float(known))) if known > 0 else "")
		if games.is_empty():
			_info_row("Keine Spiele gefunden" if StorageFlow.games_gelesen() else "Wird gelesen …",
				"Nur Spiele von Steam, Epic und der EA app.", "", "games")
		var waiting := {}
		for e in games.slice(0, 60):
			var ed: Dictionary = e
			var store := str(StorageFlow.STORES.get(str(ed.store), ""))
			var val := P.gb(float(ed.bytes)) if int(ed.bytes) > 0 else ("Wird gemessen …" if str(ed.store) == "ea" else "Unbekannt")
			var r = _action(str(ed.title), "Deinstallieren übernimmt %s." % store, val,
				func() -> void: StorageFlow.game_options(main, ed, _rebuild_keep), "games")
			r.subtitle = "%s · %s" % [store, str(ed.drive)] if str(ed.drive) != "" else store
			r.set_meta("uz_key", "speicher:" + str(ed.id))
			if int(ed.bytes) < 0:
				waiting[str(ed.dir)] = weakref(r)
		StorageFlow.measure_ea(games, func(dir: String, bytes: int) -> void:
			var w: WeakRef = waiting.get(dir)
			var row = w.get_ref() if w else null
			if row:
				row.set_value_text(P.gb(float(bytes)))
		)
	_head("Uzai aufräumen", "nur Uzais eigene Daten")
	var rows := {}
	for c in Storage.CLEAN:
		var id := str(c[0])
		var r = _action(str(c[1]), str(c[3]), "…", func() -> void: StorageFlow.ask_clean(main, id, _rebuild_keep), "trash")
		r.set_meta("uz_key", "clean:" + id)
		rows[id] = weakref(r)
	if _indexing:
		return
	StorageFlow.measure_clean(func(id: String, bytes: int, n: int) -> void:
		var row = (rows[id] as WeakRef).get_ref() if rows.has(id) else null
		if row:
			row.set_value_text(Storage.size_text(bytes) if n > 0 else "Leer")
	)


## Unterseite „Leistung“ (src/core/perf.gd): was Uzai auf diesem PC misst, gegen die Ziele.
func _perf_page() -> void:
	_head("Auf diesem PC")
	for r in Perf.rows(_perf_values()):
		# Der Leichte Modus wohnt unter Aussehen; hier nur die Messwerte.
		if str(r[0]) == "Leichter Modus":
			continue
		var row = _info_row(str(r[0]), str(r[2]), str(r[1]), str(r[4]) if r.size() > 4 else ("check" if r[3] == true else ("warning" if r[3] == false else "clock")))
		row.set("tone", "ok" if r[3] == true else ("warn" if r[3] == false else "faint"))
	_action("Jetzt messen", "", "", func() -> void:
		await main.perf.sample()
		_rebuild_keep()
	, "refresh")


func _perf_values() -> Dictionary:
	var p = main.perf if main and "perf" in main else null
	if p == null:
		return {}
	return { "start_ms": p.start_ms, "mem_mb": p.mem_mb, "mem_uzai_mb": p.mem_uzai_mb, "mem_peak_mb": p.mem_peak_mb, "game_cpu": p.game_cpu,
			"menu": p.menu_stats(),
		"light": str(Config.get_value("display.light", "auto")) }


## Kurz für die Zeile „Leistung …“: alles im Ziel, was daneben liegt, oder noch nichts gemessen.
static func perf_summary(rows: Array) -> String:
	var known := rows.filter(func(r: Array) -> bool: return r[3] != null)
	if known.is_empty():
		return "Wird gemessen"
	var off := known.filter(func(r: Array) -> bool: return r[3] == false)
	if off.is_empty():
		return "Im Ziel"
	return str(off[0][0]) + (" und mehr" if off.size() > 1 else "") + " über dem Ziel"


## Art einer Sicherung aus ihrem Namen („Vor dem Update 0.8.2 → 0.8.3“, „Von Hand“).
static func backup_kind(name: String) -> String:
	var tail := name.trim_prefix("uzai-sicherung-").trim_suffix(".zip")
	if tail.contains("-update-"):
		var v := tail.get_slice("-update-", 1).split("-")
		return "Vor dem Update %s → %s" % [v[0], v[1]] if v.size() >= 2 else "Vor einem Update"
	if tail.ends_with("-vor-wiederherstellen"):
		return "Stand vor dem Zurückholen"
	return "Von Hand"


func _backup_options(b: Dictionary) -> void:
	main.open_dialog("Diese Sicherung zurückholen?", "Uzai startet neu mit dem Stand vom %s. Der jetzige Stand wird vorher gesichert." % U.date(int(b.at)), [
		["Zurückholen und neu starten", func() -> void:
			if Backup.schedule_restore(Config.data_dir, str(b.path)):
				main.restart_uzai()
			else:
				Toasts.show_toast("Zurückholen ging nicht", "Sicherung nicht gefunden. Eine andere wählen.", "warning")],
		["Löschen", func() -> void:
			# Erst nach ein paar Sekunden wirklich weg (Rückgängig), bis dahin nur ausgeblendet.
			Undo.offer_files("Sicherung gelöscht", U.date(int(b.at)), "trash", [str(b.path)], "backup", _rebuild_keep)],
		["Abbrechen", func() -> void: pass],
	], "folder")


## Ruhebildschirm (src/core/saver.gd): wann er kommt.
func _saver_row() -> Control:
	return _choice("rest.saver", "Ruhebildschirm", "Bilder deiner Spiele, nie im Spiel oder Video.", Saver.MINUTES)


## Unterseite „Ruhemodus“ (src/core/rest.gd, src/core/quick_resume.gd, src/core/saver.gd).
func _rest_page() -> void:
	_head("Ruhebildschirm")
	_saver_row()
	_choice("rest.saver_motion", "Bewegung", "", [["fahrt", "Kamerafahrt"], ["ruhig", "Nur überblenden"]])
	_choice("rest.saver_shots", "Bilder", "", [[false, "Nur Spiele"], [true, "Spiele und Bildschirmfotos"]])
	_choice("rest.saver_rest", "Danach Ruhemodus", "", Saver.REST_AFTER)
	_action("Vorschau", "", "", func() -> void: main.saver.start(true), "image")
	_head("Ruhemodus")
	_toggle("rest.screen_off", "Bildschirm ausschalten", "Aus: nur Diashow.")
	_toggle("rest.mute", "Spiel stumm schalten", "")
	_choice("rest.pc_suspend", "PC-Spiele im Ruhemodus anhalten", "Spiele mit Anti-Cheat laufen weiter.", [["safe", "Nur ohne Anti-Cheat"], ["off", "Aus"]])
	_toggle("rest.pads_off", "Controller ausschalten", "Kabellose Xbox-Controller. Die Xbox-Taste weckt.")


func _info() -> void:
	_container().add_child(_about_card())
	_info_row("Lizenz von Uzai", "Freie Software unter der GNU General Public License 3.0: Du darfst Uzai nutzen, weitergeben und verändern. Wer eine veränderte Fassung weitergibt, muss ihren Quelltext ebenfalls offenlegen. Quelltext und vollständiger Lizenztext (LICENSE) auf GitHub.",
			"GPL-3.0", "info")
	_info_row("Menüklänge", "Selbst erzeugt (tools/synth.py, synth_tick.py, synth_klang2.py), keine Aufnahmen und keine fremden Samples.", "wie Uzai", "info")
	_head("Fremde Software")
	_info_row("IBM Plex Sans", "Die Schrift von Uzai, Titel und Wortmarke in IBM Plex Sans Condensed. IBM Corp., SIL Open Font License 1.1.", "OFL 1.1",
			"info")
	_info_row("Hanken Grotesk", "Wahlweise für alles. The Hanken Grotesk Project Authors, SIL Open Font License 1.1.", "OFL 1.1", "info")
	_info_row("Atkinson Hyperlegible", "Atkinson Hyperlegible Next und Mono, Braille Institute, SIL Open Font License 1.1.", "OFL 1.1", "info")
	_info_row("Saira", "Für Titel und Bedienung (wahlweise). Omnibus-Type, SIL Open Font License 1.1.", "OFL 1.1", "info")
	_info_row("Godot Engine", "Uzai ist mit Godot 4 gebaut.", "MIT", "info")
	_info_row("Characters PSX",
			"Die Figuren im Zimmer: „Characters PSX“ von Elbolilloduro (elbolilloduro.itch.io), Modelle und Texturen unverändert. Herkunft und SHA-256 in assets/figur/LIZENZ.txt.",
			"Lizenz des Autors", "info")
	_info_row("ambientCG",
			"Dielen, Marmor, Fliesen und Messing im Zimmer: Oberflächen von ambientCG (ambientcg.com), über github.com/pmndrs/market-assets. Herkunft und SHA-256 in assets/zimmer/LIZENZ.txt.",
			"CC0", "info")
	_info_row("Khronos glTF Sample Assets",
			"Samtsofa, Ledersofa, Sessel, Lampen, Blattpflanze, Vase, Tasse, Radio und Spielzeugauto im Zimmer (Wayfair, Khronos Group, DGG, Microsoft u. a.), ohne Etiketten. Herkunft, Urheber und SHA-256 in assets/zimmer/LIZENZ.txt.",
			"CC0 / CC BY 4.0", "info")
	_info_row("Discord Social SDK",
			"Für Discord-Nachrichten und Freunde. Discord Inc., liegt neben Uzai.exe; Uzai lädt sie nur mit gültiger Signatur von Discord.",
			"Discord-Bedingungen", "info")
	_info_row("Microsoft Edge WebView2 SDK",
			"Kern des Browsers: Microsoft.Web.WebView2.Core.dll und WebView2Loader.dll aus dem NuGet-Paket 1.0.4258.31, Microsoft Corporation. Herkunft und SHA-256 in assets/browser/webview2/LIZENZ.txt; die WebView2-Laufzeit gehört zu Windows.",
			"BSD-artig (Microsoft)", "browser")
	_info_row("EasyList, EasyPrivacy, EasyList Cookie",
			"Werbe- und Tracker-Blocker des Browsers: Fanboy, MonztA, Khrin, Yuki2718 und Beitragende (easylist.to), umgebaut in Uzais Format. Die umgebaute Liste (filter.gz) steht selbst unter CC BY-SA 3.0; Herkunft in assets/browser/filter/LIZENZ.txt.",
			"CC BY-SA 3.0", "browser")
	_info_row("CryptoJS",
			"Verschlüsselung für Erweiterungen der Filme-Quellen (Plugins), Jeff Mott und Beitragende. Lizenztext in assets/plugins/crypto-js-LICENSE.txt.",
			"MIT", "lock")
	_info_row("libsecp256k1",
			"Signatur für den Treffpunkt von „Zimmer online“ (bitcoin-core, v0.7.1, nur schnorrsig/extrakeys). Selbst gebaut, läuft nur in der Abschottung. Herkunft und SHA-256 in assets/net/LIZENZ.txt.",
			"MIT", "lock")
	_info_row("libdatachannel, libjuice, usrsctp, Mbed TLS",
			"Datenkanal für „Zimmer online“ (libdatachannel v0.24.6, libjuice v1.7.4, usrsctp, Mbed TLS v3.6.7, plog). Selbst gebaut, läuft nur in der Abschottung. Quellen, Herkunft und SHA-256 in assets/net/LIZENZ.txt.",
			"MPL-2.0 / BSD / Apache-2.0", "lock")
	_info_row("ShaderGlass", "Wird als eigenes Programm gestartet, nicht in Uzai eingebaut (mausimus).", "GPL-3.0", "tv")
	_info_row("yt-dlp", "Holt YouTube-Videos. Wird als eigenes Programm geladen und gestartet.", "Unlicense", "video")
	_info_row("mpv", "Spielt Videos ab. Wird als eigenes Programm geladen und gestartet.", "GPL / LGPL", "video")
	_info_row("Deno", "Hilft yt-dlp beim Abrufen. Wird als eigenes Programm geladen.", "MIT", "video")
	_info_row("SponsorBlock", "Freie Datenbank für gesponserte Abschnitte, sponsor.ajay.app. Daten unter CC BY-NC-SA 4.0.", "CC BY-NC-SA", "skip")
	_info_row("LRCLIB", "Freie Datenbank für Liedtexte, lrclib.net.",
			"Liedtexte", "subtitles")
