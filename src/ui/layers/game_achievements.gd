extends "res://src/ui/layers/layer.gd"
## Erfolge eines Spiels als eigene Seite – wie die Trophäenliste einer Konsole. Links das Spiel:
## Cover, Ring mit dem Stand, was nach Seltenheit schon da ist, Punkte. Rechts alle Erfolge:
## freigeschaltete zuerst (neueste oben), dann die offenen, die am leichtesten zu holen sind.
## Y holt die Freunde dazu (Achievements.friends.board): links die Rangliste in diesem Spiel (du
## mit drin), rechts in jeder Zeile, wer ihn hat – „Nur du“, „Du und Mira“, bei offenen „Mira hat
## das gestern freigeschaltet“. compare (aus dem Freundesprofil) öffnet gleich mit Freunden, der
## gewählte steht oben. LB/RB filtern, X lädt neu.

const Ach := preload("res://src/core/achievements.gd")
const Friends := preload("res://src/core/achievements_friends.gd")
const UnlocksS := preload("res://src/core/unlocks.gd")
const Ring := preload("res://src/ui/components/ach/ring.gd")
const AchRow := preload("res://src/ui/components/ach/ach_row.gd")
const Rarity := preload("res://src/ui/components/ach/rarity.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")
const Cabinet := preload("res://src/ui/components/ach/cabinet.gd")
const CoverArt := preload("res://src/ui/components/cover_art.gd")
const NavItem := preload("res://src/ui/components/nav_item.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const EdgeFade := preload("res://src/ui/components/ach/edge_fade.gd")
const TileS := preload("res://src/ui/components/ach/tile.gd")

const FILTERS := [["alle", "Alle"], ["frei", "Freigeschaltet"], ["offen", "Offen"]]
const RANK_ROWS := 5               ## Plätze links (du immer dabei)
const RANK_ROW_H := 50.0           ## Höhe eines Platzes links (für den Weg zwischen Plätzen)

var game: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var compare: Dictionary = {}       ## Freund aus dem Freundesprofil: Freunde gleich an, er zuerst
var show_friends := false          ## Freunde-Stand an (Y)
var _data: Dictionary = {}
var _board: Dictionary = {}        ## Achievements.friends.board(game)
var _board_loading := false
var _ranks_shown := {}             ## Platz-Index je Freund beim letzten Aufbau (Plätze rücken sichtbar)
var _left_shown := false           ## Cover, Ring und Zahlen standen schon (Ring füllt sich nur einmal)
var _loading := true
var _filter := "alle"
var _gen := 0
var _left: VBoxContainer
var _right: VBoxContainer
var _glow: TextureRect
var _chip_row: Control
var _scroll: ScrollContainer
var _list: VBoxContainer


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), 1.0)
	set_meta("uz_hint_b", "Zurück")
	# Weicher Schein in der Farbe des Spiels hinter dem Cover (nie ganz schwarz).
	_glow = TextureRect.new()
	_glow.texture = Cabinet._radial()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.position = Vector2(-420, -520)
	_glow.size = Vector2(1500, 1500)
	var sys_col := Color(str(Config.system(str(game.get("system", ""))).get("color", "#3a4050")))
	_glow.modulate = Color(sys_col, 0.0)
	add_child(_glow)
	var wg: WeakRef = weakref(_glow)
	Media.game_tint(game, func(c: Variant) -> void:
		var gl: TextureRect = wg.get_ref()
		if gl:
			var col: Color = c if c is Color else sys_col
			gl.create_tween().tween_property(gl, "modulate", Color(col, 0.22), U.T_AMBIENT)
	)
	var root := U.margin(96, 64, 96, 104)
	U.full_rect(root)
	add_child(root)
	var row := U.hbox(76)
	root.add_child(row)
	_left = U.vbox(0)
	_left.custom_minimum_size = Vector2(500, 0)
	row.add_child(_left)
	_right = U.vbox(18)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_right)
	# Hereinkommen: die Seite gleitet ein Stück von rechts herein (man geht eine Ebene tiefer).
	U.slide_x(root, 40.0, U.T_MOVE)
	if not compare.is_empty():
		show_friends = true
	_load(false)


