extends RefCounted
## Reine Teile der YouTube-Startseite „wie auf dem Fernseher“ (inoffiziell, SmartTube-Weg):
## Fernseher-Kennung aus der TV-Seite lesen, Geräte-Anmeldung (Antworten und Ablauf), Anmeldung
## erneuern, Anfragen an YouTubes interne Schnittstelle („InnerTube“) bauen und ihre Antworten in
## Uzais Videos übersetzen. Kein Netz, kein Zustand – darum offline prüfbar (tests/logic_youtube_tv.gd).
##
## YouTube ändert diese Antworten ohne Ankündigung. Darum liest der Leser nicht einen festen Pfad,
## sondern geht den ganzen Baum ab: Reihen (shelfRenderer & Co.) mit Titel, darin Kacheln
## (tileRenderer beim Fernseher, videoRenderer & Co. im Browser, lockupViewModel ganz neu).
## Kommt gar nichts Brauchbares heraus, gibt er leer zurück und Uzai fällt auf die Abos zurück.

const GeraeteCode := preload("res://src/core/geraete_code.gd")
const SCOPE := "http://gdata.youtube.com https://www.googleapis.com/auth/youtube"
const GRANT_DEVICE := "http://oauth.net/grant_type/device/1.0"
const CLIENT_NAME := "TVHTML5"
const CLIENT_NUM := "7"
const CLIENT_VERSION := "7.20250923.13.00"
const DEVICE_MODEL := "ytlr::"
const ACTIVATE_URL := "https://www.youtube.com/activate"

## Reihen und einzelne Videos in den Antworten (Fernseher, Browser, neue „View Models“).
const SHELF_KEYS := ["shelfRenderer", "richShelfRenderer", "reelShelfRenderer", "horizontalCardListRenderer", "gridShelfViewModel"]
const VIDEO_KEYS := ["tileRenderer", "videoRenderer", "gridVideoRenderer", "compactVideoRenderer", "playlistVideoRenderer", "reelItemRenderer",
		"lockupViewModel", "shortsLockupViewModel"]
## Teilbäume ohne Videos (Menüs, Statistik): nicht durchsuchen – spart Zeit und Fehltreffer.
const SKIP_KEYS := ["menu", "trackingParams", "accessibility", "accessibilityData", "loggingDirectives", "frameworkUpdates", "responseContext", "topbar",
		"onLongPressCommand"]

## Art eines Schlüssels beim Abgehen des Baums: ein Nachschlagen statt dreier Listen (eine Startseite hat
## Zehntausende Schlüssel). Aus den Listen oben gebaut, damit es nur eine Quelle gibt.
const _ART_SKIP := 1
const _ART_REIHE := 2
const _ART_VIDEO := 3
static var _art := _arten()

const ERR_OFFLINE := "YouTube ist gerade nicht erreichbar."
const ERR_CHANGED := "Startseite in unbekannter Form."
const ERR_EXPIRED := "Anmeldung abgelaufen. Neu anmelden."
const ERR_CLIENT := "Fernseher-Anmeldung gerade gesperrt. Abos und Mix bleiben."


## Suchmuster, einmal beim Laden übersetzt und danach nur gelesen: Die Leser hier laufen für große Antworten in
## einem Hilfsfaden (YouTubeTv._lesen). Ein Vorrat, der sich erst beim Benutzen füllt, wäre dort nicht sicher.
static var _RX_SKRIPT := RegEx.create_from_string("<script[^>]*\\bsrc=\"([^\"]*base\\.js)\"")
static var _RX_SKRIPT_PFAD := RegEx.create_from_string("\"(/s/[^\"]*?base\\.js)\"")
static var _RX_CLIENT := RegEx.create_from_string("clientId:\"([-\\w]+\\.apps\\.googleusercontent\\.com)\",\\s*[$\\w]+:\"([-\\w]+)\"")
static var _RX_ZAHL := RegEx.create_from_string("(\\d+(?:[.,\u00a0 ]\\d+)*)\\s*(mrd|mio|tsd|bn|b|m|k)?\\b")
static var _RX_ALTER := RegEx.create_from_string("(\\d+)\\s*(sekunde|second|minute|min|stunde|std|hour|tag|day|woche|week|monat|month|jahr|year)")
static var _RX_UHR := RegEx.create_from_string("^(?:(\\d+):)?(\\d{1,2}):(\\d{2})$")
static var _RX_TOKEN_HOST := RegEx.create_from_string("^https://([a-z0-9.-]+\\.)?(youtube\\.com|googleapis\\.com|google\\.com)/")
static var _RX_KENNUNG := RegEx.create_from_string("^[A-Za-z0-9_-]+$")
static var _RX_LOG_ZUGANG := RegEx.create_from_string("ya29\\.[A-Za-z0-9._-]+")
static var _RX_LOG_ERNEUERN := RegEx.create_from_string("1//[A-Za-z0-9._-]+")
static var _RX_LOG_BEARER := RegEx.create_from_string("(?i)bearer\\s+\\S+")
static var _RX_LOG_FELD := RegEx.create_from_string("(?i)(access_token|refresh_token|device_code|client_secret|code|token)([\"']?\\s*[=:]\\s*[\"']?)[^\\s&\"',}]+")


