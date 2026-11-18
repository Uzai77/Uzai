extends Node
## Bilder für Spiele, untere Schicht: reine Funktionen ohne Netz und ohne Zustand – Bilder sicher
## lesen und verkleinern (Größengrenzen), Bild-Adressen von Steam und Libretro, Namen zuordnen,
## Zuschnitt merken (look) und die Farbe eines Bildes. media.gd erbt davon.

const Leicht := preload("res://src/core/leicht.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")
const Sicher := preload("res://src/core/sicher.gd")
const Fremd := preload("res://src/core/fremd.gd")

## Größtes Bild, das Uzai dekodiert (Seite bzw. Pixel). Bilder kommen auch aus fremden Quellen
## (SteamGridDB, Addons, Wikipedia): Ein kleines PNG mit 16384 × 16384 Pixeln belegte entpackt
## 1 GB – je Kachel und Faden. 8K-Bildschirmfotos passen noch.
const IMG_MAX_SIDE := 8192
const IMG_MAX_PIXELS := 8192 * 4608
const STEAM_FILES := { "cover": "library_600x900.jpg", "hero": "library_hero.jpg", "logo": "logo.png", "wide": "header.jpg", "icon": "icon.jpg" }
## Cover in festem Format für das Regal (src/library/regal.gd BILDARTEN): Formate bei SteamGridDB.
## cover_scan: echter Scan der Verpackung (Libretro-Boxarts bzw. ScreenScraper box-2D, mit dem
## Rahmen des Systems); ruecken: Scan des Rückens (ScreenScraper box-2D-side).
const SGDB_MASSE := { "cover": "600x900", "cover_hoch": "660x930,342x482", "cover_quadrat": "1024x1024,512x512",
	"cover_quer": "920x430,460x215" }
