extends Node
## Wächter für den Konsistenz-Durchgang (Roadmap 62):
## - Fehlermeldungen sagen, was passiert ist und was man tun kann – ohne rohe Codes (HTTP 403,
##   EResult 5, 0x80070005) und ohne englische Systemmeldungen des Windows-Helfers,
## - Warn-Mitteilungen im Quelltext: kein leerer Untertitel, kein nichtssagender Titel („Ging nicht“),
##   rohe Fehler des Helfers nur über Helper.klartext, feste Texte mit Handlungsempfehlung,
## - jede Ebene hat einen Weg mit B hinaus (Ebenen mit eigener Tastenbehandlung behandeln B selbst),
## - gleiche Wörter für dasselbe auf der A-Taste.
## Aufruf: godot --headless --path . res://tests/logic_konsistenz.tscn → „Ergebnis: alles ok“

const HelperS := preload("res://src/core/helper.gd")
const EpicOnline := preload("res://src/library/epic_online.gd")
const FriendRequests := preload("res://src/core/friend_requests.gd")
const TwitchParse := preload("res://src/core/twitch_parse.gd")
const YtTvParse := preload("res://src/core/youtube_tv_parse.gd")
const InstallsS := preload("res://src/core/installs.gd")
const Dialog := preload("res://src/ui/layers/dialog.gd")
const ChoiceList := preload("res://src/ui/layers/choice_list.gd")
const SheetLayer := preload("res://src/ui/layers/sheet.gd")

const LAYER := "res://src/ui/layers/layer.gd"

## Woran man eine Handlungsempfehlung erkennt (Verben und Wege, die Uzai in Meldungen nutzt).
const RAT := "versuch|prüf|wähl|start|öffne|schließ|anmeld|verbind|Einstellungen|Erst |Guide|halten|lösch|erhöh|[Pp]robier|nochmal|noch einmal|muss|müssen|Ist .*\\?|Läuft .*\\?|Platz|bringt dich|von Hand|beend|neu |installier|geht trotzdem|zum Beispiel|Danach|Optionen"
## Rohe Codes in Meldungen.
const CODE := "HTTP ?\\d|\\bHTTP\\b|EResult|Fehler \\d|Fehlercode|\\(\\d{3}\\)|0x[0-9A-Fa-f]{4,}|Exception|\\b[45]\\d\\d\\b"
## Warn-Mitteilungen, die nur informieren (es gibt nichts zu tun) – mit Grund.
const OHNE_RAT := {
	"Geht nicht mehr": "Rückgängig ist abgelaufen – nichts mehr zu tun",
	"Spiel nicht mehr da": "das Spiel wurde entfernt – nichts zu tun",
	"Nur unter Windows": "geht auf diesem System nicht – nichts zu tun",
}
## Codes, die bewusst genannt werden – mit Grund.
const CODE_ERLAUBT := {
	"src/core/trouble.gd": "Absturz-Analyse: der Code von Windows ist hier die Auskunft selbst (unter „Was ist passiert“)",
	"src/core/dl_queue.gd": "Steams eigener Download-Code, wie Steam ihn unter Downloads zeigt",
	"src/ui/install_flow.gd": "derselbe Steam-Code im Update-Dialog, mit Hinweis auf Steams Downloads",
	"src/core/voice.gd": "„HTTP %d“ ist nur ein innerer Schlüssel für explain_token_error, nie sichtbar",
	"src/core/music.gd": "Spotify-Diagnose in den Einstellungen (bewusst technisch)",
	"src/core/installs.gd": "Fehlertext fürs Protokoll; sichtbar wird steam_refused()",
	"src/core/movies_daten.gd": "catalog_reason() ist der Grund fürs Protokoll (logs/filme.log); sichtbar wird catalog_summary(), in Worten",
}
## Gleiches Wort für dasselbe auf der A-Taste: links das alte, rechts das gemeinsame.
const WOERTER := { "Wählen": "Auswählen", "Tastatur öffnen": "Bildschirmtastatur", "Möglichkeiten": "Optionen" }
## Nichtssagende Titel von Warn-Mitteilungen.
const VAGE := ["Ging nicht", "Fehler", "Geht nicht", "Fehlgeschlagen"]