static func _arten() -> Dictionary:
	var d := {}
	for k in VIDEO_KEYS:
		d[k] = _ART_VIDEO
	for k in SHELF_KEYS:
		d[k] = _ART_REIHE
	for k in SKIP_KEYS:
		d[k] = _ART_SKIP
	return d


static func _behaelter(v: Variant) -> bool:
	var t := typeof(v)
	return t == TYPE_DICTIONARY or t == TYPE_ARRAY


# --- Fernseher-Kennung (wie SmartTube: aus der TV-Seite von YouTube) -------------------------------

## Adresse des Hauptskripts der TV-Seite (youtube.com/tv), relativ oder ganz; "" wenn keins.
static func base_js_url(html: String) -> String:
	var m := _RX_SKRIPT.search(html)
	if m == null:
		m = _RX_SKRIPT_PFAD.search(html)
	return m.get_string(1).replace("\\/", "/") if m != null else ""


## Client-ID und -Schlüssel des Fernseher-Zugangs aus dem Skript ({} wenn nicht gefunden).
static func client_from_js(js: String) -> Dictionary:
	var re := _RX_CLIENT
	var m := re.search(js)
	if m == null:
		return {}
	return { "id": m.get_string(1), "secret": m.get_string(2) }


# --- Geräte-Anmeldung --------------------------------------------------------------------------

static func device_request(client_id: String, device_id: String) -> Dictionary:
	return { "client_id": client_id, "scope": SCOPE, "device_id": device_id, "device_model": DEVICE_MODEL }


## Antwort auf die Code-Anfrage: { ok, device_code, user_code, url, interval, expires } oder { ok: false, error }.
static func parse_device_code(code: int, d: Variant) -> Dictionary:
	if code == 0:
		return { "ok": false, "error": ERR_OFFLINE }
	if not (d is Dictionary) or str(d.get("device_code", "")) == "" or str(d.get("user_code", "")) == "":
		if d is Dictionary and str(d.get("error", "")) in ["invalid_client", "unauthorized_client", "restricted_client"]:
			return { "ok": false, "error": ERR_CLIENT }
		return { "ok": false, "error": "Google hat keinen Code geschickt. Später noch einmal versuchen." }
	var url := str(d.get("verification_url", d.get("verification_uri", "")))
	if not url.begins_with("http"):
		url = ACTIVATE_URL
	return {
		"ok": true, "device_code": str(d.device_code), "user_code": str(d.user_code), "url": url,
		"interval": clampi(int(d.get("interval", 5)), 1, 60), "expires": clampi(int(d.get("expires_in", 1800)), 30, 7200),
	}


## Antwort auf eine Anmeldung oder Erneuerung:
## { ok, access, refresh, expires_at } oder { ok: false, state, error }. state ist dann
## "pending", "slow", "denied", "expired" (Code abgelaufen), "revoked" (Anmeldung ungültig) oder "error".
static func parse_token(code: int, d: Variant, now: int) -> Dictionary:
	if d is Dictionary and str(d.get("access_token", "")) != "":
		return {
			"ok": true, "access": str(d.access_token), "refresh": str(d.get("refresh_token", "")),
			"expires_at": now + clampi(int(d.get("expires_in", 3600)), 60, 86400),
		}
	var e := str(d.get("error", "")) if d is Dictionary else ""
	match e:
		"authorization_pending": return { "ok": false, "state": "pending", "error": "" }
		"slow_down": return { "ok": false, "state": "slow", "error": "" }
		"access_denied": return { "ok": false, "state": "denied", "error": "Die Anmeldung wurde auf dem Handy abgelehnt." }
		"expired_token": return { "ok": false, "state": "expired", "error": "Der Code ist abgelaufen. „Nochmal versuchen“ holt einen neuen." }
		"invalid_grant": return { "ok": false, "state": "revoked", "error": ERR_EXPIRED }
		"invalid_client", "unauthorized_client": return { "ok": false, "state": "error", "error": ERR_CLIENT }
	if code == 0:
		return { "ok": false, "state": "error", "error": ERR_OFFLINE }
	return { "ok": false, "state": "error", "error": "Google antwortet nicht wie erwartet. Später noch einmal versuchen." }


