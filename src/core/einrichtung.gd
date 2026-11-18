extends RefCounted
## Einrichtung beim ersten Start: reine Regeln ohne Oberfläche (getestet in tests/logic_einrichtung).
## Welche Schritte es gibt, wann die Einrichtung von selbst kommt (neu, angefangen, nie abgeschlossen), wo sie
## nach einem Neustart weitergeht, die Zusammenfassung am Ende und das Suchen nach Emulatoren und
## Spieleordnern an den üblichen Stellen.
##
## Gespeichert wird unter „einrichtung“ in settings.json: step (Schritt, an dem es weitergeht),
## done (fertig), skipped (nur noch aus älteren Fassungen mit „Später“: wird beim Weitergehen
## geleert), restart (aus den Einstellungen neu gestartet – B im ersten Schritt schließt dann), tour (die kurze Tour
## danach kam schon), mehr (die freiwilligen Schritte wurden vom Ende aus dazugeholt), started (Beginn, für
## „in … eingerichtet“).
##
## Kurzer Weg wie bei einer neuen Konsole, nur Momente, keine Formulare: Willkommen (das Licht geht
## an, das Zeichen erscheint groß; Sprache) → Spiele (die Suche als Höhepunkt: der Zähler läuft hoch,
## die eigenen Cover fliegen gestaffelt in die Tiefe der Bühne, je Quelle erscheint ihr Schild) → die
## Vorstellung der starken Funktionen, je ein Bild mit einer Animation und einem Satz, A geht weiter:
## Emulatoren (Systeme erkannt, Fehlendes nur angeboten – geladen erst nach Zustimmung –, Controller
## Spieler 1–4 belegt) → Die Guide-Taste
## (die echte Taste öffnet ihn zum Ausprobieren) → Dein Zimmer (bauen, Freunde kommen rein, zusammen
## per Remote Play; bei einem neuen Zimmer die Vorlage) → Schauen & Hören (Musik mit Lyrics, Videos,
## Filme, Livestreams) → Konten (alle Dienste nach Bereichen, Steam und Discord groß zuerst, freiwillig)
## → Bereit (die Bühne löst sich in die Startseite auf). Der Controller wird still erkannt (Koppeln
## und Test liegen unter Einstellungen → Controller). Ein „Überspringen“ gibt es nicht: A geht
## durch, „Weiter“ geht auch ohne das Freiwillige weiter, B zurück.
## Freiwillig (MEHR, vom Ende aus über „Mehr einrichten“, dann vor „Fertig“ eingereiht): Aussehen
## und Extras.
## Gespeicherte Schritte älterer Folgen gehen an der passenden Stelle weiter (resume_index):
## Schritte, die es nicht mehr gibt, über ERSATZ (Controller → Spiele, Freunde → Konten, Das kann
## Uzai → was danach kam), sonst über FOLGE_ALT (bis 0.14: Sprache → Controller → Aussehen → Suche →
## Guide → Freunde & Medien → Zimmer → Fertig; bis 0.16: mit Controller, Freunde und Das kann Uzai).

const Stores := preload("res://src/library/stores.gd")

const STEPS := ["willkommen", "du", "spiele", "emulatoren", "guide", "zimmer", "medien", "konten", "darstellung", "extras", "fertig"]
## Freiwillige Schritte: erst auf Wunsch von „Fertig“ aus, dann vor „Fertig“ eingereiht.
const MEHR := ["darstellung", "extras"]
## Die Szenen der Vorstellung: je eine Animation (einrichtung_szene.gd) und das, was dazu gleich
## einzurichten ist.
const SHOW := ["emulatoren", "guide", "zimmer", "medien"]
## Alle Schritte, die es je gab, in einer Folge (für resume_index): Wer mitten in einer älteren
## Einrichtung neu startet, landet beim nächsten Schritt, den es noch gibt.
const FOLGE_ALT := ["willkommen", "du", "controller", "darstellung", "spiele", "emulatoren", "guide", "freunde", "zimmer", "medien", "konten",
	"besonders", "extras", "fertig"]
## Schritte, die es nicht mehr gibt (bis 0.16), und wo es statt ihrer weitergeht: der erste
## vorhandene der Liste. Controller wird still erkannt, Steam und Discord stehen unter Konten, nach
## „Das kann Uzai“ kamen die freiwilligen Schritte bzw. Bereit.
const ERSATZ := {
	"controller": ["spiele", "guide", "konten"],
	"freunde": ["konten"],
	"besonders": ["darstellung", "extras", "fertig"],
}

