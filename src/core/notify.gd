extends Node
## Nachrichten von Freunden als Pop-up, sofort und auch im Spiel: Steam-Direktnachrichten
## (über Uzais eigene Verbindung zu Steam, sonst aus der Abfrage) und Discord-Benachrichtigungen
## (Direktnachrichten, Erwähnungen über die lokale Schnittstelle der Discord-App).
##
## Hier steht nur die Entscheidung, ob ein Pop-up erscheint (nichts doppelt, nichts Eigenes,
## nicht für den Chat, der gerade offen ist), und was „Öffnen“ tut: In Uzai öffnet View den
## Chat, im Spiel öffnet die Guide-Taste den Guide gleich beim Chat oder den Mitteilungen.
## Das Zeigen selbst übernimmt Toasts (im Spiel in einem eigenen Fenster, siehe toast_window.gd).

const NichtStoeren := preload("res://src/core/nicht_stoeren.gd")
const Online := preload("res://src/room/online.gd")
const EinladungChat := preload("res://src/room/einladung_chat.gd")
const DiscordChatS := preload("res://src/core/discord_chat.gd")      ## medien_aus: Bilder aus Discords Benachrichtigung
const SEEN_MAX := 500
## Zimmer online: Einladungen aus dem Chat (was angeboten wurde, Wiederholung, Flut) – nur im Speicher.
var einladungen := EinladungChat.new()
## Melden, wenn online: so viele Steam-Freunde höchstens (notify.watch).
const WATCH_MAX := 50
## So lange nach einem Pop-up öffnet die Guide-Taste im Spiel direkt den Chat dazu.
const OPEN_MS := 30000
const SHOW_MS := 6500

var seen := {}                  ## Schlüssel bereits gezeigter Nachrichten -> true
var last: Dictionary = {}       ## { kind: steam|discord, target, at (ms), over } – das letzte Pop-up
var shown := 0                  ## gezeigte Pop-ups (für Tests)
var _online := {}               ## Melden, wenn online: Steam-ID -> war online (leer bis zur ersten Liste)


func _ready() -> void:
	SteamChat.incoming.connect(_on_steam)
	Voice.discord_notice.connect(_on_discord)
	Social.updated.connect(_on_social)
	_apply_discord()
	Config.changed.connect(func(k: String) -> void:
		if k == "notify.discord":
			_apply_discord()
			Voice.update_notices()
	)


## Discord: Recht für Benachrichtigungen bei der Freigabe mitbeantragen (lehnt Discord es ab,
## fragt Voice von selbst ohne es neu) und das Ereignis abonnieren.
func _apply_discord() -> void:
	var on := bool(Config.get_value("notify.discord", true))
	Voice.want_notices = on
	if on and not Voice.extra_scopes.has(Voice.NOTIFY_SCOPE):
		Voice.extra_scopes.append(Voice.NOTIFY_SCOPE)
	elif not on:
		Voice.extra_scopes.erase(Voice.NOTIFY_SCOPE)


# --- Entscheidung (reine Funktionen, siehe tests/logic_mitteilungen.gd) --------------------

## Schlüssel einer Steam-Nachricht: Zeit und laufende Nummer vom Server sind in der Echtzeit-
## Meldung und im Verlauf gleich – so wird dieselbe Nachricht nie zweimal gemeldet.
static func steam_key(m: Dictionary) -> String:
	var at := int(m.get("at", 0))
	var key := "s:%s:%d:%d" % [str(m.get("friend", "")), at, int(m.get("ordinal", 0))]
	if at == 0:
		key += ":" + str(m.get("text", "")).md5_text().left(10)
	return key


## "" = Pop-up zeigen, sonst der Grund, warum nicht.
static func steam_reason(m: Dictionary, open_chat: String, seen_keys: Dictionary, enabled: bool) -> String:
	if not enabled:
		return "aus"
	if int(m.get("kind", 1)) != 1:
		return "keine Nachricht"
	if bool(m.get("echo", false)) or bool(m.get("me", false)):
		return "eigene"
	var fid := str(m.get("friend", ""))
	if fid == "" or fid == "0":
		return "unbekannt"
	if fid == open_chat:
		return "offen"
	if str(m.get("text", "")).strip_edges() == "":
		return "leer"
	if seen_keys.has(steam_key(m)):
		return "doppelt"
	return ""


