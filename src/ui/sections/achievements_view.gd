extends "res://src/ui/sections/section.gd"
## Profil: vorne das eigene Profil (Steam und RetroAchievements, siehe profile_page.gd), dahinter
## die Erfolge aus beiden Quellen – wie ein Trophäenschrank: oben der Stand über alle Spiele
## (Ring und Zahlen) und die Vitrine mit den besten Momenten, darunter die zuletzt
## freigeschalteten Erfolge, was als Nächstes greifbar ist, Spiele kurz vor 100 % und die
## kompletten. „Freunde“: Rangliste der Woche, was Freunde freigeschaltet haben (Feed) und
## Greifbares (Achievements.friends). Je Quelle ein Raster aller Spiele, dazu die Spielzeit und
## dein Backlog (backlog_page.gd).
## Ohne Konto, ohne Netz und beim Laden steht eine gestaltete Seite statt einer leeren Fläche.


const Ach := preload("res://src/core/achievements.gd")
const Lang := preload("res://src/core/lang.gd")
const Friends := preload("res://src/core/achievements_friends.gd")
const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")
const BacklogPage := preload("res://src/ui/sections/backlog_page.gd")
const ProfilePage := preload("res://src/ui/sections/profile_page.gd")
const Ring := preload("res://src/ui/components/ach/ring.gd")
const UnlockCard := preload("res://src/ui/components/ach/unlock_card.gd")
const GameTile := preload("res://src/ui/components/ach/game_tile.gd")
const Cabinet := preload("res://src/ui/components/ach/cabinet.gd")
const DataBlock := preload("res://src/ui/components/data_block.gd")
const EdgeFade := preload("res://src/ui/components/ach/edge_fade.gd")
const Vitrine := preload("res://src/ui/components/ach/vitrine.gd")
const FeedRow := preload("res://src/ui/components/ach/feed_row.gd")
const RankTile := preload("res://src/ui/components/ach/rank_tile.gd")
const ReachCard := preload("res://src/ui/components/ach/reach_card.gd")
const Rarity := preload("res://src/ui/components/ach/rarity.gd")
const GameAch := preload("res://src/ui/layers/game_achievements.gd")

const SHELF_PAD := 30        ## Platz über/unter Kachelreihen: Anheben, Ring und Schatten passen hinein
const MOMENTS := 5           ## Plätze in der Vitrine
const FEED_ROWS := 20        ## Zeilen im Freunde-Feed
const RANK_TILES := 8        ## Plätze in der Rangliste

static var _seen := {}       ## schon gezeigte Freischaltungen (frische leuchten nur einmal auf)
var _shown_data := false     ## diese Seite hat schon einmal Daten gezeigt
var _shown_once := false     ## die Übersicht stand schon einmal da (Neues danach kommt „live“)
var _lib := {}               ## Titel (vereinfacht) -> Spiel aus der Bibliothek
var _lib_ra := {}            ## RetroAchievements-ID (von Hand eingetragen) -> Spiel
var _lib_alt := true         ## beide stammen von vor dem letzten Aufbau: beim nächsten Nachschlagen neu bilden
var _profile: ProfilePage     ## Profilseite, solange sie steht (für die Zählung)
var _came_from := ""         ## Unterbereich, aus dem ein Knopf hierher gesprungen ist (B kehrt dorthin)
var _came_key := ""          ## uz_key des Knopfs, der gedrückt wurde
var _backlog_due := false    ## Backlog geändert, während er zu sehen ist: einmal neu aufbauen
var _bau_wartet := false     ## ein Neuaufbau wartet auf das Ende eines Wechsels

# --- Unterseiten: Vorrat und Nachbau -----------------------------------------------------------
# Switching between profile sub-pages lagged noticeably. Measured (LB/RB through all sub-pages): every switch
# rebuilt the sub-page from scratch – profile and achievements about 750 nodes each, 55–100 ms in one go, right
# during the key press. Only about 10 ms of that is for what is visible first. In addition, the transition
# re-parented the old page for the fade-out (U.abgang): another 6–31 ms depending on the page. Therefore:
#   – Each sub-page lives in its own wrapper covering the whole area (_seiten). On a switch the old wrapper
#     fades out in place and the new one fades in – nothing is re-parented (switch_sub, _seite_geht).
#   – Cache (Vorrat): a finished sub-page stays in place, invisible, and returns when switching back, as long as
#     its data has not changed, for at most VORRAT_MS (relative times such as „Heute“ would go stale).
#   – Deferred build (Nachbau): whatever lies below the first screen is built only after the page has slid in,
#     and then only as much per frame as fits into NACHBAU_MS (nachbau).
const VORRAT_MS := 600000
const NACHBAU_MS := 5.0

var _seiten := {}            ## Unterseite -> Hülle (Control über den ganzen Bereich) mit dem fertigen Inhalt
var _seiten_stand := {}      ## Unterseite -> { nr (Stand der Daten beim Aufbau), ms (wann gebaut), profile }
var _ziel: Control           ## die Hülle, in die build() gerade baut
var _daten_nr := 0           ## zählt mit jeder Änderung an den Daten: Was davor gebaut wurde, ist alt
var _steht := ""             ## die Unterseite, die gerade zu sehen ist
var _im_wechsel := false     ## build() läuft aus switch_sub: Der Vorrat gilt


func _init() -> void:
	super()
	id = "achievements"
	title = "Profil"
	icon_name = "user"
	Achievements.updated.connect(func(w: String) -> void:
		if not visible or sub == "statistik" or sub == "backlog":
			return
		if w == "profile_count":
			if sub == "profil" and _profile != null:
				_profile.update_counts()
		elif w == "overview" or w == "profile":
			# Kommen Übersicht und Profil nacheinander, wird einmal gebaut, wenn beide da sind –
			# nicht zweimal hintereinander über die Platzhalter.
			if (Achievements.loading or Achievements.profile_loading) and not _shown_ok():
				return
			_bald_bauen()
	)
	keep_built = true
	stale_keys = PackedStringArray(["achievements.", "accounts.", "library.", "systems."])
	# Die laufende Zählung (profile_count) macht die Seite nicht alt: Die Zahlen zieht die
	# Profilseite selbst nach (sichtbar sofort, sonst beim Betreten in reenter) – sonst baute jeder
	# Besuch während der Zählung alles neu.
	Achievements.updated.connect(func(w: String) -> void:
		if w != "profile_count":
			mark_stale()
	)
	Library.changed.connect(mark_stale)
	# Backlog: Änderungen (auch aus der Spielseite darüber) gleich zeigen – einmal je Bild.
	Library.changed.connect(_on_backlog_data)
	Library.backlog_changed.connect(_on_backlog_data)
	# Freunde-Feed und -Stände kommen später an: die Seite „Freunde“ baut sich dann weich neu.
	if Achievements.friends:
		Achievements.friends.updated.connect(func(_w: String) -> void:
			if is_visible_in_tree() and sub == "freunde":
				_bald_bauen()
		)


func subtabs() -> Array:
	var out: Array = [{ "id": "profil", "label": "Profil" }, { "id": "uebersicht", "label": "Erfolge" }]
	if _friends_possible():
		out.append({ "id": "freunde", "label": "Freunde" })
	out.append({ "id": "statistik", "label": "Spielzeit" })
	out.append({ "id": "backlog", "label": "Backlog" })
	if Achievements.has_ra():
		out.append({ "id": "retro", "label": "RetroAchievements", "count": Achievements.ra_progress.size() })
	if Achievements.has_steam():
		out.append({ "id": "steam", "label": "Steam", "count": Achievements.steam_progress.size() })
	return out