## Nächster Zustand der Geräte-Anmeldung (src/core/geraete_code.gd) mit den Texten dieses Dienstes
## (state wie bei parse_token, "ok" bei Erfolg).
static func flow_step(flow: Dictionary, state: String, now: float, err := "") -> Dictionary:
	return GeraeteCode.schritt(flow, state, now, err, { "offline": ERR_OFFLINE, "sofort": ERR_CLIENT, "grund": true })


# --- InnerTube-Anfragen -------------------------------------------------------------------------

static func context(hl: String, gl: String) -> Dictionary:
	return { "client": { "clientName": CLIENT_NAME, "clientVersion": CLIENT_VERSION, "hl": hl, "gl": gl } }


static func body(payload: Dictionary, hl: String, gl: String) -> Dictionary:
	var b := payload.duplicate()
	b["context"] = context(hl, gl)
	return b


## Deutsche Meldung, wenn eine InnerTube-Anfrage nicht klappte.
static func explain(code: int) -> String:
	if code == 0:
		return ERR_OFFLINE
	if code == 401 or code == 403:
		return "YouTube hat die Fernseher-Anmeldung abgelehnt. Bitte neu anmelden."
	if code == 400 or code == 404:
		return ERR_CHANGED
	if code == 429:
		return "YouTube bremst gerade (zu viele Anfragen). Gleich noch einmal."
	return "YouTube antwortet gerade nicht richtig. Gleich noch einmal versuchen."


# --- Texte in den Antworten -------------------------------------------------------------------

## Text aus { simpleText } / { runs: [{ text }] } / { content } (View Models) oder einem String.
static func text_of(v: Variant) -> String:
	if v is String:
		return v
	if not (v is Dictionary):
		return ""
	if v.get("simpleText") is String:
		return v.simpleText
	if v.get("runs") is Array:
		var s := ""
		for r in v.runs:
			if r is Dictionary:
				s += str(r.get("text", ""))
		return s
	if v.get("content") is String:
		return v.content
	if v.get("text") != null:
		return text_of(v.text)
	return ""


## Zahl mit Kürzel („1,2 Mio.“, „345K“, „12.345“) als ganze Zahl.
static func parse_number(s: String) -> int:
	var re := _RX_ZAHL
	var m := re.search(s.to_lower())
	if m == null:
		return 0
	var num := m.get_string(1).replace(" ", "").replace(" ", "")
	var unit := m.get_string(2)
	var mult := 1.0
	match unit:
		"k", "tsd": mult = 1e3
		"m", "mio": mult = 1e6
		"b", "bn", "mrd": mult = 1e9
	if unit == "":
		return int(num.replace(".", "").replace(",", ""))
	# Mit Kürzel ist das Trennzeichen das Komma (deutsch) oder der Punkt (englisch).
	return int(round(float(num.replace(",", ".")) * mult))


## Aufrufe aus „1,2 Mio. Aufrufe“ / „12.345 Aufrufe“ / „1.2M views“ / „345 Zuschauer“ (-1: kein Aufruf-Text).
static func parse_views(s: String) -> int:
	var l := s.to_lower()
	if not (l.contains("aufruf") or l.contains("view") or l.contains("zuschau") or l.contains("watching") or l.contains("wiedergab")):
		return -1
	if l.contains("keine") or l.begins_with("no "):
		return 0
	return parse_number(l)


## Alter aus „vor 3 Tagen“ / „3 days ago“ / „Gestreamt vor 2 Stunden“ als Zeitpunkt (0: kein Alter).
static func parse_age(s: String, now: int) -> int:
	var l := s.to_lower()
	if not (l.contains("vor ") or l.contains(" ago")):
		return 0
	var re := _RX_ALTER
	var m := re.search(l)
	if m == null:
		return 0
	var n := int(m.get_string(1))
	var unit := m.get_string(2)
	var sec := 0
	match unit:
		"sekunde", "second": sec = 1
		"minute", "min": sec = 60
		"stunde", "std", "hour": sec = 3600
		"tag", "day": sec = 86400
		"woche", "week": sec = 7 * 86400
		"monat", "month": sec = 30 * 86400
		"jahr", "year": sec = 365 * 86400
	return now - n * sec


## „1:02:03“ → 3723, „12:34“ → 754, sonst 0.
static func parse_clock(s: String) -> int:
	var t := s.strip_edges()
	var re := _RX_UHR
	var m := re.search(t)
	if m == null:
		return 0
	return int(m.get_string(1)) * 3600 + int(m.get_string(2)) * 60 + int(m.get_string(3))