## Gründe in Worten fürs Protokoll (steam.log, siehe steam_zeile).
const GRUND := { "aus": "Steam-Nachrichten in den Einstellungen aus", "keine Nachricht": "keine Nachricht",
	"eigene": "eigene Nachricht (anderes Gerät)", "unbekannt": "Absender unbekannt",
	"offen": "Chat ist offen und zu sehen (gilt als gelesen)", "leer": "ohne Text", "doppelt": "schon gemeldet" }


## Eine Zeile je eingehender Nachricht für steam.log: woher, von wem (nur das Kürzel aus SteamChat.log_tag), ob
## und warum (nicht) gemeldet – nie der Text, nie Name oder Steam-ID. So zeigt ein Protokoll den Grund, wenn ein
## Pop-up fehlt. (rein, getestet) wie: { abfrage (aus der Abfrage statt sofort), ruhig (Nicht stören),
## verdeckt (Chat offen, aber nicht zu sehen), ueber_spiel (eigenes Fenster über dem Spiel), vorn (Uzai liegt
## vorn), im_spiel_aus (Einstellung „Pop-ups im Spiel“ aus) }
static func steam_zeile(wer: String, why: String, wie: Dictionary) -> String:
	var kopf := "Nachricht %s von %s: " % ["aus der Abfrage" if bool(wie.get("abfrage", false)) else "sofort", wer]
	if why != "":
		return kopf + "kein Pop-up – " + str(GRUND.get(why, why))
	if bool(wie.get("ruhig", false)):
		return kopf + "kein Pop-up – Nicht stören (still in die Mitteilungen)"
	var ueber := bool(wie.get("ueber_spiel", false))
	var out := "Pop-up über dem Spiel" if ueber else "Pop-up in Uzai"
	if not ueber and not bool(wie.get("vorn", true)):
		out += ", aber Uzai liegt nicht vorn" + (" („Pop-ups im Spiel“ aus)" if bool(wie.get("im_spiel_aus", false)) else "")
	if bool(wie.get("verdeckt", false)):
		out += " (Chat offen, aber nicht zu sehen)"
	return kopf + out


## Liegt Uzai gerade sichtbar vorn? Nicht hinter einem Spiel (Guide zu), nicht minimiert, mit Fokus.
static func vorn(in_game: bool, guide_open: bool, minimized: bool, focused: bool) -> bool:
	return not (in_game and not guide_open) and not minimized and focused


## Ist der offene Chat wirklich zu sehen? Nur dann gilt eine Nachricht als gelesen und kommt ohne
## Pop-up. Vorher reichte „offen“: Ein im Guide über dem Spiel offen gelassener Chat schluckte jede
## weitere Nachricht des Freundes (Test 0.16.51: 18 von 25 Nachrichten ohne Pop-up). Ohne Ansicht
## (view_known = false: Tests, Rundgang) bleibt es bei „offen“.
static func chat_seen(open_id: String, fid: String, view_known: bool, view_shown: bool, uzai_front: bool) -> bool:
	if fid == "" or open_id != fid:
		return false
	return not view_known or (view_shown and uzai_front)


## Uzai vorn (siehe vorn()) – zur Laufzeit.
func uzai_vorn() -> bool:
	var root := get_tree().root
	return vorn(Launcher.in_game, Launcher.guide_open, root.mode == Window.MODE_MINIMIZED, root.has_focus())


## Chat-Ansicht (WeakRef aus chat_view) sichtbar und Uzai vorn?
func view_seen(view: WeakRef) -> bool:
	var v: Object = view.get_ref() if view != null else null
	return v is CanvasItem and (v as CanvasItem).is_visible_in_tree() and uzai_vorn()


