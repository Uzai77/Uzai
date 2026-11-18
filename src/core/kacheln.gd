extends RefCounted
## Lebendige Kacheln (Roadmap 101 → 124): Was gerade an einem Spiel los ist, steht als kleines
## Abzeichen direkt auf seinem Cover – höchstens eins je Kachel, nach fester Rangfolge (RANK).
## Die Kachel selbst zeichnet kachel_zustand.gd; hier steht nur, welcher Zustand gilt.
##
## Quellen – nur Daten, die Uzai ohnehin hat, oder sparsam über offizielle Wege:
##   Update lädt / wartet   Installs (Uzais Downloads, Steams appmanifest; nur lesen)
##   Server gestört         offizielle Statusseite von Epic (status.epicgames.com, Statuspage-
##                          Schnittstelle), nur für Spiele, die dort genau so heißen; höchstens alle
##                          STATUS_TTL, nie im Spiel. Für Steam gibt es keine offizielle Statusseite,
##                          darum zeigt Uzai dort nichts (lieber gar nichts als geraten).
##   Freunde spielen        Steam-Freunde (App-ID) und Discord-Freunde (gleicher Spielname)
##   Rabatt                 deine Steam-Wunschliste: das Spiel selbst oder ein DLC davon im Angebot
##   Neue Erfolge           die Zahl der Erfolge ist gestiegen, seit Uzai sie zuletzt sah
##   Patch / Neuigkeit      Steam-Neuigkeiten aus „Für dich“ (Zwischenspeicher), heute oder gestern;
##                          „Patch“ nur, wenn die Entwickler den Beitrag als Patchnotes markiert haben
## Ein „Event“ zeigt Uzai nicht: Steams Neuigkeiten markieren nur Patchnotes verlässlich.
##
## Zustand: { kind, icon, color, text (immer zu sehen), more (beim Aufwachen darunter),
##   frac (Fortschritt 0…1, sonst -1), people ([{ name, avatar }]) }.
## Abschaltbar: Einstellungen → Spiele → „Lebendige Kacheln“ (system.live_tiles).
## Die Auswahl ist ohne Fenster testbar (tests/logic_kacheln.gd).

const Lang := preload("res://src/core/lang.gd")
const P := preload("res://src/core/install_parse.gd")
const StoreS := preload("res://src/core/store.gd")
const ForYou := preload("res://src/ui/components/for_you.gd")

## Rangfolge: kleiner gewinnt. Was dich gerade betrifft (lädt, Server weg), vor dem, was nett ist.
const RANK := { "update_laeuft": 0, "gestoert": 1, "freunde": 2, "update": 3, "rabatt": 4, "erfolge": 5, "patch": 6, "news": 7 }

const STATUS_URL := "https://status.epicgames.com/api/v2/summary.json"
const STATUS_FILE := "cache/kacheln_status.json"
const STATUS_TTL := 15 * 60            ## Statusseite höchstens so oft fragen …
const STATUS_RETRY := 10 * 60          ## … nach einem Fehlschlag frühestens wieder
const STATUS_MAX_AGE := 30 * 60        ## älter gilt der Stand nicht mehr (lieber nichts zeigen)
const STATUS_MAX := 400                ## so viele Einträge der Statusseite höchstens lesen
## Schwere der Statuspage-Zustände; alles ab 1 zeigt Uzai.
const SEVERITY := { "operational": 0, "under_maintenance": 1, "degraded_performance": 2, "partial_outage": 3, "major_outage": 4 }

const ACH_FILE := "cache/kacheln_erfolge.json"
const ACH_DAYS := 7                    ## „neue Erfolge“ so lange zeigen
const ACH_MAX := 4000

static var _status := {}               ## { at, ok, names: [normalisiert], bad: { name: zustand } }
static var _status_loaded := false
static var _status_busy := false
static var _ach := {}                  ## Spiel-ID -> { n: Anzahl, plus, at }
static var _ach_loaded := false
static var _ach_dirty := false


## Eingeschaltet? (Standard: ja)
static func on() -> bool:
	return bool(Config.get_value("system.live_tiles", true))


# --- Auswahl (reine Funktionen) ------------------------------------------------------------------

## Der wichtigste Zustand aus mehreren ({} wenn keiner).
static func best(states: Array) -> Dictionary:
	var out: Dictionary = {}
	var r := 1000
	for s in states:
		if not (s is Dictionary) or (s as Dictionary).is_empty():
			continue
		var k := int(RANK.get(str(s.get("kind", "")), 999))
		if k < r:
			r = k
			out = s
	return out


