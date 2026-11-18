extends RefCounted
## Grundwerte des Aussehens: „Graphit“ mit der Marke (docs/DESIGN.md) – matte Graphit-Flächen, eine
## Form für alles, ein Cursor, ein Akzent, IBM Plex. Sie gelten überall dort, wo die Einstellungen
## („theme.*“) nichts Eigenes wählen („Standard“). UzTheme liest sie einmal (UzTheme.grund) und
## rechnet daraus Farben, Schriften und Formen.
## Früher standen diese Werte in einem Theme-Paket; Themes gibt es nicht mehr.

## Arten des Hintergrunds und der Startanimation, wie die Einstellungen sie kennen.
const BG_STYLES := ["game", "farbe", "nebel", "bild"]
const BOOT_STYLES := ["voll", "kurz", "roehre", "aus"]
## Stärken und Laufweite für eine selbst gewählte Titelschrift (Einstellungen › Aussehen › Mehr ›
## Schrift für Titel). Die Marke setzt ihre eigenen in werte().fonts.
const TITEL_EIGEN := { "w_title": 700, "w_display_black": 760, "w_ui": 520, "w_ui_bold": 640, "w_wide": 500,
	"title_spacing": -2, "display_spacing": -1 }


static func werte() -> Dictionary:
	return {
		"colors": {
			"bg": Color("#0b0b0d"), "surface": Color("#141417"), "surface_hi": Color("#1c1c21"), "line": Color("#2a2a30"),
			"text": Color("#f2f2f2"), "muted": Color("#a8a8b0"), "faint": Color("#80808a"),
			"accent": Color("#a47bff"), "focus": Color("#f2f2f2"),
		},
		## body: Grundschrift (Sätze, Werte), display: Titel, Reiter, Knöpfe. Stärken für variable
		## Schriften (wght), spacing: Laufweite der Titel in Punkten.
		"fonts": {
			"body": "plex", "display": "plex_condensed",
			"w_regular": 400, "w_medium": 500, "w_bold": 600, "w_black": 700,
			"w_title": 700, "w_display_black": 700, "w_ui": 500, "w_ui_bold": 600, "w_wide": 500,
			"title_spacing": 0, "display_spacing": 0,
		},
		## radius: Grundradius (Zeilen, Knöpfe); panel/cover: Faktoren für große Flächen und Cover;
		## pill: Knöpfe als Pillen; glass: Deckkraft der Glasflächen (Faktor); solid: Deckkraft der
		## festen Flächen (Guide, Menüs); shadow: Weite der Schatten (Faktor); material: „matt“ (feste
		## Graphit-Flächen) oder „glas“ (Tinte mit wenig Deckkraft); strict: eine Form für alles –
		## feste Rundungen der Bauteile höchstens der größte Radius, Pillen bleiben Pillen.
		"shape": { "radius": 10, "panel": 1.4, "cover": 1.2, "pill": true, "glass": 1.0, "solid": 0.98, "shadow": 0.6,
			"material": "matt", "strict": true },
		## glow: Glimmen um die Auswahl (Faktor); frame: heller Ring um Cover und Kacheln (Punkte) im
		## Abstand frame_gap; scale: so stark wachsen Cover und Kacheln; ring, band: Ring und zartes
		## Band im Akzent direkt am Cover (0 = keins); shine: Lichtstreif über gewählten Bildern;
		## fill: „matt“ ist der Cursor der Marke (Zeilen als gehobene Fläche ohne Linie, Knöpfe hell
		## gefüllt), „hell“ die eine helle Fläche.
		"focus": { "glow": 0.0, "frame": 4, "frame_gap": 3, "frame_color": "focus", "scale": 1.04, "ring": 0, "band": 0.0, "shine": false,
			"fill": "matt" },
		## style: Art des Hintergrunds (BG_STYLES); stage: wo das Bild des Spiels steht (Anteile x, y,
		## Breite, Höhe); fade_x/fade_y: wie weit es nach links bzw. ab wo es nach unten ausläuft;
		## top_dim: Abdunklung oben; shade: wie stark das Bild abgedunkelt wird (mal „Abdunklung“ in
		## den Einstellungen); aurora: Farbverläufe (Faktor); tint: Raum in Spielfarbe, tint_k: wie kräftig.
		"background": {
			"style": "game", "stage": [0.28, 0.0, 0.72, 0.68], "fade_x": 0.58, "fade_y": 0.4, "top_dim": 0.4, "shade": 0.45,
			"aurora": 1.0, "tint": true, "tint_k": 1.0,
		},
		"layout": { "cover_shape": "hoch", "cover_size": "m", "reflection": true },
		## style: Startanimation (BOOT_STYLES).
		"boot": { "style": "voll" },
		## Erfolgs-Pop-ups: Fläche oben/unten, Licht (Ring, erste Zeile), Scheibe; corner: 1 = Pille,
		## 0 = eckig.
		"popup": { "top": Color(0.149, 0.153, 0.173, 0.96), "bottom": Color(0.082, 0.086, 0.098, 0.96), "light": Color("#a47bff"),
			"line1": Color("#c9c9cf"), "disc_a": Color("#3b3c42"), "disc_b": Color("#232428"), "corner": 0.0 },
	}
