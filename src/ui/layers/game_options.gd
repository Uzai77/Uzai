extends "res://src/ui/layers/sheet.gd"
## Optionen eines Spiels (Y oder langes A auf einem Spiel). Oben das Cover neben dem Titel, damit
## klar ist, um welches Spiel es geht. Vorn nur, was man oft braucht: Spielen, Favorit, Backlog,
## Ordner, Bilder, dann Ausblenden und Entfernen bzw. Deinstallieren. Alles Seltene liegt geordnet
## eine Ebene tiefer unter „Spiel-Einstellungen“: Start (Profil, Startparameter, Programmdatei,
## Lossless, Remote Play), Emulator (Bildfilter, Emulator, RetroAchievements, Disc, Retro-Katalog),
## Angaben (Titel, eigene Angaben) und außerhalb von Uzai (Verknüpfung, Discord-Status).

const CoverArt := preload("res://src/ui/components/cover_art.gd")
const OverlaySpiel := preload("res://src/core/overlay_spiel.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const RemotePlay := preload("res://src/core/remote_play.gd")
const DiscSerial := preload("res://src/library/disc_serial.gd")
const GameFinder := preload("res://src/library/game_finder.gd")
const GameFields := preload("res://src/library/game_fields.gd")
const ChatLink := preload("res://src/ui/layers/chat_link.gd")
const GamePresence := preload("res://src/core/game_presence.gd")
const Backlog := preload("res://src/library/backlog.gd")
const BacklogFlow := preload("res://src/ui/backlog_flow.gd")
const GameProfile := preload("res://src/core/game_profile.gd")
const ProfileSheet := preload("res://src/ui/layers/profile_sheet.gd")
const InstallFlow := preload("res://src/ui/install_flow.gd")
const EpicInstallS := preload("res://src/core/epic_install.gd")
const MusicBits := preload("res://src/ui/components/music_bits.gd")
const IMAGE_KINDS := [["cover", "Cover"], ["hero", "Hintergrund"], ["logo", "Logo"], ["icon", "Symbol"]]

var game: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var _angaben: WeakRef = null     ## offene Seitenleiste „Eigene Angaben“ (zum Auffrischen)
var _adv: WeakRef = null         ## offenes Untermenü „Spiel-Einstellungen“
var _ov_namen := {}              ## Spielordner → Namen darin (null: wird gerade durchgesehen)


func build() -> void:
	setup(Library.display_title(game), _source_text(), 820)
	heading_raw = true      # Name des Spiels
	set_header_image(_cover_thumb())
	super()


func _source_text() -> String:
	var bits := PackedStringArray()
	match str(game.get("source", "")):
		"steam": bits.append("Steam")
		"epic": bits.append("Epic Games")
		"ea": bits.append("EA app")
		"pc": bits.append("PC-Spiel")
		_: bits.append(Library.store_name(game, false, str(Config.system(str(game.get("system", ""))).get("name", ""))))
	bits.append(U.playtime(Library.playtime(game)))
	return "  ·  ".join(bits)


## Kleines Cover im Kopf (echtes Bild, sonst das Ersatz-Cover in der Farbe des Systems).
func _cover_thumb() -> Control:
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), maxi(6, UzTheme.r_cover() - 2)))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.custom_minimum_size = Vector2(78, 104)
	clip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var art = CoverArt.new()
	art.compact = true
	art.show_title = false
	U.full_rect(art)
	clip.add_child(art)
	art.setup(game)
	var bild := TextureRect.new()
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bild)
	clip.add_child(bild)
	var wt: WeakRef = weakref(bild)
	Media.game_texture(game, "cover", func(t: Texture2D) -> void:
		var r: TextureRect = wt.get_ref()
		if r and t:
			r.texture = t
	)
	return clip


## „Overlay im Spiel (Versuch)“ (docs/OVERLAY.md): der Guide erscheint im Spiel selbst, statt es aus dem
## exklusiven Vollbild zu nehmen. Nur PC-Spiele mit bekanntem Ordner; Standard aus. Liegt ein
## Schutzprogramm im Spielordner, steht die Zeile da, lässt sich aber nicht einschalten.
func _overlay_row(sh: Control, gid: String) -> void:
	if OverlaySpiel.vorab(game, Config.is_windows()) != "":
		return
	# Der Spielordner wird im Hintergrund durchgesehen (große Ordner, langsame Platten); so lange steht
	# die Zeile schon da, damit sich danach nichts verschiebt.
	var dir := str(game.get("install_dir", ""))
	if not _ov_namen.has(dir):
		_ov_namen[dir] = null
		_overlay_ordner(dir)
	if _ov_namen[dir] == null:
		var wartet = _row("info", "Overlay im Spiel (Versuch)")
		wartet.icon_name = "tv"
		wartet.subtitle = "Spielordner wird geprüft."
		sh.add_row(wartet)
		return
	var e := OverlaySpiel.erlaubt(game, true, _ov_namen[dir])
	if str(e.grund) == "ordner":
		return
	if str(e.grund) == "anticheat":
		var nein = _row("info", "Overlay im Spiel (Versuch)")
		nein.icon_name = "tv"
		nein.value_text = str(e.schutz)
		nein.subtitle = "Nicht bei Spielen mit Anti-Cheat."
		sh.add_row(nein)
		return
	var ov = _row("toggle", "Overlay im Spiel (Versuch)", "", bool(game.get("overlay", false)))
	ov.icon_name = "tv"
	ov.subtitle = "Nur für Einzelspieler-Spiele ohne Anti-Cheat."
	ov.changed.connect(func(v: Variant) -> void: Library.set_field(gid, "overlay", true if v else null))
	sh.add_row(ov)