## Titel zum Vergleichen: klein, ohne Zeichen außer Buchstaben und Ziffern („Rocket League®“ =
## „rocket league“).
static func norm(title: String) -> String:
	var out := ""
	for ch in title.to_lower():
		if ch == " " or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch.unicode_at(0) > 0xbf:
			out += ch
	return " ".join(out.split(" ", false))


## Update: läuft es (über Uzai) oder wartet es (laut Steam)? entry: Installs.entry, pending:
## DlQueue.update_state ({} = keins).
static func update_state(entry: Dictionary, pending: Dictionary) -> Dictionary:
	if not entry.is_empty() and str(entry.get("kind", "")) == "update" and not (str(entry.get("phase", "")) in ["done", "failed", "cancelled"]):
		var frac := float(entry.get("frac", -1.0))
		var ph := str(entry.get("phase", ""))
		var t := "Update pausiert" if ph == "paused" else ("Update wartet" if ph == "queued"
				else ("Update · %d %%" % int(frac * 100.0) if frac >= 0.0 else "Update lädt"))
		return { "kind": "update_laeuft", "icon": "download", "color": "accent", "text": t,
			"more": str(entry.get("text", "")) if ph != "paused" else "In der Download-Zentrale fortsetzen", "frac": frac, "people": [] }
	if pending.is_empty():
		return {}
	var rest := int(pending.get("remaining", -1))
	var more := "Steam lädt es beim nächsten Start"
	match str(pending.get("phase", "")):
		"laeuft": more = "Steam lädt es gerade"
		"pausiert": more = "In Steam pausiert"
	return { "kind": "update", "icon": "download", "color": "text",
		"text": ("Update · %s" % P.gb(float(rest))) if rest > 0 else "Update verfügbar", "more": more, "frac": -1.0, "people": [] }


## Freunde, die das Spiel gerade spielen: steam aus Social.playing, discord: Discord-Freunde mit
## demselben Spielnamen. Je Person { name, avatar }; Steam zuerst, niemand doppelt.
static func friends_state(steam: Array, discord: Array) -> Dictionary:
	var people: Array = []
	var seen := {}
	for f in steam + discord:
		if not (f is Dictionary):
			continue
		var n := str(f.get("name", "")).strip_edges()
		if n == "" or seen.has(n.to_lower()):
			continue
		seen[n.to_lower()] = true
		people.append({ "name": n, "avatar": str(f.get("avatar", "")) })
	if people.is_empty():
		return {}
	var names := str(people[0].name) if people.size() == 1 else ("%s und %s" % [people[0].name, people[1].name] if people.size() == 2
			else "%s, %s und %d weitere" % [people[0].name, people[1].name, people.size() - 2])
	return { "kind": "freunde", "icon": "friends", "color": "ok",
		"text": "spielt gerade" if people.size() == 1 else "%d spielen gerade" % people.size(),
		"more": names, "frac": -1.0, "people": people.slice(0, 3) }


## Discord-Freunde (DiscordChat.friends), die ein Spiel dieses Titels spielen.
static func discord_playing(friends: Array, title: String) -> Array:
	var t := norm(title)
	if t == "":
		return []
	return friends.filter(func(f: Variant) -> bool:
		return f is Dictionary and str(f.get("state", "offline")) != "offline" and norm(str(f.get("game", ""))) == t)


## Rabatt auf der Wunschliste: das Spiel selbst oder ein DLC davon (dlc_ids aus Steams
## Spielangaben, parent aus der Shop-Schnittstelle). Das größte Angebot gewinnt.
static func sale_state(appid: int, wishlist: Array, dlc_ids: Array) -> Dictionary:
	if appid <= 0:
		return {}
	var top: Dictionary = {}
	var dlc := false
	for it in wishlist:
		if not (it is Dictionary) or int(it.get("discount", 0)) <= 0:
			continue
		var id := int(it.get("appid", 0))
		var own := id == appid
		var is_dlc := not own and (dlc_ids.has(id) or int(it.get("parent", 0)) == appid)
		if not (own or is_dlc):
			continue
		if top.is_empty() or int(it.discount) > int(top.discount):
			top = it
			dlc = is_dlc
	if top.is_empty():
		return {}
	var price := StoreS.price_text(int(top.get("price", 0))) if int(top.get("price", 0)) > 0 else ""
	var more := ("%s · %s" % [str(top.get("name", "")), price]) if dlc else ("Auf deiner Wunschliste · %s" % price if price != "" else "Auf deiner Wunschliste")
	return { "kind": "rabatt", "icon": "tag", "color": "sale",
		"text": ("DLC −%d %%" if dlc else "−%d %%") % int(top.discount), "more": more, "frac": -1.0, "people": [] }


