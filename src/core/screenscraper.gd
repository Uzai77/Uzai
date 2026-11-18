extends RefCounted
## ScreenScraper (screenscraper.fr): Cover, Hintergründe, Schriftzüge und Szenen für alle Spiele,
## ohne eigenen Schlüssel. Emulator-Spiele: ein Abruf je Spiel (jeuInfos, gesucht nach System,
## Dateiname und -größe). PC-Spiele (Steam, Epic, GOG …): Suche nach Namen unter „PC Windows“, sonst
## „PC Dos“ (jeuRecherche), der beste Treffer nach Name und Jahr. Danach nur noch die Bilder.
##
## Zugang: Die Schnittstelle verlangt Zugangsdaten des Programms (devid/devpassword; ScreenScraper
## vergibt sie auf Anfrage an das Projekt). Sie stehen in data/screenscraper_dev.json (nicht im Repo,
## .gitignore; das Windows-Paket bringt sie mit) oder, für eigene Builds, unter accounts.ss_devid und
## accounts.ss_devpass. Ohne sie ist ScreenScraper aus und taucht nirgends auf. Ein eigenes,
## kostenloses ScreenScraper-Konto (accounts.ss_user/ss_pass, Tresor) ist freiwillig und hebt nur das
## Tageskontingent.
##
## Sicherheit: nur https, Anfragen nur an api.screenscraper.fr, Bilder nur von *.screenscraper.fr.
## Die Bildadressen tragen die Zugangsdaten in der Abfrage – gemerkt wird nur die Adresse ohne sie
## (ohne_zugang), dazu kommen sie erst beim Laden (mit_zugang). Nie protokolliert, nie als
## öffentliche Adresse gemerkt (kein Discord-Status). Antworten werden streng geprüft (Typen, Längen,
## Hosts); nichts daraus wird ausgeführt oder als Pfad benutzt.

const Fremd := preload("res://src/core/fremd.gd")

