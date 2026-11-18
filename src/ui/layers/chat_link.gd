extends "res://src/ui/layers/modal.gd"
## Ein Link aus dem Chat, ohne Browser: Uzai öffnet, was es selbst kann (YouTube im
## Video-Player, Spotify in der Musik, Steam-Shopseiten im Shop, Beitreten startet das Spiel).
## Alles andere geht als QR-Code aufs Handy – mit kurzer Vorschau (Titel und Beschreibung der
## Seite), damit man weiß, was dahinter steckt.

const QrView := preload("res://src/ui/components/qr_view.gd")
const StoreGame := preload("res://src/ui/layers/store_game.gd")
const Lang := preload("res://src/core/lang.gd")
const Sicher := preload("res://src/core/sicher.gd")
const Fremd := preload("res://src/core/fremd.gd")

var info: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var preview := true             ## Titel und Beschreibung der Seite nachladen (eigene Links: nein)
var _title: Label
var _desc: Label


func fill() -> void:
	width = 1040.0
	set_meta("uz_hint_b", "Schließen")
	var row := U.hbox(44)
	box.add_child(row)
	var frame := PanelContainer.new()
	var fsb := UzTheme.box(Color.WHITE, UzTheme.r_panel())
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		fsb.set_content_margin(side, 10)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var qr = QrView.new()
	qr.setup(str(info.get("url", "")), 300)
	frame.add_child(qr)
	row.add_child(frame)
	var col := U.vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var kicker := U.hbox(10)
	kicker.add_child(U.icon("qr", 22, "accent"))
	kicker.add_child(U.label("Link aufs Handy", "s", "accent", "medium"))
	col.add_child(kicker)
	var web := str(info.get("kind", "web")) == "web"
	col.add_child(U.label(str(info.get("host", "Link")) if web else str(info.get("label", "Link")), "xl", "text", "black", true))
	# Titel und Beschreibung der fremden Seite und die Adresse stehen da, wie sie sind: nie übersetzen.
	_title = U.label("", "l", "text", "medium", true)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.max_lines_visible = 2
	_title.visible = false
	col.add_child(_title)
	_desc = U.label("", "m", "muted", "regular", true)
	_desc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_desc.max_lines_visible = 3
	_desc.visible = false
	col.add_child(_desc)
	var u := U.label(short_url(str(info.get("url", "")), 90), "s", "faint", "regular", true)
	u.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	u.max_lines_visible = 2
	col.add_child(u)
	col.add_child(U.spacer(0, 6, false))
	col.add_child(U.label("Mit dem Handy scannen, um den Link zu öffnen.", "s", "muted", "regular", true))
	col.add_child(U.spacer(0, 10, false))
	var btns := U.hbox(12)
	col.add_child(btns)
	var done := U.button("Fertig", "check", "primary")
	done.set_meta("uz_default", true)
	done.pressed.connect(close)
	btns.add_child(done)
	if str(info.get("kind", "web")) != "web":
		var act := U.button(str(info.get("action", "Öffnen")), str(info.get("icon", "link")))
		act.pressed.connect(func() -> void:
			close()
			open_in_uzai(main, info)
		)
		btns.add_child(act)
	if preview:
		_preview()


## Titel und Beschreibung der Seite nachladen (nur für normale Webseiten).
func _preview() -> void:
	if str(info.get("kind", "")) != "web":
		return
	var body := await _fetch_page(str(info.url))
	if body.is_empty() or not is_inside_tree():
		return
	var meta := og_meta(body.slice(0, 300000).get_string_from_utf8())
	if str(meta.title) != "":
		_title.text = str(meta.title)
		_title.visible = true
		_title.modulate.a = 0.0
		create_tween().tween_property(_title, "modulate:a", 1.0, U.T_BASE)
	if str(meta.desc) != "":
		_desc.text = str(meta.desc)
		_desc.visible = true
		_desc.modulate.a = 0.0
		create_tween().tween_property(_desc, "modulate:a", 1.0, U.T_BASE)


## Nur der Anfang einer Webseite, und nur HTML: ein Link auf eine große Datei wird nicht
## heruntergeladen (höchstens 1,5 MB, dann bricht der Abruf ab). Der Link kommt von irgendwem aus dem Chat: nie zu diesem PC oder ins
## Heimnetz (Router, NAS), auch nicht über eine Weiterleitung – der folgt Uzai darum selbst.
func _fetch_page(url: String) -> PackedByteArray:
	var target := url
	for hop in Sicher.MAX_HOPS + 1:
		if not await Sicher.public_url_async(target):
			return PackedByteArray()
		if not is_inside_tree():
			return PackedByteArray()
		var r := await Net.request(target,
				PackedStringArray(["User-Agent: Mozilla/5.0 (compatible; Uzai)", "Accept: text/html", "Accept-Language: " + str(Lang.api("accept"))]),
				HTTPClient.METHOD_GET, "", 8.0, "api", 1500000, false)
		if not is_inside_tree():
			return PackedByteArray()
		var code := int(r.code)
		if code >= 300 and code < 400:
			target = Sicher.redirect_target(target, header_of(r.headers, "location"))
			continue
		if not bool(r.ok):
			return PackedByteArray()
		var ct := header_of(r.headers, "content-type").to_lower()
		if ct != "" and not ct.contains("html"):
			return PackedByteArray()
		return r.body
	return PackedByteArray()


