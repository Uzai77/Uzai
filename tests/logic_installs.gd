extends Node
## Installieren über Uzai ohne Windows: Steams appmanifest (Stand, Tempo, Fertig), das appmanifest
## für einen gewählten Ordner, Steams ClientComm-Dienst (Sitzung dieses PCs, Fern-Download,
## Pausieren – gegen einen nachgebauten Web-API-Server im selben Prozess), Epics Pending-Manifest
## und Launcher-Protokoll, Knöpfe und Fenster der Installationsdialoge, Größen und Restzeit.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_installs.tscn → „Ergebnis: alles ok“
## Was nur unter Windows läuft (UI Automation, Fenster minimieren, PrintWindow, Tasten an ein
## Fenster), prüft diese Datei nicht – siehe docs/README.de.md „Noch nicht auf echtem Windows getestet“.

const P := preload("res://src/core/install_parse.gd")
const VDF := preload("res://src/library/vdf.gd")
const PORT := 18788
const ME := "76561198000000001"

var fails := 0
var root := ""
var srv := TCPServer.new()
var conns: Array = []
var seen: Array = []          ## { method, path, query, body }


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _ready() -> void:
	root = Config.path("installs-test")
	print("Steam: appmanifest lesen")
	_steam_state()
	print("Steam: appmanifest für einen gewählten Ordner")
	_steam_manifest()
	print("Steam: ClientComm-Antworten")
	_clientcomm_parse()
	print("Epic: Pending-Manifest, Protokoll, Standardordner")
	_epic()
	print("Dialoge: Knöpfe und Fenster")
	_dialogs()
	print("Tempo, Restzeit, Größen")
	_numbers()
	print("Installs: Fortschritt und Fertig aus dem appmanifest")
	await _installs_poll()
	print("Installs: Fern-Download über die Web-API (nachgebauter Server)")
	await _installs_remote()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _steam_state() -> void:
	var s := P.steam_state({ "StateFlags": "1026", "BytesToDownload": "9663676416", "BytesDownloaded": "3758096384" })
	check(str(s.phase) == "downloading" and str(s.text) == "Wird geladen · 38 % · 3,5 GB von 9,0 GB", "lädt: %s" % s.text)
	var paused := P.steam_state({ "StateFlags": "1538", "BytesToDownload": "1000", "BytesDownloaded": "10" })
	check(str(paused.phase) == "paused" and str(paused.text).begins_with("Pausiert"), "512: pausiert")
	var q := P.steam_state({ "StateFlags": "2" })
	check(str(q.phase) == "queued" and float(q.frac) < 0.0, "nur „Aktualisierung nötig“, nichts begonnen: Warteschlange")
	var prep := P.steam_state({ "StateFlags": "1026" })
	check(str(prep.phase) == "preparing", "begonnen, noch keine Größe: bereitet vor")
	var inst := P.steam_state(
			{ "StateFlags": str(2 | 1024 | 4194304), "BytesToDownload": "500", "BytesDownloaded": "500", "BytesToStage": "1000", "BytesStaged": "250" })
	check(str(inst.phase) == "installing" and absf(float(inst.frac) - 0.25) < 0.001 and str(inst.text).begins_with("Wird installiert"),
			"alles geladen, Steam schreibt: installiert (%s)" % inst.text)
	var done := P.steam_state({ "stateflags": "4", "BytesToDownload": "5", "BytesDownloaded": "5" })
	check(bool(done.done) and str(done.phase) == "done", "4: fertig (Schlüssel ohne Groß/klein)")
	check(not bool(P.steam_state({ "StateFlags": "6" }).done), "4 + 2: Aktualisierung nötig, nicht fertig")


