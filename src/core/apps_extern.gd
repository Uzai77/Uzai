extends RefCounted
## Apps von außen unter „Apps“ (docs/PLAN_APPS.md, Phase 1 und 2): neben den eingebauten Apps
## (Musik, Videos, Filme, Streams, Zimmer) zwei Arten, die Uzai nur startet:
##   store  Store-App (Windows-Store/MSIX: Netflix, Disney+, Prime Video, Crunchyroll …), gestartet
##          über ihre App-Kennung (AppUserModelID) mit dem offiziellen Aktivierungsweg von Windows
##          (IApplicationActivationManager im Helfer) – nie über eine Shell mit Text.
##   prog   Programm, das du selbst gewählt hast (Plex HTPC, Kodi, Moonlight, Steam Link): eine .exe,
##          nur mit Argumentliste gestartet; Shells und Skript-Programme sind gesperrt.
## Gespeichert im Profil (apps.extern, profiles.gd: nicht in SHARED). Jeder Eintrag wird beim Lesen
## neu geprüft – auch einer aus einer Sicherung oder einer von Hand geänderten Datei. Ob ein Eintrag
## auf diesem PC schon einmal bestätigt wurde, steht in cache/apps_ok.json (nie in einer Sicherung,
## backup.gd nimmt cache/ nicht mit): Ein Programm fragt beim ersten Start nach, jeder Eintrag nach
## dem Wiederherstellen einer Sicherung. Der Helfer prüft alles noch einmal selbst (Test-Aumid,
## Test-Program in helper/uzai-helper.ps1) – Uzai allein ist keine Grenze.
## Laufen sie, sind sie für Uzai wie ein Spiel (Launcher, Quelle „app“): Uzai behält die
## Guide-Taste, der Vorhang deckt Start und Rückkehr, im Guide: Weiter, Zurück zu Uzai, Schließen.
## Ohne Windows prüfbar: tests/logic_apps.gd.

const KEY := "apps.extern"
const MAX := 40                 ## so viele eigene Apps höchstens
const KINDS := ["store", "prog"]
const NAME_MAX := 60
const PATH_MAX := 260
const ARGS_MAX := 16
const ARG_MAX := 260
const AUMID_MAX := 180
const ID_LEN := 11              ## „x“ + 10 Zeichen aus SHA-256
const OK_FILE := "cache/apps_ok.json"
const LOGO_DIR := "cache/app_logos"
const LOGO_MAX := 512 * 1024    ## Logo vom Helfer (PNG) höchstens so groß
const LOGO_PX := 1024           ## … und höchstens so viele Pixel je Seite
const STORE_MAX := 400          ## so viele installierte Store-Apps nimmt Uzai aus der Liste an

## Programme, die Uzai nie startet: Shells, Skript-Hosts und Windows-Werkzeuge, die fremden Text als
## Befehl ausführen (auch umbenannt: der Helfer prüft zusätzlich den Originalnamen in der Datei).
const GESPERRT := ["cmd", "powershell", "powershell_ise", "pwsh", "wscript", "cscript", "mshta", "rundll32", "regsvr32",
	"wsl", "wslhost", "bash", "wt", "windowsterminal", "conhost", "openconsole", "msiexec", "msbuild", "installutil",
	"regasm", "regsvcs", "cmstp", "certutil", "bitsadmin", "schtasks", "forfiles", "hh", "wmic", "msxsl", "scriptrunner",
	"explorer", "control", "mmc", "reg", "regedit", "runas", "sc", "at", "pcalua", "presentationhost", "dotnet", "node", "python",
	"pythonw", "py", "pyw", "perl", "ruby", "java", "javaw", "php", "wish", "tclsh", "lua", "deno", "bun"]

## Bekannte Dienste oben in „+ App“ (nur Namen und Suchwörter – Uzai liefert keine eigenen Kennungen,
## es nimmt die App, die Windows für dieses Konto als installiert meldet). Nicht installiert: A öffnet
## die Suche im Microsoft Store.
const KATALOG := [
	{ "name": "Netflix", "match": ["netflix"] },
	{ "name": "Disney+", "match": ["disney"] },
	{ "name": "Prime Video", "match": ["primevideo", "prime video"] },
	{ "name": "Crunchyroll", "match": ["crunchyroll"] },
	{ "name": "Apple TV", "match": ["appletv", "apple tv"] },
	{ "name": "Plex", "match": ["plex"] },
]


