extends RefCounted
## Reine Teile von Twitch (Bereich Streams): Geräte-Anmeldung wie die Twitch-App auf dem
## Fernseher (inoffiziell), Anfragen an Twitchs interne Schnittstelle (GQL, wie Xtra, yt-dlp und
## streamlink) und an die offizielle (Helix, nur mit eigener Client-ID) – und ihre Antworten als
## Uzais Videos (Live, Übertragung, Clip), Kategorien und Kanäle. Kein Netz, kein Zustand – darum
## offline prüfbar (tests/logic_twitch.gd).
##
## Kennungen (öffentlich, in jeder Twitch-App enthalten, keine Geheimnisse):
##   TV_CLIENT  – Twitch-App für Android-TV. Damit melden sich Twitch-Channel-Points-Miner, Xtra und
##                twitch-miner-go per Code auf twitch.tv/activate an; yt-dlp nimmt sie für GQL.
##   WEB_CLIENT – twitch.tv im Browser (streamlink). Nur Rückfall für Anfragen ohne Anmeldung.
## Twitch ändert die interne Schnittstelle ohne Ankündigung. Darum liest der Leser Felder mit
## Rückfällen (title am Stream oder in broadcastSettings) und gibt bei Unbekanntem leer zurück.

const GeraeteCode := preload("res://src/core/geraete_code.gd")
const Lang := preload("res://src/core/lang.gd")
const Fremd := preload("res://src/core/fremd.gd")

const TV_CLIENT := "ue6666qo983tsx6so1t0vnawi233wa"
const WEB_CLIENT := "kimne78kx3ncx6brgo4mv6wki5h1ko"
## Nur Lesen: Name, Gefolgtes, Chat lesen (wie Xtra, ohne die Rechte zum Ändern).
const SCOPES := "channel_read chat:read user_blocks_read user_read"
const GRANT_DEVICE := "urn:ietf:params:oauth:grant-type:device_code"
const ACTIVATE_URL := "https://www.twitch.tv/activate"
const WEB := "https://www.twitch.tv"
## Wie die Twitch-App auf einer TV-Box (dieselbe Kennung wie oben).
const UA := "Mozilla/5.0 (Linux; Android 7.1; Smart Box C1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

const ERR_OFFLINE := "Twitch ist gerade nicht erreichbar."
const ERR_CHANGED := "Twitch hat in einer unbekannten Form geantwortet – vermutlich hat Twitch etwas geändert."
const ERR_EXPIRED := "Die Twitch-Anmeldung ist abgelaufen oder wurde widerrufen. Bitte neu anmelden."
const ERR_CLIENT := "Twitch lässt diese Anmeldung gerade nicht zu. Mit einer eigenen Client-ID (dev.twitch.tv) geht es offiziell."

## Felder eines Streams in GQL (Live-Karten überall gleich).
const STREAM_FIELDS := "id title viewersCount createdAt previewImageURL broadcaster { id login displayName profileImageURL(width: 70) broadcastSettings { title } } game { id displayName slug boxArtURL }"

## Gefolgte Kanäle, die gerade live sind (Anmeldung nötig). „user“ ohne Angabe ist das eigene
## Konto (wie Xtra); currentUser ist der Rückfall.
const Q_FOLLOWED := "query($first: Int) { currentUser { id login displayName profileImageURL(width: 70) followedLiveUsers(first: $first) { edges { node { id login displayName profileImageURL(width: 70) stream { %s } } } } } }" % STREAM_FIELDS
## Alle gefolgten Kanäle mit ihrem Live-Stand (follows). Mit der Anmeldung der Twitch-App liefert
## followedLiveUsers bei Twitch nur „service error“ (Protokoll des Nutzers) – follows geht wie in
## Xtra; wer live ist, steht dann am Kanal (stream).
const Q_FOLLOWS := "query($first: Int, $after: Cursor) { currentUser { id login displayName follows(first: $first, after: $after) { edges { cursor node { id login displayName profileImageURL(width: 70) stream { %s } } } pageInfo { hasNextPage } } } }" % STREAM_FIELDS
## Wie Twitch-Channel-Points-Miner mit derselben Anmeldung: gespeicherte Abfrage „ChannelFollows“
## (nur die Namen), danach der Live-Stand für bis zu 100 Namen auf einmal (users).
const PQ_FOLLOWS := "ChannelFollows"
const PQ_FOLLOWS_HASH := "eecf815273d3d949e5cf0085cc5084cd8a1b5b7b6f7990cf43cb0beadf546907"
const Q_USERS_LIVE := "query($logins: [String!]) { users(logins: $logins) { id login displayName profileImageURL(width: 70) stream { %s } } }" % STREAM_FIELDS

