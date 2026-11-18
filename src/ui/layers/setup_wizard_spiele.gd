extends "res://src/ui/layers/setup_wizard_start.gd"
## Einrichtung, Schicht über setup_wizard_start.gd: Spiele – Launcher, Spieleordner und Emulatoren
## suchen, finden und übernehmen; der Höhepunkt der Einrichtung (Zähler, Cover, Schilder).

const Arbeit := preload("res://src/core/arbeit.gd")
const TrackPage := preload("res://src/ui/components/track_page.gd")
const RomScanner := preload("res://src/library/rom_scanner.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const LauncherSites := preload("res://src/library/launcher_sites.gd")
const RetroAuto := preload("res://src/core/retro_auto.gd")
const EmuSuche := preload("res://src/core/emu_suche.gd")
const Logos := preload("res://src/core/badge_logos.gd")
const SpieleScrapen := preload("res://src/ui/layers/spiele_scrapen.gd")

var _zahl: Label                 ## Spiele: der große Zähler
var _zahl_satz: Label
var _lauf: _Fortschritt
var _schilder: HBoxContainer
var _schild_n := {}              ## Quelle → Zahl im Schild
var _regal: Control              ## Platz der Cover-Reihe (Bühne)
var _leer_satz: Label            ## keine Spiele: ruhige Zeile statt leerer Reihe
var _zaehl := Vector2.ZERO       ## Zähler: [Lage, Tempo] (E.zaehlen)
var _fertig_gemeldet := false
var _ziel := { "n": 0, "quellen": [] }   ## zuletzt gelesen (_spiele_ziel)
var _ziel_t := 0.0
var _scrape_r: Control           ## Zeile „Spiele scrapen“: ihr Stand läuft mit (_spiele_tick)

static var _find := {}           ## Suche nach Emulatoren/Spieleordnern: { state, emus, dirs, applied }
static var _scrape_auto := false  ## einmal von selbst gescrapt (Spiele scrapen)
static var _picks := {}          ## gefundener Eintrag → übernehmen ja/nein


# --- 4 Spiele -------------------------------------------------------------------------------

## Der Höhepunkt: oben groß der Zähler, der mit jedem gefundenen Spiel hochläuft; mit ihm fliegen
## die Cover einzeln und gestaffelt in die Reihe der Bühne (einrichtung_buehne.gd: Tiefe, Glanz beim
## Landen, Klang Stufe um Stufe), darüber erscheint je Quelle ihr Schild
## (Steam, Epic, PS2 … – mit echtem Logo, wenn es da ist). Unten, was die Suche an Emulatoren und
## Spieleordnern gefunden hat (vorgewählt, A wählt ab), und ein Ordner von Hand. „Weiter“ ist gewählt.
func _spiele() -> void:
	var col := _mitte()
	_zahl = Label.new()
	_zahl.text = "0"
	# Der Zähler läuft durch Hunderte Zahlen: jede wäre für die Übersetzung ein neuer Text.
	_zahl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_zahl.add_theme_font_override("font", UzTheme.display("title"))
	_zahl.add_theme_font_size_override("font_size", 132)
	_zahl.add_theme_color_override("font_color", UzTheme.col("text"))
	_zahl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zahl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zahl.set_meta("uz_titel", true)
	col.add_child(_zahl)
	_zahl_satz = U.label("Uzai sucht …", "l", "muted", "regular")
	_zahl_satz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_zahl_satz)
	col.add_child(U.spacer(0, 14, false))
	_lauf = _Fortschritt.new()
	_lauf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_lauf)
	col.add_child(U.spacer(0, 14, false))
	_schilder = U.hbox(12)
	_schilder.alignment = BoxContainer.ALIGNMENT_CENTER
	_schilder.custom_minimum_size = Vector2(0, 46)
	_schilder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_schilder)
	_schild_n = {}
	_leer_satz = U.label("Uzai liest neue Spiele jederzeit ein.", "m", "muted", "regular")
	_leer_satz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leer_satz.visible = false
	col.add_child(_leer_satz)
	col.add_child(U.spacer(0, 26, false))
	var regal := Control.new()
	regal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	regal.custom_minimum_size = Vector2(PAGE_W, 220)
	col.add_child(regal)
	_regal = regal
	# Neue Cover kommen aus der Tiefe der Mitte und wachsen nach außen (nicht quer über Zähler und
	# Schilder); hinter dem Zähler wächst ein Schein mit der Zahl.
	_buehne.regal(regal)
	_buehne.zaehler(_zahl)
	col.add_child(U.spacer(0, 26, false))
	# Unten die Funde: mittig, scrollt für sich.
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.custom_minimum_size = Vector2(LEFT_W, 120)
	sc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	# Unten läuft die Liste weich aus statt hart abgeschnitten zu werden.
	var maske := TrackPage.fade_mask(col)
	maske.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	maske.custom_minimum_size = Vector2(LEFT_W, 120)
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	maske.add_child(sc)
	var left := U.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(left)
	# Fehlt ein Launcher, steht oben, wo es ihn offiziell gibt (erscheint nach dem Einlesen).
	var lb := { "box": U.vbox(0), "shown": "" }
	left.add_child(lb.box)
	_live.append(func() -> void: _fill_launchers(lb))
	var frows := _card(left)
	var fb := { "rows": frows, "shown": "" }
	_live.append(func() -> void: _fill_found(fb))
	_start_find()
	var mrows := _card(left)
	var again = _row(mrows, "action", "Noch einmal suchen", "", "")
	again.icon_name = "refresh"
	again.on_activate = func() -> void:
		_find = {}
		_start_find()
		Library.scan(true)
		_tick()
	col.add_child(U.spacer(0, 22, false))
	_default = _fuss_mitte(col)
	_zaehl = Vector2(0.0, 0.0)
	_ziel_t = 0.0
	_fertig_gemeldet = false
	if not resume.is_empty():
		# Nach einem Neuaufbau steht alles sofort da (kein zweites Hochzählen).
		_zaehl = Vector2(float(_spiele_ziel().n), 0.0)
	_spiele_tick(0.0)
	if resume.is_empty():
		_steigen([_zahl, _zahl_satz], U.T_ANTWORT)