func _overlay_ordner(dir: String) -> void:
	var namen: Variant = await Arbeit.ergebnis(OverlaySpiel.ordner_namen.bind(dir, 2, 1500))
	_ov_namen[dir] = namen if namen is Array else []
	var a = _adv.get_ref() if _adv else null
	if is_inside_tree() and a and is_instance_valid(a) and not a.get("_closing"):
		a.refill()


func _row(kind: String, t: String, d := "", v: Variant = null) -> Control:
	var r = SettingRow.new()
	r.setup(kind, t, d, v)
	r.set_meta("uz_key", "opt:" + t)
	return r


func fill() -> void:
	var gid := str(game.id)
	game = Library.get_game(gid) if not Library.get_game(gid).is_empty() else game
	var installed: bool = game.get("installed", true)
	var epic_own := str(game.get("source", "")) == "epic" and EpicInstallS.can_install(game) and bool(Config.get_value("library.epic_uzai", false))
	var play = _row("action", "Spielen" if installed
			else ("Installieren" if epic_own else ("Im Epic Games Launcher installieren" if str(game.get("source", "")) == "epic" else "In Steam installieren")))
	play.icon_name = "play" if installed else "download"
	play.on_activate = func() -> void:
		if installed:
			close()
		main.launch(game)
	add_row(play)

	# Was man an einem Spiel oft braucht: merken, einordnen, Bilder.
	add_gap()
	var fav = _row("toggle", "Favorit", "", bool(game.get("favorite", false)))
	fav.icon_name = "heart"
	fav.changed.connect(func(v: Variant) -> void: Library.set_field(gid, "favorite", true if v else null))
	add_row(fav)
	var st := Backlog.status_of(game)
	var bl = _row("action", "Backlog")
	bl.icon_name = Backlog.status_icon(st) if st != "" else "bookmark"
	bl.value_text = Backlog.summary(game) if Backlog.summary(game) != "" else "Nichts eingetragen"
	bl.on_activate = func() -> void: BacklogFlow.open_sheet(main, game, refill)
	add_row(bl)
	var in_f: Array = Library.folders_for_game(game).filter(func(f): return Library.is_in_folder(game, str(f.id)))
	var fr = _row("action", "Ordner")
	fr.icon_name = "folder"
	fr.value_text = ", ".join(PackedStringArray(in_f.map(func(f): return str(f.name)))) if not in_f.is_empty() else "Keiner"
	fr.on_activate = func() -> void: main.open_game_folders(game, refill)
	add_row(fr)
	# Bilder: SteamGridDB, ScreenScraper (alle Spiele, auch Steam und PC), iiDB oder eigene Dateien – eine Zeile, A fragt, woher.
	var img = _row("action", "Bilder")
	img.icon_name = "image"
	img.value_text = _own_images_text() if _own_images_text() != "Keine" else "Automatisch"
	img.on_activate = func() -> void:
		var woher: Array = [["sgdb", "Von SteamGridDB"]]
		if Media.ss_bildwahl_ok(game):
			woher.append(["ss", "Von ScreenScraper"])
		woher.append(["iidb", "Von iiDB"])
		woher.append(["own", "Eigene Bilddateien"])
		main.open_choice("Bilder", woher, "", func(v: Variant) -> void:
			if str(v) in ["sgdb", "ss", "iidb"]:
				main.open_art_picker(game, str(v))
			else:
				_open_images()
		)
	add_row(img)
	# Soundtrack: Uzais Musiksuche (Spotify) mit dem Titel – abgespielt wird über Spotify, nichts wird
	# geladen und nichts läuft von selbst los (das risse die laufende Musik weg).
	if Music.has_spotify():
		var ost = _row("action", "Soundtrack")
		ost.icon_name = "music"
		ost.value_text = "Auf Spotify suchen"
		ost.on_activate = func() -> void:
			MusicBits.open_search(main, load("res://src/ui/layers/game_page.gd").soundtrack_query(Library.display_title(game)))
		add_row(ost)
	# Alles Seltene eine Ebene tiefer, geordnet (Start, Emulator, Angaben, außerhalb von Uzai).
	var adv = _row("action", "Spiel-Einstellungen")
	adv.icon_name = "settings"
	adv.value_text = _advanced_text()
	adv.on_activate = _open_advanced
	add_row(adv)

	add_gap()
	var hide_row = _row("toggle", "Ausblenden", "", bool(game.get("hidden", false)))
	hide_row.icon_name = "eye_off"
	hide_row.changed.connect(func(v: Variant) -> void:
		var snap := Library.snapshot([gid])
		Library.set_field(gid, "hidden", true if v else null)
		# Ausgeblendet verschwindet das Spiel aus allen Listen: kurz zurücknehmbar.
		if v:
			Undo.offer_games("Ausgeblendet", Library.display_title(game), "eye_off", snap, refill)
	)
	add_row(hide_row)
	if EpicInstallS.is_uzai(game) and installed:
		# Von Uzai selbst installiert (ohne Launcher): Deinstallieren (Prüfen steht unter Spiel-Einstellungen).
		var un = _row("action", "Deinstallieren")
		un.icon_name = "trash"
		un.on_activate = func() -> void:
			close()
			InstallFlow.epic_uninstall(main, game)
		add_row(un)
	if game.get("source") == "pc":
		var rm = _row("action", "Aus Uzai entfernen")
		rm.icon_name = "trash"
		rm.on_activate = func() -> void:
			main.open_dialog("Aus Uzai entfernen?",
					"„%s“ verschwindet aus der Bibliothek. Das Spiel selbst bleibt auf dem PC, Spielzeit und Bilder in Uzai gehen verloren." % Library.display_title(game), [
				["Entfernen", func() -> void:
					var snap := Library.snapshot([gid])
					var name_ := Library.display_title(game)
					Library.remove(gid)
					close()
					Undo.offer_games("Aus Uzai entfernt", name_, "trash", snap)],
				["Behalten", func() -> void: pass],
			], "trash")
		add_row(rm)


