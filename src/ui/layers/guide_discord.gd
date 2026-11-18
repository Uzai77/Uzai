extends "res://src/ui/layers/guide_spiel.gd"
## Guide, Schicht über guide_spiel.gd: der Reiter Discord – Sprachkanal mit den Leuten als Zeilen,
## darunter was man im Kanal tut, Kanal und Server wählen, Einrichtung, und was bei neuen Daten von
## Discord und Freunden passiert.

const FriendActions := preload("res://src/ui/layers/friend_actions.gd")
const VoiceRow := preload("res://src/ui/components/guide_voice_row.gd")
const PersonMenu := preload("res://src/ui/layers/person_menu.gd")
const MyProfile := preload("res://src/ui/layers/my_profile.gd")
const MyStatus := preload("res://src/core/my_status.gd")

var _tiles := {}               ## Personen-ID -> Zeile
var _voice_sig := ""
var _schalter := ""            ## Stand der Schalter Mikro und Ton, wie sie gerade dastehen (ohne Kanal)
var _speaker_l: Label


# --- Discord -------------------------------------------------------------------------------

func _tab_discord() -> void:
	_voice_sig = _sig()
	_schalter = _schalter_jetzt()
	if Voice.in_channel():
		_discord_channel()
	elif Voice.ready_():
		_discord_idle()
	else:
		_discord_setup()


## Stand der Schalter Mikro und Ton unter der Kanal-Liste (leer im Kanal: dort zeigt ihn deine Zeile).
func _schalter_jetzt() -> String:
	return "" if Voice.in_channel() or not Voice.ready_() else "%s|%s" % [Mixer.mic_aus(), Voice.self_deaf]


## Signatur des Kanals: ändert sie sich, wird der Reiter neu gebaut, sonst nur aufgefrischt.
func _sig() -> String:
	var ids := PackedStringArray(Voice.members.map(func(m): return str(m.id)))
	# Im Kanal stehen die anderen Kanäle nur in der Auswahl hinter „Kanal wechseln“: dann zählt
	# nur, ob es welche gibt (sonst baute jeder Wechsel woanders den Reiter neu).
	# Ohne Kanal stehen die Kanäle mit Namen da: dann zählt auch, wer darin sitzt (nicht nur wie viele).
	var wer := func(o) -> String: return "%s:%d" % [o.id, hash((o.members as Array).map(func(m): return str(m.get("id", ""))))]
	var oth := PackedStringArray(Voice.others.map(wer)) if not Voice.in_channel() else PackedStringArray([str(Voice.others.is_empty())])
	var br := PackedStringArray(Voice.browse.map(wer))
	return "%s|%s|%s|%s|%s|%d|%s|%s|%s|%s" % [Voice.state, str(Voice.channel.get("id", "")), ",".join(ids), ",".join(oth), str(main.discord_live),
			Voice.guilds.size(), Voice.browse_guild, ",".join(br), Voice.guilds_error, Voice.error]