## Jedes Bild: Zähler (Feder, E.zaehlen) und Regal der Bühne. Was gefunden ist (Bibliothek, Funde,
## Fortschritt, Schilder), liest sie nur fünfmal je Sekunde – große Bibliotheken kosten so nichts.
func _spiele_tick(dt: float) -> void:
	if not is_instance_valid(_zahl):
		return
	_ziel_t -= dt
	if _ziel_t <= 0.0 or dt <= 0.0:
		_ziel_t = 0.2
		_ziel = _spiele_ziel()
		var st := _search_state()
		_lauf.set_pct(float(st.pct), bool(st.done))
		var n0 := int(_ziel.n)
		# Nichts gefunden: keine leere Reihe und keine leeren Schilder – eine ruhige Zeile, darunter
		# gleich, was fehlt (Launcher, Ordner hinzufügen, noch einmal suchen).
		var leer := spiele_leer(bool(st.done), n0)
		_schilder.visible = not leer
		_regal.visible = not leer
		_leer_satz.visible = leer
		if bool(st.done):
			_zahl_satz.text = ("Spiel gefunden" if n0 == 1 else "Spiele gefunden") if n0 > 0 else "Keine Spiele gefunden"
			if not _fertig_gemeldet:
				_fertig_gemeldet = true
				if resume.is_empty():
					Sfx.play("toggle_on")
		else:
			_zahl_satz.text = "Uzai sucht …"
		for q in _ziel.quellen:
			_schild(q)
		# Cover kommen beim ersten Mal erst während der Suche (Libretro, für die Bühne geholt): Der Stand der Zeile
		# „Spiele scrapen“ zieht mit, statt bei dem zu bleiben, was beim Aufbau galt.
		if is_instance_valid(_scrape_r):
			var stand := scrape_stand(Media.sgdb_running, Media.scrape_spiele().size(), Media.scrape_fehlt())
			if str(_scrape_r.get("value_text")) != stand:
				_scrape_r.set("value_text", stand)
	if dt > 0.0:
		_zaehl = E.zaehlen(_zaehl.x, _zaehl.y, float(_ziel.n), dt)
	var n := int(round(_zaehl.x))
	if _zahl.text != str(n):
		_zahl.text = str(n)
	_buehne.zeigen(n)


## Ist die Suche fertig und nichts gefunden (leerer Zustand des Spiele-Schritts)?
static func spiele_leer(fertig: bool, n: int) -> bool:
	return fertig and n <= 0


## Was der Zähler zeigen soll: Spiele in der Bibliothek plus die in gefundenen (noch nicht
## übernommenen) Spieleordnern, dazu die Schilder je Quelle (E.quellen).
func _spiele_ziel() -> Dictionary:
	var c := _game_counts()
	var launcher: Array = [["steam", "Steam", int(c.steam)], ["epic", "Epic", int(c.epic) + int(c.epic_owned)], ["ea", "EA", int(c.ea)]]
	for id in Library.Stores.EXTRA:
		launcher.append([id, Library.Stores.name_of(id, true), int(c.get(id, 0))])
	launcher.append(["pc", "PC", int(c.pc)])
	var sys := {}
	for g0 in Library.games:
		var g: Dictionary = g0
		if g.get("hidden", false) or str(g.get("dupe_of", "")) != "" or g.get("missing", false) or str(g.get("source", "")) != "rom":
			continue
		var sid := str(g.get("system", ""))
		sys[sid] = int(sys.get(sid, 0)) + 1
	var extra := 0
	if str(_find.get("state", "")) == "fertig" and not bool(_find.get("applied", false)):
		for d in _find.get("dirs", []):
			if bool(_picks.get("dir:" + str(d.system), true)):
				sys[str(d.system)] = int(sys.get(str(d.system), 0)) + int(d.get("count", 0))
				extra += int(d.get("count", 0))
	var systeme: Array = []
	for sid in sys.keys():
		systeme.append([sid, str(Config.system(str(sid)).get("short", sid)), int(sys[sid])])
	var total := extra
	for k in c.keys():
		total += int(c[k])
	return { "n": total, "quellen": E.quellen(launcher, systeme) }


## Ein Schild je Quelle: echtes Logo (einfarbig in Schriftfarbe), sonst der Name, dahinter die Zahl.
## Neue steigen W_ANSTOSS von unten herein; die Zahl darin ändert sich still.
func _schild(q: Dictionary) -> void:
	var id := str(q.id)
	if _schild_n.has(id):
		var lab: Label = _schild_n[id]
		if is_instance_valid(lab):
			lab.text = str(int(q.n))
		return
	if _schild_n.size() >= 8:
		return
	var p := PanelContainer.new()
	var sb := UzTheme.flaeche(UzTheme.col("surface_hi"), UzTheme.r_pill())
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := U.hbox(12)
	p.add_child(h)
	var got := Logos.line_logo(Logos.source_key(id), 20.0, 104.0)
	if not got.is_empty():
		var tr_ := TextureRect.new()
		tr_.texture = got.tex
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr_.custom_minimum_size = got.size
		tr_.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr_.modulate = UzTheme.col("text")
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tr_)
	else:
		var nm := U.label(str(q.name), "m", "text", "bold")
		nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		h.add_child(nm)
	var cnt := U.label(str(int(q.n)), "m", "muted", "medium")
	cnt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # nur eine Zahl
	h.add_child(cnt)
	_schild_n[id] = cnt
	_schilder.add_child(p)
	if resume.is_empty() and not U.reduziert():
		p.modulate.a = 0.0
		var tw := U.ankommen(p, U.T_RAUM, "uz_schild")
		tw.tween_property(p, "modulate:a", 1.0, U.T_RAUM)
		Sfx.play("tick")


