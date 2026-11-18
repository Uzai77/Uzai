extends Node
## Epic Games und EA app ohne Windows: Manifeste lesen (Epic *.item, LauncherInstalled.dat,
## installerdata.xml, Origin *.mfst), Start-Links bauen, Quellen auf der Startseite, Einlesen
## mit echten Dateien in einem leeren Ordner und der Steam-Status „Spielt Nicht-Steam-Spiel“.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_stores.tscn → „Ergebnis: alles ok“
## Der Helfer-Befehl „ea-games“ (Registry lesen) läuft nur unter Windows richtig; unter Linux
## (pwsh) liefert er leere Listen. Hier kommen seine Einträge als fertige Liste in den Scanner.

const Epic := preload("res://src/library/epic_scanner.gd")
const EA := preload("res://src/library/ea_scanner.gd")
const Games := preload("res://src/ui/sections/games.gd")

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
	root = Config.path("stores-test")
	print("Epic: Manifest")
	_epic_parse()
	print("Epic: Einlesen mit Dateien")
	_epic_scan()
	print("Epic: gekaufte Spiele aus catcache.bin")
	_epic_catalog()
	print("Epic: gekaufte Spiele in der Bibliothek")
	_epic_owned_library()
	print("EA: installerdata.xml")
	_ea_installer()
	print("EA: Origin-Manifeste")
	_ea_mfst()
	print("EA: Einlesen mit Dateien")
	_ea_scan()
	print("Start-Links")
	_uris()
	print("Bibliothek und Startseite")
	_library()
	print("Steam-Status beim Spielen")
	_steam_status()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


const EPIC_ITEM := """{
	"FormatVersion": 0,
	"bIsIncompleteInstall": false,
	"LaunchCommand": "",
	"LaunchExecutable": "Binaries\\\\Win64\\\\AlanWake2.exe",
	"ManifestLocation": "C:\\\\ProgramData\\\\Epic\\\\EpicGamesLauncher\\\\Data\\\\Manifests",
	"DisplayName": "Alan Wake 2™ ",
	"InstallLocation": "D:\\\\Epic Games\\\\AlanWake2",
	"CatalogNamespace": "dc9d2e595d0e4650a35d659f90d41059",
	"CatalogItemId": "c4763f236d08423eb47b4c3008779c84",
	"AppName": "Kinglet",
	"MainGameAppName": "Kinglet",
	"AppCategories": ["public", "games", "applications"]
}"""


func _epic_parse() -> void:
	var g := Epic.parse_manifest(EPIC_ITEM)
	check(str(g.get("id", "")) == "epic:Kinglet" and str(g.get("source", "")) == "epic" and str(g.get("system", "")) == "epic",
			"eigene Quelle und eigenes System „epic“ (eigener Reiter wie Steam)")
	check(str(g.get("title", "")) == "Alan Wake 2", "Titel ohne ™ und Leerzeichen am Ende („%s“)" % str(g.get("title", "")))
	check(str(g.get("install_dir", "")) == "D:/Epic Games/AlanWake2", "Spielordner mit /")
	check(str(g.get("path", "")) == "D:/Epic Games/AlanWake2/Binaries/Win64/AlanWake2.exe", "Programmdatei (LaunchExecutable) für das Spielende")
	var e: Dictionary = g.get("epic", {})
	check(str(e.get("namespace", "")) == "dc9d2e595d0e4650a35d659f90d41059" and str(e.get("item", "")) == "c4763f236d08423eb47b4c3008779c84"
			and str(e.get("app", "")) == "Kinglet", "Namespace, Item-ID und AppName gemerkt")
	var dlc := EPIC_ITEM.replace('"MainGameAppName": "Kinglet"', '"MainGameAppName": "Other"')
	check(Epic.parse_manifest(dlc).is_empty(), "Zusatzinhalt (MainGameAppName anders) ausgelassen")
	var tool := EPIC_ITEM.replace('["public", "games", "applications"]', '["engines"]')
	check(Epic.parse_manifest(tool).is_empty(), "Unreal Engine und Werkzeuge ausgelassen")
	check(Epic.parse_manifest(EPIC_ITEM.replace('"bIsIncompleteInstall": false', '"bIsIncompleteInstall": true')).is_empty(), "halbe Installation ausgelassen")
	check(Epic.parse_manifest("kein json").is_empty() and Epic.parse_manifest("[]").is_empty(), "kaputte Datei: nichts")
	var no_dir := EPIC_ITEM.replace('"InstallLocation": "D:\\\\Epic Games\\\\AlanWake2",', '')
	var known := Epic.parse_installed('{"InstallationList":[{"InstallLocation":"E:\\\\Spiele\\\\AW2","NamespaceId":"x","ItemId":"y","ArtifactId":"Kinglet","AppVersion":"1","AppName":"Kinglet"}]}')
	check(str(known.get("Kinglet", "")) == "E:/Spiele/AW2", "LauncherInstalled.dat gelesen")
	check(str(Epic.parse_manifest(no_dir, known).get("install_dir", "")) == "E:/Spiele/AW2", "ohne Ordner im Manifest: aus LauncherInstalled.dat")
	check(Epic.parse_installed("").is_empty() and Epic.parse_installed("{}").is_empty(), "LauncherInstalled.dat fehlt: kein Fehler")
	# Lokale Manifeste (auch eines anderen Windows-Kontos): kein Ordner auf einer Freigabe, keine Programmdatei außerhalb.
	var unc := EPIC_ITEM.replace('"InstallLocation": "D:\\\\Epic Games\\\\AlanWake2",', '"InstallLocation": "\\\\\\\\203.0.113.5\\\\x",')
	var raus := EPIC_ITEM.replace('"LaunchExecutable": "Binaries\\\\Win64\\\\AlanWake2.exe",', '"LaunchExecutable": "..\\\\..\\\\Windows\\\\System32\\\\cmd.exe",')
	check(unc != EPIC_ITEM and raus != EPIC_ITEM, "Proben verändert")
	check(Epic.parse_manifest(unc).is_empty() and not Epic.parse_manifest(raus).has("path"),
			"Epic: Freigabe als Ordner verworfen, Programmdatei nur im Spielordner")
	check(Epic.clean_title("Fortnite®") == "Fortnite" and Epic.clean_title("  A\u00a0 B ") == "A B", "Titel säubern")


