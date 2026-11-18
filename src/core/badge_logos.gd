extends Node
## Echte Konsolen-Logos (PlayStation, GameCube, Switch, Steam, Epic …) für die Spielzeit-Abzeichen
## und die Quellen-Zeile der Startseite (PS2, GameCube, Steam … über dem Regal), dazu die Zeichen der
## Emulatoren für die Szene Emulatoren der Einrichtung (einrichtung_inhalt.gd).
##
## Die Logos liegen NICHT im Repository und nicht im Build (Marken von Sony, Nintendo, Sega, Valve,
## Microsoft, Epic …, R4). Ist badges.real_logos an (Einstellungen → Spiele → Mehr → Bilder,
## „Echte Konsolen-Logos (aus dem Netz, privat)“; Standard: an), lädt Uzai sie zur Laufzeit für den
## privaten Gebrauch von Wikimedia Commons und legt sie im Datenordner unter cache/logos ab. Eigene
## Dateien gelten immer. Reihenfolge je Logo:
##   1. eigene Datei im Medienordner: <Medien>/logos/<name>.png|svg|webp|jpg – name ist die
##      Plattform-Gruppe des Abzeichens („16bit“, „handheld“) oder ein Logo-Schlüssel („ps2“,
##      „megadrive“, „epic“). Eigene Dateien gewinnen immer.
##   2. das zwischengespeicherte Logo (cache/logos/<schlüssel>.png) – nur wenn eingeschaltet
##   3. Download (nur wenn eingeschaltet): Commons-API (und als zweite Quelle die englische Wikipedia, deren Abfrage auch
##      Commons-Dateien kennt) mit allen bekannten Dateinamen auf einmal; die erste vorhandene
##      Datei wird als PNG-Render in WIDTH Punkten Breite geholt (SVG scharf gerastert, kleine
##      Rasterbilder kommen in Originalgröße – nie hochgezogen). Passt keiner der Namen (Datei
##      umbenannt), sucht Uzai einmal auf Commons nach „<Name> logo“ (nur SVG mit „logo“ im Namen).
##   4. sonst bleibt der Kurzname bzw. das Zeichen von bisher („PS2“, Handheld-Symbol).
## Was nicht gefunden wurde, merkt sich index.json und wird erst nach RETRY_DAYS wieder gesucht;
## ohne Netz wird beim nächsten Start neu versucht.
##
## Gruppen mit mehreren Systemen (8/16 Bit, Handhelds, PC) zeigen das Logo des Systems mit der
## meisten Spielzeit (Badges.facts.top_<gruppe>, z. B. Mega Drive statt SNES), sonst das der Gruppe.
## In der Quellen-Zeile steht das Logo einfarbig in der Farbe der Schrift (mono, gleiche Höhe).

