extends Node
## Erfolgs-Pop-ups: erkennt neu freigeschaltete Erfolge, während ein Spiel läuft, und zeigt sie
## als eigenes Pop-up (achievement_popups.gd, achievement_toast.gd) mit Uzai-Punkten.
##
## Steam, sofort: Steam schreibt bei jeder Freischaltung den Zwischenspeicher
## <Steam>/appcache/stats/UserGameStats_<Konto-ID>_<App-ID>.bin neu (binäre KeyValues). Uzai
## schaut alle 1,5 s nur auf die Änderungszeit (gerade erst geänderte Dateien auch auf den
## Inhalt, siehe must_read); ändert sie sich, liest es die Datei: je Statistik
## „data“ (Bitfeld der Erfolge) und „AchievementTimes“ (Bit → Zeit). Welches Bit welcher Erfolg
## ist, steht im Schema daneben (UserGameStatsSchema_<App-ID>.bin: stats → <id> → bits → <bit>
## → name, display). So geht es ohne Netz und ohne API-Schlüssel.
## Steam, Rückfall: GetPlayerAchievements alle 30 s (und sofort, wenn sich die Datei ändert,
## aber nicht lesbar war). Namen, Beschreibung, Bild und Seltenheit kommen aus Achievements
## (Schema der Web-API, deutsch); fehlt die, aus dem Schema in der Datei und den globalen
## Anteilen (GetGlobalAchievementPercentagesForApp, ohne Schlüssel).
## RetroAchievements (Emulator-Spiele): API_GetUserRecentAchievements alle 12 s.
##
## Nichts doppelt, nichts verpasst: je Spiel eine Menge der freigeschalteten Erfolge. Die erste
## Abfrage einer Sitzung legt nur den Stand fest (alte Erfolge geben kein Pop-up) – außer was
## nach dem Spielstart freigeschaltet wurde (Steam kennt die Zeit).
##
## Uzai-Punkte: aus der globalen Seltenheit (siehe points_for), wie ein Gamerscore. Je Spiel und
## insgesamt gespeichert (Datenordner, unlocks.json), dazu die letzten Freischaltungen.
## Schnittstelle für Abzeichen/Level: total_points(), points_for_game(key), games(), history(),
## Signal unlocked(entry). Spielschlüssel: "steam:<App-ID>" bzw. "ra:<RA-Spiel-ID>".

signal unlocked(entry: Dictionary)
signal changed

const Ach := preload("res://src/core/achievements.gd")
const Lang := preload("res://src/core/lang.gd")
const Popups := preload("res://src/ui/achievement_popups.gd")
const Fremd := preload("res://src/core/fremd.gd")

const FILE := "unlocks.json"
const FILE_POLL := 1.5
const WEB_POLL := 30.0
const RA_POLL := 12.0
const HISTORY_MAX := 500
const STEAM_API := "https://api.steampowered.com/"
const STEAM_ICONS := "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/%d/%s"
## Steam-Zeiten und die Uhr hier können ein paar Sekunden auseinander liegen.
const SLACK := 20

## Punktestufen: [ab Anteil in %, Punkte]. Unbekannte Seltenheit gibt UNKNOWN_POINTS.
const TIERS := [[50.0, 10], [20.0, 20], [10.0, 30], [5.0, 50], [1.0, 75], [0.0, 100]]
const UNKNOWN_POINTS := 20
const RARE_BELOW := 10.0
const ULTRA_BELOW := 1.0

var popups: CanvasLayer
var _data := { "v": 1, "games": {}, "history": [] }
var _save_due := false
## Laufende Sitzung: { key, platform, appid, title, started, known: {api: true}, file, mtime,
## schema_mtime, bits, file_base, web_base, ra_base, info: {api: {...}}, pct: {api: %} }
var _s: Dictionary = {}
var _file_timer: Timer
var _web_timer: Timer
var _ra_timer: Timer
var _web_busy := false
var _ra_busy := false
var _glob_at := 0
var demo := false
var log_lines: Array = []       ## kurze Protokollzeilen (für Tests und die Fehlersuche)


func _ready() -> void:
	demo = "--demo" in OS.get_cmdline_user_args()
	_load()
	popups = Popups.new()
	add_child(popups)
	_file_timer = _timer(FILE_POLL, _poll_file)
	_web_timer = _timer(WEB_POLL, _poll_web)
	_ra_timer = _timer(RA_POLL, _poll_ra)
	Launcher.started.connect(_on_started)
	Launcher.ended.connect(_on_ended)
	Achievements.updated.connect(_on_ach_updated)


func _timer(sec: float, cb: Callable) -> Timer:
	var t := Timer.new()
	t.wait_time = sec
	t.timeout.connect(cb)
	add_child(t)
	return t


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 200:
		log_lines = log_lines.slice(-150)


# --- Schnittstelle ---------------------------------------------------------------------------

func enabled() -> bool:
	return bool(Config.get_value("notify.unlock_popups", true))


## Alle Uzai-Punkte (alle Spiele zusammen).
func total_points() -> int:
	var n := 0
	for k in _data.games:
		n += int((_data.games[k] as Dictionary).get("points", 0))
	return n


