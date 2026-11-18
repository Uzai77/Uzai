extends RefCounted
## Inhalte für die Szenen der Einrichtung (einrichtung_szene.gd), damit sie nicht leer wirken:
## wo es geht, echte Inhalte des Nutzers – Cover seiner Spiele, das Albumcover, das er zuletzt
## gehört hat, ein Filmposter aus seiner Filmbibliothek, sein neuestes Bildschirmfoto, das große Bild
## eines Spiels als laufender Stream –, sonst eigene, hier gezeichnete Bilder (keine Fotos, nichts
## Fremdes). System- und Emulator-Logos kommen nur zur Laufzeit über badge_logos.gd (R4); ohne Logo
## steht eine eigene Konsolen-Silhouette bzw. ein Zeichen aus den Anfangsbuchstaben da.
## Alles wird im Hintergrund geladen; was ankommt, zeichnet die Szene neu (anfordern).

const BadgeLogos := preload("res://src/core/badge_logos.gd")
const RS := preload("res://src/core/retro_systeme.gd")

## Systeme, wenn die Bibliothek noch kaum Emulator-Spiele hat (die bekanntesten, je ein Emulator).
const STANDARD := ["ps2", "gc", "ps1", "n64", "snes", "gba"]
const MAX_SYSTEME := 6
## Form der Silhouette: Disc-Konsole, Modul-Konsole oder Handheld (sonst Modul).
const DISC := ["ps1", "ps2", "ps3", "gc", "wii", "wiiu", "saturn", "dreamcast", "xbox", "xbox360"]
const HAND := ["gb", "gbc", "gba", "nds", "3ds", "psp", "vita", "gamegear", "switch"]
## Arten der Medien-Kacheln: woher ein echtes Bild kommen kann (sonst eigenes Bild).
const ARTEN := ["musik", "videos", "filme", "live", "aufnahmen", "apps"]
const BILD_ENDUNGEN := ["png", "jpg", "jpeg", "webp"]
const MAX_DATEIEN := 400
## Schauen & Hören: so viele echte Einträge je Station.
const SCHAUEN_MAX := 6

static var _bilder := {}            ## Schlüssel -> Texture2D (bleibt für die Sitzung)
static var _geladen := {}           ## Schlüssel -> true (schon angefragt)
static var _hoerer: Array = []      ## WeakRefs auf Szenen, die neu zeichnen wollen


static func _knoten(name: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null(name)
	return null


## Ein geladenes Bild oder null.
static func bild(key: String) -> Texture2D:
	return _bilder.get(key) as Texture2D


## Szene meldet sich: lädt (einmal) die echten Inhalte und zeichnet sie neu, sobald etwas ankommt.
static func anfordern(ci: CanvasItem, emus: Array = []) -> void:
	_hoerer = _hoerer.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	_hoerer.append(weakref(ci))
	var lib := _knoten("Library")
	var media := _knoten("Media")
	if lib == null or media == null:
		return
	var spiele: Array = (lib.get("games") as Array).filter(func(g: Variant) -> bool: return g is Dictionary and not bool(g.get("hidden", false)))
	spiele.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("last_played", 0)) > int(b.get("last_played", 0)))
	# Cover je erkanntem System (bis zu drei, die zuletzt gespielten zuerst).
	for e in emus:
		var sys := str((e as Dictionary).sys)
		var k := 0
		for g in spiele:
			if k >= 3:
				break
			if str(g.get("system", "")) == sys:
				_holen(media, "cover:%s:%d" % [sys, k], g, "cover")
				k += 1
	# Live: das große Bild des zuletzt gespielten Spiels mit Hintergrund (Steam & Co.).
	for g in spiele:
		if str(g.get("source", "")) in ["steam", "epic", "ea", "gog"]:
			_holen(media, "live", g, "hero")
			break
	_aufnahme(media)
	_musik(media)
	_film(media)


static func _holen(media: Node, key: String, g: Dictionary, art: String) -> void:
	if _geladen.has(key):
		return
	_geladen[key] = true
	media.call("game_texture", g, art, func(tex: Variant) -> void: _setzen(key, tex))


static func _setzen(key: String, tex: Variant) -> void:
	if not (tex is Texture2D):
		_geladen.erase(key)
		return
	_bilder[key] = tex
	for w in _hoerer:
		var ci := (w as WeakRef).get_ref() as CanvasItem
		if is_instance_valid(ci):
			ci.queue_redraw()


## Das neueste eigene Bildschirmfoto (Ordner der Aufnahmen, nur lesen).
static func _aufnahme(media: Node) -> void:
	var cap := _knoten("Capture")
	if cap == null or _geladen.has("aufnahmen") or not cap.has_method("shots_dir"):
		return
	var dir := str(cap.call("shots_dir"))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var best := ""
	var best_t := 0
	var n := 0
	for f in DirAccess.get_files_at(dir):
		n += 1
		if n > MAX_DATEIEN:
			break
		if not (f.get_extension().to_lower() in BILD_ENDUNGEN):
			continue
		var p := dir.path_join(f)
		var mt := int(FileAccess.get_modified_time(p))
		if mt > best_t:
			best_t = mt
			best = p
	if best != "":
		_geladen["aufnahmen"] = true
		media.call("file_texture", best, 640, func(tex: Variant) -> void: _setzen("aufnahmen", tex))