## Was unter „Spiel-Einstellungen“ vom Standard abweicht („Profil, Startparameter“); sonst, was
## dort steht.
func _advanced_text() -> String:
	var bits := PackedStringArray()
	if not GameProfile.own_of(game).is_empty() and GameProfile.summary(GameProfile.own_of(game), 1) != "":
		bits.append("Profil")
	if str(game.get("args", "")) != "":
		bits.append("Startparameter")
	if str(game.get("filter", "")) != "" or str(game.get("emulator", "")) != "":
		bits.append("Emulator")
	if str(game.get("lossless", "")) != "":
		bits.append("Lossless")
	if GameFields.FIELDS.any(func(k: String) -> bool: return game.get(k) != null):
		bits.append("Eigene Angaben")
	if not bits.is_empty():
		return ", ".join(bits.slice(0, 2)) + (" …" if bits.size() > 2 else "")
	return "Profil, Emulator, Angaben" if game.get("source") == "rom" else "Profil, Start, Angaben"


## Untermenü „Spiel-Einstellungen“: alles Seltene an einem Spiel in Gruppen.
func _open_advanced() -> void:
	var gid := str(game.id)
	var s = preload("res://src/ui/layers/sheet.gd").new()
	s.setup("Spiel-Einstellungen", Library.display_title(game), 820)
	s.subheading_raw = true      # Name des Spiels
	s.set_header_image(_cover_thumb())
	s.fill_func = func(sheet) -> void:
		game = Library.get_game(gid) if not Library.get_game(gid).is_empty() else game
		_advanced_rows(sheet)
	s.closed.connect(refill)
	_adv = weakref(s)
	main.open_layer(s)


