extends RefCounted
## Gemeinsame Bausteine für den Bereich Filme: Bilder laden (in 4K-passender Größe), ruhige
## Farbfelder, solange es kein Bild gibt, und die kurzen Texte (Laufzeit, Restzeit, Qualität,
## Folge). Alles ohne Zustand, damit es überall gleich aussieht und sich prüfen lässt.

const U := preload("res://src/ui/u.gd")
const Lang := preload("res://src/core/lang.gd")
const Q := preload("res://src/core/movies_quelle.gd")
const MoviesDaten := preload("res://src/core/movies_daten.gd")

const SEP := "  ·  "
const LANG_CHIPS := 4             ## so viele Sprach-Chips je Quelle, der Rest als „+n“
## Sprachen zu den Kürzeln der Chips (movies_quelle.gd).
const LANG_NAMES := {
	"de": "Deutsch", "en": "Englisch", "fr": "Französisch", "es": "Spanisch", "it": "Italienisch", "pt": "Portugiesisch",
	"ru": "Russisch", "uk": "Ukrainisch", "pl": "Polnisch", "nl": "Niederländisch", "tr": "Türkisch", "ja": "Japanisch",
	"ko": "Koreanisch", "zh": "Chinesisch", "hi": "Hindi", "ar": "Arabisch", "sv": "Schwedisch", "da": "Dänisch", "no": "Norwegisch",
	"fi": "Finnisch", "cs": "Tschechisch", "sk": "Slowakisch", "hu": "Ungarisch", "el": "Griechisch", "he": "Hebräisch",
	"ro": "Rumänisch", "hr": "Kroatisch", "sr": "Serbisch", "bg": "Bulgarisch", "th": "Thailändisch", "vi": "Vietnamesisch",
	"id": "Indonesisch", "fa": "Persisch", "sl": "Slowenisch", "lt": "Litauisch", "lv": "Lettisch", "et": "Estnisch",
	"ms": "Malaiisch", "ta": "Tamil", "te": "Telugu",
}


# --- Bilder ------------------------------------------------------------------------------------

## Bild aus Adresse oder Datei laden, max_w in 1080p-Pixeln (Media rechnet für 4K hoch).
## Leere Adresse: cb(null) sofort.
static func load_image(url: String, max_w: int, cb: Callable) -> void:
	if url == "":
		if cb.is_valid():
			cb.call(null)
		return
	Media.url_texture(url, max_w, cb)


## Hintergrundbild eines Titels (für Kopf, Detailseite, breite Karten).
static func backdrop_url(item: Dictionary) -> String:
	var b := str(item.get("background", ""))
	return b if b != "" else str(item.get("thumbnail", ""))


static var _cache := {}


## Farbton, der zu einem Titel gehört: jeder Film behält seine Farbe, wie Kanäle bei Videos.
## (Über MD5 gestreut: IDs wie tt8000001, tt8000002 liegen sonst alle im selben Farbton.)
static func hue_of(seed: String) -> float:
	return float(seed.md5_text().substr(0, 6).hex_to_int() % 360) / 360.0


## Ruhiges Farbfeld im Hochformat (Plakat ohne Bild): oben Licht, unten tief.
static func poster_tex(seed: String) -> Texture2D:
	return _field(seed, 40, 60, "p")


## Breites Farbfeld (Hintergrund ohne Bild): Licht oben rechts, nach links und unten tiefer.
static func backdrop_tex(seed: String) -> Texture2D:
	return _field(seed, 96, 54, "b")


static func _field(seed: String, w: int, h: int, kind: String) -> Texture2D:
	var bucket := int(round(hue_of(seed) * 36.0)) % 36
	var key := "%s%d" % [kind, bucket]
	if _cache.has(key):
		return _cache[key]
	var hue := float(bucket) / 36.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top := Color.from_hsv(hue, 0.42, 0.42)
	var low := Color.from_hsv(fposmod(hue + 0.05, 1.0), 0.55, 0.10)
	var glow := Color.from_hsv(fposmod(hue - 0.03, 1.0), 0.32, 0.72)
	var light := Vector2(0.72, 0.22) if kind == "b" else Vector2(0.3, 0.16)
	for y in h:
		for x in w:
			var u := float(x) / float(w - 1)
			var v := float(y) / float(h - 1)
			var c := top.lerp(low, clampf(v * 0.85 + (1.0 - u) * 0.25 if kind == "b" else v * 0.9 + u * 0.15, 0.0, 1.0))
			var d := Vector2((u - light.x) * (1.3 if kind == "b" else 1.6), v - light.y).length()
			var g := clampf(1.0 - d / 0.85, 0.0, 1.0)
			c = c.lerp(glow, g * g * 0.5)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# --- Texte ---------------------------------------------------------------------------------

