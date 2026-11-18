extends RefCounted
## Die Launcher als Quellen der Bibliothek an einem Ort (Punkt 6): Namen, eigene neutrale Symbole
## (nie Logos der Anbieter), Farben der Ersatzhülle, das Einlesen der weiteren Launcher (GOG,
## Ubisoft Connect, Battle.net, Xbox-App, Amazon Games, itch.io, Riot Client), ihr Startweg und das
## Zusammenführen doppelter Spiele (dasselbe Spiel in mehreren Launchern → ein Eintrag, gestartet
## über den gewählten Launcher).

const SU := preload("res://src/library/store_util.gd")
const Gog := preload("res://src/library/gog_scanner.gd")
const Ubisoft := preload("res://src/library/ubisoft_scanner.gd")
const BattleNet := preload("res://src/library/battlenet_scanner.gd")
const Xbox := preload("res://src/library/xbox_scanner.gd")
const Amazon := preload("res://src/library/amazon_scanner.gd")
const Itch := preload("res://src/library/itch_scanner.gd")
const Riot := preload("res://src/library/riot_scanner.gd")

## Die weiteren Launcher in fester Reihenfolge (Reiter, Einstellungen, Einrichtung, Doktor).
const EXTRA := ["gog", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot"]
## Alle Quellen mit eigenem Launcher.
const STORES := ["steam", "epic", "ea", "gog", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot"]
## Wer bei Doppelten vorn steht (Bilder, Erfolge und Freunde gibt es vor allem bei Steam).
const PRIORITY := ["steam", "gog", "epic", "ea", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot", "pc"]
## name: ausgeschrieben, short: Pille und Reiter, app: das Programm (für „… fehlt“), color: Ersatzhülle.
const INFO := {
	"steam": { "name": "Steam", "short": "Steam", "icon": "steam", "color": "#1b2838" },
	"epic": { "name": "Epic Games", "short": "Epic", "icon": "games", "color": "#202226" },
	"ea": { "name": "EA app", "short": "EA", "icon": "games", "color": "#3a1d24" },
	"gog": { "name": "GOG", "short": "GOG", "icon": "store_gog", "color": "#2a2238", "app": "GOG Galaxy" },
	"ubisoft": { "name": "Ubisoft Connect", "short": "Ubisoft", "icon": "store_ubisoft", "color": "#16263a" },
	"battlenet": { "name": "Battle.net", "short": "Battle.net", "icon": "store_battlenet", "color": "#132232" },
	"xboxpc": { "name": "Xbox-App", "short": "Xbox", "icon": "store_xbox", "color": "#1a2c1e" },
	"amazon": { "name": "Amazon Games", "short": "Amazon", "icon": "store_amazon", "color": "#2c2618" },
	"itch": { "name": "itch.io", "short": "itch", "icon": "store_itch", "color": "#33201f" },
	"riot": { "name": "Riot Client", "short": "Riot", "icon": "store_riot", "color": "#331a1c" },
	"pc": { "name": "PC", "short": "PC", "icon": "desktop", "color": "#2b2d33" },
}


static func is_extra(id: String) -> bool:
	return id in EXTRA


static func name_of(id: String, short := false) -> String:
	var i: Dictionary = INFO.get(id, {})
	return str(i.get("short" if short else "name", ""))


static func icon_of(id: String) -> String:
	return str((INFO.get(id, {}) as Dictionary).get("icon", "games"))


static func color_of(id: String) -> String:
	return str((INFO.get(id, {}) as Dictionary).get("color", "#2b2d33"))


## Ist die Quelle eingeschaltet? (Einstellungen → Spiele → Quellen; Steam, Epic und EA wie bisher.)
static func enabled(id: String) -> bool:
	return bool(Config.get_value("library.%s_enabled" % id, true))


# --- Einlesen (im Hilfsthread) --------------------------------------------------------------

## Alle Spiele der eingeschalteten weiteren Launcher. ctx: { reg (Ergebnis von „store-games“),
## xbox (Ergebnis von „xbox-games“), pd (ProgramData), local (LOCALAPPDATA), appdata (APPDATA),
## on: { id: true/false }, skip: Ordner, die Steam, Epic oder EA schon zeigen }.
static func scan_extra(ctx: Dictionary) -> Array:
	var on: Dictionary = ctx.get("on", {})
	var reg: Dictionary = ctx.get("reg", {}) if ctx.get("reg") is Dictionary else {}
	var pd := str(ctx.get("pd", ""))
	var local := str(ctx.get("local", ""))
	var appdata := str(ctx.get("appdata", ""))
	var uninstall: Array = SU.entries(reg.get("uninstall", []), 4000)
	var out: Array = []
	if bool(on.get("gog", true)):
		out.append_array(Gog.scan(SU.entries(reg.get("gog", []), 2000), pd.path_join(Gog.DB_SUB) if pd != "" else "", ctx.get("gog_roots", Gog.DEFAULT_ROOTS)))
	if bool(on.get("ubisoft", true)):
		out.append_array(Ubisoft.scan(SU.entries(reg.get("ubisoft", []), 1000), Ubisoft.names_of(uninstall), ctx.get("skip", [])))
	if bool(on.get("battlenet", true)) and pd != "":
		var names := {}
		for u in uninstall:
			if str(u.get("publisher", "")).begins_with("Blizzard") and str(u.get("dir", "")) != "":
				names[SU.norm_path(str(u.dir)).to_lower()] = str(u.get("name", ""))
		var last := BattleNet.parse_config(SU.read_text(appdata.path_join(BattleNet.CONFIG_SUB), 2 * 1024 * 1024)) if appdata != "" else {}
		out.append_array(BattleNet.scan(SU.read_bytes(pd.path_join(BattleNet.DB_SUB), BattleNet.DB_MAX), names, last))
	if bool(on.get("xboxpc", true)):
		var xb: Variant = ctx.get("xbox", {})
		out.append_array(Xbox.scan(SU.entries((xb as Dictionary).get("games", []) if xb is Dictionary else [], 600)))
	if bool(on.get("amazon", true)):
		out.append_array(Amazon.scan(local.path_join(Amazon.DB_SUB) if local != "" else "", uninstall))
	if bool(on.get("itch", true)) and appdata != "":
		out.append_array(Itch.scan(appdata.path_join(Itch.DB_SUB)))
	if bool(on.get("riot", true)) and pd != "":
		out.append_array(Riot.scan(pd.path_join(Riot.BASE_SUB)))
	# Was Steam, Epic oder EA schon zeigen (dasselbe Spiel, derselbe Ordner), nicht noch einmal.
	var skip := {}
	for s in ctx.get("skip", []):
		skip[str(s).replace("\\", "/").trim_suffix("/").to_lower()] = true
	return out.filter(func(g: Dictionary) -> bool: return not skip.has(str(g.get("install_dir", "")).to_lower()))


## Programme der Launcher, über die Uzai startet: { galaxy, battlenet, riot } (Pfade oder "").
static func clients(ctx: Dictionary) -> Dictionary:
	var reg: Dictionary = ctx.get("reg", {}) if ctx.get("reg") is Dictionary else {}
	var out := { "galaxy": "", "battlenet": "", "riot": "" }
	var gx := SU.norm_path(str(reg.get("galaxy", "")))
	if gx != "":
		gx = gx if gx.get_extension().to_lower() == "exe" else gx.path_join("GalaxyClient.exe")
		if SU.exe_ok(gx) and gx.get_file().to_lower() == "galaxyclient.exe":
			out.galaxy = gx
	out.battlenet = BattleNet.client_exe(str(reg.get("bnet_dir", "")))
	var pd := str(ctx.get("pd", ""))
	if pd != "":
		out.riot = Riot.client_exe(pd.path_join(Riot.BASE_SUB))
	return out


## Welche weiteren Launcher es auf diesem PC gibt: { id: true/false }. Nur unter Windows sinnvoll.
static func presence(ctx: Dictionary, cl: Dictionary) -> Dictionary:
	var reg: Dictionary = ctx.get("reg", {}) if ctx.get("reg") is Dictionary else {}
	var protos: Dictionary = reg.get("protos", {}) if reg.get("protos") is Dictionary else {}
	var pd := str(ctx.get("pd", ""))
	var local := str(ctx.get("local", ""))
	var appdata := str(ctx.get("appdata", ""))
	var xb: Variant = ctx.get("xbox", {})
	return {
		"gog": str(cl.get("galaxy", "")) != "" or (pd != "" and DirAccess.dir_exists_absolute(pd.path_join("GOG.com/Galaxy"))),
		"ubisoft": bool(protos.get("uplay", false)),
		"battlenet": str(cl.get("battlenet", "")) != "",
		"xboxpc": bool((xb as Dictionary).get("app", false)) if xb is Dictionary else false,
		"amazon": bool(protos.get("amazon-games", false)) or (local != "" and DirAccess.dir_exists_absolute(local.path_join("Amazon Games/App"))),
		"itch": (local != "" and DirAccess.dir_exists_absolute(local.path_join("itch")))
			or (appdata != "" and DirAccess.dir_exists_absolute(appdata.path_join("itch"))),
		"riot": str(cl.get("riot", "")) != "",
	}


# --- Starten ---------------------------------------------------------------------------------

## Braucht das Spiel seinen Launcher zum Starten? GOG- und itch.io-Spiele mit Programmdatei starten
## auch ohne (kein Kopierschutz) – dann bietet Uzai Galaxy bzw. die itch-App nicht als „fehlt“ an.
static func needs_client(g: Dictionary) -> bool:
	if str(g.get("source", "")) in ["gog", "itch"]:
		return str(g.get("path", "")) == ""
	return true

## Startweg eines Spiels der weiteren Launcher: { uri } (Link des Launchers) oder { exe, args, dir }
## (Programm des Launchers bzw. die Programmdatei des Spiels). {} = so nicht startbar (why sagt warum).
## cl: Programme aus clients(); galaxy_on: GOG-Spiele über Galaxy starten.
static func launch_plan(g: Dictionary, cl: Dictionary, galaxy_on := true) -> Dictionary:
	match str(g.get("source", "")):
		"gog":
			var p := Gog.launch_plan(g, str(cl.get("galaxy", "")) if galaxy_on else "")
			return p if not p.is_empty() else { "why": "Die Programmdatei des Spiels fehlt, und GOG Galaxy ist nicht da." }
		"ubisoft":
			var u := Ubisoft.launch_uri(g)
			return { "uri": u } if u != "" else {}
		"battlenet":
			var b := BattleNet.launch_plan(g, str(cl.get("battlenet", "")))
			return b if not b.is_empty() else { "why": "Battle.net wurde auf diesem PC nicht gefunden." }
		"xboxpc":
			var x := Xbox.launch_uri(g)
			return { "uri": x } if x != "" else {}
		"amazon":
			var a := Amazon.launch_uri(g)
			return { "uri": a } if a != "" else {}
		"itch":
			var i := Itch.launch_plan(g)
			return i if not i.is_empty() else { "why": "Die itch-App hat für dieses Spiel keine Programmdatei erkannt." }
		"riot":
			var r := Riot.launch_plan(g, str(cl.get("riot", "")))
			return r if not r.is_empty() else { "why": "Der Riot Client wurde auf diesem PC nicht gefunden." }
	return {}


# --- Doppelte ---------------------------------------------------------------------------------

## Schlüssel, unter dem gleiche Spiele zusammenfinden: Titel ohne Groß/klein, Satzzeichen und
## Markenzeichen. "" für alles, was nicht zusammengeführt wird (nicht installiert, fehlt, Emulator,
## von Hand hinzugefügt, ausgeschaltete Quelle).
static func dupe_key(g: Dictionary, on: Dictionary = {}) -> String:
	var src := str(g.get("source", ""))
	if not (src in PRIORITY) or not bool(g.get("installed", true)) or bool(g.get("missing", false)):
		return ""
	if src == "pc" and not bool(g.get("scanned", false)):
		return ""
	if not bool(on.get(src, true)):
		return ""
	var t := SU.title(str(g.get("title", ""))).to_lower()
	var k := ""
	for ch in t:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch.unicode_at(0) > 0xbf:
			k += ch
	return k if k.length() >= 2 else ""


## Rein: doppelte Spiele verknüpfen. Je Gruppe bleibt eins vorn (Reihenfolge PRIORITY), die anderen
## bekommen dupe_of (ausgeblendet), das vordere alts (ihre IDs). Zwei Einträge derselben Quelle
## bleiben getrennt. on: eingeschaltete Quellen. Gibt die Zahl der ausgeblendeten zurück.
static func link_dupes(games: Array, on: Dictionary = {}) -> int:
	var groups := {}
	for g in games:
		if not (g is Dictionary):
			continue
		g.erase("dupe_of")
		g.erase("alts")
		var k := dupe_key(g, on)
		if k != "":
			if not groups.has(k):
				groups[k] = []
			(groups[k] as Array).append(g)
	var n := 0
	for k in groups:
		var list: Array = groups[k]
		if list.size() < 2:
			continue
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa := PRIORITY.find(str(a.get("source", "")))
			var pb := PRIORITY.find(str(b.get("source", "")))
			return pa < pb if pa != pb else str(a.get("id", "")) < str(b.get("id", "")))
		var head: Dictionary = list[0]
		var alts: Array = []
		var used := { str(head.get("source", "")): true }
		for g in list.slice(1):
			var s := str(g.get("source", ""))
			if used.has(s):
				continue
			used[s] = true
			g["dupe_of"] = str(head.get("id", ""))
			alts.append(str(g.get("id", "")))
			n += 1
		if not alts.is_empty():
			head["alts"] = alts
	return n
