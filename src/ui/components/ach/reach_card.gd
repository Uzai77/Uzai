extends "res://src/ui/components/ach/tile.gd"
## „Als Nächstes greifbar“: ein offener Erfolg, den viele Spieler haben – Abzeichen (noch
## gedämpft), Name, Spiel, „62 % der Spieler haben ihn“ und, wenn bekannt, welcher Freund ihn
## schon hat. A öffnet die Erfolge des Spiels.

const Ach := preload("res://src/core/achievements.gd")
const Emblem := preload("res://src/ui/components/ach/emblem.gd")

var a: Dictionary = {}         ## Eintrag aus Achievements.reachable()
var friend_line := ""          ## „Mira hat ihn schon“ (leer: nichts bekannt)


func _init() -> void:
	super()
	tile_size = Vector2(520, 176)


func build_body() -> void:
	var tier := Ach.rarity_tier(float(a.get("rarity", -1.0)))
	var m := U.margin(20, 20, 24, 20)
	U.full_rect(m)
	body.add_child(m)
	var row := U.hbox(22)
	m.add_child(row)
	var em := Emblem.new().setup(str(a.get("icon", "")), false, tier, 128)
	em.check = false
	row.add_child(em)
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var t := U.ellipsis(U.label(str(a.get("title", "")), "m", "text", "ui_bold"))
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Name von Steam bzw. RetroAchievements
	col.add_child(t)
	var g := U.ellipsis(U.label(str(a.get("game", "")), "s", "muted"))
	g.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(g)
	col.add_child(U.spacer(0, 12, false))
	var pct := float(a.get("rarity", -1.0))
	if pct >= 0.0:
		var share := U.label("%s der Spieler haben ihn" % Ach.pct_text(pct), "s", "text", "medium")
		share.clip_text = false
		col.add_child(share)
	var foot := friend_line
	if foot == "" and int(a.get("points", 0)) > 0:
		foot = "%d Punkte" % int(a.points)
	if foot != "":
		var fl := U.ellipsis(U.label(foot, "xs", "accent" if friend_line != "" else "faint", "medium"))
		col.add_child(fl)
