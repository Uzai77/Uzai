extends RefCounted
## Installierte Spiele aus dem Epic Games Launcher. Uzai liest nur die Dateien, die der Launcher
## selbst auf den PC legt (ohne Internet, ohne Konto): je Spiel ein Manifest (*.item, JSON) unter
## ProgramData\Epic\EpicGamesLauncher\Data\Manifests, dazu die Liste LauncherInstalled.dat.
## Gestartet wird über den Launcher-Link, damit Anmeldung, Kopierschutz und Updates wie gewohnt
## laufen.
## Gekaufte, aber nicht installierte Spiele: Der Launcher legt die Katalogeinträge der eigenen
## Bibliothek als Zwischenspeicher auf den PC (Data\Catalog\catcache.bin, Base64 eines JSON-Arrays
## mit namespace, id, title, categories, mainGameItem, releaseInfo[].appId, keyImages). Uzai liest
## nur diese Datei – keine Epic-Server, keine Anmeldung, keine fremden Client-IDs. Installiert wird
## über den offiziellen Launcher-Link (…?action=install): Der Launcher zeigt seinen eigenen Dialog.

const SU := preload("res://src/library/store_util.gd")
const SUB_MANIFESTS := "Epic/EpicGamesLauncher/Data/Manifests"
const SUB_INSTALLED := "Epic/UnrealEngineLauncher/LauncherInstalled.dat"
const SUB_CATCACHE := "Epic/EpicGamesLauncher/Data/Catalog/catcache.bin"
## Ältere Launcher legten den Katalog unter %LOCALAPPDATA% ab.
const SUB_CATCACHE_LOCAL := "EpicGamesLauncher/Saved/Data/Catalog/catcache.bin"
## Bildarten aus keyImages, beste zuerst (Epics eigene Namen).
const ART_TYPES := {
	"cover": ["DieselGameBoxTall", "OfferImageTall", "Thumbnail", "CodeRedemption_340x440"],
	"hero": ["DieselGameBox", "OfferImageWide", "DieselStoreFrontWide"],
	"wide": ["DieselGameBox", "OfferImageWide", "DieselStoreFrontWide"],
	"logo": ["DieselGameBoxLogo"],
}
## Größe, in der Uzai die Bilder bei Epics Bildserver anfragt (die Originale sind bis 4K groß).
const ART_SIZE := { "cover": "?w=600&h=800&resize=1", "hero": "?w=1920&h=1080&resize=1", "wide": "?w=960&h=540&resize=1", "logo": "" }


## ProgramData (fast immer C:\ProgramData, kann aber woanders liegen).
static func program_data() -> String:
	var pd := OS.get_environment("ProgramData").replace("\\", "/")
	return pd if pd != "" else "C:/ProgramData"


## Ist der Epic Games Launcher installiert? Er legt seine Daten unter ProgramData\Epic ab.
static func launcher_present(pd := "") -> bool:
	var base := pd if pd != "" else program_data()
	return DirAccess.dir_exists_absolute(base.path_join("Epic/EpicGamesLauncher")) or FileAccess.file_exists(installed_file(base))


static func manifest_dir(pd := "") -> String:
	return (pd if pd != "" else program_data()).path_join(SUB_MANIFESTS)


static func installed_file(pd := "") -> String:
	return (pd if pd != "" else program_data()).path_join(SUB_INSTALLED)


## Alle installierten Spiele. dir: Ordner der Manifeste, installed: LauncherInstalled.dat
## (beide für Tests austauschbar). Ohne Ordner ("") die Standardorte.
static func scan(dir := "", installed := "") -> Array:
	var out: Array = []
	var mdir := dir if dir != "" else manifest_dir()
	var da := DirAccess.open(mdir)
	if da == null:
		return out
	var inst := installed if installed != "" else installed_file()
	var known := parse_installed(FileAccess.get_file_as_string(inst) if FileAccess.file_exists(inst) else "")
	var seen := {}
	for f in da.get_files():
		if not f.ends_with(".item"):
			continue
		var g := parse_manifest(FileAccess.get_file_as_string(mdir.path_join(f)), known)
		if g.is_empty() or seen.has(str(g.id)):
			continue
		# Manifest eines Spiels, dessen Ordner es nicht mehr gibt (von Hand gelöscht): nicht zeigen.
		if not DirAccess.dir_exists_absolute(str(g.install_dir)):
			continue
		seen[str(g.id)] = true
		# Das Manifest schreibt der Launcher beim Installieren und Aktualisieren neu.
		g["install_time"] = FileAccess.get_modified_time(mdir.path_join(f))
		out.append(g)
	return out


