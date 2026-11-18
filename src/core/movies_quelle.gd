extends RefCounted
## Filme: was in den Texten einer Quelle steckt – Sprachen (Flaggen, Wörter, Kürzel, „Multi“),
## Ton (Atmos, DTS, 5.1 …), Herkunft (REMUX, WEB-DL …), Container und Dateiname – und wie diese
## Texte lesbar und sicher auf den Schirm kommen. Texte von Addons und Plugins sind fremde Daten:
## clean() nimmt Steuer- und Richtungszeichen heraus und begrenzt Länge und Zeilen, pretty() macht
## aus Emojis, die die Schrift nicht hat, Wörter oder Kürzel. Nur als Text anzeigen (Label, nie
## RichText). Rein, ohne Zustand (tests/logic_filme.gd).

const NAME_MAX := 160
const TEXT_MAX := 1200
const FILE_MAX := 255
const LINES_MAX := 12
const LANGS_MAX := 8

## Land einer Flagge → Sprache (Kürzel wie in den Chips).
const FLAG_LANG := {
	"DE": "DE", "AT": "DE", "GB": "EN", "US": "EN", "AU": "EN", "IE": "EN", "NZ": "EN", "FR": "FR", "ES": "ES", "MX": "ES",
	"AR": "ES", "CO": "ES", "CL": "ES", "IT": "IT", "PT": "PT", "BR": "PT", "RU": "RU", "UA": "UK", "PL": "PL", "NL": "NL",
	"TR": "TR", "JP": "JA", "KR": "KO", "CN": "ZH", "TW": "ZH", "HK": "ZH", "IN": "HI", "SE": "SV", "DK": "DA", "NO": "NO",
	"FI": "FI", "CZ": "CS", "SK": "SK", "HU": "HU", "GR": "EL", "RO": "RO", "HR": "HR", "RS": "SR", "BG": "BG", "IL": "HE",
	"SA": "AR", "AE": "AR", "EG": "AR", "TH": "TH", "VN": "VI", "ID": "ID", "IR": "FA", "SI": "SL", "LT": "LT", "LV": "LV",
	"EE": "ET", "MY": "MS",
}
## Sprachen als Wörter in Dateinamen und Beschreibungen (klein, ganze Wörter). Kurze Kürzel, die
## auch Namen oder Wörter sein können (Dan, Ron, Vie, Por …), stehen bewusst nicht hier.
const LANG_WORDS := {
	"DE": "german|deutsch|ger|deu|gerdub|germandub",
	"EN": "english|englisch|eng",
	"FR": "french|fran[cç]ais|franz[oö]sisch|truefrench|vff|vfq|vfi|vf2|fre|fra",
	"ES": "spanish|spanisch|espa[nñ]ol|castellano|latino|spa|esp",
	"IT": "italian|italienisch|italiano|ita",
	"PT": "portuguese|portugiesisch|portugu[eê]s|pt-?br|dublado",
	"RU": "russian|russisch|rus",
	"UK": "ukrainian|ukr",
	"PL": "polish|polnisch|polski|pldub|lektor",
	"NL": "dutch|niederl[aä]ndisch|nederlands|nld",
	"TR": "turkish|t[uü]rkisch|t[uü]rk[cç]e",
	"JA": "japanese|japanisch|jpn",
	"KO": "korean|koreanisch|kor",
	"ZH": "chinese|chinesisch|mandarin|cantonese|chs|cht",
	"HI": "hindi",
	"AR": "arabic",
	"SV": "swedish|swe", "DA": "danish", "NO": "norwegian", "FI": "finnish", "CS": "czech|cze", "HU": "hungarian",
	"EL": "greek", "HE": "hebrew|heb", "RO": "romanian", "TH": "thai", "VI": "vietnamese", "TA": "tamil", "TE": "telugu",
}
## Zwei- und dreibuchstabige Kürzel – nur in Zeilen, die ausdrücklich Sprachen nennen (🗣, 🌐 …),
## und im Sprachfeld der Plugins.
const LANG_CODES := {
	"de": "DE", "ger": "DE", "deu": "DE", "en": "EN", "eng": "EN", "fr": "FR", "fre": "FR", "fra": "FR", "es": "ES", "spa": "ES",
	"it": "IT", "ita": "IT", "pt": "PT", "por": "PT", "ru": "RU", "rus": "RU", "uk": "UK", "ukr": "UK", "pl": "PL", "pol": "PL",
	"nl": "NL", "nld": "NL", "dut": "NL", "tr": "TR", "tur": "TR", "ja": "JA", "jpn": "JA", "ko": "KO", "kor": "KO", "zh": "ZH",
	"chi": "ZH", "zho": "ZH", "hi": "HI", "hin": "HI", "ar": "AR", "ara": "AR", "sv": "SV", "swe": "SV", "da": "DA", "dan": "DA",
	"no": "NO", "nor": "NO", "fi": "FI", "fin": "FI", "cs": "CS", "cze": "CS", "ces": "CS", "hu": "HU", "hun": "HU", "el": "EL",
	"gre": "EL", "ell": "EL", "he": "HE", "heb": "HE", "ro": "RO", "rum": "RO", "ron": "RO", "th": "TH", "tha": "TH", "vi": "VI",
	"vie": "VI", "hr": "HR", "hrv": "HR", "sr": "SR", "srp": "SR", "bg": "BG", "bul": "BG", "sk": "SK", "slk": "SK",
}
## Emojis, die eine Angabe einleiten → Wort davor (übersetzt); alle anderen trennen nur.
const EMOJI_WORDS := {
	0x1F464: "Seeder", 0x1F465: "Seeder", 0x1F331: "Seeder",
	0x2699: "via", 0x1F50E: "via", 0x1F50D: "via", 0x1F517: "via", 0x1F4E1: "via", 0x1F6F0: "via",
	0x1F5E3: "Sprache", 0x1F310: "Sprache", 0x1F30D: "Sprache", 0x1F30E: "Sprache", 0x1F30F: "Sprache", 0x1F524: "Sprache",
	0x1F50A: "Audio", 0x1F509: "Audio", 0x1F508: "Audio", 0x1F3B5: "Audio", 0x1F3B6: "Audio", 0x1F3A7: "Audio", 0x1F399: "Audio",
}
## Emojis und Zeichen, die die Schriften nicht haben: Bildzeichen, Pfeile, Rahmen, Formen, Tags.
const EMOJI_RX := "(?:[\\x{1F000}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{2B00}-\\x{2BFF}\\x{2300}-\\x{23FF}\\x{2190}-\\x{21FF}" + \
		"\\x{2500}-\\x{25FF}\\x{2139}\\x{3030}\\x{303D}\\x{3297}\\x{3299}\\x{E0000}-\\x{E007F}\\x{FE00}-\\x{FE0F}\\x{200D}\\x{20E3}])+"
