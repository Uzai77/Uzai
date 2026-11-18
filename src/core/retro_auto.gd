extends RefCounted
## Retro ohne Einrichtung (Roadmap 19, 104, R5) – die Regeln, ohne Oberfläche und ohne Netz:
## welche Systeme da sind und welcher Emulator fehlt, welche Emulatoren Uzai anbieten darf (nur
## feste, offizielle Quellen), wie Release-Daten von GitHub geprüft werden, welche Namen ein Archiv
## enthalten darf, BIOS-Hinweise und die Grundeinstellungen je Emulator. Laden, Prüfen, Entpacken und
## Eintragen: src/core/retro_laden.gd. Getestet in tests/logic_retroauto.gd und tests/net_retroauto.gd.
##
## Grenzen (R5): Uzai lädt nie BIOS, Firmware, Schlüssel oder Spiele und nennt keine Quellen dafür.
## Für Switch richtet Uzai nichts automatisch ein. Kein Installer, keine Adminrechte, alles liegt in
## Uzais eigenem Ordner „emulatoren“; gestartet wird ein Emulator erst mit einem Spiel.
##
## Prüfsummen: GitHub nennt zu jedem Release-Paket eine SHA-256 („digest“) – ohne sie lädt Uzai
## nichts. RetroArch (Buildbot) und Dolphin (eigener Server) veröffentlichen keine; für sie steht die
## SHA-256 der angebotenen Fassung fest in KATALOG (übernommen aus den Scoop-Manifesten, vor jeder
## Uzai-Veröffentlichung gegen die offizielle Datei prüfen). Kerne vom Buildbot ändern sich täglich;
## der Buildbot nennt je Kern nur eine CRC32 (.index-extended) – sie schützt vor kaputten Downloads,
## gegen Fälschung hilft dort nur https zum festen Server (docs/SECURITY.md).

const Doktor := preload("res://src/core/doktor.gd")
const Zip := preload("res://src/core/zip_pruefung.gd")
const Fremd := preload("res://src/core/fremd.gd")

## Hosts, die Uzai hierfür überhaupt anspricht. Weiterleitungen nur zu den Hosts, die bei der
## jeweiligen Quelle stehen (GitHub schickt Release-Pakete über seinen Dateiserver).
const HOSTS := ["api.github.com", "github.com", "buildbot.libretro.com", "dl.dolphin-emu.org", "dolphin-emu.org"]
const WEITER := {
	"github.com": ["objects.githubusercontent.com", "release-assets.githubusercontent.com"],
}
const GITHUB_API := "https://api.github.com/repos/%s/releases/latest"
const KERN_BASIS := "https://buildbot.libretro.com/nightly/windows/x86_64/latest/"
const KERN_INDEX := KERN_BASIS + ".index-extended"

## Grenzen für fremde Daten und Archive.
const MAX_RELEASE := 2 * 1024 * 1024       ## Antwort der GitHub-API
const MAX_INDEX := 1024 * 1024              ## Kern-Liste des Buildbots
const MAX_KERN := 96 * 1024 * 1024          ## ein Kern-Paket
const MAX_ARCHIV := 400 * 1024 * 1024       ## ein Emulator-Paket
const MAX_EINTRAEGE := 20000
const MAX_GESAMT := 1536 * 1024 * 1024      ## entpackt
const MAX_RATE := 1100                      ## entpackt höchstens so viel mal größer (Deflate schafft ~1032)
const MB := 1024 * 1024

