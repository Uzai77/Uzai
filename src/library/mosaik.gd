extends RefCounted
## Mosaik: eine selbst gestaltete Seite je Konsole bzw. Ordner (A auf PS2 in der Quellen-Zeile).
## Kacheln liegen auf einem Raster (Spalten × Zeilen je Seite, je Mosaik frei von 2 × 2 bis 10 × 10,
## Standard 6 × 3) in vier Größen – klein 1×1,
## breit 2×1, hoch 1×2, groß 2×2 – und sind ein Spiel, ein Ordner (eigene Sammlung, Uzai-Ordner
## aus Library.folders), ein reines Bild (Gestaltung, nicht wählbar) oder ein leerer Platzhalter.
##
## Hier steht nur die Logik ohne Oberfläche (getestet in tests/logic_mosaik.gd): Belegung ohne
## Überlappung, Verschieben und Größe (was im Weg liegt, rückt zur Seite), Seiten, das
## Auto-Mosaik und Speichern in mosaik.json (neben library.json, für alle Profile).
##
## Eine Kachel: { id, art: spiel|ordner|bild|leer, ref (Spiel- bzw. Ordner-ID), s (Seite), x, y,
## w, h, bild: { art: cover|hero|logo|datei, pfad (nur datei), fx, fy (Fokuspunkt 0…1) }, logo }.
## Ein Mosaik: { eigen (vom Nutzer gestaltet), cols, rows (Raster), kacheln, weg (bewusst
## abgenommene Spiele/Ordner) }. Ohne cols/rows (ältere Dateien) gilt 6 × 3.
## Alle Rechnungen mit Lage nehmen das Raster ra (Vector2i: Spalten, Zeilen) mit.
## Solange eigen fehlt, legt Uzai es jedes Mal neu an (auto) – es wächst mit der Bibliothek.

const Sicher := preload("res://src/core/sicher.gd")

## Raster der Vorlagen und älterer Dateien.
const COLS := 6
const ROWS := 3
const STANDARD := Vector2i(COLS, ROWS)
const MIN_RASTER := 2
const MAX_RASTER := 10
## Genug Seiten, dass auch 2400 Kacheln auf einem 2 × 2-Raster Platz finden.
const MAX_SEITEN := 1200
const MAX_KACHELN := 2400
const MAX_WEG := 5000
const ARTEN := ["spiel", "ordner", "bild", "leer"]
## [w, h, Name] – klein, breit, hoch, groß
const GROESSEN := [[1, 1, "Klein"], [2, 1, "Querformat"], [1, 2, "Hochformat"], [2, 2, "Groß"]]
const BILD_ARTEN := ["cover", "hero", "logo", "datei"]
const ENDUNGEN := ["png", "jpg", "jpeg", "webp"]
const DATEI := "mosaik.json"
const ZOOM_MAX := 4.0
## Bild vom Handy: höchstens so groß (Bytes) und so viele Punkte je Seite.
const HANDY_MAX := 15 * 1024 * 1024
const HANDY_SEITE := 8192
## Hintergrund der ganzen Seite: höchstens so stark abgedunkelt (0 = gar nicht).
const DUNKEL_MAX := 0.9

## Vorlagen für das Auto-Mosaik: Plätze [x, y, w, h] in der Reihenfolge, in der sie vergeben
## werden (der wichtigste Platz zuerst). Jede füllt eine Seite ganz.
## BUEHNE: viele breite Plätze (Spiele mit Hintergrundbild, Steam & Co.).
const BUEHNE := [[0, 0, 2, 2], [2, 0, 1, 2], [3, 0, 1, 2], [4, 0, 2, 1], [4, 1, 2, 1], [1, 2, 2, 1], [4, 2, 2, 1], [0, 2, 1, 1], [3, 2, 1, 1]]
## REGAL: vor allem hohe Plätze für Hüllen (Emulator-Spiele haben selten Hintergründe).
const REGAL := [[0, 0, 2, 2], [2, 0, 1, 2], [3, 0, 1, 2], [4, 0, 1, 2], [5, 0, 1, 2],
	[0, 2, 1, 1], [1, 2, 1, 1], [2, 2, 1, 1], [3, 2, 1, 1], [4, 2, 1, 1], [5, 2, 1, 1]]
## MITTE: groß in der Mitte, hohe Hüllen links und rechts, zwei breite unten.
const MITTE := [[2, 0, 2, 2], [0, 0, 1, 2], [1, 0, 1, 2], [4, 0, 1, 2], [5, 0, 1, 2], [0, 2, 2, 1], [4, 2, 2, 1], [2, 2, 1, 1], [3, 2, 1, 1]]


# --- Prüfen und Aufräumen ------------------------------------------------------------------------

## Pfad einer eigenen Bilddatei: lokal (kein Netzwerkpfad, kein NUL), Bild-Endung, nicht zu lang.
## Geladen wird sie nur über Media (Image.load_*_from_buffer mit Größenprüfung), nie als Ressource.
## Freigaben und NT-Pfade („\??\UNC\…“) prüft dieselbe Stelle wie überall (Sicher.local_path_ok); früher eine eigene
## Kopie ohne die Regel für „?“ und „*“.
static func pfad_ok(p: String) -> bool:
	if p.length() < 4 or p.length() > 1024 or not Sicher.local_path_ok(p):
		return false
	if p.begins_with("res://") or p.begins_with("user://") or p.contains("://"):
		return false
	return p.get_extension().to_lower() in ENDUNGEN


