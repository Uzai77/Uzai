extends "res://src/main_fenster.gd"
## Hauptbildschirm, Schicht über main_fenster.gd: Ebenen öffnen (Dialog, Auswahl, Tastatur,
## Spielseite, Ordner, Chats, Zimmer …), selten gebrauchte Ebenen im Hintergrund vorladen und
## Spiele starten.

const GameOptions := preload("res://src/ui/layers/game_options.gd")
const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")
const ColorPick := preload("res://src/ui/layers/color_pick.gd")
const ChoiceList := preload("res://src/ui/layers/choice_list.gd")
const PowerMenu := preload("res://src/ui/layers/power_menu.gd")
const Dialog := preload("res://src/ui/layers/dialog.gd")
const InGame := preload("res://src/ui/in_game.gd")
const LaunchCard := preload("res://src/ui/layers/launch_card.gd")
const SystemIntro := preload("res://src/ui/components/system_intro.gd")
const IncomingCall := preload("res://src/ui/layers/incoming_call.gd")
const SheetLayer := preload("res://src/ui/layers/sheet.gd")
const LayerS := preload("res://src/ui/layers/layer.gd")
const ChatView := preload("res://src/ui/layers/chat_view.gd")
const GamePage := preload("res://src/ui/layers/game_page.gd")
const Raumton := preload("res://src/room/raumton.gd")
## Selten gebrauchte Ebenen: nicht vor dem ersten Bild laden (zusammen gut ein Drittel der
## Ladezeit von main), sondern kurz nach dem Start im Hintergrund (_preload_rare) bzw. spätestens
## bei der ersten Nutzung (_rare).
const RARE := {
	"video_player": "res://src/ui/layers/video_player.gd",
	"art_picker": "res://src/ui/layers/art_picker.gd",
	"art_picker_iidb": "res://src/ui/layers/art_picker_iidb.gd",
	"file_browser": "res://src/ui/layers/file_browser.gd",
	"keyboard": "res://src/ui/layers/keyboard.gd",
	"yt_login": "res://src/ui/layers/yt_login.gd",
	"nuvio_login": "res://src/ui/layers/nuvio_login.gd",
	"movie_sources": "res://src/ui/layers/movie_sources.gd",
	"plex_login": "res://src/ui/layers/plex_login.gd",
	"jellyfin_login": "res://src/ui/layers/jellyfin_login.gd",
	"stremio_login": "res://src/ui/layers/stremio_login.gd",
	"twitch_login": "res://src/ui/layers/twitch_login.gd",
	"stream_page": "res://src/ui/layers/stream_page.gd",
	"game_achievements": "res://src/ui/layers/game_achievements.gd",
	"movie_detail": "res://src/ui/layers/movie_detail.gd",
	"ra_login": "res://src/ui/layers/ra_login.gd",
	"launcher_offer": "res://src/ui/layers/launcher_offer.gd",
	"global_search": "res://src/ui/layers/global_search.gd",
	"add_game": "res://src/ui/layers/add_game.gd",
	"round_summary": "res://src/ui/layers/round_summary.gd",
	"browser": "res://src/ui/layers/browser.gd",
}
const SettingRowC := preload("res://src/ui/components/setting_row.gd")
const BrowserDaten := preload("res://src/core/browser_daten.gd")
const InstallFlow := preload("res://src/ui/install_flow.gd")

var layer_host: Control
var kid_time: Node            ## Spielzeit eines Kinderprofils (src/core/kid_time.gd)


# --- Ebenen ----------------------------------------------------------------------

func open_layer(layer: Control, first: Control = null) -> Control:
	if "main" in layer:
		layer.set("main", self)
	layer.open(layer_host, first)
	return layer


func open_game_options(g: Dictionary) -> void:
	var l = GameOptions.new()
	l.game = g
	open_layer(l)


func open_library(sub_id: String, label: String) -> void:
	var l = LibraryGrid.new()
	l.sub_id = sub_id
	l.label = label
	open_layer(l)


# --- Chats und Anrufe ----------------------------------------------------------------------------

func open_chat(f: Dictionary, login_only := false) -> void:
	if Config.kid_stop("chats"):
		return
	var l = ChatView.new()
	l.friend = f
	l.main = self
	l.login_only = login_only
	open_layer(l)


func open_incoming_call(info: Dictionary) -> void:
	for l in Nav.layers:
		if is_instance_valid(l) and l.get_script() == IncomingCall:
			return
	if not Voice.ringing.has(str(info.get("channel_id", ""))) and not Voice.demo:
		Toasts.show_toast("Anruf ist vorbei", "", "phone")
		return
	var l = IncomingCall.new()
	l.info = info
	open_layer(l)