## Aus NOTIFICATION_CREATE ein Pop-up machen: { key, title, sub, image, author } oder {} (eigene
## oder leere Benachrichtigung). Discord liefert title („name (#kanal, Server)“ oder bei
## Direktnachrichten den Namen), body (Text) und icon_url (Profilbild, oft .webp).
static func discord_popup(data: Dictionary, me_id: String) -> Dictionary:
	var msg: Dictionary = data.get("message", {}) if data.get("message") is Dictionary else {}
	var author: Dictionary = msg.get("author", {}) if msg.get("author") is Dictionary else {}
	var aid := str(author.get("id", "")) if author.get("id") != null else ""
	if me_id != "" and aid == me_id:
		return {}
	var title := str(data.get("title", "")) if data.get("title") != null else ""
	var body := str(data.get("body", "")) if data.get("body") != null else ""
	if body == "":
		body = str(msg.get("content", "")) if msg.get("content") != null else ""
	if title == "":
		var uname: Variant = author.get("global_name", author.get("username", ""))
		title = str(uname) if uname != null else ""
	if title == "" and body == "":
		return {}
	var mid := str(msg.get("id", "")) if msg.get("id") != null else ""
	var key := "d:" + mid if mid != "" else "d:%s:%s" % [str(data.get("channel_id", "")), (title + "|" + body).md5_text().left(12)]
	var img := str(data.get("icon_url", "")) if data.get("icon_url") != null else ""
	# Discord liefert WebP; als PNG laden wie die anderen Profilbilder (gleiche Adresse).
	if img.contains("cdn.discordapp.com") and img.contains(".webp"):
		img = img.replace(".webp", ".png")
	# Image in the message: Discord puts only the file name into body, so show "Bild" and a small thumbnail instead.
	# The image URL comes from the message itself (checked as in the chat: Discord only, https only).
	var vorschau := ""
	var med: Dictionary = DiscordChatS.medien_aus([msg]) if mid != "" else {}
	if med.has(mid):
		var it: Dictionary = (med[mid] as Array)[0]
		var inhalt := str(msg.get("content", "")) if msg.get("content") != null else ""
		if str(it.get("art", "")) == "bild":
			vorschau = proxy_bild(str(it.url))
		if inhalt.strip_edges() == "":
			body = TranslationServer.translate("Bild" if str(it.get("art", "")) == "bild" else "Video")
	return { "key": key, "title": title, "sub": body, "image": img, "author": aid, "channel": str(data.get("channel_id", "")), "vorschau": vorschau }


## Bild aus einer Discord-Meldung über Discords Bild-Proxy, neu kodiert als PNG: Die Meldung kann von jemandem
## kommen, der nicht befreundet ist (Erwähnung in einem gemeinsamen Server), und Uzai lädt das Bild ohne Klick. So
## kommen nie die Original-Bytes des Absenders in Uzais Bild-Dekoder, nur das, was Discord selbst daraus macht.
## Andere Adressen: "" (kein Bild).
static func proxy_bild(url: String) -> String:
	const CDN := "https://cdn.discordapp.com/attachments/"
	if not url.begins_with(CDN) or url.contains("#"):
		return ""
	var rest := url.substr(CDN.length())
	if rest.contains("\\") or rest.contains("@"):
		return ""
	return PROXY + rest + ("&" if rest.contains("?") else "?") + "format=png&width=480"


const PROXY := "https://media.discordapp.net/attachments/"


## Für pop(): Jedes Vorschaubild geht über den Proxy – auch vom Weg über das Social SDK (discord_dm), der die rohe
## Adresse durchreichte. Schon umgerechnete Adressen (proxy_bild) bleiben, alles andere wird umgerechnet oder fällt weg.
static func vorschau_sicher(url: String) -> String:
	if url == "":
		return ""
	if url.begins_with(PROXY) and url.contains("format=png") and not url.contains("#") and not url.contains("\\") and not url.contains("@"):
		return url
	return proxy_bild(url)


## Frisch und über dem Spiel gezeigt (nur dann soll die Guide-Taste es öffnen).
## need_over = false: auch außerhalb des Spiels (Pop-up in Uzai), dann öffnet die Guide-Taste es ebenso.
static func fresh(entry: Dictionary, now_ms: int, need_over := true) -> bool:
	return not entry.is_empty() and (bool(entry.get("over", false)) or not need_over) and now_ms - int(entry.get("at", 0)) <= OPEN_MS