## Steuer-, Richtungs- und unsichtbare Zeichen (fremde Texte dürfen die Anzeige nicht umdrehen).
const CTL_RX := "[\\x{0001}-\\x{0008}\\x{000B}\\x{000C}\\x{000E}-\\x{001F}\\x{007F}-\\x{009F}\\x{00AD}\\x{061C}\\x{180E}\\x{200B}" + \
		"\\x{200C}\\x{200E}\\x{200F}\\x{202A}-\\x{202E}\\x{2060}-\\x{2064}\\x{2066}-\\x{206F}\\x{FEFF}\\x{FFF9}-\\x{FFFD}\\x{E000}-\\x{F8FF}]"
const VIDEO_EXT := ["mkv", "mp4", "avi", "m2ts", "ts", "webm", "mov", "m4v", "wmv", "mpg", "mpeg", "flv", "iso"]
const ZWSP := "\u200b"

## Übersetzte Muster, beim ersten Gebrauch gefüllt. Nur im Hauptfaden benutzen (Vorräte, die sich füllen, sind in
## zwei Fäden nicht sicher).
static var _rx := {}
static var _rx_wort := {}
static var _rx_marke := {}
## Reihenfolge der Sprachen in _RX_SPRACHEN (Gruppe 1 ist die erste).
static var _SPRACHEN: Array = LANG_WORDS.keys()
## Alle Sprachwörter in einem Muster, je Sprache eine Gruppe: eine Suche je Zeile statt 27. Gemessen an 200
## Quellen eines Addons: 100 ms im Hauptfaden vorher (0,5 ms je Quelle), fast alles davon hier.
static var _RX_SPRACHEN := RegEx.create_from_string("(?:^|[^a-z0-9])(?:(" + ")|(".join(PackedStringArray(LANG_WORDS.values())) + "))(?![a-z0-9])")