# --- Prüfungen (fremde Daten: Typ, Länge, Zeichensatz) -----------------------------------------

## Die Muster der Prüfungen, einmal übersetzt: entries() prüft bei jedem Aufruf jeden Eintrag, und die Oberfläche
## fragt die Liste oft (je Kachel, je Kennung).
static var _RX_AUMID := RegEx.create_from_string("^[A-Za-z0-9.\\-]{3,50}_[a-z0-9]{13}![A-Za-z][A-Za-z0-9]*(\\.[A-Za-z][A-Za-z0-9]*)*\\z")
static var _RX_LAUFWERK := RegEx.create_from_string("^[A-Za-z]:\\\\[^\\\\]")
static var _RX_FASSUNG := RegEx.create_from_string("[0-9._\\-]+$")
static var _RX_KENNUNG := RegEx.create_from_string("^x[0-9a-f]{10}$")
static var _RX_MEDIEN := RegEx.create_from_string("^[A-Za-z0-9 ._()+\\-]{1,80}\\.[Ee][Xx][Ee]\\z")
static var _RX_BASE64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}\\z")

## AppUserModelID einer Store-App: <Paketname>_<Herausgeber-Kennung>!<App-Kennung>
## Paketname 3–50 Zeichen A–Z a–z 0–9 . -, Herausgeber 13 Zeichen a–z 0–9, App-Kennung beginnt mit
## einem Buchstaben, Teile mit Punkt getrennt, höchstens 64 Zeichen (Schema des App-Manifests).
static func valid_aumid(s: Variant) -> bool:
	if not (s is String):
		return false
	var t: String = s
	if t.length() < 18 or t.length() > AUMID_MAX:
		return false
	if _RX_AUMID.search(t) == null:
		return false
	return t.substr(t.find("!") + 1).length() <= 64


## Paketfamilie und App-Kennung aus einer geprüften AUMID ({} wenn ungültig).
static func split_aumid(s: Variant) -> Dictionary:
	if not valid_aumid(s):
		return {}
	var t: String = s
	var i := t.find("!")
	var fam := t.substr(0, i)
	return { "family": fam, "name": fam.substr(0, fam.rfind("_")), "app": t.substr(i + 1) }


## Programm-Pfad in Windows-Form (C:\Ordner\Datei.exe), mit „/“ wie „\“. "" wenn er so nicht taugt.
static func norm_path(p: Variant) -> String:
	if not (p is String):
		return ""
	return (p as String).strip_edges().replace("/", "\\")


## Warum dieser Pfad kein Programm für Uzai ist ("" = in Ordnung). Nur eine .exe auf einem
## Laufwerk (keine Freigabe \\server, kein \\?\), ohne „..“, ohne Steuerzeichen und Sonderzeichen,
## nie eine Shell oder ein Skript-Programm.
static func path_problem(p: Variant) -> String:
	var s := norm_path(p)
	if s == "" or s.length() > PATH_MAX:
		return "Kein gültiger Pfad."
	if _RX_LAUFWERK.search(s) == null:
		return "Nur Programme auf einem Laufwerk dieses PCs."
	for ch in s:
		if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127 or ch in ["\"", "<", ">", "|", "*", "?"]:
			return "Kein gültiger Pfad."
	if s.substr(2).contains(":"):
		return "Kein gültiger Pfad."
	# Leere Teile, „.“/„..“ und Teile mit Punkt oder Leerzeichen am Ende (Windows schneidet sie ab –
	# zwei Schreibweisen für dieselbe Datei) gibt es nicht.
	for part in s.split("\\"):
		if part == "" or part.ends_with(" ") or part.ends_with("."):
			return "Kein gültiger Pfad."
	var file := s.get_file()
	var ext := file.get_extension().to_lower()
	if ext != "exe":
		return "Nur Programme (.exe) – keine Skripte oder Verknüpfungen."
	if blocked_name(file):
		return "Shells und Skript-Programme startet Uzai nicht."
	return ""


## Ist dieser Dateiname (mit oder ohne .exe) eine gesperrte Shell bzw. ein Skript-Programm?
static func blocked_name(file: String) -> bool:
	var stem := file.strip_edges().to_lower()
	if stem.ends_with(".exe"):
		stem = stem.substr(0, stem.length() - 4)
	# Fassungsnummern im Namen (python3, python3.12, pwsh7) zählen mit.
	var bare := _RX_FASSUNG.sub(stem, "")
	return stem in GESPERRT or bare in GESPERRT