func on_leave() -> void:
	# Was bis jetzt da war, ist beim nächsten Mal nicht mehr „Neu“.
	# Nur wenn wirklich etwas Neues zu sehen war – sonst baute jeder Besuch die Seite neu auf.
	if _shown_once and not Achievements.recent_unlocks.is_empty():
		var seen_at := int(Config.get_value("achievements.seen_at", 0))
		var newest := 0
		for a in Achievements.recent_unlocks:
			newest = maxi(newest, int((a as Dictionary).get("date", 0)))
		if seen_at == 0 or newest > seen_at:
			Config.set_value("achievements.seen_at", int(Time.get_unix_time_from_system()))


func on_enter() -> void:
	var rebuild := false
	if (Achievements.has_ra() or Achievements.has_steam()) and Achievements.recent_unlocks.is_empty() and not Achievements.loading:
		Achievements.refresh_overview()
		rebuild = true
	if Achievements.has_steam() and not Achievements.profile_loading and (Achievements.steam_me.is_empty() or Achievements.steam_stats.is_empty()):
		Achievements.refresh_profile()
		rebuild = true
	if rebuild and sub != "statistik" and sub != "backlog":
		build()


## Beim Start (main._prebuild): Übersicht und Steam-Profil laden, wie es on_enter täte – nur ohne
## Aufbau (den macht main unsichtbar, sobald die Daten da sind).
func prefetch() -> void:
	if (Achievements.has_ra() or Achievements.has_steam()) and Achievements.recent_unlocks.is_empty() and not Achievements.loading:
		Achievements.refresh_overview()
	if Achievements.has_steam() and not Achievements.profile_loading and (Achievements.steam_me.is_empty() or Achievements.steam_stats.is_empty()):
		Achievements.refresh_profile()


func data_ready() -> bool:
	return not Achievements.loading and not Achievements.profile_loading


## Ohne Neuaufbau betreten: die Zahlen der Zählung nachziehen, die kamen, während der Bereich
## nicht zu sehen war.
func reenter() -> void:
	if sub == "profil" and _profile != null:
		_profile.update_counts()


## Neu aufbauen und die Auswahl dort lassen, wo sie war. Kamen gerade Daten an (animate), tritt
## die neue Seite weich an die Stelle der alten (kreuzen, gleicher Bildlauf): Die Platzhalter
## haben die Form der Daten, darum springt nichts – es füllt sich nur.
func _rebuild_keep_focus(animate: bool) -> void:
	var f := Nav.focused()
	var inside := f != null and is_ancestor_of(f)
	var key := str(f.get_meta("uz_key", "")) if inside else ""
	var sc := _bildlauf()
	var y := sc.scroll_vertical if sc else 0
	var weich := animate and is_visible_in_tree() and not has_meta("uz_skip")
	if weich:
		# Mitten im Hereinkommen nicht dazwischen: erst den Wechsel zu Ende laufen lassen (ein
		# Aufbau wartet; kommen derweil weitere Daten, baut er sie gleich mit).
		if _bau_wartet:
			return
		_bau_wartet = true
		while im_uebergang():
			await get_tree().process_frame
			if not is_visible_in_tree():
				_bau_wartet = false
				return
		_bau_wartet = false
		if Nav.focused() != f:
			f = Nav.focused()
			inside = f != null and is_ancestor_of(f)
			key = str(f.get_meta("uz_key", "")) if inside else ""
		U.stop(self, "uz_sec")
		U.stop(self, "uz_slide")
		modulate.a = 1.0
		offset_left = 0.0
		offset_right = 0.0
		# Was im Vorrat steht, ist mit den neuen Daten alt: gleich weg, damit nur die sichtbare Seite ausblendet.
		_vorrat_leeren(_steht)
		U.abgang(self, 0)
	build()
	# Die Auswahl gleich wieder setzen (noch im selben Bild: kein Bild ohne Cursor).
	if inside and Nav.top_layer() == null and key != "":
		for c in Nav.focusables(self):
			if str(c.get_meta("uz_key", "")) == key:
				Nav.focus(c, true)
				break
	if weich:
		U.ankunft(self, 0)
		# Ein Bild warten (darin ist der neue Inhalt noch unsichtbar): dann kennt der Bildlauf
		# seine Länge.
		await get_tree().process_frame
		var sc2 := _bildlauf()
		if sc2 and y > 0:
			sc2.scroll_vertical = y
	if not inside or Nav.top_layer() != null or not is_inside_tree():
		return
	if key != "":
		for c in Nav.focusables(self):
			if str(c.get_meta("uz_key", "")) == key:
				Nav.focus(c, true)
				return
	focus_default()


## Neue Daten kommen oft kurz nacheinander (Profil, dann die fertige Zählung): erst bauen, wenn
## BAU_RUHE lang nichts mehr kam – ein weicher Wechsel statt zwei.
const BAU_RUHE := 0.2
var _bau_folge := 0


func _bald_bauen() -> void:
	_bau_folge += 1
	var n := _bau_folge
	await get_tree().create_timer(BAU_RUHE).timeout
	if n == _bau_folge and is_inside_tree():
		_rebuild_keep_focus(true)


## Steht schon eine Seite mit Daten (nicht nur Platzhalter)? Dann zeigt jede Ankunft gleich.
func _shown_ok() -> bool:
	return sub == "profil" and not Achievements.steam_me.is_empty() or sub != "profil" and _shown_data and not Achievements.recent_unlocks.is_empty()


func _bildlauf() -> ScrollContainer:
	var s := _seite()
	if s == null:
		return null
	for c in s.get_children():
		if c is ScrollContainer:
			return c
	return null


## Ohne etwas zum Auswählen (Laden) auf den Unterbereich: keine Taste geht ins Leere.
func focus_default() -> void:
	var d := Nav.default_in(self)
	if d:
		Nav.focus(d, true)
		return
	if main and is_instance_valid(main.chips_box):
		for c in main.chips_box.get_children():
			if c.get_meta("uz_selected", false):
				Nav.focus(c, true)
				return


## Die Hülle der Unterseite, die gerade zu sehen ist (null: keine).
func _seite() -> Control:
	var w: Variant = _seiten.get(_steht)
	return (w as Control) if is_instance_valid(w) and w is Control else null


## LB/RB: Die alte Unterseite blendet an ihrem Platz aus, die neue ein – aus dem Vorrat, wenn sie dort steht.
## false: main baut wie bisher (kein sichtbarer Wechsel).
func switch_sub(dir := 0) -> bool:
	var alt := _seite()
	if dir == 0 or not is_visible_in_tree() or alt == null:
		return false
	var stand: Dictionary = _seiten_stand.get(_steht, {})
	var behalten := int(stand.get("nr", -1)) == _daten_nr and not _changed_since
	U.stop(self, "uz_sec")
	U.stop(self, "uz_slide")
	modulate.a = 1.0
	offset_left = 0.0
	offset_right = 0.0
	_seite_geht(alt, _steht, dir, behalten)
	_im_wechsel = true
	build()
	var neu := _seite()
	if neu:
		U.ankunft(neu, dir)
	return true


## Eine Unterseite geht: gleitet ein Stück gegen die Richtung und blendet aus (wie U.abgang, nur ohne Umhängen).
## behalten: Sie bleibt danach unsichtbar im Vorrat stehen; sonst gibt sie sich frei.
func _seite_geht(w: Control, sub_id: String, dir: int, behalten: bool) -> void:
	U.stop(w, "uz_ankunft")
	w.set_meta("uz_skip", true)
	if not behalten:
		_seiten.erase(sub_id)
		_seiten_stand.erase(sub_id)
	var t := U.weg(w, "uz_seite_tw").set_parallel(true)
	U.kreuz_aus(t, w)
	U.titel_weichen(w)
	var px := U.weg_px(U.W_ORT) * dir
	if px != 0.0:
		var x0 := w.offset_left
		t.tween_method(func(v: float) -> void:
			if is_instance_valid(w):
				w.offset_left = x0 - v
				w.offset_right = x0 - v
		, 0.0, px, U.T_WEG).set_trans(Tween.TRANS_CUBIC)
	t.chain().tween_callback(func() -> void: _seite_ruht(w, behalten))
	U.takt_halten(t)