## Im Kanal: oben Kanal und Server, wer gerade spricht; darunter die Leute als Zeilen (A: Menü an
## der Person, X: stumm – bei anderen für dich, in deiner eigenen Zeile dein Mikro, so wie der Knopf
## „Mikro“ der Schnellleiste; Y dort der Ton), dann was man im Kanal tut: Streams ansehen, Remote Play, Kanal wechseln,
## Verlassen leise ganz unten. Die Zahl der Leute steht nur einmal (am Abschnitt).
func _discord_channel() -> void:
	var ch := Voice.channel
	var n := Voice.members.size()
	var guild := str(ch.get("guild", ""))
	_content.add_child(_heading(str(ch.get("name", tr("Sprachkanal"))), guild, true))
	# Wer gerade spricht (lebt mit).
	var sp := U.hbox(8)
	sp.add_child(_Wave.new())
	_speaker_l = U.label("", "s", "speak", "medium")
	_speaker_l.clip_text = false
	_speaker_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sp.add_child(_speaker_l)
	_content.add_child(sp)
	_update_speaker()
	_content.add_child(U.spacer(0, 14, false))
	_content.add_child(_section("Im Kanal", str(n)))
	_content.add_child(U.spacer(0, 4, false))
	var people := _list()
	people.set_meta("uz_group", "guide:voice")
	people.set_meta("uz_mem", true)
	_content.add_child(people)
	var first := true
	var k := 0
	for m in Voice.members:
		var tile = VoiceRow.new()
		tile.setup(m)
		tile.live = main.discord_live
		tile.set_meta("uz_hint_a", "Menü")
		var me: bool = m.get("me", false)
		# Die Hinweise zu X und Y setzt die Zeile selbst, passend zum Stand (guide_voice_row.gd).
		if not me:
			var uid := str(m.id)
			tile.set_meta("uz_on_x", func() -> void:
				var on := Voice.toggle_local_mute(uid)
				Toasts.show_toast(("%s für dich stumm" if on else "%s wieder hörbar") % str(Voice.member(uid).get("name", "")), "", "mic_off" if on else "volume",
						{ "ms": 1600, "quiet": true })
			)
		else:
			tile.set_meta("uz_on_x", func() -> void: Mixer.toggle_mic())
			tile.set_meta("uz_on_y", func() -> void: Voice.set_self_deaf(not Voice.self_deaf))
		if first and not me:
			tile.set_meta("uz_default", true)
			tile.set_meta("uz_entry", true)
			first = false
		tile.chosen.connect(_open_person.bind(tile))
		people.add_child(tile)
		if not _quiet:
			tile.appear(U.NACH_FLAECHE + U.staffel(k))
		k += 1
		_tiles[str(m.id)] = tile
	if first and people.get_child_count() > 0:
		people.get_child(0).set_meta("uz_default", true)
	if Voice.guilds.is_empty():
		Voice.load_guilds.call_deferred()
	_content.add_child(_divider(14))
	_content.add_child(_rv(_voice_bar()))


## Im Spiel: alle aus dem Call (Sprachkanal oder Gruppenanruf) auf einmal zu Remote Play
## Together einladen – Leiste mit Zuordnung Discord ↔ Steam (src/ui/layers/call_invite.gd).
func _call_invite_row() -> Control:
	var CallInvite = load("res://src/core/call_invite.gd")
	var av: Dictionary = CallInvite.availability()
	if not bool(av.show):
		return null
	var n: int = Voice.members.filter(func(m): return not bool(m.get("me", false)) and not bool(m.get("bot", false))).size()
	var r = GuideRow.new().setup(str(av.label), "controller", "%s · %s" % [U.plural(n, "Person", "Personen"), Library.display_title(Launcher.current)])
	r.chevron = true
	r.set_meta("uz_key", "vb:callinvite")
	r.set_meta("uz_hint_a", "Einladen" if bool(av.ok) else "Warum nicht?")
	r.activated.connect(func() -> void:
		if not bool(av.ok):
			Toasts.show_toast("Remote Play Together ist aus", str(av.why), "controller", { "ms": 8000 })
			return
		var l = load("res://src/ui/layers/call_invite.gd").new()
		l.main = main
		main.open_layer(l)
	)
	return r


## Kanal wechseln: die anderen Sprachkanäle des Servers (die mit Leuten zuerst, mit Namen), am
## Ende „Anderer Server …“.
func _pick_channel() -> void:
	var others := Voice.others.duplicate()
	others.sort_custom(func(a, b): return (a.members as Array).size() > (b.members as Array).size())
	var opts: Array = []
	for o in others:
		var names := PackedStringArray((o.members as Array).map(func(m): return str(m.name)))
		opts.append([str(o.id), str(o.name), ", ".join(names) if not names.is_empty() else "leer"])
	if Voice.guilds.size() > 1:
		opts.append(["_server", "Anderer Server …", "Sprachkanäle eines anderen Servers"])
	main.open_choice("Kanal wechseln", opts, "", func(id: Variant) -> void:
		if str(id) == "_server":
			_pick_server.call_deferred()
			return
		Voice.join(str(id))
		for o in Voice.others:
			if str(o.id) == str(id):
				Toasts.show_toast("Wechsle zu %s" % str(o.name), "", "headset", { "ms": 1600, "quiet": true })
	, str(Voice.channel.get("guild", "")))