static func _zahl(v: Variant, lo: int, hi: int, std: int) -> int:
	if v is float or v is int:
		var f := float(v)
		if is_nan(f) or is_inf(f):
			return std
		return clampi(int(f), lo, hi)
	return std


static func _bruch(v: Variant) -> float:
	if v is float or v is int:
		var f := float(v)
		return clampf(f, 0.0, 1.0) if not is_nan(f) else 0.5
	return 0.5


## Raster eines Mosaiks (Spalten, Zeilen), begrenzt auf 2 … 10; ohne Angabe 6 × 3.
static func raster_von(d: Variant) -> Vector2i:
	if not (d is Dictionary):
		return STANDARD
	return Vector2i(_zahl(d.get("cols", COLS), MIN_RASTER, MAX_RASTER, COLS), _zahl(d.get("rows", ROWS), MIN_RASTER, MAX_RASTER, ROWS))


static func zellen(ra: Vector2i) -> int:
	return ra.x * ra.y


static func bild_sauber(b: Variant) -> Dictionary:
	if not (b is Dictionary):
		return {}
	var art := str((b as Dictionary).get("art", ""))
	if not art in BILD_ARTEN:
		return {}
	var out := { "art": art, "fx": _bruch(b.get("fx", 0.5)), "fy": _bruch(b.get("fy", 0.5)) }
	# Zoom (LT/RT beim Ausschnitt): 1 = Bild füllt die Fläche gerade, bis 4fach.
	var z := clampf(float(b.get("z", 1.0)) if (b.get("z") is float or b.get("z") is int) else 1.0, 1.0, ZOOM_MAX)
	if is_nan(z):
		z = 1.0
	if z > 1.001:
		out["z"] = snappedf(z, 0.001)
	if art == "datei":
		var p := str(b.get("pfad", ""))
		if not pfad_ok(p):
			return {}
		out["pfad"] = p
	return out


## Eine Kachel prüfen; {} wenn sie unbrauchbar ist.
static func kachel_sauber(k: Variant, ra := STANDARD) -> Dictionary:
	if not (k is Dictionary):
		return {}
	var art := str(k.get("art", ""))
	if not art in ARTEN:
		return {}
	var w := _zahl(k.get("w", 1), 1, 2, 1)
	var h := _zahl(k.get("h", 1), 1, 2, 1)
	var out := {
		"id": str(k.get("id", "")).left(24),
		"art": art,
		"s": _zahl(k.get("s", 0), 0, MAX_SEITEN - 1, 0),
		"x": _zahl(k.get("x", 0), 0, ra.x - w, 0),
		"y": _zahl(k.get("y", 0), 0, ra.y - h, 0),
		"w": w, "h": h,
	}
	if art == "spiel" or art == "ordner":
		var ref := str(k.get("ref", ""))
		if ref == "" or ref.length() > 200 or ref.to_utf8_buffer().has(0):
			return {}
		out["ref"] = ref
	var b := bild_sauber(k.get("bild"))
	if not b.is_empty() and art != "leer":
		out["bild"] = b
	if bool(k.get("logo", false)) and art == "spiel":
		out["logo"] = true
	return out


## Ein ganzes Mosaik aus der Datei prüfen: unbrauchbare Kacheln fallen weg, doppelte IDs werden
## neu vergeben, doppelte Spiele/Ordner bleiben nur einmal, und was sich überlappt, rückt an den
## nächsten freien Platz (nie zwei Kacheln auf einer Zelle).
static func sauber(d: Variant) -> Dictionary:
	var ra := raster_von(d)
	var out := { "eigen": false, "cols": ra.x, "rows": ra.y, "kacheln": [], "weg": [] }
	if not (d is Dictionary):
		return out
	out.eigen = bool(d.get("eigen", false))
	var weg: Variant = d.get("weg", [])
	if weg is Array:
		for w in (weg as Array).slice(0, MAX_WEG):
			if (w is String) and (w as String) != "" and (w as String).length() <= 200 and not (out.weg as Array).has(w):
				(out.weg as Array).append(w)
	var ks: Variant = d.get("kacheln", [])
	if not (ks is Array):
		return out
	var ids := {}
	var refs := {}
	var liste: Array = out.kacheln
	var bel := {}
	# Laufen mit, statt je Kachel alles Bisherige neu durchzugehen (gemessen: 2400 überlappende Kacheln einer
	# kaputten Datei 1,8 s): die höchste Nummer der Kennungen in liste und die erste Zelle, die noch frei sein kann.
	var nr := 0
	var frei_ab := 0
	for roh in (ks as Array).slice(0, MAX_KACHELN):
		var k := kachel_sauber(roh, ra)
		if k.is_empty():
			continue
		if k.has("ref"):
			var rk := str(k.art) + ":" + str(k.ref)
			if refs.has(rk):
				continue
			refs[rk] = true
		if k.id == "" or ids.has(k.id):
			k.id = "k%d" % (nr + 1)
		ids[k.id] = true
		if not _passt(bel, ra, int(k.s), int(k.x), int(k.y), int(k.w), int(k.h)):
			while bel.has(frei_ab):
				frei_ab += 1
			var p := _frei(bel, ra, int(k.w), int(k.h), frei_ab)
			if p.is_empty():
				continue
			k.s = p.s
			k.x = p.x
			k.y = p.y
		_belegen(bel, ra, k)
		liste.append(k)
		nr = maxi(nr, _nr(str(k.id)))
	return out


