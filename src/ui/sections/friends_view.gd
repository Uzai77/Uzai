extends "res://src/ui/sections/section.gd"
## Freunde: die Liste der Seitenleiste „Freunde“ (Select im Hauptmenü, layers/freunde_leiste.gd) –
## ein Reiter für Steam und je einer pro Discord-Server. Wer spielt was (grün), wer online ist, wer
## zuletzt da war. A auf einer Person öffnet die Auswahl (Chat, Profil, Beitreten), X den Chat, Y das
## Profil; Profil, Chat und Sprachkanal öffnen sich in Uzai. (Die große Karte rechts neben der Liste
## gab es nur, solange Freunde ein eigener Bereich oben in der Leiste war.)
## Kommt jemand online oder startet ein Spiel, frischt nur die Liste auf (ohne Flackern, der
## Fokus bleibt auf derselben Person).
## Freundschaftsanfragen an dich stehen oben in der Liste des Dienstes (Steam bzw. Discord): A
## antwortet (request_flow.gd), Y zeigt vorher das Profil. Gesendete Anfragen haben keine eigene
## Liste – sie stehen nur als Zustand an der Person („Anfrage gesendet“).

const People := preload("res://src/ui/components/guide_people.gd")
const FriendRow := preload("res://src/ui/components/friend_row.gd")
const FriendActions := preload("res://src/ui/layers/friend_actions.gd")
const FriendProfile := preload("res://src/ui/layers/friend_profile.gd")
const ChatView := preload("res://src/ui/layers/chat_view.gd")
const FR := preload("res://src/core/friend_requests.gd")
const RequestFlow := preload("res://src/ui/request_flow.gd")
const DcActivity := preload("res://src/core/discord_activity.gd")

var _stale := false
var _vsig := ""
var _left: VBoxContainer          ## die Liste (für das Auffrischen ohne Neuaufbau)
var host_layer: Control           ## die Seitenleiste, in der der Bereich liegt (zählt nicht als Ebene darüber)


## Stand von Discord für den Reiter: auch wer online kommt, spielt oder schreibt (früher nur die
## Anzahl der Freunde – kam jemand online, blieb die Liste stehen).
func _voice_sig() -> String:
	var dms := ",".join(
			PackedStringArray(DiscordChat.friends.map(func(f): return "%s:%s:%s" % [str(f.get("id", "")), str(f.get("state", "")), str(f.get("game", ""))])))
	return "%s|%d|%s|%s|%s|%d|%s|%s|%s" % [DiscordChat.state, DiscordChat.friends.size(), dms, JSON.stringify(DiscordChat.unread), Voice.state,
			Voice.guilds.size(), Voice.browse_guild, ",".join(PackedStringArray(Voice.browse.map(func(o): return "%s:%d" % [o.id, o.members.size()]))),
			str(Voice.channel.get("id", ""))]


func _init() -> void:
	super()
	id = "friends"
	title = "Freunde"
	icon_name = "friends"
	Social.updated.connect(_on_social)
	# Discord über die Discord-App (Server, Sprachkanäle): bei Änderungen den Reiter auffrischen.
	DiscordChat.changed.connect(func() -> void:
		if sub == "discord":
			var sig := _voice_sig()
			if sig != _vsig:
				_vsig = sig
				_on_social("discord")
	)
	Voice.changed.connect(func() -> void:
		if sub == "discord":
			var sig := _voice_sig()
			if sig != _vsig:
				_vsig = sig
				_on_social("discord")
	)


## Neue Daten: sofort auffrischen – außer eine Ebene liegt darüber (Chat, Guide), dann danach.
## (Die Zahlen bei den Reitern zieht die Seitenleiste selbst nach.)
func _on_social(_w: String) -> void:
	if not visible:
		return
	var top := Nav.top_layer()
	if top != null and top != host_layer:
		_stale = true
		if top.has_signal("closed") and not top.is_connected("closed", _after_layer):
			top.connect("closed", _after_layer, CONNECT_ONE_SHOT)
		return
	_rebuild_keep()


func _after_layer() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _stale and visible and (Nav.top_layer() == null or Nav.top_layer() == host_layer):
		_rebuild_keep()


