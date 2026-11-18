extends Node
## Links, images and videos in chat: Steam's BB code keeps the URLs (steam_chat.gd clean), the bubble shows images
## from known services (chat_link.gd bild_url), Discord attachments become a card (discord_chat.gd anhang), and
## declining a call does not ring again (voice.gd). Pure logic, no network, no real chats.
## Run: godot --headless --path . res://tests/logic_chat_medien.tscn → „Ergebnis: alles ok“

const SC := preload("res://src/core/steam_chat.gd")
const DC := preload("res://src/core/discord_chat.gd")
const CL := preload("res://src/ui/layers/chat_link.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Steam: BB-Code")
	var bild := "https://images.steamusercontent.com/ugc/123456/ABCDEF/"
	check(SC.clean("[img src=\"%s\" width=\"640\" height=\"480\"][/img]" % bild) == bild, "Bild: die Adresse bleibt")
	check(SC.clean("[img]%s[/img]" % bild) == bild, "Bild in kurzer Form: die Adresse bleibt")
	check(SC.clean("schau [url=https://example.com/a]hier[/url]!") == "schau hier https://example.com/a!", "Link mit Wort: Wort und Adresse")
	check(SC.clean("[url=https://example.com/a]https://example.com/a[/url]") == "https://example.com/a", "Link ohne eigenes Wort: nur die Adresse")
	check(SC.clean("hi [emoticon]steamhappy[/emoticon]") == "hi :steamhappy:", "Emoticons wie bisher")
	check(SC.clean("[b]fett[/b] text") == "fett text", "andere Tags fallen weg")
	print("Bilder und Videos")
	check(CL.bild_url(bild) and str(CL.link_info(bild).kind) == "bild", "Steam-Chat-Bild (ohne Endung): Bild")
	check(CL.bild_url("https://cdn.discordapp.com/attachments/1/2/foto.png?ex=1") and CL.bild_url("https://i.imgur.com/abc.jpg"),
			"Discord- und Imgur-Bilder: Bild")
	check(not CL.bild_url("http://i.imgur.com/abc.jpg") and not CL.bild_url("https://example.com/a.png")
			and not CL.bild_url("https://192.168.178.1/a.png") and not CL.bild_url("https://cdn.discordapp.com/a/b/datei.exe"),
			"nur https, nur bekannte Dienste, nur Bilder – nie Heimnetz oder beliebige Seiten")
	# Rückstrich vor „@“: Der alte Leser sah i.imgur.com, der Abruf (Sicher.url_parts) verband zu evil.example.
	var trick := "https://evil.example\\@i.imgur.com/a.png"
	check(not CL.bild_url(trick) and CL.host_of(trick) == "evil.example" and str(CL.link_info(trick).host) == "evil.example",
			"Rückstrich-Trick: kein Bild, der QR-Dialog nennt das echte Ziel")
	check(not CL.bild_url("https://evil.example@i.imgur.com/a.png") and not DC._medien_url_ok("https://evil.example\\@cdn.discordapp.com/a.png"),
			"Anmeldedaten vor dem Host: kein Bild (Chat und Discord-Anhang)")
	check(str(CL.link_info("https://example.com/clip.mp4").kind) == "video", "Video-Datei: Karte „Video“")
	check(str(CL.link_info("https://youtu.be/dQw4w9WgXcQ").kind) == "youtube", "YouTube wie bisher")
	print("Discord: Anhang")
	var m := DC.to_message({ "id": "1", "author": "9", "text": "", "sent": 1000, "anhang": { "art": 1, "titel": "urlaub.jpg", "anzahl": 2 } }, "5")
	check(m.has("anhang") and str(m.anhang.art) == "bild" and int(m.anhang.anzahl) == 2, "Anhang mit Bildendung: Bild, Anzahl bleibt")
	check(DC.anhang({ "art": 1, "titel": "clip.mp4", "anzahl": 1 }).art == "video" and DC.anhang({ "art": 6, "titel": "", "anzahl": 1 }).art == "sticker",
			"Video und Sticker erkannt")
	check(DC.anhang({ "art": 0 }).is_empty() and DC.anhang("kaputt").is_empty() and not DC.to_message({ "text": "hi" }, "5").has("anhang"),
			"ohne Anhang oder kaputt: nichts")
	check(int(DC.anhang({ "art": 1, "titel": "x.png", "anzahl": 5000 }).anzahl) == 99, "Anzahl begrenzt")
	print("Discord: Bilder über die Discord-App (messages.read)")
	var nachrichten := [
		{ "id": "111",
			"attachments": [{ "url": "https://cdn.discordapp.com/attachments/1/2/urlaub.jpg?ex=1", "filename": "urlaub.jpg", "content_type": "image/jpeg" }] },
		{ "id": "112",
			"attachments": [{ "url": "https://cdn.discordapp.com/attachments/1/2/witz.gif", "proxy_url": "https://media.discordapp.net/attachments/1/2/witz.gif",
			"filename": "witz.gif", "content_type": "image/gif" }] },
		{ "id": "113", "embeds": [{ "type": "gifv", "thumbnail": { "proxy_url": "https://media.discordapp.net/external/abc/media.tenor.com/x.png" } }] },
		{ "id": "114", "attachments": [{ "url": "https://192.168.178.1/boese.jpg", "filename": "boese.jpg", "content_type": "image/jpeg" },
			{ "url": "http://cdn.discordapp.com/a.png", "filename": "a.png" }] },
		{ "id": "115", "attachments": [{ "url": "https://cdn.discordapp.com/attachments/1/2/clip.mp4", "filename": "clip.mp4", "content_type": "video/mp4" }] },
		{ "id": "kaputt" }, "nicht mal ein Eintrag",
	]
	var med := DC.medien_aus(nachrichten)
	check(med.has("111") and str(med["111"][0].art) == "bild" and str(med["111"][0].url).begins_with("https://cdn.discordapp.com/"), "Bild-Anhang mit Adresse")
	check(med.has("112") and str(med["112"][0].url).ends_with("format=png") and str(med["112"][0].url).begins_with("https://media.discordapp.net/"),
			"GIF: Discords Vorschau als PNG (Godot zeigt keine GIFs)")
	check(med.has("113") and str(med["113"][0].art) == "bild", "GIF-Einbettung (Tenor): Discords Vorschaubild")
	check(not med.has("114"), "fremde Adressen und http: nie geladen")
	check(med.has("115") and str(med["115"][0].art) == "video", "Video-Anhang")
	check(med.size() == 4, "Kaputtes übersprungen")
	var war_demo: bool = Voice.demo
	Voice.demo = true                       # nichts ins echte Protokoll schreiben
	var bekommen := []
	var cb := func(cid: String, liste: Array) -> void: bekommen.append([cid, liste.size()])
	Voice.channel_messages.connect(cb)
	Voice.get("_msg_wait")["555"] = true
	Voice.handle({ "cmd": "GET_CHANNEL", "data": { "id": "555", "messages": nachrichten } })
	Voice.handle({ "cmd": "GET_CHANNEL", "data": { "id": "556", "messages": nachrichten } })
	Voice.channel_messages.disconnect(cb)
	Voice.demo = war_demo
	check(bekommen.size() == 1 and str(bekommen[0][0]) == "555" and int(bekommen[0][1]) == nachrichten.size(),
			"Antwort der Discord-App geht nur für erfragte Kanäle an den Chat")
	print("Freigabe auf angemeldeter Verbindung")
	var alt := { "demo": Voice.demo, "state": Voice.state, "me_id": Voice.me_id, "tester_fehlt": Voice.tester_fehlt,
		"extra_rejected": Voice.extra_rejected, "transport": Voice.transport }
	var gesendet := []
	Voice.demo = true
	Voice.transport = func(t: String) -> void: gesendet.append(t)
	Voice.state = "anmelden"
	Voice.me_id = "123"
	Voice.tester_fehlt = false
	Voice.extra_rejected = false
	Voice.handle({ "cmd": "AUTHORIZE", "evt": "ERROR", "data": { "code": 4002, "message": "Already authenticated" } })
	check(Voice.state == "bereit" and not Voice.tester_fehlt and not Voice.extra_rejected and gesendet.is_empty(),
			"„Already authenticated“: keine Rückstufung, kein „nicht freigeschaltet“, Verbindung bleibt")
	for k in alt.keys():
		Voice.set(k, alt[k])
	print("Pop-up aus Discords Benachrichtigung")
	var NT: GDScript = load("res://src/core/notify.gd")
	var note := { "channel_id": "9", "title": "Robin", "body": "image.png", "icon_url": "",
		"message": { "id": "4242", "content": "", "author": { "id": "77" },
			"attachments": [{ "url": "https://cdn.discordapp.com/attachments/9/4242/image.png", "filename": "image.png", "content_type": "image/png" }] } }
	var pp: Dictionary = NT.discord_popup(note, "5")
	check(str(pp.sub) == TranslationServer.translate("Bild")
			and str(pp.vorschau) == "https://media.discordapp.net/attachments/9/4242/image.png?format=png&width=480",
			"Bild statt Dateiname, dazu klein die Vorschau – über Discords Proxy neu kodiert, nie die Original-Bytes")
	note.message.content = "schau mal"
	note.body = "schau mal"
	pp = NT.discord_popup(note, "5")
	check(str(pp.sub) == "schau mal" and str(pp.vorschau) != "", "mit Text: der Text bleibt, das Bild kommt dazu")
	note.message.attachments = [{ "url": "https://example.com/x.png", "filename": "x.png", "content_type": "image/png" }]
	check(str(NT.discord_popup(note, "5").vorschau) == "", "fremde Adresse: keine Vorschau")
	# Der Weg über das Social SDK (discord_dm) reichte die rohe CDN-Adresse durch: pop() rechnet jetzt jede um.
	var roh := "https://cdn.discordapp.com/attachments/9/4242/image.png"
	var prox := "https://media.discordapp.net/attachments/9/4242/image.png?format=png&width=480"
	check(NT.vorschau_sicher(roh) == prox and NT.vorschau_sicher(prox) == prox and NT.vorschau_sicher("https://example.com/x.png") == ""
			and NT.vorschau_sicher("https://cdn.discordapp.com/attachments/a\\@evil.example/x.png") == "",
			"Vorschau im Pop-up: immer über den Proxy, schon umgerechnet bleibt, fremd fällt weg")
	check(FileAccess.get_file_as_string("res://src/core/notify.gd").contains("vorschau = vorschau_sicher(vorschau)"), "pop() rechnet zentral um")
	print("Bilder nachgeholt: Chat zeichnet neu")
	var CV: GDScript = load("res://src/ui/layers/chat_view.gd")
	var verlauf := [{ "at": 1, "text": "", "me": false, "id": "1" }, { "at": 2, "text": "hi", "me": true, "id": "2" }]
	var vorher_sig: String = CV.verlauf_sig(verlauf)
	verlauf[0]["medien"] = [{ "url": "https://cdn.discordapp.com/a.png", "art": "bild" }]
	check(CV.verlauf_sig(verlauf) != vorher_sig, "Bilder einer alten Nachricht nachgeholt: der Verlauf gilt als geändert")
	print("Bilder öffnen, Schreibfeld")
	check(str(CL.link_info(bild).action) == "Ansehen", "Bild: A heißt „Ansehen“ (groß in Uzai), nicht „Aufs Handy“")
	await _schreibfeld()
	print("Anruf ablehnen")
	Voice.decline_call("777")
	check(Voice.get("_abgelehnt").has("777") and not Voice.ringing.has("777"), "abgelehnt: klingelt für diesen Anruf nicht mehr")
	Voice.get("_abgelehnt").erase("777")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Wie die Chat-Ansicht für das Schreibfeld (chat_view.gd _Composer): schickt, schreibt, kennt das Gespräch.
