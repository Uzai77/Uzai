extends "res://src/ui/layers/layer.gd"
## Chat mit einem Steam-Freund als Seitenleiste am rechten Rand (über dem Guide oder der
## Oberfläche). Der Verlauf als Sprechblasen in Gruppen: deine rechts in warmem Ton, die des
## Freundes links mit seinem Bild; Tage getrennt, die Uhrzeit nur am Ende einer Gruppe.
## Neue Nachrichten gleiten herein, gesendete springen aus dem Schreibfeld nach oben.
## ↑ wählt Nachrichten: A auf einem Link öffnet ihn in Uzai (Video, Musik, Shop, Beitreten, Bilder groß),
## Y schickt ihn als QR-Code aufs Handy (Bilder nicht). Unten das Schreibfeld: mit Maus und Tastatur tippt man direkt
## hinein, mit dem Controller öffnet A die Bildschirmtastatur.
## Gesendet wird direkt über Steam, Uzai bleibt vorn. Ohne Anmeldung zuerst der QR-Code.
## Angeheftet (angeheftet = true): dieselbe Ansicht als schmale Spalte ganz rechts, solange der Guide offen ist
## (guide.gd _pin_bauen) mit dem zuletzt geöffneten Gespräch; keine eigene Ebene, X schließt sie,
## bis wieder ein Chat aufgeht (pin_jetzt).

const Skeleton := preload("res://src/ui/components/skeleton.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const QrView := preload("res://src/ui/components/qr_view.gd")
const ChatLink := preload("res://src/ui/layers/chat_link.gd")
const Lang := preload("res://src/core/lang.gd")
const Zustand := preload("res://src/core/zustand.gd")

const WIDTH := 860.0
const BUBBLE_MAX := 540.0
const GROUP_SECS := 300
const POLL_SECS := 4.0           ## Discord: so oft nach neuen Nachrichten sehen
const WEEKDAYS := ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
const PIN_W := 500.0             ## angeheftet: so breit höchstens
const PIN_MIN_W := 380.0         ## … und schmaler gar nicht (sonst bleibt sie weg)
const PIN_MSGS := 30             ## angeheftet: nur die letzten Nachrichten
const PIN_SECS := 3600           ## so lange nach dem letzten Öffnen bzw. Senden gilt „gerade im Gespräch“

## Das zuletzt geöffnete Gespräch: { friend, kind, at } oder {} (mit X im Guide geschlossen).
static var _pin := {}

var friend: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var login_only := false          ## nur anmelden (aus den Einstellungen), danach schließen
var pending := ""                ## geht nach der Anmeldung raus (siehe Social.send_steam)
var kind := "steam"              ## steam oder discord (Direktnachrichten über das Social SDK)
var _relogin := false            ## alte Anmeldung darf nur lesen: einmal neu als Steam-App
var _panel: PanelContainer
var _body: Control
var _scroll: ScrollContainer
var _list: VBoxContainer
var _composer: Control
var _typing: Control
var _msgs: Array = []
var _sig := ""
var _timer: Timer
var _login: Dictionary = {}
## Anmeldung per QR-Code der Steam-App: "" (keine) · start (Code wird geholt) · poll (wartet auf die Bestätigung).
## „Neuer QR-Code“ beginnt neu; Schließen, Erfolg, Fehler und Ablauf führen zurück zu "".
const ZUSTAENDE_ANMELDUNG := { "*": [""], "": ["start"], "start": ["poll"], "poll": ["start"] }
var _login_state := "":
	set(neu):
		Zustand.wechsel("chat.steam_anmeldung", ZUSTAENDE_ANMELDUNG, _login_state, neu)
		_login_state = neu
var _qr = null
var _known := {}                 ## Schlüssel der schon gezeigten Nachrichten
var _sent := {}                  ## Text -> Zeit: gerade gesendet (nicht nochmal einblenden)
var _failed := {}                ## Text -> Zeit: nicht gesendet (bleibt sichtbar)
var _status_mine := ""           ## Hinweis unter deiner letzten Nachricht
var _filled_once := false
var angeheftet := false          ## als Spalte neben dem Guide statt als eigene Ebene
var bubble_max := BUBBLE_MAX
var _pin_mem: Control            ## angeheftet: zuletzt gewählt (rechts aus dem Guide wieder dorthin)


func _fid() -> String:
	return str(friend.get("id", ""))


## Takt der Abfrage: Steam seltener, solange jede Abfrage eine eigene Sitzung neben Steam am PC
## bräuchte (SteamChat.chat_poll).
func _poll_secs() -> float:
	return SteamChat.chat_poll() if kind == "steam" else POLL_SECS


## Woher die Nachrichten kommen: SteamChat oder DiscordChat (gleiche Form).
func _be() -> Node:
	return DiscordChat if kind == "discord" else SteamChat


## Gespräch für die Spalte neben dem Guide: { friend, kind } oder {} (keins offen gewesen,
## mit X geschlossen oder zu lange her).
static func pin_jetzt(now := -1) -> Dictionary:
	return _pin if pin_gilt(_pin, now if now >= 0 else int(Time.get_unix_time_from_system())) else {}


static func pin_gilt(pin: Dictionary, now: int) -> bool:
	return not pin.is_empty() and str((pin.get("friend", {}) as Dictionary).get("id", "")) != "" \
		and now - int(pin.get("at", 0)) <= PIN_SECS and now >= int(pin.get("at", 0)) - 60


## Ein Gespräch wurde geöffnet bzw. eine Nachricht ging raus: Es gilt als das laufende.
static func pin_merken(f: Dictionary, k: String, now := -1) -> void:
	_pin = { "friend": f.duplicate(), "kind": k, "at": now if now >= 0 else int(Time.get_unix_time_from_system()) }


## X in der Spalte: zu, bis wieder ein Chat aufgeht.
static func pin_loesen() -> void:
	_pin = {}


func build() -> void:
	if angeheftet:
		_build_pin()
		return
	if not login_only and _fid() != "":
		pin_merken(friend, kind)
	set_meta("uz_hint_b", "Zurück")
	set_meta("uz_hints", [["lt", ""], ["rt", "Blättern"]])
	# Seitenleiste wie die Freund-Optionen: rechts, volle Höhe, weicher Schatten, gleitet herein.
	_panel = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), 0)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 40
	sb.content_margin_bottom = 100
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 60
	sb.corner_radius_top_left = UzTheme.r_panel()
	sb.corner_radius_bottom_left = UzTheme.r_panel()
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -WIDTH
	add_child(_panel)
	var tw := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "offset_left", -WIDTH, U.T_MOVE).from(-WIDTH + 72)
	tw.tween_property(_panel, "offset_right", 0.0, U.T_MOVE).from(72.0)
	var col := U.vbox(20)
	_panel.add_child(col)
	if not login_only:
		col.add_child(_header())
	_body = U.vbox(14)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_timer = Timer.new()
	_timer.wait_time = _poll_secs()
	_timer.timeout.connect(func() -> void:
		# Läuft Steam am PC inzwischen (oder nicht mehr), gilt ab der nächsten Runde der neue Takt.
		_timer.wait_time = _poll_secs()
		_reload()
	)
	add_child(_timer)
	_be().messages.connect(func(fid: String) -> void:
		if fid == _fid():
			_reload()
	)
	_be().typing_changed.connect(func(fid: String, on: bool) -> void:
		if fid == _fid():
			_show_typing(on)
	)
	if kind == "discord":
		DiscordChat.set_open(_fid())
		DiscordChat.open_view = weakref(self)
		if DiscordChat.logged_in():
			_build_chat()
		else:
			_build_discord_setup()
	elif SteamChat.logged_in() and not login_only:
		_build_chat()
		# Für diesen Chat keine Pop-ups, solange er offen ist.
		SteamChat.open_chat = _fid()
		SteamChat.open_view = weakref(self)
		Notify.chat_opened(_fid())
	else:
		_build_login()