## Nach dem Ausblenden: in den Vorrat (unsichtbar, ohne eigene Arbeit je Bild) oder weg.
func _seite_ruht(w: Control, behalten: bool) -> void:
	if not is_instance_valid(w) or w.is_queued_for_deletion():
		return
	if not behalten or w.has_meta("uz_weg"):
		if w.get_parent() != null:
			w.get_parent().remove_child(w)
		w.queue_free()
		return
	w.visible = false
	w.process_mode = Node.PROCESS_MODE_DISABLED
	_seite_ruhelage(w)


func _seite_ruhelage(w: Control) -> void:
	w.modulate.a = 1.0
	w.offset_left = 0.0
	w.offset_right = 0.0
	for k in ["uz_skip", "uz_ank_base"]:
		if w.has_meta(k):
			w.remove_meta(k)
	U.titel_zurueck(w)


## Die Unterseite aus dem Vorrat wieder zeigen, vorn angefangen. false: steht dort nicht (oder ist alt).
func _seite_zeigen(sub_id: String) -> bool:
	var w: Variant = _seiten.get(sub_id)
	var stand: Dictionary = _seiten_stand.get(sub_id, {})
	if not is_instance_valid(w) or not (w is Control) or int(stand.get("nr", -1)) != _daten_nr \
			or Time.get_ticks_msec() - int(stand.get("ms", 0)) > VORRAT_MS:
		_seite_weg(sub_id)
		return false
	var s := w as Control
	U.stop(s, "uz_seite_tw")
	_seite_ruhelage(s)
	s.process_mode = Node.PROCESS_MODE_INHERIT
	s.visible = true
	move_child(s, -1)
	for c in s.get_children():
		if c is ScrollContainer:
			(c as ScrollContainer).scroll_vertical = 0
	_steht = sub_id
	_profile = stand.get("profile") as ProfilePage
	_shown_data = true
	reset_position()
	_kanten_neu(s)
	# Die Zählung bei Steam lief weiter, während die Seite im Vorrat stand.
	if sub_id == "profil" and _profile != null:
		_profile.update_counts()
	return true


## Die weichen Kanten (EdgeFade) rechnen mit der Lage der Reihen, und die stimmt erst nach dem nächsten Layout:
## Stand die Seite weit unten im Vorrat, blieben die obersten Reihen sonst unsichtbar (ausgeblendet wie beim Rollen).
## In dem einen Bild bis dahin ist die Seite ohnehin noch durchsichtig (U.ankunft).
func _kanten_neu(s: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(s):
		return
	for c in s.get_children():
		if c is ScrollContainer:
			for f in c.get_children():
				if f.get_script() == EdgeFade:
					f.call("_update", 0.0)


## Eine Unterseite aus dem Vorrat nehmen und freigeben. Gleitet sie gerade hinaus, gibt sie sich danach selbst frei.
func _seite_weg(sub_id: String) -> void:
	var w: Variant = _seiten.get(sub_id)
	_seiten.erase(sub_id)
	_seiten_stand.erase(sub_id)
	if not is_instance_valid(w) or not (w is Control):
		return
	var s := w as Control
	if s.visible and s.has_meta("uz_skip"):
		s.set_meta("uz_weg", true)
		return
	if s.get_parent() != null:
		s.get_parent().remove_child(s)
	s.queue_free()


## Alles im Vorrat ist alt (die Daten haben sich geändert). ausser: Diese Unterseite bleibt stehen.
func _vorrat_leeren(ausser := "") -> void:
	for s in _seiten.keys():
		if str(s) != ausser:
			_seite_weg(str(s))


## Auch das Ein- und Ausblenden der Hüllen ist ein Wechsel (section.gd kennt nur den Bereich selbst).
func im_uebergang() -> bool:
	if super():
		return true
	for c in get_children():
		for k in ["uz_ankunft", "uz_seite_tw"]:
			var t: Variant = c.get_meta(k) if c.has_meta(k) else null
			if t != null and is_instance_valid(t) and t is Tween and (t as Tween).is_valid() and (t as Tween).is_running():
				return true
	return false


## Abschnitte unter dem ersten Bildschirm: nicht im Tastendruck bauen, sondern danach. Wartet, bis die Seite
## hereingeglitten ist (im_uebergang), und baut dann je Bild, was in NACHBAU_MS passt. Hängt an der Spalte: Wird
## die Seite neu gebaut, endet es; liegt sie inzwischen im Vorrat, baut es dort zu Ende. Ohne Baum (Tests) sofort.
func nachbau(col: VBoxContainer, schritte: Array) -> void:
	if schritte.is_empty():
		return
	if not is_inside_tree() or not is_visible_in_tree():
		for s in schritte:
			(s as Callable).call()
		return
	await get_tree().process_frame
	while is_inside_tree() and is_instance_valid(col) and im_uebergang():
		await get_tree().process_frame
	var i := 0
	while i < schritte.size():
		if not is_instance_valid(col) or not is_inside_tree():
			return
		var t0 := Time.get_ticks_usec()
		while i < schritte.size() and (Time.get_ticks_usec() - t0) < NACHBAU_MS * 1000.0:
			(schritte[i] as Callable).call()
			i += 1
		await get_tree().process_frame


func build() -> void:
	# Nur der Wechsel mit LB/RB (switch_sub) lebt aus dem Vorrat. Jeder andere Aufbau heißt: Es hat sich etwas
	# geändert – dann ist auch alt, was dort steht.
	var wechsel := _im_wechsel
	_im_wechsel = false
	if not wechsel:
		_daten_nr += 1
		U.clear(self)
		_seiten.clear()
		_seiten_stand.clear()
	elif _changed_since:
		_daten_nr += 1
		_vorrat_leeren()
	mark_built()
	if wechsel and _seite_zeigen(sub):
		return
	_seite_weg(sub)
	_ziel = Control.new()
	_ziel.name = "Seite"
	_ziel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_ziel)
	add_child(_ziel)
	_seiten[sub] = _ziel
	_seiten_stand[sub] = { "nr": _daten_nr, "ms": Time.get_ticks_msec(), "profile": null }
	_steht = sub
	_profile = null
	_bauen()
	(_seiten_stand[sub] as Dictionary)["profile"] = _profile


func _bauen() -> void:
	if sub == "statistik":
		_build_stats()
		return
	if sub == "backlog":
		_build_backlog()
		return
	if not Achievements.has_ra() and not Achievements.has_steam():
		# Die Bühne mit angedeuteten Medaillen; A meldet per QR-Code bei Steam an, daneben
		# RetroAchievements für Emulator-Spiele. Danach kommen die Erfolge im Takt herein.
		# (Level und Abzeichen: Guide › „Dein Status“ › Abzeichen.)
		_ziel.add_child(leer_buehne({ "art": "erfolge", "symbol": "trophy", "titel": "Alle Erfolge an einem Ort.",
			"zeile": "Steam und RetroAchievements zusammen.", "knopf": "Steam verbinden", "tun": LeerBuehne.weg(main, "steam"),
			"neben": "RetroAchievements", "neben_tun": LeerBuehne.weg(main, "retro"),
			"fertig": func() -> bool: return Achievements.has_ra() or Achievements.has_steam(), "neu": func() -> void:
				if Achievements.loading:
					build()
				else:
					_reload() }))
		return
	if sub == "profil":
		_build_profile()
		return
	if sub == "freunde":
		_build_freunde()
		return
	var empty := Achievements.ra_progress.is_empty() and Achievements.steam_progress.is_empty() and Achievements.recent_unlocks.is_empty()
	if empty and Achievements.loading:
		_ziel.add_child(_loading_page())
		return
	if empty and Achievements.last_error != "":
		_ziel.add_child(_state_page("Gerade keine Verbindung", Achievements.last_error + " Deine Spiele und die Spielzeit gehen trotzdem.",
			[["Nochmal versuchen", "refresh", func() -> void: _reload()],
			["Konten prüfen", "user", func() -> void: main.goto("settings", "konten")]], true))
		return
	if empty:
		_ziel.add_child(_state_page("Noch keine Erfolge",
			"Freigeschaltete Erfolge mit Seltenheit und Fortschritt.",
			[["Zu den Spielen", "games", func() -> void: main.goto("games")]], false))
		return
	_shown_data = true
	_lib_alt = true
	var col := U.vbox(30)
	var sc := scroll_v(col)
	# Wenig Rand: die ersten beiden Reihen passen ohne Rollen unter den Kopf.
	sc.set_meta("uz_pad_v", 56.0)
	U.full_rect(sc)
	_ziel.add_child(sc)
	EdgeFade.attach(sc, col)
	col.add_child(U.spacer(0, 4, false))
	# Den Abstand am Ende setzen die Seiten selbst – als letzten Schritt ihres Nachbaus.
	match sub:
		"retro":
			_source_page(col, "retro")
		"steam":
			_source_page(col, "steam")
		_:
			_overview(col)
			_shown_once = true