## Was Uzai anbietet. quelle "github": neueste Fassung aus dem Release des Repositorys, Paketname
## nach festem Muster, SHA-256 von GitHub. quelle "fest": genau diese Fassung und Prüfsumme.
## exe: Programmdatei im Paket (im Paket ganz oben oder in einem Ordner darunter). bios: System →
## Unterordner, in den das BIOS der eigenen Konsole gehört.
const KATALOG := {
	"retroarch": {
		"name": "RetroArch", "quelle": "fest", "version": "1.22.2",
		"url": "https://buildbot.libretro.com/stable/1.22.2/windows/x86_64/RetroArch.7z",
		"sha256": "b2139b1d0f9d4526dc6b5ce23cbb3efdc766096fa6f2c3df016818b486ac6372",
		"neu": "https://api.github.com/repos/libretro/RetroArch/releases/latest", "neu_art": "github",
		"web": "buildbot.libretro.com", "archiv": "7z", "exe": ["retroarch.exe"], "lizenz": "GPL-3.0",
		"max_mb": 400, "systeme": [],
		"bios": { "saturn": "system", "pce": "system", "dreamcast": "system/dc" },
	},
	"duckstation": {
		"name": "DuckStation", "quelle": "github", "repo": "stenzek/duckstation",
		"muster": "^duckstation-windows-x64-release\\.zip$", "web": "github.com/stenzek/duckstation",
		"archiv": "zip", "exe": ["duckstation-qt-x64-ReleaseLTCG.exe"], "lizenz": "CC-BY-NC-ND-4.0",
		"min_mb": 10, "max_mb": 250, "systeme": ["ps1"], "bios": { "ps1": "bios" },
	},
	"pcsx2": {
		"name": "PCSX2", "quelle": "github", "repo": "PCSX2/pcsx2",
		"muster": "^pcsx2-v[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,4}-windows-x64-Qt\\.7z$", "web": "github.com/PCSX2/pcsx2",
		"archiv": "7z", "exe": ["pcsx2-qt.exe"], "lizenz": "GPL-3.0",
		"min_mb": 8, "max_mb": 200, "systeme": ["ps2"], "bios": { "ps2": "bios" },
	},
	"ppsspp": {
		"name": "PPSSPP", "quelle": "github", "repo": "hrydgard/ppsspp",
		"muster": "^PPSSPP-v[0-9]{1,3}\\.[0-9]{1,3}(\\.[0-9]{1,4})?-Windows-x64\\.zip$", "web": "github.com/hrydgard/ppsspp",
		"archiv": "zip", "exe": ["PPSSPPWindows64.exe"], "lizenz": "GPL-2.0",
		"min_mb": 5, "max_mb": 200, "systeme": ["psp"], "bios": {},
	},
	"dolphin": {
		"name": "Dolphin", "quelle": "fest", "version": "2609a",
		"url": "https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a-x64.7z",
		"sha256": "bbfd13bf9e6d2a4164a15c392b1f32a9b18150e5136746b388704608fbb60f76",
		"neu": "https://dolphin-emu.org/update/latest/beta", "neu_art": "dolphin",
		"web": "dl.dolphin-emu.org", "archiv": "7z", "exe": ["Dolphin.exe"], "lizenz": "GPL-2.0",
		"max_mb": 250, "systeme": ["gc", "wii"], "bios": {},
	},
	"melonds": {
		"name": "melonDS", "quelle": "github", "repo": "melonDS-emu/melonDS",
		"muster": "^melonDS-[0-9]{1,3}\\.[0-9]{1,3}(\\.[0-9]{1,4})?-windows-x86_64\\.zip$", "web": "github.com/melonDS-emu/melonDS",
		"archiv": "zip", "exe": ["melonDS.exe"], "lizenz": "GPL-3.0",
		"min_mb": 3, "max_mb": 120, "systeme": ["nds"], "bios": {},
	},
}

## RetroArch-Kerne je System – nur Kerne mit freier Lizenz, deren Text Uzai mitliefert. Für
## Spielhalle gibt es keinen solchen Kern, der passt (FinalBurn Neo und MAME-Fassungen haben eigene,
## nicht freie Lizenzen oder brauchen genau passende Sätze): dort bleibt es beim Selbst-Einrichten.
const KERNE := {
	"nes": "mesen", "snes": "bsnes", "n64": "mupen64plus_next", "megadrive": "clownmdemu",
	"mastersystem": "gearsystem", "gamegear": "gearsystem", "gb": "mgba", "gbc": "mgba", "gba": "mgba",
	"pce": "mednafen_pce", "saturn": "mednafen_saturn", "atari2600": "stella", "dreamcast": "flycast",
}
## Name und Lizenz je erlaubtem Kern.
const KERN_INFO := {
	"mesen": ["Mesen", "GPL-3.0"], "bsnes": ["bsnes", "GPL-3.0"], "mupen64plus_next": ["Mupen64Plus-Next", "GPL-2.0"],
	"clownmdemu": ["ClownMDEmu", "AGPL-3.0"], "gearsystem": ["Gearsystem", "GPL-3.0"], "mgba": ["mGBA", "MPL-2.0"],
	"mednafen_pce": ["Beetle PCE", "GPL-2.0"], "mednafen_saturn": ["Beetle Saturn", "GPL-2.0"],
	"stella": ["Stella", "GPL-2.0"], "flycast": ["Flycast", "GPL-2.0"],
}
## Ohne Ausnahme nie automatisch (R5: braucht Schlüssel und Firmware der Konsole).
const NIE := ["switch"]

