extends "res://src/room/bau_tafel.gd"
## Regal einrichten – Spieleregal, Pokalschrank, Plattenregal – als Tafel wie das Bau-Menü
## (bau_tafel.gd) statt einer flachen Liste: unten die Bereiche (Welche Spiele, Sortierung,
## Darstellung, Hüllen bzw. Welche Pokale), darüber große Kacheln mit den echten Hüllen. Eine Auswahl
## zeigt ihre ersten Cover als Fächer, eine Sortierung, was dann vorn steht, die Darstellung ein
## kleines Brett mit Rücken und Covern, die Hülle je System ihre Form mit einem Cover des Systems.
##
## Was der Cursor wählt, steht schon im Regal (Probe, zimmer_einrichten.gd bau_probe): A übernimmt,
## B nimmt sie zurück und geht zurück. „Selbst einräumen“ öffnet das Raster der Bibliothek,
## „Alle ausräumen“ leert das Regal (X macht es rückgängig). Gezeigt in der Seitenleiste
## (anpassen_ui.gd) an Stelle der Seite, die anpassen.gd seite_regal liefert.

const G := preload("res://src/room/gestalt.gd")
const S := preload("res://src/room/stoffe.gd")
const RInhalt := preload("res://src/room/inhalt.gd")
const Katalog := preload("res://src/room/katalog.gd")

const MAX_COVER := 240            ## so viele Cover merkt sich die Tafel (je Spiel einmal geladen)
const SORT_ZEICHEN := { "zuletzt": "history", "titel": "list", "system": "chip", "spielzeit": "clock", "backlog": "bookmark",
	"genre": "tag", "neu": "spark", "manuell": "move", "stufe": "trophy", "anteil": "pulse", "quelle": "music", "name": "list" }
const POKAL_FARBEN := { "alle": ["bronze", "silber", "gold", "platin"], "ab_gold": ["gold", "platin"], "platin": ["platin"] }

static var _cover := {}           ## Spiel-ID → Texture2D
static var _cover_reihe: Array = []

var moebel := -1                  ## Index des Möbels im Raum
var typ := ""                     ## spieleregal, trophaeenschrank, plattenregal
var seiten: RefCounted            ## anpassen.gd (Namen der Auswahlen)
var _infos := {}                  ## Kachel → { spiele, anzahl } (erst beim Zeichnen gerechnet)
var _gerechnet := 0               ## so viele Kacheln haben in diesem Bild ihre Spiele gerechnet
var _rechnen_bis := 0             ## bis dahin (µs) rechnen weitere noch in diesem Bild, danach im nächsten (kein Ruck)
var _infos_offen := false
var _laedt := {}                  ## Spiel-ID → true, solange das Cover kommt
var _timer: Timer


func _ready() -> void:
	super._ready()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.15
	_timer.timeout.connect(_probe)
	add_child(_timer)
	gewechselt.connect(func(_id: String) -> void: _timer.start())


## Auf ein Möbel einstellen und öffnen (Seite aus anpassen.gd seite_regal).
func zeigen(seite: Dictionary) -> void:
	moebel = int(seite.get("moebel", -1))
	zimmer = seite.get("zimmer")
	seiten = seite.get("seiten")
	typ = str(_it().get("t", ""))
	_kat = 0
	_sel = -1
	_merk.clear()
	_infos.clear()
	oeffnen()


func _it() -> Dictionary:
	var raum: Variant = zimmer.get("raum") if zimmer else null
	if raum is Dictionary and moebel >= 0 and moebel < (raum.moebel as Array).size():
		return raum.moebel[moebel]
	return {}


func _rg() -> Dictionary:
	var it := _it()
	return it.get("rg", G.std_regal(typ))


## Stand ohne offene Probe (Häkchen).
func _rg_stand() -> Dictionary:
	if zimmer and zimmer.has_method("bau_stand"):
		var st: Dictionary = zimmer.call("bau_stand")
		var ml: Array = st.get("moebel", [])
		if moebel >= 0 and moebel < ml.size():
			return (ml[moebel] as Dictionary).get("rg", G.std_regal(typ))
	return _rg()


func _huellen_stand() -> Dictionary:
	if zimmer and zimmer.has_method("bau_huellen"):
		return zimmer.call("bau_huellen")
	return {}


