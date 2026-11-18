extends "res://src/ui/components/ach/tile.gd"
## Ein Spiel mit seinem Erfolgsstand: Cover, Titel, System, Prozent, Balken und was noch
## fehlt. Komplette Spiele tragen ihre Auszeichnung in Gold.

const Ach := preload("res://src/core/achievements.gd")
const CoverArt := preload("res://src/ui/components/cover_art.gd")
const Rarity := preload("res://src/ui/components/ach/rarity.gd")

var p: Dictionary = {}           ## Fortschritt { title, source, total, unlocked, console_name, award, icon, appid, ra_id }
var game: Dictionary = {}        ## dasselbe Spiel aus der Bibliothek (für das Cover), darf leer sein
var system_id := ""              ## System für das Ersatz-Cover, wenn das Spiel nicht in der Bibliothek ist


func _init() -> void:
	super()
	tile_size = Vector2(560, 208)


func build_body() -> void:
	var total := int(p.get("total", 0))
	var got := int(p.get("unlocked", 0))
	var frac := float(got) / maxf(1.0, float(total))
	var done := total > 0 and got >= total
	var m := U.margin(18, 16, 24, 16)
	U.full_rect(m)
	body.add_child(m)
	var row := U.hbox(22)
	m.add_child(row)
	row.add_child(_cover(Vector2(132, 176)))
	# Oben System und Titel, unten Zahlen und Balken: in jeder Kachel auf derselben Höhe.
	var col := U.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var where := "Steam" if p.get("source") == "steam" else str(p.get("console_name", "RetroAchievements"))
	var last := Rarity.when(int(p.get("date", 0)))
	if last != "":
		where += "  ·  zuletzt " + (U.lower_first(last) if last in ["Heute", "Gestern", "Gerade eben"] or last.begins_with("Vor ") else last)
	col.add_child(U.ellipsis(U.label(where, "s", "muted", "medium")))
	var t := U.label(str(p.get("title", "")), "m", "text", "ui_bold", true)
	t.max_lines_visible = 2
	t.custom_minimum_size = Vector2(330, 0)
	col.add_child(t)
	col.add_child(U.spacer(0, 4))
	var nums := U.hbox(10)
	var pc := U.label("%d %%" % int(floor(frac * 100.0)), "l", "gold" if done else "accent", "bold")
	pc.clip_text = false
	nums.add_child(pc)
	nums.add_child(U.spacer())
	var cnt := U.label("%d / %d" % [got, total], "s", "muted", "medium")
	cnt.clip_text = false
	cnt.size_flags_vertical = Control.SIZE_SHRINK_END
	nums.add_child(cnt)
	col.add_child(nums)
	col.add_child(fill_bar(frac, "gold" if done else "accent", 8))
	var award := Ach.award_name(str(p.get("award", "")))
	var foot := ""
	if done:
		foot = award if award != "" else "Alle Erfolge freigeschaltet"
	else:
		foot = "Noch %s" % U.plural(total - got, "Erfolg", "Erfolge")
		if award != "":
			foot = award + "  ·  " + foot
	var fl := U.ellipsis(U.label(foot, "xs", "gold" if done else "faint", "medium"))
	col.add_child(fl)


## Cover: aus der Bibliothek, sonst das Bild der Quelle; bis dahin ein Ersatz-Cover.
func _cover(sz: Vector2) -> Control:
	var clip := Panel.new()
	clip.custom_minimum_size = sz
	clip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	U.clip_round(clip)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ca = CoverArt.new()
	ca.compact = true
	U.full_rect(ca)
	clip.add_child(ca)
	ca.setup(game if not game.is_empty() else { "title": str(p.get("title", "")), "system": "steam" if p.get("source") == "steam" else system_id })
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(tr)
	clip.add_child(tr)
	var wtr: WeakRef = weakref(tr)
	var put := func(t: Texture2D) -> void:
		var x: TextureRect = wtr.get_ref()
		if x and t:
			x.texture = t
			x.modulate.a = 0.0
			x.create_tween().tween_property(x, "modulate:a", 1.0, U.T_BASE)
	if not game.is_empty():
		Media.game_texture(game, "cover", put)
	elif p.get("source") == "steam" and int(p.get("appid", 0)) > 0:
		# Hülle unter ihrem echten Namen (neue Spiele: Ordner mit Prüfsumme), sonst die alte Adresse.
		var aid := int(p.appid)
		Media.with_steam_assets(aid, func(a: Dictionary) -> void:
			Media.url_texture_chain(Store.art_urls_from({ "appid": aid }, a, true, 300), 300, put)
		)
	elif str(p.get("icon", "")) != "":
		Media.url_texture(str(p.icon), 200, put)
	return clip