static func header_of(headers: PackedStringArray, name: String) -> String:
	for h in headers:
		if str(h).to_lower().begins_with(name + ":"):
			return str(h).substr(name.length() + 1).strip_edges()
	return ""


# --- Links erkennen ------------------------------------------------------------------------

static var _re := {}


static func _rx(key: String, pattern: String) -> RegEx:
	if not _re.has(key):
		_re[key] = RegEx.create_from_string(pattern)
	return _re[key]

## Alle Links in einem Text, in Reihenfolge: [{ url, start, end }]. Satzzeichen am Ende
## (Punkt, Komma, schließende Klammer ohne öffnende …) gehören nicht dazu.
static func find_links(text: String) -> Array:
	var out: Array = []
	var re := _rx("link", "(?i)(?:https?://|www\\.|steam://(?:joinlobby|connect|store)/)[^\\s<>\"]+")
	for m in re.search_all(text):
		var url := m.get_string()
		while url.length() > 0 and ".,;:!?'\u201c\u201d\u00bb\u00ab".contains(url.right(1)):
			url = url.left(-1)
		while url.ends_with(")") and url.count("(") < url.count(")"):
			url = url.left(-1)
		if url.length() < 6:
			continue
		out.append({ "url": url, "start": m.get_start(), "end": m.get_start() + url.length() })
	return out


## Was ein Link ist und was Uzai damit tun kann:
## { kind: youtube|spotify|store|join|web, url, host, id, label, action, icon }
static func link_info(raw: String) -> Dictionary:
	var url := raw
	if url.to_lower().begins_with("www."):
		url = "https://" + url
	var host := host_of(url)
	var info := { "kind": "web", "url": url, "host": host, "id": "", "label": "", "action": "Aufs Handy", "icon": "qr" }
	var low := url.to_lower()
	if low.begins_with("steam://joinlobby/") or low.begins_with("steam://connect/"):
		# Aus dem Chat, also von irgendwem: nur Lobby-Nummern bzw. Host und Anschluss – alles
		# dahinter ginge als Startparameter ins Spiel. Sonst nur als QR-Code.
		if Sicher.steam_join_ok(url):
			info.merge({ "kind": "join", "host": "Steam", "label": "Einladung zum Mitspielen", "action": "Beitreten", "icon": "play" }, true)
		return info
	if low.begins_with("steam://store/"):
		var sid := url.get_slice("/", 3).get_slice("/", 0)
		if sid.is_valid_int():
			info.merge({ "kind": "store", "host": "Steam-Shop", "id": sid, "label": "Spiel im Steam-Shop", "action": "Im Shop ansehen", "icon": "shop" }, true)
		return info
	var yt := _rx("yt", "(?i)(?:youtube\\.com/(?:watch\\?(?:[^#\\s]*&)?v=|shorts/|live/|embed/)|youtu\\.be/)([A-Za-z0-9_-]{11})")
	var m := yt.search(url)
	if m:
		info.merge({ "kind": "youtube", "host": "YouTube", "id": m.get_string(1), "label": "YouTube-Video", "action": "Ansehen", "icon": "video" }, true)
		return info
	var sp := _rx("sp", "(?i)open\\.spotify\\.com/(?:intl-[a-z]+/)?(track|album|playlist|episode)/([A-Za-z0-9]+)")
	m = sp.search(url)
	if m:
		var what := m.get_string(1).to_lower()
		var names := { "track": "Song", "album": "Album", "playlist": "Playlist", "episode": "Podcast-Folge" }
		info.merge(
				{ "kind": "spotify", "host": "Spotify", "id": "spotify:%s:%s" % [what, m.get_string(2)], "label": "%s auf Spotify" % names.get(what, "Titel"),
				"action": "Abspielen", "icon": "music" }, true)
		return info
	var st := _rx("st", "(?i)(?:store\\.steampowered\\.com|steamcommunity\\.com)/app/(\\d+)")
	m = st.search(url)
	if m:
		info.merge({ "kind": "store", "host": "Steam-Shop", "id": m.get_string(1), "label": "Spiel im Steam-Shop", "action": "Im Shop ansehen", "icon": "shop" },
				true)
		return info
	# Direct image and video links, so they are visible in the chat: an image from a known image host is shown in
	# the bubble; a video gets its own card (A: send to phone).
	if bild_url(url):
		info.merge({ "kind": "bild", "label": "Bild", "action": "Ansehen", "icon": "image" }, true)
		return info
	if video_url(url):
		info.merge({ "kind": "video", "label": "Video", "action": "Aufs Handy", "icon": "video" }, true)
		return info
	return info