const TITLES := {
	"willkommen": "Sprache", "du": "Wer spielt?", "darstellung": "Aussehen",
	"spiele": "Spiele", "emulatoren": "Emulatoren", "guide": "Die Guide-Taste", "zimmer": "Dein Zimmer",
	"medien": "Schauen & Hören",
	"konten": "Konten", "extras": "Extras", "fertig": "Fertig",
}
## So lange darf eine Einrichtung dauern, damit „in … eingerichtet“ am Ende steht (länger heißt: sie
## wurde unterbrochen – dann keine Zeit).
const TIMED_MAX_S := 900

## Konten, die zeigen, dass jemand Uzai schon benutzt (irgendeins eingetragen → kein Assistent).
const ACCOUNT_KEYS := ["steam_key", "steam_id", "ra_user", "spotify_client_id", "spotify_refresh", "discord_client_id",
	"discord_token", "discord_refresh", "sgdb_key", "iidb_key", "epic_refresh", "youtube_tv_refresh", "spotify_app_refresh", "spotify_web", "twitch_refresh"]


# --- Wann die Einrichtung kommt --------------------------------------------------------------

## Schon eingerichtet? s: { first_run, accounts: {…}, rom_dirs: {…}, pc_dirs: […], last_game,
## youtube_refresh, nuvio, played } – alles, was nur ein Nutzer hat, der Uzai schon kennt.
## first_run ist schon aus, sobald das frühere Willkommen einmal kam.
static func is_existing_user(s: Dictionary) -> bool:
	return existing_reason(s) != ""


## Woran Uzai einen bestehenden Nutzer erkennt (für das Protokoll), "" = neu.
static func existing_reason(s: Dictionary) -> String:
	if not bool(s.get("first_run", true)):
		return "Uzai lief schon"
	var acc: Variant = s.get("accounts", {})
	if acc is Dictionary:
		for k in ACCOUNT_KEYS:
			var v: Variant = (acc as Dictionary).get(k, "")
			if (v is String and (v as String).strip_edges() != "") or (v is Array and not (v as Array).is_empty()) or (v is bool and v):
				return "Konto " + k
	var dirs: Variant = s.get("rom_dirs", {})
	if dirs is Dictionary:
		for k in (dirs as Dictionary).keys():
			if str((dirs as Dictionary)[k]).strip_edges() != "":
				return "Spieleordner"
	var pcs: Variant = s.get("pc_dirs", [])
	if pcs is Array and not (pcs as Array).is_empty():
		return "PC-Spieleordner"
	if str(s.get("last_game", "")) != "":
		return "zuletzt gespielt"
	if str(s.get("youtube_refresh", "")) != "":
		return "YouTube angemeldet"
	if bool(s.get("nuvio", false)):
		return "Nuvio angemeldet"
	if int(s.get("played", 0)) > 0:
		return "Spielzeit in Uzai"
	return ""


## Returns "" (do not show), "neu" (start over), "weiter" (started, resume at the saved step) or "anbieten".
## st: { done, step, started } from „einrichtung“; user: see is_existing_user.
## The setup stops appearing only once it is finished (done: „Los“ at the end, „Abbrechen“ or B in the first step
## of an offered or freshly started setup, „Überspringen“ in older versions). If it was started but not finished
## (cancelled, crash, error), it resumes, even if only its start time (started) was saved.
## „anbieten“: an existing Uzai user who never completed the setup gets it as if opened from the settings
## (with „Abbrechen“), instead of it being skipped silently for that user.
static func start_mode(st: Dictionary, user: Dictionary, demo := false) -> String:
	if demo or bool(st.get("done", false)):
		return ""
	if str(st.get("step", "")) != "" or int(st.get("started", 0)) > 0:
		return "weiter"
	if is_existing_user(user):
		return "anbieten"
	return "neu"


