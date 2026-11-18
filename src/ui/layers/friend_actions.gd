extends "res://src/ui/layers/sheet.gd"
## Was man mit einem Freund tun kann – nur das, was gerade geht, wie im Steam-Menü:
## Spiel beitreten (offene Lobby/Server), einladen (im eigenen Steam-Spiel), Chat und Profil
## (beides in Uzai), Link schicken, Erfolge vergleichen, melden, wenn online. Bei Discord
## dieselbe Auswahl: Profil, Nachricht, Anrufen, Sprachkanal betreten (über Uzais Discord-
## Anbindung), Auch spielen; oben was der Freund gerade tut. Nichts davon holt eine andere App nach vorn.

const Avatar := preload("res://src/ui/components/avatar.gd")
const FriendProfile := preload("res://src/ui/layers/friend_profile.gd")
const RemotePlay := preload("res://src/core/remote_play.gd")
const MusicShare := preload("res://src/ui/layers/music_share.gd")
const DcActivity := preload("res://src/core/discord_activity.gd")

var friend: Dictionary = {}
var kind := "steam"             ## steam oder discord
var server_id := ""
const Main := preload("res://src/main.gd")
var main: Main


func build() -> void:
	var where := Library.friend_game_title(str(friend.get("game", "")), str(friend.get("game_id", "")))
	if kind == "discord":
		# Was Discord über die Aktivität verrät (Spiel, Musik, Stream, seit wann), sonst der Zustand.
		var act := _activity()
		where = DcActivity.headline(act)
		var since := DcActivity.since_text(int(act.since), int(Time.get_unix_time_from_system()))
		if where != "" and since != "":
			where += " · " + since
	elif where != "":
		where = "Spielt " + where
	if where == "":
		where = { "online": "Online", "away": "Abwesend", "idle": "Abwesend", "busy": "Beschäftigt", "dnd": "Bitte nicht stören", "game": "Im Spiel",
				"voice": "Im Sprachkanal" }.get(str(friend.get("state", "")), "Offline")
	setup(str(friend.get("name", "Freund")), ("Steam · " if kind == "steam" else "Discord · ") + where, 780)
	heading_raw = friend.has("name")      # der Name der Person: nie übersetzen
	var av := Avatar.new()
	av.setup(str(friend.get("name", "")), str(friend.get("avatar", "")), str(friend.get("state", "")), 72)
	set_header_image(av)
	super()


func _row(k: String, t: String, icon: String, v: Variant = null) -> Control:
	var r = SettingRow.new()
	r.setup(k, t, "", v)
	r.icon_name = icon
	return r