# --- Eingänge ---------------------------------------------------------------------------------

func _on_steam(m: Dictionary) -> void:
	var fid0 := str(m.get("friend", ""))
	var why := steam_reason(m, fid0 if SteamChat.chat_in_view(fid0) else "", seen, bool(Config.get_value("notify.steam", true)))
	if int(m.get("kind", 1)) == 1:
		var ueber := why == "" and Toasts.use_overlay()
		SteamChat.log_line(steam_zeile(SteamChat.log_tag(fid0), why, { "abfrage": bool(m.get("from_poll", false)),
			"ruhig": NichtStoeren.aktiv(), "verdeckt": fid0 != "" and SteamChat.open_chat == fid0, "ueber_spiel": ueber,
			"vorn": ueber or uzai_vorn(), "im_spiel_aus": not bool(Config.get_value("notify.in_game", true)) }))
	if why != "":
		return
	_remember(steam_key(m))
	var fid := str(m.friend)
	var f := Social.steam_friend(fid)
	var friend := f.duplicate() if not f.is_empty() else { "id": fid, "name": "Steam-Freund", "avatar": "" }
	var name_ := str(friend.get("name", "Steam-Freund"))
	if _zimmer_einladung(str(m.text), not f.is_empty(), "steam:" + fid, name_, str(friend.get("avatar", ""))):
		return
	pop("steam", name_, str(m.text), "chat", str(friend.get("avatar", "")), friend)


func _on_discord(data: Dictionary) -> void:
	if not bool(Config.get_value("notify.discord", true)):
		return
	var p := discord_popup(data, Voice.me_id)
	if p.is_empty() or seen.has(p.key):
		return
	_remember(str(p.key))
	# Direktnachricht von einem Freund, mit dem Uzai chatten kann: dann führt das Pop-up in den Chat.
	var f: Dictionary = DiscordChat.friend(str(p.author)) if DiscordChat.state == "bereit" else {}
	if not f.is_empty():
		if _zimmer_einladung(str(p.sub), true, "discord:" + str(p.author), str(f.get("name", p.title)), str(f.get("avatar", p.image))):
			return
		pop("discord_dm", str(f.get("name", p.title)), str(p.sub), "chat", str(f.get("avatar", p.image)), f, str(p.get("vorschau", "")))
		return
	pop("discord", str(p.title), str(p.sub), "discord", str(p.image), { "channel": p.channel }, str(p.get("vorschau", "")))


## Anruf im Spiel: Pop-up über dem Spiel, die Guide-Taste öffnet die Anrufkarte.
func call_popup(info: Dictionary) -> void:
	var f := DiscordChat.friend(str(info.get("user_id", "")))
	var name_ := str(f.get("name", info.get("name", "Discord-Freund")))
	shown += 1
	last = { "kind": "discord_call", "target": info, "at": Time.get_ticks_msec(), "over": Toasts.use_overlay() }
	var opts := { "image": str(f.get("avatar", info.get("avatar", ""))), "sound": "notify",
		"ms": 20000, "tag": "call:" + str(info.get("channel_id", "")), "overlay": true, "open": open_last, "open_text": "Annehmen" }
	# In der Mitteilungsliste führt der Anruf später in den Chat mit dem Freund.
	if not f.is_empty():
		opts["go"] = open_entry.bind({ "kind": "discord_dm", "target": f })
		opts["go_text"] = "Chat öffnen"
	Toasts.show_toast("%s ruft an" % name_, "Guide-Taste drücken zum Annehmen", "phone", opts)


## Discord-Direktnachricht aus dem Social SDK (DiscordChat): Pop-up, das in den Chat führt.
## vorschau: Bild aus der Nachricht (Adresse von Discord), klein im Pop-up.
func discord_dm(f: Dictionary, text: String, msg_id: String, vorschau := "") -> void:
	if not bool(Config.get_value("notify.discord", true)):
		return
	var key := "d:" + msg_id if msg_id != "" else "d:%s:%s" % [str(f.get("id", "")), text.md5_text().left(12)]
	if seen.has(key):
		return
	_remember(key)
	pop("discord_dm", str(f.get("name", "Discord")), text, "chat", str(f.get("avatar", "")), f, vorschau)


