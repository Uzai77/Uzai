extends RefCounted
## Der Browser-Kern (Chromium über CEF): Laden beim ersten Öffnen, Stand, Gesundheit, Updates – reine Logik und der
## Ablauf ohne Oberfläche (docs/BROWSER_PLAN.md 2.1/2.2, docs/SECURITY.md „Uzai-Browser“).
##
## Ablauf des ersten Ladens (laden(), nur Windows; der Vorführmodus spielt ihn in browser_demo.gd nach):
##   1. stable.txt → Meilenstein; <m>_windows64.json → Bauten (nur signierte: abi_hash, file, sha1, version);
##      revoked.json → zurückgerufene Fassungen. Die minimal-Verteilung derselben Fassung steht nur im Gesamt-Index
##      index.json (windows64 → versions → files: name, sha1, size, type „minimal“); fehlt sie dort, die
##      .sha1-Beilage des Hosts. Alles nur https vom festen Host, ohne Weiterleitungen, mit Größengrenzen; die
##      Einträge werden Feld für Feld geprüft.
##   2. Die neueste nicht zurückgerufene signierte Verteilung (cef_binary_<Fassung>_windows64_signed.tar.xz, nur
##      Laufzeit, ohne Bootstrap) nach %LOCALAPPDATA%\Uzai\browser\kern\spiegel (höchstens 500 MB) und die
##      minimal-Verteilung DERSELBEN Fassung (…_windows64_minimal.tar.bz2 oder .tar.xz, nur für bootstrap.exe) nach
##      kern\boot (höchstens 400 MB). Je Datei SHA-1 (und Größe, wenn bekannt) aus dem Index, SHA-256 aus der
##      Beilage (.sha256, wenn es sie gibt) – stimmt eine nicht, wird die Datei gelöscht. Ohne Größe im Index
##      begrenzt nur die feste Obergrenze (gezählte Bytes beim Download).
##   3. Helfer kern-auslegen: mit eigenem Entpacker (UzKernPack: xz, bzip2, tar; nicht Windows-tar) aus der signierten
##      nur chrome_elf.dll (Hauptordner), aus der minimal nur Release/bootstrap.exe; Stummel, Skripte, Filterliste
##      daneben; kern-bauen: den Kern übersetzen. Geprüfte Archive bleiben bis zum Erfolg liegen: Nochmal lädt nicht neu.
##   4. uzai-kernladen.exe --uzai-install: der offizielle Installer im Bootstrap prüft Katalog und Zertifikat der
##      Verteilung, entpackt sie nach kern\store und trägt Uzai ein; Fortschritt kommt als kern-Ereignisse.
##   5. Helfer kern-ressource: Konfiguration (App-Kennung, Fassungen, ABI-Hash, Store) in die Kopie uzai-browser.dll.
## Danach löst der Bootstrap die Fassung bei jedem Start offline auf. Nach der ersten geladenen Seite meldet Uzai
## „gesund“ (Rückfall-Schutz), höchstens einmal am Tag „update“ (neue Fassung gilt ab dem nächsten Start).
## Jeder Schritt und jeder Grund steht in logs/browser_kern.log (ohne Benutzerpfad, ohne Geheimnisse).
## Den Lauf im Hintergrund (von selbst, Fortschritt, Abbruch) führt browser_kern_lauf.gd.
## Tests: tests/logic_browser_kern.gd.