func _advanced_rows(sh) -> void:
	var gid := str(game.id)
	var installed: bool = game.get("installed", true)
	var src := str(game.get("source", ""))
	# Start: wie das Spiel startet.
	sh.add_label(TranslationServer.translate("Start", "spiel"))
	_profile_row(sh)
	if src in ["rom", "pc"]:
		var args = _row("action", "Zusätzliche Startparameter")
		args.icon_name = "keyboard"
		args.value_raw = true      # eigener Text
		args.value_text = str(game.get("args", "")) if str(game.get("args", "")) != "" else tr("Keine")
		args.on_activate = func() -> void:
			main.open_keyboard("Startparameter", str(game.get("args", "")), func(t: String) -> void:
				var problem := GameFinder.args_problem(t.strip_edges(), str(game.get("target", game.get("path", ""))))
				if problem != "":
					main.open_dialog("Startparameter nicht übernommen", problem, [["OK", func() -> void: pass]], "warning")
					return
				Library.set_field(gid, "args", t.strip_edges())
				_refresh_all()
			)
		sh.add_row(args)
	if src == "pc" and str(game.get("url", "")) == "":
		_pc_rows(gid, sh)
	if Lossless.exe_path() != "" or Library.demo:
		var ls = _row("choice", "Lossless Scaling beim Start", "", str(game.get("lossless", "")))
		ls.icon_name = "bolt"
		var auto_txt := str(
				{ "aus": "nie", "pc": "bei PC-Spielen", "emu": "bei Emulator-Spielen", "alle": "bei allen Spielen" }.get(str(Config.get_value("lossless.auto", "aus")),
				"nie"))
		ls.options = [["", "Standard (%s)" % auto_txt], ["an", "Immer einschalten"], ["aus", "Nie einschalten"]]
		ls.changed.connect(func(v: Variant) -> void: Library.set_field(gid, "lossless", v if str(v) != "" else null))
		sh.add_row(ls)
	_remote_play_row(sh, installed)
	# Nur wenn Uzai es für dieses Spiel abgeschaltet hat (main_fenster.gd guide_tod_melden): Das Spiel
	# endete, als der Guide es aus dem exklusiven Vollbild nahm. Hier lässt es sich wieder einschalten.
	if str(game.get("guide_vollbild", "")) == "nie":
		var gv = _row("toggle", "Guide im Vollbild", "Das Spiel endete, als der Guide aufging.", false)
		gv.icon_name = "tv"
		gv.subtitle = "Das Spiel endete, als der Guide aufging."
		gv.changed.connect(func(v: Variant) -> void: Library.set_field(gid, "guide_vollbild", null if v else "nie"))
		sh.add_row(gv)
	_overlay_row(sh, gid)

	# Emulator: Bild, Emulator, Erfolge und Disc.
	if src == "rom":
		sh.add_gap()
		sh.add_label("Emulator")
		var sys := Config.system(str(game.get("system", "")))
		var flt_opts: Array = [["", "Wie alle %s-Spiele (%s)" % [sys.get("short", ""), _filter_name(str(sys.get("filter", "")))]], ["aus", "Aus"]]
		for f in Config.filters():
			flt_opts.append([str(f.id), str(f.name)])
		var flt = _row("choice", "Bildfilter", "", str(game.get("filter", "")))
		flt.icon_name = "tv"
		flt.options = flt_opts
		flt.changed.connect(func(v: Variant) -> void: Library.set_field(gid, "filter", v))
		sh.add_row(flt)
		var emus: Array = [["", "Standard (%s)" % Config.emulator(str(sys.get("emulator", ""))).get("name", "—")]]
		for e in Config.emulators_for(str(game.get("system", ""))):
			emus.append([str(e.id), str(e.name)])
		if emus.size() > 2:
			var emu = _row("choice", "Emulator", "", str(game.get("emulator", "")))
			emu.icon_name = "chip"
			emu.options = emus
			emu.changed.connect(func(v: Variant) -> void: Library.set_field(gid, "emulator", v))
			sh.add_row(emu)
		var ra = _row("action", "RetroAchievements-Spiel")
		ra.icon_name = "trophy"
		ra.value_text = "Nr. %d" % int(game.ra_id) if int(game.get("ra_id", 0)) > 0 else "Automatisch"
		ra.on_activate = func() -> void:
			main.open_keyboard("RetroAchievements-Spiel (Nummer aus retroachievements.org/game/…)", str(game.get("ra_id", "")), func(t: String) -> void:
				Library.set_field(gid, "ra_id", int(t) if t.is_valid_int() and int(t) > 0 else null)
				_refresh_all()
			)
		sh.add_row(ra)
		_disc_rows(gid, sh)

	# Angaben: wie das Spiel in Uzai heißt und eigene Angaben dazu.
	sh.add_gap()
	sh.add_label("Angaben")
	var title = _row("action", "Titel ändern")
	title.icon_name = "edit"
	title.value_raw = true      # Name des Spiels
	title.value_text = Library.display_title(game)
	title.on_activate = func() -> void:
		main.open_keyboard("Titel", Library.display_title(game), func(t: String) -> void:
			if t.strip_edges() != "":
				Library.set_field(gid, "title", t.strip_edges())
				_refresh_all()
		)
	sh.add_row(title)
	_angaben_row(gid, sh)

	# Außerhalb von Uzai: Verknüpfung auf dem PC, Discord-Status.
	var sc_on := Config.is_windows() or Library.demo
	var dc_on := bool(Config.get_value("accounts.discord_presence", true)) and (Config.is_windows() or Library.demo)
	if sc_on or dc_on:
		sh.add_gap()
		sh.add_label("Außerhalb von Uzai")
	if sc_on:
		var sc = _row("action", "Verknüpfung anlegen")
		sc.icon_name = "link"
		sc.value_text = "Desktop oder Startmenü"
		sc.on_activate = func() -> void:
			main.open_choice("Verknüpfung anlegen", [["desktop", "Auf dem Desktop"], ["startmenu", "Im Startmenü"]], "", func(v: Variant) -> void:
				main.create_shortcut(game, str(v))
			)
		sh.add_row(sc)
	# Discord-Status (Roadmap 89): einzelne Spiele dort nicht zeigen. Nur, wenn der Status an ist.
	if dc_on:
		var pr = _row("toggle", "Im Discord-Status zeigen", "", not GamePresence.hidden(game))
		pr.icon_name = "discord"
		pr.changed.connect(func(v: Variant) -> void:
			Library.set_field(gid, "presence_hidden", null if v else true)
			Launcher.refresh_presence(gid))
		sh.add_row(pr)

	# Von Uzai selbst installiert (ohne Launcher): Update und Prüfen.
	if EpicInstallS.is_uzai(game) and installed:
		sh.add_gap()
		sh.add_label("Installation")
		var chk = _row("action", "Prüfen und aktualisieren")
		chk.icon_name = "refresh"
		chk.on_activate = func() -> void:
			sh.close()
			close()
			InstallFlow.epic_check(main, game)
		sh.add_row(chk)

	# Ganz unten, klein: wo das Spiel liegt (für Fragen und Fehlersuche).
	var where := PackedStringArray()
	if src == "steam" and int(game.get("appid", 0)) > 0:
		where.append(tr("Steam-App %d") % int(game.appid))
	var p := str(game.get("path", game.get("install_dir", "")))
	if p != "":
		where.append(p)
	if not where.is_empty():
		sh.add_gap()
		# Ordnernamen bleiben, wie sie sind („Spiele“ im Pfad ist kein Text von Uzai).
		sh.add_label("  ·  ".join(where), "xs", "faint").auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