func _epic_scan() -> void:
	var man := root.path_join("Epic/Manifests")
	var game_dir := root.path_join("Epic Games/AW2")
	DirAccess.make_dir_recursive_absolute(game_dir)
	var item := JSON.parse_string(EPIC_ITEM) as Dictionary
	item["InstallLocation"] = game_dir
	write(man.path_join("A1.item"), JSON.stringify(item))
	var gone := item.duplicate()
	gone["AppName"] = "Gone"
	gone["MainGameAppName"] = "Gone"
	gone["InstallLocation"] = root.path_join("Epic Games/gibt es nicht")
	write(man.path_join("B2.item"), JSON.stringify(gone))
	write(man.path_join("notiz.txt"), "x")
	var got := Epic.scan(man, root.path_join("Epic/keine.dat"))
	check(got.size() == 1 and str(got[0].id) == "epic:Kinglet", "nur Spiele, deren Ordner es gibt (%d)" % got.size())
	check(Epic.scan(root.path_join("gibt-es-nicht")).is_empty(), "ohne Epic: leere Liste")


## Katalogeinträge wie in catcache.bin (selbst geschrieben, Felder wie im Launcher).
func _cat_items() -> Array:
	return [
		# installiert (gleicher App-Name wie EPIC_ITEM): nur Bilder für den installierten Eintrag
		{ "id": "c4763f236d08423eb47b4c3008779c84", "namespace": "dc9d2e595d0e4650a35d659f90d41059", "title": "Alan Wake 2",
			"categories": [{ "path": "games" }, { "path": "applications" }], "mainGameItem": null,
			"releaseInfo": [{ "id": "r1", "appId": "Kinglet", "platform": ["Windows"] }],
			"keyImages": [{ "type": "DieselGameBoxTall", "url": "https://cdn1.epicgames.com/aw2/tall.jpg" }] },
		# gekauft, nicht installiert; Katalog schreibt ™ als „?“
		{ "id": "item-apex", "namespace": "ns-apex", "title": "Apex Legends?", "categories": [{ "path": "games" }],
			"mainGameItem": { "id": "", "namespace": "" },
			"releaseInfo": [{ "appId": "ApexMac", "platform": ["Mac"] }, { "appId": "Apex", "platform": ["Windows", "Win32"] }],
			"keyImages": [{ "type": "Thumbnail", "url": "https://cdn1.epicgames.com/apex/thumb.png" },
				{ "type": "DieselGameBoxTall", "url": "https://cdn1.epicgames.com/apex/tall.jpg" },
				{ "type": "DieselGameBox", "url": "https://cdn1.epicgames.com/apex/wide.jpg" },
				{ "type": "DieselGameBoxLogo", "url": "https://cdn1.epicgames.com/apex/logo.png" }] },
		{ "id": "item-control", "namespace": "ns-control", "title": "Control: Ultimate Edition", "categories": [{ "path": "games" }, { "path": "applications" }],
			"releaseInfo": [{ "appId": "Control" }], "keyImages": [{ "type": "OfferImageTall", "url": "https://cdn1.epicgames.com/control/tall.jpg?x=1" }] },
		# Zusatzinhalt, Add-on, Engine, nur Mac, ohne App-Name, kaputt
		{ "id": "item-dlc", "namespace": "ns-control", "title": "Control: AWE", "categories": [{ "path": "games" }],
			"mainGameItem": { "id": "item-control", "namespace": "ns-control" }, "releaseInfo": [{ "appId": "ControlAWE" }] },
		{ "id": "item-addon", "namespace": "ns-x", "title": "Skin-Paket", "categories": [{ "path": "addons" }, { "path": "games" }],
			"releaseInfo": [{ "appId": "Skins" }] },
		{ "id": "item-ue", "namespace": "ue", "title": "Unreal Engine", "categories": [{ "path": "engines" }, { "path": "applications" }],
			"releaseInfo": [{ "appId": "UE_5.4" }] },
		{ "id": "item-mac", "namespace": "ns-mac", "title": "Nur Mac", "categories": [{ "path": "games" }],
			"releaseInfo": [{ "appId": "MacOnly", "platform": ["Mac"] }] },
		{ "id": "item-noapp", "namespace": "ns-n", "title": "Ohne App", "categories": [{ "path": "games" }], "releaseInfo": [] },
		"kein Eintrag", 42,
		# doppelt (gleicher App-Name): einmal
		{ "id": "item-control-2", "namespace": "ns-control", "title": "Control", "categories": [{ "path": "games" }], "releaseInfo": [{ "appId": "Control" }] },
	]