func _fill_launchers(lb: Dictionary) -> void:
	var box: VBoxContainer = lb.box
	if not is_instance_valid(box):
		return
	var enabled := {}
	for id in LauncherSites.ORDER:
		enabled[id] = bool(Config.get_value("library.%s_enabled" % id, true))
	var miss := LauncherSites.missing(Library.launchers, enabled, Library.launcher_need)
	var sig := ",".join(PackedStringArray(miss))
	if sig == str(lb.shown):
		return
	lb.shown = sig
	var had := box.is_ancestor_of(Nav.focused()) if Nav.focused() else false
	for ch in box.get_children():
		ch.queue_free()
		box.remove_child(ch)
	if miss.is_empty():
		if had:
			_focus_default()
		return
	_head(box, "Fehlt noch", "kostenlos beim Anbieter")
	var rows := _card(box)
	for id in miss:
		var s := LauncherSites.site(str(id))
		var r = _row(rows, "action", str(s.name), "Nicht gefunden",
			"%s fehlt, damit fehlen %s. Download auf der offiziellen Seite." % [str(s.name), str(s.what)])
		r.icon_name = str(s.icon)
		r.value_text = "Offizielle Seite"
		r.tone = "accent"
		var lid := str(id)
		r.on_activate = func() -> void: main.open_launcher_offer(lid)
	box.add_child(U.spacer(0, 8, false))


func _focus_default() -> void:
	var d := Nav.default_in(_page) if is_instance_valid(_page) else null
	if d:
		Nav.focus(d, true)


func _game_counts() -> Dictionary:
	var c := { "steam": 0, "epic": 0, "epic_owned": 0, "ea": 0, "emu": 0, "pc": 0 }
	for id in Library.Stores.EXTRA:
		c[id] = 0
	for g0 in Library.games:
		var g: Dictionary = g0
		# Doppelte (dasselbe Spiel in zwei Launchern) zählen einmal, wie in der Bibliothek.
		if g.get("hidden", false) or str(g.get("dupe_of", "")) != "" or g.get("missing", false):
			continue
		var sys := str(g.get("system", ""))
		var inst := Library.is_installed(g)
		if sys == "steam":
			if inst:
				c.steam += 1
		elif sys == "epic":
			if inst:
				c.epic += 1
			else:
				c.epic_owned += 1
		elif sys == "ea":
			c.ea += 1
		elif Library.Stores.is_extra(sys):
			c[sys] = int(c[sys]) + 1
		elif sys == "pc":
			c.pc += 1
		elif str(g.get("source", "")) == "rom":
			c.emu += 1
	return c


func _summary_games(c: Dictionary) -> Dictionary:
	var out := { "steam": c.steam, "epic": int(c.epic) + int(c.epic_owned), "ea": c.ea, "emu": c.emu, "pc": c.pc }
	for id in Library.Stores.EXTRA:
		out[id] = int(c.get(id, 0))
	return out


## Wie weit die Suche ist (E.search_progress): { pct, done } für die Linie unter dem Zähler.
func _search_state() -> Dictionary:
	var p := { "launcher": "läuft" if Library.scanning else "fertig", "state": str(_find.get("state", "")) }
	if _find.has("lock"):
		(_find.lock as Mutex).lock()
		for k in ["emu_done", "emu_total", "dir_done", "dir_total"]:
			p[k] = int(_find.get(k, 0))
		(_find.lock as Mutex).unlock()
	var pr := E.search_progress(p)
	return { "pct": float(pr.pct), "done": bool(pr.done) }


## Suchen im Hintergrund (Dateisystem, nur lesen): Emulatoren ohne Programmdatei und Spieleordner.
func _start_find() -> void:
	if str(_find.get("state", "")) != "":
		return
	var env := search_env()
	var drives := _drives()
	var systems := Config.systems()
	var emus: Array = []
	for e in Config.emulators():
		var exe := str(e.get("exe", ""))
		if exe == "" or not FileAccess.file_exists(exe):
			emus.append({ "id": str(e.id), "name": str(e.get("name", e.id)), "exe_hint": str(e.get("exe_hint", "")), "systems": e.get("systems", []) })
	var libs: Array = SteamScanner.library_dirs(Library.steam_root()) if Library.steam_root() != "" else []
	var taken := {}
	var dirs: Dictionary = Config.get_value("library.rom_dirs", {})
	for k in dirs.keys():
		if str(dirs[k]) != "":
			taken[str(k)] = true
	# Alle Felder schon jetzt: Der Faden schreibt nur Werte (unter dem Schloss), nie neue Schlüssel.
	var box := { "state": "läuft", "emus": [], "dirs": [], "emu_done": 0, "emu_total": 0, "dir_done": 0, "dir_total": 0, "where": "",
		"weiter": false, "lock": Mutex.new() }
	_find = box
	Zustand.melden("einrichtung.suche", "läuft")
	_find_go(self, box, drives, env, systems, emus, libs, taken)


