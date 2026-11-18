extends RefCounted
## Spielstart-Karte, ohne Bildschirm (darum testbar): welches Bild wie gezeigt wird, wie groß
## Logo und Hülle höchstens werden, was Steam gerade tut – und das Vorbereiten der Bilder im
## Hintergrund-Thread (prepare).
##
## Grundsatz: nie ein kleines Bild groß ziehen. Gerechnet wird in Bildschirmpunkten (UI-Punkte
## × pxs, in 4K 2): Ein Logo mit 640 Punkten Breite ist in 4K höchstens 320 UI-Punkte breit.
## Ein Hero, der den Schirm nicht ohne Hochziehen füllt, steht scharf in der Mitte und läuft
## nach außen weich in sich selbst aus; reicht er dafür nicht, kommt die Hülle scharf in die
## Mitte und dahinter ein weichgezeichneter Grund aus dem Bild.

const MediaScript := preload("res://src/core/media.gd")
const InstallParse := preload("res://src/core/install_parse.gd")
const VDF := preload("res://src/library/vdf.gd")

## So weit darf ein Bild höchstens hochgezogen werden (12 % sieht man bei linearer Filterung nicht).
const UP_TOL := 1.12
## Ken Burns: so viel größer wird das Bild in der ganzen Startzeit höchstens.
const KB_ZOOM := 1.05
## Das scharfe Bild muss mindestens so viel vom Schirm decken, sonst Hülle in die Mitte.
const HERO_MIN := Vector2(0.7, 0.4)
## Höchstmaße (UI-Punkte): Logo allein, Logo unter der Hülle, Hülle, breites Bild als Element.
const LOGO_BOX := Vector2(860, 330)
const LOGO_BOX_SMALL := Vector2(600, 150)
const BOX_BOX := Vector2(760, 540)
const WIDE_BOX := Vector2(1100, 470)
## Kleiner wirkt ein Logo verloren: dann lieber der gesetzte Titel.
const LOGO_MIN := Vector2(230, 64)
## Grund aus einem kleinen Bild: so breit reicht, er wird ohnehin weichgezeichnet.
const BACK_SMALL := 720


## Wie groß (UI-Punkte) und wo das scharfe Bild bei Zoom 1 liegt: deckend wie
## STRETCH_KEEP_ASPECT_COVERED, aber höchstens UP_TOL-fach vergrößert.
static func band(tex_px: Vector2, view: Vector2, pxs: float) -> Rect2:
	if tex_px.x <= 0.0 or tex_px.y <= 0.0:
		return Rect2()
	var vp := view * pxs
	var cs := maxf(vp.x / tex_px.x, vp.y / tex_px.y)
	var s := minf(cs, UP_TOL)
	var sz := tex_px * s / pxs
	var pos := Vector2((view.x - sz.x) * 0.5, 0.0)
	if sz.y >= view.y:
		pos.y = (view.y - sz.y) * 0.5
	else:
		# Ein flacher Streifen (Hero) steht etwas über der Mitte, beim Logo.
		pos.y = clampf(view.y * 0.46 - sz.y * 0.5, 0.0, view.y - sz.y)
	return Rect2(pos, sz)


## Wie stark das Bild beim Zeichnen höchstens vergrößert wird (1 = Bildpunkt auf Bildpunkt).
static func band_scale(tex_px: Vector2, view: Vector2, pxs: float) -> float:
	var b := band(tex_px, view, pxs)
	return b.size.x * pxs / tex_px.x if tex_px.x > 0.0 else 0.0


## Deckend ohne Grenze (Grund, der ohnehin weichgezeichnet wird).
static func cover_rect(tex_px: Vector2, view: Vector2) -> Rect2:
	if tex_px.x <= 0.0 or tex_px.y <= 0.0:
		return Rect2(Vector2.ZERO, view)
	var sz := tex_px * maxf(view.x / tex_px.x, view.y / tex_px.y)
	return Rect2((view - sz) * 0.5, sz)


static func hero_ok(tex_px: Vector2, view: Vector2, pxs: float) -> bool:
	var b := band(tex_px, view, pxs)
	return b.size.x >= view.x * HERO_MIN.x - 0.5 and b.size.y >= view.y * HERO_MIN.y - 0.5