## PS1/PS2: eingelegte Disc diesem Abbild zuordnen bzw. die eigene Zuordnung lösen.
func _disc_rows(gid: String, sh) -> void:
	if not DiscSerial.is_disc_game(game):
		return
	var links: Array = Library.disc_links_for(gid)
	if Discs.serial != "" and not Discs.is_disc_game(game):
		var dl = _row("action", "Eingelegte Disc zuordnen")
		dl.icon_name = "disc"
		dl.value_text = "%s · startet dann dieses Abbild" % Discs.title()
		dl.on_activate = func() -> void:
			Discs.link(gid)
			Toasts.show_toast("Disc zugeordnet", "%s startet jetzt, wenn diese Disc drin ist." % Library.display_title(game), "check", { "sound": "select" })
			_refresh_all()
		sh.add_row(dl)
	elif not links.is_empty():
		var du = _row("action", "Disc-Zuordnung lösen")
		du.icon_name = "disc"
		du.value_text = ", ".join(PackedStringArray(links.map(func(x): return str(x))))
		du.on_activate = func() -> void:
			for x in links:
				Library.link_disc(str(x), "")
			Discs.link_changed()
			_refresh_all()
		sh.add_row(du)


## Spiel-Profil (Roadmap 18, 43): Bildschirm, Ton, Controller und Aktionen beim Start – eine
## Ebene tiefer (profile_sheet.gd). Rechts steht, was gilt, sonst die Vorlage des Systems.
func _profile_row(sh) -> void:
	var own := GameProfile.own_of(game)
	var pr = _row("action", "Profil")
	pr.icon_name = "settings"
	var txt := GameProfile.summary(own, 2)
	if txt == "":
		var tpl := GameProfile.summary(GameProfile.template_for(game), 2)
		txt = (tr("Vorlage: %s") % tpl) if tpl != "" else tr("Keins")
	pr.value_text = txt
	pr.on_activate = func() -> void:
		var s = ProfileSheet.new()
		s.game = game
		s.main = main
		s.closed.connect(_refresh_all)
		main.open_layer(s)
	sh.add_row(pr)


## Eigene Angaben (Roadmap 41) als eine Zeile unter „Spiel-Einstellungen“: A öffnet Tags,
## Kategorie, Altersfreigabe, Region und Links.
func _angaben_row(gid: String, sh) -> void:
	var bits := PackedStringArray()
	var cat := GameFields.category_of(game)
	if cat != "":
		bits.append(cat)
	var nt := GameFields.tags_of(game).size()
	if nt > 0:
		# „Tag“ heißt im Katalog sonst „day“ (Mehrzahl über Kontext): hier das Etikett.
		bits.append("1 " + TranslationServer.translate("Tag", "etikett") if nt == 1 else U.plural(nt, "Tag", "Tags"))
	var ar = _row("action", "Eigene Angaben")
	ar.icon_name = "tag"
	ar.value_text = ", ".join(bits) if not bits.is_empty() else "Keine"
	ar.on_activate = func() -> void:
		var s = preload("res://src/ui/layers/sheet.gd").new()
		s.setup("Eigene Angaben", Library.display_title(game), 760)
		s.subheading_raw = true      # Name des Spiels
		s.fill_func = func(sheet) -> void:
			game = Library.get_game(gid) if not Library.get_game(gid).is_empty() else game
			_own_rows(gid, sheet)
		s.closed.connect(_refresh_all)
		_angaben = weakref(s)
		main.open_layer(s)
	sh.add_row(ar)


## Nach einer Änderung: diese Seite, ein offenes „Spiel-Einstellungen“ und „Eigene Angaben“ neu.
func _refresh_all() -> void:
	refill()
	for w in [_adv, _angaben]:
		var a = w.get_ref() if w else null
		if a and is_instance_valid(a) and not a.get("_closing"):
			a.refill()