func _epic_catalog() -> void:
	var b64 := Marshalls.utf8_to_base64(JSON.stringify(_cat_items()))
	var items := Epic.parse_catcache(b64)
	check(items.size() == _cat_items().size(), "catcache.bin: Base64 → JSON-Array (%d Einträge)" % items.size())
	check(Epic.parse_catcache(JSON.stringify(_cat_items())).size() == items.size(), "zur Not auch unkodiertes JSON")
	check(Epic.parse_catcache("").is_empty() and Epic.parse_catcache("@@@kein base64@@@").is_empty()
			and Epic.parse_catcache(Marshalls.utf8_to_base64("{}")).is_empty(), "leere/kaputte Datei: nichts, kein Absturz")
	var owned := Epic.parse_catalog(items)
	var by := {}
	for g in owned:
		by[str(g.epic.app)] = g
	check(by.size() == 3 and by.has("Kinglet") and by.has("Apex") and by.has("Control"),
			"nur Hauptspiele für Windows (%s)" % ", ".join(PackedStringArray(by.keys())))
	check(not by.has("ControlAWE") and not by.has("Skins") and not by.has("UE_5.4") and not by.has("MacOnly"),
			"ohne Zusatzinhalte, Add-ons, Engine und Mac-Spiele")
	var apex: Dictionary = by.get("Apex", {})
	check(str(apex.get("title", "")) == "Apex Legends", "„?“ statt ™ am Wortende entfernt („%s“)" % str(apex.get("title", "")))
	check(str(apex.get("id", "")) == "epic:Apex" and str(apex.get("source", "")) == "epic" and not bool(apex.get("installed", true)),
			"ID epic:<AppName> wie installierte, „nicht installiert“")
	check(str(apex.get("path", "x")) == "" and str(apex.get("install_dir", "x")) == "", "ohne Programmdatei (wird beim Deinstallieren auch geleert)")
	check(str((apex.get("epic", {}) as Dictionary).get("namespace", "")) == "ns-apex" and str(apex.epic.item) == "item-apex",
			"Namespace und Katalog-ID für den Launcher-Link")
	var art: Dictionary = apex.get("art", {})
	check(str(art.get("cover", "")) == "https://cdn1.epicgames.com/apex/tall.jpg?w=600&h=800&resize=1",
			"Cover: DieselGameBoxTall vor Thumbnail, verkleinert angefragt")
	check(str(art.get("hero", "")).begins_with("https://cdn1.epicgames.com/apex/wide.jpg")
			and str(art.get("logo", "")) == "https://cdn1.epicgames.com/apex/logo.png", "Hintergrund und Schriftzug")
	check(str(((by.get("Control", {}) as Dictionary).get("art", {}) as Dictionary).get("cover", "")) == "https://cdn1.epicgames.com/control/tall.jpg?x=1",
			"OfferImageTall als Ersatz, eigene Abfrage bleibt")
	check(Epic.fix_title("Who?s There?") == "Who?s There" and Epic.fix_title("A? B") == "A B", "„?“ nur am Wortende")
	# Abgleich mit den installierten
	var inst := Epic.parse_manifest(EPIC_ITEM)
	var rest := Epic.dedupe([inst], owned)
	check(rest.size() == 2 and not rest.any(func(g): return str(g.epic.app) == "Kinglet"), "schon installiert: nicht doppelt (App-Name)")
	check(str((inst.get("art", {}) as Dictionary).get("cover", "")).begins_with("https://cdn1.epicgames.com/aw2/tall.jpg"),
			"installiertes Spiel bekommt das Cover aus dem Katalog")
	var other := inst.duplicate(true)
	other.epic.app = "AndererName"
	check(Epic.dedupe([other], owned).size() == 2, "auch über die Katalog-ID erkannt")
	# Link zum Installieren
	check(Epic.install_uri(apex) == "com.epicgames.launcher://apps/ns-apex%3Aitem-apex%3AApex?action=install",
			"Installieren: com.epicgames.launcher://apps/<Namespace>%3A<Item>%3A<App>?action=install")
	check(Epic.install_uri({ "epic": { "namespace": "a", "item": "", "app": "c" } }) == "" and Epic.install_uri({}) == "", "ohne vollständige IDs kein Link")
	check(Epic.install_uri({ "epic": { "namespace": "n s", "item": "i", "app": "a:b" } }) == "com.epicgames.launcher://apps/n%20s%3Ai%3Aa%3Ab?action=install",
			"Teile kodiert")
	# Mit Dateien: Manifest-Ordner + catcache.bin, fehlende Datei
	var man := root.path_join("EpicOwned/Manifests")
	var game_dir := root.path_join("EpicOwned/Games/AW2")
	DirAccess.make_dir_recursive_absolute(game_dir)
	var item := JSON.parse_string(EPIC_ITEM) as Dictionary
	item["InstallLocation"] = game_dir
	write(man.path_join("A.item"), JSON.stringify(item))
	var cat := root.path_join("EpicOwned/Catalog/catcache.bin")
	write(cat, b64)
	var r := Epic.scan_all(true, man, root.path_join("keine.dat"), [root.path_join("fehlt/catcache.bin"), cat])
	var got: Array = r.games
	check(bool(r.catalog) and got.size() == 3, "installiert + gekauft in einem Durchgang (%d)" % got.size())
	check(got.filter(func(g): return bool(g.installed)).size() == 1 and str(got[0].id) == "epic:Kinglet", "installierte zuerst, nicht doppelt")
	var none := Epic.scan_all(true, man, "", [root.path_join("fehlt/catcache.bin")])
	check(not bool(none.catalog) and (none.games as Array).size() == 1, "ohne catcache.bin: nur installierte, Hinweis „Katalog fehlt“")
	check((Epic.scan_all(false, man, "", [cat]).games as Array).size() == 1, "gekaufte aus: nur installierte")
	var paths := Epic.catcache_paths("C:/ProgramData", "C:/Users/x/AppData/Local")
	check(
			paths == ["C:/ProgramData/Epic/EpicGamesLauncher/Data/Catalog/catcache.bin", "C:/Users/x/AppData/Local/EpicGamesLauncher/Saved/Data/Catalog/catcache.bin"],
			"Orte der Katalogdatei")
	# Fingerabdruck des Manifest-Ordners (Nachsehen während einer Installation) und Pending
	var sig1 := Epic.manifest_sig(man)
	write(man.path_join("Pending/B.item"), JSON.stringify({ "AppName": "Apex" }))
	check(Epic.manifest_sig(man) != sig1, "neue Datei im Manifest-Ordner ändert den Fingerabdruck")
	check(Epic.pending_apps(man) == ["Apex"], "Epic lädt gerade: Manifests\\Pending")
	check(Epic.pending_apps(root.path_join("leer")).is_empty() and Epic.manifest_sig(root.path_join("leer")) == "", "ohne Ordner: nichts")