func _steam_manifest() -> void:
	var text := P.steam_manifest_text(1145360, "Hades \"II\"", "Hades II", ME)
	var st: Dictionary = VDF.get_ci(VDF.parse(text), "AppState", {})
	check(str(st.get("appid", "")) == "1145360" and str(st.get("StateFlags", "")) == "1026", "appid und StateFlags 1026")
	check(str(st.get("installdir", "")) == "Hades II" and str(st.get("LastOwner", "")) == ME, "installdir und Besitzer")
	check(str(st.get("name", "")) == "Hades \"II\"", "Anführungszeichen im Namen bleiben heil")
	check(not bool(P.steam_state(st).done) and str(P.steam_state(st).phase) == "preparing", "so ein Manifest heißt für Uzai „bereitet vor“")
	check(P.install_dir_name("Half-Life 2: Episode One") == "Half-Life 2 Episode One", "Doppelpunkt fällt weg")
	check(P.install_dir_name("Star Wars™ Outlaws...") == "Star Wars Outlaws", "Markenzeichen und Punkte am Ende fallen weg")
	check(P.install_dir_name("CON") == "" and P.install_dir_name("???") == "", "verbotene Namen: leer")


func _clientcomm_parse() -> void:
	var sess := [
		{ "client_instanceid": "1234567890123456789", "machine_name": "WOHNZIMMER", "os_name": "Windows 11" },
		{ "client_instanceid": "18446744073709551000", "machine_name": "laptop", "os_name": "Windows 10" },
	]
	check(P.pick_session(sess, "laptop", false) == "18446744073709551000", "gleicher Rechnername (groß/klein egal)")
	check(P.pick_session(sess, "BUERO", true) == "", "zwei fremde Sitzungen: keine (nie auf dem falschen PC)")
	check(P.pick_session([sess[0]], "BUERO", true) == "1234567890123456789", "eine Sitzung und Steam läuft hier: diese")
	check(P.pick_session([sess[0]], "BUERO", false) == "", "eine Sitzung, Steam hier aus: keine")
	check(P.pick_session([sess[0], { "client_instanceid": "7", "machine_name": "Uzai" }], "BUERO", true) == "1234567890123456789",
			"Uzais eigene Sitzung zählt nicht mit")
	check(P.u64_text(P.u64_parse("18446744073709551000")) == "18446744073709551000", "64 Bit ohne Vorzeichen hin und zurück")
	var js := P.sessions_from_json({ "response": { "sessions": [{ "client_instanceid": "99", "machine_name": "PC", "os_name": "Windows" }] } })
	check(js.size() == 1 and str(js[0].client_instanceid) == "99", "Sitzungen aus der Web-API")
	var inner := PackedByteArray()
	inner.append_array(SteamCM.Pb.f_varint(1, P.u64_parse("18446744073709551000")))
	inner.append_array(SteamCM.Pb.f_string(3, "Windows 11"))
	inner.append_array(SteamCM.Pb.f_string(4, "WOHNZIMMER"))
	var body := SteamCM.Pb.f_msg(1, inner)
	var pb := P.sessions_from_pb(SteamCM.Pb, body)
	check(pb.size() == 1 and str(pb[0].client_instanceid) == "18446744073709551000" and str(pb[0].machine_name) == "WOHNZIMMER",
			"Sitzungen aus protobuf (Chat-Server)")
	var app := P.client_app(
			{ "response": { "apps": [{ "appid": 10, "bytes_downloaded": "1" }, { "appid": 620, "bytes_downloaded": "5368709120",
					"bytes_to_download": "10737418240",
		"bytes_download_rate": 31457280, "estimated_seconds_remaining": 171, "download_paused": false }] } }, 620)
	check(float(app.got) == 5368709120.0 and float(app.total) == 10737418240.0 and float(app.rate) == 31457280.0 and float(app.eta) == 171.0,
			"GetClientAppList: Bytes, Tempo, Restzeit")
	check(P.client_app({ "response": {} }, 620).is_empty() and P.client_app(null, 1).is_empty(), "leere Antwort: nichts")