## Die Zeilen der Seitenleiste „Eigene Angaben“: Tags und Links eine Ebene tiefer, Kategorie aus
## einer Liste der schon vergebenen, Altersfreigabe und Region blättern links/rechts.
func _own_rows(gid: String, sheet) -> void:
	var tags := GameFields.tags_of(game)
	var tg = _row("action", "Tags")
	tg.icon_name = "tag"
	tg.value_raw = true      # eigene Tags
	tg.value_text = ", ".join(tags) if not tags.is_empty() else tr("Keine")
	tg.on_activate = func() -> void: _open_tags(gid)
	sheet.add_row(tg)
	var cat := GameFields.category_of(game)
	var cr = _row("action", "Kategorie")
	cr.icon_name = "bookmark"
	cr.value_raw = true      # eigene Kategorie
	cr.value_text = cat if cat != "" else tr("Keine")
	cr.on_activate = func() -> void: _pick_category(gid)
	sheet.add_row(cr)
	var age = _row("choice", "Altersfreigabe", "", str(game.get("age", "")))
	age.icon_name = "lock"
	age.options = [["", "Keine Angabe"]] + GameFields.AGES
	age.changed.connect(func(v: Variant) -> void: Library.set_field(gid, "age", v))
	sheet.add_row(age)
	var reg = _row("choice", "Region", "", str(game.get("region", "")))
	reg.icon_name = "tv"
	reg.options = [["", "Keine Angabe"]] + GameFields.REGIONS.map(func(r): return [r[0], r[1]])
	reg.changed.connect(func(v: Variant) -> void: Library.set_field(gid, "region", v))
	sheet.add_row(reg)
	var links := GameFields.links_of(game)
	var lk = _row("action", "Links")
	lk.icon_name = "link"
	lk.value_text = U.plural(links.size(), "Link", "Links") if not links.is_empty() else "Keine"
	lk.on_activate = func() -> void: _open_links(gid)
	sheet.add_row(lk)


## Tags: Schalter je Tag – oben die eigenen (an), darunter die schon vergebenen als Vorschlag (aus).
## Umschalten setzt oder nimmt den Tag sofort; die Liste ordnet sich erst beim nächsten Öffnen neu,
## damit nichts unter dem Fokus wegspringt.
func _open_tags(gid: String) -> void:
	var s = preload("res://src/ui/layers/sheet.gd").new()
	s.setup("Tags", Library.display_title(game), 760)
	s.subheading_raw = true      # Name des Spiels
	s.fill_func = func(sheet) -> void:
		var mine := GameFields.tags_of(Library.get_game(gid))
		var add = SettingRow.new()
		add.setup("action", "Neuer Tag")
		add.icon_name = "plus"
		add.set_meta("uz_key", "tag:new")
		add.value_text = "Höchstens %d" % GameFields.TAGS_MAX if mine.size() >= GameFields.TAGS_MAX else ""
		add.on_activate = func() -> void:
			if GameFields.tags_of(Library.get_game(gid)).size() >= GameFields.TAGS_MAX:
				return
			main.open_keyboard("Neuer Tag", "", func(t: String) -> void:
				_add_tag(gid, t)
				if is_instance_valid(sheet):
					sheet.refill()
			)
		sheet.add_row(add)
		for t in mine:
			sheet.add_row(_tag_row(gid, t, true))
		var all := GameFields.all_tags(Library.games)
		var lower := Array(mine).map(func(x): return str(x).to_lower())
		var more: Array = GameFields.by_count(all).filter(func(x): return not lower.has(str(x).to_lower())).slice(0, 12)
		if not more.is_empty():
			sheet.add_gap()
			sheet.add_label("Schon vergeben")
			for t in more:
				var r = _tag_row(gid, str(t), false)
				r.subtitle = U.plural(int(all[t]), "Spiel", "Spiele")
				sheet.add_row(r)
		sheet.add_gap()
		sheet.add_label("Im Raster „Alle anzeigen“ lässt sich danach filtern.", "s", "faint")
	s.closed.connect(_refresh_all)
	main.open_layer(s)


func _tag_row(gid: String, t: String, on: bool) -> Control:
	var r = SettingRow.new()
	r.setup("toggle", t, "", on)
	r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # eigener Tag; die Zeile darunter ist schon in der Sprache
	r.icon_name = "tag"
	r.set_meta("uz_key", "tag:" + t)
	r.changed.connect(func(v: Variant) -> void:
		if v and GameFields.tags_of(Library.get_game(gid)).size() >= GameFields.TAGS_MAX:
			# Voll: der Schalter geht zurück, statt „an“ zu zeigen, was nicht gespeichert ist.
			Toasts.show_toast("Höchstens %d Tags" % GameFields.TAGS_MAX, "Erst einen anderen ausschalten.", "info", { "ms": 2500, "quiet": true })
			r.value = false
			r.call("_refresh")
		elif v:
			_add_tag(gid, t)
		else:
			var rest := GameFields.without_tag(GameFields.tags_of(Library.get_game(gid)), t)
			Library.set_field(gid, "tags", rest if not rest.is_empty() else null)
	)
	return r


## Gleiche Tags behalten ihre Schreibung („koop“ → „Koop“), es gibt keine doppelten.
func _add_tag(gid: String, t: String) -> void:
	var g := Library.get_game(gid)
	var next := GameFields.with_tag(GameFields.tags_of(g), t, GameFields.all_tags(Library.games).keys())
	Library.set_field(gid, "tags", next if not next.is_empty() else null)


const NEW := "\u0001"     ## „Neue Kategorie …“ – kein Name kann so heißen (Steuerzeichen fallen weg)


func _pick_category(gid: String) -> void:
	var opts: Array = [[NEW, "Neue Kategorie …"]]
	for c in GameFields.by_count(GameFields.categories(Library.games)):
		opts.append([c, c])
	opts.append(["", "Keine"])
	main.open_choice("Kategorie", opts, GameFields.category_of(game), func(v: Variant) -> void:
		if str(v) != NEW:
			_set_category(gid, str(v))
			return
		main.open_keyboard("Neue Kategorie", "", func(t: String) -> void: _set_category(gid, t))
	)