## Channel actions as rows: watch streams, Remote Play, switch channel, and a subdued "leave" at the
## end. „Übertragen“ is no longer offered here because its purpose was unclear; you stream your own
## game from the game's actions on the home screen. While a stream is running, this only shows how to
## end it. Without a channel: microphone and sound as toggles (left/right or A).
func _voice_bar() -> Control:
	var bar := _list()
	bar.set_meta("uz_group", "guide:voicebar")
	if main.discord_live:
		var go = GuideRow.new().setup("Stream beenden", "live", "live")
		go.icon_color = "accent"
		go.set_meta("uz_key", "vb:live")
		go.set_meta("uz_hint_a", "Stream beenden")
		go.activated.connect(func() -> void: main.discord_go_live())
		bar.add_child(go)
	# Zuschauen geht nur in der Discord-App: „Streams ansehen“ holt sie mit dem Kanal nach vorn –
	# die eine bewusste Ausnahme, die Guide-Taste bringt dich zurück.
	if Voice.in_channel():
		var streams := Voice.members.filter(func(m): return bool(m.get("streaming", false))).map(func(m): return str(m.name))
		# own_text: the suffix is names (kept as they are), while the title is Uzai's own text and is therefore
		# translated here; otherwise "Streams ansehen" stayed German in the English UI.
		var watch := _act(tr("Streams ansehen"), "tv", func() -> void: main.watch_discord_streams(), ", ".join(PackedStringArray(streams)))
		watch.set("own_text", true)
		watch.set_meta("uz_key", "vb:watch")
		watch.set_meta("uz_hint_a", "Ansehen")
		bar.add_child(watch)
		var rp := _call_invite_row()
		if rp:
			bar.add_child(rp)
		if not Voice.others.is_empty() or Voice.guilds.size() > 1:
			var sw := _act("Kanal wechseln", "headset", _pick_channel)
			sw.set_meta("uz_key", "vb:switch")
			sw.set_meta("uz_hint_a", "Wechseln")
			bar.add_child(sw)
		var leave = GuideRow.new().setup("Verlassen", "leave")
		leave.set("icon_color", "faint")
		leave.set_meta("uz_key", "vb:leave")
		leave.activated.connect(func() -> void:
			Voice.leave()
			Toasts.show_toast("Sprachkanal verlassen", "", "leave", { "ms": 1600, "quiet": true })
		)
		bar.add_child(leave)
		return bar
	# Ohne Kanal: Mikro und Ton als Schalter (links/rechts oder A).
	if Voice.ready_():
		var mic_aus := Mixer.mic_aus()
		var mic = GuideRow.new().setup("Mikro", "mic_off" if mic_aus else "mic")
		mic.switch_state = 0 if mic_aus else 1
		mic.set_meta("uz_key", "vb:mic")
		mic.set_meta("uz_hint_a", "Mikro an" if mic_aus else "Mikro aus")
		# Der Neuaufbau kommt mit der Meldung des neuen Stands (_mikro_neu), die Auswahl bleibt.
		var flip_mic := func(_d: int = 0) -> void: Mixer.toggle_mic()
		mic.activated.connect(flip_mic)
		mic.stepped.connect(flip_mic)
		bar.add_child(mic)
		var deaf = GuideRow.new().setup("Ton", "headset_off" if Voice.self_deaf else "headset")
		deaf.switch_state = 0 if Voice.self_deaf else 1
		deaf.set_meta("uz_key", "vb:deaf")
		deaf.set_meta("uz_hint_a", "Ton an" if Voice.self_deaf else "Ton aus")
		var flip_deaf := func(_d: int = 0) -> void: Voice.set_self_deaf(not Voice.self_deaf)
		deaf.activated.connect(flip_deaf)
		deaf.stepped.connect(flip_deaf)
		bar.add_child(deaf)
	return bar