func _epic_owned_library() -> void:
	var keep: Array = Library.games
	Library.games = []
	Library._reindex()
	var owned := Epic.parse_catalog(Epic.parse_catcache(Marshalls.utf8_to_base64(JSON.stringify(_cat_items()))))
	var inst := Epic.parse_manifest(EPIC_ITEM)
	var played := { "id": "steam:7", "title": "Zz Steam", "system": "steam", "source": "steam", "appid": 7, "installed": true }
	var found: Array = [inst, played] + Epic.dedupe([inst], owned)
	Library._merge(found)
	var apex := Library.get_game("epic:Apex")
	check(not apex.is_empty() and Library.owned_only(apex) and Library.is_visible(apex), "gekauftes Epic-Spiel sichtbar, als „nur gekauft“ erkannt")
	check(not Library.owned_only(Library.get_game("epic:Kinglet")) and not Library.owned_only({ "source": "steam", "installed": false }),
			"installierte und Steam-Spiele nicht")
	var gs = Games.new()
	var epic_tab: Array = gs.games_for("epic").map(func(g): return str(g.id))
	check(epic_tab == ["epic:Kinglet", "epic:Apex", "epic:Control"],
			"Reiter Epic: installierte zuerst, dann gekaufte (%s)" % ", ".join(PackedStringArray(epic_tab)))
	var alle: Array = Library.sorted(Library.visible_games(), "title").map(func(g): return str(g.id))
	check(alle.slice(-2) == ["epic:Apex", "epic:Control"], "auch im Raster (nach Titel) hinten (%s)" % ", ".join(PackedStringArray(alle)))
	gs.free()
	check(not Library.recent(24).any(func(g): return Library.owned_only(g)), "nie in „Zuletzt“")
	Config.set_value("library.epic_owned", false)
	check(not Library.is_visible(apex) and Library.is_visible(Library.get_game("epic:Kinglet")), "Schalter aus: gekaufte sofort weg, installierte bleiben")
	Config.set_value("library.epic_owned", true)
	# Starten geht nicht – nur installieren.
	Launcher.launch(apex)
	check(not Launcher.in_game and not Launcher.is_starting(), "nicht installiert: Launcher startet nichts")
	# Installiert (Manifest taucht auf): derselbe Eintrag wird spielbar, Favorit bleibt.
	Library.set_field("epic:Apex", "favorite", true)
	var now_inst := inst.duplicate(true)
	now_inst["id"] = "epic:Apex"
	now_inst["title"] = "Apex Legends"
	now_inst["epic"] = { "namespace": "ns-apex", "item": "item-apex", "app": "Apex" }
	now_inst["install_dir"] = "D:/Epic/Apex"
	now_inst["path"] = "D:/Epic/Apex/r5apex.exe"
	Library._merge([now_inst], ["epic"])
	apex = Library.get_game("epic:Apex")
	check(Library.is_installed(apex) and str(apex.path) == "D:/Epic/Apex/r5apex.exe" and bool(apex.get("favorite", false)),
			"nach der Installation: spielbar, Favorit bleibt")
	check(apex.has("art"), "Bilder aus dem Katalog bleiben")
	check(not bool(Library.get_game("steam:7").get("missing", false)), "Nachsehen nur bei Epic lässt Steam unberührt")
	check(bool(Library.get_game("epic:Control").get("missing", false)) and bool(Library.get_game("epic:Kinglet").get("missing", false)),
			"… Epic-Einträge, die fehlen, werden ausgeblendet")
	# Wieder deinstalliert, aber im Katalog: wieder „nicht installiert“, ohne alte Programmdatei.
	Library._merge(Epic.parse_catalog(_cat_items()), ["epic"])
	apex = Library.get_game("epic:Apex")
	check(Library.owned_only(apex) and str(apex.get("path", "")) == "" and not bool(apex.get("missing", false)),
			"deinstalliert: wieder „Installieren“, Programmdatei vergessen")
	# Installation anstoßen (Demo: ohne den Link wirklich zu öffnen) und warten
	var was_demo := Library.demo
	Library.demo = true
	check(Library.start_epic_install(apex) and Library.epic_install_pending("epic:Apex"), "Installation angestoßen: Uzai wartet darauf")
	check(not Library.start_epic_install({ "id": "epic:x", "epic": {} }), "ohne IDs: nichts angestoßen")
	Library._epic_wait.clear()
	Library.demo = was_demo
	Library.games = keep
	Library._reindex()


