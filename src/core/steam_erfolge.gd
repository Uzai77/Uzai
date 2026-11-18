extends RefCounted
## Steam-Erfolge ohne Web-API: aus Steams eigenen Dateien am PC (nur lesend) und über Steams
## Chat-Server. Die Web-API lehnt den Zugang der QR-Anmeldung als Steam-App ab (HTTP 400) – beim
## Nutzer kamen so keine Erfolge („erfolge werden nicht aus steam gezogen“, 0.16.0).
##
## Lokal: <Steam>/appcache/stats/UserGameStatsSchema_<App-ID>.bin (Namen, Beschreibungen, Bilder
## je Erfolg) und UserGameStats_<Konto-ID>_<App-ID>.bin (was du freigeschaltet hast, mit Zeit).
## Beides sind binäre KeyValues; gelesen mit dem strengen eigenen Leser aus unlocks.gd (parse_kv,
## nie str_to_var), Dateien mit Größengrenze (read_capped).
## Chat-Server: ClientGetUserStats (EMsg 818 → 819: Schema als binäre KeyValues und je Statistik die
## Freischaltzeiten – für dich und für Freunde, wie der Vergleich in der Steam-App) und
## Player.GetAchievementsProgress#1 (Stand je Spiel, für die Zählung über die Bibliothek; siehe
## SteamCM.achievements_progress).
## Alles hier ist rein (ohne Netz) und wird von tests/logic_steam_erfolge.gd mit Beispieldateien
## (tests/fixtures/steam_stats) geprüft.

const UnlocksS := preload("res://src/core/unlocks.gd")
const CM := preload("res://src/core/steam_cm.gd")

const STEAM64 := 76561197960265728
const ICONS := "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/%d/%s"
const SCHEMA_MAX := 4 * 1024 * 1024     ## größere Schema-Dateien liest Uzai nicht
const USER_MAX := 512 * 1024            ## … Spielerdaten
const FILES_MAX := 4000                 ## höchstens so viele Dateien im Ordner ansehen
const TITLE_MAX := 160
const DESC_MAX := 400
const BLOCKS_MAX := 256                 ## Statistiken mit Erfolgen je Antwort des Chat-Servers

## Steuerzeichen (clean) und der erlaubte Name einer Bilddatei (icon_url): je Erfolg mehrfach gebraucht. Vorher
## ging beides Zeichen für Zeichen – bei einem Spiel mit 1.000 Erfolgen gemessen 75 ms beim Öffnen der Liste.
static var _RX_STEUER := RegEx.create_from_string("[\\x{00}-\\x{1F}\\x{7F}]")
static var _RX_BILDNAME := RegEx.create_from_string("^[A-Za-z0-9_.-]+\\z")


# --- Dateien ------------------------------------------------------------------------------------

## Datei ganz lesen, aber nur bis max_bytes – größer, leer oder nicht lesbar: leer.
static func read_capped(path: String, max_bytes: int) -> PackedByteArray:
	if path == "" or not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var n := f.get_length()
	if n <= 0 or n > max_bytes:
		f.close()
		return PackedByteArray()
	var b := f.get_buffer(n)
	f.close()
	return b


## Konto-ID (untere 32 Bit) aus der SteamID64, 0 bei Unsinn.
static func account_id(sid64: String) -> int:
	if not sid64.is_valid_int() or sid64.length() < 16 or sid64.length() > 20:
		return 0
	var a := int(sid64) - STEAM64
	return a if a > 0 and a < (1 << 32) else 0


static func schema_path(dir: String, appid: int) -> String:
	return dir.path_join("UserGameStatsSchema_%d.bin" % appid)


static func user_path(dir: String, acct: int, appid: int) -> String:
	return dir.path_join("UserGameStats_%d_%d.bin" % [acct, appid])


## Text aus fremden Daten: ohne Steuerzeichen, gekürzt.
static func clean(v: Variant, max_len: int) -> String:
	var s := (str(v) if v != null else "").left(maxi(max_len, 0))
	return (_RX_STEUER.sub(s, " ", true) if _RX_STEUER.search(s) != null else s).strip_edges()


## Bildadresse aus dem Dateinamen im Schema ("" bei allem, was kein schlichter Name ist).
static func icon_url(appid: int, name: String) -> String:
	if name == "" or name.length() > 128 or appid <= 0 or _RX_BILDNAME.search(name) == null:
		return ""
	if name.begins_with(".") or name.contains(".."):
		return ""
	return ICONS % [appid, name]


## Spielname aus dem Schema ("gamename" unter der Wurzel), "" ohne.
static func schema_title(schema: Dictionary) -> String:
	for k in schema.keys():
		if schema[k] is Dictionary and (schema[k] as Dictionary).has("gamename"):
			return clean(schema[k].gamename, TITLE_MAX)
	return clean(schema.get("gamename", ""), TITLE_MAX)


