extends Node
## Selbst-Update (src/core/update_pruefung.gd, src/core/updater.gd): Fassungen, Pakete im Release, Signatur mit
## einem Probe-Schlüssel (in dieser Probe erzeugt, nirgends gespeichert), Entpacken nur erlaubter Dateien, Auftrag
## für den Helfer. Schreibt nur in einen eigenen Ordner im Temp-Ordner des Systems und räumt ihn wieder weg.
## Aufruf: godot --headless --path . res://tests/logic_updater.tscn

const UP := preload("res://src/core/update_pruefung.gd")
const SysS := preload("res://src/ui/sections/settings_system.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_fassungen()
	_release()
	_signatur()
	_entpacken()
	_auftrag()
	print("Im Programm")
	var m := FileAccess.get_file_as_string("res://src/main.gd")
	var a := m.find("func _start_services(")
	var body := m.substr(a, m.find("\nfunc ", a + 5) - a)
	var nach_zweigen := body.substr(body.find("\n\telse:"))
	check(nach_zweigen.contains("updater = load(\"res://src/core/updater.gd\")"), "Updater entsteht auch mit Startanimation (nach dem if/else)")
	var u := FileAccess.get_file_as_string("res://src/core/updater.gd")
	a = u.find("func pruefen(")
	var pr := u.substr(a, u.find("\nfunc ", a + 5) - a)
	check(pr.find("zustand[\"geprueft\"]") > pr.find("UP.fassung_aus_tag"), "nur ein gelungener Blick zählt als geprüft")
	a = u.find("func laden(")
	var ld := u.substr(a, u.find("\nfunc ", a + 5) - a)
	check(ld.contains("str(b0.get(\"ordner\", \"\")) == ordner") and u.contains("bool(zustand.get(\"pruef_fehler\", false))"),
		"bereites älteres Update bleibt beim Entpacken eines neuen; schneller Neuversuch nur, wenn GitHub nicht erreichbar war")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _fassungen() -> void:
	print("Fassungen")
	check(UP.fassung_aus_tag("v0.16.91") == "0.16.91" and UP.fassung_aus_tag("0.17.0") == "0.17.0", "Tag mit und ohne v")
	check(UP.fassung_aus_tag("v0.16.91-beta") == "" and UP.fassung_aus_tag("../1.2.3") == "" and UP.fassung_aus_tag("") == "", "fremde Tags: nichts")
	check(UP.neuer("0.16.91", "0.16.90") and UP.neuer("0.17.0", "0.16.99") and UP.neuer("1.0.0", "0.99.999"), "neuer: Zahl für Zahl")
	check(not UP.neuer("0.16.90", "0.16.90") and not UP.neuer("0.16.9", "0.16.10") and not UP.neuer("kaputt", "0.1.0"), "nicht neuer: gleich, älter, kaputt")
	check(SysS.update_text({ "neueste": "0.16.91", "geprueft": 1 }, false, "0.16.90") == "Uzai 0.16.91 ist da."
			and SysS.update_text({ "neueste": "0.16.90", "geprueft": 1 }, false, "0.16.90") == "Aktuell.", "Zeile in den Einstellungen")


func _release() -> void:
	print("Pakete im Release")
	var rel := { "assets": [
		{ "name": "Uzai-0.16.91-windows.zip", "size": 1000,
			"browser_download_url": "https://github.com/Uzai77/Uzai/releases/download/v0.16.91/Uzai-0.16.91-windows.zip" },
		{ "name": "Uzai-0.16.91-windows.zip.sig", "size": 500, "browser_download_url": "https://evil.example/Uzai-0.16.91-windows.zip.sig" },
		{ "name": "Uzai-0.16.91-windows.zip.sig", "size": 500, "browser_download_url": "https://github.com/Fremd/Uzai/releases/download/v0.16.91/x.sig" },
	] }
	check(not UP.asset_finden(rel, UP.paket_name("0.16.91"), "Uzai77/Uzai").is_empty(), "Paket vom eigenen Repository gefunden")
	check(UP.asset_finden(rel, UP.paket_name("0.16.91") + ".sig", "Uzai77/Uzai").is_empty(), "Signatur von fremdem Server oder fremdem Repository: nicht genommen")
	check(UP.asset_finden({ "assets": "kaputt" }, "x", "Uzai77/Uzai").is_empty(), "kaputte Antwort: nichts")


func _signatur() -> void:
	print("Signatur")
	var key := Crypto.new().generate_rsa(2048)
	var pem := key.save_to_string(true)
	var sha := "ab".repeat(32)
	var datei := UP.paket_name("0.16.91")
	var sig := UP.signieren("0.16.91", datei, sha, key)
	check(bool(UP.signatur_pruefen(sig, "0.16.91", datei, pem).ok) and str(UP.signatur_pruefen(sig, "0.16.91", datei, pem).sha256) == sha,
		"echte Signatur: ok, Prüfsumme übernommen")
	check(not bool(UP.signatur_pruefen(sig, "0.16.91", datei, "").ok), "ohne Schlüssel in Uzai: nie ok")
	var fremd := Crypto.new().generate_rsa(2048).save_to_string(true)
	check(not bool(UP.signatur_pruefen(sig, "0.16.91", datei, fremd).ok), "anderer Schlüssel: abgelehnt")
	var falsch: Dictionary = sig.duplicate()
	falsch["sha256"] = "cd".repeat(32)
	check(not bool(UP.signatur_pruefen(falsch, "0.16.91", datei, pem).ok), "andere Prüfsumme (anderes Paket): abgelehnt")
	var alt: Dictionary = sig.duplicate()
	alt["version"] = "0.16.92"
	check(not bool(UP.signatur_pruefen(alt, "0.16.92", UP.paket_name("0.16.92"), pem).ok), "alte Signatur für neue Fassung: abgelehnt")
	check(not bool(UP.signatur_pruefen(sig, "0.16.92", datei, pem).ok), "Signatur passt nicht zur Fassung des Releases: abgelehnt")
	check(not bool(UP.signatur_pruefen("kaputt", "0.16.91", datei, pem).ok) and not bool(UP.signatur_pruefen({ "format": 1 }, "0.16.91", datei, pem).ok),
		"kaputte Signatur-Datei: abgelehnt")


func _entpacken() -> void:
	print("Entpacken")
	# Im Temp-Ordner des Systems, nie in Uzais Datenordner (user:// zeigt bei Uzai auf die echten Daten).
	var temp := OS.get_environment("TEMP") if OS.get_environment("TEMP") != "" else "/tmp"
	var wurzel := temp.replace("\\", "/").path_join("uzai_probe_updater_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(wurzel)
	var gut := _zip(wurzel.path_join("gut.zip"), { "Uzai.exe": "EXE", "Uzai.pck": "PCK", "discord_partner_sdk.dll": "DLL" })
	var e := UP.entpacken(gut, wurzel.path_join("gut"))
	check(bool(e.ok) and (e.dateien as Array).size() == 3 and FileAccess.get_file_as_string(wurzel.path_join("gut/Uzai.pck")) == "PCK",
			"erlaubte Dateien entpackt")
	check(int(e.groessen["Uzai.pck"]) == 3 and str(e.sha256["Uzai.pck"]) == FileAccess.get_sha256(wurzel.path_join("gut/Uzai.pck")).to_lower(),
		"je Datei Größe und Prüfsumme gemerkt")
	var b := { "fassung": "9.9.9", "ordner": wurzel.path_join("gut"), "dateien": e.dateien, "groessen": e.groessen, "sha256": e.sha256 }
	check(UP.bereit_ok(b), "bereit: alles da, Größen stimmen")
	var f := FileAccess.open(wurzel.path_join("gut/Uzai.pck"), FileAccess.WRITE)
	f.store_string("P")
	f.close()
	check(not UP.bereit_ok(b), "halbe Uzai.pck (Platte voll, abgebrochen): nicht bereit")
	check(not UP.bereit_ok({ "fassung": "9.9.9", "ordner": wurzel.path_join("gut"), "dateien": e.dateien }), "alter Eintrag ohne Prüfsummen: nicht bereit")
	var boese := _zip(wurzel.path_join("boese.zip"), { "Uzai.exe": "EXE", "Uzai.pck": "PCK", "../../evil.exe": "X" })
	check(not bool(UP.entpacken(boese, wurzel.path_join("boese")).ok) and not FileAccess.file_exists(wurzel.path_join("evil.exe")),
			"Pfad-Trick im Paket: abgelehnt, nichts geschrieben")
	var fremd := _zip(wurzel.path_join("fremd.zip"), { "Uzai.exe": "EXE", "Uzai.pck": "PCK", "version.dll": "X" })
	check(not bool(UP.entpacken(fremd, wurzel.path_join("fremd")).ok), "fremde DLL im Paket: abgelehnt")
	var halb := _zip(wurzel.path_join("halb.zip"), { "Uzai.exe": "EXE" })
	check(not bool(UP.entpacken(halb, wurzel.path_join("halb")).ok), "ohne Uzai.pck: abgelehnt")
	print("Signieren: nie ein Paket mit dem ScreenScraper-Programmzugang")
	var RS: GDScript = load("res://tools/release_signieren.gd")
	var privat := _zip(wurzel.path_join("Uzai-9.9.9-windows.zip"),
			{ "Uzai.exe": "EXE", "Uzai.pck": "GDPC\u0001xx" + "res://data/screenscraper_dev.json" + "\u0001yy" })
	check(str(RS.privat_im_paket(privat)) != "" and str(RS.privat_im_paket(gut)) == "", "privates Paket erkannt, sauberes durchgelassen")
	check(FileAccess.get_file_as_string("res://export_presets.cfg").contains("data/screenscraper_dev.json\""), "Export schließt den Programmzugang aus")
	_weg(wurzel)


func _auftrag() -> void:
	print("Auftrag für den Helfer")
	var sha := { "Uzai.exe": "A".repeat(64), "Uzai.pck": "b".repeat(64), "boese.dll": "c".repeat(64) }
	var j := UP.auftrag(42, "C:/Spiele/Uzai/Uzai.exe", "C:/Users/a/AppData/Roaming/Uzai/update/0.16.91", ["Uzai.exe", "Uzai.pck", "boese.dll"], "0.16.91",
		true, "C:/Users/a/AppData/Roaming/Uzai/update/ergebnis.json", sha)
	check((j.sha256 as Dictionary).keys() == ["Uzai.exe", "Uzai.pck"] and str(j.sha256["Uzai.exe"]) == "a".repeat(64),
			"Prüfsummen für den Helfer, nur erlaubte Dateien")
	check(str(j.dir) == "C:\\Spiele\\Uzai" and str(j.ordner).ends_with("update\\0.16.91") and (j.dateien as Array) == ["Uzai.exe", "Uzai.pck"]
			and bool(j.neu_starten) and int(j.pid) == 42, "Windows-Pfade, nur erlaubte Dateien")


func _zip(pfad: String, inhalt: Dictionary) -> String:
	var z := ZIPPacker.new()
	z.open(pfad)
	for n in inhalt.keys():
		z.start_file(str(n))
		z.write_file(str(inhalt[n]).to_utf8_buffer())
		z.close_file()
	z.close()
	return pfad


func _weg(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_weg(dir.path_join(d))
	DirAccess.remove_absolute(dir)