func _reload() -> void:
	if Achievements.loading:
		return
	Achievements.refresh_overview()
	if Achievements.has_steam():
		Achievements.refresh_profile(true)
	_rebuild_keep_focus(false)


# --- Profil -----------------------------------------------------------------------------

func _build_profile() -> void:
	_shown_data = true
	_lib_alt = true
	var col := U.vbox(30)
	var sc := scroll_v(col)
	sc.set_meta("uz_pad_v", 120.0)
	U.full_rect(sc)
	_ziel.add_child(sc)
	EdgeFade.attach(sc, col)
	_profile = ProfilePage.new()
	_profile.build(self, col)
	# Banner oben: wer dort landet, sieht ihn ganz (Profilbild und Hintergrund), wie beim Betreten.
	if col.get_child_count() > 0:
		sc.set_meta("uz_top_node", col.get_child(0))


# --- Übersicht --------------------------------------------------------------------------

func _overview(col: VBoxContainer) -> void:
	col.add_child(_header())
	var notice := _notice()
	if notice:
		col.add_child(notice)
	_vitrine(col)
	# Bis hierher reicht der erste Bildschirm (die Reihe „Zuletzt freigeschaltet“ ragt noch hinein: ihre ersten
	# Karten gleich). Alles Weitere nach dem Hereingleiten, Reihe für Reihe (nachbau).
	var unten: Array = _zuletzt(col)
	unten.append(func() -> void: _reach(col))
	unten.append(func() -> void: _fast_und_komplett(col))
	unten.append(func() -> void: col.add_child(U.spacer(0, 60, false)))
	nachbau(col, unten)


## „Zuletzt freigeschaltet“: die Reihe mit den ersten ZULETZT_GLEICH Karten sofort; zurück kommen die Schritte
## für die übrigen (rechts außerhalb des Bildes).
const ZULETZT_GLEICH := 4


func _zuletzt(col: VBoxContainer) -> Array:
	var now := int(Time.get_unix_time_from_system())
	var recent: Array = Achievements.recent_unlocks.slice(0, 20)
	if recent.is_empty():
		return []
	# „Neu“ ist, was seit dem letzten Blick auf diese Seite kam (beim ersten Mal: heute), höchstens drei.
	var seen_at := int(Config.get_value("achievements.seen_at", 0))
	var stand := { "fresh_left": 3 }
	col.add_child(section_title("Zuletzt freigeschaltet"))
	var shelf = Shelf.new().setup("ach:recent", 24, true, SHELF_PAD, GUTTER, SHELF_PAD + 6)
	col.add_child(_tight(shelf))
	var karte := func(i: int) -> void:
		if not is_instance_valid(shelf):
			return
		var a: Dictionary = recent[i]
		var card = UnlockCard.new()
		card.a = a
		var at := int(a.get("date", 0))
		card.fresh = int(stand.fresh_left) > 0 and (at > seen_at if seen_at > 0 else now - at < 86400)
		if card.fresh:
			stand.fresh_left = int(stand.fresh_left) - 1
		var key := "ach:%s:%s:%d" % [a.get("game", ""), a.get("title", ""), int(a.get("date", 0))]
		card.set_meta("uz_key", key)
		_tile_hints(card, "Erfolge des Spiels")
		if i == 0:
			card.set_meta("uz_entry", true)
		card.chosen.connect(func() -> void: _open_unlock(a))
		shelf.add(card)
		_maybe_celebrate(card, key, shelf.items().size())
	var spaeter: Array = []
	for i in recent.size():
		if i < ZULETZT_GLEICH:
			karte.call(i)
		else:
			spaeter.append(karte.bind(i))
	return spaeter


func _fast_und_komplett(col: VBoxContainer) -> void:
	var near: Array = []
	var done: Array = []
	var done_steam := {}
	for g in Achievements.steam_perfect():
		done.append(g)
		done_steam[int(g.get("appid", 0))] = true
	for g in Achievements.ra_progress + Achievements.steam_progress:
		var t := int(g.get("total", 0))
		if t <= 0:
			continue
		if int(g.get("unlocked", 0)) >= t:
			if not (g.get("source") == "steam" and done_steam.has(int(g.get("appid", 0)))):
				done.append(g)
		elif float(g.get("unlocked", 0)) / t >= 0.4:
			near.append(g)
	near.sort_custom(func(a, b): return float(a.unlocked) / a.total > float(b.unlocked) / b.total)
	if not near.is_empty():
		col.add_child(section_title("Fast geschafft", "kurz vor 100 %"))
		_tile_shelf(col, near.slice(0, 10), "ach:near")
	if not done.is_empty():
		done.sort_custom(func(a, b): return int(a.get("date", 0)) > int(b.get("date", 0)))
		col.add_child(section_title("Komplett", U.plural(done.size(), "Spiel", "Spiele")))
		_tile_shelf(col, done, "ach:done")