func _first_focus() -> Control:
	return Nav.default_in(_right) if is_instance_valid(_right) else null


func _appid() -> int:
	return int(game.get("_appid", game.get("appid", 0)))


# --- Laden ------------------------------------------------------------------------------

func _load(force: bool) -> void:
	_gen += 1
	if force and _list_ready():
		# Neu laden mit Liste: sie bleibt stehen, bis der neue Stand da ist.
		Toasts.show_toast("Erfolge werden neu geladen", Library.display_title(game), "refresh", { "sub_raw": true, "ms": 1400, "quiet": true })
	else:
		_loading = true
		_refill()
	_fetch(weakref(self), _gen, force)


## Läuft ohne Bindung an die Seite: wird sie inzwischen geschlossen, passiert einfach nichts.
static func _fetch(wr: WeakRef, gen: int, force: bool) -> void:
	var me: Node = wr.get_ref()
	if me == null:
		return
	var g: Dictionary = me.get("game")
	var d: Dictionary
	if g.has("_ra_id"):
		d = await Achievements.ra_game(int(g._ra_id))
	elif g.has("_appid"):
		d = await Achievements.steam_game(int(g._appid), str(g.get("title", "")), true)
	else:
		d = await Achievements.for_game(g, force, true)
	me = wr.get_ref()
	if me and me.is_inside_tree():
		me.call("_apply", gen, d)
		if bool(me.get("show_friends")):
			_fetch_board(wr, gen, force)


## Der Freunde-Stand, getrennt vom eigenen (er dauert länger): die Liste steht schon, die Namen
## kommen dazu.
static func _fetch_board(wr: WeakRef, gen: int, force: bool) -> void:
	var me: Node = wr.get_ref()
	if me == null:
		return
	var g: Dictionary = me.get("game")
	var pin := str((me.get("compare") as Dictionary).get("id", ""))
	var b: Dictionary = await Achievements.friends.board(_board_game(g, me.get("_data")), force, pin)
	me = wr.get_ref()
	if me and me.is_inside_tree():
		me.call("_apply_board", gen, b)


## Das Spiel so, wie das Freunde-Modul es kennt: Quelle und Kennung aus der Seite bzw. den Daten.
static func _board_game(g: Dictionary, d: Dictionary) -> Dictionary:
	if g.has("_ra_id") or str(d.get("source", "")) == "ra":
		return { "source": "ra", "ra_id": int(g.get("_ra_id", d.get("ra_id", 0))) }
	return { "source": "steam", "appid": int(g.get("_appid", g.get("appid", d.get("appid", 0)))) }


func _apply(gen: int, d: Dictionary) -> void:
	if gen != _gen:
		return
	_data = d
	_loading = false
	_board_loading = show_friends
	_refill(true)


func _apply_board(gen: int, b: Dictionary) -> void:
	if gen != _gen:
		return
	_board = b
	_board_loading = false
	_refill(false)


## Y: Freunde dazu (oder wieder weg). Der Stand kommt aus dem Zwischenspeicher oder wird geholt.
func _toggle_friends() -> void:
	show_friends = not show_friends
	Sfx.play("toggle_on" if show_friends else "toggle_off")
	if show_friends:
		_board = Achievements.friends.board_cached(_board_game(game, _data))
		_board_loading = _board.is_empty()
		if _board_loading:
			_fetch_board(weakref(self), _gen, false)
	_refill()


func handle(cmd: String) -> bool:
	match cmd:
		"x":
			_load(true)
			return true
		"y":
			if _list_ready():
				_toggle_friends()
			return true
		"lb", "rb":
			if _list_ready():
				_step_filter(-1 if cmd == "lb" else 1)
			return true
	return false