# --- Bereiche und Kacheln ---------------------------------------------------------------------------

## Bereiche je Möbel: [Kennung, Name, Zeichen].
static func gruppen_fuer(t: String) -> Array:
	match t:
		"spieleregal":
			return [["spiele", "Welche Spiele", "games"], ["ordnung", "Sortierung", "sort"], ["look", "Darstellung", "regal"], ["huellen", "Hüllen", "disc"]]
		"trophaeenschrank":
			return [["pokale", "Welche Pokale", "trophy"], ["ordnung", "Sortierung", "sort"]]
		"plattenregal":
			return [["ordnung", "Sortierung", "sort"], ["look", "Darstellung", "regal"]]
	return []


func _gruppen() -> Array:
	return gruppen_fuer(typ)


static func _k(art: String, feld: String, wert: Variant, name: String, abschnitt: String, extra := {}) -> Dictionary:
	var d := { "id": "%s:%s:%s" % [art, feld, str(wert)], "art": art, "feld": feld, "wert": wert, "name": name, "abschnitt": abschnitt,
		"sofort": art in ["regal", "huelle"] }
	d.merge(extra, true)
	return d


## Kacheln eines Bereichs; i: Möbel, t: seine Art, filter: anpassen.gd filter_gruppen (Spieleregal).
static func kacheln(gruppe: String, i: int, t: String, filter: Array, systeme: Array) -> Array:
	var out: Array = []
	match gruppe:
		"spiele":
			out.append(_k("aktion", "", "einraeumen", "Selbst einräumen", "Einräumen"))
			out.append(_k("aktion", "", "ausraeumen", "Alle ausräumen", "Einräumen"))
			for ab in filter:
				var erst := true
				for o in ab[1]:
					var extra := { "reihe": erst, "roh": true }
					# Systeme: mehrere zugleich (A hakt an bzw. ab, keine Probe beim Drüberfahren).
					if str(o[0]).begins_with("system:"):
						extra.merge({ "mehrfach": true, "sid": str(o[0]).substr(7), "sofort": false }, true)
					out.append(_k("regal", "fi", str(o[0]), str(o[1]), str(ab[0]), extra))
					erst = false
		"pokale":
			for p in G.POKAL_FILTER:
				out.append(_k("regal", "fi", str(p[0]), str(p[1]), "Welche Pokale"))
		"ordnung":
			var liste: Array = { "spieleregal": G.SORTIERUNGEN, "trophaeenschrank": G.POKAL_SORT, "plattenregal": G.PLATTEN_SORT }.get(t, [])
			for p in liste:
				out.append(_k("regal", "so", str(p[0]), str(p[1]), "Sortierung"))
			if t == "spieleregal":
				out.append(_k("aktion", "", "hand_weg", "Sortierung zurücksetzen", "Von Hand umgestellt", { "reihe": true }))
		"look":
			var da: Array = G.PLATTEN_DARST if t == "plattenregal" else G.DARSTELLUNGEN
			for p in da:
				out.append(_k("regal", "da", str(p[0]), str(p[1]), "Darstellung"))
			if t == "spieleregal":
				for j in G.DEKO.size():
					out.append(_k("regal", "de", str(G.DEKO[j][0]), str(G.DEKO[j][1]), "Deko", { "reihe": j == 0 }))
				out.append(_k("regal", "ab", true, "Gebrauchsspuren", "Hüllen", { "reihe": true }))
				out.append(_k("regal", "ab", false, "Wie neu", "Hüllen"))
		"huellen":
			for s in systeme:
				for j in G.HUELLEN.size():
					out.append(_k("huelle", str(s[0]), str(G.HUELLEN[j][0]), str(G.HUELLEN[j][1]), str(s[1]), { "reihe": j == 0, "sid": str(s[0]) }))
	for k in out:
		k["moebel"] = i
	return out


## Systeme einer Auswahl („system:a“ bzw. „systeme:a,b“), sonst [].
static func systeme_von(fi: String) -> Array:
	if fi.begins_with("system:"):
		return [fi.substr(7)]
	if fi.begins_with("systeme:"):
		return Array(fi.substr(8).split(",", false))
	return []