## Warum die Einrichtung (nicht) kommt – eine Zeile fürs Protokoll (logs/einrichtung.log), ohne Daten des Nutzers.
static func start_grund(st: Dictionary, user: Dictionary, demo := false) -> String:
	match start_mode(st, user, demo):
		"neu":
			return "Einrichtung neu (erster Start)"
		"weiter":
			var step := str(st.get("step", ""))
			return "Einrichtung geht weiter bei „%s“ (angefangen, nicht fertig)" % step if step != "" else "Einrichtung geht weiter (angefangen, nicht fertig)"
		"anbieten":
			return "Einrichtung angeboten (nie abgeschlossen; bestehender Nutzer: %s)" % existing_reason(user)
	if demo:
		return "keine Einrichtung (Vorführung)"
	var sk: Variant = st.get("skipped", [])
	return "keine Einrichtung (fertig%s)" % (", ältere Fassung übersprungen" if sk is Array and not (sk as Array).is_empty() else "")


# --- Schritte ------------------------------------------------------------------------------

## Heißt das Profil noch, wie Uzai es angelegt hat („Spieler 1“, „Player 2“)? Dann grüßt „Fertig“
## ohne Namen.
static func name_ist_standard(name: String) -> bool:
	var rx := RegEx.create_from_string("^(Spieler|Player) ?\\d*$")
	return name.strip_edges() == "" or rx.search(name.strip_edges()) != null


## Überschrift von „Fertig“: mit Namen, wenn er gewählt und kurz genug für die große Zeile ist.
static func fertig_titel(name: String, tr_: Callable) -> String:
	var n := name.strip_edges()
	if name_ist_standard(n) or n.length() > 14:
		return str(tr_.call("Alles bereit"))
	return str(tr_.call("Alles bereit, %s")) % n


## Schritte, die es auf diesem PC gibt. features: { extras: [ids], accounts: [ids], show: [ids] }.
## Ohne mehr nur der kurze Weg (Aussehen, Zimmer und Extras fehlen); mit mehr fällt „Extras“ weg,
## wenn keine Zusatzfunktion da ist. „Konten“ fehlt, wenn es keine gibt. show: welche Szenen es gibt
## (fehlt es, alle aus SHOW).
static func steps_for(features: Dictionary, mehr := true) -> Array:
	var out: Array = []
	var show: Array = features.get("show", SHOW)
	var acc: Array = features.get("accounts", ["steam"])
	for s in STEPS:
		if s in MEHR and not mehr:
			continue
		if s in SHOW and not show.has(s):
			continue
		if s == "extras" and (features.get("extras", []) as Array).is_empty():
			continue
		if s == "konten" and acc.is_empty():
			continue
		out.append(s)
	return out


## „in 1 Min. 42 s eingerichtet“ – nur, wenn die Einrichtung am Stück lief ("" sonst).
static func timed_text(started: int, now: int) -> String:
	var s := now - started
	if started <= 0 or s <= 0 or s > TIMED_MAX_S:
		return ""
	if s < 60:
		return "In %d Sekunden eingerichtet" % s
	return "In %d Min. %d s eingerichtet" % [s / 60, s % 60]


## Wo es nach einem Neustart weitergeht: der gespeicherte Schritt, sonst der erste. Gibt es den
## gespeicherten Schritt nicht mehr (ERSATZ: controller, freunde, besonders), der erste vorhandene
## seiner Nachfolger. Gibt es ihn hier nicht – etwa „extras“ ohne Zusatzfunktionen oder „zimmer“ aus
## einer älteren Einrichtung, in der die Szene noch zum Weg gehörte –, der nächste vorhandene danach
## (in FOLGE_ALT, die jeden Schritt kennt, den es je gab). Ein unbekannter Wert beginnt von vorn.
static func resume_index(saved: String, steps: Array) -> int:
	if saved == "":
		return 0
	var i := steps.find(saved)
	if i >= 0:
		return i
	for nach in ERSATZ.get(saved, []):
		var k0 := steps.find(nach)
		if k0 >= 0:
			return k0
	var at := FOLGE_ALT.find(saved)
	if at < 0:
		return 0
	for j in range(at + 1, FOLGE_ALT.size()):
		var k := steps.find(FOLGE_ALT[j])
		if k >= 0:
			return k
	return maxi(0, steps.size() - 1)


## Nächster Schritt (dir +1 weiter, −1 zurück), am Rand stehen bleiben.
static func step_index(cur: int, steps: Array, dir: int) -> int:
	return clampi(cur + dir, 0, maxi(0, steps.size() - 1))


