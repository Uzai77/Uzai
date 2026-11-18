extends Node
## Bibliothek, unterste Schicht: die Spiele selbst – finden (get_game, sichtbare Spiele, je
## System), installiert oder nur gekauft, Anzeigename, Speichern und Arbeit im Hintergrund.
## Die Bibliothek besteht aus Schichten; jede erbt von der darunter und kennt nur sie:
## library_kern.gd → library_quellen.gd → library_ordnung.gd → library.gd.

const Arbeit := preload("res://src/core/arbeit.gd")
const Logdatei := preload("res://src/core/logdatei.gd")
const Stores := preload("res://src/library/stores.gd")
const Profiles := preload("res://src/core/profiles.gd")

var games: Array = []
var folders: Array = []          # { id, name, system }  system "" = für alle Systeme
var lists: Array = []            # Backlog: eigene Listen { id, name, games }
var goals := {}                  # Backlog: Jahresziele { "2026": 12 }
var demo := false
var _by_id := {}
var _dirty := false
var _save_timer: Timer
const WEICH_AB := 400            ## ab so vielen Spielen speichert der Zeitgeber über mehrere Bilder verteilt
const WEICH_JE_BILD := 150       ## so viele Spiele je Bild in Text wandeln
var _save_gen := 0               ## zählt jedes Speichern: ein verteiltes bricht ab, wenn ein neueres dazwischenkam
var _aenderung := 0              ## zählt jede Änderung (mark_dirty): kam während des Speicherns eine, bleibt „offen“
var _weich_laeuft := false


# --- Speichern und Index -------------------------------------------------------------------------

func save() -> void:
	if demo:
		return
	_save_gen += 1
	# Die Bibliothek gilt für alle Profile; was einem Profil gehört (Favoriten, Spielzeit, Backlog,
	# Listen), steht in dessen spieler.json (src/core/profiles.gd).
	var eigen := Config.write_json(Config.path("spieler.json"), { "games": Profiles.personal_of(games), "lists": lists, "goals": goals })
	var alle := Config.write_json(Config.path("library.json"), { "profiles": true, "games": Profiles.strip_games(games), "folders": folders })
	# Ging es nicht (Platte voll, Datei gesperrt): „noch zu speichern“ bleibt stehen. Die nächste Änderung und das
	# Beenden versuchen es wieder; die bisherigen Dateien sind unversehrt (Config.write_json).
	_dirty = not (eigen and alle)


func mark_dirty() -> void:
	forget_visible()
	_dirty = true
	_aenderung += 1
	_save_timer.start()


## Zählt jede Änderung an der Bibliothek: Wer sich etwas über alle Spiele merkt, sieht daran, ob es noch gilt.
func aenderung() -> int:
	return _aenderung


## Speichern auf Zeitgeber. Eine große Bibliothek in einem Stück zu speichern hält das Bild an: gemessen 183 ms bei
## 4000 Spielen, jeweils 1,5 s nach einer Änderung – auch nach jedem neu geladenen Cover. Darum hier über mehrere
## Bilder verteilt: je Bild WEICH_JE_BILD Spiele in Text wandeln, am Ende einmal schreiben (alles im Hauptfaden).
## Jedes Spiel steht für sich richtig in der Datei; ändert sich währenddessen etwas, bleibt „offen“ stehen, und das
## nächste Speichern folgt. save() (sofort, in einem Stück) bleibt für alles, was nicht warten darf – Beenden,
## Profilwechsel, Ende des Einlesens – und hat Vorrang: Ein verteiltes Speichern, das davon überholt wurde,
## schreibt nicht mehr.
func _speichern_weich() -> void:
	if demo:
		return
	if games.size() < WEICH_AB:
		save()
		return
	if _weich_laeuft:
		_save_timer.start()
		return
	_weich_laeuft = true
	_save_gen += 1
	var gen := _save_gen
	var stand := _aenderung
	var profil := str(Config.profile_id)
	var liste := games.duplicate()
	var alle := PackedStringArray()
	var eigen := PackedStringArray()
	var i := 0
	while i < liste.size():
		var bis := mini(i + WEICH_JE_BILD, liste.size())
		while i < bis:
			var g: Variant = liste[i]
			i += 1
			if not (g is Dictionary):
				continue
			# Wie Profiles.strip_games und personal_of, je Spiel: Persönliches in spieler.json, der Rest in library.json.
			var c: Dictionary = (g as Dictionary).duplicate()
			var mine := {}
			for k in Profiles.PERSONAL:
				if c.has(k):
					mine[k] = c[k]
					c.erase(k)
			alle.append(JSON.stringify(c))
			if not mine.is_empty():
				eigen.append(JSON.stringify(str(c.get("id", ""))) + ":" + JSON.stringify(mine))
		await get_tree().process_frame
		if gen != _save_gen or profil != str(Config.profile_id):
			_weich_laeuft = false
			return
	var text_eigen := "{\"games\":{" + ",".join(eigen) + "},\"lists\":" + JSON.stringify(lists) + ",\"goals\":" + JSON.stringify(goals) + "}"
	var text_alle := "{\"profiles\":true,\"games\":[" + ",".join(alle) + "],\"folders\":" + JSON.stringify(folders) + "}"
	var ok_eigen := Config.write_text(Config.path("spieler.json"), text_eigen)
	var ok_alle := Config.write_text(Config.path("library.json"), text_alle)
	_weich_laeuft = false
	_dirty = not (ok_eigen and ok_alle) or _aenderung != stand


