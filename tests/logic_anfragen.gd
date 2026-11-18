extends Node
## Freundschaftsanfragen (Punkt 11) und „Was ist neu“ (Punkt 141): Anfragen aus Steams
## Freundesliste und aus dem Discord Social SDK, Zusammenführen, einmal melden, Annehmen und
## Ablehnen nur für Anfragen an dich; Fassungen vergleichen, Karte nur nach einem Update.
## Aufruf: godot --headless --path . res://tests/logic_anfragen.tscn

const FR := preload("res://src/core/friend_requests.gd")
const WN := preload("res://src/core/whats_new.gd")
const CM := preload("res://src/core/steam_cm.gd")

const A := "76561198000000101"
const B := "76561198000000102"
const C := "76561198000000103"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_steam_list()
	_merge()
	_announce()
	await _steam_answer()
	await _discord()
	await _social_demo()
	_versions()
	_items()
	_file()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Ein Eintrag der Freundesliste: ulfriendid (1, fixed64), efriendrelationship (2).
static func _friend(id: String, rel: int) -> PackedByteArray:
	var f := PackedByteArray()
	f.append_array(CM.Pb.f_fixed64(1, int(id)))
	f.append_array(CM.Pb.f_varint(2, rel))
	return CM.Pb.f_msg(2, f)


static func _list(incremental: bool, rows: Array) -> PackedByteArray:
	var b := CM.Pb.f_varint(1, 1 if incremental else 0)
	for r in rows:
		b.append_array(_friend(str(r[0]), int(r[1])))
	return b


func _steam_list() -> void:
	print("Steams Freundesliste")
	var fl := CM.parse_friends_list(_list(false, [[A, 3], [B, 2], [C, 4]]))
	check(fl.add == [A], "befreundet (3) zählt als Freund")
	check((fl.remove as Array).has(B) and (fl.remove as Array).has(C), "Anfragen sind keine Freunde")
	check(fl.requests == { B: 2, C: 4 }, "Anfrage an dich (2) und gesendete (4) erkannt")
	var cur := {}
	check(CM.apply_requests(cur, fl) and cur == { B: 2, C: 4 }, "erste Liste: Anfragen übernommen")
	check(not CM.apply_requests(cur, fl), "dieselbe Liste noch einmal: keine Änderung")
	var inc := CM.parse_friends_list(_list(true, [[B, 3]]))
	check(CM.apply_requests(cur, inc) and cur == { C: 4 }, "angenommen (schrittweise): Anfrage weg, die andere bleibt")
	check(CM.apply_requests(cur, CM.parse_friends_list(_list(true, [[C, 0]]))) and cur.is_empty(), "zurückgezogen (0): weg")
	CM.apply_requests(cur, CM.parse_friends_list(_list(true, [[A, 2]])))
	check(cur == { A: 2 }, "neue Anfrage kommt schrittweise dazu")
	check(CM.apply_requests(cur, CM.parse_friends_list(_list(false, []))) and cur.is_empty(), "leere volle Liste räumt alles ab")
	var resp := PackedByteArray()
	resp.append_array(CM.Pb.f_varint(1, 1))
	resp.append_array(CM.Pb.f_fixed64(2, int(B)))
	resp.append_array(CM.Pb.f_string(3, "Marlene"))
	var r := CM.parse_add_response(resp)
	check(int(r.eresult) == 1 and str(r.id) == B and str(r.name) == "Marlene", "Antwort auf Annehmen gelesen")
	check(int(CM.parse_add_response(PackedByteArray()).eresult) == 2, "leere Antwort gilt als Fehler")
	check(FR.steam_error(1) == "" and FR.steam_error(25).contains("voll") and FR.steam_error(99).contains("noch einmal") and not FR.steam_error(99).contains("99"),
			"Fehler von Steam als Satz (mit Rat, ohne rohen Code)")


func _merge() -> void:
	print("Zusammenführen")
	var st := FR.from_steam({ A: 2, B: 4, "kaputt": 2, C: 3 }, { A: { "name": "Zoe", "avatar": "a.jpg" } })
	check(st.size() == 2, "nur Anfragen, keine Freunde oder kaputten IDs")
	var a: Dictionary = st.filter(func(x): return str(x.id) == A)[0]
	check(str(a.dir) == FR.IN and str(a.name) == "Zoe" and str(a.avatar) == "a.jpg" and str(a.key) == "steam:" + A, "Anfrage an dich mit Name und Bild")
	var b: Dictionary = st.filter(func(x): return str(x.id) == B)[0]
	check(str(b.dir) == FR.OUT and str(b.name) == "Steam-Nutzer", "ohne bekannten Namen ein ehrlicher Platzhalter")
	var dc := FR.from_discord([{ "id": "5", "name": "", "username": "tarik" }, { "name": "ohne ID" }], [{ "id": "6", "name": "Pia" }])
	check(dc.size() == 2 and str(dc[0].name) == "tarik" and str(dc[0].dir) == FR.IN and str(dc[1].dir) == FR.OUT,
			"Discord: Anzeigename, sonst Nutzername; ohne ID weg")
	var all := FR.sorted(st + dc)
	check(str(all[0].dir) == FR.IN and str(all[1].dir) == FR.IN and str(all[2].dir) == FR.OUT, "Anfragen an dich zuerst")
	check(str(all[0].name) == "tarik" and str(all[1].name) == "Zoe", "innerhalb nach Namen")
	check(FR.incoming(all, "steam").size() == 1 and FR.outgoing(all).size() == 2, "nach Richtung und Dienst filtern")
	check(FR.line(a).begins_with("Möchte") and FR.line(b).begins_with("Anfrage gesendet"), "Zeile in der Liste")