static func _is_live_text(s: String) -> bool:
	var l := s.strip_edges().to_lower()
	return l == "live" or l == "live now" or l == "jetzt live" or l.contains("zuschauer") or l.contains("watching") or l.contains("schauen gerade")


# --- Baum durchsuchen ---------------------------------------------------------------------------

## Erster Wert eines Schlüssels irgendwo im Baum (Tiefe begrenzt), sonst null.
static func find_key(node: Variant, key: String, depth := 14, skip := true) -> Variant:
	if depth < 0:
		return null
	if node is Dictionary:
		if node.has(key):
			return node[key]
		for k in node:
			var v: Variant = node[k]
			if not _behaelter(v) or (skip and _art.get(k, 0) == _ART_SKIP):
				continue
			var r: Variant = find_key(v, key, depth - 1, skip)
			if r != null:
				return r
	elif node is Array:
		for e in node:
			if not _behaelter(e):
				continue
			var r2: Variant = find_key(e, key, depth - 1, skip)
			if r2 != null:
				return r2
	return null


## Kanal-ID (UC…) irgendwo in einer Kachel (Verweis auf die Kanalseite).
static func _channel_id_in(node: Variant, depth := 12) -> String:
	if depth < 0:
		return ""
	if node is Dictionary:
		var be: Variant = node.get("browseEndpoint")
		if be is Dictionary and str(be.get("browseId", "")).begins_with("UC"):
			return str(be.browseId)
		for k in node:
			var v: Variant = node[k]
			if not _behaelter(v):
				continue
			var r := _channel_id_in(v, depth - 1)
			if r != "":
				return r
	elif node is Array:
		for e in node:
			if not _behaelter(e):
				continue
			var r2 := _channel_id_in(e, depth - 1)
			if r2 != "":
				return r2
	return ""


## Unter diesen Schlüsseln stehen keine Zeilen für unter dem Titel (der Titel selbst, Bilder, Verweise).
const _TEXT_OHNE := ["title", "thumbnail", "image", "avatar", "onTap", "onSelectCommand", "navigationEndpoint", "commandRuns", "rendererContext"]


## Alle Texte eines Teilbaums in Lesereihenfolge (für die Zeilen unter dem Titel).
static func _texts(node: Variant, out: PackedStringArray, depth := 10) -> void:
	if depth < 0:
		return
	if node is Dictionary:
		if node.get("simpleText") is String or node.get("runs") is Array:
			var t := text_of(node).strip_edges()
			if t != "":
				out.append(t)
			return
		if node.get("label") is String and node.get("style") is String:
			out.append(str(node.label).strip_edges())
			return
		if node.get("content") is String:
			var c := str(node.content).strip_edges()
			if c != "":
				out.append(c)
			return
		for k in node:
			var v: Variant = node[k]
			if not _behaelter(v) or _art.get(k, 0) == _ART_SKIP or k in _TEXT_OHNE:
				continue
			_texts(v, out, depth - 1)
	elif node is Array:
		for e in node:
			if _behaelter(e):
				_texts(e, out, depth - 1)


## Alle Texte unter einem Schlüssel (auch reine Strings wie in thumbnailBadgeViewModel.text).
static func _strings_under(node: Variant, key: String, out: PackedStringArray, depth := 10) -> void:
	if depth < 0:
		return
	if node is Dictionary:
		for k in node.keys():
			var v: Variant = node[k]
			if str(k) == key:
				var t := text_of(v).strip_edges()
				if t != "":
					out.append(t)
			elif v is Dictionary or v is Array:
				_strings_under(v, key, out, depth - 1)
	elif node is Array:
		for e in node:
			_strings_under(e, key, out, depth - 1)


## Breitestes Vorschaubild aus { thumbnails: [...] } oder { sources: [...] }.
static func _best_thumb(node: Variant) -> String:
	var list: Variant = null
	if node is Dictionary:
		list = node.get("thumbnails", node.get("sources"))
	if not (list is Array):
		return ""
	var best := ""
	var bw := -1
	for t in list:
		if t is Dictionary and str(t.get("url", "")) != "":
			var w := int(t.get("width", 0))
			if w > bw:
				bw = w
				best = str(t.url)
	if best.begins_with("//"):
		best = "https:" + best
	return best