func _remember(key: String) -> void:
	seen[key] = true
	if seen.size() > SEEN_MAX:
		for k in seen.keys().slice(0, 100):
			seen.erase(k)


## Pop-up zeigen und als „zuletzt“ merken (zum Öffnen). Bei „Nicht stören“ nur still in die
## Mitteilungen: dann öffnet auch die Guide-Taste nichts, und der Controller bleibt ruhig.
## Zimmer online: Steht in der Nachricht eines Freundes eine gültige Einladung, bietet Uzai „Zimmer betreten“
## an (statt der gewöhnlichen Chat-Mitteilung). Nur lesen und prüfen – betreten wird nie von selbst, und vor
## dem Anklopfen kommt der Hinweis zur IP-Adresse. Regeln und Flutschutz: src/room/einladung_chat.gd.
## true: als Einladung gemeldet.
func _zimmer_einladung(text: String, von_freund: bool, fid: String, name_: String, avatar: String) -> bool:
	var an := Online.BEREIT and bool(Config.get_value("room.online", false)) and bool(Config.get_value("room.online_hinweis", false))
	var e := einladungen.pruefen(text, von_freund, an, fid, int(Time.get_unix_time_from_system()))
	if str(e.art) != "anbieten":
		return false
	pop("zimmer", name_, "lädt dich in sein Zimmer ein", "friends", avatar, { "id": fid, "code": str(e.code), "name": name_ })
	return true


func pop(kind: String, title: String, sub: String, icon: String, image: String, target: Dictionary, vorschau := "") -> void:
	shown += 1
	vorschau = vorschau_sicher(vorschau)
	var ruhig := NichtStoeren.aktiv()
	if not ruhig:
		last = { "kind": kind, "target": target, "at": Time.get_ticks_msec(), "over": Toasts.use_overlay() }
	var opts := { "image": image, "vorschau": vorschau, "sound": "notify", "ms": SHOW_MS,
		"tag": "%s:%s" % [kind, str(target.get("id", target.get("channel", "")))],
		"overlay": true, "open": open_last, "stoert": true, "title_raw": true, "sub_raw": kind != "zimmer",
		"open_text": "Chat öffnen" if kind in ["steam", "discord_dm"] else ("Zimmer betreten" if kind == "zimmer" else "Mitteilungen") }
	if kind == "zimmer":
		opts["go"] = open_entry.bind({ "kind": kind, "target": target })
		opts["go_text"] = "Zimmer betreten"
	# In der Mitteilungsliste führt eine Nachricht später in den Chat (Discord-Server: kein Ziel in Uzai).
	if kind in ["steam", "discord_dm"]:
		opts["go"] = open_entry.bind({ "kind": kind, "target": target })
		opts["go_text"] = "Chat öffnen"
	Toasts.show_toast(title, sub, icon, opts)
	# Kurzer, leiser Impuls am Controller (Einstellung „Vibration bei Bestätigungen“, siehe pads.gd).
	if not ruhig:
		Pads.pulse("message")


## Der Chat mit diesem Freund ist aufgegangen: seine Pop-ups weichen, „Öffnen“ ist erledigt.
func chat_opened(friend_id: String) -> void:
	Toasts.dismiss("steam:" + friend_id)
	if str(last.get("kind", "")) == "steam" and str((last.get("target", {}) as Dictionary).get("id", "")) == friend_id:
		last = {}


# --- Melden, wenn online --------------------------------------------------------------------

## Gemerkte Steam-Freunde (Freunde → A → „Melden, wenn online“), geprüft: nur Ziffern.
static func watch_list() -> Array:
	var raw: Variant = Config.get_value("notify.watch", [])
	var out: Array = []
	if not (raw is Array):
		return out
	for x in raw:
		var id := str(x) if (x is String or x is StringName) else ""
		if watch_id_ok(id) and not out.has(id):
			out.append(id)
		if out.size() >= WATCH_MAX:
			break
	return out