const API := "https://api.screenscraper.fr/api2/jeuInfos.php?"
const SUCHE_API := "https://api.screenscraper.fr/api2/jeuRecherche.php?"
const RetroMatch := preload("res://src/core/retro_match.gd")
const SOFT := "Uzai"
const DEV_FILE := "res://data/screenscraper_dev.json"
const DEV_FILE_EIGEN := "user://screenscraper_dev.json"
const ZUGANG := ["devid", "devpassword", "ssid", "sspassword"]
## Uzais Systeme → Kennung bei ScreenScraper (systemesListe).
const SYSTEME := {
	"megadrive": 1, "mastersystem": 2, "nes": 3, "snes": 4, "gb": 9, "gbc": 10, "gba": 12, "gc": 13, "n64": 14,
	"nds": 15, "wii": 16, "3ds": 17, "wiiu": 18, "gamegear": 21, "saturn": 22, "dreamcast": 23, "atari2600": 26,
	"pce": 31, "xbox": 32, "xbox360": 33, "ps1": 57, "ps2": 58, "ps3": 59, "psp": 61, "arcade": 75, "switch": 225,
}
## PC-Spiele bei ScreenScraper (systemesListe): PC Windows 138, PC Dos 135, PC Win3.xx 136.
const PC_SYSTEME := { "windows": 138, "dos": 135, "win3x": 136 }
## Namenssuche für PC-Spiele in dieser Reihenfolge: erst Windows, dann DOS (alte Spiele, Neuauflagen).
const PC_SUCHE := ["windows", "dos"]
## Quellen der PC-Spiele in der Bibliothek (game.source; wie GameProfile.SOURCE_NAMES).
const PC_QUELLEN := ["steam", "epic", "ea", "pc", "gog", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot"]
## Bildart von Uzai → Medienarten bei ScreenScraper, die erste vorhandene gewinnt. ruecken: der
## Scan des Rückens der Verpackung (fürs Regal, src/room/regal_welt.gd).
const ARTEN := { "cover": ["box-2D"], "hero": ["fanart", "ss"], "logo": ["wheel-hd", "wheel"], "ruecken": ["box-2D-side"] }
## Kandidaten je Bildart für die Bildwahl eines Spiels (art_picker.gd): alle Regionen und Varianten,
## in dieser Reihenfolge der Medienarten.
const KANDIDAT_ARTEN := {
	"cover": ["box-2D", "box-3D"], "hero": ["fanart", "ss", "sstitle"],
	"logo": ["wheel-hd", "wheel", "wheel-carbon", "wheel-steel"], "ruecken": ["box-2D-side"],
}
const KANDIDATEN_MAX := 30    ## je Bildart höchstens so viele
## Stand der gemerkten Medien im Eintrag: ältere (ohne ruecken) werden einmal neu gefragt.
const MEDIEN_STAND := 2
const REGIONEN := { "de": ["de", "eu", "wor", "us", "ss", "jp"], "en": ["us", "wor", "eu", "uk", "ss", "jp"] }
const FORMATE := ["png", "jpg", "jpeg", "webp"]
const WERT_MAX := 64          ## Zugangsdaten: so lang höchstens
const NAME_MAX := 300
const URL_MAX := 2048
const MEDIEN_MAX := 600       ## so viele Medien einer Antwort werden höchstens angesehen
const GROESSE_MAX := 64 * 1024 * 1024 * 1024    ## Dateigröße in der Anfrage (größer: weggelassen)
const BILD_MAX := 32 * 1024 * 1024                ## größere Bilder (Angabe „size“) gar nicht erst laden
const TREFFER_MIN := 0.85                         ## Suche nach Namen: so ähnlich muss der Treffer heißen
## Endungen von Abbildern einer Disc: Bei ihnen fragt Uzai als „iso“, sonst als „rom“.
const DISC_ENDUNGEN := ["iso", "cue", "bin", "chd", "gdi", "cdi", "cso", "rvz", "wbfs", "gcm", "gcz", "m3u", "pbp", "img", "mdf", "nrg", "wud", "wux", "xci", "nsp"]
## Endungen von Archiven: Ihre Prüfsumme kennt ScreenScraper nicht (die der ROM darin schon).
const ARCHIV_ENDUNGEN := ["zip", "7z", "rar", "gz", "xz"]
const MD5_MAX := 64 * 1024 * 1024                 ## Prüfsumme nur für Dateien bis zu dieser Größe
const PAUSE_MS := 1100                            ## mindestens so lange zwischen zwei Anfragen
const FAEDEN_MAX := 4                             ## mehr Fäden nie, auch wenn das Konto mehr erlaubt

static var _dev: Dictionary = {}
static var _dev_gelesen := false


## Zugangsdaten des Programms und (freiwillig) des Nutzers. Leere Werte fehlen.
static func zugang() -> Dictionary:
	if not _dev_gelesen:
		_dev_gelesen = true
		_dev = dev_aus(FileAccess.get_file_as_string(DEV_FILE) if FileAccess.file_exists(DEV_FILE) else "")
		# Öffentliche Pakete bringen den Zugang nicht mit (tools/build_windows.sh). Wer ihn hat, legt dieselbe Datei in
		# seinen Datenordner (%APPDATA%\Uzai) – dort bleibt sie, kommt in kein Paket und gilt für jede neue Version.
		if _dev.is_empty() and FileAccess.file_exists(DEV_FILE_EIGEN):
			_dev = dev_aus(FileAccess.get_file_as_string(DEV_FILE_EIGEN))
	var out := {}
	var devid := str(_dev.get("devid", Config.get_value("accounts.ss_devid", "")))
	var devpass := str(_dev.get("devpassword", Config.get_value("accounts.ss_devpass", "")))
	if wert_ok(devid) and wert_ok(devpass):
		out["devid"] = devid
		out["devpassword"] = devpass
	var user := str(Config.get_value("accounts.ss_user", ""))
	var pw := str(Config.get_value("accounts.ss_pass", ""))
	if wert_ok(user) and wert_ok(pw):
		out["ssid"] = user
		out["sspassword"] = pw
	return out


## Inhalt von data/screenscraper_dev.json lesen: { devid, devpassword } oder {}.
static func dev_aus(text: String) -> Dictionary:
	if text == "" or text.length() > 4096:
		return {}
	var d: Variant = Fremd.json_roh(text)
	if not (d is Dictionary):
		return {}
	var id := str((d as Dictionary).get("devid", ""))
	var pw := str((d as Dictionary).get("devpassword", ""))
	return { "devid": id, "devpassword": pw } if wert_ok(id) and wert_ok(pw) else {}


## Ein Zugangswert: nicht leer, kurz, nur sichtbare Zeichen ohne Leerraum.
static func wert_ok(v: String) -> bool:
	if v == "" or v.length() > WERT_MAX:
		return false
	for i in v.length():
		var c := v.unicode_at(i)
		if c <= 32 or c == 127 or c > 0xFFFF:
			return false
	return true


## Gibt es ScreenScraper in diesem Paket (Programmzugang da) und ist es eingeschaltet?
static func verfuegbar() -> bool:
	return zugang().has("devid") and bool(Config.get_value("library.screenscraper", true))


## Ein PC-Spiel (Steam, Epic, EA, GOG, Ubisoft, Battle.net, Xbox, eigene …)?
static func ist_pc(game: Dictionary) -> bool:
	return str(game.get("source", "")) in PC_QUELLEN


## System eines Spiels, wie ScreenScraper-Anfragen es nehmen: PC-Spiele "windows", sonst game.system.
static func schluessel(game: Dictionary) -> String:
	return "windows" if ist_pc(game) else str(game.get("system", ""))


## Kennung eines Systems bei ScreenScraper (0 = unbekannt).
static func nummer(system: String) -> int:
	return int(SYSTEME.get(system, PC_SYSTEME.get(system, 0)))


## Kennt ScreenScraper das System dieses Spiels? (PC-Spiele immer.)
static func kennt(game: Dictionary) -> bool:
	return nummer(schluessel(game)) > 0


## Adresse der Anfrage für ein Spiel ("" ohne System oder Zugang). groesse: Dateigröße oder -1,
## md5: Prüfsumme der Datei ("" = keine; nur 32 Hex-Zeichen zählen).
static func anfrage(game: Dictionary, groesse: int, z: Dictionary, md5 := "") -> String:
	var sys := int(SYSTEME.get(str(game.get("system", "")), 0))
	if sys <= 0 or not z.has("devid") or ist_pc(game):
		return ""
	var datei := str(game.get("path", "")).get_file()
	if datei == "":
		datei = str(game.get("title", ""))
	datei = datei.left(NAME_MAX)
	if datei.strip_edges() == "":
		return ""
	var teile := _zugang_teile(z)
	teile.append("softname=" + SOFT)
	teile.append("output=json")
	teile.append("romtype=" + ("iso" if datei.get_extension().to_lower() in DISC_ENDUNGEN else "rom"))
	teile.append("systemeid=%d" % sys)
	teile.append("romnom=" + datei.uri_encode())
	if groesse > 0 and groesse <= GROESSE_MAX:
		teile.append("romtaille=%d" % groesse)
	if md5.length() == 32 and md5.is_valid_hex_number():
		teile.append("md5=" + md5.to_lower())
	return API + "&".join(teile)


## Anfrage für ein Spiel, dessen Kennung bei ScreenScraper schon bekannt ist (gewählt oder gesucht).
## sys_nr: System des Treffers (z. B. PC Dos statt Windows), nur bekannte Kennungen.
static func anfrage_id(jeu_id: String, system: String, z: Dictionary, sys_nr := 0) -> String:
	var sys := nummer(system)
	if sys > 0 and sys_nr > 0 and (sys_nr in SYSTEME.values() or sys_nr in PC_SYSTEME.values()):
		sys = sys_nr
	if not jeu_id.is_valid_int() or int(jeu_id) <= 0 or sys <= 0 or not z.has("devid"):
		return ""
	var teile := _zugang_teile(z)
	teile.append_array(["softname=" + SOFT, "output=json", "systemeid=%d" % sys, "gameid=%d" % int(jeu_id)])
	return API + "&".join(teile)


## Suche nach Namen (jeuRecherche): wenn Dateiname und Prüfsumme nichts fanden, und für „Anderes
## Spiel“ in der Bildwahl. Nur ein kurzer, sauberer Name geht hinaus.
static func anfrage_suche(titel: String, system: String, z: Dictionary) -> String:
	var sys := nummer(system)
	var t := RetroMatch.norm(titel).left(80).strip_edges()
	if t == "" or sys <= 0 or not z.has("devid"):
		return ""
	var teile := _zugang_teile(z)
	teile.append_array(["softname=" + SOFT, "output=json", "systemeid=%d" % sys, "recherche=" + t.uri_encode()])
	return SUCHE_API + "&".join(teile)


## Darf von dieser Datei die Prüfsumme gebildet werden? Nicht zu groß, kein Archiv.
static func md5_sinnvoll(pfad: String, groesse: int) -> bool:
	return groesse > 0 and groesse <= MD5_MAX and not pfad.get_extension().to_lower() in ARCHIV_ENDUNGEN


static func _zugang_teile(z: Dictionary) -> PackedStringArray:
	var teile := PackedStringArray()
	for k in ZUGANG:
		if z.has(k):
			teile.append("%s=%s" % [k, str(z[k]).uri_encode()])
	return teile


## Adresse ohne Zugangsdaten (zum Merken). Nur Adressen von screenscraper.fr, sonst "".
static func ohne_zugang(url: String) -> String:
	if not bild_ok(url):
		return ""
	var basis := url.get_slice("?", 0)
	if not url.contains("?"):
		return basis
	var rest := PackedStringArray()
	for p in url.substr(url.find("?") + 1).split("&", false):
		if not (p.get_slice("=", 0).to_lower() in ZUGANG):
			rest.append(p)
	return basis + ("?" + "&".join(rest) if not rest.is_empty() else "")


## Gemerkte Adresse zum Laden: die Zugangsdaten wieder dazu.
static func mit_zugang(url: String, z: Dictionary) -> String:
	if not bild_ok(url):
		return ""
	var teile := _zugang_teile(z)
	if teile.is_empty():
		return url
	return url + ("&" if url.contains("?") else "?") + "&".join(teile)


## Darf von dieser Adresse ein Bild kommen? Nur https zu screenscraper.fr (auch Unterdomänen),
## ohne Anmeldung oder Port in der Adresse.
static func bild_ok(url: String) -> bool:
	if url.length() > URL_MAX or not url.begins_with("https://"):
		return false
	var host := url.substr(8).get_slice("/", 0).get_slice("?", 0)
	if host.contains("@") or host.contains(":") or host.contains("\\"):
		return false
	host = host.to_lower()
	return host == "screenscraper.fr" or host.ends_with(".screenscraper.fr")


## Antwort von jeuInfos lesen: { ok, id, name, medien: { Bildart: { url (ohne Zugang), fmt } } }.
## sprache: "de" oder "en" (Reihenfolge der Regionen).
static func lesen(data: Variant, sprache := "de") -> Dictionary:
	var leer := { "ok": false, "id": "", "name": "", "medien": {} }
	if not (data is Dictionary):
		return leer
	var resp: Variant = (data as Dictionary).get("response")
	if not (resp is Dictionary):
		return leer
	var jeu: Variant = (resp as Dictionary).get("jeu")
	if not (jeu is Dictionary):
		return leer
	return jeu_lesen(jeu, sprache)


## Ein Spiel aus einer Antwort (jeuInfos: response.jeu, jeuRecherche: ein Eintrag aus response.jeux):
## { ok, id, name, system, medien: { Bildart: { url, fmt } }, kandidaten: { Bildart: [ … ] } }.
static func jeu_lesen(j: Dictionary, sprache := "de") -> Dictionary:
	var id := str(j.get("id", ""))
	if not id.is_valid_int() or int(id) <= 0:
		return { "ok": false, "id": "", "name": "", "medien": {}, "kandidaten": {} }
	var regionen: Array = REGIONEN.get(sprache, REGIONEN.en)
	var name := _bester_name(j.get("noms"), regionen)
	if name == "" and j.get("nom") is String:
		name = str(j.nom).strip_edges().left(NAME_MAX)
	var sys := 0
	if j.get("systeme") is Dictionary and str((j.systeme as Dictionary).get("id", "")).is_valid_int() and str(j.systeme.id).length() < 6:
		sys = int(str(j.systeme.id))
	var medien_roh: Variant = j.get("medias")
	var medien := {}
	var kand := {}
	if medien_roh is Array:
		var liste: Array = (medien_roh as Array).slice(0, MEDIEN_MAX)
		for art in ARTEN.keys():
			var m := _bestes_medium(liste, ARTEN[art], regionen)
			if not m.is_empty():
				medien[art] = m
		kand = kandidaten(liste, regionen)
	return { "ok": true, "id": id, "name": name, "system": sys, "jahr": jahr_aus(j.get("dates")), "medien": medien, "kandidaten": kand }


## Frühestes Erscheinungsjahr aus „dates“ ([{ region, text: "1993-12-10" }]); 0 wenn keins.
static func jahr_aus(dates: Variant) -> int:
	if not (dates is Array):
		return 0
	var best := 0
	for d in (dates as Array).slice(0, 40):
		if not (d is Dictionary):
			continue
		var t := str((d as Dictionary).get("text", "")).left(4)
		if t.length() == 4 and t.is_valid_int() and int(t) >= 1950 and int(t) <= 2100 and (best == 0 or int(t) < best):
			best = int(t)
	return best


## Alle brauchbaren Bilder je Bildart (KANDIDAT_ARTEN): Medienart in ihrer Reihenfolge, darin die
## Regionen nach Sprache. Je Eintrag { url (ohne Zugang), fmt, typ, region }. Nur erlaubte Hosts und
## Formate, keine zu großen Dateien, nichts doppelt.
static func kandidaten(liste: Array, regionen: Array) -> Dictionary:
	var out := {}
	for art in KANDIDAT_ARTEN.keys():
		var typen: Array = KANDIDAT_ARTEN[art]
		var gesehen := {}
		var reihe: Array = []
		for m in liste:
			if not (m is Dictionary):
				continue
			var e := _medium(m, typen)
			if e.is_empty() or gesehen.has(e.url):
				continue
			gesehen[e.url] = true
			var r := regionen.find(str(e.region)) if str(e.region) != "" else regionen.size()
			e["_rang"] = typen.find(e.typ) * 1000 + (r if r >= 0 else 500)
			reihe.append(e)
		reihe.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a._rang) < int(b._rang))
		var fertig: Array = []
		for e in reihe.slice(0, KANDIDATEN_MAX):
			e.erase("_rang")
			fertig.append(e)
		if not fertig.is_empty():
			out[art] = fertig
	return out