func _reindex() -> void:
	forget_visible()
	_title_idx.clear()
	_by_id.clear()
	for g in games:
		_by_id[str(g.get("id", ""))] = g


func get_game(id: String) -> Dictionary:
	return _by_id.get(id, {})


var _title_idx := {}


# --- Abfragen ----------------------------------------------------------------

## with_hidden: auch ausgeblendete Spiele zählen (Liste „Ausgeblendete Spiele“ zum Zurückholen).
## Ausgeblendete Spiele stehen sonst nirgends – auch nicht, wenn früher „Ausgeblendete Spiele
## zeigen“ (library.show_hidden) an war: zu sehen sind sie nur noch in ihrer eigenen Liste.
func is_visible(g: Dictionary, with_hidden := false) -> bool:
	if g.get("missing", false):
		return false
	if g.get("hidden", false) and not with_hidden:
		return false
	# Kinderprofil: nur Spiele bis zur eingestellten Altersstufe (src/core/profiles.gd).
	if Config.kid_hides(g):
		return false
	if g.get("source") == "rom":
		var sys := Config.system(str(g.get("system", "")))
		if not sys.get("enabled", false):
			return false
	# Epic bzw. EA in den Einstellungen aus: sofort weg (nicht erst nach dem nächsten Einlesen).
	if g.get("source") == "epic" and not bool(Config.get_value("library.epic_enabled", true)):
		return false
	# Gekaufte, nicht installierte Epic-Spiele (aus dem Katalog des Launchers): eigener Schalter.
	if owned_only(g) and not bool(Config.get_value("library.epic_owned", true)):
		return false
	if g.get("source") == "ea" and not bool(Config.get_value("library.ea_enabled", true)):
		return false
	# Weitere Launcher (stores.gd): eigener Schalter je Launcher.
	if Stores.is_extra(str(g.get("source", ""))) and not Stores.enabled(str(g.source)):
		return false
	# Dasselbe Spiel in einem anderen Launcher: steht beim vorderen Eintrag (Wahl beim Start).
	if str(g.get("dupe_of", "")) != "":
		return false
	return true


## Sichtbare Spiele, pro Bild nur einmal gefiltert: Startseite, Reiter und „Für dich“ fragen
## dutzendfach hintereinander (bei 1000 Spielen kostete ein Bereichswechsel sonst Sekunden).
## Jede Änderung über Library oder an den Systemen verwirft das Ergebnis sofort.
var _vis: Array = []
var _vis_src: Array = []
var _vis_frame := -1
var _vis_size := -1


func visible_games() -> Array:
	return _sichtbar().duplicate()


## Dieselbe Liste ohne Kopie, nur zum Lesen (für Durchgänge in der Bibliothek selbst).
func _sichtbar() -> Array:
	var f := Engine.get_process_frames()
	if f != _vis_frame or games.size() != _vis_size or not is_same(games, _vis_src):
		_vis = games.filter(is_visible)
		_vis_src = games
		_vis_frame = f
		_vis_size = games.size()
		_zahl_da = false
	return _vis


## Wie viele sichtbare Spiele ein System bzw. Laden hat – wie by_system(…).size(), also mit den Spielen, die es dort
## auch gibt. Ein Durchgang zählt alle Systeme (je Bild einmal): Die Einstellungen fragten je Zeile by_system, bei
## 3000 Spielen und 40 Systemen kostete eine Seite so 59 ms (gemessen).
var _zahl := {}
var _zahl_da := false