static func _re(key: String, pattern: String) -> RegEx:
	var r: RegEx = _rx.get(key)
	if r == null:
		r = RegEx.create_from_string(pattern)
		_rx[key] = r
	return r


## Wort aus alts: davor kein Buchstabe/keine Ziffer, danach kein Buchstabe (Ziffern dürfen folgen: „ddp5.1“).
## Das Muster wird nur beim ersten Mal zusammengesetzt (vorher bei jedem Aufruf, samt Schlüssel).
static func _word(t: String, alts: String) -> RegExMatch:
	var r: RegEx = _rx_wort.get(alts)
	if r == null:
		r = RegEx.create_from_string("(?:^|[^a-z0-9])(" + alts + ")(?![a-z])")
		_rx_wort[alts] = r
	return r.search(t)


static func _token(t: String, alts: String) -> RegExMatch:
	var r: RegEx = _rx_marke.get(alts)
	if r == null:
		r = RegEx.create_from_string("(?:^|[^a-z0-9])(" + alts + ")(?![a-z0-9])")
		_rx_marke[alts] = r
	return r.search(t)


# --- Säubern -----------------------------------------------------------------------------------

## Fremden Text sicher machen: ohne Steuer- und Richtungszeichen, Zeilen getrimmt und ohne
## doppelte Leerzeichen, höchstens LINES_MAX Zeilen und max_len Zeichen (dann mit „…“).
## multiline = false: alles in einer Zeile.
static func clean(text: String, max_len := TEXT_MAX, multiline := true) -> String:
	if text == "":
		return ""
	var t := text.left(max_len * 4 + 64)
	t = t.replace("\r\n", "\n").replace("\r", "\n").replace("\u2028", "\n").replace("\u2029", "\n").replace("\t", " ")
	t = _re("ctl", CTL_RX).sub(t, "", true)
	var lines := PackedStringArray()
	for raw in t.split("\n"):
		var l := _re("sp", "[ \\x{00A0}\\x{2000}-\\x{200A}\\x{202F}\\x{205F}\\x{3000}]+").sub(raw, " ", true).strip_edges()
		if l != "":
			lines.append(l)
		if lines.size() >= LINES_MAX:
			break
	var out := ("\n" if multiline else " ").join(lines)
	if out.length() > max_len:
		out = out.left(max_len - 1).strip_edges() + "…"
	return out


## Emojis und fremde Zeichen ganz entfernen (für Namen und Dateinamen); „[RD⚡]“ wird „[RD+]“.
static func strip_marks(text: String) -> String:
	var t := _re("bolt", "\\[([A-Za-z]{2,4})\\s*\\x{26A1}\\x{FE0F}?\\]").sub(text, "[$1+]", true)
	t = _re("emoji", EMOJI_RX).sub(t, " ", true)
	t = _re("sp2", " {2,}").sub(t, " ", true).strip_edges()
	t = _re("brk", "\\[\\s+").sub(t, "[", true)
	return _re("brk2", "\\s+\\]").sub(t, "]", true)


## Flaggen als Sprachkürzel („🇩🇪“ → „DE“, „🇬🇧“ → „EN“); unbekannte Länder als Länderkürzel.
static func flags_to_codes(text: String) -> String:
	var rx := _re("flag", "([\\x{1F1E6}-\\x{1F1FF}])([\\x{1F1E6}-\\x{1F1FF}])")
	var out := ""
	var at := 0
	for m in rx.search_all(text):
		out += text.substr(at, m.get_start() - at) + str(FLAG_LANG.get(_flag_cc(m), _flag_cc(m)))
		at = m.get_end()
	return out + text.substr(at)