## Angeheftet: eine ruhige Fläche über die volle Höhe der Spalte, Kopf knapp, darunter derselbe
## Verlauf mit Schnellantworten und Schreibfeld. Den Fokus nimmt sie sich nicht (der Guide hat ihn).
func _build_pin() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_panel = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel())
	UzTheme.lift(sb, 3)
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		sb.set_content_margin(side, 26)
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	_panel.add_theme_stylebox_override("panel", sb)
	U.full_rect(_panel)
	_panel.set_meta("uz_group", "pin_chat")
	add_child(_panel)
	var col := U.vbox(14)
	_panel.add_child(col)
	col.add_child(_header())
	_body = U.vbox(12)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_timer = Timer.new()
	_timer.wait_time = _poll_secs()
	_timer.timeout.connect(_reload)
	add_child(_timer)
	_be().messages.connect(func(fid: String) -> void:
		if fid == _fid():
			_reload()
	)
	_be().typing_changed.connect(func(fid: String, on: bool) -> void:
		if fid == _fid():
			_show_typing(on)
	)
	if kind == "discord":
		if not DiscordChat.logged_in():
			_body.add_child(_note("Discord ist nicht verbunden."))
			return
		DiscordChat.set_open(_fid())
	elif not SteamChat.logged_in():
		_body.add_child(_note("Steam-Chat ist nicht angemeldet."))
		return
	else:
		SteamChat.open_chat = _fid()
	_build_chat()


## Rechts aus dem Guide: zurück zur zuletzt gewählten Stelle, sonst ins Schreibfeld.
func pin_fokus() -> Control:
	if is_instance_valid(_pin_mem) and _pin_mem.is_visible_in_tree() and is_ancestor_of(_pin_mem):
		return _pin_mem
	if is_instance_valid(_composer) and _composer.is_visible_in_tree():
		return _composer
	return Nav.default_in(self)


func pin_verlassen(f: Control) -> void:
	_pin_mem = f


## Jedes Element der Spalte: X schließt sie (vor den X-Aufgaben des Guides).
func _pin_tasten() -> void:
	if not angeheftet or not is_inside_tree():
		return
	for c in Nav.focusables(self):
		c.set_meta("uz_hint_x", "Chat schließen")
		c.set_meta("uz_on_x", close)


func _exit_motion(tw: Tween) -> void:
	tw.set_parallel(true)
	tw.tween_property(_panel, "offset_left", -WIDTH + 48, U.T_FAST)
	tw.tween_property(_panel, "offset_right", 48.0, U.T_FAST)


## Kopf: Bild mit Status, Name, was die Person gerade macht; rechts Beitreten und Profil.
func _header() -> Control:
	var head := U.hbox(18)
	var av := Avatar.new()
	av.setup(str(friend.get("name", "")), str(friend.get("avatar", "")), str(friend.get("state", "")), 48 if angeheftet else 64)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(av)
	var hv := U.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_l := U.ellipsis(U.label(str(friend.get("name", "Freund")), "l" if angeheftet else "xl", "text", "black"))
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Freundes
	hv.add_child(name_l)
	var line := status_line(friend)
	hv.add_child(U.ellipsis(U.label(line, "s", "ok" if str(friend.get("game", "")) != "" else "muted", "medium")))
	head.add_child(hv)
	var url := Social.join_url(friend)
	if angeheftet:
		return head
	if url != "":
		var j := U.button("Beitreten", "play", "flat")
		j.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		j.set_meta("uz_hint_a", "Mitspielen")
		j.pressed.connect(func() -> void:
			close()
			main.join_game(friend, url)
		)
		head.add_child(j)
	if _fid() != "":
		var p := U.button("", "user", "icon")
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.set_meta("uz_hint_a", "Profil")
		p.pressed.connect(func() -> void:
			var l = load("res://src/ui/layers/friend_profile.gd").new()
			l.friend = friend
			main.open_layer(l)
		)
		head.add_child(p)
	return head


## „Spielt ELDEN RING“, „Online“, „Zuletzt online vor 2 Std.“
static func status_line(f: Dictionary) -> String:
	var game := Library.friend_game_title(str(f.get("game", "")), str(f.get("game_id", "")))
	if game != "":
		return "Spielt " + game
	var st := str(f.get("state", ""))
	if st == "offline" or st == "":
		var last := int(f.get("last", 0))
		return ("Zuletzt online " + last_seen(last)) if last > 0 else "Offline"
	return str(
			{ "online": "Online", "away": "Abwesend", "idle": "Abwesend", "busy": "Beschäftigt", "dnd": "Bitte nicht stören", "game": "Im Spiel" }.get(st, "Online"))


## „vor 5 Min.“, „vor 2 Std.“, „gestern“, „vor 3 Tagen“, „am 12.03.2024“
static func last_seen(unix: int, now := 0) -> String:
	if now <= 0:
		now = int(Time.get_unix_time_from_system())
	var d := now - unix
	if d < 120:
		return "gerade eben"
	if d < 3600:
		return "vor %d Min." % (d / 60)
	if d < 86400:
		return "vor %d Std." % (d / 3600)
	if d < 2 * 86400:
		return "gestern"
	if d < 14 * 86400:
		return "vor %d Tagen" % (d / 86400)
	return "am " + U.date(unix)


# --- Chat ------------------------------------------------------------------------------