const Fremd := preload("res://src/core/fremd.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

signal logo_ready(key: String)

const COMMONS_API := "https://commons.wikimedia.org/w/api.php?"
const ENWIKI_API := "https://en.wikipedia.org/w/api.php?"
const FILEPATH := "https://commons.wikimedia.org/wiki/Special:FilePath/"
## Breite des Renders. Wikimedia liefert Vorschaubilder nur noch in festen Stufen (…, 500, 960,
## 1280) zuverlässig aus; 960 reicht für die größte Medaille in 4K (≈ 190 Punkte Logo) mit Reserve.
const WIDTH := 960
const CACHE_DIR := "cache/logos"
const INDEX := "cache/logos/index.json"
const RETRY_DAYS := 14
const EXTS := ["png", "svg", "webp", "jpg", "jpeg"]
const MAX_SIDE := 640            ## vorbereitete Logos höchstens so groß (spart Rechenzeit)

## Logo-Schlüssel -> Name und Commons-Dateinamen in Wunschreihenfolge (die erste vorhandene zählt).
const LOGOS := {
	"ps1": { "name": "PlayStation", "files": ["PlayStation logo.svg", "Playstation logo colour.svg", "PlayStation logo (1994).svg"] },
	"ps2": { "name": "PlayStation 2", "files": ["PlayStation 2 logo.svg", "PS2 logo.svg", "Playstation 2 logo.svg", "PlayStation2 logo.svg"] },
	## Das PS-Zeichen allein, einfarbig (Rückfall für das farbige, src/room/regal_welt.gd).
	"ps_zeichen": { "name": "PlayStation", "files": ["PlayStation logo.svg", "Playstation logo.svg", "PlayStation logo colour.svg"] },
	## Das farbige PS-Zeichen (rot, gelb, grün, blau) wie auf PS1/PS2-Hüllen: rechts im Band der
	## PS2-Vorderseite und oben am Rücken (Regal). Bleibt farbig (line_logo mit bunt).
	"ps_logo_farbe": { "name": "PlayStation", "suche": "PlayStation logo colour", "noetig": ["playstation", "colo"],
		"files": ["Playstation logo colour.svg", "PlayStation logo colour.svg", "PlayStation logo (colour).svg", "PlayStation logo color.svg",
			"Playstation logo color.svg", "PlayStation 1 logo.svg"] },
	## Die Wortmarke „PlayStation®2“ wie im Band der PS2-Cover und am Rücken (nicht das stilisierte
	## „PS2“-Logo von ps2). Suche nur nach „wordmark“, sonst fände sie wieder das „PS2“-Logo.
	"ps2_wortmarke": { "name": "PlayStation 2", "suche": "PlayStation 2 wordmark", "noetig": ["playstation", "2", "wordmark"],
		"files": ["PlayStation 2 wordmark.svg", "Playstation 2 wordmark.svg", "PlayStation2 wordmark.svg", "PlayStation 2 (wordmark).svg",
			"PlayStation 2 text logo.svg", "PlayStation 2 logotype.svg"] },
	"psp": { "name": "PlayStation Portable", "files": ["PSP Logo.svg", "PlayStation Portable logo.svg", "PSP logo.svg"] },
	"gc": { "name": "GameCube",
		"files": ["Nintendo GameCube Logo.svg", "Nintendo GameCube logo.svg", "GameCube logo.svg", "Nintendo Gamecube logo.svg", "GCN Logo.svg"] },
	"wii": { "name": "Wii", "files": ["Wii.svg", "Wii logo.svg", "Wii Logo.svg"] },
	"wiiu": { "name": "Wii U", "files": ["WiiU.svg", "Wii U logo.svg", "Wii U Logo.svg"] },
	"n64": { "name": "Nintendo 64", "files": ["Nintendo 64 Logo.svg", "N64-logo.svg", "Nintendo 64 logo.svg", "N64 logo.svg"] },
	"snes": { "name": "Super Nintendo",
		"files": ["SNES logo.svg", "Super Nintendo Entertainment System logo.svg", "SNES Japan PAL Logo.svg", "Super Famicom logo.svg"] },
	"nes": { "name": "NES", "files": ["NES logo.svg", "Nintendo Entertainment System logo.svg", "NES Logo.svg"] },
	"megadrive": { "name": "Mega Drive", "files": ["Sega Mega Drive logo.svg", "Mega Drive logo.svg", "Sega Genesis logo.svg", "Sega genesis logo.svg"] },
	"mastersystem": { "name": "Master System", "files": ["Sega Master System logo.svg", "Master System logo.svg"] },
	"pce": { "name": "PC Engine", "files": ["PC Engine logo.svg", "TurboGrafx-16 logo.svg", "TurboGrafx16 logo.svg"] },
	"switch": { "name": "Nintendo Switch", "files": ["Nintendo Switch logo.svg", "Nintendo Switch Logo.svg", "Nintendo switch logo.svg"] },
	"gb": { "name": "Game Boy", "files": ["Game Boy logo.svg", "Gameboy logo.svg", "Nintendo Game Boy Logo.svg"] },
	"gbc": { "name": "Game Boy Color", "files": ["Game Boy Color logo.svg", "Nintendo Game Boy Color logo.svg", "Gameboy color logo.svg"] },
	"gba": { "name": "Game Boy Advance",
		"files": ["Game Boy Advance logo.svg", "Nintendo Game Boy Advance logo.svg", "Gameboy advance logo.svg", "GBA logo.svg"] },
	"nds": { "name": "Nintendo DS", "files": ["Nintendo DS Logo.svg", "Nintendo DS logo.svg", "NintendoDS logo.svg"] },
	"3ds": { "name": "Nintendo 3DS", "files": ["Nintendo 3DS logo.svg", "Nintendo 3DS Logo.svg", "Nintendo 3ds logo.svg"] },
	"gamegear": { "name": "Game Gear", "files": ["Game Gear logo.svg", "Sega Game Gear logo.svg", "Sega Game Gear Logo.svg"] },
	"atari2600": { "name": "Atari 2600", "files": ["Atari 2600 logo.svg", "Atari 2600 Logo.svg", "Atari2600 logo.svg"] },
	"steam": { "name": "Steam", "files": ["Steam icon logo.svg", "Steam 2016 logo black.svg", "Steam logo.svg"] },
	"discord": { "name": "Discord", "files": ["Discord icon.svg", "Discord logo.svg", "Discord-Logo-Color.svg"] },
	"windows": { "name": "Windows", "files": ["Windows logo - 2021.svg", "Windows logo - 2012.svg", "Windows 11 logo.svg"] },
	"ps3": { "name": "PlayStation 3", "files": ["PlayStation 3 logo (2009).svg", "PS3 logo.svg", "PlayStation 3 logo.svg", "Playstation 3 logo.svg"] },
	"ps4": { "name": "PlayStation 4", "files": ["PlayStation 4 logo and wordmark.svg", "PS4 logo.svg", "PlayStation 4 logo.svg"] },
	"ps5": { "name": "PlayStation 5", "files": ["PlayStation 5 logo and wordmark.svg", "PS5 logo.svg", "PlayStation 5 logo.svg"] },
	"vita": { "name": "PlayStation Vita", "files": ["PlayStation Vita logo.svg", "PS Vita logo.svg", "Playstation Vita logo.svg"] },
	"saturn": { "name": "Sega Saturn", "files": ["Sega Saturn logo.svg", "Sega Saturn Logo.svg", "SegaSaturn logo.svg", "Saturn logo.svg"] },
	"dreamcast": { "name": "Dreamcast", "files": ["Dreamcast logo.svg", "Sega Dreamcast logo.svg", "Dreamcast Logo.svg", "Dreamcast-Logo.svg"] },
	"xbox": { "name": "Xbox", "files": ["Xbox logo (2019).svg", "Xbox one logo.svg", "Xbox logo.svg", "XBOX logo 2012.svg"] },
	"xbox360": { "name": "Xbox 360", "files": ["Xbox 360 logo.svg", "Xbox 360 Logo.svg", "Xbox360 logo.svg"] },
	"epic": { "name": "Epic Games", "files": ["Epic Games logo.svg", "Epic games store logo.svg", "Epic Games Logo.svg"] },
	"gog": { "name": "GOG.com", "files": ["GOG.com logo.svg", "GOG Galaxy logo.svg", "Logo GOG.com.svg"] },
	"ea": { "name": "Electronic Arts", "files": ["Electronic Arts 2020.svg", "EA app logo.svg", "Electronic-Arts-Logo.svg", "Electronic Arts logo.svg"] },
	"ubisoft": { "name": "Ubisoft", "files": ["Ubisoft logo.svg", "Ubisoft 2017.svg", "Ubisoft Logo.svg"] },
	"battlenet": { "name": "Battle.net", "files": ["Battle.net 2021 icon.svg", "Battle.net logo.svg", "Blizzard Battle.net logo.svg"] },
	"itch": { "name": "itch.io", "files": ["Itch.io logo.svg", "Itch-io-logo.svg", "Itchio logo.svg"] },
	"amazon": { "name": "Amazon Games", "files": ["Amazon Games logo.svg", "Prime Gaming logo.svg", "Amazon logo.svg"] },
	"riot": { "name": "Riot Games", "files": ["Riot Games logo.svg", "Riot Games 2022.svg", "Riot Games Logo.svg"] },
	## Emulatoren (Einrichtung, Szene Emulatoren): „emu_“ + ID aus data/emulators.json.
	"emu_pcsx2": { "name": "PCSX2", "noetig": ["pcsx2"], "files": ["PCSX2 logo.svg", "PCSX2-logo.svg", "PCSX2 Logo.svg"] },
	"emu_duckstation": { "name": "DuckStation", "noetig": ["duckstation"], "files": ["DuckStation logo.svg", "DuckStation icon.svg"] },
	"emu_dolphin": { "name": "Dolphin", "suche": "Dolphin emulator logo", "noetig": ["dolphin", "emu"],
		"files": ["Dolphin Emulator Logo.svg", "Dolphin emulator logo.svg", "Dolphin-emu logo.svg"] },
	"emu_mgba": { "name": "mGBA", "noetig": ["mgba"], "files": ["MGBA logo.svg", "MGBA Logo.svg", "MGBA icon.svg"] },
	"emu_retroarch": { "name": "RetroArch", "noetig": ["retroarch"], "files": ["RetroArch logo.svg", "Retroarch logo.svg", "RetroArch Logo.svg"] },
	"emu_ppsspp": { "name": "PPSSPP", "noetig": ["ppsspp"], "files": ["PPSSPP logo.svg", "PPSSPP Logo.svg", "PPSSPP icon.svg"] },
	"emu_melonds": { "name": "melonDS", "noetig": ["melonds"], "files": ["MelonDS logo.svg", "MelonDS icon.svg"] },
	"emu_cemu": { "name": "Cemu", "suche": "Cemu emulator logo", "noetig": ["cemu"], "files": ["Cemu logo.svg", "Cemu Logo.svg", "Cemu icon.svg"] },
	"emu_rpcs3": { "name": "RPCS3", "noetig": ["rpcs3"], "files": ["RPCS3 logo.svg", "RPCS3 Logo.svg", "RPCS3 icon.svg"] },
	"emu_xemu": { "name": "xemu", "suche": "xemu emulator logo", "noetig": ["xemu"], "files": ["Xemu logo.svg", "Xemu icon.svg"] },
	"emu_flycast": { "name": "Flycast", "noetig": ["flycast"], "files": ["Flycast logo.svg", "Flycast icon.svg"] },
	"emu_snes9x": { "name": "Snes9x", "noetig": ["snes9x"], "files": ["Snes9x logo.svg", "Snes9x Logo.svg", "Snes9x icon.svg"] },
	"emu_project64": { "name": "Project64", "noetig": ["project64"], "files": ["Project64 logo.svg", "Project64 Logo.svg", "Project64 icon.svg"] },
	"emu_azahar": { "name": "Azahar", "suche": "Azahar emulator logo", "noetig": ["azahar"], "files": ["Azahar logo.svg", "Azahar icon.svg"] },
	"emu_ryubing": { "name": "Ryujinx", "noetig": ["ryujinx"], "files": ["Ryujinx logo.svg", "Ryujinx Logo.svg", "Ryujinx icon.svg"] },
}

## Quelle der Startseite (System oder Launcher) -> Logo-Schlüssel. Fehlt sie (Zuletzt, Favoriten,
## Ordner, Alle, Arcade …), steht dort der Name als Text.
const SOURCE_LOGO := {
	"ps1": "ps1", "ps2": "ps2", "ps3": "ps3", "ps4": "ps4", "ps5": "ps5", "psp": "psp", "vita": "vita", "psvita": "vita",
	"gc": "gc", "wii": "wii", "wiiu": "wiiu", "switch": "switch", "n64": "n64", "snes": "snes", "nes": "nes",
	"gb": "gb", "gbc": "gbc", "gba": "gba", "nds": "nds", "3ds": "3ds", "megadrive": "megadrive",
	"mastersystem": "mastersystem", "gamegear": "gamegear", "pce": "pce", "saturn": "saturn", "dreamcast": "dreamcast", "atari2600": "atari2600",
	"xbox": "xbox", "xbox360": "xbox360", "xboxpc": "xbox", "steam": "steam", "epic": "epic", "gog": "gog", "ea": "ea",
	"ubisoft": "ubisoft", "battlenet": "battlenet", "itch": "itch", "amazon": "amazon", "riot": "riot", "pc": "windows",
}

## System der Bibliothek -> Logo-Schlüssel (Epic/EA/eigene PC-Spiele: Windows).
const SYSTEM_LOGO := {
	"ps1": "ps1", "ps2": "ps2", "psp": "psp", "gc": "gc", "wii": "wii", "wiiu": "wiiu", "n64": "n64",
	"snes": "snes", "nes": "nes", "megadrive": "megadrive", "mastersystem": "mastersystem", "pce": "pce",
	"switch": "switch", "gb": "gb", "gbc": "gbc", "gba": "gba", "nds": "nds", "3ds": "3ds",
	"gamegear": "gamegear", "steam": "steam", "pc": "windows", "epic": "windows", "ea": "windows",
	"gog": "windows", "ubisoft": "windows", "battlenet": "windows", "xboxpc": "windows", "amazon": "windows", "itch": "windows", "riot": "windows",
}

## Plattform-Gruppe (badges_logic.PLATFORMS) -> Logo, wenn kein System heraussticht.
const GROUP_LOGO := {
	"ps1": "ps1", "ps2": "ps2", "gc": "gc", "wii": "wii", "n64": "n64", "16bit": "snes",
	"switch": "switch", "handheld": "gba", "steam": "steam", "pc": "windows",
}

const BadgesL := preload("res://src/core/badges_logic.gd")

static var net := true           ## Downloads erlaubt (Tests schalten ab)
static var media_dir_override := ""  ## Tests: eigener Medienordner
static var data_dir_override := ""   ## Tests: eigener Datenordner
static var _inst: Node
static var _images := {}         ## Logo-Schlüssel bzw. "o:<pfad>" -> vorbereitetes Image
static var _mono_voll := {}      ## vorbereitetes Image -> seine einfarbige Fassung in derselben Größe (für line_logo)
static var _tried := {}          ## in dieser Sitzung schon versucht (Schlüssel -> true)
static var _warm := false        ## aufwaermen() lief schon
const WARM_MAX := 80             ## höchstens so viele Dateien beim Start vorbereiten
var _busy := {}


# --- Zuordnung (rein) ----------------------------------------------------------------------

## Plattform-Gruppe eines Abzeichens („ps2“, „16bit“) aus need = "plat:<gruppe>"; sonst "".
static func group_of(d: Dictionary) -> String:
	var need := str(d.get("need", ""))
	if need.begins_with("plat:"):
		var g := need.substr(5)
		return g if GROUP_LOGO.has(g) else ""
	return ""


## Logo-Schlüssel in Wunschreihenfolge: System mit der meisten Spielzeit (wenn es zur Gruppe
## gehört und ein Logo hat), dann das Logo der Gruppe.
static func keys_for(d: Dictionary, top_system := "") -> Array:
	var g := group_of(d)
	if g == "":
		return []
	var out: Array = []
	if top_system != "" and SYSTEM_LOGO.has(top_system) and (BadgesL.PLATFORMS.get(g, []) as Array).has(top_system):
		out.append(str(SYSTEM_LOGO[top_system]))
	var gk := str(GROUP_LOGO[g])
	if not out.has(gk):
		out.append(gk)
	return out


## Namen, unter denen eigene Dateien im Medienordner gesucht werden: Gruppe, dann die Schlüssel.
static func override_names(d: Dictionary, top_system := "") -> Array:
	var g := group_of(d)
	if g == "":
		return []
	var out: Array = [g]
	for k in keys_for(d, top_system):
		if not out.has(k):
			out.append(k)
	return out


static func _data_path(rel: String) -> String:
	if data_dir_override != "":
		return data_dir_override.path_join(rel)
	var cfg := _config()
	if cfg:
		return str(cfg.call("path", rel))
	return ProjectSettings.globalize_path("user://").path_join(rel)


static func _media_dir() -> String:
	if media_dir_override != "":
		return media_dir_override
	var cfg := _config()
	return str(cfg.call("media_dir")) if cfg else ""


static func _config() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("/root/Config")
	return null


## Zwischengespeichertes Logo im Datenordner: cache/logos/<schlüssel>.png
static func cache_path(key: String) -> String:
	return _data_path(CACHE_DIR.path_join(key.validate_filename() + ".png"))


## Eigene Datei im Medienordner (<Medien>/logos/<name>.<ext>) oder "".
static func override_file(names: Array) -> String:
	var md := _media_dir()
	if md == "":
		return ""
	for n in names:
		for ext in EXTS:
			var p := md.path_join("logos").path_join("%s.%s" % [str(n), ext])
			if FileAccess.file_exists(p):
				return p
	return ""


## Woher das Logo eines Abzeichens kommt, ohne Netz: { path, key, source: "eigen"|"cache"|"" }.
## Leer: Kurzname/Zeichen zeigen (und, wenn erlaubt, herunterladen).
static func local_source(d: Dictionary, top_system := "") -> Dictionary:
	var keys := keys_for(d, top_system)
	if keys.is_empty():
		return { "path": "", "key": "", "source": "" }
	var ov := override_file(override_names(d, top_system))
	if ov != "":
		return { "path": ov, "key": "o:" + ov.get_file().get_basename(), "source": "eigen" }
	for k in keys:
		var cp := cache_path(str(k))
		if FileAccess.file_exists(cp):
			return { "path": cp, "key": str(k), "source": "cache" }
	return { "path": "", "key": "", "source": "" }


## Adresse der Abfrage: alle Dateinamen eines Logos auf einmal, Vorschaubild in WIDTH Punkten.
static func api_url(base: String, files: Array) -> String:
	var titles := PackedStringArray()
	for f in files:
		titles.append("File:" + str(f))
	return base + "action=query&format=json&formatversion=2&prop=imageinfo&iiprop=url%7Csize%7Cmime&iiurlwidth=" \
		+ str(WIDTH) + "&titles=" + "|".join(titles).uri_encode()


## Wie MediaWiki Titel schreibt: Unterstriche als Leerzeichen, erster Buchstabe groß.
static func normalize_title(t: String) -> String:
	var s := t.replace("_", " ").strip_edges()
	var colon := s.find(":")
	var ns := s.substr(0, colon + 1) if colon >= 0 else ""
	var rest := s.substr(colon + 1) if colon >= 0 else s
	if rest.length() > 0:
		rest = rest.substr(0, 1).to_upper() + rest.substr(1)
	return ns + rest


## Aus der API-Antwort die erste vorhandene Datei in Wunschreihenfolge: { url, title, width,
## height } – url ist das PNG-Vorschaubild (SVG gerastert; Rasterbilder unter WIDTH kommen im
## Original, nie größer). {} wenn keine da ist.
static func pick(data: Variant, files: Array) -> Dictionary:
	if not (data is Dictionary) or not (data as Dictionary).has("query"):
		return {}
	var q: Dictionary = data.query
	var by := {}
	var pages: Variant = q.get("pages", [])
	var plist: Array = []
	if pages is Dictionary:
		plist = (pages as Dictionary).values()
	elif pages is Array:
		plist = pages
	for p in plist:
		if not (p is Dictionary) or p.has("missing") or p.has("invalid"):
			continue
		var ii: Array = p.get("imageinfo", [])
		if ii.is_empty() or not (ii[0] is Dictionary):
			continue
		by[normalize_title(str(p.get("title", "")))] = ii[0]
	for f in files:
		var t := normalize_title("File:" + str(f))
		if not by.has(t):
			continue
		var info: Dictionary = by[t]
		var url := str(info.get("thumburl", ""))
		var w := int(info.get("thumbwidth", 0))
		var h := int(info.get("thumbheight", 0))
		var mime := str(info.get("mime", ""))
		# Rasterbild kleiner als WIDTH: Commons gibt das Original zurück – genau das wollen wir.
		if url == "" and mime in ["image/png", "image/jpeg", "image/webp"]:
			url = str(info.get("url", ""))
			w = int(info.get("width", 0))
			h = int(info.get("height", 0))
		if url == "":
			continue
		return { "url": url, "title": t, "width": w, "height": h }
	return {}


## Suche auf Commons, wenn keiner der bekannten Dateinamen (mehr) passt: Dateien zu „<Name> logo“.
static func search_url(name: String) -> String:
	return search_url_q(name + " logo")


## Suche mit eigenem Suchtext (LOGOS „suche“: die Wortmarke soll nicht das „PS2“-Logo finden).
static func search_url_q(q: String) -> String:
	return COMMONS_API + "action=query&format=json&formatversion=2&generator=search&gsrnamespace=6&gsrlimit=10&gsrsearch=" \
		+ q.uri_encode() + "&prop=imageinfo&iiprop=url%7Csize%7Cmime&iiurlwidth=" + str(WIDTH)


## Aus den Suchtreffern das beste Logo: nur SVG, „logo“ und alle Wörter des Namens im Dateinamen,
## in der Reihenfolge der Suche. noetig: statt dessen genau diese Wörter (LOGOS „noetig“ – die
## Wortmarke heißt „wordmark“, nicht „logo“). {} wenn keins passt.
static func pick_search(data: Variant, name: String, noetig: Array = []) -> Dictionary:
	if not (data is Dictionary) or not (data as Dictionary).has("query"):
		return {}
	var pages: Variant = (data.query as Dictionary).get("pages", [])
	var plist: Array = (pages as Dictionary).values() if pages is Dictionary else (pages if pages is Array else [])
	plist = plist.filter(func(p: Variant) -> bool: return p is Dictionary)
	plist.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("index", 0)) < int(b.get("index", 0)))
	var words := name.to_lower().replace(".", " ").split(" ", false)
	if not noetig.is_empty():
		words = PackedStringArray(noetig.map(func(w: Variant) -> String: return str(w).to_lower()))
	for p in plist:
		var t := str(p.get("title", ""))
		var low := t.to_lower()
		if (noetig.is_empty() and not low.contains("logo")) or not low.ends_with(".svg"):
			continue
		if not Array(words).all(func(w: String) -> bool: return low.contains(w)):
			continue
		var ii: Array = p.get("imageinfo", [])
		if ii.is_empty() or not (ii[0] is Dictionary) or str(ii[0].get("thumburl", "")) == "":
			continue
		return { "url": str(ii[0].thumburl), "title": t, "width": int(ii[0].get("thumbwidth", 0)), "height": int(ii[0].get("thumbheight", 0)) }
	return {}