# --- Aufbau -----------------------------------------------------------------------------

func _list_ready() -> bool:
	return not _loading and int(_data.get("total", 0)) > 0


## Alles neu: links das Spiel, rechts Filter und Liste (oder ein Hinweis).
func _refill(animate := false) -> void:
	if not is_instance_valid(_left):
		return
	var f := Nav.focused()
	# Nach dem Laden auf den ersten Erfolg; wer gerade die Filter bedient, bleibt dort, und wer
	# in der Liste steht, bleibt auf demselben Erfolg (zum Beispiel wenn der Vergleich ankommt).
	var on_filter := f != null and f.has_meta("uz_filter") and not f.has_meta("uz_loading")
	var key := str(f.get_meta("uz_key", "")) if f != null and is_ancestor_of(f) and not f.has_meta("uz_filter") else ""
	U.clear(_left)
	U.clear(_right)
	_build_left()
	if _loading:
		_build_loading()
	elif _list_ready():
		_build_list(animate)
	else:
		_build_empty()
	var hints: Array = []
	if _list_ready():
		hints = [["lb", ""], ["rb", "Filter"], ["x", "Neu laden"], ["y", "Freunde aus" if show_friends else "Freunde"]]
	elif str(_data.get("error", "")) != "":
		hints = [["x", "Neu laden"]]
	set_meta("uz_hints", hints)
	_refocus.call_deferred(on_filter, key)


func _refocus(on_filter: bool, key := "") -> void:
	if not is_inside_tree() or Nav.top_layer() != self:
		return
	var cur := Nav.focused()
	if cur and is_ancestor_of(cur) and cur.is_inside_tree() and not cur.is_queued_for_deletion():
		return
	if key != "":
		for c in Nav.focusables(_right):
			if str(c.get_meta("uz_key", "")) == key:
				Nav.focus(c, true)
				return
	if on_filter:
		for c in Nav.focusables(_right):
			if c.has_meta("uz_filter") and c.get_meta("uz_selected", false):
				Nav.focus(c, true)
				return
	var d := Nav.default_in(_right)
	if d:
		Nav.focus(d, true)


func _build_left() -> void:
	_left.add_child(_cover(Vector2(216, 288)))
	_left.add_child(U.spacer(0, 30, false))
	var src := { "steam": "Steam", "ra": "RetroAchievements" }.get(_source(), "") as String
	if _source() == "ra" and str(_data.get("console", "")) != "":
		src += "  ·  " + str(_data.console)
	var kick := U.label("Erfolge" + ("  ·  " + src if src != "" else ""), "s", "muted", "medium")
	kick.clip_text = false
	_left.add_child(kick)
	_left.add_child(U.spacer(0, 4, false))
	var t := U.label(Library.display_title(game) if not game.is_empty() else str(_data.get("title", "")), "xl", "text", "bold", true)
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels
	t.max_lines_visible = 2
	_left.add_child(t)
	_left.add_child(U.spacer(0, 28, false))
	if _loading:
		var sk := U.hbox(28)
		sk.add_child(Skeleton.new().setup(Vector2(140, 140), -1, true))
		var lines := U.vbox(12)
		lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lines.add_child(Skeleton.new().setup(Vector2(180, 30), 8))
		lines.add_child(Skeleton.new().setup(Vector2(140, 20), 8))
		sk.add_child(lines)
		_left.add_child(sk)
		return
	if not _list_ready():
		return
	var total := int(_data.total)
	var got := int(_data.get("unlocked", 0))
	var frac := float(got) / maxf(1.0, float(total))
	var ring_row := U.hbox(28)
	var ring = Ring.new().setup(frac, 140, 12, str(int(floor(frac * 100.0))), "%")
	# Der Ring füllt sich beim ersten Stand; kommen danach nur die Freunde dazu, steht er still.
	ring.instant = _left_shown
	_left_shown = true
	ring_row.add_child(ring)
	var nums := U.vbox(2)
	nums.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var big := U.label("%d von %d" % [got, total], "l", "text", "bold")
	big.clip_text = false
	nums.add_child(big)
	nums.add_child(U.label("freigeschaltet" if got < total else "alle freigeschaltet", "s", "gold" if got >= total else "muted", "medium"))
	# Uzai-Punkte des Spiels (nach Seltenheit, src/core/unlocks.gd): klein, unter dem Stand.
	var uz: Dictionary = UnlocksS.score_list(_data)
	if int(uz.max) > 0:
		var ul := U.label("%s von %s Uzai-Punkten" % [UnlocksS.num_text(int(uz.points)), UnlocksS.num_text(int(uz.max))], "xs", "faint", "medium")
		ul.clip_text = false
		nums.add_child(ul)
	if _source() == "ra" and int(_data.get("points_total", 0)) > 0:
		nums.add_child(U.spacer(0, 6, false))
		var pts := U.label("%d von %d Punkten" % [int(_data.get("points", 0)), int(_data.points_total)], "s", "text", "medium")
		pts.clip_text = false
		nums.add_child(pts)
		var hc := (_data.get("list", []) as Array).filter(func(a): return a.get("hardcore", false)).size()
		if hc > 0:
			nums.add_child(U.label("davon %d im Hardcore-Modus" % hc, "xs", "faint", "medium"))
	ring_row.add_child(nums)
	_left.add_child(ring_row)
	_left.add_child(U.spacer(0, 30, false))
	if show_friends:
		_left.add_child(_friends_block(got, total))
	else:
		_left.add_child(_tiers())


