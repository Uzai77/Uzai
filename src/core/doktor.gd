extends RefCounted
## Uzai-Doktor (Punkt 133) ohne Oberfläche: aus dem, was Uzai über diesen PC weiß (die „Lage“,
## gesammelt in src/core/doktor_lage.gd), die bekannten Probleme als Karten – jede mit einer klaren
## Erklärung und einem Weg, der in Uzai sicher ist. Was Uzai nicht selbst darf (Uhrzeit,
## Netzwerkeinstellungen, Virenscanner), erklärt die Karte nur; ein WLAN wählen und Bluetooth
## einschalten geht nur auf Knopfdruck (src/core/win_einst.gd). Getestet in tests/logic_doktor.gd;
## die Seite dazu: src/ui/layers/doktor.gd.
##
## Karte: { id, check, sev, icon, title, text, fix, fix_label, self, how }
##   check  – zu welcher Prüfung sie gehört (CHECKS), damit „in Ordnung“ stimmt
##   sev    – "wichtig" (etwas geht gerade nicht) oder "hinweis" (geht, aber besser nicht so)
##   fix    – was „Beheben“ tut (die Seite kennt jede Kennung), "" = nur erklären
##   self   – true: Uzai behebt es selbst auf sicherem Weg; false: „So geht's“ erklärt den Weg
##   how    – Schritte zum Selbermachen (immer zu sehen unter „Mehr dazu“)

const Lang := preload("res://src/core/lang.gd")

## Prüfungen in fester Reihenfolge: [Kennung, Name in „Geprüft und in Ordnung“].
const CHECKS := [["controller", "Controller"], ["launcher", "Launcher"], ["emulatoren", "Emulatoren"],
	["ordner", "Spieleordner"], ["spiele", "Bibliothek"], ["speicher", "Speicher"], ["helfer", "Windows-Helfer"],
	["konten", "Anmeldungen"], ["uhr", "Uhrzeit"], ["netz", "Internet"], ["bluetooth", "Bluetooth"], ["absturz", "Stabilität"]]

const GB := 1024 * 1024 * 1024
const SPACE_LOW := 5 * GB          ## darunter ein Hinweis
const SPACE_CRIT := GB             ## darunter wichtig: Updates, Aufnahmen und Sicherungen scheitern
const CLOCK_MAX := 300             ## so viele Sekunden darf die Uhr abweichen (Anmeldungen vertragen 5 Min.)
const NET_FAILS := 3               ## so viele Fehlschläge in Folge ohne Antwort dazwischen: Netz weg
const EMU_CARDS := 3               ## mehr Emulator- oder Ordner-Karten fassen sich zusammen

## Lage für die Vorführung und die Proben: ein PC mit ein paar typischen Problemen.
const DEMO := {
	"windows": true, "pads": 1, "known_pad": true, "pad_low": ["DualSense"], "pad_dupes": [],
	"launchers_missing": [{ "id": "battlenet", "name": "Battle.net", "what": "deine Blizzard- und Battle.net-Spiele", "icon": "store_battlenet" }],
	"emus_missing": [{ "id": "dolphin", "name": "Dolphin", "systems": ["GC", "Wii"], "games": 6, "angebot": "dolphin" }],
	"romdirs_missing": [{ "system": "gba", "name": "Game Boy Advance", "dir": "E:\\ROMs\\gba" }],
	"games": 48, "scanning": false,
	"space_free": 3 * GB + 400 * 1024 * 1024, "space_dir": "C:",
	"helper": "ok",
	"logins_expired": [{ "id": "twitch", "name": "Twitch" }],
	"clock_known": true, "clock_skew": 0,
	"net": "ok",
	"crash": false,
}


## Ein Satzteil schon übersetzt: Aus zwei Sätzen zusammengesetzte Texte findet der Katalog nicht
## als Ganzes (auf Deutsch ändert das nichts).
static func _t(s: String) -> String:
	return TranslationServer.translate(s)