## Uzai-Punkte eines Spiels ("steam:<App-ID>" oder "ra:<ID>"), 0 wenn unbekannt.
func points_for_game(key: String) -> int:
	return int((_data.games.get(key, {}) as Dictionary).get("points", 0))


## Je Spiel: key -> { title, platform, points, max, count, total, at }.
func games() -> Dictionary:
	return (_data.games as Dictionary).duplicate(true)


## Freischaltungen, neueste zuerst: [{ game, game_key, name, desc, api, points, rarity,
## platform: "steam"|"ra", unlocked_at, icon, hardcore, ra_points }].
func history(limit := 0) -> Array:
	var h: Array = (_data.history as Array).duplicate(true)
	return h.slice(0, limit) if limit > 0 else h


## Ein Pop-up zum Ausprobieren (Einstellungen): normal, selten, ultra, retro oder komplett
## (der letzte Erfolg eines Spiels).
func test_popup(kind := "normal") -> void:
	var e := {
		"game": "Uzai", "game_key": "test", "api": "TEST_" + kind, "platform": "steam", "unlocked_at": int(Time.get_unix_time_from_system()),
		"icon": "", "hardcore": false, "ra_points": 0, "test": true,
	}
	match kind:
		"rare":
			e.merge({ "name": "Meister der stillen Stunden", "desc": "Spiele eine Nacht lang, ohne zu pausieren.", "rarity": 3.2 }, true)
		"ultra":
			e.merge({ "name": "Unberührbar", "desc": "Schaffe das letzte Kapitel ohne Treffer.", "rarity": 0.4 }, true)
		"retro":
			e.merge({ "name": "Ring-Sammler", "desc": "Sammle 100 Ringe in einer Zone.", "rarity": 24.0, "platform": "ra", "ra_points": 10, "hardcore": true }, true)
		"komplett":
			e.merge({ "name": "Bis zum letzten Stern", "desc": "Schalte jeden Erfolg frei.", "rarity": 2.1, "complete": true, "game": "Hades" }, true)
		_:
			e.merge({ "name": "Erste Schritte", "desc": "Schließe das erste Kapitel ab.", "rarity": 42.0 }, true)
	# Das Pop-up zeichnet Name und Beschreibung, wie sie kommen (bei echten Erfolgen fremder Text): Uzais eigene
	# Probe-Texte darum hier in die Sprache der Oberfläche.
	e["name"] = str(TranslationServer.translate(str(e.name)))
	e["desc"] = str(TranslationServer.translate(str(e.desc)))
	e["points"] = entry_points(e)
	popups.show_entry(e, decorate(e, bool(Config.get_value("notify.unlock_rare", true))))


# --- Reine Regeln (siehe tests/logic_erfolge_popup.gd) ---------------------------------------

## 1.240 statt 1240
static func num_text(n: int) -> String:
	return Lang.tausender(n)


## Uzai-Punkte aus dem Anteil der Spieler (in %): ≥ 50 → 10, 20–50 → 20, 10–20 → 30,
## 5–10 → 50, 1–5 → 75, unter 1 → 100. Unbekannt (< 0) → 20.
static func points_for(pct: float) -> int:
	if pct < 0.0:
		return UNKNOWN_POINTS
	for t in TIERS:
		if pct >= float(t[0]):
			return int(t[1])
	return 100


## RetroAchievements: mit bekannter Seltenheit wie Steam, sonst aus den RA-Punkten (1–100).
static func points_for_ra(ra_points: int, pct := -1.0) -> int:
	if pct >= 0.0:
		return points_for(pct)
	if ra_points <= 2:
		return 10
	if ra_points <= 5:
		return 20
	if ra_points <= 10:
		return 30
	if ra_points <= 25:
		return 50
	if ra_points <= 50:
		return 75
	return 100


static func entry_points(e: Dictionary) -> int:
	if str(e.get("platform", "")) == "ra":
		return points_for_ra(int(e.get("ra_points", 0)), float(e.get("rarity", -1.0)))
	return points_for(float(e.get("rarity", -1.0)))


## Wie ein Pop-up aussieht: { variant: normal|rare|ultra|retro|komplett, rare (bool), line1, sound,
## chip, sound2 }. „komplett“: der letzte Erfolg eines Spiels (e.complete) – der große Moment, mit
## zweitem Klang (sound2, eine halbe Sekunde später) und längerem Halten.
static func decorate(e: Dictionary, highlight_rare := true) -> Dictionary:
	var pct := float(e.get("rarity", -1.0))
	var rare := highlight_rare and pct >= 0.0 and pct < RARE_BELOW
	var ultra := rare and pct < ULTRA_BELOW
	var share := "%s der Spieler" % Ach.pct_text(pct) if pct >= 0.0 else ""
	if bool(e.get("complete", false)):
		var ra := str(e.get("platform", "")) == "ra"
		var chip := "100 %"
		if ra and bool(e.get("hardcore", false)):
			chip = "Gemeistert"
		return { "variant": "komplett", "rare": true, "line1": "Alle Erfolge freigeschaltet" + ("  ·  " + share if share != "" and not ra else ""),
			"sound": "unlock_rare", "sound2": "unlock", "chip": chip }
	if str(e.get("platform", "")) == "ra":
		var bits := PackedStringArray(["Seltener Retro-Erfolg" if rare else "Retro-Erfolg freigeschaltet"])
		if int(e.get("ra_points", 0)) > 0:
			bits.append("%d RA-Punkte" % int(e.ra_points))
		return { "variant": "retro", "rare": rare, "line1": " · ".join(bits), "sound": "unlock_retro", "chip": "Hardcore" if bool(e.get("hardcore", false)) else "" }
	if ultra:
		return { "variant": "ultra", "rare": true, "line1": "Ultraseltener Erfolg · " + share, "sound": "unlock_rare", "chip": "" }
	if rare:
		return { "variant": "rare", "rare": true, "line1": "Seltener Erfolg · " + share, "sound": "unlock_rare", "chip": "" }
	return { "variant": "normal", "rare": false, "line1": "Erfolg freigeschaltet", "sound": "unlock", "chip": "" }


