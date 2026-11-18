extends Node
## Weitere Bibliotheken (Punkt 6): GOG, Ubisoft Connect, Battle.net, Xbox-App, Amazon Games, itch.io
## und Riot – ohne Windows, mit Beispieldateien je Launcher (tests/fixtures/bibliotheken, gebaut von
## make.py) und mit kaputten, riesigen und bösartigen Daten: Pfade mit „..“, Netzwerkpfade,
## Steuerzeichen, absurde IDs, Schleifen in der Datenbank. Dazu Startwege, Doppelte (ein Spiel in
## mehreren Launchern) und fehlende Launcher.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_bibliotheken.tscn → „Ergebnis: alles ok“
## Die Helfer-Befehle „store-games“ und „xbox-games“ lesen nur unter Windows echte Daten; hier kommen
## ihre Einträge als fertige Listen in die Scanner.

const SU := preload("res://src/library/store_util.gd")
const Sql := preload("res://src/library/sqlite_reader.gd")
const Gog := preload("res://src/library/gog_scanner.gd")
const Ubi := preload("res://src/library/ubisoft_scanner.gd")
const Bnet := preload("res://src/library/battlenet_scanner.gd")
const Xbox := preload("res://src/library/xbox_scanner.gd")
const Amazon := preload("res://src/library/amazon_scanner.gd")
const Itch := preload("res://src/library/itch_scanner.gd")
const Riot := preload("res://src/library/riot_scanner.gd")
const Stores := preload("res://src/library/stores.gd")
const LauncherSites := preload("res://src/library/launcher_sites.gd")
const FIX := "res://tests/fixtures/bibliotheken/"

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


