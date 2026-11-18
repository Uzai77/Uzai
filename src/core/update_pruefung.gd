extends RefCounted
## Reine Teile des Selbst-Updates (src/core/updater.gd), ohne Dienste: Fassungen vergleichen, Pakete im Release
## finden, Signatur prüfen, Paket entpacken, Auftrag für den Helfer. Dieselben Teile nutzt tools/release_signieren.gd
## (die Nachricht, die signiert wird), geprüft von tests/logic_updater.gd.

const Fremd := preload("res://src/core/fremd.gd")

## Nur diese Dateien kommen aus einem Paket (ohne Ordner, genau so geschrieben).
const ERLAUBT := ["Uzai.exe", "Uzai.pck", "discord_partner_sdk.dll"]
const PFLICHT := ["Uzai.exe", "Uzai.pck"]

static var _RX_FASSUNG := RegEx.create_from_string("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,4}$")


## „v0.16.91“ → „0.16.91“, sonst "".
static func fassung_aus_tag(tag: String) -> String:
	var t := tag.strip_edges().trim_prefix("v").trim_prefix("V")
	return t if _RX_FASSUNG.search(t) != null else ""


## Ist a neuer als b? (Zahl für Zahl.)
static func neuer(a: String, b: String) -> bool:
	if _RX_FASSUNG.search(a) == null:
		return false
	var x := a.split(".")
	var y := b.split(".")
	for i in 3:
		var u := int(x[i])
		var v := int(y[i]) if i < y.size() else 0
		if u != v:
			return u > v
	return false


static func paket_name(f: String) -> String:
	return "Uzai-%s-windows.zip" % f


## Ein Paket des Releases mit genau diesem Namen, geladen nur von den Releases dieses Repositorys.
static func asset_finden(rel: Dictionary, name_: String, repo: String) -> Dictionary:
	var vorne := "https://github.com/%s/releases/download/" % repo
	for a in Fremd.zeilen(rel.get("assets")):
		if str(a.get("name", "")) == name_ and str(a.get("browser_download_url", "")).begins_with(vorne) and int(a.get("size", 0)) > 0:
			return a
	return {}


## Was signiert wird: Format, Fassung, Dateiname und Prüfsumme – eine Signatur passt nur zu genau diesem Paket.
static func nachricht(f: String, datei: String, sha256: String) -> String:
	return "uzai-update:1\n%s\n%s\n%s\n" % [f, datei, sha256.to_lower()]


## Signatur-Datei prüfen (JSON: format, version, datei, sha256, signatur). { ok, sha256, grund }.
static func signatur_pruefen(sig: Variant, f: String, datei: String, pem: String) -> Dictionary:
	if pem.strip_edges() == "":
		return _nein("kein Schlüssel in Uzai")
	if not (sig is Dictionary):
		return _nein("keine Signatur")
	var s: Dictionary = sig
	var sha := str(s.get("sha256", "")).to_lower()
	if int(s.get("format", 0)) != 1 or str(s.get("version", "")) != f or str(s.get("datei", "")) != datei:
		return _nein("passt nicht zu diesem Release")
	if sha.length() != 64 or not sha.is_valid_hex_number():
		return _nein("Prüfsumme fehlt")
	var roh := Marshalls.base64_to_raw(str(s.get("signatur", "")))
	if roh.size() < 128 or roh.size() > 1024:
		return _nein("Signatur fehlt")
	var key := CryptoKey.new()
	if key.load_from_string(pem, true) != OK:
		return _nein("Schlüssel in Uzai unlesbar")
	if not Crypto.new().verify(HashingContext.HASH_SHA256, nachricht(f, datei, sha).sha256_buffer(), roh, key):
		return _nein("Signatur passt nicht")
	return { "ok": true, "sha256": sha, "grund": "" }


static func _nein(g: String) -> Dictionary:
	return { "ok": false, "sha256": "", "grund": g }


## Signatur-Datei zu einem Paket (für tools/release_signieren.gd und die Proben).
static func signieren(f: String, datei: String, sha256: String, privat: CryptoKey) -> Dictionary:
	var roh := Crypto.new().sign(HashingContext.HASH_SHA256, nachricht(f, datei, sha256).sha256_buffer(), privat)
	return { "format": 1, "version": f, "datei": datei, "sha256": sha256.to_lower(), "signatur": Marshalls.raw_to_base64(roh) }