## Das Albumcover, das gerade läuft oder zuletzt lief (nicht in der Demo).
static func _musik(media: Node) -> void:
	var mu := _knoten("Music")
	if mu == null or _geladen.has("musik") or bool(mu.call("demo")):
		return
	var urls: Array = []
	var now: Variant = mu.get("now")
	if now is Dictionary:
		urls.append(str((now as Dictionary).get("art", "")))
	for e in (mu.get("recent_list") as Array).slice(0, 6):
		if e is Dictionary:
			urls.append(str(e.get("art", "")))
	for u in urls:
		if str(u).begins_with("https://"):
			_geladen["musik"] = true
			media.call("url_texture", str(u), 360, func(tex: Variant) -> void: _setzen("musik", tex))
			return


## Ein Poster aus der eigenen Filmbibliothek (nicht in der Demo).
static func _film(media: Node) -> void:
	var mo := _knoten("Movies")
	if mo == null or _geladen.has("filme") or bool(mo.get("demo")) or not mo.has_method("library_items"):
		return
	for e in (mo.call("library_items") as Array).slice(0, 12):
		if e is Dictionary and str(e.get("poster", "")).begins_with("https://"):
			_geladen["filme"] = true
			media.call("url_texture", str(e.poster), 360, func(tex: Variant) -> void: _setzen("filme", tex))
			return


## Schauen & Hören (Szene „schauen“): was es auf diesem PC wirklich gibt – je Station höchstens
## SCHAUEN_MAX Einträge { key, titel, zeile, quelle (Pfad oder https-Adresse), anteil (gesehen
## 0 … 1), dauer (s), zahl (Zuschauer) }; das Bild liegt nach dem Laden unter key (anfordern_schauen).
## Musik: die eigenen Alben aus dem Musikordner (mit Cover), sonst zuletzt gehört; Videos: zuletzt
## gesehen, dann die Abos; Filme: Weiterschauen, dann die Bibliothek („bild“: das große Bild des
## ersten); Live: gefolgte Kanäle, die gerade senden. In der Vorführung nichts – die Szene malt dann
## eigene Bilder (landschaft).
static func schauen() -> Dictionary:
	var out := { "musik": [], "videos": [], "filme": [], "live": [], "bild": "" }
	var mu := _knoten("Music")
	if mu and not bool(mu.call("demo")):
		var loc: Variant = mu.get("local")
		if loc is Node and is_instance_valid(loc):
			for al in (loc.get("albums") as Array):
				if al is Dictionary and str(al.get("art", "")) != "" and (out.musik as Array).size() < SCHAUEN_MAX:
					(out.musik as Array).append(_eintrag(str(al.art), str(al.get("name", "")), str(al.get("artist", ""))))
		if (out.musik as Array).is_empty():
			var liste: Array = []
			if mu.get("now") is Dictionary:
				liste.append(mu.get("now"))
			liste.append_array((mu.get("recent_list") as Array).slice(0, 40))
			var alben := {}
			for e in liste:
				if not (e is Dictionary) or (out.musik as Array).size() >= SCHAUEN_MAX:
					continue
				var art := str(e.get("art", ""))
				var alb := str(e.get("album", ""))
				if art.begins_with("https://") and not alben.has(alb):
					alben[alb] = true
					(out.musik as Array).append(_eintrag(art, str(e.get("title", "")), str(e.get("artist", ""))))
	var yt := _knoten("YouTube")
	if yt and not bool(yt.get("demo")):
		var gesehen := {}
		for e in ((yt.get("data") as Dictionary).get("history", []) as Array) + (yt.get("feed") as Array):
			if not (e is Dictionary) or (out.videos as Array).size() >= SCHAUEN_MAX:
				continue
			var th := str(e.get("thumb", ""))
			if th.begins_with("https://") and not gesehen.has(th) and not bool(e.get("short", false)):
				gesehen[th] = true
				var v := _eintrag(th, str(e.get("title", "")), str(e.get("channel", "")))
				v["dauer"] = float(e.get("duration", 0))
				(out.videos as Array).append(v)
	var mo := _knoten("Movies")
	if mo and not bool(mo.get("demo")) and mo.has_method("continue_watching"):
		var gesehen2 := {}
		for e in (mo.call("continue_watching") as Array) + (mo.call("library_items") as Array):
			if not (e is Dictionary) or (out.filme as Array).size() >= SCHAUEN_MAX:
				continue
			var po := str(e.get("poster", ""))
			if po.begins_with("https://") and not gesehen2.has(po):
				gesehen2[po] = true
				var f := _eintrag(po, str(e.get("name", "")), str(e.get("episode_title", "")))
				var dur := float(e.get("duration", 0))
				f["anteil"] = clampf(float(e.get("position", 0)) / dur, 0.0, 1.0) if dur > 0.0 else 0.0
				(out.filme as Array).append(f)
				var bg := str(e.get("background", ""))
				if out.bild == "" and bg.begins_with("https://"):
					out.bild = bg
	var tw := _knoten("Twitch")
	if tw and not bool(tw.get("demo")):
		for e in (tw.get("followed") as Array):
			if e is Dictionary and bool(e.get("live", false)) and str(e.get("thumb", "")).begins_with("https://") and (out.live as Array).size() < SCHAUEN_MAX:
				var l := _eintrag(str(e.thumb), str(e.get("channel", "")), str(e.get("title", "")))
				l["zahl"] = int(((e.get("twitch", {}) as Dictionary) if e.get("twitch") is Dictionary else {}).get("viewers", 0))
				(out.live as Array).append(l)
	return out