## Ein Spiel aus den lokalen Dateien: { ok, bits, got, has_user, title } – ok: Schema da und lesbar;
## has_user: deine Datei dazu war da (sonst ist „nichts freigeschaltet“ nicht sicher).
static func local_game(dir: String, acct: int, appid: int) -> Dictionary:
	var out := { "ok": false, "bits": {}, "got": {}, "has_user": false, "title": "" }
	if dir == "" or appid <= 0:
		return out
	var sb := read_capped(schema_path(dir, appid), SCHEMA_MAX)
	if sb.is_empty():
		return out
	var schema := UnlocksS.parse_kv(sb)
	var bits := UnlocksS.schema_bits(schema)
	if bits.is_empty():
		return out
	out.ok = true
	out.bits = bits
	out.title = schema_title(schema)
	if acct > 0:
		var ub := read_capped(user_path(dir, acct, appid), USER_MAX)
		if not ub.is_empty():
			var user := UnlocksS.parse_kv(ub)
			if not user.is_empty():
				out.has_user = true
				out.got = UnlocksS.unlocked_from_stats(user, bits)
	return out


## Stand eines Spiels aus den lokalen Dateien: { u, t } – {} ohne Schema oder ohne deine Datei.
static func local_count(dir: String, acct: int, appid: int) -> Dictionary:
	var lg := local_game(dir, acct, appid)
	if not bool(lg.ok) or not bool(lg.has_user):
		return {}
	var t := (lg.bits as Dictionary).size()
	return { "u": mini((lg.got as Dictionary).size(), t), "t": t }


## Spiele mit deiner Statistik-Datei im Ordner, zuletzt geschriebene zuerst: [{ appid, at }].
static func local_apps(dir: String, acct: int, max_n := FILES_MAX) -> Array:
	var out: Array = []
	if dir == "" or acct <= 0 or not DirAccess.dir_exists_absolute(dir):
		return out
	var prefix := "UserGameStats_%d_" % acct
	var n := 0
	for f in DirAccess.get_files_at(dir):
		n += 1
		if n > max_n:
			break
		if not f.begins_with(prefix) or not f.ends_with(".bin"):
			continue
		var mid := f.trim_prefix(prefix).trim_suffix(".bin")
		if not mid.is_valid_int() or mid.length() > 10 or int(mid) <= 0:
			continue
		out.append({ "appid": int(mid), "at": FileAccess.get_modified_time(dir.path_join(f)) })
	out.sort_custom(func(a, b): return int(a.at) > int(b.at))
	return out


# --- Liste wie Achievements.steam_game ------------------------------------------------------------

## Erfolgsliste aus dem Schema (schema_bits) und den Freischaltungen (api -> Unix-Zeit), Namen ohne
## Groß/klein verglichen. pct: api -> globaler Anteil (GetGlobalAchievementPercentagesForApp, ohne
## Schlüssel). Format wie Achievements.steam_game: [{ id, title, desc, secret, icon, icon_locked,
## unlocked, date, points, rarity, hardcore, hidden, order }].
static func build_list(appid: int, bits: Dictionary, got: Dictionary, pct: Dictionary) -> Array:
	var up := {}
	for k in got.keys():
		up[str(k).to_upper()] = maxi(0, int(got[k]))
	var pct_up := {}
	for k in pct.keys():
		pct_up[str(k).to_upper()] = float(pct[k])
	var keys: Array = bits.keys()
	keys.sort_custom(_bit_order)
	var out: Array = []
	var seen := {}
	for key in keys:
		var b: Dictionary = bits[key]
		var api := clean(b.get("api", key), 128)
		if api == "" or seen.has(api.to_upper()):
			continue
		seen[api.to_upper()] = true
		var has := up.has(api.to_upper())
		var hidden := bool(b.get("hidden", false)) and not has
		var real := clean(b.get("desc", ""), DESC_MAX)
		var icon := icon_url(appid, str(b.get("icon", "")))
		var gray := icon_url(appid, str(b.get("icon_gray", "")))
		var title := clean(b.get("title", ""), TITLE_MAX)
		out.append({
			"id": api, "title": title if title != "" else api,
			"desc": "Geheimer Erfolg" if hidden else real, "secret": real if hidden else "",
			"icon": icon, "icon_locked": gray if gray != "" else icon,
			"unlocked": has, "date": int(up.get(api.to_upper(), 0)), "points": 0,
			"rarity": float(pct_up.get(api.to_upper(), -1.0)), "hardcore": false, "hidden": hidden, "order": out.size(),
		})
	return out


## Reihenfolge wie im Schema: Statistik, dann Bit (Schlüssel "<Statistik>/<Bit>").
static func _bit_order(a: Variant, b: Variant) -> bool:
	var sa := str(a).get_slice("/", 0).to_int()
	var sb := str(b).get_slice("/", 0).to_int()
	if sa != sb:
		return sa < sb
	return str(a).get_slice("/", 1).to_int() < str(b).get_slice("/", 1).to_int()


