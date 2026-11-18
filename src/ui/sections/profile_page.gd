extends RefCounted
## Profil wie ein persönliches Konsolen-Profil: oben der Kopf (Profilhintergrund, sonst das Bild
## des meistgespielten Spiels, sonst ein Licht in der Farbe des Namens), großes Profilbild mit
## Status, Name, Status, eine leise Zeile mit den Angaben (seit wann bei Steam, Wohnort,
## Steam-Level) und der Info-Text; rechts das Uzai-Level (profile_badges.gd). Der Kopf ist
## wählbar: A ändert den Status, Y vergleicht Erfolge mit einem Freund – keine Knopfreihe.
## Darunter die Vitrine (Favoriten, sonst Meistgespielt, am Ende Dein Zimmer), gleich danach Steam
## in einer Zahlenzeile mit perfekten Spielen und seltensten Erfolgen, klein „Diese Woche“,
## Abzeichen und zuletzt Freigeschaltetes, Freunde und RetroAchievements. Steam zählt im Hintergrund; die Zahlen zeigen „…“ und füllen sich, ohne
## dass die Seite springt. Bausteine (Banner, Cover, Zahlen) nutzt auch das Profil eines Freundes.

const People := preload("res://src/ui/components/guide_people.gd")
const U := preload("res://src/ui/u.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const Ring := preload("res://src/ui/components/ach/ring.gd")
const UnlockCard := preload("res://src/ui/components/ach/unlock_card.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")
const SocialS := preload("res://src/core/social.gd")
const ProfilePageS := preload("res://src/ui/sections/profile_page.gd")
const ProfileBadges := preload("res://src/ui/sections/profile_badges.gd")
const ProfileUnlocks := preload("res://src/ui/sections/profile_unlocks.gd")
const Buehne := preload("res://src/ui/spielseite/buehne.gd")
const PB := preload("res://src/ui/spielseite/profil_bloecke.gd")
const MyProfile := preload("res://src/ui/layers/my_profile.gd")
const MyStatus := preload("res://src/core/my_status.gd")
const ZimmerBild := preload("res://src/ui/components/zimmer_bild.gd")

const G := 96                    ## Seitenrand wie in allen Bereichen
const BANNER_H := 380
const NARROW_W := 1300.0         ## schmaler (Oberfläche ab ~130 %): Banner ohne Level-Ring
const SHELF_PAD := 30            ## wie im Bereich: Luft fürs Anheben der Kacheln
const COVER := Vector2(176, 236)
const STATES := { "online": "Online", "game": "Im Spiel", "away": "Abwesend", "busy": "Beschäftigt", "offline": "Offline",
	"invisible": "Unsichtbar" }

var view: Control
var _zahlen: Control             ## Zahlenzeile Steam (Spiele, Spielzeit, Perfekte, Erfolge)
var _perfect_tile: Control       ## bleibt für ältere Aufrufer (update_counts)
var _ach_tile: Control


func build(v: Control, col: VBoxContainer) -> void:
	view = v
	var me: Dictionary = Achievements.steam_me
	var steam: bool = Achievements.has_steam()
	col.add_child(_banner(me, steam))
	var games: Array = Library.visible_games().filter(func(g: Dictionary) -> bool: return not Library.owned_only(g))
	_vitrine(col, games)
	# Bis hierher reicht der erste Bildschirm. Alles darunter entsteht erst nach dem Hereingleiten, Abschnitt für
	# Abschnitt (achievements_view.gd nachbau) – in einem Zug kostete die Seite 55–65 ms mitten im Tastendruck.
	var unten: Array = []
	# Steam and its achievements right below the showcase; „Zuletzt gespielt“ is no longer shown here
	# because the home page already shows it.
	if steam:
		unten.append(func() -> void:
			col.add_child(title("Steam", "deine Bibliothek in Zahlen"))
			col.add_child(_zahlen_steam()))
		unten.append(func() -> void: _perfect(col))
		unten.append(func() -> void: _rarest(col))
	# The week kept small, so playtime is not the center of the page.
	unten.append(func() -> void: _woche(col, games))
	unten.append(func() -> void: ProfileBadges.row(view, col))
	unten.append(func() -> void: ProfileUnlocks.section(view, col))
	unten.append(func() -> void: _freunde(col))
	if Achievements.has_ra():
		unten.append(func() -> void: _retro(col))
	unten.append(func() -> void: col.add_child(U.spacer(0, 110, false)))
	if view.has_method("nachbau"):
		view.call("nachbau", col, unten)
	else:
		for s in unten:
			(s as Callable).call()


## Während Steam zählt: nur die Zahlen auffrischen (kein Neuaufbau, kein Springen).
func update_counts() -> void:
	var st: Dictionary = Achievements.steam_stats
	if is_instance_valid(_zahlen):
		_zahlen.call("set_wert", 2, _perfect_value(st), _perfect_sub(st))
		_zahlen.call("set_wert", 3, _ach_value(st), _ach_sub(st))
	if is_instance_valid(_perfect_tile):
		_perfect_tile.call("set_values", _perfect_value(st), _perfect_sub(st))
	if is_instance_valid(_ach_tile):
		_ach_tile.call("set_values", _ach_value(st), _ach_sub(st))


# --- Kopf --------------------------------------------------------------------------------

func _banner(me: Dictionary, steam: bool) -> Control:
	var ra: Dictionary = Achievements.ra_profile
	var name_ := str(me.get("name", ""))
	if name_ == "":
		name_ = str(Social.me.get("name", ""))
	if name_ == "":
		name_ = str(ra.get("name", "Du"))
	var avatar := str(me.get("avatar", Social.me.get("avatar", "")))
	if avatar == "" and not steam:
		avatar = str(ra.get("pic", ""))
	var b := Banner.new()
	var st := _state_of(me) if steam else ""
	b.setup(name_, avatar, MyStatus.dot(st) if steam else "", steam, "")
	if steam:
		# Platz für Zeile, Angaben und Info-Text von Anfang an: kommen die Daten, springt nichts.
		b.reserve()
		b.set_status(_state_text(me), st in ["online", "game"], Achievements.profile_loading and me.is_empty())
	elif not ra.is_empty():
		b.set_status("RetroAchievements", false)
	b.set_chips(_chips_of(me, ra, steam))
	var bio := _bio_text(me, ra, steam)
	b.set_bio(bio, bio == "" and steam and Achievements.profile_loading and me.is_empty())
	# Der Kopf ist wählbar: A ändert den Status (wie an der Karte im Guide), Y vergleicht.
	var wb: WeakRef = weakref(b)
	b.make_focusable("Status", func() -> void: _status(wb.get_ref()),
		"Vergleichen" if not Social.steam_friends.is_empty() else "", func() -> void: _act("cmp"))
	# Rechts das Uzai-Level (Punkte aus allen Plattformen); das Steam-Level steht in der Zeile.
	ProfileBadges.banner(b, int(me.get("level", -1)) if steam else -1)
	_load_art(b, me)
	return b


func _chips_of(me: Dictionary, ra: Dictionary, steam: bool) -> Array:
	var out: Array = []
	if steam:
		if int(me.get("created", 0)) > 0:
			out.append(["star", since_text(int(me.created))])
		if str(me.get("location", "")) != "":
			out.append(["home", str(me.location)])
		if str(me.get("realname", "")) != "":
			out.append(["user", str(me.realname)])
	elif int(ra.get("member_since", 0)) > 0:
		out.append(["star", "Seit %s dabei" % SocialS.month_year(int(ra.member_since))])
	if Achievements.has_ra() and int(ra.get("points", 0)) > 0:
		out.append(["retro", "%s RA-Punkte" % num(int(ra.points))])
	return out


## „Seit September 2009 bei Steam · 17 Jahre“
static func since_text(created: int) -> String:
	var now := int(Time.get_unix_time_from_system())
	var years := int(Time.get_date_dict_from_unix_time(now).year) - int(Time.get_date_dict_from_unix_time(created).year)
	var t := "Seit %s bei Steam" % SocialS.month_year(created)
	if years >= 2:
		t += " · %d Jahre" % years
	return t


## Info-Text aus dem Steam-Profil (sonst Überschrift, sonst das Motto bei RetroAchievements).
func _bio_text(me: Dictionary, ra: Dictionary, steam: bool) -> String:
	if steam:
		for k in ["summary", "headline"]:
			if str(me.get(k, "")) != "":
				return str(me[k])
		if bool(me.get("public", true)) == false and not me.is_empty():
			return tr("Dein Steam-Profil ist privat – Info-Text und Wohnort zeigt Steam nur bei öffentlichen Profilen.")
	return str(ra.get("motto", ""))


func _state_text(me: Dictionary) -> String:
	if Achievements.profile_loading and me.is_empty():
		return ""
	if Achievements.profile_error != "" and me.is_empty():
		return Achievements.profile_error
	var st := _state_of(me)
	if st == "game" and str(me.get("game", "")) != "":
		return "Spielt " + str(me.game)
	return str(STATES.get(st, "Online"))


## Dein Status im Kopf: aus dem Profil der Web-API, sonst (Web-API lehnt ab) bzw. neben Steam am PC
## wie überall in Uzai (MyStatus) – vorher stand dann immer „Offline“.
func _state_of(me: Dictionary) -> String:
	var mine := "" if MyStatus.demo() else MyStatus.steam_now()
	return MyStatus.profile_state(str(me.get("state", "")), mine, SteamCM.pc_persona >= 0)


## A auf dem Profilbild: „Dein Status“ (Steam, Discord; Wege zu Aufnahmen, Abzeichen, Konten).
func _status(b: Variant) -> void:
	if view == null or view.main == null:
		return
	var l = MyProfile.new()
	l.main = view.main
	if b is Banner and is_instance_valid(b) and is_instance_valid(b.avatar):
		l.anchor = (b.avatar as Control).get_global_rect()
	view.main.open_layer(l)


func _act(kind: String) -> void:
	match kind:
		"ach":
			view.jump("uebersicht")
		"play":
			view.jump("statistik")
		"zimmer":
			view.main.open_room()
		"cmp":
			var opts: Array = []
			for f in Social.steam_friends:
				var st := str(f.get("state", ""))
				var sub := (tr("Spielt %s") % str(f.game)) if st == "game" and str(f.get("game", "")) != "" else ""
				opts.append([str(f.id), str(f.name), sub, { "avatar": str(f.get("avatar", "")), "status": People.dot(f) }])
			if opts.is_empty():
				return
			view.main.open_choice("Mit wem vergleichen?", opts, "", func(fid: Variant) -> void:
				var f: Dictionary = Social.steam_friend(str(fid))
				if not f.is_empty():
					view.main.open_compare_picker(f)
			, "Erfolge mit Steam-Freunden")


## Profilhintergrund von Steam; sonst das große Bild des meistgespielten bzw. letzten Spiels.
func _load_art(b: Banner, me: Dictionary) -> void:
	if str(me.get("background", "")) != "":
		b.load_url(str(me.background), 2)
		return
	if not Achievements.steam_recent.is_empty():
		b.load_game(int(Achievements.steam_recent[0].appid), str(Achievements.steam_recent[0].get("name", "")), 1)
	elif not (me.get("top", {}) as Dictionary).is_empty():
		b.load_game(int(me.top.appid), str(me.top.name), 1)
	else:
		# Ohne Steam: das Bild des zuletzt gespielten Spiels der Bibliothek.
		var rec := Library.recent(1)
		if not rec.is_empty():
			var wr: WeakRef = weakref(b)
			Media.game_texture(rec[0], "hero", func(t: Texture2D) -> void:
				var bb: Variant = wr.get_ref()
				if bb != null and t != null:
					bb.call("show_art", t, 1)
			)


# --- Diese Woche, Vitrine, Zuletzt gespielt --------------------------------------------------

func _woche(col: VBoxContainer, games: Array) -> void:
	var sessions := Library.load_sessions()
	var total := 0
	var n := 0
	for g in games:
		var pt := Library.playtime(g)
		total += pt
		if pt > 0:
			n += 1
	if total <= 0 and sessions.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	col.add_child(PB.woche(sessions, total, n, now, bias, "prof:woche", func() -> void: view.jump("statistik")))


## Favoriten (sonst die meistgespielten) als Cover; am Ende Dein Zimmer als kleines Live-Bild.
func _vitrine(col: VBoxContainer, games: Array) -> void:
	var vt := Buehne.vitrine(games, Library.playtime)
	var room: bool = bool(Config.get_value("room.kachel", true)) and view.main != null and view.main.has_method("open_room")
	if vt.is_empty() and not room:
		return
	col.add_child(title(str(vt.get("titel", "Vitrine")), str(vt.get("extra", ""))))
	var shelf = PB.cover_shelf("prof:vitrine")
	var list: Array = vt.get("list", [])
	for i in list.size():
		var g: Dictionary = list[i]
		shelf.add(PB.cover_game(g, Buehne.zeit_kurz(Library.playtime(g)) if Library.playtime(g) > 0 else "", _last_text(g),
			"prof:vitrine:" + str(g.get("id", "")), "Spielseite", i == 0, _open_lib.bind(g)))
	if room:
		var v := U.vbox(12)
		var zb = ZimmerBild.new().setup(Vector2(314, COVER.y))
		zb.set_meta("uz_key", "prof:zimmer")
		zb.activated.connect(func() -> void: view.main.open_room())
		if list.is_empty():
			zb.set_meta("uz_entry", true)
		v.add_child(zb)
		var cap := U.label("Dein Zimmer", "s", "text", "ui_bold")
		cap.clip_text = false
		v.add_child(cap)
		shelf.add(v)
	col.add_child(shelf)


func _last_text(g: Dictionary) -> String:
	var last := Library.last_played(g)
	return tr("zuletzt %s") % tr(Buehne.zuletzt_text(U.ago(last))) if last > 0 else ""


func _open_lib(g: Dictionary) -> void:
	view.main.open_game(g)


# --- Steam in Zahlen ---------------------------------------------------------------------

func _zahlen_steam() -> Control:
	var st: Dictionary = Achievements.steam_stats
	var me: Dictionary = Achievements.steam_me
	var loading := st.is_empty()
	var games := "…" if loading else num(int(st.get("games", 0)))
	var games_sub := "Spiele"
	if bool(me.get("games_private", false)):
		games = "–"
		games_sub = "Bibliothek privat"
	elif not loading and int(st.get("played", 0)) > 0:
		games_sub = "Spiele · %s gespielt" % num(int(st.get("played", 0)))
	_zahlen = PB.zahlen([
		[games, games_sub],
		["…" if loading else hours(int(st.get("minutes", 0))), "Spielzeit bei Steam"],
		[_perfect_value(st), _perfect_sub(st)],
		[_ach_value(st), _ach_sub(st)],
	], "prof:zahlen", "Alle Erfolge", func() -> void: view.jump("uebersicht"))
	return _zahlen


static func _perfect_value(st: Dictionary) -> String:
	if st.is_empty() or (bool(st.get("counting", false)) and int(st.get("perfect_count", 0)) == 0):
		return "…"
	return num(int(st.get("perfect_count", 0)))


static func _perfect_sub(st: Dictionary) -> String:
	if st.is_empty() or bool(st.get("counting", false)):
		return "Perfekte Spiele · wird gezählt"
	return "Perfekte Spiele"


static func _ach_value(st: Dictionary) -> String:
	if st.is_empty() or (bool(st.get("counting", false)) and int(st.get("unlocked", 0)) == 0):
		return "…"
	return num(int(st.get("unlocked", 0)))


static func _ach_sub(st: Dictionary) -> String:
	if st.is_empty() or bool(st.get("counting", false)):
		return "Erfolge · wird gezählt"
	if int(st.get("started", 0)) <= 0:
		return "Erfolge"
	return "Erfolge · Ø %d %%" % int(round(float(st.get("avg", 0.0))))


# --- Freunde, perfekte Spiele, seltenste Erfolge ---------------------------------------------

## Freunde als Kacheln: wer spielt, zuerst, dann wer online ist. A: was man mit der Person tun kann.
func _freunde(col: VBoxContainer) -> void:
	var fr := Buehne.freunde_reihe(Social.steam_friends, 10)
	var list: Array = fr.get("list", [])
	if list.is_empty():
		return
	col.add_child(title("Freunde", ("%d online" % int(fr.online)) if int(fr.online) > 0 else ""))
	var shelf = Shelf.new().setup("prof:freunde", 24, true, SHELF_PAD, G, SHELF_PAD + 6)
	col.add_child(view._tight(shelf))
	for i in list.size():
		var f: Dictionary = list[i]
		var k := PB.freund(f, "prof:freund:" + str(f.get("id", "")), "Mehr", func() -> void: view.main.open_friend(f, "steam"))
		if i == 0:
			k.set_meta("uz_entry", true)
		shelf.add(k)


func _perfect(col: VBoxContainer) -> void:
	var list: Array = Achievements.steam_perfect()
	if list.is_empty():
		return
	col.add_child(title("Perfekte Spiele", "100 % bei Steam · " + U.plural(list.size(), "Spiel", "Spiele")))
	var shelf = Shelf.new().setup("prof:perfect", 24, true, SHELF_PAD, G, SHELF_PAD + 6)
	col.add_child(view._tight(shelf))
	for i in list.size():
		var tile: Control = view._game_tile(list[i])
		if i == 0:
			tile.set_meta("uz_entry", true)
		shelf.add(tile)


func _rarest(col: VBoxContainer) -> void:
	var list: Array = Achievements.steam_rarest(10)
	if list.is_empty():
		return
	col.add_child(title("Seltenste Erfolge", "die wenigsten Spieler haben sie"))
	_cards(col, list, "prof:rare")


func _cards(col: VBoxContainer, list: Array, group: String) -> void:
	var shelf = Shelf.new().setup(group, 24, true, SHELF_PAD, G, SHELF_PAD + 6)
	col.add_child(view._tight(shelf))
	for i in list.size():
		var a: Dictionary = list[i]
		var card = UnlockCard.new()
		card.a = a
		card.set_meta("uz_key", "%s:%s:%s" % [group, a.get("game", ""), a.get("title", "")])
		card.set_meta("uz_hint_a", "Erfolge des Spiels")
		if i == 0:
			card.set_meta("uz_entry", true)
		card.chosen.connect(func() -> void: view._open_unlock(a))
		shelf.add(card)


# --- RetroAchievements -------------------------------------------------------------------

func _retro(col: VBoxContainer) -> void:
	var ra: Dictionary = Achievements.ra_profile
	var rs: Dictionary = Achievements.ra_stats()
	col.add_child(U.spacer(0, 6, false))
	var hm := U.margin(G, 0, G, 0)
	var head := U.hbox(22)
	hm.add_child(head)
	var name_ := str(ra.get("name", Config.get_value("accounts.ra_user", "")))
	var av := Avatar.new()
	av.setup(name_, str(ra.get("pic", "")), "", 72)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(av)
	var hv := U.vbox(0)
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hv)
	var hl := U.label("RetroAchievements", "l", "text", "bold")
	hl.clip_text = false
	hv.add_child(hl)
	var bits := PackedStringArray([name_])
	if int(ra.get("member_since", 0)) > 0:
		bits.append("dabei seit " + SocialS.month_year(int(ra.member_since)))
	if int(ra.get("rank", 0)) > 0:
		bits.append("Rang " + num(int(ra.rank)))
	var sl := U.label("  ·  ".join(bits), "m", "muted", "medium")
	sl.clip_text = false
	hv.add_child(sl)
	col.add_child(hm)
	if ra.is_empty() and Achievements.loading:
		# Platzhalter in der Form der Zeile statt „Wird geladen …“ (nichts springt, wenn sie kommt).
		var lm := U.margin(G, 0, G, 0)
		lm.add_child(Skeleton.new().setup(Vector2(U.room_w(G), 120), UzTheme.r_panel()))
		col.add_child(lm)
		return
	var soft := int(ra.get("softcore", 0))
	col.add_child(PB.zahlen([
		[num(int(ra.get("points", 0))), "Hardcore-Punkte" + ((" · %s Softcore" % num(soft)) if soft > 0 else "")],
		[num(int(ra.get("true_points", 0))), "RetroPoints"],
		[num(int(rs.mastered)), "Gemeistert" + ((" · %d Hardcore" % int(rs.mastered_hc)) if int(rs.mastered) > 0 else "")],
		[num(int(rs.beaten)), "Durchgespielt · von %s" % U.plural(int(rs.games), "Spiel", "Spielen")],
	], "prof:ra", "Alle RA-Spiele", func() -> void: view.jump("retro")))
	var recent: Array = Achievements.recent_unlocks.filter(func(a): return str(a.get("source", "")) == "ra").slice(0, 12)
	if not recent.is_empty():
		col.add_child(title("Zuletzt bei RetroAchievements", U.plural(recent.size(), "Erfolg", "Erfolge")))
		_cards(col, recent, "prof:ra_recent")