## Neuer Stand nach einem Schritt. how: "weiter" (A) oder "zurück" (B); alles andere gilt als
## „Weiter“ (ein „Später“ gibt es nicht mehr). Gibt { step, skipped, index } zurück: „Weiter“ nimmt
## einen Schritt, den eine ältere Fassung als übersprungen gemerkt hatte, wieder heraus.
static func advance(state: Dictionary, steps: Array, cur: int, how: String) -> Dictionary:
	var skipped: Array = (state.get("skipped", []) as Array).duplicate()
	var id := str(steps[cur]) if cur >= 0 and cur < steps.size() else ""
	if how != "zurück" and skipped.has(id):
		skipped.erase(id)
	var to := step_index(cur, steps, -1 if how == "zurück" else 1)
	return { "step": str(steps[to]) if not steps.is_empty() else "", "skipped": skipped, "index": to }


## Konten, die die Einrichtung zeigt (Punkt 52): alle zur Wahl, die sich ohne eigene IDs oder
## Schlüssel anmelden lassen – per QR-Code oder Code am Handy ("qr") oder mit einer Bestätigung in
## der App am PC ("app"). Wofür noch eine eigene Entwickler-App nötig wäre (needs_id), steht
## trotzdem da und sagt ehrlich, dass es gerade nicht geht. list: [{ title, way, needs_id }].
static func setup_accounts(list: Array) -> Array:
	return list.filter(func(a: Variant) -> bool: return a is Dictionary and _in_setup(a))


## Die, die nur mit eigener Entwickler-App gingen: ihre Namen.
static func app_accounts(list: Array) -> Array:
	var out: Array = []
	for a in list:
		if a is Dictionary and bool((a as Dictionary).get("needs_id", false)):
			out.append(str((a as Dictionary).get("title", "")))
	return out


static func _in_setup(a: Dictionary) -> bool:
	return str(a.get("way", "")) in ["qr", "app"] and str(a.get("title", "")) != ""


## Accounts below Steam and Discord: two columns, exactly as wide as the two large tiles above them, so the
## accounts stay centered under the tiles. The groups are distributed so that both columns end up about the
## same height. gruppen: [[id, height], …] in their order. The first group goes on the left; within a column
## the order is kept. A front | back split is preferred (keeps related groups together) unless another split
## is more balanced by more than SPALTEN_FOLGE_PX. Returns [[ids left], [ids right]].
const SPALTEN_FOLGE_PX := 40.0

static func spalten_verteilen(gruppen: Array) -> Array:
	var n := gruppen.size()
	if n == 0:
		return [[], []]
	if n == 1:
		return [[str(gruppen[0][0])], []]
	var best_mask := 1
	var best := INF
	# Bit i: Gruppe i links. Gruppe 0 immer links, rechts nie leer.
	for mask in range(1, 1 << n):
		if mask & 1 == 0 or mask == (1 << n) - 1:
			continue
		var hl := 0.0
		var hr := 0.0
		for i in n:
			if mask & (1 << i):
				hl += float(gruppen[i][1])
			else:
				hr += float(gruppen[i][1])
		var vorn := (mask & (mask + 1)) == 0   # nur die ersten k Bits gesetzt
		var cost := absf(hl - hr) + (0.0 if vorn else SPALTEN_FOLGE_PX)
		if cost < best - 0.001:
			best = cost
			best_mask = mask
	var out := [[], []]
	for i in n:
		(out[0 if best_mask & (1 << i) else 1] as Array).append(str(gruppen[i][0]))
	return out


## Zusatzfunktionen, die es im Code gibt (nur die werden gezeigt). has: { key → bool }.
static func extras_for(has: Dictionary) -> Array:
	var out: Array = []
	for id in ["lossless", "background_wake", "autostart", "clips", "gamebar", "steam_guide", "ruhemodus", "browser_kern"]:
		if bool(has.get(id, false)):
			out.append(id)
	return out


# --- Suche mit Fortschritt -------------------------------------------------------------------

## Fortschritt der automatischen Suche (Punkt 51): p: { launcher: "läuft"/"fertig", emu_done,
## emu_total, dir_done, dir_total, state: "läuft"/"fertig" }. Gibt { pct, launcher, emus, dirs,
## done } zurück (alles 0..1). Das Einlesen der Launcher meldet keinen Stand: solange es läuft,
## zählt es halb.
static func search_progress(p: Dictionary) -> Dictionary:
	var fin := str(p.get("state", "")) == "fertig"
	var la := 1.0 if str(p.get("launcher", "")) == "fertig" else (0.5 if str(p.get("launcher", "")) == "läuft" else 0.0)
	var part := func(done_k: String, total_k: String) -> float:
		var t := int(p.get(total_k, 0))
		if fin:
			return 1.0
		return clampf(float(p.get(done_k, 0)) / float(t), 0.0, 0.99) if t > 0 else 0.0
	var em: float = part.call("emu_done", "emu_total")
	var di: float = part.call("dir_done", "dir_total")
	return { "pct": (la + em + di) / 3.0, "launcher": la, "emus": em, "dirs": di, "done": fin and la >= 1.0 }