func _rebuild_keep() -> void:
	_stale = false
	if _refresh_list():
		return
	var f := Nav.focused()
	var inside := f != null and is_ancestor_of(f)
	var key := str(f.get_meta("uz_key", "")) if inside else ""
	build()
	if not inside:
		return
	for c in Nav.focusables(self):
		if key != "" and str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return
	# Die Person ist weg (offline gegangen o. ä.): auf den Anfang der Liste, Hinweise neu.
	var d := Nav.default_in(self)
	if d:
		Nav.focus(d, true)
	else:
		Nav.focus_moved.emit(null)


func subtabs() -> Array:
	var out: Array = []
	if Social.has_steam():
		out.append({ "id": "steam", "label": "Steam", "count": Social.steam_friends.filter(func(f): return f.state != "offline").size() })
	# Discord über die Discord-App: deine Server und wer in den Sprachkanälen ist. Die Zahl sind
	# deine Discord-Freunde online (früher die Leute in den Sprachkanälen des gewählten Servers –
	# eine „3“, die niemand zuordnen konnte). Ohne Freundesliste keine Zahl.
	if Voice.configured() or Voice.demo:
		var tab := { "id": "discord", "label": "Discord" }
		if DiscordChat.logged_in() and not DiscordChat.friends.is_empty():
			tab["count"] = DiscordChat.friends.filter(func(f): return str(f.state) != "offline").size()
		out.append(tab)
	for sid in Social.servers():
		var s: Dictionary = Social.discord.get(sid, {})
		out.append({ "id": "discord:" + sid, "label": str(s.get("name", "Discord")), "count": int(s.get("online", 0)) })
	if out.is_empty():
		out.append({ "id": "einrichten", "label": "Einrichten" })
	return out


func on_enter() -> void:
	# Frisch beim Hereinkommen (früher nur, solange die Liste leer war – wer inzwischen online kam,
	# stand bis zur nächsten Abfrage noch als offline da).
	if Social.has_steam() and Social.steam_friends.is_empty():
		Social.refresh()
	elif Social.has_steam() or not Social.servers().is_empty():
		Social.refresh_stale(20.0)
	SteamChat.refresh_unread()


## Ist ein Konto für Freunde da (Steam, Discord verbunden oder ein Server)?
func _eingerichtet() -> bool:
	return Social.has_steam() or Voice.ready_() or not Social.servers().is_empty() or DiscordChat.logged_in()


## Eben eingerichtet (leer_buehne.gd): zum ersten Dienst, der jetzt da ist, und die Reiter der
## Seitenleiste nachziehen.
func _nach_einrichten() -> void:
	var subs: Array = subtabs()
	if not subs.is_empty() and not (subs as Array).any(func(t: Dictionary) -> bool: return str(t.id) == sub and sub != "einrichten"):
		sub = str(subs[0].id)
	build()
	if is_instance_valid(host_layer) and host_layer.has_method("_fill_tabs"):
		host_layer.call("_fill_tabs")


func build() -> void:
	U.clear(self)
	_left = null
	if sub == "einrichten" or sub == "":
		add_child(leer_buehne({ "art": "personen", "symbol": "friends", "schmal": true, "rand": 14,
			"titel": "Freunde von Steam und Discord.", "knopf": "Steam verbinden", "tun": LeerBuehne.weg(main, "steam"),
			"neben": "Discord verbinden", "neben_tun": LeerBuehne.weg(main, "discord"),
			"fertig": _eingerichtet, "neu": _nach_einrichten }))
		return
	# Die Liste über die ganze Breite der Seitenleiste.
	var liste := U.vbox(2)
	var sc := scroll_v(liste)
	sc.set_meta("uz_pad_v", 120.0)
	U.full_rect(sc)
	add_child(sc)
	# Die Leiste lässt die Liste unten weich auslaufen, solange darunter noch Freunde stehen.
	if is_instance_valid(host_layer) and host_layer.has_method("kante_unten_fuer"):
		host_layer.call("kante_unten_fuer", sc)
	liste.set_meta("uz_group", "friends:" + sub)
	liste.set_meta("uz_mem", true)
	_left = liste
	_fill(liste)


func _fill(left: VBoxContainer) -> void:
	if sub == "steam":
		_steam(left)
	elif sub == "discord":
		_vsig = _voice_sig()
		_discord_app(left)
	elif sub.begins_with("discord:"):
		_discord(left, sub.substr(8))