## Hinweise holen, dann suchen – statisch: Baut sich die Oberfläche währenddessen neu (die Ebene
## geht und kommt wieder), läuft die Suche trotzdem an. Früher blieb sie dann ohne Faden auf
## „läuft“ stehen, und die neue Ebene zeigte für immer „Suche läuft …“. Danach wartet es auf das
## Ende des Fadens und schließt die Suche ab (_find_fertig), egal welcher Schritt zu sehen ist.
static func _find_go(n: Node, box: Dictionary, drives: Array, env: Dictionary, systems: Array, emus: Array, libs: Array,
		taken: Dictionary) -> void:
	# Was Windows weiß (Deinstallations-Einträge, laufende Programme): vom Helfer, nur gelesen.
	var hints: Dictionary = await emu_hints(n) if not emus.is_empty() else {}
	box["task"] = _spawn(box, drives, env, systems, emus, libs, taken, hints)
	var tree := Engine.get_main_loop() as SceneTree
	while tree != null and str(box.get("state", "")) == "läuft" and not _find_fertig(box):
		await tree.process_frame


## Ist der Faden durch, gilt die Suche als fertig. Früher sah das nur die Liste im Schritt Spiele:
## Wer vor dem Ende weiterging, behielt „läuft“ für immer – die Funde kamen nie in die Einstellungen,
## und „Ordner hinzufügen …“ im Schritt Emulatoren tat nichts. Ging es schon weiter („Weiter“
## während der Suche), übernimmt es die Funde jetzt. true = fertig.
static func _find_fertig(box: Dictionary) -> bool:
	if str(box.get("state", "")) == "läuft" and box.has("task") and (box.task as Arbeit.Auftrag).fertig:
		box.erase("task")
		box["state"] = "fertig"
		if is_same(box, _find):
			Zustand.melden("einrichtung.suche", "fertig")
			if bool(box.get("weiter", false)):
				_apply_found()
	return str(box.get("state", "")) == "fertig"


## Umgebung für die Suche (Benutzerordner, Programme, Scoop …).
static func search_env() -> Dictionary:
	var env := {}
	for k in ["USERPROFILE", "LOCALAPPDATA", "APPDATA", "ProgramFiles", "ProgramFiles(x86)", "ProgramData", "PUBLIC", "SCOOP"]:
		env[k] = OS.get_environment(k)
	return env


## Hinweise des Helfers für die Emulator-Suche (src/core/emu_suche.gd), höchstens ein paar Sekunden
## warten – sonst sucht Uzai ohne sie.
static func emu_hints(n: Node) -> Dictionary:
	if not Config.is_windows() or not Helper.available:
		return {}
	var hb := { "done": false, "res": {} }
	var go := func() -> void:
		var r: Dictionary = await Helper.run_once("emu-hints", { "timeout": 20 })
		var res: Variant = r.get("result", {})
		hb.res = res if bool(r.get("ok", false)) and res is Dictionary else {}
		hb.done = true
	go.call()
	var t0 := Time.get_ticks_msec()
	# Ebene weg (Neuaufbau): weiter warten, über den Baum selbst – sonst fehlten die Hinweise.
	var tree := n.get_tree() if is_instance_valid(n) and n.is_inside_tree() else Engine.get_main_loop() as SceneTree
	while not bool(hb.done) and Time.get_ticks_msec() - t0 < 8000 and tree != null:
		await tree.process_frame
	return hb.res


## Die Suche im Hintergrund starten (ohne Bezug auf die Ebene: sie darf inzwischen weg sein).
static func _spawn(box: Dictionary, drives: Array, env: Dictionary, systems: Array, emus: Array, libs: Array, taken: Dictionary,
		hints: Dictionary = {}) -> Arbeit.Auftrag:
	return Arbeit.auftrag(_suchen.bind(box, drives, env, systems, emus, libs, taken, hints), Arbeit.LANG)


static func _suchen(box: Dictionary, drives: Array, env: Dictionary, systems: Array, emus: Array, libs: Array, taken: Dictionary,
		hints: Dictionary) -> void:
	var res := _find_all(drives, env, systems, emus, libs, taken, box, hints)
	(box.lock as Mutex).lock()
	box["emus"] = res.emus
	box["dirs"] = res.dirs
	(box.lock as Mutex).unlock()


static func _drives() -> Array:
	var over := Config.probe_env("UZAI_SETUP_DRIVES")   # Proben/Tests: eigene Suchorte
	if over != "":
		return Array(over.split(";", false))
	var out: Array = []
	if OS.get_name() == "Windows":
		for i in DirAccess.get_drive_count():
			var d := DirAccess.get_drive_name(i)
			if d.to_upper() in ["A:", "B:"]:
				continue
			out.append(d)
	return out