## Wie lange ein Pop-up voll stehen bleibt (s), je nachdem, wie viele noch warten.
static func hold_for(waiting: int) -> float:
	if waiting <= 0:
		return 3.4
	if waiting == 1:
		return 2.2
	if waiting <= 3:
		return 1.6
	return 1.0


## Ist das Spiel mit diesen Freischaltungen komplett? total: alle Erfolge des Spiels, had: vorher
## freigeschaltet (ohne die neuen), fresh_n: jetzt dazugekommen. Ohne bekannte Gesamtzahl nie.
static func complete_after(total: int, had: int, fresh_n: int) -> bool:
	return total > 0 and fresh_n > 0 and had + fresh_n >= total


## Was neu ist: Erfolge in now (api -> Unix-Zeit, 0 = unbekannt), die known noch nicht hat.
## Beim ersten Blick einer Sitzung (baseline) nur, was nach since freigeschaltet wurde.
## Nach Zeit sortiert, älteste zuerst.
static func diff_new(known: Dictionary, now: Dictionary, baseline: bool, since: int) -> Array:
	var out: Array = []
	for api in now.keys():
		if known.has(api):
			continue
		var at := int(now[api])
		if baseline and (at <= 0 or at < since - SLACK):
			continue
		out.append(api)
	out.sort_custom(func(a, b): return int(now[a]) < int(now[b]) if int(now[a]) != int(now[b]) else str(a) < str(b))
	return out


# --- Binäre KeyValues (Steam-Zwischenspeicher) ------------------------------------------------

## Liest binäre KeyValues: 0x00 Abschnitt, 0x01 Text, 0x02 int32, 0x03 float32, 0x04 Zeiger,
## 0x05 Breittext, 0x06 Farbe, 0x07 uint64, 0x0A int64, 0x08/0x0B Ende. Kaputt → {}.
static func parse_kv(b: PackedByteArray) -> Dictionary:
	var pos := [0]
	var out: Variant = _kv_block(b, pos, 0)
	return out if out != null else {}


static func _kv_block(b: PackedByteArray, pos: Array, depth: int) -> Variant:
	var d := {}
	if depth > 32:
		return null
	while pos[0] < b.size():
		var t: int = b[pos[0]]
		pos[0] += 1
		if t == 0x08 or t == 0x0B:
			return d
		var key: Variant = _kv_str(b, pos)
		if key == null:
			return null
		match t:
			0x00:
				var sub: Variant = _kv_block(b, pos, depth + 1)
				if sub == null:
					return null
				d[key] = sub
			0x01:
				var s: Variant = _kv_str(b, pos)
				if s == null:
					return null
				d[key] = s
			0x02, 0x04, 0x06:
				if pos[0] + 4 > b.size():
					return null
				d[key] = b.decode_s32(pos[0])
				pos[0] += 4
			0x03:
				if pos[0] + 4 > b.size():
					return null
				d[key] = b.decode_float(pos[0])
				pos[0] += 4
			0x07, 0x0A:
				if pos[0] + 8 > b.size():
					return null
				d[key] = b.decode_s64(pos[0])
				pos[0] += 8
			0x05:
				var e: int = pos[0]
				while e + 1 < b.size() and not (b[e] == 0 and b[e + 1] == 0):
					e += 2
				if e + 1 >= b.size():
					return null
				d[key] = b.slice(pos[0], e).get_string_from_utf16()
				pos[0] = e + 2
			_:
				return null
	# Ohne abschließendes Ende (oberste Ebene): gilt als gelesen.
	return d if depth == 0 else null


static func _kv_str(b: PackedByteArray, pos: Array) -> Variant:
	var e: int = pos[0]
	while e < b.size() and b[e] != 0:
		e += 1
	if e >= b.size():
		return null
	var s := b.slice(pos[0], e).get_string_from_utf8()
	pos[0] = e + 1
	return s