## Chat mit einem Discord-Freund (Direktnachrichten über das Discord Social SDK).
## f: Eintrag aus DiscordChat.friends ({ id, name, avatar, state, game }).
func open_discord_chat(f: Dictionary) -> void:
	if Config.kid_stop("chats"):
		return
	var l = ChatView.new()
	l.friend = f
	l.kind = "discord"
	l.main = self
	open_layer(l)


# --- Ordner, Spielseite und weitere Ebenen -------------------------------------------------------

## Optionen eines Ordners: Spiele wählen, umbenennen, löschen.
func open_folder_options(f: Dictionary) -> void:
	var s = SheetLayer.new()
	var sys_name := str(Config.system(str(f.get("system", ""))).get("name", "Alle Systeme")) if str(f.get("system", "")) != "" else "Alle Systeme"
	s.setup(str(f.get("name", "Ordner")), "Ordner · " + sys_name, 760)
	s.fill_func = func(sheet) -> void:
		var fid := str(f.get("id", ""))
		var open = SettingRowC.new()
		open.setup("action", "Ordner öffnen")
		open.icon_name = "grid"
		open.on_activate = func() -> void:
			sheet.close()
			open_library("ordner:" + fid, str(f.get("name", "")))
		sheet.add_row(open)
		if f.get("auto", false):
			sheet.add_label("Automatischer Ordner aus dem Spieleordner.", "s", "muted")
			var off = SettingRowC.new()
			off.setup("toggle", "Unterordner als Ordner zeigen", "", true)
			off.icon_name = "folder"
			off.changed.connect(func(v: Variant) -> void:
				Config.set_system(str(f.system), "subfolders", bool(v))
				Library.changed.emit()
				sheet.close()
			)
			sheet.add_row(off)
			return
		var pick = SettingRowC.new()
		pick.setup("action", "Spiele auswählen")
		pick.icon_name = "check"
		pick.value_text = U.plural(Library.in_folder(fid).size(), "Spiel", "Spiele")
		pick.on_activate = func() -> void:
			sheet.close()
			open_folder_picker(fid)
		sheet.add_row(pick)
		var ren = SettingRowC.new()
		ren.setup("action", "Umbenennen")
		ren.icon_name = "edit"
		ren.on_activate = func() -> void:
			open_keyboard("Name des Ordners", str(f.get("name", "")), func(n: String) -> void:
				Library.rename_folder(fid, n)
				sheet.close()
			)
		sheet.add_row(ren)
		var del = SettingRowC.new()
		del.setup("action", "Ordner löschen")
		del.icon_name = "trash"
		del.on_activate = func() -> void:
			open_dialog("Ordner löschen?", "Der Ordner „%s“ wird entfernt. Die Spiele bleiben." % str(f.get("name", "")), [
				# Drittes Feld: zerstörerisch (dialog.gd kann es leise statt hell zeigen).
				["Löschen", func() -> void:
					var ids: Array = Library.games.filter(func(g): return fid in g.get("folders", [])).map(func(g): return str(g.get("id", "")))
					var snap := Library.snapshot(ids, true)
					Library.delete_folder(fid)
					sheet.close()
					Undo.offer_games("Ordner gelöscht", str(f.get("name", "")), "trash", snap), "danger"],
				["Abbrechen", func() -> void: pass],
			])
		sheet.add_row(del)
	open_layer(s)


## Spiele für einen Ordner an- und abhaken (Raster im Auswahlmodus).
func open_folder_picker(fid: String) -> void:
	var f := Library.folder(fid)
	var l = LibraryGrid.new()
	l.sub_id = "ordner:" + fid
	l.pick_folder = fid
	l.label = "„%s“ füllen" % str(f.get("name", "Ordner"))
	open_layer(l)