## box (freiwillig): Fortschritt { emu_done, emu_total, dir_done, dir_total, where, lock }.
static func _find_all(drives: Array, env: Dictionary, systems: Array, emus: Array, libs: Array, taken: Dictionary, box: Dictionary = {},
		hints: Dictionary = {}) -> Dictionary:
	var eroots: Array = E.emu_roots(drives, env).filter(func(p): return DirAccess.dir_exists_absolute(str(p)))
	var rroots: Array = E.rom_roots(drives, env).filter(func(p): return DirAccess.dir_exists_absolute(str(p)))
	var cands: Array = emus.map(func(e: Dictionary) -> Array: return E.emu_candidates(e, eroots, libs))
	var total := 0
	for cl in cands:
		total += (cl as Array).size()
	var report := func(k: String, v: int, where: String) -> void:
		if not box.has("lock"):
			return
		(box.lock as Mutex).lock()
		box[k] = v
		if where != "":
			box["where"] = where
		(box.lock as Mutex).unlock()
	# Danach die breite Suche (EmuSuche): Ordner zählen mit, höchstens MAX_DIRS.
	report.call("emu_total", total + EmuSuche.MAX_DIRS, "")
	report.call("dir_total", rroots.size(), "")
	# Proben: langsamer suchen, damit der Fortschritt zu sehen ist (ms je Ort).
	var slow := Config.probe_env("UZAI_SETUP_SLOW").to_int()
	var found_emus: Array = []
	var done := 0
	var rest: Array = []
	for i in emus.size():
		var e: Dictionary = emus[i]
		var cl: Array = cands[i]
		var hit := false
		for j in cl.size():
			var p := str(cl[j])
			if FileAccess.file_exists(p):
				found_emus.append({ "id": str(e.id), "name": str(e.name), "exe": p, "systems": e.systems })
				hit = true
				break
		if not hit:
			rest.append(e)
		done += cl.size()
		report.call("emu_done", done, str(cl[0]).get_base_dir() if not cl.is_empty() else "")
		if slow > 0:
			OS.delay_msec(mini(slow, 2000))
	# Nicht am üblichen Platz: Startmenü, Registry, laufende Programme und eigene Ordner (begrenzt).
	if not rest.is_empty():
		var walked := [0]
		var on_dir := func(p: String) -> void:
			walked[0] = int(walked[0]) + 1
			if int(walked[0]) % 40 == 0:
				report.call("emu_done", done + int(walked[0]), p)
		var more := EmuSuche.find(rest, E.ALT_EXE, drives, env, libs, hints, {}, on_dir)
		for e in rest:
			if more.has(str(e.id)):
				found_emus.append({ "id": str(e.id), "name": str(e.name), "exe": str(more[str(e.id)].exe), "systems": e.systems })
	report.call("emu_done", total + EmuSuche.MAX_DIRS, "")
	var list_dirs := func(q: String) -> Array: return EmuSuche.dirs_at(q)
	var by_id := {}
	for s in systems:
		by_id[str(s.id)] = s
	var found_dirs: Array = []
	var seen := taken.duplicate()
	for ri in rroots.size():
		report.call("dir_done", ri, str(rroots[ri]))
		if slow > 0:
			OS.delay_msec(mini(slow, 2000))
		for d in E.find_rom_dirs([rroots[ri]], systems, list_dirs, seen):
			seen[d.system] = true
			var n := RomScanner.scan(by_id[d.system], str(d.dir)).size()
			if n > 0:
				d["count"] = n
				d["name"] = str(by_id[d.system].get("name", d.system))
				found_dirs.append(d)
	report.call("dir_done", rroots.size(), "")
	return { "emus": found_emus, "dirs": found_dirs }


## Die Funde als Zeilen (A wählt ab/an, „Weiter“ übernimmt).
func _fill_found(fb: Dictionary) -> void:
	var rows: VBoxContainer = fb.rows
	if not is_instance_valid(rows):
		return
	var state := str(_find.get("state", ""))
	if _find_fertig(_find):
		state = "fertig"
	var retro := _retro_fehlt() if state == "fertig" else {}
	var schon := schon_eingerichtet() if state == "fertig" else {}
	var sig := "%s|%d|%d|%s|%s|%s|%s" % [state, (_find.get("emus", []) as Array).size(), (_find.get("dirs", []) as Array).size(), str(_find.get("applied", false)),
			str(retro.get("text", "")), str(_find.get("folder_busy", false)), str(schon)]
	if sig == str(fb.shown):
		return
	fb.shown = sig
	var had := rows.is_ancestor_of(Nav.focused()) if Nav.focused() else false
	var keep := str(Nav.focused().get_meta("uz_key", "")) if had else ""
	for ch in rows.get_children():
		ch.queue_free()
		rows.remove_child(ch)
	if state != "fertig":
		var r = _row(rows, "info", "Suche läuft …", "Emulatoren und Spieleordner",
				"Übliche Ordner auf allen Laufwerken.")
		r.icon_name = "search"
		return
	var emus: Array = _find.get("emus", [])
	var dirs: Array = _find.get("dirs", [])
	var applied := bool(_find.get("applied", false))
	# The search only covers what is still missing; whatever is already set up is listed on top. Otherwise the
	# row would say no emulators were found although all of them are already set up.
	if not schon.is_empty():
		var rs = _row(rows, "info", "Alles eingerichtet" if emus.is_empty() and dirs.is_empty() else "Schon eingerichtet",
				str(schon.text), str(schon.names))
		rs.icon_name = "check"
		rs.value_text = "Bereit"
		rs.tone = "ok"
	if emus.is_empty() and dirs.is_empty():
		if schon.is_empty():
			var r2 = _row(rows, "info", "Keine Emulatoren oder Spieleordner", "", "Ordner wählen oder später unter Einstellungen → Emulation.")
			r2.icon_name = "info"
		_retro_offer(rows, retro)
		_folder_row(rows)
		return
	for e in emus:
		var k := "emu:" + str(e.id)
		var r3 = _row(rows, "info" if applied else "toggle", str(e.name), str(e.exe).replace("/", "\\"),
				"Emulator für %s." % ", ".join(PackedStringArray((e.systems as Array).map(func(s): return str(
				Config.system(str(s)).get("short", s))))), bool(_picks.get(k, true)))
		r3.icon_name = "chip"
		r3.set_meta("uz_key", "su:f:" + k)
		if applied:
			r3.value_text = "Übernommen" if bool(_picks.get(k, true)) else "Nicht übernommen"
			r3.tone = "ok" if bool(_picks.get(k, true)) else "faint"
		else:
			r3.changed.connect(func(v: Variant) -> void: _picks[k] = bool(v))
	for d in dirs:
		var k2 := "dir:" + str(d.system)
		var r4 = _row(rows, "info" if applied else "toggle", "%s · %s" % [str(d.name), U.plural(int(d.count), "Spiel", "Spiele")], str(d.dir).replace("/", "\\"),
				"Spieleordner für %s." % str(d.name), bool(_picks.get(k2, true)))
		r4.icon_name = "folder"
		r4.set_meta("uz_key", "su:f:" + k2)
		if applied:
			r4.value_text = "Übernommen" if bool(_picks.get(k2, true)) else "Nicht übernommen"
			r4.tone = "ok" if bool(_picks.get(k2, true)) else "faint"
		else:
			r4.changed.connect(func(v: Variant) -> void: _picks[k2] = bool(v))
	_retro_offer(rows, retro)
	_folder_row(rows)
	_scrape_row(rows)
	if had:
		for c in Nav.focusables(rows):
			if str(c.get_meta("uz_key", "")) == keep:
				Nav.focus(c, true)
				return
		var d0 := Nav.default_in(rows)
		if d0:
			Nav.focus(d0, true)