## Nur die erlaubten Dateien aus dem Paket, flach in ordner. { ok, dateien, groessen, sha256, grund }; groessen und
## sha256 je Datei, damit vor dem Einspielen (bereit_fassung, Helfer) nichts Halbes durchrutscht. Läuft im Hilfsfaden.
static func entpacken(zip: String, ordner: String) -> Dictionary:
	var z := ZIPReader.new()
	if z.open(zip) != OK:
		return { "ok": false, "dateien": [], "grund": "nicht lesbar" }
	var gut: Array = []
	for n in z.get_files():
		if n.ends_with("/"):
			continue
		if not (n in ERLAUBT):
			z.close()
			return { "ok": false, "dateien": [], "grund": "fremde Datei im Paket" }
		gut.append(n)
	for p in PFLICHT:
		if not (p in gut):
			z.close()
			return { "ok": false, "dateien": [], "grund": "unvollständig" }
	if DirAccess.dir_exists_absolute(ordner):
		for alt in DirAccess.get_files_at(ordner):
			DirAccess.remove_absolute(ordner.path_join(alt))
	DirAccess.make_dir_recursive_absolute(ordner)
	var groessen := {}
	var sha := {}
	for n in gut:
		var daten := z.read_file(n)
		var pfad := ordner.path_join(n)
		var f := FileAccess.open(pfad, FileAccess.WRITE)
		if f == null:
			z.close()
			return { "ok": false, "dateien": [], "grund": "nicht schreibbar" }
		var geschrieben := f.store_buffer(daten)
		f.close()
		# Platte voll oder Lesefehler im Paket: Eine halbe Uzai.pck darf nie eingespielt werden – darum die Datei auf
		# der Platte gegen die Bytes aus dem (signierten) Paket prüfen.
		var soll := sha256_von(daten)
		if daten.is_empty() or not geschrieben or FileAccess.get_sha256(pfad).to_lower() != soll:
			z.close()
			DirAccess.remove_absolute(pfad)
			return { "ok": false, "dateien": [], "grund": "nicht ganz geschrieben (Platte voll?)" }
		groessen[n] = daten.size()
		sha[n] = soll
	z.close()
	return { "ok": true, "dateien": gut, "groessen": groessen, "sha256": sha, "grund": "" }


static func sha256_von(daten: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(daten)
	return h.finish().hex_encode()


## Liegt ein entpacktes Update noch genau so da? (Größe je Datei; die volle Prüfsumme rechnet der Helfer vor dem Tausch.)
static func bereit_ok(b: Variant) -> bool:
	if not (b is Dictionary):
		return false
	var dateien: Variant = b.get("dateien")
	var groessen: Variant = b.get("groessen")
	var sha: Variant = b.get("sha256")
	if not (dateien is Array) or not (groessen is Dictionary) or not (sha is Dictionary):
		return false
	for p in PFLICHT:
		if not (p in dateien):
			return false
	for d in dateien:
		var pfad := str(b.get("ordner", "")).path_join(str(d))
		if not (str(d) in ERLAUBT) or str(sha.get(d, "")).length() != 64 or int(groessen.get(d, -1)) <= 0:
			return false
		var f := FileAccess.open(pfad, FileAccess.READ)
		if f == null or f.get_length() != int(groessen[d]):
			return false
	return true


## Auftrag für den Helfer (-Update): Windows-Pfade, nur erlaubte Dateien, je Datei die Prüfsumme (der Helfer prüft
## sie vor dem Tausch).
static func auftrag(pid: int, exe: String, ordner: String, dateien: Array, f: String, neu: bool, ergebnis: String, sha: Dictionary) -> Dictionary:
	var nur := dateien.filter(func(d: Variant) -> bool: return str(d) in ERLAUBT)
	var pruef := {}
	for d in nur:
		pruef[str(d)] = str(sha.get(d, "")).to_lower()
	return { "pid": pid, "dir": exe.get_base_dir().replace("/", "\\"), "ordner": ordner.replace("/", "\\"), "fassung": f, "neu_starten": neu,
		"dateien": nur, "sha256": pruef, "ergebnis": ergebnis.replace("/", "\\") }


## Darf Uzai neben sich schreiben? (Nicht unter „Programme“ ohne Rechte.)
static func ordner_beschreibbar(dir: String) -> bool:
	var p := dir.path_join(".uzai-schreibprobe")
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(p)
	return true