## Rein: ein Manifest (*.item) → Spiel, {} für Zusatzinhalte, Werkzeuge und halbe Installationen.
## known: AppName → Ordner aus LauncherInstalled.dat (falls im Manifest kein Ordner steht).
static func parse_manifest(text: String, known := {}) -> Dictionary:
	var data: Variant = _json(text)
	if not (data is Dictionary):
		return {}
	var cats: Variant = data.get("AppCategories", [])
	if cats is Array and not (cats as Array).is_empty() and not ("games" in cats):
		return {}
	var app := str(data.get("AppName", ""))
	if app == "" or str(data.get("MainGameAppName", app)) != app:
		return {}
	if bool(data.get("bIsIncompleteInstall", false)):
		return {}
	var dir := str(data.get("InstallLocation", "")).replace("\\", "/").trim_suffix("/")
	if dir == "":
		dir = str(known.get(app, "")).trim_suffix("/")
	# Lokale Manifeste: Ordner nur als gültiger lokaler Pfad (keine Freigabe, kein „..“), die Programmdatei nur darunter.
	dir = SU.norm_path(dir)
	if dir == "":
		return {}
	var exe := str(data.get("LaunchExecutable", "")).replace("\\", "/")
	var title := clean_title(str(data.get("DisplayName", "")))
	var g := {
		"id": "epic:%s" % app,
		"title": title if title != "" else app,
		"system": "epic",
		"source": "epic",
		"epic": { "namespace": str(data.get("CatalogNamespace", "")), "item": str(data.get("CatalogItemId", "")), "app": app },
		"install_dir": dir,
		"installed": true,
	}
	if exe != "" and SU.child(dir, exe) != "":
		g["path"] = SU.child(dir, exe)
	return g


## Rein: LauncherInstalled.dat → { AppName: Ordner }.
static func parse_installed(text: String) -> Dictionary:
	var out := {}
	var data: Variant = _json(text)
	if not (data is Dictionary) or not (data.get("InstallationList") is Array):
		return out
	for e in data.InstallationList:
		if e is Dictionary and str(e.get("AppName", "")) != "":
			out[str(e.AppName)] = str(e.get("InstallLocation", "")).replace("\\", "/")
	return out


## JSON ohne Fehlermeldung im Protokoll (eine kaputte Datei ist kein Programmfehler).
static func _json(text: String) -> Variant:
	if text == "":
		return null
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


## Link, über den der Epic Games Launcher das Spiel startet (still, ohne Bibliotheksfenster).
static func launch_uri(game: Dictionary) -> String:
	var e: Dictionary = game.get("epic", {})
	return "com.epicgames.launcher://apps/%s%%3A%s%%3A%s?action=launch&silent=true" % [
		str(e.get("namespace", "")).uri_encode(), str(e.get("item", "")).uri_encode(), str(e.get("app", "")).uri_encode()]


## Link, über den der Epic Games Launcher ein gekauftes Spiel installiert: Der Launcher öffnet
## seinen Installationsdialog (Speicherort, Größe). "" ohne Katalog-IDs.
static func install_uri(game: Dictionary) -> String:
	var e: Dictionary = game.get("epic", {})
	if str(e.get("namespace", "")) == "" or str(e.get("item", "")) == "" or str(e.get("app", "")) == "":
		return ""
	return "com.epicgames.launcher://apps/%s%%3A%s%%3A%s?action=install" % [
		str(e.namespace).uri_encode(), str(e.item).uri_encode(), str(e.app).uri_encode()]


# --- Gekauft, nicht installiert --------------------------------------------------------------

