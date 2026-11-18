extends RefCounted
## Symbol einer Desktop-Verknüpfung (main_guide.gd create_shortcut): das des Spiels, nicht Uzais.
## Reihenfolge: Emulator (ROMs) bzw. die eigene Programmdatei (eigene Spiele), dann die
## Programmdatei im Installationsordner (Steam, GOG, Epic …, über game_finder.gd), dann das Symbol
## aus der Bibliothek (Steam-Cache, eigenes Bild) als .ico im Datenordner. Erst ohne all das Uzai.
## Nur gelesen und geprüft: Pfade über store_util.gd (kein Netzwerkpfad, kein „..“), nur .exe und
## .ico, nur vorhandene Dateien. Getestet in tests/logic_eigene_spiele.gd.

const GameFinder := preload("res://src/library/game_finder.gd")
const SU := preload("res://src/library/store_util.gd")

const ICO_PX := 256                ## größte Seite im .ico (Windows zeigt bis 256 × 256)
const BILD_MAX := 4 * 1024 * 1024  ## größere Bilddateien sind kein Symbol


## Taugt der Pfad als Symbol (vorhandene .exe oder .ico, sauberer lokaler Pfad)? "" sonst.
static func gueltig(p: String, exists: Callable = Callable()) -> String:
	var n := SU.norm_path(p)
	if n == "" or not n.get_extension().to_lower() in ["exe", "ico"]:
		return ""
	var da: bool = bool(exists.call(n)) if exists.is_valid() else FileAccess.file_exists(n)
	return n if da else ""


## Ohne Suchen: Emulator (ROM) bzw. Programmdatei des Spiels (eigene Spiele, Launcher mit eigener
## Programmdatei). emu_exe: Programm des Emulators oder "".
static func direkt(g: Dictionary, emu_exe: String, exists: Callable = Callable()) -> String:
	var cands: Array = []
	if str(g.get("source", "")) == "rom":
		cands.append(emu_exe)
	else:
		for k in ["target", "path", "exe"]:
			cands.append(str(g.get(k, "")))
	for c in cands:
		var ok := gueltig(str(c), exists)
		if ok != "":
			return ok
	return ""


## Installationsordner, in dem Uzai suchen darf ("" sonst: kein Spiel-Ordner, Sammelordner).
static func ordner(g: Dictionary) -> String:
	if str(g.get("source", "")) == "rom":
		return ""
	return SU.game_dir(str(g.get("install_dir", "")))


## Die Programmdatei des Spiels im Ordner (im Faden aufrufen: liest bis zu 20 000 Einträge).
## title hilft bei mehreren Funden (Unterordner je Teil).
static func aus_ordner(dir: String, title := "") -> String:
	var found := GameFinder.scan(dir)
	if found.is_empty():
		return ""
	var want := GameFinder._squash(title)
	var best: Dictionary = found[0]
	for f in found:
		if str(f.folder).to_lower() == dir.to_lower().trim_suffix("/"):
			best = f
			break
		if want != "" and GameFinder._squash(str(f.title)) == want:
			best = f
	return gueltig(str(best.exe))


## Bild (png/jpg/webp) als .ico mit einem PNG darin (geht ab Windows Vista). Leer bei Unsinn.
static func ico_aus_bild(img: Image) -> PackedByteArray:
	if img == null or img.is_empty():
		return PackedByteArray()
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	# Quadratisch, höchstens ICO_PX: das Bild mittig auf eine durchsichtige Fläche.
	var s := mini(ICO_PX, maxi(im.get_width(), im.get_height()))
	var k := float(s) / float(maxi(im.get_width(), im.get_height()))
	im.resize(maxi(1, roundi(im.get_width() * k)), maxi(1, roundi(im.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	var sq := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	sq.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i((s - im.get_width()) / 2, (s - im.get_height()) / 2))
	var png := sq.save_png_to_buffer()
	var out := PackedByteArray()
	out.resize(22)
	out.encode_u16(0, 0)               # reserviert
	out.encode_u16(2, 1)               # 1 = Symbol
	out.encode_u16(4, 1)               # ein Bild
	out.encode_u8(6, 0 if s >= 256 else s)
	out.encode_u8(7, 0 if s >= 256 else s)
	out.encode_u8(8, 0)                # keine Palette
	out.encode_u8(9, 0)
	out.encode_u16(10, 1)              # Ebenen
	out.encode_u16(12, 32)             # Bit je Punkt
	out.encode_u32(14, png.size())
	out.encode_u32(18, 22)             # Versatz der Bilddaten
	out.append_array(png)
	return out


## Symbol aus einer Bilddatei der Bibliothek als <ordner>/<name>.ico schreiben. Pfad oder "".
static func ico_schreiben(bild: String, ziel_ordner: String, name: String) -> String:
	var safe := ""
	for ch in name.left(80):
		safe += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in "-_" else "_"
	if safe == "" or bild == "" or not FileAccess.file_exists(bild) or not bild.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
		return ""
	var f := FileAccess.open(bild, FileAccess.READ)
	if f == null or f.get_length() > BILD_MAX:
		return ""
	f.close()
	var img := Image.load_from_file(bild)
	var ico := ico_aus_bild(img)
	if ico.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ziel_ordner)
	var out := ziel_ordner.path_join(safe + ".ico")
	var w := FileAccess.open(out, FileAccess.WRITE)
	if w == null:
		return ""
	w.store_buffer(ico)
	w.close()
	return out
