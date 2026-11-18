extends Node
## Speicherplatz (src/core/storage.gd): Platzbedarf aus Steams Systemanforderungen, „passt / knapp /
## voll“, Laufwerke aus der Antwort des Helfers, Größen aus Steams appmanifest und Epics Manifesten –
## und vor allem, was Aufräumen löschen darf: nur Dateien in den Aufräum-Ordnern von Uzais
## Datenordner, nie etwas daneben, nie über eine Verknüpfung hinaus, nie ein Ordner.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_speicher.tscn → „Ergebnis: alles ok“

const Storage := preload("res://src/core/storage.gd")
const StorageFlow := preload("res://src/ui/storage_flow.gd")
const P := preload("res://src/core/install_parse.gd")
const G := 1073741824

var fails := 0
var root := ""


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
	root = Config.path("speicher-test")
	print("Platzbedarf aus den Systemanforderungen")
	_requirements()
	print("Passt, knapp, voll")
	_levels()
	print("Laufwerke")
	_drives()
	print("Größen aus Steam und Epic")
	_launchers()
	print("Aufräumen: welche Pfade gelöscht werden dürfen")
	_paths()
	print("Aufräumen: Dateien finden und löschen")
	_clean()
	print("Aufräumen: Verknüpfungen nach draußen")
	_links()
	print("Spielseite und Ziel-Laufwerk")
	_flow()
	print("Seite „Speicher“: Spiele über den Hilfsfaden")
	await _auffrischen()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _requirements() -> void:
	check(
			Storage.size_from_requirements([["Betriebssystem", "Windows 10"], ["Arbeitsspeicher", "8 GB RAM"],
			["Speicherplatz", "50 GB verfügbarer Speicherplatz"]]) == 50 * G, "Deutsch: Speicherplatz 50 GB (Arbeitsspeicher davor zählt nicht)")
	check(Storage.size_from_requirements([["Storage", "1.5 GB available space"]]) == int(1.5 * G), "Englisch: Storage 1.5 GB")
	check(Storage.size_from_requirements([["Speicherplatz", "1,5 GB verfügbarer Speicherplatz"]]) == int(1.5 * G), "Komma als Dezimalzeichen")
	check(Storage.size_from_requirements([["Hard Drive", "500 MB HD space"]]) == 500 * 1048576, "ältere Seite: Hard Drive 500 MB")
	check(Storage.size_from_requirements([["Festplatte", "1 TB"]]) == 1024 * G, "Festplatte 1 TB")
	check(Storage.size_from_requirements([["Arbeitsspeicher", "16 GB RAM"], ["Grafik", "GTX 1060, 6 GB"]]) == -1, "nur Arbeits- und Grafikspeicher → unbekannt")
	check(Storage.size_from_requirements([["Grafikspeicher", "4 GB"]]) == -1, "Grafikspeicher zählt nicht")
	check(Storage.size_from_requirements([["Speicherplatz", "viel"]]) == -1, "ohne Zahl → unbekannt")
	check(Storage.size_from_requirements([]) == -1 and Storage.size_from_requirements(["kaputt", ["nur eins"], 5]) == -1, "leer und kaputte Einträge → unbekannt")


func _levels() -> void:
	check(Storage.space_level(50 * G, 200 * G) == "ok", "50 GB auf 200 GB frei: passt")
	check(Storage.space_level(50 * G, 55 * G) == "knapp", "50 GB auf 55 GB frei: knapp (unter 10 GB übrig)")
	check(Storage.space_level(50 * G, 40 * G) == "voll", "50 GB auf 40 GB frei: passt nicht")
	check(Storage.space_level(-1, 5 * G) == "knapp", "Größe unbekannt, nur 5 GB frei: knapp")
	check(Storage.space_level(-1, 100 * G) == "ok", "Größe unbekannt, 100 GB frei: passt")
	check(Storage.space_level(50 * G, -1) == "", "freier Platz unbekannt: keine Aussage")
	check(Storage.note(45 * G, 210 * G, "D:") == "ca. %s · %s frei auf D:" % [P.gb(45.0 * G), P.gb(210.0 * G)], "Kurztext mit Größe und Platz")
	check(Storage.note(-1, 210 * G, "") == "%s frei" % P.gb(210.0 * G) and Storage.note(-1, -1, "C:") == "", "Kurztext ohne Größe bzw. ganz ohne Angaben")
	check(Storage.size_text(90000) == "unter 1 MB" and Storage.size_text(0) == P.gb(0.0) and Storage.size_text(5 * 1048576) == P.gb(5.0 * 1048576),
			"kleine Mengen beim Aufräumen nicht als „0 MB“")