## Ein Video aus einer Kachel ({} wenn es keins ist: Playlist, Kanal, Werbung, Mix).
static func video_from(kind: String, n: Dictionary, now: int) -> Dictionary:
	var id := ""
	var title := ""
	var thumb := ""
	var duration := 0
	var live := false
	var short := kind in ["reelItemRenderer", "shortsLockupViewModel"]
	var lines := PackedStringArray()
	match kind:
		"tileRenderer":
			var ct := str(n.get("contentType", ""))
			if ct != "" and not (ct.contains("VIDEO") or ct.contains("SHORT")):
				return {}
			if ct.contains("SHORT"):
				short = true
			var cmd: Variant = n.get("onSelectCommand")
			var we: Variant = find_key(cmd, "watchEndpoint", 6)
			if we is Dictionary:
				id = str(we.get("videoId", ""))
			var rw: Variant = find_key(cmd, "reelWatchEndpoint", 6)
			if rw != null:
				short = true
				if id == "" and rw is Dictionary:
					id = str(rw.get("videoId", ""))
			if id == "":
				id = str(n.get("contentId", ""))
			var md: Variant = find_key(n.get("metadata"), "tileMetadataRenderer", 3)
			if md is Dictionary:
				title = text_of(md.get("title"))
				_texts(md.get("lines"), lines)
			var hd: Variant = find_key(n.get("header"), "tileHeaderRenderer", 3)
			if hd is Dictionary:
				thumb = _best_thumb(hd.get("thumbnail"))
				for o in hd.get("thumbnailOverlays", []):
					var ts: Variant = o.get("thumbnailOverlayTimeStatusRenderer") if o is Dictionary else null
					if ts is Dictionary:
						var tt := text_of(ts.get("text"))
						if str(ts.get("style", "")) == "LIVE" or _is_live_text(tt):
							live = true
						elif parse_clock(tt) > 0:
							duration = parse_clock(tt)
						if str(ts.get("style", "")) == "SHORTS":
							short = true
		"lockupViewModel":
			var lt := str(n.get("contentType", ""))
			if lt != "" and not lt.contains("VIDEO"):
				return {}
			id = str(n.get("contentId", ""))
			var lm: Variant = find_key(n.get("metadata"), "lockupMetadataViewModel", 3)
			if lm is Dictionary:
				title = text_of(lm.get("title"))
				_texts(lm.get("metadata"), lines)
			thumb = _best_thumb(find_key(n.get("contentImage"), "image", 6))
			var badges := PackedStringArray()
			_strings_under(find_key(n.get("contentImage"), "overlays", 6), "text", badges)
			for b in badges:
				if _is_live_text(b):
					live = true
				elif parse_clock(b) > 0:
					duration = parse_clock(b)
		"shortsLockupViewModel":
			var ep: Variant = find_key(n.get("onTap"), "reelWatchEndpoint", 6)
			if ep is Dictionary:
				id = str(ep.get("videoId", ""))
			if id == "":
				id = str(n.get("entityId", "")).trim_prefix("shorts-shelf-item-")
			title = text_of(find_key(n.get("overlayMetadata"), "primaryText", 3))
			_texts(find_key(n.get("overlayMetadata"), "secondaryText", 3), lines)
			thumb = _best_thumb(n.get("thumbnail"))
		_:
			# videoRenderer, gridVideoRenderer, compactVideoRenderer, playlistVideoRenderer, reelItemRenderer
			id = str(n.get("videoId", ""))
			title = text_of(n.get("title", n.get("headline")))
			for k in ["longBylineText", "shortBylineText", "ownerText"]:
				if n.has(k):
					lines.append(text_of(n[k]))
					break
			for k2 in ["viewCountText", "shortViewCountText", "publishedTimeText"]:
				var t2 := text_of(n.get(k2))
				if t2 != "":
					lines.append(t2)
			thumb = _best_thumb(n.get("thumbnail"))
			duration = parse_clock(text_of(n.get("lengthText")))
			for b in n.get("badges", []):
				var mb: Variant = b.get("metadataBadgeRenderer") if b is Dictionary else null
				if mb is Dictionary and (str(mb.get("style", "")).contains("LIVE") or _is_live_text(str(mb.get("label", "")))):
					live = true
			for o2 in n.get("thumbnailOverlays", []):
				var ts2: Variant = o2.get("thumbnailOverlayTimeStatusRenderer") if o2 is Dictionary else null
				if ts2 is Dictionary:
					var st := str(ts2.get("style", ""))
					if st == "LIVE":
						live = true
					elif st == "SHORTS":
						short = true
					elif duration == 0:
						duration = parse_clock(text_of(ts2.get("text")))
	if id.length() != 11 or title.strip_edges() == "":
		return {}
	var channel := ""
	var views := 0
	var published := 0
	# Kanal zuerst in den Angaben unter dem Titel suchen, erst dann in der ganzen Kachel (Menü).
	var cid := _channel_id_in(n.get("metadata", n.get("longBylineText", n.get("shortBylineText"))))
	if cid == "":
		cid = _channel_id_in(n)
	for l in lines:
		var s := str(l).strip_edges()
		if s == "" or s == "•" or s == "·":
			continue
		var vw := parse_views(s)
		if vw >= 0:
			views = maxi(views, vw)
			if s.to_lower().contains("zuschau") or s.to_lower().contains("watching"):
				live = true
			continue
		var age := parse_age(s, now)
		if age > 0:
			published = age
			continue
		if _is_live_text(s):
			live = true
			continue
		if channel == "" and parse_clock(s) == 0:
			channel = s
	return {
		"id": id, "title": title.strip_edges(), "channel": channel, "channel_id": cid,
		"duration": duration, "views": views, "thumb": thumb if thumb != "" else "https://i.ytimg.com/vi/%s/mqdefault.jpg" % id,
		"published": published, "short": short, "live": live, "src": "tv",
	}