## Aus dem Schema: "<Statistik>/<Bit>" -> { api, title, desc, icon, icon_gray, hidden }. Sprache: deutsch,
## sonst englisch, sonst der erste Text. icon ist der Dateiname auf dem Steam-Server.
static func schema_bits(schema: Dictionary) -> Dictionary:
	var out := {}
	var stats := _find_stats(schema, 0)
	for sid in stats.keys():
		var st: Variant = stats[sid]
		if not (st is Dictionary) or not (st.get("bits") is Dictionary):
			continue
		for bit in (st.bits as Dictionary).keys():
			var e: Variant = st.bits[bit]
			if not (e is Dictionary):
				continue
			var disp: Dictionary = e.get("display", {}) if e.get("display") is Dictionary else {}
			var b := int(e.get("bit", int(str(bit)) if str(bit).is_valid_int() else 0))
			out["%s/%d" % [str(sid), b]] = {
				"api": str(e.get("name", "%s/%d" % [str(sid), b])),
				"title": _lang(disp.get("name", "")), "desc": _lang(disp.get("desc", "")),
				"icon": str(disp.get("icon", "")), "icon_gray": str(disp.get("icon_gray", "")),
				"hidden": str(disp.get("hidden", "0")) in ["1", "true"],
			}
	return out


static func _find_stats(d: Dictionary, depth: int) -> Dictionary:
	if d.get("stats") is Dictionary:
		return d.stats
	if depth > 3:
		return {}
	for k in d.keys():
		if d[k] is Dictionary:
			var s := _find_stats(d[k], depth + 1)
			if not s.is_empty():
				return s
	return {}


## Text in der Sprache der Oberfläche (Steams Schema nennt jede Sprache einzeln), sonst englisch, sonst irgendeine.
## Bis 0.16.62 stand hier fest „deutsch zuerst“: Auf Englisch gestellt blieben Namen und Beschreibungen deutsch, wo
## Uzai sie aus Steams Dateien oder vom Chat-Server liest – ohne Web-API-Schlüssel also überall.
static func _lang(v: Variant) -> String:
	if v is Dictionary:
		for l in [str(Lang.api("steam")), "english"]:
			if v.has(l) and str(v[l]) != "":
				return str(v[l])
		for k in v.keys():
			if str(k) != "token" and str(v[k]) != "":
				return str(v[k])
		return ""
	return str(v) if v != null else ""


## Aus den Spielerdaten: api -> Unix-Zeit (0, wenn Steam keine Zeit kennt). bits aus
## schema_bits; ohne Schema heißen die Erfolge "<Statistik>/<Bit>".
static func unlocked_from_stats(user: Dictionary, bits: Dictionary) -> Dictionary:
	var out := {}
	for st in _stat_blocks(user, 0):
		var sid := str(st[0])
		var blk: Dictionary = st[1]
		var data := int(blk.get("data", 0))
		var times: Dictionary = blk.get("AchievementTimes", {}) if blk.get("AchievementTimes") is Dictionary else {}
		for i in 32:
			var on := ((data >> i) & 1) == 1
			var at := int(times.get(str(i), 0))
			if not on and at <= 0:
				continue
			# Ohne Schema nur Bits mit Zeit (eine reine Zahl-Statistik hat keine AchievementTimes).
			var id := "%s/%d" % [sid, i]
			if bits.is_empty() and times.is_empty():
				continue
			if not bits.is_empty() and not bits.has(id):
				continue
			var api := str((bits.get(id, {}) as Dictionary).get("api", id))
			out[api] = maxi(at, 0)
	return out


## Alle Statistik-Abschnitte (Name aus Ziffern, mit „data“), egal wie tief (Steam legt sie
## unter einen Wurzelabschnitt, etwa "cache").
static func _stat_blocks(d: Dictionary, depth: int) -> Array:
	var out: Array = []
	if depth > 4:
		return out
	for k in d.keys():
		var v: Variant = d[k]
		if not (v is Dictionary):
			continue
		if str(k).is_valid_int() and ((v as Dictionary).has("data") or (v as Dictionary).has("AchievementTimes")):
			out.append([str(k), v])
		elif not str(k).is_valid_int() or depth == 0:
			out.append_array(_stat_blocks(v, depth + 1))
	return out


## GetPlayerAchievements → api -> Unix-Zeit (nur freigeschaltete). Kaputt/privat: null.
static func parse_player(data: Variant) -> Variant:
	if not (data is Dictionary) or not (data.get("playerstats") is Dictionary):
		return null
	var ps: Dictionary = data.playerstats
	if not bool(ps.get("success", true)) or not (ps.get("achievements") is Array):
		return null
	var out := {}
	for a in ps.achievements:
		if a is Dictionary and int(a.get("achieved", 0)) == 1:
			out[str(a.get("apiname", ""))] = int(a.get("unlocktime", 0))
	return out


## API_GetUserRecentAchievements → [{ key, id, title, desc, icon, points, hardcore, game,
## game_id, at }] (key: Erfolg + Modus; Hardcore nach Softcore ist eine neue Freischaltung).
static func parse_ra_recent(data: Variant) -> Array:
	var out: Array = []
	if not (data is Array):
		return out
	for a in data:
		if not (a is Dictionary):
			continue
		var id := str(a.get("AchievementID", ""))
		if id == "":
			continue
		var hc := int(a.get("HardcoreMode", 0)) == 1
		var badge := str(a.get("BadgeURL", "")) if a.get("BadgeURL") != null else ""
		if badge == "":
			badge = "/Badge/%s.png" % str(a.get("BadgeName", ""))
		out.append({ "key": "%s:%s" % [id, "hc" if hc else "sc"], "id": id, "title": str(a.get("Title", "")),
			"desc": str(a.get("Description", "")) if a.get("Description") != null else "",
			"icon": badge if badge.begins_with("http") else Ach.RA_MEDIA + badge,
			"points": int(a.get("Points", 0)), "hardcore": hc, "game": str(a.get("GameTitle", "")),
			"game_id": int(a.get("GameID", 0)), "at": Ach._ra_date(str(a.get("Date", ""))) })
	return out


