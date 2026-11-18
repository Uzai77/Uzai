extends Node
## Netz-Probe für Downloads von Programmen (Punkt 74): nur https (http nur zu 127.0.0.1 in
## Proben mit UZAI_TEST_LOOPBACK=1), Prüfsummen-Listen lesen, Datei erst nach passender SHA-256
## an ihrem Platz.
## Startet dafür einen kleinen Python-Dateiserver auf 127.0.0.1.
## Aufruf: UZAI_DATA=<ordner> godot --headless --path . res://tests/net_downloads.tscn

const PORT := 18791

var fails := 0
var _srv := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await _run()
	if _srv > 0:
		OS.kill(_srv)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _run() -> void:
	print("Nur verschlüsselt")
	check(Net.download_allowed("https://github.com/a/b.zip") and Net.download_allowed("HTTPS://x/y"), "https erlaubt")
	check(not Net.download_allowed("http://github.com/a/b.zip") and not Net.download_allowed("ftp://x/y") and not Net.download_allowed("file:///C:/x.exe"),
			"http, ftp und Dateien nicht")
	check(not Net.download_allowed("http://127.0.0.1:18791/x") and not Net.download_allowed("http://localhost:18791/x"),
			"http zu diesem PC im Betrieb nicht (Bildadressen aus fremden Antworten)")
	OS.set_environment("UZAI_TEST_LOOPBACK", "1")
	check(Net.download_allowed("http://127.0.0.1:18791/x") and not Net.download_allowed("http://127.0.0.1.evil.com/x"),
			"http nur zu 127.0.0.1 mit Anschluss (Proben)")
	check(not await Net.download_big("http://example.com/x.exe", Config.path("tmp/x.exe")), "download_big lehnt http ab")

	print("Prüfsummen-Listen")
	var a64 := "a".repeat(64)
	var b64 := "B".repeat(64)
	var sums := "%s  yt-dlp\n%s *yt-dlp.exe\n%s  yt-dlp_linux\n" % [a64, b64, "c".repeat(64)]
	check(Net.sha_for(sums, "yt-dlp.exe") == b64.to_lower() and Net.sha_for(sums, "yt-dlp") == a64, "SHA2-256SUMS: richtige Zeile je Datei (auch mit *)")
	check(Net.sha_for(sums, "yt-dlp.ex") == "" and Net.sha_for("kaputt", "yt-dlp.exe") == "", "fehlende Datei: keine Prüfsumme")
	var ps := "\r\nAlgorithm       Hash                                                                   Path\r\n---------       ----                                                                   ----\r\nSHA256          %s       D:\\a\\deno.zip\r\n" % "0123456789ABCDEF".repeat(4)
	check(Net.first_sha(ps) == "0123456789abcdef".repeat(4), "Deno (Get-FileHash-Format): Prüfsumme gefunden")
	check(Net.first_sha("abc " + "f".repeat(65)) == "" and Net.first_sha("") == "", "zu lange oder keine Hex-Folge: nichts")
	check(Net.github_digest({ "digest": "sha256:" + a64 }) == a64 and Net.github_digest({ "digest": "sha1:abc" }) == "" and Net.github_digest({}) == "",
			"GitHub-„digest“: nur sha256")

	print("Laden mit Prüfung")
	var dir := Config.path("dl_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var payload := "Uzai-Testdatei ".repeat(500).to_utf8_buffer()
	var f := FileAccess.open(dir.path_join("tool.bin"), FileAccess.WRITE)
	f.store_buffer(payload)
	f.close()
	var good := FileAccess.get_sha256(dir.path_join("tool.bin"))
	_srv = OS.create_process("python3",
			PackedStringArray(["-m", "http.server", str(PORT), "--bind", "127.0.0.1", "--directory", ProjectSettings.globalize_path(dir)]))
	await get_tree().create_timer(1.5).timeout
	var url := "http://127.0.0.1:%d/tool.bin" % PORT
	var dest := Config.path("dl_out/tool.exe")
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var why := await Net.download_verified(url, dest, "0".repeat(64))
	check(why.contains("Prüfsumme") and not FileAccess.file_exists(dest) and not FileAccess.file_exists(dest + ".pruefen"),
			"falsche Prüfsumme: nichts installiert, nichts liegen gelassen (%s)" % why)
	why = await Net.download_verified(url, dest, "")
	check(why.contains("Keine Prüfsumme") and not FileAccess.file_exists(dest), "ohne Prüfsumme: gar nicht erst geladen")
	why = await Net.download_verified(url, dest, good.to_upper())
	check(why == "" and FileAccess.get_sha256(dest) == good, "passende Prüfsumme: Datei an ihrem Platz (%s)" % why)
	var txt := await Net.get_text("http://127.0.0.1:%d/tool.bin" % PORT)
	check(txt.begins_with("Uzai-Testdatei"), "Prüfsummen-Liste als Text geladen")
	check(await Net.get_text("http://example.com/SHA2-256SUMS") == "", "Prüfsummen-Liste nur über https")