const STEAM_MATCH_SOURCES := ["ea", "epic", "pc", "gog", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot"]


## Rückruf absichern. Eine Lambda, die self benutzt (Mitglied, Methode, create_tween …), hält
## einen rohen Zeiger auf ihren Knoten. Wurde der Knoten geschlossen, bevor das Bild kam, griff
## schon cb.is_valid() auf freigegebenen Speicher zu: im Editor eine rote Meldung, in Uzai.exe
## (Release) ein harter Absturz – etwa Guide auf und gleich zu, Spielseite auf und gleich zu.
## Die Hülle merkt sich die Objekt-ID (beim Anmelden lebt der Knoten noch) und ruft nur, solange
## es ihn gibt.
static func guard(cb: Callable) -> Callable:
	if cb.is_null():
		return cb
	var oid := cb.get_object_id()
	return func(v: Variant) -> void:
		if oid != 0 and not is_instance_id_valid(oid):
			return
		if cb.is_valid():
			cb.call(v)


static func _find_in(dir: String, names: Array, depth: int) -> String:
	if depth < 0 or not DirAccess.dir_exists_absolute(dir):
		return ""
	var da := DirAccess.open(dir)
	if da == null:
		return ""
	for n in names:
		if FileAccess.file_exists(dir.path_join(str(n))):
			return dir.path_join(str(n))
	for sub in da.get_directories():
		var found := _find_in(dir.path_join(sub), names, depth - 1)
		if found != "":
			return found
	return ""


const STORE_ASSETS := "https://shared.steamstatic.com/store_item_assets/"
const ASSETS_TTL := 7 * 86400          ## Bilder bekannt: eine Woche
const ASSETS_TTL_NONE := 86400         ## Steam kennt keine Bilder zum Spiel: einen Tag
const ASSET_KEYS := { "cover": ["library_capsule_2x", "library_capsule"], "hero": ["library_hero_2x", "library_hero"],
		"logo": ["library_logo_2x", "library_logo"], "wide": ["header"], "capsule": ["main_capsule"], "icon": ["community_icon"] }


# --- Steam-Store: Bildpfade neuer Spiele ---------------------------------------------------

static func _akey(appid: Variant) -> String:
	return str(Fremd.zahl(appid))       # fehlt die Kennung (null), ist es „0“ statt eines Abbruchs


## Sind gemerkte Angaben frisch genug, um nicht neu zu fragen?
static func assets_fresh(a: Dictionary, now: int) -> bool:
	if a.is_empty():
		return false
	var age := now - int(a.get("_t", 0))
	return age < (ASSETS_TTL if str(a.get("asset_url_format", "")) != "" else ASSETS_TTL_NONE)


## Bildangaben aus einer Antwort von GetItems: appid -> assets.
static func parse_store_assets(data: Variant) -> Dictionary:
	var out := {}
	if not (data is Dictionary) or not (data.get("response") is Dictionary):
		return out
	var items: Variant = data.response.get("store_items", [])
	for it in items if items is Array else []:
		if it is Dictionary and it.get("assets") is Dictionary:
			var id := int(it.get("appid", it.get("id", 0)))
			if id > 0:
				out[str(id)] = it.assets
	return out


## Alle Adressen einer Bildart aus den Store-Angaben, beste zuerst ([] ohne Angaben).
static func asset_urls(a: Dictionary, kind: String, appid: String) -> Array:
	var out: Array = []
	var fmt := str(a.get("asset_url_format", ""))
	if fmt == "":
		return out
	for key in ASSET_KEYS.get(kind, []):
		var file := str(a.get(key, ""))
		if file == "":
			continue
		if key == "community_icon":
			out.append("https://shared.steamstatic.com/community_assets/images/apps/%s/%s.jpg" % [appid, file])
		else:
			out.append(STORE_ASSETS + fmt.replace("${FILENAME}", file))
	return out


static func asset_url_from(a: Dictionary, kind: String, appid: String) -> String:
	var urls := asset_urls(a, kind, appid)
	return str(urls[0]) if not urls.is_empty() else ""


# --- Is an image suitable as a large background (hero)? ----------------------------------------
# A hero fills the full width (1920 × 620 or 3840 × 1240). Smaller images (screenshots from older
# systems, 640 × 480 and below) would have to be upscaled and cropped for that, which makes them blurry,
# zoomed in and shows an arbitrary crop. So only images that are wide enough and already close to that
# shape count as heroes; everything else is shown uncropped by the retro stage (retro_buehne.gd).

const HERO_MIN_BREITE := 1600        ## so breit muss ein Bild mindestens sein
const HERO_SEITEN_MIN := 1.7         ## Breite : Höhe mindestens (16 : 9 und breiter)


static func hero_tauglich(groesse: Vector2i) -> bool:
	if groesse.x < HERO_MIN_BREITE or groesse.y <= 0:
		return false
	return float(groesse.x) / float(groesse.y) >= HERO_SEITEN_MIN


## Aus einer Antwort von SteamGridDB das erste brauchbare Bild (Adresse, "" wenn keins): Heroes nur
## in Hero-Größe; fehlen Breite und Höhe in einem Eintrag, zählt er wie bisher.
static func sgdb_wahl(items: Variant, kind: String) -> String:
	if not (items is Array):
		return ""
	for it in items:
		if not (it is Dictionary) or str(it.get("url", "")) == "":
			continue
		if kind == "hero" and it.has("width") and it.has("height") \
				and not hero_tauglich(Vector2i(int(it.get("width", 0)), int(it.get("height", 0)))):
			continue
		return str(it.url)
	return ""


## Woher ein Bild aus dem Netz kommt, in dieser Reihenfolge. opts: steam, libretro (Einstellungen),
## sgdb (eigener Schlüssel). Getestet in tests/logic_bilder.gd.
static func remote_sources(game: Dictionary, kind: String, opts: Dictionary) -> PackedStringArray:
	var src := str(game.get("source", ""))
	var out := PackedStringArray()
	var steam_kind := STEAM_FILES.has(kind) and bool(opts.get("steam", true))
	if src == "steam" and steam_kind:
		out.append("steam")
	if game.get("art") is Dictionary:
		out.append("art")
	if src in STEAM_MATCH_SOURCES and steam_kind:
		out.append("steam_match")
	if bool(opts.get("sgdb", false)) and not kind in ["wide", "shot", "cover_scan", "ruecken"]:
		out.append("sgdb")
	# ScreenScraper (ohne eigenen Schlüssel): Emulator-Spiele, nach SteamGridDB, vor der Libretro-Sammlung.
	if bool(opts.get("ss", false)) and src in ["rom", "disc"] and kind in ["cover", "hero", "logo", "ruecken"]:
		out.append("ss")
	# iiDB (eigener Schlüssel): Cover, Hintergrund, Schriftzug und Symbol für jedes Spiel.
	if bool(opts.get("iidb", false)) and kind in ["cover", "hero", "logo", "icon"]:
		out.append("iidb")
	# Emulator-Spiele: ein echter Hintergrund auch von Steam, wenn es dort ein Spiel mit genau
	# gleichem Namen gibt (Neuauflage, Sammlung) – nach SteamGridDB, das das Spiel selbst kennt.
	if src in ["rom", "disc"] and kind == "hero" and bool(opts.get("steam", true)):
		out.append("steam_match")
	if src in ["rom", "disc"] and kind in ["cover", "logo", "cover_scan"] and bool(opts.get("libretro", true)):
		out.append("libretro")
	# Scan der Verpackung: nach Libretro auch ScreenScraper (box-2D ist ein Scan).
	if bool(opts.get("ss", false)) and src in ["rom", "disc"] and kind == "cover_scan":
		out.append("ss")
	if src in ["rom", "disc"] and kind == "shot":
		out.append("shot")
	return out


## Vorgabe fürs Scrapen: zuerst ScreenScraper (echte Scans der Verpackung, Schriftzüge, Rücken),
## dann SteamGridDB für das, was dort fehlt.
const SCRAPE_VORGABE := ["ss", "sgdb"]


## Gemerkte Wahl der Quellen fürs Scrapen (library.scrape_quellen) prüfen: "ss", "sgdb" und "iidb",
## jede höchstens einmal, in ihrer Reihenfolge. Sonst die Vorgabe.
static func quellen_pruefen(v: Variant) -> Array:
	if not (v is Array) or (v as Array).is_empty() or (v as Array).size() > 3:
		return SCRAPE_VORGABE.duplicate()
	var out: Array = []
	for q in v:
		if not (q is String) or not q in ["ss", "sgdb", "iidb"] or q in out:
			return SCRAPE_VORGABE.duplicate()
		out.append(q)
	return out


# --- Steam-Bilder für Spiele aus anderen Quellen ------------------------------------------------

## App-ID des Treffers mit genau gleichem Namen (RetroMatch.norm: ohne ™/®, Groß-/Kleinschreibung,
## Satzzeichen, „The“ hinten). 0 wenn keiner passt.
static func steam_title_match(items: Variant, title: String) -> int:
	if not (items is Array):
		return 0
	var want := RetroMatch.norm(title)
	if want == "":
		return 0
	for it in items:
		if it is Dictionary and str(it.get("type", "app")) == "app" and int(it.get("id", 0)) > 0 \
				and RetroMatch.norm(str(it.get("name", ""))) == want:
			return int(it.id)
	return 0


# --- Woher ein Bild kommt (Discord-Status) -----------------------------------------------------

## Steam-App, deren Bilder für den Status taugen: das Spiel selbst oder sein gleichnamiges
## Steam-Spiel (steam_match, nur wenn schon bekannt – der Status fragt nie neu danach).
static func presence_appid(game: Dictionary) -> int:
	if str(game.get("source", "")) == "steam":
		return int(game.get("appid", 0)) if str(game.get("appid", "")).is_valid_int() else 0
	if str(game.get("source", "")) in STEAM_MATCH_SOURCES:
		return maxi(int(game.get("steam_match", 0)), 0)
	return 0


const LIBRETRO_ANY := "https://thumbnails.libretro.com/%s/%s/%s.png"
const RetroMatch := preload("res://src/core/retro_match.gd")
const LIBRETRO_SYSTEMS := {
	"ps2": "Sony - PlayStation 2", "ps1": "Sony - PlayStation", "psp": "Sony - PlayStation Portable",
	"ps3": "Sony - PlayStation 3", "gc": "Nintendo - GameCube", "wii": "Nintendo - Wii",
	"wiiu": "Nintendo - Wii U", "switch": "Nintendo - Switch", "n64": "Nintendo - Nintendo 64",
	"snes": "Nintendo - Super Nintendo Entertainment System", "nes": "Nintendo - Nintendo Entertainment System",
	"gba": "Nintendo - Game Boy Advance", "gb": "Nintendo - Game Boy", "gbc": "Nintendo - Game Boy Color",
	"nds": "Nintendo - Nintendo DS", "3ds": "Nintendo - Nintendo 3DS", "megadrive": "Sega - Mega Drive - Genesis",
	"mastersystem": "Sega - Master System - Mark III", "gamegear": "Sega - Game Gear", "saturn": "Sega - Saturn",
	"dreamcast": "Sega - Dreamcast", "pce": "NEC - PC Engine - TurboGrafx 16", "xbox": "Microsoft - Xbox",
	"xbox360": "Microsoft - Xbox 360", "arcade": "MAME", "atari2600": "Atari - 2600",
}


# --- Cover ohne Schlüssel: Libretro-Vorschaubilder ------------------------------------------

## Libretro ersetzt diese Zeichen in Dateinamen durch "_".
static func libretro_name(s: String) -> String:
	var out := s
	for ch in ["&", "*", "/", ":", "`", "<", ">", "?", "\\", "|", "\""]:
		out = out.replace(ch, "_")
	return out.strip_edges()


static func libretro_urls(game: Dictionary, folder := "Named_Boxarts") -> PackedStringArray:
	var out := PackedStringArray()
	var sys := str(LIBRETRO_SYSTEMS.get(str(game.get("system", "")), ""))
	if sys == "":
		return out
	var names := PackedStringArray()
	var p := str(game.get("path", ""))
	if p != "":
		names.append(p.get_file().get_basename())
	var t := str(game.get("title", ""))
	if t != "" and not names.has(t):
		names.append(t)
	for n in names:
		var u := LIBRETRO_ANY % [sys.uri_encode(), folder, libretro_name(n).uri_encode()]
		if not out.has(u):
			out.append(u)
	return out


static func libretro_candidates(game: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var p := str(game.get("path", ""))
	if p != "":
		out.append(p.get_file().get_basename())
	for t in [str(game.get("title", "")), str(game.get("name", ""))]:
		if t != "" and not out.has(t):
			out.append(t)
	return out


# --- SteamGridDB: alles auf einmal holen -----------------------------------------------------

static func _fit_key(path: String, a: Vector2i) -> String:
	return "%s@%dx%d" % [path, a.x, a.y]


## Bild laden. Godot wählt den Dekoder nach der Endung; ein PNG namens „cover.jpg“ (kommt bei
## heruntergeladenen Bildern vor) ging so nie auf. Dann nach den ersten Bytes entscheiden. PNG, JPG
## und WebP zeigen ihre Größe vor dem Dekodieren (image_dims); zu große fallen weg.
static func load_image(path: String) -> Image:
	if not Sicher.local_path_ok(path) or not FileAccess.file_exists(path):
		return null
	var data := FileAccess.get_file_as_bytes(path)
	var dims := image_dims(data)
	if dims.x > IMG_MAX_SIDE or dims.y > IMG_MAX_SIDE or dims.x * dims.y > IMG_MAX_PIXELS:
		return null
	var img: Image = null
	if dims.x < 0:
		img = Image.load_from_file(path)
		if img and not img.is_empty():
			return img
	if data.size() < 12:
		return null
	img = Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		err = img.load_png_from_buffer(data)
	elif data[0] == 0xFF and data[1] == 0xD8:
		err = img.load_jpg_from_buffer(data)
	elif data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(data)
	elif data[0] == 0x42 and data[1] == 0x4D:
		err = img.load_bmp_from_buffer(data)
	return img if err == OK and not img.is_empty() and img.get_width() <= IMG_MAX_SIDE and img.get_height() <= IMG_MAX_SIDE else null


## Breite und Höhe aus dem Kopf (PNG, JPG, WebP, BMP – nach den ersten Bytes, nicht nach der
## Endung). Vector2i(-1, -1) bei anderen Formaten; ein Kopf mit unsinniger Größe gilt als riesig.
static func image_dims(b: PackedByteArray) -> Vector2i:
	if b.size() < 26:
		return Vector2i(-1, -1)
	var ext := ""
	if b[0] == 0x89 and b[1] == 0x50:
		ext = "png"
	elif b[0] == 0xFF and b[1] == 0xD8:
		ext = "jpg"
	elif b[0] == 0x52 and b[1] == 0x49 and b[2] == 0x46 and b[3] == 0x46:
		ext = "webp"
	elif b[0] == 0x42 and b[1] == 0x4D:
		return Vector2i(absi(b.decode_s32(18)), absi(b.decode_s32(22)))
	else:
		return Vector2i(-1, -1)
	var sz := kopf_groesse(b, ext)
	return sz if sz.x > 0 and sz.y > 0 else Vector2i(1 << 30, 1 << 30)


## Breite und Höhe eines Bilds aus seinen Kopfdaten, ohne es zu dekodieren – für genau dieses Format
## (ext: png, jpg, jpeg oder webp). Vector2i(-1, -1), wenn der Kopf nicht dazu passt.
static func kopf_groesse(b: PackedByteArray, ext: String) -> Vector2i:
	var n := b.size()
	match ext:
		"png":
			if n >= 24 and b.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) and b.slice(12, 16).get_string_from_ascii() == "IHDR":
				return Vector2i(_be32(b, 16), _be32(b, 20))
		"jpg", "jpeg":
			if n >= 4 and b[0] == 0xff and b[1] == 0xd8:
				var i := 2
				var guard := 0
				while i + 9 < n and guard < 400:
					guard += 1
					if b[i] != 0xff:
						return Vector2i(-1, -1)
					var m := b[i + 1]
					if m == 0xff:
						i += 1
						continue
					if m >= 0xc0 and m <= 0xcf and m != 0xc4 and m != 0xc8 and m != 0xcc:
						return Vector2i((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6])
					if m == 0xd8 or (m >= 0xd0 and m <= 0xd7) or m == 0x01:
						i += 2
						continue
					i += 2 + ((b[i + 2] << 8) | b[i + 3])
		"webp":
			if n >= 30 and b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP":
				var tag := b.slice(12, 16).get_string_from_ascii()
				if tag == "VP8 " and b[23] == 0x9d and b[24] == 0x01 and b[25] == 0x2a:
					return Vector2i(b.decode_u16(26) & 0x3fff, b.decode_u16(28) & 0x3fff)
				if tag == "VP8L" and b[20] == 0x2f:
					var v := b.decode_u32(21)
					return Vector2i((v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1)
				if tag == "VP8X":
					return Vector2i((b[24] | (b[25] << 8) | (b[26] << 16)) + 1, (b[27] | (b[28] << 8) | (b[29] << 16)) + 1)
	return Vector2i(-1, -1)


static func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


## Auf höchstens max_w Punkte Breite verkleinern. Erst halbieren, solange es geht (shrink_x2
## mittelt je 2 × 2 Punkte: schnell und ohne Treppen), den Rest kubisch – bei großen Bildern
## bilinear: kubisch kostete einen Hero (3840 → 1920) gut 100 ms im Hintergrund-Thread, das Bild
## kam entsprechend später; nach dem Halbieren ist der Rest kleiner als 2 : 1, da sieht bilinear
## gleich aus.
static func shrink_to(img: Image, max_w: int) -> void:
	var ar := float(img.get_height()) / maxf(1.0, float(img.get_width()))
	while img.get_width() >= max_w * 2 and img.get_height() >= 4:
		img.shrink_x2()
	if img.get_width() > max_w:
		var h := maxi(1, int(round(max_w * ar)))
		img.resize(max_w, h, Image.INTERPOLATE_CUBIC if max_w * h <= 600000 else Image.INTERPOLATE_BILINEAR)


## Wie STRETCH_KEEP_ASPECT_COVERED: der Ausschnitt mit dem Seitenverhältnis der Fläche, höchstens
## so groß wie die Fläche (kleinere Bilder bleiben in ihrer Größe, gezeichnet wird dann
## hochgezogen wie bisher). Mit look (Zuschnitt.analyze) dort, wo das Wichtige ist, sonst mittig.
static func cover_image(img: Image, area: Vector2i, look := {}) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var s := maxf(float(area.x) / w, float(area.y) / h)
	var cw := clampi(int(round(area.x / s)), 1, w)
	var ch := clampi(int(round(area.y / s)), 1, h)
	var out := img
	if cw < w or ch < h:
		var r := Zuschnitt.window(look, Vector2(w, h), Vector2(cw, ch))
		out = img.get_region(Rect2i(clampi(int(round(r.position.x)), 0, w - cw), clampi(int(round(r.position.y)), 0, h - ch), cw, ch))
	if s < 1.0:
		shrink_to(out, mini(area.x, cw))
	return out


# --- Weichgezeichnet, ohne Rücklesen -----------------------------------------------------------

## Bild mit Kastenfilter klein rechnen (shrink_x2 mittelt je 2×2 Punkte – kein Flimmern, keine
## Treppen), auf etwa 2 × steps Punkte Breite. Der BLUR-Shader (radius = Background.soft_radius)
## streut dann 12 Proben über gut einen Punkt davon; das Ergebnis ist glatt. Läuft auch im
## Hintergrund-Thread.
static func soft_image(src: Image, steps: int) -> Image:
	if src == null or src.is_empty():
		return null
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var target := steps * 2
	var ar := float(img.get_height()) / maxf(1.0, float(img.get_width()))
	while img.get_width() >= target * 2 and img.get_height() >= 4:
		img.shrink_x2()
	if img.get_width() > target:
		img.resize(target, maxi(2, int(round(target * ar))), Image.INTERPOLATE_BILINEAR)
	return img


# --- Zuschnitt und Farbe je Bild (Zuschnitt.gd) -------------------------------------------------

## Analyse eines Bilds: Profile und Helligkeit aus einer kleinen Fassung, dazu die Akzentfarbe.
static func look_of(img: Image) -> Dictionary:
	var small := Zuschnitt.small_of(img, Zuschnitt.SIDE_LEICHT if Leicht.active else Zuschnitt.SIDE)
	var look := Zuschnitt.analyze(small)
	if look.is_empty():
		return {}
	var c: Variant = vivid_color(small)
	look["c"] = Zuschnitt.accent(c) if c is Color else null
	return look


static func look_encode(look: Dictionary, mtime: int) -> Array:
	var c: Variant = look.get("c")
	return [mtime, _prof_hex(look.x), _prof_hex(look.y), int(round(float(look.l) * 1000.0)), (c as Color).to_html(false) if c is Color else ""]


static func _prof_hex(p: PackedFloat32Array) -> String:
	var mx := 0.000001
	for v in p:
		mx = maxf(mx, v)
	var b := PackedByteArray()
	b.resize(p.size())
	for i in p.size():
		b[i] = clampi(int(round(p[i] / mx * 255.0)), 0, 255)
	return b.hex_encode()


## Gespeicherten Eintrag prüfen und lesen (die Datei kann kaputt oder verändert sein): {} wenn
## etwas nicht stimmt.
static func look_decode(e: Variant) -> Dictionary:
	if not (e is Array) or (e as Array).size() != 5:
		return {}
	var a: Array = e
	if not (a[1] is String and a[2] is String and a[4] is String) or not (a[0] is float or a[0] is int) or not (a[3] is float or a[3] is int):
		return {}
	var x := _hex_prof(a[1])
	var y := _hex_prof(a[2])
	if x.is_empty() or y.is_empty():
		return {}
	var c: Variant = null
	var cs: String = a[4]
	if cs != "":
		if cs.length() != 6 or not cs.is_valid_hex_number():
			return {}
		c = Color.html(cs)
	return { "x": x, "y": y, "l": clampf(float(a[3]) / 1000.0, 0.0, 1.0), "c": c }


static func _hex_prof(h: String) -> PackedFloat32Array:
	if h.length() != Zuschnitt.BINS * 2 or not h.is_valid_hex_number():
		return PackedFloat32Array()
	var b := h.hex_decode()
	var out := PackedFloat32Array()
	out.resize(Zuschnitt.BINS)
	var s := 0.0
	for i in Zuschnitt.BINS:
		out[i] = b[i]
		s += b[i]
	for i in Zuschnitt.BINS:
		out[i] = out[i] / s if s > 0.0 else 1.0 / Zuschnitt.BINS
	return out


# --- Spielfarbe ------------------------------------------------------------------------------

## Farbe einer Textur (wie vivid_color). Bilder aus Media bringen sie schon mit (im
## Hintergrund-Thread gerechnet); nur sonst wird die Textur dafür zurückgelesen.
static func color_of(t: Texture2D) -> Variant:
	if t == null:
		return null
	if t.has_meta("uz_vivid"):
		var v: Array = t.get_meta("uz_vivid")
		return v[0] if not v.is_empty() else null
	# Ohne mitgegebene Farbe: kleine, selbst erzeugte Bilder (Farbfelder) dürfen zurückgelesen
	# werden; große nie – das Rücklesen hält in Uzai.exe das Bild an (Ruckler beim Blättern).
	if t.get_width() * t.get_height() > 64 * 64:
		return null
	return vivid_color(t.get_image())


## Die Farbe, die ein Bild prägt: Farbtöne in 12 Fächer, gewichtet nach Sättigung und Helligkeit.
## Grau, Schwarz und Weiß zählen kaum. null, wenn das Bild keine kräftige Farbe hat.
static func vivid_color(img: Image) -> Variant:
	if img == null or img.is_empty():
		return null
	var im := img.duplicate() as Image
	if im.is_compressed():
		if im.decompress() != OK:
			return null
	im.convert(Image.FORMAT_RGBA8)
	im.resize(24, 24, Image.INTERPOLATE_BILINEAR)
	var w := []
	var sums := []
	for i in 12:
		w.append(0.0)
		sums.append(Color(0, 0, 0, 0))
	for y in 24:
		for x in 24:
			var c := im.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var weight := c.s * c.s * c.v
			if c.s < 0.2 or c.v < 0.18:
				weight *= 0.05
			var bin := int(c.h * 12.0) % 12
			w[bin] += weight
			sums[bin] += Color(c.r * weight, c.g * weight, c.b * weight, 0)
	var best := 0
	for i in 12:
		if w[i] > w[best]:
			best = i
	if w[best] < 1.2:
		return null
	var s: Color = sums[best]
	return Color(s.r / w[best], s.g / w[best], s.b / w[best])


static func safe_name(s: String) -> String:
	var out := s
	for ch in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]:
		out = out.replace(ch, "")
	return out.strip_edges()