func _drives() -> void:
	check(Storage.drive_of("C:\\Games\\Elden Ring") == "C:" and Storage.drive_of("d:/SteamLibrary") == "D:", "Laufwerksbuchstabe aus Windows-Pfaden")
	check(Storage.drive_of("/home/uzai") == "/" and Storage.drive_of("relativ/pfad") == "" and Storage.drive_of("1:/x") == "",
			"Linux-Pfad, relativ, kein Buchstabe")
	var list := Storage.drives_from({ "drives": [
		{ "name": "D:\\", "label": "Spiele", "total": 2000 * G, "free": 400 * G },
		{ "name": "C:\\", "label": "", "total": 1000 * G, "free": 150 * G },
		{ "name": "E:\\", "total": 100 * G, "free": 300 * G },
		{ "name": "/", "total": 100 * G, "free": 3 * G },
		{ "name": "F:\\", "total": 0, "free": 0 },
		"kaputt",
	] })
	check(list.size() == 2 and str(list[0].name) == "C:" and str(list[1].name) == "D:", "Helfer-Antwort: nur plausible Laufwerke, sortiert")
	check(str(list[1].label) == "Spiele" and int(list[1].free) == 400 * G, "Name und freier Platz übernommen")
	check(Storage.drives_from(null).is_empty() and Storage.drives_from({ "drives": "x" }).is_empty(), "kaputte Antwort → keine Laufwerke")
	var games := [
		{ "title": "B", "bytes": 10 * G, "drive": "C:" }, { "title": "A", "bytes": 10 * G, "drive": "D:" },
		{ "title": "Groß", "bytes": 90 * G, "drive": "D:" }, { "title": "Wird gemessen", "bytes": -1, "drive": "D:" },
	]
	var per := Storage.games_per_drive(games)
	check(int(per.get("C:", 0)) == 10 * G and int(per.get("D:", 0)) == 100 * G, "Spiele je Laufwerk zusammengezählt (unbekannte nicht)")
	var order := Storage.by_size(games).map(func(e: Dictionary) -> String: return str(e.title))
	check(order == ["Groß", "A", "B", "Wird gemessen"], "größte zuerst, gleich große nach Titel, unbekannte am Ende")


