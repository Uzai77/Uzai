extends RefCounted
## Installierte Spiele aus der EA app (früher Origin). Uzai liest nur, was die EA app, Origin und
## die Spiele selbst auf den PC legen – ohne Internet, ohne Konto, ohne etwas zu ändern:
##   - je Spiel __Installer\installerdata.xml im Spielordner (Titel, Inhalts-IDs, Programmdatei),
##   - die Spielordner aus der Registry („Install Dir“ unter EA Games / Electronic Arts /
##     Origin Games, dazu Deinstallations-Einträge von Electronic Arts; liest der Windows-Helfer),
##   - die Origin-Manifeste ProgramData\Origin\LocalContent\*\*.mfst (Angebots-ID und Ordner),
##   - die üblichen Spielordner (Program Files\EA Games, Origin Games).
## Gestartet wird über den Link der EA app (origin2://, notfalls link2ea://), damit Anmeldung und
## Kopierschutz wie gewohnt laufen; ohne Link die Programmdatei selbst. Den verschlüsselten
## Installationsstand der EA app (ProgramData\EA Desktop\…\IS) liest Uzai nicht.

const EpicScanner := preload("res://src/library/epic_scanner.gd")
const SU := preload("res://src/library/store_util.gd")
const Gog := preload("res://src/library/gog_scanner.gd")

const DEFAULT_ROOTS := [
	"C:/Program Files/EA Games",
	"C:/Program Files (x86)/EA Games",
	"C:/Program Files (x86)/Origin Games",
	"C:/Program Files/Origin Games",
]
const INSTALLER_DATA := "__Installer/installerdata.xml"


## Alle installierten Spiele.
## reg: Spielordner aus der Registry [{ dir, name }] (Helfer-Befehl „ea-games“),
## protos: { origin2, link2ea } – welche Links angemeldet sind ({} = unbekannt, dann origin2),
## skip: Ordner, die schon eine andere Quelle zeigt (Epic), pd/roots: für Tests austauschbar.
static func scan(reg: Array = [], protos: Dictionary = {}, skip: Array = [], pd := "", roots: Array = DEFAULT_ROOTS) -> Array:
	var cands := {}        ## Ordner (klein) → { dir, name, ids }
	var order: Array = []
	var blocked := {}      ## über Steam oder Epic gekaufte EA-Spiele: startet die jeweilige Quelle
	for m in origin_manifests((pd if pd != "" else EpicScanner.program_data()).path_join("Origin/LocalContent")):
		if str(m.platform) != "":
			blocked[dir_key(str(m.dir))] = true
			continue
		_add(cands, order, str(m.dir), "", [str(m.id)] if str(m.id) != "" else [])
	for r in reg:
		if r is Dictionary:
			_add(cands, order, str(r.get("dir", "")), str(r.get("name", "")), [])
	for root in roots:
		if not DirAccess.dir_exists_absolute(str(root)):
			continue
		for sub in DirAccess.get_directories_at(str(root)):
			_add(cands, order, str(root).path_join(sub), "", [])
	var skip_keys := {}
	for s in skip:
		skip_keys[dir_key(str(s))] = true
	var proto := pick_proto(protos)
	var out: Array = []
	var seen := {}
	for k in order:
		var c: Dictionary = cands[k]
		if blocked.has(k) or skip_keys.has(k) or str(k).contains("/steamapps/"):
			continue
		var xml := str(c.dir).path_join(INSTALLER_DATA)
		if not FileAccess.file_exists(xml):
			continue
		var g := entry(parse_installer_data(FileAccess.get_file_as_string(xml), str(c.dir)), str(c.dir), str(c.name), c.ids, proto)
		if g.is_empty() or seen.has(str(g.id)):
			continue
		seen[str(g.id)] = true
		g["install_time"] = FileAccess.get_modified_time(xml)
		out.append(g)
	return out


static func _add(cands: Dictionary, order: Array, dir: String, name: String, ids: Array) -> void:
	var d := dir.replace("\\", "/").strip_edges().trim_suffix("/")
	if d == "":
		return
	var k := dir_key(d)
	if not cands.has(k):
		cands[k] = { "dir": d, "name": "", "ids": [] }
		order.append(k)
	var c: Dictionary = cands[k]
	if str(c.name) == "" and name != "":
		c["name"] = name
	for i in ids:
		if not (c.ids as Array).has(i):
			(c.ids as Array).append(i)