static func neue_id(kacheln: Array) -> String:
	return "k%d" % (_hoechste_nr(kacheln) + 1)


static func _hoechste_nr(kacheln: Array) -> int:
	var n := 0
	for k in kacheln:
		n = maxi(n, _nr(str(k.get("id", ""))))
	return n


## Zahl hinter dem „k“ einer Kennung („k12“ → 12), sonst 0.
static func _nr(id: String) -> int:
	return int(id.substr(1)) if id.begins_with("k") and id.substr(1).is_valid_int() else 0


# --- Belegung ------------------------------------------------------------------------------------
# Belegung: Zelle (Schlüssel über alle Seiten, Lesereihenfolge) → ID der Kachel. Einmal je Aufruf
# gebaut statt je Seite neu (bei 10 × 10 und vielen Seiten sonst spürbar).

static func _key(s: int, x: int, y: int, ra: Vector2i) -> int:
	return s * ra.x * ra.y + y * ra.x + x


static func _belegen(bel: Dictionary, ra: Vector2i, k: Dictionary) -> void:
	for yy in int(k.h):
		for xx in int(k.w):
			bel[_key(int(k.s), int(k.x) + xx, int(k.y) + yy, ra)] = str(k.id)


static func belegung(kacheln: Array, ra: Vector2i, ohne := "") -> Dictionary:
	var bel := {}
	for k in kacheln:
		if str(k.id) != ohne:
			_belegen(bel, ra, k)
	return bel


static func _passt(bel: Dictionary, ra: Vector2i, s: int, x: int, y: int, w: int, h: int) -> bool:
	if x < 0 or y < 0 or x + w > ra.x or y + h > ra.y or s < 0 or s >= MAX_SEITEN:
		return false
	for yy in h:
		for xx in w:
			if bel.has(_key(s, x + xx, y + yy, ra)):
				return false
	return true


static func passt(kacheln: Array, ra: Vector2i, s: int, x: int, y: int, w: int, h: int, ohne := "") -> bool:
	return _passt(belegung(kacheln, ra, ohne), ra, s, x, y, w, h)


static func _frei(bel: Dictionary, ra: Vector2i, w: int, h: int, ab_key := 0) -> Dictionary:
	if w > ra.x or h > ra.y:
		return {}
	var z := zellen(ra)
	for s in range(maxi(0, floori(float(ab_key) / z)), MAX_SEITEN):
		for y in ra.y - h + 1:
			for x in ra.x - w + 1:
				if _key(s, x, y, ra) >= ab_key and _passt(bel, ra, s, x, y, w, h):
					return { "s": s, "x": x, "y": y }
	return {}


## Erster freier Platz für w × h in Lesereihenfolge (Seite, Zeile, Spalte) ab ab_key; {} wenn
## alle Seiten voll sind.
static func frei_ab(kacheln: Array, ra: Vector2i, w: int, h: int, ab_key := 0, ohne := "") -> Dictionary:
	return _frei(belegung(kacheln, ra, ohne), ra, w, h, ab_key)


## Hinter der letzten Kachel (Lesereihenfolge ihrer oberen linken Ecken): hier landen neue Spiele.
static func ende_key(kacheln: Array, ra: Vector2i) -> int:
	var e := 0
	for k in kacheln:
		e = maxi(e, _key(int(k.s), int(k.x), int(k.y), ra) + 1)
	return e


static func seiten(kacheln: Array) -> int:
	var n := 1
	for k in kacheln:
		n = maxi(n, int(k.s) + 1)
	return n


static func finde(kacheln: Array, id: String) -> Dictionary:
	for k in kacheln:
		if str(k.id) == id:
			return k
	return {}


## Kachel an der Zelle (Seite s, x, y), {} wenn dort nichts liegt.
static func an(kacheln: Array, s: int, x: int, y: int) -> Dictionary:
	for k in kacheln:
		if int(k.s) == s and x >= int(k.x) and x < int(k.x) + int(k.w) and y >= int(k.y) and y < int(k.y) + int(k.h):
			return k
	return {}


