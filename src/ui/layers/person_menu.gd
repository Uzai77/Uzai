extends "res://src/ui/layers/layer.gd"
## Kleines Menü direkt an einer Person im Guide, mit einem Pfeil zur Kachel bzw. Zeile.
## - Im Sprachkanal: Lautstärke (links/rechts), für mich stumm, Nachricht (Steam-Freunde).
## - Bei dir selbst: Übertragen (nur im Spiel), Mikro, Ton.
## - An Freunden (Reiter Freunde, „Mit dir im Spiel“): Profil (Steam), Nachricht, Einladen, Spiel
##   beitreten, Sprachkanal beitreten, auch spielen, Erfolge vergleichen.
## Alles bleibt in Uzai: keine Aktion holt eine andere App nach vorn. Nachrichten und Anrufe an
## Discord-Freunde gehen über das Social SDK (nur mit Discord-Freunden). B schließt; LT/RT
## gehen an den Guide (Lautstärke nur in den Reitern Spiel und Musik, sonst nichts).

const Avatar := preload("res://src/ui/components/avatar.gd")
const People := preload("res://src/ui/components/guide_people.gd")
const RemotePlay := preload("res://src/core/remote_play.gd")
const MusicShare := preload("res://src/ui/layers/music_share.gd")
const DcActivity := preload("res://src/core/discord_activity.gd")
const FriendActions := preload("res://src/ui/layers/friend_actions.gd")

const WIDTH := 400.0

var member: Dictionary = {}       ## Person im Sprachkanal (Voice.members)
var friend: Dictionary = {}       ## Eintrag aus guide_people.gd
var anchor := Rect2()             ## Kachel bzw. Zeile in Bildschirmkoordinaten
const Main := preload("res://src/main.gd")
var main: Main
var guide: Node                   ## der Guide (Lautstärke, Schließen)
var source: Control               ## Kachel/Zeile, an der das Menü hängt
var _panel: PanelContainer
var _caret: Control
var _vol_item
var _mute_item
var _mic_item
var _deaf_item


func build() -> void:
	dim = 0.3
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Zurück")
	set_meta("uz_hints_center", true)
	if is_instance_valid(source) and "hold" in source:
		source.set("hold", true)
	_panel = PanelContainer.new()
	var sb := UzTheme.box(Color(UzTheme.col("surface").lightened(0.05), 0.985), 24, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 36
	sb.shadow_offset = Vector2(0, 16)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	# Erst unsichtbar: die Lage steht erst nach dem ersten Bild fest (sonst blitzt es oben links).
	_panel.modulate.a = 0.0
	add_child(_panel)
	_caret = _Caret.new()
	_caret.color = sb.bg_color
	_caret.modulate.a = 0.0
	add_child(_caret)
	var v := U.vbox(2)
	_panel.add_child(v)
	v.add_child(_header())
	v.add_child(_Sep.new())
	if not friend.is_empty():
		_friend_items(v)
	elif member.get("me", false):
		_me_items(v)
	else:
		_member_items(v)
	_refresh()
	# Unter der Kachel, sonst darüber; nie aus dem Bild. Der Pfeil zeigt auf die Mitte der Kachel.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var ps := _panel.get_combined_minimum_size()
	var vs := get_viewport_rect().size
	var below := anchor.end.y + 14 + ps.y <= vs.y - 96
	var pos := Vector2(anchor.get_center().x - ps.x * 0.5, anchor.end.y + 14 if below else anchor.position.y - ps.y - 14)
	pos.x = clampf(pos.x, 40, vs.x - ps.x - 40)
	pos.y = clampf(pos.y, 24, vs.y - ps.y - 24)
	_panel.position = pos
	_caret.down = not below
	_caret.position = Vector2(clampf(anchor.get_center().x, pos.x + 30, pos.x + ps.x - 30) - 11, pos.y - 10 if below else pos.y + ps.y - 1)
	# Wächst aus der Richtung der Kachel heraus, die Zeilen folgen kurz nacheinander.
	_panel.pivot_offset = Vector2(_caret.position.x + 11 - pos.x, 0.0 if below else ps.y)
	_panel.modulate.a = 0.0
	_caret.modulate.a = 0.0
	_panel.scale = Vector2(0.96, 0.96)
	var tw := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_caret, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_panel, "scale", Vector2.ONE, U.T_MOVE)
	var i := 0
	for c in v.get_children():
		if c is Control and i > 0:
			(c as Control).modulate.a = 0.0
			tw.tween_property(c, "modulate:a", 1.0, U.T_BASE).set_delay(0.03 + i * 0.03)
		i += 1


func _header() -> Control:
	var head := U.margin(14, 10, 16, 10)
	var hr := U.hbox(14)
	head.add_child(hr)
	var av := Avatar.new()
	var nm := str(friend.get("name", member.get("name", "?")))
	var pic := str(friend.get("avatar", member.get("avatar", "")))
	av.setup(nm, pic, People.dot(friend) if not friend.is_empty() else "", 56)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(av)
	var hc := U.vbox(0)
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.alignment = BoxContainer.ALIGNMENT_CENTER
	var nl := U.ellipsis(U.label(nm, "m", "text", "ui_bold"))
	nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name der Person: nie übersetzen
	hc.add_child(nl)
	hc.add_child(U.ellipsis(U.label(_status_line(), "s", "muted", "regular")))
	hr.add_child(hc)
	return head


func _status_line() -> String:
	if not friend.is_empty():
		var parts: PackedStringArray = []
		var g := str(friend.get("game", ""))
		# Discord-Freund (Social SDK): Musik und seit wann, siehe discord_activity.gd.
		var dm: Dictionary = friend.get("dm", {}) if friend.get("dm") is Dictionary else {}
		if g == "" and str(dm.get("music", "")) != "":
			parts.append("hört " + str(dm.music))
		else:
			parts.append(("spielt " + _title(g)) if g != "" else People.doing(friend))
		if g != "" and str(friend.get("join_url", "")) != "":
			parts.append("Lobby offen")
		elif g != "" and bool(friend.get("with_me", false)):
			parts.append("im Sprachkanal")
		elif g != "" and str(dm.get("game", "")) == g:
			var since := DcActivity.since_text(int(dm.get("since", 0)), int(Time.get_unix_time_from_system()))
			if since != "":
				parts.append(since)
		return " · ".join(parts)
	if member.get("me", false):
		var game := Library.display_title(Launcher.current) if Launcher.in_game else ""
		return "Du · " + People.me_status(bool(member.get("speaking", false)), Voice.self_mute, Voice.self_deaf, main != null and bool(main.discord_live), game,
				Video.active)
	return Voice.status_text(member)


## Spieltitel so, wie er in der Bibliothek heißt (Steam meldet etwa „ELDEN RING“).
func _title(g: String) -> String:
	return Library.friend_game_title(g, str(friend.get("game_id", "")))


# --- Einträge ------------------------------------------------------------------------------

func _me_items(v: VBoxContainer) -> void:
	var live: bool = main.discord_live
	var what: String = main.live_source()
	if live or (what != "" and Voice.in_channel()):
		v.add_child(_item("Übertragung beenden" if live else ("Video übertragen" if what == "video" else "Mein Spiel übertragen"), "live", "", func() -> void:
			close()
			main.discord_go_live()
		))
	_mic_item = _item("Mikro", "mic_off" if Mixer.mic_aus() else "mic", "Aus" if Mixer.mic_aus() else "An", func() -> void:
		await Mixer.toggle_mic()
		if is_inside_tree():
			_refresh()
	)
	v.add_child(_mic_item)
	_deaf_item = _item("Ton", "headset_off" if Voice.self_deaf else "headset", "Aus" if Voice.self_deaf else "An", func() -> void:
		Voice.set_self_deaf(not Voice.self_deaf)
		_refresh()
	)
	v.add_child(_deaf_item)


func _member_items(v: VBoxContainer) -> void:
	var uid := str(member.get("id", ""))
	_vol_item = _item("Lautstärke", "volume", "", func() -> void:
		# A setzt auf 100 % zurück, links/rechts ändern in Zehnerschritten.
		Voice.set_volume(uid, 100)
		_refresh()
	)
	_vol_item.bar = true
	_vol_item.on_lr = func(d: int) -> void:
		Voice.set_volume(uid, int(Voice.member(uid).get("volume", 100)) + d * 10)
		Sfx.play("tick", 0.9 + float(Voice.member(uid).get("volume", 100)) / 1000.0)
		_refresh()
	_vol_item.set_meta("uz_hint_a", "Auf 100 %")
	v.add_child(_vol_item)
	_mute_item = _item("Für mich stumm", "mic_off", "", func() -> void:
		Voice.toggle_local_mute(uid)
		_refresh()
	)
	v.add_child(_mute_item)
	var sf := _steam_friend(str(member.get("name", "")))
	if sf.is_empty():
		# Einmal zugeordnet (Alle im Call einladen, siehe call_invite.gd): derselbe Mensch bei Steam.
		var sid: String = load("res://src/core/call_invite.gd").map_steam(load("res://src/core/call_invite.gd").load_map(), uid)
		for f in Social.steam_friends:
			if sid != "" and str(f.get("id", "")) == sid:
				sf = f
	if not sf.is_empty():
		v.add_child(_item("Nachricht", "chat", "Steam", func() -> void:
			close()
			main.open_chat(sf)
		))
		_remote_play_item(v, sf, str(sf.get("state", "offline")) != "offline")