# --- Kurze Tour danach ---------------------------------------------------------------------

## Die Hinweise der Tour (Punkt 52), je eine Taste oder ein Zeichen: [{ id, key, icon, title, text }].
## key ist eine Taste für glyph.gd (zeigt das Symbol des Controllers bzw. der Tastatur), icon ein
## Zeichen, wenn es keine eigene Taste gibt. Die Texte nennen keine Tasten – das Symbol daneben
## passt sich dem Gerät an, ein „Y“ im Text stimmte am PlayStation-Controller nicht.
const TOUR := [
	{ "id": "guide", "key": "guide", "title": "Guide",
		"text": "Jederzeit, auch im Spiel." },
	{ "id": "suche", "key": "search", "title": "Suche",
		"text": "Spiele, Einstellungen, Freunde und Shop." },
	{ "id": "optionen", "key": "y", "title": "Spieloptionen",
		"text": "Für das gewählte Spiel." },
	{ "id": "einstellungen", "icon": "settings", "title": "Einstellungen",
		"text": "Aussehen, Spiele, Konten und System." },
]


## Kommt nach der Einrichtung die Tour? Einmal, nach dem ersten Einrichten – auch wenn es
## übersprungen wurde (B beendet die Tour sofort). Nicht nach einem Neustart der Einrichtung aus
## den Einstellungen (wer das tut, kennt Uzai) und nicht in der Vorführung.
## st: { tour, restart } aus „einrichtung“.
static func tour_due(st: Dictionary, demo := false) -> bool:
	return not demo and not bool(st.get("tour", false)) and not bool(st.get("restart", false))


## Nächster Hinweis: A weiter (am Ende -1: fertig), B beendet sofort (-1).
static func tour_next(cur: int, count: int, cmd: String) -> int:
	if cmd == "b" or count <= 0:
		return -1
	if cmd == "a":
		return cur + 1 if cur + 1 < count else -1
	return clampi(cur, 0, count - 1)


# --- Zusammenfassung ----------------------------------------------------------------------

## Was am Ende steht: [[Titel, Text, ok]]. s: { pad, preset, accent_own, games: {steam, epic, ea, emu,
## pc}, accounts: [Namen], extras: [Texte] }.
static func summary(s: Dictionary) -> Array:
	var out: Array = []
	var pad := str(s.get("pad", ""))
	out.append(["Controller", pad if pad != "" else "Tastatur", pad != ""])
	# Das gewählte Farbschema; ohne eigene Wahl das Aussehen der Marke.
	var look := str(s.get("preset", ""))
	if look == "":
		look = "Graphit"
	if bool(s.get("accent_own", false)):
		look += " mit eigener Akzentfarbe"
	out.append(["Aussehen", look, true])
	var g: Dictionary = s.get("games", {})
	var parts := PackedStringArray()
	var total := 0
	for k in [["steam", "Steam"], ["epic", "Epic"], ["ea", "EA"]] + Stores.EXTRA.map(func(id: String) -> Array: return [id, Stores.name_of(id, true)]) + [
			["emu", "Emulator"], ["pc", "PC"]]:
		var n := int(g.get(k[0], 0))
		total += n
		if n > 0:
			parts.append("%s %d" % [k[1], n])
	if total > 0:
		out.append(["Spiele", "%d %s · %s" % [total, "Spiel" if total == 1 else "Spiele", " · ".join(parts)], true])
	else:
		out.append(["Spiele", "Noch keine gefunden", false])
	var acc: Array = s.get("accounts", [])
	if not acc.is_empty():
		out.append(["Konten", ", ".join(PackedStringArray(acc)), true])
	else:
		out.append(["Konten", "Nicht verbunden", false])
	var ex: Array = s.get("extras", [])
	if s.get("has_extras", true):
		if not ex.is_empty():
			out.append(["Extras", ", ".join(PackedStringArray(ex)), true])
		else:
			out.append(["Extras", "Keine", false])
	return out