## Neue Kachel hinten anhängen (hinter der letzten). false: kein Platz mehr. fuellen: passt sie
## nicht mehr auf die letzte Seite, aber eine kleine schon, wird sie klein (keine halb leeren Seiten).
## bel: schon gebaute Belegung (wird mitgeführt), sonst neu gebaut. lauf: { ende, nr } für viele Kacheln
## nacheinander (abgleichen) – Ende und höchste Kennung laufen mit, statt jedes Mal alle Kacheln durchzugehen.
static func anhaengen(kacheln: Array, ra: Vector2i, k: Dictionary, fuellen := false, bel: Variant = null, lauf: Variant = null) -> bool:
	if kacheln.size() >= MAX_KACHELN:
		return false
	var b: Dictionary = bel if bel is Dictionary else belegung(kacheln, ra)
	var ende: int = int(lauf.ende) if lauf is Dictionary else ende_key(kacheln, ra)
	var p := _frei(b, ra, int(k.get("w", 1)), int(k.get("h", 1)), ende)
	if fuellen and not p.is_empty() and int(p.s) > floori(float(maxi(ende - 1, 0)) / zellen(ra)) and not kacheln.is_empty():
		var klein := _frei(b, ra, 1, 1, ende)
		if not klein.is_empty() and int(klein.s) < int(p.s):
			p = klein
			k.w = 1
			k.h = 1
	if p.is_empty():
		p = _frei(b, ra, 1, 1, 0)
		if p.is_empty():
			return false
		k.w = 1
		k.h = 1
	k.s = p.s
	k.x = p.x
	k.y = p.y
	if str(k.get("id", "")) == "" or not finde(kacheln, str(k.id)).is_empty():
		k.id = "k%d" % (int(lauf.nr) + 1) if lauf is Dictionary else neue_id(kacheln)
	kacheln.append(k)
	_belegen(b, ra, k)
	if lauf is Dictionary:
		lauf.nr = maxi(int(lauf.nr), _nr(str(k.id)))
		lauf.ende = maxi(ende, _key(int(k.s), int(k.x), int(k.y), ra) + 1)
	return true


## Neue Kachel an eine bestimmte Zelle legen (Bearbeiten: A auf einem leeren Feld). Passt sie dort
## nicht ganz, wird sie kleiner; sonst an den nächsten freien Platz.
static func einsetzen(kacheln: Array, ra: Vector2i, k: Dictionary, s: int, x: int, y: int) -> bool:
	if kacheln.size() >= MAX_KACHELN:
		return false
	k.id = neue_id(kacheln)
	var bel := belegung(kacheln, ra)
	for g in [[int(k.get("w", 1)), int(k.get("h", 1))], [1, int(k.get("h", 1))], [int(k.get("w", 1)), 1], [1, 1]]:
		if _passt(bel, ra, s, x, y, g[0], g[1]):
			k.merge({ "s": s, "x": x, "y": y, "w": g[0], "h": g[1] }, true)
			kacheln.append(k)
			return true
	return anhaengen(kacheln, ra, k, false, bel)


## Nächster freier Platz für w × h, möglichst nah an (px, py) auf Seite s; sonst irgendwo dahinter.
static func naechst_frei(kacheln: Array, ra: Vector2i, w: int, h: int, s: int, px: int, py: int) -> Dictionary:
	var bel := belegung(kacheln, ra)
	var best := {}
	var best_d := INF
	for y in ra.y - h + 1:
		for x in ra.x - w + 1:
			if _passt(bel, ra, s, x, y, w, h):
				var d := float((x - px) * (x - px) + (y - py) * (y - py)) + y * 0.01
				if d < best_d:
					best_d = d
					best = { "s": s, "x": x, "y": y }
	if not best.is_empty():
		return best
	var p := _frei(bel, ra, w, h, _key(s, 0, 0, ra))
	return p if not p.is_empty() else _frei(bel, ra, w, h, 0)


## Kachel id nach (s, x, y) mit Größe w × h legen. Was dort lag, rückt auf den frei gewordenen
## Platz bzw. so nah wie möglich daneben (gleich große Kacheln tauschen also einfach); Kacheln,
## deren Spiel fehlt (fehlt(kachel) == true), fallen dabei weg statt zu wandern.
static func setzen(kacheln: Array, ra: Vector2i, id: String, s: int, x: int, y: int, w: int, h: int, fehlt: Callable = Callable()) -> bool:
	var k := finde(kacheln, id)
	if k.is_empty():
		return false
	w = clampi(w, 1, mini(2, ra.x))
	h = clampi(h, 1, mini(2, ra.y))
	x = clampi(x, 0, ra.x - w)
	y = clampi(y, 0, ra.y - h)
	if s < 0 or s >= MAX_SEITEN:
		return false
	var alt := { "s": int(k.s), "x": int(k.x), "y": int(k.y) }
	var weg: Array = []
	for o in kacheln:
		if is_same(o, k) or int(o.s) != s:
			continue
		if int(o.x) < x + w and x < int(o.x) + int(o.w) and int(o.y) < y + h and y < int(o.y) + int(o.h):
			weg.append(o)
	for o in weg:
		kacheln.erase(o)
	k.s = s
	k.x = x
	k.y = y
	k.w = w
	k.h = h
	for o in weg:
		if fehlt.is_valid() and bool(fehlt.call(o)):
			continue
		# Erst genau dorthin, wo die bewegte Kachel lag (Tausch), sonst so nah wie möglich.
		var p := {}
		if passt(kacheln, ra, int(alt.s), int(alt.x), int(alt.y), int(o.w), int(o.h)):
			p = alt
		else:
			p = naechst_frei(kacheln, ra, int(o.w), int(o.h), int(alt.s), int(alt.x), int(alt.y))
		if p.is_empty():
			# Alles voll: lieber klein als verloren.
			p = frei_ab(kacheln, ra, 1, 1, 0)
			if p.is_empty():
				continue
			o.w = 1
			o.h = 1
		o.s = p.s
		o.x = p.x
		o.y = p.y
		kacheln.append(o)
	return true