const Logdatei := preload("res://src/core/logdatei.gd")
const P := preload("res://src/core/browser_protokoll.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

const HOST := "https://cef-builds.spotifycdn.com/"
const PLATTFORM := "windows64"
## Feste App-Kennung des Uzai-Browsers beim CEF-Installer (nie ändern: daran hängt die Registrierung im Store).
const APPID := "7A5E2B1C-4D3F-4E8A-9C6B-0F1D2E3A4B5C"
const API := 15101
## Start-Stummel (assets/browser/cef/uzai-browser-start.dll, gebaut von tools/kern_shim_bauen.sh), gleich im Helfer.
const SHIM := "res://assets/browser/cef/uzai-browser-start.dll"
const SHIM_SHA256 := "3e8257dff57644731000628ffa75b586c6c95740ccfda83ca78c2ba53cc28ac5"
const FILTER := "res://assets/browser/filter/filter.gz"
const FILTER_SHA256 := "32275b8fce9d1b36ba8493b3cb160694d438c90ce4275ace4c3d87f2e02329f6"
const MAX_ARCHIV := 500 * 1024 * 1024
const MAX_MINIMAL := 400 * 1024 * 1024
const MAX_LISTE := 2 * 1024 * 1024
## index.json (alle Plattformen, alle Fassungen) ist mehrere MB groß.
const MAX_INDEX := 64 * 1024 * 1024
const MIN_FASSUNG := "151.1"           ## ab hier gibt es Bootstrap-Installer und API 15101
const PRUEFUNG_S := 24 * 3600          ## höchstens einmal am Tag nach Updates sehen
const FASSUNG_RE := "^[0-9]{2,4}\\.[0-9]{1,4}\\.[0-9]{1,4}$"
const DATEI_RE := "^cef_binary_[0-9]{2,4}\\.[0-9]{1,4}\\.[0-9]{1,4}\\+g[0-9a-f]{7}\\+chromium-[0-9]{2,4}\\.0\\.[0-9]{3,5}\\.[0-9]{1,3}_windows64_signed\\.tar\\.xz$"
## Die minimal-Verteilung derselben Fassung: nur ihr Release/bootstrap.exe wird genommen (die signierte hat keinen).
const MINIMAL_RE := "^cef_binary_[0-9]{2,4}\\.[0-9]{1,4}\\.[0-9]{1,4}\\+g[0-9a-f]{7}\\+chromium-[0-9]{2,4}\\.0\\.[0-9]{3,5}\\.[0-9]{1,3}_windows64_minimal\\.tar\\.(bz2|xz)$"
const SHA1_RE := "^[0-9a-f]{40}$"
const EXE_MUSTER := "^[A-Za-z]:\\\\.+\\\\Uzai\\\\browser\\\\kern\\\\app\\\\uzai-(browser|kernladen)\\.exe\\z"
const LOG := "logs/browser_kern.log"
const LOG_MAX := 200000
## Was der Helfer bei kern-auslegen meldet (schritt) → kurzer Grund für den Nutzer; der genaue Text steht im Protokoll.
const AUSLEGEN_TEXT := {
	"admin": "Uzai läuft mit Adminrechten – so richtet es den Kern nicht ein.",
	"archiv": "Das geladene Archiv fehlt oder liegt am falschen Ort.",
	"entpacken": "Das Archiv ließ sich nicht entpacken.",
	"bootstrap": "Der Bootstrap ließ sich nicht entpacken.",
	"kopieren": "Die Kern-Dateien ließen sich nicht in den Uzai-Ordner schreiben.",
	"signatur": "Die Kern-Dateien ließen sich nicht vorbereiten (Signatur).",
	"beilagen": "Uzais eigene Kern-Dateien fehlen oder sind verändert.",
}
const ABI_RE := "^[0-9a-f]{16}$"

## Für fassung(): je Vergleich zweier Fassungen gebraucht (beim Laden gefüllt, danach nur gelesen).
static var _RX_FASSUNG := RegEx.create_from_string(FASSUNG_RE)
static var _RX_FASSUNG_KURZ := RegEx.create_from_string("^[0-9]{2,4}\\.[0-9]{1,4}$")


# --- Reine Logik ------------------------------------------------------------------------------------------

## Fassung „154.3.2“ → [154, 3, 2]; [] wenn kaputt.
static func fassung(s: String) -> Array:
	if _RX_FASSUNG.search(s) == null:
		if _RX_FASSUNG_KURZ.search(s) == null:
			return []
		s += ".0"
	var out: Array = []
	for t in s.split("."):
		out.append(t.to_int())
	return out


## a < b? (beide Fassungen; kaputte zählen als kleinste)
static func aelter(a: String, b: String) -> bool:
	var fa := fassung(a)
	var fb := fassung(b)
	if fa.is_empty() or fb.is_empty():
		return fa.is_empty() and not fb.is_empty()
	for i in 3:
		if fa[i] != fb[i]:
			return fa[i] < fb[i]
	return false


## Die größte Fassung unterhalb dieser (für vmax, wenn eine Fassung unseren Kern nicht mehr verträgt).
static func unter(s: String) -> String:
	var f := fassung(s)
	if f.is_empty():
		return ""
	if f[2] > 0:
		return "%d.%d.%d" % [f[0], f[1], f[2] - 1]
	if f[1] > 0:
		return "%d.%d.99" % [f[0], f[1] - 1]
	return "%d.99.99" % [f[0] - 1]


## Zurückgerufene Fassungen aus revoked.json (fremde Daten) → Array aus [von, bis] (Fassungen als Text).
static func rueckrufe(roh: Variant) -> Array:
	var out: Array = []
	if not (roh is Dictionary) or not ((roh as Dictionary).get("revoked_versions", null) is Array):
		return out
	for e in roh.revoked_versions:
		if out.size() >= 10000 or not (e is Dictionary):
			continue
		var von := str(e.get("version_min", e.get("version", "")))
		var bis := str(e.get("version_max", e.get("version", "")))
		if fassung(von).is_empty() or fassung(bis).is_empty():
			continue
		out.append([von, bis])
	return out


static func zurueckgerufen(f: String, liste: Array) -> bool:
	for r in liste:
		if not aelter(f, str(r[0])) and not aelter(str(r[1]), f):
			return true
	return false


## Größe aus der Liste: -1 ohne Angabe, -2 wenn kaputt.
static func _groesse(v: Variant) -> int:
	if v == null:
		return -1
	if not (v is int or v is float) or float(v) < 0.0 or float(v) > 1e12 or float(v) != floorf(float(v)):
		return -2
	return int(v)


## Der Name ohne Art und Endung („cef_binary_<Fassung>+g…+chromium-…_windows64“): signiert und minimal gleich?
static func _basis(datei: String) -> String:
	var k := datei.rfind("_windows64_")
	return datei.substr(0, k + 10) if k > 0 else ""


## Die signierten Bauten aus <m>_windows64.json (fremde Daten; echter Aufbau 156: eine Liste aus
## { abi_hash, file, last_modified, sha1, version }, ohne size): Fassung ≥ MIN_FASSUNG, nicht zurückgerufen, Datei nach
## festem Muster mit SHA-1, höchstens MAX_ARCHIV; optional nur ein bestimmter ABI-Hash (die Generation unseres
## Bootstraps). Neueste zuerst, je Fassung eine. Steht die minimal-Verteilung derselben Fassung mit in der Liste
## (gleicher Name bis „_windows64“, gleicher ABI-Hash; xz vor bz2), kommt sie als boot, boot_sha1, boot_groesse dazu.
## [{ fassung, datei, sha1, groesse, abi, (boot, boot_sha1, boot_groesse) }]
static func kandidaten(roh: Variant, rueckruf: Array, abi := "") -> Array:
	var liste: Variant = roh.get("builds", roh.get("versions", null)) if roh is Dictionary else roh
	if not (liste is Array):
		return []
	var je := {}
	var n := 0
	var re_s := RegEx.create_from_string(DATEI_RE)
	var re_m := RegEx.create_from_string(MINIMAL_RE)
	var re_sha := RegEx.create_from_string(SHA1_RE)
	var re_abi := RegEx.create_from_string(ABI_RE)
	for e in liste:
		n += 1
		if n > 2000 or not (e is Dictionary):
			continue
		var f := str(e.get("version", ""))
		var datei := str(e.get("file", ""))
		var sha1 := str(e.get("sha1", "")).to_lower()
		var eabi := str(e.get("abi_hash", "")).to_lower()
		var groesse := _groesse(e.get("size", null))
		if fassung(f).is_empty() or aelter(f, MIN_FASSUNG) or zurueckgerufen(f, rueckruf):
			continue
		if re_sha.search(sha1) == null or groesse < -1 or not datei.begins_with("cef_binary_" + f + "+"):
			continue
		if eabi != "" and re_abi.search(eabi) == null:
			continue
		var k: Dictionary = je.get(f, {})
		var d := { "datei": datei, "sha1": sha1, "groesse": groesse, "abi": eabi }
		if re_s.search(datei) != null:
			if groesse > MAX_ARCHIV or k.has("s") or (abi != "" and eabi != abi):
				continue
			k["s"] = d
		elif re_m.search(datei) != null:
			if str(e.get("type", "minimal")) != "minimal" or groesse > MAX_MINIMAL:
				continue
			if k.has("m") and not (str(k.m.datei).ends_with(".bz2") and datei.ends_with(".xz")):
				continue
			k["m"] = d
		else:
			continue
		je[f] = k
	var out: Array = []
	for f in je:
		var k: Dictionary = je[f]
		if not k.has("s"):
			continue
		var sg: Dictionary = k.s
		var w := { "fassung": f, "datei": sg.datei, "sha1": sg.sha1, "groesse": sg.groesse, "abi": sg.abi }
		var mi: Dictionary = k.get("m", {})
		if not mi.is_empty() and _basis(str(mi.datei)) == _basis(str(sg.datei)) and (str(mi.abi) == "" or mi.abi == sg.abi):
			w.merge({ "boot": mi.datei, "boot_sha1": mi.sha1, "boot_groesse": mi.groesse })
		out.append(w)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return aelter(str(y.fassung), str(x.fassung)))
	return out


## Der beste (neueste) signierte Bau – { fassung, datei, sha1, groesse, abi, (boot …) } oder {}.
static func wahl(roh: Variant, rueckruf: Array, abi := "") -> Dictionary:
	var k := kandidaten(roh, rueckruf, abi)
	return k[0] if not k.is_empty() else {}


## Die minimal-Verteilung zu einem signierten Bau aus index.json (fremde Daten, mehrere MB; nur der Zweig windows64:
## { versions: [{ cef_version, files: [{ name, sha1, size, type }] }] }, Feldnamen tolerant: version/file auch).
## Gesucht: Name = Name der signierten bis „_windows64“ + „_minimal.tar.bz2“ (oder .tar.xz, xz vor bz2), Typ
## „minimal“ oder ohne Typ, SHA-1, Größe höchstens MAX_MINIMAL. → { boot, boot_sha1, boot_groesse } oder
## { diagnose } (kurz: was zur Fassung im Index steht – fürs Protokoll).
static func minimal_aus_index(roh: Variant, w: Dictionary) -> Dictionary:
	var basis := _basis(str(w.get("datei", "")))
	if basis == "":
		return { "diagnose": "kein signierter Name" }
	if not (roh is Dictionary):
		return { "diagnose": "nicht lesbar" }
	var zweig: Variant = (roh as Dictionary).get(PLATTFORM, null)
	if not (zweig is Dictionary) or not ((zweig as Dictionary).get("versions", null) is Array):
		return { "diagnose": "ohne %s.versions (Schlüssel: %s)" % [PLATTFORM, _kurzliste((roh as Dictionary).keys(), 8)] }
	var cef := basis.trim_prefix("cef_binary_").trim_suffix("_" + PLATTFORM)
	var re_m := RegEx.create_from_string(MINIMAL_RE)
	var re_sha := RegEx.create_from_string(SHA1_RE)
	var gesehen: Array = []
	var neueste: Array = []
	var best := {}
	var n := 0
	for v in zweig.versions:
		n += 1
		if n > 20000 or not (v is Dictionary):
			continue
		var vname := str(v.get("cef_version", v.get("version", "")))
		if neueste.size() < 3:
			neueste.append(vname)
		var dateien: Variant = v.get("files", null)
		if not (dateien is Array):
			continue
		var passt := vname == cef
		var m := 0
		for d in dateien:
			m += 1
			if m > 50 or not (d is Dictionary):
				continue
			var name := str(d.get("name", d.get("file", "")))
			if not name.begins_with(basis):
				continue
			passt = true
			var typ := str(d.get("type", ""))
			if gesehen.size() < 12:
				gesehen.append("%s %s" % [typ if typ != "" else "?", name.trim_prefix(basis)])
			var sha1 := str(d.get("sha1", "")).to_lower()
			var groesse := _groesse(d.get("size", null))
			if re_m.search(name) == null or _basis(name) != basis or (typ != "" and typ != "minimal"):
				continue
			if re_sha.search(sha1) == null or groesse < -1 or groesse > MAX_MINIMAL:
				continue
			if best.is_empty() or (str(best.boot).ends_with(".bz2") and name.ends_with(".xz")):
				best = { "boot": name, "boot_sha1": sha1, "boot_groesse": groesse }
		if passt and gesehen.is_empty():
			gesehen.append("ohne Dateien")
	if not best.is_empty():
		return best
	if gesehen.is_empty():
		return { "diagnose": "%s fehlt (%d Fassungen, oben: %s)" % [cef, n, _kurzliste(neueste, 3)] }
	return { "diagnose": "zu %s: %s" % [w.get("fassung", "?"), _kurzliste(gesehen, 12)] }


## Die minimal-Verteilung, wenn index.json sie nicht nennt: Name aus dem signierten, SHA-1 aus der Beilage.
static func minimal_name(w: Dictionary) -> String:
	var b := _basis(str(w.get("datei", "")))
	return b + "_minimal.tar.bz2" if b != "" else ""


## SHA-1 aus einer .sha1-Beilage ("<hex>  datei" oder nur "<hex>"), "" wenn kaputt.
static func sha1_aus(text: String) -> String:
	var t := text.strip_edges().to_lower()
	var k := t.find(" ")
	if k > 0:
		t = t.substr(0, k)
	return t if t.length() == 40 and t.is_valid_hex_number() else ""


## Für das Protokoll: höchstens n Einträge, je kurz, ohne Steuerzeichen.
static func _kurzliste(a: Array, n: int) -> String:
	var out: Array = []
	for x in a.slice(0, n):
		out.append(anonym(str(x), 60))
	return ", ".join(PackedStringArray(out)) + (" …" if a.size() > n else "")


## Meilenstein aus stable.txt ("154\n") → 154, 0 wenn kaputt.
static func meilenstein(text: String) -> int:
	var t := text.strip_edges()
	if t.length() < 2 or t.length() > 4 or not t.is_valid_int():
		return 0
	var m := t.to_int()
	return m if m >= 151 and m < 10000 else 0


static func url_liste(m: int) -> String:
	return HOST + "%d_%s.json" % [m, PLATTFORM]


static func url_datei(datei: String) -> String:
	return HOST + datei


## Die Zeile für uzai-kernladen.exe --uzai-install (Standardeingabe) – nur geprüfte Werte. vmin = vmax = die
## Fassung im Spiegel: der Installer nimmt die neueste passende des Manifests (FindBestBuildEntry) – erschiene dort
## inzwischen eine neuere, fehlte ihr Archiv im Spiegel. Die Ressource (kern-ressource) bleibt ohne vmax.
static func install_zeile(fassung_s: String, abi: String, store: String, spiegel: String) -> String:
	if fassung(fassung_s).is_empty() or (abi != "" and RegEx.create_from_string(ABI_RE).search(abi) == null):
		return ""
	return JSON.stringify({ "t": "kern-install", "appid": APPID, "vmin": fassung_s, "vmax": fassung_s, "abi": abi, "store": store, "spiegel": spiegel }) + "\n"


## Welches Manifest der offizielle Installer liest (installer_controller.cc QueryCdnForVersion): mit ABI-Hash
## „<abi>_windows64.json“ (BuildAbiHashUrl), sonst „<Meilenstein von vmin>_windows64.json“ (BuildPlatformUrl). Aus
## einem Spiegel liest er die Datei mit genau diesem Namen (installer_download.cc ReadLocalFileToSink).
static func manifest_name(w: Dictionary, m: int) -> String:
	var abi := str(w.get("abi", ""))
	if abi != "" and RegEx.create_from_string(ABI_RE).search(abi) != null:
		return "%s_%s.json" % [abi, PLATTFORM]
	return "%d_%s.json" % [m, PLATTFORM]


## Prüft ein Manifest (fremde Daten) wie der Installer (installer_cdn_manifest.cc ParsePlatformManifest,
## ParseBuildEntry: ein ungültiger Eintrag verwirft das ganze Manifest) und dass es unseren Bau genau so führt
## (Fassung, Datei, SHA-1, ABI-Hash). "" oder der Grund (kurz, fürs Protokoll).
static func manifest_pruefen(roh: Variant, w: Dictionary) -> String:
	if not (roh is Array):
		return "keine Liste"
	var gefunden := false
	var i := 0
	for e in roh:
		i += 1
		if i > 5000:
			return "zu viele Einträge"
		if not (e is Dictionary):
			return "Eintrag %d: kein Objekt" % i
		var v: Variant = e.get("version", null)
		var f: Variant = e.get("file", null)
		var h: Variant = e.get("sha1", null)
		if not (v is String) or (v as String).is_empty() or (v as String).length() > 64:
			return "Eintrag %d: version" % i
		if not (f is String) or (f as String).is_empty() or (f as String).length() > 256 or (f as String).begins_with(".") \
				or not (f as String).to_lower().ends_with(".tar.xz") or ["/", "\\", ":", ".."].any(func(x: String) -> bool: return (f as String).contains(x)):
			return "Eintrag %d: file" % i
		if not (h is String) or (h as String).is_empty() or (h as String).length() > 40:
			return "Eintrag %d: sha1" % i
		var lm: Variant = e.get("last_modified", null)
		if lm != null and (not (lm is String) or (lm as String).length() > 64):
			return "Eintrag %d: last_modified" % i
		var a: Variant = e.get("abi_hash", null)
		if a != null and (not (a is String) or ((a as String) != "" and not (a as String).is_valid_hex_number()) or (a as String).length() > 256):
			return "Eintrag %d: abi_hash" % i
		if v == str(w.get("fassung", "")) and f == str(w.get("datei", "")) and (h as String).to_lower() == str(w.get("sha1", "")) \
				and str(a if a != null else "").to_lower() == str(w.get("abi", "")):
			gefunden = true
	return "" if gefunden else "Fassung %s fehlt (%d Einträge)" % [w.get("fassung", "?"), i]


## SHA-256 aus einer .sha256-Beilage ("<hex>  datei" oder nur "<hex>"), "" wenn kaputt.
static func sha256_aus(text: String) -> String:
	var t := text.strip_edges().to_lower()
	var k := t.find(" ")
	if k > 0:
		t = t.substr(0, k)
	return t if t.length() == 64 and t.is_valid_hex_number() else ""


## Ist die tägliche Update-Prüfung fällig? (Nie geprüft, ein Tag vorbei oder eine Uhr, die zurückging: ja.)
static func pruefung_faellig(letzte: int, jetzt: int) -> bool:
	return letzte <= 0 or jetzt - letzte >= PRUEFUNG_S or letzte > jetzt


## Was Uzai über den Kern weiß (browser.kern_*): Stand für Oberfläche und Entscheidungen.
static func stand() -> Dictionary:
	return {
		"kern": str(Config.get_value("browser.kern", "cef")),
		"fassung": str(Config.get_value("browser.kern_fassung", "")),
		"abi": str(Config.get_value("browser.kern_abi", "")),
		"gesund": bool(Config.get_value("browser.kern_gesund", false)),
		"pruefung": int(Config.get_value("browser.kern_pruefung", 0)),
		"fehler": str(Config.get_value("browser.kern_fehler", "")),
	}


static func bereit() -> bool:
	return str(Config.get_value("browser.kern_fassung", "")) != ""


static func merken(fassung_s: String, abi: String) -> void:
	Config.set_value("browser.kern_fassung", fassung_s)
	Config.set_value("browser.kern_abi", abi)
	Config.set_value("browser.kern_gesund", false)
	Config.set_value("browser.kern_fehler", "")


static func vergessen(fehler: String) -> void:
	Config.set_value("browser.kern_fassung", "")
	Config.set_value("browser.kern_fehler", fehler)


# --- Pfade (Windows) ----------------------------------------------------------------------------------------

static func wurzel() -> String:
	return OS.get_environment("LOCALAPPDATA").path_join("Uzai/browser/kern")


static func exe() -> String:
	return wurzel().path_join("app/uzai-browser.exe").replace("/", "\\")


static func lader() -> String:
	return wurzel().path_join("app/uzai-kernladen.exe").replace("/", "\\")


# --- Der Ablauf (nur Windows; ohne Netz nicht prüfbar – darum ist jeder Schritt klein und meldet, woran es lag) ----

## So lang darf die Übersicht des Archivs im Protokoll sein (wenn eine Datei fehlt).
const LISTE_MAX := 2000
## So lange wartet laden() auf den Helfer, der beim Start von Uzai noch hochfahren kann.
const HELFER_WARTEN_MS := 30000


## Lädt den Kern. fortschritt(schritt: String, prozent: int), stop["stop"] = true bricht zwischen den Schritten ab.
## Ergebnis "" oder ein kurzer Grund für den Nutzer (der genaue steht in logs/browser_kern.log).
static func laden(fortschritt: Callable, zeilen: Callable, stop: Dictionary = {}) -> String:
	if not Config.is_windows():
		return "Der Browser-Kern läuft nur unter Windows."
	# Gleich nach dem Start (Bereich Browser offen) kann der Helfer noch hochfahren: kurz auf ihn warten.
	var bis := Time.get_ticks_msec() + HELFER_WARTEN_MS
	var loop := Engine.get_main_loop() as SceneTree
	while not Helper.available and Time.get_ticks_msec() < bis and loop and not bool(stop.get("stop", false)):
		await loop.create_timer(0.25).timeout
	if not Helper.available:
		return _grund("Der Helfer läuft nicht.", "helfer: nicht verfügbar")
	protokoll("Laden beginnt (%s)" % ProjectSettings.get_setting("application/config/version", ""))
	fortschritt.call("liste", 0)
	var r0: Dictionary = await Net.request(HOST + "stable.txt", PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "api", 4096, false)
	var stable := (r0.body as PackedByteArray).get_string_from_utf8() if bool(r0.ok) else ""
	var m := meilenstein(stable)
	if m == 0:
		return _grund("Die Liste der Fassungen war nicht lesbar.", "stable.txt: %s" % _netz(r0))
	if bool(stop.get("stop", false)):
		return "-"
	var r: Dictionary = await Net.request(url_liste(m), PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "api", MAX_LISTE, false)
	if not bool(r.ok) or (r.body as PackedByteArray).size() > MAX_LISTE:
		return _grund("Die Liste der Bauten kam nicht.", "%d_%s.json: %s" % [m, PLATTFORM, _netz(r)])
	var r2: Dictionary = await Net.request(HOST + "revoked.json", PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "api", MAX_LISTE, false)
	var rueckruf := rueckrufe(Net.parse_json_now(r2.body) if bool(r2.ok) and (r2.body as PackedByteArray).size() <= MAX_LISTE else null)
	if not bool(r2.ok):
		protokoll("revoked.json: %s (ohne Rückrufliste weiter)" % _netz(r2))
	var abi_bisher := str(Config.get_value("browser.kern_abi", ""))
	var ks := kandidaten(Net.parse_json_now(r.body), rueckruf, "")
	if ks.is_empty():
		return _grund("Keine passende Fassung gefunden.", "Meilenstein %d: keine signierte Fassung ab %s" % [m, MIN_FASSUNG])
	var w: Dictionary = ks[0]
	if not w.has("boot"):
		# Die Meilenstein-Liste nennt nur die signierte Verteilung: die minimal derselben Fassung aus index.json.
		var ri: Dictionary = await Net.request(HOST + "index.json", PackedStringArray(), HTTPClient.METHOD_GET, "", 120.0, "api", MAX_INDEX, false)
		var idx: Variant = null
		if bool(ri.ok) and (ri.body as PackedByteArray).size() <= MAX_INDEX:
			idx = await Net.parse_json(ri.body)
		var diag := "index.json: %s" % _netz(ri) if not bool(ri.ok) else ""
		ri.clear()                      # mehrere MB: nicht länger als nötig halten
		if bool(stop.get("stop", false)):
			return "-"
		for k in ks.slice(0, 5):
			# Im Hilfsfaden: Der Index hat Tausende Fassungen mit je einem Dutzend Dateien.
			var gelesen: Variant = await Arbeit.ergebnis(minimal_aus_index.bind(idx, k))
			var mi: Dictionary = gelesen if gelesen is Dictionary else { "diagnose": "nicht lesbar" }
			if mi.has("boot"):
				if k != ks[0]:
					protokoll("index.json: zu %s keine minimal-Verteilung, nehme %s" % [ks[0].fassung, k.fassung])
				w = (k as Dictionary).merged(mi)
				break
			if diag == "":
				diag = "index.json %s" % str(mi.diagnose)
		idx = null
		if not w.has("boot"):
			protokoll(diag, LISTE_MAX)
			# Rückfall: SHA-1 aus der .sha1-Beilage – vom selben Host über https wie die Listen, also nicht weniger
			# vertrauenswürdig als index.json (wer die Beilage fälschen kann, kann auch den Index fälschen).
			var name := minimal_name(w)
			var r4: Dictionary = await Net.request(url_datei(name + ".sha1"), PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "api", 4096, false)
			var s1 := sha1_aus((r4.body as PackedByteArray).get_string_from_utf8() if bool(r4.ok) else "")
			if s1 == "" or RegEx.create_from_string(MINIMAL_RE).search(name) == null:
				return _grund("Keine passende Fassung gefunden.", "minimal-Verteilung zu %s nicht gefunden (index.json, %s.sha1: %s)" % [w.fassung, name, _netz(r4)])
			w = w.merged({ "boot": name, "boot_sha1": s1, "boot_groesse": -1 })
			protokoll("Bootstrap-Archiv: SHA-1 aus der .sha1-Beilage des Hosts")
	protokoll("Fassung %s (%s), %d Rückrufe" % [w.fassung, w.datei, rueckruf.size()])
	protokoll("Bootstrap aus %s%s" % [w.boot, "" if int(w.boot_groesse) >= 0 else " (ohne Größe im Index)"])
	# Das Manifest, das der offizielle Installer im Spiegel sucht (mit ABI-Hash ein eigenes; 0.16.29: fehlte →
	# „103 No CDN version matches … no validated CDN manifest candidates“). Roh vom Host, vorher wie dort geprüft.
	var mname := manifest_name(w, m)
	var rm: Dictionary = r
	if mname != "%d_%s.json" % [m, PLATTFORM]:
		rm = await Net.request(url_datei(mname), PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "api", MAX_LISTE, false)
	var mgrund := manifest_pruefen(Net.parse_json_now(rm.body) if bool(rm.ok) and (rm.body as PackedByteArray).size() <= MAX_LISTE else null, w) \
		if bool(rm.ok) else _netz(rm)
	if mgrund != "":
		return _grund("Die Liste der Bauten kam nicht.", "%s: %s" % [mname, mgrund])
	protokoll("Manifest für den Installer: %s" % mname)
	if bool(stop.get("stop", false)):
		return "-"
	var spiegel := wurzel().path_join("spiegel")
	var boot := wurzel().path_join("boot")
	for o in [spiegel, boot]:
		if DirAccess.make_dir_recursive_absolute(o) != OK and not DirAccess.dir_exists_absolute(o):
			return _grund("Der Uzai-Ordner ist nicht beschreibbar.", "Ordner %s nicht anlegbar" % str(o).get_file())
	_aufraeumen(boot, str(w.boot))
	# Erst die signierte Verteilung (Laufzeit, der größere Teil des Balkens), dann die minimal (nur der Bootstrap).
	var a1: Dictionary = await _holen(str(w.datei), str(w.sha1), int(w.groesse), spiegel, MAX_ARCHIV, "Archiv", fortschritt, 0, 75, stop)
	if a1.has("grund"):
		return str(a1.grund)
	var a2: Dictionary = await _holen(str(w.boot), str(w.boot_sha1), int(w.boot_groesse), boot, MAX_MINIMAL, "Bootstrap-Archiv", fortschritt, 75, 100, stop)
	if a2.has("grund"):
		return str(a2.grund)
	fortschritt.call("pruefen", 100)
	var archiv := str(a1.pfad)
	var archiv_boot := str(a2.pfad)
	# Beilagen für den Installer in den Spiegel (er liest sie von dort statt aus dem Netz).
	_schreiben(spiegel.path_join("stable.txt"), stable.to_utf8_buffer())
	_schreiben(spiegel.path_join("%d_%s.json" % [m, PLATTFORM]), r.body)
	_schreiben(spiegel.path_join(mname), rm.body)
	if bool(r2.ok):
		_schreiben(spiegel.path_join("revoked.json"), r2.body)
	if str(a1.sha256) != "":
		_schreiben(spiegel.path_join(str(w.datei) + ".sha256"), str(a1.beilage).to_utf8_buffer())
	if bool(stop.get("stop", false)):
		return "-"
	fortschritt.call("auslegen", 0)
	var fehlt := dateien_auslegen()
	if fehlt != "":
		return _grund("Uzais eigene Kern-Dateien fehlen oder sind verändert.", "Auslegen neben dem Helfer: " + fehlt)
	protokoll("Auslegen: chrome_elf.dll aus der signierten, bootstrap.exe aus der minimal-Verteilung")
	var a: Dictionary = await Helper.run("kern-auslegen", { "archiv": archiv.replace("/", "\\"), "boot": archiv_boot.replace("/", "\\") }, 900.0)
	var ar: Dictionary = a.result if bool(a.get("ok", false)) and a.get("result") is Dictionary else {}
	if not bool(ar.get("ok", false)):
		var sch := str(ar.get("schritt", ""))
		if str(ar.get("liste", "")) != "":
			protokoll("Im %s: %s" % ["Bootstrap-Archiv" if sch == "bootstrap" else "Archiv", str(ar.liste)], LISTE_MAX)
		return _grund(str(AUSLEGEN_TEXT.get(sch, "Der Kern ließ sich nicht auslegen.")),
			"kern-auslegen: %s / %s %s" % [sch if sch != "" else "?", str(ar.get("text", a.get("error", "keine Antwort"))), str(ar.get("info", ""))])
	if str(ar.get("boot_signatur", "")) != "":
		protokoll("Bootstrap in der Verteilung: %s" % str(ar.boot_signatur))
	protokoll("Ausgelegt: %s%s" % [str(ar.get("info", "")), (", Signatur aus Kopien entfernt: %s" % str(ar.get("entsigniert"))) if not (ar.get("entsigniert", []) as Array).is_empty() else ""])
	fortschritt.call("auslegen", 60)
	var b: Dictionary = await Helper.run("kern-bauen", {}, 300.0)
	if not (b.ok and b.result is Dictionary and bool(b.result.get("ok", false))):
		return _grund("Der Kern ließ sich nicht übersetzen.", "kern-bauen: %s" % str(b.result.get("fehler", "?") if b.result is Dictionary else b.get("error", "?")))
	if bool(stop.get("stop", false)):
		return "-"
	fortschritt.call("install", 0)
	DirAccess.make_dir_recursive_absolute(wurzel().path_join("store"))
	var zeile := install_zeile(str(w.fassung), str(w.abi), wurzel().path_join("store").replace("/", "\\"), spiegel.replace("/", "\\"))
	var ergebnis: Dictionary = await zeilen.call(lader(), zeile)
	if str(ergebnis.get("stand", "")) != "fertig":
		if bool(stop.get("stop", false)):
			return "-"
		return _grund("Der Installer meldet: %s" % _kurz(str(ergebnis.get("text", "kein Ergebnis"))), "Installer: %s" % str(ergebnis.get("text", "")))
	var c: Dictionary = await Helper.run("kern-ressource", { "appid": APPID, "vmin": str(w.fassung), "vmax": "", "abi": str(w.abi) }, 60.0)
	if not (c.ok and c.result is Dictionary and bool(c.result.get("ok", false))):
		return _grund("Die Kern-Konfiguration ließ sich nicht schreiben.", "kern-ressource: %s" % str(c.result.get("text", c.result.get("fehler", "?")) if c.result is Dictionary else c.get("error", "?")))
	DirAccess.remove_absolute(archiv)
	DirAccess.remove_absolute(archiv_boot)
	merken(str(w.fassung), str(w.abi))
	if abi_bisher != "" and abi_bisher != str(w.abi):
		Config.set_value("browser.kern_generation", int(Config.get_value("browser.kern_generation", 0)) + 1)
	protokoll("Fertig: Fassung %s" % w.fassung)
	return ""