# --- Höhepunkt und Ende ----------------------------------------------------------------------

## Der Zähler der Spielesuche folgt der gefundenen Zahl als kritisch gedämpfte Feder (läuft hoch,
## ohne zu springen und ohne über das Ziel hinauszuschießen; eine Ausnahme von „Nichts zählt hoch“
## wie das Erfolgs-Pop-up, siehe docs/DESIGN.md › Bewegung). Gibt [Lage, Tempo] zurück.
const ZAEHL_OMEGA := 4.2

static func zaehlen(pos: float, vel: float, ziel: float, dt: float) -> Vector2:
	var x := pos - ziel
	var e := exp(-ZAEHL_OMEGA * dt)
	var k := vel + ZAEHL_OMEGA * x
	var p := ziel + (x + k * dt) * e
	# Nie über das Ziel hinaus (bei großen Schritten der Uhr); im letzten halben Spiel genau dorthin
	# (die Anzeige rundet ohnehin – so endet das Zählen klar statt mit einem langen Ausläufer).
	if (pos <= ziel and p > ziel) or (pos >= ziel and p < ziel) or absf(p - ziel) < 0.5:
		return Vector2(ziel, 0.0)
	return Vector2(p, (vel - ZAEHL_OMEGA * k * dt) * e)


## Platz des i-ten Covers im Regal der Bühne, von der Mitte aus abwechselnd rechts und links:
## 0, +1, −1, +2, −2 … – das Regal füllt sich von innen nach außen.
static func regal_platz(i: int) -> int:
	if i <= 0:
		return 0
	return (i + 1) / 2 if i % 2 == 1 else -(i / 2)


## Die Schilder der Suche (je Quelle eins, sobald dort etwas gefunden ist): erst die Launcher in
## ihrer Folge, dann die Systeme der Spieleordner nach Zahl. launcher, systeme: [[id, Name, Zahl]].
## Gibt [{ id, name, n }] zurück, höchstens hoechstens.
static func quellen(launcher: Array, systeme: Array, hoechstens := 8) -> Array:
	var out: Array = []
	for q in launcher:
		if int(q[2]) > 0:
			out.append({ "id": str(q[0]), "name": str(q[1]), "n": int(q[2]) })
	var sys := systeme.filter(func(q: Array) -> bool: return int(q[2]) > 0)
	sys.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]) or (int(a[2]) == int(b[2]) and str(a[1]) < str(b[1])))
	for q in sys:
		out.append({ "id": str(q[0]), "name": str(q[1]), "n": int(q[2]) })
	return out.slice(0, hoechstens)


## Die eine Zeile unter „Bereit“: „59 Spiele · Xbox Wireless Controller · 2 Konten“ (was fehlt,
## fällt weg). s wie summary: { games: { Quelle → Zahl }, pad, accounts: [Namen] }. uebersetzen:
## übersetzt die Muster („%d Spiele“ …), z. B. tr der Oberfläche.
static func bilanz(s: Dictionary, uebersetzen := Callable()) -> String:
	var t := func(x: String) -> String: return str(uebersetzen.call(x)) if uebersetzen.is_valid() else x
	var parts := PackedStringArray()
	var total := 0
	var g: Dictionary = s.get("games", {})
	for k in g.keys():
		total += int(g[k])
	if total > 0:
		parts.append(str(t.call("%d Spiel" if total == 1 else "%d Spiele")) % total)
	var pad := str(s.get("pad", ""))
	if pad != "":
		parts.append(pad)
	var acc: Array = s.get("accounts", [])
	if acc.size() == 1:
		parts.append(str(acc[0]))
	elif acc.size() > 1:
		parts.append(str(t.call("%d Konten")) % acc.size())
	return " · ".join(parts)


# --- Suchen: Emulatoren und Spieleordner -----------------------------------------------------

