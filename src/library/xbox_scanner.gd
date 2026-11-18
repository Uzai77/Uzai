extends RefCounted
## Installierte PC-Spiele aus der Xbox-App bzw. dem PC Game Pass (Microsoft Store). Welche
## App-Pakete es für dieses Windows-Konto gibt, fragt der Helfer bei Windows ab (Get-AppxPackage,
## nur lesen, ohne Adminrechte). Ein Spiel ist nur ein Paket mit MicrosoftGame.config im Ordner –
## die legen ausschließlich Spiele an; normale Apps bleiben draußen. Titel und Programm kommen aus
## dieser Datei (streng begrenzt gelesen). Gestartet wird wie im Startmenü über
## shell:AppsFolder\<Paketfamilie>!<App-ID> – Windows und die Xbox-App kümmern sich um Lizenz und
## Anmeldung. Spielzeit speichert die Xbox-App nicht lesbar auf dem PC; die misst Uzai selbst.

const SU := preload("res://src/library/store_util.gd")

const FAMILY_RE := "^[A-Za-z0-9][A-Za-z0-9.\\-]{2,63}_[a-z0-9]{13}$"
const APP_RE := "^[A-Za-z][A-Za-z0-9.]{0,63}$"
const CONFIG := "MicrosoftGame.config"
const CONFIG_MAX := 256 * 1024
## Pakete der Xbox-App und von Windows, die selbst kein Spiel sind (falls sie je eine Spieldatei hätten).
const NOT_GAMES := ["Microsoft.GamingApp", "Microsoft.XboxApp", "Microsoft.GamingServices", "Microsoft.XboxIdentityProvider",
	"Microsoft.Xbox.TCUI", "Microsoft.XboxGameOverlay", "Microsoft.XboxGamingOverlay", "Microsoft.XboxSpeechToTextOverlay"]


## pkgs: Einträge des Helfers [{ family, name, dir, apps: [IDs], title }].
static func scan(pkgs: Array) -> Array:
	var out: Array = []
	var seen := {}
	for p in SU.entries(pkgs, 600):
		var g := entry(p, parse_config(SU.read_text(SU.norm_path(str(p.get("dir", ""))).path_join(CONFIG), CONFIG_MAX)))
		if g.is_empty() or seen.has(str(g.id)):
			continue
		seen[str(g.id)] = true
		out.append(g)
	return out


## Rein: ein Paket (Helfer) und seine MicrosoftGame.config → Spiel; {} wenn etwas nicht passt.
static func entry(p: Dictionary, cfg: Dictionary) -> Dictionary:
	var family := SU.id_ok(str(p.get("family", "")), FAMILY_RE)
	var name := str(p.get("name", ""))
	if family == "" or name in NOT_GAMES or family.get_slice("_", 0) in NOT_GAMES:
		return {}
	var dir := SU.game_dir(str(p.get("dir", "")))
	if dir == "":
		return {}
	var apps: Array = []
	var av: Variant = p.get("apps", [])
	for a in (av if av is Array else [av]).slice(0, 16):
		var id := SU.id_ok(str(a), APP_RE)
		if id != "":
			apps.append(id)
	# Die App, die in MicrosoftGame.config als Spiel steht; sonst die erste des Pakets.
	var app := ""
	for e in cfg.get("exes", []):
		if apps.has(str(e.id)):
			app = str(e.id)
			break
	if app == "" and not apps.is_empty():
		app = str(apps[0])
	if app == "":
		return {}
	var title := ""
	for t in [str(cfg.get("title", "")), str(p.get("title", ""))]:
		if not t.begins_with("ms-resource:"):
			title = SU.title(t)
			if title != "":
				break
	if title == "":
		title = title_from(name, dir)
	if title == "":
		return {}
	var g := {
		"id": "xboxpc:%s" % family,
		"title": title,
		"system": "xboxpc",
		"source": "xboxpc",
		"xboxpc": { "aumid": "%s!%s" % [family, app] },
		"install_dir": dir,
		"installed": true,
	}
	if FileAccess.file_exists(dir.path_join(CONFIG)):
		g["install_time"] = FileAccess.get_modified_time(dir.path_join(CONFIG))
	for e in cfg.get("exes", []):
		if str(e.id) == app and str(e.get("exe", "")) != "":
			var exe := SU.child(dir, str(e.exe))
			if exe != "" and exe.get_extension().to_lower() == "exe":
				g["path"] = exe
	return g


## Lesbarer Name ohne Angaben in der Datei: Ordner über „Content“ (C:\XboxGames\<Spiel>\Content),
## sonst der Paketname in Wörtern („Microsoft.MinecraftUWP“ → „Minecraft UWP“) – nie eine
## Kennung aus Ziffern und Buchstaben („Microsoft.624F8B84B80“).
static func title_from(name: String, dir: String) -> String:
	if dir.get_file().to_lower() == "content":
		var t := SU.title(dir.get_base_dir().get_file())
		if t != "":
			return t
	var n := name.get_slice(".", name.get_slice_count(".") - 1) if name.contains(".") else name
	var hexish := RegEx.create_from_string("^[0-9A-F]{6,}$").search(n) != null
	if n == "" or hexish or (RegEx.create_from_string("\\d{3,}").search(n) != null and n.to_upper() == n):
		return ""
	return SU.title(RegEx.create_from_string("(?<=[a-z])(?=[A-Z0-9])").sub(n, " ", true))


## Rein: MicrosoftGame.config → { title, exes: [{ id, exe }] }. Nur ShellVisuals/DefaultDisplayName
## und ExecutableList/Executable (Name, Id); alles andere bleibt unbeachtet.
static func parse_config(text: String) -> Dictionary:
	var out := { "title": "", "exes": [] }
	var xp := XMLParser.new()
	if text == "" or text.length() > CONFIG_MAX or xp.open_buffer(text.to_utf8_buffer()) != OK:
		return out
	var n := 0
	while xp.read() == OK and n < 5000:
		n += 1
		if xp.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match xp.get_node_name():
			"ShellVisuals":
				if out.title == "":
					out.title = xp.get_named_attribute_value_safe("DefaultDisplayName")
			"Executable":
				if (out.exes as Array).size() < 16:
					(out.exes as Array).append({ "id": xp.get_named_attribute_value_safe("Id"), "exe": xp.get_named_attribute_value_safe("Name") })
	return out


## Start wie im Startmenü; "" bei ungültiger Kennung.
static func launch_uri(g: Dictionary) -> String:
	var a := str(SU.sub(g, "xboxpc").get("aumid", ""))
	if a.get_slice_count("!") != 2 or SU.id_ok(a.get_slice("!", 0), FAMILY_RE) == "" or SU.id_ok(a.get_slice("!", 1), APP_RE) == "":
		return ""
	return "shell:AppsFolder\\" + a