# --- Bausteine (auch fürs Freundesprofil, friend_profile.gd) ------------------------------

## Überschrift einer Reihe wie in allen Bereichen: fett, daneben leiser ein Zusatz.
static func title(text: String, extra := "") -> Control:
	return PB.title(text, extra)


## Eine Angabe in der Zeile unter dem Namen: kleines Symbol und Wort, davor ein Punkt (den die
## Zeile beim ersten Eintrag ausblendet) – keine Pille.
static func chip(icon_name: String, text: String) -> Control:
	var h := U.hbox(9)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := U.label("·", "s", "faint", "medium")
	dot.name = "Dot"
	dot.clip_text = false
	h.add_child(dot)
	var ic := U.icon(icon_name, 18, "muted")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := U.label(text, "s", "muted", "medium")
	l.clip_text = false
	h.add_child(l)
	return h


## Eine Kachel „in Zahlen“ (Symbol, Bezeichnung, große Zahl, ein Satz darunter); A ruft on_pick.
static func stat(icon_name: String, label: String, value: String, sub: String, key: String, hint: String, on_pick: Callable) -> Stat:
	var tile := Stat.new()
	tile.setup(icon_name, label, value, sub, Vector2(414, 200))
	tile.set_meta("uz_key", key)
	tile.set_meta("uz_hint_a", hint)
	if on_pick.is_valid():
		tile.chosen.connect(func() -> void: on_pick.call())
	return tile