static func _flag_cc(m: RegExMatch) -> String:
	return char(m.get_string(1).unicode_at(0) - 0x1F1E6 + 65) + char(m.get_string(2).unicode_at(0) - 0x1F1E6 + 65)


## Eine Zeile lesbar: Flaggen werden Kürzel; jedes andere Emoji beginnt einen Abschnitt, manche mit
## Wort davor („👤 154 💾 15.7 GB ⚙️ Tracker“ → „Seeder 154  ·  15.7 GB  ·  via Tracker“).
static func pretty(line: String) -> String:
	var t := flags_to_codes(line)
	t = _re("bolt", "\\[([A-Za-z]{2,4})\\s*\\x{26A1}\\x{FE0F}?\\]").sub(t, "[$1+]", true)
	var segs := PackedStringArray()
	var at := 0
	var word := ""
	for m in _re("emoji", EMOJI_RX).search_all(t):
		_seg(segs, word, t.substr(at, m.get_start() - at))
		word = str(EMOJI_WORDS.get(m.get_string().unicode_at(0), ""))
		at = m.get_end()
	_seg(segs, word, t.substr(at))
	return "  ·  ".join(segs)


static func _seg(segs: PackedStringArray, word: String, text: String) -> void:
	var s := _re("sp2", " {2,}").sub(text, " ", true).strip_edges()
	s = _re("edge", "^[\\s|·•:,;/\\-–]+|[\\s|·•:,;/\\-–]+$").sub(s, "", true)
	if s == "":
		return
	segs.append((TranslationServer.translate(word) + " " + s) if word != "" else s)


## Lange Dateinamen ohne Leerzeichen dürfen nach Punkt und Unterstrich umbrechen (unsichtbar).
static func breakable(text: String) -> String:
	if text.contains(" ") and text.count(".") < 4:
		return text
	return text.replace(".", "." + ZWSP).replace("_", "_" + ZWSP)


# --- Erkennen ----------------------------------------------------------------------------------

## Sieht die Zeile wie ein Datei- oder Release-Name aus („Film.2024.2160p.WEB-DL-GRP.mkv“)?
static func looks_like_file(t: String) -> bool:
	if t.length() < 8:
		return false
	var low := t.to_lower()
	if low.get_extension() in VIDEO_EXT:
		return true
	var res := _token(low, "2160p|1080p|720p|576p|480p|4k|uhd") != null
	if not low.contains(" ") and low.count(".") >= 2 and (res or _token(low, "(19|20)[0-9]{2}|s[0-9]{1,2}e[0-9]{1,3}") != null):
		return true
	return res and low.contains("[") and low.length() >= 20


## Dateiname einer Quelle: der Hinweis des Addons, sonst die erste Zeile aus Titel oder
## Beschreibung, die wie ein Release aussieht; "" ohne.
static func file_of(s: Dictionary) -> String:
	var f := strip_marks(clean(str(s.get("filename", "")), FILE_MAX, false))
	if f != "":
		return f
	var lines := PackedStringArray()
	for k in ["title", "description"]:
		for line in str(s.get(k, "")).split("\n"):
			lines.append(strip_marks(str(line)))
	# Erst eine Zeile mit Dateiendung (die Datei im Paket), sonst die erste Release-Zeile.
	for t in lines:
		if t.length() >= 8 and t.get_extension().to_lower() in VIDEO_EXT:
			return t.left(FILE_MAX)
	for t in lines:
		if looks_like_file(t):
			return t.left(FILE_MAX)
	return ""