func _build_chat() -> void:
	U.clear(_body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = false
	_scroll.set_meta("uz_pad_v", 70.0)
	_body.add_child(_scroll)
	var pad := U.margin(4, 6, 4, 10)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pad)
	_list = U.vbox(0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_list)
	_list.add_child(_warte_verlauf())
	# No quick replies (message suggestions) above the input field.
	var bar := U.hbox(12)
	_body.add_child(bar)
	_composer = _Composer.new()
	_composer.view = self
	_composer.placeholder = "Nachricht an %s …" % str(friend.get("name", ""))
	_composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if angeheftet:
		_composer.custom_minimum_size.x = 200.0
	_composer.set_meta("uz_default", true)
	_composer.set_meta("uz_hint_a", "Schreiben")
	bar.add_child(_composer)
	var more := U.button("", "more", "icon")
	more.set_meta("uz_hint_a", "Mehr")
	more.pressed.connect(func() -> void: main.open_friend(friend, kind))
	bar.add_child(more)
	await get_tree().process_frame
	if is_instance_valid(_composer) and is_inside_tree() and not angeheftet:
		Nav.focus(_composer, true)
	_pin_tasten()
	_reload()
	_timer.start()
	if pending != "":
		var p := pending
		pending = ""
		_send(p)


## Der Verlauf kommt: zwei, drei Blasen als ruhige Platzhalter (ihre Seite, ihre Breite), kein Text.
func _warte_verlauf() -> Control:
	var v := U.vbox(14)
	var m := U.margin(8, 24, 8, 24)
	m.add_child(v)
	for b in [[Vector2(420, 54), false], [Vector2(300, 54), true], [Vector2(520, 54), false]]:
		var sk := Skeleton.new().setup(b[0], 18)
		sk.size_flags_horizontal = Control.SIZE_SHRINK_END if b[1] else Control.SIZE_SHRINK_BEGIN
		v.add_child(sk)
	return m


func _note(text: String) -> Control:
	var m := U.margin(8, 24, 8, 24)
	m.add_child(U.label(text, "m", "muted", "regular", true))
	return m


func _reload() -> void:
	if not is_inside_tree() or _list == null:
		return
	# Gelesen nur, was zu sehen ist: Liegt der Chat hinter dem Spiel (Guide zu), bleibt es ungelesen.
	var got := _with_echo(await _be().history(_fid(), 80, _be().chat_in_view(_fid())))
	if not is_inside_tree() or not is_instance_valid(_list):
		return
	if angeheftet and got.size() > PIN_MSGS:
		got = got.slice(got.size() - PIN_MSGS)
	var sig := verlauf_sig(got)
	if sig == _sig:
		return
	var bar := _scroll.get_v_scroll_bar()
	var at_bottom := _scroll.scroll_vertical >= int(bar.max_value - _scroll.size.y - 60)
	var first := not _filled_once
	_sig = sig
	var grew := got.size() > _msgs.size() and not first
	_msgs = got
	_fill()
	if grew and not _msgs.is_empty() and not bool(_msgs.back().me):
		Sfx.play("notify")
	await get_tree().process_frame
	await get_tree().process_frame
	if first or at_bottom or grew:
		_scroll_to_end(not first)


## Eigene Nachrichten, die Steam noch nicht im Verlauf zeigt (gerade gesendet, oder nicht
## gesendet), bleiben sichtbar statt kurz zu verschwinden.
func _with_echo(got: Array) -> Array:
	var now := int(Time.get_unix_time_from_system())
	var added := false
	for t in _sent.keys() + _failed.keys():
		var at := int(_failed.get(t, _sent.get(t, 0)))
		if not _failed.has(t) and now - at > 90:
			continue
		var found := false
		for m in got:
			if bool(m.get("me", false)) and str(m.get("text", "")) == str(t) and int(m.get("at", 0)) >= at - 30:
				found = true
				break
		if not found:
			got.append({ "me": true, "text": str(t), "at": at, "ordinal": 0 })
			added = true
	if added:
		got.sort_custom(func(a, b): return int(a.get("at", 0)) < int(b.get("at", 0)))
	return got


## Has the history changed so that it must be redrawn? Count, last message – and how many already have their
## images: Uzai fetches those later (DiscordChat.medien); without them in the comparison, „Nachricht ohne Text“
## stayed visible until a new message arrived.
static func verlauf_sig(got: Array) -> String:
	var mit_bild := got.filter(func(x: Dictionary) -> bool: return x.has("medien")).size()
	return "%d:%d:%s" % [got.size(), mit_bild, (str(got.back().get("at", 0)) + str(got.back().get("text", ""))) if not got.is_empty() else ""]


## Ein Bild in einer Blase ist da (die Blase wird höher): Stand man unten, bleibt man unten.
func bild_geladen() -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	if _scroll.scroll_vertical >= int(bar.max_value - _scroll.size.y - 500):
		await get_tree().process_frame
		if is_instance_valid(_scroll):
			_scroll_to_end(true)


static func msg_key(m: Dictionary) -> String:
	return "%d|%d|%s" % [int(m.get("at", 0)), int(bool(m.get("me", false))), str(m.get("text", "")).md5_text().left(10)]


## Aufbau der Liste ohne Oberfläche (auch für die Tests): Tagestrenner und Nachrichten mit
## first/last (Anfang und Ende einer Gruppe: gleiche Person, höchstens 5 Minuten Abstand).
static func layout(msgs: Array, now: int, bias := 0) -> Array:
	var out: Array = []
	var last_day := ""
	for i in msgs.size():
		var m: Dictionary = msgs[i]
		var day := day_label(int(m.get("at", 0)), now, bias)
		var new_day := day != last_day
		if new_day:
			out.append({ "type": "day", "text": day })
			last_day = day
		var me := bool(m.get("me", false))
		var prev: Dictionary = msgs[i - 1] if i > 0 else {}
		var nxt: Dictionary = msgs[i + 1] if i + 1 < msgs.size() else {}
		var first := new_day or prev.is_empty() or bool(prev.get("me", false)) != me or int(m.get("at", 0)) - int(prev.get("at", 0)) >= GROUP_SECS
		var last := nxt.is_empty() or bool(nxt.get("me", false)) != me or int(nxt.get("at", 0)) - int(m.get("at", 0)) >= GROUP_SECS \
			or day_label(int(nxt.get("at", 0)), now, bias) != day
		out.append({ "type": "msg", "i": i, "first": first, "last": last })
	return out


## „Heute“, „Gestern“, Wochentag (diese Woche), „12. Oktober“, ältere mit Jahr.
static func day_label(at: int, now: int, bias := 0) -> String:
	var d := Time.get_date_dict_from_unix_time(at + bias)
	var today_start := int((now + bias) / 86400) * 86400
	var day_start := int((at + bias) / 86400) * 86400
	var diff := (today_start - day_start) / 86400
	if diff <= 0:
		return "Heute"
	if diff == 1:
		return "Gestern"
	if diff < 7:
		return WEEKDAYS[int(d.weekday)]
	var n := Time.get_date_dict_from_unix_time(now + bias)
	return Lang.date_text(int(d.day), int(d.month), 0 if int(d.year) == int(n.year) else int(d.year))