## Schlanke Fassung (nur, was eine Live-Karte braucht): falls Twitch bei der vollen „service error“
## meldet.
const Q_FOLLOWED_LEAN := "query($first: Int) { currentUser { id login displayName followedLiveUsers(first: $first) { edges { node { id login displayName profileImageURL(width: 70) stream { id title viewersCount previewImageURL game { id displayName slug boxArtURL } } } } } } }"
const Q_FOLLOWED_ALT := "query($first: Int) { user { id login displayName profileImageURL(width: 70) followedLiveUsers(first: $first) { edges { node { id login displayName profileImageURL(width: 70) stream { %s } } } } } }" % STREAM_FIELDS
const Q_ME := "query { currentUser { id login displayName profileImageURL(width: 150) } }"
const Q_TOP := "query($first: Int) { streams(first: $first) { edges { node { %s } } } }" % STREAM_FIELDS
const Q_TOP_LANG := "query($first: Int, $langs: [Language!]) { streams(first: $first, options: { broadcasterLanguages: $langs }) { edges { node { %s } } } }" % STREAM_FIELDS
const Q_GAMES := "query($first: Int) { games(first: $first) { edges { node { id displayName slug boxArtURL viewersCount broadcastersCount } } } }"
const Q_GAME := "query($id: ID, $slug: String, $first: Int) { game(id: $id, slug: $slug) { id displayName slug boxArtURL viewersCount broadcastersCount streams(first: $first) { edges { node { %s } } } } }" % STREAM_FIELDS
const Q_SEARCH := "query($q: String!, $first: Int) { searchUsers(userQuery: $q, first: $first) { edges { node { id login displayName profileImageURL(width: 150) followers { totalCount } stream { id viewersCount } } } } searchCategories(query: $q, first: $first) { edges { node { id displayName slug boxArtURL viewersCount broadcastersCount } } } searchStreams(userQuery: $q, first: $first) { edges { node { %s } } } }" % STREAM_FIELDS
const Q_CHANNEL := "query($login: String!) { user(login: $login) { id login displayName description profileImageURL(width: 300) bannerImageURL followers { totalCount } stream { %s } videos(first: 12, types: [ARCHIVE], sort: TIME) { edges { node { id title lengthSeconds createdAt viewCount previewThumbnailURL game { displayName } } } } clips(first: 12, criteria: { period: LAST_MONTH }) { edges { node { slug title durationSeconds createdAt viewCount thumbnailURL game { displayName } } } } } }" % STREAM_FIELDS

## Bildgrößen (Uzai-Punkte × gut 2 für 4K; Media rechnet beim Laden passend klein).
const THUMB := Vector2i(800, 450)
const HERO := Vector2i(1280, 720)
const BOX := Vector2i(540, 720)


## Feste Bildgröße am Ende einer Adresse („-52x72.jpg“).
static var _RX_GROESSE := RegEx.create_from_string("-\\d+x\\d+\\.(jpg|jpeg|png|webp)")


# --- Geräte-Anmeldung --------------------------------------------------------------------------

static func device_request(client_id: String) -> Dictionary:
	return { "client_id": client_id, "scopes": SCOPES }


static func poll_request(client_id: String, device_code: String) -> Dictionary:
	return { "client_id": client_id, "scopes": SCOPES, "device_code": device_code, "grant_type": GRANT_DEVICE }


static func refresh_request(client_id: String, refresh: String) -> Dictionary:
	return { "client_id": client_id, "grant_type": "refresh_token", "refresh_token": refresh }