## Sprachen aus Texten: Flaggen, Wörter („German“, „iTALiAN“, „VFF“), Kürzel in Sprachzeilen
## („🗣 DE | EN“) und „Multi“/„Dual Audio“/„German DL“. Untertitel („GerSub“, „Multi Subs“) zählen
## nicht. Gibt { langs: ["DE", "EN" …] in der Reihenfolge im Text, multi: bool }.
static func langs_of(texts: Array, codes_text := "") -> Dictionary:
	var found: Array = []      # [Stelle, Kürzel]
	var multi := false
	var base := 0
	var parts: Array = []
	for x in texts:
		for line in str(x).split("\n"):
			parts.append([str(line), _is_lang_line(str(line))])
	if codes_text != "":
		parts.append([codes_text, true])
	for p in parts:
		var line: String = p[0]
		for m in _re("flag", "([\\x{1F1E6}-\\x{1F1FF}])([\\x{1F1E6}-\\x{1F1FF}])").search_all(line):
			var cc := _flag_cc(m)
			if FLAG_LANG.has(cc):
				found.append([base + m.get_start(), FLAG_LANG[cc]])
		var t := _re("subs", "(?:^|[^a-z0-9])[a-z]{0,12}[ ._-]?(?:subs?|subbed|subtitles?|untertitel|vostfr)(?![a-z])").sub(line.to_lower(), " ", true)
		for m in _RX_SPRACHEN.search_all(t):
			for gi in range(1, _SPRACHEN.size() + 1):
				if m.get_start(gi) >= 0:
					found.append([base + m.get_start(gi), _SPRACHEN[gi - 1]])
					break
		if bool(p[1]):
			for m in _re("codes", "(?:^|[^a-z])([a-z]{2,3})(?![a-z])").search_all(t):
				var c := m.get_string(1)
				if LANG_CODES.has(c):
					found.append([base + m.get_start(1), LANG_CODES[c]])
		if _token(t, "multi|multi[ ._-]?(?:audio|lang|language)s?|dual[ ._-]?(?:audio|lang)|german[ ._-]dl") != null:
			multi = true
		base += line.length() + 1
	found.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var langs: Array = []
	for f in found:
		if not langs.has(f[1]) and langs.size() < LANGS_MAX:
			langs.append(f[1])
	return { "langs": langs, "multi": multi }


## Zeile, die ausdrücklich Sprachen nennt: mit 🗣/🌐/🌍 … oder „Sprache:“/„Language:“/„Audio:“ davor.
static func _is_lang_line(line: String) -> bool:
	if _re("langemoji", "[\\x{1F5E3}\\x{1F310}\\x{1F30D}-\\x{1F30F}\\x{1F524}]").search(line) != null:
		return not line.to_lower().contains("sub")
	return _re("langword", "(?i)^\\s*(sprachen?|languages?|lang|audio)\\s*:").search(line) != null


## Sprachkürzel aus einer Angabe wie „de“, „ger“, „German“, „Deutsch“; "" wenn unbekannt.
static func code_of(lang: String) -> String:
	var l := lang.strip_edges().to_lower()
	if l == "":
		return ""
	if LANG_CODES.has(l):
		return str(LANG_CODES[l])
	var r := langs_of([l])
	return str(r.langs[0]) if not (r.langs as Array).is_empty() else ""


## Ton aus Freitext: Codec, Atmos und Kanäle, z. B. „TrueHD Atmos 7.1“, „DD+ 5.1“, „AAC 2.0“; "" ohne.
static func audio_of(text: String) -> String:
	var t := text.to_lower()
	var codec := ""
	if _word(t, "truehd|true[ ._-]hd"):
		codec = "TrueHD"
	elif _word(t, "dts[ ._:-]?x"):
		codec = "DTS:X"
	elif _word(t, "dts[ ._-]?hd[ ._-]?ma|dts[ ._-]?ma"):
		codec = "DTS-HD MA"
	elif _word(t, "dts[ ._-]?hd"):
		codec = "DTS-HD"
	elif _word(t, "dts"):
		codec = "DTS"
	elif _word(t, "ddp|dd\\+|eac3|e-ac-?3|dolby[ ._-]?digital[ ._-]?plus"):
		codec = "DD+"
	elif _word(t, "dd|ac3|ac-3|dolby[ ._-]?digital"):
		codec = "DD"
	elif _word(t, "flac"):
		codec = "FLAC"
	elif _word(t, "opus"):
		codec = "Opus"
	elif _word(t, "aac"):
		codec = "AAC"
	elif _word(t, "lpcm|pcm"):
		codec = "PCM"
	elif _word(t, "mp3"):
		codec = "MP3"
	var parts := PackedStringArray()
	if codec != "":
		parts.append(codec)
	if _word(t, "atmos") and codec != "DTS:X":
		parts.append("Atmos")
	var ch := ""
	for m in _re("ch", "(?<![0-9])([2-8])\\.([01])(?![0-9]|[.,][0-9])(?!\\s*(?:[kmgt]i?b|gb|mb)(?![a-z]))").search_all(t):
		var v := m.get_string(1) + "." + m.get_string(2)
		if v in ["2.0", "5.1", "6.1", "7.1"] and not _re("chno", "(?:imdb|rating|bewertung|v)\\s*$").search(t.left(m.get_start())):
			ch = v
			break
	if ch == "":
		var m2 := _re("chn", "(?<![0-9])([268])\\s?ch(?![a-z])").search(t)
		if m2:
			ch = { "2": "2.0", "6": "5.1", "8": "7.1" }[m2.get_string(1)]
	if ch != "":
		parts.append(ch)
	return " ".join(parts)