## Orte der Katalogdatei, wahrscheinlichster zuerst.
static func catcache_paths(pd := "", local := "") -> Array:
	var la := local if local != "" else OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	var out: Array = [(pd if pd != "" else program_data()).path_join(SUB_CATCACHE)]
	if la != "":
		out.append(la.path_join(SUB_CATCACHE_LOCAL))
	return out


## Katalogeinträge aus der ersten lesbaren Datei. ok = false: keine Datei bzw. nicht lesbar.
static func read_catcache(paths: Array) -> Dictionary:
	for p in paths:
		if not FileAccess.file_exists(str(p)):
			continue
		var items := parse_catcache(FileAccess.get_file_as_string(str(p)))
		if items is Array and not (items as Array).is_empty():
			return { "ok": true, "items": items, "path": str(p) }
	return { "ok": false, "items": [], "path": "" }


## Rein: Inhalt von catcache.bin (Base64 eines JSON-Arrays; zur Not auch das JSON selbst) → Array.
static func parse_catcache(text: String) -> Array:
	var t := text.strip_edges()
	if t == "":
		return []
	var json := t
	if not t.begins_with("["):
		var b64 := t.replace("\n", "").replace("\r", "")
		# Nur echtes Base64 dekodieren (sonst meldet Godot einen Fehler im Protokoll).
		if RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$").search(b64) == null:
			return []
		var raw := Marshalls.base64_to_raw(b64)
		if raw.is_empty():
			return []
		json = raw.get_string_from_utf8()
	var data: Variant = _json(json)
	return data if data is Array else []


## Rein: Katalogeinträge → gekaufte Spiele (nicht installiert). Ausgelassen: Zusatzinhalte
## (mainGameItem gesetzt, Kategorie „addons“), Engine, Werkzeuge und Programme ohne Kategorie
## „games“, Einträge ohne App-Namen (die kann der Launcher nicht installieren) und Spiele nur
## für Mac/Mobil.
static func parse_catalog(items: Array) -> Array:
	var out: Array = []
	var seen := {}
	for it in items:
		if not (it is Dictionary):
			continue
		var ns := str(it.get("namespace", ""))
		var id := str(it.get("id", ""))
		if ns == "" or id == "":
			continue
		var main_item: Variant = it.get("mainGameItem")
		if main_item is Dictionary and str((main_item as Dictionary).get("id", "")) != "":
			continue
		var mgl: Variant = it.get("mainGameItemList")
		if mgl is Array and not (mgl as Array).is_empty():
			continue
		var cats := {}
		var cv: Variant = it.get("categories", [])
		if cv is Array:
			for c in cv:
				if c is Dictionary:
					cats[str(c.get("path", ""))] = true
				elif c is String:
					cats[c] = true
		if not cats.has("games") or cats.has("addons") or cats.has("digitalextras"):
			continue
		var app := _app_name(it.get("releaseInfo", []))
		if app == "" or seen.has(app):
			continue
		seen[app] = true
		var title := clean_title(fix_title(str(it.get("title", ""))))
		var g := {
			"id": "epic:%s" % app,
			"title": title if title != "" else app,
			"system": "epic",
			"source": "epic",
			"epic": { "namespace": ns, "item": id, "app": app },
			"installed": false,
			"install_dir": "",
			"path": "",
		}
		var art := pick_art(it.get("keyImages", []))
		if not art.is_empty():
			g["art"] = art
		out.append(g)
	return out


## App-Name (AppName/ArtifactId) für Windows aus releaseInfo; "" wenn es keinen für Windows gibt.
static func _app_name(rel: Variant) -> String:
	if not (rel is Array):
		return ""
	var first := ""
	for r in rel:
		if not (r is Dictionary):
			continue
		var app := str(r.get("appId", ""))
		if app == "":
			continue
		var pf: Variant = r.get("platform", [])
		if pf is Array and not (pf as Array).is_empty():
			if "Windows" in pf or "Win32" in pf:
				return app
			continue
		if first == "":
			first = app
	return first