## Antwort auf die Code-Anfrage: { ok, device_code, user_code, url (für den QR-Code, mit Code),
## short (zum Eintippen), interval, expires } oder { ok: false, error }.
static func parse_device_code(code: int, d: Variant) -> Dictionary:
	if code == 0:
		return { "ok": false, "error": ERR_OFFLINE }
	if not (d is Dictionary) or str(d.get("device_code", "")) == "" or str(d.get("user_code", "")) == "":
		if _err_word(d) in ["invalid client", "invalid_client", "unauthorized_client"]:
			return { "ok": false, "error": ERR_CLIENT }
		return { "ok": false, "error": "Twitch hat keinen Code geschickt. Später noch einmal versuchen." }
	var user_code := str(d.user_code)
	var url := str(d.get("verification_uri", d.get("verification_uri_complete", "")))
	if not url.begins_with("https://"):
		url = ACTIVATE_URL + "?device-code=" + user_code
	return {
		"ok": true, "device_code": str(d.device_code), "user_code": user_code, "url": url,
		"short": "twitch.tv/activate",
		"interval": clampi(int(d.get("interval", 5)), 1, 60), "expires": clampi(int(d.get("expires_in", 1800)), 30, 7200),
	}


## Fehlerwort einer Twitch-Antwort: Twitch schickt { status, message }, andere { error }.
static func _err_word(d: Variant) -> String:
	if not (d is Dictionary):
		return ""
	var w := str(d.get("message", ""))
	if w == "":
		w = str(d.get("error", ""))
	return w.strip_edges().to_lower()


## Antwort auf eine Anmeldung oder Erneuerung:
## { ok, access, refresh, expires_at (0 = ohne Ablauf) } oder { ok: false, state, error }. state:
## "pending", "slow", "denied", "expired" (Code abgelaufen), "revoked" (Anmeldung ungültig), "error".
static func parse_token(code: int, d: Variant, now: int) -> Dictionary:
	if d is Dictionary and str(d.get("access_token", "")) != "":
		var ex := int(d.get("expires_in", 0))
		return {
			"ok": true, "access": str(d.access_token), "refresh": str(d.get("refresh_token", "")),
			"expires_at": now + clampi(ex, 60, 90 * 86400) if ex > 0 else 0,
		}
	var e := _err_word(d)
	match e:
		"authorization_pending": return { "ok": false, "state": "pending", "error": "" }
		"slow_down": return { "ok": false, "state": "slow", "error": "" }
		"access_denied": return { "ok": false, "state": "denied", "error": "Die Anmeldung wurde auf dem Handy abgelehnt." }
		"expired_token", "invalid device code": return { "ok": false, "state": "expired", "error": "Der Code ist abgelaufen. „Nochmal versuchen“ holt einen neuen." }
		"invalid refresh token", "invalid_grant", "invalid oauth token", "invalid access token": return { "ok": false, "state": "revoked", "error": ERR_EXPIRED }
		"invalid client", "invalid_client", "unauthorized_client": return { "ok": false, "state": "error", "error": ERR_CLIENT }
	if code == 0:
		return { "ok": false, "state": "error", "error": ERR_OFFLINE }
	return { "ok": false, "state": "error", "error": "Twitch antwortet nicht wie erwartet. Später noch einmal versuchen." }


## Antwort von /oauth2/validate: { ok, login, user_id, client_id } (ok: false bei 401).
static func parse_validate(code: int, d: Variant) -> Dictionary:
	if code == 200 and d is Dictionary and str(d.get("login", "")) != "":
		return { "ok": true, "login": str(d.login), "user_id": str(d.get("user_id", "")), "client_id": str(d.get("client_id", "")),
				"expires_in": int(d.get("expires_in", 0)) }
	return { "ok": false, "login": "", "user_id": "", "client_id": "", "expires_in": 0 }


## Nächster Zustand der Geräte-Anmeldung (src/core/geraete_code.gd) mit den Texten dieses Dienstes
## (state wie bei parse_token, "ok" bei Erfolg).
static func flow_step(flow: Dictionary, state: String, now: float, err := "") -> Dictionary:
	return GeraeteCode.schritt(flow, state, now, err, { "offline": ERR_OFFLINE, "sofort": ERR_CLIENT, "grund": true })