func _launchers() -> void:
	var lib := root.path_join("steamlib")
	write(lib.path_join("steamapps/appmanifest_10.acf"),
			"\"AppState\"\n{\n\t\"appid\"\t\t\"10\"\n\t\"name\"\t\t\"Spiel A\"\n\t\"installdir\"\t\t\"Spiel A\"\n\t\"SizeOnDisk\"\t\t\"48318382080\"\n}\n")
	write(lib.path_join("steamapps/appmanifest_20.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"20\"\n\t\"name\"\t\t\"Spiel B\"\n\t\"installdir\"\t\t\"B\"\n}\n")
	var st := Storage.steam_installed([lib, root.path_join("gibt-es-nicht")])
	check(st.size() == 2 and int(st[10].bytes) == 48318382080, "Steam: SizeOnDisk aus dem appmanifest")
	check(int(st[20].bytes) == -1 and str(st[10].dir) == lib.path_join("steamapps/common/Spiel A"), "Steam: ohne SizeOnDisk unbekannt, Ordner aus installdir")
	var man := root.path_join("epic")
	write(man.path_join("a.item"), JSON.stringify({ "AppName": "Fortnite", "InstallLocation": "C:\\Epic\\Fortnite", "InstallSize": 31000000000 }))
	write(man.path_join("b.item"), JSON.stringify({ "AppName": "Halb", "InstallLocation": "C:\\Epic\\Halb", "InstallSize": 5, "bIsIncompleteInstall": true }))
	write(man.path_join("c.item"), "kein json")
	var ep := Storage.epic_installed(man)
	check(ep.size() == 1 and int(ep["Fortnite"].bytes) == 31000000000 and str(ep["Fortnite"].dir) == "C:/Epic/Fortnite",
			"Epic: InstallSize, halbe Installation und Kaputtes weggelassen")
	check(Storage.epic_installed(root.path_join("nicht-da")).is_empty(), "Epic: ohne Manifest-Ordner nichts")


func _paths() -> void:
	var d := root.path_join("daten")
	check(not Storage.data_dir_ok("/") and not Storage.data_dir_ok("C:/") and not Storage.data_dir_ok("C:"), "Laufwerk als Datenordner: nein")
	check(not Storage.data_dir_ok("/home") and not Storage.data_dir_ok("user://") and not Storage.data_dir_ok("relativ/x"),
			"oberste Ebene, user:// und relativ: nein")
	check(not Storage.data_dir_ok("/tmp/../etc") and Storage.data_dir_ok("C:/Users/jo/AppData/Roaming/Uzai") and Storage.data_dir_ok(d),
			"„..“ nein, echte Datenordner ja")
	check(Storage.may_delete(d.path_join("cache/img/steam/10_cover.jpg"), d), "Bild im Zwischenspeicher: ja")
	check(Storage.may_delete(d.path_join("cache/wiki/x.json"), d), "Liste im Zwischenspeicher: ja")
	check(Storage.may_delete(d.path_join("logs/steam.log"), d), "Protokoll: ja")
	check(Storage.may_delete(d.path_join("capture/puffer/seg_001.ts"), d), "Aufnahme-Puffer: ja")
	check(not Storage.may_delete(d.path_join("settings.json"), d), "Einstellungen: nein")
	check(not Storage.may_delete(d.path_join("library.json"), d), "Bibliothek: nein")
	check(not Storage.may_delete(d.path_join("media/sgdb/cover.png"), d), "Medienordner (selbst gewählte Bilder): nein")
	check(not Storage.may_delete(d.path_join("backups/uzai-sicherung.zip"), d), "Sicherungen: nein")
	check(not Storage.may_delete(d.path_join("capture/clip/x.mp4"), d) and not Storage.may_delete(d.path_join("capture/aufnahme/x.mkv"), d),
			"Clips und laufende Aufnahmen: nein")
	check(not Storage.may_delete(d.path_join("cache"), d) and not Storage.may_delete(d.path_join("cache/"), d), "Aufräum-Ordner selbst: nein")
	check(not Storage.may_delete(d.path_join("cache/../settings.json"), d) and not Storage.may_delete(d.path_join("cache/./x"), d), "„..“ und „.“ im Pfad: nein")
	check(not Storage.may_delete(d + "x/cache/a.jpg", d), "Nachbarordner mit gleichem Anfang: nein")
	check(not Storage.may_delete("/etc/passwd", d) and not Storage.may_delete("C:/Windows/System32/x.dll", d), "außerhalb des Datenordners: nein")
	check(not Storage.may_delete("cache/img/a.jpg", d) and not Storage.may_delete("user://cache/img/a.jpg", d), "relative und user://-Pfade: nein")
	check(Storage.may_delete(d.replace("/", "\\") + "\\cache\\img\\a.jpg", d), "Windows-Trenner werden gleich behandelt")
	check(not Storage.may_delete("/cache/img/a.jpg", "/") and not Storage.may_delete("C:/cache/a.jpg", "C:/"), "Datenordner auf oberster Ebene: nichts")
	check(Storage.clean_root(d, "bilder") == d.path_join("cache/img") and Storage.clean_root(d, "gibt-es-nicht") == "",
			"Ordner je Eintrag, unbekannte Kennung → nichts")


func _clean() -> void:
	var d := root.path_join("daten")
	write(d.path_join("cache/img/steam/10_cover.jpg"), "0123456789")
	write(d.path_join("cache/img/web/x.png"), "ab")
	write(d.path_join("cache/wiki/a.json"), "12345")
	write(d.path_join("cache/youtube-feed.json"), "123")
	write(d.path_join("logs/steam.log"), "1234567")
	write(d.path_join("capture/puffer/seg_001.ts"), "123")
	write(d.path_join("capture/clip/mein-clip.mp4"), "clip")
	write(d.path_join("settings.json"), "{}")
	write(d.path_join("media/eigenes.png"), "png")
	var img := Storage.clean_files(d, "bilder")
	check(img.size() == 2 and Storage.files_bytes(img) == 12, "Bilder: nur cache/img (2 Dateien, 12 Byte)")
	var lists := Storage.clean_files(d, "listen")
	var lnames := lists.map(func(f: Array) -> String: return str(f[0]).get_file())
	lnames.sort()
	check(lnames == ["a.json", "youtube-feed.json"], "weitere Zwischenspeicher: ohne die Bilder")
	# Was Uzai nicht neu holen kann, bleibt stehen: Weiterschauen bei Twitch, die letzte Warteschlange der Musik.
	write(d.path_join("cache/twitch.json"), "{}")
	write(d.path_join("cache/musik/zuletzt.json"), "{}")
	write(d.path_join("cache/musik/index.json"), "{}")
	var l2 := Storage.clean_files(d, "listen").map(func(f: Array) -> String: return str(f[0]).get_file())
	l2.sort()
	check(l2 == ["a.json", "index.json", "youtube-feed.json"], "weitere Zwischenspeicher: ohne Twitch-Stellen und letzte Warteschlange (%s)" % str(l2))
	check(not Storage.may_delete(d.path_join("cache/twitch.json"), d) and not Storage.may_delete(d.path_join("cache/musik/zuletzt.json"), d)
			and Storage.may_delete(d.path_join("cache/musik/index.json"), d), "may_delete: die beiden nie, das Verzeichnis der Musik schon")
	var res0 := Storage.delete_files([[d.path_join("cache/twitch.json"), 2], [d.path_join("cache/musik/index.json"), 2]], d)
	check(int(res0.count) == 1 and FileAccess.file_exists(d.path_join("cache/twitch.json")), "auch eine untergeschobene Liste löscht sie nicht")
	check(Storage.clean_files(d, "protokolle").size() == 1 and Storage.clean_files(d, "puffer").size() == 1, "Protokolle und Puffer je eine Datei")
	check(Storage.clean_files(d, "gibt-es-nicht").is_empty() and Storage.clean_files("/", "listen").is_empty(),
			"unbekannte Kennung und Laufwerk als Datenordner: nichts")
	# Eine untergeschobene Liste: Nur, was Aufräumen darf, wird gelöscht.
	var sneaky: Array = img.duplicate()
	sneaky.append([d.path_join("settings.json"), 2])
	sneaky.append([d.path_join("media/eigenes.png"), 3])
	sneaky.append([d.path_join("cache/img/../../settings.json"), 2])
	sneaky.append([d.path_join("cache/img"), 0])
	var res := Storage.delete_files(sneaky, d)
	check(int(res.count) == 2 and int(res.freed) == 12 and int(res.left) == 4, "Löschen: 2 Bilder weg, 4 verbotene Einträge übrig")
	check(FileAccess.file_exists(d.path_join("settings.json")) and FileAccess.file_exists(d.path_join("media/eigenes.png")),
			"Einstellungen und Medienordner unberührt")
	check(DirAccess.dir_exists_absolute(d.path_join("cache/img/steam")), "Ordner bleiben stehen")
	check(not FileAccess.file_exists(d.path_join("cache/img/steam/10_cover.jpg")), "das Bild ist wirklich weg")
	var res2 := Storage.delete_files(Storage.clean_files(d, "puffer"), d)
	check(int(res2.count) == 1 and FileAccess.file_exists(d.path_join("capture/clip/mein-clip.mp4")), "Puffer geleert, fertiger Clip bleibt")


func _links() -> void:
	var d := root.path_join("daten2")
	var outside := root.path_join("draussen")
	write(outside.path_join("geheim.txt"), "nicht löschen")
	write(d.path_join("cache/wiki/a.json"), "12345")
	var da := DirAccess.open(d.path_join("cache"))
	var linked := da != null and da.create_link(outside, d.path_join("cache/abzweig")) == OK
	check(linked, "Verknüpfung im Zwischenspeicher angelegt (Testaufbau)")
	if linked:
		var files := Storage.clean_files(d, "listen")
		check(files.size() == 1 and str(files[0][0]).ends_with("a.json"), "Verknüpfung nach draußen wird nicht verfolgt")
		Storage.delete_files(files, d)
		check(FileAccess.file_exists(outside.path_join("geheim.txt")), "Datei hinter der Verknüpfung bleibt")
		var forged := [[d.path_join("cache/abzweig/geheim.txt"), 13], [d.path_join("cache/abzweig"), 0]]
		var res := Storage.delete_files(forged, d)
		check(int(res.count) == 0 and FileAccess.file_exists(outside.path_join("geheim.txt")), "auch eine untergeschobene Liste löscht nichts hinter der Verknüpfung")
	# Ist der Aufräum-Ordner selbst eine Verknüpfung, gibt es gar nichts.
	var d3 := root.path_join("daten3")
	DirAccess.make_dir_recursive_absolute(d3)
	var da3 := DirAccess.open(d3)
	if da3 != null and da3.create_link(outside, d3.path_join("logs")) == OK:
		check(Storage.clean_files(d3, "protokolle").is_empty(), "Aufräum-Ordner als Verknüpfung: nichts")
	else:
		check(false, "Verknüpfung als Aufräum-Ordner angelegt (Testaufbau)")


## StorageFlow.games_auffrischen: Die Manifeste liest der Hilfsfaden, die Seite zeigt den bekannten Stand und
## hört nur, wenn er sich geändert hat (Steam-Bibliothek aus _launchers: Spiel 10 mit Größe, Spiel 20 ohne).
func _auffrischen() -> void:
	var demo_war: bool = Library.demo
	var root_war: String = Library._steam_root
	Library.demo = false
	Library._steam_root = root.path_join("steamlib")
	Library.games.append({ "id": "steam:10", "title": "Spiel A", "source": "steam", "system": "steam", "appid": 10, "installed": true })
	Library._reindex()
	check(StorageFlow.games_stand().is_empty() and not StorageFlow.games_gelesen(), "vor dem ersten Lesen: leer, und „leer“ heißt noch nicht „keine Spiele“")
	var rufe := [0, 0]
	StorageFlow.games_auffrischen(func() -> void: rufe[0] += 1)
	StorageFlow.games_auffrischen(func() -> void: rufe[1] += 1)
	check(StorageFlow._spiele_liest and StorageFlow.games_stand().is_empty(), "das Lesen läuft nebenher – der Aufruf kehrt sofort zurück")
	for i in 300:
		if StorageFlow.games_gelesen():
			break
		await get_tree().process_frame
	var st: Array = StorageFlow.games_stand()
	check(st.size() == 1 and str(st[0].id) == "steam:10" and int(st[0].bytes) == 48318382080 and str(st[0].store) == "steam",
			"gelesen: nur Spiele der Bibliothek, mit Größe (%s)" % str(st).left(120))
	check(rufe == [1, 1], "beide Wartenden hören genau einmal, auch wer während des Lesens dazukam")
	StorageFlow.games_auffrischen(func() -> void: rufe[0] += 1)
	for i in 300:
		if not StorageFlow._spiele_liest:
			break
		await get_tree().process_frame
	check(rufe == [1, 1] and StorageFlow._spiele_warten.is_empty(), "unverändert: niemand wird gerufen, keiner bleibt hängen")
	DirAccess.remove_absolute(root.path_join("steamlib/steamapps/appmanifest_10.acf"))
	StorageFlow.games_auffrischen(func() -> void: rufe[0] += 1)
	for i in 300:
		if not StorageFlow._spiele_liest:
			break
		await get_tree().process_frame
	check(rufe == [2, 1] and StorageFlow.games_stand().is_empty() and StorageFlow.games_gelesen(), "Spiel deinstalliert: Die Seite hört es, die Liste ist leer – und gelesen")
	Library.games.pop_back()
	Library._reindex()
	Library._steam_root = root_war
	Library.demo = demo_war


func _flow() -> void:
	check(StorageFlow.free_at(root.path_join("gibt/es/noch/nicht")) > 0, "freier Platz: nächster vorhandener Ordner darüber zählt")
	check(StorageFlow.free_at("") == -1, "ohne Ordner: unbekannt")
	check(StorageFlow.target_dir({ "source": "pc" }) == "", "PC-Spiele: kein Ziel-Laufwerk")
	check(StorageFlow.need_cached({ "source": "epic", "appid": 5 }) == -1, "Epic: Größe erst im Launcher")
	var dr := StorageFlow.drives([{ "dir": root, "bytes": 3 * G, "drive": Storage.drive_of(root) }])
	check(not dr.is_empty() and int(dr[0].free) > 0 and int(dr[0].games) == 3 * G, "ohne Helfer: Laufwerk mit freiem Platz und Spielen")