## Andere Programmnamen und Ordner, unter denen Emulatoren oft liegen (zusätzlich zu exe_hint).
const ALT_EXE := {
	"pcsx2": ["pcsx2-qt.exe", "pcsx2-qtx64-avx2.exe", "pcsx2-qtx64.exe", "pcsx2.exe"],
	"duckstation": ["duckstation-qt-x64-ReleaseLTCG.exe", "duckstation-qt.exe"],
	"retroarch": ["retroarch.exe"],
	"ryubing": ["Ryujinx.exe", "Ryubing.exe"],
	"ppsspp": ["PPSSPPWindows64.exe", "PPSSPPWindows.exe"],
	"xenia": ["xenia_canary.exe", "xenia.exe"],
}
const ALT_DIR := {
	"pcsx2": ["PCSX2", "pcsx2-qt"],
	"duckstation": ["DuckStation", "duckstation-windows-x64-release"],
	"dolphin": ["Dolphin", "Dolphin-x64", "Dolphin Emulator"],
	"retroarch": ["RetroArch", "RetroArch-Win64"],
	"ryubing": ["Ryubing", "Ryujinx", "publish"],
	"ppsspp": ["PPSSPP"],
	"cemu": ["Cemu"],
	"rpcs3": ["RPCS3"],
	"mgba": ["mGBA"],
	"melonds": ["melonDS"],
	"xenia": ["Xenia", "xenia_canary"],
}
## Programme, die auch über Steam kommen (Ordner unter steamapps/common).
const STEAM_EMUS := { "retroarch": "RetroArch/retroarch.exe", "dolphin": "Dolphin/Dolphin.exe", "ppsspp": "PPSSPP/PPSSPPWindows64.exe",
		"xemu": "xemu/xemu.exe" }

## Ordner, in denen Emulatoren meist liegen. drives: ["C:", "D:"], env: Umgebungsvariablen.
static func emu_roots(drives: Array, env: Dictionary) -> Array:
	var out: Array = []
	for d in drives:
		for sub in ["Emulatoren", "Emulators", "Emulation", "Emulation/Emulators", "Emu", "Games/Emulatoren", "Games/Emulators", "Spiele/Emulatoren",
				"RetroBat/emulators", "LaunchBox/Emulators"]:
			out.append(str(d).trim_suffix("/") + "/" + sub)
		out.append(str(d).trim_suffix("/"))
	var home := str(env.get("USERPROFILE", "")).replace("\\", "/")
	if home != "":
		for sub in ["Emulatoren", "Emulators", "Emulation", "Documents/Emulatoren", "Documents/Emulators", "Desktop/Emulatoren", "Desktop/Emulators", "Downloads"]:
			out.append(home + "/" + sub)
	for k in ["ProgramFiles", "ProgramFiles(x86)"]:
		var p := str(env.get(k, "")).replace("\\", "/")
		if p != "":
			out.append(p)
	var la := str(env.get("LOCALAPPDATA", "")).replace("\\", "/")
	if la != "":
		out.append(la + "/Programs")
	return _unique(out)


## Mögliche Programmdateien eines Emulators: exe_hint selbst, dann seine Ordner- und
## Programmnamen unter jedem Suchort, dazu die Steam-Bibliotheken.
static func emu_candidates(emu: Dictionary, roots: Array, steam_libs: Array = []) -> Array:
	var id := str(emu.get("id", ""))
	var hint := str(emu.get("exe_hint", "")).replace("\\", "/")
	var exes: Array = []
	if hint != "":
		exes.append(hint.get_file())
	for e in ALT_EXE.get(id, []):
		if not exes.has(e):
			exes.append(e)
	var dirs: Array = []
	if hint != "" and hint.get_base_dir().get_file() != "":
		dirs.append(hint.get_base_dir().get_file())
	var nm := str(emu.get("name", ""))
	if nm != "" and not dirs.has(nm):
		dirs.append(nm)
	for d in ALT_DIR.get(id, []):
		if not dirs.has(d):
			dirs.append(d)
	var out: Array = []
	if hint != "":
		out.append(hint)
	for r in roots:
		for d in dirs:
			for e in exes:
				out.append("%s/%s/%s" % [str(r).trim_suffix("/"), d, e])
	if STEAM_EMUS.has(id):
		for lib in steam_libs:
			out.append(str(lib).replace("\\", "/").trim_suffix("/") + "/steamapps/common/" + str(STEAM_EMUS[id]))
	return _unique(out)