# --- GQL -----------------------------------------------------------------------------------------

## Körper einer GQL-Anfrage: Abfrage ohne Namen (wie Xtra: Twitch nimmt sie dann als freie
## Abfrage, nicht als eine seiner gespeicherten).
static func gql_body(query: String, vars: Dictionary = {}) -> Dictionary:
	return { "query": query, "variables": vars }


## Gespeicherte Abfrage (wie die Twitch-Apps): Name und Prüfsumme statt Abfragetext.
static func persisted_body(op: String, sha: String, vars: Dictionary = {}) -> Dictionary:
	return { "operationName": op, "variables": vars, "extensions": { "persistedQuery": { "version": 1, "sha256Hash": sha } } }


## Seite der gefolgten Kanäle (Q_FOLLOWS oder ChannelFollows): { ok, items (live), logins,
## more, after, me }. ok: false, wenn die Liste selbst fehlt.
static func parse_follows(d: Variant, now: int) -> Dictionary:
	var data := gql_data(d)
	var me: Variant = data.get("currentUser") if data.get("currentUser") is Dictionary else data.get("user")
	if not (me is Dictionary) or not ((me as Dictionary).get("follows") is Dictionary):
		return { "ok": false, "items": [], "logins": [], "more": false, "after": "", "me": user_brief(me) }
	var conn: Dictionary = me.follows
	var items: Array = []
	var logins: Array = []
	var after := ""
	if conn.get("edges") is Array:
		for e in conn.edges:
			if not (e is Dictionary):
				continue
			if e.get("cursor") != null and str(e.cursor) != "":
				after = str(e.cursor)
			var n: Variant = e.get("node")
			if not (n is Dictionary) or str((n as Dictionary).get("login", "")) == "":
				continue
			logins.append(str(n.login).to_lower())
			if n.get("stream") is Dictionary:
				var it := stream_item(n.stream, n, now)
				if not it.is_empty():
					items.append(it)
	var more := conn.get("pageInfo") is Dictionary and bool((conn.pageInfo as Dictionary).get("hasNextPage", false)) and after != ""
	return { "ok": true, "items": items, "logins": logins, "more": more, "after": after, "me": user_brief(me) }


## Live-Stand für eine Liste von Namen (Q_USERS_LIVE): nur die, die gerade live sind.
static func parse_users_live(d: Variant, now: int) -> Dictionary:
	var data := gql_data(d)
	if not (data.get("users") is Array):
		return { "ok": false, "items": [] }
	var items: Array = []
	for u in data.users:
		if u is Dictionary and u.get("stream") is Dictionary:
			var it := stream_item(u.stream, u, now)
			if not it.is_empty():
				items.append(it)
	return { "ok": true, "items": items }


## Gefolgte live: meiste Zuschauer zuerst, jeder Kanal einmal.
static func sort_live(items: Array) -> Array:
	var seen := {}
	var out: Array = []
	for it in items:
		if not seen.has(str(it.id)):
			seen[str(it.id)] = true
			out.append(it)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.twitch.viewers) > int(b.twitch.viewers))
	return out


## Daten einer GQL-Antwort ({} wenn keine kamen). Teilantworten (Daten und Fehler) gelten.
static func gql_data(d: Variant) -> Dictionary:
	if d is Dictionary and d.get("data") is Dictionary:
		return d.data
	return {}


## Erste Fehlermeldung einer GQL-Antwort ("" wenn keine), fürs Protokoll.
static func gql_error(d: Variant) -> String:
	if d is Dictionary:
		if d.get("errors") is Array and not (d.errors as Array).is_empty():
			var e: Variant = d.errors[0]
			return str(e.get("message", e)) if e is Dictionary else str(e)
		if str(d.get("error", "")) != "":
			return "%s: %s" % [str(d.error), str(d.get("message", ""))]
	return ""