## Stand nach Seltenheit: je Stufe, wie viele davon schon da sind.
func _tiers() -> Control:
	var have := [0, 0, 0, 0]
	var all := [0, 0, 0, 0]
	var any := false
	for a in _data.get("list", []):
		var tier := Ach.rarity_tier(float(a.get("rarity", -1.0)))
		if tier < 0:
			continue
		any = true
		all[tier] += 1
		if a.get("unlocked", false):
			have[tier] += 1
	var v := U.vbox(10)
	if not any:
		return v
	for tier in [3, 2, 1, 0]:
		if int(all[tier]) == 0:
			continue
		var r := U.hbox(12)
		r.add_child(Rarity.gem(tier, 16))
		var n := U.label(Ach.rarity_name(tier), "m", "text" if int(have[tier]) > 0 else "muted", "medium")
		n.custom_minimum_size = Vector2(190, 0)
		r.add_child(n)
		var c := U.label("%d von %d" % [int(have[tier]), int(all[tier])], "m", "accent" if tier == 3 and int(have[tier]) > 0 else "muted", "ui")
		c.clip_text = false
		r.add_child(c)
		v.add_child(r)
	return v


## Links statt der Seltenheitsstufen: die Rangliste in diesem Spiel – Platz, Profilbild, Name,
## „21 von 42“ mit schmalem Balken; du bist markiert. Wer nichts zeigt, steht leise darunter.
func _friends_block(got: int, total: int) -> Control:
	var v := U.vbox(10)
	var head := U.hbox(12)
	var hl := U.label("Freunde in diesem Spiel", "m", "text", "ui_bold")
	hl.clip_text = false
	head.add_child(hl)
	v.add_child(head)
	if _board_loading or _board.is_empty():
		for i in 3:
			var r := U.hbox(14)
			r.add_child(Skeleton.new().setup(Vector2(40, 40), -1, true))
			var lines := U.vbox(8)
			lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			lines.add_child(Skeleton.new().setup(Vector2(200 - i * 30, 14), 7))
			lines.add_child(Skeleton.new().setup(Vector2(120, 10), 5))
			r.add_child(lines)
			v.add_child(r)
		return v
	if not bool(_board.get("ok", false)):
		var l := U.label(str(_board.get("error", "Keine Erfolge von Freunden.")), "s", "muted", "regular", true)
		l.custom_minimum_size = Vector2(440, 0)
		v.add_child(l)
		return v
	var me: Dictionary = Achievements.friends.me()
	me["count"] = got
	me["total"] = total
	var rank := Friends.ranking(_board.get("rows", []), me)
	var mine_i := 0
	for i in rank.size():
		if bool(rank[i].me):
			mine_i = i
	# Die ersten Plätze; liegst du weiter hinten, rückt dein Platz als letzter mit hinein.
	var shown: Array = rank.slice(0, RANK_ROWS)
	if mine_i >= RANK_ROWS:
		shown[RANK_ROWS - 1] = rank[mine_i]
	var now_ranks := {}
	for i in shown.size():
		var r: Dictionary = shown[i]
		now_ranks[str(r.id)] = i
		v.add_child(_rank_row(r, total, i, int(_ranks_shown.get(str(r.id), -1))))
	_ranks_shown = now_ranks
	var hidden := int(_board.get("hidden", 0))
	var more := rank.size() - shown.size()
	var notes := PackedStringArray()
	if more > 0:
		notes.append(U.plural(more, "weiterer Freund", "weitere Freunde"))
	if hidden > 0:
		notes.append("%s ohne öffentliche Erfolge" % U.plural(hidden, "Freund", "Freunde"))
	if not notes.is_empty():
		var nl := U.label("  ·  ".join(notes), "xs", "faint", "medium")
		nl.clip_text = false
		v.add_child(nl)
	return v