## Startparameter: Liste aus Text, jeder ohne Steuerzeichen und nicht leer, höchstens ARGS_MAX.
static func args_ok(a: Variant) -> bool:
	if not (a is Array):
		return false
	var arr: Array = a
	if arr.size() > ARGS_MAX:
		return false
	for x in arr:
		if not (x is String):
			return false
		var t: String = x
		if t == "" or t.length() > ARG_MAX:
			return false
		for ch in t:
			if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127:
				return false
	return true


## Name aus fremder Quelle (Helfer, Datei): ohne Steuerzeichen, getrimmt, höchstens NAME_MAX.
static func clean_name(s: Variant) -> String:
	if not (s is String):
		return ""
	var out := ""
	for ch in (s as String):
		var c := ch.unicode_at(0)
		if c >= 32 and c != 127 and not (c >= 0x200B and c <= 0x200F) and not (c >= 0x202A and c <= 0x202E) and not (c >= 0x2066 and c <= 0x2069):
			out += ch
	out = out.strip_edges()
	return out.substr(0, NAME_MAX).strip_edges()


## Kennung einer eigenen App (Bereich, Reihe, apps.order/hidden): „x“ und 10 Zeichen aus dem
## Fingerabdruck – dieselbe App bekommt dieselbe Kennung (keine Doppelten).
static func make_id(kind: String, key: String) -> String:
	return "x" + ("%s|%s" % [kind, key.to_lower()]).sha256_text().substr(0, ID_LEN - 1)


static func is_ext_id(id: Variant) -> bool:
	if not (id is String) or (id as String).length() != ID_LEN or not (id as String).begins_with("x"):
		return false
	return _RX_KENNUNG.search(id) != null


## Ist der gespeicherte Eintrag in Ordnung? (Typ, Länge, Zeichensatz, Kennung passt zum Inhalt.)
static func entry_ok(e: Variant) -> bool:
	if not (e is Dictionary):
		return false
	var d: Dictionary = e
	var kind := str(d.get("kind", ""))
	if not (kind in KINDS) or clean_name(d.get("name", "")) == "" or not (d.get("name") is String):
		return false
	if kind == "store":
		return valid_aumid(d.get("aumid")) and str(d.get("id", "")) == make_id(kind, str(d.aumid))
	if path_problem(d.get("path")) != "" or not args_ok(d.get("args", [])):
		return false
	return str(d.get("id", "")) == make_id(kind, norm_path(d.path))


# --- Gespeicherte Apps -----------------------------------------------------------------------

## Alle eigenen Apps dieses Profils, die die Prüfung bestehen (in der Reihenfolge des Hinzufügens).
static func entries() -> Array:
	var raw: Variant = Config.get_value(KEY, [])
	var out: Array = []
	var seen := {}
	if not (raw is Array):
		return out
	for e in raw:
		if out.size() >= MAX:
			break
		if entry_ok(e) and not seen.has(str(e.id)):
			seen[str(e.id)] = true
			out.append(_tidy(e))
	return out


## Nur die bekannten Felder, sauber (was sonst noch in der Datei steht, fällt weg).
static func _tidy(e: Dictionary) -> Dictionary:
	var d := { "id": str(e.id), "kind": str(e.kind), "name": clean_name(e.name) }
	if d.kind == "store":
		d["aumid"] = str(e.aumid)
	else:
		d["path"] = norm_path(e.path)
		d["args"] = (e.get("args", []) as Array).duplicate()
	return d


static func get_entry(id: String) -> Dictionary:
	for e in entries():
		if str(e.id) == id:
			return e
	return {}


## Neue Store-App: { ok, id, why } – ok auch, wenn es sie schon gibt (dann ihre Kennung).
## Hinzugefügt aus der Liste, die Windows liefert, gilt sie auf diesem PC als bestätigt.
static func add_store(aumid: String, name: String) -> Dictionary:
	if not valid_aumid(aumid):
		return { "ok": false, "why": "Ungültige App-Kennung." }
	var n := clean_name(name)
	if n == "":
		n = str(split_aumid(aumid).name)
	var e := { "id": make_id("store", aumid), "kind": "store", "name": n, "aumid": aumid }
	var r := _add(e)
	if bool(r.ok):
		confirm(e)
	return r