## Um eine Zelle verschieben; über den Rand links/rechts auf die Seite davor bzw. dahinter.
## Gibt die neue Seite zurück (-1: ging nicht).
static func verschieben(kacheln: Array, ra: Vector2i, id: String, dx: int, dy: int, fehlt: Callable = Callable()) -> int:
	var k := finde(kacheln, id)
	if k.is_empty():
		return -1
	var s := int(k.s)
	var nx := int(k.x) + dx
	var ny := int(k.y) + dy
	if ny < 0 or ny + int(k.h) > ra.y:
		return -1
	if nx < 0:
		if s == 0:
			return -1
		s -= 1
		nx = ra.x - int(k.w)
	elif nx + int(k.w) > ra.x:
		if s + 1 >= MAX_SEITEN:
			return -1
		s += 1
		nx = 0
	return s if setzen(kacheln, ra, id, s, nx, ny, int(k.w), int(k.h), fehlt) else -1


## Größe ändern; am Rand rückt die Kachel nach links bzw. oben.
static func groesse(kacheln: Array, ra: Vector2i, id: String, w: int, h: int, fehlt: Callable = Callable()) -> bool:
	var k := finde(kacheln, id)
	if k.is_empty():
		return false
	return setzen(kacheln, ra, id, int(k.s), mini(int(k.x), ra.x - w), mini(int(k.y), ra.y - h), w, h, fehlt)


## Anderes Raster (Spalten × Zeilen): Jede Kachel bleibt, wo sie war, wenn sie dort noch Platz hat.
## Sonst rückt sie in Lesereihenfolge an den nächsten freien Platz ab ihrer Seite (auf die nächste
## Seite bzw. nach hinten); passt eine große gar nicht mehr, wird sie kleiner. Nichts geht verloren.
## Gibt eine neue Liste zurück (die alte bleibt unberührt – Vorschau beim Einstellen).
static func umbauen(kacheln: Array, alt: Vector2i, neu: Vector2i) -> Array:
	var liste: Array = kacheln.duplicate(true)
	liste.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _key(int(a.s), int(a.x), int(a.y), alt) < _key(int(b.s), int(b.x), int(b.y), alt))
	var out: Array = []
	var bel := {}
	for k in liste:
		k.w = mini(int(k.w), neu.x)
		k.h = mini(int(k.h), neu.y)
		if not _passt(bel, neu, int(k.s), int(k.x), int(k.y), int(k.w), int(k.h)):
			var p := _frei(bel, neu, int(k.w), int(k.h), _key(int(k.s), 0, 0, neu))
			if p.is_empty():
				p = _frei(bel, neu, 1, 1, 0)
				if p.is_empty():
					continue
				k.w = 1
				k.h = 1
			k.s = p.s
			k.x = p.x
			k.y = p.y
		_belegen(bel, neu, k)
		out.append(k)
	return out


## Nächste Größe (X im Bearbeiten): klein → breit → hoch → groß → klein.
static func naechste_groesse(w: int, h: int) -> Array:
	for i in GROESSEN.size():
		if int(GROESSEN[i][0]) == w and int(GROESSEN[i][1]) == h:
			var n: Array = GROESSEN[(i + 1) % GROESSEN.size()]
			return [int(n[0]), int(n[1])]
	return [1, 1]


static func groesse_name(w: int, h: int) -> String:
	for g in GROESSEN:
		if int(g[0]) == w and int(g[1]) == h:
			return str(g[2])
	return "Klein"


## Leere Seiten zwischendrin schließen (nach dem Bearbeiten).
static func seiten_schliessen(kacheln: Array) -> void:
	var used := {}
	for k in kacheln:
		used[int(k.s)] = true
	var order: Array = used.keys()
	order.sort()
	var neu := {}
	for i in order.size():
		neu[order[i]] = i
	for k in kacheln:
		k.s = int(neu[int(k.s)])


# --- Abgleich mit der Bibliothek -----------------------------------------------------------------

## Gestaltetes Mosaik mit dem abgleichen, was es gibt: Neue Spiele und Ordner (weder auf dem Mosaik
## noch bewusst abgenommen) kommen hinten dazu – Spiele hoch mit Hülle, Ordner klein. Kacheln, deren
## Spiel gerade fehlt, bleiben gespeichert (es kommt vielleicht zurück, z. B. Laufwerk getrennt);
## gezeigt werden sie nicht, und wer ihren Platz belegt, verdrängt sie (setzen mit fehlt).
## Gibt zurück, ob sich etwas geändert hat.
static func abgleichen(d: Dictionary, spiele: Array, ordner: Array) -> bool:
	var ra := raster_von(d)
	var ks: Array = d.get("kacheln", [])
	var da := {}
	for k in ks:
		if k.has("ref"):
			da[str(k.art) + ":" + str(k.ref)] = true
	var weg: Array = d.get("weg", [])
	var neu := false
	var bel := belegung(ks, ra)
	# Gemessen ohne das Mitlaufen: 2000 neue Spiele auf einmal (viele ROMs dazugekommen) hielten Uzai beim
	# Öffnen der Seite 1,8 s an.
	var lauf := { "ende": ende_key(ks, ra), "nr": _hoechste_nr(ks) }
	var weg_da := {}
	for w in weg:
		weg_da[w] = true
	for f in ordner:
		var fid := str(f)
		if not da.has("ordner:" + fid) and not weg_da.has(fid):
			if anhaengen(ks, ra, { "art": "ordner", "ref": fid, "w": 1, "h": 1 }, false, bel, lauf):
				da["ordner:" + fid] = true
				neu = true
	for g in spiele:
		var gid := str(g)
		if not da.has("spiel:" + gid) and not weg_da.has(gid):
			if anhaengen(ks, ra, { "art": "spiel", "ref": gid, "w": 1, "h": 2, "bild": { "art": "cover", "fx": 0.5, "fy": 0.3 } }, true, bel, lauf):
				da["spiel:" + gid] = true
				neu = true
	d["kacheln"] = ks
	return neu