const DIP_NEW := """<?xml version="1.0" encoding="utf-8"?>
<DiPManifest version="4.0">
	<contentIDs>
		<contentID>1035052</contentID>
		<contentID>71171</contentID>
	</contentIDs>
	<gameTitles>
		<gameTitle locale="en_US">Battlefield™ 1</gameTitle>
		<gameTitle locale="de_DE">Battlefield™ 1 (DE)</gameTitle>
	</gameTitles>
	<runtime>
		<launcher uid="trial">
			<filePath>[HKEY_LOCAL_MACHINE\\SOFTWARE\\EA Games\\Battlefield 1\\Install Dir]bf1_trial.exe</filePath>
			<trial>1</trial>
		</launcher>
		<launcher uid="x86">
			<filePath>[HKEY_LOCAL_MACHINE\\SOFTWARE\\EA Games\\Battlefield 1\\Install Dir]bf1_x86.exe</filePath>
			<requires64BitOS>0</requires64BitOS>
			<trial>0</trial>
		</launcher>
		<launcher uid="x64">
			<filePath>[HKEY_LOCAL_MACHINE\\SOFTWARE\\EA Games\\Battlefield 1\\Install Dir]bin\\bf1.exe</filePath>
			<parameters>-dx12</parameters>
			<requires64BitOS>1</requires64BitOS>
			<trial>0</trial>
		</launcher>
	</runtime>
</DiPManifest>
"""