## Rückfall ohne API: Special:FilePath mit Breite (leitet auf das Vorschaubild weiter).
static func filepath_url(file: String) -> String:
	return FILEPATH + file.replace(" ", "_").uri_encode() + "?width=" + str(WIDTH)


## Noch einmal suchen? Fehlschläge (Datei gibt es nicht) erst nach RETRY_DAYS; Netzfehler sofort
## beim nächsten Start (stehen nicht im Index).
static func should_try(entry: Variant, now: int) -> bool:
	if not (entry is Dictionary):
		return true
	if not bool(entry.get("miss", false)):
		return true
	return now - int(entry.get("at", 0)) >= RETRY_DAYS * 86400


# --- Bilder --------------------------------------------------------------------------------

## Bild aus Datei (PNG/JPG/WEBP nach Inhalt, SVG groß gerastert).
static func load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if path.get_extension().to_lower() == "svg":
		var text := FileAccess.get_file_as_string(path)
		err = img.load_svg_from_string(text, 1.0)
		if err == OK and maxi(img.get_width(), img.get_height()) > 0:
			var sc := float(WIDTH) / float(maxi(img.get_width(), img.get_height()))
			img = Image.new()
			err = img.load_svg_from_string(text, clampf(sc, 0.05, 64.0))
	else:
		var b := FileAccess.get_file_as_bytes(path)
		err = load_buffer(img, b)
	return img if err == OK and not img.is_empty() else null