## Uzai-Punkte eines ganzen Spiels aus seiner Erfolgsliste (Format wie Achievements.for_game).
static func score_list(res: Dictionary) -> Dictionary:
	var pts := 0
	var mx := 0
	var n := 0
	var ra := str(res.get("source", "")) == "ra"
	for a in res.get("list", []):
		var p := points_for_ra(int(a.get("points", 0)), float(a.get("rarity", -1.0))) if ra else points_for(float(a.get("rarity", -1.0)))
		mx += p
		if bool(a.get("unlocked", false)):
			pts += p
			n += 1
	return { "points": pts, "max": mx, "count": n, "total": (res.get("list", []) as Array).size() }


static func game_key(res_or_game: Dictionary) -> String:
	if int(res_or_game.get("appid", 0)) > 0 and str(res_or_game.get("source", "steam")) != "ra":
		return "steam:%d" % int(res_or_game.appid)
	if int(res_or_game.get("ra_id", 0)) > 0:
		return "ra:%d" % int(res_or_game.ra_id)
	return ""


# --- Speicher --------------------------------------------------------------------------------

func _load() -> void:
	var d: Variant = Config.read_json(Config.path(FILE), null)
	if not (d is Dictionary and d.get("games") is Dictionary and d.get("history") is Array):
		return
	# Nur Einträge der erwarteten Form: ein anderer Wert (Zahl, Text) bräche sonst record() und total_points() ab.
	var spiele := {}
	for k in d.games:
		if d.games[k] is Dictionary:
			spiele[str(k)] = d.games[k]
	_data = { "v": 1, "games": spiele, "history": (d.history as Array).filter(func(h: Variant) -> bool: return h is Dictionary) }


func _save_soon() -> void:
	if _save_due:
		return
	_save_due = true
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		_save_due = false
		Config.write_json(Config.path(FILE), _data)
	)


## Eine Erfolgsliste wurde geladen (Achievements.for_game): Punkte des Spiels neu rechnen.
func _on_ach_updated(what: String) -> void:
	if not what.begins_with("game:"):
		return
	var res := Achievements.cached({ "id": what.substr(5) })
	# Demo-Listen zählen nicht (sie sollen nie in die echten Punkte geraten).
	if demo or Achievements.demo or res.is_empty() or not res.has("list") or res.has("error"):
		return
	var key := game_key(res)
	if key == "" or key.begins_with("test"):
		return
	var sc := score_list(res)
	var g: Dictionary = _data.games.get(key, {})
	g.merge({ "title": str(res.get("title", g.get("title", ""))), "platform": "ra" if key.begins_with("ra:") else "steam",
		"at": int(Time.get_unix_time_from_system()) }, true)
	g.merge(sc, true)
	_data.games[key] = g
	_save_soon()
	changed.emit()


# --- Sitzung ---------------------------------------------------------------------------------

func _on_started(g: Dictionary) -> void:
	_stop()
	if demo:
		return
	var now := int(Time.get_unix_time_from_system())
	if str(g.get("source", "")) == "steam" and int(g.get("appid", 0)) > 0:
		var appid := int(g.appid)
		_s = { "key": "steam:%d" % appid, "platform": "steam", "appid": appid, "gid": str(g.get("id", "")),
			"title": Library.display_title(g) if g.has("title") else "", "started": now, "known": {}, "file": "", "mtime": 0, "sig": 0,
			"schema_mtime": 0, "bits": {}, "file_base": true, "web_base": true, "info": {}, "pct": {}, "info_ready": false }
		_log("Sitzung Steam %d" % appid)
		_poll_file()
		_file_timer.start()
		_web_timer.start()
		_poll_web()
		_load_info(appid)
	elif str(g.get("source", "")) == "rom" and Achievements.has_ra() and bool(Config.get_value("accounts.ra_toasts", true)):
		_s = { "key": "", "platform": "ra", "gid": str(g.get("id", "")), "title": Library.display_title(g), "started": now,
			"known": {}, "ra_base": true }
		_log("Sitzung RA %s" % str(g.get("id", "")))
		_ra_timer.start()
		_poll_ra()


func _on_ended(_g: Dictionary, _secs: int) -> void:
	# Ein letzter Blick: Erfolge der letzten Sekunden (etwa im Abspann) nicht verlieren.
	var alt := _s
	if not alt.is_empty():
		if alt.platform == "steam":
			_poll_file()
		elif alt.platform == "ra":
			await _poll_ra()
	# Während der Abfrage kann schon das nächste Spiel begonnen haben: dessen Sitzung bleibt stehen.
	if is_same(_s, alt):
		_stop()


func _stop() -> void:
	_s = {}
	_glob_at = 0          # die nächste Sitzung sucht ihre Datei sofort
	for t in [_file_timer, _web_timer, _ra_timer]:
		if is_instance_valid(t):
			t.stop()