## Mehrzeilige Beschriftung mit „…“ am Ende: Godot meldet dafür nur eine Höhe von 1 Pixel. Hier
## wird die Höhe der wirklich gebrauchten Zeilen (höchstens max_lines) fest eingetragen.
static func fit_lines(l: Label, width: float, max_lines: int) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = max_lines
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var lh := f.get_height(fs)
	var txt: String = l.text if l.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else TranslationServer.translate(l.text)
	var sz := f.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, width, fs, max_lines)
	var lines := clampi(int(round(sz.y / maxf(1.0, lh))), 1, max_lines)
	l.custom_minimum_size = Vector2(width, ceilf(lh * lines + float(l.get_theme_constant("line_spacing")) * (lines - 1)))
	return l


static func type_label(type: String) -> String:
	return "Serie" if type == "series" else "Film"


## Laufzeit lesbar: „128“, „128 min“, „2h 8min“ → „2 Std. 8 Min.“; unbekannt → "".
static func runtime_text(rt: Variant) -> String:
	var s := str(rt).strip_edges().to_lower()
	if s == "" or s == "0":
		return ""
	var mins := 0
	if s.contains("h"):
		var h := s.get_slice("h", 0).strip_edges().to_int()
		var rest := s.get_slice("h", 1)
		mins = h * 60 + rest.to_int()
	else:
		mins = s.to_int()
	if mins <= 0:
		return ""
	if mins < 60:
		return "%d Min." % mins
	var m := mins % 60
	return "%d Std." % floori(mins / 60.0) + (" %d Min." % m if m > 0 else "")


## Zeit wie im Player: 37:12 oder 1:04:09.
static func clock(sec: float) -> String:
	var s := maxi(0, int(sec))
	if s >= 3600:
		return "%d:%02d:%02d" % [floori(s / 3600.0), floori(s / 60.0) % 60, s % 60]
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## Restzeit kurz: „noch 52 Min.“, „noch 1 Std. 12 Min.“ (übersetzt: die Zeilen zeigen Titel unübersetzt)
static func left_text(pos: float, dur: float) -> String:
	var sec := int(maxf(0.0, dur - pos))
	if dur <= 0.0:
		return ""
	if sec >= 3600:
		var m := floori(sec / 60.0) % 60
		return (TranslationServer.translate("noch %d Std. %d Min.") % [floori(sec / 3600.0), m]) if m > 0 \
				else TranslationServer.translate("noch %d Std.") % floori(sec / 3600.0)
	return TranslationServer.translate("noch %d Min.") % maxi(1, int(ceil(sec / 60.0)))


## Anteil gesehen (0…1), 0 ohne Dauer.
static func frac(pos: float, dur: float) -> float:
	return clampf(pos / dur, 0.0, 1.0) if dur > 0.0 else 0.0


## Lohnt sich „Fortsetzen“? Erst nach einer halben Minute und nicht kurz vor Schluss.
static func can_resume(pos: float, dur: float) -> bool:
	return pos >= 30.0 and (dur <= 0.0 or pos < dur * 0.92)


## Folge kurz („S1 F3“) bzw. lang („Staffel 1 · Folge 3“). Staffel 0 sind die Extras.
static func episode_code(season: int, episode: int, long := false) -> String:
	if long:
		return ("Extras" if season == 0 else "Staffel %d" % season) + SEP + "Folge %d" % episode
	return ("Extra" if season == 0 else "S%d" % season) + " F%d" % episode


static func season_name(season: int) -> String:
	return "Extras" if season == 0 else "Staffel %d" % season


## Bewertung mit Komma („7,8“), leer, wenn es keine gibt.
static func rating_text(r: Variant) -> String:
	var s := str(r).strip_edges()
	if s == "" or s == "0" or s == "0.0" or not s.is_valid_float():
		return ""
	return Lang.dec("%.1f" % s.to_float())


## Die Zeile unter dem Titel: Art · Genre, Laufzeit, Jahr (die Bewertung steht eigens daneben).
static func meta_line(item: Dictionary, max_genres := 1) -> String:
	var parts := PackedStringArray()
	var lead := type_label(str(item.get("type", "movie")))
	var g: Array = item.get("genres", []) if item.get("genres") is Array else []
	for i in mini(max_genres, g.size()):
		lead += SEP + str(g[i])
	parts.append(lead)
	var rt := runtime_text(item.get("runtime", ""))
	if rt != "":
		parts.append(rt)
	var y := str(item.get("year", "")).strip_edges()
	if y != "":
		parts.append(y)
	# Freigabe vom eigenen Medienserver („FSK 12“, „PG-13“).
	var cr := str(item.get("content_rating", "")).strip_edges()
	if cr != "":
		parts.append(cr)
	return SEP.join(parts)