## Bilddienste, von denen Uzai ein Bild aus dem Chat zeigt – nur diese, nur https: Der Link kommt von irgendwem, und
## ein Bild zu laden heißt, die Adresse abzurufen (nie den eigenen PC, das Heimnetz oder eine beliebige Seite).
const BILD_HOSTS := ["images.steamusercontent.com", "steamuserimages-a.akamaihd.net", "cdn.discordapp.com", "media.discordapp.net",
	"i.imgur.com", "i.redd.it", "pbs.twimg.com", "shared.akamai.steamstatic.com", "shared.fastly.steamstatic.com"]
const BILD_ENDUNGEN := ["png", "jpg", "jpeg", "webp"]
const VIDEO_ENDUNGEN := ["mp4", "webm", "mov", "m4v", "mkv"]


## Zeigt Uzai dieses Bild direkt? https, bekannter Bilddienst, Bildendung – Steams Chat-Bilder (ugc) kommen ohne Endung.
static func bild_url(url: String) -> bool:
	if not url.to_lower().begins_with("https://") or url.length() > 2048 or mehrdeutig(url):
		return false
	var host := host_of(url)
	if not host in BILD_HOSTS:
		return false
	if host == "images.steamusercontent.com" or host == "steamuserimages-a.akamaihd.net":
		return true
	return _endung(url) in BILD_ENDUNGEN


static func video_url(url: String) -> bool:
	return url.to_lower().begins_with("http") and _endung(url) in VIDEO_ENDUNGEN


static func _endung(url: String) -> String:
	var pfad := url.get_slice("?", 0).get_slice("#", 0)
	var datei := pfad.get_slice("/", pfad.count("/"))
	return datei.get_extension().to_lower() if datei.contains(".") else ""


## Host einer Adresse – mit demselben Leser wie der Abruf (Sicher.url_parts). Früher las diese Funktion
## „https://evil.example\@i.imgur.com/a.png“ als i.imgur.com (Bild erlaubt, QR-Dialog zeigt i.imgur.com), der Abruf
## und das Handy verbanden aber zu evil.example.
static func host_of(url: String) -> String:
	var u := url if url.contains("://") else "https://" + url
	return str(Sicher.url_parts(u).get("host", "")).trim_prefix("www.")


## Adressen, die zwei Lesern verschieden erscheinen können: Rückstrich irgendwo oder Anmeldedaten vor dem Host.
static func mehrdeutig(url: String) -> bool:
	var rest := url.get_slice("://", 1) if url.contains("://") else url
	return url.contains("\\") or rest.get_slice("/", 0).get_slice("?", 0).get_slice("#", 0).contains("@")


## Link kurz zum Anzeigen: ohne https://, notfalls in der Mitte gekürzt.
static func short_url(url: String, max_len := 42) -> String:
	var s := url
	for p in ["https://", "http://"]:
		if s.to_lower().begins_with(p):
			s = s.substr(p.length())
	s = s.trim_prefix("www.")
	if s.length() <= max_len:
		return s
	return s.left(max_len - 11) + "…" + s.right(10)


## Titel, Beschreibung und Seitenname aus dem Kopf einer Webseite (Open Graph, sonst <title>).
static func og_meta(html: String) -> Dictionary:
	var out := { "title": "", "desc": "", "site": "" }
	var tag := RegEx.create_from_string("(?is)<meta\\s[^>]*>")
	var key := RegEx.create_from_string("(?i)(?:property|name)\\s*=\\s*[\"']([^\"']+)[\"']")
	var c1 := RegEx.create_from_string("(?is)content\\s*=\\s*\"([^\"]*)\"")
	var c2 := RegEx.create_from_string("(?is)content\\s*=\\s*'([^']*)'")
	for m in tag.search_all(html):
		var t := m.get_string()
		var k := key.search(t)
		if k == null:
			continue
		var c := c1.search(t)
		if c == null:
			c = c2.search(t)
		if c == null:
			continue
		var v := unescape(c.get_string(1)).strip_edges()
		match k.get_string(1).to_lower():
			"og:title", "twitter:title":
				if out.title == "":
					out.title = v
			"og:description", "description", "twitter:description":
				if out.desc == "":
					out.desc = v
			"og:site_name":
				out.site = v
	if out.title == "":
		var tt := RegEx.create_from_string("(?is)<title[^>]*>(.*?)</title>")
		var m2 := tt.search(html)
		if m2:
			out.title = unescape(m2.get_string(1)).strip_edges()
	# Was die fremde Seite über sich sagt, kommt nur als schlichter Text in die Vorschau (Fremd.anzeige).
	out.title = Fremd.anzeige(str(out.title), 160)
	out.desc = Fremd.anzeige(str(out.desc), 320)
	out.site = Fremd.anzeige(str(out.site), 80)
	return out


