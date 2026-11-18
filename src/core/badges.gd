extends Node
## Profil-Level und Abzeichen (Autoload „Badges“). Sammelt die Zahlen aus Bibliothek,
## Sitzungen, Erfolgen (Steam, RetroAchievements) und Uzais Freischaltungen (Unlocks, falls da),
## rechnet über badges_logic.gd Level und Stufen aus und meldet Neues mit einem Pop-up
## (badge_popup.gd).
##
## Nicht aufdringlich: Beim allerersten Lauf gibt es für die Abzeichen, die schon verdient
## sind, kein Pop-up je Abzeichen, sondern einmal „Du hast 14 Abzeichen freigeschaltet“. Beim
## Start (Daten kommen nach und nach) wird gesammelt und erst gemeldet, wenn alles da ist; was
## seit dem letzten Mal dazukam, kommt als eine Zusammenfassung. Im Spiel wartet ein Pop-up, bis
## Uzai wieder vorn ist; mehr als zwei auf einmal werden zu einer Zusammenfassung.
##
## Gespeichert in badges.json: Stufen, Zeitpunkt je Stufe, Level, höchste Zahlen (gehen nie
## zurück), bekannte Erfolgslisten (Punkte nach Seltenheit) und eigene Zähler (Bildschirmfotos,
## Remote Play, Spiele mit Freunden).

signal changed
signal badge_unlocked(id: String, tier: int)
signal level_up(level: int)

const L := preload("res://src/core/badges_logic.gd")
const BadgePopup := preload("res://src/ui/badge_popup.gd")
const BadgeLogos := preload("res://src/core/badge_logos.gd")
const Ach := preload("res://src/core/achievements.gd")
const FILE := "badges.json"
const SETTLE_MIN := 6.0          ## so lange nach dem Start mindestens sammeln (s)
const SETTLE_MAX := 150.0        ## spätestens dann melden, auch wenn Steam noch zählt

var tiers := {}                  ## Abzeichen-ID -> Stufe 0…4
var facts := {}                  ## die Zahlen dahinter
var points := {}                 ## { total, ach, play, badges }
var level := {}                  ## wie L.level_of
var earned_at := {}              ## Abzeichen-ID -> [Unix-Zeit je Stufe]
var demo := false
var popups := true               ## Pop-ups zeigen (in der Demo aus, außer --badges-popups)
var file := FILE                 ## Datei im Datenordner (Tests nehmen eine eigene)
var announced: Array = []        ## alles, was gemeldet wurde (Tests, Fehlersuche)
var _state := {}
var _first := false              ## noch nie gerechnet (kein badges.json)
var _settled := false
var _quiet := false              ## beim Abschluss des Start-Sammelns: nichts einzeln melden
var _start_tiers := {}
var _start_level := 0
var _started_ms := 0
var _dirty := false
var _timer: Timer
var _settle_timer: Timer
var _popup: CanvasLayer
var _held: Array = []            ## Pop-ups, die auf das Ende des Spiels warten
var _session := {}               ## laufende Sitzung: { id, rp, together }


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	demo = "--demo" in args
	popups = not demo or "--badges-popups" in args
	_started_ms = Time.get_ticks_msec()
	_load()
	# Die Konsolen-Logos, die schon auf der Platte liegen, im Hintergrund vorbereiten (Startseite, Abzeichen).
	BadgeLogos.aufwaermen()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 1.5
	_timer.timeout.connect(recompute)
	add_child(_timer)
	_settle_timer = Timer.new()
	_settle_timer.wait_time = 2.0
	_settle_timer.timeout.connect(_check_settled)
	add_child(_settle_timer)
	_settle_timer.start()
	_popup = BadgePopup.new()
	add_child(_popup)
	Achievements.updated.connect(func(w: String) -> void:
		if w != "profile_count":
			soon()
	)
	Library.changed.connect(soon)
	Launcher.started.connect(_on_started)
	Launcher.ended.connect(_on_ended)
	Social.updated.connect(func(_w: String) -> void: _check_together())
	var u := unlocks()
	if u and u.has_signal("unlocked"):
		u.connect("unlocked", func(_a = null) -> void: soon())
	var cap := get_node_or_null("/root/Capture")
	if cap and cap.has_signal("changed"):
		cap.connect("changed", func(w = "") -> void:
			if str(w) == "files":
				soon()
		)
	# Erst rechnen, wenn die Bibliothek steht (sonst „Level 1“ für einen Augenblick).
	recompute.call_deferred()