static func dir_key(d: String) -> String:
	return d.replace("\\", "/").strip_edges().trim_suffix("/").to_lower()


## Welcher Link startet Spiele? origin2 können EA app und Origin, link2ea nur die EA app.
static func pick_proto(protos: Dictionary) -> String:
	if protos.is_empty() or bool(protos.get("origin2", false)):
		return "origin2"
	if bool(protos.get("link2ea", false)):
		return "link2ea"
	return ""


## Rein: aus den Angaben des Spielordners ein Spiel. {} ohne Programmdatei und ohne ID.
static func entry(info: Dictionary, dir: String, reg_name := "", extra_ids: Array = [], proto := "origin2") -> Dictionary:
	var ids: Array = (info.get("ids", []) as Array).duplicate()
	for i in extra_ids:
		if str(i) != "" and not ids.has(str(i)):
			ids.append(str(i))
	# Aus lokalen Manifesten (auch eines anderen Windows-Kontos): Programmdatei nur als gültiger lokaler Pfad mit .exe
	# (keine Freigabe, kein „..“), Parameter nur in der Form, die auch GOG annimmt – sonst startete _launch_exe sie roh.
	var exe := str(info.get("exe", ""))
	if exe != "" and (SU.norm_path(exe) == "" or exe.get_extension().to_lower() != "exe"):
		exe = ""
	if SU.norm_path(dir) == "":
		return {}
	if ids.is_empty() and exe == "":
		return {}
	var title := EpicScanner.clean_title(str(info.get("title", "")))
	if title == "":
		title = EpicScanner.clean_title(reg_name)
	if title == "":
		title = dir.get_file()
	var g := {
		"id": "ea:%s" % (str(ids[0]) if not ids.is_empty() else dir.to_lower().md5_text().substr(0, 14)),
		"title": title,
		"system": "ea",
		"source": "ea",
		"ea": { "ids": ids, "proto": proto },
		"install_dir": dir,
		"installed": true,
	}
	if exe != "":
		g["path"] = exe
	var args := str(info.get("args", ""))
	if args != "" and SU.id_ok(args, Gog.ARGS_RE) != "" and args.count("\"") % 2 == 0:
		g["args"] = args
	return g


## Rein: installerdata.xml (DiP-Manifest der EA app und von Origin, alte und neue Form) →
## { title, ids, exe, args }. Titel bevorzugt deutsch, sonst englisch, sonst der erste.
static func parse_installer_data(text: String, dir: String) -> Dictionary:
	var xp := XMLParser.new()
	if text == "" or xp.open_buffer(text.trim_prefix("\ufeff").to_utf8_buffer()) != OK:
		return {}
	var stack: Array = []
	var titles := {}
	var first_title := ""
	var ids: Array = []
	var launchers: Array = []
	var cur := {}
	var locale := ""
	while xp.read() == OK:
		var t := xp.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := xp.get_node_name().to_lower()
			if xp.has_attribute("locale"):
				locale = xp.get_named_attribute_value_safe("locale").to_lower()
			if n == "launcher":
				cur = {}
			if xp.is_empty():
				continue
			stack.append(n)
		elif t == XMLParser.NODE_ELEMENT_END:
			var n2 := xp.get_node_name().to_lower()
			if n2 == "launcher":
				launchers.append(cur)
				cur = {}
			if not stack.is_empty():
				stack.pop_back()
		elif t == XMLParser.NODE_TEXT or t == XMLParser.NODE_CDATA:
			var v := xp.get_node_data().strip_edges()
			if v == "" or stack.is_empty():
				continue
			var top: String = stack[-1]
			var parent: String = stack[-2] if stack.size() > 1 else ""
			if "launcher" in stack:
				match top:
					"filepath": cur["path"] = v
					"parameters": cur["args"] = v
					"trial": cur["trial"] = v == "1" or v.to_lower() == "true"
					"requires64bitos": cur["x64"] = v == "1" or v.to_lower() == "true"
			elif top == "contentid":
				if not ids.has(v):
					ids.append(v)
			elif top == "gametitle" or (top == "title" and parent == "localeinfo"):
				if not titles.has(locale):
					titles[locale] = v
				if first_title == "":
					first_title = v
	var title := str(titles.get("de_de", titles.get("en_us", first_title)))
	var pick := {}
	for l in launchers:
		if bool(l.get("trial", false)) or str(l.get("path", "")) == "":
			continue
		if pick.is_empty() or (bool(l.get("x64", false)) and not bool(pick.get("x64", false))):
			pick = l
	return {
		"title": title,
		"ids": ids,
		"exe": resolve_path(str(pick.get("path", "")), dir) if not pick.is_empty() else "",
		"args": str(pick.get("args", "")),
	}


