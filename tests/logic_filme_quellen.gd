extends Node
## Angaben der Quellen aus echten Antworten typischer Addons und Plugins (tests/fixtures/filme_quellen):
## Sprachen (Flaggen, Wörter, Kürzel, Multi), Ton, HDR, Codec, Herkunft, Größe, Container, Dateiname,
## lesbare Beschreibung ohne Emojis, Säubern fremder Texte, Sortierung und Filter nach Sprache.
## Aufruf: godot --headless --path . res://tests/logic_filme_quellen.tscn

const M := preload("res://src/core/movies.gd")
const Q := preload("res://src/core/movies_quelle.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const FIX := "res://tests/fixtures/filme_quellen/"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _fix(file: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(FIX + file))


func _addon(file: String, name_: String) -> Array:
	var out: Array = []
	var i := 0
	for s in _fix(file).streams:
		var st := M.parse_stream(s, { "id": name_.to_lower(), "name": name_ }, i)
		i += 1
		if not st.is_empty():
			out.append(st)
	return out


## Kurz: Sprachen, multi, Ton, HDR, Codec, Herkunft, Container einer Quelle als Text.
func _sig(s: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%d" % [",".join(PackedStringArray(s.langs)), "M" if bool(s.multi) else "-", s.audio, s.hdr, s.codec, s.release,
			s.container, int(s.quality)]


func _ready() -> void:
	print("Addon mit Flaggen und Debrid (Torrentio-Art)")
	var t := _addon("torrentio.json", "Torrentio")
	check(t.size() == 4, "vier Quellen")
	check(_sig(t[0]) == "EN,DE,FR,IT,ES|M|TrueHD Atmos 7.1|DV|HEVC|REMUX|MKV|2160", "REMUX: " + _sig(t[0]))
	check(int(t[0].size_bytes) == int(74.6 * 1073741824.0) and bool(t[0].cached), "Größe und gecacht")
	check(Art.stream_file(t[0]) == "Beispielfilm.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC.TrueHD.Atmos.7.1-GRP.mkv", "Dateiname ganz")
	check(Art.stream_desc(t[0]) == "Seeder 312  ·  74.6 GB  ·  via Quelle-A\nMulti Audio / EN / DE / FR / IT / ES",
			"Beschreibung lesbar, Release-Zeile nicht doppelt: " + Art.stream_desc(t[0]).replace("\n", " ⏎ "))
	check(_sig(t[1]) == "DE|M|||AVC|WEB|MKV|1080", "German DL: Deutsch und mehrsprachig: " + _sig(t[1]))
	check(_sig(t[2]) == "|-|AAC||AVC|WEBRip|MP4|720", "Englisch ohne Angabe, Ton und Container aus der Adresse: " + _sig(t[2]))
	check(Art.stream_file(t[2]) == "Beispielfilm.2024.720p.WEBRip.x264.AAC-[GRP].mp4" and not bool(t[2].cached),
			"Dateiname aus der zweiten Zeile, ohne Hinweis; „download“ ist nicht gecacht")
	check(Art.stream_desc(t[2]).begins_with("Beispielfilm (2024) [720p] [WEBRip] [GRP]"), "Paketname bleibt in der Beschreibung")
	check(_sig(t[3]) == "FR|-|DD 5.1||HEVC|BluRay||1080" and bool(t[3].is_p2p), "TRUEFRENCH, AC3 5.1, P2P: " + _sig(t[3]))

	print("Addon mit Beschreibung (Comet-Art)")
	var c := _addon("comet.json", "Comet")
	check(_sig(c[0]) == "FR,EN,DE|M|DD+ 5.1|DV|HEVC|WEB-DL|MKV|2160", "Flaggen in der Sprachzeile, MULTi: " + _sig(c[0]))
	check(int(c[0].size_bytes) == 19542107340 and bool(c[0].cached) and str(Art.stream_name(c[0])) == "[RD+] Comet 2160p",
			"Größe aus videoSize, ⚡ als gecacht, Name ohne Emoji: " + Art.stream_name(c[0]))
	check(Art.stream_desc(c[0]) == "HEVC • HDR10+ • DV\nAudio DDP • 5.1\nSprache FR/EN/DE\n18.2 GB  ·  Seeder 34\nvia Torrentio",
			"Beschreibung Zeile für Zeile: " + Art.stream_desc(c[0]).replace("\n", " ⏎ "))
	check(_sig(c[1]) == "EN|-|DD+ Atmos||AVC|WEB-DL||1080" and not bool(c[1].cached), "Release mit Leerzeichen: " + _sig(c[1]))
	check(Art.stream_file(c[1]) == "", "Zeile mit Leerzeichen und ohne Endung ist kein Dateiname")

	print("Addon mit Sprachwörtern (MediaFusion-/AIO-Art)")
	var mf := _addon("mediafusion.json", "MediaFusion")
	check(_sig(mf[0]) == "EN,DE,ES|-|DD+ Atmos 5.1|DV|HEVC|WEB-DL|MKV|2160", "„iT“ ist keine Sprache, Wörter in der Sprachzeile: " + _sig(mf[0]))
	check(Art.stream_desc(mf[0]) == "Beispielfilm 2024\n22.4 GB  ·  Seeder 89\nSprache English + German + Spanish\nvia Torrentio",
			"Rahmenzeichen weg, Größe bleibt neben den Seedern: " + Art.stream_desc(mf[0]).replace("\n", " ⏎ "))
	check(_sig(mf[1]) == "DE,EN|-|DTS-HD MA 7.1||HEVC|BluRay||1080", "Kürzel nur in der Sprachzeile, DTS-HD MA: " + _sig(mf[1]))
	check(Art.stream_file(mf[1]) == "Beispielfilm.Teil.Zwei.2024.German.DTSHD.DL.1080p.BluRay.x265-GRP", "Dateiname hinter 🏷️")

	print("Plugins (Nuvio-Art)")
	var sc := { "id": "r:p", "name": "Plugin X" }
	var raw: Array = _fix("nuvio_plugin.json")
	var p: Array = raw.map(func(it): return M.parse_plugin_result(it, sc))
	check(_sig(p[0]) == "HI,EN|-|||||HLS|1080", "Hindi-English, HLS: " + _sig(p[0]))
	check(_sig(p[1]) == "EN|-|Atmos|DV|||MP4|2160", "Sprachfeld „en“: " + _sig(p[1]))
	check(_sig(p[2]) == "DE,EN|-|||||HLS|1080", "Sprachfeld als Liste, „Deutsch“ im Titel: " + _sig(p[2]))
	check(str(p[2].description) == "de, en", "Beschreibung aus dem Sprachfeld: " + str(p[2].description))

	print("Erkennen im Einzelnen")
	check(Q.audio_of("Film.DDP5.1.Atmos") == "DD+ Atmos 5.1" and Q.audio_of("x AAC2.0 y") == "AAC 2.0" and Q.audio_of("DTS-X 7.1") == "DTS:X 7.1"
			and Q.audio_of("EAC3 6CH") == "DD+ 5.1" and Q.audio_of("FLAC") == "FLAC", "Ton: Codec, Atmos, Kanäle")
	check(Q.audio_of("💾 7.1 GB") == "" and Q.audio_of("Size 5.1GB") == "" and Q.audio_of("H.264 x264") == "" and Q.audio_of("WEB-DL") == "",
			"Größen und Videocodecs sind keine Kanäle")
	check(Q.release_of("HDCAM") == "CAM" and Q.release_of("x.TS.mkv") == "" and Q.release_of("BDRip") == "BluRay"
			and Q.release_of("Film.WEB-DL") == "WEB-DL", "Herkunft")
	check(Q.container_of("", "https://x/a/b.m3u8?t=1") == "HLS" and Q.container_of("a.MKV") == "MKV" and Q.container_of("", "https://x/play") == "",
			"Container")
	var l1 := Q.langs_of(["Film.German.Subbed.1080p", "Multi Subs"])
	check((l1.langs as Array).is_empty() and not bool(l1.multi), "Untertitel zählen nicht als Sprache")
	var l2 := Q.langs_of(["De.Niro.Story.2020.1080p", "Ron und Dan"])
	check((l2.langs as Array).is_empty(), "„De“ und Namen außerhalb von Sprachzeilen sind keine Sprache")
	var l3 := Q.langs_of(["Sprache: de, en", "🇯🇵 🇰🇷 🇧🇷 🇦🇹"])
	check(l3.langs == ["DE", "EN", "JA", "KO", "PT"], "Sprachzeile mit Kürzeln, Flaggen (AT → Deutsch): " + str(l3.langs))
	check(Q.code_of("ger") == "DE" and Q.code_of("English") == "EN" and Q.code_of("Deutsch") == "DE" and Q.code_of("xx") == "", "Kürzel aus Angaben")

	print("Fremde Texte säubern")
	var b := _addon("boese.json", "Böse")
	check(b.size() == 2, "beide Quellen bleiben")
	var nm := str(b[0].name)
	check(not nm.contains("\u0007") and not nm.contains("\u202e") and nm.contains("[b]Fett[/b]"), "Steuer- und Richtungszeichen weg, BBCode bleibt bloßer Text")
	check(str(b[0].description) == "Zeile 1\nZeile 2\nZeile 3\nZeile 4\nZeile 5", "Zeilenumbrüche vereinheitlicht: " + str(b[0].description).c_escape())
	check(not str(b[0].title).contains("\u200b") and not str(b[0].title).contains("\ufeff") and not str(b[0].title).contains("\u0085"),
			"unsichtbare Zeichen weg: " + str(b[0].title).c_escape())
	check(str(b[0].filename) == "" and str(b[1].name) == "Böse" and str(b[1].title) == "", "Objekte statt Text werden leer")
	var long := "x".repeat(50000) + "\n" + "y\n".repeat(400)
	var cl := Q.clean(long)
	check(cl.length() <= Q.TEXT_MAX and cl.ends_with("…"), "Länge begrenzt (%d)" % cl.length())
	check(Q.clean("a\n".repeat(100)).split("\n").size() == Q.LINES_MAX, "Zeilen begrenzt")
	check(Q.pretty("✅ Fertig ⏳ 2 h") == "Fertig  ·  2 h" and Q.pretty("ℹ️ Info") == "Info" and Q.pretty("1️⃣ Eins") == "1  ·  Eins",
			"Emojis ohne Schriftzeichen werden Trenner: %s / %s" % [Q.pretty("ℹ️ Info"), Q.pretty("1️⃣ Eins")])
	check(Q.strip_marks("[RD⚡] Name 🍿") == "[RD+] Name" and Q.strip_marks("[AD ⚡️] X") == "[AD+] X", "Namen ohne Emojis")
	check(Q.breakable("A.B.C.D.E.mkv").contains(Q.ZWSP) and Q.breakable("Ein Titel.mkv") == "Ein Titel.mkv", "lange Dateinamen dürfen umbrechen")

	print("Sortieren und Filtern nach Sprache")
	var all: Array = t.duplicate() + c + mf + p
	all = all.filter(func(s): return not bool(s.is_p2p))
	var de := M.sort_streams(all, 0, "DE")
	var de_rank: Array = de.map(func(s): return Q.lang_rank(s, "DE"))
	var gecacht: Array = de.map(func(s): return bool(s.cached))
	var ok_order := true
	for i in range(1, de.size()):
		if gecacht[i] == gecacht[i - 1] and int(de_rank[i]) < int(de_rank[i - 1]):
			ok_order = false
	check(ok_order and gecacht[0] and int(de_rank[0]) == 0, "Deutsch zuerst (innerhalb gecacht/nicht gecacht)")
	var none := M.sort_streams(all, 0)
	var none2 := M.sort_streams(all, 0, "")
	check(none.map(func(s): return s.id) == none2.map(func(s): return s.id), "ohne Sprache bleibt die Sortierung wie bisher")
	check(Q.lang_rank({ "langs": [], "multi": false }, "EN") == 0 and Q.lang_rank({ "langs": [], "multi": true }, "DE") == 1
			and Q.lang_rank({ "langs": ["FR"] }, "DE") == 2, "Englisch ohne Angabe ist das Original; Multi ohne Kürzel dazwischen")
	var lc := Art.lang_counts(all, "DE")
	check(lc[0][0] == "DE" and lc[lc.size() - 1][0] == "MULTI", "Sprachen mit Anzahl, gewünschte zuerst: " + str(lc))
	check(Art.filter_streams(all, "", 0, "DE").all(func(s): return (s.langs as Array).has("DE"))
			and Art.filter_streams(all, "", 0, "DE").size() == int(lc[0][1]), "Filter nach Sprache")
	check(Art.lang_name("DE") == "Deutsch" and Art.lang_name("MULTI") == "Mehrsprachig" and Art.lang_name("QQ") == "QQ", "Sprachnamen")
	var bd := Art.stream_badges(t[0], "DE")
	var texts: Array = bd.map(func(x): return str(x[0]))
	check(texts.slice(0, 6) == ["4K", "Dolby Vision", "HEVC", "TrueHD Atmos 7.1", "REMUX", "74,6 GB"], "Chips der Reihe nach: " + str(texts))
	check(texts.has("EN") and texts.has("+1") and texts.has("Multi") and bd.any(func(x): return x[0] == "DE" and x[1] == "lang_on"),
			"Sprach-Chips, gewünschte hervorgehoben, Rest als +n")

	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