## Uzais eigene Freischaltungen mit Uzai-Punkten (Pop-ups im Spiel; eigener Autoload, falls da).
## Erwartet: total_points() -> int, history() -> Array, Signal unlocked.
func unlocks() -> Node:
	return get_node_or_null("/root/Unlocks")


## Bald neu rechnen (mehrere Änderungen kurz hintereinander: einmal).
func soon() -> void:
	if is_instance_valid(_timer):
		_timer.start()


# --- Lesen ---------------------------------------------------------------------------------

func level_number() -> int:
	return int(level.get("level", 1))


func total_points() -> int:
	return int(points.get("total", 0))


func earned_count() -> int:
	return L.count_earned(tiers)


## Alle Abzeichen für die Oberfläche, in der Reihenfolge des Katalogs:
## [{ def, id, tier, value, progress, at (Unix der letzten Stufe), visible }]
func entries(only_visible := true) -> Array:
	var ctx := { "ra": Achievements.has_ra() or int(facts.get("ra_unlocked", 0)) > 0, "platforms": facts.get("present", {}) }
	var out: Array = []
	for d in L.DEFS:
		var id := str(d.id)
		var t := int(tiers.get(id, 0))
		var vis := L.visible(d, ctx, t)
		if only_visible and not vis:
			continue
		var v := float(facts.get(str(d.fact), 0.0))
		var at_list: Array = earned_at.get(id, [])
		out.append({ "def": d, "id": id, "tier": t, "value": v, "progress": L.progress(d, v, t),
			"at": int(at_list[t - 1]) if t > 0 and at_list.size() >= t else 0, "visible": vis })
	return out


## Für die Reihe im Profil: zuletzt verdiente zuerst, dann die, die am nächsten dran sind.
func showcase(limit := 12) -> Array:
	var list := entries()
	var got := list.filter(func(e): return int(e.tier) > 0)
	got.sort_custom(func(a, b): return int(a.at) > int(b.at) if int(a.at) != int(b.at) else int(a.tier) > int(b.tier))
	var open := list.filter(func(e): return int(e.tier) == 0)
	open.sort_custom(func(a, b): return float(a.progress.frac) > float(b.progress.frac))
	return (got + open).slice(0, limit)


# --- Rechnen -------------------------------------------------------------------------------

func recompute() -> void:
	var now_facts := collect()
	var best: Dictionary = _state.get("best", {})
	var merged := L.keep_best(best, now_facts)
	merged["present"] = now_facts.get("present", {})
	var r := L.compute(merged, _state.get("tiers", {}))
	var old_tiers: Dictionary = (_state.get("tiers", {}) as Dictionary).duplicate()
	var old_level := int(_state.get("level", 0))
	facts = r.facts
	tiers = r.tiers
	points = r.points
	level = r.level
	var stamp := int(Time.get_unix_time_from_system())
	for id in tiers.keys():
		var t := int(tiers[id])
		var list: Array = earned_at.get(id, [])
		while list.size() < t:
			list.append(stamp)
		if t > 0:
			earned_at[id] = list
	var keep := {}
	for k in merged.keys():
		if merged[k] is int or merged[k] is float:
			keep[k] = merged[k]
	_state["best"] = keep
	_state["tiers"] = tiers.duplicate()
	_state["level"] = level_number()
	_state["at"] = earned_at
	_state["v"] = 1
	# Erst nach dem Start-Sammeln speichern: sonst gälte beim nächsten Mal als „schon gemeldet“,
	# was nie gezeigt wurde (Uzai früh beendet).
	if _settled:
		_save()
	changed.emit()
	if _settled and not _quiet:
		_announce(L.diff(old_tiers, tiers, old_level, level_number(), false))