static func watch_id_ok(id: String) -> bool:
	return id.length() >= 5 and id.length() <= 20 and id.is_valid_int() and not id.begins_with("-")


static func watching(id: String) -> bool:
	return watch_list().has(id)


static func watch_set(id: String, on: bool) -> void:
	if not watch_id_ok(id):
		return
	var l := watch_list()
	l.erase(id)
	if on:
		l.push_front(id)
	Config.set_value("notify.watch", l.slice(0, WATCH_MAX))


## Wer aus der Liste gerade online gekommen ist: vorher bekannt und offline, jetzt nicht. Neue
## Einträge (erste Liste nach dem Start) melden nichts. Rückgabe: die Freunde.
static func came_online(prev: Dictionary, friends: Array, watch: Array) -> Array:
	var out: Array = []
	for f in friends:
		if not (f is Dictionary):
			continue
		var id := str(f.get("id", ""))
		if watch.has(id) and prev.has(id) and not bool(prev[id]) and str(f.get("state", "offline")) != "offline":
			out.append(f)
	return out


func _on_social(what: Variant = null) -> void:
	if what != null and str(what) != "steam":
		return
	var watch := watch_list()
	var now := {}
	for f in Social.steam_friends:
		if f is Dictionary and watch.has(str(f.get("id", ""))):
			now[str(f.id)] = str(f.get("state", "offline")) != "offline"
	var came := came_online(_online, Social.steam_friends, watch)
	_online = now
	for f in came:
		friend_online(f)


## „Mira ist online“ (bzw. „spielt …“): leise, über dem Spiel; A in der Liste und View öffnen den Chat.
func friend_online(f: Dictionary) -> void:
	var game := Library.friend_game_title(str(f.get("game", "")), str(f.get("game_id", "")))
	var target := f.duplicate()
	Toasts.show_toast(str(f.get("name", "Steam-Freund")),
		(TranslationServer.translate("spielt jetzt %s") % game) if game != "" else TranslationServer.translate("ist jetzt online"),
		"friends", { "image": str(f.get("avatar", "")), "ms": SHOW_MS, "overlay": true, "stoert": true, "tag": "online:" + str(f.get("id", "")),
			"title_raw": true, "sub_raw": true,
			"open": open_entry.bind({ "kind": "steam", "target": target }), "open_text": "Chat öffnen",
			"go": open_entry.bind({ "kind": "steam", "target": target }), "go_text": "Chat öffnen" })


# --- Öffnen ----------------------------------------------------------------------------------

## Das letzte Pop-up öffnen: Steam → der Chat mit dem Freund, Discord → die Mitteilungen
## (Uzai holt die Discord-App nie nach vorn). true, wenn etwas geöffnet wurde.
func open_last() -> bool:
	if last.is_empty():
		return false
	var m: Node = get_tree().current_scene
	if m == null or not m.has_method("open_chat"):
		return false
	var entry := last
	last = {}
	return open_entry(entry)


## Ein Pop-up öffnen (frisch oder aus der Mitteilungsliste): Steam/Discord-Nachricht → Chat,
## Anruf → Anrufkarte, sonst die Mitteilungen.
func open_entry(entry: Dictionary) -> bool:
	var m: Node = get_tree().current_scene
	if m == null or not m.has_method("open_chat"):
		return false
	if str(entry.kind) == "steam":
		m.call("open_chat", entry.target)
	elif str(entry.kind) == "discord_dm":
		m.call("open_discord_chat", entry.target)
	elif str(entry.kind) == "discord_call":
		m.call("open_incoming_call", entry.target)
	elif str(entry.kind) == "zimmer" and m.has_method("zimmer_einladung_oeffnen"):
		m.call("zimmer_einladung_oeffnen", entry.target)
	else:
		m.call("open_notifications")
	return true


## Für die Guide-Taste im Spiel: das letzte Pop-up, wenn es noch frisch ist (und dann vergessen).
func take_pending(in_game := true) -> Dictionary:
	if not fresh(last, Time.get_ticks_msec(), in_game):
		last = {}
		return {}
	var entry := last
	last = {}
	return entry