static func load_buffer(img: Image, b: PackedByteArray) -> int:
	if b.size() < 12:
		return ERR_FILE_CORRUPT
	if b[0] == 0x89 and b[1] == 0x50:
		return img.load_png_from_buffer(b)
	if b[0] == 0xFF and b[1] == 0xD8:
		return img.load_jpg_from_buffer(b)
	if b[0] == 0x52 and b[1] == 0x49:
		return img.load_webp_from_buffer(b)
	return ERR_FILE_UNRECOGNIZED


## Für die Medaille vorbereiten: RGBA8, ein voller einfarbiger Hintergrund (eigene JPGs, Logos
## auf Weiß) wird durchsichtig, durchsichtige Ränder ab, höchstens MAX_SIDE groß.
static func prepare(src: Image) -> Image:
	if src == null or src.is_empty():
		return null
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var corners := [img.get_pixel(0, 0), img.get_pixel(w - 1, 0), img.get_pixel(0, h - 1), img.get_pixel(w - 1, h - 1)]
	var opaque := true
	for c in corners:
		if (c as Color).a < 0.9 or _dist(c, corners[0]) > 0.08:
			opaque = false
	if opaque:
		var bg: Color = corners[0]
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				c.a *= clampf((_dist(c, bg) - 0.04) / 0.22, 0.0, 1.0)
				img.set_pixel(x, y, c)
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	img = img.get_region(used)
	var big := maxi(img.get_width(), img.get_height())
	if big > MAX_SIDE:
		var k := float(MAX_SIDE) / float(big)
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	return img