static func _eintrag(quelle: String, titel: String, zeile: String) -> Dictionary:
	return { "key": "s:" + quelle, "quelle": quelle, "titel": titel.substr(0, 120), "zeile": zeile.substr(0, 120), "anteil": 0.0, "dauer": 0.0, "zahl": 0 }


## Die Bilder zu schauen() im Hintergrund laden (je Quelle einmal); was ankommt, zeichnet ci neu.
static func anfordern_schauen(ci: CanvasItem, sch: Dictionary) -> void:
	_hoerer = _hoerer.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	_hoerer.append(weakref(ci))
	var media := _knoten("Media")
	if media == null:
		return
	var alle: Array = []
	for k in ["musik", "videos", "filme", "live"]:
		alle.append_array(sch.get(k, []) as Array)
	if str(sch.get("bild", "")) != "":
		alle.append(_eintrag(str(sch.bild), "", ""))
	for e in alle:
		var key := str(e.key)
		var q := str(e.quelle)
		if _geladen.has(key) or q == "":
			continue
		_geladen[key] = true
		if q.begins_with("https://"):
			media.call("url_texture", q, 640, func(tex: Variant) -> void: _setzen(key, tex))
		elif FileAccess.file_exists(q):
			media.call("file_texture", q, 480, func(tex: Variant) -> void: _setzen(key, tex))


## Was die Szene Emulatoren zeigt: die Systeme der eigenen Sammlung (die meisten Spiele zuerst),
## je mit dem Emulator, der eingerichtet ist oder empfohlen wird. Fehlen eigene, ergänzen die
## bekanntesten. [{ sys, kurz, name, farbe, emu, emu_name, spiele, eigen }]
static func emu_liste() -> Array:
	var cfg := _knoten("Config")
	var lib := _knoten("Library")
	var zahl := {}
	if lib:
		for g in lib.get("games"):
			if g is Dictionary and RS.is_retro_game(g):
				var s := str(g.get("system", ""))
				zahl[s] = int(zahl.get(s, 0)) + 1
	var syss: Array = zahl.keys()
	syss.sort_custom(func(a: String, b: String) -> bool: return int(zahl[a]) > int(zahl[b]) or (zahl[a] == zahl[b] and a < b))
	for s in STANDARD:
		if syss.size() >= MAX_SYSTEME:
			break
		if not syss.has(s):
			syss.append(s)
	var out: Array = []
	var emus: Array = cfg.call("emulators") if cfg else []
	for s in syss.slice(0, MAX_SYSTEME):
		var sd: Dictionary = cfg.call("system", s) if cfg else {}
		var kurz := str(sd.get("short", str(s).to_upper()))
		var emu := str(sd.get("emulator", ""))
		var eigen := false
		for e in emus:
			if e is Dictionary and s in (e.get("systems", []) as Array) and str(e.get("exe", "")) != "":
				emu = str(e.id)
				eigen = true
				break
		var emu_name := emu
		for e in emus:
			if e is Dictionary and str(e.get("id", "")) == emu:
				emu_name = str(e.get("name", emu)).get_slice(" (", 0)
		out.append({ "sys": str(s), "kurz": kurz, "name": str(sd.get("name", kurz)), "farbe": Color(str(sd.get("color", "#7a5fd0"))),
			"emu": emu, "emu_name": emu_name, "spiele": int(zahl.get(s, 0)), "eigen": eigen })
	return out


# --- Zeichnen ----------------------------------------------------------------------------------