func _friend_items(v: VBoxContainer) -> void:
	var sf: Dictionary = friend.get("steam", {})
	var is_discord := not (friend.get("discord", {}) as Dictionary).is_empty() or str(friend.get("voice_id", "")) != "" or sf.is_empty()
	var online := str(friend.get("state", "offline")) != "offline"
	var gid := str(friend.get("game_id", ""))
	var cur: Dictionary = Launcher.current if Launcher.in_game else {}
	var who := str(friend.get("name", ""))
	# Reihenfolge wie auf einer Konsole: Profil, Nachricht, Einladen, Anrufen, Beitreten.
	if not sf.is_empty():
		v.add_child(_item("Profil", "user", "Level und Spiele", func() -> void:
			close()
			var l = load("res://src/ui/layers/friend_profile.gd").new()
			l.friend = sf
			main.open_layer(l)
		))
		var n := int(friend.get("unread", 0))
		var chat := _item("Nachricht", "chat", U.plural(n, "neue", "neue") if n > 0 else "", func() -> void:
			close()
			main.open_chat(sf)
		)
		chat.set_meta("uz_default", true)
		v.add_child(chat)
	# Kein „Profil“ bei Discord: das Discord-Profil zeigte dieselben Wege wie dieses Menü
	# (Nachricht, Anrufen, Sprachkanal, Auch spielen). Es bleibt in Freunde erreichbar.
	if sf.is_empty() and not (friend.get("dm", {}) as Dictionary).is_empty():
		# Discord-Freund: Direktnachricht über das Social SDK, ganz in Uzai.
		var dm: Dictionary = friend.dm
		var n2 := int(friend.get("unread", 0))
		var dchat := _item("Nachricht", "chat", U.plural(n2, "neue", "neue") if n2 > 0 else "Discord", func() -> void:
			close()
			main.open_discord_chat(dm)
		)
		dchat.set_meta("uz_default", true)
		v.add_child(dchat)
		# Anrufen: die Discord-App ruft an, Uzai bleibt vorn (Ton läuft über Discord).
		if Voice.ready_() or Voice.demo:
			v.add_child(_item("Anrufen", "phone", "über Discord", func() -> void:
				close()
				FriendActions.call_discord(dm)
			))
	_together_item(v, sf)
	# Einladen: ins eigene Steam-Spiel (direkt über Steam, ohne Overlay).
	if not sf.is_empty() and online and str(cur.get("source", "")) == "steam":
		v.add_child(_item("Einladen", "plus", Library.display_title(cur), func() -> void:
			close()
			main.invite_friend(sf)
		, true))
	_remote_play_item(v, sf, online)
	# Beitreten: Steam startet das Spiel und verbindet (läuft ein anderes Spiel, nicht anbieten).
	var url := str(friend.get("join_url", ""))
	if url != "" and (cur.is_empty() or str(cur.get("appid", "")) == gid):
		v.add_child(_item("Spiel beitreten", "join", "über Steam", func() -> void:
			close()
			if is_instance_valid(guide):
				guide.close()
			var sf2: Dictionary = friend.get("steam", {}) if friend.get("steam") is Dictionary else {}
			var jf := sf2.duplicate()
			if jf.is_empty():
				jf = { "name": who, "game_id": gid, "game": str(friend.get("game", "")) }
			main.join_game(jf, url)
		))
	# Sprachkanal beitreten: über die offizielle Discord-Schnittstelle, Uzai bleibt vorn.
	var vid := str(friend.get("voice_id", ""))
	if vid != "" and not bool(friend.get("with_me", false)) and Voice.ready_():
		var ch := str(friend.get("voice", ""))
		v.add_child(_item("Sprachkanal beitreten", "headset", ch, func() -> void:
			close()
			Voice.join(vid)
			Toasts.show_toast("Wechsle zu %s" % (ch if ch != "" else "Sprachkanal"), "", "headset", { "ms": 1600, "quiet": true })
		, true))
	# Auch spielen: das Spiel des Freundes liegt in deiner Bibliothek.
	if cur.is_empty() and str(friend.get("game", "")) != "" and url == "":
		var mine := _owned(gid, str(friend.get("game", "")))
		if not mine.is_empty():
			v.add_child(_item("Auch spielen", "play", Library.display_title(mine), func() -> void:
				close()
				if is_instance_valid(guide):
					guide.close()
				main.launch(mine)
			, true))
	if not sf.is_empty():
		v.add_child(_item("Erfolge vergleichen", "trophy", "", func() -> void:
			close()
			main.open_compare_picker(sf)
		))
	# Discord ohne Nachrichten-Verbindung: sagen, wo man sie einrichtet.
	if is_discord and sf.is_empty() and (friend.get("dm", {}) as Dictionary).is_empty():
		var note := U.label("Nachrichten an Discord-Freunde: unter Einstellungen → Konten einrichten." if not DiscordChat.can_send()
				else "Nur mit Discord-Freunden kann Uzai Nachrichten tauschen.", "s", "muted", "regular")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(WIDTH - 48, 0)
		var pad := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			pad.add_theme_constant_override("margin_" + side, 14 if side in ["left", "right"] else 10)
		pad.add_child(note)
		v.add_child(pad)