func _epic() -> void:
	var item := """{ "FormatVersion": 0, "AppName": "Fortnite", "DisplayName": "Fortnite", "InstallLocation": "C:\\\\Program Files\\\\Epic Games\\\\Fortnite", "InstallSize": 32212254720, "bIsIncompleteInstall": true }"""
	var pe := P.epic_pending_parse(item)
	check(str(pe.app) == "Fortnite" and float(pe.size) == 32212254720.0 and str(pe.location) == "C:/Program Files/Epic Games/Fortnite",
			"Pending-Manifest: App, Größe, Ordner")
	write(root.path_join("Manifests/Pending/ABC.item"), item)
	write(root.path_join("Manifests/Pending/DEF.item"), "{ \"AppName\": \"Other\" }")
	write(root.path_join("Manifests/Pending/kaputt.item"), "{ nicht json")
	check(str(P.epic_pending(root.path_join("Manifests"), "Fortnite").get("app", "")) == "Fortnite", "Pending-Ordner: das richtige Spiel")
	check(P.epic_pending(root.path_join("Manifests"), "Gibtsnicht").is_empty(), "anderes Spiel: nichts")
	var log := "\n".join([
		"[2026.10.17-10.00.01:000][  1]LogHttp: Download of https://example/launcher 100%",
		"[2026.10.17-10.00.02:000][  2]LogInstall: Fortnite: Downloading 12.5 GB of 30.0 GB (41.7%) at 25.0 MB/s",
		"[2026.10.17-10.00.03:000][  3]LogPortal: Library refreshed 100%",
	])
	var lp := P.epic_log_progress(log, "Fortnite")
	check(absf(float(lp.frac) - 12.5 / 30.0) < 0.001 and float(lp.speed) == 25000000.0, "Zeile mit App-Name: GB von GB und Tempo (%s)" % JSON.stringify(lp))
	var lp2 := P.epic_log_progress("[x]LogBuildPatchServices: Progress 63.5% Downloading\n[y]LogPortal: done 100%", "Fortnite")
	check(absf(float(lp2.frac) - 0.635) < 0.001, "ohne App-Name: Ladezeile mit Prozent (nicht die fremde 100 %)")
	check(P.epic_log_progress("[x]LogPortal: Library refreshed 100%\n[y]LogSelfUpdate: Download 50%", "Fortnite").is_empty(),
			"fremde Zeilen und Selbstaktualisierung: nichts")
	check(P.epic_log_progress("[x]LogUninstall: Fortnite 30%", "Fortnite").is_empty(), "Deinstallieren zählt nicht")
	var ini := "[RememberMe]\nEnable=False\n[Launcher]\nDefaultAppInstallLocation=D:\\Spiele\\Epic\nShowGameLibrary=True\n"
	check(P.epic_default_dir(ini) == "D:/Spiele/Epic", "Standardordner aus GameUserSettings.ini")
	check(P.epic_default_dir("[Other]\nDefaultAppInstallLocation=X\n") == "", "nur im Abschnitt [Launcher]")
	write(root.path_join("size/a.bin"), "12345")
	write(root.path_join("size/sub/b.bin"), "1234567890")
	check(P.dir_size(root.path_join("size")) == 15, "Ordnergröße mit Unterordnern")
	# Eine Verknüpfung im Ordner (hier: zurück auf ihn selbst) zählt nicht mit.
	var mit_link := root.path_join("size")
	if DirAccess.open(mit_link).create_link(mit_link, mit_link.path_join("schleife")) == OK:
		check(P.dir_size(mit_link) == 15, "Ordnergröße: Verknüpfungen werden nicht verfolgt")
		DirAccess.remove_absolute(mit_link.path_join("schleife"))