## Die Zahlen von jetzt (ohne die gespeicherten Höchststände).
func collect() -> Dictionary:
	var games: Array = []
	for g in Library.visible_games():
		if Library.owned_only(g):
			continue
		games.append({ "system": str(g.get("system", "")), "source": str(g.get("source", "")), "secs": Library.playtime(g) })
	var st: Dictionary = Achievements.steam_stats
	var f := L.playtime_facts(games, int(st.get("minutes", 0)), int(st.get("played", 0)))
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	f.merge(L.session_facts(Library.load_sessions(), bias), true)
	var tot: Dictionary = Achievements.totals()
	var rs: Dictionary = Achievements.ra_stats()
	var hard := 0
	var ra_games := 0
	for g in Achievements.ra_progress:
		hard += int(g.get("hardcore", 0))
		if int(g.get("unlocked", 0)) > 0:
			ra_games += 1
	var steam_games := 0
	if int(st.get("counted", 0)) > 0:
		steam_games = int(st.get("started", 0))
	else:
		for g in Achievements.steam_progress:
			if int(g.get("unlocked", 0)) > 0:
				steam_games += 1
	f["ach_total"] = int(tot.get("unlocked", 0))
	f["perfect"] = int(tot.get("complete", 0))
	f["ach_games"] = ra_games + steam_games
	f["ra_unlocked"] = int(rs.get("unlocked", 0))
	f["ra_hardcore"] = hard
	f["ra_mastered"] = int(rs.get("mastered", 0))
	f["ra_beaten"] = int(rs.get("beaten", 0))
	# Erfolgspunkte: bekannte Listen genau (nach Seltenheit), der Rest geschätzt.
	var known: Dictionary = _state.get("known", {})
	_learn_lists(known)
	_state["known"] = known
	var all_known := merge_unlocks(known, _unlock_games(), _unlock_history())
	var ap := L.ach_points(all_known, int(f.ach_total))
	var ach := int(ap.points)
	var u := unlocks()
	if u and u.has_method("total_points"):
		ach = maxi(ach, int(u.call("total_points")))
	f["ach_points"] = ach
	f["ach_total"] = maxi(int(f.ach_total), int(ap.known))
	f["ach_rare10"] = int(ap.rare10)
	f["ach_rare1"] = int(ap.rare1)
	var c: Dictionary = _state.get("count", {})
	f["together"] = (c.get("together", {}) as Dictionary).size()
	f["remote_play"] = int(c.get("remote_play", 0))
	# Bildschirmfotos und Clips: was in der Galerie liegt (Capture), mindestens die eigene Zählung.
	var cap := get_node_or_null("/root/Capture")
	var shots := 0
	if cap and cap.has_method("count_items"):
		shots = int(cap.call("count_items"))
	f["captures"] = maxi(int(c.get("captures", 0)), shots)
	return f


## Erfolgslisten, die gerade im Speicher liegen (Spielseiten, seltenste Erfolge, Uzais
## Freischaltungen), in die bekannten Spiele übernehmen.
func _learn_lists(known: Dictionary) -> void:
	var lists: Array = []
	var games: Variant = Achievements.get("_games")
	if games is Dictionary:
		lists.append_array((games as Dictionary).values())
	var sl: Variant = Achievements.get("_steam_lists")
	if sl is Dictionary:
		lists.append_array((sl as Dictionary).values())
	for res in lists:
		if not (res is Dictionary) or (res as Dictionary).get("list", []).is_empty():
			continue
		var key := ""
		if int(res.get("appid", 0)) > 0:
			key = "steam:%d" % int(res.appid)
		elif int(res.get("ra_id", 0)) > 0:
			key = "ra:%d" % int(res.ra_id)
		else:
			continue
		var s := L.game_summary(res)
		var old: Dictionary = known.get(key, {})
		if old.is_empty() or int(s.n) >= int(old.get("n", 0)):
			known[key] = s
	Config.cap(known, 4000)


func _unlock_games() -> Dictionary:
	var u := unlocks()
	if u and u.has_method("games"):
		var g: Variant = u.call("games")
		if g is Dictionary:
			return g
	return {}


func _unlock_history() -> Array:
	var u := unlocks()
	if u and u.has_method("history"):
		var h: Variant = u.call("history")
		if h is Array:
			return h
	return []