## Rein: keyImages → { cover, hero, wide, logo } (Adressen auf Epics Bildserver, schon in Größe).
static func pick_art(images: Variant) -> Dictionary:
	var by_type := {}
	if images is Array:
		for k in images:
			if k is Dictionary and str(k.get("url", "")).begins_with("https://") and not by_type.has(str(k.get("type", ""))):
				by_type[str(k.get("type", ""))] = str(k.url)
	var out := {}
	for kind in ART_TYPES:
		for t in ART_TYPES[kind]:
			if by_type.has(t):
				var u := str(by_type[t])
				out[kind] = u + (str(ART_SIZE[kind]) if not u.contains("?") else "")
				break
	return out


## Epics Katalog speichert ™/® als „?“ („Apex Legends?“): ein „?“ direkt am Wortende fällt weg.
static func fix_title(t: String) -> String:
	if not t.contains("?"):
		return t
	# Eigene RegEx je Aufruf (selten, und der Scan läuft im Hilfsthread).
	return RegEx.create_from_string("(?<=\\w)\\?(?=[\\s:,.\\-]|$)").sub(t, "", true)


## Rein: gekaufte ohne die schon installierten (gleicher App-Name oder gleiche Katalog-ID).
## Installierte bekommen dabei die Bilder aus dem Katalog (Cover ohne SteamGridDB-Schlüssel).
static func dedupe(installed: Array, owned: Array) -> Array:
	var by_app := {}
	var by_item := {}
	for g in installed:
		var e: Dictionary = g.get("epic", {})
		if str(e.get("app", "")) != "":
			by_app[str(e.app)] = g
		if str(e.get("item", "")) != "":
			by_item[str(e.item)] = g
	var out: Array = []
	for o in owned:
		var e2: Dictionary = o.get("epic", {})
		var hit: Dictionary = by_app.get(str(e2.get("app", "")), by_item.get(str(e2.get("item", "")), {}))
		if hit.is_empty():
			out.append(o)
		elif o.has("art") and not hit.has("art"):
			hit["art"] = o.art
	return out


## Installierte und (mit owned) gekaufte Spiele in einem Durchgang. Für den Hilfsthread.
## Ergebnis: { games, catalog: true/false (Katalogdatei gefunden) }.
static func scan_all(owned := true, dir := "", installed := "", caches: Array = []) -> Dictionary:
	var inst := scan(dir, installed)
	if not owned:
		return { "games": inst, "catalog": false }
	var cat := read_catcache(caches if not caches.is_empty() else catcache_paths())
	var own := dedupe(inst, parse_catalog(cat.items))
	return { "games": inst + own, "catalog": bool(cat.ok) }


## Günstiger Fingerabdruck des Manifest-Ordners (Dateinamen, Größe, Änderungszeit): ändert er
## sich, hat der Launcher etwas installiert, entfernt oder fertig geladen.
static func manifest_sig(dir := "") -> String:
	var mdir := dir if dir != "" else manifest_dir()
	var parts := PackedStringArray()
	for d in [mdir, mdir.path_join("Pending")]:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			var p := str(d).path_join(f)
			parts.append("%s:%d" % [p, FileAccess.get_modified_time(p)])
	return ",".join(parts)


## App-Namen, die der Launcher gerade lädt (Manifeste unter Manifests\Pending).
static func pending_apps(dir := "") -> Array:
	var out: Array = []
	var pdir := (dir if dir != "" else manifest_dir()).path_join("Pending")
	if not DirAccess.dir_exists_absolute(pdir):
		return out
	for f in DirAccess.get_files_at(pdir):
		if not f.ends_with(".item"):
			continue
		var data: Variant = _json(FileAccess.get_file_as_string(pdir.path_join(f)))
		if data is Dictionary and str(data.get("AppName", "")) != "":
			out.append(str(data.AppName))
	return out


## Titel ohne Markenzeichen und doppelte Leerzeichen („Battlefield™ 2042“ → „Battlefield 2042“).
static func clean_title(t: String) -> String:
	for ch in ["™", "®", "©"]:
		t = t.replace(ch, "")
	t = t.replace("\u00a0", " ").replace("\t", " ")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.strip_edges()