func _dialogs() -> void:
	check(P.dialog_kind("Installieren") == "install" and P.dialog_kind("INSTALL") == "install" and P.dialog_kind("Weiter >") == "next",
			"Installieren, Install, Weiter >")
	check(P.dialog_kind("Deinstallieren") == "" and P.dialog_kind("Uninstall") == "", "Deinstallieren nie")
	check(P.dialog_kind("Ich stimme zu") == "agree" and P.dialog_kind("I AGREE") == "agree", "Lizenz erkannt")
	check(P.dialog_kind("Abbrechen") == "cancel" and P.dialog_kind("Minimieren") == "window" and P.dialog_kind("Schließen") == "window",
			"Abbrechen, Fensterknöpfe")
	var steam := [
		{ "i": 0, "name": "Minimieren", "enabled": true }, { "i": 1, "name": "Schließen", "enabled": true },
		{ "i": 2, "name": "Durchsuchen", "enabled": true }, { "i": 3, "name": "Installieren", "enabled": true },
		{ "i": 4, "name": "Abbrechen", "enabled": true },
	]
	var p1 := P.dialog_pick(steam)
	check(int(p1.get("i", -1)) == 3 and str(p1.kind) == "install", "Steam-Dialog: „Installieren“")
	check(P.dialog_pick([{ "i": 0, "name": "Installieren", "enabled": false }, { "i": 1, "name": "Abbrechen", "enabled": true }]).is_empty(),
			"ausgegrauter Knopf: nicht drücken")
	var eula := [{ "i": 0, "name": "Ich stimme zu", "enabled": true }, { "i": 1, "name": "Ich lehne ab", "enabled": true },
			{ "i": 2, "name": "Abbrechen", "enabled": true }]
	check(P.dialog_pick(eula).is_empty(), "Lizenz: Uzai drückt nichts selbst")
	var ch := P.dialog_choices(eula)
	check(ch.size() == 3 and str(ch[0].kind) == "agree" and str(ch[2].kind) == "cancel", "Lizenz: Auswahl in Uzai, Abbrechen zuletzt")
	var epic := [{ "i": 0, "name": "Installieren", "enabled": true }, { "i": 1, "name": "Installieren", "enabled": true },
			{ "i": 2, "name": "Abbrechen", "enabled": true }]
	check(P.dialog_pick(epic).is_empty(), "zwei „Installieren“ (Bibliothek dahinter): keiner, du wählst")
	var epic2 := [{ "i": 0, "name": "Installieren", "enabled": true, "offscreen": true }, { "i": 1, "name": "Installieren", "enabled": true,
			"offscreen": false }]
	check(int(P.dialog_pick(epic2).get("i", -1)) == 1, "zwei, aber nur einer sichtbar: der sichtbare")
	check(int(P.dialog_pick([{ "i": 5, "name": "Weiter >", "enabled": true }, { "i": 6, "name": "< Zurück", "enabled": true }]).get("i", -1)) == 5,
			"alter Steam-Dialog: Weiter")
	var wins := [
		{ "hwnd": 1, "title": "Steam", "w": 1600, "h": 900 },
		{ "hwnd": 2, "title": "Freundesliste", "w": 400, "h": 800 },
		{ "hwnd": 3, "title": "Installieren – Hades II", "w": 760, "h": 560 },
	]
	check(int(P.steam_dialog_pick(wins, [1, 2], "Hades II").get("hwnd", 0)) == 3, "Steam: das Installationsfenster")
	check(int(P.steam_dialog_pick([{ "hwnd": 7, "title": "Hades II", "w": 760, "h": 560 }], [], "Hades II").get("hwnd", 0)) == 7,
			"neues Fenster mit dem Spieltitel")
	check(P.steam_dialog_pick([wins[0], wins[1]], [1, 2], "Hades II").is_empty(), "nur Hauptfenster und Freunde: keins")
	# Steam fragt vor dem Spielstart (Startoptionen): das neue Fenster in Dialoggröße.
	var vor := [{ "hwnd": 1, "title": "Steam", "w": 1600, "h": 900 }, { "hwnd": 2, "title": "Freundesliste", "w": 320, "h": 700 },
		{ "hwnd": 5, "title": "Skyrim", "w": 620, "h": 380 }, { "hwnd": 6, "title": "Sonderangebote", "w": 1500, "h": 1050 },
		{ "hwnd": 8, "title": "Alt", "w": 500, "h": 300 }, { "hwnd": 9, "title": "Klein", "w": 120, "h": 40 }, { "hwnd": 10, "title": "Weg", "w": 500,
				"h": 300, "min": true }]
	check(int(P.steam_start_dialog(vor, [1, 2, 8]).get("hwnd", 0)) == 5,
			"Start: neues Fenster in Dialoggröße (nicht Hauptfenster, Freunde, altes, winziges, minimiertes, riesiges)")
	check(P.steam_start_dialog([vor[0], vor[1], vor[4]], [1, 2, 8]).is_empty() and P.steam_start_dialog([{ "hwnd": 3, "title": "Steam", "w": 600,
			"h": 400 }], []).is_empty(),
			"Start: ohne neues Fenster keins; ein neues Hauptfenster zählt nicht")
	var spielen := [{ "name": "Spielen", "enabled": true }, { "name": "Abbrechen", "enabled": true }]
	check(P.start_dialog_urteil(spielen, false, 1000) == "warten" and P.start_dialog_urteil(spielen, false, 3000) == "zeigen",
			"Startoptionen: erst kurz warten, dann in Uzai zeigen")
	check(P.start_dialog_urteil([{ "name": "Abbrechen", "enabled": true }], true, 9000) == "lassen"
			and P.start_dialog_urteil([{ "name": "Überspringen", "enabled": true }, { "name": "Schließen", "enabled": true }], true, 9000) == "lassen",
			"nur Abbrechen oder Überspringen (Steam arbeitet): nicht stören")
	check(P.start_dialog_urteil([{ "name": "Normal starten", "enabled": true }, { "name": "Mit Mods starten", "enabled": true }], false, 3000) == "zeigen",
			"zwei eigene Knöpfe (Startarten): zeigen")
	check(P.start_dialog_urteil([{ "name": "Play", "enabled": false }, { "name": "Cancel", "enabled": true }], false, 3000) == "lassen",
			"gesperrter Knopf zählt nicht")
	check(P.start_dialog_urteil([], true, 4000) == "warten" and P.start_dialog_urteil([], true, 7000) == "zeigen" and P.start_dialog_urteil([], false,
			7000) == "lassen",
			"nichts lesbar: nur mit dem Spielnamen im Titel und erst nach längerem Warten zeigen")
	check(P.steam_dialog_pick([{ "hwnd": 9, "title": "Install - X", "w": 100, "h": 50 }], [], "").is_empty(), "winziges Fenster zählt nicht")
	check(
			int(P.epic_window_pick([{ "hwnd": 1, "w": 300, "h": 100 }, { "hwnd": 2, "w": 1400, "h": 900 }, { "hwnd": 3, "w": 1920, "h": 1080,
					"min": true }]).get("hwnd",
			0)) == 2, "Epic: das große, nicht minimierte Fenster")