## Ein Platz links. Neu: kommt gestaffelt von unten (U.staffel); hat er den Platz gewechselt,
## rückt er von seinem alten Platz herüber (T_RAUM). Die Hülle hält den Platz im Layout, die
## Zeile darin bewegt sich.
func _rank_row(r: Dictionary, total: int, i := 0, old_i := -1) -> Control:
	var h := _rank_line(r, total)
	var holder := _Slot.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(0, RANK_ROW_H - 10.0)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(h)
	if U.reduziert():
		return holder
	if old_i < 0:
		h.position.y = U.weg_px(12.0)
		h.modulate.a = 0.0
		var tw := U.ankommen(h, U.T_ORT, "uz_rank").set_parallel(true)
		tw.tween_property(h, "position:y", 0.0, U.T_ORT).set_delay(U.staffel(i))
		tw.tween_property(h, "modulate:a", 1.0, U.T_ORT).set_delay(U.staffel(i))
	elif old_i != i:
		h.position.y = float(old_i - i) * RANK_ROW_H
		U.ankommen(h, U.T_RAUM, "uz_rank").tween_property(h, "position:y", 0.0, U.T_RAUM)
	return holder


## Hülle einer Rangzeile: hält den Platz im Layout und gibt der Zeile darin ihre Größe (ohne
## Anker – so bleibt die Zeile frei beweglich und wird nie breiter als die Hülle).
class _Slot extends Control:
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			for c in get_children():
				if c is Control:
					(c as Control).size = size


func _rank_line(r: Dictionary, total: int) -> Control:
	var me := bool(r.get("me", false))
	var h := U.hbox(12)
	var nr := U.label(str(int(r.get("rank", 0))), "m", "gold" if int(r.get("rank", 0)) == 1 else "muted", "bold")
	nr.custom_minimum_size.x = 28
	nr.clip_text = false
	nr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nr)
	var av = Avatar.new()
	av.setup(str(r.get("name", "")), str(r.get("avatar", "")), "", 40)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var tv := U.vbox(5)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	var line := U.hbox(10)
	var nl := U.ellipsis(U.label("Du" if me else str(r.get("name", "")), "s", "text", "ui_bold" if me else "medium"))
	if not me:
		nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nl.custom_minimum_size.x = 150
	line.add_child(nl)
	var cnt := U.label("%d von %d" % [int(r.get("count", 0)), total], "s", "muted", "ui")
	cnt.clip_text = false
	line.add_child(cnt)
	tv.add_child(line)
	var frac := float(r.get("count", 0)) / maxf(1.0, float(total))
	tv.add_child(TileS.fill_bar(frac, "gold" if frac >= 0.999 else ("accent" if me else "steam"), 5, 360))
	h.add_child(tv)
	return h