func _set_category(gid: String, t: String) -> void:
	var c := GameFields.known_spelling(GameFields.clean_text(t, GameFields.CATEGORY_MAX), GameFields.categories(Library.games).keys())
	Library.set_field(gid, "category", c)
	_refresh_all()


## Links: A zeigt den QR-Code fürs Handy, Y nimmt den Link weg. Uzai öffnet keinen Browser und
## lädt von dort nichts – nur https-Links kommen überhaupt hinein (GameFields.link_problem).
func _open_links(gid: String) -> void:
	var s = preload("res://src/ui/layers/sheet.gd").new()
	s.setup("Links", Library.display_title(game), 820)
	s.subheading_raw = true      # Name des Spiels
	s.fill_func = func(sheet) -> void:
		var links := GameFields.links_of(Library.get_game(gid))
		for i in links.size():
			var l: Dictionary = links[i]
			var r = SettingRow.new()
			r.setup("action", GameFields.link_title(l))
			r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # eigener Name des Links
			r.value_raw = true      # Adresse
			r.icon_name = "qr"
			r.value_text = ChatLink.short_url(str(l.url), 34)
			r.set_meta("uz_key", "link:%d" % i)
			r.set_meta("uz_hint_a", "Aufs Handy")
			r.set_meta("uz_hint_y", "Entfernen")
			r.set_meta("uz_on_y", func() -> void: _remove_link(gid, str(l.url), sheet))
			r.on_activate = func() -> void: ChatLink.show_qr(main, ChatLink.link_info(str(l.url)), false)
			sheet.add_row(r)
		var add = SettingRow.new()
		add.setup("action", "Link hinzufügen")
		add.icon_name = "plus"
		add.set_meta("uz_key", "link:new")
		add.value_text = "Höchstens %d" % GameFields.LINKS_MAX if links.size() >= GameFields.LINKS_MAX else "Wiki, Lösung, Mod-Seite …"
		add.on_activate = func() -> void:
			if GameFields.links_of(Library.get_game(gid)).size() < GameFields.LINKS_MAX:
				_add_link(gid, sheet)
		sheet.add_row(add)
		sheet.add_gap()
		sheet.add_label("Nur https.", "s", "faint")
	s.closed.connect(_refresh_all)
	main.open_layer(s)


func _add_link(gid: String, sheet) -> void:
	main.open_keyboard("Link (https://…)", "https://", func(t: String) -> void:
		var url := t.strip_edges()
		var problem := GameFields.link_problem(url)
		if problem != "":
			main.open_dialog("Link nicht übernommen", problem, [["OK", func() -> void: pass]], "warning")
			return
		main.open_keyboard("Name des Links (leer lassen: Adresse)", "", func(n: String) -> void:
			var list := GameFields.links_of(Library.get_game(gid))
			if list.any(func(x): return str(x.url) == url):
				return
			list.append({ "name": GameFields.clean_text(n, GameFields.LINK_NAME_MAX), "url": url })
			Library.set_field(gid, "links", list)
			if is_instance_valid(sheet):
				sheet.refill()
		)
	)


func _remove_link(gid: String, url: String, sheet) -> void:
	main.open_dialog("Link entfernen?", ChatLink.short_url(url, 60), [
		["Entfernen", func() -> void:
			var snap := Library.snapshot([gid])
			var rest := GameFields.links_of(Library.get_game(gid)).filter(func(x): return str(x.url) != url)
			Library.set_field(gid, "links", rest if not rest.is_empty() else null)
			if is_instance_valid(sheet):
				sheet.refill()
			Undo.offer_games("Link entfernt", ChatLink.short_url(url, 40), "trash", snap, sheet.refill if is_instance_valid(sheet) else Callable()), "danger"],
		["Behalten", func() -> void: pass],
	], "trash")


## Eigenes PC-Spiel: welche Datei startet und in welchem Ordner (Punkt 117). Den Arbeitsordner
## brauchen Spiele, deren Programm in einem Unterordner liegt, die Dateien aber daneben suchen.
func _pc_rows(gid: String, sh) -> void:
	var exe := str(game.get("path", ""))
	var file = _row("action", "Programmdatei")
	file.icon_name = "file"
	file.value_text = exe.get_file()
	file.on_activate = func() -> void:
		main.open_file_browser("Programmdatei wählen", false, func(p: String) -> void:
			var problem := GameFinder.exe_problem(p)
			if problem == "":
				problem = GameFinder.args_problem(str(game.get("args", "")), p)
			if problem != "":
				main.open_dialog("Das geht nicht", problem, [["OK", func() -> void: pass]], "warning")
				return
			Library.set_field(gid, "path", p)
			Library.set_field(gid, "install_dir", p.get_base_dir())
			Library.set_field(gid, "target", null)
			_refresh_all()
		, ["exe", "lnk", "bat", "cmd"], exe.get_base_dir())
	sh.add_row(file)
	var wd := str(game.get("work_dir", ""))
	var dir = _row("action", "Arbeitsordner")
	dir.icon_name = "folder"
	dir.value_text = wd.replace("\\", "/").get_file() if wd != "" else "Ordner des Programms"
	dir.on_activate = func() -> void:
		var pick := func() -> void:
			main.open_file_browser("Arbeitsordner", true, func(d: String) -> void:
				var problem := GameFinder.dir_problem(d)
				if problem != "":
					main.open_dialog("Das geht nicht", problem, [["OK", func() -> void: pass]], "warning")
					return
				Library.set_field(gid, "work_dir", d if d != exe.get_base_dir() else null)
				_refresh_all()
			, [], wd if wd != "" else exe.get_base_dir())
		if wd == "":
			pick.call()
			return
		main.open_choice("Arbeitsordner", [["pick", "Anderen Ordner wählen"], ["reset", "Ordner des Programms"]], "", func(v: Variant) -> void:
			if str(v) == "reset":
				Library.set_field(gid, "work_dir", null)
				_refresh_all()
			else:
				pick.call())
	sh.add_row(dir)