func _announce() -> void:
	print("Einmal melden")
	var list := FR.sorted(FR.from_steam({ A: 2, B: 2, C: 4 }, { A: { "name": "Zoe" } }))
	var fresh := FR.to_announce(list, [])
	check(fresh.size() == 1 and str(fresh[0].id) == A, "nur Anfragen an dich mit Namen (ohne Namen erst später, gesendete nie)")
	var seen := FR.remember([], fresh.map(func(r): return str(r.key)))
	check(FR.to_announce(list, seen).is_empty(), "schon gemeldet: kein zweites Mal")
	var many: Array = []
	for i in FR.SEEN_MAX + 20:
		many.append("k%d" % i)
	var kept := FR.remember([], many)
	check(kept.size() == FR.SEEN_MAX and kept[-1] == "k%d" % (FR.SEEN_MAX + 19) and not kept.has("k0"), "Gedächtnis gekappt, die ältesten fallen heraus")


func _steam_answer() -> void:
	print("Steam: Antworten")
	SteamCM.requests = { A: 2, C: 4 }
	check(await SteamCM.answer_request("", A, true) == "Nicht bei Steam angemeldet.", "ohne Anmeldung nichts")
	check(await SteamCM.answer_request("tok", C, true) == "Diese Anfrage gibt es nicht mehr.", "gesendete Anfrage lässt sich nicht annehmen")
	check(await SteamCM.answer_request("tok", B, false) == "Diese Anfrage gibt es nicht mehr.", "unbekannte Anfrage: nichts senden")
	SteamCM.requests = {}


func _discord() -> void:
	print("Discord: Anfragen aus dem SDK")
	var calls: Array = []
	var reply := { "friends": [{ "id": "1", "name": "Mira", "state": "online" }], "incoming": [{ "id": "5", "name": "Tarik" }],
			"outgoing": [{ "id": "6", "name": "Pia" }] }
	var box := { "answer": { "ok": true } }    ## Lambdas sehen Variablen nur zum Zeitpunkt ihrer Erstellung
	DiscordChat.demo = false
	DiscordChat.set("_started", true)
	DiscordChat.state = "bereit"
	DiscordChat.runner = func(cmd: String, args: Dictionary, _t: float) -> Dictionary:
		calls.append([cmd, args])
		if cmd == "dsdk-friends":
			return { "ok": true, "result": { "ok": true, "friends": reply.friends, "incoming": reply.incoming, "outgoing": reply.outgoing } }
		return { "ok": true, "result": box.answer }
	await DiscordChat.refresh_friends()
	check(DiscordChat.friends.size() == 1 and DiscordChat.requests_in.size() == 1 and DiscordChat.requests_out.size() == 1, "Freunde und Anfragen getrennt")
	check(str(DiscordChat.requests_in[0].name) == "Tarik", "Anfrage an dich mit Namen")
	check(await DiscordChat.answer_request("6", true) == "Diese Anfrage gibt es nicht mehr.", "gesendete Anfrage: nicht annehmbar")
	calls.clear()
	check(await DiscordChat.answer_request("5", true) == "" and calls.size() >= 1 and calls[0][0] == "dsdk-accept" and str(calls[0][1].id) == "5",
			"Annehmen geht als dsdk-accept an den Helfer")
	calls.clear()
	check(await DiscordChat.answer_request("5", false) == "" and calls[0][0] == "dsdk-reject", "Ablehnen als dsdk-reject")
	box.answer = { "ok": false, "error": "unsupported" }
	check((await DiscordChat.answer_request("5", true)).contains("neuere"), "alte SDK-Fassung: ehrlicher Hinweis")
	box.answer = { "ok": false, "error": "no pending request" }
	check((await DiscordChat.answer_request("5", false)).contains("no pending request"), "Fehler von Discord weitergereicht")
	DiscordChat.state = "fehler"
	check((await DiscordChat.answer_request("5", true)).contains("nicht verbunden"), "ohne Verbindung nichts")
	DiscordChat.state = "aus"
	DiscordChat.requests_in = []
	DiscordChat.requests_out = []
	DiscordChat.friends = []