var fails := 0
var _rat := RegEx.create_from_string(RAT)
var _code := RegEx.create_from_string(CODE)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_meldungen()
	_quelltext()
	_b_wege()
	await _b_laufend()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Eine Meldung: ohne Code, mit Rat (rat = false: nur ohne Code, z. B. Satzteile).
func _klar(text: String, what: String, rat := true) -> void:
	var ok := text != "" and _code.search(text) == null and (not rat or _rat.search(text) != null)
	check(ok, "%s: „%s“" % [what, text.left(110)])


func _meldungen() -> void:
	print("Fehlermeldungen")
	_klar(HelperS.klartext(""), "Helfer ohne Antwort")
	_klar(HelperS.klartext("Zeitüberschreitung"), "Helfer: Zeitgrenze")
	_klar(HelperS.klartext("Helfer antwortet nicht"), "Helfer läuft nicht")
	_klar(HelperS.klartext("Exception calling \"Open\" with \"1\" argument(s): \"Access to the path 'C:\\x' is denied.\""), "englische Systemmeldung")
	_klar(HelperS.klartext("Audiogerät lässt sich nicht öffnen (88890008)"), "Code in Klammern")
	_klar(HelperS.klartext("Discord läuft nicht."), "eigener Satz des Helfers")
	check(HelperS.klartext("Discord läuft nicht.").begins_with("Discord läuft nicht."), "eigener Satz des Helfers bleibt vorn")
	check(not HelperS.klartext("x", "Kürzel prüfen.").contains("Gleich noch einmal"), "eigener Rat ersetzt den allgemeinen")
	# Hier gibt es nichts zu tun: Uzai fällt selbst auf die Spiele des Launchers zurück und sagt das.
	_klar(str(EpicOnline.error_info(418, null).error), "Epic: unbekannter Code", false)
	_klar(str(EpicOnline.error_info(503, null).error), "Epic: Störung")
	_klar(Store.service_error(503, 1, "Die Wunschliste"), "Steam-Shop: Störung")
	_klar(Store.service_error(200, 2, "Der Warenkorb"), "Steam-Shop: EResult")
	_klar(Store.service_error(418, 1, "Der Warenkorb"), "Steam-Shop: unbekannter Code")
	_klar(SteamChat.send_error(400, "400"), "Steam-Chat: unbekannter Code")
	_klar(Music.connect_error(418), "Spotify Connect: unbekannter Code")
	_klar(Music.transfer_error(418, "", ""), "Spotify Gerätewechsel: unbekannter Code")
	_klar(Music.problem_text("app"), "Spotify im Grundmodus", false)
	_klar(Voice.explain_token_error("HTTP 403"), "discord.com blockiert")
	_klar(Voice.explain_token_error("HTTP 418"), "Discord: unbekannter Code")
	_klar(str(TwitchParse.parse_device_code(500, {}).error), "Twitch ohne Code")
	_klar(TwitchParse.explain(502), "Twitch: Störung")
	_klar(str(YtTvParse.parse_device_code(500, {}).error), "Google ohne Code")
	_klar(YtTvParse.explain(500), "YouTube: Störung")
	_klar(YtTvParse.explain(401), "YouTube: Anmeldung abgelehnt")
	_klar(str(Achievements.ra_check_result(418, null).error), "RetroAchievements: unbekannter Code")
	_klar(FriendRequests.steam_error(99), "Freundschaftsanfrage: unbekannter Code")
	_klar(Lossless.start_problem({ "ok": false, "error": "Zeitüberschreitung" }), "Lossless Scaling: Helfer")
	_klar(Lossless.start_problem({ "ok": true, "result": { "started": false, "code": 2 } }), "Lossless Scaling: Windows-Code")
	_klar(InstallsS.steam_refused("Web-API HTTP 403, EResult ?"), "Steam-Fernauftrag abgelehnt")
	_klar(InstallsS.steam_refused(InstallsS.NO_STEAM_LOGIN), "Steam-Fernauftrag ohne Anmeldung")
	_klar(Quellen._reason({ "code": 500 }, "Plex"), "Medienquelle: Störung")
	_klar(Quellen._reason({ "code": 401 }, "Plex"), "Medienquelle: Anmeldung")
	_klar(NuvioSync.reason({ "code": 500 }, "Anmelden"), "Nuvio: Störung")
	_klar(Movies._http_reason({ "code": 500 }, "Katalog nicht geladen"), "Addon: Störung (Satzteil)", false)
	_klar(Movies._http_reason({ "code": 404 }, "Katalog nicht geladen"), "Addon: nicht gefunden (Satzteil)", false)