const DIP_OLD := """<?xml version="1.0" encoding="utf-8"?>
<game manifestVersion="1.1">
	<metadata>
		<localeInfo locale="en_US"><title>Dragon Age™: Origins</title></localeInfo>
	</metadata>
	<contentIDs><contentID>70377</contentID></contentIDs>
	<runtime><launcher><filePath>[HKEY_LOCAL_MACHINE\\SOFTWARE\\BioWare\\Dragon Age\\Path]bin_ship\\daorigins.exe</filePath></launcher></runtime>
</game>
"""


func _ea_installer() -> void:
	var d := EA.parse_installer_data(DIP_NEW, "C:/Games/BF1")
	check(d.get("ids", []) == ["1035052", "71171"], "Inhalts-IDs gelesen")
	check(str(d.get("title", "")) == "Battlefield™ 1 (DE)", "deutscher Titel bevorzugt")
	check(str(d.get("exe", "")) == "C:/Games/BF1/bin/bf1.exe" and str(d.get("args", "")) == "-dx12",
			"64-Bit-Programmdatei samt Parametern, Testversion ausgelassen")
	var o := EA.parse_installer_data(DIP_OLD, "D:/DAO")
	check(str(o.get("title", "")) == "Dragon Age™: Origins" and o.get("ids", []) == ["70377"], "alte Form (localeInfo/title)")
	check(str(o.get("exe", "")) == "D:/DAO/bin_ship/daorigins.exe", "Registry-Platzhalter in eckigen Klammern = Spielordner")
	check(EA.parse_installer_data("", "x").is_empty() and str(EA.parse_installer_data("kein xml <<<", "x").get("exe", "")) == "", "kaputte Datei: kein Absturz")
	check(EA.resolve_path("C:\\Games\\X\\x.exe", "D:/Y") == "C:/Games/X/x.exe" and EA.resolve_path("bin\\x.exe", "D:/Y") == "D:/Y/bin/x.exe",
			"absolute und relative Pfade")
	var g := EA.entry(d, "C:/Games/BF1", "", [], "origin2")
	check(str(g.get("id", "")) == "ea:1035052" and str(g.get("source", "")) == "ea" and str(g.get("system", "")) == "ea",
			"eigene Quelle „ea“, ID aus der ersten Inhalts-ID")
	check(str(g.get("title", "")) == "Battlefield 1 (DE)", "Titel ohne ™")
	check(EA.entry({}, "C:/Games/Leer").is_empty(), "ohne ID und Programmdatei: kein Spiel")
	var eb := EA.entry({ "ids": ["1"], "exe": "//203.0.113.5/x/spiel.exe", "args": "-x & calc" }, "C:/Games/X")
	check(not eb.has("path") and not eb.has("args") and EA.entry({ "ids": ["1"] }, "//203.0.113.5/x").is_empty(),
			"EA: Programmdatei auf Freigabe und Parameter mit Sonderzeichen verworfen, Ordner auf Freigabe: kein Spiel")
	check(str(EA.entry({ "exe": "C:/G/Z/z.exe" }, "C:/G/Z", "Zuma Deluxe").get("title", "")) == "Zuma Deluxe",
			"Titel aus der Registry, wenn installerdata keinen hat")


func _ea_mfst() -> void:
	var m := EA.parse_mfst("?currentstate=kReadyToStart&downloading=0&id=OFB-EAST%3a109552316&dipinstallpath=C%3a%5cProgram%20Files%20(x86)%5cOrigin%20Games%5cBattlefield%201%5c&previousstate=kInstalling")
	check(str(m.id) == "OFB-EAST:109552316", "Angebots-ID entschlüsselt")
	check(str(m.dir) == "C:/Program Files (x86)/Origin Games/Battlefield 1", "Spielordner entschlüsselt")
	check(str(m.state) == "kReadyToStart" and str(m.platform) == "", "Zustand, kein fremder Shop")
	var s := EA.parse_mfst("?id=Origin.OFR.50.0002694%40steam&dipinstallpath=D%3a%5cSteam%5csteamapps%5ccommon%5cX%5c")
	check(str(s.id) == "Origin.OFR.50.0002694" and str(s.platform) == "steam", "über Steam gekauft erkannt (@steam)")


