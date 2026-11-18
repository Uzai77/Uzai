extends RefCounted
## Nur für Tests: die Werte des früheren Glas-Aussehens (Hanken Grotesk, runde Ecken, Glimmen, volle
## Schatten, helle Auswahl). UzTheme zeichnet diese Zweige noch; die Grundwerte der Marke
## (src/core/aussehen.gd: matt, flach, eckiger) nehmen sie nicht. Tests, die Schatten, Glimmen und
## Glas prüfen, setzen sie mit UzTheme.grund = GlasWerte.werte() und rufen UzTheme.apply().

const Aussehen := preload("res://src/core/aussehen.gd")


static func werte() -> Dictionary:
	var w := Aussehen.werte()
	w.colors = {
		"bg": Color("#0d0e10"), "surface": Color("#17181b"), "surface_hi": Color("#222327"), "line": Color("#2c2d31"),
		"text": Color("#f3f1ec"), "muted": Color("#a6a49f"), "faint": Color("#77756f"),
		"accent": Color("#a47bff"), "focus": Color("#f4efe6"),
	}
	w.fonts = {
		"body": "hanken", "display": "hanken",
		"w_regular": 400, "w_medium": 520, "w_bold": 650, "w_black": 760,
		"w_title": 700, "w_display_black": 760, "w_ui": 520, "w_ui_bold": 640, "w_wide": 500,
		"title_spacing": -2, "display_spacing": -1,
	}
	w.shape = { "radius": 16, "panel": 1.6, "cover": 0.85, "pill": true, "glass": 1.0, "solid": 0.94, "shadow": 1.0,
		"material": "glas", "strict": false }
	w.focus = { "glow": 1.0, "frame": 0, "frame_gap": 3, "frame_color": "accent", "scale": 1.12, "ring": 3, "band": 1.0, "shine": true,
		"fill": "hell" }
	w.popup = { "top": Color(0.149, 0.153, 0.173, 0.96), "bottom": Color(0.082, 0.086, 0.098, 0.96), "light": Color("#a47bff"),
		"line1": Color("#c9c5bc"), "disc_a": Color("#3b3c42"), "disc_b": Color("#232428"), "corner": 1.0 }
	return w
