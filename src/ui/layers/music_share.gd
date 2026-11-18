extends "res://src/ui/layers/sheet.gd"
## Den laufenden Song an einen Freund schicken oder zum Zusammenhören einladen – über Uzais
## eigenen Chat (Steam bzw. Discord-Direktnachrichten), ohne eine andere App nach vorn zu holen.
## Alle Freunde sind wählbar, wer online ist, steht oben (Nachrichten an Offline-Freunde kommen an,
## sobald sie wieder da sind). Früher zeigte die Auswahl nur Steam-Freunde, die laut Web-API online
## waren – mit privatem Profil oder ohne Chat-Anmeldung meldet die Web-API alle „offline“, und die
## Liste blieb leer.

const STATE_TEXT := { "online": "Online", "away": "Abwesend", "idle": "Abwesend", "busy": "Beschäftigt", "snooze": "Abwesend",
	"dnd": "Bitte nicht stören", "offline": "Offline" }
const RANK := { "game": 0, "online": 1, "busy": 2, "dnd": 2, "away": 3, "idle": 3, "snooze": 3, "offline": 4 }

var mode := "song"            ## song: Song schicken · together: Zusammen hören einladen
const Main := preload("res://src/main.gd")
var main: Main
var _asked := false


func build() -> void:
	var title := str(Music.now.get("title", ""))
	var artist := str(Music.now.get("artist", ""))
	var song := ("„%s“" % title + (" · " + artist if artist != "" else "")) if title != "" else "Gerade läuft nichts"
	setup("Zusammen hören einladen" if mode == "together" else "Song schicken an", song, 760)
	super()


## Alle Freunde, an die Uzai schreiben kann: Steam und (verbunden) Discord-Direktnachrichten.
## Wer online ist, zuerst (im Spiel, online, beschäftigt, abwesend), dann nach Name; offline am
## Ende. Öffentlich für die Tests. [{ kind, friend, name, avatar, state, online, sub }]
static func targets(steam: Array, discord: Array, with_discord: bool) -> Array:
	var out: Array = []
	for f in steam:
		if f is Dictionary and str(f.get("id", "")) != "":
			out.append(_entry("steam", f))
	if with_discord:
		for f2 in discord:
			if f2 is Dictionary and str(f2.get("id", "")) != "":
				out.append(_entry("discord", f2))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(RANK.get(str(a.state), 1))
		var rb := int(RANK.get(str(b.state), 1))
		if ra != rb:
			return ra < rb
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	)
	return out


static func _entry(kind: String, f: Dictionary) -> Dictionary:
	var st := str(f.get("state", "offline"))
	if st == "online" and str(f.get("game", "")) != "":
		st = "game"
	var sub := ("Spielt " + str(f.game)) if str(f.get("game", "")) != "" and st != "offline" else str(STATE_TEXT.get(st, "Online"))
	return { "kind": kind, "friend": f, "name": str(f.get("name", "?")), "avatar": str(f.get("avatar", "")), "state": st,
		"online": st != "offline", "sub": sub }


func fill() -> void:
	var with_discord := DiscordChat.can_send()
	var list := targets(Social.steam_friends, DiscordChat.friends, with_discord)
	if list.is_empty():
		# Steam verbunden, aber die Liste ist (noch) leer: einmal nachladen, dann neu füllen.
		if Social.has_steam() and not _asked and not Social.demo:
			_asked = true
			add_label("Freunde werden geladen …", "m", "muted")
			await Social.refresh_steam()
			if is_inside_tree():
				await refill()
				var d := Nav.default_in(content)
				if d and is_inside_tree():
					Nav.focus(d, true)
			return
		var why := Social.steam_error if Social.steam_error != "" else "Noch keine Freunde: unter Einstellungen → Konten Steam anmelden oder Discord-Nachrichten einschalten."
		add_label(why, "m", "muted")
		return
	var shown_offline := false
	var first := true
	for e in list:
		if not bool(e.online) and not shown_offline:
			shown_offline = true
			add_gap(8)
			add_label("Offline – bekommt die Nachricht, sobald er wieder da ist", "s", "faint")
		var it = ListItem.new()
		it.setup(str(e.name), str(e.sub), "Steam" if str(e.kind) == "steam" else "Discord")
		it.avatar = true
		it.image_url = str(e.avatar)
		it.status = str((e.friend as Dictionary).get("state", "offline"))
		it.set_meta("uz_hint_a", "Einladen" if mode == "together" else "Schicken")
		if first:
			it.set_meta("uz_default", true)
			first = false
		var kind := str(e.kind)
		var fd: Dictionary = e.friend
		it.activated.connect(func() -> void:
			close()
			if mode == "together":
				invite(main, kind, fd)
			else:
				send_song(main, kind, fd)
		)
		add_row(it)
	if not with_discord and DiscordChat.wanted():
		add_gap(10)
		add_label("Discord-Freunde erscheinen hier, sobald Discord-Nachrichten verbunden sind.", "s", "faint")


## Den laufenden Song schicken (Steam- oder Discord-Chat in Uzai); Uzai meldet „Gesendet an …“.
static func send_song(main_node: Main, kind: String, f: Dictionary) -> void:
	var link := Music.share_link()
	if link == "":
		Toasts.show_toast("Gerade läuft kein Spotify-Titel", "", "music", { "ms": 1800 })
		return
	main_node.send_message(kind, f, "Hör mal: %s – %s %s" % [str(Music.now.get("title", "")), str(Music.now.get("artist", "")), link])


## Zum Zusammenhören einladen: Einladung mit Titel, Stelle und Link (oder Jam-Link aus der
## Zwischenablage). Hört der Freund danach dasselbe (Discord-Status), meldet Uzai „… hört jetzt mit“.
static func invite(main_node: Main, kind: String, f: Dictionary) -> void:
	if Music.share_link() == "":
		Toasts.show_toast("Gerade läuft kein Spotify-Titel", "", "music", { "ms": 1800 })
		return
	var text := Music.invite_together(kind, f)
	main_node.send_message(kind, f, text)


## Läuft gerade ein Spotify-Titel, den man teilen kann? (Bedingung für „Zusammen hören einladen“.)
static func can_share() -> bool:
	return not Music.now.is_empty() and bool(Music.now.get("playing", false)) and Music.share_link() != ""


## Auswahl öffnen.
static func show_for(main_node: Main, mode_: String) -> void:
	var l = load("res://src/ui/layers/music_share.gd").new()
	l.mode = mode_
	main_node.open_layer(l)