## Was gezeigt wird: Kacheln ohne fehlende Spiele/Ordner. da(kachel) -> bool.
static func sichtbar(kacheln: Array, da: Callable) -> Array:
	return kacheln.filter(func(k: Dictionary) -> bool: return not k.has("ref") or bool(da.call(k)))


## Wählbar ohne Bearbeiten: nur Spiele und Ordner (Bilder und Platzhalter sind Gestaltung).
static func waehlbar(k: Dictionary) -> bool:
	return str(k.get("art", "")) in ["spiel", "ordner"]


# --- Auto-Mosaik ---------------------------------------------------------------------------------

## Wie wichtig ein Spiel ist: Favoriten zuerst, dann Spielzeit, dann zuletzt gespielt.
## info: { id, fav, zeit, zuletzt, breit (hat ein breites Bild), ordner (ist ein Ordner) }
static func wichtiger(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.get("fav", false)) != bool(b.get("fav", false)):
		return bool(a.get("fav", false))
	if int(a.get("zeit", 0)) != int(b.get("zeit", 0)):
		return int(a.get("zeit", 0)) > int(b.get("zeit", 0))
	return int(a.get("zuletzt", 0)) > int(b.get("zuletzt", 0))


## Auto-Mosaik: nur Spiele und Ordner, keine Bilder. Wichtige Spiele groß, Hüllen in hohe Plätze,
## Spiele mit breitem Bild (Hintergrund) in breite. spiele: Liste von info (siehe wichtiger) in der
## Reihenfolge der Bibliothek; ordner: Ordner-IDs (kommen klein auf die erste Seite). Auf 6 × 3 aus
## gestalteten Vorlagen, auf anderen Rastern dicht gepackt (jede Seite voll, eine große je Seite).
static func auto(spiele: Array, ordner: Array, ra := STANDARD) -> Array:
	var reihe: Array = spiele.duplicate()
	reihe.sort_custom(wichtiger)
	var items: Array = []
	for i in reihe.size():
		items.append(reihe[i])
		if i == 2 or (i == reihe.size() - 1 and i < 2):
			for f in ordner:
				items.append({ "id": str(f), "ordner": true })
	if reihe.is_empty():
		for f in ordner:
			items.append({ "id": str(f), "ordner": true })
	if ra != STANDARD:
		return _auto_dicht(items, ra)
	var out: Array = []
	var s := 0
	var pos := 0
	while pos < items.size() and s < MAX_SEITEN:
		var rest := items.size() - pos
		var breit := 0
		for it in items.slice(pos, pos + 9):
			if bool(it.get("breit", false)):
				breit += 1
		# Viele breite Bilder: Bühne (abwechselnd gespiegelt); sonst Regal und Mitte im Wechsel.
		# Die letzte, nicht volle Seite füllt sich von links (Regal bzw. Bühne), ohne Lücken vorn.
		var vorlage: Array
		if breit >= mini(4, maxi(2, floori(rest / 2.0))):
			vorlage = BUEHNE if s % 2 == 0 else _spiegel(BUEHNE)
		elif rest < MITTE.size() or s % 2 == 0:
			vorlage = REGAL
		else:
			vorlage = MITTE
		var n := mini(rest, vorlage.size())
		var batch: Array = items.slice(pos, pos + n)
		for platz in vorlage.slice(0, n):
			var it := _bester(batch, int(platz[2]), int(platz[3]))
			batch.erase(it)
			out.append(_auto_kachel(it, s, platz, out))
		pos += n
		s += 1
	return out


## Auto-Mosaik auf einem freien Raster: Größe je Spiel (das erste und Favoriten groß – höchstens
## eine große je Seite –, mit Hintergrund breit, sonst hoch, Ordner klein), dann dicht von vorn
## gepackt. Passt eine Kachel nicht mehr auf die Seite, wird sie kleiner, statt Lücken zu lassen.
static func _auto_dicht(items: Array, ra: Vector2i) -> Array:
	var out: Array = []
	var bel := {}
	var seite := 0
	var gross_auf := {}
	var z := zellen(ra)
	for i in items.size():
		var it: Dictionary = items[i]
		var wh := Vector2i(1, 2)
		if bool(it.get("ordner", false)):
			wh = Vector2i(1, 1)
		elif (i == 0 or bool(it.get("fav", false))) and not gross_auf.has(seite):
			wh = Vector2i(2, 2)
		elif bool(it.get("breit", false)) and i % 3 == 1:
			wh = Vector2i(2, 1)
		wh = Vector2i(mini(wh.x, ra.x), mini(wh.y, ra.y))
		var p := _frei(bel, ra, wh.x, wh.y, seite * z)
		if p.is_empty() or int(p.s) > seite:
			for g in [Vector2i(1, 2), Vector2i(2, 1), Vector2i(1, 1)]:
				if g.x * g.y >= wh.x * wh.y or g.x > ra.x or g.y > ra.y:
					continue
				var q := _frei(bel, ra, g.x, g.y, seite * z)
				if not q.is_empty() and int(q.s) == seite:
					p = q
					wh = g
					break
		if p.is_empty():
			break
		seite = int(p.s)
		if wh == Vector2i(2, 2):
			gross_auf[seite] = true
		var k := _auto_kachel(it, seite, [int(p.x), int(p.y), wh.x, wh.y], out)
		_belegen(bel, ra, k)
		out.append(k)
	return out