func _source() -> String:
	if str(_data.get("source", "")) != "":
		return str(_data.source)
	if game.has("_ra_id") or game.get("source") == "rom":
		return "ra"
	if game.has("_appid") or game.get("source") == "steam":
		return "steam"
	return "pc"


## Cover mit Schatten wie eine Hülle (Ersatz-Cover, bis das echte da ist).
func _cover(sz: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = sz
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Panel.new()
	var ssb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_cover())
	ssb.shadow_size = 28
	ssb.shadow_offset = Vector2(0, 12)
	ssb.shadow_color = Color(0, 0, 0, 0.5)
	sh.add_theme_stylebox_override("panel", ssb)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(sh)
	holder.add_child(sh)
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_cover()))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(clip)
	holder.add_child(clip)
	var ca = CoverArt.new()
	U.full_rect(ca)
	clip.add_child(ca)
	ca.setup(game if not game.is_empty() else { "title": str(_data.get("title", "")) })
	var bild := TextureRect.new()
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bild)
	clip.add_child(bild)
	var wtr: WeakRef = weakref(bild)
	var put := func(t: Texture2D) -> void:
		var x: TextureRect = wtr.get_ref()
		if x and t:
			x.texture = t
	if Library.get_game(str(game.get("id", ""))).is_empty():
		if _appid() > 0:
			var aid := _appid()
			Media.with_steam_assets(aid, func(a: Dictionary) -> void:
				Media.url_texture_chain(Store.art_urls_from({ "appid": aid }, a, true, 400), 400, put)
			)
		elif str(_data.get("icon", "")) != "":
			Media.url_texture(str(_data.icon), 300, put)
	else:
		Media.game_texture(game, "cover", put)
	return holder


# --- Rechts: Filter und Liste -----------------------------------------------------------

func _counts() -> Dictionary:
	var list: Array = _data.get("list", [])
	var got := list.filter(func(a): return a.get("unlocked", false)).size()
	return { "alle": list.size(), "frei": got, "offen": list.size() - got }


func _chips() -> Control:
	var h := U.hbox(6)
	h.set_meta("uz_group", "ach:filter")
	h.set_meta("uz_enter", "sel")
	h.add_child(U.glyph("lb", 28))
	var n := _counts()
	for fdef in FILTERS:
		var fid := str(fdef[0])
		if fid != "alle" and int(n[fid]) == 0:
			continue
		var item = NavItem.new()
		item.setup(str(fdef[1]), "", "chip", fid == _filter, int(n[fid]))
		item.set_meta("uz_filter", fid)
		item.set_meta("uz_key", "achf:" + fid)
		item.picked.connect(func() -> void:
			if _filter != fid:
				_set_filter(fid, false)
		)
		h.add_child(item)
	h.add_child(U.glyph("rb", 28))
	return h


## Filter wechseln beim Wählen; A hat dort nichts zu tun (erst im Baum setzen: der Reiter
## schreibt beim Erscheinen seinen eigenen Hinweis).
func _chip_hints() -> void:
	for c in Nav.focusables(_right):
		if c.has_meta("uz_filter"):
			c.set_meta("uz_hint_a", "—")


func _build_list(animate: bool) -> void:
	_chip_row = _chips()
	_right.add_child(_chip_row)
	_chip_hints()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.follow_focus = false
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.set_meta("uz_pad_v", 120.0)
	_right.add_child(_scroll)
	var pad := U.margin(4, 6, 8, 40)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pad)
	_list = U.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_list)
	EdgeFade.attach(_scroll, _list)
	_fill_rows(animate)