static func _card(id: String, check: String, sev: String, icon: String, title: String, text: String, fix: String, fix_label: String, self_fix: bool,
		how: Array = []) -> Dictionary:
	return { "id": id, "check": check, "sev": sev, "icon": icon, "title": title, "text": text,
		"fix": fix, "fix_label": fix_label, "self": self_fix, "how": how }


## Alle Karten zur Lage f, wichtige zuerst (sonst in der Reihenfolge von CHECKS). Fehlt ein Wert in
## f, prüft der Doktor das gar nicht (kein Raten: unbekannt ist nicht kaputt).
static func cards(f: Dictionary) -> Array:
	var out: Array = []
	# Controller
	if f.has("pads") and int(f.pads) <= 0:
		var known := bool(f.get("known_pad", false))
		out.append(_card("pad_fehlt", "controller", "wichtig" if known else "hinweis", "controller",
			"Kein Controller verbunden",
			"Controller einschalten, anstecken oder koppeln." if known
				else "Per Kabel anstecken oder per Bluetooth koppeln.",
			"koppeln", "Koppeln", true,
			["Xbox-Controller: Verbindungstaste halten, bis das Logo schnell blinkt. PlayStation: PS und Create halten.",
				"Mit USB-Kabel oder Xbox-Funkadapter muss nichts gekoppelt werden."]))
	for n in f.get("pad_low", []):
		out.append(_card("pad_akku:" + str(n), "controller", "hinweis", "controller", "Akku fast leer: %s" % str(n),
			"Per USB-Kabel laden.", "", "", false,
			["Xbox-Controller mit Batterien: frische Batterien einlegen.",
				"Akkustand im Guide unter System."]))
	var dupes: Array = f.get("pad_dupes", [])
	if not dupes.is_empty():
		out.append(_card("pad_doppelt", "controller", "hinweis", "controller", "Eingaben kommen doppelt an",
			"Ein zweiter, virtueller Controller ist aktiv (Steam Input oder DS4Windows).",
			"pad_help", "Prüfen", true,
			["DS4Windows o. Ä. beenden."]))
	# Launcher (zusammengefasst – meist fehlt einer, den man gar nicht nutzt)
	var miss: Array = f.get("launchers_missing", [])
	if not miss.is_empty():
		var names := PackedStringArray(miss.map(func(m: Dictionary) -> String: return str(m.get("name", m.get("id", "")))))
		var one := miss.size() == 1
		out.append(_card("launcher", "launcher", "hinweis", str(miss[0].get("icon", "games")) if one else "games",
			("%s ist nicht installiert" % names[0]) if one else "Launcher fehlen: %s" % ", ".join(names),
			(_t("Damit fehlen %s. ") % _t(str(miss[0].get("what", "seine Spiele"))) if one else _t("Damit fehlen ihre Spiele in Uzai. "))
				+ _t("Download auf der offiziellen Seite."),
			"launcher", "Offizielle Seite", true,
			["Nach der Installation erscheinen die Spiele automatisch.",
				"Nicht genutzt: Quelle unter Einstellungen → Spiele ausschalten."]))
	# Emulatoren ohne Programmdatei
	var emus: Array = f.get("emus_missing", [])
	for i in mini(emus.size(), EMU_CARDS):
		var e: Dictionary = emus[i]
		var sys := ", ".join(PackedStringArray(e.get("systems", [])))
		var has_games := int(e.get("games", 0)) > 0
		# Kann Uzai ihn von der offiziellen Quelle einrichten (src/core/retro_auto.gd), heißt der Weg
		# „Einrichten“: erst auf diesem PC suchen, sonst Quelle, Lizenz und Größe zeigen.
		var offer := str(e.get("angebot", "")) != ""
		out.append(_card("emu:" + str(e.id), "emulatoren", "wichtig" if has_games else "hinweis", "chip",
			"%s: Programm nicht gefunden" % str(e.get("name", e.id)),
			((_t("Ein Spiel für %s startet so nicht. ") % sys) if int(e.games) == 1 else (_t("%d Spiele für %s starten so nicht. ") % [int(e.games), sys]) if has_games
				else (_t("Spiele für %s starten so nicht. ") % sys))
				+ (_t("Auf diesem PC suchen oder von der offiziellen Quelle laden.") if offer
					else _t("Auf diesem PC suchen.")),
			"emu:" + str(e.id), "Einrichten" if offer else "Suchen", true,
			(["Download nur nach Zustimmung. Keine BIOS oder Spiele."] if offer else [])
				+ ["Anderer Ort: Einstellungen → Emulation → %s." % str(e.get("name", e.id))]))
	if emus.size() > EMU_CARDS:
		out.append(_card("emu_mehr", "emulatoren", "hinweis", "chip", "Noch %s ohne Programm" % plural(emus.size() - EMU_CARDS, "ein Emulator", "%d Emulatoren"),
			"Unter Einstellungen → Emulation steht bei jedem, was fehlt.", "seite:emulation", "Öffnen", true))
	# Spieleordner, die es nicht mehr gibt
	var dirs: Array = f.get("romdirs_missing", [])
	for i in mini(dirs.size(), EMU_CARDS):
		var d: Dictionary = dirs[i]
		out.append(_card("ordner:" + str(d.system), "ordner", "wichtig", "folder", "Spieleordner fehlt: %s" % str(d.get("name", d.system)),
			"„%s“ nicht gefunden." % str(d.get("dir", "")),
			"ordner:" + str(d.system), "Neu wählen", true,
			["Externes Laufwerk anschließen und erneut prüfen.",
				"Oder neuen Ort wählen. Spielzeit und Favoriten bleiben."]))
	if dirs.size() > EMU_CARDS:
		out.append(_card("ordner_mehr", "ordner", "wichtig", "folder", "Noch %s fehlen" % plural(dirs.size() - EMU_CARDS, "ein Spieleordner", "%d Spieleordner"),
			"Unter Einstellungen → Emulation steht bei jedem System sein Ordner.", "seite:emulation", "Öffnen", true))
	# Bibliothek leer
	if f.has("games") and int(f.games) <= 0 and not bool(f.get("scanning", false)):
		out.append(_card("spiele", "spiele", "hinweis", "search", "Noch keine Spiele gefunden",
			"Steam, Epic, EA app und übliche Ordner werden durchsucht.",
			"suche", "Neu suchen", true,
			["Emulator-Spiele: einen Ordner mit Spielen wählen (Einstellungen → Emulation).",
				"Eigene PC-Spiele: Einstellungen → Spiele → PC-Spiele → „PC-Spiel hinzufügen“."]))
	# Speicher
	if f.has("space_free") and int(f.space_free) >= 0 and int(f.space_free) < SPACE_LOW:
		var crit := int(f.space_free) < SPACE_CRIT
		out.append(_card("speicher", "speicher", "wichtig" if crit else "hinweis", "drive", "Speicher fast voll",
			"Auf %s sind noch %s frei." % [
				str(f.get("space_dir", "dem Laufwerk")), size_text(int(f.space_free))],
			"speicher", "Aufräumen", true,
			["Details unter Einstellungen → System → Speicher.",
				"Spiele deinstallieren im jeweiligen Launcher."]))
	# Helfer
	if str(f.get("helper", "")) == "blockiert":
		out.append(_card("helfer", "helfer", "wichtig", "warning", "Windows-Helfer startet nicht",
			"Guide im Spiel, Lautstärke und Koppeln gehen nicht. Oft blockiert ein Virenscanner.",
			"helfer", "Neu starten", true,
			["Grund im Datenordner unter logs\\helper.log.",
				"Im Virenscanner eine Ausnahme für den Uzai-Ordner anlegen."]))
	# Anmeldungen
	for a in f.get("logins_expired", []):
		out.append(_card("konto:" + str(a.id), "konten", "wichtig", "user", "%s: Anmeldung abgelaufen" % str(a.get("name", a.id)),
			"Neu anmelden.",
			"konto:" + str(a.id), "Neu anmelden", true))
	# Uhr
	if bool(f.get("clock_known", false)) and absi(int(f.get("clock_skew", 0))) > CLOCK_MAX:
		var sk := int(f.clock_skew)
		out.append(_card("uhr", "uhr", "wichtig", "clock", "Die Uhrzeit stimmt nicht",
			"Die Uhr geht %s %s. Anmeldungen scheitern." % [duration_text(absi(sk)), "nach" if sk > 0 else "vor"],
			"", "", false,
			["Windows: Zeit und Sprache → „Uhrzeit automatisch festlegen“."]))
	# Netz: Weiß Uzai vom WLAN (f.wlan, WinEinst.lage), führt „Beheben“ in die WLAN-Liste – sonst
	# nur erklären. Windows selbst sagt „kein Internet“ auch, bevor Uzai etwas abgerufen hat.
	var wl: Dictionary = f.get("wlan", {})
	var no_net := str(f.get("net", "")) == "weg" or str(wl.get("internet", "")) == "keins"
	if no_net and not wl.is_empty() and str(wl.get("connected", "")) == "":
		var off := str(wl.get("radio", "")) == "aus"
		out.append(_card("netz", "netz", "wichtig", "wifi", "Kein Netz",
			(_t("Das WLAN ist aus.") if off else _t("Dieser PC ist mit keinem WLAN verbunden."))
				+ " " + _t("Spiele laufen weiter."),
			"wlan", "WLAN-Liste", true,
			["Netz in der WLAN-Liste wählen.",
				"Kabel prüfen, Router neu starten."]))
	elif no_net:
		out.append(_card("netz", "netz", "wichtig", "live", "Keine Verbindung zum Internet",
			"Kein Server erreichbar. Spiele laufen weiter.",
			"", "", false,
			["Kabel oder WLAN prüfen, Router neu starten."]))
	# Bluetooth aus, obwohl gekoppelte Geräte warten oder gar kein Controller da ist.
	var bt: Dictionary = f.get("bt", {})
	if str(bt.get("radio", "")) == "aus" and (int(bt.get("paired", 0)) > 0 or (f.has("pads") and int(f.pads) <= 0)):
		out.append(_card("bt_aus", "bluetooth", "hinweis", "bluetooth", "Bluetooth ist aus – einschalten?",
			"Gekoppelte Geräte verbinden sich nicht.",
			"bt_an", "Einschalten", true,
			["Ausschalten unter Einstellungen → System → Windows.",
				"Ein Controller mit Kabel oder Xbox-Funkadapter braucht kein Bluetooth."]))
	# Absturz beim letzten Mal
	if bool(f.get("crash", false)):
		out.append(_card("absturz", "absturz", "hinweis", "warning", "Uzai ist zuletzt abgestürzt",
			"Fehlerbericht als QR-Code, ohne Namen und Pfade.",
			"absturz", "Fehlerbericht", true,
			["Wieder: Einstellungen → System → Sicherer Modus."]))
	# Wichtige zuerst, sonst wie gesammelt (stabil).
	var ranked: Array = []
	for i in out.size():
		ranked.append([0 if str(out[i].sev) == "wichtig" else 1, i, out[i]])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return ranked.map(func(r: Array) -> Dictionary: return r[2])