## Ein Medium prüfen: { url, fmt, typ, region } oder {}.
static func _medium(m: Dictionary, typen: Array) -> Dictionary:
	var typ := str(m.get("type", ""))
	if not typ in typen:
		return {}
	var fmt := str(m.get("format", "")).to_lower()
	if not fmt in FORMATE:
		return {}
	var groesse := str(m.get("size", ""))
	if groesse.is_valid_int() and int(groesse) > BILD_MAX:
		return {}
	var url := ohne_zugang(str(m.get("url", "")))
	if url == "":
		return {}
	var reg := str(m.get("region", "")).to_lower()
	if reg.length() > 8 or not reg.is_valid_identifier() and reg != "":
		reg = ""
	return { "url": url, "fmt": "jpg" if fmt == "jpeg" else fmt, "typ": typ, "region": reg }


## Gemerkte Kandidaten (eigene Datei im Cache, aber von der Platte – also wie fremde Daten) streng
## prüfen: nur bekannte Bildarten, erlaubte Adressen und Formate. Gibt die geprüfte Liste zurück.
static func kandidaten_pruefen(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for art in KANDIDAT_ARTEN.keys():
		var roh: Variant = (v as Dictionary).get(art)
		if not (roh is Array):
			continue
		var reihe: Array = []
		for e in (roh as Array).slice(0, KANDIDATEN_MAX):
			if not (e is Dictionary):
				continue
			var url := str((e as Dictionary).get("url", ""))
			var fmt := str((e as Dictionary).get("fmt", ""))
			var typ := str((e as Dictionary).get("typ", ""))
			var reg := str((e as Dictionary).get("region", ""))
			if ohne_zugang(url) != url or url == "" or not fmt in FORMATE or not typ in KANDIDAT_ARTEN[art] or reg.length() > 8:
				continue
			reihe.append({ "url": url, "fmt": fmt, "typ": typ, "region": reg })
		if not reihe.is_empty():
			out[art] = reihe
	return out


## Treffer einer Suche (jeuRecherche): [{ ok, id, name, system, medien, kandidaten }], höchstens 30.
## Leere Einträge (ScreenScraper schickt ohne Treffer ein leeres Spiel) fallen weg.
static func suche_lesen(data: Variant, sprache := "de") -> Array:
	var out: Array = []
	if not (data is Dictionary) or not ((data as Dictionary).get("response") is Dictionary):
		return out
	var jeux: Variant = (data.response as Dictionary).get("jeux")
	if not (jeux is Array):
		return out
	for j in (jeux as Array).slice(0, 30):
		if j is Dictionary:
			var e := jeu_lesen(j, sprache)
			if bool(e.ok):
				out.append(e)
	return out


## Der Treffer einer Suche, der zum Spiel passt: gleiches System (PC: Windows, Dos, Win3.xx), Name
## ähnlich genug; bei gleich gutem Namen das nächste Erscheinungsjahr (jahr: 0 = unbekannt), z. B.
## DOOM von 1993 und 2016. {} wenn keiner.
static func bester_treffer(treffer: Array, titel: String, system: String, jahr := 0) -> Dictionary:
	var erlaubt: Array = PC_SYSTEME.values() if PC_SYSTEME.has(system) else [nummer(system)]
	var best := {}
	var wert := TREFFER_MIN
	var abstand := 9999
	for e in treffer:
		if not (e is Dictionary) or (int(e.get("system", 0)) != 0 and not int(e.get("system", 0)) in erlaubt):
			continue
		var s := RetroMatch.similarity(titel, str(e.get("name", "")))
		if s < TREFFER_MIN:
			continue
		var j := int(e.get("jahr", 0))
		var a := absi(j - jahr) if jahr > 0 and j > 0 else 9999
		if best.is_empty() or s >= wert + 0.0001 or (s > wert - 0.0001 and a < abstand):
			wert = s
			best = e
			abstand = a
	return best


## Kontingent aus der Antwort (response.ssuser, wie ssuserInfos): { heute, max, ko_heute, ko_max,
## faeden (maxthreads), pro_min (maxrequestspermin) } (fehlende: -1). Nur Zahlen – Name und
## sonstiges aus dem Konto werden nicht gelesen.
static func kontingent(data: Variant) -> Dictionary:
	var out := { "heute": -1, "max": -1, "ko_heute": -1, "ko_max": -1, "faeden": -1, "pro_min": -1 }
	if not (data is Dictionary) or not ((data as Dictionary).get("response") is Dictionary):
		return out
	var u: Variant = (data.response as Dictionary).get("ssuser")
	if not (u is Dictionary):
		return out
	for paar in [["heute", "requeststoday"], ["max", "maxrequestsperday"], ["ko_heute", "requestskotoday"], ["ko_max", "maxrequestskoperday"],
			["faeden", "maxthreads"], ["pro_min", "maxrequestspermin"]]:
		var v := str((u as Dictionary).get(paar[1], ""))
		if v.is_valid_int() and v.length() < 10:
			out[paar[0]] = int(v)
	return out


## So viele Anfragen dürfen zugleich laufen: maxthreads des Kontos (ohne Angabe 1, höchstens FAEDEN_MAX).
static func faeden(k: Dictionary) -> int:
	return clampi(int(k.get("faeden", 1)), 1, FAEDEN_MAX)


## Mindestabstand zwischen zwei Anfragen: PAUSE_MS, bei einem Minutenlimit (maxrequestspermin) so,
## dass es nie überschritten wird.
static func pause_ms(k: Dictionary) -> int:
	var pro_min := int(k.get("pro_min", -1))
	return maxi(PAUSE_MS, ceili(60000.0 / pro_min) + 50) if pro_min > 0 else PAUSE_MS


## Ist das Tageskontingent erschöpft (laut Antwort)?
static func kontingent_voll(k: Dictionary) -> bool:
	return (int(k.get("max", -1)) > 0 and int(k.get("heute", -1)) >= int(k.max)) \
			or (int(k.get("ko_max", -1)) > 0 and int(k.get("ko_heute", -1)) >= int(k.ko_max))


## Kleine Vorschau eines Bilds (ScreenScraper verkleinert selbst: maxwidth). "" bei fremder Adresse.
static func vorschau(url: String, breite: int) -> String:
	if not bild_ok(url):
		return ""
	return url + ("&" if url.contains("?") else "?") + "maxwidth=%d" % clampi(breite, 64, 1200)


## Text fürs Protokoll: nie Zugangsdaten, nie Adressen, kurz und einzeilig.
static func sauber(text: String, z: Dictionary) -> String:
	var t := text.left(300)
	for k in ZUGANG:
		var w := str(z.get(k, ""))
		if w.length() >= 2:
			t = t.replace(w, "***").replace(w.uri_encode(), "***")
	var i := t.find("http")
	if i >= 0:
		t = t.left(i) + "[Adresse]"
	return t.replace("\n", " ").replace("\r", " ").strip_edges().left(160)


static func _bester_name(noms: Variant, regionen: Array) -> String:
	if not (noms is Array):
		return ""
	var best := ""
	var rang := 999
	for n in noms:
		if not (n is Dictionary):
			continue
		var t := str((n as Dictionary).get("text", "")).strip_edges()
		if t == "" or t.length() > NAME_MAX:
			continue
		var r := regionen.find(str((n as Dictionary).get("region", "")))
		r = r if r >= 0 else 500
		if r < rang:
			rang = r
			best = t
	return best


## Das beste Medium für eine Bildart: Art in der Reihenfolge von typen, dann Region.
static func _bestes_medium(liste: Array, typen: Array, regionen: Array) -> Dictionary:
	for typ in typen:
		var best := {}
		var rang := 999
		for m in liste:
			if not (m is Dictionary) or str((m as Dictionary).get("type", "")) != typ:
				continue
			var fmt := str((m as Dictionary).get("format", "")).to_lower()
			if not fmt in FORMATE:
				continue
			var url := ohne_zugang(str((m as Dictionary).get("url", "")))
			if url == "":
				continue
			var reg := str((m as Dictionary).get("region", ""))
			var r := regionen.find(reg) if reg != "" else regionen.size()
			r = r if r >= 0 else 500
			if r < rang:
				rang = r
				best = { "url": url, "fmt": "jpg" if fmt == "jpeg" else fmt }
		if not best.is_empty():
			return best
	return {}


## Was eine Ablehnung bedeutet: "zugang" (Programm- oder Kontodaten falsch), "fehlt" (Spiel nicht
## gefunden), "kontingent" (Tageslimit, zu viele Fäden oder zu viele unbekannte Spiele), "zu"
## (Schnittstelle geschlossen, Programm gesperrt) oder "netz".
## text: Antwort des Servers (ScreenScraper erklärt Ablehnungen auf Französisch, teils mit 200).
static func fehler(code: int, text := "") -> String:
	match code:
		401, 403:
			return "zugang"
		404:
			return "fehlt"
		429, 430, 431:
			return "kontingent"
		423, 426:
			return "zu"
		400:
			return "fehlt"
	var t := text.to_lower()
	if t.contains("identifiant") or t.contains("login"):
		return "zugang"
	if t.contains("quota") or t.contains("thread") or t.contains("trop de"):
		return "kontingent"
	if t.contains("non trouv"):
		return "fehlt"
	if t.contains("ferm") or t.contains("blacklist"):
		return "zu"
	return "netz"


## Kurzer Satz zu einem Grund (Mitteilung und Bildwahl).
static func grund_text(grund: String) -> String:
	match grund:
		"zugang": return "Zugang abgelehnt"
		"kontingent": return "Tageslimit erreicht"
		"zu": return "gerade geschlossen"
		"fehlt": return "nicht gefunden"
		"netz": return "nicht erreichbar"
	return ""