## Für Tests: eine Sitzung ohne Launcher beginnen (Steam-Ordner und Konto vorgeben).
func begin_steam_session(appid: int, title: String, stats_dir: String, started := -1) -> void:
	_stop()
	_s = { "key": "steam:%d" % appid, "platform": "steam", "appid": appid, "gid": "steam:%d" % appid, "title": title,
		"started": started if started >= 0 else int(Time.get_unix_time_from_system()), "known": {}, "file": "", "mtime": 0, "sig": 0,
		"schema_mtime": 0, "bits": {}, "file_base": true, "web_base": true, "info": {}, "pct": {}, "dir": stats_dir }
	_poll_file()


func session() -> Dictionary:
	return _s


# --- Steam: Datei -----------------------------------------------------------------------------

func _stats_dir() -> String:
	if _s.has("dir"):
		return str(_s.dir)
	var root := Library.steam_root()
	return root.path_join("appcache/stats") if root != "" else ""


## Muss die Datei gelesen werden? Die Änderungszeit kennt nur ganze Sekunden: Schreibt Steam
## zweimal in derselben Sekunde (zwei Erfolge kurz hintereinander), sähe die zweite Fassung aus
## wie die schon gelesene. Darum zählt bei einer gerade erst geänderten Datei der Inhalt –
## 2 s, damit einer der Abrufe alle 1,5 s sicher hineinfällt. Sonst reicht die Zeit.
static func must_read(mtime: int, last_mtime: int, now: int) -> bool:
	return mtime != last_mtime or mtime >= now - 2


## Datei des eigenen Kontos; ohne bekannte Steam-ID die zuletzt geschriebene zu diesem Spiel.
func _find_file(dir: String, appid: int) -> String:
	var sid := str(Config.get_value("accounts.steam_id", ""))
	if not sid.is_valid_int():
		sid = str(Config.get_value("accounts.steam_chat_id", ""))
	if sid.is_valid_int() and sid.length() >= 16:
		var p := dir.path_join("UserGameStats_%d_%d.bin" % [int(sid) - 76561197960265728, appid])
		if FileAccess.file_exists(p):
			return p
	var best := ""
	var best_t := -1
	var suffix := "_%d.bin" % appid
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("UserGameStats_") and f.ends_with(suffix) and not f.begins_with("UserGameStatsSchema_"):
			var t := FileAccess.get_modified_time(dir.path_join(f))
			if t > best_t:
				best_t = t
				best = dir.path_join(f)
	return best


func _poll_file() -> void:
	if _s.is_empty() or _s.platform != "steam":
		return
	var dir := _stats_dir()
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var appid := int(_s.appid)
	if str(_s.file) == "" or not FileAccess.file_exists(str(_s.file)):
		# Noch keine Datei (erstes Spielen): nur alle paar Sekunden im Ordner suchen.
		if Time.get_ticks_msec() - _glob_at < 4500 and _glob_at > 0:
			return
		_glob_at = Time.get_ticks_msec()
		_s.file = _find_file(dir, appid)
		if str(_s.file) == "":
			return
	var mt := FileAccess.get_modified_time(str(_s.file))
	if not must_read(mt, int(_s.mtime), int(Time.get_unix_time_from_system())):
		return
	var raw := FileAccess.get_file_as_bytes(str(_s.file))
	var sig := hash(raw)
	if mt == int(_s.mtime) and sig == int(_s.sig):
		return
	_s.mtime = mt
	_s.sig = sig
	var schema_path := dir.path_join("UserGameStatsSchema_%d.bin" % appid)
	var smt := FileAccess.get_modified_time(schema_path) if FileAccess.file_exists(schema_path) else 0
	if smt != int(_s.schema_mtime):
		_s.schema_mtime = smt
		_s.bits = schema_bits(parse_kv(FileAccess.get_file_as_bytes(schema_path))) if smt > 0 else {}
	var user := parse_kv(raw)
	var now := unlocked_from_stats(user, _s.bits)
	if user.is_empty() or (now.is_empty() and not bool(_s.file_base)):
		# Datei geändert, aber nicht lesbar (oder leer): sofort im Netz nachsehen.
		_log("Datei geändert, nicht lesbar – frage Steam")
		_poll_web()
		return
	_take("file", now, bool(_s.file_base))
	_s.file_base = false


# --- Steam: Netz --------------------------------------------------------------------------------

## Läufe von _poll_web, die gerade unterwegs sind (siehe dort).
var _poll_web_offen := 0


func _poll_web() -> void:
	_poll_web_offen += 1
	await _poll_web_lauf()
	_poll_web_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _poll_web täte bis zum Neustart nichts mehr.
	if _poll_web_offen == 0 and _web_busy:
		_web_busy = false


func _poll_web_lauf() -> void:
	# Lehnt die Web-API den Zugang ab (QR-Anmeldung, HTTP 400), bleibt es bei der Datei.
	if _s.is_empty() or _s.platform != "steam" or _web_busy or not Achievements.has_steam() or not Achievements.steam_web_ok():
		return
	_web_busy = true
	var key := str(_s.key)
	var sid := await Social.steam_id()
	if sid == "":
		_web_busy = false
		return
	var r := await Net.get_json(
			STEAM_API + "ISteamUserStats/GetPlayerAchievements/v1/?" + await Social.steam_query({ "appid": int(_s.get("appid", 0)), "steamid": sid }))
	_web_busy = false
	if _s.is_empty() or str(_s.key) != key or not r.ok:
		return
	var now: Variant = parse_player(r.data)
	if now == null:
		return
	_take("web", now, bool(_s.web_base))
	_s.web_base = false


