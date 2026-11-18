extends Node
## Rechte der Filme-Plugins (Punkte 131, 72, 73): Deno lässt fremden Plugin-Code nur ins Internet
## und nur die eigenen Dateien lesen. Mit UZAI_TEST_DENO=<pfad zu deno> läuft ein Probeskript mit
## genau Uzais Aufruf und versucht alles, was ein bösartiges Plugin versuchen würde.
## Aufruf: UZAI_TEST_DENO=… godot --headless --path . res://tests/logic_plugin_rechte.tscn

const MoviesS := preload("res://src/core/movies.gd")

const PROBE := """
const job = Deno.args[0];
const outside = job.split("/").slice(0, -2).join("/") + "/aussen.txt";
const out = {};
const t = async (k, f) => { try { await f(); out[k] = "erlaubt"; } catch (e) { out[k] = String(e?.cause?.message ?? e?.message ?? e).includes("Requires") || e?.name === "NotCapable" ? "gesperrt" : "fehler: " + e?.name; } };
await t("lesen_eigen", () => Deno.readTextFileSync(job));
await t("lesen_fremd", () => Deno.readTextFileSync(outside));
await t("schreiben", () => Deno.writeTextFileSync(job + ".neu", "x"));
await t("umgebung", () => Deno.env.get("PATH"));
await t("programm", () => new Deno.Command("whoami").outputSync());
await t("loopback", () => fetch("http://127.0.0.1:8080/"));
await t("localhost", () => fetch("http://localhost:8080/"));
await t("heimnetz", () => fetch("http://192.168.178.1/"));
await t("ipv6_loopback", () => fetch("http://[::1]:8080/"));
await t("mapped", () => fetch("http://[::ffff:127.0.0.1]:8080/"));
await t("roh", () => Deno.connect({ hostname: "10.0.0.1", port: 80 }));
await t("nachladen", () => import("https://example.com/plugin.js"));
console.log(JSON.stringify(out));
"""

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _gd_dateien(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_dateien(dir.path_join(d)))
	return out


func _ready() -> void:
	print("Aufruf")
	var a := MoviesS.deno_args("/d/runtime/runner.js", "/d/runtime/auftrag.json", PackedStringArray(["/d/runtime", "/d/plugins"]))
	check(a.has("--allow-read=/d/runtime,/d/plugins") and a.has("--allow-net") and a.has("--deny-net=" + MoviesS.PLUGIN_DENY_NET),
			"Netz ohne Heimnetz, lesen nur Runner und Skripte")
	check(a.has("--no-remote") and a.has("--no-npm") and a.has("--no-prompt"), "kein Nachladen, keine Rückfragen")
	check(
			not Array(a).any(func(x: String) -> bool: return x.begins_with("--allow-write") or x.begins_with("--allow-run") or x.begins_with(
			"--allow-env") or x.begins_with("--allow-ffi") or x.begins_with("--allow-sys") or x == "-A" or x == "--allow-all"),
			"kein Schreiben, keine Programme, keine Umgebung")
	check(MoviesS.deno_args("r", "j", PackedStringArray(["C:/Users/a,b/Uzai"])).is_empty(), "Pfad mit Komma: lieber gar nicht als ungenau")
	for net in ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "[::1]", "localhost"]:
		check(MoviesS.PLUGIN_DENY_NET.split(",").has(net), "gesperrt: " + net)
	print("Test-Umleitungen")
	# Umgebungsvariablen UZAI_… lenken für Proben Adressen der Dienste um, wählen einen anderen Helfer oder eine
	# andere JavaScript-Laufzeit (ohne Deno-Absicherung). Im ausgelieferten Programm gelten sie nicht.
	OS.set_environment("UZAI_PROBE_REGEL", "http://fremd.example")
	check(Config.probe_env("UZAI_PROBE_REGEL", false) == "", "ausgeliefert: eine gesetzte Variable gilt nicht")
	check(Config.probe_env("UZAI_PROBE_REGEL", true) == "http://fremd.example" and Config.probe_env("UZAI_PROBE_REGEL") == "http://fremd.example",
			"Entwickler-Fassung (so laufen die Tests): sie gilt")
	OS.unset_environment("UZAI_PROBE_REGEL")
	var offen := PackedStringArray()
	var re := RegEx.create_from_string("OS\\.get_environment\\(\\s*\"UZAI_(?!DATA\")")
	for f in _gd_dateien("res://src"):
		if re.search(FileAccess.get_file_as_string(f)) != null:
			offen.append(f)
	check(offen.is_empty(), "keine Stelle in src liest eine Test-Umleitung an Config.probe_env vorbei: " + ", ".join(offen))
	var deno := OS.get_environment("UZAI_TEST_DENO")
	if deno == "" or not FileAccess.file_exists(deno):
		print("  –    ohne UZAI_TEST_DENO kein Probelauf")
	else:
		_probe(deno)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _probe(deno: String) -> void:
	print("Probelauf mit Deno")
	var base := OS.get_user_data_dir().path_join("plugin_rechte")
	var dir := base.path_join("runtime")
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("probe.js"), PROBE)
	_write(dir.path_join("auftrag.json"), "{}")
	_write(base.path_join("aussen.txt"), "geheim")
	OS.set_environment("DENO_DIR", base.path_join("cache"))
	var out: Array = []
	OS.execute(deno, MoviesS.deno_args(dir.path_join("probe.js"), dir.path_join("auftrag.json"), PackedStringArray([dir])), out, true)
	var res: Dictionary = {}
	for line in str(out[0] if not out.is_empty() else "").split("\n"):
		var j := JSON.new()
		if line.begins_with("{") and j.parse(line) == OK and j.data is Dictionary:
			res = j.data
	check(res.get("lesen_eigen") == "erlaubt", "eigene Dateien lesen")
	for k in ["lesen_fremd", "schreiben", "umgebung", "programm", "loopback", "localhost", "heimnetz", "ipv6_loopback", "mapped", "roh", "nachladen"]:
		check(res.get(k) == "gesperrt", "gesperrt: %s (%s)" % [k, res.get(k, "keine Antwort")])


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