## Was schon da ist (Emulatoren mit Programmdatei, Spieleordner): { text, names } oder {}.
static func schon_eingerichtet() -> Dictionary:
	var names := PackedStringArray()
	for e in Config.emulators():
		var exe := str(e.get("exe", ""))
		if exe != "" and FileAccess.file_exists(exe):
			names.append(str(e.get("name", e.id)))
	var nd := 0
	var dirs: Dictionary = Config.get_value("library.rom_dirs", {})
	for k in dirs.keys():
		if str(dirs[k]) != "":
			nd += 1
	if names.is_empty() and nd == 0:
		return {}
	var parts := PackedStringArray()
	if not names.is_empty():
		parts.append(U.plural(names.size(), "Emulator", "Emulatoren"))
	if nd > 0:
		parts.append(U.plural(nd, "Spieleordner", "Spieleordner"))
	return { "text": " · ".join(parts), "names": ", ".join(names) }


## „Ordner hinzufügen …“: Emulatoren (und Spieleordner) in einem selbst gewählten Ordner suchen –
## für alles, was nicht an den üblichen Stellen liegt. Funde stehen danach in der Liste darüber.
func _folder_row(rows: VBoxContainer) -> void:
	var busy := bool(_find.get("folder_busy", false))
	var r = _row(rows, "action", "Ordner hinzufügen …", "Spiele oder Emulatoren an einem anderen Ort",
		"Ordner wählen. Unterordner werden mit durchsucht.")
	r.icon_name = "folder"
	r.value_text = "Sucht …" if busy else "Wählen"
	r.set_meta("uz_key", "su:f:ordner")
	r.on_activate = func() -> void:
		if not bool(_find.get("folder_busy", false)):
			main.open_file_browser("Ordner mit Emulatoren oder Spielen", true, _search_folder)


## Scrape games right here: covers and images for all games (spiele_scrapen.gd). If emulator games
## lack covers and a source is available, scraping starts for them on its own the first time, as part
## of setup (PC games bring their own images); it runs in the background while setup continues. The
## row opens the selection (source, systems, replace all) and shows the status.
func _scrape_row(rows: VBoxContainer) -> void:
	var n := Media.scrape_spiele().size()
	if n == 0:
		return
	var retro := Media.retro_systeme()
	if not retro.is_empty() and scrape_auto_ok(_scrape_auto, Media.sgdb_missing(), Media.sgdb_running, Media.scrape_quellen().size()):
		_scrape_auto = true
		SpieleScrapen.starten(main, false, retro)
	var fehlt := Media.scrape_fehlt()
	var r = _row(rows, "action", "Spiele scrapen", "Für %s" % U.plural(n, "Spiel", "Spiele"),
		"Cover, Hintergründe und Schriftzüge aus dem Netz.")
	r.icon_name = "image"
	r.value_text = scrape_stand(Media.sgdb_running, n, fehlt)
	_scrape_r = r
	r.set_meta("uz_key", "su:scrapen")
	r.on_activate = func() -> void:
		var l = SpieleScrapen.new()
		l.main = main
		main.open_layer(l)


## Status of the „Spiele scrapen“ row: running, all present, or how many already have a cover - including those
## that came without „Spiele scrapen“ (Libretro during scanning). Otherwise the row would show nothing on the first
## run, although the covers of the emulator games were already fetched.
static func scrape_stand(laeuft: bool, n: int, fehlt: int) -> String:
	if laeuft:
		return TranslationServer.translate("Läuft …")
	if fehlt <= 0:
		return TranslationServer.translate("Alle da")
	return TranslationServer.translate("%d von %d mit Cover") % [maxi(0, n - fehlt), n]


## Von selbst scrapen? Einmal je Einrichtung, nur wenn Cover fehlen, nichts läuft und es eine Quelle gibt.
static func scrape_auto_ok(schon: bool, fehlt: int, laeuft: bool, quellen: int) -> bool:
	return not schon and fehlt > 0 and not laeuft and quellen > 0