## Lädt ein Archiv der Verteilung nach ordner – nur vom festen Host, ohne Weiterleitung, höchstens max_bytes – und
## prüft SHA-1 und Größe (aus der Liste) und SHA-256 (aus der Beilage .sha256, wenn es sie gibt); stimmt eine nicht,
## wird es gelöscht. Ein schon geprüftes bleibt liegen (Nochmal lädt nicht neu). Fortschritt: download von…bis.
## { pfad, sha256, beilage } oder { grund } (Grund für den Nutzer, "-" beim Abbruch). was: Name im Protokoll.
static func _holen(datei: String, sha1: String, groesse: int, ordner: String, max_bytes: int, was: String,
		fortschritt: Callable, von: int, bis: int, stop: Dictionary) -> Dictionary:
	var pfad := ordner.path_join(datei)
	var r3: Dictionary = await Net.request(url_datei(datei + ".sha256"), PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "api", 4096, false)
	var beilage := (r3.body as PackedByteArray).get_string_from_utf8() if bool(r3.ok) else ""
	var sha256 := sha256_aus(beilage)
	if sha256 == "":
		protokoll("%s .sha256: %s (nur SHA-1 aus der Liste)" % [was, _netz(r3)])
	if bool(stop.get("stop", false)):
		return { "grund": "-" }
	if FileAccess.file_exists(pfad) and await _geprueft(pfad, sha1, sha256, groesse):
		protokoll("%s liegt schon geprüft da" % was)
		fortschritt.call("download", bis)
	else:
		fortschritt.call("download", von)
		var ok := await Net.download_big(url_datei(datei), pfad, func(got: int, total: int) -> void:
			fortschritt.call("download", von + clampi(int(got * float(bis - von) / maxf(1.0, float(total))), 0, bis - von)), max_bytes, false, stop)
		if bool(stop.get("stop", false)):
			return { "grund": "-" }
		if not ok:
			return { "grund": _grund("Der Download ging nicht.", "%s: Download abgebrochen oder Fehler (höchstens %d MB, keine Weiterleitung)" % [was, max_bytes >> 20]) }
		if not await _geprueft(pfad, sha1, sha256, groesse):
			DirAccess.remove_absolute(pfad)
			return { "grund": _grund("Die Prüfsumme des Kerns stimmt nicht – nichts installiert.", "%s: Prüfsumme oder Größe falsch, gelöscht" % was) }
	protokoll("%s: Prüfsummen ok (SHA-1%s%s)" % [was, " und SHA-256" if sha256 != "" else "", ", Größe" if groesse >= 0 else ""])
	return { "pfad": pfad, "sha256": sha256, "beilage": beilage }


## Alte minimal-Archive (andere Fassung, abgebrochene Downloads) aus kern\boot entfernen; nur cef_binary_*-Dateien.
static func _aufraeumen(ordner: String, behalten: String) -> void:
	for name in DirAccess.get_files_at(ordner):
		if name.begins_with("cef_binary_") and name != behalten:
			DirAccess.remove_absolute(ordner.path_join(name))