## Namen, Bilder und Seltenheit für diese Sitzung laden (im Hintergrund).
func _load_info(appid: int) -> void:
	var key := str(_s.key)
	# Globale Anteile gehen ohne Schlüssel.
	var rare := await Net.get_json(STEAM_API + "ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?" + Net.query({ "gameid": appid }))
	if _s.is_empty() or str(_s.key) != key:
		return
	if rare.ok and rare.data is Dictionary:
		for a in Fremd.zeilen(rare.data, "achievementpercentages/achievements"):
			_s.pct[str(a.get("name", ""))] = float(a.get("percent", -1))
	if Achievements.has_steam():
		var res: Dictionary = await Achievements.steam_game(appid, str(_s.title))
		if _s.is_empty() or str(_s.key) != key:
			return
		for a in res.get("list", []):
			_s.info[str(a.id)] = a
	_s.info_ready = true


## Neue Erfolge aus einer Quelle übernehmen (Datei oder Netz) und zeigen.
## Namen vergleicht Uzai ohne Groß/klein (manche Spiele schreiben sie im Schema anders).
func _take(src: String, now: Dictionary, baseline: bool) -> void:
	var up := {}
	var orig := {}
	for api in now.keys():
		up[str(api).to_upper()] = int(now[api])
		orig[str(api).to_upper()] = str(api)
	var fresh := diff_new(_s.known, up, baseline, int(_s.started))
	for k in up.keys():
		_s.known[k] = true
	_log("%s: %d frei, %d neu%s" % [src, now.size(), fresh.size(), " (Stand)" if baseline else ""])
	# Der letzte Erfolg des Spiels: der große Moment (nur das letzte Pop-up einer Welle).
	var complete := complete_after(_steam_total(), (_s.known as Dictionary).size() - fresh.size(), fresh.size())
	for i in fresh.size():
		_steam_unlocked(str(orig[fresh[i]]), int(up[fresh[i]]), complete and i == fresh.size() - 1)


## Wie viele Erfolge das laufende Steam-Spiel hat: aus der Web-Liste, sonst aus dem Schema der Datei.
func _steam_total() -> int:
	var n := (_s.get("info", {}) as Dictionary).size()
	if n == 0:
		n = (_s.get("bits", {}) as Dictionary).size()
	return n


func _steam_unlocked(api: String, at: int, complete := false) -> void:
	# Kam die Freischaltung vor Namen und Bildern an (gleich nach dem Start): kurz darauf warten.
	var waited := 0
	while not bool(_s.get("info_ready", true)) and waited < 20 and not (_s.info as Dictionary).has(api):
		await get_tree().create_timer(0.2).timeout
		waited += 1
		if _s.is_empty():
			return
	var info: Dictionary = _s.info.get(api, {})
	if info.is_empty():
		for k in (_s.info as Dictionary).keys():
			if str(k).to_upper() == api.to_upper():
				info = _s.info[k]
				break
	var sch := {}
	for k in (_s.bits as Dictionary).keys():
		if str(_s.bits[k].api).to_upper() == api.to_upper():
			sch = _s.bits[k]
			break
	var icon := str(info.get("icon", ""))
	if icon == "" and str(sch.get("icon", "")) != "":
		icon = STEAM_ICONS % [int(_s.appid), str(sch.icon)]
	var pct := float(info.get("rarity", _s.pct.get(api, -1.0)))
	var desc := str(info.get("secret", "")) if str(info.get("secret", "")) != "" else str(info.get("desc", sch.get("desc", "")))
	var e := {
		"game": str(_s.title), "game_key": str(_s.key), "api": api,
		"name": str(info.get("title", sch.get("title", api))), "desc": desc, "icon": icon,
		"rarity": pct, "platform": "steam", "unlocked_at": at if at > 0 else int(Time.get_unix_time_from_system()),
		"hardcore": false, "ra_points": 0, "complete": complete,
	}
	e["points"] = entry_points(e)
	# Die Erfolgsliste des Spiels ist veraltet: beim nächsten Öffnen neu laden.
	Achievements._games.erase(str(_s.gid))
	record(e)


# --- RetroAchievements ---------------------------------------------------------------------------

## Läufe von _poll_ra, die gerade unterwegs sind (siehe dort).
var _poll_ra_offen := 0


func _poll_ra() -> void:
	_poll_ra_offen += 1
	await _poll_ra_lauf()
	_poll_ra_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _poll_ra täte bis zum Neustart nichts mehr.
	if _poll_ra_offen == 0 and _ra_busy:
		_ra_busy = false