## Die Reihen für den gewählten Filter (Überschriften nur bei „Alle“).
func _fill_rows(animate: bool) -> void:
	var all: Array = _data.get("list", [])
	var open: Array = all.filter(func(a): return not a.get("unlocked", false))
	var done: Array = all.filter(func(a): return a.get("unlocked", false))
	# Offene: die am leichtesten zu holen sind zuerst (häufigste oben), geheime zuletzt.
	open.sort_custom(func(a, b):
		var ha: bool = a.get("hidden", false)
		var hb: bool = b.get("hidden", false)
		if ha != hb:
			return hb
		return float(a.get("rarity", -1.0)) > float(b.get("rarity", -1.0))
	)
	var now := int(Time.get_unix_time_from_system())
	var fresh_left := 3
	var rows: Array = _board.get("rows", []) if show_friends and bool(_board.get("ok", false)) else []
	var first := true
	var groups: Array = []
	if _filter != "offen" and not done.is_empty():
		groups.append(["Freigeschaltet", done])
	if _filter != "frei" and not open.is_empty():
		groups.append(["Noch offen", open])
	for grp in groups:
		if _filter == "alle":
			_list.add_child(_group_head(str(grp[0]), (grp[1] as Array).size()))
		for a in grp[1]:
			var r = AchRow.new()
			r.a = a
			r.fresh = fresh_left > 0 and a.get("unlocked", false) and now - int(a.get("date", 0)) < 86400
			if r.fresh:
				fresh_left -= 1
			if not rows.is_empty():
				var api := str(a.get("id", ""))
				r.friends_on = true
				r.friends_have = Friends.who_has(rows, api)
				r.friend_when = Friends.latest_of(rows, api)
			r.set_meta("uz_key", "acha:" + str(a.get("id", a.get("title", ""))))
			if first:
				r.set_meta("uz_default", true)
				first = false
			_list.add_child(r)
			if r.fresh:
				r.call_deferred("celebrate", 0.4)
	if animate:
		U.cascade.call_deferred(_scroll, 9)


func _group_head(text: String, n: int) -> Control:
	var m := U.margin(16, 14, 0, 6)
	var h := U.hbox(12)
	var l := U.label(text, "m", "text", "ui_bold")
	l.clip_text = false
	h.add_child(l)
	var c := U.label(str(n), "s", "faint", "medium")
	c.clip_text = false
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	m.add_child(h)
	return m


func _set_filter(fid: String, focus_list: bool) -> void:
	if (fid == _filter and not focus_list) or not is_instance_valid(_list):
		return
	_filter = fid
	Sfx.play("tab")
	# Die Filterleiste bleibt stehen (der gewählte Reiter darf nicht verschwinden), nur die
	# Reihen darunter bauen sich neu auf.
	for c in _chip_row.get_children():
		if c.has_meta("uz_filter") and c.has_method("set_selected"):
			c.call("set_selected", str(c.get_meta("uz_filter")) == fid)
	U.clear(_list)
	_scroll.scroll_vertical = 0
	_fill_rows(true)
	if not focus_list:
		# Mit LB/RB auf der Filterleiste: die Auswahl wandert mit zum neuen Filter.
		for c in _chip_row.get_children():
			if c.has_meta("uz_filter") and str(c.get_meta("uz_filter")) == fid and Nav.focused() != c:
				Nav.focus(c, true)
		return
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(_list):
		return
	var d := Nav.default_in(_list)
	if d:
		Nav.focus(d, true)


func _step_filter(d: int) -> void:
	var ids: Array = []
	var n := _counts()
	for fdef in FILTERS:
		if str(fdef[0]) == "alle" or int(n[str(fdef[0])]) > 0:
			ids.append(str(fdef[0]))
	var i := ids.find(_filter)
	var nxt := str(ids[(i + d + ids.size()) % ids.size()])
	var f := Nav.focused()
	_set_filter(nxt, not (f and f.has_meta("uz_filter")))