## Der Start-Stummel neben dem Kern (kern\app\uzai-kernladen.dll ohne, uzai-browser.dll mit Konfiguration) ist von
## einer älteren Fassung von Uzai (0.16.35: Pfadprüfung um ein Zeichen falsch – kein Unterprozess startete): beide neu
## aus dem geprüften Stummel, danach die Konfiguration wieder in uzai-browser.dll. "" = aktuell oder erneuert, sonst der Grund.
static func stummel_auffrischen() -> String:
	var app := wurzel().path_join("app")
	var kl := app.path_join("uzai-kernladen.dll")
	if not FileAccess.file_exists(kl) or FileAccess.get_sha256(kl) == SHIM_SHA256:
		return ""
	if FileAccess.get_sha256(SHIM) != SHIM_SHA256:
		return "Stummel (Prüfsumme)"
	for name in ["uzai-browser.dll", "uzai-kernladen.dll"]:
		if not _kopieren(SHIM, app.path_join(name)):
			return "Stummel: " + name
	if not Helper.available:
		return "Helfer läuft nicht"
	var c: Dictionary = await Helper.run("kern-ressource", { "appid": APPID, "vmin": str(Config.get_value("browser.kern_fassung", "")), "vmax": "",
		"abi": str(Config.get_value("browser.kern_abi", "")) }, 60.0)
	if not (c.ok and c.result is Dictionary and bool(c.result.get("ok", false))):
		return "kern-ressource: %s" % str(c.result.get("text", c.result.get("fehler", "?")) if c.result is Dictionary else c.get("error", "?"))
	protokoll("Start-Stummel erneuert (alte Fassung neben dem Kern)")
	return ""


## Quellen, Skripte, Cookie-Regeln, Filterliste (Prüfsumme) und Start-Stummel (Prüfsumme) neben den Helfer, die
## Daten auch neben den Kern, wenn er schon liegt (nach einem Update von Uzai sind sie sonst alt). "" oder was fehlt.
## (Vorher lief das erst beim Start des Kerns – beim ersten Laden fehlte dem Helfer darum der Stummel.)
static func dateien_auslegen() -> String:
	var dir := Config.path("helper/browser")
	DirAccess.make_dir_recursive_absolute(dir)
	var ziele := [dir]
	var app := wurzel().path_join("app")
	if DirAccess.dir_exists_absolute(app):
		ziele.append(app)
	for name in ["uzai-browser-gemeinsam.cs", "uzai-browser-kern.cs"]:
		if not _kopieren("res://helper/" + name, dir.path_join(name)):
			return name
	if FileAccess.get_sha256(SHIM) != SHIM_SHA256:
		return "Stummel (Prüfsumme)"
	if FileAccess.get_sha256(FILTER) != FILTER_SHA256:
		return "Filterliste (Prüfsumme)"
	if not _kopieren(SHIM, dir.path_join("uzai-browser-start.dll")):
		return "Stummel"
	for z in ziele:
		for name in ["uzai-browser-karte.js", "uzai-browser-filter.js"]:
			if not _kopieren("res://helper/" + name, str(z).path_join(name)):
				return name
		if not _kopieren("res://assets/browser/filter/cookies.json", str(z).path_join("cookies.json")):
			return "cookies.json"
		var f := str(z).path_join("filter.gz")
		if FileAccess.get_sha256(f) != FILTER_SHA256:
			if not _kopieren(FILTER, f) or FileAccess.get_sha256(f) != FILTER_SHA256:
				return "filter.gz"
	return ""


static func _kopieren(von: String, nach: String) -> bool:
	var b := FileAccess.get_file_as_bytes(von)
	if b.is_empty():
		return false
	var f := FileAccess.open(nach, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(b)
	f.close()
	return true


## Eine Zeile ins Protokoll logs/browser_kern.log: Zeit und Text, Benutzerpfade ersetzt, gekürzt.
static func protokoll(text: String, laenge := 400) -> void:
	Logdatei.zeile(Config.path(LOG), anonym(text, laenge), LOG_MAX)


## Ohne Benutzerpfade (LOCALAPPDATA, USERPROFILE), ohne Steuerzeichen, höchstens 400 Zeichen.
static func anonym(text: String, laenge := 400) -> String:
	var t := text
	for v in ["LOCALAPPDATA", "USERPROFILE"]:
		var e := OS.get_environment(v)
		if e.length() > 3:
			t = t.replace(e, "%" + v + "%").replace(e.replace("\\", "/"), "%" + v + "%")
	var out := ""
	for ch in t:
		if ch.unicode_at(0) >= 0x20:
			out += ch
	return out.left(laenge)


static func _grund(fuer_nutzer: String, genau: String) -> String:
	protokoll("Fehler: " + genau)
	return fuer_nutzer


static func _netz(r: Dictionary) -> String:
	var c := int(r.get("code", 0))
	return ("Antwort %d" % c) if c > 0 else "keine Verbindung"


static func _kurz(t: String) -> String:
	var s := anonym(t).strip_edges()
	return s.left(140) if s != "" else "kein Ergebnis"


## Prüfsummen im Hilfsfaden: Gemessen hält ein Archiv mit 180 MB den Hauptfaden sonst 0,9 s an (beide Archive
## zusammen entsprechend länger, mitten im Fortschrittsbalken).
static func _geprueft(pfad: String, sha1: String, sha256: String, groesse: int) -> bool:
	return await Arbeit.ergebnis(_pruefsummen_ok.bind(pfad, sha1, sha256, groesse), Arbeit.LANG) == true


static func _pruefsummen_ok(pfad: String, sha1: String, sha256: String, groesse := -1) -> bool:
	var f := FileAccess.open(pfad, FileAccess.READ)
	if f == null:
		return false
	if groesse >= 0 and f.get_length() != groesse:
		f.close()
		return false
	var h1 := HashingContext.new()
	var h2 := HashingContext.new()
	h1.start(HashingContext.HASH_SHA1)
	h2.start(HashingContext.HASH_SHA256)
	while not f.eof_reached():
		var b := f.get_buffer(1 << 20)
		if b.is_empty():
			break
		h1.update(b)
		h2.update(b)
	f.close()
	if h1.finish().hex_encode() != sha1:
		return false
	return sha256 == "" or h2.finish().hex_encode() == sha256


static func _schreiben(pfad: String, daten: PackedByteArray) -> void:
	var f := FileAccess.open(pfad, FileAccess.WRITE)
	if f:
		f.store_buffer(daten)
		f.close()
