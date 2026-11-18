extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Spielhüllen je System im Regal (src/room/regal_welt.gd) – je Konsole eine Hülle
## mit Scan (herausgezogen, zur Kamera gedreht) und eine ohne Bild (Uzais Ersatz-Vorderseite).
## Scans nur zum Vergleich von außen: Umgebungsvariable UZAI_SCANS = Ordner mit <system>.png (nie
## im Repo – fremde Logos). Ohne sie bekommt die erste Hülle ein selbst gerechnetes Motiv.
## Schreibt neben die Bilder lagen.json: je Bild das Rechteck der gewählten Hülle auf dem Schirm.
## Aufruf siehe probe_base.gd (--demo).

const SYSTEME := ["ps2", "gc", "wii", "wiiu", "xbox", "xbox360", "ps3", "psp", "switch", "ps1", "dreamcast", "saturn",
	"megadrive", "mastersystem", "n64", "snes", "nes", "nds", "3ds", "gba"]

var _lagen := {}


func _motiv(sid: String) -> String:
	var img := Image.create(400, 560, false, Image.FORMAT_RGB8)
	for y in 560:
		img.fill_rect(Rect2i(0, y, 400, 1), Color("#1d3557").lerp(Color("#e63946"), float(y) / 560.0))
	var p := Config.media_dir().path_join("probe_huellen_" + sid + ".png")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)
	return p


func run() -> void:
	var scans := OS.get_environment("UZAI_SCANS")
	for sid in SYSTEME:
		var bild := scans.path_join(sid + ".png") if scans != "" else ""
		if bild == "" or not FileAccess.file_exists(bild):
			bild = _motiv(sid) if scans == "" else ""
		var mit := { "id": "%s:probe_a" % sid, "title": "Aurora", "system": sid, "source": "disc", "installed": true }
		if bild != "":
			mit["images"] = { "cover": bild }
		Library.games.append(mit)
		Library.games.append({ "id": "%s:probe_b" % sid, "title": "Sternenfeld", "system": sid, "source": "disc", "installed": true })
	if Library.has_method("_reindex"):
		Library.call("_reindex")
	main.goto("games")
	await wait(1.0)
	var gs: Node = main.sections.get("games")
	for sid in SYSTEME:
		gs.open_regal(sid, str(Config.system(sid).get("name", sid)))
		await wait(2.0)
		await _zu(sid + ":probe_a")
		await _bild(sid + "_a")
		await _zu(sid + ":probe_b")
		await _bild(sid + "_b")
		Nav.top_layer().close()
		await wait(0.7)


## Zur Hülle eines Spiels blättern (die Demo bringt eigene Spiele mit).
func _zu(id: String) -> void:
	var l: Node = Nav.top_layer()
	var sp: Array = l.get("_spiele") if l else []
	for k in sp.size():
		if str(sp[k].get("id", "")) == id:
			var d := k - int(l.get("_i"))
			for n in absi(d):
				l.nav_dir("right" if d > 0 else "left")
			break
	await wait(1.8)


## Bild und Rechteck der gewählten Hülle (alle acht Ecken auf den Schirm gerechnet).
func _bild(name: String) -> void:
	await shot(name, 0.2)
	var l: Node = Nav.top_layer()
	var w: Node = l.get("welt") if l else null
	if w == null:
		return
	var h: Node3D = (w.get("_huellen") as Dictionary).get(int(w.get("auswahl")))
	if h == null:
		return
	var cam: Camera3D = w.get("kamera")
	var m: Vector3 = h.get("masse")
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var e := Vector3((i & 1) - 0.5, float((i >> 1) & 1), ((i >> 2) & 1) - 0.5) * Vector3(m.x, m.y, m.z)
		var s := cam.unproject_position(h.global_transform * e)
		lo = lo.min(s)
		hi = hi.max(s)
	# Die Welt liegt in einem SubViewport: auf den Schirm umrechnen.
	var vp := w.get_viewport() as SubViewport
	var k := Vector2(get_viewport().get_visible_rect().size) / Vector2(vp.size) if vp else Vector2.ONE
	_lagen[name] = [lo.x * k.x, lo.y * k.y, hi.x * k.x, hi.y * k.y]
	var f := FileAccess.open(out.path_join("lagen.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_lagen))
	f.close()