func _poll_ra_lauf() -> void:
	if _s.is_empty() or _s.platform != "ra" or _ra_busy or not Achievements.has_ra():
		return
	_ra_busy = true
	var r := await Net.get_json(Achievements._ra_url("API_GetUserRecentAchievements.php", { "m": 30 }))
	_ra_busy = false
	if _s.is_empty() or _s.platform != "ra" or not r.ok or not (r.data is Array):
		return
	var list := parse_ra_recent(r.data)
	var now := {}
	var by_key := {}
	for a in list:
		now[a.key] = int(a.at)
		by_key[a.key] = a
	var fresh := diff_new(_s.known, now, bool(_s.ra_base), int(_s.started))
	for k in now.keys():
		_s.known[k] = true
	_log("ra: %d zuletzt, %d neu%s" % [now.size(), fresh.size(), " (Stand)" if _s.ra_base else ""])
	_s.ra_base = false
	var arrived: Array = []
	var fresh_ids := {}
	for k in fresh:
		fresh_ids[str((by_key[k] as Dictionary).id)] = true
	for i in fresh.size():
		var a: Dictionary = by_key[fresh[i]]
		var key := "ra:%d" % int(a.game_id)
		_s.key = key
		var pct := _ra_rarity(str(a.id))
		var e := {
			"game": str(a.game) if str(a.game) != "" else str(_s.title), "game_key": key, "api": str(a.id),
			"name": str(a.title), "desc": str(a.desc), "icon": str(a.icon), "rarity": pct, "platform": "ra",
			"unlocked_at": int(a.at) if int(a.at) > 0 else int(Time.get_unix_time_from_system()),
			"hardcore": bool(a.hardcore), "ra_points": int(a.points),
			"complete": i == fresh.size() - 1 and _ra_complete(int(a.game_id), fresh_ids),
		}
		e["points"] = entry_points(e)
		arrived.append(a)
		record(e)
	if not arrived.is_empty():
		Achievements.ra_unlocks_arrived(arrived)


## Seltenheit eines RA-Erfolgs aus der geladenen Liste des laufenden Spiels (sonst unbekannt).
func _ra_rarity(id: String) -> float:
	var res := Achievements.cached({ "id": str(_s.get("gid", "")) })
	for a in res.get("list", []):
		if str(a.get("id", "")) == id:
			return float(a.get("rarity", -1.0))
	return -1.0


## Ist das RA-Spiel mit den neuen Freischaltungen (fresh_ids) komplett? Aus der geladenen Liste,
## sonst aus dem Fortschritt der Übersicht; ohne beides nie.
func _ra_complete(game_id: int, fresh_ids: Dictionary) -> bool:
	var res := Achievements.cached({ "id": str(_s.get("gid", "")) })
	if int(res.get("ra_id", 0)) == game_id and res.has("list"):
		var had := 0
		for a in res.list:
			if bool(a.get("unlocked", false)) and not fresh_ids.has(str(a.get("id", ""))):
				had += 1
		return complete_after((res.list as Array).size(), had, fresh_ids.size())
	for p in Achievements.ra_progress:
		if int(p.get("ra_id", 0)) == game_id:
			return complete_after(int(p.get("total", 0)), int(p.get("unlocked", 0)), fresh_ids.size())
	return false


# --- Merken und zeigen -----------------------------------------------------------------------

## Eine Freischaltung speichern, melden und zeigen (auch aus Tests).
func record(e: Dictionary) -> void:
	var key := str(e.get("game_key", ""))
	for h in _data.history:
		if str(h.get("game_key", "")) == key and str(h.get("api", "")) == str(e.get("api", "")) and bool(h.get("hardcore", false)) == bool(e.get("hardcore", false)):
			_log("schon gemeldet: %s" % str(e.get("api", "")))
			return
	var entry := e.duplicate()
	_data.history.push_front(entry)
	if (_data.history as Array).size() > HISTORY_MAX:
		_data.history = (_data.history as Array).slice(0, HISTORY_MAX)
	if key != "":
		var g: Dictionary = _data.games.get(key, {})
		g["title"] = str(e.get("game", g.get("title", "")))
		g["platform"] = str(e.get("platform", "steam"))
		g["points"] = int(g.get("points", 0)) + int(e.get("points", 0))
		g["count"] = int(g.get("count", 0)) + 1
		g["at"] = int(e.get("unlocked_at", 0))
		_data.games[key] = g
	_save_soon()
	unlocked.emit(entry)
	changed.emit()
	if enabled():
		popups.show_entry(entry, decorate(entry, bool(Config.get_value("notify.unlock_rare", true))))
	# Auch in der Mitteilungsliste (leise: das Pop-up hat schon geklungen); A führt zu den Erfolgen des Spiels.
	var g := {}
	if key.begins_with("steam:"):
		g = Library.get_game(key)
		if g.is_empty():
			g = { "id": key, "title": str(e.get("game", "")), "source": "steam", "system": "steam", "appid": int(key.get_slice(":", 1)) }
	elif not Launcher.current.is_empty():
		g = Launcher.current.duplicate()
	var what := "Alle Erfolge freigeschaltet" if bool(e.get("complete", false)) else "Erfolg freigeschaltet"
	Toasts.merken({ "title": str(e.get("name", "")), "sub": "%s · %s · +%d Uzai-Punkte" % [what, str(e.get("game", "")), int(e.get("points", 0))],
		"icon": "trophy", "image": str(e.get("icon", "")),
		"go": Achievements._open_achievements.bind(g) if not g.is_empty() else Callable(), "go_text": "Erfolge" })