## In welchen Ordnern ein Spiel liegt, plus „Neuer Ordner“.
func open_game_folders(g: Dictionary, on_done: Callable = Callable()) -> void:
	var s = SheetLayer.new()
	s.setup("Ordner", Library.display_title(g), 720)
	var gid := str(g.get("id", ""))
	s.fill_func = func(sheet) -> void:
		var game := Library.get_game(gid)
		for f in Library.folders_for_game(game):
			var fid := str(f.id)
			var r = SettingRowC.new()
			r.setup("toggle", str(f.name), "", Library.is_in_folder(game, fid))
			r.icon_name = "folder"
			r.value_text = "Alle Systeme" if str(f.get("system", "")) == "" else ""
			r.changed.connect(func(v: Variant) -> void: Library.set_in_folder(gid, fid, bool(v)))
			sheet.add_row(r)
		if str(game.get("subdir", "")) != "" and Config.system(str(game.get("system", ""))).get("subfolders", true):
			sheet.add_label("Liegt außerdem automatisch in „%s“ (Unterordner auf der Festplatte)." % str(game.subdir), "s", "faint")
		sheet.add_gap()
		var sysname := str(Config.system(str(game.get("system", ""))).get("short", ""))
		for spec in [[str(game.get("system", "")), "Neuer Ordner für %s" % (sysname if sysname != "" else str(game.get("system", "")).capitalize())],
				["", "Neuer Ordner für alle Systeme"]]:
			var sys_id: String = spec[0]
			var nr = SettingRowC.new()
			nr.setup("action", spec[1])
			nr.icon_name = "plus"
			nr.on_activate = func() -> void:
				open_keyboard("Name des Ordners", "", func(n: String) -> void:
					var fid := Library.create_folder(n, sys_id)
					if fid != "":
						Library.set_in_folder(gid, fid, true)
					sheet.refill()
				)
			sheet.add_row(nr)
	if on_done.is_valid():
		s.closed.connect(on_done)
	open_layer(s)


## quelle: "sgdb" (SteamGridDB), "ss" (ScreenScraper, Emulator- und PC-Spiele) oder "iidb" (iiSU).
func open_art_picker(g: Dictionary, quelle := "sgdb") -> void:
	var l = _rare("art_picker_iidb" if quelle == "iidb" else "art_picker").new()
	l.game = Library.get_game(str(g.get("id", ""))) if not Library.get_game(str(g.get("id", ""))).is_empty() else g
	l.quelle = quelle
	open_layer(l)


## Ein Spiel öffnen: erst seine Seite (Bilder, Erfolge, Freunde), gestartet wird dort.
## Ohne Spielseite (Einstellungen → System) startet A direkt.
func open_game(g: Dictionary) -> void:
	if not game_page_on() or Launcher.in_game:
		launch(g)
		return
	var l = GamePage.new()
	l.game = g
	open_layer(l)


func game_page_on() -> bool:
	return bool(Config.get_value("system.game_page", true))


## Dein Zimmer (3D, src/room/zimmer.gd): erst beim Öffnen geladen, beim Spielen ganz entladen.
## Im Spiel nur über dem Guide (Uzai liegt dann durchsichtig vorn): Der Fernseher zeigt das Spiel.
## Einladung ins Zimmer eines Freundes, die über den Chat kam (Notify „Zimmer betreten“): die Seite
## „Zimmer online“ öffnen und dort wie bei einem eingetippten Code weitermachen – Abschottung prüfen,
## Hinweis zur IP-Adresse, erst dann anklopfen. t: { code, name }.
func zimmer_einladung_oeffnen(t: Dictionary) -> void:
	var l: Control = load("res://src/room/online_ui.gd").new()
	open_layer(l)
	l.call("einladung_aus_chat", str(t.get("code", "")))


## direkt: ohne den Weg über die Tür (main.open_room) – zurück nach einem Spiel, das im Zimmer gestartet wurde.
## Sonst steht man beim Hereinkommen immer am Anfang, nicht mehr dort, wo man zuletzt war (Meta „uz_anfang“).
func open_room(direkt := false) -> void:
	if (Launcher.in_game and not _overlay_mode) or _launching:
		return
	if room_layer():
		# Das Zimmer wartet hinter dem Spiel (Vollbild): zurück hinein, statt ein zweites zu öffnen.
		if _tv == "vollbild":
			tv_aufstehen()
		return
	var from: Control = Nav.focused()
	var z: Control = (Arbeit.geladen(ZIMMER) as GDScript).new()
	# Durch die Tür (zimmer_tuer.gd): Die Kamera tritt durch die Zimmertür herein, die Tür führt die Fahrt.
	# Aus einer Kachel (Live-Bild, Zimmer-Kachel): das Zimmer wächst aus ihrem Rechteck.
	var von := zimmer_kachel_rect(from)
	if not direkt and not Launcher.in_game:
		z.set_meta("uz_anfang", true)
	if from and from.has_meta("uz_tuer_fahrt"):
		z.set_meta("uz_tuer", true)
	elif von.size.x > 0.0:
		z.set_meta("uz_von", von)
	var l: Control = open_layer(z)
	# Im Spiel aus dem Guide: gleich „im Zimmer“ (fernsehspiel.gd) – der Guide darunter geht, das Spiel
	# läuft weiter, die Guide-Taste öffnet über dem Zimmer wieder den Guide.
	if Launcher.in_game:
		tv_aufstehen.call_deferred()
	# Das Zimmer blendet die Oberfläche dahinter aus und erst beim Verlassen wieder ein – B führt
	# dann zurück, wo man war (Reiter „Zimmer“, Kachel), statt ins Leere.
	l.tree_exited.connect(func() -> void:
		if is_instance_valid(from) and from.is_visible_in_tree() and Nav.top_layer() == null \
				and (Nav.focused() == null or not Nav.focused().is_visible_in_tree()):
			Nav.focus(from, true)
	, CONNECT_ONE_SHOT)