## Oben: der Ring über alle Erfolge, die große Zahl und die Eckdaten je Quelle.
func _header() -> Control:
	var t := Achievements.totals()
	var m := U.margin(GUTTER, 6, GUTTER, 0)
	var row := U.hbox(48)
	m.add_child(row)
	var frac := float(t.unlocked) / maxf(1.0, float(t.total))
	row.add_child(Ring.new().setup(frac, 184, 14, str(int(floor(frac * 100.0))), "%", "aller Erfolge"))
	var v := U.vbox(0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	v.add_child(U.label("Deine Erfolge", "m", "muted", "medium"))
	var big := U.hbox(16)
	var n := U.label(_num(int(t.unlocked)), "hero", "text", "black")
	n.clip_text = false
	big.add_child(n)
	var fl := U.label("freigeschaltet in %s" % U.plural(int(t.games), "Spiel", "Spielen"), "l", "muted")
	fl.clip_text = false
	var flm := U.margin(0, 0, 0, 14)
	flm.size_flags_vertical = Control.SIZE_SHRINK_END
	flm.add_child(fl)
	big.add_child(flm)
	v.add_child(big)
	v.add_child(U.spacer(0, 14, false))
	var fields: Array = [["Komplett", "wird gezählt …" if bool(t.counting) and int(t.complete) == 0 else U.plural(int(t.complete), "Spiel", "Spiele")]]
	if Achievements.has_ra():
		var p: Dictionary = Achievements.ra_profile
		if int(p.get("points", 0)) > 0:
			fields.append(["RetroAchievements", "%s Punkte" % _num(int(p.points))])
		if int(p.get("rank", 0)) > 0:
			fields.append(["Rang", _num(int(p.rank))])
	var st: Dictionary = Achievements.steam_stats
	if Achievements.has_steam() and int(st.get("counted", 0)) > 0:
		fields.append(
				["Steam", "%s %s in %s" % [_num(int(st.unlocked)), "Erfolg" if int(st.unlocked) == 1 else "Erfolge", U.plural(int(st.started), "Spiel", "Spielen")]])
	elif Achievements.has_steam() and not Achievements.steam_progress.is_empty():
		var su := 0
		for g in Achievements.steam_progress:
			su += int(g.get("unlocked", 0))
		fields.append(["Steam", "%s in %s" % [U.plural(su, "Erfolg", "Erfolge"), U.plural(Achievements.steam_progress.size(), "Spiel", "Spielen")]])
	var db = DataBlock.new()
	v.add_child(db)
	db.set_fields(fields)
	return m


# --- Vitrine und Greifbares -------------------------------------------------------------------

## Die Vitrine: die besten Momente (höchstens MOMENTS) – gemeisterte bzw. perfekte Spiele (die
## zwei neuesten), die seltensten freigeschalteten Erfolge, zur Not das Neueste.
func _vitrine(col: VBoxContainer) -> void:
	var items := _moments()
	if items.size() < 2:
		return
	col.add_child(section_title("Vitrine", "deine besten Momente"))
	var v = Vitrine.new().setup(items, GUTTER)
	v.chosen.connect(func(it: Dictionary) -> void:
		if str(it.get("kind", "")) == "game":
			_open_game(it.get("p", {}))
		else:
			_open_unlock(it.get("a", {}))
	)
	var m := U.margin(0, -4, 0, 0)
	m.add_child(v)
	col.add_child(m)


func _moments() -> Array:
	var out: Array = []
	var seen := {}
	var done: Array = []
	var done_steam := {}
	for g in Achievements.steam_perfect():
		done.append(g)
		done_steam[int(g.get("appid", 0))] = true
	for g in Achievements.ra_progress + Achievements.steam_progress:
		var t := int(g.get("total", 0))
		if t > 0 and int(g.get("unlocked", 0)) >= t and not (g.get("source") == "steam" and done_steam.has(int(g.get("appid", 0)))):
			done.append(g)
	done.sort_custom(func(a, b): return int(a.get("date", 0)) > int(b.get("date", 0)))
	for g in done.slice(0, 2):
		var award := Ach.award_name(str(g.get("award", "")))
		var where := "Steam" if g.get("source") == "steam" else str(g.get("console_name", "RetroAchievements"))
		out.append({ "kind": "game", "a": { "icon": "", "rarity": -1.0 }, "name": str(g.get("title", "")), "p": g, "gold": true, "tier": 3,
			"caption": award if award != "" else "Alle Erfolge · 100 %", "game": where, "key": "g:%s:%s" % [g.get("source", ""), g.get("title", "")] })
	# Die seltensten freigeschalteten aus allen bekannten Listen (Steam: die perfekten und
	# geladenen Spiele; RetroAchievements: geöffnete Spiele).
	var rare: Array = Achievements.steam_rarest(6, 1)
	for res in Achievements.known_lists():
		if str(res.get("source", "")) != "ra":
			continue
		for a in res.get("list", []):
			if bool(a.get("unlocked", false)) and float(a.get("rarity", -1.0)) >= 0.0:
				rare.append({ "source": "ra", "title": a.title, "desc": a.get("desc", ""), "game": res.get("title", ""), "icon": a.get("icon", ""),
					"date": int(a.get("date", 0)), "points": int(a.get("points", 0)), "rarity": float(a.rarity), "hardcore": bool(a.get("hardcore", false)),
					"game_id": int(res.get("ra_id", 0)) })
	rare.sort_custom(func(x, y): return float(x.rarity) < float(y.rarity))
	var per_game := {}
	for a in rare:
		if out.size() >= MOMENTS:
			break
		var gk := str(a.get("game", ""))
		var key := "%s:%s" % [gk, a.get("title", "")]
		if seen.has(key) or per_game.has(gk):
			continue
		seen[key] = true
		per_game[gk] = true
		var tier := Ach.rarity_tier(float(a.get("rarity", -1.0)))
		out.append({ "kind": "ach", "a": a, "name": str(a.get("title", "")), "tier": tier, "game": gk,
			"caption": "%s  ·  %s" % [Ach.rarity_name(tier), Ach.pct_text(float(a.rarity))], "key": "a:" + key })
	for a in Achievements.recent_unlocks:
		if out.size() >= MOMENTS:
			break
		var key := "%s:%s" % [a.get("game", ""), a.get("title", "")]
		if seen.has(key):
			continue
		seen[key] = true
		var tier := Ach.rarity_tier(float(a.get("rarity", -1.0)))
		var cap := Rarity.when(int(a.get("date", 0)))
		if int(a.get("points", 0)) > 0:
			cap = "%d Punkte  ·  %s" % [int(a.points), cap] if cap != "" else "%d Punkte" % int(a.points)
		out.append({ "kind": "ach", "a": a, "name": str(a.get("title", "")), "tier": tier, "game": str(a.get("game", "")), "caption": cap, "key": "n:" + key })
	return out


## „Als Nächstes greifbar“: offene Erfolge, die viele haben – mit dem Freund, der ihn schon hat,
## wenn ein Freunde-Stand des Spiels im Speicher liegt.
func _reach(col: VBoxContainer) -> void:
	var list: Array = Achievements.reachable(8)
	if list.is_empty():
		return
	col.add_child(section_title("Als Nächstes greifbar", "offene Erfolge, die viele Spieler haben"))
	var shelf = Shelf.new().setup("ach:reach", 24, true, SHELF_PAD, GUTTER, SHELF_PAD + 6)
	col.add_child(_tight(shelf))
	for i in list.size():
		var a: Dictionary = list[i]
		var card = ReachCard.new()
		card.a = a
		var b: Dictionary = Achievements.friends.board_cached(a)
		if bool(b.get("ok", false)):
			var names := Friends.who_has(b.get("rows", []), str(a.get("id", "")), 2)
			if names.size() == 1:
				card.friend_line = "%s hat ihn schon" % str(names[0])
			elif names.size() > 1:
				card.friend_line = "%s und %s haben ihn schon" % [str(names[0]), str(names[1])]
		card.set_meta("uz_key", "reach:%s:%s" % [a.get("gk", ""), a.get("id", "")])
		_tile_hints(card, "Erfolge des Spiels")
		if i == 0:
			card.set_meta("uz_entry", true)
		card.chosen.connect(func() -> void: _open_unlock(a))
		shelf.add(card)


# --- Freunde ------------------------------------------------------------------------------------

func _friends_possible() -> bool:
	return not Social.steam_friends.is_empty() or Achievements.has_ra()


func _build_freunde() -> void:
	_shown_data = true
	_lib_alt = true
	var fr: Node = Achievements.friends
	var col := U.vbox(30)
	var sc := scroll_v(col)
	sc.set_meta("uz_pad_v", 120.0)
	U.full_rect(sc)
	_ziel.add_child(sc)
	EdgeFade.attach(sc, col)
	col.add_child(U.spacer(0, 4, false))
	# Erst beim Öffnen fragen, nie beim Start; was schon da ist (auch der gemerkte Stand vom letzten
	# Mal), steht sofort, der Rest kommt nach (friends.updated baut die Seite weich neu).
	if not fr.feed_frisch() and not fr.feed_loading():
		fr.feed()
	if Achievements.has_ra():
		fr.following()
	if not fr.feed_ready():
		col.add_child(_friends_loading())
		col.add_child(U.spacer(0, 60, false))
		return
	var laedt: bool = fr.feed_loading()
	var feed: Array = fr.feed_cached()
	var now := int(Time.get_unix_time_from_system())
	var rank := Friends.weekly(feed, fr.my_recent_dates(), fr.me(), now)
	col.add_child(section_title("Rangliste", "letzte 7 Tage  ·  unter Freunden"))
	var shelf = Shelf.new().setup("ach:rank", 20, true, SHELF_PAD, GUTTER, SHELF_PAD + 6)
	col.add_child(_tight(shelf))
	var ids: Array = []
	for i in mini(rank.size(), RANK_TILES):
		var r: Dictionary = rank[i]
		var cap := U.plural(int(r.count), "Erfolg", "Erfolge")
		if int(r.get("last", 0)) > 0:
			cap += "  ·  " + U.lower_first(Rarity.when(int(r.last)))
		var tile = RankTile.new()
		tile.setup(r, cap, Vector2(414, 124))
		tile.place("ach:rank", i, 20.0)
		tile.set_meta("uz_key", "rank:" + str(r.id))
		tile.set_meta("uz_hint_a", "Profil" if bool(r.me) else "Freund")
		if i == 0:
			tile.set_meta("uz_entry", true)
		tile.chosen.connect(func() -> void: _open_rank(r))
		shelf.add(tile)
		ids.append(str(r.id))
	# Die Plätze merken: beim nächsten Stand rückt, wer aufgestiegen ist, sichtbar herüber.
	RankTile.remember("ach:rank", ids)
	var fl: Array = fr.following_cached()
	if not fl.is_empty():
		var pts: Array = []
		for f in fl:
			pts.append({ "id": str(f.id), "name": str(f.name), "avatar": str(f.avatar), "count": int(f.points), "me": false })
		pts.append({ "id": "me", "name": str(Achievements.ra_profile.get("name", "Du")), "avatar": str(Achievements.ra_profile.get("pic", "")),
			"count": int(Achievements.ra_profile.get("points", 0)), "me": true })
		pts.sort_custom(func(a, b): return int(a.count) > int(b.count) if int(a.count) != int(b.count) else bool(a.me))
		for i in pts.size():
			pts[i]["rank"] = i + 1
		col.add_child(section_title("RetroAchievements", "Punkte  ·  wem du folgst"))
		var ps = Shelf.new().setup("ach:rapts", 20, true, SHELF_PAD, GUTTER, SHELF_PAD + 6)
		col.add_child(_tight(ps))
		var pids: Array = []
		for i in mini(pts.size(), RANK_TILES):
			var r: Dictionary = pts[i]
			var tile = RankTile.new()
			tile.setup(r, "%s Punkte" % _num(int(r.count)), Vector2(414, 124))
			tile.place("ach:rapts", i, 20.0)
			tile.set_meta("uz_key", "rapts:" + str(r.id))
			tile.set_meta("uz_hint_a", "Profil" if bool(r.me) else "—")
			if bool(r.me):
				tile.chosen.connect(func() -> void: jump("profil"))
			ps.add(tile)
			pids.append(str(r.id))
		RankTile.remember("ach:rapts", pids)
	col.add_child(section_title("Freunde haben freigeschaltet", freunde_stand(feed.size(), laedt)))
	if feed.is_empty() and laedt:
		col.add_child(_friends_loading())
	elif feed.is_empty():
		var em := U.margin(GUTTER, 0, GUTTER, 0)
		var l := U.label(
				"Noch nichts in den letzten 7 Tagen. Steam zeigt Erfolge nur von Freunden mit öffentlichem Profil; bei RetroAchievements zählt, wem du folgst.",
				"m", "muted", "regular", true)
		l.custom_minimum_size.x = 1100
		em.add_child(l)
		col.add_child(em)
	else:
		var lm := U.margin(GUTTER - 16, 0, GUTTER - 8, 0)
		var lv := U.vbox(6)
		lv.set_meta("uz_group", "ach:feed")
		lv.set_meta("uz_edge_rows", true)    # die Kanten blenden Zeile für Zeile, nicht die ganze Liste
		lm.add_child(lv)
		col.add_child(lm)
		for i in mini(feed.size(), FEED_ROWS):
			var e: Dictionary = feed[i]
			var row = FeedRow.new()
			row.e = e
			row.set_meta("uz_key", "feed:%s:%s:%s" % [e.get("friend_id", ""), e.get("gk", ""), e.get("id", "")])
			row.set_meta("uz_hint_x", "Neu laden")
			row.set_meta("uz_on_x", func() -> void: _reload_friends())
			row.chosen.connect(func() -> void: _open_feed(e))
			lv.add_child(row)
		# Die Zeilen kommen gestaffelt (Takt: höchstens vier Glieder), der Rest steht sofort.
		U.cascade.call_deferred(lm, 4)
	_reach(col)
	col.add_child(U.spacer(0, 60, false))


## Unterzeile des Feeds: wie viele Einträge, und ob noch geladen wird.
static func freunde_stand(n: int, laedt: bool) -> String:
	var t: String = U.plural(n, "Eintrag", "Einträge") if n > 0 else str(TranslationServer.translate("letzte 7 Tage"))
	return t + "  ·  " + str(TranslationServer.translate("wird aktualisiert")) if laedt else t


## Platzhalter in der Form der Seite, solange Feed und Stände kommen.
func _friends_loading() -> Control:
	var col := U.vbox(26)
	var tm := U.margin(GUTTER, 0, GUTTER, 0)
	tm.add_child(Skeleton.new().setup(Vector2(260, 30), 8))
	col.add_child(tm)
	var rm := U.margin(GUTTER, 0, GUTTER, 0)
	rm.add_child(Skeleton.cards(4, Vector2(414, 124)))
	col.add_child(rm)
	var fm := U.margin(GUTTER, 10, GUTTER, 0)
	fm.add_child(Skeleton.new().setup(Vector2(420, 30), 8))
	col.add_child(fm)
	for i in 4:
		var m := U.margin(GUTTER, 0, GUTTER, 0)
		var r := U.hbox(20)
		r.add_child(Skeleton.new().setup(Vector2(52, 52), -1, true))
		r.add_child(Skeleton.new().setup(Vector2(76, 76), 14))
		var lines := U.vbox(12)
		lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lines.add_child(Skeleton.new().setup(Vector2(420 - (i % 3) * 60, 18), 8))
		lines.add_child(Skeleton.new().setup(Vector2(560 - (i % 2) * 90, 24), 8))
		r.add_child(lines)
		m.add_child(r)
		col.add_child(m)
	return col


func _reload_friends() -> void:
	Achievements.friends.feed(true)
	Toasts.show_toast("Freunde werden neu geladen", "", "refresh", { "ms": 1400, "quiet": true })


## A in der Rangliste: du → Profil, ein Steam-Freund → seine Handlungen.
func _open_rank(r: Dictionary) -> void:
	if bool(r.get("me", false)):
		jump("profil")
		return
	var f := Social.steam_friend(str(r.get("id", "")))
	if not f.is_empty() and main:
		main.open_friend(f)


## A im Feed: die Erfolge des Spiels mit Freunden, dieser Freund zuerst.
func _open_feed(e: Dictionary) -> void:
	var p := { "source": str(e.get("source", "")), "appid": int(e.get("appid", 0)), "ra_id": int(e.get("game_id", 0)), "title": str(e.get("game", "")) }
	if p.source == "ra":
		for pr in Achievements.ra_progress:
			if int(pr.get("ra_id", 0)) == int(p.ra_id):
				p["console"] = int(pr.get("console", 0))
	var l = GameAch.new()
	l.game = _game_for(p)
	l.compare = { "id": str(e.get("friend_id", "")), "name": str(e.get("friend", "")), "avatar": str(e.get("avatar", "")) }
	main.open_layer(l)


## Schmaler Hinweis unter dem Kopf: gerade am Aktualisieren, oder offline mit altem Stand.
func _notice() -> Control:
	var text := ""
	var icon := "refresh"
	if Achievements.loading:
		text = "Wird aktualisiert …"
	elif Achievements.last_error != "":
		icon = "info"
		text = Achievements.last_error + " Du siehst den letzten Stand."
	if text == "":
		return null
	var m := U.margin(GUTTER, 0, GUTTER, 0)
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("glass"), 999, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 18
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var h := U.hbox(12)
	h.add_child(U.icon(icon, 22, "muted"))
	var l := U.label(text, "s", "muted", "medium")
	l.clip_text = false
	h.add_child(l)
	p.add_child(h)
	m.add_child(p)
	return m


## Die ersten REIHE_GLEICH Kacheln gleich, die übrigen (rechts außerhalb des Bildes) im Nachbau – „Komplett“ kann
## Dutzende Spiele lang sein.
const REIHE_GLEICH := 8


func _tile_shelf(col: VBoxContainer, list: Array, group: String) -> void:
	var shelf = Shelf.new().setup(group, 24, true, SHELF_PAD, GUTTER, SHELF_PAD + 6)
	col.add_child(_tight(shelf))
	var spaeter: Array = []
	for i in list.size():
		var eine := func() -> void:
			if not is_instance_valid(shelf):
				return
			var tile := _game_tile(list[i])
			if i == 0:
				tile.set_meta("uz_entry", true)
			shelf.add(tile)
		if i < REIHE_GLEICH:
			eine.call()
		else:
			spaeter.append(eine)
	nachbau(col, spaeter)


## Reihen mit Kacheln brauchen oben Luft fürs Anheben; der Abstand zur Überschrift bleibt gleich.
func _tight(c: Control) -> Control:
	var m := U.margin(0, -SHELF_PAD + 6, 0, -SHELF_PAD)
	m.add_child(c)
	return m


func _game_tile(p: Dictionary) -> Control:
	var tile = GameTile.new()
	tile.p = p
	tile.game = _lib_game(p)
	if tile.game.is_empty() and p.get("source") == "ra":
		tile.system_id = _system_for(int(p.get("console", 0)))
	tile.set_meta("uz_key", "achg:%s:%s" % [p.get("source", ""), str(p.get("ra_id", p.get("appid", "")))])
	_tile_hints(tile, "Erfolge ansehen")
	var pd: Dictionary = p
	tile.chosen.connect(func() -> void: _open_game(pd))
	return tile


func _tile_hints(c: Control, a: String) -> void:
	c.set_meta("uz_hint_a", a)
	c.set_meta("uz_hint_x", "Neu laden")
	c.set_meta("uz_on_x", func() -> void: _reload())


## Frisch Freigeschaltetes leuchtet einmal auf, wenn man es zum ersten Mal sieht; kommt ein
## Erfolg herein, während die Seite offen ist, klingt dazu der Erfolgston.
func _maybe_celebrate(card: Control, key: String, idx: int) -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	var live := _shown_once
	if card.get("fresh") or live:
		card.call_deferred("celebrate", 0.35 + 0.08 * idx)
		if live and idx <= 3:
			Sfx.play("achievement")


# --- Je Quelle --------------------------------------------------------------------------

func _source_page(col: VBoxContainer, kind: String) -> void:
	var list: Array = Achievements.ra_progress if kind == "retro" else Achievements.steam_progress
	var got := 0
	var all := 0
	var done := 0
	for g in list:
		got += int(g.get("unlocked", 0))
		all += int(g.get("total", 0))
		if int(g.get("total", 0)) > 0 and int(g.get("unlocked", 0)) >= int(g.get("total", 0)):
			done += 1
	# Steam: über die ganze Bibliothek, sobald gezählt (die Liste unten sind die zuletzt gespielten).
	var st: Dictionary = Achievements.steam_stats
	var full := kind == "steam" and int(st.get("counted", 0)) > 0
	if full:
		got = int(st.unlocked)
		all = int(st.total)
		done = int(st.perfect_count)
	var m := U.margin(GUTTER, 6, GUTTER, 0)
	var row := U.hbox(40)
	m.add_child(row)
	var frac := float(got) / maxf(1.0, float(all))
	row.add_child(Ring.new().setup(frac, 128, 11, str(int(floor(frac * 100.0))), "%"))
	var v := U.vbox(4)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	var head := "RetroAchievements" if kind == "retro" else "Steam"
	var hl := U.label(head, "xl", "text", "bold")
	hl.clip_text = false
	v.add_child(hl)
	var fields: Array = [["Freigeschaltet", "%s von %s" % [_num(got), _num(all)]], ["Spiele", str(list.size())], ["Komplett", str(done)]]
	if full:
		fields[1] = ["Spiele mit Erfolgen", _num(int(st.with_ach))]
	if kind == "steam" and bool(st.get("counting", false)):
		fields[2] = ["Komplett", "wird gezählt …"]
	if kind == "retro":
		var p: Dictionary = Achievements.ra_profile
		if int(p.get("points", 0)) > 0:
			fields.insert(0, ["Punkte", _num(int(p.points))])
		if int(p.get("rank", 0)) > 0:
			fields.insert(1, ["Rang", _num(int(p.rank))])
	var db = DataBlock.new()
	v.add_child(db)
	db.set_fields(fields)
	col.add_child(m)
	var notice := _notice()
	if notice:
		col.add_child(notice)
	var what := "Alle gespielten Spiele" if kind == "retro" else "Zuletzt gespielt"
	col.add_child(section_title(what, U.plural(list.size(), "Spiel", "Spiele")))
	if list.is_empty():
		var em := U.margin(GUTTER, 0, GUTTER, 0)
		# Lädt es noch: Platzhalter in Form der Spielkacheln statt eines Satzes.
		if Achievements.loading:
			em.add_child(Skeleton.cards(3, Vector2(560, 208)))
		else:
			em.add_child(U.label("Noch keine Erfolge.", "m", "muted"))
		col.add_child(em)
		col.add_child(U.spacer(0, 60, false))
		return
	var gm := U.margin(GUTTER, 4, GUTTER, 0)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 30)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gm.add_child(grid)
	col.add_child(gm)
	# Die ersten beiden Reihen gleich, die übrigen Kacheln nach dem Hereingleiten (nachbau) – bei langen Listen
	# stand sonst jeder Wechsel hierher spürbar still.
	var unten: Array = _kacheln(grid, list, RASTER_GLEICH)
	if kind == "steam":
		var perfect: Array = Achievements.steam_perfect()
		if not perfect.is_empty():
			var raster := { "pg": null }
			unten.append(func() -> void:
				col.add_child(section_title("Perfekte Spiele", U.plural(perfect.size(), "Spiel", "Spiele") + " mit 100 %"))
				var pm := U.margin(GUTTER, 4, GUTTER, 0)
				var pg := GridContainer.new()
				pg.columns = 3
				pg.add_theme_constant_override("h_separation", 24)
				pg.add_theme_constant_override("v_separation", 30)
				pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pm.add_child(pg)
				col.add_child(pm)
				raster.pg = pg)
			for i in range(0, perfect.size(), 3):
				unten.append(func() -> void:
					if is_instance_valid(raster.pg):
						for g in perfect.slice(i, i + 3):
							(raster.pg as GridContainer).add_child(_game_tile(g)))
	unten.append(func() -> void: col.add_child(U.spacer(0, 60, false)))
	nachbau(col, unten)