## Neue Erfolge: Schritt der Erinnerung je Spiel. old: bisheriger Eintrag ({} = noch nie gesehen),
## total: jetzt bekannte Anzahl. Rückgabe [neuer Eintrag, Zustand]. Beim ersten Blick merkt sich
## Uzai nur die Zahl; steigt sie später, gibt es ACH_DAYS lang „+n Erfolge“.
static func ach_step(old: Dictionary, total: int, now: int) -> Array:
	if total <= 0:
		return [old, {}]
	var e := old.duplicate()
	if old.is_empty():
		return [{ "n": total, "plus": 0, "at": 0 }, {}]
	if total > int(old.get("n", 0)):
		# Kam vor Kurzem schon etwas dazu, zählt es mit („+3“ und dann noch „+2“ ergibt „+5“).
		var carry := int(old.get("plus", 0)) if now - int(old.get("at", 0)) < ACH_DAYS * 86400 else 0
		e = { "n": total, "plus": total - int(old.get("n", 0)) + carry, "at": now }
	elif total < int(old.get("n", 0)):
		e = { "n": total, "plus": 0, "at": 0 }
	var plus := int(e.get("plus", 0))
	if plus <= 0 or now - int(e.get("at", 0)) >= ACH_DAYS * 86400:
		return [e, {}]
	return [e, { "kind": "erfolge", "icon": "trophy", "color": "gold",
		"text": "+%s" % Lang.count(plus, "neuer Erfolg", "neue Erfolge"), "more": "Neu im Spiel, seit Uzai zuletzt nachsah", "frac": -1.0, "people": [] }]


## Neuigkeit oder Patch von heute bzw. gestern (Ortszeit, bias in Sekunden). items: neueste zuerst.
static func news_state(items: Array, now: int, bias: int) -> Dictionary:
	if items.is_empty() or not (items[0] is Dictionary):
		return {}
	var it: Dictionary = items[0]
	var at := int(it.get("date", 0))
	if at <= 0 or at > now + 3600:
		return {}
	var day_now := floori(float(now + bias) / 86400.0)
	var day_it := floori(float(at + bias) / 86400.0)
	var d := day_now - day_it
	if d < 0 or d > 1:
		return {}
	var patch := bool(it.get("patch", false))
	var when := "heute" if d == 0 else "gestern"
	return { "kind": "patch" if patch else "news", "icon": "refresh" if patch else "info", "color": "text",
		"text": ("Patch %s" if patch else "Neuigkeit %s") % when, "more": str(it.get("title", "")), "frac": -1.0, "people": [] }


## Statusseite (Statuspage, summary.json) lesen: { name (normalisiert): Zustand } für alles, was
## nicht „operational“ ist – je Eintrag der schlimmste Zustand aus ihm und seinen Unterpunkten
## (Gruppe „Fortnite“ mit „Login“, „Matchmaking“ …). names: alle Einträge der obersten Ebene.
static func parse_status(data: Variant) -> Dictionary:
	var out := { "names": [], "bad": {} }
	if not (data is Dictionary) or not (data.get("components") is Array):
		return out
	var by_id := {}
	var list: Array = (data.components as Array).slice(0, STATUS_MAX)
	for c in list:
		if c is Dictionary and str(c.get("id", "")) != "":
			by_id[str(c.id)] = c
	for c in list:
		if not (c is Dictionary) or c.get("group_id") != null:
			continue
		var name := norm(str(c.get("name", "")).left(80))
		if name == "":
			continue
		(out.names as Array).append(name)
		var worst := str(c.get("status", ""))
		if c.get("components") is Array:
			for cid in (c.components as Array).slice(0, 60):
				var sub: Variant = by_id.get(str(cid))
				if sub is Dictionary and int(SEVERITY.get(str(sub.get("status", "")), 0)) > int(SEVERITY.get(worst, 0)):
					worst = str(sub.status)
		if int(SEVERITY.get(worst, 0)) > 0:
			out.bad[name] = worst
	return out


## Zustand „Server gestört“ für einen Titel aus einem gelesenen Stand ({} wenn alles läuft).
static func status_state(title: String, st: Dictionary, now: int) -> Dictionary:
	if st.is_empty() or now - int(st.get("at", 0)) > STATUS_MAX_AGE:
		return {}
	var bad: Dictionary = st.get("bad", {}) if st.get("bad") is Dictionary else {}
	var s := str(bad.get(norm(title), ""))
	if s == "":
		return {}
	var t := "Server gestört"
	match s:
		"under_maintenance": t = "Wartung"
		"degraded_performance": t = "Server langsam"
		"major_outage": t = "Server ausgefallen"
	return { "kind": "gestoert", "icon": "warning", "color": "danger_text" if s in ["partial_outage", "major_outage"] else "warn",
		"text": t, "more": "Laut Epic-Statusseite", "frac": -1.0, "people": [] }


