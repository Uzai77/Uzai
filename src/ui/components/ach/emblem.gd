extends Control
## Bild eines Erfolgs: das echte Symbol mit runden Ecken – oder, solange es fehlt (ohne Netz,
## Demo), ein ruhiges Abzeichen in der Farbe der Seltenheit statt einer leeren Fläche.
## Gesperrt: gedämpft, im Abzeichen ein Schloss. Freigeschaltet: kleiner Goldhaken.

const Rarity := preload("res://src/ui/components/ach/rarity.gd")

var url := ""
var unlocked := true
var tier := -1
var px := 96
var check := true            ## Goldhaken bei freigeschalteten
var glow := 0.0              ## 0…1: Schein (frisch freigeschaltet, ultra selten)
var secret := false          ## geheimer Erfolg: verdecktes Auge statt Schloss
var gold := false            ## Pokal-Gold statt der Seltenheitsfarbe (gemeisterte Spiele, Vitrine)
var _tex: Texture2D


func setup(icon_url: String, is_unlocked: bool, rarity_tier: int, size_px := 96) -> Control:
	url = icon_url
	unlocked = is_unlocked
	tier = rarity_tier
	px = size_px
	return self


func _ready() -> void:
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unlocked and tier == 3:
		glow = maxf(glow, 0.55)
	if url != "":
		var wr: WeakRef = weakref(self)
		Media.url_texture(url, 128, func(t: Texture2D) -> void:
			var me: Control = wr.get_ref()
			if me and t:
				me.set("_tex", t)
				me.queue_redraw()
		)


func set_glow(v: float) -> void:
	glow = v
	queue_redraw()


## Abgerundetes Rechteck als Punktliste (für Bild und Fläche mit Verlauf).
static func rounded(r: Rect2, rad: float, seg := 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
	for c in corners:
		for i in seg + 1:
			var a: float = float(c[1]) + PI * 0.5 * float(i) / seg
			pts.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	return pts


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(px, px))
	var rad := clampf(px * 0.17, 8.0, 20.0)
	var tc := UzTheme.col("gold") if gold else Rarity.color(maxi(tier, 0))
	if glow > 0.01:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(tc, 0.0)
		sb.set_corner_radius_all(int(rad))
		sb.shadow_color = Color(UzTheme.col("gold") if gold else UzTheme.col("accent"), 0.42 * glow * UzTheme.glow_k())
		sb.shadow_size = int(px * 0.22)
		draw_style_box(sb, r)
	var pts := rounded(r, rad)
	if _tex:
		var uvs := PackedVector2Array()
		var ts := _tex.get_size()
		# Bild füllt die Fläche (mittig zugeschnitten, falls es nicht quadratisch ist).
		var crop := Rect2(Vector2.ZERO, Vector2.ONE)
		if ts.x > ts.y and ts.y > 0:
			var w := ts.y / ts.x
			crop = Rect2((1.0 - w) * 0.5, 0.0, w, 1.0)
		elif ts.y > ts.x and ts.x > 0:
			var h := ts.x / ts.y
			crop = Rect2(0.0, (1.0 - h) * 0.5, 1.0, h)
		for p in pts:
			uvs.append(crop.position + (p / r.size) * crop.size)
		var a := 1.0 if unlocked else 0.5
		draw_polygon(pts, PackedColorArray([Color(1, 1, 1, a)]), uvs, _tex)
		if not unlocked:
			draw_polygon(pts, PackedColorArray([Color(UzTheme.col("bg"), 0.25)]))
	else:
		_badge(r, pts, tc)
	var edge := pts.duplicate()
	edge.append(pts[0])
	draw_polyline(edge, Color(UzTheme.col("text"), 0.07 if unlocked else 0.05), 1.0, true)
	if unlocked and check:
		var cr := maxf(9.0, px * 0.13)
		var c := r.end - Vector2(cr * 0.7, cr * 0.7)
		draw_circle(c, cr + 2.0, UzTheme.col("surface"))
		draw_circle(c, cr, UzTheme.col("gold"))
		var ic := Icons.tex("check", int(cr * 1.3))
		var isz := Vector2(cr * 1.3, cr * 1.3)
		draw_texture_rect(ic, Rect2(c - isz * 0.5, isz), false, UzTheme.col("on_accent"))


## Abzeichen ohne Bild: Fläche mit Verlauf in der Seltenheitsfarbe, Ring und Pokal.
func _badge(r: Rect2, pts: PackedVector2Array, tc: Color) -> void:
	var base := UzTheme.col("surface_hi")
	var top := base.lerp(tc, 0.2 if unlocked else 0.05)
	var bottom := base.lerp(UzTheme.col("bg"), 0.35)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf(p.y / r.size.y, 0.0, 1.0)))
	draw_polygon(pts, cols)
	var c := r.get_center()
	var rr := px * 0.3
	var ring := Color(tc, 0.55 if unlocked else 0.16)
	draw_arc(c, rr, 0.0, TAU, 56, ring, maxf(1.5, px * 0.022), true)
	if unlocked and tier >= 2:
		# Seltene tragen einen zweiten, feinen Ring wie eine Medaille.
		draw_arc(c, rr + px * 0.07, 0.0, TAU, 64, Color(tc, 0.22), 1.0, true)
	var gs := int(px * 0.32)
	var ic := Icons.tex("trophy" if unlocked else ("eye_off" if secret else "lock"), gs)
	draw_texture_rect(ic, Rect2(c - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false,
		tc if unlocked else UzTheme.col("faint", 0.9))