## Qualität als kurzes Wort.
static func quality_label(q: int) -> String:
	if q >= 2160:
		return "4K"
	if q >= 1440:
		return "1440p"
	if q >= 1080:
		return "1080p"
	if q >= 720:
		return "720p"
	if q > 0:
		return "SD"
	return ""


## Abzeichen einer Quelle: [[Text, Ton]] – Ton "gold" für das, was zählt (4K, HDR, Atmos, REMUX,
## die gewünschte Sprache, sofort da). want_lang: Kürzel der bevorzugten Sprache ("DE"), "" = keine.
static func stream_badges(s: Dictionary, want_lang := "") -> Array:
	var out: Array = []
	var ql := quality_label(int(s.get("quality", 0)))
	if ql != "":
		out.append([ql, "gold" if int(s.get("quality", 0)) >= 2160 else "text"])
	var hdr := str(s.get("hdr", ""))
	if hdr != "":
		out.append(["Dolby Vision" if hdr == "DV" else hdr, "gold"])
	var codec := str(s.get("codec", ""))
	if codec != "":
		out.append([codec, "muted"])
	var audio := str(s.get("audio", ""))
	if audio != "":
		out.append([audio, "gold" if audio.contains("Atmos") or audio.begins_with("DTS:X") else "muted"])
	var rel := str(s.get("release", ""))
	if rel != "":
		out.append([rel, "gold" if rel == "REMUX" else ("warn" if rel == "CAM" else "muted")])
	var size := str(s.get("size_text", ""))
	if size == "" and int(s.get("size_bytes", 0)) > 0:
		size = size_text(int(s.size_bytes))
	if size != "":
		out.append([size, "muted"])
	var langs: Array = s.get("langs", []) if s.get("langs") is Array else []
	for i in mini(langs.size(), LANG_CHIPS):
		out.append([str(langs[i]), "lang_on" if str(langs[i]) == want_lang else "lang"])
	if langs.size() > LANG_CHIPS:
		out.append(["+%d" % (langs.size() - LANG_CHIPS), "lang"])
	if bool(s.get("multi", false)):
		out.append(["Multi", "lang"])
	if bool(s.get("cached", false)):
		out.append(["Sofort bereit", "ok"])
	if bool(s.get("is_p2p", false)):
		out.append(["P2P", "warn"])
	if str(s.get("source", "")) == "plugin":
		out.append(["Plugin", "muted"])
	return out


## Dieselbe Größe wie in der Quellenliste (movies_daten.gd rundet; früher rundete diese Kopie ab – derselbe Film stand
## mit zwei verschiedenen Größen da).
static func size_text(bytes: int) -> String:
	return MoviesDaten.size_text(bytes)


## Name einer Quelle in einer Zeile (Addons schicken oft „Name\n4K“), ohne Emojis.
static func stream_name(s: Dictionary) -> String:
	var n := Q.strip_marks(str(s.get("name", "")).replace("\n", " "))
	return n if n != "" else str(s.get("addon_name", "Quelle"))


## Dateiname einer Quelle (Hinweis des Addons oder Release-Zeile aus dem Text), "" ohne.
static func stream_file(s: Dictionary) -> String:
	return Q.file_of(s)


## Beschreibung einer Quelle aus den Addon-Texten, Zeile für Zeile wie geschickt: Emojis als Wort
## oder Trenner, Flaggen als Kürzel; ohne den Dateinamen und den Namen (stehen schon da) und ohne
## Zeilen, die nur wiederholen, was die Chips zeigen (Größe, Auflösung).
static var _re_known := RegEx.create_from_string(
		"(?i)\\b\\d+(?:[.,]\\d+)?\\s*(?:gb|mb|gib|mib)\\b|\\b(?:2160|1440|1080|720|576|480)p\\b|\\b4k\\b|\\buhd\\b|[|·•:\\-–\\s]+")