func _fill() -> void:
	var keep := ""
	var f := Nav.focused()
	if f and is_instance_valid(_list) and _list.is_ancestor_of(f):
		keep = str(f.get_meta("uz_key", ""))
	U.clear(_list)
	_typing = null
	if _msgs.is_empty():
		_list.add_child(_note(_be().error if _be().error != "" else "Noch keine Nachrichten. Schreib die erste."))
		_list.add_child(_typing_row())
		_filled_once = true
		return
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var now := int(Time.get_unix_time_from_system())
	var fresh := {}
	var known := {}
	for m in _msgs:
		var k := msg_key(m)
		known[k] = true
		if _filled_once and not _known.has(k) and not _just_sent(m):
			fresh[k] = true
	var last_mine := -1
	for i in _msgs.size():
		if bool(_msgs[i].me):
			last_mine = i
	var refocus: Control = null
	var rows := layout(_msgs, now, bias)
	for e in rows:
		if str(e.type) == "day":
			_list.add_child(_day_sep(str(e.text), _list.get_child_count() > 0))
			continue
		var i := int(e.i)
		var m: Dictionary = _msgs[i]
		var me := bool(m.me)
		var k := msg_key(m)
		if bool(e.first) and _list.get_child_count() > 0:
			_list.add_child(U.spacer(0, 14, false))
		elif not bool(e.first):
			_list.add_child(U.spacer(0, 4, false))
		var row := _bubble_row(m, me, bool(e.first), bool(e.last))
		_list.add_child(row)
		var bub: Control = row.get_meta("bubble")
		bub.set_meta("uz_key", "msg:" + k)
		if keep != "" and keep == "msg:" + k:
			refocus = bub
		if bool(e.last):
			var t := _time(int(m.at))
			if me and i == last_mine and _status_mine != "":
				t += "  ·  " + tr(_status_mine)
			_list.add_child(_time_row(t, me))
		if fresh.has(k):
			_pop_in(row, me)
	var bilder := _bilder_hinweis()
	if bilder:
		_list.add_child(bilder)
	_list.add_child(_typing_row())
	_known = known
	_filled_once = true
	_pin_tasten()
	if refocus:
		Nav.focus(refocus, true)
	elif keep != "" and is_instance_valid(_composer):
		Nav.focus(_composer, true)


## Discord-Bilder, die nur als Karte stehen (das Social SDK nennt keine Adresse): einmal das Lesen über die Discord-App
## freigeben (Voice.msg_scope_anfragen verbindet dafür kurz neu), dann stehen sie als Bild da.
func _bilder_hinweis() -> Control:
	if _be() != DiscordChat or not Voice.ready_() or Voice.granted.has(Voice.MSG_SCOPE):
		return null
	if not _msgs.any(func(x: Dictionary) -> bool: return x.has("anhang") and str(x.anhang.get("art", "")) in ["bild", "video", "datei", "anhang", "einbettung"]):
		return null
	var row := U.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if Voice.has_msg_scope():
		row.add_child(U.label("Bilder erscheinen nach dem nächsten Start von Uzai.", "s", "muted", "regular"))
		return row
	var b := U.button("Bilder anzeigen", "image", "flat")
	b.set_meta("uz_hint_a", "In Discord freigeben")
	b.pressed.connect(func() -> void:
		Voice.msg_scope_anfragen()
		Toasts.show_toast("In Discord bestätigen", "Gleich öffnet die Discord-App ein Fenster: „Autorisieren“ – danach zeigt Uzai die Bilder.", "image",
				{ "ms": 6000 }))
	row.add_child(b)
	return row


func _just_sent(m: Dictionary) -> bool:
	if not bool(m.get("me", false)):
		return false
	var t := str(m.get("text", ""))
	return _sent.has(t) and absi(int(_sent[t]) - int(m.get("at", 0))) < 90


func _day_sep(text: String, gap: bool) -> Control:
	var m := U.margin(0, 26 if gap else 4, 0, 10)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(cc)
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("text", 0.06), 999)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(U.label(text, "16", "muted", "medium"))
	cc.add_child(p)
	return m


func _time_row(t: String, me: bool) -> Control:
	var m := U.margin(0 if me else 52, 6, 4, 0)
	var l := U.label(t, "16", "faint", "medium")
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Uhrzeit (der Stand dahinter ist schon übersetzt)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if me else HORIZONTAL_ALIGNMENT_LEFT
	m.add_child(l)
	return m


## Eine Zeile: Bild des Freundes am Ende seiner Gruppe (sonst Platz), dann die Blase.
func _bubble_row(m: Dictionary, me: bool, first: bool, last: bool) -> Control:
	var row := U.hbox(12)
	if me:
		row.add_child(U.spacer())
	else:
		if last:
			var av := Avatar.new()
			av.setup(str(friend.get("name", "")), str(friend.get("avatar", "")), "", 40)
			av.size_flags_vertical = Control.SIZE_SHRINK_END
			row.add_child(av)
		else:
			row.add_child(U.spacer(40, 0, false))
	var b := _Bubble.new()
	b.view = self
	b.me = me
	b.first = first
	b.tail = last
	var text := str(m.get("text", ""))
	var links := ChatLink.find_links(text)
	var shown := text
	if not links.is_empty():
		b.link = ChatLink.link_info(str(links[0].url))
		# Der Link selbst steht unten als Karte; im Text nur kurz.
		for i in range(links.size() - 1, -1, -1):
			var l: Dictionary = links[i]
			var rep := "" if i == 0 and int(l.end) >= text.strip_edges().length() else ChatLink.short_url(str(l.url), 34)
			shown = shown.substr(0, int(l.start)) + rep + shown.substr(int(l.end))
		shown = shown.strip_edges()
	b.text = shown
	if m.get("anhang") is Dictionary:
		b.anhang = m.anhang
	# Discord: Bild bzw. Video mit Adresse über die Discord-App (DiscordChat.medien) – dann steht es selbst da.
	if m.get("medien") is Array and not (m.medien as Array).is_empty():
		var it: Dictionary = m.medien[0]
		var bild := str(it.get("art", "")) == "bild"
		b.link = { "kind": "bild" if bild else "video", "url": str(it.url), "host": "Discord", "id": "",
			"label": "Bild" if bild else "Video", "action": "Ansehen" if bild else "Aufs Handy", "icon": "image" if bild else "video",
			"titel": str(friend.get("name", "")) if not me else "",
			"bilder": (m.medien as Array).filter(func(x: Dictionary) -> bool: return str(x.get("art", "")) == "bild").map(
					func(x: Dictionary) -> String: return str(x.url)) }
		b.anhang = {}
	elif str(b.link.get("kind", "")) == "bild":
		b.link["titel"] = str(friend.get("name", "")) if not me else ""
	b.set_meta("uz_hint_a", str(b.link.get("action", "Öffnen")) if not b.link.is_empty() else "Antworten")
	# Images: A shows them large in Uzai – no „Aufs Handy“ (send to phone). Other links keep Y for the phone.
	if not b.link.is_empty() and str(b.link.get("kind", "")) != "bild":
		b.set_meta("uz_hint_y", "Aufs Handy")
		var li: Dictionary = b.link
		b.set_meta("uz_on_y", func() -> void: ChatLink.show_qr(main, li))
	row.add_child(b)
	if not me:
		row.add_child(U.spacer())
	row.set_meta("bubble", b)
	return row