func _social_demo() -> void:
	print("Social: beide Dienste (Vorführung)")
	DiscordChat.demo = true
	DiscordChat.call("_load_demo")
	Social._load_demo()
	await get_tree().process_frame
	var keys: Array = Social.requests.map(func(r): return str(r.key))
	check(keys.has("steam:76561190000000021") and keys.has("discord:1005") and keys.has("steam:76561190000000022") and keys.has("discord:1006"),
			"Steam und Discord in einer Liste")
	check(str(Social.requests[0].dir) == FR.IN and str(Social.requests[-1].dir) == FR.OUT, "Anfragen an dich oben")
	var marlene: Dictionary = Social.requests.filter(func(r): return str(r.key) == "steam:76561190000000021")[0]
	var ole: Dictionary = Social.requests.filter(func(r): return str(r.key) == "steam:76561190000000022")[0]
	check((await Social.answer_request(ole, true)).contains("andere Person"), "gesendete Anfrage beantwortet die andere Person")
	var before := Social.steam_friends.size()
	check(await Social.answer_request(marlene, true) == "", "Steam-Anfrage angenommen")
	check(Social.steam_friends.size() == before + 1 and not Social.steam_friend("76561190000000021").is_empty(), "jetzt bei den Freunden")
	check(not Social.requests.any(func(r): return str(r.key) == "steam:76561190000000021"), "Anfrage verschwunden")
	var tarik: Dictionary = Social.requests.filter(func(r): return str(r.key) == "discord:1005")[0]
	check(await Social.answer_request(tarik, false) == "", "Discord-Anfrage abgelehnt")
	check(not Social.requests.any(func(r): return str(r.key) == "discord:1005") and DiscordChat.friend("1005").is_empty(), "abgelehnt: weg und nicht befreundet")
	check(Social.requests.size() == 2 and FR.incoming(Social.requests).is_empty(), "nur gesendete bleiben stehen")


func _versions() -> void:
	print("Was ist neu: Fassungen")
	check(WN.compare("0.10.0", "0.9.2") == 1 and WN.compare("0.9.0", "0.9") == 0 and WN.compare("0.8.3", "0.9.0") == -1, "Fassungen als Zahlen verglichen")
	var e := { "0.9.0": [{ "icon": "search", "de": ["Suche", "Satz"], "en": ["Search", "Line"] }],
			"0.8.3": [{ "icon": "video", "de": ["Filme", "Satz"], "en": ["Movies", "Line"] }] }
	check(not WN.due("", "0.9.0", true, e), "allererster Start: keine Karte")
	check(WN.due("", "0.9.0", false, e), "Update von einer Fassung ohne Karte: einmal zeigen")
	check(WN.due("0.8.3", "0.9.0", false, e), "Update von 0.8.3: zeigen")
	check(not WN.due("0.9.0", "0.9.0", false, e), "schon gesehen: nicht noch einmal")
	check(not WN.due("0.8.3", "0.8.3", false, e), "ohne neue Fassung nichts")
	check(not WN.due("0.8.2", "0.8.5", false, { "0.9.0": e["0.9.0"] }), "Punkte einer späteren Fassung warten, bis sie da ist")


func _items() -> void:
	print("Was ist neu: Punkte")
	var e := { "0.9.0": [{ "icon": "search", "de": ["Suche", "S"], "en": ["Search", "L"] }, { "de": ["kaputt"] }],
		"0.8.3": [{ "icon": "video", "de": ["Filme", "S"], "en": ["Movies", "L"] }], "0.7.0": [{ "icon": "x", "de": ["Alt", "S"] }] }
	var it := WN.items(e, "0.8.2", "0.9.0")
	check(it.size() == 2 and str(it[0].version) == "0.9.0" and str(it[1].version) == "0.8.3", "alles nach der gesehenen Fassung, neueste zuerst")
	check(str(it[0].title) == "Suche" and str(it[0].icon) == "search", "Deutsch, mit Zeichen")
	check(str(WN.items(e, "0.8.2", "0.9.0", "en")[0].title) == "Search", "Englisch, wenn so eingestellt")
	check(str(WN.items(e, "", "0.7.0", "en")[0].title) == "Alt", "fehlt Englisch: Deutsch")
	check(WN.items(e, "", "0.9.0").size() == 1, "ohne gesehene Fassung nur die aktuelle; kaputte Punkte fallen weg")
	var big := { "1.0.0": [] }
	for i in 10:
		big["1.0.0"].append({ "de": ["T%d" % i, "S"] })
	check(WN.items(big, "", "1.0.0").size() == WN.MAX_ITEMS, "höchstens %d Punkte" % WN.MAX_ITEMS)


func _file() -> void:
	print("data/neu.json")
	var e := WN.load_entries()
	check(not e.is_empty(), "lesbar")
	var bad := 0
	for v in e:
		for it in e[v]:
			var de: Variant = it.get("de")
			var en: Variant = it.get("en")
			if not (de is Array and en is Array and (de as Array).size() == 2 and (en as Array).size() == 2 and str(it.get("icon", "")) != ""):
				bad += 1
			elif str(de[0]) == "" or str(en[0]) == "" or str(de[1]).length() > 160 or str(en[1]).length() > 160:
				bad += 1
	check(bad == 0, "jeder Punkt mit Zeichen, Deutsch und Englisch, kurz genug (%d abweichend)" % bad)
	check(e.has(Config.VERSION), "Punkte für die aktuelle Fassung %s" % Config.VERSION)
	check(WN.load_entries("res://data/gibt_es_nicht.json").is_empty(), "fehlende Datei: keine Karte statt Fehler")