## Neues Programm: { ok, id, why }. Bestätigt wird es erst beim ersten Start.
static func add_prog(path: String, name := "", args: Array = []) -> Dictionary:
	var why := path_problem(path)
	if why != "":
		return { "ok": false, "why": why }
	if not args_ok(args):
		return { "ok": false, "why": "Ungültige Startparameter." }
	var p := norm_path(path)
	var n := clean_name(name)
	if n == "":
		n = clean_name(p.get_file().get_basename())
	var e := { "id": make_id("prog", p), "kind": "prog", "name": n, "path": p, "args": args.duplicate() }
	return _add(e)


static func _add(e: Dictionary) -> Dictionary:
	if not entry_ok(e):
		return { "ok": false, "why": "Ungültige App." }
	var list := entries()
	for x in list:
		if str(x.id) == str(e.id):
			return { "ok": true, "id": str(e.id), "neu": false }
	if list.size() >= MAX:
		return { "ok": false, "why": "Höchstens %d eigene Apps." % MAX }
	list.append(e)
	Config.set_value(KEY, list)
	return { "ok": true, "id": str(e.id), "neu": true }


## Entfernen: aus der Liste, aus Reihenfolge und Ausgeblendetem; die Bestätigung bleibt nicht.
static func remove(id: String) -> bool:
	var list := entries()
	var keep := list.filter(func(x: Dictionary) -> bool: return str(x.id) != id)
	if keep.size() == list.size():
		return false
	var gone: Dictionary = list.filter(func(x: Dictionary) -> bool: return str(x.id) == id)[0]
	unconfirm(gone)
	for k in ["apps.order", "apps.hidden"]:
		var arr: Array = (Config.get_value(k, []) as Array).duplicate()
		if arr.has(id):
			arr.erase(id)
			Config.set_value(k, arr)
	Config.set_value(KEY, keep)
	var logo := logo_path(id)
	if logo != "":
		DirAccess.remove_absolute(logo)
	return true


# --- Bestätigung auf diesem PC -----------------------------------------------------------------

## Fingerabdruck dessen, was gestartet würde (Art, Kennung bzw. Pfad und Parameter).
static func fingerprint(e: Dictionary) -> String:
	if str(e.get("kind", "")) == "store":
		return ("store|" + str(e.get("aumid", ""))).sha256_text()
	return ("prog|%s|%s" % [norm_path(e.get("path", "")).to_lower(), JSON.stringify(e.get("args", []))]).sha256_text()


static func _ok_list() -> Array:
	var v: Variant = Config.read_json(Config.path(OK_FILE), [])
	if not (v is Array):
		return []
	return (v as Array).filter(func(x: Variant) -> bool: return x is String and (x as String).length() == 64).slice(0, 500)


static func confirmed(e: Dictionary) -> bool:
	return _ok_list().has(fingerprint(e))


static func confirm(e: Dictionary) -> void:
	var l := _ok_list()
	var f := fingerprint(e)
	if l.has(f):
		return
	l.append(f)
	DirAccess.make_dir_recursive_absolute(Config.path(OK_FILE).get_base_dir())
	Config.write_json(Config.path(OK_FILE), l)


static func unconfirm(e: Dictionary) -> void:
	var l := _ok_list()
	var f := fingerprint(e)
	if not l.has(f):
		return
	l.erase(f)
	Config.write_json(Config.path(OK_FILE), l)


## Muss Uzai vor dem Start fragen? Programme beim ersten Start, alles nach einer Sicherung.
static func needs_ask(e: Dictionary) -> bool:
	return not confirmed(e)


# --- Start, Kopf, Logo -------------------------------------------------------------------------

## Was der Launcher bekommt (wie ein Spiel, Quelle „app“). Kein Eintrag der Bibliothek: Spielzeit,
## Erfolge, Discord-Status und „Gerade gespielt“ gibt es dafür nicht.
static func launch_game(e: Dictionary) -> Dictionary:
	var g := { "id": "app:" + str(e.id), "title": str(e.name), "source": "app", "app": e.duplicate(true), "installed": true }
	var logo := logo_path(str(e.id))
	if logo != "":
		g["images"] = { "logo": logo }
	return g