func fill() -> void:
	var online := str(friend.get("state", "offline")) != "offline"
	# Reihenfolge wie auf einer Konsole: Profil, Nachricht, Einladen, Anrufen, Beitreten.
	if kind == "steam":
		var pr = _row("action", "Profil", "user")
		pr.on_activate = func() -> void:
			close()
			var l = FriendProfile.new()
			l.friend = friend
			main.open_layer(l)
		add_row(pr)
		var msg = _row("action", "Nachricht", "chat")
		if SteamChat.unread.has(str(friend.get("id", ""))):
			msg.value_text = U.plural(int(SteamChat.unread[str(friend.id)]), "neue Nachricht", "neue Nachrichten")
			msg.set_meta("uz_default", true)      # Ungelesenes: die Auswahl steht gleich auf „Nachricht“
		msg.on_activate = func() -> void:
			close()
			main.open_chat(friend)
		add_row(msg)
		_together_row("steam", friend)
		if Launcher.in_game and str(Launcher.current.get("source", "")) == "steam" and online:
			var inv = _row("action", "Einladen", "plus")
			inv.value_text = str(Launcher.current.get("title", "dein Spiel"))
			inv.on_activate = func() -> void:
				close()
				main.invite_friend(friend)
			add_row(inv)
		_remote_play_row(online)
		var url := Social.join_url(friend)
		if url != "":
			var j = _row("action", "Spiel beitreten", "play")
			j.value_text = Library.friend_game_title(str(friend.get("game", "")), str(friend.get("game_id", "")))
			j.on_activate = func() -> void:
				close()
				# Beitreten startet das Spiel wie jeder Spielstart (Steam verbindet dann).
				main.join_game(friend, url)
			add_row(j)
		var mine := Library.get_game("steam:" + str(friend.get("game_id", "")))
		if not mine.is_empty() and not Launcher.in_game and url == "":
			var p = _row("action", "Auch spielen", "games")
			p.value_text = Library.display_title(mine)
			p.on_activate = func() -> void:
				close()
				main.launch(mine)
			add_row(p)
	else:
		var prof = _row("action", "Profil", "user")
		prof.on_activate = func() -> void:
			close()
			var l = load("res://src/ui/layers/discord_profile.gd").new()
			var f2 := friend.duplicate()
			var dmf := _dm_friend()
			if not dmf.is_empty():
				f2["dm"] = dmf
			l.friend = f2
			main.open_layer(l)
		add_row(prof)
		# Discord-Freund, mit dem Uzai über das Social SDK chatten kann: Nachricht und Anrufen.
		var dm := _dm_friend()
		if not dm.is_empty():
			var m = _row("action", "Nachricht", "chat")
			var n := int(DiscordChat.unread.get(str(dm.get("id", "")), 0))
			if n > 0:
				m.value_text = U.plural(n, "neue Nachricht", "neue Nachrichten")
				m.set_meta("uz_default", true)
			m.on_activate = func() -> void:
				close()
				main.open_discord_chat(dm)
			add_row(m)
			if DiscordChat.can_send():
				_together_row("discord", dm)
			if Voice.ready_() or Voice.demo:
				var c = _row("action", "Anrufen", "phone")
				c.on_activate = func() -> void:
					close()
					call_discord(dm)
				add_row(c)
		var vc_id := str(friend.get("channel", ""))
		if vc_id != "":
			var vc = _row("action", "Sprachkanal beitreten", "headset")
			var ch_name := channel_name(server_id, vc_id)
			vc.value_text = ch_name
			vc.on_activate = func() -> void:
				close()
				join_voice(main, vc_id, ch_name)
			add_row(vc)
		# Auch spielen: das Spiel des Freundes liegt in deiner Bibliothek. Beitreten und Einladen
		# bietet Discord nur innerhalb derselben App an – für fremde Spiele gibt es das nicht.
		var act := _activity()
		var mine := DcActivity.owned(str(act.title), Library.games) if str(act.kind) == "game" else {}
		if not mine.is_empty() and not Launcher.in_game:
			var p = _row("action", "Auch spielen", "games")
			p.value_text = Library.display_title(mine)
			p.on_activate = func() -> void:
				close()
				main.launch(mine)
			add_row(p)
	add_gap()
	var clip := DisplayServer.clipboard_get().strip_edges()
	if kind == "steam" and clip.begins_with("http") and clip.length() < 300:
		var cr = _row("action", "Link aus der Zwischenablage schicken", "link")
		cr.value_text = clip.get_slice("//", 1).get_slice("/", 0)
		cr.on_activate = func() -> void:
			close()
			main.send_message(kind, friend, clip)
		add_row(cr)
	if kind == "steam":
		var cmp = _row("action", "Erfolge vergleichen", "trophy")
		cmp.on_activate = func() -> void:
			close()
			main.open_compare_picker(friend)
		add_row(cmp)
		# Eine leise Mitteilung, sobald er online kommt oder ein Spiel startet (src/core/notify.gd).
		var fid := str(friend.get("id", ""))
		if Notify.watch_id_ok(fid):
			var w = _row("toggle", "Melden, wenn online", "bell", Notify.watching(fid))
			w.changed.connect(func(v: Variant) -> void: Notify.watch_set(fid, bool(v)))
			add_row(w)
	if kind == "discord" and _dm_friend().is_empty():
		add_gap(6)
		add_label("Nachrichten gehen mit Discord-Freunden (Konten → Discord).", "s", "faint")


## Zusammen hören einladen (nur, solange ein Spotify-Titel läuft): Einladung mit Titel, Stelle und
## Link über den Chat in Uzai; hört der Freund danach dasselbe, meldet Uzai „… hört jetzt mit“.
func _together_row(k: String, f: Dictionary) -> void:
	if not MusicShare.can_share():
		return
	var r = _row("action", "Zusammen hören einladen", "headset")
	r.value_text = str(Music.now.get("title", ""))
	r.on_activate = func() -> void:
		close()
		MusicShare.invite(main, k, f)
	add_row(r)