func write_bytes(path: String, b: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


func fix(name: String) -> String:
	return ProjectSettings.globalize_path(FIX + name)


func _ready() -> void:
	root = Config.path("bibliotheken-test")
	print("Pfade und Texte prüfen")
	_util()
	print("SQLite-Leser")
	_sqlite()
	print("GOG")
	_gog()
	print("Ubisoft Connect")
	_ubisoft()
	print("Battle.net")
	_battlenet()
	print("Xbox-App")
	_xbox()
	print("Amazon Games")
	_amazon()
	print("itch.io")
	_itch()
	print("Riot")
	_riot()
	print("Startwege und Launcher")
	_launch()
	print("Doppelte")
	_dupes()
	print("Bibliothek")
	_library()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _util() -> void:
	check(SU.norm_path("C:\\Spiele\\\\X\\") == "C:/Spiele/X", "Pfad vereinheitlicht (Trenner, doppelt, am Ende)")
	check(SU.norm_path("c:/a/b") == "C:/a/b", "Laufwerk groß")
	for bad in ["C:\\Spiele\\..\\Windows", "C:/a/./b", "\\\\server\\share\\x", "//server/x", "Spiele\\X", "C:Spiele", "C:/a\nb", "C:/a\u0001b", "C:/a\u0085b",
			"C:/a\"b", "C:/a|b", "C:/a /b", "C:/a/b.", "C:/x:y", "", " ", "C:/" + "a".repeat(2000)]:
		check(SU.norm_path(bad) == "", "abgelehnt: %s" % bad.c_escape().left(40))
	check(SU.game_dir("C:/Program Files") == "" and SU.game_dir("D:/") == "" and SU.game_dir("C:/XboxGames") == "" and SU.game_dir("C:/Spiele") == "",
		"Sammelordner sind nie ein Spielordner (sonst träfe „Spiel beenden“ Fremdes)")
	check(SU.game_dir("D:/GOG Games/Witcher") == "D:/GOG Games/Witcher", "echter Spielordner")
	check(SU.child("D:/G/X", "bin\\x64\\w.exe") == "D:/G/X/bin/x64/w.exe", "Datei im Spielordner")
	for bad in ["..\\..\\Windows\\cmd.exe", "C:\\Windows\\cmd.exe", "/etc/passwd", "a/../../b.exe", ""]:
		check(SU.child("D:/G/X", bad) == "", "nicht aus dem Spielordner heraus: %s" % bad)
	check(SU.title("The Witcher® 3:\tWild\u0007Hunt™ ") == "The Witcher 3: Wild Hunt", "Titel ohne Marken- und Steuerzeichen")
	check(SU.title("x".repeat(5000)).length() <= 160, "Titel begrenzt")
	check(SU.id_ok("1207664663", Gog.ID_RE) != "" and SU.id_ok("12; calc", Gog.ID_RE) == "" and SU.id_ok("9".repeat(40), Gog.ID_RE) == "", "IDs nur nach Muster")
	check(SU.unix_of("2024-05-01 18:20:11") == 1714587611 and SU.unix_of("2024-05-01T18:20:11.5Z") == 1714587611, "Zeitstempel (UTC)")
	check(SU.unix_of("kein Datum") == 0 and SU.unix_of("1900-01-01") == 0 and SU.unix_of("2024-13-01") == 0, "unplausible Zeiten: 0")
	write(root.path_join("gross.txt"), "x".repeat(SU.TEXT_MAX + 10))
	check(SU.read_text(root.path_join("gross.txt")) == "", "zu große Datei wird nicht gelesen")
	check(SU.read_text(root.path_join("gibtsnicht.txt")) == "", "fehlende Datei: leer")
	check(SU.entries({ "a": 1 }).size() == 1 and SU.entries("x").is_empty() and SU.entries([1, {}, "x"]).size() == 1, "Helfer-Listen (ein Eintrag, Unsinn)")
	check(SU.sub({ "gog": "kein Wörterbuch" }, "gog").is_empty(), "Teil-Wörterbuch: Unsinn wird leer")


func _sqlite() -> void:
	var names := Sql.table_names(fix("galaxy.db"))
	check("installedbaseproducts" in names and "viel" in names and not ("ohne" in names),
			"Tabellen aus sqlite_master (WITHOUT ROWID übersprungen): %s" % str(names))
	var r := Sql.read_tables(fix("galaxy.db"), { "Viel": ["id", "a", "b", "c"], "LimitedDetails": ["productId", "title", "images"], "Fehlt": ["x"] })
	var viel: Array = r.tables.Viel
	check(r.ok and viel.size() == 3000, "große Tabelle über innere Seiten: %d Zeilen" % viel.size())
	var by_id := {}
	for row in viel:
		by_id[int(row.id)] = row
	check(by_id.has(1) and by_id.has(3000) and str(by_id[1234].a) == "Zeile 1233" and int(by_id[1234].b) == 1233 * 1000003,
			"Werte und rowid-Spalte (INTEGER PRIMARY KEY)")
	check(absf(float(by_id[8].c) - 1.0) < 0.0001, "Kommazahlen (REAL)")
	var ld: Array = r.tables.LimitedDetails
	check(ld.size() == 2 and str(ld[0].images).length() == 5000, "langer Text über Überlaufseiten")
	check(str(ld[0].title) == "The Witcher® 3: Wild Hunt", "UTF-8")
	check((r.tables.Fehlt as Array).is_empty(), "fehlende Tabelle: leer")
	var loop := Sql.read_tables(fix("schleife.db"), { "t": ["id", "a"] })
	check(str(loop.error) == "Schleife" and (loop.tables.t as Array).size() < 400,
			"Schleife in der Datei: endet, mit Fehler (%d Zeilen)" % (loop.tables.t as Array).size())
	write(root.path_join("muell.db"), "kein sqlite".repeat(100))
	check(not bool(Sql.read_tables(root.path_join("muell.db"), { "t": ["a"] }).ok), "keine SQLite-Datei: abgelehnt")
	var head := "SQLite format 3".to_utf8_buffer()
	head.append(0)
	head.resize(2048)
	head[16] = 0x03
	head[17] = 0x00
	write_bytes(root.path_join("seite.db"), head)
	check(Sql.read_tables(root.path_join("seite.db"), { "t": ["a"] }).error == "Seitengröße", "unsinnige Seitengröße: abgelehnt")
	var rnd := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 8192:
		rnd.append(rng.randi() % 256)
	var hdr := "SQLite format 3".to_utf8_buffer()
	hdr.append(0)
	for i in hdr.size():
		rnd[i] = hdr[i]
	rnd[16] = 0x04
	rnd[17] = 0x00
	rnd[20] = 0
	for i in [56, 57, 58, 59]:
		rnd[i] = 0
	rnd[59] = 1
	write_bytes(root.path_join("zufall.db"), rnd)
	var z := Sql.read_tables(root.path_join("zufall.db"), { "t": ["a"] })
	check(z.tables.t is Array, "Zufallsdaten mit gültigem Kopf: kein Absturz")
	var cols := Sql.columns("CREATE TABLE \"x y\" ([a b] TEXT, `c` INTEGER PRIMARY KEY, \"d\" TEXT DEFAULT 'a,b', e, PRIMARY KEY (e), CONSTRAINT k UNIQUE (d))")
	check(cols.names == ["a b", "c", "d", "e"] and int(cols.rowid) == 1, "Spaltennamen mit Anführungszeichen, Standardwerten und Bedingungen: %s" % str(cols))
	check(Sql.columns("CREATE TABLE t (a TEXT PRIMARY KEY) WITHOUT ROWID").is_empty() and Sql.columns("kaputt").is_empty(), "WITHOUT ROWID und Unsinn: nichts")
	check(Sql.record(PackedByteArray([0x7f, 1, 2])) == null and Sql.record(PackedByteArray([2, 0x30, 0x41])) == null, "kaputter Satz: null")
	check(Sql.record(PackedByteArray([3, 1, 0x17, 0xff, 0x41, 0x42, 0x43, 0x44, 0x45])) == [-1, "ABCDE"], "Satz mit Zahl (Vorzeichen) und Text")


func _gog() -> void:
	var info := """{"gameId":"1207664663","rootGameId":"1207664663","name":"The Witcher 3: Wild Hunt","playTasks":[
		{"category":"document","type":"FileTask","path":"manual.pdf"},
		{"category":"game","isPrimary":true,"type":"FileTask","path":"bin\\\\x64\\\\witcher3.exe","arguments":"-debugscripts","workingDir":"bin\\\\x64"}]}"""
	var p := Gog.parse_info(info)
	check(str(p.id) == "1207664663" and str(p.exe) == "bin\\x64\\witcher3.exe" and str(p.args) == "-debugscripts", "goggame-*.info: Hauptaufgabe gelesen")
	check(Gog.parse_info("kaputt").is_empty() and Gog.parse_info("[]").is_empty(), "kaputte info-Datei: nichts")
	var dir := root.path_join("GOG Games/Witcher")
	write(dir.path_join("bin/x64/witcher3.exe"), "x")
	write(dir.path_join("goggame-1207664663.info"), info)
	var g := Gog.entry("1207664663", dir, p)
	check(str(g.id) == "gog:1207664663" and str(g.source) == "gog" and str(g.system) == "gog", "eigene Quelle „gog“")
	check(str(g.path).ends_with("/bin/x64/witcher3.exe") and str(g.gog.args) == "-debugscripts", "Programmdatei und Parameter")
	var evil := Gog.entry("1207664663", dir,
			Gog.parse_info(info.replace("bin\\\\x64\\\\witcher3.exe", "..\\\\..\\\\..\\\\Windows\\\\System32\\\\cmd.exe").replace("-debugscripts", "& calc")))
	check(not evil.has("path") and not (evil.gog as Dictionary).has("args"), "Programm außerhalb des Spielordners und Parameter mit & werden verworfen")
	check(Gog.entry("12;calc", dir, p).is_empty() and Gog.entry("1207664663", "C:/Program Files", p).is_empty(), "absurde ID und Sammelordner: kein Spiel")
	var dlc := Gog.parse_info(info.replace("\"rootGameId\":\"1207664663\"", "\"rootGameId\":\"1495134320\""))
	check(Gog.entry("1207664663", dir, dlc).is_empty(), "Zusatzinhalt (rootGameId anders): kein eigenes Spiel")
	var db := Gog.read_db(fix("galaxy.db"))
	check(str(db.installed.get("1207664663", "")).contains("Witcher") and str(db.titles.get("1771589310", "")) == "Disco Elysium - The Final Cut",
			"Galaxy-Datenbank: installiert und Titel")
	check(int(db.minutes.get("1207664663", 0)) == 5460 and not db.minutes.has("1771589310") and not db.minutes.has("292030"),
			"Spielzeit nur von GOG-Spielen, nie negativ")
	check(int(db.last.get("1207664663", 0)) == 1714587611 and not db.last.has("1771589310"), "zuletzt gespielt; ohne Datum nichts")
	check(not db.installed.has("123"), "zu kurze ID (keine echte GOG-ID) übergangen")
	var reg := [{ "id": "1207664663", "path": dir.replace("/", "\\"), "name": "Witcher 3", "exe": dir.path_join("bin/x64/witcher3.exe") },
		{ "id": "1495134320", "path": dir, "name": "DLC", "depends": "1207664663" },
		{ "id": "abc", "path": dir, "name": "Böse" }, { "id": "1771589311", "path": "\\\\server\\share\\spiel", "name": "Netz" }]
	var odir := root.path_join("GOG Games Ordner/Celeste")
	write(odir.path_join("Celeste.exe"), "x")
	write(odir.path_join("goggame-1497013334.info"),
			"{\"gameId\":\"1497013334\",\"name\":\"Celeste\",\"playTasks\":[{\"isPrimary\":true,\"type\":\"FileTask\",\"path\":\"Celeste.exe\"}]}")
	var got := Gog.scan(reg, fix("galaxy.db"), [root.path_join("GOG Games Ordner")])
	var ids := got.map(func(x: Dictionary) -> String: return str(x.id))
	check(ids == ["gog:1207664663", "gog:1497013334"], "Registry und Spieleordner, ohne DLC, Unsinn und Netzwerkpfad: %s" % str(ids))
	check(int(got[0].get("store_minutes", 0)) == 5460 and int(got[0].get("store_last", 0)) > 0, "Spielzeit und zuletzt aus Galaxy am Spiel")


func _ubisoft() -> void:
	var names := Ubi.names_of(
			[{ "key": "Uplay Install 5059", "name": "Assassin's Creed Valhalla" }, { "key": "Uplay Install x;y", "name": "Böse" }, { "key": "Anderes", "name": "X" }])
	check(names.size() == 1 and str(names["5059"]) == "Assassin's Creed Valhalla", "Namen aus den Deinstallations-Einträgen")
	var d1 := root.path_join("Ubisoft/games/Valhalla")
	DirAccess.make_dir_recursive_absolute(d1)
	var reg := [{ "id": "5059", "dir": d1.replace("/", "\\") + "\\" }, { "id": "999999999", "dir": d1 },
			{ "id": "77", "dir": root.path_join("steamapps/common/X") },
		{ "id": "78", "dir": root.path_join("gibt es nicht") }, { "id": "79", "dir": "C:\\..\\Windows" }]
	DirAccess.make_dir_recursive_absolute(root.path_join("steamapps/common/X"))
	var got := Ubi.scan(reg, names, [])
	check(got.size() == 1 and str(got[0].id) == "ubisoft:5059" and str(got[0].title) == "Assassin's Creed Valhalla",
			"nur gültige IDs mit Ordner, nichts aus Steam: %d" % got.size())
	check(Ubi.scan(reg, names, [d1]).is_empty(), "Ordner, den schon Epic zeigt: nicht doppelt")
	check(Ubi.launch_uri(got[0]) == "uplay://launch/5059/0", "Start-Link wie Ubisoft Connects Verknüpfungen")
	check(Ubi.launch_uri({ "ubisoft": { "id": "5059/0&x" } }) == "" and Ubi.launch_uri({}) == "", "kein Link aus ungültiger ID")


## Protobuf bauen (wie product.db), für eigene Ordner im Testverzeichnis.
func _pv(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	while true:
		var b := n & 0x7f
		n >>= 7
		if n != 0:
			out.append(b | 0x80)
		else:
			out.append(b)
			return out
	return out


func _pf(num: int, v: Variant) -> PackedByteArray:
	if v is int:
		var a := _pv(num << 3)
		a.append_array(_pv(v))
		return a
	var payload: PackedByteArray = v.to_utf8_buffer() if v is String else v
	var b := _pv((num << 3) | 2)
	b.append_array(_pv(payload.size()))
	b.append_array(payload)
	return b


func _product(uid: String, code: String, path: String) -> PackedByteArray:
	var inner := _pf(1, uid)
	inner.append_array(_pf(2, code))
	inner.append_array(_pf(3, _pf(1, path)))
	inner.append_array(_pf(4, _pf(1, _pf(1, 1))))
	return _pf(1, inner)


func _battlenet() -> void:
	var raw := FileAccess.get_file_as_bytes(fix("product.db"))
	var ps := Bnet.parse_db(raw)
	var codes := ps.map(func(p: Dictionary) -> String: return str(p.code))
	check("Pro" in codes and "WoW" in codes and "agent" in codes, "product.db gelesen: %s" % str(codes))
	var d3: Array = ps.filter(func(p: Dictionary) -> bool: return str(p.code) == "D3")
	check(d3.size() == 1 and not bool(d3[0].installed), "nicht installiert erkannt")
	var ow := root.path_join("Blizzard/Overwatch")
	var bad := root.path_join("Blizzard/Boese")
	DirAccess.make_dir_recursive_absolute(ow)
	DirAccess.make_dir_recursive_absolute(bad)
	var db := _product("prometheus", "Pro", ow)
	db.append_array(_product("agent", "agent", root.path_join("Blizzard")))
	db.append_array(_product("battle.net", "App", ow))
	db.append_array(_product("x", "B;calc", bad))
	db.append_array(_product("y", "ZZZ9", bad))
	var got := Bnet.scan(db, { bad.to_lower(): "Neues Spiel" }, { "prometheus": 1714587611 })
	var ids := got.map(func(x: Dictionary) -> String: return str(x.id))
	check(ids == ["battlenet:Pro", "battlenet:ZZZ9"], "Spiele ohne Agent/App, ohne ungültigen Code: %s" % str(ids))
	check(str(got[0].title) == "Overwatch 2" and str(got[1].title) == "Neues Spiel" and int(got[0].get("store_last", 0)) == 1714587611,
			"Titel aus fester Liste bzw. Windows, zuletzt gespielt")
	check(Bnet.parse_db(PackedByteArray([0x0a, 0xff, 0xff, 0xff, 0x0f, 1, 2])).is_empty(), "Länge über das Ende: nichts")
	var junk := PackedByteArray()
	junk.resize(4096)
	junk.fill(0xff)
	check(Bnet.parse_db(junk).is_empty(), "Unsinn: nichts, kein Absturz")
	var huge := PackedByteArray()
	huge.resize(Bnet.DB_MAX + 1)
	check(Bnet.parse_db(huge).is_empty(), "zu große Datei: nichts")
	var cfg := Bnet.parse_config("{\"Games\":{\"prometheus\":{\"LastPlayed\":\"1714587611\"},\"wow\":{\"LastPlayed\":\"9999999999999\"},\"x\":\"y\"}}")
	check(int(cfg.get("prometheus", 0)) == 1714587611 and not cfg.has("wow") and not cfg.has("x"), "Battle.net.config: zuletzt gespielt, Unsinn übergangen")
	var cdir := root.path_join("Battle.net")
	write(cdir.path_join("Battle.net.exe"), "x")
	check(Bnet.client_exe(cdir) == cdir.path_join("Battle.net.exe"), "Battle.net-Programm gefunden")
	var plan := Bnet.launch_plan(got[0], Bnet.client_exe(cdir))
	check(str(plan.get("args", "")) == "--exec=\"launch Pro\"", "Start wie Battle.nets Verknüpfungen: %s" % str(plan.get("args", "")))
	check(Bnet.launch_plan({ "battlenet": { "code": "Pro\" & calc" } }, Bnet.client_exe(cdir)).is_empty(), "kein Start mit ungültigem Code")


const XBOX_CFG := """<?xml version="1.0" encoding="utf-8"?>
<Game configVersion="1">
  <Identity Name="Microsoft.624F8B84B80" Publisher="CN=Microsoft" Version="3.0.0.0"/>
  <ExecutableList>
    <Executable Name="ForzaHorizon5.exe" Id="ForzaHorizon5" TargetDeviceFamily="PC"/>
  </ExecutableList>
  <ShellVisuals DefaultDisplayName="Forza Horizon 5" PublisherDisplayName="Microsoft Studios"/>
</Game>"""


func _xbox() -> void:
	var c := Xbox.parse_config(XBOX_CFG)
	check(str(c.title) == "Forza Horizon 5" and (c.exes as Array).size() == 1 and str(c.exes[0].id) == "ForzaHorizon5", "MicrosoftGame.config gelesen")
	check(str(Xbox.parse_config("<kaputt").title) == "" and str(Xbox.parse_config("").title) == "", "kaputte Datei: nichts")
	var dir := root.path_join("XboxGames/Forza Horizon 5/Content")
	write(dir.path_join("MicrosoftGame.config"), XBOX_CFG)
	write(dir.path_join("ForzaHorizon5.exe"), "x")
	var pk := { "family": "Microsoft.624F8B84B80_8wekyb3d8bbwe", "name": "Microsoft.624F8B84B80", "dir": dir.replace("/", "\\"),
			"apps": ["Launcher", "ForzaHorizon5"], "title": "ms-resource:AppName" }
	var got := Xbox.scan([pk, { "family": "Microsoft.GamingApp_8wekyb3d8bbwe", "name": "Microsoft.GamingApp", "dir": dir, "apps": ["App"] },
		{ "family": "Böse\";calc_8wekyb3d8bbwe", "name": "x", "dir": dir, "apps": ["App"] }, { "family": "A.B_8wekyb3d8bbwe", "name": "A.B", "dir": dir, "apps": [] },
		{ "family": "C.D_8wekyb3d8bbwe", "name": "C.D", "dir": "C:\\Program Files\\WindowsApps", "apps": ["App"] }])
	check(got.size() == 1 and str(got[0].id) == "xboxpc:Microsoft.624F8B84B80_8wekyb3d8bbwe",
			"nur Spiele (Xbox-App selbst, ungültige Familie, ohne App, Sammelordner raus): %d" % got.size())
	check(str(got[0].title) == "Forza Horizon 5" and str(got[0].xboxpc.aumid) == "Microsoft.624F8B84B80_8wekyb3d8bbwe!ForzaHorizon5",
			"Titel aus der Spieldatei, App laut ExecutableList")
	check(str(got[0].get("path", "")).ends_with("Content/ForzaHorizon5.exe"), "Programmdatei für das Spielende")
	check(Xbox.launch_uri(got[0]) == "shell:AppsFolder\\Microsoft.624F8B84B80_8wekyb3d8bbwe!ForzaHorizon5", "Start wie im Startmenü")
	check(Xbox.launch_uri({ "xboxpc": { "aumid": "A.B_8wekyb3d8bbwe!App & calc" } }) == "" and Xbox.launch_uri({ "xboxpc": { "aumid": "x!y!z" } }) == "",
			"kein Start mit ungültiger Kennung")
	var no_cfg := Xbox.entry(
			{ "family": "Studio.SuperGame_1234567890abc", "name": "Studio.SuperGame", "dir": root.path_join("Pakete/Studio.SuperGame_1.0"), "apps": ["Game"],
			"title": "ms-resource:x" }, {})
	check(str(no_cfg.title) == "Super Game", "ohne lesbaren Titel: Paketname in Wörtern („%s“)" % str(no_cfg.get("title", "")))
	check(Xbox.title_from("Microsoft.624F8B84B80", "C:/Program Files/WindowsApps/x") == "", "Kennung aus Ziffern und Buchstaben ist kein Titel")


func _amazon() -> void:
	var rows := Amazon.read_db(fix("amazon.sqlite"))
	check(rows.size() == 2, "installierte Zeilen aus DbSet (deinstallierte nicht): %d" % rows.size())
	var g := Amazon.entry(str(rows[0].id), str(rows[0].dir), str(rows[0].name))
	check(str(g.get("title", "")) == "Fallout 3: Game of the Year Edition" and str(g.install_dir) == "C:/Amazon Games/Library/Fallout 3",
			"Spiel aus der Datenbank")
	check(Amazon.entry(str(rows[1].id), str(rows[1].dir), str(rows[1].name)).is_empty(), "ID mit Anführungszeichen und &: abgelehnt")
	check(Amazon.launch_uri(g) == "amazon-games://play/amzn1.adg.product.2d7d6c8e-3a4f-4c2b-9a77-1f5d8c0b6e21", "Start-Link der App")
	var un := Amazon.from_uninstall(
			[{ "cmd": "\"C:\\Users\\X\\AppData\\Local\\Amazon Games\\App\\Amazon Game Remover.exe\" -m Game -p amzn1.adg.product.2d7d6c8e-3a4f-4c2b-9a77-1f5d8c0b6e21",
			"dir": "C:\\Amazon Games\\Library\\Fallout 3", "name": "Fallout 3" },
		{ "cmd": "C:\\evil.exe -p amzn1.adg.product.2d7d6c8e-3a4f-4c2b-9a77-1f5d8c0b6e21", "dir": "C:\\x\\y", "name": "Böse" }])
	check(un.size() == 1 and str(un[0].name) == "Fallout 3", "Deinstallations-Einträge nur von Amazon Games")
	var d := root.path_join("Amazon Games/Library/Fallout 3")
	DirAccess.make_dir_recursive_absolute(d)
	var got := Amazon.scan("", [{ "cmd": "\"X\\Amazon Game Remover.exe\" -m Game -p " + str(un[0].id), "dir": d, "name": "Fallout 3" }])
	check(got.size() == 1 and str(got[0].id) == "amazon:2d7d6c8e-3a4f-4c2b-9a77-1f5d8c0b6e21", "Einlesen ohne Datenbank über Windows")


func _itch() -> void:
	var list := Itch.read_db(fix("butler.db"))
	check(list.size() == 1, "nur Spiele mit gültigem Ordner (Werkzeuge und „..“ raus): %d" % list.size())
	var g: Dictionary = list[0]
	check(str(g.id) == "itch:115302" and str(g.title) == "A Short Hike", "Spiel aus der itch-App")
	check(str(g.get("path", "")).ends_with("/a-short-hike/AShortHike.exe"), "erkannte Programmdatei – nie eine außerhalb des Ordners")
	check(int(g.get("store_minutes", 0)) == 190 and int(g.get("store_last", 0)) == 1712739600, "Spielzeit und zuletzt gespielt aus der App")
	var dir := root.path_join("itch/apps/hike")
	write(dir.path_join("AShortHike.exe"), "x")
	var plan := Itch.launch_plan({ "install_dir": dir, "path": dir.path_join("AShortHike.exe") })
	check(str(plan.get("exe", "")) == dir.path_join("AShortHike.exe") and str(plan.args) == "", "Start: die Programmdatei, ohne Parameter")
	check(Itch.launch_plan({ "install_dir": dir, "path": root.path_join("anderswo.exe") }).is_empty(), "keine Programmdatei außerhalb des Spielordners")


func _riot() -> void:
	var y := Riot.parse_yaml(
			"product_install_full_path: \"C:/Riot Games/League of Legends\"\nsettings:\n  product_install_full_path: falsch\nshortcut_name: League of Legends.lnk\n")
	check(str(y.product_install_full_path) == "C:/Riot Games/League of Legends" and y.size() == 2, "YAML: nur oberste Ebene")
	var base := root.path_join("Riot Games")
	var lol := root.path_join("RiotSpiele/League of Legends")
	DirAccess.make_dir_recursive_absolute(lol)
	write(base.path_join("Metadata/league_of_legends.live/league_of_legends.live.product_settings.yaml"), "product_install_full_path: %s\n" % lol)
	write(base.path_join("Metadata/valorant.pbe/valorant.pbe.product_settings.yaml"), "product_install_full_path: %s\n" % lol)
	write(base.path_join("Metadata/riot_client.live/riot_client.live.product_settings.yaml"), "product_install_full_path: %s\n" % lol)
	write(base.path_join("Metadata/Böse;x.live/a.yaml"), "product_install_full_path: %s\n" % lol)
	write(base.path_join("Metadata/bacon.live/bacon.live.product_settings.yaml"), "product_install_full_path: C:/Riot Games/../Windows\n")
	var got := Riot.scan(base)
	var ids := got.map(func(x: Dictionary) -> String: return str(x.id))
	ids.sort()
	check(ids == ["riot:league_of_legends", "riot:valorant.pbe"], "Spiele aus Metadata (Client, ungültige Namen und „..“ raus): %s" % str(ids))
	var client := root.path_join("RiotClient/RiotClientServices.exe")
	write(client, "x")
	write(base.path_join("RiotClientInstalls.json"), JSON.stringify({ "rc_default": client, "rc_live": "C:/Windows/System32/cmd.exe" }))
	check(Riot.client_exe(base) == client, "Riot Client aus RiotClientInstalls.json")
	write(base.path_join("RiotClientInstalls.json"), JSON.stringify({ "rc_default": root.path_join("cmd.exe") }))
	check(Riot.client_exe(base) == "", "nur RiotClientServices.exe, kein anderes Programm")
	var lg: Dictionary = got.filter(func(x: Dictionary) -> bool: return str(x.id) == "riot:league_of_legends")[0]
	var plan := Riot.launch_plan(lg, client)
	check(str(plan.get("args", "")) == "--launch-product=league_of_legends --launch-patchline=live", "Start wie Riots Verknüpfungen")
	check(Riot.launch_plan({ "riot": { "product": "lol --x", "line": "live" } }, client).is_empty(), "kein Start mit ungültigem Produkt")


func _launch() -> void:
	var gx := root.path_join("GOG Galaxy/GalaxyClient.exe")
	write(gx, "x")
	var dir := root.path_join("GOG Games/Witcher")
	var g := { "source": "gog", "gog": { "id": "1207664663", "args": "-debugscripts" }, "install_dir": dir, "path": dir.path_join("bin/x64/witcher3.exe") }
	var p := Stores.launch_plan(g, { "galaxy": gx })
	check(str(p.get("exe", "")) == gx and str(p.args) == "/command=runGame /gameId=1207664663 /path=\"%s\"" % dir.replace("/", "\\"),
			"GOG über Galaxy wie seine Verknüpfungen")
	var p2 := Stores.launch_plan(g, { "galaxy": gx }, false)
	check(str(p2.get("exe", "")).ends_with("witcher3.exe") and str(p2.args) == "-debugscripts", "GOG ohne Galaxy: die Programmdatei")
	check(Stores.launch_plan(g, { "galaxy": root.path_join("cmd.exe") }).get("via", "") == "exe", "anderes Programm als Galaxy: nie")
	check(Stores.launch_plan({ "source": "gog", "gog": { "id": "1" }, "install_dir": dir }, {}).has("why"), "ohne Weg: Grund statt Start")
	check(Stores.launch_plan({ "source": "ubisoft", "ubisoft": { "id": "5059" } }, {}).get("uri", "") == "uplay://launch/5059/0", "Ubisoft über den Link")
	check(Stores.launch_plan({ "source": "battlenet", "battlenet": { "code": "Pro" } }, {}).has("why"), "Battle.net fehlt: Grund")
	print("Fehlende Launcher")
	var all_on := {}
	check(LauncherSites.missing({ "steam": true, "gog": false, "battlenet": false, "xboxpc": false }, all_on, { "battlenet": true }) == ["battlenet"],
		"weitere Launcher nur, wenn es Spiele gibt, die sie brauchen")
	check(LauncherSites.missing({ "battlenet": false }, { "battlenet": false }, { "battlenet": true }).is_empty(), "ausgeschaltet: nichts anbieten")
	for id in Stores.EXTRA:
		check(LauncherSites.url(id).begins_with("https://") and str(LauncherSites.site(id).get("what", "")) != "", "offizielle HTTPS-Seite: " + id)
	check(not Stores.needs_client({ "source": "gog", "path": "D:/x/a.exe" }) and Stores.needs_client({ "source": "gog" })
			and Stores.needs_client({ "source": "ubisoft" }),
		"GOG mit Programmdatei braucht Galaxy nicht")
	for id in Stores.EXTRA:
		check(Icons.P.has(Stores.icon_of(id)), "eigenes Symbol: " + id)


func _dupes() -> void:
	var list: Array = [
		{ "id": "steam:1", "title": "Cyberpunk 2077", "source": "steam", "installed": true },
		{ "id": "gog:2", "title": "Cyberpunk 2077™", "source": "gog", "installed": true },
		{ "id": "xboxpc:3", "title": "CYBERPUNK 2077", "source": "xboxpc", "installed": true },
		{ "id": "gog:4", "title": "Hades", "source": "gog", "installed": true },
		{ "id": "epic:5", "title": "Hades", "source": "epic", "installed": false },
		{ "id": "rom:6", "title": "Hades", "source": "rom" },
		{ "id": "gog:7", "title": "Doom", "source": "gog", "installed": true },
		{ "id": "gog:8", "title": "DOOM", "source": "gog", "installed": true },
		{ "id": "pc:9", "title": "Doom", "source": "pc", "installed": true },
	]
	var n := Stores.link_dupes(list)
	check(n == 2 and str(list[1].get("dupe_of", "")) == "steam:1" and str(list[2].get("dupe_of", "")) == "steam:1",
			"ein Eintrag: Steam vorn, GOG und Xbox dahinter")
	check(list[0].get("alts", []) == ["gog:2", "xboxpc:3"], "vorderer Eintrag kennt die anderen")
	check(not list[3].has("dupe_of") and not list[4].has("dupe_of"), "nicht installiert und Emulator: nie zusammengeführt")
	check(not list[7].has("dupe_of") and not list[8].has("dupe_of"), "zweimal dieselbe Quelle und eigene PC-Spiele bleiben getrennt")
	Stores.link_dupes(list, { "steam": false })
	check(str(list[2].get("dupe_of", "")) == "gog:2" and not list[0].has("alts"), "Steam ausgeschaltet: GOG steht vorn")
	Stores.link_dupes(list)
	check(Stores.link_dupes([]) == 0, "leere Liste")


func _library() -> void:
	var keep: Array = Library.games
	var demo_keep: bool = Library.demo
	Library.demo = true
	Library.games = [
		{ "id": "steam:1091500", "title": "Cyberpunk 2077", "system": "steam", "source": "steam", "appid": 1091500, "installed": true, "steam_minutes": 60 },
		{ "id": "gog:1423049311", "title": "Cyberpunk 2077", "system": "gog", "source": "gog", "installed": true, "store_minutes": 300, "store_last": 1714587611,
			"gog": { "id": "1423049311" }, "install_dir": "D:/GOG Games/Cyberpunk 2077" },
		{ "id": "riot:valorant", "title": "VALORANT", "system": "riot", "source": "riot", "installed": true, "riot": { "product": "valorant", "line": "live" },
			"install_dir": "C:/Riot Games/VALORANT" },
	]
	Library.relink()
	Library._reindex()
	var vis := Library.visible_games().map(func(x: Dictionary) -> String: return str(x.id))
	check(vis.size() == 2 and "steam:1091500" in vis and "riot:valorant" in vis, "Doppelte einmal sichtbar: %s" % str(vis))
	var cp := Library.get_game("steam:1091500")
	check(Library.alternatives(cp).size() == 2 and Library.playtime(cp) == 300 * 60 and Library.last_played(cp) == 1714587611,
			"Spielzeit und zuletzt über die Launcher (größter Wert)")
	check(Library.launch_target(cp) == cp, "ohne Wahl: der eigene Launcher")
	cp["launch_via"] = "gog"
	var t := Library.launch_target(cp)
	check(str(t.id) == "steam:1091500" and str(t.source) == "gog" and str(t.via_id) == "gog:1423049311" and str(t.title) == "Cyberpunk 2077",
			"gewählt: GOG startet, Spielzeit bleibt am Eintrag")
	check(str(Library.get_game("gog:1423049311").get("id", "")) == "gog:1423049311", "Bibliothek bleibt unverändert")
	cp["_rp"] = true
	check(bool(Library.launch_target(cp).get("_rp", false)), "Felder mit _ gehen mit")
	check(Library.store_name(Library.get_game("riot:valorant")) == "Riot Client" and Library.store_name({ "source": "gog" }, true) == "GOG", "Namen der Quellen")
	Config.set_value("library.riot_enabled", false)
	check(not Library.visible_games().any(func(x: Dictionary) -> bool: return str(x.id) == "riot:valorant"), "Quelle aus: sofort weg")
	Config.set_value("library.riot_enabled", true)
	Config.set_value("library.steam_enabled", false)
	Library.relink()
	vis = Library.visible_games().map(func(x: Dictionary) -> String: return str(x.id))
	check("gog:1423049311" in vis, "Steam aus: das Spiel steht bei GOG")
	Config.set_value("library.steam_enabled", true)
	Library.launcher_need = { "battlenet": true }
	Library.launchers = { "battlenet": false, "ubisoft": false }
	check(Library.launcher_missing("battlenet") and not Library.launcher_missing("ubisoft"), "„fehlt“ nur mit Spielen, die den Launcher brauchen")
	Library.launchers = {}
	Library.launcher_need = {}
	Library.games = keep
	Library.demo = demo_keep
	Library.relink()
	Library._reindex()