## Uzai-Browser (src/ui/layers/browser.gd, Wunschliste 120): eine Ebene über allem; von: die Startbühne
## (browser_view.gd), aus der er wächst ({ rect, marke, hoehe }, sonst Überblendung). url öffnet gleich eine
## Seite (Lesezeichen, angeheftete App mit ihrer Zoomstufe); allein: als eigenes Programm gestartet
## (--browser), Schließen beendet Uzai. Läuft er schon, kommt er nur nach vorn.
func open_browser(url := "", zoom := 0, allein := false, von: Dictionary = {}) -> void:
	if (Launcher.in_game and not _overlay_mode) or _launching:
		return
	if not BrowserDaten.verfuegbar():
		return
	Config.set_value("apps.last", "browser")
	var skript: Script = _rare("browser")
	for l in Nav.layers:
		if is_instance_valid(l) and l.get_script() == skript:
			return
	var b: Control = skript.new()
	b.set("start_url", url)
	b.set("start_zoom", zoom)
	b.set("allein", allein)
	b.set("von", von)
	open_layer(b)


## Das Rechteck (Schirm-Koordinaten) einer Kachel, die ins Zimmer führt (Live-Bild im Kopf der
## Apps, „Dein Zimmer“ auf der Startseite, im Bereich Zimmer); sonst ein leeres Rechteck.
static func zimmer_kachel_rect(c: Control) -> Rect2:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return Rect2()
	var key := str(c.get_meta("uz_key", ""))
	if not (key == "apps:zimmer" or key == "app:room" or key == "f:_zimmer" or key.begins_with("room:")):
		return Rect2()
	var r := U.sichtbar(c)
	return r if r.size.x >= 48.0 and r.size.y >= 48.0 else Rect2()


## Das Zimmer vorab laden (Skripte, im Hintergrund), sobald eine Kachel dorthin gewählt ist: Beim
## Betreten ist dann nur noch das Zimmer selbst zu bauen. Vor allem anderen, was noch vorlädt.
const ZIMMER := "res://src/room/zimmer.gd"


static func zimmer_vorladen() -> void:
	Arbeit.vorladen([ZIMMER], true)


## Das offene Zimmer (oder null).
func room_layer() -> Control:
	for l in Nav.layers:
		if is_instance_valid(l) and l.has_method("bauen_an"):
			return l
	return null


## Aus dem Zimmer ins laufende Spiel (zimmer_ansehen.gd zum_spiel): Die Kamera ist in den Fernseher
## gefahren, das Spielbild füllt den Schirm. Uzai legt das Zimmer still dahinter (es bleibt offen und
## zeichnet nichts, zimmer_basis.gd ruhen), schließt den Guide darüber und ruht; das Spiel kommt randlos
## nach vorn – nur, weil du es so gewählt hast. Die Guide-Taste holt das Zimmer zurück (tv_aufstehen).
## Ohne laufendes Spiel (Demo-Bild im Fernseher) geht das Zimmer zu.
func zimmer_zum_spiel(zimmer: Control) -> void:
	if not Launcher.in_game or not (_tv in ["startet", "zimmer"]):
		if Launcher.in_game and _guide and is_instance_valid(_guide):
			_guide.close()
		elif Launcher.in_game and _overlay_mode:
			_leave_overlay()
		if is_instance_valid(zimmer):
			zimmer.close()
		return
	_tv = Fernsehspiel.weiter(_tv, "vollbild")
	Launcher.log_launch("Fernseher: fokussiert – das Spiel liegt randlos vorn, das Zimmer wartet dahinter")
	if is_instance_valid(zimmer):
		zimmer.call("ruhen", true)
	_tv_melden()
	if _guide and is_instance_valid(_guide):
		_guide.close()          # _on_guide_closed → _leave_overlay → _park
	elif _overlay_mode:
		await _leave_overlay()
		Launcher.hide_filter(false)
	else:
		await _park()