## Auswahl nach dem Anhaken bzw. Abhaken eines Systems: eins → „system:a“, mehrere → „systeme:a,b“
## (sortiert), keins mehr → alle Spiele.
static func systeme_umschalten(fi: String, sid: String) -> String:
	var s := systeme_von(fi)
	if sid in s:
		s.erase(sid)
	else:
		s.append(sid)
	s.sort()
	if s.is_empty():
		return "alle"
	return "system:%s" % s[0] if s.size() == 1 else "systeme:%s" % ",".join(s)


## Systeme der Bibliothek (mit eigener Hülle): [[Kennung, Name] …], nach Namen.
static func systeme() -> Array:
	var da := {}
	for g in Library.visible_games():
		var sid := str(g.get("system", ""))
		if sid != "" and G.kennung(sid):
			da[sid] = true
	var out: Array = []
	for sid in da.keys():
		var n := str(Config.system(str(sid)).get("name", ""))
		out.append([str(sid), n if n != "" else Library.Stores.name_of(str(sid))])
	out.sort_custom(func(a: Array, b: Array) -> bool: return str(a[1]).naturalnocasecmp_to(str(b[1])) < 0)
	return out


func _kacheln_fuer(id: String) -> Array:
	var filter: Array = seiten.call("filter_gruppen") if id == "spiele" and seiten and seiten.has_method("filter_gruppen") else []
	return kacheln(id, moebel, typ, filter, systeme() if id == "huellen" else [])


func _aktiv(k: Dictionary) -> bool:
	match str(k.get("art", "")):
		"regal":
			var rg := _rg_stand()
			if bool(k.get("mehrfach", false)):
				return str(k.sid) in systeme_von(str(rg.get("fi", "")))
			return rg.get(str(k.feld)) == k.wert
		"huelle":
			return str(_huellen_stand().get(str(k.sid), "auto")) == str(k.wert)
	return false


func _texte(k: Dictionary) -> Array:
	if k.is_empty():
		return ["", ""]
	var titel := str(k.name) if bool(k.get("roh", false)) else tr(str(k.name))
	var teile: Array = [str(k.abschnitt) if bool(k.get("roh", false)) or str(k.art) == "huelle" else tr(str(k.abschnitt))]
	if str(k.art) == "regal" and str(k.feld) == "fi" and typ == "spieleregal":
		teile.append(tr("%d Spiele") % int(_info(k).anzahl))
	if _aktiv(k):
		teile.append(tr("im Regal"))
	return [titel, " · ".join(teile)]


## Zur Kachel die ersten Spiele (Cover) und wie viele es sind – einmal gerechnet. Je Bild eine Kachel und
## weitere nur, solange RECHEN_MS nicht um sind: Früher waren es fest vier je Bild, und jede wählt und
## sortiert die Bibliothek (gemessen bei 2250 Spielen: 20 ms je Kachel, vor dem Umbau des Sortierens 80 bis
## 150 ms) – das Öffnen der Tafel stand dann mehrere Bilder lang.
const RECHEN_MS := 5.0

func _info(k: Dictionary) -> Dictionary:
	if _infos.has(k.id):
		return _infos[k.id]
	if _gerechnet > 0 and Time.get_ticks_usec() > _rechnen_bis:
		# Im nächsten Bild weiter – auch wenn die Tafel gerade ruht (nach A: die Kacheln rechnen neu).
		_infos_offen = true
		set_process(true)
		return { "spiele": [], "anzahl": 0 }
	_gerechnet += 1
	var rg := _rg_stand().duplicate()
	var spiele: Array = []
	match str(k.get("art", "")):
		"regal":
			rg[str(k.feld)] = k.wert
			if typ == "spieleregal":
				spiele = RInhalt.spiele(rg)
			elif typ == "plattenregal":
				spiele = RInhalt.platten(rg)
			elif typ == "trophaeenschrank":
				spiele = RInhalt.pokale(rg).map(func(p: Dictionary) -> Dictionary: return p.spiel)
		"huelle":
			spiele = Library.visible_games().filter(func(g: Dictionary) -> bool: return str(g.get("system", "")) == str(k.sid)).slice(0, 3)
		"aktion":
			spiele = RInhalt.spiele(_rg_stand())
	# Darstellung, Deko, Abnutzung eines leeren Regals: mit den Spielen der Bibliothek gezeigt.
	if spiele.is_empty() and typ == "spieleregal" and str(k.get("feld", "")) in ["da", "de", "ab"]:
		spiele = RInhalt.spiele({ "fi": "alle", "so": "zuletzt" })
	var d := { "spiele": spiele.slice(0, 12), "anzahl": spiele.size() }
	_infos[k.id] = d
	return d


