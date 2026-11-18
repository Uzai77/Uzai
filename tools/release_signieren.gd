extends SceneTree
## Releases für das Selbst-Update signieren (src/core/updater.gd, docs/SECURITY.md „Updates“).
## Der private Schlüssel liegt NIE im Projekt und nie im Repository – nur beim Herausgeber.
##
##   godot --headless --path . --script res://tools/release_signieren.gd -- --neu <außerhalb/uzai-release.pem>
##       Neues RSA-4096-Schlüsselpaar. Der private Teil landet in der Datei (nur außerhalb des Projekts, nie
##       überschrieben); der öffentliche wird ausgegeben und gehört als SCHLUESSEL in src/core/updater.gd.
##   godot --headless --path . --script res://tools/release_signieren.gd -- --signieren <privat.pem> <Uzai-X.Y.Z-windows.zip>
##       Schreibt <zip>.sig (JSON: format, version, datei, sha256, signatur) und prüft sie gleich mit dem öffentlichen
##       Teil nach. Beide Dateien gehören ins Release (Tag vX.Y.Z).

const UP := preload("res://src/core/update_pruefung.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var code := 1
	if a.size() == 2 and a[0] == "--neu":
		code = _neu(a[1])
	elif a.size() == 3 and a[0] == "--signieren":
		code = _signieren(a[1], a[2])
	else:
		print("Aufruf: --neu <privat.pem> | --signieren <privat.pem> <Uzai-X.Y.Z-windows.zip>")
	quit(code)


func _im_projekt(pfad: String) -> bool:
	var p := ProjectSettings.globalize_path(pfad).simplify_path().to_lower().replace("\\", "/")
	var proj := ProjectSettings.globalize_path("res://").simplify_path().to_lower().replace("\\", "/")
	return p.begins_with(proj)


func _neu(pfad: String) -> int:
	if _im_projekt(pfad):
		print("FEHLER: Der private Schlüssel darf nicht ins Projekt (", pfad, ").")
		return 1
	if FileAccess.file_exists(pfad):
		print("FEHLER: ", pfad, " gibt es schon – wird nie überschrieben.")
		return 1
	var key := Crypto.new().generate_rsa(4096)
	if key.save(pfad) != OK:
		print("FEHLER: Ließ sich nicht speichern: ", pfad)
		return 1
	print("Privater Schlüssel: ", pfad, "  (sicher aufbewahren, nie teilen, nie ins Repository)")
	print("Öffentlicher Schlüssel für SCHLUESSEL in src/core/updater.gd:")
	print(key.save_to_string(true))
	return 0


func _signieren(privat_pfad: String, zip: String) -> int:
	var datei := zip.get_file()
	var m := RegEx.create_from_string("^Uzai-([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,4})-windows\\.zip$").search(datei)
	if m == null or not FileAccess.file_exists(zip):
		print("FEHLER: Paket muss Uzai-X.Y.Z-windows.zip heißen und da sein: ", zip)
		return 1
	var privat := privat_im_paket(zip)
	if privat != "":
		print("FEHLER: ", privat, " – ein öffentliches Release darf das nicht enthalten (UZAI_PRIVAT-Paket?). Nicht signiert.")
		return 1
	var key := CryptoKey.new()
	if key.load(privat_pfad) != OK:
		print("FEHLER: Privater Schlüssel nicht lesbar: ", privat_pfad)
		return 1
	var f := m.get_string(1)
	var sha := FileAccess.get_sha256(zip).to_lower()
	var sig := UP.signieren(f, datei, sha, key)
	var oeffentlich := key.save_to_string(true)
	var probe := UP.signatur_pruefen(sig, f, datei, oeffentlich)
	if not bool(probe.ok):
		print("FEHLER: Probe der eigenen Signatur: ", probe.grund)
		return 1
	var out := FileAccess.open(zip + ".sig", FileAccess.WRITE)
	out.store_string(JSON.stringify(sig, "  "))
	out.close()
	print("Signiert: ", datei, "  Fassung ", f, "  SHA-256 ", sha)
	print("Ins Release (Tag v", f, "): ", datei, " und ", datei, ".sig")
	return 0


## Steckt Privates im Paket? Der ScreenScraper-Programmzugang (data/screenscraper_dev.json) gehört nur in eigene Pakete
## (UZAI_PRIVAT=1); in der Uzai.pck steht sein Pfad im Verzeichnis lesbar. "" = sauber, sonst der Grund.
static func privat_im_paket(zip: String) -> String:
	var z := ZIPReader.new()
	if z.open(zip) != OK:
		return "Paket nicht lesbar"
	var namen := z.get_files()
	if not "Uzai.pck" in namen:
		z.close()
		return "Paket ohne Uzai.pck"
	for n in namen:
		if str(n).get_file() == "screenscraper_dev.json":
			z.close()
			return "screenscraper_dev.json im Paket"
	var pck := z.read_file("Uzai.pck")
	z.close()
	return "ScreenScraper-Programmzugang in Uzai.pck" if enthaelt(pck, "screenscraper_dev.json".to_utf8_buffer()) else ""


static func enthaelt(daten: PackedByteArray, nadel: PackedByteArray) -> bool:
	if nadel.is_empty():
		return false
	var i := daten.find(nadel[0])
	while i >= 0 and i + nadel.size() <= daten.size():
		if (nadel.size() < 2 or daten[i + 1] == nadel[1]) and daten.slice(i, i + nadel.size()) == nadel:
			return true
		i = daten.find(nadel[0], i + 1)
	return false