## Welche Bilder die Karte nimmt. sizes: Art → Größe in Bildpunkten (fehlend oder 0: keins).
## { mode: hero | box | plain, back: Art für den Grund, front: Art für das Element in der Mitte }
## Reihenfolge: großer Hero ganzflächig → Hülle (sonst breites Bild, sonst kleiner Hero) scharf
## in der Mitte vor einem weichen Grund aus dem Hero oder dem Element selbst → nur Farben.
static func pick(sizes: Dictionary, view: Vector2, pxs: float) -> Dictionary:
	var hero: Vector2 = sizes.get("hero", Vector2.ZERO)
	if hero.x > 0.0 and hero_ok(hero, view, pxs):
		return { "mode": "hero", "back": "hero", "front": "" }
	for k in ["cover", "wide", "hero"]:
		var s: Vector2 = sizes.get(k, Vector2.ZERO)
		if s.x > 0.0 and s.y > 0.0:
			return { "mode": "box", "back": "hero" if hero.x > 0.0 else k, "front": k }
	return { "mode": "plain", "back": "", "front": "" }


## Anzeigegröße (UI-Punkte) für ein Bild in einem Rahmen: eingepasst, aber nie größer als die
## Bildpunkte des Bilds selbst (pxs: Bildschirmpunkte je UI-Punkt). Auf ganze Bildschirmpunkte
## gerundet, damit es Punkt auf Punkt gezeichnet wird.
static func fit_native(tex_px: Vector2, box_ui: Vector2, pxs: float) -> Vector2:
	if tex_px.x <= 0.0 or tex_px.y <= 0.0:
		return Vector2.ZERO
	var native := tex_px / pxs
	var s := minf(1.0, minf(box_ui.x / native.x, box_ui.y / native.y))
	var phys := (tex_px * s).round()
	return Vector2(maxf(1.0, phys.x), maxf(1.0, phys.y)) / pxs


static func logo_ok(tex_px: Vector2, box_ui: Vector2, pxs: float) -> bool:
	var sz := fit_native(tex_px, box_ui, pxs)
	return sz.x >= LOGO_MIN.x or sz.y >= LOGO_MIN.y


static func front_box(kind: String) -> Vector2:
	return WIDE_BOX if kind in ["wide", "hero"] else BOX_BOX


## Was Steam gerade mit dem Spiel tut (appmanifest, AppState): { text, frac (-1 = unbekannt) };
## text leer, wenn nichts Besonderes ansteht.
static func steam_note(st: Dictionary) -> Dictionary:
	var flags := int(str(VDF.get_ci(st, "StateFlags", "0")))
	var total := float(str(VDF.get_ci(st, "BytesToDownload", "0")))
	var got := float(str(VDF.get_ci(st, "BytesDownloaded", "0")))
	if flags & InstallParse.ST_VALIDATING:
		return { "text": "Steam überprüft Dateien …", "frac": -1.0 }
	if flags & (InstallParse.ST_STAGING | InstallParse.ST_COMMITTING):
		return { "text": "Steam installiert ein Update …", "frac": -1.0 }
	if flags & InstallParse.ST_PREALLOCATING:
		return { "text": "Steam reserviert Speicherplatz …", "frac": -1.0 }
	if flags & (InstallParse.ST_DOWNLOADING | InstallParse.ST_UPDATE_RUNNING | InstallParse.ST_UPDATE_STARTED):
		if total > 0.0:
			var f := clampf(got / total, 0.0, 1.0)
			return { "text": "Steam lädt ein Update · %d %%" % int(f * 100.0), "frac": f }
		return { "text": "Steam bereitet ein Update vor …", "frac": -1.0 }
	if (flags & InstallParse.ST_UPDATE_REQUIRED) and not (flags & InstallParse.ST_UPDATE_PAUSED):
		return { "text": "Steam bereitet ein Update vor …", "frac": -1.0 }
	return { "text": "", "frac": -1.0 }


## Zustand vom Launcher für die Karte: ohne den Titel (der steht groß darüber).
## „Steam startet Portal 2 …“ → „Steam startet …“, „Portal 2 startet …“ → „Wird gestartet …“.
static func status_text(text: String, title: String) -> String:
	var t := text.strip_edges()
	if t == "":
		return "Wird gestartet …"
	if title != "" and t.contains(title):
		t = t.replace("„" + title + "“", "").replace(title, "").replace("  ", " ").strip_edges()
		if t == "" or t.begins_with("startet") or t.begins_with("…"):
			return "Wird gestartet …"
	return t