static func _edges(conn: Variant) -> Array:
	var out: Array = []
	if conn is Dictionary and conn.get("edges") is Array:
		for e in conn.edges:
			if e is Dictionary and e.get("node") is Dictionary:
				out.append(e.node)
	return out


## Liste von Streams (streams, searchStreams, game.streams) als Live-Karten.
static func parse_streams(conn: Variant, now: int) -> Array:
	var out: Array = []
	var seen := {}
	for n in _edges(conn):
		var it := stream_item(n, {}, now)
		if not it.is_empty() and not seen.has(it.id):
			seen[it.id] = true
			out.append(it)
	return out


## Gefolgte Kanäle, die live sind: { items, me: { login, name, avatar } }.
static func parse_followed(d: Variant, now: int) -> Dictionary:
	var data := gql_data(d)
	var me: Variant = data.get("currentUser") if data.get("currentUser") is Dictionary else data.get("user")
	# Ohne die Liste selbst (Twitch: „service error“ am Feld) zählt die Antwort nicht.
	if not (me is Dictionary) or not ((me as Dictionary).get("followedLiveUsers") is Dictionary):
		return { "items": [], "me": user_brief(me), "ok": false }
	var items: Array = []
	for u in _edges(me.get("followedLiveUsers")):
		if u.get("stream") is Dictionary:
			var it := stream_item(u.stream, u, now)
			if not it.is_empty():
				items.append(it)
	# Meiste Zuschauer zuerst (wie in der Twitch-App).
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.twitch.viewers) > int(b.twitch.viewers))
	return { "items": items, "me": user_brief(me), "ok": true }


static func user_brief(u: Variant) -> Dictionary:
	if not (u is Dictionary):
		return {}
	return { "id": str(u.get("id", "")), "login": str(u.get("login", "")), "name": _name(u), "avatar": str(u.get("profileImageURL", "")) }


static func _name(u: Dictionary) -> String:
	var n := str(u.get("displayName", ""))
	return n if n != "" and n != "<null>" else str(u.get("login", ""))


## Ein Stream als Video für Uzais Karten und den Player. owner: der Kanal, falls der Stream ihn
## nicht selbst mitbringt (gefolgte Kanäle).
static func stream_item(s: Variant, owner: Variant, now: int) -> Dictionary:
	if not (s is Dictionary):
		return {}
	var b: Variant = s.get("broadcaster")
	if not (b is Dictionary) or str((b as Dictionary).get("login", "")) == "":
		b = owner
	if not (b is Dictionary) or str((b as Dictionary).get("login", "")) == "":
		return {}
	var login := str(b.login).to_lower()
	var title := str(s.get("title", ""))
	if (title == "" or title == "<null>") and b.get("broadcastSettings") is Dictionary:
		title = str(b.broadcastSettings.get("title", ""))
	var name := _name(b)
	if title == "" or title == "<null>":
		title = name + " ist live"
	var game := ""
	var game_id := ""
	if s.get("game") is Dictionary:
		game = str(s.game.get("displayName", s.game.get("name", "")))
		game_id = str(s.game.get("id", ""))
	var viewers := int(s.get("viewersCount", 0))
	var started := iso_time(str(s.get("createdAt", "")))
	return {
		"id": "tw:live:" + login, "url": WEB + "/" + login, "title": title, "channel": name,
		"thumb": live_thumb(str(s.get("previewImageURL", "")), login, now), "live": true, "views": 0,
		"info": info_line(game, viewers), "media_title": "%s – %s" % [name, title],
		"twitch": { "kind": "live", "login": login, "name": name, "game": game, "game_id": game_id,
			"viewers": viewers, "started": started, "avatar": str(b.get("profileImageURL", "")) },
	}