## Kacheln eines Rasters: die ersten gleich, zurück kommen die Schritte für den Rest (je eine Reihe).
const RASTER_GLEICH := 6


func _kacheln(grid: GridContainer, list: Array, gleich: int) -> Array:
	for g in list.slice(0, gleich):
		grid.add_child(_game_tile(g))
	var spaeter: Array = []
	for i in range(gleich, list.size(), 3):
		spaeter.append(func() -> void:
			if is_instance_valid(grid):
				for g in list.slice(i, i + 3):
					grid.add_child(_game_tile(g)))
	return spaeter


# --- Leer, Fehler, Laden ----------------------------------------------------------------

## Ganze Seite mit Bild rechts: Überschrift, Satz, Knöpfe (der erste ist hell und gewählt).
func _state_page(head: String, text: String, buttons: Array, dim: bool) -> Control:
	var m := U.margin(GUTTER, 0, GUTTER, 60)
	U.full_rect(m)
	var row := U.hbox(60)
	m.add_child(row)
	var col := U.vbox(22)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	var h := U.label(head, "xxl", "text", "black", true)
	col.add_child(h)
	var p := U.label(text, "l", "muted", "regular", true)
	p.custom_minimum_size = Vector2(860, 0)
	col.add_child(p)
	col.add_child(U.spacer(0, 12, false))
	var brow := U.hbox(16)
	col.add_child(brow)
	for i in buttons.size():
		var b: Array = buttons[i]
		var btn := U.button(str(b[0]), str(b[1]), "primary" if i == 0 else "normal")
		btn.pressed.connect(b[2])
		if i == 0:
			btn.set_meta("uz_default", true)
		brow.add_child(btn)
	var cab = Cabinet.new().setup(dim)
	cab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cab)
	return m