func _numbers() -> void:
	check(P.speed_from([[0, 0], [2000, 20971520]]) == 10485760.0, "Tempo aus zwei Messpunkten")
	check(P.speed_from([[0, 0], [500, 100]]) == 0.0, "zu kurz gemessen: noch kein Tempo")
	check(P.speed_from([[0, 0], [20000, 100], [30000, 1100]], 12000) == 100.0, "nur die letzten 12 s zählen")
	check(P.speed_text(12.34 * 1048576.0) == "12,3 MB/s" and P.speed_text(512000.0) == "500 KB/s" and P.speed_text(0.0) == "", "Tempo-Text")
	check(P.eta_text(600.0 * 1048576.0, 1048576.0) == "noch 10 Min." and P.eta_text(10.0, 1.0) == "noch < 1 Min."
			and P.eta_text(5400.0, 1.0) == "noch 1 Std. 30 Min.", "Restzeit-Text")
	check(P.eta_text(100.0, 0.0) == "", "ohne Tempo keine Restzeit")
	var l := P.line("Wird geladen", 0.5, 2147483648.0, 4294967296.0, 10485760.0)
	check(l == "Wird geladen · 50 % · 2,0 GB von 4,0 GB · 10,0 MB/s · noch 4 Min.", "ganze Zeile: %s" % l)
	check(P.line("Wird geladen", 0.3, 0.0, 0.0, 0.0, true) == "Wird geladen · ca. 30 %", "geschätzt: „ca.“")