func count_by_system(system_id: String) -> int:
	var vis := _sichtbar()
	if not _zahl_da:
		_zahl_da = true
		_zahl = {}
		for g: Dictionary in vis:
			var sid := str(g.get("system", ""))
			_zahl[sid] = int(_zahl.get(sid, 0)) + 1
			if g.get("alts") is Array:
				var auch := {}
				for a: Variant in g.alts:
					var asid := str(a).get_slice(":", 0)
					if asid != sid and not auch.has(asid) and str(a).contains(":"):
						auch[asid] = true
						_zahl[asid] = int(_zahl.get(asid, 0)) + 1
	return int(_zahl.get(system_id, 0))


## Ausgeblendete Spiele, die sonst zu sehen wären – zum Zurückholen (langes A auf einer Quelle).
func hidden_games() -> Array:
	return games.filter(func(g: Dictionary) -> bool: return bool(g.get("hidden", false)) and is_visible(g, true))


func forget_visible() -> void:
	_vis_frame = -1


## Spiele eines Systems bzw. Ladens – mit den Spielen, die es dort auch gibt, aber unter einem
## anderen Laden stehen (Doppelte: Hollow Knight bei Steam und GOG erscheint auch unter GOG).
func by_system(system_id: String) -> Array:
	return visible_games().filter(
			func(g): return g.get("system") == system_id or (g.get("alts") is Array
			and (g.alts as Array).any(func(a: Variant) -> bool: return str(a).begins_with(system_id + ":"))))


## Selbst hinzugefügtes Spiel („Hinzufügen“, add_manual) – nicht aus einem eingelesenen PC-Ordner.
static func eigen(g: Dictionary) -> bool:
	return str(g.get("source", "")) == "pc" and not bool(g.get("scanned", false))


## The games of one source at the top of the library. "Steam" also lists the self-added games (like Steam's own
## "Add a Non-Steam Game"); they stay listed under "PC" as well.
func by_tab(sub_id: String) -> Array:
	var out := by_system(sub_id)
	if sub_id == "steam":
		out.append_array(visible_games().filter(func(g: Dictionary) -> bool: return eigen(g) and not out.has(g)))
	return out


# --- Installiert, gekauft, Anzeigename -----------------------------------------------------------

## Installiert? Fehlt die Angabe, ja (Emulator-, PC- und alte Einträge).
static func is_installed(g: Dictionary) -> bool:
	return bool(g.get("installed", true))


## Gekauft, aber nicht installiert, und nicht von Steam (Steam bringt Spielzeit und „zuletzt“
## mit, auch von anderen PCs): Solche Spiele stehen nur in ihrem Reiter und im Raster, hinten –
## nie in „Zuletzt“, „Für dich“ oder der Spielzeit. Starten lassen sie sich nicht, nur installieren.
static func owned_only(g: Dictionary) -> bool:
	return not is_installed(g) and str(g.get("source", "")) == "epic"


func display_title(g: Dictionary) -> String:
	return str(g.get("title", "?"))


# --- Doppelte: Eintrag wieder verknüpfen ---------------------------------------------------------

## Doppelte neu verknüpfen (nach dem Einlesen, Laden und wenn eine Quelle umgeschaltet wird).
func relink() -> void:
	var on := {}
	for id in Stores.STORES:
		on[id] = Stores.enabled(id)
	Stores.link_dupes(games, on)
	forget_visible()


# --- Arbeit im Hintergrund und Protokoll ---------------------------------------------------------

## Der letzte Scan im Hintergrund brach mit einem Fehler ab (statt einer Liste kam nichts). Wer danach zusammenführt,
## lässt die Spiele dieser Quelle stehen: „Einlesen ging nicht“ heißt nicht „alle Spiele sind weg“.
var _scan_abbruch := false


## Ein Scan im Hintergrund; das Ergebnis ist immer eine Liste (leer, wenn er nichts liefert).
func _threaded(c: Callable) -> Array:
	var r: Variant = await Arbeit.ergebnis(c, Arbeit.LANG)
	_scan_abbruch = not (r is Array)
	return r if r is Array else []


## Kurzes Protokoll des Einlesens (logs/bibliothek.log), jede Zeile sofort geschrieben: Stürzt
## Uzai ab, steht dort der letzte Schritt.
func scan_log(text: String) -> void:
	Logdatei.zeile(Config.path("logs/bibliothek.log"), text, 256 * 1024)