# --- Probe und Tasten -------------------------------------------------------------------------------

## Die gewählte Kachel steht als Probe im Regal (erst nach einer Bewegung, kurz ruhig).
func _probe() -> void:
	var k := kachel()
	if not _offen or not _angefasst or not bool(k.get("sofort", false)) or zimmer == null or not zimmer.has_method("bau_probe"):
		return
	zimmer.call("bau_probe", k)
	if zimmer.has_method("_hinweise_auffrischen"):
		zimmer.call("_hinweise_auffrischen")


func _verlassen() -> void:
	_timer.stop()
	if zimmer and zimmer.has_method("bau_verwerfen"):
		zimmer.call("bau_verwerfen")


func auffrischen() -> void:
	_infos.clear()
	super.auffrischen()


## Tasten (true: erledigt); B, X und das Schließen erledigt die Seitenleiste.
func taste(cmd: String) -> bool:
	var k := kachel()
	match cmd:
		"lb", "rb":
			kategorie(-1 if cmd == "lb" else 1)
			return true
		"y":
			Sfx.play("bump")
			return true
		"a":
			match str(k.get("art", "")):
				"aktion":
					# Eine Probe, die noch steht, war nicht gewollt: erst zurück, dann ein- bzw. ausräumen.
					_verlassen()
					if str(k.wert) == "einraeumen":
						zimmer.call("regal_einraeumen", moebel)
					elif str(k.wert) == "hand_weg":
						if not (_rg().get("pl", {}) as Dictionary).is_empty() and zimmer.has_method("regal_hand_weg"):
							zimmer.call("regal_hand_weg", moebel)
							Sfx.play("select")
							auffrischen()
						else:
							Sfx.play("bump")
					elif RInhalt.spiele(_rg()).is_empty() or str(_rg().get("fi", "")) != "eigene":
						Sfx.play("bump")
					else:
						zimmer.call("regal_ausraeumen", moebel)
						auffrischen()
				"regal", "huelle":
					if bool(k.get("mehrfach", false)):
						k = k.duplicate()
						k["wert"] = systeme_umschalten(str(_rg_stand().get("fi", "")), str(k.sid))
					elif not bool(zimmer.call("bau_offen")) and _aktiv(k):
						Sfx.play("bump")
						return true
					_timer.stop()
					zimmer.call("bau_probe", k)
					zimmer.call("bau_uebernehmen")
					Sfx.play("select")
					_angefasst = false
					_infos.clear()
			return true
	return false


## Tastenzeile: A, X, B (zurueck: Wort für B) – LB/RB stehen an der Leiste.
func hinweise(zurueck := "Fertig") -> Array:
	var h: Array = []
	var k := kachel()
	match str(k.get("art", "")):
		"aktion":
			h.append(["a", { "einraeumen": "Einräumen", "hand_weg": "Zurücksetzen" }.get(str(k.wert), "Ausräumen")])
		"regal", "huelle":
			if bool(k.get("mehrfach", false)):
				h.append(["a", "Abwählen" if _aktiv(k) else "Dazunehmen"])
			elif (zimmer and bool(zimmer.call("bau_offen"))) or not _aktiv(k):
				h.append(["a", "Übernehmen"])
	var rueck: Variant = zimmer.get("_rueck") if zimmer else null
	if rueck is Array and not (rueck as Array).is_empty():
		h.append(["x", "Rückgängig"])
	h.append(["b", zurueck])
	return h


# --- Cover ------------------------------------------------------------------------------------------

func _cover_von(g: Dictionary) -> Texture2D:
	var id := str(g.get("id", ""))
	if id == "":
		return null
	if _cover.has(id):
		return _cover[id]
	if not _laedt.has(id):
		_laedt[id] = true
		RInhalt.cover_textur(self, g, Vector2i(216, 288), func(tex: Texture2D) -> void:
			_laedt.erase(id)
			if tex == null:
				return
			_cover[id] = tex
			_cover_reihe.append(id)
			while _cover_reihe.size() > MAX_COVER:
				_cover.erase(_cover_reihe.pop_front())
			if is_inside_tree():
				set_process(true)
				queue_redraw())
	return null