## Neue Nachricht: gleitet aus ihrer Richtung herein und federt minimal nach.
func _pop_in(row: Control, me: bool) -> void:
	var b: Control = row.get_meta("bubble")
	b.modulate.a = 0.0
	b.scale = Vector2(0.9, 0.9)
	var me_ref: WeakRef = weakref(b)
	b.resized.connect(func() -> void:
		var bb: Variant = me_ref.get_ref()
		if bb != null:
			(bb as Control).pivot_offset = Vector2((bb as Control).size.x if me else 0.0, (bb as Control).size.y)
	)
	var t := U.tw(b, "uz_pop").set_parallel(true)
	t.tween_property(b, "modulate:a", 1.0, U.T_BASE).set_delay(0.03)
	t.tween_property(b, "scale", Vector2.ONE, U.T_FOCUS + 0.08).set_trans(Tween.TRANS_CUBIC).set_delay(0.03)


func _typing_row() -> Control:
	var row := U.hbox(12)
	var av := Avatar.new()
	av.setup(str(friend.get("name", "")), str(friend.get("avatar", "")), "", 40)
	av.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(av)
	row.add_child(_Dots.new())
	row.add_child(U.spacer())
	var m := U.margin(0, 14, 0, 0)
	m.add_child(row)
	m.visible = _be().is_typing(_fid())
	_typing = m
	return m


func _show_typing(on: bool) -> void:
	if not is_instance_valid(_typing) or _typing.visible == on:
		return
	var at_bottom := _scroll.scroll_vertical >= int(_scroll.get_v_scroll_bar().max_value - _scroll.size.y - 60)
	_typing.visible = on
	if on:
		_typing.modulate.a = 0.0
		U.tw(_typing, "uz_typ").tween_property(_typing, "modulate:a", 1.0, U.T_BASE)
		if at_bottom:
			await get_tree().process_frame
			await get_tree().process_frame
			_scroll_to_end(true)


func _scroll_to_end(smooth: bool) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var target := int(_scroll.get_v_scroll_bar().max_value)
	if smooth:
		U.tw(_scroll, "uz_scroll").tween_property(_scroll, "scroll_vertical", target, U.T_MOVE)
	else:
		_scroll.scroll_vertical = target


func scroll_by(dy: int) -> void:
	if _scroll == null:
		return
	var to := clampi(_scroll.scroll_vertical + dy, 0, int(_scroll.get_v_scroll_bar().max_value))
	U.tw(_scroll, "uz_scroll").tween_property(_scroll, "scroll_vertical", to, U.T_BASE)


func write() -> void:
	_be().send_typing(_fid())
	main.open_keyboard("Nachricht an " + str(friend.get("name", "")), "", func(t: String) -> void:
		if t.strip_edges() != "":
			_send(t.strip_edges())
	)


func open_link(li: Dictionary) -> void:
	ChatLink.open_in_uzai(main, li)


## Alle Blasen in Lesereihenfolge.
func _bubbles() -> Array:
	var out: Array = []
	if is_instance_valid(_list):
		for row in _list.get_children():
			if row.has_meta("bubble"):
				out.append(row.get_meta("bubble"))
	return out


## ↑/↓ auf einer Blase: genau eine Nachricht weiter (nicht quer über die Seiten springen).
## Unter der letzten geht es zum Schreibfeld; über der ersten entscheidet Nav (Kopf).
func step_bubble(b: Control, d: int) -> bool:
	var all := _bubbles()
	var j := all.find(b) + d
	if j >= 0 and j < all.size():
		Nav.focus(all[j])
		return true
	if j >= all.size() and is_instance_valid(_composer):
		Nav.focus(_composer)
		return true
	return false


## ↑ vom Schreibfeld: zur letzten Nachricht.
func to_last_bubble() -> bool:
	var all := _bubbles()
	if all.is_empty():
		return false
	Nav.focus(all.back())
	return true


func _send(text: String) -> void:
	if not is_inside_tree() or _list == null:
		return
	if kind == "discord" and not DiscordChat.can_send():
		Toasts.show_toast("Nicht gesendet", DiscordChat.error if DiscordChat.error != "" else "Discord-Nachrichten sind noch nicht verbunden.", "warning")
		return
	if kind == "steam" and not SteamChat.can_send():
		SteamChat._log("Senden: Anmeldung darf nur lesen – QR-Code für die Steam-App")
		# Die bisherige Anmeldung (Browser-Art) darf nur lesen. Gleich hier einmal neu per QR als
		# Steam-App anmelden; danach geht die Nachricht von selbst raus. Nichts verlässt Uzai.
		pending = text
		_relogin = true
		_build_login()
		return
	# Sofort zeigen (springt aus dem Schreibfeld nach oben), Steam bestätigt im Hintergrund.
	var at := int(Time.get_unix_time_from_system())
	_status_mine = "Wird gesendet …"
	_failed.erase(text)
	_msgs.append({ "me": true, "text": text, "at": at, "ordinal": 0 })
	_fill()
	# Ab jetzt gilt die Nachricht als gesendet: Steams eigene Kopie (andere Uhrzeit) springt
	# nicht noch einmal herein, und bis Steam sie liefert, bleibt sie sichtbar.
	_sent[text] = at
	await get_tree().process_frame
	_scroll_to_end(true)
	Sfx.play("select")
	var err: String = await _senden(_be(), _fid(), text)
	if not is_inside_tree():
		return
	if err != "":
		_status_mine = "Nicht gesendet"
		_failed[text] = at
		_fill()
		return
	_status_mine = "Gesendet"
	pin_merken(friend, kind)
	_sig = ""
	_reload()


## Senden und einen Fehlschlag melden. Statisch: Wer eine Schnellantwort schickt und den Chat gleich schließt, erführe
## sonst nie, dass sie nicht ankam – die Meldung hinge an der geschlossenen Ansicht.
static func _senden(be: Node, fid: String, text: String) -> String:
	var err: String = await be.send(fid, text)
	if err != "":
		Toasts.show_toast("Nicht gesendet", err, "warning")
	return err


func handle(cmd: String) -> bool:
	match cmd:
		"lt":
			scroll_by(-480)
			return true
		"rt":
			scroll_by(480)
			return true
	return false