# --- Chat-Server ----------------------------------------------------------------------------------

## CMsgClientGetUserStatsResponse: game_id (1), eresult (2), crc_stats (3), schema (4, binäre
## KeyValues), stats (5) = { stat_id (1), stat_value (2) }, achievement_blocks (6) =
## { achievement_id (1, die Statistik), unlock_time (2, je Bit ein fixed32 – auch gepackt) }.
## bits_hint: Schema, falls die Antwort keins mitbringt (etwa aus der lokalen Datei).
## { eresult, appid, bits, title, got: { api: Unix-Zeit } } – fremde Daten, alles begrenzt.
static func parse_user_stats(body: PackedByteArray, bits_hint := {}) -> Dictionary:
	var d := CM.Pb.decode(body)
	var out := { "eresult": CM.Pb.zahl(d, 2, 2), "appid": CM.Pb.zahl(d, 1, 0) & 0xFFFFFF, "bits": {}, "title": "", "got": {} }
	var bits: Dictionary = bits_hint
	var raw: Variant = CM.Pb.first(d, 4, null)
	if raw is PackedByteArray and not (raw as PackedByteArray).is_empty() and (raw as PackedByteArray).size() <= SCHEMA_MAX:
		var schema := UnlocksS.parse_kv(raw)
		var sb := UnlocksS.schema_bits(schema)
		if not sb.is_empty():
			bits = sb
			out.title = schema_title(schema)
	out.bits = bits
	var data := {}
	for rs in (d.get(5, []) as Array).slice(0, BLOCKS_MAX * 4):
		if rs is PackedByteArray:
			var s := CM.Pb.decode(rs)
			data[CM.Pb.zahl(s, 1, -1)] = CM.Pb.zahl(s, 2, 0) & 0xFFFFFFFF
	var times := {}
	for rb in (d.get(6, []) as Array).slice(0, BLOCKS_MAX):
		if not (rb is PackedByteArray):
			continue
		var blk := CM.Pb.decode(rb)
		var aid := CM.Pb.zahl(blk, 1, -1)
		if aid < 0:
			continue
		var list := _u32_list(blk.get(2, []))
		for i in mini(list.size(), 32):
			if int(list[i]) > 0:
				times["%d/%d" % [aid, i]] = int(list[i])
	var got := {}
	if bits.is_empty():
		for k in times.keys():
			got[k] = times[k]
	else:
		for key in bits.keys():
			var sid := str(key).get_slice("/", 0).to_int()
			var bit := str(key).get_slice("/", 1).to_int()
			var on := times.has(key) or (bit >= 0 and bit < 32 and ((int(data.get(sid, 0)) >> bit) & 1) == 1)
			if on:
				got[clean((bits[key] as Dictionary).get("api", key), 128)] = int(times.get(key, 0))
	out.got = got
	return out


## Wiederholte fixed32-Werte: einzeln (je ein int) oder gepackt (Bytes, je 4).
static func _u32_list(vals: Array) -> Array:
	var out: Array = []
	for v in vals:
		if v is PackedByteArray:
			var b: PackedByteArray = v
			for i in range(0, b.size() - 3, 4):
				out.append(int(b.decode_u32(i)))
		else:
			out.append(int(v) & 0xFFFFFFFF)
		if out.size() >= 32:
			break
	return out


## Stand eines Freundes aus parse_user_stats für den Vergleich, im Format von
## achievements_friends.parse_steam_friend: { ok, reason, got, total, last }.
static func friend_result(p: Dictionary) -> Dictionary:
	var out := { "ok": false, "reason": "", "got": {}, "total": 0, "last": 0 }
	if p.is_empty():
		out.reason = "Keine Antwort"
		return out
	var res := int(p.get("eresult", 2))
	if res == 15:
		out.reason = "Profil privat"
		return out
	if res != 1:
		out.reason = "Nicht sichtbar"
		return out
	out.ok = true
	out.total = (p.get("bits", {}) as Dictionary).size()
	for api in (p.get("got", {}) as Dictionary).keys():
		var at := maxi(0, int(p.got[api]))
		out.got[str(api)] = at
		out.last = maxi(int(out.last), at)
	if int(out.total) == 0:
		out.total = (out.got as Dictionary).size()
	return out


## Logzeile für steam.log (rein, getestet): „Erfolge: Web-API abgelehnt → lokal …, N Spiele, M Erfolge“.
static func log_text(what: String, local_n: int, cm_n: int, games: int, achs: int) -> String:
	var ways: PackedStringArray = []
	if local_n > 0:
		ways.append("lokal (Steam-Ordner) %d" % local_n)
	if cm_n > 0:
		ways.append("Chat-Server %d" % cm_n)
	var via := " + ".join(ways) if not ways.is_empty() else "weder lokal noch Chat-Server"
	return "Erfolge%s: Web-API abgelehnt → %s, %d Spiele, %d Erfolge" % ["" if what == "" else " " + what, via, games, achs]
