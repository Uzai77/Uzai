extends "res://src/ui/layers/layer.gd"
## Profil eines Steam-Freundes in Uzai – statt der Steam-Seite, aufgebaut wie der eigene
## Profil-Reiter und aus denselben Bausteinen (profile_page.gd): oben das breite Banner mit dem
## Profilhintergrund (bei öffentlichen Profilen; sonst das Bild des laufenden, zuletzt oder meist
## gespielten Spiels, sonst ein Licht in der Farbe des Profilbilds), großes Profilbild mit
## Statusring, Name, was gerade läuft, eine Zeile mit den Angaben (befreundet seit, bei Steam
## seit, Wohnort), Info-Text, Level-Ring und die Handlungen (Beitreten, Chat, Einladen – wenn du
## gerade ein Steam-Spiel spielst –, Auch spielen, Erfolge vergleichen). Darunter der Vergleich
## (Level, Spielzeit, Spiele – du im Akzent, der Freund leise), Zuletzt gespielt, Steam als
## Zahlenzeile (Spiele, Spielzeit der letzten zwei Wochen, gemeinsame Spiele, meistgespielt) und
## Gemeinsame Spiele; A öffnet die Spielseite (eigene Spiele) oder die Shopseite in Uzai. LB/RB
## springen zwischen Kopf, Vergleich, Zahlen und den Reihen.
## Daten aus der Steam-Web-API (Social.steam_profile, Achievements.steam_profile_extra); was
## privat ist, steht als kurzer Satz da.
## Für eine Freundschaftsanfrage (friend.request, request_flow.gd) dieselbe Seite: statt Chat und
## Vergleichen stehen dann Annehmen und Ablehnen da (bei gesendeten Anfragen nichts).