static var _ZEICHEN_NR := RegEx.create_from_string("&#(x?)([0-9a-fA-F]{1,8});")


## Zeichen-Kürzel in Titel und Beschreibung einer fremden Seite auflösen. Nummern ergeben keine Steuerzeichen und
## keine umgedrehte Schreibrichtung (Fremd.zeichen): Mit ihr ließe sich in der Vorschau ein anderer Text vortäuschen,
## als die Seite trägt.
static func unescape(s: String) -> String:
	var t := s.replace("&quot;", "\"").replace("&#39;", "'").replace("&#x27;", "'").replace("&apos;", "'")
	t = t.replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ").replace("&ndash;", "–").replace("&mdash;", "—")
	for m in _ZEICHEN_NR.search_all(t):
		var code := m.get_string(2).hex_to_int() if m.get_string(1) != "" else int(m.get_string(2))
		t = t.replace(m.get_string(), Fremd.zeichen(code))
	return t.replace("&amp;", "&")


# --- Öffnen --------------------------------------------------------------------------------

## A auf einem Link: in Uzai öffnen, was Uzai kann; sonst der QR-Code fürs Handy.
static func open_in_uzai(main_node: Main, li: Dictionary) -> void:
	match str(li.get("kind", "web")):
		"youtube":
			var vid := str(li.id)
			main_node.open_video([{ "id": vid, "title": "Video aus dem Chat", "channel": "", "channel_id": "",
				"duration": 0, "views": 0, "thumb": YouTube.thumb_for(vid), "short": false, "live": false }], 0)
		"spotify":
			if Music.has_spotify():
				var uri := str(li.id)
				if uri.begins_with("spotify:track:") or uri.begins_with("spotify:episode:"):
					Music.play_list([{ "uri": uri }], 0)
				else:
					Music.play_playlist(uri)
				Toasts.show_toast("Läuft gleich", str(li.get("label", "Spotify")), "music", { "sound": "select" })
			else:
				show_qr(main_node, li)
		"store":
			var appid := int(str(li.id))
			var mine := Library.get_game("steam:%d" % appid)
			if not mine.is_empty():
				main_node.open_game(mine)
				return
			# Name für die Shopseite (die Seite selbst lädt Bilder, Preis und Beschreibung).
			var nm := "Spiel im Steam-Shop"
			var r := await Net.get_json(Store.DETAILS % appid)
			if r.ok and r.data is Dictionary and r.data.get(str(appid)) is Dictionary and r.data[str(appid)].get("data") is Dictionary:
				nm = str(r.data[str(appid)].data.get("name", nm))
			if not is_instance_valid(main_node):
				return
			var l = StoreGame.new()
			l.item = { "appid": appid, "name": nm, "header": Store.CDN % [appid, "header.jpg"],
				"capsule": Store.CDN % [appid, "capsule_616x353.jpg"], "price": 0, "original": 0, "discount": 0 }
			l.main = main_node
			main_node.open_layer(l)
		"bild":
			# An image from the chat opens large in Uzai (like a screenshot), never on the phone.
			var v = load("res://src/ui/layers/capture_view.gd").new()
			var alle: Array = li.get("bilder", [str(li.url)]) if li.get("bilder") is Array else [str(li.url)]
			v.files = alle.filter(func(u: Variant) -> bool: return str(u).begins_with("https://"))
			v.titel = str(li.get("titel", "Bild"))
			if not (v.files as Array).is_empty():
				main_node.open_layer(v)
		"join":
			# Beitreten startet das Spiel selbst (Steam verbindet), das ist keine Weiterleitung.
			if not Sicher.steam_join_ok(str(li.url)):
				return
			OS.shell_open(str(li.url))
			Toasts.show_toast("Beitreten", "Steam startet das Spiel und verbindet dich.", "play", { "sound": "launch" })
		_:
			show_qr(main_node, li)


## preview false: nichts aus dem Netz holen, nur den Code zeigen (Links an Spielen, Roadmap 41).
static func show_qr(main_node: Main, li: Dictionary, preview := true) -> void:
	var l = load("res://src/ui/layers/chat_link.gd").new()
	l.info = li
	l.preview = preview
	main_node.open_layer(l)