## Übertragungen (VODs) eines Kanals.
static func parse_videos(conn: Variant, owner: Dictionary) -> Array:
	var out: Array = []
	for n in _edges(conn):
		var vid := str(n.get("id", ""))
		if vid == "":
			continue
		var game := str(n.game.get("displayName", "")) if n.get("game") is Dictionary else ""
		out.append({
			"id": "tw:v:" + vid, "url": WEB + "/videos/" + vid, "title": str(n.get("title", "")), "channel": str(owner.get("name", "")),
			"thumb": sized(str(n.get("previewThumbnailURL", "")), THUMB), "duration": int(n.get("lengthSeconds", 0)),
			"published": iso_time(str(n.get("createdAt", ""))), "views": int(n.get("viewCount", 0)),
			"media_title": "%s – %s" % [str(owner.get("name", "")), str(n.get("title", ""))],
			"twitch": { "kind": "vod", "login": str(owner.get("login", "")), "name": str(owner.get("name", "")), "game": game, "avatar": str(owner.get("avatar", "")) },
		})
	return out


## Clips eines Kanals.
static func parse_clips(conn: Variant, owner: Dictionary) -> Array:
	var out: Array = []
	for n in _edges(conn):
		var slug := str(n.get("slug", ""))
		if slug == "":
			continue
		var game := str(n.game.get("displayName", "")) if n.get("game") is Dictionary else ""
		out.append({
			"id": "tw:c:" + slug, "url": "https://clips.twitch.tv/" + slug, "title": str(n.get("title", "")), "channel": str(owner.get("name", "")),
			"thumb": sized(str(n.get("thumbnailURL", "")), THUMB), "duration": int(n.get("durationSeconds", 0)),
			"published": iso_time(str(n.get("createdAt", ""))), "views": int(n.get("viewCount", 0)),
			"media_title": "%s – %s" % [str(owner.get("name", "")), str(n.get("title", ""))],
			"twitch": { "kind": "clip", "login": str(owner.get("login", "")), "name": str(owner.get("name", "")), "game": game, "avatar": str(owner.get("avatar", "")) },
		})
	return out


## Kategorien (Spiele, „Just Chatting“ …) als Karten im Hochformat.
static func parse_games(conn: Variant) -> Array:
	var out: Array = []
	for n in _edges(conn):
		var g := game_item(n)
		if not g.is_empty():
			out.append(g)
	return out


static func game_item(n: Variant) -> Dictionary:
	if not (n is Dictionary) or str(n.get("id", "")) == "":
		return {}
	var name := str(n.get("displayName", n.get("name", "")))
	return {
		"id": "tw:g:" + str(n.id), "game_id": str(n.id), "slug": str(n.get("slug", "")), "title": name, "channel": name,
		"thumb": sized(str(n.get("boxArtURL", "")), BOX), "viewers": int(n.get("viewersCount", 0)),
		"channels": int(n.get("broadcastersCount", 0)),
	}


## Kategorie mit ihren Streams: { game, items }.
static func parse_game(d: Variant, now: int) -> Dictionary:
	var g: Variant = gql_data(d).get("game")
	if not (g is Dictionary):
		return { "game": {}, "items": [] }
	return { "game": game_item(g), "items": parse_streams(g.get("streams"), now) }


## Suche: { channels: [{ id, login, title, thumb, live, viewers, followers }], games, streams }.
static func parse_search(d: Variant, now: int) -> Dictionary:
	var data := gql_data(d)
	var chans: Array = []
	for u in _edges(data.get("searchUsers")):
		var login := str(u.get("login", "")).to_lower()
		if login == "":
			continue
		var st: Variant = u.get("stream")
		chans.append({
			"id": login, "login": login, "title": _name(u), "thumb": str(u.get("profileImageURL", "")),
			"live": st is Dictionary, "viewers": int(st.get("viewersCount", 0)) if st is Dictionary else 0,
			"followers": int(u.followers.get("totalCount", 0)) if u.get("followers") is Dictionary else 0,
		})
	return { "channels": chans, "games": parse_games(data.get("searchCategories")), "streams": parse_streams(data.get("searchStreams"), now) }