static func stream_desc(s: Dictionary) -> String:
	var file := stream_file(s)
	var skip := [file, file.get_basename() if file.get_extension().to_lower() in Q.VIDEO_EXT else file, stream_name(s),
		Q.strip_marks(str(s.get("name", "")).get_slice("\n", 0))]
	var lines := PackedStringArray()
	for k in ["title", "description"]:
		for raw in str(s.get(k, "")).split("\n"):
			if skip.has(Q.strip_marks(str(raw))):
				continue
			var t := Q.pretty(str(raw))
			if t == "" or lines.has(t) or skip.has(t):
				continue
			if _re_known.sub(t, "", true).strip_edges() == "":
				continue
			lines.append(t)
	return "\n".join(lines)


## Quellen filtern: addon "" = alle, min_q 0 = jede Qualität, sonst genau diese Stufe
## (SD = alles unter 720p); lang "" = jede Sprache, "MULTI" = mehrsprachig, sonst das Kürzel.
static func filter_streams(list: Array, addon: String, q: int, lang := "") -> Array:
	var out: Array = []
	for s in list:
		if addon != "" and str(s.get("addon_name", "")) != addon:
			continue
		var sq := int(s.get("quality", 0))
		if q > 0:
			if q == 480 and sq >= 720:
				continue
			if q != 480 and sq != q:
				continue
		if lang != "" and not has_lang(s, lang):
			continue
		out.append(s)
	return out


static func has_lang(s: Dictionary, lang: String) -> bool:
	var langs: Array = s.get("langs", []) if s.get("langs") is Array else []
	if lang == "MULTI":
		return bool(s.get("multi", false)) or langs.size() > 1
	return langs.has(lang)


## Sprachen der Quellen mit Anzahl: [[Kürzel, Anzahl]], die gewünschte zuerst, dann nach Anzahl;
## „MULTI“ am Ende, wenn es mehrsprachige gibt.
static func lang_counts(list: Array, want := "") -> Array:
	var counts := {}
	var multi := 0
	for s in list:
		for l in (s.get("langs", []) if s.get("langs") is Array else []):
			counts[str(l)] = int(counts.get(str(l), 0)) + 1
		if has_lang(s, "MULTI"):
			multi += 1
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		if (a == want) != (b == want):
			return a == want
		if int(counts[a]) != int(counts[b]):
			return int(counts[a]) > int(counts[b])
		return a < b
	)
	var out: Array = keys.map(func(k: String) -> Array: return [k, int(counts[k])])
	if multi > 0:
		out.append(["MULTI", multi])
	return out


## Name einer Sprache zum Kürzel („DE“ → „Deutsch“, „MULTI“ → „Mehrsprachig“); unbekannt das Kürzel.
static func lang_name(code: String) -> String:
	if code == "MULTI":
		return "Mehrsprachig"
	return str(LANG_NAMES.get(code.to_lower(), code))


## Anzahl Quellen je Addon in der Reihenfolge, in der sie zuerst vorkommen.
static func addon_counts(list: Array) -> Array:
	var names: Array = []
	var counts := {}
	for s in list:
		var n := str(s.get("addon_name", ""))
		if not counts.has(n):
			names.append(n)
			counts[n] = 0
		counts[n] = int(counts[n]) + 1
	var out: Array = []
	for n in names:
		out.append([n, int(counts[n])])
	return out


## Welche Quelle zuerst gewählt ist: die erste in der bevorzugten Qualität (oder darunter).
static func preferred_index(list: Array, pref: String) -> int:
	if pref == "" or pref == "auto" or list.is_empty():
		return 0
	var want := pref.to_int()
	for i in list.size():
		if int(list[i].get("quality", 0)) <= want:
			return i
	return 0


## Was „Abspielen“ bei einer Serie meint: die angefangene Folge, sonst die erste ungesehene.
## Gibt { video, resume (bool), label } zurück; ohne Folgen leer.
static func next_up(meta: Dictionary, cw: Array, watched_cb: Callable, progress_cb: Callable) -> Dictionary:
	var mid := str(meta.get("id", ""))
	var vids: Array = meta.get("videos", []) if meta.get("videos") is Array else []
	if str(meta.get("type", "")) != "series" or vids.is_empty():
		var p: Dictionary = progress_cb.call(mid, mid)
		var res := can_resume(float(p.get("position", 0.0)), float(p.get("duration", 0.0)))
		return { "video": {}, "resume": res, "label": "Fortsetzen" if res else "Abspielen" }
	for c in cw:
		if str(c.get("id", "")) == mid:
			for v in vids:
				if str(v.id) == str(c.get("video_id", "")):
					var r := can_resume(float(c.get("position", 0.0)), float(c.get("duration", 0.0)))
					return { "video": v, "resume": r, "label": ("%s fortsetzen" if r else "%s abspielen") % episode_code(int(v.season), int(v.episode)) }
	# Erste ungesehene Folge (Extras zuletzt), die es schon gibt.
	var ordered := vids.filter(func(v: Dictionary) -> bool: return int(v.get("season", 0)) > 0)
	ordered.append_array(vids.filter(func(v: Dictionary) -> bool: return int(v.get("season", 0)) == 0))
	var first: Dictionary = {}
	for v in ordered:
		if not bool(v.get("available", true)):
			continue
		if first.is_empty():
			first = v
		if not bool(watched_cb.call(mid, str(v.id))):
			return { "video": v, "resume": false, "label": "%s abspielen" % episode_code(int(v.season), int(v.episode)) }
	if first.is_empty():
		return {}
	return { "video": first, "resume": false, "label": "%s abspielen" % episode_code(int(first.season), int(first.episode)) }


