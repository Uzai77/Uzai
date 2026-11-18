extends "res://src/ui/layers/sheet.gd"
## Profil eines Discord-Freundes in Uzai: Bild, Name, @Nutzername und Zustand, oben eine Karte
## mit dem, was er gerade tut (Spiel mit Cover aus deiner Bibliothek, System und Dauer; Musik;
## Stream – siehe discord_activity.gd), Sprachkanal, gemeinsame Server – und von hier Nachricht,
## Anrufen, Sprachkanal beitreten, Auch spielen. Alles aus Uzais Discord-Anbindung (Social SDK,
## lokale Schnittstelle der Discord-App, Server-Widgets); Discord wird dafür nie nach vorn geholt.
## Über-mich- und Banner-Texte gibt Discord an Apps nicht heraus, darum fehlen sie – still.
## Für eine Freundschaftsanfrage (friend.request, request_flow.gd): wer es ist, gemeinsame Server
## und – bei einer Anfrage an dich – Annehmen und Ablehnen.

const Avatar := preload("res://src/ui/components/avatar.gd")
const People := preload("res://src/ui/components/guide_people.gd")
const FriendActions := preload("res://src/ui/layers/friend_actions.gd")
const DcActivity := preload("res://src/core/discord_activity.gd")

const STATE_TEXT := { "online": "Online", "away": "Abwesend", "idle": "Abwesend", "busy": "Bitte nicht stören",
	"dnd": "Bitte nicht stören", "offline": "Offline" }

var friend: Dictionary = {}     ## Eintrag aus dem Guide (People) oder ein Discord-Freund (DiscordChat)
const Main := preload("res://src/main.gd")
var main: Main


func _dm() -> Dictionary:
	if friend.get("dm") is Dictionary and not (friend.dm as Dictionary).is_empty():
		return friend.dm
	if bool(friend.get("dm", false)):
		return friend
	return DiscordChat.friend(str(friend.get("id", "")))


func build() -> void:
	var dm := _dm()
	var uname := str(dm.get("username", friend.get("username", "")))
	var st := str(friend.get("state", dm.get("state", "offline")))
	var st_text := "Streamt" if bool(dm.get("streaming", false)) else str(STATE_TEXT.get(st, "Online"))
	setup(str(friend.get("name", dm.get("name", "Discord-Freund"))), ("@" + uname + "  ·  " if uname != "" else "") + (st_text if not friend.has("request")
			else "Discord"), 840)
	heading_raw = true      # der Name der Person: nie übersetzen
	var av := Avatar.new()
	av.setup(str(friend.get("name", "")), str(friend.get("avatar", dm.get("avatar", ""))), People.dot(friend) if friend.has("rank") else st, 88)
	set_header_image(av)
	super()


func _row(k: String, t: String, icon: String) -> Control:
	var r = SettingRow.new()
	r.setup(k, t, "")
	r.icon_name = icon
	return r


func fill() -> void:
	if friend.get("request") is Dictionary:
		_fill_request(friend.request)
		return
	var dm := _dm()
	var who: Dictionary = dm if not dm.is_empty() else friend
	var act := DcActivity.of(who, DcActivity.widget_game(who, Social.discord))
	var mine := DcActivity.owned(str(act.title), Library.games) if str(act.kind) == "game" else {}
	if str(act.kind) != "":
		add_row(_ActCard.new().setup(act, mine))
		add_gap(10)
	if not mine.is_empty() and not Launcher.in_game:
		var p = _row("action", "Auch spielen", "play")
		p.value_text = Library.display_title(mine)
		p.on_activate = func() -> void:
			close()
			main.launch(mine)
		add_row(p)
	var vid := str(friend.get("voice_id", ""))
	if vid != "":
		var vc = _row("action", "Im Sprachkanal" if bool(friend.get("with_me", false)) else "Sprachkanal beitreten", "headset")
		vc.value_text = str(friend.get("voice", ""))
		if not bool(friend.get("with_me", false)):
			vc.on_activate = func() -> void:
				close()
				FriendActions.join_voice(main, vid, str(friend.get("voice", "")))
		add_row(vc)
	var servers := _servers()
	if not servers.is_empty():
		var sv = _row("info", "Gemeinsame Server", "discord")
		sv.value_text = ", ".join(PackedStringArray(servers))
		add_row(sv)
	add_gap()
	if not dm.is_empty():
		var m = _row("action", "Nachricht", "chat")
		var n := int(DiscordChat.unread.get(str(dm.get("id", "")), 0))
		m.value_text = U.plural(n, "neue Nachricht", "neue Nachrichten") if n > 0 else ""
		m.set_meta("uz_default", true)
		m.on_activate = func() -> void:
			close()
			main.open_discord_chat(dm)
		add_row(m)
		if Voice.ready_() or Voice.demo:
			var c = _row("action", "Anrufen", "phone")
			c.value_text = "über Discord"
			c.on_activate = func() -> void:
				close()
				FriendActions.call_discord(dm)
			add_row(c)
	else:
		add_label("Nachrichten und Anrufe gehen mit deinen Discord-Freunden, sobald unter Einstellungen → Konten „Discord-Nachrichten“ eingerichtet ist.", "s",
				"faint")