static func _spiegel(v: Array) -> Array:
	return v.map(func(p: Array) -> Array: return [COLS - int(p[0]) - int(p[2]), p[1], p[2], p[3]])


## Wer bekommt den Platz w × h? Große und hohe Plätze: das wichtigste Spiel (Ordner nie); breite:
## das wichtigste mit breitem Bild; kleine: zuerst Ordner, sonst das wichtigste.
static func _bester(batch: Array, w: int, h: int) -> Dictionary:
	var spiele := batch.filter(func(it: Dictionary) -> bool: return not bool(it.get("ordner", false)))
	var ordner := batch.filter(func(it: Dictionary) -> bool: return bool(it.get("ordner", false)))
	if w == 1 and h == 1 and not ordner.is_empty():
		return ordner[0]
	if w == 2 and h == 1:
		for it in spiele:
			if bool(it.get("breit", false)):
				return it
	if not spiele.is_empty():
		return spiele[0]
	return batch[0]


static func _auto_kachel(it: Dictionary, s: int, p: Array, schon: Array) -> Dictionary:
	var w := int(p[2])
	var h := int(p[3])
	var k := { "id": "k%d" % (schon.size() + 1), "s": s, "x": int(p[0]), "y": int(p[1]), "w": w, "h": h }
	if bool(it.get("ordner", false)):
		k["art"] = "ordner"
		k["ref"] = str(it.id)
		return k
	k["art"] = "spiel"
	k["ref"] = str(it.id)
	var quer := w > h or (w == 2 and h == 2)
	var art := "hero" if quer and bool(it.get("breit", false)) else "cover"
	# Eine Hülle in einer breiten Kachel: oberes Drittel (dort steht meist der Titel).
	k["bild"] = { "art": art, "fx": 0.5, "fy": 0.5 if art == "hero" or not quer else 0.3 }
	if art == "hero":
		k["logo"] = true
	return k


# --- Hintergrund der Seite -----------------------------------------------------------------------

## Hintergrund eines Mosaiks prüfen: { bild (wie bei Kacheln), farbe "#rrggbb", dunkel 0 … 0,9 }.
## {} = der übliche Raum von Uzai.
static func hintergrund_sauber(h: Variant) -> Dictionary:
	if not (h is Dictionary):
		return {}
	var out := {}
	var b := bild_sauber(h.get("bild"))
	if not b.is_empty() and str(b.art) == "datei":
		out["bild"] = b
	var f := str(h.get("farbe", ""))
	if f.length() == 7 and f.begins_with("#") and f.substr(1).is_valid_hex_number():
		out["farbe"] = f.to_lower()
	if out.is_empty():
		return {}
	var dn: Variant = h.get("dunkel", 0.35)
	out["dunkel"] = clampf(float(dn), 0.0, DUNKEL_MAX) if (dn is float or dn is int) and not is_nan(float(dn)) else 0.35
	return out


# --- Bild vom Handy ------------------------------------------------------------------------------

## Format nach den ersten Bytes (nicht nach Name oder Angabe des Handys): png, jpg, webp oder "".
static func bild_format(b: PackedByteArray) -> String:
	if b.size() < 16:
		return ""
	if b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47 and b[4] == 0x0D and b[5] == 0x0A:
		return "png"
	if b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF:
		return "jpg"
	if b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	return ""


## Bild vom Handy übernehmen: Größe und echten Kopf prüfen, aus dem Puffer dekodieren
## (Image.load_*_from_buffer), auf höchstens HANDY_SEITE begrenzen und NEU kodiert in den Ordner
## dir schreiben (PNG bei Durchsicht, sonst JPEG) – die Originaldatei wird nie gespeichert, Name
## und Pfad kommen von Uzai. Gibt den Pfad zurück, "" wenn das Bild nicht taugt.
static func bild_aus_bytes(b: PackedByteArray, dir: String) -> String:
	if b.is_empty() or b.size() > HANDY_MAX:
		return ""
	var fmt := bild_format(b)
	if fmt == "":
		return ""
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match fmt:
		"png": err = img.load_png_from_buffer(b)
		"jpg": err = img.load_jpg_from_buffer(b)
		"webp": err = img.load_webp_from_buffer(b)
	if err != OK or img.is_empty() or img.get_width() > HANDY_SEITE or img.get_height() > HANDY_SEITE:
		return ""
	if img.is_compressed():
		img.decompress()
	var name := "handy_%d_%s" % [int(Time.get_unix_time_from_system()), Crypto.new().generate_random_bytes(6).hex_encode()]
	DirAccess.make_dir_recursive_absolute(dir)
	var durchsicht := img.detect_alpha() != Image.ALPHA_NONE
	var pfad := dir.path_join(name + (".png" if durchsicht else ".jpg"))
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8 if durchsicht else Image.FORMAT_RGB8)
	var ok := img.save_png(pfad) if durchsicht else img.save_jpg(pfad, 0.9)
	return pfad if ok == OK else ""


