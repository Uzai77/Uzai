extends Node
## Retro ohne Einrichtung: Emulatoren und RetroArch-Kerne laden, prüfen, entpacken und eintragen –
## nur nach Zustimmung (src/ui/layers/retro_einrichten.gd), nur von den festen Quellen aus
## src/core/retro_auto.gd. Ablauf je Emulator:
##   1. Angebot frisch holen (GitHub-API bzw. feste Fassung) und streng prüfen.
##   2. Weiterleitungen selbst auflösen (HEAD, jede einzeln gegen die Liste geprüft), dann laden –
##      ohne weitere Weiterleitung, mit Größengrenze, abbrechbar.
##   3. SHA-256 vergleichen; passt sie nicht, wird gelöscht und nichts entpackt.
##   4. Inhalt prüfen (ZIP: eigener Leser; 7z: Liste von Windows-tar), dann in einen eigenen
##      Zwischenordner entpacken und dort noch einmal nachsehen (keine Verknüpfungen, Größe).
##   5. In Uzais Ordner „emulatoren\<id>“ übernehmen (eigene Dateien darin – Spielstände, BIOS,
##      Einstellungen – bleiben), Grundeinstellungen nur anlegen, wo es noch keine gibt, Pfad
##      eintragen. Ausgeführt wird dabei nichts; den Emulator startet erst ein Spiel.
## Ein Knoten unter Net, damit ein Auftrag weiterläuft, wenn die Seite zugeht.

signal changed(id: String)