## Was der Discord-Freund gerade tut (Social SDK, sonst Server-Widget), siehe discord_activity.gd.
func _activity() -> Dictionary:
	var dm := _dm_friend()
	var src: Dictionary = dm if not dm.is_empty() else friend
	var wg := str(friend.get("game", "")) if dm.is_empty() else DcActivity.widget_game(dm, Social.discord)
	return DcActivity.of(src, wg)


## Derselbe Mensch in DiscordChats Freundesliste (per ID, sonst per Name).
func _dm_friend() -> Dictionary:
	var f := DiscordChat.friend(str(friend.get("id", "")))
	if f.is_empty() and str(friend.get("name", "")) != "":
		for x in DiscordChat.friends:
			if str(x.get("name", "")).to_lower() == str(friend.name).to_lower():
				return x
	return f


## Zu Remote Play Together einladen (Steam-Spiel oder Start über den Spender).
func _remote_play_row(online: bool) -> void:
	if not online or not RemotePlay.can_invite():
		return
	var rp = _row("action", "Zu Remote Play einladen", "controller")
	rp.value_text = Library.display_title(Launcher.current)
	rp.on_activate = func() -> void:
		close()
		RemotePlay.invite(friend)
	add_row(rp)


## Name eines Sprachkanals aus dem Server-Widget ("" wenn unbekannt).
static func channel_name(sid: String, channel_id: String) -> String:
	for s in ([Social.discord.get(sid, {})] if sid != "" else Social.discord.values()):
		for c in (s as Dictionary).get("channels", []):
			if str(c.get("id", "")) == channel_id:
				return str(c.get("name", ""))
	return ""


## Einen Discord-Sprachkanal betreten – über Uzais Discord-Anbindung (die offizielle lokale
## Schnittstelle der Discord-App), ohne Discord nach vorn zu holen. Geht das gerade nicht,
## sagt Uzai in Uzai, warum, und was zu tun ist.
## Discord-Freund anrufen (Menü an der Person, Leiste, Discord-Profil). Statisch, weil sich das Menü dabei schließt:
## Muss erst der Verlauf geladen werden, kommt die Antwort nach dem Menü – an ihm hängend ginge sie verloren, und
## „Anrufen ging nicht“ erschiene nie.
static func call_discord(dm: Dictionary) -> void:
	Toasts.show_toast("Rufe %s an …" % str(dm.get("name", "Freund")), "Discord klingelt bei deinem Freund. Auflegen: im Guide unter Discord „Verlassen“.", "phone",
			{ "sound": "select", "ms": 4000, "image": str(dm.get("avatar", "")) })
	var err: String = await DiscordChat.call_friend(str(dm.get("id", "")))
	if err != "":
		Toasts.show_toast("Anrufen ging nicht", err, "warning", { "ms": 7000 })


static func join_voice(main_node: Main, channel_id: String, channel_name_: String) -> void:
	var nm := channel_name_ if channel_name_ != "" else "den Sprachkanal"
	if Voice.in_channel() and str(Voice.channel.get("id", "")) == channel_id:
		Toasts.show_toast("Du bist schon in %s" % nm, "Im Guide siehst du, wer gerade spricht.", "headset")
		return
	if Voice.ready_():
		Voice.join(channel_id)
		Toasts.show_toast("Sprachkanal %s" % nm, "Uzai holt dich über Discord dazu.", "headset", { "sound": "select" })
		return
	if not Voice.demo and not Config.is_windows():
		Toasts.show_toast("Sprachkanäle gehen unter Windows", "Dafür braucht es die Discord-App auf diesem PC.", "headset")
		return
	if not Voice.configured():
		main_node.open_dialog("Discord verbinden",
			Voice.missing_text() if Voice.client_id() == "" else "Damit Uzai dich in Sprachkanäle bringt, verbindet es sich einmal mit der Discord-App auf diesem PC: unter Einstellungen → Konten → Discord „Sprachkanal im Guide“ einschalten.",
			[["Zu den Konten", func() -> void: main_node.goto("settings", "konten")], ["Später", Callable()]])
		return
	match Voice.state:
		"getrennt":
			var dc = load("res://src/ui/layers/discord_connect.gd").new()
			dc.autostart = true
			main_node.open_layer(dc)
		"verbinde", "anmelden":
			Toasts.show_toast("Einen Moment", "Uzai verbindet sich gerade mit Discord.", "headset")
		_:
			Voice.start()
			Toasts.show_toast("Discord antwortet nicht", Voice.error if Voice.error != "" else "Läuft die Discord-App auf diesem PC?", "warning", { "ms": 6000 })