# --- Quelltext ------------------------------------------------------------------------------

func _files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_files(dir.path_join(sub), out)


## Argumente eines Aufrufs ab pos (direkt hinter der Klammer), auf oberster Ebene getrennt.
static func args_at(src: String, pos: int) -> Array:
	var out: Array = []
	var cur := ""
	var depth := 0
	var quote := ""
	var i := pos
	while i < src.length():
		var c := src[i]
		if quote != "":
			cur += c
			if c == "\\":
				cur += src[i + 1]
				i += 2
				continue
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
			cur += c
		elif c in ["(", "[", "{"]:
			depth += 1
			cur += c
		elif c in [")", "]", "}"]:
			if depth == 0:
				out.append(cur.strip_edges())
				return out
			depth -= 1
			cur += c
		elif c == "," and depth == 0:
			out.append(cur.strip_edges())
			cur = ""
		else:
			cur += c
		i += 1
	return out


func _quelltext() -> void:
	print("Quelltext")
	var files: Array = []
	_files("res://src", files)
	var n_warn := 0
	var bad_title: Array = []
	var empty_sub: Array = []
	var raw_helper: Array = []
	var no_rat: Array = []
	var codes: Array = []
	var words: Array = []
	var log_re := RegEx.create_from_string("log_line|hlog\\(|_log\\(|_log_path|print\\(|push_warning|push_error|_dealer_fail|_app_reject|PlayerLog\\.zeile")
	var lit_code := RegEx.create_from_string("\"[^\"]*(HTTP %|Fehler %|Fehlercode %|Code %|EResult %|Steam-Fehler %|Windows-Fehler %)[^\"]*\"")
	for path in files:
		var rel: String = str(path).trim_prefix("res://")
		var src := FileAccess.get_file_as_string(path)
		# Warn-Mitteilungen
		var at := src.find("show_toast(")
		while at >= 0:
			var a := args_at(src, at + 11)
			if a.size() >= 3 and str(a[2]) == "\"warning\"":
				n_warn += 1
				var where := "%s:%d" % [rel, src.substr(0, at).count("\n") + 1]
				var title := str(a[0])
				var sub := str(a[1])
				for v in VAGE:
					if title == "\"%s\"" % v:
						bad_title.append(where)
				if sub == "\"\"":
					empty_sub.append(where)
				if sub.contains(".get(\"error\"") and not sub.contains("klartext("):
					raw_helper.append(where)
				# Nur feste Sätze (mit Wörtern); „%s: %s“ und Zusammengesetztes sagt der Aufrufer.
				var lit := RegEx.create_from_string("^\"([^\"]*)\"( % .*)?$").search(sub)
				if lit and RegEx.create_from_string("[a-zäöü]{3}").search(lit.get_string(1)) != null and _rat.search(sub) == null:
					var known := false
					for t in OHNE_RAT:
						if title == "\"%s\"" % t:
							known = true
					if not known:
						no_rat.append("%s %s" % [where, sub.left(60)])
			at = src.find("show_toast(", at + 11)
		# Rohe Codes in sichtbaren Texten
		if not CODE_ERLAUBT.has(rel):
			var ln := 0
			var im_log := 0      # offene Klammern eines Protokoll-Aufrufs, der über mehrere Zeilen geht
			for line in src.split("\n"):
				ln += 1
				if im_log > 0:
					im_log += line.count("(") - line.count(")")
					continue
				if line.strip_edges().begins_with("#"):
					continue
				var lm := log_re.search(line)
				if lm != null:
					var rest := line.substr(lm.get_start())
					im_log = maxi(0, rest.count("(") - rest.count(")"))
					continue
				if lit_code.search(line) != null:
					codes.append("%s:%d" % [rel, ln])
		# Wörter auf der A-Taste
		for w in WOERTER:
			if src.contains("\"uz_hint_a\", \"%s\"" % w):
				words.append("%s: „%s“ statt „%s“" % [rel, w, WOERTER[w]])
	check(n_warn > 80, "Warn-Mitteilungen gefunden (%d)" % n_warn)
	check(bad_title.is_empty(), "kein nichtssagender Titel („Ging nicht“) %s" % str(bad_title))
	check(empty_sub.is_empty(), "kein leerer Untertitel %s" % str(empty_sub))
	check(raw_helper.is_empty(), "rohe Fehler des Helfers nur über Helper.klartext %s" % str(raw_helper))
	check(no_rat.is_empty(), "feste Texte sagen, was zu tun ist %s" % str(no_rat))
	check(codes.is_empty(), "keine rohen Codes in sichtbaren Texten %s" % str(codes))
	check(words.is_empty(), "gleiche Wörter auf der A-Taste %s" % str(words))