static func _dist(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


## Größe des Logos in einem Feld, Seitenverhältnis bleibt, nie größer als das Bild selbst.
static func fit(src: Vector2i, box: Vector2) -> Vector2i:
	if src.x <= 0 or src.y <= 0:
		return Vector2i.ZERO
	var k := minf(minf(box.x / float(src.x), box.y / float(src.y)), 1.0)
	return Vector2i(maxi(1, floori(src.x * k)), maxi(1, floori(src.y * k)))


## Feld (im 100er Raster der Medaille) für ein Logo mit Seitenverhältnis aspect: breite
## Schriftzüge dürfen breiter, fast quadratische Zeichen bleiben kompakter.
static func box_for(aspect: float) -> Vector2:
	if aspect >= 2.4:
		return Vector2(54, 24)
	if aspect >= 1.4:
		return Vector2(48, 30)
	return Vector2(38, 36)


## Logo einfarbig in Metall: Fläche hell (oben) bis Metallton (unten), Helligkeit des Originals
## als leichte Prägung erhalten; gesperrt grau und gedämpft. Ergebnis: RGBA8 in size.
static func tinted(src: Image, size: Vector2i, top: Color, bottom: Color, alpha := 1.0) -> Image:
	var img := src.duplicate() as Image
	if img.get_width() != size.x or img.get_height() != size.y:
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var w := img.get_width()
	var h := img.get_height()
	var lo := 1.0
	var hi := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				var l := c.get_luminance()
				lo = minf(lo, l)
				hi = maxf(hi, l)
	var span := hi - lo
	for y in h:
		var g := top.lerp(bottom, float(y) / float(maxi(h - 1, 1)) * 0.75)
		for x in w:
			var c := img.get_pixel(x, y)
			var l := (c.get_luminance() - lo) / span if span > 0.2 else 1.0
			var k := 0.84 + 0.16 * clampf(l, 0.0, 1.0)
			img.set_pixel(x, y, Color(g.r * k, g.g * k, g.b * k, c.a * alpha))
	return img


## Einfarbige Fläche aus der Deckkraft eines Bilds (Schatten, Glanzkante).
static func silhouette(src: Image, col: Color) -> Image:
	var img := src.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, Color(col.r, col.g, col.b, img.get_pixel(x, y).a * col.a))
	return img