# --- Speichern -----------------------------------------------------------------------------------
# Alle Mosaike in einer Datei: { "v": 1, "mosaike": { "<Quelle>": Mosaik } }. Quelle wie in der
# Quellen-Zeile der Startseite („ps2“, „ordner:f_123“). In der Vorführung bleibt alles im Speicher.
# Raster (cols, rows), Hintergrund und Ordner-Bild (cover) gehören zur Quelle, nicht zur Anordnung:
# Sie gelten auch für das Auto-Mosaik und bleiben beim Neu-Anlegen.

const BLEIBT := ["cover", "cols", "rows", "hintergrund"]

static var _alle := {}
static var _pfad := ""
static var _nur_speicher := false
static var _geladen := false


## Einmal je Lauf laden (die Seite ruft das bei jedem Öffnen).
static func sicher_geladen(pfad: String, nur_speicher := false) -> void:
	if not _geladen:
		laden(pfad, nur_speicher)


static func laden(pfad: String, nur_speicher := false) -> void:
	_pfad = pfad
	_nur_speicher = nur_speicher
	_geladen = true
	_alle = {}
	if nur_speicher or pfad == "":
		return
	var roh: Variant = Config.read_json(pfad, {})
	if roh is Dictionary and (roh as Dictionary).get("mosaike") is Dictionary:
		var m: Dictionary = roh.mosaike
		for key in m.keys():
			if schluessel_ok(str(key)) and m[key] is Dictionary:
				_alle[str(key)] = m[key]


static func schluessel_ok(key: String) -> bool:
	return key != "" and key.length() <= 220 and not key.to_utf8_buffer().has(0)


## Gestaltetes Mosaik einer Quelle (geprüft); {} wenn es keins gibt (dann gilt das Auto-Mosaik).
static func holen(key: String) -> Dictionary:
	if not _alle.has(key):
		return {}
	var d := sauber(_alle[key])
	return d if bool(d.eigen) else {}


## Raster einer Quelle – auch ohne eigene Anordnung (Auto-Mosaik in 10 × 10).
static func raster(key: String) -> Vector2i:
	return raster_von(_alle.get(key, {}))


static func raster_setzen(key: String, ra: Vector2i) -> void:
	_feld(key, "cols", clampi(ra.x, MIN_RASTER, MAX_RASTER))
	_feld(key, "rows", clampi(ra.y, MIN_RASTER, MAX_RASTER))
	speichern()


static func hintergrund(key: String) -> Dictionary:
	var m: Variant = _alle.get(key, {})
	return hintergrund_sauber(m.get("hintergrund")) if m is Dictionary else {}


static func hintergrund_setzen(key: String, h: Dictionary) -> void:
	_feld(key, "hintergrund", hintergrund_sauber(h))
	speichern()


static func _feld(key: String, feld: String, wert: Variant) -> void:
	if not schluessel_ok(key):
		return
	var m: Dictionary = (_alle.get(key) as Dictionary).duplicate(true) if _alle.get(key) is Dictionary else {}
	if wert == null or (wert is Dictionary and (wert as Dictionary).is_empty()):
		m.erase(feld)
	else:
		m[feld] = wert
	if m.is_empty():
		_alle.erase(key)
	else:
		_alle[key] = m


## Anordnung speichern (d leer: zurück zum Auto-Mosaik). Raster, Hintergrund und Ordner-Bild der
## Quelle bleiben; hat d ein Raster, gilt dessen.
static func ablegen(key: String, d: Dictionary) -> void:
	if not schluessel_ok(key):
		return
	var alt: Dictionary = _alle.get(key) if _alle.get(key) is Dictionary else {}
	var neu := {} if d.is_empty() else d.duplicate(true)
	if not d.is_empty():
		neu["eigen"] = true
	for f in BLEIBT:
		if alt.has(f) and not neu.has(f):
			neu[f] = alt[f]
	if neu.is_empty():
		_alle.erase(key)
	else:
		_alle[key] = neu
	speichern()


## Eigenes Ordner-Bild (Cover der Sammlung) – gilt überall, wo der Ordner als Kachel liegt.
static func ordner_bild(fid: String) -> Dictionary:
	var m: Variant = _alle.get("ordner:" + fid, {})
	return bild_sauber(m.get("cover")) if m is Dictionary else {}


static func ordner_bild_setzen(fid: String, b: Dictionary) -> void:
	_feld("ordner:" + fid, "cover", bild_sauber(b))
	speichern()


static func speichern() -> void:
	if _nur_speicher or _pfad == "":
		return
	Config.write_json(_pfad, { "v": 1, "mosaike": _alle })


static func alle() -> Dictionary:
	return _alle
