extends "res://tests/probe_base.gd"
## Arbeitsspeicher und Ruckler je Bereich (Speicherplatz prüft probe_speicher.gd): Zeile „SPEICHER <schritt> …“
## mit RSS (Prozess, Linux), Godot-Speicher (static), Texturen/Puffer auf der Grafikkarte, Objekte/Ressourcen/Knoten
## und den Bildzeiten des Schritts (längstes Bild, dessen Skript-Rechenzeit, Bilder über 50 und 100 ms). Am Ende die
## größten Texturen im Baum. docs/LADEN.md.
##
##   UZAI_DATA=<leer> xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##       -- --demo --no-boot --uzai-script=res://tests/probe_arbeitsspeicher.gd --uzai-out=<ordner> [--uzai-runden=2]
##
## Werte unter xvfb (Software-Grafik) sind nicht die von Windows, aber Vergleiche vorher/nachher und
## zwischen Bereichen stimmen: Was hier wächst, wächst auch dort.

var _bilder: Array = []      ## Bildzeiten (ms) seit dem letzten Schritt
var _rechnen: Array = []     ## davon Rechenzeit der Skripte (Performance.TIME_PROCESS, ms)
var _t := 0


func run() -> void:
	get_tree().process_frame.connect(_bild)
	var runden := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-runden="):
			runden = maxi(1, int(a.substr(14)))
	await _messen("start", 1.0)
	for r in runden:
		var n := "" if runden == 1 else "%d." % (r + 1)
		for sec in ["games", "shop", "movies", "videos", "music", "apps", "settings"]:
			main.goto(sec)
			await _messen(n + sec, 3.0)
		main.goto("games")
		await _messen(n + "zurueck", 2.0)
		main.open_room(true)
		await _messen(n + "zimmer", 8.0)
		Nav._fire("b")
		await wait(1.0)
		Nav._fire("b")
		await _messen(n + "zimmer_zu", 4.0)
	await _gross()


func _bild() -> void:
	var t := Time.get_ticks_usec()
	if _t > 0:
		_bilder.append((t - _t) / 1000.0)
		_rechnen.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_t = t


func _messen(name: String, sec: float) -> void:
	_bilder.clear()
	_rechnen.clear()
	await wait(sec)
	var lang := 0.0
	var rechnen := 0.0
	for ms in _rechnen:
		rechnen = maxf(rechnen, ms)
	var ueber50 := 0
	var ueber100 := 0
	for ms in _bilder:
		lang = maxf(lang, ms)
		ueber50 += 1 if ms > 50.0 else 0
		ueber100 += 1 if ms > 100.0 else 0
	var mb := func(b: float) -> String: return "%.0f" % (b / 1048576.0)
	print("SPEICHER %-14s rss=%s static=%s tex=%s buf=%s vram=%s obj=%d res=%d knoten=%d waisen=%d bilder=%d lang=%.0fms skript=%.0fms >50=%d >100=%d media=%d/%sMB" % [
		name, _rss(), mb.call(Performance.get_monitor(Performance.MEMORY_STATIC)),
		mb.call(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		mb.call(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		mb.call(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		_bilder.size(), lang, rechnen, ueber50, ueber100, Media._tex.size(), mb.call(float(Media._tex_total))])


func _rss() -> String:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	while f != null and not f.eof_reached():
		var zeile := f.get_line()
		if zeile.begins_with("VmRSS:"):
			return "%d" % int(int(zeile.split(":")[1].strip_edges().split(" ")[0]) / 1024)
	return "?"


## Die größten Texturen, die gerade im Baum hängen (geschätzt: Breite × Höhe × 4, mit Mipmaps × 1,33).
func _gross() -> void:
	var seen := {}
	_sammeln(get_tree().root, seen)
	var liste: Array = seen.values()
	liste.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var summe := 0
	for e in liste:
		summe += int(e[0])
	print("TEXTUREN im Baum: %d, zusammen ~%d MB" % [liste.size(), summe / 1048576])
	for e in liste.slice(0, 25):
		print("TEXTUR %6d KB  %s" % [int(e[0]) / 1024, str(e[1])])


func _sammeln(n: Node, seen: Dictionary) -> void:
	var texs: Array = []
	for p in ["texture", "icon", "texture_normal"]:
		var v: Variant = n.get(p) if p in n else null
		if v is Texture2D:
			texs.append(v)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			_mat_tex(mi.get_active_material(i), texs)
	for t in texs:
		var tex := t as Texture2D
		var rid := tex.get_rid()
		if not rid.is_valid() or seen.has(rid):
			continue
		var w := tex.get_width()
		var h := tex.get_height()
		var name := tex.resource_path if tex.resource_path != "" else ("%s %dx%d (%s)" % [tex.get_class(), w, h, str(tex.get_meta("uz_src", n.get_path()))])
		seen[rid] = [w * h * 4, name]
	for c in n.get_children():
		_sammeln(c, seen)


func _mat_tex(m: Material, out: Array) -> void:
	if m is BaseMaterial3D:
		for p in ["albedo_texture", "normal_texture", "roughness_texture", "emission_texture", "orm_texture"]:
			var v: Variant = m.get(p)
			if v is Texture2D:
				out.append(v)
	elif m is ShaderMaterial:
		for u in (m as ShaderMaterial).get_property_list():
			if str(u.name).begins_with("shader_parameter/"):
				var v: Variant = m.get(u.name)
				if v is Texture2D:
					out.append(v)