# --- B-Wege ---------------------------------------------------------------------------------

func _b_wege() -> void:
	print("B-Wege")
	var files: Array = []
	_files("res://src", files)
	var parent := {}
	var re := RegEx.create_from_string("^extends\\s+\"(res://[^\"]+)\"")
	var srcs := {}
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		srcs[path] = src
		var m := re.search(src)
		if m:
			parent[path] = m.get_string(1)
	var layers: Array = []
	for path in files:
		var p: String = path
		var guard := 0
		while parent.has(p) and guard < 8:
			p = parent[p]
			guard += 1
			if p == LAYER:
				layers.append(path)
				break
	check(layers.size() > 60, "Ebenen gefunden (%d)" % layers.size())
	var traps: Array = []
	for path in layers:
		var src: String = srcs[path]
		var own_keys := src.contains("func nav_command(")
		var locked := RegEx.create_from_string("\\n\\s+closable = false\\n").search(src) != null
		if not (own_keys or locked):
			continue
		# Wer die Tasten selbst nimmt, muss B selbst behandeln – oder jede Taste schließt (Ruhebild).
		var handles_b := src.contains("\"b\"") or src.contains("\"b\", ") \
				or RegEx.create_from_string("func nav_command\\(_cmd: String\\) -> bool:\\n\\s+_wake\\(\\)").search(src) != null
		if not handles_b:
			traps.append(str(path).get_file())
	check(traps.is_empty(), "Ebenen mit eigener Tastenbehandlung haben einen B-Weg %s" % str(traps))


## Die häufigsten Ebenen wirklich öffnen und B drücken.
func _b_laufend() -> void:
	var host := Control.new()
	add_child(host)
	Nav.root_scope = host
	var d = Dialog.new()
	d.heading = "Spiel startet nicht"
	d.text = "Probe"
	d.buttons = [["Verstanden", func() -> void: pass]]
	var c = ChoiceList.new()
	c.setup("Sprache")
	c.options = [["de", "Deutsch"], ["en", "English"]]
	c.value = "de"
	var s = SheetLayer.new()
	s.setup("Mitteilungen", "")
	for l in [d, c, s]:
		l.open(host)
		await get_tree().process_frame
		await get_tree().process_frame
		check(l.nav_command("b") and l.get("_closing") == true, "%s: B schließt" % l.get_script().resource_path.get_file())
	await get_tree().create_timer(0.4).timeout
	host.queue_free()