## Was geprüft wurde und in Ordnung ist: Namen aus CHECKS (nur Prüfungen, für die f etwas weiß).
static func ok_checks(f: Dictionary, list: Array) -> Array:
	var known := {
		"controller": f.has("pads"), "launcher": f.has("launchers_missing"), "emulatoren": f.has("emus_missing"),
		"ordner": f.has("romdirs_missing"), "spiele": f.has("games") and not bool(f.get("scanning", false)),
		"speicher": int(f.get("space_free", -1)) >= 0, "helfer": str(f.get("helper", "")) in ["ok", "blockiert"],
		"konten": f.has("logins_expired"), "uhr": bool(f.get("clock_known", false)),
		"netz": str(f.get("net", "")) in ["ok", "weg"] or str((f.get("wlan", {}) as Dictionary).get("internet", "")) in ["ok", "keins"],
		"bluetooth": f.has("bt"), "absturz": f.has("crash"),
	}
	var bad := {}
	for c in list:
		bad[str(c.check)] = true
	var out: Array = []
	for c in CHECKS:
		if bool(known.get(c[0], false)) and not bad.has(c[0]):
			out.append(str(c[1]))
	return out


## { wichtig, hinweis, text } für Überschrift, Guide und Einstellungen.
static func summary(list: Array) -> Dictionary:
	var w := 0
	var h := 0
	for c in list:
		if str(c.sev) == "wichtig":
			w += 1
		else:
			h += 1
	var parts := PackedStringArray()
	if w > 0:
		parts.append(plural(w, "1 Problem", "%d Probleme"))
	if h > 0:
		parts.append(plural(h, "1 Hinweis", "%d Hinweise"))
	return { "wichtig": w, "hinweis": h, "text": " · ".join(parts) if not parts.is_empty() else "Alles in Ordnung" }