## Wofür das BIOS gebraucht wird: System → [Satz, nur für einen Teil der Spiele].
const BIOS_INFO := {
	"ps1": ["braucht das BIOS deiner eigenen PlayStation", false],
	"ps2": ["braucht das BIOS deiner eigenen PlayStation 2", false],
	"saturn": ["braucht das BIOS deines eigenen Saturn", false],
	"pce": ["braucht für CD-Spiele die System-Card deiner eigenen PC Engine", true],
	"dreamcast": ["läuft meist ohne, genauer mit dem BIOS deiner eigenen Dreamcast", true],
}

const WIN_RESERVIERT := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7",
	"COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]

static var _lizenzen := {}


# --- Quellen ---------------------------------------------------------------------------------

## Host einer https-Adresse ohne Anschluss, Benutzer oder Sonderzeichen ("" sonst).
static func host_von(url: String) -> String:
	if not url.begins_with("https://") or url.length() > 2048:
		return ""
	for ch in [" ", "\\", "\t", "\n", "\r", "@"]:
		if url.contains(ch):
			return ""
	var rest := url.substr(8)
	var cut := rest.find("/")
	if cut <= 0:
		return ""
	var host := rest.left(cut)
	if not RegEx.create_from_string("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$").search(host):
		return ""
	return host


## Darf Uzai diese Adresse für Emulatoren abrufen? Nur https zu den festen Hosts.
static func quelle_ok(url: String) -> bool:
	return host_von(url) in HOSTS


## Weiterleitung von → nach erlaubt? Nur https zu den Hosts, die zur Quelle gehören.
static func weiterleitung_ok(von: String, nach: String) -> bool:
	var h := host_von(nach)
	return h != "" and h in (WEITER.get(host_von(von), []) as Array)


static func eintrag(id: String) -> Dictionary:
	return KATALOG.get(id, {})


static func lizenz(key: String) -> Dictionary:
	if _lizenzen.is_empty():
		var f := FileAccess.open("res://data/emu_lizenzen.json", FileAccess.READ)
		var d: Variant = Fremd.json_roh(f.get_as_text()) if f else null
		_lizenzen = (d.get("lizenzen", {}) if d is Dictionary else {}) as Dictionary
	var l: Variant = _lizenzen.get(key)
	return l if l is Dictionary else {}


## Lizenz-Pflicht: Uzai bietet nur an, wessen Lizenztext es zeigen kann.
static func lizenz_ok(key: String) -> bool:
	var l := lizenz(key)
	return str(l.get("name", "")) != "" and str(l.get("text", "")).length() >= 2000


## Fassung aus Tag und Datum: „2.8.2“, bei laufenden Fassungen (Tag „latest“) das Datum.
static func fassung_text(tag: String, published: String) -> String:
	if tag != "latest":
		return tag.trim_prefix("v")
	var m := RegEx.create_from_string("^([0-9]{4})-([0-9]{2})-([0-9]{2})T").search(published)
	if m == null:
		return "Laufende Fassung"
	return TranslationServer.translate("Fassung vom %s") % ("%s.%s.%s" % [m.get_string(3), m.get_string(2), m.get_string(1)])


## Release-Daten von GitHub (fremde Daten) → Angebot, streng geprüft: Tag nach Muster, genau ein
## Paket mit dem festen Namen, Adresse genau so, wie GitHub sie für dieses Repository baut, Größe in
## den Grenzen, SHA-256 von GitHub. Ergebnis: { ok, error, id, name, fassung, kennung, datei, url,
## groesse, sha256, lizenz, web, pruefung }.
static func angebot_github(id: String, data: Variant) -> Dictionary:
	var e := eintrag(id)
	if e.is_empty() or str(e.get("quelle", "")) != "github":
		return _nein("Unbekannter Emulator.")
	if not (data is Dictionary):
		return _nein("GitHub hat keine gültigen Daten geschickt.")
	var d: Dictionary = data
	if bool(d.get("draft", false)) or bool(d.get("prerelease", false)):
		return _nein("Die neueste Fassung ist noch keine fertige Ausgabe.")
	var tag := str(d.get("tag_name", ""))
	if not RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$").search(tag):
		return _nein("Die Fassung hat einen ungewöhnlichen Namen – Uzai lädt sie nicht.")
	var assets: Variant = d.get("assets", [])
	if not (assets is Array) or (assets as Array).size() > 200:
		return _nein("GitHub hat keine gültigen Daten geschickt.")
	var re := RegEx.create_from_string(str(e.muster))
	var treffer: Array = (assets as Array).filter(func(a: Variant) -> bool: return a is Dictionary and re.search(str((a as Dictionary).get("name", ""))) != null)
	if treffer.size() != 1:
		return _nein("Für Windows gibt es in dieser Fassung kein passendes Paket.")
	var a: Dictionary = treffer[0]
	var datei := str(a.name)
	var url := str(a.get("browser_download_url", ""))
	if url != "https://github.com/%s/releases/download/%s/%s" % [str(e.repo), tag, datei]:
		return _nein("Die Download-Adresse passt nicht zum Projekt – Uzai lädt nichts.")
	var size: Variant = a.get("size", 0)
	if not (size is int or size is float) or int(size) < int(e.get("min_mb", 1)) * MB or int(size) > int(e.get("max_mb", 100)) * MB:
		return _nein("Das Paket ist ungewöhnlich groß oder klein – Uzai lädt es nicht.")
	var sha := Net.github_digest(a)
	if sha == "":
		return _nein("GitHub nennt keine Prüfsumme – aus Sicherheitsgründen lädt Uzai nichts.")
	return _angebot(id, e, fassung_text(tag, str(d.get("published_at", ""))), sha, datei, url, int(size), sha, "SHA-256 von GitHub")