# --- Zustand eines Spiels (aus den Diensten) ------------------------------------------------------

## Der Zustand, den die Kachel dieses Spiels zeigt ({} = keiner oder ausgeschaltet).
static func for_game(g: Dictionary) -> Dictionary:
	if g.is_empty() or not on() or str(g.get("source", "")) == "disc":
		return {}
	var gid := str(g.get("id", ""))
	var appid := int(g.get("appid", 0)) if str(g.get("source", "")) == "steam" else 0
	var title := Library.display_title(g)
	var now := int(Time.get_unix_time_from_system())
	var states: Array = []
	if Library.is_installed(g):
		states.append(update_state(Installs.entry(gid), Installs.update_known(gid)))
	states.append(status_state(title, _status_now(), now))
	states.append(friends_state(Social.playing(appid), discord_playing(DiscordChat.friends, title)))
	if appid > 0:
		var d := Store.cached(appid)
		states.append(sale_state(appid, Store.wishlist, d.get("dlc_ids", []) if d.get("dlc_ids") is Array else []))
		var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		states.append(news_state(ForYou.news_for(appid), now, bias))
	var known: Array = Achievements.known(g)
	if known.size() == 2:
		_ach_load()
		var step := ach_step(_ach.get(gid, {}), int(known[1]), now)
		if step[0] != _ach.get(gid, {}):
			_ach[gid] = step[0]
			_ach_dirty = true
		states.append(step[1])
	return best(states)


## Gemerkte Erfolgs-Zahlen sichern (nach dem Aufbau eines Regals; nur wenn sich etwas tat).
static func flush() -> void:
	if not _ach_dirty or Library.demo:
		return
	_ach_dirty = false
	Config.cap(_ach, ACH_MAX)
	Config.write_json(Config.path(ACH_FILE), _ach)


static func _ach_load() -> void:
	if _ach_loaded:
		return
	_ach_loaded = true
	if Library.demo:
		return
	var d: Variant = Config.read_json(Config.path(ACH_FILE), {})
	if d is Dictionary:
		for k in d:
			if d[k] is Dictionary:
				_ach[str(k)] = { "n": int(d[k].get("n", 0)), "plus": int(d[k].get("plus", 0)), "at": int(d[k].get("at", 0)) }


# --- Statusseite -----------------------------------------------------------------------------------

static func _status_now() -> Dictionary:
	if not _status_loaded:
		_status_loaded = true
		if not Library.demo:
			var d: Variant = Config.read_json(Config.path(STATUS_FILE), {})
			if d is Dictionary:
				_status = { "at": int(d.get("at", 0)), "ok": bool(d.get("ok", false)),
					"names": d.get("names", []) if d.get("names") is Array else [],
					"bad": d.get("bad", {}) if d.get("bad") is Dictionary else {} }
	return _status


## Vorführung und Tests: Stand der Statusseite direkt setzen.
static func set_status(st: Dictionary) -> void:
	_status_loaded = true
	_status = st


## Lohnt die Statusseite? Nur, wenn ein Spiel der Bibliothek von Epic ist oder so heißt wie ein
## Eintrag der Seite (vom letzten Mal).
static func status_wanted(vis: Array, names: Array) -> bool:
	for g in vis:
		if str(g.get("source", "")) == "epic" or (not names.is_empty() and names.has(norm(str(g.get("title", ""))))):
			return true
	return false


## Statusseite nachladen, wenn fällig; danach done(), wenn sich etwas geändert hat.
## Nie im Spiel, nie in der Vorführung, nur eingeschaltet.
static func load_status(vis: Array, done: Callable) -> void:
	if _status_busy or Library.demo or Launcher.in_game or not on():
		return
	var st := _status_now()
	var now := int(Time.get_unix_time_from_system())
	var ttl := STATUS_TTL if bool(st.get("ok", false)) else STATUS_RETRY
	if not st.is_empty() and now - int(st.get("at", 0)) < ttl:
		return
	if not status_wanted(vis, st.get("names", [])):
		return
	_status_busy = true
	var r: Dictionary = await Net.get_json(STATUS_URL)
	_status_busy = false
	var p := parse_status(r.data) if r.ok else { "names": st.get("names", []), "bad": {} }
	var before := JSON.stringify(st.get("bad", {}))
	_status = { "at": int(Time.get_unix_time_from_system()), "ok": bool(r.ok), "names": p.names, "bad": p.bad }
	Config.write_json(Config.path(STATUS_FILE), _status)
	if JSON.stringify(p.bad) != before and done.is_valid():
		done.call()