func _installs_poll() -> void:
	var lib := root.path_join("steamlib")
	var acf := lib.path_join("steamapps/appmanifest_4242.acf")
	write(acf, "\"AppState\"\n{\n\t\"appid\"\t\t\"4242\"\n\t\"installdir\"\t\t\"Testspiel\"\n\t\"StateFlags\"\t\t\"1026\"\n\t\"BytesToDownload\"\t\t\"1073741824\"\n\t\"BytesDownloaded\"\t\t\"268435456\"\n}\n")
	var g := { "id": "steam:4242", "source": "steam", "appid": 4242, "title": "Testspiel", "installed": false }
	Library.games.append(g)
	Library._reindex()
	var e := Installs._new_entry(g)
	e["manifest"] = acf
	e["phase"] = "preparing"
	Installs.items[str(g.id)] = e
	var got := { "done": "" }
	Installs.finished.connect(func(id: String) -> void: got.done = id)
	Installs._poll_steam(str(g.id))
	var cur := Installs.entry(str(g.id))
	check(str(cur.phase) == "downloading" and absf(float(cur.frac) - 0.25) < 0.001, "lädt: 25 %% (%s)" % cur.text)
	check(Installs.busy(str(g.id)) and Installs.active_count() >= 1, "läuft und zählt als aktiv")
	write(acf, "\"AppState\"\n{\n\t\"appid\"\t\t\"4242\"\n\t\"installdir\"\t\t\"Testspiel\"\n\t\"StateFlags\"\t\t\"4\"\n\t\"BytesToDownload\"\t\t\"1073741824\"\n\t\"BytesDownloaded\"\t\t\"1073741824\"\n}\n")
	Installs._poll_steam(str(g.id))
	var lg := Library.get_game(str(g.id))
	check(str(Installs.entry(str(g.id)).phase) == "done" and got.done == str(g.id), "fertig: Meldung „finished“")
	check(Library.is_installed(lg) and str(lg.get("install_dir", "")) == lib.path_join("steamapps/common/Testspiel"), "Spiel ist installiert, Ordner stimmt")
	check(not Installs.busy(str(g.id)), "nicht mehr aktiv")
	Installs.dismiss(str(g.id))
	check(Installs.entry(str(g.id)).is_empty(), "aus der Liste genommen")
	# Verschwindet das Manifest mitten im Laden: in Steam abgebrochen.
	var g2 := { "id": "steam:4343", "source": "steam", "appid": 4343, "title": "Weg", "installed": false }
	Library.games.append(g2)
	Library._reindex()
	var acf2 := lib.path_join("steamapps/appmanifest_4343.acf")
	write(acf2, "\"AppState\"\n{\n\t\"StateFlags\"\t\t\"1026\"\n\t\"BytesToDownload\"\t\t\"100\"\n\t\"BytesDownloaded\"\t\t\"1\"\n}\n")
	var e2 := Installs._new_entry(g2)
	e2["manifest"] = acf2
	Installs.items[str(g2.id)] = e2
	Installs._poll_steam(str(g2.id))
	DirAccess.remove_absolute(acf2)
	Installs._poll_steam(str(g2.id))
	check(str(Installs.entry(str(g2.id)).phase) == "cancelled", "Manifest weg: abgebrochen")
	Installs.dismiss(str(g2.id))
	await get_tree().process_frame


# --- Nachgebaute Web-API (IClientCommService) ---------------------------------------------------

func _jwt(claims: Dictionary) -> String:
	var b := Marshalls.utf8_to_base64(JSON.stringify(claims)).replace("+", "-").replace("/", "_").replace("=", "")
	return "eyJhbGciOiJub25lIn0." + b + ".x"