## Zurück ins Zimmer (Guide-Taste im Vollbild, Guide › Dein Zimmer über dem Spiel): Du läufst im Zimmer,
## das Spiel läuft weiter und der Fernseher zeigt es (spielbild.gd). Uzai liegt durchsichtig vorn und hat
## den Fokus; der Guide darunter bzw. darüber geht zu, ohne das Zimmer mitzunehmen. Wartete das Zimmer
## hinter dem Spiel, fährt die Kamera aus dem Fernseher an deinen Platz (zimmer_ansehen.gd aus_dem_spiel).
## Zurück ins Spiel: A am Fernseher bzw. Guide › Zum Spiel (tv_vollbild).
func tv_aufstehen() -> void:
	var zim := room_layer()
	if not Launcher.in_game or zim == null or _tv == "zimmer":
		return
	var aus_dem_spiel := _tv == "vollbild"
	_tv = Fernsehspiel.weiter(_tv, "aufstehen")
	if _tv != "zimmer":
		return
	if not _overlay_mode:
		_enter_overlay()
	if _guide and is_instance_valid(_guide):
		# Das Zimmer im Stapel vor den Guide: Der Guide schließt sonst alles, was über ihm liegt.
		var gi := Nav.layers.find(_guide)
		var zi := Nav.layers.find(zim)
		if gi >= 0 and zi > gi:
			Nav.layers.remove_at(zi)
			Nav.layers.insert(gi, zim)
		_guide.close()          # _on_guide_closed: das Spiel läuft weiter, Uzai bleibt vorn
	if aus_dem_spiel:
		zim.call("aus_dem_spiel")
	_tv_melden()


## Ins Spiel als eigene Handlung (Guide › Zum Spiel): der Guide geht, die Kamera fährt in den Fernseher.
func tv_vollbild() -> void:
	var zim := room_layer()
	if not Launcher.in_game or zim == null or _tv != "zimmer":
		return
	if _guide and is_instance_valid(_guide):
		_guide.close()
	zim.call("zum_spiel")


## Das Zimmer ging zu, während das Spiel lief (aufgestanden oder dahinter wartend): ein Spiel wie jedes
## andere – Uzai ruht, das Spiel kommt nach vorn, die Guide-Taste öffnet wieder den Guide.
func tv_zimmer_zu() -> void:
	if not (_tv in ["zimmer", "vollbild"]) or room_layer() != null:
		return
	var war := _tv
	_tv = Fernsehspiel.weiter(_tv, "ende")
	if not Launcher.in_game or war != "zimmer":
		return
	if _guide and is_instance_valid(_guide):
		return                   # der Guide liegt vorn; schließt er, geht es wie sonst ins Spiel
	if _overlay_mode:
		_leave_overlay()
		Launcher.hide_filter(false)


func open_game_achievements(g: Dictionary) -> void:
	var l = _rare("game_achievements").new()
	l.game = g
	open_layer(l)


## kuerzel: Textstücke als eigene Tasten über dem Tastenfeld (keyboard.gd kuerzel_fuer).
func open_keyboard(head: String, text: String, cb: Callable, secret := false, link := "", kuerzel: Array = []) -> void:
	var l = _rare("keyboard").new()
	l.heading = head
	l.text = text
	l.secret = secret
	l.phone_link = link
	l.kuerzel = kuerzel
	l.done.connect(cb)
	open_layer(l)


## Die Suche über alles (src/ui/layers/global_search.gd): R3, F oder die Lupe oben rechts.
func open_search(q := "") -> void:
	var l = _rare("global_search").new()
	l.query = q
	open_layer(l)


func open_file_browser(head: String, want_dir: bool, cb: Callable, exts: Array = [], start := "") -> void:
	var l = _rare("file_browser").new()
	l.heading = head
	l.want_dir = want_dir
	l.exts = exts
	l.start_dir = start
	l.picked.connect(cb)
	open_layer(l)


func open_color_picker(head: String, color: Color, cb: Callable) -> void:
	var l = ColorPick.new()
	l.heading = head
	l.color = color
	l.picked.connect(cb)
	open_layer(l)


## Alle Ebenen schließen (vor einem Spielstart, dem Player, einem Wechsel), auf Wunsch nur die über
## „bis“. Höchstens EBENEN_ZU_BILDER Bilder lang: Die Schleife stand sechsmal ohne Grenze da – eine
## Ebene, die nicht zugeht, hielt die wartende Funktion für immer fest, und der Start kam nie.
const EBENEN_ZU_BILDER := 90


func alle_ebenen_zu(bis: Control = null) -> bool:
	var n := 0
	while Nav.top_layer() and Nav.top_layer() != bis:
		if n >= EBENEN_ZU_BILDER:
			push_warning("Ebene geht nicht zu: %s" % str(Nav.top_layer().get_script().resource_path if Nav.top_layer().get_script() else Nav.top_layer()))
			return false
		Nav.top_layer().close()
		n += 1
		await get_tree().process_frame
	return true


func open_choice(head: String, options: Array, current_value: Variant, cb: Callable, sub := "") -> Control:
	var l = ChoiceList.new()
	l.setup(head, sub)
	l.options = options
	l.value = current_value
	l.picked.connect(cb)
	open_layer(l)
	return l


## icon/tone: Zeichen über der Überschrift, „warn“ oder „danger“ färbt es (z. B. Startfehler).
func open_dialog(head: String, text: String, buttons: Array, icon := "", tone := "") -> Control:
	var l = Dialog.new()
	l.heading = head
	l.text = text
	l.buttons = buttons
	l.icon_name = icon
	l.tone = tone
	open_layer(l)
	return l


## Gekauftes Spiel (Steam oder Epic) installieren – über Uzai, ohne fremdes Fenster (Installs,
## InstallFlow). Fertig installiert erscheint das Spiel von selbst, mit Mitteilung und „Spielen“.
func install_epic(g: Dictionary) -> void:
	if str(g.get("source", "")) == "epic" and Library.EpicScanner.install_uri(g) == "":
		Toasts.show_toast("Nicht installierbar",
				"Für %s fehlen die Angaben des Epic Games Launchers. Das Spiel einmal im Epic Games Launcher installieren." % Library.display_title(g), "warning")
		return
	InstallFlow.begin(self, g)


## Im Fenster des Epic Games Launchers „Ohne Launcher installieren“ gewählt: Uzais eigener Installer.
func install_epic_uzai(g: Dictionary) -> void:
	InstallFlow.begin_uzai(self, g)


## Vor dem Start eines Programms, das Adminrechte verlangt: Windows zeigt dann seine Abfrage auf
## dem gesicherten Desktop, die nur Maus oder Tastatur bedienen – mit dem Controller hing man fest.
## Uzai sagt das vorher. true = starten.
func _confirm_admin(name_: String, exe: String) -> bool:
	var keep := Nav.game_mode
	Nav.game_mode = false
	var box := { "done": false, "ok": false }
	var l := open_dialog("%s braucht Administratorrechte" % name_, "Windows fragt nach Administratorrechten. Bestätigen mit Maus oder Tastatur.", [
		["Trotzdem starten", func() -> void:
			box.ok = true
			box.done = true],
		["Immer starten", func() -> void:
			var ok_list: Array = (Config.get_value("launcher.admin_ok", []) as Array).duplicate()
			if not ok_list.has(exe):
				ok_list.append(exe)
			Config.set_value("launcher.admin_ok", ok_list)
			box.ok = true
			box.done = true],
		["Abbrechen", func() -> void: box.done = true],
	], "warning", "warn")
	l.closed.connect(func() -> void: box.done = true)
	while not bool(box.done):
		await get_tree().process_frame
	Nav.game_mode = keep
	return bool(box.ok)


func open_power() -> void:
	var l = PowerMenu.new()
	l.main = self
	open_layer(l)


# --- Selten gebrauchte Ebenen im Hintergrund laden -----------------------------------------------

## Selten gebrauchte Ebenen im Hintergrund laden, eine nach der anderen (kein Ruckler). Zuerst, was
## die Reiter des Guides beim Aufbau laden: Der Guide kann gleich nach dem Start aufgehen.
func _preload_rare() -> void:
	load("res://src/ui/layers/guide.gd").vorladen()
	Arbeit.vorladen(RARE.values())


## Skript einer selten gebrauchten Ebene: vorgeladen, sonst lädt es jetzt.
func _rare(key: String) -> GDScript:
	return Arbeit.geladen(str(RARE[key])) as GDScript


# --- Spielstart --------------------------------------------------------------

## im_fernseher: im Zimmer eingelegt – das Spiel läuft auf dem Fernseher dort (fernsehspiel.gd), das
## Zimmer bleibt offen und deckt den Start ab statt der Spielstart-Karte.
func launch(g: Dictionary, im_fernseher := false) -> void:
	# Zweimal schnell A (Spielseite, Cover) startete sonst zwei Ladebildschirme und zwei Spiele.
	if Launcher.in_game or _launching:
		return
	# Dasselbe Spiel in mehreren Launchern (src/library/stores.gd): beim ersten Start fragen, über
	# welchen – danach startet A direkt (änderbar auf der Spielseite unter „Starten über“).
	if str(g.get("launch_via", "")) == "" and Library.alternatives(Library.get_game(str(g.get("id", "")))).size() > 1:
		ask_launch_via(g, func(via: String) -> void:
			var g2 := g.duplicate()
			g2["launch_via"] = via
			launch(g2, im_fernseher))
		return
	# Kinderprofil: Altersstufe und Spielzeit je Tag (src/core/kid_time.gd) – freundlich, nie erzwungen.
	if Config.is_kid() and kid_time:
		_launching = true
		var ok: bool = await kid_time.may_launch(g)
		_launching = false
		if not ok:
			return
	_launching = true
	# Bild in Bild bleibt beim Spielstart (es liegt dann über dem Spiel); Video-Ton im Hintergrund
	# endet (das Spiel bringt seinen eigenen Ton).
	if Video.watching() or (Video.active and Video.background):
		await Video.stop()
	if not Library.is_installed(g):
		# Gekauft, nicht installiert (Steam, Epic): nie starten, sondern über Uzai installieren.
		_launching = false
		install_epic(g)
		return
	var zim := room_layer() if im_fernseher else null
	if zim:
		# Nur was über dem Zimmer liegt, schließt; das Zimmer selbst deckt den Start ab.
		await alle_ebenen_zu(zim)
		_ingame = null
		Nav.game_mode = true
		set_meta("zimmer_zurueck", true)
		_tv = Fernsehspiel.weiter("", "einlegen")
		_cover("start", true)
		_tv_melden()
		await Launcher.launch(g)
		_launching = false
		if not Launcher.in_game:
			_tv = Fernsehspiel.weiter(_tv, "ende")
			_tv_melden()
		return
	await alle_ebenen_zu()
	Sfx.play("launch")
	spielstart_zeigen(g)
	Nav.game_mode = true
	# Ab jetzt bleibt der Startbildschirm vorn, bis das Spiel wirklich da ist (siehe _cover).
	_cover("start", true)
	await Launcher.launch(g)
	_launching = false
	# Die Hinweisleiste gehörte bis eben zum Cover dahinter: neu lesen (im Spiel nur „Guide“).
	Nav.focus_moved.emit(Nav.focused())


## Der sichtbare Spielstart (Plan „Gefühl“: Spielen holt das Bild nach vorn). Spielstart-Karte
## (Bild, Logo, feine Leiste; launch_card.gd) oder der schlichte Ladebildschirm. Mit der Karte: Das Bild des
## Spiels, das schon weich hinter der Startseite liegt, füllt in T_RAUM den Schirm (background.gd
## nach_vorn), die Oberfläche tritt zurück und geht in T_WEG; die Karte kommt aus dem Bild
## (aus_dem_bild), danach Schwarz wie bisher (hand_over). Ohne Bild blendet sie wie bisher ein.
func spielstart_zeigen(g: Dictionary) -> Control:
	var card := bool(Config.get_value("system.launch_card", true))
	_ingame = LaunchCard.new() if card else InGame.new()
	_ingame.game = g
	U.full_rect(_ingame)
	layer_host.add_child(_ingame)
	# Startanimation je System (Punkt 17): liegt kurz über dem Ladebildschirm; das Spiel startet
	# gleichzeitig, nichts wartet auf sie.
	var intro: Control = null
	if SystemIntro.soll(g, str(Config.get_value("theme.system_intro", "theme")), Leicht.active, U.reduziert()):
		intro = SystemIntro.new().setup(g)
		U.full_rect(intro)
		_ingame.add_child(intro)
	Toasts.unruhe(U.T_RAUM)
	# Mit Startanimation des Systems deckt die den Schirm: dann blendet die Karte samt ihr ein.
	if card and intro == null and _ingame.has_method("aus_dem_bild") and is_instance_valid(background) \
			and bool(background.nach_vorn(g)):
		_ingame.call("aus_dem_bild")
		# Die Oberfläche tritt zurück (wie hinter einer Ebene) und geht; das Bild bleibt.
		U.stop(shell, "uz_depth")
		shell.pivot_offset = shell.size * 0.5
		var tw := U.weg(shell, "uz_spielstart").set_parallel(true)
		tw.tween_property(shell, "modulate:a", 0.0, U.T_WEG)
		tw.tween_property(shell, "scale", Vector2.ONE * U.wachsen(LayerS.DEPTH_SCALE), U.T_WEG).set_trans(Tween.TRANS_CUBIC)
		return _ingame
	# Weich einblenden statt in einem Bild von der Startseite auf den Ladebildschirm zu springen.
	_ingame.modulate.a = 0.0
	U.ankommen(_ingame, U.T_ORT, "uz_spielstart").tween_property(_ingame, "modulate:a", 1.0, U.T_WEG if card else U.T_ORT)
	return _ingame


## Über welchen Launcher starten? Die Wahl bleibt am Spiel (launch_via). done bekommt die Quelle.
func ask_launch_via(g: Dictionary, done: Callable) -> void:
	var lib_g := Library.get_game(str(g.get("id", "")))
	if lib_g.is_empty():
		return
	var opts: Array = []
	for a in Library.alternatives(lib_g):
		var t := Library.time_in(a)
		opts.append([str(a.get("source", "")), Library.store_name(a, false, "PC"), U.playtime(t) if t > 0 else tr("Dort noch nicht gespielt")])
	open_choice("Starten über", opts, str(lib_g.get("launch_via", lib_g.get("source", ""))), func(v: Variant) -> void:
		Library.set_field(str(lib_g.id), "launch_via", str(v))
		done.call(str(v)), "Dieses Spiel gibt es in mehreren Launchern.")


func _on_launch_state(text: String) -> void:
	if _ingame and is_instance_valid(_ingame):
		_ingame.set_status(text)
	elif _tv == "startet" and room_layer():
		room_layer().call("tv_status", text)


## Das Spielfenster ist da (Launcher.window_ready): kurz auf Schwarz blenden, dann aus dem Weg.
## Vorher zeigte Uzai nach festen 2,5 s den Desktop, während Steam noch startete.
var _launching := false


func _on_game_window(_g: Dictionary) -> void:
	# Kam der Ton dieses Spiels beim letzten Mal aus dem Fernseher und stürzte Uzai dabei ab: zurück.
	Raumton.aufraeumen()
	if _ingame and is_instance_valid(_ingame):
		_ingame.set_running()
	# Im Zimmer eingelegt: Uzai bleibt vorn, die Kamera fährt in den Fernseher, dann liegt das Spiel
	# randlos vorn (zimmer_zum_spiel).
	if _tv == "startet" and Launcher.in_game and _guide == null and not _overlay_mode:
		_tv_einsteigen()
		return
	if not Config.is_windows() or not Launcher.in_game or _guide != null or _parked or _overlay_mode:
		return
	if _ingame and is_instance_valid(_ingame) and _ingame.has_method("hand_over"):
		# Spielstart-Karte: blendet selbst in 0,3 s auf Schwarz, dann gibt Uzai ab. Der Schleier
		# kommt leicht versetzt mit (endet zugleich) und nimmt die Hinweisleiste mit ins Schwarz.
		get_tree().create_timer(0.08).timeout.connect(func() -> void:
			if Launcher.in_game and not _parked and _guide == null and not _overlay_mode:
				_veil(true))
		await _ingame.hand_over()
	else:
		await _veil(true)
	if Launcher.in_game and _guide == null and not _overlay_mode and not _parked:
		# Vorhang zu, bevor Uzai durchsichtig wird und sich wegräumt: Zeigt das Spiel noch nicht den
		# ganzen Bildschirm (Startfenster, Fenstermodus, Starter), bleibt um es herum Schwarz statt
		# Desktop und Taskleiste; deckt es ihn, geht der Vorhang von selbst. Läuft schon ein Bildfilter,
		# deckt ShaderGlass den Bildschirm – ein Vorhang darüber zeigte vom gefilterten Bild nur den
		# Ausschnitt über dem Emulatorfenster (Emulator im Fenster), bis er nach Sekunden ging.
		# Eigene App: Uzai bleibt als Kulisse dahinter (_park → _kulisse_zeigen), kein Vorhang nötig.
		var app := Launcher.is_app(Launcher.current)
		if not Launcher.filter_active() and not app:
			await _vorhang("start" if Launcher.window_is_game else "starter")
		await _park()
		if app:
			app_hinweis()
		# Mauszeiger aus dem Bild (an den Bildschirmrand), wenn mit dem Controller gespielt wird.
		# Erst jetzt: Über Uzai bewegt, hätte er Uzais versteckten Zeiger wieder eingeblendet.
		if Nav.device == "pad" and Config.get_value("controller.hide_mouse", true):
			Helper.run("cursor-park", { "hwnd": Launcher.game_hwnd() })
	_veil(false)