# --- Laden (mit Speicher) --------------------------------------------------------------------

## Vorbereitetes Logo eines Abzeichens, wenn es lokal da ist: { key, img } – sonst {} (und, wenn
## erlaubt, wird der Download angestoßen; logo_ready meldet, wenn er da ist).
static func image_for(d: Dictionary, top_system := "") -> Dictionary:
	if group_of(d) == "":
		return {}
	return _image(keys_for(d, top_system), override_names(d, top_system))


## Vorbereitetes Logo zu einem Logo-Schlüssel („ps2“, „epic“) – wie image_for, eigene Datei
## <Medien>/logos/<schlüssel> zuerst.
static func image_for_key(key: String) -> Dictionary:
	if not LOGOS.has(key):
		return {}
	return _image([key], [key])


static func _image(keys: Array, names: Array) -> Dictionary:
	var on := enabled()
	var src := { "path": "", "key": "", "source": "" }
	var ov := override_file(names)
	if ov != "":
		src = { "path": ov, "key": "o:" + ov.get_file().get_basename(), "source": "eigen" }
	elif on:
		# Geladene Logos (Cache) nur, solange das Laden eingeschaltet ist; eigene Dateien immer.
		for k in keys:
			var cp := cache_path(str(k))
			if FileAccess.file_exists(cp):
				src = { "path": cp, "key": str(k), "source": "cache" }
				break
	if str(src.key) != "":
		var k := str(src.key)
		var mk := k + "|" + str(src.path)
		if not _images.has(mk):
			_images[mk] = prepare(load_image(str(src.path)))
		if _images[mk] != null:
			return { "key": k, "img": _images[mk], "source": src.source }
	if net and on:
		var l := loader()
		if l:
			for k in keys:
				l.call_deferred("fetch", str(k))
	return {}