func _fill_request(r: Dictionary) -> void:
	var incoming := str(r.get("dir", "")) == "in"
	var info = _row("info", "Freundschaftsanfrage", "friends")
	info.value_text = "an dich" if incoming else "von dir gesendet, wartet auf Antwort"
	add_row(info)
	var servers := _servers()
	if not servers.is_empty():
		var sv = _row("info", "Gemeinsame Server", "discord")
		sv.value_text = ", ".join(PackedStringArray(servers))
		add_row(sv)
	if not incoming:
		add_gap()
		add_label("Sobald %s annimmt, steht die Person bei deinen Discord-Freunden. Zurückziehen geht in der Discord-App." % str(friend.get("name", "")), "s",
				"faint")
		return
	add_gap()
	var flow := load("res://src/ui/request_flow.gd")
	var done: Callable = friend.get("request_done", Callable())
	var after := func() -> void:
		close()
		if done.is_valid():
			done.call()
	var yes = _row("action", flow.accept_text(), "check")
	yes.set_meta("uz_default", true)
	yes.on_activate = func() -> void: flow.accept(r, after)
	add_row(yes)
	var no = _row("action", "Ablehnen", "close")
	no.on_activate = func() -> void: flow.decline(main, r, after)
	add_row(no)


## Server (aus den Widgets), in denen dieser Mensch auch ist.
func _servers() -> Array:
	var f := friend.duplicate()
	if str(_dm().get("username", "")) != "":
		f["username"] = str(_dm().username)
	return DcActivity.shared_servers(f, Social.discord)


## Karte „Spielt gerade“ oben im Profil: Cover (wenn das Spiel in deiner Bibliothek liegt, sonst
## ein ruhiges Zeichen), was und wo, seit wann. Nur zum Ansehen; die Dauer zählt mit.
class _ActCard extends PanelContainer:
	const UU := preload("res://src/ui/u.gd")
	const DA := preload("res://src/core/discord_activity.gd")
	const COVER := Vector2(84, 112)
	var act: Dictionary = {}
	var game: Dictionary = {}
	var _meta: Label
	var _t := 0.0

	func setup(a: Dictionary, g: Dictionary) -> Control:
		act = a
		game = g
		return self

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UzTheme.box(UzTheme.col("text", 0.06), UzTheme.r_cover() + 6)
		sb.content_margin_left = 16
		sb.content_margin_right = 20
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		add_theme_stylebox_override("panel", sb)
		var row := UU.hbox(18)
		add_child(row)
		var art := Control.new()
		art.custom_minimum_size = COVER if not game.is_empty() else Vector2(64, 64)
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(art)
		var glyph := UU.icon({ "music": "music", "stream": "live" }.get(str(act.kind), "games"), 30, "muted")
		glyph.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		art.add_child(glyph)
		art.draw.connect(func() -> void: art.draw_style_box(UzTheme.box(UzTheme.col("text", 0.07), UzTheme.r_cover()), Rect2(Vector2.ZERO, art.size)))
		if not game.is_empty():
			var img := UU.rounded_image(UzTheme.r_cover())
			UU.full_rect(img)
			img.visible = false
			art.add_child(img)
			var ref: WeakRef = weakref(img)
			Media.game_texture(game, "cover", func(t: Texture2D) -> void:
				var i: Variant = ref.get_ref()
				if i != null and t != null:
					(i as TextureRect).texture = t
					(i as TextureRect).visible = true
					glyph.visible = false
			)
		var col := UU.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		var kind_text: String = { "game": "Spielt gerade", "music": "Hört gerade", "stream": "Streamt gerade" }.get(str(act.kind), "")
		col.add_child(UU.label(kind_text, "xs", "ok" if str(act.kind) == "game" else "muted", "ui_bold"))
		if str(act.title) != "":
			var tl := UU.ellipsis(UU.label(str(act.title), "l", "text", "ui_bold"))
			tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Titel bleiben, wie sie sind
			col.add_child(tl)
		_meta = UU.ellipsis(UU.label("", "s", "muted", "regular"))
		col.add_child(_meta)
		_tick()

	## Die Dauer läuft mit (einmal je halbe Minute reicht).
	func _process(dt: float) -> void:
		_t += dt
		if _t >= 30.0:
			_t = 0.0
			_tick()

	func _tick() -> void:
		if is_instance_valid(_meta):
			_meta.text = DA.subline(act, int(Time.get_unix_time_from_system()))
			_meta.visible = _meta.text != ""