## Angebot einer fest hinterlegten Fassung (Größe kommt beim Laden vom Server, -1 = unbekannt).
static func angebot_fest(id: String, groesse := -1) -> Dictionary:
	var e := eintrag(id)
	if e.is_empty() or str(e.get("quelle", "")) != "fest":
		return _nein("Unbekannter Emulator.")
	return _angebot(id, e, str(e.version), str(e.version), str(e.url).get_file(), str(e.url), groesse, str(e.sha256), "SHA-256 fest in Uzai")


static func _angebot(id: String, e: Dictionary, fassung: String, kennung: String, datei: String, url: String, groesse: int, sha: String,
		pruefung: String) -> Dictionary:
	if not lizenz_ok(str(e.lizenz)):
		return _nein("Ohne Lizenztext bietet Uzai nichts an.")
	if not quelle_ok(url) or sha.length() != 64 or not sha.is_valid_hex_number():
		return _nein("Die Quelle ist nicht erlaubt.")
	return { "ok": true, "error": "", "id": id, "name": str(e.name), "fassung": fassung, "kennung": kennung,
		"datei": datei, "url": url, "groesse": groesse, "sha256": sha.to_lower(), "lizenz": str(e.lizenz),
		"web": str(e.web), "pruefung": pruefung, "archiv": str(e.archiv) }


static func _nein(why: String) -> Dictionary:
	return { "ok": false, "error": why }


## Ist b eine neuere Fassung als a? Zahlen zählen als Zahlen, Buchstaben dahinter als Nachtrag
## („2609a“ nach „2609“, „1.22.10“ nach „1.22.2“).
static func neuer(a: String, b: String) -> bool:
	var ta := _teile(a)
	var tb := _teile(b)
	for i in maxi(ta.size(), tb.size()):
		var x: Variant = ta[i] if i < ta.size() else 0
		var y: Variant = tb[i] if i < tb.size() else 0
		if typeof(x) != typeof(y):
			x = str(x)
			y = str(y)
		if y > x:
			return true
		if y < x:
			return false
	return false


static func _teile(v: String) -> Array:
	var out: Array = []
	for m in RegEx.create_from_string("[0-9]+|[a-z]+").search_all(v.to_lower().trim_prefix("v")):
		var s := m.get_string()
		out.append(int(s) if s.is_valid_int() else s)
	return out


## Neuere Fassung beim Projekt, als Uzai sie fest kennt ("" wenn keine): GitHub-Tag (RetroArch) bzw.
## „shortrev“ vom Dolphin-Server. Fremde Daten: nur ein Name nach festem Muster.
static func neue_fassung(id: String, data: Variant) -> String:
	var e := eintrag(id)
	if not (data is Dictionary) or str(e.get("quelle", "")) != "fest":
		return ""
	var v := str((data as Dictionary).get("tag_name" if str(e.neu_art) == "github" else "shortrev", "")).trim_prefix("v")
	if not RegEx.create_from_string("^[0-9]{1,4}(\\.[0-9]{1,4}){0,3}[a-z]?$").search(v):
		return ""
	return v if neuer(str(e.version), v) else ""


# --- Kerne -------------------------------------------------------------------------------------

static func kern_ok(kern: String) -> bool:
	return KERN_INFO.has(kern) and lizenz_ok(str(KERN_INFO[kern][1]))