const RA := preload("res://src/core/retro_auto.gd")
const Zip := preload("res://src/core/zip_pruefung.gd")
const Sicher := preload("res://src/core/sicher.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const SELF := "res://src/core/retro_laden.gd"
const ANGEBOT_FRISCH_MS := 600000
const PLATZ_REST := 256 * 1024 * 1024   ## so viel bleibt auf dem Laufwerk mindestens frei

## Vorführung (--demo) und Proben: ohne Netz, mit echten Namen und Größen der Pakete.
const DEMO_RELEASES := {
	"duckstation": { "tag_name": "latest", "published_at": "2026-10-12T08:00:00Z", "assets": [{ "name": "duckstation-windows-x64-release.zip",
		"size": 73295462, "digest": "sha256:c7b126b98c19a87fa5f7068adc26d8f59d8e3266cd7ec5d257d039c8984fbbb8",
		"browser_download_url": "https://github.com/stenzek/duckstation/releases/download/latest/duckstation-windows-x64-release.zip" }] },
	"pcsx2": { "tag_name": "v2.8.2", "assets": [{ "name": "pcsx2-v2.8.2-windows-x64-Qt.7z", "size": 25690112,
		"digest": "sha256:7dfc829ca1994cc1045ac49f05e39b6cf968b72e6a374c40e05c2a2b4ac200b4",
		"browser_download_url": "https://github.com/PCSX2/pcsx2/releases/download/v2.8.2/pcsx2-v2.8.2-windows-x64-Qt.7z" }] },
	"ppsspp": { "tag_name": "v1.20.4", "assets": [{ "name": "PPSSPP-v1.20.4-Windows-x64.zip", "size": 20342374,
		"digest": "sha256:fbc9cd2f5131b159a92424e5c458c35ce43ba603cdded64dfc98e4bd4f17ff93",
		"browser_download_url": "https://github.com/hrydgard/ppsspp/releases/download/v1.20.4/PPSSPP-v1.20.4-Windows-x64.zip" }] },
	"melonds": { "tag_name": "1.1", "assets": [{ "name": "melonDS-1.1-windows-x86_64.zip", "size": 19503513,
		"digest": "sha256:9f3f8a244103be20b5b657af5b0ed1b2a66bb20a7181476a6d294c9a53d4f8c8",
		"browser_download_url": "https://github.com/melonDS-emu/melonDS/releases/download/1.1/melonDS-1.1-windows-x86_64.zip" }] },
}

static var _inst: Node

## Aufträge: id ("pcsx2", "kern:mgba") → { phase, text, got, total, fehler, stop, systeme }.
## phase: wartet | laeuft | fertig | fehler | abgebrochen.
var auftraege := {}
var _schlange: Array = []
var _laeuft := false
var _angebote := {}
var _index := ""
var demo_bereit := {}          ## Vorführung: was „eingerichtet“ ist (Emulator-ID bzw. „kern:…“)


static func inst() -> Node:
	if _inst == null or not is_instance_valid(_inst):
		_inst = load(SELF).new()
		_inst.name = "RetroLaden"
		Net.add_child(_inst)
	return _inst


# --- Orte und Zustand --------------------------------------------------------------------------

func ordner() -> String:
	return Config.shared_path("emulatoren")


func emu_dir(id: String) -> String:
	return ordner().path_join(id)


static func win(p: String) -> String:
	return p.replace("/", "\\") if Config.is_windows() else p


## Von Uzai eingerichtet: { fassung, kennung, datei, zeit, kerne } oder {}.
func installiert(id: String) -> Dictionary:
	var u: Variant = Config.emulator(id).get("uzai", {})
	return u if u is Dictionary else {}


func exe_da(exe: String) -> bool:
	if Library.demo:
		return demo_bereit.has(exe)
	return exe != "" and FileAccess.file_exists(exe)


func kern_da(e: Dictionary, kern: String) -> bool:
	if Library.demo:
		return demo_bereit.has("kern:" + kern)
	var exe := str(e.get("exe", ""))
	return exe != "" and FileAccess.file_exists(exe.get_base_dir().path_join("cores/%s_libretro.dll" % kern))


## Spiele je System aus der Bibliothek, dazu extra (gefundene Ordner der Einrichtung).
static func spiele_je_system(extra: Dictionary = {}) -> Dictionary:
	var out := {}
	for g in Library.games:
		if str(g.get("source", "")) == "rom" and not bool(g.get("hidden", false)):
			var s := str(g.get("system", ""))
			out[s] = int(out.get(s, 0)) + 1
	for k in extra.keys():
		out[k] = maxi(int(out.get(k, 0)), int(extra[k]))
	return out


## Lage aller Systeme mit Spielen (RA.erkennen mit Uzais echten Daten). extra: siehe oben;
## schon_da: Emulator-IDs, die gleich eingetragen werden (Funde der Einrichtung).
func lage(extra: Dictionary = {}, schon_da: Array = []) -> Array:
	return RA.erkennen(spiele_je_system(extra), Config.systems(), func(id: String) -> Dictionary: return Config.emulator(id),
		func(exe: String) -> bool: return exe_da(exe) or schon_da.any(func(x: String) -> bool: return str(Config.emulator(x).get("exe", "")) == exe),
		kern_da, ordner()).map(func(r: Dictionary) -> Dictionary:
			if schon_da.has(str(r.emulator)) and str(r.grund) == "" and str(r.kern) == "":
				r.bereit = true
				r.angebot = ""
			return r)


func beschaeftigt() -> bool:
	return _laeuft


# --- Angebote ------------------------------------------------------------------------------

## Angebot für einen Emulator (frisch: nicht aus dem Zwischenspeicher). { ok, error, … } wie
## RA.angebot_github / RA.angebot_fest.
func angebot(id: String, frisch := false) -> Dictionary:
	var c: Variant = _angebote.get(id)
	if not frisch and c is Dictionary and Time.get_ticks_msec() - int(c.t) < ANGEBOT_FRISCH_MS:
		return c.a
	var e := RA.eintrag(id)
	var a := {}
	if e.is_empty():
		a = RA._nein("Unbekannter Emulator.")
	elif str(e.quelle) == "github":
		if Library.demo:
			a = RA.angebot_github(id, DEMO_RELEASES.get(id, {}))
		else:
			var r := await _json(RA.GITHUB_API % str(e.repo))
			a = RA.angebot_github(id, r.data) if bool(r.ok) else RA._nein(_netzfehler(int(r.code)))
	else:
		a = RA.angebot_fest(id, -1 if Library.demo else await _groesse(str(e.url)))
	if bool(a.get("ok", false)):
		_angebote[id] = { "t": Time.get_ticks_msec(), "a": a }
	return a


func _netzfehler(code: int) -> String:
	if code == 403 or code == 429:
		return "GitHub lässt gerade keine Abfrage zu (zu viele in kurzer Zeit). Bitte in einer Stunde noch einmal."
	if code == 404:
		return "Die offizielle Quelle kennt keine Fassung für Windows."
	return "Die offizielle Quelle ist gerade nicht erreichbar."


# --- Einrichten ----------------------------------------------------------------------------

## Nach Zustimmung: Emulatoren (ids) und Kerne in die Warteschlange. systeme: { id → [System-IDs] }
## wie in RA.plan – diese Systeme bekommen den Emulator danach als Standard.
func einrichten(ids: Array, kerne: Array, systeme: Dictionary) -> void:
	for id in ids:
		_rein(str(id), systeme.get(id, []))
	for k in kerne:
		var sys: Array = []
		for sid in systeme.get("retroarch", []):
			if RA.KERNE.get(sid, "") == k or str(Config.system(str(sid)).get("core", "")) == k:
				sys.append(sid)
		_rein("kern:" + str(k), sys)
	if not _laeuft:
		_lauf()


func _rein(key: String, systeme: Array) -> void:
	if auftraege.has(key) and str(auftraege[key].phase) in ["wartet", "laeuft"]:
		return
	auftraege[key] = { "phase": "wartet", "text": "Wartet …", "got": 0, "total": 0, "fehler": "", "stop": { "stop": false }, "systeme": systeme,
		"ok": false }
	_schlange.append(key)
	changed.emit(key)


func abbrechen(key: String) -> void:
	var a: Variant = auftraege.get(key)
	if not (a is Dictionary) or not (str(a.phase) in ["wartet", "laeuft"]):
		return
	(a.stop as Dictionary)["stop"] = true
	if str(a.phase) == "wartet":
		_schlange.erase(key)
		_ende(key, "abgebrochen", "Abgebrochen")


func _lauf() -> void:
	_laeuft = true
	while not _schlange.is_empty():
		var key: String = _schlange.pop_front()
		var a: Dictionary = auftraege[key]
		a.phase = "laeuft"
		changed.emit(key)
		var why := ""
		if Library.demo:
			why = await _demo(key)
		elif key.begins_with("kern:"):
			why = await _kern(key)
		else:
			why = await _emu(key)
		if bool(a.stop.stop):
			_ende(key, "abgebrochen", "Abgebrochen – nichts ist liegen geblieben.")
		elif why != "":
			_ende(key, "fehler", why)
		elif not bool(a.get("ok", false)):
			# Bricht der Lauf mit einem Skriptfehler ab, kommt hier der Ersatzwert "" an (gemessen) – das hieße „kein
			# Fehler“. Fertig ist ein Auftrag nur, wenn er sein Ende erreicht und es selbst vermerkt hat.
			_ende(key, "fehler", "Das Einrichten ist unerwartet abgebrochen. Bitte noch einmal versuchen.")
		else:
			_ende(key, "fertig", "Bereit")
	_laeuft = false


func _ende(key: String, phase: String, text: String) -> void:
	var a: Dictionary = auftraege[key]
	a.phase = phase
	a.text = text
	a.fehler = text if phase == "fehler" else ""
	changed.emit(key)


func _stand(key: String, text: String, got := -1, total := -1) -> void:
	var a: Dictionary = auftraege[key]
	a.text = text
	if got >= 0:
		a.got = got
	if total >= 0:
		a.total = total
	changed.emit(key)


## Vorführung: dieselben Schritte, ohne Netz und ohne Dateien.
func _demo(key: String) -> String:
	var a: Dictionary = auftraege[key]
	var an: Dictionary = (_angebote.get(key, {}) as Dictionary).get("a", {})
	var total := int(an.get("groesse", 0)) if int(an.get("groesse", 0)) > 0 else (6 if key.begins_with("kern:") else 48) * RA.MB
	for i in 30:
		if bool(a.stop.stop):
			return ""
		_stand(key, "Lädt …", int(total * (i + 1) / 30.0), total)
		await get_tree().create_timer(0.07).timeout
	for t in ["Prüft die Prüfsumme …", "Entpackt …", "Richtet ein …"]:
		if bool(a.stop.stop):
			return ""
		_stand(key, t)
		await get_tree().create_timer(0.35).timeout
	if key.begins_with("kern:"):
		demo_bereit[key] = true
	else:
		var exe := "C:/Uzai/emulatoren/%s/%s" % [key, str(RA.eintrag(key).exe[0])]
		demo_bereit[exe] = true
		Config.set_emulator(key, "exe", exe)
		Config.set_emulator(key, "uzai", { "fassung": str(an.get("fassung", "")), "kennung": str(an.get("kennung", "")) })
		for sid in a.systeme:
			Config.set_system(str(sid), "emulator", key)
	a["ok"] = true
	return ""


func _emu(id: String) -> String:
	var job: Dictionary = auftraege[id]
	var e := RA.eintrag(id)
	_stand(id, "Fragt die offizielle Quelle …")
	var an := await angebot(id, true)
	if not bool(an.get("ok", false)):
		return str(an.error)
	if bool(job.stop.stop):
		return ""
	var laden := ordner().path_join(".laden")
	var neu := ordner().path_join(".neu_" + id)
	DirAccess.make_dir_recursive_absolute(laden)
	var archiv := laden.path_join("%s.%s" % [id, str(an.archiv)])
	var groesse := int(an.groesse)
	if not _platz(ordner(), maxi(groesse, 0) * 5):
		return "Auf dem Laufwerk ist nicht genug Platz frei."
	var why := await _laden(id, str(an.url), archiv, groesse if groesse > 0 else int(e.get("max_mb", 100)) * RA.MB)
	if why != "" or bool(job.stop.stop):
		return why
	_stand(id, "Prüft die Prüfsumme …")
	var sha := str(await _im_faden(func() -> Variant: return FileAccess.get_sha256(archiv).to_lower()))
	if sha != str(an.sha256):
		_weg(archiv)
		return "Die Prüfsumme stimmt nicht – Uzai hat nichts entpackt und die Datei gelöscht."
	_stand(id, "Prüft den Inhalt …")
	_weg(neu)
	DirAccess.make_dir_recursive_absolute(neu)
	why = await _auspacken(id, archiv, neu)
	_weg(archiv)
	if why == "" and not bool(job.stop.stop):
		why = str(await _im_faden(func() -> Variant: return _nachpruefen(neu)))
	var root := _finde_exe(neu, e.exe) if why == "" else ""
	if why == "" and root == "" and not bool(job.stop.stop):
		why = "Im Paket fehlt die Programmdatei – Uzai hat nichts eingetragen."
	if why != "" or bool(job.stop.stop):
		_weg(neu)
		return why
	_stand(id, "Richtet ein …")
	var ziel := emu_dir(id)
	DirAccess.make_dir_recursive_absolute(ziel)
	if not _uebernehmen(root.get_base_dir(), ziel):
		_weg(neu)
		return "Die Dateien ließen sich nicht in Uzais Ordner legen."
	_weg(neu)
	_grund(id, ziel)
	var exe := ziel.path_join(root.get_file())
	Config.set_emulator(id, "exe", exe)
	# RetroArch-Systeme stellt erst ihr Kern um – ohne Kern startete dort kein Spiel.
	if id != "retroarch":
		for sid in job.systeme:
			Config.set_system(str(sid), "emulator", id)
	var alt := installiert(id)
	Config.set_emulator(id, "uzai", { "fassung": str(an.fassung), "kennung": str(an.kennung), "datei": str(an.datei),
		"zeit": int(Time.get_unix_time_from_system()), "kerne": alt.get("kerne", {}) })
	job["ok"] = true
	return ""


func _kern(key: String) -> String:
	var job: Dictionary = auftraege[key]
	var kern := key.trim_prefix("kern:")
	var url := RA.kern_url(kern)
	var exe := str(Config.emulator("retroarch").get("exe", ""))
	if url == "":
		return "Diesen Kern bietet Uzai nicht an."
	if exe == "" or not FileAccess.file_exists(exe) or not exe.begins_with(emu_dir("retroarch") + "/"):
		return "Kerne legt Uzai nur in sein eigenes RetroArch – das fehlt noch."
	_stand(key, "Fragt den Buildbot …")
	if _index == "":
		var r := await Net.request(_netz(RA.KERN_INDEX), PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "api", RA.MAX_INDEX, false)
		_index = (r.body as PackedByteArray).get_string_from_utf8() if bool(r.ok) else ""
	var crc := RA.kern_crc(_index, kern)
	if crc < 0:
		return "Der Buildbot nennt für diesen Kern keine Prüfsumme – Uzai lädt ihn nicht."
	var laden := ordner().path_join(".laden")
	DirAccess.make_dir_recursive_absolute(laden)
	var zip := laden.path_join(kern + ".zip")
	var why := await _laden(key, url, zip, RA.MAX_KERN)
	if why != "" or bool(job.stop.stop):
		return why
	_stand(key, "Prüft die Prüfsumme …")
	var dll := kern + "_libretro.dll"
	var ziel := emu_dir("retroarch").path_join("cores")
	why = str(await _im_faden(func() -> Variant: return _kern_auspacken(zip, ziel, dll, crc, job.stop)))
	_weg(zip)
	if why != "":
		return why
	for sid in job.systeme:
		Config.set_system(str(sid), "emulator", "retroarch")
		Config.set_system(str(sid), "core", kern)
	var u := installiert("retroarch").duplicate(true)
	var kerne: Dictionary = (u.get("kerne", {}) as Dictionary).duplicate()
	kerne[kern] = { "crc": crc, "zeit": int(Time.get_unix_time_from_system()) }
	u["kerne"] = kerne
	Config.set_emulator("retroarch", "uzai", u)
	job["ok"] = true
	return ""


## Im Faden: Kern-Paket prüfen (genau eine Datei mit festem Namen, CRC32 laut Buildbot – für das
## Paket oder den Kern darin) und den Kern über eine .neu-Datei ablegen.
static func _kern_auspacken(zip: String, ziel: String, dll: String, crc: int, stop: Dictionary) -> String:
	var b := FileAccess.get_file_as_bytes(zip)
	var idx := RA.zip_index(b, [dll])
	if not bool(idx.ok):
		return str(idx.error)
	var e: Dictionary = idx.entries[0]
	if int(e.crc) != crc and Zip.crc32(b) != crc:
		return "Die Prüfsumme stimmt nicht – Uzai hat den Kern nicht übernommen."
	if bool(stop.get("stop", false)):
		return ""
	var data: Variant = Zip.entpacken(b, e)
	if data == null:
		return "Das Paket ist beschädigt."
	DirAccess.make_dir_recursive_absolute(ziel)
	var tmp := ziel.path_join(dll + ".neu")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Der Kern ließ sich nicht speichern."
	f.store_buffer(data)
	f.close()
	if FileAccess.file_exists(ziel.path_join(dll)):
		DirAccess.remove_absolute(ziel.path_join(dll))
	return "" if DirAccess.rename_absolute(tmp, ziel.path_join(dll)) == OK else "Der Kern ließ sich nicht speichern."


# --- Netz ----------------------------------------------------------------------------------

## Proben: alle festen Hosts auf einen nachgebauten Server (UZAI_RETRO_FAKE, nur zusammen mit
## UZAI_TEST_LOOPBACK=1). Geprüft wird immer die echte https-Adresse.
static func _netz(url: String) -> String:
	var fake := Config.probe_env("UZAI_RETRO_FAKE")
	if fake == "" or Config.probe_env("UZAI_TEST_LOOPBACK") != "1" or not url.begins_with("https://"):
		return url
	return fake.trim_suffix("/") + "/" + url.substr(8)


func _json(url: String) -> Dictionary:
	if not RA.quelle_ok(url):
		return { "ok": false, "code": 0, "data": null }
	var r := await Net.request(_netz(url), PackedStringArray(["Accept: application/vnd.github+json"]), HTTPClient.METHOD_GET, "", 20.0, "api", RA.MAX_RELEASE,
			false)
	var out := Net._decode(r)
	out["ok"] = bool(r.ok) and out.data is Dictionary
	return out


## Größe laut Server (HEAD), -1 wenn unbekannt.
func _groesse(url: String) -> int:
	if not RA.quelle_ok(url):
		return -1
	var r := await Net.request(_netz(url), PackedStringArray(), HTTPClient.METHOD_HEAD, "", 15.0, "api", 0, false)
	var n := Net.header(r, "content-length")
	return n.to_int() if bool(r.ok) and n.is_valid_int() else -1


## Weiterleitungen selbst auflösen: jede einzeln gegen die Liste, höchstens vier. "" = nicht erlaubt.
func _aufloesen(url: String) -> String:
	if not RA.quelle_ok(url):
		return ""
	var cur := url
	for hop in Sicher.MAX_HOPS:
		var r := await Net.request(_netz(cur), PackedStringArray(), HTTPClient.METHOD_HEAD, "", 20.0, "api", 0, false)
		var code := int(r.code)
		if code in [301, 302, 303, 307, 308]:
			var nach := Sicher.redirect_target(cur, Net.header(r, "location"))
			if not RA.weiterleitung_ok(cur, nach):
				return ""
			cur = nach
			continue
		# Manche Dateiserver nehmen keine HEAD-Anfrage an; dann gilt die zuletzt geprüfte Adresse.
		return cur if (code >= 200 and code < 300) or code == 403 or code == 405 else ""
	return ""


func _laden(key: String, url: String, ziel: String, grenze: int) -> String:
	var job: Dictionary = auftraege[key]
	var final := await _aufloesen(url)
	if final == "":
		return "Die offizielle Quelle leitet woandershin weiter – Uzai lädt nichts."
	if bool(job.stop.stop):
		return ""
	_stand(key, "Lädt …", 0, grenze)
	var ok: bool = await Net.download_big(_netz(final), ziel, func(got: int, total: int) -> void:
		_stand(key, "Lädt …", got, total if total > 0 else grenze)
	, grenze, false, job.stop)
	if bool(job.stop.stop):
		_weg(ziel)
		return ""
	return "" if ok else "Der Download ging nicht (abgebrochen, zu groß oder die Quelle antwortet nicht)."


# --- Entpacken -------------------------------------------------------------------------------

func _auspacken(id: String, archiv: String, ziel: String) -> String:
	var job: Dictionary = auftraege[id]
	if archiv.ends_with(".zip"):
		_stand(id, "Entpackt …")
		return str(await _im_faden(func() -> Variant: return _zip_auspacken(archiv, ziel, job.stop)))
	if not Config.is_windows():
		return "7z-Pakete entpackt Uzai mit dem tar von Windows – das gibt es nur dort."
	var tar: String = YouTube.windows_tar()       # aus dem Systemordner, nie über den Suchpfad
	if tar == "":
		return "Das Entpack-Programm von Windows wurde nicht gefunden. Den Emulator dann selbst entpacken und unter Einstellungen → Emulatoren eintragen."
	var l: Dictionary = await YouTube.exec(tar, PackedStringArray(["-tvf", win(archiv)]), 120.0, job.stop)
	if bool(job.stop.stop):
		return ""
	if not bool(l.get("ok", false)):
		return "Dieses Windows kann .7z-Pakete nicht öffnen (ab Windows 11 23H2). Den Emulator dann selbst entpacken und unter Einstellungen → Emulatoren eintragen."
	var liste := RA.tar_liste(str(l.text))
	if not bool(liste.ok):
		return str(liste.error)
	if not _platz(ziel, int(liste.total)):
		return "Auf dem Laufwerk ist nicht genug Platz frei."
	_stand(id, "Entpackt …")
	var x: Dictionary = await YouTube.exec(tar, PackedStringArray(["-xf", win(archiv), "-C", win(ziel)]), 600.0, job.stop)
	if bool(job.stop.stop):
		return ""
	return "" if bool(x.get("ok", false)) else "Das Paket ließ sich nicht entpacken."


## Im Faden: ZIP prüfen und Datei für Datei schreiben (Deflate prüft seine CRC selbst).
static func _zip_auspacken(archiv: String, ziel: String, stop: Dictionary) -> String:
	if FileAccess.get_size(archiv) > RA.MAX_ARCHIV:
		return "Das Paket ist zu groß."
	var b := FileAccess.get_file_as_bytes(archiv)
	var idx := RA.zip_index(b)
	if not bool(idx.ok):
		return str(idx.error)
	if not _platz(ziel, int(idx.total)):
		return "Auf dem Laufwerk ist nicht genug Platz frei."
	for d in idx.dirs:
		DirAccess.make_dir_recursive_absolute(ziel.path_join(str(d)))
	for e in idx.entries:
		if bool(stop.get("stop", false)) or Arbeit.endet:
			return ""
		var data: Variant = Zip.entpacken(b, e)
		if data == null:
			return TranslationServer.translate("„%s“ im Paket ist beschädigt.") % str(e.name).left(80)
		var p := ziel.path_join(str(e.name))
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			return "Die Dateien ließen sich nicht in Uzais Ordner legen."
		f.store_buffer(data)
		f.close()
	return ""


## Im Faden: nach dem Entpacken noch einmal nachsehen – keine Verknüpfungen, Namen erlaubt, Zahl
## und Größe in den Grenzen. "" = in Ordnung.
static func _nachpruefen(dir: String) -> String:
	var stack := [dir]
	var n := 0
	var total := 0
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			return "Das Paket ließ sich nicht prüfen."
		da.include_hidden = true
		for name in da.get_directories() + da.get_files():
			var p := d.path_join(name)
			if da.is_link(name):
				return TranslationServer.translate("Das Paket enthält eine Verknüpfung: %s") % name.left(80)
			if not RA.pfad_ok(p.substr(dir.length() + 1)):
				return TranslationServer.translate("Ein Name im Paket ist nicht erlaubt: %s") % name.c_escape().left(80)
			n += 1
			if DirAccess.dir_exists_absolute(p):
				stack.append(p)
			else:
				total += FileAccess.get_size(p)
		if n > RA.MAX_EINTRAEGE or total > RA.MAX_GESAMT:
			return "Das Paket ist entpackt zu groß."
	return ""


## Programmdatei im Paket: ganz oben oder in genau einem Ordner darunter. "" wenn keine.
static func _finde_exe(dir: String, namen: Array) -> String:
	var want := namen.map(func(x: String) -> String: return x.to_lower())
	for f in DirAccess.get_files_at(dir):
		if f.to_lower() in want:
			return dir.path_join(f)
	var subs := DirAccess.get_directories_at(dir)
	if subs.size() == 1:
		for f in DirAccess.get_files_at(dir.path_join(subs[0])):
			if f.to_lower() in want:
				return dir.path_join(subs[0]).path_join(f)
	return ""


## Neue Dateien über die alten legen; was nur im Ziel liegt (Spielstände, BIOS, eigene
## Einstellungen), bleibt. Nie über Verknüpfungen.
func _uebernehmen(von: String, nach: String) -> bool:
	var da := DirAccess.open(von)
	if da == null or not _eigen(nach):
		return false
	for sub in da.get_directories():
		var z := nach.path_join(sub)
		if DirAccess.dir_exists_absolute(z) and DirAccess.open(nach).is_link(sub):
			return false
		DirAccess.make_dir_recursive_absolute(z)
		if not _uebernehmen(von.path_join(sub), z):
			return false
	for f in da.get_files():
		var z := nach.path_join(f)
		if FileAccess.file_exists(z):
			DirAccess.remove_absolute(z)
		if DirAccess.rename_absolute(von.path_join(f), z) != OK:
			return false
	return true


## Grundeinstellungen nur anlegen, wo noch keine liegen; dazu die Ordner fürs BIOS und die Kerne.
func _grund(id: String, ziel: String) -> void:
	for o in RA.ordner(id):
		DirAccess.make_dir_recursive_absolute(ziel.path_join(str(o)))
	var files := RA.grund_dateien(id)
	for rel in files.keys():
		var p := ziel.path_join(str(rel))
		if FileAccess.file_exists(p):
			continue
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.store_string(str(files[rel]))
			f.close()


## Liegt der Pfad in Uzais Ordner „emulatoren“?
func _eigen(p: String) -> bool:
	return p == ordner() or p.begins_with(ordner() + "/")


## Datei oder Ordner in Uzais Ordner „emulatoren“ löschen – nie etwas außerhalb, nie über
## Verknüpfungen (eine Verknüpfung selbst verschwindet, ihr Ziel bleibt).
func _weg(p: String) -> void:
	if not _eigen(p) or p == ordner():
		return
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
		return
	var da := DirAccess.open(p)
	if da == null:
		return
	da.include_hidden = true
	for sub in da.get_directories():
		if da.is_link(sub):
			DirAccess.remove_absolute(p.path_join(sub))
		else:
			_weg(p.path_join(sub))
	for f in da.get_files():
		DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)