## Titel einer Reihe (title, headerRenderer, header …), "" wenn keiner.
static func shelf_title(n: Dictionary) -> String:
	for k in ["title", "headerRenderer", "header"]:
		if not n.has(k):
			continue
		var t := text_of(n[k])
		if t == "":
			var inner: Variant = find_key(n[k], "title", 5)
			t = text_of(inner)
		if t.strip_edges() != "":
			return t.strip_edges()
	return ""


## Weiterblättern-Marke aus continuations: [{ nextContinuationData: { continuation } }] oder
## einem continuationItemRenderer (Browser).
static func _cont_token(v: Variant) -> String:
	if v is Array:
		for c in v:
			if c is Dictionary:
				for k in ["nextContinuationData", "reloadContinuationData"]:
					if c.get(k) is Dictionary and str(c[k].get("continuation", "")) != "":
						return str(c[k].continuation)
	elif v is Dictionary:
		var cc: Variant = find_key(v, "continuationCommand", 5)
		if cc is Dictionary and str(cc.get("token", "")) != "":
			return str(cc.token)
	return ""


static func _walk(node: Variant, ctx: Dictionary, cur: Variant, depth: int) -> void:
	if depth > 60:
		return
	if node is Array:
		for e in node:
			_walk(e, ctx, cur, depth + 1)
		return
	if not (node is Dictionary):
		return
	for k in node:
		var v: Variant = node[k]
		# Die allermeisten Werte sind Texte und Zahlen: Für sie ist hier nichts zu tun.
		if not _behaelter(v):
			continue
		var art := int(_art.get(k, 0))
		if art == _ART_SKIP:
			continue
		if art == _ART_REIHE and v is Dictionary:
			var shelf := { "title": shelf_title(v), "items": [], "_ids": {} }
			(ctx.shelves as Array).append(shelf)
			_walk(v, ctx, shelf, depth + 1)
		elif art == _ART_VIDEO and v is Dictionary:
			var vid := video_from(str(k), v, int(ctx.now))
			if vid.is_empty():
				continue
			var into: Dictionary = cur if cur is Dictionary else _loose(ctx)
			if not (into._ids as Dictionary).has(vid.id):
				into._ids[vid.id] = true
				(into.items as Array).append(vid)
		elif cur == null and (k == "continuations" or k == "continuationItemRenderer") and str(ctx.cont) == "":
			ctx.cont = _cont_token(v)
		else:
			_walk(v, ctx, cur, depth + 1)


## Videos außerhalb einer Reihe sammeln sich in einer Reihe ohne Titel.
static func _loose(ctx: Dictionary) -> Dictionary:
	if not (ctx.get("loose") is Dictionary):
		ctx.loose = { "title": "", "items": [], "_ids": {} }
		(ctx.shelves as Array).append(ctx.loose)
	return ctx.loose


## Startseite (browse FEwhat_to_watch) oder ihre Fortsetzung:
## { shelves: [{ title, items: [Video] }], continuation }. Leere Reihen (etwa nur Shorts bei
## „Shorts ausblenden“) fallen weg. first_title: Name der ersten Reihe ohne Titel.
static func parse_browse(d: Variant, now: int, hide_shorts := true, first_title := "Für dich") -> Dictionary:
	var ctx := { "shelves": [], "cont": "", "now": now }
	if d is Dictionary or d is Array:
		_walk(d, ctx, null, 0)
	var out: Array = []
	for s in ctx.shelves:
		var items: Array = s.items
		if hide_shorts:
			items = items.filter(func(v: Dictionary) -> bool: return not bool(v.short))
		if items.is_empty():
			continue
		var t := str(s.title)
		if t == "":
			t = first_title if out.is_empty() else "Mehr für dich"
		out.append({ "title": t, "items": items })
	return { "shelves": out, "continuation": str(ctx.cont) }