const Skeleton := preload("res://src/ui/components/skeleton.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const StoreGame := preload("res://src/ui/layers/store_game.gd")
const ChatView := preload("res://src/ui/layers/chat_view.gd")
const PP := preload("res://src/ui/sections/profile_page.gd")
const EdgeFade := preload("res://src/ui/components/ach/edge_fade.gd")
const PB := preload("res://src/ui/spielseite/profil_bloecke.gd")
const Buehne := preload("res://src/ui/spielseite/buehne.gd")

const SIDE := PP.G
const ROWS := ["head", "vergleich", "recent", "tiles", "shared"]

var friend: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var _glow: TextureRect
var _sc: ScrollContainer
var _col: VBoxContainer
var _banner: PP.Banner
var _btns: HBoxContainer
var _p: Dictionary = {}
var _x: Dictionary = {}          ## Profil-XML: Info-Text, Wohnort, bei Steam seit
var _rows := {}                  ## Abschnitt -> Knoten mit seinen Fokuselementen (LB/RB)
var _gen := 0
var _hero_key := ""

static var _bg_cache := {}       ## Steam-ID -> Profilhintergrund ("" = keiner)


func build() -> void:
	dim = 0.0
	_scrim.color = Color(UzTheme.col("bg"), 1.0)
	set_meta("uz_hint_b", "Zurück")
	var name_ := _name()
	# Licht in der Farbe der Person hinter der ganzen Seite (wie der Grund im Profil-Reiter).
	_glow = TextureRect.new()
	_glow.texture = radial_texture()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.position = Vector2(-420, -560)
	_glow.size = Vector2(1700, 1300)
	_glow.modulate = Color(Avatar.hue_color(name_), 0.0)
	add_child(_glow)
	U.tw(_glow, "uz_glow").tween_property(_glow, "modulate:a", 0.3, U.T_AMBIENT)
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.follow_focus = false
	_sc.set_meta("uz_pad_v", 190.0)    ## Reihen samt Bildunterschrift über der Hinweisleiste
	U.full_rect(_sc)
	add_child(_sc)
	_col = U.vbox(30)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(_col)
	_banner = PP.Banner.new()
	_banner.setup(name_, str(friend.get("avatar", "")), str(friend.get("state", "")), true, _kicker(), 56)
	_banner.set_status(ChatView.status_line(friend), _active(friend))
	_banner.set_level(-1, true)
	_banner.set_bio("", true)
	_banner.avatar.connect("texture_loaded", _tint_from)
	_col.add_child(_banner)
	_btns = _banner.actions
	_fill_buttons()
	_rows["head"] = _btns
	_update_chips()
	# Kopf (Knöpfe) gewählt: die Seite steht ganz oben, Banner ganz zu sehen.
	_sc.set_meta("uz_top_node", _banner)
	EdgeFade.attach(_sc, _col)
	_body_loading()
	set_meta("uz_hints", [["lb", ""], ["rb", "Abschnitt"]])
	# Geteilte Elemente (src/ui/flug.gd): das Profilbild aus der Freundesliste fliegt hierher.
	if str(friend.get("id", "")) != "":
		set_meta("uz_flug", "fr:" + str(friend.id))
	_load()


func flug_ziel() -> Control:
	return _banner.avatar if is_instance_valid(_banner) else null


func _name() -> String:
	return str(friend.get("name", "Freund"))


static func _active(f: Dictionary) -> bool:
	return str(f.get("game", "")) != "" or str(f.get("state", "")) in ["online", "game"]


func _request() -> Dictionary:
	return friend.get("request", {}) if friend.get("request") is Dictionary else {}


func _kicker() -> String:
	var r := _request()
	if r.is_empty():
		return ""
	return "Freundschaftsanfrage" if str(r.get("dir", "")) == "in" else "Anfrage gesendet"


func _fill_buttons() -> void:
	U.clear(_btns)
	if not _request().is_empty():
		_request_buttons()
		return
	var url := Social.join_url(friend)
	if url != "":
		var j := U.button("Beitreten", "play", "primary")
		j.set_meta("uz_default", true)
		j.set_meta("uz_hint_a", "Mitspielen")
		j.set_meta("uz_key", "fp:btn:join")
		j.pressed.connect(func() -> void:
			close()
			main.join_game(friend, url)
		)
		_btns.add_child(j)
	var n := int(SteamChat.unread.get(str(friend.get("id", "")), 0))
	var chat := U.button("Chat" if n == 0 else "Chat · %d neu" % n, "chat", "normal" if url != "" else "primary")
	if url == "":
		chat.set_meta("uz_default", true)
	chat.set_meta("uz_key", "fp:btn:chat")
	chat.pressed.connect(func() -> void: main.open_chat(friend))
	_btns.add_child(chat)
	# Einladen: du spielst gerade ein Steam-Spiel und die Person ist erreichbar (main.invite_friend
	# lädt über die Steamworks-Bibliothek des Spiels ein, sonst als Beitreten-Link in den Chat).
	if Launcher.in_game and str(Launcher.current.get("source", "")) == "steam" and str(friend.get("state", "")) in ["online", "game", "away", "busy"]:
		var inv := U.button("Einladen", "plus")
		inv.set_meta("uz_key", "fp:btn:invite")
		inv.set_meta("uz_hint_a", "Zu deinem Spiel einladen")
		inv.pressed.connect(func() -> void: main.invite_friend(friend))
		_btns.add_child(inv)
	var mine := Library.get_game("steam:" + str(friend.get("game_id", "")))
	if url == "" and not mine.is_empty() and not Launcher.in_game:
		var play := U.button("Auch spielen", "games")
		play.set_meta("uz_key", "fp:btn:play")
		play.pressed.connect(func() -> void:
			close()
			main.launch(mine)
		)
		_btns.add_child(play)
	var cmp := U.button("Erfolge vergleichen", "trophy")
	cmp.set_meta("uz_key", "fp:btn:cmp")
	cmp.pressed.connect(func() -> void: main.open_compare_picker(friend))
	_btns.add_child(cmp)


## Anfrage an dich: Annehmen (vorgewählt) und Ablehnen; danach schließt die Seite.
func _request_buttons() -> void:
	var r := _request()
	if str(r.get("dir", "")) != "in":
		return
	var flow := load("res://src/ui/request_flow.gd")
	var done: Callable = friend.get("request_done", Callable())
	var after := func() -> void:
		close()
		if done.is_valid():
			done.call()
	var yes := U.button(flow.accept_text(), "check", "primary")
	yes.set_meta("uz_default", true)
	yes.set_meta("uz_key", "fp:btn:accept")
	yes.pressed.connect(func() -> void: flow.accept(r, after))
	_btns.add_child(yes)
	var no := U.button("Ablehnen", "close")
	no.set_meta("uz_key", "fp:btn:decline")
	no.pressed.connect(func() -> void: flow.decline(main, r, after))
	_btns.add_child(no)


func _load(force := false) -> void:
	_gen += 1
	var gen := _gen
	var id := str(friend.get("id", ""))
	var p := await Social.steam_profile(id, force)
	if gen != _gen or not is_inside_tree():
		return
	_fill(p)
	if bool(p.get("public", false)):
		_load_background(id, gen, force)
	var x := await Achievements.steam_profile_extra(id, force)
	if gen != _gen or not is_inside_tree():
		return
	_x = x
	_update_chips()
	_update_bio()


func _fill(p: Dictionary) -> void:
	_p = p
	# Frischer Stand aus Steam (Spiel, Status) – die Liste kann ein paar Minuten alt sein.
	if str(p.get("state", "")) != "":
		var before := Social.join_url(friend) + "|" + str(friend.get("game_id", ""))
		var merged := friend.duplicate()
		for k in ["state", "game", "game_id", "lobby", "server", "last"]:
			if p.has(k):
				merged[k] = p[k]
		friend = merged
		_banner.set_status(ChatView.status_line(friend), _active(friend))
		if Social.join_url(friend) + "|" + str(friend.get("game_id", "")) != before:
			var f := Nav.focused()
			var had := f != null and _btns.is_ancestor_of(f)
			_fill_buttons()
			if had:
				_refocus_buttons.call_deferred()
	_update_chips()
	var level := int(p.get("level", -1))
	if _failed(p):
		_banner.set_level(-1, false, "Level unbekannt")
		_banner.set_bio("", false)
	else:
		_banner.set_level(level, false)
	# Bild: das laufende Spiel, sonst das zuletzt gespielte, sonst das meistgespielte.
	var recent: Array = p.get("recent", [])
	var top: Dictionary = p.get("top", {})
	var gid := str(friend.get("game_id", ""))
	if gid != "" and gid.is_valid_int():
		_show_hero(int(gid), str(friend.get("game", "")))
	elif not recent.is_empty():
		_show_hero(int(recent[0].appid), str(recent[0].name))
	elif not top.is_empty():
		_show_hero(int(top.appid), str(top.name))
	_build_body()


static func _failed(p: Dictionary) -> bool:
	return str(p.get("error", "")) != "" and int(p.get("level", -1)) < 0 \
		and (p.get("recent", []) as Array).is_empty() and (p.get("shared", []) as Array).is_empty()


func _refocus_buttons() -> void:
	if is_instance_valid(_btns):
		var d := Nav.default_in(_btns)
		if d:
			Nav.focus(d, true)


# --- Kopf: Chips, Info-Text, Hintergrund ---------------------------------------------------

func _update_chips() -> void:
	var list: Array = []
	var since := int(_p.get("since", 0))
	if since <= 0:
		since = int(friend.get("since", 0))
	if since > 0:
		list.append(["friends", "Befreundet seit " + Social.month_year(since)])
	var created := int(_p.get("created", 0))
	if created <= 0:
		created = int(_x.get("member_since", 0))
	if created > 0:
		list.append(["star", PP.since_text(created)])
	if str(_x.get("location", "")) != "":
		list.append(["home", str(_x.location)])
	if str(_x.get("realname", "")) != "":
		list.append(["user", str(_x.realname)])
	_banner.set_chips(list)


func _update_bio() -> void:
	var bio := str(_x.get("summary", "")).strip_edges()
	if bio == "":
		bio = str(_x.get("headline", "")).strip_edges()
	if bio == "" and bool(_x.get("ok", false)) and not bool(_x.get("public", true)):
		bio = tr("Das Profil von %s ist privat – Info-Text und Wohnort zeigt Steam nur bei öffentlichen Profilen.") % _name()
	_banner.set_bio(bio, false)


## Profilhintergrund des Freundes (IPlayerService/GetProfileItemsEquipped, nur öffentliche
## Profile). Schlägt das Spielbild; kommt keiner, bleibt es beim Spielbild bzw. Licht.
func _load_background(id: String, gen: int, force: bool) -> void:
	var url := ""
	if _bg_cache.has(id) and not force:
		url = str(_bg_cache[id])
	elif Social.demo or not Social.has_steam() or not id.is_valid_int():
		return
	else:
		var q := await Social.steam_query({ "steamid": id })
		var r := await Net.get_json(Social.STEAM + "IPlayerService/GetProfileItemsEquipped/v1/?" + q)
		if not bool(r.get("ok", false)):
			return
		url = Achievements.parse_items(r.get("data"))
		_bg_cache[id] = url
		Config.cap(_bg_cache, 300)
	if url != "" and gen == _gen and is_inside_tree():
		_banner.load_url(url, 2)


func _show_hero(appid: int, title: String) -> void:
	var key := "steam:%d" % appid
	if key == _hero_key:
		return
	_hero_key = key
	_banner.load_game(appid, title, 1)
	var g := Library.get_game(key)
	if g.is_empty():
		g = { "id": key, "title": title, "source": "steam", "system": "steam", "appid": appid }
	var me: WeakRef = weakref(self)
	Media.game_tint(g, func(c: Variant) -> void:
		var l: Variant = me.get_ref()
		if l != null and c is Color:
			l.call("_glow_to", c)
	)


func _glow_to(c: Color) -> void:
	if is_instance_valid(_glow):
		U.tw(_glow, "uz_glow").tween_property(_glow, "modulate", Color(c, 0.3), U.T_AMBIENT)


## Ohne Spielfarbe: das Licht nimmt die Farbe des Profilbilds an.
func _tint_from(t: Texture2D) -> void:
	if _hero_key != "" or t == null or not t.has_meta("uz_vivid"):
		return
	var c: Variant = Media.color_of(t)
	if c is Color:
		_glow_to(c)


# --- Darunter: Zahlen und Reihen -----------------------------------------------------------

## Alles unter dem Banner neu; die Auswahl bleibt, wo sie war (gleiche Kachel bzw. Reihe).
func _rebuild_body(fill: Callable) -> void:
	var f := Nav.focused()
	var key := ""
	var had := f != null and is_instance_valid(_col) and _col.is_ancestor_of(f) and not _banner.is_ancestor_of(f)
	if had:
		key = str(f.get_meta("uz_key", ""))
	for i in range(_col.get_child_count() - 1, 0, -1):
		var c := _col.get_child(i)
		_col.remove_child(c)
		c.queue_free()
	_rows.clear()
	_rows["head"] = _btns
	var first := _col.get_child_count()
	fill.call()
	_col.add_child(U.spacer(0, 60, false))
	var i := 0
	for k in range(first, _col.get_child_count()):
		var c := _col.get_child(k) as Control
		c.modulate.a = 0.0
		U.ankommen(c, U.T_ORT, "uz_in").tween_property(c, "modulate:a", 1.0, U.T_ORT).set_delay(U.staffel(i))
		i += 1
	if had:
		_refocus_body.call_deferred(key)


func _refocus_body(key: String) -> void:
	if not is_instance_valid(_col):
		return
	var items := Nav.focusables(_col)
	for c in items:
		if key != "" and str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return
	for c in items:
		if not _banner.is_ancestor_of(c):
			Nav.focus(c, true)
			return
	_refocus_buttons()


func _body_loading() -> void:
	_rebuild_body(func() -> void:
		# Platzhalter in der Form des Vergleichs, der Reihe und der Zahlen: kommt alles, füllt es sich nur.
		var vm := U.margin(SIDE, 0, SIDE, 0)
		vm.add_child(Skeleton.new().setup(Vector2(U.room_w(SIDE), 72.0 + 3 * 58.0), UzTheme.r_panel()))
		_col.add_child(vm)
		_col.add_child(PP.title("Zuletzt gespielt"))
		var m := U.margin(SIDE, 0, SIDE, 0)
		var gr := U.hbox(28)
		m.add_child(gr)
		for i in 7:
			gr.add_child(Skeleton.cards(1, PP.COVER))
		_col.add_child(m)
		_col.add_child(PP.title("Steam", "wird geladen …"))
		var row := PB.zahlen([["…", "Spiele"], ["…", "Spielzeit"], ["…", "Gemeinsame Spiele"], ["…", "Meistgespielt"]], "fp:zahlen", "—", Callable())
		_col.add_child(row)
		_rows["tiles"] = row
	)


func _build_body() -> void:
	_rebuild_body(_fill_body)


func _fill_body() -> void:
	var p := _p
	var name_ := _name()
	var recent: Array = p.get("recent", [])
	var shared: Array = p.get("shared", [])
	var top: Dictionary = p.get("top", {})
	var gp := bool(p.get("games_private", false))
	var rp := bool(p.get("recent_private", false))
	if _failed(p):
		var e := str(p.error)
		var err := _card("warning", "Steam antwortet gerade nicht", "Level, Spiele und Spielzeit kommen, sobald Steam wieder erreichbar ist.", true) \
			if e.begins_with("Steam antwortet") else _card("warning", "Profil nicht geladen", e, true)
		_col.add_child(err)
		_rows["tiles"] = err
		return
	if int(p.get("level", -1)) < 0 and gp and rp:
		_col.add_child(_card("lock", "Privates Profil",
			"Level, Spiele und Spielzeit zeigt Steam nur, wenn %s das Profil öffentlich macht." % name_, false))
		return
	var two := 0
	for g in recent:
		two += int(g.get("two_weeks", 0))
	var total := 0 if gp else int(p.get("minutes", 0))
	# Im Vergleich: Level, Spielzeit und Spiele – du im Akzent, die Person leise.
	var rows := _vergleich_rows(p, gp, shared)
	if not rows.is_empty():
		var vg := PB.vergleich(rows, ["Du", name_], "fp:vergleich", "Erfolge vergleichen", func() -> void: main.open_compare_picker(friend))
		_col.add_child(vg)
		_rows["vergleich"] = vg
	# Zuletzt gespielt (vor den Zahlen: so stehen die Cover schon auf dem ersten Bild,
	# nicht nur die Überschrift am unteren Rand)
	_col.add_child(PP.title("Zuletzt gespielt", ("%s in zwei Wochen" % PP.hours(two)) if not rp and not recent.is_empty() else ""))
	if rp:
		_col.add_child(_note("Was %s zuletzt gespielt hat, ist privat." % name_))
	elif recent.is_empty():
		_col.add_child(_note("%s hat in den letzten zwei Wochen nichts gespielt." % name_))
	else:
		var shelf = PP.cover_shelf("fp:recent")
		for i in recent.size():
			var g: Dictionary = recent[i]
			shelf.add(_cover(int(g.appid), str(g.name), "%s in 2 Wochen" % PP.hours(int(g.two_weeks)), "insgesamt " + PP.hours(int(g.total)), "fp:recent", i == 0))
		_col.add_child(shelf)
		_rows["recent"] = shelf
	_col.add_child(PP.title("Steam", "die Bibliothek von %s in Zahlen" % name_))
	var top_ok := not top.is_empty()
	var ziel := "shared" if not gp and not shared.is_empty() else ("recent" if not rp and not recent.is_empty() else "")
	var row := PB.zahlen([
		["–" if gp else PP.num(int(p.get("games_count", 0))), "Spiele" + (" · Bibliothek privat" if gp else "")],
		[PP.hours(total) if total > 0 else ("–" if rp else PP.hours(two)),
			"Spielzeit" + ((" · %s in zwei Wochen" % PP.hours(two)) if total > 0 and two > 0 else (" in zwei Wochen" if total <= 0 and not rp else ""))],
		["–" if gp else PP.num(shared.size()), "Gemeinsame Spiele"],
		[PP.hours(int(top.total)) if top_ok else "–", ("Meistgespielt · " + str(top.name)) if top_ok else "Meistgespielt"],
	], "fp:zahlen", ("Gemeinsame Spiele" if ziel == "shared" else ("Zuletzt gespielt" if ziel == "recent" else "—")),
		_focus_row.bind(ziel) if ziel != "" else Callable())
	_col.add_child(row)
	_rows["tiles"] = row
	# Gemeinsame Spiele
	_col.add_child(
			PP.title("Gemeinsame Spiele", ("%s, die ihr beide habt" % U.plural(shared.size(), "Spiel", "Spiele")) if not gp and not shared.is_empty() else ""))
	if gp:
		_col.add_child(_note("Die Bibliothek von %s ist privat – gemeinsame Spiele sind deshalb nicht zu sehen." % name_))
	elif shared.is_empty():
		_col.add_child(_note("Ihr habt noch kein Spiel gemeinsam."))
	else:
		var shelf2 = PP.cover_shelf("fp:shared")
		var list := shared.slice(0, 30)
		for i in list.size():
			var g: Dictionary = list[i]
			var mine_txt := ("Du %s" % PP.hours(int(g.mine))) if int(g.mine) > 0 else "Bei dir noch ungespielt"
			var theirs_txt := ("%s %s" % [name_, PP.hours(int(g.theirs))]) if int(g.theirs) > 0 else "%s noch nicht" % name_
			shelf2.add(_cover(int(g.appid), str(g.name), mine_txt, theirs_txt, "fp:shared", i == 0))
		_col.add_child(shelf2)
		_rows["shared"] = shelf2


static func _owned(appid: int) -> bool:
	return not Library.get_game("steam:%d" % appid).is_empty()


## Zeilen des Vergleichs: Steam-Level, Spielzeit insgesamt, Zahl der Spiele (mit den gemeinsamen).
## Deine Zahlen aus dem eigenen Profil (Achievements.steam_me, steam_stats), sonst aus der Bibliothek.
func _vergleich_rows(p: Dictionary, gp: bool, shared: Array) -> Array:
	var rows: Array = []
	var me: Dictionary = Achievements.steam_me
	var st: Dictionary = Achievements.steam_stats
	var my_level := int(me.get("level", -1))
	var their_level := int(p.get("level", -1))
	if my_level >= 0 and their_level >= 0:
		var a := Buehne.anteile(float(my_level), float(their_level))
		rows.append({ "label": "Steam-Level", "a": a.a, "b": a.b, "a_text": str(my_level), "b_text": str(their_level) })
	var my_min := int(st.get("minutes", 0))
	if my_min <= 0:
		for g in Library.by_system("steam"):
			my_min += int(Library.playtime(g) / 60)
	var their_min := 0 if gp else int(p.get("minutes", 0))
	if my_min > 0 or their_min > 0:
		var a2 := Buehne.anteile(float(my_min), float(their_min))
		rows.append({ "label": "Spielzeit", "a": a2.a, "b": a2.b, "a_text": PP.hours(my_min), "b_text": "privat" if gp else PP.hours(their_min) })
	var my_games := int(st.get("games", 0))
	if my_games <= 0:
		my_games = Library.count_by_system("steam")
	var their_games := 0 if gp else int(p.get("games_count", 0))
	if my_games > 0 and (their_games > 0 or gp):
		var a3 := Buehne.anteile(float(my_games), float(their_games))
		rows.append({ "label": "Spiele", "a": a3.a, "b": a3.b, "a_text": PP.num(my_games),
			"b_text": "privat" if gp else (PP.num(their_games) + ((" · %d gemeinsam" % shared.size()) if not shared.is_empty() else "")) })
	return rows


func _cover(appid: int, title: String, line1: String, line2: String, group: String, entry: bool) -> Control:
	return PP.cover(appid, title, line1, line2, "%s:%d" % [group, appid], "Spielseite" if _owned(appid) else "Im Shop ansehen",
		entry, _open.bind(appid, title))


func _note(text: String) -> Control:
	var m := U.margin(SIDE, 0, SIDE, 6)
	var l := U.label(text, "m", "muted", "regular", true)
	l.custom_minimum_size = Vector2(900, 0)
	m.add_child(l)
	return m


## Breite Karte statt der Zahlen: privates Profil oder Steam nicht erreichbar (mit Nochmal laden).
func _card(icon_name: String, head: String, text: String, retry: bool) -> Control:
	var m := U.margin(SIDE, 4, SIDE, 0)
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface", 0.9), UzTheme.r_panel())
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 34
	sb.content_margin_bottom = 34
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(p)
	var h := U.hbox(30)
	p.add_child(h)
	var ic := U.icon(icon_name, 44, "warn" if icon_name == "warning" else "muted")
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := U.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var hl := U.label(head, "l", "text", "bold")
	hl.clip_text = false
	v.add_child(hl)
	var tl := U.label(text, "m", "muted", "regular", true)
	tl.custom_minimum_size = Vector2(900, 0)
	v.add_child(tl)
	if retry:
		v.add_child(U.spacer(0, 14, false))
		var again := U.button("Nochmal laden", "refresh")
		again.set_meta("uz_key", "fp:retry")
		again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		again.pressed.connect(func() -> void:
			_banner.set_level(-1, true)
			_banner.set_bio("", true)
			_body_loading()
			_load(true)
		)
		v.add_child(again)
	return m


func _open(appid: int, title: String) -> void:
	var g := Library.get_game("steam:%d" % appid)
	if not g.is_empty():
		main.open_game(g)
		return
	var l = StoreGame.new()
	l.item = { "appid": appid, "name": title, "header": Store.CDN % [appid, "header.jpg"],
		"capsule": Store.CDN % [appid, "capsule_616x353.jpg"], "price": 0, "original": 0, "discount": 0 }
	l.main = main
	main.open_layer(l)


# --- Steuerung: LB/RB springen zwischen den Abschnitten ------------------------------------

func handle(cmd: String) -> bool:
	if cmd == "lb" or cmd == "rb":
		_jump(-1 if cmd == "lb" else 1)
		return true
	return false


func _jump(step: int) -> void:
	var order: Array = []
	for k in ROWS:
		if _rows.has(k) and is_instance_valid(_rows[k]) and not Nav.focusables(_rows[k]).is_empty():
			order.append(k)
	if order.is_empty():
		return
	var f := Nav.focused()
	var cur := 0
	for i in order.size():
		if f != null and (_rows[order[i]] as Control).is_ancestor_of(f):
			cur = i
	var nxt := clampi(cur + step, 0, order.size() - 1)
	if nxt == cur:
		Sfx.play("bump")
		return
	Sfx.play("tab")
	_focus_row(str(order[nxt]), true)


## Erstes Element eines Abschnitts wählen (Reihe: das mit uz_entry, Kopf: der Standardknopf).
func _focus_row(id: String, silent := false) -> void:
	if not _rows.has(id) or not is_instance_valid(_rows[id]):
		return
	var root: Control = _rows[id]
	var items := Nav.focusables(root)
	if items.is_empty():
		return
	var pick: Control = Nav.default_in(root) if id == "head" else items[0]
	for c in items:
		if c.has_meta("uz_entry"):
			pick = c
			break
	Nav.focus(pick, silent)


# --- Licht -----------------------------------------------------------------------------------

static var _radial: GradientTexture2D


## Weiches rundes Licht (weiß, beim Zeichnen einfärben).
static func radial_texture() -> GradientTexture2D:
	if _radial != null:
		return _radial
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	_radial = t
	return t