## Nur die Liste neu füllen: der Bildlauf bleibt stehen, der Fokus auf derselben Person. false: geht
## nicht (anderer Unterbereich, noch nichts aufgebaut) – dann baut _rebuild_keep ganz neu.
func _refresh_list() -> bool:
	if not is_instance_valid(_left) or not _left.is_inside_tree():
		return false
	if str(_left.get_meta("uz_group", "")) != "friends:" + sub or not (sub == "steam" or sub == "discord" or sub.begins_with("discord:")):
		return false
	var f := Nav.focused()
	var inside := f != null and is_ancestor_of(f)
	var key := str(f.get_meta("uz_key", "")) if inside else ""
	var keep_y := _left_scroll()
	U.clear(_left)
	_fill(_left)
	if keep_y >= 0.0:
		_set_left_scroll(keep_y)
	if not inside:
		return true
	var to: Control = _rows(_left).get(key) if key != "" else null
	if to == null:
		# Die Person ist weg (offline gegangen o. ä.): auf den Anfang der Liste.
		to = _default_row(_left)
	if to != null:
		Nav.focus(to, true)
	else:
		Nav.focus_moved.emit(null)
	return true


## Zeilen der Liste nach Schlüssel.
static func _rows(left: Control) -> Dictionary:
	var out := {}
	for c in left.get_children():
		if c is Control and c.has_meta("uz_key"):
			out[str(c.get_meta("uz_key"))] = c
	return out


static func _default_row(left: Control) -> Control:
	for c in left.get_children():
		if c is Control and bool(c.get_meta("uz_default", false)):
			return c
	for c in left.get_children():
		if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE:
			return c
	return null


func _left_scroll() -> float:
	var sc := _left.get_parent() as ScrollContainer if is_instance_valid(_left) else null
	return float(sc.scroll_vertical) if sc else -1.0


func _set_left_scroll(y: float) -> void:
	var sc := _left.get_parent() as ScrollContainer if is_instance_valid(_left) else null
	if sc:
		sc.scroll_vertical = int(y)


func _group(parent: VBoxContainer, text: String, count := -1) -> void:
	var m := U.margin(14, 20 if parent.get_child_count() > 0 else 6, 0, 8)
	var h := U.hbox(10)
	h.add_child(U.label(text, "s", "muted", "bold"))
	if count >= 0:
		h.add_child(U.label(str(count), "s", "faint", "medium"))
	m.add_child(h)
	parent.add_child(m)


# --- Steam ---------------------------------------------------------------------------------

func _steam(left: VBoxContainer) -> void:
	if Social.steam_error != "":
		left.add_child(_problem(Social.steam_error, Social.steam_friends.is_empty()))
		if Social.steam_friends.is_empty():
			_hinweis(left, "Warten auf Steam …")
	var groups := [["game", "Im Spiel"], ["online", "Online"], ["busy", "Beschäftigt"], ["away", "Abwesend"], ["offline", "Offline"]]
	var first := not _requests(left, "steam")
	for gr in groups:
		var list := Social.steam_friends.filter(func(f): return f.state == gr[0])
		if list.is_empty():
			continue
		if gr[0] == "offline":
			list.sort_custom(func(a, b): return int(a.get("last", 0)) > int(b.get("last", 0)))
		_group(left, str(gr[1]), list.size())
		for f in list.slice(0, 60 if gr[0] == "offline" else 200):
			var fd: Dictionary = f
			var it = FriendRow.new()
			var game := Library.friend_game_title(str(fd.get("game", "")), str(fd.get("game_id", "")))
			var offline := str(fd.state) == "offline"
			it.setup(str(fd.name), game if game != "" else ChatView.status_line(fd), str(fd.avatar), str(fd.state))
			it.line_color = "ok" if game != "" else ("faint" if offline else "muted")
			it.unread = int(SteamChat.unread.get(str(fd.id), 0))
			it.joinable = Social.join_url(fd) != ""
			it.faded = offline
			it.set_meta("uz_key", "fr:" + str(fd.id))
			it.set_meta("uz_flug", "fr:" + str(fd.id))
			it.set_meta("uz_hint_a", "Optionen")
			it.set_meta("uz_hint_x", "Chat")
			it.set_meta("uz_on_x", func() -> void: main.open_chat(fd))
			it.set_meta("uz_hint_y", "Profil")
			it.set_meta("uz_on_y", func() -> void: _open_profile(fd))
			it.activated.connect(func() -> void: main.open_friend(fd, "steam"))
			if first:
				it.set_meta("uz_default", true)
				first = false
			left.add_child(it)
	if Social.steam_friends.is_empty() and Social.steam_error == "" and FR.incoming(Social.requests, "steam").is_empty():
		# Laden: die Liste in ihrer fertigen Form, ohne Text.
		for i in 6:
			left.add_child(Skeleton.person())