## Empfohlene Videos zu einem Video (next): alle Reihen flach, ohne das Video selbst und Doppelte.
static func parse_next(d: Variant, video_id: String, now: int, hide_shorts := true, limit := 40) -> Array:
	var p := parse_browse(d, now, hide_shorts)
	var out: Array = []
	var seen := { video_id: true }
	for s in p.shelves:
		for v in s.items:
			if seen.has(v.id):
				continue
			seen[v.id] = true
			out.append(v)
			if out.size() >= limit:
				return out
	return out


## Kontoname aus account/accounts_list ("" wenn keiner).
static func parse_account_name(d: Variant) -> String:
	# Steckt in einem Menü (getMultiPageMenuAction) – darum hier auch Menüs durchsuchen.
	return text_of(find_key(d, "accountName", 24, false)).strip_edges()


## Adresse, über die YouTube „gesehen“ zählt (player → playbackTracking), "" wenn keine.
static func tracking_url(d: Variant) -> String:
	var pt: Variant = find_key(d, "playbackTracking", 4)
	if not (pt is Dictionary):
		return ""
	var u: Variant = pt.get("videostatsPlaybackUrl")
	return str(u.get("baseUrl", "")) if u is Dictionary else ""


## Zufällige Wiedergabe-Kennung (16 Zeichen wie beim Player von YouTube).
static func cpn(rng: RandomNumberGenerator) -> String:
	const CH := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
	var s := ""
	for i in 16:
		s += CH[rng.randi_range(0, CH.length() - 1)]
	return s


## Darf das Anmelde-Token an diese Adresse? Nur YouTube/Google selbst (oder der Testserver).
static func token_host_ok(url: String, test_base := "") -> bool:
	if test_base != "" and url.begins_with(test_base.trim_suffix("/") + "/"):
		return true
	var re := _RX_TOKEN_HOST
	return re.search(url) != null


# --- Abos (browse FEsubscriptions, Rückfall FEchannels) -----------------------------------------
# Auf dem Fernseher stehen die Abos als Reiter links (tvSecondaryNavRenderer → tabRenderer je
# Kanal, der erste „Alle“ mit dem Feed als gridRenderer voller tileRenderer). Im Browser und in
# neueren Antworten kommen Kanäle auch als Kachel (tileRenderer mit Kanal-Inhalt), als
# gridChannelRenderer/channelRenderer, in der Seitenleiste (guideEntryRenderer) oder als
# lockupViewModel. Der Leser nimmt alles davon – Kanäle nur aus diesen Behältern, nie aus den
# Videos selbst (die verweisen auch auf ihren Kanal, der aber kein Abo sein muss).

const CHANNEL_KEYS := ["tabRenderer", "compactLinkRenderer", "tileRenderer", "gridChannelRenderer", "channelRenderer", "guideEntryRenderer",
		"lockupViewModel", "channelListItemRenderer"]
## Wo in einem solchen Behälter der Verweis steht (nicht im Inhalt: Reiter tragen ihren Feed mit).
const CHANNEL_LINKS := ["endpoint", "navigationEndpoint", "onSelectCommand", "onTap", "command", "rendererContext"]


## Kanal-Kennung, wie YouTube sie vergibt: UC und 22 Zeichen aus A–Z, a–z, 0–9, - und _ (etwas
## Spielraum für die Länge). Wird in Adressen eingesetzt (RSS) – darum streng.
static func channel_id_ok(id: String) -> bool:
	return id.length() >= 20 and id.length() <= 34 and id.begins_with("UC") and _RX_KENNUNG.search(id) != null


## Vorschaubild irgendwo unter einem Knoten (thumbnails oder sources).
static func _thumb_in(node: Variant) -> String:
	var t := _best_thumb(node)
	if t != "":
		return t
	for k in ["thumbnails", "sources"]:
		var l: Variant = find_key(node, k, 8)
		if l is Array:
			t = _best_thumb({ k: l })
			if t != "":
				return t
	return ""