## Deep-Link in den Kanal; Anrufe und Gruppen (ohne Server) liegen unter „@me“.
static func discord_channel_url(channel: Dictionary) -> String:
	var cid := str(channel.get("id", ""))
	if cid == "":
		return ""
	var gid := str(channel.get("guild_id", ""))
	return "discord://-/channels/%s/%s" % [gid if gid != "" else "@me", cid]


## Du bist verbunden, aber in keinem Kanal: oben der Server (A: anderen wählen), darunter seine
## Sprachkanäle mit den Leuten darin – ein Druck, und du bist drin.
func _discord_idle() -> void:
	var shown_guild := Voice.browse_guild if Voice.browse_guild != "" else Voice.others_guild
	_content.add_child(_heading("Discord", Voice.guild_name(shown_guild) if shown_guild != "" else "", true))
	_content.add_child(_divider(14))
	var list := _list()
	_content.add_child(list)
	if Voice.guilds.is_empty():
		if Voice.guilds_error != "":
			list.add_child(_rv(U.label(Voice.guilds_error, "s", "muted", "regular", true)))
		else:
			Voice.load_guilds.call_deferred()
	else:
		var srv := _act(tr("Server"), "discord", _pick_server, Voice.guild_name(shown_guild) if shown_guild != "" else "")
		srv.set("own_text", true)
		srv.set_meta("uz_key", "srv:more")
		srv.set_meta("uz_hint_a", "Server wählen")
		list.add_child(_rv(srv))
	var any := false
	var chans: Array = Voice.browse if Voice.browse_guild != "" else Voice.others
	if not chans.is_empty() or Voice.browse_guild != "":
		_content.add_child(_divider(14))
		_content.add_child(_section("Sprachkanäle"))
		_content.add_child(U.spacer(0, 6, false))
	var cl := _list()
	_content.add_child(cl)
	for o in chans:
		var names := PackedStringArray(o.members.map(func(m): return str(m.name)))
		var oid := str(o.id)
		var r = GuideRow.new().setup(str(o.name), "headset", ", ".join(names), str(o.members.size()) if not o.members.is_empty() else "")
		r.own_text = true
		r.set_meta("uz_hint_a", "Beitreten")
		r.set_meta("uz_key", "ch:" + oid)
		r.activated.connect(func() -> void: Voice.join(oid))
		if not any:
			r.set_meta("uz_default", true)
		any = true
		cl.add_child(_rv(r))
	if not any:
		if Voice.browse_guild != "":
			if Voice.browse.is_empty():
				cl.add_child(U.label("Lädt die Sprachkanäle …", "s", "faint", "regular"))
		else:
			_widget_channels(cl)
	_content.add_child(_divider(14))
	_content.add_child(_rv(_voice_bar()))


## Alle Server zur Wahl, danach dessen Sprachkanäle (auch aus einem Kanal heraus).
func _pick_server() -> void:
	var opts: Array = []
	for g in Voice.guilds:
		opts.append([str(g.id), str(g.name), ""])
	main.open_choice("Server", opts, Voice.browse_guild, func(id: Variant) -> void:
		Voice.browse_server(str(id))
		if Voice.in_channel():
			_pick_browse_channel()
	)