## Beim Start (Badges): alle Logos, die schon auf der Platte liegen, im Hilfsfaden vorbereiten – lesen,
## zuschneiden, einfarbige Fassung. Gemessen kostet das rund 50 ms je Logo (35 ms davon die einfarbige Fassung);
## vorher fiel es beim ersten Aufbau der Startseite im Hauptfaden an, bei acht Quellen 0,4 s gleich nach dem Start.
## Was bis zum ersten Gebrauch nicht fertig ist, entsteht dort wie bisher.
static func aufwaermen() -> void:
	if _warm:
		return
	_warm = true
	var liste := _vorhandene()
	if liste.is_empty():
		return
	_uebernehmen(await Arbeit.ergebnis(_vorbereiten.bind(liste)))


## Was auf der Platte liegt: [[Merkschlüssel wie in _image, Pfad], …] – eigene Dateien im Medienordner immer,
## geladene nur, solange das Laden eingeschaltet ist (wie _image). Nur Pfade; gelesen wird im Hilfsfaden.
static func _vorhandene() -> Array:
	var out: Array = []
	var eigene := {}
	var md := _media_dir()
	var ld := md.path_join("logos") if md != "" else ""
	if ld != "" and DirAccess.dir_exists_absolute(ld):
		for f in DirAccess.get_files_at(ld):
			if f.get_extension().to_lower() in EXTS and out.size() < WARM_MAX:
				eigene[f.get_basename()] = true
				out.append(["o:%s|%s" % [f.get_basename(), ld.path_join(f)], ld.path_join(f)])
	var cd := _data_path(CACHE_DIR)
	if enabled() and DirAccess.dir_exists_absolute(cd):
		for f in DirAccess.get_files_at(cd):
			var key := f.get_basename()
			if f.get_extension() == "png" and LOGOS.has(key) and not eigene.has(key) and out.size() < WARM_MAX:
				out.append(["%s|%s" % [key, cd.path_join(f)], cd.path_join(f)])
	return out


## Läuft im Hilfsfaden: rein, nur Dateien und eigene Bilder. [{ mk, img, mono }]
static func _vorbereiten(liste: Array) -> Array:
	var out: Array = []
	for e in liste:
		var img := prepare(load_image(str(e[1])))
		out.append({ "mk": str(e[0]), "img": img, "mono": mono(img) })
	return out


## Ergebnis des Hilfsfadens übernehmen. Was inzwischen im Hauptfaden entstanden ist, bleibt.
static func _uebernehmen(fertig: Variant) -> void:
	if not (fertig is Array):
		return
	for e in fertig:
		if e is Dictionary and e.get("img") is Image and not _images.has(str(e.mk)):
			_images[str(e.mk)] = e.img
			if e.get("mono") is Image:
				_mono_voll[e.img] = e.mono


## Logo-Schlüssel einer Quelle der Startseite ("" = Text).
static func source_key(sub_id: String) -> String:
	return str(SOURCE_LOGO.get(sub_id, ""))