## Reihe für Cover (cover()): Luft fürs Anheben, links bündig mit dem Seitenrand.
static func cover_shelf(group: String) -> ScrollContainer:
	return PB.cover_shelf(group)


## Ein Steam-Spiel als Cover mit zwei Zeilen darunter (eigenes Spiel: Bild und Titel aus der
## Bibliothek). A ruft on_pick.
static func cover(appid: int, title_: String, line1: String, line2: String, key: String, hint: String, entry: bool, on_pick: Callable) -> Control:
	var g := Library.get_game("steam:%d" % appid)
	if g.is_empty():
		g = { "id": "steam:%d" % appid, "title": title_, "source": "steam", "system": "steam", "appid": appid }
	return PB.cover_game(g, line1, line2, key, hint, entry, on_pick)


## 6.873 statt 6873
static func num(n: int) -> String:
	return Buehne.tausender(n)


## Spielzeit aus Minuten: „45 Min.“, „3,5 Std.“, „6.873 Std.“
static func hours(minutes: int) -> String:
	if minutes < 600:
		return SocialS.hours(minutes) if minutes > 0 else "0 Std."
	return "%s Std." % num(int(round(minutes / 60.0)))


## Kopf einer Profilseite (eigenes Profil und Steam-Freunde): breite Karte mit Hintergrund
## (Bild oder Licht in der Farbe des Profilbilds), großes Profilbild mit Statusring, leiser
## Kicker (nur, wenn er etwas sagt: „Freundschaftsanfrage“), Name, Status, Angaben als eine
## Zeile, Info-Text, Knöpfe (actions) und rechts der Level-Ring. Alles lässt sich nachträglich
## setzen, ohne dass der Kopf neu gebaut wird (Fokus auf den Knöpfen bleibt).
class Banner extends MarginContainer:
	var art: Control
	var avatar: Control
	var status: Label
	var chips: HFlowContainer
	var actions: HBoxContainer       ## Knöpfe hier hinein
	var _bio_box: VBoxContainer
	var _row: HBoxContainer
	var _side: VBoxContainer
	var _art_prio := -1
	var _status_ph: Control          ## Platzhalter der Zeile, solange das Profil lädt
	var _kopf: Control               ## wählbarer Rahmen um das Profilbild (make_focusable)
	## Große Oberfläche (schmal): kleineres Bild, engere Abstände, ohne Level-Ring rechts (das
	## Level steht ohnehin in den Angaben darunter).
	var _narrow := false

	func setup(name_: String, avatar_url: String, state: String, ring: bool, kicker: String, top := 8) -> void:
		for k in ["margin_left", "margin_right"]:
			add_theme_constant_override(k, G)
		add_theme_constant_override("margin_top", top)
		add_theme_constant_override("margin_bottom", 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel()))
		card.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		card.custom_minimum_size = Vector2(0, BANNER_H)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(card)
		art = _Art.new()
		art.set("hue", Avatar.hue_color(name_))
		card.add_child(art)
		_narrow = U.room_w(G) < NARROW_W
		var pad := U.margin(40 if _narrow else 52, 44, 40 if _narrow else 52, 40)
		card.add_child(pad)
		_row = U.hbox(30 if _narrow else 44)
		pad.add_child(_row)
		var av := Avatar.new()
		av.setup(name_, avatar_url, state, 128 if _narrow else 184)
		av.ring = ring
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(av)
		avatar = av
		# Ohne Bild im Hintergrund nimmt das Licht die Farbe des Profilbilds an (Media-Bild mit
		# vorab bestimmter Farbe, kein Zurücklesen von der Grafikkarte).
		av.texture_loaded.connect(_tint)
		if av.texture() != null:
			_tint.call_deferred(av.texture())
		var info := U.vbox(6)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Senkrecht mittig neben dem Bild (oben angeschlagen wirkte der Text zu hoch).
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(info)
		var kl := U.label(kicker, "s", "muted", "medium")
		kl.clip_text = false
		kl.visible = kicker != ""
		info.add_child(kl)
		var nl := U.ellipsis(U.label(name_, "hero", "text", "title"))
		nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # der eigene Name: nie übersetzen
		nl.set_meta("uz_titel", true)
		U.shadow(nl, 0.4)
		info.add_child(nl)
		status = U.ellipsis(U.label("", "l", "muted", "medium"))
		status.visible = false
		info.add_child(status)
		var lh := UzTheme.font("medium").get_height(UzTheme.size("l"))
		_status_ph = U.margin(0, 6, 0, 6)
		_status_ph.add_child(Skeleton.new().setup(Vector2(260, maxf(8.0, lh - 12.0)), 8))
		_status_ph.visible = false
		info.add_child(_status_ph)
		info.add_child(U.spacer(0, 6, false))
		chips = HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 12)
		chips.add_theme_constant_override("v_separation", 6)
		chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chips.child_entered_tree.connect(func(_n: Node) -> void: _dots.call_deferred())
		info.add_child(chips)
		_bio_box = U.vbox(0)
		info.add_child(_bio_box)
		var luft := U.spacer(0, 14, false)
		luft.visible = false
		info.add_child(luft)
		actions = U.hbox(14)
		actions.visible = false
		# Leer (eigenes Profil) nimmt die Knopfzeile keinen Platz; mit Knöpfen kommt sie samt Luft.
		actions.child_entered_tree.connect(func(_n: Node) -> void:
			actions.visible = true
			luft.visible = true)
		info.add_child(actions)

	## Das Profilbild wird wählbar: A ruft on_a (Hinweis hint_a), Y on_y (hint_y, "" ohne).
	func make_focusable(hint_a: String, on_a: Callable, hint_y := "", on_y := Callable()) -> void:
		if _kopf != null or not is_instance_valid(avatar):
			return
		var k := _Kopf.new()
		k.px = avatar.get("px")
		k.on_a = on_a
		k.set_meta("uz_key", "prof:kopf")
		k.set_meta("uz_default", true)
		k.set_meta("uz_hint_a", hint_a)
		if hint_y != "" and on_y.is_valid():
			k.set_meta("uz_hint_y", hint_y)
			k.set_meta("uz_on_y", on_y)
		var at := avatar.get_index()
		_row.remove_child(avatar)
		k.add_child(avatar)
		avatar.position = Vector2.ZERO
		_row.add_child(k)
		_row.move_child(k, at)
		_kopf = k

	## wartet: Das Profil lädt noch – ein ruhiger Platzhalter in der Höhe der Zeile statt Text.
	func set_status(text: String, ok: bool, wartet := false) -> void:
		status.text = text
		status.visible = text != "" and not wartet
		if is_instance_valid(_status_ph):
			_status_ph.visible = wartet
		U.set_label_color(status, "ok" if ok else "muted")

	## Platz für Angaben (Chips) und zwei Zeilen Info-Text von Anfang an: Kommen die Daten nach,
	## behält der Kopf seine Höhe (eigenes Profil).
	func reserve() -> void:
		var ch := UzTheme.font("medium").get_height(UzTheme.size("s"))
		chips.custom_minimum_size.y = maxf(20.0, ch) + 6.0
		chips.visible = true
		var bh := UzTheme.font("regular").get_height(UzTheme.size("m"))
		_bio_box.custom_minimum_size.y = 6.0 + 2.0 * (bh + 4.0)

	## list: [[Symbol, Text], …] – eine leise Zeile, Angaben durch Punkte getrennt.
	func set_chips(list: Array) -> void:
		U.clear(chips)
		for c in list:
			chips.add_child(ProfilePageS.chip(str(c[0]), str(c[1])))
		# Reservierter Platz (reserve) bleibt, auch ohne Angaben.
		chips.visible = not list.is_empty() or chips.custom_minimum_size.y > 0.0
		_dots()

	## Der Punkt vor jeder Angabe – außer vor der ersten (auch, wenn später eine dazukommt).
	func _dots() -> void:
		if not is_instance_valid(chips):
			return
		var first := true
		for c in chips.get_children():
			if c.is_queued_for_deletion():
				continue
			var d := c.get_node_or_null("Dot") as Control
			if d:
				d.visible = not first
			first = false

	## Info-Text; leer und loading: ein ruhiger Platzhalter, bis er da ist.
	func set_bio(text: String, loading := false) -> void:
		U.clear(_bio_box)
		if text != "":
			var bl := U.label(text, "m", "text", "regular", true)
			# Info-Text aus dem Profil (von Steam, in irgendeiner Sprache): nie durch die Übersetzung. Eigene Sätze
			# („… ist privat“) kommen schon übersetzt herein.
			bl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			bl.max_lines_visible = 3
			# Breit wie gebaut, auf schmaleren Flächen (größere Oberfläche) entsprechend weniger.
			bl.custom_minimum_size = Vector2(clampf(U.view_size().x - 1040.0, 480.0, 880.0), 0)
			bl.modulate.a = 0.86
			_bio_box.add_child(U.spacer(0, 6, false))
			_bio_box.add_child(bl)
		elif loading:
			_bio_box.add_child(U.spacer(0, 8, false))
			_bio_box.add_child(Skeleton.new().setup(Vector2(640, 24), 8))

	## Level-Ring rechts; lv < 0: privat („–“), pending: wird noch geladen („…“). caption ersetzt
	## die Zeile darunter (etwa „Level unbekannt“, wenn Steam nicht antwortet).
	func set_level(lv: int, pending: bool, caption := "") -> void:
		if _narrow:
			return
		if _side == null:
			_side = U.vbox(10)
			_side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_side.alignment = BoxContainer.ALIGNMENT_CENTER
			_row.add_child(_side)
		U.clear(_side)
		var ring := Ring.new().setup(1.0 if lv >= 0 else 0.0, 150, 10, str(lv) if lv >= 0 else ("…" if pending else "–"), "", "Level")
		ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_side.add_child(ring)
		if caption == "":
			caption = "Steam-Level" if lv >= 0 or pending else "Level privat"
		var cap := U.label(caption, "s", "muted", "medium")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_side.add_child(cap)

	## Bild in den Hintergrund; ein Bild mit höherem Rang (Profilhintergrund: 2, Spielbild: 1)
	## wird von einem niedrigeren nicht mehr verdrängt.
	func show_art(t: Texture2D, prio: int) -> void:
		if t == null or prio < _art_prio or not is_instance_valid(art):
			return
		_art_prio = prio
		art.call("show_texture", t)

	func load_url(url: String, prio: int) -> void:
		var wr: WeakRef = weakref(self)
		Media.url_texture(url, 1920, func(t: Texture2D) -> void:
			var b: Variant = wr.get_ref()
			if b != null:
				b.call("show_art", t, prio)
		)

	## Großes Bild des Spiels (sonst das breite Kapselbild).
	func load_game(appid: int, title_: String, prio: int) -> void:
		if appid <= 0:
			return
		var g := Library.get_game("steam:%d" % appid)
		if g.is_empty():
			g = { "id": "steam:%d" % appid, "title": title_, "source": "steam", "system": "steam", "appid": appid }
		var wr: WeakRef = weakref(self)
		Media.game_texture(g, "hero", func(t: Texture2D) -> void:
			var b: Variant = wr.get_ref()
			if b == null:
				return
			if t != null:
				b.call("show_art", t, prio)
			else:
				Media.game_texture(g, "wide", func(t2: Texture2D) -> void:
					var b2: Variant = wr.get_ref()
					if b2 != null:
						b2.call("show_art", t2, prio)
				)
		)

	func _tint(t: Texture2D) -> void:
		if t == null or not t.has_meta("uz_vivid"):
			return
		var c: Variant = Media.color_of(t)
		if c is Color and is_instance_valid(art):
			art.set("hue", c)
			art.queue_redraw()