class Ansicht extends Node:
	var geschickt: Array = []
	var tastatur := 0

	func _send(t: String) -> void:
		geschickt.append(t)

	func write() -> void:
		tastatur += 1

	func _be() -> Object:
		return DiscordChat

	func _fid() -> String:
		return ""

	func to_last_bubble() -> bool:
		return false


func _schreibfeld() -> void:
	var cv: GDScript = load("res://src/ui/layers/chat_view.gd")
	var ansicht := Ansicht.new()
	add_child(ansicht)
	var ui := Control.new()
	ui.size = Vector2(800, 200)
	add_child(ui)
	var c: Control = cv.get("_Composer").new()
	c.set("view", ansicht)
	c.size = Vector2(500, 60)
	ui.add_child(c)
	await get_tree().process_frame
	var vorher := str(Nav.device)
	Nav.device = "mouse"
	Nav.activate(c)
	await get_tree().process_frame
	var feld: LineEdit = c.get("_feld")
	check(feld != null and feld.visible and feld.has_focus() and ansicht.tastatur == 0, "Maus: direkt im Schreibfeld tippen, kein Fenster")
	feld.text = "Hallo"
	Nav.activate(feld)
	feld.text_submitted.emit("Hallo")          # Enter erreicht beide Wege – geschickt wird einmal
	check(ansicht.geschickt == ["Hallo"] and feld.text == "", "Enter schickt genau einmal, das Feld bleibt frei fürs Nächste")
	feld.call("nav_b")
	check(not feld.visible and c.has_focus(), "Esc: aufhören zu tippen, der Chat bleibt")
	Nav.device = "pad"
	Nav.activate(c)
	check(ansicht.tastatur == 1, "Controller: A öffnet die Bildschirmtastatur")
	Nav.device = vorher
	ui.queue_free()
	ansicht.queue_free()
	await get_tree().process_frame
