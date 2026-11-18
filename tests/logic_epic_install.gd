extends Node
## Uzais eigener Epic-Installer ohne Netz: Manifeste im echten Format (binär Fassung 18 und 22,
## altes JSON), Chunks (Kopf 2–4, gepackt und roh), Zusammensetzen mit Prüfsummen, bösartige
## Manifeste und Chunks, abgeschnittene und verfälschte Daten, Pfade, Epics Antwort mit den
## Adressen und der Liste erlaubter Server, Plan für Installation und Update, Startparameter,
## Uzais Angaben zu installierten Spielen und gesicherter Stand.
## Die Beispieldateien schreibt tests/fake_epic_cdn.py --fixtures tests/fixtures/epic_install
## (unabhängig von Uzais Leser). Den Ablauf mit Netz prüft tests/net_epic_install.gd.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_epic_install.tscn → „Ergebnis: alles ok“

const M := preload("res://src/library/epic_manifest.gd")
const EI := preload("res://src/core/epic_install.gd")
const WR := preload("res://src/ui/layers/window_remote.gd")
const FX := "res://tests/fixtures/epic_install/"

var fails := 0
var want: Dictionary = {}


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var j := JSON.new()
	j.parse(FileAccess.get_file_as_string(FX + "erwartet.json"))
	want = j.data if j.data is Dictionary else {}
	print("Binäres Manifest (Fassung 18, gepackt)")
	_binary()
	print("Chunks und Zusammensetzen")
	_assemble()
	print("Fassung 22 (roh) und altes JSON")
	_v22_json()
	print("Chunk-Köpfe und verfälschte Chunks")
	_chunks()
	print("Bösartige Manifeste")
	_evil()
	print("Abgeschnitten und verfälscht (kein Absturz, nichts Falsches durch)")
	_fuzz()
	print("Pfade")
	_paths()
	print("Epics Antwort und erlaubte Server")
	_assets()
	print("Plan, Startparameter, Uzais Angaben")
	_plan_and_more()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _fx(name: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(FX + name)


func _binary() -> void:
	var r := M.parse(_fx("v18.manifest"))
	check(bool(r.ok), "liest sich (%s)" % str(r.error))
	if not bool(r.ok):
		return
	var m: Dictionary = r.m
	check(str(m.app) == "Probe" and str(m.build) == "1.2.3" and int(m.feature) == 18, "App, Fassung, Merkmal-Stufe")
	check(str(m.exe) == "Spiel/Start.exe" and str(m.args) == str(want.args), "Programmdatei und Startparameter")
	check(str(m.prereq_name) == "Visual C++" and str(m.prereq_path) == "Installers/vc.exe", "Voraussetzung nur gelesen (Name, Pfad)")
	var names := {}
	for f in m.files:
		names[str(f.name)] = str(f.sha)
	check(names.size() == 4 and names.has("Spiel/Ünïcödé Datei.txt"), "vier Dateien, Unicode-Name (UTF-16) richtig")
	var same := true
	for n in want.files.keys():
		same = same and str(names.get(n, "")) == str(want.files[n])
	check(same, "SHA-1 jeder Datei wie geschrieben")
	check((m.chunks as Array).size() == (want.chunks as Array).size(), "Zahl der Chunks")
	var paths_ok := true
	for i in (m.chunks as Array).size():
		paths_ok = paths_ok and str(m.chunks[i].path) == str(want.chunks[i].path18) and str(m.chunks[i].sha) == str(want.chunks[i].sha)
	check(paths_ok, "Chunk-Pfade (ChunksV4/Gruppe/Hash_GUID) und SHA-1 wie bei Epic")
	check(int(m.total) == 10000 + 3300 + 140, "Gesamtgröße der Dateien")


func _assemble() -> void:
	var r := M.parse(_fx("v18.manifest"))
	if not bool(r.ok):
		check(false, "Manifest fehlt")
		return
	var m: Dictionary = r.m
	var data: Array = []
	var all_ok := true
	for i in (m.chunks as Array).size():
		var d := M.decode_chunk(_fx("chunks/%d.chunk" % i), m.chunks[i])
		all_ok = all_ok and bool(d.ok)
		data.append(d.get("data", PackedByteArray()))
	check(all_ok, "alle Chunks (gepackt und roh) geprüft entpackt")
	var files_ok := true
	for f in m.files:
		var buf := PackedByteArray()
		for p in f.parts:
			buf.append_array((data[int(p[0])] as PackedByteArray).slice(int(p[1]), int(p[1]) + int(p[2])))
		files_ok = files_ok and M.sha1_hex(buf) == str(f.sha) and buf.size() == int(f.size)
	check(files_ok, "Dateien aus den Teilen zusammengesetzt: SHA-1 stimmt (auch die leere)")
	# Ein Chunk mit fremdem Inhalt an der richtigen Stelle: Prüfsumme greift.
	var swapped := M.decode_chunk(_fx("chunks/1.chunk"), m.chunks[0])
	check(not bool(swapped.ok), "Chunk an falscher Stelle abgelehnt (%s)" % str(swapped.error))


func _v22_json() -> void:
	var r := M.parse(_fx("v22_roh.manifest"))
	check(bool(r.ok) and int(r.m.feature) == 22, "Fassung 22 ungepackt liest sich")
	if bool(r.ok):
		var ok := true
		for i in (r.m.chunks as Array).size():
			ok = ok and str(r.m.chunks[i].path) == str(want.chunks[i].path22)
		check(ok, "Fassung 22: ChunksV5/plain/Gruppe/Base64-Namen")
		var d := M.decode_chunk(_fx("chunks/0.chunk"), r.m.chunks[0])
		check(bool(d.ok), "Chunk passt auch zur Fassung 22")
	var jr := M.parse(_fx("alt.json.manifest"))
	check(bool(jr.ok), "altes JSON-Manifest liest sich (%s)" % str(jr.error))
	if bool(jr.ok):
		var jm: Dictionary = jr.m
		check(str(jm.app) == "AltesSpiel" and int(jm.feature) == 13 and str(jm.exe) == "Alt/spiel.exe", "JSON: App, Stufe 13, Programmdatei")
		var ok2 := true
		for f in jm.files:
			ok2 = ok2 and str(want.json.files.get(str(f.name), "")) == str(f.sha)
		check(ok2 and (jm.files as Array).size() == 2, "JSON: Datei-Prüfsummen aus Blob-Zahlen")
		check(str(jm.chunks[0].path) == str(want.json.chunk.path) and str(jm.chunks[0].g) == str(want.json.chunk.guid), "JSON: Chunk-Pfad (ChunksV3) und GUID")
		var d2 := M.decode_chunk(_fx("alt_chunk.bin"), jm.chunks[0])
		check(bool(d2.ok) and (d2.data as PackedByteArray).size() == 1024 * 1024, "JSON: Chunk mit 1-MiB-Fenster")
	check(M.blob_int("013000000000") == 13 and M.blob_int("255001") == 511 and M.blob_int("256") == -1 and M.blob_int("12") == -1, "Blob-Zahlen streng")
	check(M.blob_bytes("001002003", 2).is_empty() and M.blob_bytes("001002000", 2) == PackedByteArray([1, 2]), "Blob länger als erwartet nur mit Nullen")


func _chunks() -> void:
	var r := M.parse(_fx("v18.manifest"))
	if not bool(r.ok):
		return
	var info: Dictionary = r.m.chunks[0]
	check(bool(M.decode_chunk(_fx("chunk_v2.bin"), info).ok), "Kopf Fassung 2")
	check(bool(M.decode_chunk(_fx("chunk_v4.bin"), info).ok), "Kopf Fassung 4 (ohne Schlüssel)")
	check(str(M.decode_chunk(_fx("chunk_verschluesselt.bin"), info).error) == "verschluesselt", "verschlüsselter Chunk abgelehnt")
	check(str(M.decode_chunk(_fx("chunk_falsche_guid.bin"), info).error) == "kaputt", "fremde GUID im Kopf abgelehnt")
	var raw := _fx("chunks/0.chunk")
	var flip := raw.duplicate()
	flip[flip.size() - 1] ^= 0xFF
	check(not bool(M.decode_chunk(flip, info).ok), "ein Byte verfälscht: abgelehnt")
	check(not bool(M.decode_chunk(raw.slice(0, 50), info).ok), "abgeschnitten: abgelehnt")
	var big := info.duplicate()
	big.win = 1024 * 1024
	check(not bool(M.decode_chunk(raw, big).ok), "andere Fenstergröße als im Manifest: abgelehnt")
	var nosha := info.duplicate()
	nosha.sha = M.ZERO_SHA
	check(bool(M.decode_chunk(raw, nosha).ok), "ohne SHA-1 im Manifest gilt die im Kopf")
	var wrong := info.duplicate()
	wrong.sha = "1".repeat(40)
	check(str(M.decode_chunk(raw, wrong).error) == "pruefsumme", "SHA-1 laut Manifest stimmt nicht: abgelehnt")
	var bomb := raw.duplicate()
	bomb.resize(raw.size() + 20000)
	check(not bool(M.decode_chunk(bomb, info).ok), "viel zu groß: abgelehnt")


func _evil() -> void:
	var cases := {
		"punktpunkt": "pfad", "absolut": "pfad", "laufwerk": "pfad", "rueckstrich": "pfad", "datenstrom": "pfad", "geraet": "pfad",
		"doppelt": "doppelt", "datei_als_ordner": "doppelt", "leerer_teil": "pfad", "punkt_am_ende": "pfad", "verknuepfung": "verknuepfung",
		"teil_ausserhalb": "kaputt", "fremde_guid": "kaputt", "ohne_pruefsumme": "pruefsumme", "verschluesselt": "verschluesselt",
		"kopf_pruefsumme": "pruefsumme", "riesige_anzahl": "grenze", "teil_kopf": "kaputt",
	}
	for k in cases.keys():
		var r := M.parse(_fx("boese_%s.manifest" % k))
		check(not bool(r.ok) and str(r.error) == str(cases[k]), "%s → %s (%s)" % [k, cases[k], str(r.error)])
	check(str(M.parse(PackedByteArray()).error) == "kaputt", "leer → kaputt")
	var huge := PackedByteArray()
	huge.resize(M.MAX_MANIFEST + 1)
	check(str(M.parse(huge).error) == "zu_gross", "über der Größengrenze → zu_gross, ohne zu lesen")
	check(not bool(M.parse("{\"FileManifestList\": 5}".to_utf8_buffer()).ok), "JSON mit falschen Typen")
	check(not bool(M.parse("{\"ChunkFilesizeList\":{\"ZZ\":\"001\"},\"ChunkHashList\":{},\"ChunkShaList\":{},\"DataGroupList\":{},\"FileManifestList\":[]}".to_utf8_buffer()).ok),
			"JSON mit kaputter GUID")


func _fuzz() -> void:
	var data := _fx("v18.manifest")
	var cut_ok := true
	for n in range(0, data.size(), 7):
		if bool(M.parse(data.slice(0, n)).ok):
			cut_ok = false
	check(cut_ok, "jede abgeschnittene Fassung abgelehnt")
	var raw := _fx("v22_roh.manifest")
	var body := raw.slice(73)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 7
	var crashes := 0
	var passed := 0
	for i in 400:
		var b := body.duplicate()
		for k in rnd.randi_range(1, 4):
			b[rnd.randi_range(0, b.size() - 1)] = rnd.randi_range(0, 255)
		var r := M._body(b)
		if not (r is Dictionary):
			crashes += 1
		elif bool(r.ok) and M.check(r.m) == "":
			passed += 1
			for f in r.m.files:
				if M.safe_path(str(f.name)) == "":
					crashes += 1
	check(crashes == 0, "400 verfälschte Inhalte: kein Absturz, kein unsicherer Pfad durch (%d gingen als gültig durch)" % passed)
	var cut_body := true
	for n in range(0, body.size(), 3):
		var r2 := M._body(body.slice(0, n))
		if bool(r2.ok) and M.check(r2.m) == "" and (r2.m.files as Array).size() == 4 and n < body.size() - 40:
			cut_body = false
	check(cut_body, "abgeschnittener Inhalt liefert nie die volle Liste")
	var flipped := raw.duplicate()
	flipped[100] ^= 0x01
	check(str(M.parse(flipped).error) == "pruefsumme", "ungepackt, ein Bit gekippt: Kopf-Prüfsumme greift")


func _paths() -> void:
	var good := { "a.txt": "a.txt", "Spiel\\Bin\\x.exe": "Spiel/Bin/x.exe", "Ünï/Grüße.txt": "Ünï/Grüße.txt", "a/b c/d.e": "a/b c/d.e",
		"Engine/.hidden": "Engine/.hidden", "CONFIG.ini": "CONFIG.ini" }
	for k in good.keys():
		check(M.safe_path(k) == str(good[k]), "gut: %s" % k)
	for bad in ["", "/etc/passwd", "\\\\server\\share\\x", "C:/x", "c:x", "a/../b", "..", "./a", "a//b", "a/", "a\u0001b", "a\nb",
			"a:b", "a|b", "a?b", "a*b", "a<b", "a\"b", "NUL", "nul.txt", "com1.log", "LPT9", "CONIN$", "a./b", "a /b", " a", "a" .repeat(1100)]:
		check(M.safe_path(bad) == "", "abgelehnt: %s" % bad.c_escape().left(40))


func _assets() -> void:
	var good := { "elements": [{ "appName": "Kinglet", "buildVersion": "1.0", "hash": "a".repeat(40), "manifests": [
		{ "uri": "https://download.epicgames.com/Builds/Org/o-1/x/default/a.manifest" },
		{ "uri": "https://epicgames-download1.akamaized.net/Builds/Org/o-1/x/default/a.manifest", "queryParams": [{ "name": "f_token", "value": "abc" }] },
		{ "uri": "https://evil.example.com/Builds/a.manifest" },
		{ "uri": "http://download.epicgames.com/Builds/a.manifest" },
		{ "uri": "https://download.epicgames.com.evil.net/a.manifest" },
		{ "uri": "https://user@download.epicgames.com/a.manifest" },
		{ "uri": "https://download.epicgames.com:8443/a.manifest" },
		{ "uri": "https://download.epicgames.com/../a.manifest" },
		{ "uri": "https://fastly-download.epicgames.com/a.manifest", "queryParams": [{ "name": "x", "value": "a b" }] },
	] }] }
	var a := M.parse_assets(good)
	check(bool(a.ok) and (a.urls as Array).size() == 2, "nur die zwei Adressen bei Epics Servern (%d)" % (a.urls as Array).size())
	check(str(a.urls[1]).ends_with("a.manifest?f_token=abc") and str(a.bases[0]) == "https://download.epicgames.com/Builds/Org/o-1/x/default",
			"queryParams angehängt, Basis ohne Dateinamen")
	var two := good.duplicate(true)
	(two.elements as Array).append(two.elements[0])
	check(not bool(M.parse_assets(two).ok), "mehr als ein Eintrag: abgelehnt (wie Legendary)")
	var nohash := good.duplicate(true)
	nohash.elements[0].hash = ""
	check(str(M.parse_assets(nohash).error) == "pruefsumme", "ohne SHA-1 des Manifests: abgelehnt")
	var only_evil := { "elements": [{ "hash": "b".repeat(40), "manifests": [{ "uri": "https://evil.example.com/a.manifest" }] }] }
	check(str(M.parse_assets(only_evil).error) == "adresse", "nur fremde Server: nichts")
	check(not bool(M.parse_assets("Unsinn").ok) and not bool(M.parse_assets({}).ok), "Unsinn")
	check(M.cdn_ok("https://cloudflare.epicgamescdn.com/x/y.chunk") and M.cdn_ok("https://egdownload.fastly-edge.epicgames.com/x"), "Epics CDN-Namen")
	check(not M.cdn_ok("https://akamaized.net/x") and not M.cdn_ok("https://evil.akamaized.net/x"), "fremde Kunden desselben CDN nicht")
	check(not M.cdn_ok("http://127.0.0.1:18789/cdn/x") and M.cdn_ok("http://127.0.0.1:18789/cdn/x", true), "Heimrechner nur in Netz-Proben")
	check(not M.cdn_ok("http://127.0.0.1:1/x y", true) and not M.cdn_ok("https://download.epicgames.com/a\\b"), "Leerzeichen und Rückstriche nicht")


func _plan_and_more() -> void:
	# Abbrechen: Eine neue Installation räumt alles weg – außer das Spiel liegt in genau diesem Ordner schon fertig.
	check(EI.aufraeum_art("install", "D:/Spiele/X", {}) == "install" and EI.aufraeum_art("install", "D:/Spiele/X", { "dir": "D:/Spiele/Y" }) == "install",
			"Abbrechen einer neuen Installation: alles laut Dateiliste fällt weg")
	check(EI.aufraeum_art("install", "D:/Spiele/X", { "dir": "D:/Spiele/X" }) == "update" and EI.aufraeum_art("update", "D:/Spiele/X", { "dir": "D:/Spiele/X" }) == "update"
			and EI.aufraeum_art("uninstall", "D:/Spiele/X", { "dir": "D:/Spiele/X" }) == "uninstall" and EI.aufraeum_art("install", "", { "dir": "" }) == "install",
			"Abbrechen über einem fertig installierten Spiel: nur die Zwischendateien")
	var r := M.parse(_fx("v18.manifest"))
	if not bool(r.ok):
		return
	var m: Dictionary = r.m
	var p := M.plan(m)
	check((p.files as Array).size() == 4 and (p.remove as Array).is_empty() and (p.chunks as Array).size() == (m.chunks as Array).size(), "neu: alles laden")
	var old := m.duplicate(true)
	old.files[1].sha = "2".repeat(40)
	old.files.append({ "name": "weg.txt", "sha": "3".repeat(40), "size": 1, "parts": [] })
	var u := M.plan(m, old)
	check((u.files as Array) == [1] and (u.remove as Array) == ["weg.txt"], "Update: nur die geänderte Datei, weggefallene löschen")
	check((u.chunks as Array).size() < (m.chunks as Array).size(), "Update: nur deren Chunks")
	var have := { "spiel/start.exe": str(m.files[0].sha) }
	check(not (M.plan(m, {}, have).files as Array).has(0), "geprüfte heile Datei nicht neu laden")
	var args := M.launch_args("-nosplash \"-pfad=C:\\Spiele\" -x&calc", "Probe", "ns1", "Spieler \"x", "acc1", "de")
	check(args.has("-nosplash") and not "\n".join(args).contains("calc") and not "\n".join(args).contains("C:\\"), "Startparameter aus dem Manifest gefiltert")
	check(args.has("-epicapp=Probe") and args.has("-EpicPortal") and args.has("-epicuserid=acc1") and args.has("-epiclocale=de"), "Epics übliche Angaben")
	check(not "\n".join(args).contains("Spieler") and not "\n".join(args).to_lower().contains("auth_password"), "kein unsicherer Name, nie ein Zugangs-Code")
	var list := [{ "id": "epic:Probe", "source": "epic", "installed": false, "epic": { "namespace": "ns1", "item": "i1", "app": "Probe" } },
		{ "id": "epic:Launcher", "source": "epic", "installed": true, "install_dir": "D:/L", "epic": { "app": "Launcher" } }]
	var recs := { "Probe": { "dir": "D:/Spiele/Probe", "exe": "Spiel/Start.exe", "account": "acc1" },
		"Launcher": { "dir": "D:/Spiele/L2", "exe": "a.exe", "account": "acc1" },
		"Fehlt": { "dir": "D:/Spiele/Fehlt", "exe": "f.exe", "account": "acc1", "title": "Fehlt", "ns": "n", "item": "i" },
		"Fremd": { "dir": "D:/Spiele/Fremd", "exe": "f.exe", "account": "anderes" } }
	var out := EI.apply_records(list, recs, "acc1")
	check(bool(out[0].installed) and str(out[0].path) == "D:/Spiele/Probe/Spiel/Start.exe" and bool(out[0].epic_uzai), "von Uzai installiert: startbar")
	check(str(out[1].install_dir) == "D:/L" and not out[1].has("epic_uzai"), "vom Launcher installiert: der gewinnt")
	check(out.size() == 3 and str(out[2].id) == "epic:Fehlt", "fehlendes Spiel dieses Kontos kommt dazu, fremdes nicht")
	var mask: Array = [0, 1, 1, 0, 1]
	check(EI._mask(EI._pack(PackedByteArray(mask)), 5) == mask, "gesicherter Stand: hin und zurück")
	check(EI._mask(EI._pack(PackedByteArray(mask)), 6) == [0, 0, 0, 0, 0, 0] and EI._mask("5:%%%", 5) == [0, 0, 0, 0, 0], "falscher Stand: alles offen")
	check(EI.base_problem("/gibt/es/nicht") != "", "Ordner, den es nicht gibt")
	var codes := ["anmeldung", "nicht_erreichbar", "kein_download", "server", "manifest", "verschluesselt", "pruefsumme", "pruefsumme_datei",
		"schreiben", "pfad", "adresse", "grenze", "kaputt"]
	var texts_ok := true
	for c in codes:
		var t := EI._error_text(c)
		texts_ok = texts_ok and t.length() > 20 and not t.contains("HTTP") and t.ends_with(".")
	check(texts_ok, "Fehler auf Deutsch, ohne Codes")
	var black := Image.create(64, 36, false, Image.FORMAT_RGB8)
	var shot := Image.create(64, 36, false, Image.FORMAT_RGB8)
	shot.fill(Color(0.1, 0.1, 0.12))
	shot.fill_rect(Rect2i(20, 10, 30, 12), Color(0.9, 0.9, 0.9))
	check(WR.dark(black) and not WR.dark(shot), "Fenster ohne Bild (schwarz) erkannt, echtes Bild nicht")