func _search_folder(p: String) -> void:
	# Läuft die Suche noch (kurz nach dem Schritt Spiele): erst sie zu Ende, dann der gewählte Ordner –
	# früher ging die Wahl dann verloren.
	if p != "" and str(_find.get("state", "")) == "läuft":
		var tree := Engine.get_main_loop() as SceneTree
		while tree != null and str(_find.get("state", "")) == "läuft":
			await tree.process_frame
		if not is_inside_tree():
			return
	if p != "" and str(_find.get("state", "")) == "":
		# Ohne Suche in dieser Einrichtung (etwa nach einem Neustart im Schritt Emulatoren): Funde
		# gelten wie nach dem Spiele-Schritt gleich als übernommen.
		_find = { "state": "fertig", "emus": [], "dirs": [], "applied": true }
		Zustand.melden("einrichtung.suche", "fertig")
	if p == "" or str(_find.get("state", "")) != "fertig":
		return
	var erg: Dictionary = await _ordner_lauf(_find, p)
	# Wurde die Einrichtung inzwischen geschlossen, kommt hier nichts mehr an – gesucht, eingetragen und
	# gemeldet hat _ordner_lauf dann schon.
	if (erg.names as PackedStringArray).is_empty():
		# Keine Unterordner je System und kein Emulator: Liegen die Spiele direkt darin, fragt Uzai,
		# für welches System der Ordner ist.
		_ordner_zuordnen(p, erg.subs, erg.counts)
	if is_inside_tree():
		_tick()


## Die Suche im gewählten Ordner samt Eintragen und Meldung. Statisch, damit sie auch zu Ende läuft,
## wenn die Einrichtung inzwischen geschlossen wurde: Sonst blieb „Sucht …“ stehen (folder_busy liegt
## in der statischen Suche), und die Funde gingen verloren. { names, subs, counts } – subs und counts
## (_ordner_zaehlen) nur, wenn nichts gefunden wurde.
static func _ordner_lauf(box: Dictionary, p: String) -> Dictionary:
	box["folder_busy"] = true
	var have := {}
	for e in box.get("emus", []):
		have[str(e.id)] = true
	var emus: Array = []
	for e in Config.emulators():
		if not have.has(str(e.id)):
			emus.append({ "id": str(e.id), "name": str(e.get("name", e.id)), "exe_hint": str(e.get("exe_hint", "")), "systems": e.get("systems", []) })
	var systems := Config.systems()
	var taken := {}
	for d in box.get("dirs", []):
		taken[str(d.system)] = true
	var dirs0: Dictionary = Config.get_value("library.rom_dirs", {})
	for k in dirs0.keys():
		if str(dirs0[k]) != "":
			taken[str(k)] = true
	var fund: Variant = await Arbeit.ergebnis(_ordner_suchen.bind(p, emus, systems, taken), Arbeit.LANG)
	var res: Dictionary = fund if fund is Dictionary else { "emus": {}, "dirs": [] }
	var names := PackedStringArray()
	for e in emus:
		if (res.emus as Dictionary).has(str(e.id)):
			var f := { "id": str(e.id), "name": str(e.name), "exe": str(res.emus[str(e.id)].exe), "systems": e.systems }
			(box.emus as Array).append(f)
			_picks["emu:" + f.id] = true
			names.append(f.name)
			if bool(box.get("applied", false)):
				Config.set_emulator(f.id, "exe", f.exe)
	for d in res.dirs:
		(box.dirs as Array).append(d)
		_picks["dir:" + str(d.system)] = true
		names.append(str(d.name))
		if bool(box.get("applied", false)):
			Config.set_rom_dir(str(d.system), str(d.dir))
			Config.set_system(str(d.system), "enabled", true)
	var erg := { "names": names, "subs": [], "counts": {} }
	if names.is_empty():
		var lage: Variant = await Arbeit.ergebnis(_ordner_zaehlen.bind(p, systems), Arbeit.LANG)
		if lage is Dictionary:
			erg.subs = lage.subs
			erg.counts = lage.counts
	else:
		Toasts.show_toast("Gefunden", ", ".join(names), "check", { "quiet": true })
		if bool(box.get("applied", false)):
			Library.scan()
	box["folder_busy"] = false
	return erg


## Was direkt im Ordner liegt: seine Unterordner und je System die Zahl der passenden Dateien. Im
## Hintergrund – vorher ging der Ordner für jedes System einzeln durch den Hauptfaden.
static func _ordner_zaehlen(p: String, systems: Array) -> Dictionary:
	var counts := {}
	for s: Variant in systems:
		var n := RomScanner.scan(s, p).size()
		if n > 0:
			counts[str(s.id)] = n
	return { "subs": EmuSuche.dirs_at(p), "counts": counts }


## Einen gewählten Ordner durchsuchen (im Hintergrund): Emulatoren darin und Spieleordner je System.
## { emus: { id: { exe … } }, dirs: [ { system, dir, count, name } ] }
static func _ordner_suchen(p: String, emus: Array, systems: Array, taken: Dictionary) -> Dictionary:
	var pats := EmuSuche.patterns(emus, E.ALT_EXE)
	var ld := func(q: String) -> Array: return EmuSuche.dirs_at(q)
	var lf := func(q: String) -> Array: return EmuSuche.files_at(q)
	var res := { "emus": {}, "dirs": [] }
	res.emus = EmuSuche.walk([[p.replace("\\", "/").trim_suffix("/"), 4]], pats, ld, lf, EmuSuche.budget(4000, 8000), {}, "ordner")
	var by_id := {}
	for s: Variant in systems:
		by_id[str(s.id)] = s
	for d: Variant in E.find_rom_dirs([p, p.get_base_dir()], systems, ld, taken):
		var n := RomScanner.scan(by_id[d.system], str(d.dir)).size()
		if n > 0:
			d["count"] = n
			d["name"] = str(by_id[d.system].get("name", d.system))
			res.dirs.append(d)
	return res