func _build_loading() -> void:
	# Der Filter steht schon da (und ist wählbar): Tasten gehen so nie an das Element dahinter.
	var chips := _chips()
	for c in chips.get_children():
		if c.has_meta("uz_filter"):
			c.set_meta("uz_loading", true)
			c.set_meta("uz_default", true)
	_right.add_child(chips)
	_chip_hints()
	_right.add_child(U.spacer(0, 6, false))
	for i in 6:
		var r := U.hbox(24)
		r.add_child(Skeleton.new().setup(Vector2(84, 84), 14))
		var lines := U.vbox(12)
		lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lines.add_child(Skeleton.new().setup(Vector2(360 - (i % 3) * 50, 24), 8))
		lines.add_child(Skeleton.new().setup(Vector2(560 - (i % 2) * 90, 18), 8))
		r.add_child(lines)
		var m := U.margin(16, 14, 16, 14)
		m.add_child(r)
		_right.add_child(m)


## Kein Ergebnis: ehrlich sagen warum, mit dem passenden nächsten Schritt.
func _build_empty() -> void:
	var head := ""
	var text := ""
	var buttons: Array = []
	var err := str(_data.get("error", ""))
	var rom := _source() == "ra"
	if err != "":
		var net := err.ends_with("nicht erreichbar.")
		head = "Gerade keine Verbindung" if net else "Erfolge gerade nicht abrufbar"
		text = err
		buttons.append(["Nochmal versuchen", "refresh", func() -> void: _load(true)])
		if err.contains("Konten"):
			buttons.append(["Konten öffnen", "user", func() -> void: _to_accounts()])
	elif rom and not Achievements.has_ra():
		head = "RetroAchievements verbinden"
		text = "RetroAchievements verbinden."
		if main:
			buttons.append(["Verbinden", "qr", func() -> void: main.open_ra_login()])
		else:
			buttons.append(["Konten einrichten", "user", func() -> void: _to_accounts()])
	elif not rom and not Achievements.has_steam():
		head = "Mit Steam anmelden"
		text = "Mit der Steam-App anmelden."
		buttons.append(["Konten einrichten", "user", func() -> void: _to_accounts()])
	elif _source() == "pc":
		head = "Keine Erfolge"
		text = "Keine Erfolge für eigene Spiele."
	elif rom:
		head = "Nichts bei RetroAchievements gefunden"
		text = "Nicht zugeordnet. Spiel-ID in den Spiel-Optionen eintragen."
		if main and not Library.get_game(str(game.get("id", ""))).is_empty():
			buttons.append(["Spiel-Optionen", "settings", func() -> void: main.open_game_options(Library.get_game(str(game.id)))])
	else:
		head = "Keine Erfolge"
		text = "Dieses Spiel hat bei Steam keine Erfolge."
	buttons.append(["Zurück", "", func() -> void: close()])
	var col := U.vbox(20)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_right.add_child(col)
	var cab = Cabinet.new().setup(err != "" or head == "Keine Erfolge" or head.begins_with("Nichts"))
	cab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(cab)
	var h := U.label(head, "xl", "text", "bold", true)
	col.add_child(h)
	var p := U.label(text, "m", "muted", "regular", true)
	p.custom_minimum_size = Vector2(760, 0)
	col.add_child(p)
	col.add_child(U.spacer(0, 8, false))
	var row := U.hbox(16)
	col.add_child(row)
	for i in buttons.size():
		var b: Array = buttons[i]
		var btn := U.button(str(b[0]), str(b[1]), "primary" if i == 0 else "normal")
		btn.pressed.connect(b[2])
		if i == 0:
			btn.set_meta("uz_default", true)
		row.add_child(btn)


func _to_accounts() -> void:
	close()
	if main:
		main.goto("settings", "konten")