func _pick_browse_channel() -> void:
	# Kurz warten, bis Discord die Kanäle geschickt hat.
	for i in 30:
		if not Voice.browse.is_empty():
			break
		await get_tree().create_timer(0.1).timeout
		# Guide inzwischen zu: keine Auswahl mehr öffnen (und kein Baum mehr für die nächste Runde).
		if not is_inside_tree() or _closing:
			return
	if Voice.browse.is_empty():
		Toasts.show_toast("Keine Sprachkanäle", Voice.guild_name(Voice.browse_guild), "headset")
		return
	var opts: Array = []
	for o in Voice.browse:
		var cnt := (o.members as Array).size()
		opts.append([str(o.id), str(o.name), U.plural(cnt, "Person", "Personen") if cnt > 0 else "leer"])
	main.open_choice("Sprachkanal", opts, str(Voice.channel.get("id", "")), func(id: Variant) -> void:
		Voice.join(str(id))
	, Voice.guild_name(Voice.browse_guild))


## Noch nicht eingerichtet oder nicht freigegeben: was fehlt, und der eine Weg dorthin.
func _discord_setup() -> void:
	_content.add_child(_heading("Discord"))
	_content.add_child(U.spacer(0, 10, false))
	var text := ""
	var btn_text := ""
	var btn_cb: Callable
	match Voice.state:
		"aus":
			text = Voice.missing_text() if Voice.client_id() == "" else "Unter Einstellungen → Konten → Discord „Sprachkanal im Guide“ einschalten."
			# Im Spiel käme die Seite hinter dem Spiel heraus: dann nur der Hinweis.
			if not Launcher.in_game and not Video.active:
				btn_text = "Einstellungen öffnen"
				btn_cb = func() -> void:
					close()
					main.goto("settings", "konten")
		"getrennt", "fehler" when Voice.tester_fehlt and Voice.builtin():
			# Uzais App ist für dieses Konto nicht freigeschaltet: kein „In der Discord-App freigeben“, das ginge nicht.
			text = Voice.TESTER_TEXT
			btn_text = "Einrichten"
			btn_cb = func() -> void: main.open_layer(load("res://src/ui/layers/discord_eigen.gd").new())
		"getrennt", "fehler":
			text = "In der Discord-App freigeben."
			if Voice.error != "":
				text += "\n" + Voice.error
			btn_text = "Mit Discord verbinden"
			btn_cb = func() -> void:
				var dc = load("res://src/ui/layers/discord_connect.gd").new()
				dc.autostart = true
				main.open_layer(dc)
		"anmelden":
			text = "In Discord „Autorisieren“ klicken."
			btn_text = "Maus mit dem Controller"
			btn_cb = func() -> void: main.set_mouse_mode(true)
		_:
			text = "Verbinde mit Discord …"
	var p := U.label(text, "s", "muted", "regular", true)
	_content.add_child(_rv(p))
	_content.add_child(U.spacer(0, 14, false))
	var list := _list()
	_content.add_child(list)
	if btn_text != "":
		var b := _act(btn_text, "discord", btn_cb)
		b.set_meta("uz_default", true)
		list.add_child(_rv(b))
	if Voice.state in ["getrennt", "fehler", "anmelden"] and btn_text != "Maus mit dem Controller":
		list.add_child(_rv(_act("Maus mit dem Controller", "controller", func() -> void: main.set_mouse_mode(true))))
	var gr := _list()
	if _widget_channels(gr):
		_content.add_child(_divider(14))
		_content.add_child(_section("Sprachkanäle mit Leuten"))
		_content.add_child(U.spacer(0, 6, false))
		_content.add_child(gr)
	_content.add_child(_divider(14))
	_content.add_child(_voice_bar())


## Kanäle aus dem Server-Widget (Discord noch nicht verbunden): A betritt den Kanal über Uzai.
## Fehlt die Verbindung, führt Uzai durch die Einrichtung – die Discord-App kommt nicht nach vorn.
func _widget_channels(into: Container) -> bool:
	var any := false
	for c in Social.voice_channels().slice(0, 4):
		var names := PackedStringArray(c.members.map(func(m): return str(m.name)))
		var cid := str(c.id)
		var cname := str(c.name)
		var it = GuideRow.new().setup("%s · %s" % [c.name, c.server_name], "headset", ", ".join(names), str(c.members.size()))
		it.own_text = true
		it.set_meta("uz_hint_a", "Beitreten")
		it.activated.connect(func() -> void: FriendActions.join_voice(main, cid, cname))
		into.add_child(_rv(it))
		any = true
	return any