func _open_profile(f: Dictionary) -> void:
	var l = FriendProfile.new()
	l.friend = f
	main.open_layer(l)


# --- Freundschaftsanfragen ---------------------------------------------------------------------

## Anfragen an dich oben in der Liste (A antwortet, Y Profil). Gesendete stehen nicht als eigene
## Liste da (Wunsch), nur als Zustand an der Person. true, wenn die erste Anfrage die Startauswahl
## ist (sie wartet auf dich).
func _requests(left: VBoxContainer, source: String) -> bool:
	var list := FR.incoming(Social.requests, source)
	if list.is_empty():
		return false
	_group(left, "Freundschaftsanfragen", list.size())
	var first := true
	for r in list:
		var rd: Dictionary = r
		var incoming := str(rd.dir) == FR.IN
		var it = FriendRow.new()
		it.setup(str(rd.name), FR.line(rd), str(rd.avatar), "")
		it.line_color = "accent" if incoming else "faint"
		it.faded = not incoming
		it.set_meta("uz_key", "rq:" + str(rd.key))
		it.set_meta("uz_hint_a", TranslationServer.translate("Antworten", "anfrage") if incoming else "Profil")
		it.set_meta("uz_hint_y", "Profil")
		it.set_meta("uz_on_y", func() -> void: RequestFlow.open_profile(main, rd))
		it.activated.connect(func() -> void: RequestFlow.ask(main, rd))
		if first and incoming:
			it.set_meta("uz_default", true)
			first = false
		left.add_child(it)
	return not first


## Discord-Freunde mit Chat (wenn Discord-Nachrichten verbunden sind). true = Liste gezeigt.
func _discord_friends(left: VBoxContainer, after_requests := false) -> bool:
	if not DiscordChat.logged_in() or DiscordChat.friends.is_empty():
		return false
	var online := DiscordChat.friends.filter(func(f): return str(f.state) != "offline" or int(DiscordChat.unread.get(str(f.id), 0)) > 0)
	_group(left, "Discord-Freunde", online.size())
	var first := not after_requests
	for f in online.slice(0, 80):
		var fd: Dictionary = f
		var it = FriendRow.new()
		# Wie bei Steam: A öffnet die Auswahl (friend_actions.gd), X den Chat, Y das Profil.
		var act := DcActivity.of(fd, DcActivity.widget_game(fd, Social.discord))
		var line := str(act.title) if str(act.kind) == "game" else DcActivity.headline(act)
		it.setup(str(fd.name), line if line != "" else str(People.STATE_TEXT.get(str(fd.state), "Online")), str(fd.avatar), str(fd.state))
		it.line_color = "ok" if str(act.kind) != "" else "muted"
		it.unread = int(DiscordChat.unread.get(str(fd.id), 0))
		it.set_meta("uz_key", "dm:" + str(fd.id))
		it.set_meta("uz_hint_a", "Optionen")
		it.set_meta("uz_hint_x", "Chat")
		it.set_meta("uz_on_x", func() -> void: main.open_discord_chat(fd))
		it.set_meta("uz_hint_y", "Profil")
		it.set_meta("uz_on_y", func() -> void: _open_discord_profile(fd))
		it.activated.connect(func() -> void: main.open_friend(fd, "discord"))
		if first:
			it.set_meta("uz_default", true)
			first = false
		left.add_child(it)
	return true


func _open_discord_profile(f: Dictionary) -> void:
	var l = load("res://src/ui/layers/discord_profile.gd").new()
	var f2 := f.duplicate()
	f2["dm"] = f
	l.friend = f2
	main.open_layer(l)


## Leiser Hinweis unter der Liste (Server wählen, niemand online …).
func _hinweis(left: VBoxContainer, text: String) -> void:
	var m := U.margin(14, 12, 14, 8)
	m.add_child(U.label(text, "m", "muted", "regular", true))
	left.add_child(m)