## Kurzer Hinweis auf der Startseite (abschaltbar): nur bei wichtigen Karten und nur, wenn sich
## seit dem letzten Mal etwas geändert hat – nie zweimal wegen derselben Sache. Gibt die neue
## Kennung zurück ("" = nichts zeigen).
static func hint_sig(list: Array, enabled: bool, last: String) -> String:
	if not enabled:
		return ""
	var ids := PackedStringArray()
	for c in list:
		if str(c.sev) == "wichtig":
			ids.append(str(c.id))
	ids.sort()
	var sig := ",".join(ids)
	return "" if sig == "" or sig == last else sig


## Netz weg? Mehrere Fehlschläge in Folge und seitdem keine Antwort. "" = weiß nicht.
static func net_state(last_ok_ms: int, last_fail_ms: int, fails: int) -> String:
	if fails >= NET_FAILS and last_fail_ms >= last_ok_ms:
		return "weg"
	return "ok" if last_ok_ms > 0 else ""


## HTTP-Kopfzeile „Date“ (RFC 7231, z. B. „Sun, 06 Nov 1994 08:49:37 GMT“) → Unix-Zeit, -1 wenn
## sie so nicht aussieht.
static func http_date(s: String) -> int:
	var p := s.strip_edges().split(" ", false)
	if p.size() != 6 or p[5] != "GMT":
		return -1
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var mon := months.find(p[2]) + 1
	var t := p[4].split(":")
	if mon <= 0 or t.size() != 3 or not p[1].is_valid_int() or not p[3].is_valid_int():
		return -1
	for x in t:
		if not x.is_valid_int():
			return -1
	var d := { "year": p[3].to_int(), "month": mon, "day": p[1].to_int(), "hour": t[0].to_int(), "minute": t[1].to_int(), "second": t[2].to_int() }
	if d.year < 2000 or d.day < 1 or d.day > 31 or d.hour > 23 or d.minute > 59 or d.second > 60:
		return -1
	return Time.get_unix_time_from_datetime_dict(d)


static func plural(n: int, one: String, many: String) -> String:
	return one if n == 1 else (many % n if many.contains("%d") else many)


static func size_text(b: int) -> String:
	if b >= GB:
		return Lang.dec("%.1f GB" % (b / float(GB)))
	return "%d MB" % int(b / (1024.0 * 1024.0))


static func duration_text(s: int) -> String:
	if s >= 86400:
		return plural(int(round(s / 86400.0)), "einen Tag", "%d Tage")
	if s >= 3600:
		return plural(int(round(s / 3600.0)), "eine Stunde", "%d Stunden")
	return plural(maxi(1, int(round(s / 60.0))), "eine Minute", "%d Minuten")