func _open_person(_m: Dictionary, tile) -> void:
	var pm = PersonMenu.new()
	pm.member = Voice.member(str(tile.member.get("id", "")))
	if pm.member.is_empty():
		pm.member = tile.member
	pm.anchor = tile.get_global_rect()
	pm.guide = self
	pm.source = tile
	main.open_layer(pm)


## Dein Profil oben in der Leiste (Kopf): A öffnet „Dein Status“ (Steam und Discord ändern, Wege
## zu Profil und Konten), siehe my_profile.gd.
func _open_my_profile(card: Control) -> void:
	var l = MyProfile.new()
	l.anchor = card.get_global_rect()
	l.main = main
	l.guide = self
	l.source = card
	main.open_layer(l)


func _open_friend(e: Dictionary, row: Control) -> void:
	var pm = PersonMenu.new()
	pm.friend = e
	pm.anchor = row.get_global_rect()
	pm.guide = self
	pm.source = row
	main.open_layer(pm)


func _on_voice_changed() -> void:
	if tab != "discord" or not is_instance_valid(_content):
		return
	if _sig() != _voice_sig:
		_rebuild_soon()
		return
	for m in Voice.members:
		var t = _tiles.get(str(m.id))
		if t and is_instance_valid(t):
			t.refresh(m)
	_update_speaker()
	# Tastenhinweise unten (X) passen sich dem neuen Zustand an.
	Nav.focus_moved.emit(Nav.focused())


## Dein Mikro oder Ton wurde geschaltet, vielleicht nur in Windows oder in Discord selbst (guide.gd
## _on_mic): Deine Zeile im Kanal zeigt denselben Stand wie der Knopf „Mikro“ der Schnellleiste;
## ohne Kanal stehen die beiden Schalter neu da.
func _mikro_neu() -> void:
	if tab != "discord" or not is_instance_valid(_content) or _sig() != _voice_sig:
		return
	if _schalter_jetzt() != _schalter:
		_rebuild_soon()
		return
	for m in Voice.members:
		var t = _tiles.get(str(m.id)) if m.get("me", false) else null
		if t and is_instance_valid(t):
			t.refresh(m)
			if t == Nav.focused():
				Nav.focus_moved.emit(t)


func _on_speaking(uid: String, _on: bool) -> void:
	var t = _tiles.get(uid)
	if t and is_instance_valid(t):
		t.refresh(Voice.member(uid))
	_update_speaker()


func _update_speaker() -> void:
	if not is_instance_valid(_speaker_l):
		return
	var who := Voice.members.filter(func(m): return m.get("speaking", false)).map(func(m): return str(m.name))
	var wave: Control = _speaker_l.get_parent().get_child(0)
	wave.visible = not who.is_empty()
	wave.set_process(not who.is_empty())
	if who.is_empty():
		_speaker_l.text = ""
	elif who.size() == 1:
		_speaker_l.text = "%s spricht" % who[0]
	else:
		_speaker_l.text = "%s und %s sprechen" % [", ".join(PackedStringArray(who.slice(0, who.size() - 1))), who.back()]


# --- Zeichnen: wer spricht -------------------------------------------------------------------------

## Drei grüne Balken, die sich bewegen, solange jemand spricht.
class _Wave extends Control:
	var _t := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(20, 22)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var c := UzTheme.col("speak")
		for i in 3:
			var h := 6.0 + 14.0 * absf(sin(_t * (5.0 + i * 1.7) + i))
			draw_style_box(UzTheme.box(c, 2), Rect2(i * 7, (size.y - h) * 0.5, 4, h))