## Wählbarer Rahmen um das Profilbild: runde Lichtkante mit Schein wie bei Kacheln, hebt sich
## leicht; A ruft on_a, Y liegt als Meta an (uz_on_y).
class _Kopf extends Control:
	signal chosen
	const UU := preload("res://src/ui/u.gd")
	var px := 184
	var on_a: Callable
	var _lift := 0.0

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		custom_minimum_size = Vector2(px, px)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		focus_entered.connect(_on_focus.bind(true))
		focus_exited.connect(_on_focus.bind(false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event())

	func _on_focus(on: bool) -> void:
		UU.focus_anim(self, on)
		var wr: WeakRef = weakref(self)
		UU.ankommen(self, UU.T_ANTWORT, "uz_lift").tween_method(func(v: float) -> void:
			var me: Control = wr.get_ref()
			if me:
				me.set("_lift", v)
				for c in me.get_children():
					if c is Control:
						(c as Control).position.y = -v
				me.queue_redraw()
		, _lift, 6.0 if on else 0.0, UU.T_ANTWORT)

	func activate() -> void:
		if on_a.is_valid():
			on_a.call()
		chosen.emit()

	func _draw() -> void:
		var f: float = float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0
		if f > 0.01:
			UzTheme.draw_tile_focus(self, Rect2(Vector2(0, -_lift), Vector2(px, px)).grow(4), int(px * 0.5) + 4, f)


## Kachel mit Zahl, deren Werte sich nachträglich ändern lassen (Zählung läuft).
class Stat extends "res://src/ui/components/ach/stat_tile.gd":
	var _val: Label
	var _sub: Label

	func build_body() -> void:
		var m := U.margin(28, 26, 28, 24)
		U.full_rect(m)
		body.add_child(m)
		var col := U.vbox(6)
		m.add_child(col)
		var head := U.hbox(12)
		head.add_child(U.icon(icon_name, 26, "accent"))
		var l := U.label(label, "s", "muted", "medium")
		l.clip_text = false
		head.add_child(l)
		col.add_child(head)
		col.add_child(U.spacer(0, 8, false))
		_val = U.ellipsis(U.label(value, "xl", "faint" if value in ["…", "–"] else "text", "black"))
		col.add_child(_val)
		_sub = U.label(sub, "s", "muted", "regular", true)
		_sub.max_lines_visible = 2
		col.add_child(_sub)

	func set_values(v: String, s: String) -> void:
		value = v
		sub = s
		if is_instance_valid(_val):
			_val.text = v
			U.set_label_color(_val, "faint" if v in ["…", "–"] else "text")
		if is_instance_valid(_sub):
			_sub.text = s


## Hintergrund des Banners: Bild (zugeschnitten, abgedunkelt) oder ein Licht in der Farbe des
## Namens; links und unten läuft es in den Grund aus, damit die Schrift lesbar bleibt.
class _Art extends Control:
	var hue := Color(0.4, 0.3, 0.6)
	var tex: Texture2D
	var _a := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_texture(t: Texture2D) -> void:
		tex = t
		var wr: WeakRef = weakref(self)
		# Weich über das Licht (Hintergrund: T_LICHT, sine in-out).
		U.tw(self, "uz_art", Tween.TRANS_SINE, Tween.EASE_IN_OUT).tween_method(func(v: float) -> void:
			var me: Control = wr.get_ref()
			if me:
				me.set("_a", v)
				me.queue_redraw()
		, _a, 1.0, U.T_LICHT)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, UzTheme.col("surface"))
		var glow := U.fade_texture(false, true)
		# Licht: rechts oben in der Farbe des Profils, links unten ein Hauch des Akzents.
		draw_texture_rect(glow, r, false, Color(hue, 0.55))
		draw_texture_rect(U.fade_texture(true), Rect2(0, 0, size.x, size.y * 0.7), false, Color(hue.lightened(0.15), 0.18))
		draw_circle(Vector2(size.x * 0.82, size.y * 0.15), size.y * 0.9, Color(hue, 0.10))
		draw_circle(Vector2(size.x * 0.12, size.y * 1.1), size.y * 0.6, UzTheme.col("accent", 0.05))
		if tex != null and _a > 0.0:
			var ts := tex.get_size()
			var k := maxf(size.x / ts.x, size.y / ts.y)
			var src := Rect2((ts - size / k) * 0.5, size / k)
			draw_texture_rect_region(tex, r, src, Color(0.78, 0.78, 0.8, _a))
		var ground := UzTheme.col("bg")
		draw_texture_rect(U.fade_texture(false), Rect2(0, 0, size.x * 0.78, size.y), false, Color(ground, 0.82))
		draw_texture_rect(U.fade_texture(true, true), Rect2(0, size.y * 0.45, size.x, size.y * 0.55), false, Color(ground, 0.55))