static func _time(at: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(at + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%02d:%02d" % [t.hour, t.minute]


# --- Discord: noch nicht verbunden -------------------------------------------------------

## Discord-Nachrichten sind (noch) nicht da: sagen, woran es liegt, und den einen Schritt anbieten.
func _build_discord_setup() -> void:
	U.clear(_body)
	var col := U.vbox(18)
	_body.add_child(col)
	col.add_child(U.label("Discord-Nachrichten einrichten", "xl", "text", "black", true))
	var why := DiscordChat.error if DiscordChat.error != "" else "Discord-Nachrichten sind gerade nicht verbunden."
	var p := U.label(why, "m", "muted", "regular", true)
	p.custom_minimum_size = Vector2(700, 0)
	col.add_child(p)
	var b: Button
	if DiscordChat.state == "freigabe":
		b = U.button("In Discord freigeben", "discord", "primary")
		b.pressed.connect(func() -> void:
			DiscordChat.authorize()
			Toasts.show_toast("Bitte in Discord bestätigen", "Danach geht es hier weiter.", "discord")
		)
	else:
		b = U.button("Einstellungen öffnen", "settings", "primary")
		b.pressed.connect(func() -> void:
			close()
			main.goto("settings", "konten")
		)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.set_meta("uz_default", true)
	col.add_child(b)
	DiscordChat.changed.connect(func() -> void:
		if is_inside_tree() and kind == "discord" and DiscordChat.logged_in() and _list == null:
			_build_chat()
	)
	await get_tree().process_frame
	if is_inside_tree():
		Nav.focus(b, true)


# --- Anmeldung -------------------------------------------------------------------------

func _build_login() -> void:
	U.clear(_body)
	var col := U.vbox(18)
	_body.add_child(col)
	col.add_child(U.label("Neu bei Steam anmelden" if _relogin else "Mit Steam anmelden", "xl", "text", "black", true))
	var p := U.label(
			"Zum Senden ist eine neue Anmeldung nötig."
			if _relogin else "Code mit der Steam-App scannen.", "m", "muted",
			"regular", true)
	p.custom_minimum_size = Vector2(700, 0)
	col.add_child(p)
	col.add_child(U.spacer(0, 6, false))
	var row := U.hbox(34)
	col.add_child(row)
	var qr_frame := PanelContainer.new()
	qr_frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("text", 0.06), UzTheme.r_panel()))
	qr_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	qr_frame.custom_minimum_size = Vector2(320, 320)
	qr_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(qr_frame)
	var steps := U.vbox(16)
	steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steps.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(steps)
	var n := 1
	for s in ["Steam-App öffnen", "Steam Guard öffnen", "„QR-Code scannen“ wählen",
			"Anmeldung bestätigen"]:
		steps.add_child(_step(n, str(s)))
		n += 1
	var st := U.label("QR-Code wird geholt …", "m", "accent", "medium", true)
	col.add_child(U.spacer(0, 4, false))
	col.add_child(st)
	if pending != "":
		var w := U.label("Wird danach gesendet: „%s“" % ChatLink.short_url(pending, 70), "s", "muted", "regular", true)
		col.add_child(w)
	var again := U.button("Neuer QR-Code", "refresh", "primary")
	again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	again.set_meta("uz_default", true)
	again.pressed.connect(func() -> void: _start_login(qr_frame, st))
	col.add_child(again)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	Nav.focus(again, true)
	_start_login(qr_frame, st)


func _step(n: int, text: String) -> Control:
	var h := U.hbox(16)
	var num := PanelContainer.new()
	num.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("text", 0.08), 999))
	num.custom_minimum_size = Vector2(38, 38)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := U.label(str(n), "s", "text", "ui_bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_child(l)
	h.add_child(num)
	var t := U.label(text, "m", "text", "regular", true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	return h


## Statt eines leeren weißen Felds: ruhiger Platzhalter mit Symbol, bis der Code da ist.
func _qr_placeholder(frame: PanelContainer, icon_name: String) -> void:
	U.clear(frame)
	frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("text", 0.06), UzTheme.r_panel()))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(U.icon(icon_name, 64, "faint"))
	frame.add_child(cc)


func _start_login(frame: PanelContainer, st: Label) -> void:
	_qr_placeholder(frame, "qr")
	st.text = "QR-Code wird geholt …"
	U.set_label_color(st, "accent")
	_login_state = "start"
	var info := await SteamChat.login_start()
	if not is_inside_tree():
		return
	if not info.ok:
		st.text = str(info.error)
		U.set_label_color(st, "warn")
		_qr_placeholder(frame, "warning")
		_login_state = ""
		return
	_login = info
	U.clear(frame)
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.r_panel()))
	_qr = QrView.new()
	_qr.setup(str(info.url), 300)
	var cc := CenterContainer.new()
	cc.add_child(_qr)
	frame.add_child(cc)
	frame.modulate.a = 0.0
	create_tween().tween_property(frame, "modulate:a", 1.0, U.T_BASE)
	st.text = "Warten auf Bestätigung …"
	if str(info.get("warning", "")) != "":
		st.text = str(info.warning)
		U.set_label_color(st, "warn")
	_login_state = "poll"
	var shown := str(info.url)
	var t0 := Time.get_ticks_msec()
	while is_inside_tree() and _login_state == "poll" and _login == info:
		await get_tree().create_timer(maxf(2.0, float(info.interval))).timeout
		if not is_inside_tree() or _login != info:
			return
		var res := await SteamChat.login_poll(info)
		if res == "ok":
			_login_state = ""
			Toasts.show_toast("Bei Steam angemeldet", SteamChat.account_name(), "check", { "sound": "select" })
			if login_only:
				close()
			else:
				_build_chat()
			return
		if str(info.url) != shown and is_instance_valid(_qr):
			shown = str(info.url)
			_qr.setup(shown, 300)
		if res == "expired" or Time.get_ticks_msec() - t0 > 170000:
			st.text = "Der QR-Code ist abgelaufen. „Neuer QR-Code“ holt einen frischen."
			U.set_label_color(st, "muted")
			_qr_placeholder(frame, "refresh")
			_login_state = ""
			return


func close() -> void:
	_login_state = ""
	_login = {}
	if kind == "discord":
		DiscordChat.set_open("")
	_release_open()
	if angeheftet:
		# Schon am Gehen (B zweimal kurz hintereinander): nicht noch einmal melden und ausblenden.
		if _closing:
			return
		# Zu, bis wieder ein Chat aufgeht; der Guide holt den Fokus zurück (closed).
		pin_loesen()
		_closing = true
		Sfx.play("back")
		closed.emit()
		var tw := U.im_tempo(create_tween()).set_parallel(true)
		tw.tween_property(self, "modulate:a", 0.0, U.T_WEG)
		tw.tween_property(self, "position:x", position.x + 24.0, U.T_WEG)
		tw.chain().tween_callback(queue_free)
		return
	super()