## Wo Spieleordner meist liegen: <Laufwerk>/ROMs, <Laufwerk>/Emulation/roms, ~/ROMs …
static func rom_roots(drives: Array, env: Dictionary) -> Array:
	var out: Array = []
	for d in drives:
		for sub in ["ROMs", "Roms", "Games/ROMs", "Spiele/ROMs", "Emulation/roms", "Emulation/ROMs", "Emulatoren/ROMs", "Emulators/ROMs", "RetroBat/roms", "Spiele",
				"Games", "ISOs"]:
			out.append(str(d).trim_suffix("/") + "/" + sub)
	var home := str(env.get("USERPROFILE", "")).replace("\\", "/")
	if home != "":
		for sub in ["ROMs", "Roms", "Documents/ROMs", "Games/ROMs", "Emulation/roms", "Spiele/ROMs"]:
			out.append(home + "/" + sub)
	return _unique(out)


## Andere Ordnernamen für Systeme (EmuDeck, RetroBat, Batocera, LaunchBox …).
const SYS_ALIASES := {
	"ps1": ["psx", "playstation", "playstation1", "ps", "sonyplaystation"],
	"ps2": ["playstation2", "sonyplaystation2"],
	"ps3": ["playstation3"],
	"psp": ["playstationportable"],
	"gc": ["gamecube", "ngc", "nintendogamecube"],
	"wii": ["nintendowii"],
	"wiiu": ["nintendowiiu"],
	"switch": ["nintendoswitch", "ns"],
	"n64": ["nintendo64"],
	"snes": ["supernintendo", "superfamicom", "sfc"],
	"nes": ["famicom", "fc", "nintendoentertainmentsystem"],
	"gba": ["gameboyadvance"],
	"gb": ["gameboy"],
	"gbc": ["gameboycolor"],
	"nds": ["ds", "nintendods"],
	"3ds": ["n3ds", "nintendo3ds"],
	"megadrive": ["genesis", "segagenesis", "segamegadrive", "md"],
	"mastersystem": ["sms", "segamastersystem"],
	"gamegear": ["gg", "segagamegear"],
	"saturn": ["segasaturn"],
	"dreamcast": ["dc", "segadreamcast"],
	"pce": ["pcengine", "tg16", "turbografx16", "turbografx"],
	"arcade": ["mame", "fbneo", "fba"],
	"atari2600": ["atari", "a2600"],
	"xbox": ["microsoftxbox"],
	"xbox360": ["x360", "microsoftxbox360"],
}


static func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## Welches System ein Ordner meint ("" wenn keins): Kennung, Kurzname, Name oder ein Alias.
static func system_for_dir(dir_name: String, systems: Array) -> String:
	var n := _norm(dir_name)
	if n == "":
		return ""
	for s in systems:
		var sid := str(s.get("id", ""))
		if n == _norm(sid) or n == _norm(str(s.get("short", ""))) or n == _norm(str(s.get("name", ""))):
			return sid
	for s in systems:
		var sid2 := str(s.get("id", ""))
		for a in SYS_ALIASES.get(sid2, []):
			if n == str(a):
				return sid2
	return ""


## Spieleordner unter den Suchorten: [{ system, dir }]. list_dirs(pfad) → Unterordner (zum Testen
## austauschbar). Jedes System nur einmal (der erste Fund zählt), schon eingetragene nicht.
static func find_rom_dirs(roots: Array, systems: Array, list_dirs: Callable, taken: Dictionary = {}) -> Array:
	var out: Array = []
	var seen := taken.duplicate()
	for r in roots:
		for sub in list_dirs.call(str(r)):
			var sid := system_for_dir(str(sub), systems)
			if sid == "" or seen.has(sid):
				continue
			seen[sid] = true
			out.append({ "system": sid, "dir": str(r).trim_suffix("/") + "/" + str(sub) })
	return out


## Ein selbst gewählter Ordner: Liegen darin Unterordner pro System (ps2, gba …), alle; sonst das
## System mit den meisten passenden Dateien. counts: { system → Dateien direkt im Ordner }.
static func classify_folder(dir: String, subdirs: Array, systems: Array, counts: Dictionary) -> Dictionary:
	var found := find_rom_dirs([dir], systems, func(_p: String) -> Array: return subdirs)
	if not found.is_empty():
		return { "kind": "unterordner", "list": found }
	var best := ""
	var most := 0
	for sid in counts.keys():
		if int(counts[sid]) > most:
			most = int(counts[sid])
			best = str(sid)
	return { "kind": "ein_system", "system": best, "count": most }


static func _unique(a: Array) -> Array:
	var seen := {}
	var out: Array = []
	for x in a:
		var k := str(x).to_lower()
		if not seen.has(k):
			seen[k] = true
			out.append(x)
	return out