## Zusammen hören einladen – nur, solange ein Spotify-Titel läuft. Die Einladung geht über den
## Chat in Uzai (Steam, sonst Discord-Direktnachricht); eine Spotify-Jam starten kann Uzai nicht
## (Spotify hat dafür keine Schnittstelle), ein kopierter Jam-Link geht aber mit.
func _together_item(v: VBoxContainer, sf: Dictionary) -> void:
	if not MusicShare.can_share():
		return
	var dm: Dictionary = friend.get("dm", {}) if friend.get("dm") is Dictionary else {}
	var kind := "steam" if not sf.is_empty() else ("discord" if not dm.is_empty() and DiscordChat.can_send() else "")
	if kind == "":
		return
	var target: Dictionary = sf if kind == "steam" else dm
	var item := _item("Zusammen hören einladen", "headset", "", func() -> void:
		close()
		MusicShare.invite(main, kind, target)
	)
	item.set_meta("uz_hint_a", "„%s“ zusammen hören" % str(Music.now.get("title", "")).left(30))
	v.add_child(item)


## Zu Remote Play Together einladen: im Steam-Spiel oder wenn Uzai das Spiel über den Spender
## gestartet hat (auch Emulatoren). Der Freund nimmt in Steam an; Uzai bleibt vorn.
func _remote_play_item(v: VBoxContainer, sf: Dictionary, online: bool) -> void:
	if sf.is_empty() or not online or not RemotePlay.can_invite():
		return
	v.add_child(_item("Zu Remote Play einladen", "controller", "Steam", func() -> void:
		close()
		RemotePlay.invite(sf)
	))


func _steam_friend(n: String) -> Dictionary:
	var k := People.name_key(n)
	for f in Social.steam_friends:
		if k != "" and People.name_key(str(f.get("name", ""))) == k:
			return f
	return {}


func _owned(gid: String, title: String) -> Dictionary:
	if gid != "":
		var g := Library.get_game("steam:" + gid)
		if not g.is_empty():
			return g
	var tk := People.title_key(title)
	if tk == "":
		return {}
	for g2 in Library.visible_games():
		if People.title_key(Library.display_title(g2)) == tk:
			return g2
	return {}


func handle(cmd: String) -> bool:
	match cmd:
		"lt", "rt":
			if is_instance_valid(guide) and guide.has_method("volume_step"):
				guide.call("volume_step", -1 if cmd == "lt" else 1)
			return true
		"lb", "rb", "x", "y":
			return true
		"guide":
			# Guide-Taste: Menü zu, der Guide schließt sich gleich mit.
			close()
			return false
	return false


func close() -> void:
	if is_instance_valid(source) and "hold" in source:
		source.set("hold", false)
	super()


func _exit_motion(tw: Tween) -> void:
	if is_instance_valid(_panel):
		tw.set_parallel(true)
		tw.tween_property(_panel, "scale", Vector2(0.97, 0.97), U.T_FAST)