func _ea_scan() -> void:
	var pd := root.path_join("ProgramData")
	var roots := root.path_join("Program Files/EA Games")
	var sims := roots.path_join("The Sims 4")
	write(sims.path_join("__Installer/installerdata.xml"),
			DIP_NEW.replace("Battlefield™ 1 (DE)", "Die Sims™ 4").replace("Battlefield™ 1", "The Sims™ 4").replace("1035052", "1014052"))
	DirAccess.make_dir_recursive_absolute(roots.path_join("Kein Spiel"))
	var reg_dir := root.path_join("D-Spiele/Mass Effect")
	write(reg_dir.path_join("__Installer/installerdata.xml"), DIP_OLD.replace("Dragon Age™: Origins", "Mass Effect™ Legendary Edition").replace("70377", "1999"))
	var mf_dir := root.path_join("Origin Games/Titanfall 2")
	write(mf_dir.path_join("__Installer/installerdata.xml"),
			DIP_OLD.replace("Dragon Age™: Origins", "Titanfall® 2").replace("<contentIDs><contentID>70377</contentID></contentIDs>", ""))
	write(pd.path_join("Origin/LocalContent/Titanfall 2/OFB.mfst"),
			"?id=Origin.OFR.50.0001452&dipinstallpath=%s%%5c" % mf_dir.replace("/", "%5c").replace(":", "%3a"))
	var st_dir := root.path_join("Origin Games/Steamspiel")
	write(st_dir.path_join("__Installer/installerdata.xml"), DIP_OLD.replace("70377", "555"))
	write(pd.path_join("Origin/LocalContent/Steamspiel/S.mfst"), "?id=Origin.OFR.50.555%%40steam&dipinstallpath=%s" % st_dir)
	var ep_dir := root.path_join("Epic Games/EA-über-Epic")
	write(ep_dir.path_join("__Installer/installerdata.xml"), DIP_OLD.replace("70377", "777"))
	var reg := [{ "dir": reg_dir.replace("/", "\\") + "\\", "name": "Mass Effect Legendary Edition" }, { "dir": sims, "name": "The Sims 4" },
		{ "dir": st_dir, "name": "Steamspiel" }, { "dir": ep_dir, "name": "Über Epic" }, { "dir": root.path_join("Leer"), "name": "Weg" }]
	var got := EA.scan(reg, { "origin2": true, "link2ea": true }, [ep_dir], pd, [roots])
	var by := {}
	for g in got:
		by[str(g.title)] = g
	check(got.size() == 3, "drei EA-Spiele, ohne doppelte (%d: %s)" % [got.size(), ", ".join(PackedStringArray(by.keys()))])
	check(by.has("Die Sims 4") and str((by["Die Sims 4"] as Dictionary).id) == "ea:1014052", "Standardordner Program Files\\EA Games (und Registry) – einmal")
	check(by.has("Mass Effect Legendary Edition") and str((by["Mass Effect Legendary Edition"] as Dictionary).install_dir) == reg_dir,
			"Ordner aus der Registry (Backslashes, Schrägstrich am Ende)")
	var tf: Dictionary = by.get("Titanfall 2", {})
	check(not tf.is_empty() and (tf.get("ea", {}) as Dictionary).get("ids", []) == ["Origin.OFR.50.0001452"], "Origin-Manifest: Angebots-ID für den Start")
	check(not by.has("Steamspiel") and not by.has("Dragon Age: Origins"), "über Steam bzw. Epic gekaufte EA-Spiele nicht doppelt")
	check(str((by.get("Die Sims 4", {}) as Dictionary).get("path", "")) == sims.path_join("bin/bf1.exe"), "Programmdatei fürs Spielende und als Notlösung")
	check(EA.scan([], {}, [], root.path_join("leer"), [root.path_join("gibt-es-nicht")]).is_empty(), "ohne EA app: leere Liste")


func _uris() -> void:
	var e := Epic.parse_manifest(EPIC_ITEM)
	check(Epic.launch_uri(e) == "com.epicgames.launcher://apps/dc9d2e595d0e4650a35d659f90d41059%3Ac4763f236d08423eb47b4c3008779c84%3AKinglet?action=launch&silent=true", "Epic: com.epicgames.launcher://apps/<Namespace>%3A<Item>%3A<App>?action=launch&silent=true")
	var g := { "ea": { "ids": ["1035052", "71171"], "proto": "origin2" } }
	check(EA.launch_uri(g) == "origin2://game/launch?offerIds=1035052,71171", "EA: origin2://game/launch?offerIds=…")
	g.ea.proto = "link2ea"
	check(EA.launch_uri(g) == "link2ea://launchgame/1035052?platform=pcwin", "EA: link2ea://launchgame/<ID>?platform=pcwin")
	g.ea.proto = ""
	check(EA.launch_uri(g) == "", "EA ohne angemeldeten Link: Programmdatei direkt")
	check(EA.launch_uri({ "ea": { "ids": ["OFB-EAST:109552316"], "proto": "origin2" } }) == "origin2://game/launch?offerIds=OFB-EAST%3A109552316",
			"Doppelpunkt in der ID kodiert")
	check(EA.launch_uri({}) == "", "ohne IDs: kein Link")
	check(EA.pick_proto({}) == "origin2" and EA.pick_proto({ "origin2": false, "link2ea": true }) == "link2ea"
			and EA.pick_proto({ "origin2": false, "link2ea": false }) == "", "Link je nachdem, was angemeldet ist")