## Herkunft: REMUX, BluRay, WEB-DL, WEBRip, WEB, HDTV, DVD oder CAM (Kinoaufnahme); "" ohne.
static func release_of(text: String) -> String:
	var t := text.to_lower()
	if _word(t, "remux|bdremux"):
		return "REMUX"
	if _word(t, "blu-?ray|bdrip|brrip|bd25|bd50|bluray"):
		return "BluRay"
	if _word(t, "web-?dl|webdl"):
		return "WEB-DL"
	if _word(t, "web-?rip"):
		return "WEBRip"
	if _token(t, "web"):
		return "WEB"
	if _word(t, "hdtv|pdtv"):
		return "HDTV"
	if _word(t, "dvd-?rip|dvd5|dvd9|dvd"):
		return "DVD"
	if _token(t, "hd-?cam|cam-?rip|cam|telesync|hd-?ts|ts-?rip|telecine|hd-?tc"):
		return "CAM"
	return ""


## Container aus Dateiname oder Adresse: MKV, MP4 …, HLS (m3u8), DASH (mpd); "" ohne.
static func container_of(filename: String, url := "") -> String:
	for x in [filename, url.get_slice("?", 0).get_slice("#", 0)]:
		var e := str(x).get_extension().to_lower()
		if e == "m3u8":
			return "HLS"
		if e == "mpd":
			return "DASH"
		if e in VIDEO_EXT:
			return e.to_upper()
	return ""


## Fehlende Angaben einer Quelle aus ihren Texten ergänzen (Sprachen, Ton, Herkunft, Container).
## lang_field: Sprachfeld eines Plugins (Kürzel erlaubt). Vorhandene Werte bleiben.
static func enrich(st: Dictionary, lang_field := "") -> Dictionary:
	var texts := [str(st.get("name", "")), str(st.get("title", "")), str(st.get("description", "")), str(st.get("filename", ""))]
	var all := " ".join(PackedStringArray(texts))
	if not st.has("langs"):
		var l := langs_of(texts, lang_field)
		st["langs"] = l.langs
		st["multi"] = bool(l.multi)
	if not st.has("multi"):
		st["multi"] = false
	if not st.has("audio"):
		st["audio"] = audio_of(all)
	if not st.has("release"):
		st["release"] = release_of(all)
	if not st.has("container"):
		st["container"] = container_of(file_of(st), str(st.get("url", "")))
	return st


## Rang der Sprache beim Sortieren: 0 hat die gewünschte (Englisch: auch ohne Angabe, das ist meist
## das Original), 1 mehrsprachig ohne genaue Angabe, 2 sonst.
static func lang_rank(s: Dictionary, want: String) -> int:
	var langs: Array = s.get("langs", []) if s.get("langs") is Array else []
	if langs.has(want):
		return 0
	if langs.is_empty():
		if want == "EN" and not bool(s.get("multi", false)):
			return 0
		if bool(s.get("multi", false)):
			return 1
	return 2
