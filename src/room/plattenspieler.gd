extends RefCounted
## Der Plattenspieler im Zimmer zeigt, was gerade läuft – aus dem, was Uzai schon hat (Music.now:
## Spotify Connect, Windows-Mediensitzung oder eigene Musik), ohne neue Netzwege. Teller und Platte
## drehen sich nur bei Wiedergabe mit 33⅓ U/min (Riemen: kurzer An- und Auslauf), der Tonarm hebt
## sich beim Start, schwenkt sanft auf die Einlaufrille und senkt sich; während des Titels wandert
## er langsam nach innen, beim Stopp hebt er sich und kehrt auf die Stütze zurück. Das Cover steht
## als Plattenhülle hinter dem Teller. Läuft nichts: Teller still, Arm auf der Stütze, keine Hülle.
##
## Cover nur aus Uzais eigenem Zwischenspeicher (cache/…, bzw. die uzai-cover-*.png des Helfers im
## Temp-Ordner), geladen mit Image.load_*_from_buffer nach Prüfung von Größe, Kopf und Format –
## nie über ResourceLoader. Logik ohne Szene: tests/logic_plattenkonsole.gd.

const MediaDaten := preload("res://src/core/media_daten.gd")
const Sicher := preload("res://src/core/sicher.gd")

const UPM := 100.0 / 3.0                 ## 33⅓ Umdrehungen je Minute
const DREH := UPM / 60.0 * TAU           ## im Bogenmaß je Sekunde (≈ 3,49)
const ANLAUF := 0.7                      ## s bis zur vollen Drehzahl
const AUSLAUF := 1.2                     ## s bis zum Stillstand
const ARM_RUHE := 0.0                    ## auf der Stütze
const ARM_AUSSEN := 0.4887               ## 28°: Einlaufrille (Radius ≈ 14,6 cm)
const ARM_INNEN := 0.8727                ## 50°: Auslaufrille (Radius ≈ 6,3 cm)
const HUB_S := 0.24                      ## s zum Anheben bzw. Absenken (Lift)
const SCHWENK := 0.9                     ## höchstens so schnell schwenkt der Arm (rad/s)
const WEIT := 0.03                       ## ab hier hebt sich der Arm vor dem Schwenken

const COVER_MAX_BYTES := 4 * 1024 * 1024
const COVER_MAX_SEITE := 2048
const COVER_SEITE := 512
const EXTS := ["png", "jpg", "jpeg", "webp"]


static func neu() -> Dictionary:
	return { "dreh": 0.0, "winkel": 0.0, "arm": ARM_RUHE, "hub": 0.0 }


## Wohin der Tonarm will: auf der Stütze, oder über der Rille an der Stelle des Titels (anteil 0…1).
static func arm_ziel(spielt: bool, anteil: float) -> float:
	return lerpf(ARM_AUSSEN, ARM_INNEN, clampf(anteil, 0.0, 1.0)) if spielt else ARM_RUHE


## Ein Bild weiter: Drehzahl, Stellung des Tellers, Arm (Schwenk) und Hub (0 liegt auf, 1 gehoben).
## ruhig (Animationen reduzieren): alles sofort am Ziel.
static func schritt(z: Dictionary, spielt: bool, anteil: float, dt: float, ruhig := false) -> Dictionary:
	var o := neu() if z.is_empty() else z.duplicate()
	var soll := DREH if spielt else 0.0
	var ziel := arm_ziel(spielt, anteil)
	if ruhig:
		o.dreh = soll
		o.arm = ziel
		o.hub = 0.0
	else:
		o.dreh = move_toward(float(o.dreh), soll, DREH / (ANLAUF if spielt else AUSLAUF) * dt)
		var d := ziel - float(o.arm)
		var weit := absf(d) > WEIT
		o.hub = move_toward(float(o.hub), 1.0 if weit else 0.0, dt / HUB_S)
		# Erst ganz anheben, dann schwenken; kleine Wege (der Lauf nach innen) ohne Heben.
		if not weit or float(o.hub) >= 1.0:
			var v := clampf(d * 4.0, -SCHWENK, SCHWENK)
			if absf(v) < 0.08:
				v = 0.08 * signf(d)
			var neu_arm := float(o.arm) + v * dt
			o.arm = ziel if absf(d) < 0.0005 or (ziel - neu_arm) * d <= 0.0 else neu_arm
	o.winkel = fposmod(float(o.winkel) + float(o.dreh) * dt, TAU)
	return o


## Zustand auf den Plattenspieler übertragen (Meta teller, tonarm, tonarm_hub, ps_led aus moebel.gd).
static func anwenden(n: Node3D, z: Dictionary) -> void:
	if n.has_meta("teller"):
		(n.get_meta("teller") as Node3D).rotation.y = -float(z.winkel)
	if n.has_meta("tonarm"):
		(n.get_meta("tonarm") as Node3D).rotation.y = -float(z.arm)
	if n.has_meta("tonarm_hub"):
		(n.get_meta("tonarm_hub") as Node3D).rotation.x = -0.075 * smoothstep(0.0, 1.0, float(z.hub))
	if n.has_meta("ps_led"):
		var m: StandardMaterial3D = n.get_meta("ps_led")
		var e := 1.8 if float(z.dreh) > DREH * 0.5 else 0.0
		if m.emission_energy_multiplier != e:
			m.emission_energy_multiplier = e


# --- Cover ----------------------------------------------------------------------------------------

## Wo das Cover zu art liegt – nur in Uzais eigenem Zwischenspeicher: Bilder von Spotify (Adresse)
## legt die Musik ohnehin unter cache/img/web ab (Media.url_texture), eigene Musik unter
## cache/musik, die Windows-Mediensitzung als uzai-cover-*.png im Temp-Ordner (Helfer).
## "" = nicht aus dem eigenen Speicher (dann keine Hülle mit Bild).
static func cover_pfad(art: String, cache: String, temp: String) -> String:
	if art == "" or art.length() > 2048 or art.to_utf8_buffer().has(0):
		return ""
	if art.begins_with("https://") or art.begins_with("http://"):
		var ext := art.get_extension().get_slice("?", 0).to_lower()
		if not ext in EXTS:
			ext = "jpg"
		return cache.path_join("img/web/%s.%s" % [art.md5_text(), ext]) if cache != "" else ""
	if art.contains("://") or art.contains("..") or not Sicher.local_path_ok(art):
		return ""
	var p := art.replace("\\", "/").to_lower()
	var c := cache.replace("\\", "/").to_lower().trim_suffix("/")
	if c != "" and p.begins_with(c + "/") and p.get_extension() in EXTS:
		return art
	var t := temp.replace("\\", "/").to_lower().trim_suffix("/")
	if t != "" and p.get_base_dir() == t and p.get_file().begins_with("uzai-cover-") and p.get_extension() == "png":
		return art
	return ""


## Das Cover aus einer Datei des eigenen Speichers: höchstens COVER_MAX_BYTES, Kopf PNG, JPG oder
## WebP (nach den Bytes, nicht nach der Endung), höchstens COVER_MAX_SEITE Punkte je Seite; mittig
## quadratisch und auf COVER_SEITE verkleinert. null, wenn etwas nicht passt.
static func cover_laden(pfad: String) -> Image:
	if pfad == "" or not FileAccess.file_exists(pfad):
		return null
	var f := FileAccess.open(pfad, FileAccess.READ)
	if f == null:
		return null
	var n := f.get_length()
	if n < 32 or n > COVER_MAX_BYTES:
		return null
	var b := f.get_buffer(n)
	f.close()
	return cover_aus_bytes(b)


static func cover_aus_bytes(b: PackedByteArray) -> Image:
	if b.size() < 32 or b.size() > COVER_MAX_BYTES:
		return null
	var dims := MediaDaten.image_dims(b)
	if dims.x <= 0 or dims.y <= 0 or dims.x > COVER_MAX_SEITE or dims.y > COVER_MAX_SEITE:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47:
		err = img.load_png_from_buffer(b)
	elif b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF:
		err = img.load_jpg_from_buffer(b)
	elif b[0] == 0x52 and b[1] == 0x49 and b[2] == 0x46 and b[3] == 0x46 and b[8] == 0x57 and b[9] == 0x45 and b[10] == 0x42 and b[11] == 0x50:
		err = img.load_webp_from_buffer(b)
	if err != OK or img.is_empty():
		return null
	var w := img.get_width()
	var h := img.get_height()
	if w < 8 or h < 8 or w > COVER_MAX_SEITE or h > COVER_MAX_SEITE:
		return null
	if img.is_compressed():
		img.decompress()
	var s := mini(w, h)
	if w != h:
		img = img.get_region(Rect2i(int((w - s) * 0.5), int((h - s) * 0.5), s, s))
	if s > COVER_SEITE:
		img.resize(COVER_SEITE, COVER_SEITE, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return img


## Mittlere Farbe eines Covers (für Kante der Hülle und Etikett).
static func mittelfarbe(img: Image) -> Color:
	var k := img.duplicate() as Image
	k.clear_mipmaps()
	k.resize(4, 4, Image.INTERPOLATE_BILINEAR)
	var c := Color(0, 0, 0, 0)
	for y in 4:
		for x in 4:
			c += k.get_pixel(x, y)
	return Color(c.r / 16.0, c.g / 16.0, c.b / 16.0, 1.0)