func _release_open() -> void:
	if SteamChat.open_chat == _fid() and _fid() != "":
		SteamChat.open_chat = ""
		SteamChat.open_view = null
	if kind == "discord" and DiscordChat.open_view != null and DiscordChat.open_view.get_ref() == self:
		DiscordChat.open_view = null
	# Angeheftet geht die Spalte mit dem Guide: Discord wieder Pop-ups für dieses Gespräch.
	if angeheftet and kind == "discord" and DiscordChat.open_chat == _fid() and _fid() != "":
		DiscordChat.set_open("")


## Wieder vorn (Guide über dem Spiel geöffnet, Fenster zurück): Verlauf frisch und gelesen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_inside_tree() and _list != null:
		_reload.call_deferred()


func _exit_tree() -> void:
	_release_open()
	# Die QR-Anmeldung gehört zur eigenen Ebene (die angeheftete Spalte meldet nie an): kein alter Stand im Fehlerbericht.
	if not angeheftet:
		Zustand.vergessen("chat.steam_anmeldung")


## Eine Sprechblase. Deine in warmem Ton, die des Freundes in Glas; die Ecke zur Person hin
## wird am Ende einer Gruppe spitzer. Gewählt: heller Ring mit Gold-Glimmen (wie Kacheln).
## Ein Link erscheint unten als Karte (YouTube mit Vorschaubild).
class _Bubble extends PanelContainer:
	const UU := preload("res://src/ui/u.gd")
	const R := 22
	var view
	var me := false
	var first := true
	var tail := true
	var text := ""
	var link: Dictionary = {}
	var anhang: Dictionary = {}     ## Discord: Anhang ohne Adresse (Art, Dateiname, Anzahl) – DiscordChat.anhang
	var _thumb: TextureRect

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 20
		e.content_margin_right = 20
		e.content_margin_top = 12
		e.content_margin_bottom = 13
		add_theme_stylebox_override("panel", e)
		var col := UU.vbox(10)
		add_child(col)
		var inner := float(view.bubble_max) - 40.0
		if text != "":
			var l := UU.label(text, "m", "text", "regular", true)
			# Die Nachricht steht da, wie sie geschrieben wurde – nie durch die Übersetzung (aus „Später?“ eines
			# Freundes würde im Englischen sonst „Later?“).
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			var w := UzTheme.font("regular").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
			l.custom_minimum_size = Vector2(minf(w + 4.0, inner), 0)
			if not link.is_empty():
				l.custom_minimum_size.x = maxf(l.custom_minimum_size.x, minf(340.0, inner))
			col.add_child(l)
		if not link.is_empty():
			col.add_child(_card())
		if not anhang.is_empty():
			col.add_child(_anhang_karte())
		if text == "" and link.is_empty() and anhang.is_empty():
			col.add_child(UU.label("Nachricht ohne Text", "s", "muted", "regular"))
		focus_entered.connect(func() -> void:
			UU.focus_anim(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			UU.focus_anim(self, false)
			queue_redraw()
		)
		gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event()
			elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				view.scroll_by(-120 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 120)
		)

	## Karte für den Link: Symbol, wohin er führt, was A tut. YouTube zeigt das Vorschaubild, ein Bild sich selbst.
	func _card() -> Control:
		var v := UU.vbox(0)
		v.custom_minimum_size.x = 340
		var bild := str(link.get("kind", "")) == "bild"
		if str(link.get("kind", "")) == "youtube" or bild:
			_thumb = TextureRect.new()
			_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			# Ein Bild ganz (nichts abgeschnitten), ein Vorschaubild füllt die Fläche.
			_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if bild else TextureRect.STRETCH_KEEP_ASPECT_COVERED
			_thumb.custom_minimum_size = Vector2(340, 240) if bild else Vector2(340, 191)
			_thumb.material = UU.rounded_mat(12.0)
			_thumb.resized.connect(func() -> void: (_thumb.material as ShaderMaterial).set_shader_parameter("size", _thumb.size))
			_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_thumb.visible = false
			v.add_child(_thumb)
			var me_ref: WeakRef = weakref(self)
			# Nur Adressen bekannter Bilddienste (ChatLink.bild_url): nie den eigenen PC oder das Heimnetz.
			var quelle := str(link.url) if bild else YouTube.thumb_for(str(link.id), true)
			Media.url_texture(quelle, 900 if bild else 640, func(t: Texture2D) -> void:
				var b: Variant = me_ref.get_ref()
				if b != null and t != null:
					b.call("_show_thumb", t)
			)
		# An image stands on its own – without a line below it showing the file name and „A Aufs Handy“.
		if bild:
			return v
		var p := PanelContainer.new()
		var sb := UzTheme.box(Color(0, 0, 0, 0.22), 14)
		sb.content_margin_left = 14
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 11
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UU.hbox(14)
		p.add_child(h)
		var ic := UU.icon(str(link.get("icon", "link")), 26, "text")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var tv := UU.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UU.ellipsis(UU.label(str(link.get("label", "")) if str(link.get("label", "")) != "" else str(link.get("host", "")), "s", "text", "ui_bold")))
		var sub := str(link.get("host", "")) if str(link.get("kind", "")) == "web" else ("A " + str(link.get("action", "")) + " · in Uzai")
		if str(link.get("kind", "")) == "web":
			sub = ChatLink.short_url(str(link.get("url", "")), 40)
		tv.add_child(UU.ellipsis(UU.label(sub, "16", "muted", "regular")))
		h.add_child(tv)
		v.add_child(p)
		return v

	## Anhang aus Discord: Art und Dateiname. Ansehen geht nur in Discord – das SDK gibt die Datei nicht heraus.
	func _anhang_karte() -> Control:
		var p := PanelContainer.new()
		var sb := UzTheme.box(Color(0, 0, 0, 0.22), 14)
		sb.content_margin_left = 14
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 11
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.custom_minimum_size.x = 300
		var h := UU.hbox(14)
		p.add_child(h)
		var art := str(anhang.get("art", "datei"))
		var symbol := { "bild": "image", "video": "video", "sprache": "mic", "sticker": "spark", "umfrage": "list" }
		var ic := UU.icon(str(symbol.get(art, "link")), 26, "text")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var tv := UU.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UU.label(DiscordChat.anhang_text(anhang), "s", "text", "ui_bold"))
		var titel := str(anhang.get("titel", ""))
		var unter := UU.label(titel if titel != "" else "In Discord ansehen", "16", "muted", "regular")
		unter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if titel != "" else Node.AUTO_TRANSLATE_MODE_INHERIT
		tv.add_child(UU.ellipsis(unter))
		h.add_child(tv)
		return p

	func _show_thumb(t: Texture2D) -> void:
		if not is_instance_valid(_thumb):
			return
		# Bild: so hoch, wie es sein Format verlangt (kein schwarzer Rand oben und unten), in Grenzen.
		if str(link.get("kind", "")) == "bild" and t.get_width() > 0:
			var h := clampf(340.0 * float(t.get_height()) / float(t.get_width()), 120.0, 440.0)
			var w := 340.0 if h < 440.0 else clampf(440.0 * float(t.get_width()) / float(t.get_height()), 160.0, 340.0)
			_thumb.custom_minimum_size = Vector2(w, h)
			_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			if view != null and view.has_method("bild_geladen"):
				view.bild_geladen()
		_thumb.texture = t
		_thumb.visible = true
		_thumb.modulate.a = 0.0
		create_tween().tween_property(_thumb, "modulate:a", 1.0, UU.T_BASE)

	func activate() -> void:
		if not link.is_empty():
			view.open_link(link)
		else:
			view.write()

	func activate_sound() -> String:
		return "open"

	func nav_ud(d: int) -> bool:
		return view.step_bubble(self, d)

	func _bg() -> Color:
		return UzTheme.col("accent", 0.2) if me else UzTheme.col("text", 0.075)

	func _shape(sb: StyleBoxFlat, grow := 0) -> void:
		var near := 8 + grow
		var far := R + grow
		sb.corner_radius_top_left = far if me or first else near
		sb.corner_radius_top_right = far if not me or first else near
		sb.corner_radius_bottom_left = far if me else (5 + grow if tail else near)
		sb.corner_radius_bottom_right = far if not me else (5 + grow if tail else near)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := UzTheme.box(_bg(), R)
		_shape(sb)
		draw_style_box(sb, r)
		var f: float = get_meta("uz_f", 0.0) if has_meta("uz_f") else 0.0
		if f > 0.01:
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.set_border_width_all(3)
			ring.border_color = Color(UzTheme.col("focus"), f)
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				ring.set_expand_margin(side, 4)
			ring.shadow_color = Color(UzTheme.col("accent"), 0.32 * f * UzTheme.glow_k())
			ring.shadow_size = int(14 * f)
			ring.anti_aliasing = true
			_shape(ring, 4)
			draw_style_box(ring, r)