static func kern_url(kern: String) -> String:
	return KERN_BASIS + kern + "_libretro.dll.zip" if kern_ok(kern) else ""


## CRC32 eines Kern-Pakets aus der Liste des Buildbots („<Datum> <crc> <Datei>“ je Zeile); -1 wenn
## der Kern nicht drinsteht.
static func kern_crc(index: String, kern: String) -> int:
	var want := kern + "_libretro.dll.zip"
	for line in index.split("\n"):
		var p := line.strip_edges().split(" ", false)
		if p.size() == 3 and p[2] == want and p[1].length() == 8 and p[1].is_valid_hex_number():
			return p[1].hex_to_int()
	return -1


# --- Systeme erkennen ----------------------------------------------------------------------------

## Welche Systeme da sind und was ihnen fehlt. spiele: { System → Zahl der Spiele } (aus der
## Bibliothek und gefundenen Spieleordnern). systems: Config.systems(). emu(id) → Emulator,
## exe_ok(pfad) → gibt es die Datei, kern_da(emulator, kern) → liegt der Kern bereit. eigen: Uzais
## Ordner „emulatoren“ – nur dorthin legt Uzai Kerne, nie in ein RetroArch, das du selbst hast.
## Ergebnis, meiste Spiele zuerst: [{ system, name, short, spiele, bereit, emulator, angebot,
## kern, grund }] – grund: "" (Uzai kann es einrichten), "switch" (nie automatisch), "selbst"
## (dafür bietet Uzai keinen Emulator an), "kern_selbst" (dein RetroArch, der Kern fehlt).
static func erkennen(spiele: Dictionary, systems: Array, emu: Callable, exe_ok: Callable, kern_da: Callable, eigen := "") -> Array:
	var out: Array = []
	for s in systems:
		var sid := str(s.get("id", ""))
		var n := int(spiele.get(sid, 0))
		if n <= 0:
			continue
		var eid := str(s.get("emulator", ""))
		var e: Dictionary = emu.call(eid) if eid != "" else {}
		var r := { "system": sid, "name": str(s.get("name", sid)), "short": str(s.get("short", sid)), "spiele": n,
			"bereit": false, "emulator": eid, "angebot": "", "kern": "", "grund": "" }
		var exe := str(e.get("exe", ""))
		var will_kern := str(e.get("args", "")).contains("{core}")
		var kern := str(s.get("core", ""))
		if exe != "" and exe_ok.call(exe):
			if not will_kern or kern == "" or kern_da.call(e, kern):
				r.bereit = true
				out.append(r)
				continue
			if eigen == "" or not exe.replace("\\", "/").begins_with(eigen.replace("\\", "/").trim_suffix("/") + "/"):
				r.grund = "kern_selbst"
				r.kern = kern
				out.append(r)
				continue
		if sid in NIE:
			r.grund = "switch"
		elif KATALOG.has(eid) and (eid != "retroarch" or kern_ok(kern) or KERNE.has(sid)):
			r.angebot = eid
		else:
			for id in KATALOG.keys():
				if sid in (KATALOG[id].systeme as Array):
					r.angebot = str(id)
			if r.angebot == "" and KERNE.has(sid):
				r.angebot = "retroarch"
		if r.angebot == "retroarch":
			r.kern = kern if kern_ok(kern) else str(KERNE.get(sid, ""))
			if r.kern == "":
				r.angebot = ""
		if r.angebot == "" and r.grund == "":
			r.grund = "selbst"
		out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.spiele) > int(b.spiele))
	return out


## Was einzurichten ist: { emus: [ids, in Reihenfolge], kerne: [Kerne], systeme: { id → [System-IDs] } }.
static func plan(liste: Array) -> Dictionary:
	var emus: Array = []
	var kerne: Array = []
	var by := {}
	for r in liste:
		var id := str(r.get("angebot", ""))
		if bool(r.get("bereit", false)) or id == "":
			continue
		if not emus.has(id):
			emus.append(id)
			by[id] = []
		(by[id] as Array).append(str(r.system))
		var k := str(r.get("kern", ""))
		if k != "" and not kerne.has(k):
			kerne.append(k)
	return { "emus": emus, "kerne": kerne, "systeme": by }


## „Für 3 Systeme fehlt ein Emulator“ – "" wenn nichts fehlt, was Uzai einrichten kann.
static func fehlt_text(liste: Array) -> String:
	var n := liste.filter(func(r: Dictionary) -> bool: return not bool(r.bereit) and str(r.angebot) != "").size()
	if n <= 0:
		return ""
	return "Für ein System fehlt ein Emulator" if n == 1 else TranslationServer.translate("Für %d Systeme fehlt ein Emulator") % n