## Beim ersten Laden: die Form der Seite als ruhige Platzhalter.
func _loading_page() -> Control:
	var m := U.margin(GUTTER, 10, GUTTER, 0)
	U.full_rect(m)
	var col := U.vbox(34)
	m.add_child(col)
	var head := U.hbox(48)
	head.add_child(Skeleton.new().setup(Vector2(184, 184), -1, true))
	var lines := U.vbox(16)
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lines.add_child(Skeleton.new().setup(Vector2(220, 22), 8))
	lines.add_child(Skeleton.new().setup(Vector2(460, 64), 12))
	lines.add_child(Skeleton.new().setup(Vector2(620, 40), 10))
	head.add_child(lines)
	col.add_child(head)
	col.add_child(Skeleton.new().setup(Vector2(300, 30), 8))
	var cards := U.hbox(24)
	for i in 4:
		cards.add_child(Skeleton.new().setup(Vector2(520, 176), UzTheme.r_panel()))
	col.add_child(cards)
	col.add_child(Skeleton.new().setup(Vector2(240, 30), 8))
	var tiles := U.hbox(24)
	for i in 4:
		tiles.add_child(Skeleton.new().setup(Vector2(560, 208), UzTheme.r_panel()))
	col.add_child(tiles)
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.clip_contents = true
	U.full_rect(wrap)
	wrap.add_child(m)
	return wrap