## Rein: Pfad aus installerdata.xml. Vorn steht meist der Registry-Wert des Spielordners in
## eckigen Klammern („[HKEY_LOCAL_MACHINE\SOFTWARE\EA Games\X\Install Dir]bin\x.exe“).
static func resolve_path(raw: String, dir: String) -> String:
	var p := raw.strip_edges()
	if p == "":
		return ""
	if p.begins_with("["):
		var close := p.find("]")
		p = p.substr(close + 1) if close > 0 else ""
		p = p.replace("\\", "/").trim_prefix("/")
		return dir.path_join(p) if p != "" else ""
	p = p.replace("\\", "/")
	if p.length() > 1 and p[1] == ":":
		return p
	return dir.path_join(p.trim_prefix("/"))


## Origin-Manifeste (*.mfst, eine bzw. zwei Ebenen tief) → [{ id, dir, state, platform }].
static func origin_manifests(root: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	var dirs: Array = [root]
	for sub in DirAccess.get_directories_at(root):
		dirs.append(root.path_join(sub))
	for d in dirs:
		for f in DirAccess.get_files_at(str(d)):
			if f.get_extension().to_lower() == "mfst":
				var m := parse_mfst(FileAccess.get_file_as_string(str(d).path_join(f)))
				if str(m.get("dir", "")) != "":
					out.append(m)
	return out


## Rein: ein Origin-Manifest (eine Zeile wie eine URL-Abfrage: „?id=OFB-EAST%3a109552316&
## dipinstallpath=C%3a%5cGames%5cX%5c&…“). platform: „steam“/„epic“, wenn das Spiel dort gekauft
## wurde (id endet auf @steam bzw. @epic).
static func parse_mfst(text: String) -> Dictionary:
	var q := text.strip_edges().trim_prefix("\ufeff")
	q = q.trim_prefix("?")
	var kv := {}
	for part in q.split("&", false):
		var p := part.split("=", true, 1)
		if p.size() == 2:
			kv[p[0].to_lower()] = percent_decode(p[1].replace("+", " "))
	var id := str(kv.get("id", ""))
	var platform := ""
	if id.contains("@"):
		platform = id.get_slice("@", 1).to_lower()
		id = id.get_slice("@", 0)
	var dir := str(kv.get("dipinstallpath", kv.get("installpath", ""))).replace("\\", "/").trim_suffix("/")
	return { "id": id, "dir": dir, "state": str(kv.get("currentstate", "")), "platform": platform }


## Rein: %xx-Kodierung auflösen. Origin schreibt klein („%3a%5c“), das versteht uri_decode() nicht.
static func percent_decode(s: String) -> String:
	if not s.contains("%"):
		return s
	var src := s.to_utf8_buffer()
	var out := PackedByteArray()
	var i := 0
	while i < src.size():
		var c := src[i]
		if c == 37 and i + 2 < src.size():
			var hx := src.slice(i + 1, i + 3).get_string_from_ascii()
			if hx.is_valid_hex_number():
				out.append(hx.hex_to_int())
				i += 3
				continue
		out.append(c)
		i += 1
	return out.get_string_from_utf8()


## Link, über den die EA app (bzw. Origin) das Spiel startet; "" = Programmdatei direkt starten.
static func launch_uri(game: Dictionary) -> String:
	var e: Dictionary = game.get("ea", {})
	var ids: Array = e.get("ids", [])
	if ids.is_empty():
		return ""
	match str(e.get("proto", "origin2")):
		"origin2":
			return "origin2://game/launch?offerIds=%s" % ",".join(PackedStringArray(ids.map(func(i): return str(i).uri_encode())))
		"link2ea":
			return "link2ea://launchgame/%s?platform=pcwin" % str(ids[0]).uri_encode()
	return ""