func _refresh() -> void:
	if not member.is_empty() and not member.get("me", false):
		var m := Voice.member(str(member.get("id", "")))
		if m.is_empty():
			return
		if _vol_item:
			_vol_item.set_value("‹  %d %%  ›" % int(m.get("volume", 100)))
			_vol_item.frac = float(m.get("volume", 100)) / 200.0
			_vol_item.queue_redraw()
		if _mute_item:
			_mute_item.set_value("An" if m.get("local_mute", false) else "Aus")
	if _mic_item:
		_mic_item.set_value("Aus" if Mixer.mic_aus() else "An")
		_mic_item.set_icon("mic_off" if Mixer.mic_aus() else "mic")
	if _deaf_item:
		_deaf_item.set_value("Aus" if Voice.self_deaf else "An")
		_deaf_item.set_icon("headset_off" if Voice.self_deaf else "headset")


## roh: der Wert rechts ist ein Name (Spiel, Kanal) und wird nie übersetzt.
func _item(t: String, ic: String, v: String, cb: Callable, roh := false) -> Control:
	var it := _Item.new()
	it.text = t
	it.icon_name = ic
	it.value = v
	it.value_raw = roh
	it.on_a = cb
	return it


## Eine Zeile im Menü. Mit bar = true zeigt sie einen Schieberegler (links/rechts).
class _Item extends Control:
	const UU := preload("res://src/ui/u.gd")
	const LI := preload("res://src/ui/components/liste.gd")
	const ROW := 60
	var text := ""
	var icon_name := ""
	var value := ""
	var value_raw := false
	var bar := false
	var frac := 0.5
	var on_a: Callable
	var on_lr: Callable
	var _v: Label
	var _ic: TextureRect

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(WIDTH - 20, ROW + 26 if bar else ROW)
		var m := UU.margin(16, 0, 18, 0)
		m.anchor_right = 1.0
		m.offset_bottom = ROW
		add_child(m)
		var row := UU.hbox(14)
		m.add_child(row)
		_ic = UU.icon(icon_name, 24, "text")
		_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_ic)
		var l := UU.label(text, "m", "text", "ui_bold")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(l)
		_v = UU.label(value, "xs", "muted", "medium")
		_v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_v.clip_text = true
		_v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if value_raw:
			_v.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_v.custom_minimum_size.x = _wert_breite(value)
		_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(_v)
		focus_entered.connect(func() -> void:
			UU.etikett(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			UU.etikett(self, false)
			queue_redraw()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func set_value(v: String) -> void:
		value = v
		if _v:
			_v.text = v
			_v.custom_minimum_size.x = _wert_breite(v)

	## Platz für den Wert rechts: so breit wie der Text, der wirklich dasteht (übersetzt oder als Name), höchstens 150.
	func _wert_breite(v: String) -> float:
		return minf(150.0, UzTheme.font("medium").get_string_size(v if value_raw else tr(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 2)

	func set_icon(n: String) -> void:
		icon_name = n
		if _ic:
			_ic.texture = Icons.tex(n, 24)

	func activate() -> void:
		if on_a.is_valid():
			on_a.call()

	func nav_lr(d: int) -> bool:
		if on_lr.is_valid():
			on_lr.call(d)
			return true
		return false

	func _draw() -> void:
		var on := has_focus()
		# Derselbe Zeilen-Cursor wie in jeder Liste (liste.gd); im Rahmen-Cursor bleibt die Tinte hell.
		LI.zeilen_auswahl(self, 16)
		if bar:
			var ink := UzTheme.col("on_focus") if on and not UzTheme.cursor_frame() else UzTheme.col("text")
			var r := Rect2(54, ROW + 4, size.x - 54 - 20, 5)
			draw_style_box(UzTheme.box(Color(ink, 0.18), 3), r)
			draw_style_box(UzTheme.box(ink, 3), Rect2(r.position, Vector2(maxf(5, r.size.x * frac), r.size.y)))
			draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 1, r.position.y - 4, 2, 13), Color(ink, 0.4))


class _Sep extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(0, 11)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(12, 5, size.x - 24, 1), UzTheme.col("stroke"))


## Kleiner Pfeil vom Menü zur Kachel (nach oben, oder nach unten, wenn das Menü darüber liegt).
class _Caret extends Control:
	var color := Color.WHITE
	var down := false

	func _ready() -> void:
		size = Vector2(22, 11)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(0, 11), Vector2(11, 0), Vector2(22, 11)]) if not down else PackedVector2Array(
				[Vector2(0, 0), Vector2(11, 11), Vector2(22, 0)])
		draw_colored_polygon(pts, color)