# --- Spielzeit --------------------------------------------------------------------------

func _build_stats() -> void:
	var col := U.vbox(30)
	var sc := scroll_v(col)
	sc.set_meta("uz_pad_v", 190.0)
	U.full_rect(sc)
	_ziel.add_child(sc)
	EdgeFade.attach(sc, col)
	col.add_child(U.spacer(0, 6, false))
	PlaytimePage.new().build(self, col)


# --- Backlog ----------------------------------------------------------------------------

func _build_backlog() -> void:
	var col := U.vbox(30)
	var sc := scroll_v(col)
	sc.set_meta("uz_pad_v", 190.0)
	U.full_rect(sc)
	_ziel.add_child(sc)
	EdgeFade.attach(sc, col)
	col.add_child(U.spacer(0, 6, false))
	BacklogPage.new().build(self, col)
	col.add_child(U.spacer(0, 60, false))


func _on_backlog_data() -> void:
	if sub != "backlog" or not is_visible_in_tree() or _backlog_due:
		return
	_backlog_due = true
	await get_tree().process_frame
	_backlog_due = false
	if sub == "backlog" and is_visible_in_tree():
		_rebuild_keep_focus(false)


# --- Spiele finden und öffnen -----------------------------------------------------------

## Titel und RetroAchievements-IDs der Emulator-Spiele zum Nachschlagen. Erst, wenn eine Kachel danach fragt
## (_lib_game): Jeder Aufbau bildete das vorher für die ganze Bibliothek, auch wo nur Steam-Spiele stehen.
func _index_library() -> void:
	_lib_alt = false
	_lib.clear()
	_lib_ra.clear()
	for g in Library.visible_games():
		if g.get("source") == "rom":
			_lib[Ach.norm(str(g.get("title", "")))] = g
			if int(g.get("ra_id", 0)) > 0:
				_lib_ra[int(g.ra_id)] = g


## Das Spiel aus der Bibliothek zu einem Eintrag von Steam bzw. RetroAchievements.
func _lib_game(p: Dictionary) -> Dictionary:
	if p.get("source") == "steam":
		return Library.get_game("steam:%d" % int(p.get("appid", 0)))
	if _lib_alt:
		_index_library()
	var rid := int(p.get("ra_id", p.get("game_id", 0)))
	if rid > 0 and _lib_ra.has(rid):
		return _lib_ra[rid]
	return _lib.get(Ach.norm(str(p.get("title", p.get("game", "")))), {})


static func _system_for(console: int) -> String:
	if console <= 0:
		return ""
	for s in Config.systems():
		if int(s.get("ra_console", 0)) == console:
			return str(s.id)
	return ""


## Das Spiel für die Erfolgsseite zu einem Eintrag von Steam bzw. RetroAchievements: aus der
## Bibliothek, sonst ein Ersatz mit Kennung.
func _game_for(p: Dictionary) -> Dictionary:
	var lib := _lib_game(p)
	var g: Dictionary = lib.duplicate() if not lib.is_empty() else {}
	if p.get("source") == "steam":
		# Spiel aus der Bibliothek: über den Zwischenspeicher (wie Startseite und Spielseite).
		var appid := int(p.get("appid", 0))
		if g.is_empty():
			g = { "id": "steam:%d" % appid, "title": p.get("title", ""), "source": "steam", "system": "steam", "appid": appid, "_appid": appid }
	else:
		var rid := int(p.get("ra_id", p.get("game_id", 0)))
		if g.is_empty():
			g = { "id": "ra:%d" % rid, "title": p.get("title", p.get("game", "")), "source": "rom", "system": _system_for(int(p.get("console", 0))) }
		g["_ra_id"] = rid
	return g


func _open_game(p: Dictionary) -> void:
	main.open_game_achievements(_game_for(p))


## Ein freigeschalteter Erfolg: die Liste seines Spiels öffnen, wenn bekannt welches.
func _open_unlock(a: Dictionary) -> void:
	if a.get("source") == "steam" and int(a.get("appid", 0)) > 0:
		_open_game({ "source": "steam", "appid": int(a.appid), "title": a.get("game", "") })
	elif a.get("source") == "ra" and int(a.get("game_id", 0)) > 0:
		var console := 0
		for p in Achievements.ra_progress:
			if int(p.get("ra_id", 0)) == int(a.game_id):
				console = int(p.get("console", 0))
		_open_game({ "source": "ra", "ra_id": int(a.game_id), "title": a.get("game", ""), "console": console })
	else:
		Toasts.show_toast(str(a.get("title", "")), str(a.get("desc", "")), "trophy", { "ms": 2600, "quiet": true })


static func _num(n: int) -> String:
	return Lang.tausender(n)


## Ein Knopf im Inhalt (Profil → „Alle Erfolge“) springt in einen anderen Unterbereich: B führt
## danach zurück auf den Knopf, statt nach oben zu den Reitern.
func jump(sub_id: String) -> void:
	var f := Nav.focused()
	_came_key = str(f.get_meta("uz_key", "")) if f and is_ancestor_of(f) and f.has_meta("uz_key") else ""
	_came_from = sub
	main.goto(id, sub_id)


func handle_back() -> bool:
	if _came_from == "" or _came_from == sub:
		_came_from = ""
		return false
	_return_to(_came_from, _came_key)
	_came_from = ""
	return true


func _return_to(to: String, key: String) -> void:
	await main.goto(id, to, false)
	if not is_inside_tree() or main.current != id:
		return
	var hit := _find_key(_seite() if _seite() != null else self, key) if key != "" else null
	if hit:
		Nav.focus(hit, true)
	else:
		focus_default()


func back_hint() -> String:
	return "Zurück" if _came_from != "" and _came_from != sub else super()


func reset_position() -> void:
	super()
	_came_from = ""


static func _find_key(n: Node, key: String) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree() and str(c.get_meta("uz_key", "")) == key:
			return c
		var r := _find_key(c, key)
		if r:
			return r
	return null