## Uzais eigene Freischaltungen dazu (Unlocks): je Spiel { points, count } aus games() und die
## Seltenheit aus history(). Je Spiel zählt der vollständigere Stand; seltene Erfolge aus der
## Liste und aus den Freischaltungen nie doppelt (das Größere je Spiel).
static func merge_unlocks(known: Dictionary, ugames: Dictionary, uhist: Array) -> Dictionary:
	var out := known.duplicate(true)
	var hr := {}
	for h in uhist:
		if not (h is Dictionary) or bool(h.get("test", false)):
			continue
		var key := str(h.get("game_key", ""))
		if key == "":
			continue
		var pct := float(h.get("rarity", -1.0))
		var e: Dictionary = hr.get(key, { "r10": 0, "r1": 0 })
		if pct >= 0.0 and pct < 10.0:
			e.r10 = int(e.r10) + 1
		if pct >= 0.0 and pct < 1.0:
			e.r1 = int(e.r1) + 1
		hr[key] = e
	for key in ugames.keys():
		var g: Variant = ugames[key]
		if not (g is Dictionary) or str(key).begins_with("test"):
			continue
		var n := int(g.get("count", 0))
		var cur: Dictionary = out.get(key, {})
		if cur.is_empty() or n > int(cur.get("n", 0)):
			out[key] = { "n": n, "p": int(g.get("points", 0)), "r10": int(cur.get("r10", 0)), "r1": int(cur.get("r1", 0)) }
	for key in hr.keys():
		var cur2: Dictionary = out.get(key, { "n": 0, "p": 0, "r10": 0, "r1": 0 })
		cur2["r10"] = maxi(int(cur2.get("r10", 0)), int(hr[key].r10))
		cur2["r1"] = maxi(int(cur2.get("r1", 0)), int(hr[key].r1))
		out[key] = cur2
	return out


# --- Ereignisse ----------------------------------------------------------------------------

func _count_add(key: String, n: int) -> void:
	var c: Dictionary = _state.get("count", {})
	c[key] = int(c.get(key, 0)) + n
	_state["count"] = c
	soon()


func _together(game_id: String) -> void:
	if game_id == "":
		return
	var c: Dictionary = _state.get("count", {})
	var t: Dictionary = c.get("together", {})
	if t.has(game_id):
		return
	t[game_id] = int(Time.get_unix_time_from_system())
	c["together"] = t
	_state["count"] = c
	soon()


func _on_started(g: Dictionary) -> void:
	_session = { "id": str(g.get("id", "")), "rp": false }
	await get_tree().create_timer(2.0).timeout
	_check_together()


func _on_ended(_g: Dictionary, _secs: int) -> void:
	_session = {}
	soon()
	if not _held.is_empty():
		await get_tree().create_timer(2.5).timeout
		_flush_held()


## Spielt ein Steam-Freund gerade dasselbe Spiel oder läuft Remote Play: „mit Freunden“.
func _check_together() -> void:
	if not Launcher.in_game or _session.is_empty():
		return
	var g: Dictionary = Launcher.current
	var gid := str(g.get("id", ""))
	if Launcher.remote_play and not bool(_session.get("rp", false)):
		_session["rp"] = true
		_count_add("remote_play", 1)
		_together(gid)
	var appid := str(g.get("appid", ""))
	var title := Ach.norm(str(g.get("title", "")))
	for f in Social.steam_friends:
		if str(f.get("state", "")) != "game":
			continue
		if (appid != "" and appid != "0" and str(f.get("game_id", "")) == appid) or (title != "" and Ach.norm(str(f.get("game", ""))) == title):
			_together(gid)
			return


# --- Melden --------------------------------------------------------------------------------

func _check_settled() -> void:
	if _settled:
		return
	var age := (Time.get_ticks_msec() - _started_ms) / 1000.0
	if age < SETTLE_MIN:
		return
	var busy: bool = Achievements.loading or Achievements.profile_loading or bool(Achievements.steam_stats.get("counting", false))
	if busy and age < SETTLE_MAX:
		return
	_settled = true
	_settle_timer.stop()
	_quiet = true
	recompute()
	_quiet = false
	var d := L.diff(_start_tiers, tiers, _start_level, level_number(), _first)
	_first = false
	if int(d.summary) > 0:
		_show({ "kind": "summary", "count": int(d.summary), "level": level_number(), "first": true })
		return
	var fresh: Array = d.fresh
	if fresh.size() == 1 and not d.level_up:
		_announce(d)
	elif not fresh.is_empty():
		_show({ "kind": "summary", "count": fresh.size(), "level": level_number(), "first": false, "best": fresh[0] })
	elif d.level_up:
		_announce(d)