## Steam antwortet nicht o. ä.: ruhige Zeile mit „Nochmal versuchen“.
func _problem(text: String, first := false) -> Control:
	var m := U.margin(14, 8, 14, 14)
	var v := U.vbox(14)
	m.add_child(v)
	var h := U.hbox(12)
	var ic := U.icon("warning", 24, "warn")
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var l := U.label(text, "m", "muted", "regular", true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	v.add_child(h)
	var b := U.button("Nochmal versuchen", "refresh")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_key", "fr:retry")
	if first:
		b.set_meta("uz_default", true)
	b.pressed.connect(func() -> void: Social.refresh())
	v.add_child(b)
	return m


# --- Discord -------------------------------------------------------------------------------

## Discord über die Discord-App (offizielle RPC): Server wählen, Sprachkanäle mit den Leuten,
## beitreten. Nicht verbunden: sagen, woran es hängt, und „Verbinden“ anbieten.
func _discord_app(left: VBoxContainer) -> void:
	# Anfragen und deine Discord-Freunde (Social SDK): Nachricht schreiben direkt in Uzai.
	var req_first := _requests(left, "discord")
	var dm_first := _discord_friends(left, req_first) or req_first
	if not Voice.ready_() and not dm_first:
		# Noch nicht verbunden: die Bühne mit angedeuteten Personen; A verbindet gleich (Freigabe in
		# der Discord-App), ohne Steam daneben auch Steam. Danach füllt sich die Liste von selbst.
		var why := Voice.error
		if why == "" and not Voice.configured():
			why = Voice.missing_text() if Voice.client_id() == "" else "Sprachkanal aus. Einstellungen → Konten → Discord."
		var o := { "art": "personen", "symbol": "discord", "schmal": true, "rand": 14,
			"titel": "Discord ist nicht verbunden.", "zeile": why, "knopf": "Verbinden", "tun": LeerBuehne.weg(main, "discord"),
			"host": self, "fertig": func() -> bool: return Voice.ready_() or DiscordChat.logged_in() }
		if not Social.has_steam():
			o["neben"] = "Steam verbinden"
			o["neben_tun"] = LeerBuehne.weg(main, "steam")
		var lb: Control = LeerBuehne.new().setup(o)
		lb.custom_minimum_size.y = 0
		left.add_child(U.spacer(0, 10, false))
		left.add_child(lb)
		return
	if not Voice.ready_():
		# Nur Nachrichten verbunden (ohne Sprachkanal-Anbindung): die Freunde reichen.
		return
	if Voice.guilds.is_empty():
		if Voice.guilds_error != "":
			_group(left, "Discord")
			left.add_child(U.margin(14, 8, 14, 14))
			(left.get_child(left.get_child_count() - 1) as Control).add_child(
					U.label(Voice.guilds_error + " Einzelheiten stehen im Protokoll im Datenordner.", "m", "muted", "regular", true))
			_hinweis(left, "Aktueller Sprachkanal im Guide unter Discord.")
			return
		Voice.load_guilds.call_deferred()
		_group(left, "Server werden geladen …")
		_hinweis(left, "Discord schickt gleich deine Server.")
		return
	_group(left, "Server", Voice.guilds.size())
	var first := true
	for g in Voice.guilds:
		var gid := str(g.id)
		var on := gid == Voice.browse_guild
		var gr = FriendRow.new()
		gr.setup(str(g.name), "Sprachkanäle zeigen" if not on else "gewählt", str(g.get("icon", "")), "")
		gr.glyph_icon = "discord" if str(g.get("icon", "")) == "" else ""
		gr.line_color = "ok" if on else "muted"
		gr.set_meta("uz_key", "srv:" + gid)
		gr.set_meta("uz_hint_a", "Kanäle zeigen")
		gr.activated.connect(func() -> void: Voice.browse_server(gid))
		if first and Voice.browse_guild == "":
			gr.set_meta("uz_default", true)
			first = false
		left.add_child(gr)
	if Voice.browse_guild == "":
		# Mit Discord-Freunden oben braucht es den Hinweis nicht.
		if not dm_first:
			_hinweis(left, "Server wählen.")
		return
	_group(left, "Sprachkanäle in " + Voice.guild_name(Voice.browse_guild), Voice.browse.size())
	if Voice.browse.is_empty():
		for i in 4:
			left.add_child(Skeleton.person())
		return
	for ch in Voice.browse:
		var cid := str(ch.id)
		var cname := str(ch.name)
		var mem: Array = ch.members
		var cr = FriendRow.new()
		var names := PackedStringArray(mem.slice(0, 3).map(func(m): return str(m.name)))
		var here := cid == str(Voice.channel.get("id", ""))
		cr.setup(cname,
				("Du bist hier · " if here else "") + (", ".join(names) + (" und %d weitere" % (mem.size() - 3) if mem.size() > 3 else "") if not mem.is_empty()
				else "leer"), "", "")
		cr.glyph_icon = "headset"
		cr.line_color = "ok" if not mem.is_empty() else "muted"
		cr.stack = mem.map(func(m): return { "name": m.name, "avatar": m.avatar })
		cr.set_meta("uz_key", "vc:" + cid)
		cr.set_meta("uz_hint_a", "Beitreten" if not here else "Du bist hier")
		cr.activated.connect(func() -> void:
			if not here:
				Voice.join(cid)
				Toasts.show_toast("Wechsle zu %s" % cname, Voice.guild_name(Voice.browse_guild), "headset", { "ms": 1600, "quiet": true })
		)
		if first:
			cr.set_meta("uz_default", true)
			first = false
		left.add_child(cr)
		for m in mem:
			var md: Dictionary = { "name": str(m.name), "avatar": str(m.avatar), "state": "online", "game": "", "channel": cid }
			left.add_child(_member(md, ""))
	if first:
		_hinweis(left, "Niemand im Sprachkanal.")


func _discord(left: VBoxContainer, sid: String) -> void:
	var s: Dictionary = Social.discord.get(sid, {})
	if s.is_empty():
		for i in 6:
			left.add_child(Skeleton.person())
		return
	if str(s.get("error", "")) != "":
		left.add_child(_problem(str(s.error), (s.get("members", []) as Array).is_empty()))
	var first := true
	for ch in s.get("channels", []):
		if (ch.members as Array).is_empty():
			continue
		var chd: Dictionary = ch
		_group(left, "Sprachkanal", (ch.members as Array).size())
		var cr = FriendRow.new()
		var names := PackedStringArray((ch.members as Array).slice(0, 3).map(func(m): return str(m.name)))
		cr.setup(str(ch.name), ", ".join(names) + (" und %d weitere" % (ch.members.size() - 3) if ch.members.size() > 3 else ""), "", "")
		cr.glyph_icon = "headset"
		cr.line_color = "muted"
		cr.stack = (ch.members as Array).map(func(m): return { "name": m.name, "avatar": m.avatar })
		cr.set_meta("uz_key", "vc:" + str(ch.id))
		cr.set_meta("uz_hint_a", "Beitreten")
		cr.activated.connect(func() -> void: FriendActions.join_voice(main, str(chd.id), str(chd.name)))
		if first:
			cr.set_meta("uz_default", true)
			first = false
		left.add_child(cr)
		for m in ch.members:
			left.add_child(_member(m, sid))
	var idle: Array = (s.get("members", []) as Array).filter(func(m): return str(m.channel) == "")
	if not idle.is_empty():
		_group(left, "Online", idle.size())
		for m in idle:
			var it := _member(m, sid)
			if first:
				it.set_meta("uz_default", true)
				first = false
			left.add_child(it)
	if first:
		_hinweis(left, "Gerade ist niemand aus %s online." % str(s.get("name", "dem Server")))


func _member(m: Dictionary, sid: String) -> Control:
	var it = FriendRow.new()
	var in_voice := str(m.get("channel", "")) != ""
	var where := str(m.game) if str(m.game) != "" else ChatView.status_line({ "state": str(m.state) })
	if bool(m.get("muted", false)):
		where += " · stumm"
	# Eine gesendete Freundschaftsanfrage steht als Zustand an der Person, nicht als eigene Liste.
	if FR.sent_to(Social.requests, "discord", str(m.get("id", "")), str(m.name)):
		where = FR.line({ "dir": FR.OUT })
	it.setup(str(m.name), where, str(m.avatar), "voice" if in_voice else str(m.state))
	it.line_color = "ok" if str(m.game) != "" else "muted"
	if in_voice:
		it.badge_icon = "headset"
	it.set_meta("uz_hint_a", "Optionen")
	it.set_meta("uz_key", "dm:" + str(m.name))
	it.activated.connect(func() -> void: main.open_friend(m, "discord", sid))
	return it