# --- Im Hintergrund-Thread ----------------------------------------------------------------------

## Lädt die Bilder (paths: Art → Datei), wählt die Darstellung und rechnet alles so vor, dass der
## Hauptthread nur noch hochlädt. Ergebnis in box["res"], danach box["done"] = true (unter box["m"]).
static func prepare(box: Dictionary, paths: Dictionary, view: Vector2, pxs: float) -> void:
	var imgs := {}
	var sizes := {}
	for k in paths:
		if k == "logo":
			continue
		var img := MediaScript.load_image(str(paths[k]))
		if img and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			imgs[k] = img
			sizes[k] = Vector2(img.get_size())
	var res := pick(sizes, view, pxs)
	res["sizes"] = sizes.duplicate()
	if res.mode != "plain":
		var src: Image = imgs[res.back]
		var tex_px := Vector2(src.get_size())
		var img := src.duplicate() as Image if res.front == res.back else src
		if res.mode == "hero":
			res["band"] = band(tex_px, view, pxs)
			res["up"] = band_scale(tex_px, view, pxs)
			# Größer als je gezeichnet (bei vollem Ken-Burns-Zoom Punkt auf Punkt) muss es nicht sein.
			var need := band_scale(tex_px, view, pxs) * KB_ZOOM
			if need < 1.0:
				MediaScript.shrink_to(img, int(ceil(tex_px.x * need)))
		else:
			res["band"] = cover_rect(tex_px, view)
			if img.get_width() > BACK_SMALL:
				MediaScript.shrink_to(img, BACK_SMALL)
		_rgba(img)
		var small := img.duplicate() as Image
		MediaScript.shrink_to(small, 96)
		res["palette"] = palette(small)
		if res.mode != "hero":
			# Blur here already (in the background thread) instead of in the shader from small mip levels,
			# which looked blocky/pixelated: first very small, then scaled up cubically = smooth gradient.
			img = vorweich(img)
			res["vorweich"] = true
		img.generate_mipmaps()
		res["back_img"] = img
		if res.front != "":
			var f: Image = imgs[res.front]
			var fsz := fit_native(Vector2(f.get_size()), front_box(res.front), pxs)
			var fi := _scaled(f, (fsz * pxs).round())
			res["front_img"] = fi
			res["front_size"] = fsz
	if paths.has("logo"):
		var lg := MediaScript.load_image(str(paths.logo))
		if lg and not lg.is_empty():
			if lg.is_compressed():
				lg.decompress()
			_rgba(lg)
			# Durchsichtige Ränder weg: sonst steht das Logo optisch nicht in der Mitte.
			var ur := lg.get_used_rect()
			if ur.size.x > 0 and ur.size.y > 0 and ur.size != lg.get_size():
				lg = lg.get_region(ur)
			var lbox := LOGO_BOX_SMALL if res.mode == "box" else LOGO_BOX
			var lpx := Vector2(lg.get_size())
			res["logo_native"] = lpx
			if logo_ok(lpx, lbox, pxs):
				var lsz := fit_native(lpx, lbox, pxs)
				lg.fix_alpha_edges()
				var li := _scaled(lg, (lsz * pxs).round())
				res["logo_img"] = li
				res["logo_size"] = lsz
				var g := glow(li)
				res["glow_img"] = g.img
				res["glow_pad"] = g.pad / pxs
	var m: Mutex = box.m
	m.lock()
	box["res"] = res
	box["done"] = true
	m.unlock()


## Glatt weichgezeichnet (für den Hintergrund ohne großes Bild): auf WEICH_KLEIN Punkte Breite
## verkleinern und kubisch auf das Achtfache vergrößern. Kein Muster, keine Treppen.
const WEICH_KLEIN := 40


static func vorweich(src: Image) -> Image:
	var b := src.duplicate() as Image
	_rgba(b)
	MediaScript.shrink_to(b, WEICH_KLEIN)
	b.resize(b.get_width() * 8, b.get_height() * 8, Image.INTERPOLATE_CUBIC)
	return b


static func _rgba(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)