## Retro ohne Einrichtung: Für welche Systeme (Bibliothek und gewählte Funde) fehlt ein Emulator,
## den Uzai von der offiziellen Quelle einrichten kann? { text, extra, schon_da } oder {}.
func _retro_fehlt() -> Dictionary:
	var wahl := _funde_wahl()
	var extra: Dictionary = wahl[0]
	var schon_da: Array = wahl[1]
	var text := RetroAuto.fehlt_text(load("res://src/core/retro_laden.gd").inst().lage(extra, schon_da))
	return { "text": text, "extra": extra, "schon_da": schon_da } if text != "" else {}


## Die gewählten Funde der Suche: [{ System → Spiele } aus Spieleordnern, [Emulator-IDs]].
func _funde_wahl() -> Array:
	var extra := {}
	for d in _find.get("dirs", []):
		if bool(_picks.get("dir:" + str(d.system), true)):
			extra[str(d.system)] = int(d.get("count", 0))
	var schon_da: Array = []
	for e in _find.get("emus", []):
		if bool(_picks.get("emu:" + str(e.id), true)):
			schon_da.append(str(e.id))
	return [extra, schon_da]


## „Für 3 Systeme fehlt ein Emulator – einrichten?“ (öffnet Retro einrichten über der Einrichtung).
func _retro_offer(rows: VBoxContainer, retro: Dictionary) -> void:
	if retro.is_empty():
		return
	var r = _row(rows, "action", tr(str(retro.text)) + " – " + tr("einrichten?"), "Erst nach Zustimmung · offizielle Quelle",
		"Nur Emulatoren. Keine BIOS, Firmware oder Spiele.")
	r.icon_name = "download"
	r.value_text = "Einrichten"
	r.tone = "accent"
	r.set_meta("uz_key", "su:f:retro")
	r.on_activate = func() -> void:
		var l: Control = load("res://src/ui/layers/retro_einrichten.gd").open_for(main, retro.extra, retro.schon_da)
		l.closed.connect(func() -> void: _tick())


## Beim Weitergehen: gewählte Funde eintragen und einlesen. Läuft die Suche noch, merkt es sich das
## und übernimmt, sobald sie fertig ist (_find_fertig) – statisch, die Einrichtung kann dann schon zu sein.
static func _apply_found() -> void:
	if str(_find.get("state", "")) == "läuft" and _find.has("lock"):
		(_find.lock as Mutex).lock()
		_find["weiter"] = true
		(_find.lock as Mutex).unlock()
		return
	if str(_find.get("state", "")) != "fertig" or bool(_find.get("applied", false)):
		return
	var ne := 0
	var nd := 0
	for e in _find.get("emus", []):
		if bool(_picks.get("emu:" + str(e.id), true)):
			Config.set_emulator(str(e.id), "exe", str(e.exe))
			ne += 1
	for d in _find.get("dirs", []):
		if bool(_picks.get("dir:" + str(d.system), true)):
			Config.set_rom_dir(str(d.system), str(d.dir))
			Config.set_system(str(d.system), "enabled", true)
			nd += 1
	_find["applied"] = true
	if ne + nd > 0:
		var parts := PackedStringArray()
		if ne > 0:
			parts.append(U.plural(ne, "Emulator", "Emulatoren"))
		if nd > 0:
			parts.append(U.plural(nd, "Spieleordner", "Spieleordner"))
		Toasts.show_toast("Übernommen", " und ".join(parts) + ". Spiele werden eingelesen.", "check", { "quiet": true })
		Library.scan()


## Ein Ordner, in dem Spiele direkt liegen (oder Unterordner je System): übernehmen bzw. fragen,
## für welches System er ist. Nichts Passendes darin: sagt es.
func _ordner_zuordnen(p: String, subs: Array, counts: Dictionary) -> void:
	var systems := Config.systems()
	if counts.is_empty() and E.find_rom_dirs([p], systems, func(_q: String) -> Array: return subs).is_empty():
		Toasts.show_toast("Nichts gefunden", "In „%s“ liegt kein bekannter Emulator und kein Spieleordner." % p.get_file(), "search")
		return
	var res := E.classify_folder(p, subs, systems, counts)
	if res.kind == "unterordner":
		var names := PackedStringArray()
		for d in res.list:
			Config.set_rom_dir(str(d.system), str(d.dir))
			Config.set_system(str(d.system), "enabled", true)
			names.append(str(Config.system(str(d.system)).get("short", d.system)))
		Toasts.show_toast("Spieleordner übernommen", ", ".join(names), "folder")
		Library.scan()
		return
	var opts: Array = []
	var best := str(res.get("system", ""))
	var order: Array = systems.duplicate()
	order.sort_custom(func(a, b): return int(counts.get(str(a.id), 0)) > int(counts.get(str(b.id), 0)))
	for s in order:
		var n2 := int(counts.get(str(s.id), 0))
		opts.append([str(s.id), str(s.name) + (" · %d Dateien" % n2 if n2 > 0 else "")])
	main.open_choice("Für welches System ist der Ordner?", opts, best if best != "" else null, func(v: Variant) -> void:
		Config.set_rom_dir(str(v), p)
		Config.set_system(str(v), "enabled", true)
		Toasts.show_toast("Spieleordner übernommen", "%s: %s" % [str(Config.system(str(v)).get("name", v)), p.get_file()], "folder")
		Library.scan()
	, p.get_file())