func _announce(d: Dictionary) -> void:
	var list: Array = d.get("popups", [])
	for e in list:
		badge_unlocked.emit(str(e.id), int(e.tier))
	if bool(d.get("level_up", false)):
		level_up.emit(int(d.level))
	if list.size() > 2:
		_show({ "kind": "summary", "count": list.size(), "level": int(d.level), "first": false, "best": list[0] })
	else:
		for e in list:
			_show({ "kind": "badge", "id": str(e.id), "tier": int(e.tier) })
	if bool(d.get("level_up", false)):
		_show({ "kind": "level", "level": int(d.level) })


## Ein Pop-up zeigen – im Spiel erst danach (Uzai liegt dann ja nicht vorn).
func _show(item: Dictionary) -> void:
	announced.append(item)
	_note(item)
	if not popups:
		return
	if Launcher.in_game and not Launcher.guide_open:
		_held.append(item)
		return
	_popup.call("push", item)


func _flush_held() -> void:
	if Launcher.in_game:
		return
	var list := _held.duplicate()
	_held.clear()
	var badges := list.filter(func(i): return str(i.kind) == "badge")
	if badges.size() > 2:
		list = list.filter(func(i): return str(i.kind) != "badge")
		list.push_front({ "kind": "summary", "count": badges.size(), "level": level_number(), "first": false, "best": badges[0] })
	for i in list:
		_popup.call("push", i)


## Auch in die Mitteilungen im Guide (ohne zweites Pop-up).
func _note(item: Dictionary) -> void:
	var t := ""
	var s := ""
	match str(item.kind):
		"badge":
			var d := L.def_of(str(item.id))
			t = "Abzeichen: " + L.tier_title(d, int(item.tier))
			s = "%s · %s" % [L.TIER_NAMES[int(item.tier)], str(d.get("name", ""))]
		"level":
			t = "Level %d erreicht" % int(item.level)
			s = L.level_left_text(total_points())
		"summary":
			t = summary_text(item)
			s = "Level %d · %s Uzai-Punkte" % [int(item.level), L.num(total_points())]
	# kind „abzeichen“: steht in „Alle Mitteilungen“, nicht im Guide-Reiter System (dort nur echte Ereignisse).
	Toasts.merken({ "title": t, "sub": s, "icon": "star_f", "go": open_page, "go_text": "Abzeichen", "kind": "abzeichen" })


static func summary_text(item: Dictionary) -> String:
	return BadgePopup.summary_text(item)


## Die Abzeichen-Seite öffnen (aus Pop-ups, Mitteilungen, Profil).
func open_page(focus_id := "") -> void:
	var m: Node = get_tree().current_scene
	if m == null or not m.has_method("open_layer"):
		return
	var page = load("res://src/ui/layers/badges_page.gd").new()
	page.set("focus_id", focus_id)
	m.call("open_layer", page)


## Für Proben und Tests: ein Pop-up wie beim Freischalten.
func preview(item: Dictionary) -> void:
	if is_instance_valid(_popup):
		_popup.call("push", item)


# --- Speichern -----------------------------------------------------------------------------

func _load() -> void:
	var d: Variant = Config.read_json(Config.path(file), null)
	_first = not (d is Dictionary) or not (d as Dictionary).has("tiers")
	_state = d if d is Dictionary else {}
	var t: Variant = _state.get("tiers", {})
	_start_tiers = {}
	if t is Dictionary:
		for k in t.keys():
			_start_tiers[str(k)] = int(t[k])
	_state["tiers"] = _start_tiers.duplicate()
	_start_level = int(_state.get("level", 0))
	var at: Variant = _state.get("at", {})
	earned_at = {}
	if at is Dictionary:
		for k in at.keys():
			if at[k] is Array:
				earned_at[str(k)] = (at[k] as Array).map(func(x): return int(x))
	tiers = _start_tiers.duplicate()
	level = L.level_of(0)


func _save() -> void:
	if demo and not "--badges-popups" in OS.get_cmdline_user_args():
		return
	Config.write_json(Config.path(file), _state)