## Kennung der Windows-Mediensitzung dieser App: bei Store-Apps die AUMID, bei Programmen der
## Dateiname (so melden sich Win32-Programme meist bei Windows).
static func media_id(e: Dictionary) -> String:
	if str(e.get("kind", "")) == "store":
		return str(e.get("aumid", ""))
	return norm_path(e.get("path", "")).get_file()


## Prüfung der Kennung für „app-media“ (wie im Helfer): AUMID oder Name einer .exe.
static func valid_media_id(s: Variant) -> bool:
	if valid_aumid(s):
		return true
	return s is String and _RX_MEDIEN.search(s) != null


static func logo_path(id: String) -> String:
	if not is_ext_id(id):
		return ""
	var p := Config.path(LOGO_DIR).path_join(id + ".png")
	return p if FileAccess.file_exists(p) else ""


## Logo vom Helfer (PNG als Base64) prüfen, neu kodiert ablegen. true: gespeichert.
static func save_logo(id: String, b64: Variant) -> bool:
	if not is_ext_id(id) or not (b64 is String) or (b64 as String).length() > LOGO_MAX * 4 / 3 + 8 or (b64 as String).length() % 4 != 0:
		return false
	if _RX_BASE64.search(b64) == null:
		return false
	var raw := Marshalls.base64_to_raw(b64)
	if raw.is_empty() or raw.size() > LOGO_MAX or raw.slice(0, 8) != PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return false
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK or img.get_width() < 8 or img.get_height() < 8 or img.get_width() > LOGO_PX or img.get_height() > LOGO_PX:
		return false
	DirAccess.make_dir_recursive_absolute(Config.path(LOGO_DIR))
	return img.save_png(Config.path(LOGO_DIR).path_join(id + ".png")) == OK


# --- Liste der installierten Store-Apps (Helfer „store-apps“) -------------------------------------

## Antwort des Helfers prüfen: [{ aumid, name }], nach Namen sortiert, ohne Doppelte.
static func clean_store_list(raw: Variant) -> Array:
	var out: Array = []
	var seen := {}
	var list: Variant = (raw as Dictionary).get("apps", []) if raw is Dictionary else []
	if not (list is Array):
		return out
	for a in list:
		if out.size() >= STORE_MAX:
			break
		if not (a is Dictionary) or not valid_aumid((a as Dictionary).get("aumid")):
			continue
		var id := str(a.aumid)
		if seen.has(id.to_lower()):
			continue
		var n := clean_name(a.get("name", ""))
		if n == "" or n.begins_with("ms-resource:"):
			n = str(split_aumid(id).name)
		seen[id.to_lower()] = true
		out.append({ "aumid": id, "name": n })
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x.name).naturalnocasecmp_to(str(y.name)) < 0)
	return out


## Passt eine installierte Store-App zu einem Dienst des Katalogs?
static func katalog_match(k: Dictionary, app: Dictionary) -> bool:
	var hay := (str(app.get("name", "")) + " " + str(split_aumid(app.get("aumid", "")).get("name", ""))).to_lower()
	for w in k.get("match", []):
		if hay.contains(str(w)):
			return true
	return false


## Katalog oben in „+ App“: je Dienst die installierte App ({} = nicht installiert).
static func katalog_rows(installed: Array) -> Array:
	var out: Array = []
	for k in KATALOG:
		var hit: Dictionary = {}
		for a in installed:
			if katalog_match(k, a):
				hit = a
				break
		out.append({ "name": str(k.name), "app": hit })
	return out


## Store-Suche für einen Dienst, der nicht installiert ist (feste Form, nur Name aus dem Katalog).
static func store_search_url(name: String) -> String:
	return "ms-windows-store://search/?query=" + name.uri_encode()


## Liste für Vorschau und Tests ohne Windows.
static func demo_store_apps() -> Array:
	return clean_store_list({ "apps": [
		{ "aumid": "4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "name": "Netflix" },
		{ "aumid": "Disney.37853FC22B2CE_6rarf9sa4v8jt!App", "name": "Disney+" },
		{ "aumid": "AmazonVideo.PrimeVideo_pwbj9vvecjh7j!App", "name": "Prime Video for Windows" },
		{ "aumid": "Microsoft.ZuneVideo_8wekyb3d8bbwe!Microsoft.ZuneVideo", "name": "Filme & TV" },
		{ "aumid": "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App", "name": "Rechner" },
		{ "aumid": "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", "name": "Spotify" },
	] })