func _process(_dt: float) -> void:
	if not srv.is_listening():
		return
	while srv.is_connection_available():
		conns.append({ "peer": srv.take_connection(), "buf": PackedByteArray() })
	for c in conns.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			conns.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var part: Array = peer.get_data(n)
			var buf: PackedByteArray = c.buf
			buf.append_array(part[1])
			c.buf = buf
		var text := (c.buf as PackedByteArray).get_string_from_utf8()
		var head_end := text.find("\r\n\r\n")
		if head_end < 0:
			continue
		var head := text.substr(0, head_end)
		var len := 0
		for line in head.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				len = int(line.substr(15).strip_edges())
		var body := text.substr(head_end + 4)
		if body.to_utf8_buffer().size() < len:
			continue
		var first := head.split("\r\n")[0].split(" ")
		var url := first[1]
		var path := url.split("?")[0]
		var query := url.split("?")[1] if url.contains("?") else ""
		seen.append({ "method": first[0], "path": path, "query": query, "body": body })
		var out := "{\"response\":{}}"
		if path.ends_with("/GetAllClientLogonInfo/v1/"):
			out = "{\"response\":{\"sessions\":[{\"client_instanceid\":\"5555\",\"machine_name\":\"ANDERER-PC\"},{\"client_instanceid\":\"18446744073709551000\",\"machine_name\":\"UZAI-PC\",\"os_name\":\"Windows 11\"}]}}"
		var resp := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nx-eresult: 1\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [
				out.to_utf8_buffer().size(), out]
		peer.put_data(resp.to_utf8_buffer())
		peer.disconnect_from_host()
		conns.erase(c)


static func _form(s: String) -> Dictionary:
	var d := {}
	for kv in s.split("&"):
		var p := kv.split("=")
		if p.size() == 2:
			d[p[0].uri_decode()] = p[1].uri_decode()
	return d


func _installs_remote() -> void:
	if srv.listen(PORT, "127.0.0.1") != OK:
		check(false, "Port %d belegt" % PORT)
		return
	OS.set_environment("UZAI_STEAM_API", "http://127.0.0.1:%d" % PORT)
	OS.set_environment("COMPUTERNAME", "UZAI-PC")
	var far := 4102444800
	Config.set_value("accounts.steam_chat_id", ME)
	Config.set_value("accounts.steam_chat_refresh", _jwt({ "sub": ME, "exp": far, "aud": ["web", "renew"] }))
	Config.set_value("accounts.steam_chat_access", _jwt({ "sub": ME, "exp": far, "aud": ["web"] }))
	var r: Dictionary = await Installs._steam_remote("InstallClientApp", 620)
	check(bool(r.ok) and str(r.get("via", "")) == "web", "Fern-Download angenommen (über die Web-API)")
	var calls := seen.map(func(s): return str(s.path).get_slice("/", 2))
	check(calls == ["GetAllClientLogonInfo", "InstallClientApp"], "erst Sitzungen, dann Installieren (%s)" % str(calls))
	var inst: Dictionary = seen[seen.size() - 1] if not seen.is_empty() else {}
	var f := _form(str(inst.get("body", "")))
	check(str(inst.get("method", "")) == "POST" and str(f.get("appid", "")) == "620" and str(f.get("client_instanceid", "")) == "18446744073709551000",
			"POST mit appid und der Sitzung dieses PCs (nicht der fremden)")
	check(str(f.get("access_token", "")) != "", "mit dem Zugang aus der Anmeldung")
	seen.clear()
	var r2: Dictionary = await Installs._steam_remote("SetClientAppUpdateState", 620, 0)
	var f2 := _form(str(seen[0].get("body", ""))) if not seen.is_empty() else {}
	check(bool(r2.ok) and seen.size() == 1 and str(f2.get("action", "")) == "0", "Pausieren: action 0, Sitzung gemerkt (keine zweite Abfrage)")
	srv.stop()
	OS.set_environment("UZAI_STEAM_API", "")