## Staffeln in der Anzeige-Reihenfolge: 1, 2, … und die Extras (0) am Ende.
static func season_order(meta: Dictionary) -> Array:
	var seasons: Array = []
	var src: Array = meta.get("seasons", []) if meta.get("seasons") is Array else []
	for s in src:
		if not seasons.has(int(s)):
			seasons.append(int(s))
	if seasons.is_empty():
		for v in (meta.get("videos", []) if meta.get("videos") is Array else []):
			if not seasons.has(int(v.get("season", 0))):
				seasons.append(int(v.get("season", 0)))
	seasons.sort()
	if seasons.has(0):
		seasons.erase(0)
		seasons.append(0)
	return seasons


## Ähnliche Titel aus den Reihen der Startseite: gleiche Art, mindestens ein gleiches Genre.
static func similar(meta: Dictionary, rows: Array, limit := 15) -> Array:
	var mid := str(meta.get("id", ""))
	var genres: Array = meta.get("genres", []) if meta.get("genres") is Array else []
	var seen := { mid: true }
	var out: Array = []
	for r in rows:
		for it in r.get("items", []):
			var iid := str(it.get("id", ""))
			if seen.has(iid) or str(it.get("type", "")) != str(meta.get("type", "")):
				continue
			var share := false
			for g in it.get("genres", []):
				if genres.has(g):
					share = true
			if share:
				seen[iid] = true
				out.append(it)
				if out.size() >= limit:
					return out
	return out


## Initialen für runde Bilder ohne Foto (Besetzung).
static func initials(name_: String) -> String:
	var parts := name_.strip_edges().split(" ", false)
	if parts.is_empty():
		return "?"
	var s := parts[0].substr(0, 1)
	if parts.size() > 1:
		s += parts[parts.size() - 1].substr(0, 1)
	return s.to_upper()


# --- Eigene Symbole ----------------------------------------------------------------------------

## Was Icons nicht kennt (Pfeile zum Verschieben, Baustein für Addons), im selben Strich.
const ICONS := {
	"arrow_up": '<path d="M12 19V5.5M6 11l6-6 6 6"/>',
	"arrow_down": '<path d="M12 5v13.5M6 13l6 6 6-6"/>',
	"puzzle": '<path d="M5 8.5h3.2a2.3 2.3 0 1 1 4.6 0H16v3.2a2.3 2.3 0 1 1 0 4.6V19.5H5v-3.4a2.3 2.3 0 1 0 0-4.6Z"/>',
}

static var _icons := {}


static func icon_tex(name: String, px := 24) -> Texture2D:
	if not ICONS.has(name):
		return Icons.tex(name, px)
	var key := "%s@%d" % [name, px]
	if _icons.has(key):
		return _icons[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="square" stroke-linejoin="miter">%s</svg>' % ICONS[name]
	var img := Image.new()
	if img.load_svg_from_string(svg, float(px) / 24.0 * 2.0) != OK:
		img = Image.create(px, px, false, Image.FORMAT_RGBA8)
	var t := ImageTexture.create_from_image(img)
	_icons[key] = t
	return t


## Runder Symbolknopf (wie U.button "icon"), auch mit eigenen Symbolen.
static func icon_button(name: String) -> Button:
	var b := U.button("", "", "icon")
	b.icon = icon_tex(name, 26)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 26)
	# Ausgegraut gleich breit wie die anderen (sonst verrutschen die Knöpfe einer Zeile).
	b.add_theme_stylebox_override("disabled", UzTheme.box(UzTheme.col("glass"), 27))
	b.add_theme_color_override("icon_disabled_color", UzTheme.col("faint", 0.6))
	return b