static func _platz(dir: String, bytes: int) -> bool:
	var d := dir
	while d != "" and not DirAccess.dir_exists_absolute(d):
		d = d.get_base_dir()
	var da := DirAccess.open(d) if d != "" else null
	if da == null:
		return true
	var frei := int(da.get_space_left())
	return frei <= 0 or frei >= bytes + PLATZ_REST


## Eine Aufgabe im Hintergrund ausführen und das Ergebnis abwarten (die Oberfläche bleibt flüssig).
func _im_faden(fn: Callable) -> Variant:
	return await Arbeit.ergebnis(fn, Arbeit.LANG)


# --- Updates ----------------------------------------------------------------------------------

## Nach neuen Fassungen sehen (nur auf Wunsch). Ergebnis je von Uzai eingerichtetem Emulator:
## [{ id, name, alt, neu, angebot, hinweis }] – angebot ist gesetzt, wenn Uzai aktualisieren kann.
func updates() -> Array:
	var out: Array = []
	for id in RA.KATALOG.keys():
		var u := installiert(str(id))
		if u.is_empty():
			continue
		var e := RA.eintrag(id)
		var r := { "id": str(id), "name": str(e.name), "alt": str(u.get("fassung", "")), "neu": "", "angebot": {}, "hinweis": "" }
		var an := await angebot(str(id), true)
		if not bool(an.get("ok", false)):
			r.hinweis = str(an.get("error", ""))
		elif str(an.kennung) != str(u.get("kennung", "")):
			r.neu = str(an.fassung)
			r.angebot = an
		if str(e.quelle) == "fest" and r.neu == "" and not Library.demo:
			var d := await _json(str(e.neu))
			var v := RA.neue_fassung(str(id), d.data)
			if v != "":
				r.hinweis = TranslationServer.translate(
						"Beim Projekt gibt es schon %s. Uzai bietet sie an, sobald ihre Prüfsumme in Uzai steht (mit dem nächsten Update von Uzai).") % v
		out.append(r)
	return out