## Ein Kanal aus einem Behälter ({} wenn es keiner ist).
static func channel_from(kind: String, n: Dictionary) -> Dictionary:
	if kind in ["tileRenderer", "lockupViewModel"] and not str(n.get("contentType", "")).contains("CHANNEL"):
		return {}
	var id := ""
	for k in CHANNEL_LINKS:
		if n.has(k):
			var be: Variant = find_key(n[k], "browseEndpoint", 8)
			if be is Dictionary and channel_id_ok(str(be.get("browseId", ""))):
				id = str(be.browseId)
				break
	if id == "" and channel_id_ok(str(n.get("channelId", ""))):
		id = str(n.channelId)
	if id == "" and kind in ["tileRenderer", "lockupViewModel"] and channel_id_ok(str(n.get("contentId", ""))):
		id = str(n.contentId)
	if id == "":
		return {}
	var title := ""
	match kind:
		"tileRenderer", "lockupViewModel":
			title = text_of(find_key(n.get("metadata"), "title", 5))
		"guideEntryRenderer":
			title = text_of(n.get("formattedTitle", n.get("title")))
		_:
			title = text_of(n.get("title", n.get("text")))
	title = title.strip_edges()
	if title == "":
		return {}
	var thumb := ""
	for k in ["thumbnail", "avatar", "image", "header", "contentImage", "icon"]:
		if n.has(k):
			thumb = _thumb_in(n[k])
			if thumb != "":
				break
	return { "id": id, "title": title, "thumb": thumb }


static func _walk_channels(node: Variant, out: Array, seen: Dictionary, depth: int) -> void:
	if depth > 60:
		return
	if node is Array:
		for e in node:
			_walk_channels(e, out, seen, depth + 1)
		return
	if not (node is Dictionary):
		return
	for k in node:
		var v: Variant = node[k]
		if not _behaelter(v) or _art.get(k, 0) == _ART_SKIP:
			continue
		if v is Dictionary and k in CHANNEL_KEYS:
			var c := channel_from(str(k), v)
			if not c.is_empty() and not seen.has(c.id):
				seen[c.id] = true
				out.append(c)
		_walk_channels(v, out, seen, depth + 1)


## Abos (browse FEsubscriptions bzw. FEchannels): { channels: [{ id, title, thumb }],
## videos: [Video] (neueste zuerst, wie YouTube sie schickt), continuation }.
static func parse_subs(d: Variant, now: int, hide_shorts := true) -> Dictionary:
	var channels: Array = []
	if d is Dictionary or d is Array:
		_walk_channels(d, channels, {}, 0)
	var p := parse_browse(d, now, hide_shorts, "Abos")
	var videos: Array = []
	var seen := {}
	for s in p.shelves:
		for v in s.items:
			if not seen.has(v.id):
				seen[v.id] = true
				videos.append(v)
	return { "channels": channels, "videos": videos, "continuation": str(p.continuation) }


## Kanäle aus den Videos des Abo-Feeds (wenn YouTube keine Kanalliste schickt): je Kanal einmal,
## nur mit gültiger Kennung und Namen.
static func channels_from_videos(videos: Array) -> Array:
	var out: Array = []
	var seen := {}
	for v in videos:
		if not (v is Dictionary):
			continue
		var cid := str(v.get("channel_id", ""))
		var name := str(v.get("channel", "")).strip_edges()
		if channel_id_ok(cid) and name != "" and not seen.has(cid):
			seen[cid] = true
			out.append({ "id": cid, "title": name, "thumb": "" })
	return out


# --- Protokoll (logs/youtube.log) ----------------------------------------------------------------

## Aufbau einer Antwort nur aus ihren Schlüsseln, ohne Werte (nichts Persönliches, keine
## Kennungen) – fürs Protokoll, wenn der Leser nichts fand: so sieht man, was YouTube geändert hat.
static func shape(node: Variant, depth := 5, width := 6) -> String:
	if depth <= 0:
		return "…"
	if node is Dictionary:
		var parts := PackedStringArray()
		for k in node.keys():
			if str(k) in ["responseContext", "trackingParams", "frameworkUpdates", "clickTrackingParams", "loggingDirectives"]:
				continue
			if parts.size() >= width:
				parts.append("…")
				break
			var v: Variant = node[k]
			parts.append(str(k).left(48) + ("{" + shape(v, depth - 1, width) + "}" if v is Dictionary or v is Array else ""))
		return ",".join(parts)
	if node is Array:
		return "[%d]%s" % [node.size(), shape(node[0], depth - 1, width) if node.size() > 0 and (node[0] is Dictionary or node[0] is Array) else ""]
	return ""


## Protokollzeile ohne Zugangsdaten: Anmelde- und Erneuerungsmarken, Bearer, Codes in Adressen
## werden unkenntlich gemacht (Sicherheitsnetz – die Zeilen selbst nennen sie nie).
static func log_sicher(text: String) -> String:
	var t := _RX_LOG_ZUGANG.sub(text, "[…]", true)
	t = _RX_LOG_ERNEUERN.sub(t, "[…]", true)
	t = _RX_LOG_BEARER.sub(t, "Bearer […]", true)
	t = _RX_LOG_FELD.sub(t, "$1$2[…]", true)
	return t.replace("\n", " ").left(600)