func _library() -> void:
	var keep: Array = Library.games
	Library.games = []
	Library._reindex()
	var epic := Epic.parse_manifest(EPIC_ITEM)
	var ea := EA.entry(EA.parse_installer_data(DIP_NEW, "C:/Games/BF1"), "C:/Games/BF1")
	var steam := { "id": "steam:1", "title": "Portal", "system": "steam", "source": "steam", "appid": 1, "installed": true }
	Library._merge([epic, ea, steam])
	check(Library.visible_games().size() == 3, "Epic, EA und Steam in der Bibliothek")
	var gs = Games.new()
	var tabs: Array = gs.subtabs().map(func(t): return str(t.id))
	check("epic" in tabs and "ea" in tabs and "steam" in tabs, "Reiter „Epic“ und „EA“ wie „Steam“ (%s)" % ", ".join(PackedStringArray(tabs)))
	var labels: Array = gs.subtabs().map(func(t): return str(t.label))
	check("Epic" in labels and "EA" in labels, "Beschriftung der Reiter")
	check(gs.games_for("epic").size() == 1 and gs.games_for("ea").size() == 1, "Raster je Quelle (Alle anzeigen)")
	gs.sub = "ea"
	check(gs._source_name() == "EA app", "„Alle anzeigen“ nennt die EA app")
	gs.sub = "epic"
	check(gs._source_name() == "Epic Games", "… und Epic Games")
	gs.free()
	check(Library.store_name(epic) == "Epic Games" and Library.store_name(ea, true) == "EA" and Library.store_name({ "source": "rom" }, false, "PS2") == "PS2",
			"Name der Quelle für Spielseite und Guide")
	# Spielzeit: eigene Messung wie bei Emulator-Spielen.
	Library.record_session(str(ea.id), 600)
	check(Library.playtime(Library.get_game(str(ea.id))) == 600 and Library.last_played(Library.get_game(str(ea.id))) > 0, "Spielzeit und „zuletzt“ gemessen")
	# Deinstalliert (oder Quelle aus): bleibt mit Spielzeit erhalten, wird ausgeblendet.
	var title_custom := Library.get_game(str(epic.id))
	title_custom["title"] = "Mein Alan Wake"
	title_custom["title_custom"] = true
	Library._merge([epic, steam])
	check(bool(Library.get_game(str(ea.id)).get("missing", false)) and Library.playtime(Library.get_game(str(ea.id))) == 600,
			"EA-Spiel nicht mehr da: ausgeblendet, Spielzeit bleibt")
	check(Library.display_title(Library.get_game(str(epic.id))) == "Mein Alan Wake", "eigener Titel bleibt beim Neueinlesen")
	Library._merge([epic, ea, steam])
	check(not bool(Library.get_game(str(ea.id)).get("missing", false)), "wieder installiert: wieder da")
	Config.set_value("library.ea_enabled", false)
	check(not Library.is_visible(Library.get_game(str(ea.id))) and Library.is_visible(Library.get_game(str(epic.id))),
			"EA in den Einstellungen aus: sofort ausgeblendet")
	Config.set_value("library.ea_enabled", true)
	Config.set_value("library.epic_enabled", false)
	check(not Library.is_visible(Library.get_game(str(epic.id))) and Library.is_visible(Library.get_game(str(ea.id))), "Epic aus: ebenso")
	Config.set_value("library.epic_enabled", true)
	Library.games = keep
	Library._reindex()


func _steam_status() -> void:
	Config.set_value("steam.status_nonsteam", true)
	Launcher.remote_play = false
	for g in [Epic.parse_manifest(EPIC_ITEM), EA.entry(EA.parse_installer_data(DIP_NEW, "C:/Games/BF1"), "C:/Games/BF1")]:
		Launcher.current = g
		Launcher._steam_status(true)
		check(SteamCM.games_name == Library.display_title(g), "%s: „Spielt Nicht-Steam-Spiel: %s“" % [Library.store_name(g), SteamCM.games_name])
		Launcher._steam_status(false)
		check(SteamCM.games_name == "", "%s: Spielende setzt den Status zurück" % Library.store_name(g))
	Launcher.current = {}