## Neutraler BIOS-Hinweis ("" wenn das System keins braucht): was fehlt, dass man es von der eigenen
## Konsole selbst sichert und in welchen Ordner es gehört – ohne Quellen, Namen von Seiten oder Links.
static func bios_hinweis(sid: String, sys_name: String, emu_id: String, emu_dir_win: String) -> String:
	var ordner := str((eintrag(emu_id).get("bios", {}) as Dictionary).get(sid, ""))
	if ordner == "" or not BIOS_INFO.has(sid):
		return ""
	var sep := "\\" if emu_dir_win.contains("\\") else "/"
	var ziel := emu_dir_win.trim_suffix(sep) + sep + ordner.replace("/", sep)
	return TranslationServer.translate(
			"%s %s. Uzai lädt es nicht und nennt keine Quelle dafür: Sichere es selbst von deiner Konsole und lege die Datei in diesen Ordner: %s") % [sys_name,
			TranslationServer.translate(str(BIOS_INFO[sid][0])), ziel]


# --- Archive ---------------------------------------------------------------------------------------

## Name im Archiv erlaubt? Relativ, mit „/“ getrennt, keine Ebene „.“ oder „..“, kein Laufwerk,
## kein „:“ (auch keine Datenströme), keine Steuer- und in Windows verbotenen Zeichen, keine
## reservierten Gerätenamen, höchstens 16 Ebenen und 240 Zeichen.
static func pfad_ok(name: String) -> bool:
	var n := name.trim_suffix("/")
	if n == "" or n.length() > 240 or n.begins_with("/") or n.contains("\\") or n.contains(":"):
		return false
	var teile := n.split("/")
	if teile.size() > 16:
		return false
	for t in teile:
		if t == "" or t == "." or t == ".." or t.ends_with(".") or t.ends_with(" ") or t.begins_with(" "):
			return false
		if t.get_slice(".", 0).to_upper() in WIN_RESERVIERT:
			return false
		for ch in t:
			var c := ch.unicode_at(0)
			if c < 32 or c == 127 or "<>\"|?*".contains(ch):
				return false
	return true


## Inhaltsverzeichnis eines Programm-ZIP prüfen, ohne zu entpacken (src/core/zip_pruefung.gd, derselbe
## Leser wie für geteilte Zimmer), mit Grenzen für Programme: Namen nach pfad_ok (UTF-8 erlaubt), Grenzen für
## Zahl, Größe und Packrate. nur: wenn gesetzt, genau diese Dateinamen (Kern-Pakete).
## Ergebnis: { ok, error, entries: [{ name, method, crc, csize, usize, data_at }], dirs: [Namen], total }.
static func zip_index(b: PackedByteArray, nur: Array = []) -> Dictionary:
	var name_ok := func(name: String, ordner: bool) -> String:
		if not pfad_ok(name):
			return "name"
		if not nur.is_empty() and (ordner or not nur.has(name)):
			return "nicht_dabei"
		return ""
	var r := Zip.verzeichnis(b, { "max_archiv": MAX_ARCHIV, "max_eintraege": MAX_EINTRAEGE, "max_dateien": MAX_EINTRAEGE,
		"max_name": 240, "utf8": true, "name_ok": name_ok, "grenze": func(_n: String) -> int: return -1,
		"rate_ab": 65536, "max_rate": MAX_RATE, "max_gesamt": MAX_GESAMT })
	if not bool(r.ok):
		return _nein(_zip_text(r))
	return { "ok": true, "error": "", "entries": r.entries, "dirs": r.dirs, "total": r.total }


## Satz für den Nutzer zu einem Fehler des ZIP-Lesers.
static func _zip_text(r: Dictionary) -> String:
	var name := str(r.name)
	match str(r.fehler):
		"kein_zip":
			return "Das Paket ist kein gültiges ZIP."
		"zip64":
			return "Geteilte oder ZIP64-Pakete liest Uzai nicht."
		"zu_viele", "leer":
			return "Das Paket enthält zu viele oder keine Dateien."
		"name", "name_kodierung":
			return TranslationServer.translate("Ein Name im Paket ist nicht erlaubt: %s") % name.c_escape().left(80)
		"nicht_dabei", "ordner":
			return TranslationServer.translate("Ein Name im Paket ist nicht erlaubt: %s") % name.left(80)
		"doppelt":
			return TranslationServer.translate("Eine Datei steht doppelt im Paket: %s") % name.left(80)
		"verschluesselt":
			return "Verschlüsselte Pakete liest Uzai nicht."
		"verknuepfung":
			return TranslationServer.translate("Das Paket enthält eine Verknüpfung: %s") % name.left(80)
		"verfahren":
			return TranslationServer.translate("„%s“ ist mit einem Verfahren gepackt, das Uzai nicht liest.") % name.left(80)
		"packrate":
			return TranslationServer.translate("„%s“ ist ungewöhnlich stark gepackt – Uzai entpackt es nicht.") % name.left(80)
		"zu_gross":
			return "Das Paket ist entpackt zu groß."
	return "Das Paket ist beschädigt."