## Drei Punkte, die nacheinander aufleuchten: der Freund schreibt gerade.
class _Dots extends Control:
	var _t := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(92, 52)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		if is_visible_in_tree():
			_t += dt
			queue_redraw()

	func _draw() -> void:
		var sb := UzTheme.box(UzTheme.col("text", 0.075), 22)
		sb.corner_radius_bottom_left = 5
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		for i in 3:
			var ph := fposmod(_t * 1.4 - i * 0.18, 1.0)
			var lift := sin(clampf(ph / 0.5, 0.0, 1.0) * PI)
			var c := Vector2(28 + i * 18, size.y * 0.5 - lift * 4.0)
			draw_circle(c, 5.0, UzTheme.col("text", 0.35 + 0.5 * lift))


## The input field. With a controller (and touch), A opens the on-screen keyboard or the phone as a keyboard. With
## mouse and keyboard you type directly into it – no window in between; Enter sends, Esc stops editing.
class _Composer extends Control:
	const UU := preload("res://src/ui/u.gd")
	var view
	var placeholder := "Nachricht schreiben …"
	var _feld: LineEdit

	func nav_ud(d: int) -> bool:
		return d < 0 and view != null and view.to_last_bubble()

	## Direkt tippen: ein Eingabefeld im Schreibfeld selbst.
	func tippen() -> void:
		if _feld == null:
			_feld = _Feld.new()
			_feld.set("composer", self)
			UU.full_rect(_feld)
			_feld.offset_left = 60
			_feld.offset_right = -22
			_feld.placeholder_text = tr(placeholder)
			_feld.max_length = 2000
			_feld.context_menu_enabled = false
			for st in ["normal", "focus", "read_only"]:
				_feld.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			_feld.add_theme_font_override("font", UzTheme.font("medium"))
			_feld.add_theme_font_size_override("font_size", 20)
			_feld.add_theme_color_override("font_color", UzTheme.col("text"))
			_feld.add_theme_color_override("font_placeholder_color", UzTheme.col("text", 0.45))
			_feld.text_changed.connect(func(_t: String) -> void: view._be().send_typing(view._fid()))
			_feld.text_submitted.connect(func(_t: String) -> void: senden())
			_feld.focus_exited.connect(func() -> void:
				if is_instance_valid(_feld) and _feld.text.strip_edges() == "":
					_feld.visible = false
					queue_redraw())
			add_child(_feld)
		_feld.visible = true
		_feld.grab_focus()
		queue_redraw()

	## Enter (über Nav als A oder vom Feld selbst – nur einmal je Druck): schicken, Feld bleibt offen fürs Nächste.
	var _gesendet_ms := -1000

	func senden() -> void:
		if not is_instance_valid(_feld) or Time.get_ticks_msec() - _gesendet_ms < 150:
			return
		_gesendet_ms = Time.get_ticks_msec()
		var t := _feld.text.strip_edges()
		if t != "":
			view._send(t)
		_feld.clear()
		_feld.grab_focus.call_deferred()

	## Esc (B): aufhören zu tippen – der Chat bleibt offen.
	func aufhoeren() -> void:
		if not is_instance_valid(_feld):
			return
		_feld.clear()
		_feld.visible = false
		grab_focus()
		queue_redraw()


	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(360, 60)
		focus_entered.connect(func() -> void: UU.focus_anim(self, true))
		focus_exited.connect(func() -> void: UU.focus_anim(self, false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				grab_focus()
				Nav.activate(self)
				accept_event()
			elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				view.scroll_by(-120 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 120)
		)

	func activate() -> void:
		if Nav.device in ["pad", "touch"]:
			view.write()
		else:
			tippen()

	func activate_sound() -> String:
		return "open"

	func _draw() -> void:
		var tippt := is_instance_valid(_feld) and _feld.visible
		var f := 0.0 if tippt else (float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0)
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.11 if tippt else 0.07), int(size.y * 0.5) - 1, 1,
				UzTheme.col("accent") if tippt else UzTheme.col("stroke")), r)
		if not tippt:
			UU.draw_focus(self, int(size.y * 0.5) - 1)
		var ink := UzTheme.col("text").lerp(UzTheme.col("on_focus"), f)
		draw_texture_rect(Icons.tex("chat", 24), Rect2(26, size.y * 0.5 - 12, 24, 24), false, Color(ink, 0.8))
		if not tippt:
			var font := UzTheme.font("medium")
			draw_string(font, Vector2(64, size.y * 0.5 + 7), tr(placeholder), HORIZONTAL_ALIGNMENT_LEFT, size.x - 90, 20, Color(ink, 0.7))


## Eingabefeld im Schreibfeld: A (Enter) schickt, B (Esc) hört auf zu tippen, statt den Chat zu schließen.
class _Feld extends LineEdit:
	var composer

	func activate() -> void:
		composer.senden()

	func activate_sound() -> String:
		return "select"

	func nav_b() -> bool:
		composer.aufhoeren()
		return true