## Einfarbig weißes Zeichen aus einem Logo (zum Einfärben mit modulate, wie Schrift): die Form
## aus der Deckkraft; fast weiße Innenflächen eines farbigen Logos (Switch, Steam) werden zu
## Löchern, damit es nicht als Klecks erscheint. Ein Logo, das selbst weiß ist, bleibt ganz.
static func mono(src: Image) -> Image:
	if src == null or src.is_empty():
		return null
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var solid := 0
	var light := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				solid += 1
				if _near_white(c):
					light += 1
	var holes := solid > 0 and light < solid * 0.6
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var a := c.a
			if holes and a > 0.0:
				# weich: je näher an Weiß, desto durchsichtiger (Kanten bleiben glatt)
				var m := minf(c.r, minf(c.g, c.b))
				a *= 1.0 - clampf((m - 0.72) / 0.2, 0.0, 1.0) * clampf(1.0 - (_dist(c, Color(m, m, m)) - 0.06) / 0.12, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


static func _near_white(c: Color) -> bool:
	return minf(c.r, minf(c.g, c.b)) > 0.82 and _dist(c, Color.WHITE) < 0.18


## Höhe (Punkte der Oberfläche) eines Logos in einer Zeile der Höhe h: breite Schriftzüge genau h,
## kompakte Zeichen etwas größer (wirken sonst kleiner); nie breiter als max_w.
static func line_size(aspect: float, h: float, max_w: float) -> Vector2:
	var hh := h * clampf(sqrt(3.2 / maxf(aspect, 0.2)), 1.0, 1.4)
	var ww := hh * aspect
	if ww > max_w:
		hh *= max_w / ww
		ww = max_w
	return Vector2(roundf(ww), roundf(hh))


static var _mono_tex := {}       ## "<key>|<px>" -> ImageTexture


## Logo einer Quelle als einfarbige Textur für eine Zeile der Höhe h (Punkte) – gerastert mit
## Reserve für 4K (Oberfläche ×2) und Mipmaps (scharf auch verkleinert). { tex, size, bunt } oder {}.
## bunt: das Logo in seinen eigenen Farben (das farbige PS-Zeichen) – nur, wenn das geladene Bild
## wirklich farbig ist (ist_bunt); sonst einfarbig weiß wie immer (ein schwarzes Zeichen verschwände
## sonst im schwarzen Band). Die Textur trägt dann uz_bunt.
static func line_logo(key: String, h: float, max_w: float, bunt := false) -> Dictionary:
	var got := image_for_key(key)
	if got.is_empty():
		return {}
	var img: Image = got.img
	var aspect := float(img.get_width()) / float(maxi(img.get_height(), 1))
	var sz := line_size(aspect, h, max_w)
	var px := int(ceilf(sz.y * 2.5))
	var farbig := bunt and ist_bunt(img)
	var mk := "%s|%d%s" % [str(got.key), px, "|b" if farbig else ""]
	if not _mono_tex.has(mk):
		var m: Image
		if farbig:
			m = img.duplicate() as Image
		else:
			# Die einfarbige Fassung je Logo nur einmal rechnen (mehrere Zeilenhöhen teilen sie sich; beim Start
			# kommt sie schon aus aufwaermen()).
			if not (_mono_voll.get(img) is Image):
				_mono_voll[img] = mono(img)
			m = (_mono_voll[img] as Image).duplicate() as Image if _mono_voll[img] is Image else null
		if m == null:
			return {}
		if farbig:
			m.convert(Image.FORMAT_RGBA8)
		if m.get_height() > px:
			m.resize(maxi(1, roundi(px * aspect)), px, Image.INTERPOLATE_LANCZOS)
		m.generate_mipmaps()
		var tex := ImageTexture.create_from_image(m)
		tex.set_meta("uz_logo", str(got.key))
		if farbig:
			tex.set_meta("uz_bunt", true)
		_mono_tex[mk] = tex
	return { "tex": _mono_tex[mk], "size": sz, "key": str(got.key), "bunt": farbig }


## Ist ein Logo farbig (nicht nur schwarz, weiß oder grau)? Wenigstens ein Fünftel der deckenden
## Punkte kräftig gesättigt.
static func ist_bunt(img: Image) -> bool:
	if img == null or img.is_empty():
		return false
	var w := img.get_width()
	var h := img.get_height()
	var sx := maxi(1, w / 64)
	var sy := maxi(1, h / 64)
	var deckend := 0
	var satt := 0
	for y in range(0, h, sy):
		for x in range(0, w, sx):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				deckend += 1
				if c.s > 0.4 and c.v > 0.25:
					satt += 1
	return deckend > 0 and satt >= deckend * 0.2


## Logos von Wikimedia laden und zeigen? Standard an, abschaltbar: Es sind Marken der Hersteller,
## Uzai bringt sie nicht mit (R4) – sie kommen nur zur Laufzeit, privat, in den eigenen Cache.
static func enabled() -> bool:
	var cfg := _config()
	return cfg != null and bool(cfg.call("get_value", "badges.real_logos", true))


## Der Lader hängt sich einmal unter die Wurzel (für Netz und Signal).
static func loader() -> Node:
	if is_instance_valid(_inst):
		return _inst
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return null
	_inst = load("res://src/core/badge_logos.gd").new()
	_inst.name = "BadgeLogos"
	(ml as SceneTree).root.call_deferred("add_child", _inst)
	return _inst


## Ein Logo holen (einmal je Sitzung, Fehlschläge mit Pause).
func fetch(key: String) -> void:
	if _busy.has(key) or _tried.has(key) or not LOGOS.has(key) or not net:
		return
	if FileAccess.file_exists(cache_path(key)):
		return
	var index_file := _data_path(INDEX)
	var index: Dictionary = _read_index(index_file)
	var now := int(Time.get_unix_time_from_system())
	if not should_try(index.get(key), now):
		_tried[key] = true
		return
	var net_node := get_node_or_null("/root/Net")
	if net_node == null:
		return
	_busy[key] = true
	_tried[key] = true
	var files: Array = LOGOS[key].files
	var found := {}
	var answered := false
	for base in [COMMONS_API, ENWIKI_API]:
		var r: Dictionary = await net_node.call("get_json", api_url(str(base), files))
		if bool(r.get("ok", false)):
			answered = true
			found = pick(r.data, files)
			if not found.is_empty():
				break
	if found.is_empty() and answered:
		var e: Dictionary = LOGOS[key]
		var q := str(e.get("suche", str(e.name) + " logo"))
		var rs: Dictionary = await net_node.call("get_json", search_url_q(q))
		if bool(rs.get("ok", false)):
			found = pick_search(rs.data, str(e.name), e.get("noetig", []))
	var got := ""
	var dest := cache_path(key)
	if not found.is_empty():
		got = str(await net_node.call("download", str(found.url), dest))
	elif not answered:
		# API nicht erreichbar (Filter, Proxy): direkt über Special:FilePath versuchen.
		for f in files:
			got = str(await net_node.call("download", filepath_url(str(f)), dest))
			if got != "":
				found = { "title": "File:" + str(f), "url": filepath_url(str(f)) }
				break
	_busy.erase(key)
	# Das neue Logo gleich im Hilfsfaden vorbereiten (und damit prüfen): Wer auf logo_ready hin danach fragt,
	# bekommt es fertig, statt es im Hauptfaden zu lesen und zuzuschneiden.
	var bereit: Variant = await Arbeit.ergebnis(_vorbereiten.bind([["%s|%s" % [key, got], got]])) if got != "" else null
	if bereit is Array and not (bereit as Array).is_empty() and bereit[0].get("img") is Image:
		_uebernehmen(bereit)
		index[key] = { "file": str(found.get("title", "")), "url": str(found.get("url", "")), "at": now }
		_write_index(index_file, index)
		logo_ready.emit(key)
	else:
		if got != "":
			DirAccess.remove_absolute(got)
		if answered:
			index[key] = { "miss": true, "at": now }
			_write_index(index_file, index)


static func _read_index(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var v: Variant = Fremd.json_roh(FileAccess.get_file_as_string(p))
	return v if v is Dictionary else {}


static func _write_index(p: String, v: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(v, "\t"))
		f.close()


## Tests und neues Laden nach Änderung im Medienordner.
static func forget() -> void:
	_images.clear()
	_mono_voll.clear()
	_tried.clear()
	_mono_tex.clear()