## Liste von „tar -tvf“ (Windows-tar, auch für .7z) prüfen, bevor entpackt wird: nur Dateien und
## Ordner (keine Verknüpfungen, Geräte, harten Links), Namen nach pfad_ok, Grenzen für Zahl und
## Größe. Jede Zeile muss sich lesen lassen – sonst wird nichts entpackt.
## Ergebnis: { ok, error, files, total }.
static func tar_liste(text: String) -> Dictionary:
	var re := RegEx.create_from_string("^([-dlhcbps])[-rwxsStTlL]{9}\\S*\\s+\\d+\\s+\\S+\\s+\\S+\\s+(\\d+)\\s+\\S+\\s+\\d{1,2}\\s+\\S+\\s(.+)$")
	var files := 0
	var total := 0
	var seen := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if line == "":
			continue
		var m := re.search(line)
		if m == null:
			return _nein("Der Inhalt des Pakets lässt sich nicht prüfen – Uzai entpackt es nicht.")
		var kind := m.get_string(1)
		var name := m.get_string(3).replace("\\", "/")
		if kind != "-" and kind != "d":
			return _nein(TranslationServer.translate("Das Paket enthält eine Verknüpfung: %s") % name.left(80))
		if name.contains(" -> ") or name.contains(" link to ") or not pfad_ok(name):
			return _nein(TranslationServer.translate("Ein Name im Paket ist nicht erlaubt: %s") % name.c_escape().left(80))
		var low := name.to_lower().trim_suffix("/")
		if seen.has(low):
			return _nein(TranslationServer.translate("Eine Datei steht doppelt im Paket: %s") % name.left(80))
		seen[low] = true
		if kind == "-":
			files += 1
			total += m.get_string(2).to_int()
		if seen.size() > MAX_EINTRAEGE or total > MAX_GESAMT:
			return _nein("Das Paket ist entpackt zu groß.")
	if files == 0:
		return _nein("Das Paket enthält zu viele oder keine Dateien.")
	return { "ok": true, "error": "", "files": files, "total": total }


# --- Grundeinstellungen ------------------------------------------------------------------------