## Kanalseite: { ok, user: { id, login, name, avatar, banner, about, followers }, live (Karte
## oder {}), videos, clips }.
static func parse_channel(d: Variant, now: int) -> Dictionary:
	var u: Variant = gql_data(d).get("user")
	if not (u is Dictionary) or str(u.get("login", "")) == "":
		return { "ok": false, "user": {}, "live": {}, "videos": [], "clips": [] }
	var me := user_brief(u)
	me["banner"] = str(u.get("bannerImageURL", "")) if u.get("bannerImageURL") != null else ""
	me["about"] = str(u.get("description", "")) if u.get("description") != null else ""
	me["followers"] = int(u.followers.get("totalCount", 0)) if u.get("followers") is Dictionary else 0
	var live := stream_item(u.get("stream"), u, now) if u.get("stream") is Dictionary else {}
	return { "ok": true, "user": me, "live": live, "videos": parse_videos(u.get("videos"), me), "clips": parse_clips(u.get("clips"), me) }


# --- Helix (offiziell, nur mit eigener Client-ID) ------------------------------------------------

## /helix/streams und /helix/streams/followed: { data: [{ user_login, user_name, game_name, title,
## viewer_count, started_at, thumbnail_url }] }.
static func parse_helix_streams(d: Variant, now: int) -> Array:
	var out: Array = []
	if not (d is Dictionary) or not (d.get("data") is Array):
		return out
	for s in Fremd.zeilen(d.data):
		if not (s is Dictionary) or str(s.get("user_login", "")) == "":
			continue
		var login := str(s.user_login).to_lower()
		var name := str(s.get("user_name", login))
		var title := str(s.get("title", ""))
		if title == "":
			title = name + " ist live"
		var game := str(s.get("game_name", ""))
		var viewers := int(s.get("viewer_count", 0))
		out.append({
			"id": "tw:live:" + login, "url": WEB + "/" + login, "title": title, "channel": name,
			"thumb": live_thumb(str(s.get("thumbnail_url", "")), login, now), "live": true, "views": 0,
			"info": info_line(game, viewers), "media_title": "%s – %s" % [name, title],
			"twitch": { "kind": "live", "login": login, "name": name, "game": game, "game_id": str(s.get("game_id", "")),
				"viewers": viewers, "started": iso_time(str(s.get("started_at", ""))), "avatar": "" },
		})
	if out.size() > 1:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.twitch.viewers) > int(b.twitch.viewers))
	return out


## /helix/games/top und /helix/search/categories.
static func parse_helix_games(d: Variant) -> Array:
	var out: Array = []
	if not (d is Dictionary) or not (d.get("data") is Array):
		return out
	for g in Fremd.zeilen(d.data):
		if g is Dictionary and str(g.get("id", "")) != "":
			out.append({ "id": "tw:g:" + str(g.id), "game_id": str(g.id), "slug": "", "title": str(g.get("name", "")), "channel": str(g.get("name", "")),
				"thumb": sized(str(g.get("box_art_url", "")), BOX), "viewers": 0, "channels": 0 })
	return out


## /helix/search/channels.
static func parse_helix_channels(d: Variant) -> Array:
	var out: Array = []
	if not (d is Dictionary) or not (d.get("data") is Array):
		return out
	for c in Fremd.zeilen(d.data):
		if c is Dictionary and str(c.get("broadcaster_login", "")) != "":
			var login := str(c.broadcaster_login).to_lower()
			out.append({ "id": login, "login": login, "title": str(c.get("display_name", login)), "thumb": str(c.get("thumbnail_url", "")),
				"live": bool(c.get("is_live", false)), "viewers": 0, "followers": 0 })
	return out


## /helix/users (das eigene Konto).
static func parse_helix_user(d: Variant) -> Dictionary:
	if d is Dictionary and d.get("data") is Array and not (d.data as Array).is_empty() and d.data[0] is Dictionary:
		var u: Dictionary = d.data[0]
		return { "id": str(u.get("id", "")), "login": str(u.get("login", "")), "name": str(u.get("display_name", u.get("login", ""))),
				"avatar": str(u.get("profile_image_url", "")) }
	return {}


# --- Bilder, Zeiten, Texte -----------------------------------------------------------------------