## „Mit Remote Play Together starten“: über den Spender, damit Steam-Freunde mitspielen können.
## Steam-Spiele haben das (wenn sie es können) selbst; dort fehlt die Zeile.
func _remote_play_row(sh, installed: bool) -> void:
	if not installed or not RemotePlay.possible_for(game):
		return
	var rp = _row("action", "Mit Remote Play Together starten")
	rp.icon_name = "controller"
	rp.value_text = RemotePlay.donor_title() if RemotePlay.configured() else "Erst einrichten"
	if str(game.get("source", "")) == "epic" and RemotePlay.configured():
		rp.value_text = "nur ohne Epic-Kopierschutz"
	rp.on_activate = func() -> void:
		if not RemotePlay.configured():
			main.open_dialog("Remote Play Together einrichten",
				"Dafür leiht sich Uzai einmal ein Steam-Spiel als Spender, z. B. das kostenlose RetroArch.",
				[["Zu den Einstellungen", func() -> void:
					sh.close()
					_goto_remote_play_settings()], ["Später", Callable()]], "controller")
			return
		var g := game.duplicate()
		g["_rp"] = true
		sh.close()
		close()
		main.launch(g)
	sh.add_row(rp)


func _goto_remote_play_settings() -> void:
	close()
	await main.goto("settings", "imspiel")
	var sv = main.sections.get("settings")
	if sv and sv.has_method("open_more"):
		sv.open_more("Remote Play Together")


## Welche eigenen Bilddateien gesetzt sind („Cover, Logo“), sonst „Keine“.
func _own_images_text() -> String:
	var imgs: Dictionary = game.get("images", {}) if game.get("images") is Dictionary else {}
	var names := PackedStringArray()
	for k in IMAGE_KINDS:
		if str(imgs.get(k[0], "")) != "":
			names.append(str(k[1]))
	return ", ".join(names) if not names.is_empty() else "Keine"


## Eine Ebene tiefer: je Bildart eine Datei wählen, oder alle eigenen wieder entfernen.
func _open_images() -> void:
	var s = preload("res://src/ui/layers/sheet.gd").new()
	s.setup("Eigene Bilddateien", Library.display_title(game), 760)
	s.subheading_raw = true      # Name des Spiels
	var gid := str(game.id)
	s.fill_func = func(sheet) -> void:
		var g := Library.get_game(gid)
		var imgs: Dictionary = g.get("images", {}) if g.get("images") is Dictionary else {}
		for kind in IMAGE_KINDS:
			var k: String = kind[0]
			var label_text: String = kind[1]
			var r = SettingRow.new()
			r.setup("action", label_text)
			r.icon_name = "image"
			r.set_meta("uz_key", "img:" + k)
			var custom := str(imgs.get(k, ""))
			r.value_text = custom.get_file() if custom != "" else "Automatisch"
			r.on_activate = func() -> void:
				main.open_file_browser("%s wählen" % label_text, false, func(path: String) -> void:
					var cur: Dictionary = (Library.get_game(gid).get("images", {}) as Dictionary).duplicate()
					cur[k] = path
					Library.set_field(gid, "images", cur)
					if is_instance_valid(sheet):
						sheet.refill()
				, ["png", "jpg", "jpeg", "webp"], Config.media_dir())
			sheet.add_row(r)
		if not imgs.is_empty():
			var reset = SettingRow.new()
			reset.setup("action", "Eigene Bilder entfernen")
			reset.icon_name = "trash"
			reset.on_activate = func() -> void:
				var snap := Library.snapshot([gid])
				Library.set_field(gid, "images", null)
				if is_instance_valid(sheet):
					sheet.refill()
				Undo.offer_games("Eigene Bilder entfernt", Library.display_title(game), "image", snap, sheet.refill if is_instance_valid(sheet) else Callable())
			sheet.add_row(reset)
		sheet.add_gap()
		sheet.add_label("PNG, JPG oder WebP. Ohne eigene Datei sucht Uzai selbst.", "s", "faint")
	s.closed.connect(refill)
	main.open_layer(s)


func _filter_name(id: String) -> String:
	if id == "":
		return "aus"
	return str(Config.filter(id).get("name", id))