## Auf genau diese Größe (Bildschirmpunkte) verkleinern: erst halbieren, solange es geht, den Rest
## mit Lanczos (scharf, ohne Treppen). Nie vergrößern.
static func _scaled(src: Image, target: Vector2) -> Image:
	var img := src.duplicate() as Image
	_rgba(img)
	var tw := int(target.x)
	var th := int(target.y)
	if tw >= img.get_width() or th >= img.get_height():
		return img
	while img.get_width() >= tw * 2 and img.get_height() >= th * 2:
		img.shrink_x2()
	if img.get_width() != tw or img.get_height() != th:
		img.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	return img


## Kräftige Farbe und dunkle Grundfarbe eines (kleinen) Bilds: { vivid, ground }.
static func palette(small: Image) -> Dictionary:
	var vivid: Variant = MediaScript.vivid_color(small)
	var acc := Color(0, 0, 0, 0)
	var n := 0.0
	for y in small.get_height():
		for x in small.get_width():
			var c := small.get_pixel(x, y)
			acc += Color(c.r, c.g, c.b, 0) * c.a
			n += c.a
	var avg := Color(acc.r / maxf(n, 1.0), acc.g / maxf(n, 1.0), acc.b / maxf(n, 1.0))
	# Wie alle Spielfarben im festen Helligkeitsband (Zuschnitt.accent).
	var v: Color = MediaScript.Zuschnitt.accent(vivid) if vivid is Color else avg
	return { "vivid": v, "ground": ground_of(avg, v) }


## Dunkle Grundfarbe aus Mittel- und kräftiger Farbe: sehr dunkel, leicht gesättigt.
static func ground_of(avg: Color, vivid: Color) -> Color:
	var g := avg.lerp(vivid, 0.35)
	var h := g.h
	var s := clampf(g.s * 0.9, 0.12, 0.6)
	return Color.from_hsv(h, s, 0.085)


## Weicher Hof unter dem Logo: die Form des Logos, stark weichgezeichnet, mit Rand. Klein
## gerechnet (höchstens ~140 Punkte breit), dreimal Kastenweichzeichner (wirkt wie ein Gauß)
## und kubisch auf das Vierfache – auf dem Schirm wird es nur noch leicht linear gestreckt.
## { img: weißes Bild mit Deckkraft, pad: Rand in Bildschirmpunkten }
static func glow(logo: Image) -> Dictionary:
	var small := logo.duplicate() as Image
	var f := 1
	while small.get_width() > 140 and small.get_height() > 8:
		small.shrink_x2()
		f *= 2
	var sw := small.get_width()
	var sh := small.get_height()
	var r := maxi(2, int(round(minf(sh, sw * 0.25) * 0.16)))
	var pad := r * 4 + 2
	var gw := sw + pad * 2
	var gh := sh + pad * 2
	var a := PackedFloat32Array()
	a.resize(gw * gh)
	for y in sh:
		for x in sw:
			a[(y + pad) * gw + x + pad] = small.get_pixel(x, y).a
	for i in 3:
		a = _box_blur(a, gw, gh, r, true)
		a = _box_blur(a, gw, gh, r, false)
	var bytes := PackedByteArray()
	bytes.resize(gw * gh * 4)
	for i in gw * gh:
		bytes[i * 4] = 255
		bytes[i * 4 + 1] = 255
		bytes[i * 4 + 2] = 255
		bytes[i * 4 + 3] = clampi(int(a[i] * 255.0 + 0.5), 0, 255)
	var img := Image.create_from_data(gw, gh, false, Image.FORMAT_RGBA8, bytes)
	var up := mini(4, f)
	if up > 1:
		img.resize(gw * up, gh * up, Image.INTERPOLATE_CUBIC)
	return { "img": img, "pad": float(pad * f) }


static func _box_blur(src: PackedFloat32Array, w: int, h: int, r: int, horiz: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var n := float(r * 2 + 1)
	var lines := h if horiz else w
	var ln := w if horiz else h
	var st := 1 if horiz else w
	for l in lines:
		var base := l * w if horiz else l
		var s := 0.0
		for k in range(-r, r + 1):
			s += src[base + clampi(k, 0, ln - 1) * st]
		for i in ln:
			out[base + i * st] = s / n
			var add := clampi(i + r + 1, 0, ln - 1)
			var sub := clampi(i - r, 0, ln - 1)
			s += src[base + add * st] - src[base + sub * st]
	return out