## Abgerundetes Rechteck als Vieleck.
static func rund(r: Rect2, rad: float, n := 6) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var ecken := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
	for e in ecken:
		for i in n + 1:
			var a := float(e[1]) + PI * 0.5 * i / n
			pts.append((e[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	return pts


## Fläche mit senkrechtem Verlauf (Farbe je Punkt nach seiner Höhe in r).
static func verlauf(ci: CanvasItem, pts: PackedVector2Array, r: Rect2, oben: Color, unten: Color) -> void:
	if pts.size() < 3:
		return
	var cols := PackedColorArray()
	for p in pts:
		cols.append(oben.lerp(unten, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	ci.draw_polygon(pts, cols)


## Teil einer Form innerhalb von huelle (für Bilder, die nicht über den Rand dürfen).
static func in_huelle(form: PackedVector2Array, huelle: PackedVector2Array) -> Array:
	return Geometry2D.intersect_polygons(form, huelle)


## Weicher Schatten unter einer Fläche (einige ausgreifende, sehr leichte Lagen).
static func schatten(ci: CanvasItem, r: Rect2, rad: float, a: float) -> void:
	if a <= 0.01:
		return
	for i in 4:
		var g := 4.0 + i * 7.0
		ci.draw_colored_polygon(rund(Rect2(r.position + Vector2(-g * 0.5, g * 0.8), r.size + Vector2(g, g * 0.6)), rad + g), Color(0, 0, 0, a * 0.13))


## Bild, das die Fläche füllt (Ausschnitt um den Fokuspunkt, gerundete Ecken).
static func bild_zeichnen(ci: CanvasItem, r: Rect2, tex: Texture2D, rad: float, a := 1.0, zoom := 1.0, fokus := Vector2(0.5, 0.4)) -> void:
	var ts := Vector2(tex.get_size())
	if ts.x < 1.0 or ts.y < 1.0:
		return
	var k := maxf(r.size.x / ts.x, r.size.y / ts.y) * zoom
	var sicht := r.size / (ts * k)
	var o := Vector2((1.0 - sicht.x) * fokus.x, (1.0 - sicht.y) * fokus.y)
	var pts := rund(r, rad)
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(o + (p - r.position) / r.size * sicht)
	ci.draw_polygon(pts, PackedColorArray([Color(1, 1, 1, a)]), uvs, tex)


## Dunkler Schleier von anteil (0 … 1 der Höhe) bis unten, damit Schrift auf Bildern lesbar bleibt.
static func schleier(ci: CanvasItem, r: Rect2, rad: float, anteil: float, a: float) -> void:
	var y0 := r.position.y + r.size.y * anteil
	var unten := Rect2(r.position.x - 1.0, y0, r.size.x + 2.0, r.end.y - y0 + 1.0)
	for poly in in_huelle(rund(r, rad), PackedVector2Array([unten.position, Vector2(unten.end.x, y0), unten.end, Vector2(unten.position.x, unten.end.y)])):
		var cols := PackedColorArray()
		for p in poly:
			var x := clampf((p.y - y0) / maxf(r.end.y - y0, 1.0), 0.0, 1.0)
			cols.append(Color(0, 0, 0, a * x * x * (3.0 - 2.0 * x)))
		ci.draw_polygon(poly, cols)


## Logo zu einem Schlüssel aus badge_logos (einfarbig in col) mittig bzw. links in r; false, wenn es keins gibt.
static func logo(ci: CanvasItem, key: String, r: Rect2, col: Color, links := false) -> bool:
	if key == "" or not BadgeLogos.LOGOS.has(key):
		return false
	var got := BadgeLogos.line_logo(key, r.size.y, r.size.x)
	if got.is_empty():
		return false
	var sz: Vector2 = got.size
	if sz.y > r.size.y:
		sz *= r.size.y / sz.y
	var pos := r.get_center() - sz * 0.5
	if links:
		pos.x = r.position.x
	ci.draw_texture_rect(got.tex, Rect2(pos, sz), false, col)
	return true


## Eigene Silhouette einer Konsole (Disc-Konsole, Modul-Konsole, Handheld), Mitte c, Breite etwa s.
static func silhouette(ci: CanvasItem, sys: String, c: Vector2, s: float, ink: Color, farbe: Color) -> void:
	var tief := Color(ink, ink.a * 0.18)
	if sys in HAND:
		var r := Rect2(c - Vector2(s * 0.3, s * 0.46), Vector2(s * 0.6, s * 0.92))
		verlauf(ci, rund(r, s * 0.08), r, Color(ink, ink.a * 0.32), Color(ink, ink.a * 0.16))
		var sc := Rect2(r.position + Vector2(s * 0.07, s * 0.08), Vector2(r.size.x - s * 0.14, r.size.y * 0.42))
		verlauf(ci, rund(sc, s * 0.025), sc, farbe.lightened(0.15), farbe.darkened(0.45))
		var pad := Vector2(r.position.x + s * 0.16, r.end.y - s * 0.2)
		ci.draw_rect(Rect2(pad - Vector2(s * 0.075, s * 0.022), Vector2(s * 0.15, s * 0.044)), Color(ink, ink.a * 0.7))
		ci.draw_rect(Rect2(pad - Vector2(s * 0.022, s * 0.075), Vector2(s * 0.044, s * 0.15)), Color(ink, ink.a * 0.7))
		ci.draw_circle(Vector2(r.end.x - s * 0.17, pad.y + s * 0.03), s * 0.035, farbe.lightened(0.2), true, -1.0, true)
		ci.draw_circle(Vector2(r.end.x - s * 0.1, pad.y - s * 0.04), s * 0.035, farbe.lightened(0.2), true, -1.0, true)
		return
	var body := Rect2(c - Vector2(s * 0.5, s * 0.08), Vector2(s, s * 0.34))
	if sys in DISC:
		# Die Scheibe liegt halb im Laufwerk: zuerst sie, dann das Gehäuse darüber.
		var dc := Vector2(c.x + s * 0.12, body.position.y + s * 0.02)
		ci.draw_circle(dc, s * 0.24, Color(ink, ink.a * 0.24), true, -1.0, true)
		ci.draw_arc(dc, s * 0.19, PI * 1.05, PI * 1.6, 24, Color(farbe.lightened(0.4), 0.8 * ink.a), s * 0.02, true)
		ci.draw_circle(dc, s * 0.05, Color(0, 0, 0, 0.55 * ink.a), true, -1.0, true)
	else:
		var mod := Rect2(Vector2(c.x - s * 0.2, body.position.y - s * 0.24), Vector2(s * 0.4, s * 0.3))
		verlauf(ci, rund(mod, s * 0.03), mod, Color(ink, ink.a * 0.55), Color(ink, ink.a * 0.35))
		ci.draw_rect(Rect2(mod.position + Vector2(s * 0.05, s * 0.05), Vector2(mod.size.x - s * 0.1, s * 0.1)), farbe.lightened(0.1))
	verlauf(ci, rund(body, s * 0.07), body, Color(ink, ink.a * 0.42), Color(ink, ink.a * 0.2))
	ci.draw_rect(Rect2(body.position.x + s * 0.08, body.position.y + s * 0.03, s * 0.84, maxf(1.0, s * 0.012)), Color(ink, ink.a * 0.35))
	ci.draw_circle(Vector2(body.position.x + s * 0.14, body.end.y - s * 0.1), s * 0.03, farbe.lightened(0.3), true, -1.0, true)
	ci.draw_rect(Rect2(body.end.x - s * 0.34, body.end.y - s * 0.12, s * 0.22, s * 0.035), tief)


## Zeichen eines Emulators in einem runden Feld: sein Logo (zur Laufzeit), sonst die Anfangsbuchstaben
## auf einer Fläche in der Farbe seines Systems.
static func emu_zeichen(ci: CanvasItem, e: Dictionary, c: Vector2, rad: float, a: float) -> void:
	var farbe: Color = e.get("farbe", Color("#7a5fd0"))
	var hell := farbe.lightened(0.25)
	ci.draw_circle(c, rad, Color(farbe.darkened(0.55), a), true, -1.0, true)
	ci.draw_arc(c, rad - 0.5, 0.0, TAU, 48, Color(hell, 0.35 * a), 1.0, true)
	var lr := Rect2(c - Vector2(rad, rad) * 0.62, Vector2(rad, rad) * 1.24)
	if logo(ci, "emu_" + str(e.get("emu", "")), lr, Color(1, 1, 1, a)):
		return
	var name := str(e.get("emu_name", "?"))
	var kurz := name.substr(0, 1).to_upper()
	for i in range(1, name.length()):
		var ch := name.substr(i, 1)
		if ch == ch.to_upper() and ch != ch.to_lower() and kurz.length() < 2:
			kurz += ch
	if kurz.length() < 2 and name.length() > 1:
		kurz += name.substr(1, 1).to_lower()
	var f := UzTheme.font("bold")
	var fs := int(rad * 0.82)
	var w := f.get_string_size(kurz, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), kurz, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(hell.lerp(Color.WHITE, 0.6), a))


# --- Eigene Bilder der Medien-Kacheln ------------------------------------------------------------

## Eigenes Bild einer Kachel (wenn kein echtes da ist): art aus ARTEN, zeit läuft (Schallplatte dreht,
## Pegel), akz ist der Akzent.
static func illu(ci: CanvasItem, art: String, r: Rect2, rad: float, zeit: float, akz: Color) -> void:
	var huelle := rund(r, rad)
	match art:
		"musik":
			verlauf(ci, huelle, r, Color("#2a1846"), Color("#0e0a18"))
			var rr := r.size.y * 0.38
			var c := Vector2(r.end.x - rr - r.size.y * 0.1, r.get_center().y - r.size.y * 0.04)
			for poly in in_huelle(_kreis(c, rr, 64), huelle):
				ci.draw_colored_polygon(poly, Color("#08070c"))
			for i in 7:
				var gr := rr * (0.48 + i * 0.075)
				if c.x + gr < r.end.x - 2.0:
					ci.draw_arc(c, gr, 0.0, TAU, 64, Color(1, 1, 1, 0.045), 1.0, true)
			var glanz := zeit * 0.6
			ci.draw_arc(c, rr * 0.78, glanz, glanz + 0.7, 24, Color(1, 1, 1, 0.12), rr * 0.32, true)
			ci.draw_circle(c, rr * 0.3, akz, true, -1.0, true)
			ci.draw_circle(c, rr * 0.05, Color("#08070c"), true, -1.0, true)
			for i in (9 if r.size.x > 160.0 else 0):
				var lv := 0.35 + 0.65 * absf(sin(zeit * (2.4 + i * 0.37) + i * 1.3))
				var bh := r.size.y * 0.22 * lv
				ci.draw_rect(Rect2(r.position.x + 24.0 + i * 9.0, r.get_center().y + r.size.y * 0.02 - bh, 5.0, bh), Color(akz.lightened(0.3), 0.8))
		"videos":
			verlauf(ci, huelle, r, Color("#f3a46b"), Color("#5b2d5c"))
			var sun := Vector2(r.position.x + r.size.x * 0.66, r.position.y + r.size.y * 0.5)
			ci.draw_circle(sun, r.size.y * 0.14, Color("#ffe1b0"), true, -1.0, true)
			for berg in [[0.62, 0.16, Color("#7a3a63"), 0.013], [0.76, 0.12, Color("#3d1f45"), 0.021]]:
				var pts := PackedVector2Array([Vector2(r.position.x - 2.0, r.end.y + 2.0)])
				var x := 0.0
				while x <= r.size.x + 20.0:
					var u := x + zeit * 6.0
					pts.append(
							Vector2(r.position.x + x,
							r.position.y + r.size.y * float(berg[0]) - r.size.y * float(berg[1]) * (0.6 * sin(u * float(berg[3])) + 0.4 * sin(u * float(berg[3]) * 2.3 + 1.7))))
					x += 16.0
				pts.append(Vector2(r.end.x + 20.0, r.end.y + 2.0))
				for poly in in_huelle(pts, huelle):
					ci.draw_colored_polygon(poly, berg[2])
			var pc := r.get_center() - Vector2(0, r.size.y * 0.06)
			ci.draw_circle(pc, r.size.y * 0.13, Color(0, 0, 0, 0.35), true, -1.0, true)
			var d := r.size.y * 0.055
			ci.draw_colored_polygon(PackedVector2Array([pc + Vector2(-d * 0.7, -d), pc + Vector2(d * 1.1, 0), pc + Vector2(-d * 0.7, d)]), Color(1, 1, 1, 0.95))
		"filme":
			verlauf(ci, huelle, r, Color("#14182a"), Color("#06070c"))
			var licht := PackedVector2Array([Vector2(r.get_center().x - r.size.x * 0.08, r.position.y), Vector2(r.get_center().x + r.size.x * 0.08, r.position.y),
				Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)])
			for poly in in_huelle(licht, huelle):
				var cols := PackedColorArray()
				for p in poly:
					cols.append(Color(0.75, 0.82, 1.0, 0.1 * (1.0 - (p.y - r.position.y) / r.size.y)))
				ci.draw_polygon(poly, cols)
			var ph := r.size.y * 0.62
			var pw := ph * 0.68
			var farben := [[Color("#2d4a7a"), Color("#0f1a33")], [Color("#7a3546"), Color("#2a0f1a")], [Color("#3b6b5a"), Color("#0f2a22")]]
			for i in 3:
				var k := i - 1
				var pr := Rect2(r.get_center() + Vector2(k * pw * 0.78 - pw * 0.5, -ph * 0.42 + absf(k) * ph * 0.06), Vector2(pw, ph))
				var fa: Array = farben[(i + 1) % 3]
				schatten(ci, pr, 6.0, 0.6)
				verlauf(ci, rund(pr, 6.0), pr, fa[0], fa[1])
				if i == 1:
					ci.draw_circle(pr.position + Vector2(pw * 0.68, ph * 0.3), pw * 0.12, Color("#ffe9c7"), true, -1.0, true)
					ci.draw_colored_polygon(PackedVector2Array([pr.position + Vector2(0, ph * 0.78), pr.position + Vector2(pw * 0.42, ph * 0.5),
						pr.position + Vector2(pw, ph * 0.74), pr.end, Vector2(pr.position.x, pr.end.y)]), Color(0, 0, 0, 0.35))
				ci.draw_rect(Rect2(pr.position.x + pw * 0.14, pr.end.y - ph * 0.16, pw * 0.72, maxf(2.0, ph * 0.028)), Color(1, 1, 1, 0.55))
		"live":
			verlauf(ci, huelle, r, Color("#0f2236"), Color("#081019"))
			var gp := PackedVector2Array([Vector2(r.position.x - 2.0, r.end.y + 2.0)])
			var x2 := 0.0
			while x2 <= r.size.x + 20.0:
				var u2 := x2 + zeit * 14.0
				gp.append(Vector2(r.position.x + x2, r.position.y + r.size.y * (0.7 - 0.08 * sin(u2 * 0.02) - 0.05 * sin(u2 * 0.051 + 1.0))))
				x2 += 14.0
			gp.append(Vector2(r.end.x + 20.0, r.end.y + 2.0))
			for poly in in_huelle(gp, huelle):
				ci.draw_colored_polygon(poly, Color("#173a4f"))
			ci.draw_circle(Vector2(r.position.x + r.size.x * 0.3, r.position.y + r.size.y * 0.55), r.size.y * 0.05, Color("#8fe3ff"), true, -1.0, true)
			live_chat(ci, r, zeit)
		"aufnahmen":
			verlauf(ci, huelle, r, Color("#1c1a26"), Color("#0b0a10"))
			for i in 2:
				var pr2 := Rect2(r.get_center() - Vector2(r.size.y * 0.34, r.size.y * 0.23), Vector2(r.size.y * 0.68, r.size.y * 0.46))
				var dreh := -0.12 if i == 0 else 0.07
				ci.draw_set_transform(r.get_center() + Vector2(-r.size.x * 0.06 + i * r.size.x * 0.1, -r.size.y * 0.02), dreh, Vector2.ONE)
				pr2.position -= r.get_center()
				schatten(ci, pr2, 4.0, 0.5)
				ci.draw_colored_polygon(rund(pr2, 4.0), Color("#f2efe8"))
				var innen := pr2.grow(-r.size.y * 0.03)
				verlauf(ci, rund(innen, 2.0), innen, Color("#6fa6d6") if i == 1 else Color("#d98f6a"), Color("#e8d6b4") if i == 1 else Color("#5a3550"))
				ci.draw_colored_polygon(
						PackedVector2Array([Vector2(innen.position.x, innen.end.y), Vector2(innen.position.x + innen.size.x * 0.35, innen.position.y + innen.size.y * 0.5),
					Vector2(innen.position.x + innen.size.x * 0.6, innen.position.y + innen.size.y * 0.72),
						Vector2(innen.position.x + innen.size.x * 0.8, innen.position.y + innen.size.y * 0.45),
					innen.end]), Color(0, 0, 0, 0.32))
				ci.draw_set_transform(Vector2.ZERO)
		_:
			verlauf(ci, huelle, r, Color("#1b1f2e"), Color("#0b0d14"))
			var cols2 := [Color("#e06b8b"), Color("#6b8de0"), Color("#5fc49a"), Color("#e0b05f"), Color("#a07be0"), Color("#5fb8d6")]
			var zeichen := ["music", "video", "chat", "browser", "star", "film"]
			var s2 := minf(r.size.y * 0.26, r.size.x * 0.14)
			var g2 := s2 * 0.32
			var start := r.get_center() - Vector2(s2 * 3.0 + g2 * 2.0, s2 * 2.0 + g2) * 0.5 - Vector2(0, r.size.y * 0.06)
			for i in 6:
				var tr2 := Rect2(start + Vector2((i % 3) * (s2 + g2), int(i / 3.0) * (s2 + g2)), Vector2(s2, s2))
				var col: Color = cols2[i]
				verlauf(ci, rund(tr2, s2 * 0.24), tr2, col.lightened(0.12), col.darkened(0.3))
				ci.draw_texture_rect(Icons.tex(str(zeichen[i]), int(s2 * 0.5)), Rect2(tr2.get_center() - Vector2(s2, s2) * 0.25, Vector2(s2, s2) * 0.5), false,
						Color(1, 1, 1, 0.92))


## Live: ein paar Zeilen Chat rechts, die nach oben wandern.
static func live_chat(ci: CanvasItem, r: Rect2, zeit: float) -> void:
	var f := UzTheme.font("medium")
	var fs := int(clampf(r.size.y * 0.075, 11.0, 16.0))
	var zeilen := [["Mira", Color("#f29ad8")], ["Jonas", Color("#69e39a")], ["Noor", Color("#e7c27d")], ["Kai", Color("#7aa2ff")]]
	var x := r.end.x - r.size.x * 0.34
	var schritt := fs * 1.9
	var off := fmod(zeit * 10.0, schritt)
	for i in 5:
		var y := r.end.y - r.size.y * 0.12 - i * schritt + off
		if y < r.position.y + r.size.y * 0.25 or y > r.end.y - 6.0:
			continue
		var z: Array = zeilen[i % zeilen.size()]
		var a := clampf((y - r.position.y - r.size.y * 0.25) / (r.size.y * 0.2), 0.0, 1.0)
		ci.draw_string(f, Vector2(x, y), str(z[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(z[1], a))
		var w := f.get_string_size(str(z[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var bw := minf(r.size.x * 0.12 + (i % 3) * 10.0, r.end.x - 14.0 - (x + w + 8.0))
		if bw > 4.0:
			ci.draw_rect(Rect2(x + w + 8.0, y - fs * 0.62, bw, fs * 0.42), Color(1, 1, 1, 0.22 * a))


## Eigenes Bild, wo es kein echtes gibt (Schauen & Hören): eine ruhige Landschaft in einem Farbton –
## Himmel im Verlauf, Licht und Sonne bzw. Mond, drei Hügelketten (hinten im Dunst, vorn dunkel) oder
## Meer mit Lichtspur (art 2); art 1 ist Nacht mit Sternen. zeit schiebt die Ketten leise gegeneinander
## (Tiefe). In r mit runden Ecken rad geschnitten; gl: weicher Lichtfleck für das Licht um die Sonne.
static func landschaft(ci: CanvasItem, r: Rect2, rad: float, hue: float, art: int, zeit: float, a := 1.0, gl: Texture2D = null) -> void:
	if a <= 0.003 or r.size.x < 4.0 or r.size.y < 4.0:
		return
	var huelle := rund(r, rad)
	var nacht := art == 1
	var oben := Color.from_hsv(fposmod(hue + 0.04, 1.0), 0.7, 0.16 if nacht else 0.32)
	var unten := Color.from_hsv(fposmod(hue - 0.05, 1.0), 0.5, 0.4 if nacht else 0.9)
	var glanz := Color.from_hsv(fposmod(hue + 0.08, 1.0), 0.25 if nacht else 0.42, 1.0)
	var horizont := 0.62 if art == 2 else 0.58
	verlauf(ci, huelle, r, Color(oben, a), Color(unten.lerp(oben, 0.15), a))
	var sonne := r.position + r.size * (Vector2(0.72, 0.24) if nacht else Vector2(0.68, horizont - 0.06))
	if gl:
		var gr := r.size.y * (0.5 if nacht else 0.9)
		ci.draw_texture_rect(gl, Rect2(sonne - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(glanz, (0.25 if nacht else 0.55) * a))
	var sr := r.size.y * (0.045 if nacht else 0.075)
	for poly in in_huelle(_kreis(sonne, sr, 40), huelle):
		ci.draw_colored_polygon(poly, Color(Color(1.0, 0.97, 0.9), a))
	if nacht:
		for i in 26:
			var h := absi(hash(Vector2i(i, int(hue * 100.0))))
			var p := r.position + Vector2(float(h % 997) / 997.0 * r.size.x, float(floori(h / 997.0) % 601) / 601.0 * r.size.y * horizont * 0.9)
			var tw := 0.5 + 0.5 * sin(zeit * 1.7 + i)
			ci.draw_rect(Rect2(p, Vector2.ONE * maxf(1.0, r.size.y / 260.0)), Color(1, 1, 1, (0.35 + 0.4 * tw) * a))
	if art == 2:
		var meer := Rect2(r.position.x, r.position.y + r.size.y * horizont, r.size.x, r.size.y * (1.0 - horizont))
		var mp := PackedVector2Array([meer.position, Vector2(meer.end.x, meer.position.y), meer.end, Vector2(meer.position.x, meer.end.y)])
		for poly in in_huelle(mp, huelle):
			var cols := PackedColorArray()
			for q in poly:
				var mv := clampf((q.y - meer.position.y) / maxf(meer.size.y, 1.0), 0.0, 1.0)
				cols.append(Color(unten.lerp(oben, mv * 0.9).darkened(0.35 + mv * 0.3), a))
			ci.draw_polygon(poly, cols)
		for i in 9:
			var y := meer.position.y + meer.size.y * (0.06 + i * 0.1)
			var bw := r.size.x * (0.05 + i * 0.022) * (0.7 + 0.3 * sin(zeit * 1.3 + i))
			ci.draw_rect(Rect2(sonne.x - bw * 0.5, y, bw, maxf(1.0, r.size.y * 0.008)), Color(glanz, (0.5 - i * 0.04) * a))
		return
	for l in 3:
		var basis := horizont + 0.03 + l * 0.12
		var amp := (0.11 if nacht else 0.06) * (1.0 - l * 0.22)
		var land := Color.from_hsv(fposmod(hue + 0.02 * l, 1.0), 0.5, 0.32 - l * 0.09).lerp(unten, 0.42 - l * 0.18)
		var pts := PackedVector2Array([Vector2(r.position.x - 2.0, r.end.y + 2.0)])
		var x := 0.0
		var schritt := maxf(r.size.x / 48.0, 3.0)
		var ver := zeit * (2.0 + l * 3.0)
		while x <= r.size.x + schritt:
			var u := (x + ver) / maxf(r.size.x, 1.0)
			var y := basis - amp * (0.6 * sin(u * (3.0 + l * 1.7) * TAU + l * 1.3) + 0.4 * sin(u * (7.0 + l * 2.3) * TAU + l * 0.7))
			pts.append(Vector2(r.position.x + x, r.position.y + r.size.y * y))
			x += schritt
		pts.append(Vector2(r.end.x + 2.0, r.end.y + 2.0))
		for poly in in_huelle(pts, huelle):
			ci.draw_colored_polygon(poly, Color(land, a))


static func _kreis(c: Vector2, rad: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts
