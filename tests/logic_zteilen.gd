extends Node
## Zimmer teilen und Spielbild (Punkt 131, Stufe 2 und 3): Auszug ohne persönliche Daten, Datei und
## Code hin und zurück, atomares Schreiben nur in eigene Ordner, bösartige Pakete und Codes (kein
## ZIP, Zip-Slip, fremde Dateien, Verknüpfungen, Verschlüsselung, Bomben, gelogene Größen, falsche
## Bilder, kaputtes JSON, Grenzen), Fuzzing, eigene Möbel mit neuen Kennungen, gesperrte Möbel,
## eigene Vorlagen, Wasserzeichen, Schnappschuss und die Antwort des Helfers für den Fernseher.
## Mit UZAI_HELPER_SHELL=<pwsh> zusätzlich: Helfer-C# für „window-frame“ übersetzt mit C# 5.
## Aufruf: godot --headless --path . res://tests/logic_zteilen.tscn

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const T := preload("res://src/room/zimmer_teilen.gd")
const Spielbild := preload("res://src/room/spielbild.gd")
const Paket := preload("res://src/core/paket.gd")
const HelperScript := preload("res://src/core/helper.gd")
const Zip := preload("res://src/core/zip_pruefung.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Ein eigenes Möbel aus dem Baukasten (gültig).
func _eigenes(id: String, name: String, farbe := "#b5623e") -> Dictionary:
	return { "id": id, "name": name, "ebene": "boden", "w": 2, "d": 2,
		"teile": [{ "a": "kasten", "x": 0, "y": 0, "z": 0, "b": 80, "h": 40, "t": 60, "r": 0, "f": farbe }] }


## Ein Zimmer voller persönlicher Daten (so sieht zimmer.json beim Nutzer aus).
func _persoenlich() -> Dictionary:
	var d := Daten.standard()
	var r: Dictionary = d.raeume[0]
	r.name = "Robins Geheimzimmer"
	d.eigene = [_eigenes("e_regal1", "Omas Kommode"), _eigenes("e_unbenutzt", "Geheimprojekt Kiste", "#2f3d5c")]
	(r.moebel as Array).append({ "t": "e_regal1", "x": 6, "z": 1, "r": 0, "v": "", "an": true })
	for m in r.moebel:
		if str(m.t) == "spieleregal":
			m["rg"] = { "so": "manuell", "fi": "ordner:Meine Privatspiele", "ma": ["steam_123456", "epic_geheim"], "da": "cover", "de": "viel", "ab": true }
			break
	d.stimmungen = [{ "id": "s_abc123", "name": "Robins Kuschelabend", "licht": G.std_licht() }]
	r.licht.st = "s_abc123"
	d.farben = ["#123456"]
	d.huellen = { "ps2": "dvd" }
	d.tier.name = "Funke"
	d.figur.person = "theo"
	d.gemeldet = ["stunden_100"]
	return Daten.pruefe(d)


func _jpg(w: int, h: int) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("#e7c27d"))
	return img.save_jpg_to_buffer(0.8)


## Ein ZIP mit genau einem Eintrag, Verfahren und Größen frei wählbar (für gelogene Angaben).
func _zip_roh(name: String, body: PackedByteArray, method: int, usize: int, crc: int) -> PackedByteArray:
	var nb := name.to_ascii_buffer()
	var out := PackedByteArray()
	var lh := PackedByteArray()
	lh.resize(30)
	lh.encode_u32(0, 0x04034b50)
	lh.encode_u16(4, 20)
	lh.encode_u16(8, method)
	lh.encode_u32(14, crc)
	lh.encode_u32(18, body.size())
	lh.encode_u32(22, usize)
	lh.encode_u16(26, nb.size())
	out.append_array(lh)
	out.append_array(nb)
	out.append_array(body)
	var ch := PackedByteArray()
	ch.resize(46)
	ch.encode_u32(0, 0x02014b50)
	ch.encode_u16(4, 20)
	ch.encode_u16(6, 20)
	ch.encode_u16(10, method)
	ch.encode_u32(16, crc)
	ch.encode_u32(20, body.size())
	ch.encode_u32(24, usize)
	ch.encode_u16(28, nb.size())
	var cd_at := out.size()
	out.append_array(ch)
	out.append_array(nb)
	var eo := PackedByteArray()
	eo.resize(22)
	eo.encode_u32(0, 0x06054b50)
	eo.encode_u16(8, 1)
	eo.encode_u16(10, 1)
	eo.encode_u32(12, 46 + nb.size())
	eo.encode_u32(16, cd_at)
	out.append_array(eo)
	return out


## Im Verzeichnis eines ZIP den n-ten Eintrag ändern (Ersteller, Attribute, Schalter).
func _zentral(b: PackedByteArray, n: int, made: int, eattr: int, flags := 0) -> PackedByteArray:
	var out := b.duplicate()
	var p := out.decode_u32(out.size() - 22 + 16)
	for k in n:
		p += 46 + out.decode_u16(p + 28) + out.decode_u16(p + 30) + out.decode_u16(p + 32)
	out.encode_u16(p + 4, made)
	out.encode_u16(p + 8, flags)
	out.encode_u32(p + 38, eattr)
	return out


func _paket_json(j: Variant) -> PackedByteArray:
	var txt: String = j if j is String else JSON.stringify(j)
	return Paket.zip([[T.JSON_NAME, txt.to_utf8_buffer()]])


func _ready() -> void:
	var tmp := OS.get_user_data_dir().path_join("zteilen_%d" % randi())
	DirAccess.make_dir_recursive_absolute(tmp)

	print("Auszug: nur Einrichtung, nichts Persönliches")
	var daten := _persoenlich()
	Katalog.eigene_setzen(daten.eigene)
	var raum: Dictionary = daten.raeume[0]
	var aus := T.auszug(daten, raum)
	check(not aus.is_empty(), "Auszug entsteht")
	var txt := JSON.stringify(aus)
	for geheim in ["Robins", "Geheimzimmer", "Funke", "Meine Privatspiele", "steam_123456", "epic_geheim", "Kuschelabend", "s_abc123",
			"#123456", "gemeldet", "stunden_100", "huellen", "Geheimprojekt", "e_unbenutzt", "stimmungen", "farben"]:
		if txt.contains(geheim):
			check(false, "nichts Persönliches im Auszug: „%s“ steckt noch darin" % geheim)
	check(not txt.contains("Robins") and not txt.contains("Funke") and not txt.contains("steam_123456"),
			"kein Name, kein Haustiername, keine Spiele, keine Stimmungsnamen, kein Spielstand im Auszug")
	check(str(aus.raeume[0].name) == T.RAUM_NAME and str(aus.raeume[0].id) == T.RAUM_ID, "Raum heißt neutral „Geteiltes Zimmer“")
	check((aus.eigene as Array).size() == 1 and str(aus.eigene[0].id) == "e_regal1", "nur eigene Möbel, die im Raum stehen, reisen mit")
	check(str(aus.tier.name) == FD.TIER_NAME and str(aus.figur.person) == "theo", "Figur und Haustier-Aussehen ja, Haustiername nein")
	var regal_ok := true
	for m in aus.raeume[0].moebel:
		if m.has("rg") and (m.rg.has("ma") or str(m.rg.get("fi", "alle")).begins_with("ordner") or str(m.rg.get("so", "")) == "manuell"):
			regal_ok = false
	check(regal_ok, "Regale ohne eigene Reihenfolge und ohne Auswahl nach Ordnern")
	check(str(aus.raeume[0].licht.st) == "", "eigene Stimmung: das Licht reist mit, ihr Name nicht")
	check(T.gleich(aus, T.pruefen(aus)), "Auszug besteht den Prüfer von zimmer.json unverändert")
	check(Katalog.ist_eigen("e_unbenutzt"), "Prüfen lässt die eigenen Möbel im Katalog, wie sie waren")

	print("Datei hin und zurück")
	var jpg := _jpg(320, 180)
	var bytes := T.paket(aus, jpg)
	var gel := T.lesen_bytes(bytes)
	check(bool(gel.ok), "Paket wird gelesen (%s)" % str(gel.get("error", "")))
	check(bool(gel.ok) and T.gleich(gel.daten, aus), "gelesen = geteilt (Round-Trip)")
	check(bool(gel.ok) and (gel.raum.moebel as Array).size() == (raum.moebel as Array).size(), "alle Möbel kommen an (%d)" % (raum.moebel as Array).size())
	check(bool(gel.ok) and (gel.vorschau as PackedByteArray) == jpg, "Vorschaubild kommt mit")
	var ex := [tmp.path_join("export"), tmp.path_join("export/Zimmer")]
	var name := T.dateiname(str(ex[1]), { "year": 2026, "month": 10, "day": 23, "hour": 20, "minute": 15, "second": 4 })
	check(name == "zimmer-20261023-201504.uzaizimmer", "Dateiname nach fester Regel")
	var w := T.schreiben(str(ex[0]), str(ex[1]), name, bytes, aus)
	check(bool(w.ok) and FileAccess.file_exists(str(w.get("pfad", ""))), "atomar geschrieben (%s)" % str(w.get("error", "")))
	check(not FileAccess.file_exists(str(ex[1]).path_join(name + ".neu")), "keine .neu-Datei bleibt liegen")
	var gd := T.lesen_datei(str(w.get("pfad", "")))
	check(bool(gd.ok) and T.gleich(gd.daten, aus), "Datei gelesen = geteilt")
	check(T.dateiname(str(ex[1]), { "year": 2026, "month": 10, "day": 23, "hour": 20, "minute": 15, "second": 4 }) == "zimmer-20261023-201504-2.uzaizimmer",
			"gleicher Zeitpunkt: neuer Name statt Überschreiben")
	check(not bool(T.schreiben(str(ex[0]), str(ex[1]), "../boese.uzaizimmer", bytes, aus).ok)
			and not bool(T.schreiben(str(ex[0]), str(ex[1]), "zimmer.exe", bytes, aus).ok), "nur feste Dateinamen, kein Pfad")
	check(not bool(T.schreiben(str(ex[0]), tmp.path_join("woanders"), "zimmer-20261023-201504.uzaizimmer", bytes, aus).ok), "nur in Uzais eigenen Ordner")
	var anders := aus.duplicate(true)
	(anders.raeume[0].moebel as Array).pop_back()
	check(not bool(T.schreiben(str(ex[0]), str(ex[1]), "zimmer-20261023-201505.uzaizimmer", bytes, anders).ok),
			"geschrieben wird nur, was wieder genauso gelesen wird")
	var link_ziel := tmp.path_join("fremd")
	DirAccess.make_dir_recursive_absolute(link_ziel)
	var link := tmp.path_join("export/Verlinkt")
	OS.execute("ln", PackedStringArray(["-s", link_ziel, link]))
	if DirAccess.open(tmp.path_join("export")).is_link("Verlinkt"):
		check(not bool(T.schreiben(str(ex[0]), link, "zimmer-20261023-201506.uzaizimmer", bytes, aus).ok), "nie über eine Verknüpfung schreiben")
		check(T.foto_speichern(Image.create(8, 8, false, Image.FORMAT_RGB8), [str(ex[0]), link]) == "", "Schnappschuss nie über eine Verknüpfung")
	check(not bool(T.lesen_datei(tmp.path_join("x.zip")).ok), "andere Endung: abgelehnt")
	# Nur der eigene Ordner oder einer darunter – ein Nachbar mit demselben Anfang im Namen zählt nicht dazu.
	var daneben := str(ex[0]) + "2"
	check(not bool(T.schreiben(str(ex[0]), daneben.path_join("Zimmer"), "zimmer-20261023-201507.uzaizimmer", bytes, aus).ok)
			and not DirAccess.dir_exists_absolute(daneben), "Nachbarordner mit gleichem Namensanfang: abgelehnt, nichts angelegt")
	check(T.foto_speichern(Image.create(8, 8, false, Image.FORMAT_RGB8), [str(ex[0]), daneben]) == "" and T.foto_ziel(["", tmp]) == "",
			"Schnappschuss: weder in den Nachbarordner noch ohne Basis")

	print("Code hin und zurück")
	var code := T.code(aus)
	check(code.begins_with("UZZ1:") and code.length() <= T.QR_MAX, "Standardzimmer passt in einen QR-Code (%d Zeichen)" % code.length())
	var gc := T.code_lesen(code)
	check(bool(gc.ok) and T.gleich(gc.daten, aus), "Code gelesen = geteilt")
	check(bool(T.code_lesen("  " + code.substr(0, 40) + "\n" + code.substr(40) + " ").ok), "Zeilenumbrüche und Leerzeichen im Code stören nicht")
	check(not bool(T.code_lesen("UZT1:" + code.substr(5)).ok), "Theme-Code ist kein Zimmer-Code")
	check(not bool(T.code_lesen("UZZ1:<script>alert(1)</script>==").ok) and not bool(T.code_lesen("UZZ1:abc").ok), "fremde Zeichen, zu kurz: abgelehnt")
	check(not bool(T.code_lesen("UZZ1:" + "A".repeat(T.QR_MAX * 2 + 4)).ok) and not bool(T.code_lesen("x".repeat(T.QR_MAX * 4)).ok), "zu lang: abgelehnt")
	check(not bool(T.code_lesen("UZZ1:" + Marshalls.raw_to_base64("kein zip, nur text".to_utf8_buffer())).ok), "Base64 ohne ZIP: abgelehnt")
	# Viele Möbel mit lauter verschiedenen Farben (lässt sich kaum packen): zu groß für einen QR-Code.
	var voll := Daten.standard()
	var vr: Dictionary = voll.raeume[0]
	vr.w = 20
	vr.d = 20
	vr.moebel = []
	var zufall := RandomNumberGenerator.new()
	zufall.seed = 7
	for x in range(0, 20, 2):
		for z in range(0, 20, 2):
			vr.moebel.append(
					{ "t": "sessel", "x": x, "z": z, "r": (x + z) % 4, "f": "#%06x" % zufall.randi_range(0, 0xffffff), "f2": "#%06x" % zufall.randi_range(0, 0xffffff) })
	var vp := Daten.pruefe(voll)
	var voll_aus := T.auszug(vp, vp.raeume[0])
	check((voll_aus.raeume[0].moebel as Array).size() > 60 and T.code(voll_aus) == "", "sehr volles Zimmer: kein QR-Code (dann als Datei)")
	print("Bösartige Pakete")
	check(not bool(T.lesen_bytes(PackedByteArray()).ok) and not bool(T.lesen_bytes("hallo".to_utf8_buffer()).ok), "leer, kein ZIP: abgelehnt")
	var riesig := PackedByteArray()
	riesig.resize(T.MAX_DATEI + 1)
	check(not bool(T.lesen_bytes(riesig).ok), "größer als %d MB: abgelehnt" % (T.MAX_DATEI / 1048576))
	var j := T.json(aus)
	check(not bool(T.lesen_bytes(Paket.zip([["../zimmer.json", j]])).ok), "Zip-Slip (../): abgelehnt")
	check(not bool(T.lesen_bytes(Paket.zip([["a/zimmer.json", j]])).ok), "Ordner im Namen: abgelehnt")
	check(not bool(T.lesen_bytes(Paket.zip([[T.JSON_NAME, j], ["boese.exe", "MZ".to_utf8_buffer()]])).ok), "fremde Datei im Paket: abgelehnt")
	check(not bool(T.lesen_bytes(Paket.zip([[T.JSON_NAME, j], ["theme.json", j]])).ok), "andere bekannte Datei (theme.json): abgelehnt")
	check(not bool(T.lesen_bytes(Paket.zip([[T.JSON_NAME, j], ["ZIMMER.JSON", j]])).ok), "doppelt (Groß/klein): abgelehnt")
	check(not bool(T.lesen_bytes(Paket.zip([["vorschau.jpg", jpg]])).ok), "ohne zimmer.json: abgelehnt")
	var mit_link := _zentral(Paket.zip([[T.JSON_NAME, j], [T.BILD_NAME, jpg]]), 1, (3 << 8) | 20, 0xA1FF << 16)
	check(not bool(T.lesen_bytes(mit_link).ok), "Verknüpfung (Unix-Symlink) im Paket: abgelehnt")
	check(not bool(T.lesen_bytes(_zentral(Paket.zip([[T.JSON_NAME, j]]), 0, 20, 0, 1)).ok), "verschlüsselt: abgelehnt")
	check(not bool(T.lesen_bytes(_zip_roh(T.JSON_NAME, j, 12, j.size(), Zip.crc32(j))).ok), "fremdes Packverfahren (bzip2): abgelehnt")
	var leer := " ".repeat(200 * 1024).to_utf8_buffer()
	var bombe := _zip_roh(T.JSON_NAME, Paket.deflate(leer), 8, leer.size(), Zip.crc32(leer))
	check(not bool(T.lesen_bytes(bombe).ok), "Bombe (stark gepackt): abgelehnt")
	var gross := " ".repeat(T.MAX_JSON + 10).to_utf8_buffer()
	check(not bool(T.lesen_bytes(_zip_roh(T.JSON_NAME, gross, 0, gross.size(), Zip.crc32(gross))).ok), "zimmer.json zu groß: abgelehnt")
	var packed := Paket.deflate(j)
	check(not bool(T.lesen_bytes(_zip_roh(T.JSON_NAME, packed, 8, j.size() + 100, Zip.crc32(j))).ok), "gelogene Größe: abgelehnt")
	check(not bool(T.lesen_bytes(_zip_roh(T.JSON_NAME, j, 0, j.size(), 12345)).ok), "falsche Prüfsumme (gespeichert): abgelehnt")
	check(not bool(T.lesen_bytes(_zip_roh(T.JSON_NAME, packed, 8, j.size(), 12345)).ok), "falsche Prüfsumme (gepackt): abgelehnt")
	check(not bool(T.lesen_bytes(T.paket(aus, "kein bild".to_utf8_buffer())).ok), "Vorschau ist kein JPEG: abgelehnt")
	var png := Image.create(16, 16, false, Image.FORMAT_RGB8).save_png_to_buffer()
	check(not bool(T.lesen_bytes(T.paket(aus, png)).ok), "PNG als vorschau.jpg: abgelehnt")
	var riesenbild := _jpg(32, 32)
	for i in riesenbild.size() - 9:
		if riesenbild[i] == 0xff and riesenbild[i + 1] == 0xc0:
			riesenbild.encode_u16(i + 5, 0xffff)
			riesenbild.encode_u16(i + 7, 0xffff)
			break
	check(not bool(T.lesen_bytes(T.paket(aus, riesenbild)).ok), "Vorschau mit 65535 × 65535 im Kopf: abgelehnt (nie dekodiert)")
	var bild_gross := PackedByteArray()
	bild_gross.resize(T.MAX_VORSCHAU + 1)
	bild_gross[0] = 0xff
	bild_gross[1] = 0xd8
	check(not bool(T.lesen_bytes(_zip_roh(T.BILD_NAME, bild_gross, 0, bild_gross.size(), Zip.crc32(bild_gross))).ok), "Vorschau zu groß: abgelehnt")
	for boese in ["", "nicht json", "[1,2,3]", "\"text\"", "{\"format\":\"uzai-theme\"}", "{\"format\":\"uzai-zimmer\",\"version\":99,\"raeume\":[]}",
			"{\"format\":\"uzai-zimmer\",\"version\":2,\"raeume\":[]}", "{\"format\":\"uzai-zimmer\",\"version\":2,\"raeume\":[{\"id\":\"../x\",\"w\":12,\"d\":10}]}"]:
		if bool(T.lesen_bytes(_paket_json(boese)).ok):
			check(false, "kaputtes zimmer.json angenommen: %s" % boese.left(40))
	check(true, "kaputtes oder fremdes zimmer.json: alles abgelehnt")

	print("Feindliche Werte im Zimmer")
	var feind := aus.duplicate(true)
	var fr: Dictionary = feind.raeume[0]
	(fr.moebel as Array).append_array([
		{ "t": "../../windows/system32", "x": 1, "z": 1 }, { "t": "sofa", "x": 99999, "z": -5 }, { "t": "sofa", "x": "1", "z": 2 },
		{ "t": "sessel", "x": 1.5, "z": 2 }, { "t": "sessel", "x": 2, "z": 2, "r": 7 },
			{ "t": "pflanze", "x": 3, "z": 3, "f": "javascript:alert(1)", "m": "../../etc" },
		{ "t": "tischlampe", "x": 4, "z": 3, "l": { "k": 99999, "c": "#gggggg", "h": -40 } }, { "t": "e_fehlt", "x": 5, "z": 5 },
	])
	fr.waende.hinten = { "m": "<script>", "f": "rgb(1,2,3)", "mu": "x", "mf": 7 }
	fr.w = 500
	var gf := T.lesen_bytes(T.paket(feind))
	check(not bool(gf.ok), "Raumgröße außerhalb 8 … 20: Raum abgelehnt")
	fr.w = 12
	gf = T.lesen_bytes(T.paket(feind))
	check(bool(gf.ok), "Zimmer mit feindlichen Werten wird gelesen, Feindliches fällt weg")
	if bool(gf.ok):
		var ft := JSON.stringify(gf.daten)
		check(not ft.contains("system32") and not ft.contains("javascript") and not ft.contains("<script>") and not ft.contains("gggggg")
				and not ft.contains("e_fehlt") and not ft.contains("../"), "nur Kennungen aus dem Katalog, gültige Farben und Materialien")
		check((gf.raum.moebel as Array).size() <= (aus.raeume[0].moebel as Array).size() + 2, "nur gültige Möbel kommen dazu (Pflanze, Lampe – bereinigt)")
		var lampe_ok := true
		for m in gf.raum.moebel:
			if m.has("l") and (int(m.l.get("k", 0)) > 10000 or int(m.l.get("h", 100)) < 0):
				lampe_ok = false
		check(lampe_ok, "Zahlen in festen Bereichen (Lampe)")
	var feind2 := aus.duplicate(true)
	var e_viele: Array = []
	for i in 60:
		e_viele.append(_eigenes("e_x%02d" % i, "Möbel %d" % i))
	e_viele.append({ "id": "../boese", "name": "x", "teile": [{ "a": "kasten" }] })
	e_viele.append(
			{ "id": "e_teile", "name": "viele Teile", "teile": range(500).map(func(_i: int) -> Dictionary: return { "a": "kugel", "x": 0, "y": 0, "z": 0 }) })
	feind2.eigene = e_viele
	var mm: Array = feind2.raeume[0].moebel
	for i in 2000:
		mm.append({ "t": "pflanze", "x": i % 12, "z": 9 })
	var g2 := T.lesen_bytes(T.paket(feind2))
	check(bool(g2.ok) and (g2.raum.moebel as Array).size() <= Daten.MAX_MOEBEL, "höchstens %d Möbel" % Daten.MAX_MOEBEL)
	var p2 := T.pruefen(feind2)
	check((p2.eigene as Array).size() <= G.MAX_EIGENE and not JSON.stringify(p2.eigene).contains("boese"),
			"höchstens %d eigene Möbel, nur Kennungen „e_…“" % G.MAX_EIGENE)
	var teile_ok := true
	for e in p2.eigene:
		if (e.teile as Array).size() > G.MAX_TEILE:
			teile_ok = false
	check(teile_ok, "höchstens %d Teile je eigenem Möbel" % G.MAX_TEILE)
	var mehr := aus.duplicate(true)
	for i in 30:
		var rr: Dictionary = (aus.raeume[0] as Dictionary).duplicate(true)
		rr.id = "r%d" % i
		(mehr.raeume as Array).append(rr)
	var gm := T.lesen_bytes(T.paket(mehr))
	check(bool(gm.ok) and (gm.daten.raeume as Array).size() == 1, "mehrere Räume: genau einer wird übernommen")

	print("Fuzzing (300 veränderte Pakete)")
	var heil := T.paket(aus, jpg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 131
	var angenommen := 0
	var stabil := true
	for i in 300:
		var b := heil.duplicate()
		for k in rng.randi_range(1, 6):
			var at := rng.randi_range(0, b.size() - 1)
			b[at] = rng.randi_range(0, 255)
		if rng.randf() < 0.15:
			b = b.slice(0, rng.randi_range(0, b.size()))
		var r := T.lesen_bytes(b)
		if bool(r.ok):
			angenommen += 1
			if not T.gleich(r.daten, T.pruefen(r.daten)):
				stabil = false
	check(stabil, "kein Absturz; was angenommen wird (%d), ist geprüft und stabil" % angenommen)
	var zeichen := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_ äö\n"
	for i in 200:
		var c := "UZZ1:"
		for k in rng.randi_range(0, 300):
			c += zeichen[rng.randi_range(0, zeichen.length() - 1)]
		T.code_lesen(c)
	check(true, "200 zufällige Codes: kein Absturz")

	# Fuzzing auf Ebene der Daten: zufällige Felder mit zufälligen Typen und Werten.
	var werte: Array = [null, true, -1, 0, 3.5, 1e30, NAN, "", "../../x", "#zzzzzz", "<script>", "e_x", "a".repeat(5000), [], {}, [1, "x"], { "a": 1 }]
	var feld_namen: Array = ["t", "x", "z", "r", "v", "an", "f", "f2", "m", "mu", "s", "l", "rg", "be", "gr", "w", "d", "id", "name", "teile", "ebene"]
	var heil_stabil := true
	var fremd_drin := false
	for i in 300:
		var a: Dictionary = aus.duplicate(true)
		var ziele: Array = [a, a.raeume[0], a.raeume[0].licht, a.raeume[0].boden, a.figur, a.tier] + (a.raeume[0].moebel as Array).slice(0, 8) + (a.eigene as Array)
		for k in rng.randi_range(1, 5):
			var z: Dictionary = ziele[rng.randi_range(0, ziele.size() - 1)]
			z[feld_namen[rng.randi_range(0, feld_namen.size() - 1)]] = werte[rng.randi_range(0, werte.size() - 1)]
		var r := T.lesen_bytes(T.paket(a))
		if bool(r.ok):
			# Namen eigener Möbel sind Text (gekürzt, ohne Steuerzeichen) – alles andere nur Kennungen.
			var ohne_namen: Dictionary = (r.daten as Dictionary).duplicate(true)
			for e in ohne_namen.eigene:
				e.name = ""
			var rt := JSON.stringify(ohne_namen)
			if rt.contains("<script>") or rt.contains("../") or rt.contains("zzzzzz") or rt.contains("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"):
				fremd_drin = true
			if not T.gleich(r.daten, T.pruefen(r.daten)):
				heil_stabil = false
	check(heil_stabil and not fremd_drin, "300 Zimmer mit zufällig vergifteten Feldern: nichts Fremdes kommt durch, Ergebnis stabil")

	print("Übernehmen: eigene Möbel, Sperren, Vorlagen")
	var eigene_jetzt: Array = [_eigenes("e_regal1", "Mein ganz anderes Möbel", "#2f3d5c"), _eigenes("e_sofa22", "Sofa-Ecke", "#87977a")]
	var vb := T.vorbereiten(gel, eigene_jetzt, [])
	var neu_id := ""
	for m in vb.raum.moebel:
		if str(m.t).begins_with("e_"):
			neu_id = str(m.t)
	check(neu_id != "" and neu_id != "e_regal1", "gleiche Kennung, anderes Möbel: das fremde bekommt eine neue Kennung (%s)" % neu_id)
	check((vb.eigene as Array).size() == 3 and int(vb.neu) == 1 and str(vb.eigene[0].name) == "Mein ganz anderes Möbel",
			"eigenes Möbel bleibt, das fremde kommt dazu")
	var gleiches := [_eigenes("e_hier01", "Omas Kommode")]
	var vb2 := T.vorbereiten(gel, gleiches, [])
	check(int(vb2.neu) == 0 and (vb2.eigene as Array).size() == 1 and JSON.stringify(vb2.raum).contains("e_hier01"),
			"dasselbe Möbel gibt es schon: wird wiederverwendet")
	var voll_eigene: Array = []
	for i in G.MAX_EIGENE:
		voll_eigene.append(_eigenes("e_v%02d" % i, "Voll %d" % i, "#%02x3344" % (i * 9)))
	var vb3 := T.vorbereiten(gel, voll_eigene, [])
	check(int(vb3.weg_eigene) == 1 and (vb3.eigene as Array).size() == G.MAX_EIGENE and not JSON.stringify(vb3.raum).contains("e_regal1"),
			"Liste voll: das fremde Möbel bleibt weg, gezählt")
	var mit_lava := aus.duplicate(true)
	var stelle: Dictionary = Daten.freie_stelle(T.pruefen(mit_lava).raeume[0], "lavalampe", 6, 6)
	(mit_lava.raeume[0].moebel as Array).append({ "t": "lavalampe", "x": int(stelle.x), "z": int(stelle.z) })
	var gl := T.lesen_bytes(T.paket(mit_lava))
	var gesperrt := T.vorbereiten(gl, [], [])
	var frei := T.vorbereiten(gl, [], ["stunden_100"])
	check(int(gesperrt.weg_gesperrt) == 1 and not JSON.stringify(gesperrt.raum).contains("lavalampe"), "noch nicht freigespielt: bleibt weg (nur durchs Spielen)")
	check(int(frei.weg_gesperrt) == 0 and JSON.stringify(frei.raum).contains("lavalampe"), "freigespielt: kommt mit")
	check(
			T.gleich({ "format": "uzai-zimmer", "version": 2, "raeume": [vb.raum], "eigene": vb.eigene },
			{ "format": "uzai-zimmer", "version": 2, "raeume": [vb.raum], "eigene": vb.eigene }), "vorbereiteter Raum besteht den Prüfer")
	var vl := T.vorlage(vb.raum, "Lauras Zimmer\u0007\n", [])
	check(not vl.is_empty() and str(vl.id).begins_with("v_") and str(vl.name) == "Lauras Zimmer", "Vorlage mit Kennung „v_…“ und sauberem Namen")
	var mit_vorlagen := Daten.standard()
	Katalog.eigene_setzen(vb.eigene)
	mit_vorlagen.eigene = vb.eigene
	var vliste: Array = []
	for i in 12:
		vliste.append({ "id": "v_t%02d" % i, "name": "V %d" % i, "raum": vb.raum })
	vliste.append({ "id": "../x", "name": "böse", "raum": vb.raum })
	vliste.append({ "id": "v_kaputt", "name": "kaputt", "raum": { "w": 999 } })
	mit_vorlagen.vorlagen = vliste
	var pv := Daten.pruefe(mit_vorlagen)
	check((pv.vorlagen as Array).size() == Daten.MAX_VORLAGEN and str(pv.vorlagen[0].raum.id) == "vorlage",
			"zimmer.json: höchstens %d eigene Vorlagen, jede geprüft" % Daten.MAX_VORLAGEN)
	check(Daten.standard().has("vorlagen") and Daten.pruefe(Daten.standard()).vorlagen == [], "Standardzimmer: keine eigenen Vorlagen")

	print("Schnappschuss und Wasserzeichen")
	var foto := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	foto.fill(Color("#203040"))
	var marke := Image.create(200, 70, false, Image.FORMAT_RGBA8)
	marke.fill(Color(1, 1, 1, 1))
	T.wasserzeichen(foto, marke)
	var ecke := foto.get_pixel(1920 - 36 - 100, 1080 - 36 - 35)
	check(ecke.r > 0.3 and ecke.r < 0.8, "Wasserzeichen unten rechts, dezent (nicht deckend)")
	check(foto.get_pixel(100, 100).is_equal_approx(Color("#203040")), "sonst bleibt das Bild unverändert")
	var fo := [tmp.path_join("export"), tmp.path_join("export/Bilder")]
	var fp := T.foto_speichern(foto, fo)
	check(fp != "" and FileAccess.file_exists(fp) and fp.get_file().begins_with("Dein Zimmer ") and fp.ends_with(".png"),
			"Schnappschuss als PNG unter Bilder (%s)" % fp.get_file())
	check(not FileAccess.file_exists(fp + ".neu"), "Schnappschuss atomar (keine .neu)")
	var fp2 := T.foto_speichern(foto, fo)
	check(fp2 != fp and FileAccess.file_exists(fp2), "zweiter Schnappschuss überschreibt den ersten nicht")
	# Ziel im Hauptfaden, Schreiben im Hilfsfaden: Ein Name, der gerade geschrieben wird, bleibt frei.
	var z1 := T.foto_ziel(fo)
	var z2 := T.foto_ziel(fo, [z1.get_file()])
	check(z1 != "" and z2 != "" and z1 != z2 and not FileAccess.file_exists(z1), "nächster Schnappschuss weicht dem aus, der noch geschrieben wird")
	check(T.foto_schreiben(foto, "") == "" and T.foto_schreiben(null, z1) == "", "ohne Ziel oder ohne Bild wird nichts geschrieben")
	check(T.foto_schreiben(foto, z1) == z1 and FileAccess.file_exists(z1) and not FileAccess.file_exists(z1 + ".neu"), "foto_schreiben schreibt genau dorthin")

	print("Fernseher: Antwort des Helfers")
	var bild := Image.create(512, 288, false, Image.FORMAT_RGB8)
	bild.fill(Color("#3a7bd5"))
	var b64 := Marshalls.raw_to_base64(bild.save_jpg_to_buffer(0.7))
	var gut := Spielbild.bild_aus({ "ok": true, "result": { "result": "ok", "jpg": b64 } })
	check(gut != null and gut.get_width() == 512, "gültiges Bild wird angenommen")
	check(Spielbild.bild_aus({ "ok": false }) == null and Spielbild.bild_aus({ "ok": true, "result": { "result": "Zeitgrenze" } }) == null,
			"Fehler und Zeitgrenze: kein Bild")
	check(Spielbild.bild_aus({ "ok": true, "result": { "result": "ok", "jpg": 42 } }) == null and Spielbild.bild_aus({ "ok": true, "result": "ok" }) == null,
			"falsche Typen: kein Bild")
	check(Spielbild.bild_aus({ "ok": true, "result": { "result": "ok", "jpg": "A".repeat(Spielbild.MAX_B64 + 4) } }) == null, "zu lange Antwort: kein Bild")
	check(Spielbild.bild_aus({ "ok": true, "result": { "result": "ok", "jpg": Marshalls.raw_to_base64(png) } }) == null, "kein JPEG: kein Bild")
	var gross_bild := Image.create(2000, 100, false, Image.FORMAT_RGB8)
	check(Spielbild.bild_aus({ "ok": true, "result": { "result": "ok", "jpg": Marshalls.raw_to_base64(gross_bild.save_jpg_to_buffer()) } }) == null,
			"zu breit (> %d): kein Bild" % Spielbild.MAX_PX)
	var schwarz := Image.create(64, 36, false, Image.FORMAT_RGB8)
	check(Spielbild.fast_schwarz(schwarz) and not Spielbild.fast_schwarz(bild), "schwarzes Bild (exklusives Vollbild) zählt als kein Bild")
	check(Spielbild.TAKT.leicht[0] > Spielbild.TAKT.mittel[0] and Spielbild.TAKT.mittel[0] > Spielbild.TAKT.hoch[0]
			and Spielbild.TAKT.leicht[1] < Spielbild.TAKT.hoch[1], "Leicht: seltener und kleiner")
	check(not Spielbild.spiel_laeuft(), "ohne Spiel (und ohne Demo-Bild) zeigt der Fernseher nichts Fremdes")

	var shell := HelperScript._test_shell()
	if shell != "":
		print("Helfer (PowerShell)")
		var probe := tmp.path_join("snap_probe.ps1")
		var pf := FileAccess.open(probe, FileAccess.WRITE)
		pf.store_string("""
$src = Get-Content -Raw $args[0]
$tokens = $null; $errs = $null
[System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$tokens, [ref]$errs) | Out-Null
"PARSE " + $errs.Count
"CMD " + ([regex]::Matches($src, "'window-frame'")).Count
$cs = [regex]::Match($src, '(?s)\\$script:SnapSrc = @''\\r?\\n(.*?)\\r?\\n''@').Groups[1].Value
"CSLEN " + $cs.Length
try { Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Drawing, System.Drawing.Primitives, System.Drawing.Common, System.Private.Windows.Core, System.ComponentModel.Primitives, System.Threading.Thread, System.Runtime.InteropServices -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; "CS ok" } catch { "CS FEHLER " + $_.Exception.Message }
""")
		pf.close()
		var o: Array = []
		OS.execute(shell, PackedStringArray(["-NoProfile", "-NonInteractive", "-File", probe, ProjectSettings.globalize_path("res://helper/uzai-helper.ps1")]), o,
				true)
		var ot := str(o[0] if not o.is_empty() else "")
		check(ot.contains("PARSE 0") and ot.contains("CMD 1"), "Helfer liest sich ein, „window-frame“ gibt es genau einmal")
		check(ot.contains("CS ok"), "C# von UzSnap.Frame übersetzt mit C# 5" + ("" if ot.contains("CS ok") else " – " + ot.right(300)))
		# Der Befehl im laufenden Helfer: nur Zahlen, ohne Fenster sofort „kein Fenster“.
		var r0 := await Helper.run("window-frame", { "hwnd": 0, "max_w": 99999, "q": -5 }, 30.0)
		check(bool(r0.ok) and str((r0.result as Dictionary).get("result", "")) == "kein Fenster", "window-frame ohne Fenster: „kein Fenster“, nichts passiert")
		var r1 := await Helper.run("window-frame", { "hwnd": "1; Remove-Item C:\\", "max_w": 320 }, 30.0)
		check(not bool(r1.ok) or str((r1.result as Dictionary).get("result", "")) != "ok", "Text statt Zahl als Fenster: abgelehnt")
	else:
		print("  (Helfer-Prüfung übersprungen: UZAI_HELPER_SHELL nicht gesetzt)")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