## Dateien, die Uzai vor dem ersten Start in den Ordner des Emulators legt (nur, wenn es sie dort
## noch nicht gibt – eigene Einstellungen bleiben immer): Tragbar-Modus (alles bleibt im Ordner),
## Vollbild, kein Begrüßungs-Assistent mit Maus, Controller über SDL bzw. XInput.
## Ergebnis: { relativer Pfad → Inhalt }.
static func grund_dateien(id: String) -> Dictionary:
	match id:
		"retroarch":
			return { "retroarch.cfg": _zeilen([
				"video_fullscreen = \"true\"", "input_autodetect_enable = \"true\"", "pause_nonactive = \"false\"",
				"config_save_on_exit = \"true\"", "system_directory = \":\\system\"", "libretro_directory = \":\\cores\""]) }
		"duckstation":
			return { "portable.txt": "", "settings.ini": _zeilen(["[Main]", "SettingsVersion = 3", "SetupWizardIncomplete = false",
				"StartFullscreen = true", "ConfirmPowerOff = false", "", "[InputSources]", "SDL = true", "", "[Pad1]", "Type = AnalogController"]
				+ _sdl_pad(["Up", "Down", "Left", "Right", "Triangle", "Circle", "Cross", "Square", "Select", "Start", "L1", "R1", "L2", "R2", "L3", "R3",
					"LLeft", "LRight", "LUp", "LDown", "RLeft", "RRight", "RUp", "RDown", "LargeMotor", "SmallMotor"], false)) }
		"pcsx2":
			return { "portable.ini": "", "inis/PCSX2.ini": _zeilen(["[UI]", "SettingsVersion = 1", "SetupWizardIncomplete = false",
				"StartFullscreen = true", "ConfirmShutdown = false", "", "[InputSources]", "SDL = true", "", "[Pad1]", "Type = DualShock2"]
				+ _sdl_pad(["Up", "Down", "Left", "Right", "Triangle", "Circle", "Cross", "Square", "Select", "Start", "L1", "R1", "L2", "R2", "L3", "R3",
					"LLeft", "LRight", "LUp", "LDown", "RLeft", "RRight", "RUp", "RDown", "LargeMotor", "SmallMotor"], true)) }
		"ppsspp":
			return { "memstick/PSP/SYSTEM/ppsspp.ini": _zeilen(["[Graphics]", "FullScreen = True"]) }
		"dolphin":
			return { "portable.txt": "",
				"User/Config/Dolphin.ini": _zeilen(["[Display]", "Fullscreen = True", "", "[Interface]", "ConfirmStop = False", "",
					"[Analytics]", "PermissionAsked = True", "Enabled = False", "", "[AutoUpdate]", "UpdateTrack = "]),
				"User/Config/GCPadNew.ini": _zeilen(["[GCPad1]", "Device = XInput/0/Gamepad", "Buttons/A = `Button A`", "Buttons/B = `Button B`",
					"Buttons/X = `Button X`", "Buttons/Y = `Button Y`", "Buttons/Z = `Shoulder R`", "Buttons/Start = Start",
					"Main Stick/Up = `Left Y+`", "Main Stick/Down = `Left Y-`", "Main Stick/Left = `Left X-`", "Main Stick/Right = `Left X+`",
					"C-Stick/Up = `Right Y+`", "C-Stick/Down = `Right Y-`", "C-Stick/Left = `Right X-`", "C-Stick/Right = `Right X+`",
					"Triggers/L = `Trigger L`", "Triggers/R = `Trigger R`", "Triggers/L-Analog = `Trigger L`", "Triggers/R-Analog = `Trigger R`",
					"D-Pad/Up = `Pad N`", "D-Pad/Down = `Pad S`", "D-Pad/Left = `Pad W`", "D-Pad/Right = `Pad E`", "Rumble/Motor = `Motor L`"]) }
	return {}


## Ordner, die Uzai dazu anlegt (für das BIOS der eigenen Konsole, die Kerne).
static func ordner(id: String) -> Array:
	var out: Array = []
	for o in (eintrag(id).get("bios", {}) as Dictionary).values():
		if not out.has(o):
			out.append(o)
	if id == "retroarch":
		out.append("cores")
	return out


## Belegung „wie ein Xbox-Controller“ für DuckStation und PCSX2 (gleiche Namen der SDL-Eingaben).
## face: PCSX2 ab 2.4 nennt die Tasten FaceSouth/East/West/North; DuckStation kennt nur A/B/X/Y
## (FaceSouth hieße dort: Kreuz, Kreis, Quadrat, Dreieck tot). Kein „Analog“ auf Guide – die Taste
## gehört Uzai, und DuckStation schaltete sonst bei jedem Guide auf digital.
static func _sdl_pad(keys: Array, face: bool) -> Array:
	const SDL := { "Up": "DPadUp", "Down": "DPadDown", "Left": "DPadLeft", "Right": "DPadRight", "Triangle": "FaceNorth",
		"Circle": "FaceEast", "Cross": "FaceSouth", "Square": "FaceWest", "Select": "Back", "Start": "Start", "L1": "LeftShoulder",
		"R1": "RightShoulder", "L2": "+LeftTrigger", "R2": "+RightTrigger", "L3": "LeftStick", "R3": "RightStick", "LLeft": "-LeftX",
		"LRight": "+LeftX", "LUp": "-LeftY", "LDown": "+LeftY", "RLeft": "-RightX", "RRight": "+RightX", "RUp": "-RightY",
		"RDown": "+RightY", "Analog": "Guide", "LargeMotor": "LargeMotor", "SmallMotor": "SmallMotor" }
	const ABXY := { "FaceSouth": "A", "FaceEast": "B", "FaceWest": "X", "FaceNorth": "Y" }
	return keys.map(func(k: String) -> String: return "%s = SDL-0/%s" % [k, SDL[k] if face else str(ABXY.get(SDL[k], SDL[k]))])


static func _zeilen(l: Array) -> String:
	return "\n".join(PackedStringArray(l)) + "\n"


static func groesse_text(b: int) -> String:
	return Doktor.size_text(b) if b > 0 else TranslationServer.translate("Größe unbekannt")