## Eine Hülle von vorn: Cover (sonst die Farbe der Hülle), weicher Schatten, Lichtkante.
func _huelle(g: Dictionary, r: Rect2, a: float, winkel := 0.0) -> void:
	draw_set_transform(r.get_center(), winkel, Vector2.ONE)
	var lokal := Rect2(-r.size * 0.5, r.size)
	draw_rect(Rect2(lokal.position + Vector2(3, 5), lokal.size), Color(0, 0, 0, 0.32 * a))
	var tex := _cover_von(g)
	if tex:
		draw_texture_rect(tex, lokal, false, Color(1, 1, 1, a))
	else:
		draw_rect(lokal, Color(S.huellen_farbe(g), a))
	draw_rect(Rect2(lokal.position, Vector2(lokal.size.x, 1.5)), Color(1, 1, 1, 0.22 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Zeichnen ---------------------------------------------------------------------------------------

func _draw() -> void:
	_gerechnet = 0
	_rechnen_bis = Time.get_ticks_usec() + int(RECHEN_MS * 1000.0)
	super._draw()


func _jede_runde(_dt: float) -> bool:
	var weiter := _infos_offen
	_infos_offen = false
	return weiter

func _kachel_zeichnen(k: Dictionary, _i: int, r: Rect2, ia: float, gew: bool, rc: int) -> void:
	var art := str(k.get("art", ""))
	if art == "aktion":
		var ein := str(k.wert) == "einraeumen"
		if str(k.wert) == "hand_weg":
			_zeichen_kachel(r, ia, gew, rc, "refresh", "Automatisch", Stil.TINTE)
			return
		_zeichen_kachel(r, ia, gew, rc, "add" if ein else "trash", "Einräumen" if ein else "Ausräumen",
			Stil.TINTE if ein else UzTheme.col("danger_text"))
		return
	_grund(r, ia, gew, rc)
	draw_texture_rect(_schein(), Rect2(r.position + Vector2(r.size.x * 0.1, 0), r.size * Vector2(0.8, 0.75)), false, Color(1.0, 0.9, 0.76, 0.1 * ia))
	match art:
		"huelle":
			_huelle_kachel(k, r, ia)
		"regal":
			match str(k.feld):
				"fi":
					if typ == "trophaeenschrank":
						_pokale(r, ia, POKAL_FARBEN.get(str(k.wert), ["gold"]))
						_wort_unten(r, ia, str(k.name), 14.0)
					else:
						_faecher(_info(k).spiele, r, ia)
						_wort_unten(r, ia, str(k.name), 14.0, bool(k.get("roh", false)))
				"so":
					_sortierung(k, r, ia)
				"da", "de":
					_brett(k, r, ia)
				"ab":
					_abnutzung(k, r, ia)


## Bis zu drei Cover als Fächer, das erste vorn.
func _faecher(spiele: Array, r: Rect2, a: float) -> void:
	var h := r.size.y * 0.56
	var w := h * 0.75
	var m := Vector2(r.get_center().x, r.position.y + 12.0 + h * 0.5)
	if spiele.is_empty():
		draw_rect(Rect2(m - Vector2(w, h) * 0.5, Vector2(w, h)), Color(Stil.TINTE, 0.06 * a))
		draw_rect(Rect2(m - Vector2(w, h) * 0.5, Vector2(w, h)), Color(Stil.LINIE, a), false, 1.0)
		return
	var n := mini(spiele.size(), 3)
	for j in range(n - 1, -1, -1):
		var seite := 0.0 if j == 0 else (-1.0 if j == 1 else 1.0)
		var rr := Rect2(m + Vector2(seite * w * 0.42, 3.0 * absf(seite)) - Vector2(w, h) * 0.5, Vector2(w, h))
		_huelle(spiele[j], rr, a * (1.0 if j == 0 else 0.85), deg_to_rad(9.0 * seite))


## Sortierung: ihr Zeichen und was dann vorn steht (drei kleine Cover).
func _sortierung(k: Dictionary, r: Rect2, a: float) -> void:
	var ic := str(SORT_ZEICHEN.get(str(k.wert), "sort"))
	draw_texture_rect(Icons.tex(ic, 30), Rect2(r.get_center().x - 15.0, r.position.y + 14.0, 30, 30), false, Color(Stil.TINTE, 0.9 * a))
	if typ == "plattenregal":
		var pl: Array = _info(k).spiele
		for j in mini(pl.size(), 3):
			var q := Rect2(r.position.x + 20.0 + j * 38.0, r.position.y + 58.0, 32.0, 32.0)
			draw_rect(q, Color(pl[j].get("farbe", Color("#5c3b2e")), a))
			draw_circle(q.get_center(), 6.0, Color(0, 0, 0, 0.35 * a), true, -1.0, true)
	else:
		var sp: Array = _info(k).spiele
		for j in mini(sp.size(), 3):
			_huelle(sp[j], Rect2(r.position.x + 22.0 + j * 36.0, r.position.y + 54.0, 30.0, 40.0), a)
	_wort_unten(r, a, str(k.name), 14.0)


## Kleines Brett: Rücken, Cover, Deko – so steht es dann im Regal.
func _brett(k: Dictionary, r: Rect2, a: float) -> void:
	var spiele: Array = _info(k).spiele
	var boden := r.position.y + r.size.y * 0.7
	var holz := Color("#6b4a32")
	draw_rect(Rect2(r.position.x + 10.0, r.position.y + 18.0, r.size.x - 20.0, boden - r.position.y - 18.0), Color(0, 0, 0, 0.18 * a))
	var da := str(_rg().get("da", "gemischt")) if str(k.feld) == "de" else str(k.wert)
	var x := r.position.x + 16.0
	var ende := r.end.x - 16.0
	var deko := str(k.wert) if str(k.feld) == "de" else str(_rg().get("de", "wenig"))
	if typ == "plattenregal":
		for j in 8:
			var c := Color.from_hsv(fmod(0.08 + j * 0.13, 1.0), 0.45, 0.62)
			if da == "kiste":
				var q := Rect2(x + j * 9.0, boden - 54.0 + j * 1.5, 50.0, 50.0)
				draw_rect(q, Color(c, a))
				draw_rect(q, Color(0, 0, 0, 0.2 * a), false, 1.0)
			else:
				draw_rect(Rect2(x + j * 12.0, boden - 56.0, 9.0, 56.0), Color(c, a))
	else:
		var j := 0
		var cover_da := 0
		while x < ende - 8.0:
			var g: Dictionary = spiele[j % maxi(spiele.size(), 1)] if not spiele.is_empty() else {}
			var cover := da == "cover" or (da == "gemischt" and j == 3 and cover_da == 0)
			if cover and x + 36.0 <= ende:
				_huelle(g, Rect2(x, boden - 50.0, 36.0, 48.0), a, -0.04)
				x += 40.0
				cover_da += 1
			else:
				var hh := 46.0 + float((j * 7) % 9)
				draw_rect(Rect2(x, boden - hh, 7.0, hh), Color(S.huellen_farbe(g) if not g.is_empty() else Color("#2b2d33"), a))
				draw_rect(Rect2(x, boden - hh, 1.0, hh), Color(1, 1, 1, 0.12 * a))
				x += 8.0
			j += 1
			if deko != "keine" and j == 6:
				# Deko zwischen den Spielen: eine kleine Pflanze, bei „viel“ noch eine Kugel.
				draw_rect(Rect2(x + 2.0, boden - 12.0, 14.0, 12.0), Color("#c97b54", a))
				draw_circle(Vector2(x + 9.0, boden - 20.0), 9.0, Color("#5d7a5a", a), true, -1.0, true)
				x += 20.0
				if deko == "viel":
					draw_circle(Vector2(x + 7.0, boden - 7.0), 7.0, Color("#d9cbb3", a), true, -1.0, true)
					x += 16.0
	draw_rect(Rect2(r.position.x + 8.0, boden, r.size.x - 16.0, 6.0), Color(holz, a))
	draw_rect(Rect2(r.position.x + 8.0, boden, r.size.x - 16.0, 1.5), Color(holz.lightened(0.3), a))
	_wort_unten(r, a, str(k.name), 14.0)


func _abnutzung(k: Dictionary, r: Rect2, a: float) -> void:
	var ab := bool(k.wert)
	# Das meistgespielte der ersten Spiele zeigt es am deutlichsten.
	var g: Dictionary = {}
	for s in _info(k).spiele:
		if g.is_empty() or Library.playtime(s) > Library.playtime(g):
			g = s
	var hr := Rect2(r.get_center().x - 33.0, r.position.y + 14.0, 66.0, 88.0)
	_huelle(g, hr, a)
	if ab:
		# Abgegriffen: helle Kanten, ein paar Kratzer.
		draw_rect(Rect2(hr.position, Vector2(hr.size.x, 3.0)), Color(1, 1, 1, 0.35 * a))
		draw_rect(Rect2(hr.end.x - 3.0, hr.position.y, 3.0, hr.size.y), Color(1, 1, 1, 0.25 * a))
		for j in 4:
			var p := hr.position + Vector2(10.0 + j * 13.0, 20.0 + (j * 23) % 50)
			draw_line(p, p + Vector2(9, 3), Color(1, 1, 1, 0.4 * a), 1.0, true)
	_wort_unten(r, a, "Gebrauchsspuren" if ab else "Wie neu", 14.0)


## Hülle eines Systems in ihrer Form, mit einem Cover des Systems.
func _huelle_kachel(k: Dictionary, r: Rect2, a: float) -> void:
	var sp: Array = _info(k).spiele
	var g: Dictionary = sp[0] if not sp.is_empty() else { "system": str(k.sid) }
	var art := str(k.wert)
	if art == "auto":
		art = RInhalt.huellen_art(g, {})
	var mass: Array = RInhalt.HUELLEN.get(art, RInhalt.HUELLEN.dvd)
	var verh := float(mass[2]) / float(mass[1])
	var h := r.size.y * 0.6
	var w := h * verh
	if w > r.size.x * 0.66:
		w = r.size.x * 0.66
		h = w / verh
	var hr := Rect2(r.get_center().x - w * 0.5, r.position.y + 12.0 + (r.size.y * 0.6 - h), w, h)
	match art:
		"modul":
			draw_rect(Rect2(hr.position + Vector2(3, 5), hr.size), Color(0, 0, 0, 0.3 * a))
			draw_rect(hr, Color("#3a3c42", a))
			_huelle(g, hr.grow_individual(-6.0, -14.0, -6.0, -6.0), a)
			for j in 4:
				draw_rect(Rect2(hr.position.x + 8.0 + j * 7.0, hr.position.y + 4.0, 4.0, 6.0), Color(0, 0, 0, 0.35 * a))
		"jewel":
			_huelle(g, hr, a)
			draw_rect(Rect2(hr.position, Vector2(6.0, hr.size.y)), Color(0.06, 0.06, 0.07, 0.9 * a))
			draw_rect(hr, Color(1, 1, 1, 0.3 * a), false, 1.5)
		_:
			draw_rect(Rect2(hr.position + Vector2(3, 5), hr.size), Color(0, 0, 0, 0.3 * a))
			draw_rect(hr.grow(3.0), Color("#c8312c", a) if str(k.sid) == "switch" else Color(0.07, 0.07, 0.08, a))
			_huelle(g, hr, a)
	_wort_unten(r, a, str(k.name), 14.0)


func _pokale(r: Rect2, a: float, stufen: Array) -> void:
	var farben := { "bronze": RInhalt.BRONZE, "silber": RInhalt.SILBER, "gold": RInhalt.GOLD, "platin": RInhalt.PLATIN }
	var n := stufen.size()
	var gr := 64.0 if n == 1 else (48.0 if n == 2 else 34.0)
	var x0 := r.get_center().x - (n * gr + (n - 1) * 4.0) * 0.5
	for j in n:
		var c: Color = farben.get(str(stufen[j]), RInhalt.GOLD)
		var q := Rect2(x0 + j * (gr + 4.0), r.position.y + 58.0 - gr * 0.5, gr, gr)
		draw_texture_rect(_schein(), q.grow(gr * 0.3), false, Color(c, 0.35 * a))
		draw_texture_rect(Icons.tex("trophy", int(gr)), q, false, Color(c, a))