## Bildadresse in der gewünschten Größe: Twitch schickt Vorlagen mit {width}x{height} (Helix:
## auch %{width}x%{height}) oder eine feste Größe wie -52x72.jpg.
static func sized(url: String, sz: Vector2i) -> String:
	if url == "" or url == "<null>":
		return ""
	if url.contains("{width}"):
		return url.replace("%{width}", str(sz.x)).replace("%{height}", str(sz.y)).replace("{width}", str(sz.x)).replace("{height}", str(sz.y))
	return _RX_GROESSE.sub(url, "-%dx%d.$1" % [sz.x, sz.y])


## Vorschaubild eines Live-Streams. Twitch erneuert es alle paar Minuten unter derselben Adresse;
## Uzai merkt sich Bilder je Adresse – darum ein Zusatz, der alle 10 Minuten wechselt.
static func live_thumb(url: String, login: String, now: int) -> String:
	var u := sized(url, THUMB)
	if u == "":
		u = "https://static-cdn.jtvnw.net/previews-ttv/live_user_%s-%dx%d.jpg" % [login, THUMB.x, THUMB.y]
	return u + ("&" if u.contains("?") else "?") + "t=%d" % floori(now / 600.0)


## Größeres Bild derselben Adresse (für das große Bild oben).
static func bigger(url: String) -> String:
	return url.replace("-%dx%d." % [THUMB.x, THUMB.y], "-%dx%d." % [HERO.x, HERO.y])


## ISO-Zeit von Twitch („2026-10-17T12:30:00Z“, auch mit Bruchteilen) als Unix-Zeit, 0 wenn leer.
static func iso_time(s: String) -> int:
	if s.length() < 19:
		return 0
	var t := s.substr(0, 19)
	var v := Time.get_unix_time_from_datetime_string(t)
	return int(v) if v > 0 else 0


## „12.345 Zuschauer“, „45 Tsd. Zuschauer“, „1,2 Mio. Zuschauer“ ("" bei 0).
static func viewers_text(n: int) -> String:
	if n <= 0:
		return ""
	if n >= 1000000:
		return Lang.dec(("%.1f" % (n / 1000000.0)).trim_suffix(".0")) + " Mio. Zuschauer"
	if n >= 10000:
		return "%d Tsd. Zuschauer" % floori(n / 1000.0)
	if n >= 1000:
		return "%s Zuschauer" % Lang.tausender(n)
	return "%d Zuschauer" % n


## Zahl mit Tausenderpunkt („4.200“).
static func count_text(n: int) -> String:
	return Lang.tausender(n)


## „Live seit 2 Std. 5 Min.“ ("" ohne Startzeit).
static func uptime_text(started: int, now: int) -> String:
	if started <= 0 or now < started:
		return ""
	var m := floori((now - started) / 60.0)
	if m < 1:
		return TranslationServer.translate("Gerade gestartet")
	if m < 60:
		return TranslationServer.translate("Live seit %d Min.") % m
	var h := floori(m / 60.0)
	if m % 60 > 0:
		return TranslationServer.translate("Live seit %d Std. %d Min.") % [h, m % 60]
	return TranslationServer.translate("Live seit %d Std.") % h


## Zeile unter dem Titel: Kategorie · Zuschauer.
static func info_line(game: String, viewers: int) -> String:
	var parts := PackedStringArray()
	if game != "":
		parts.append(game)
	var vt := viewers_text(viewers)
	if vt != "":
		parts.append(vt)
	return "  ·  ".join(parts)


## Deutsche Meldung, wenn eine Anfrage nicht klappte.
static func explain(code: int, gql_err := "") -> String:
	if code == 0:
		return ERR_OFFLINE
	if code == 401:
		return ERR_EXPIRED
	if code == 400 or code == 403 or gql_err != "":
		return ERR_CHANGED
	return "Twitch antwortet gerade nicht. Gleich noch einmal versuchen."


## Nur an Twitch selbst (oder den ausdrücklich gesetzten Testserver) geht die Anmeldung mit.
static func token_host_ok(url: String, test_base := "") -> bool:
	if test_base != "" and url.begins_with(test_base.trim_suffix("/") + "/"):
		return true
	for h in ["https://gql.twitch.tv/", "https://api.twitch.tv/", "https://id.twitch.tv/"]:
		if url.begins_with(str(h)):
			return true
	return false
