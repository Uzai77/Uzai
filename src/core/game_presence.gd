extends RefCounted
## Discord-Status beim Spielen (Roadmap 89): „Spielt <Titel>“ mit dem Cover, darunter Laden bzw.
## System („PlayStation 2 · Uzai“) und die Zeit seit dem Start – für Steam-, Epic-, EA-, PC- und
## Emulator-Spiele gleich. Discord lädt das Cover selbst über seinen Bild-Proxy; Uzai gibt dafür
## nur öffentliche https-Adressen bekannter Bildserver weiter (Steam, Epic, SteamGridDB, iiDB, Libretro),
## nie eigene Dateien, nie andere Adressen. Je Spiel abschaltbar (presence_hidden).
##
## Einen Beitreten-Knopf gibt es bewusst nicht: Knöpfe im Discord-Status dürfen nur Webadressen
## öffnen (steam://joinlobby geht nicht), und Discords eigenes „Beitreten“ erreicht nur Freunde,
## deren Uzai dieselbe Discord-App nutzt – heute trägt jeder seine eigene ein (siehe Roadmap 48).
## Ohne Discord und ohne Windows, darum testbar (tests/logic_dcstatus.gd).

## Bildserver, deren Adressen in den Status dürfen (genau diese Namen, keine Unterdomänen).
const IMAGE_HOSTS := [
	"shared.steamstatic.com", "shared.akamai.steamstatic.com", "shared.fastly.steamstatic.com",
	"shared.cloudflare.steamstatic.com", "cdn.cloudflare.steamstatic.com", "cdn.akamai.steamstatic.com",
	"cdn.fastly.steamstatic.com", "steamcdn-a.akamaihd.net",
	"cdn1.epicgames.com", "cdn2.unrealengine.com",
	"cdn2.steamgriddb.com", "cdn.steamgriddb.com",
	"assets.iisu.network",           # iiDB: der Dateiserver aus der Entwickler-Doku (docs/IIDB.md)
	"thumbnails.libretro.com", "raw.githubusercontent.com",
]
## Auf GitHub nur der Libretro-Spiegel der Vorschaubilder.
const GITHUB_PATH := "/libretro-thumbnails/"
const URL_MAX := 256      ## längere Bildadressen nimmt Discord nicht
const TEXT_MAX := 128     ## Discords Grenze für Zeilen im Status
## status_display_type der Aktivität: welche Zeile Discord kurz neben dem Namen zeigt (0 App-Name,
## 1 state, 2 details).
const DISPLAY_DETAILS := 2


## Darf diese Adresse als Cover in den Status? Nur https, bekannter Bildserver, kein Port, keine
## Anmeldedaten, keine Leer- oder Steuerzeichen, höchstens URL_MAX Zeichen.
static func image_ok(url: String) -> bool:
	if url.length() > URL_MAX or not url.begins_with("https://"):
		return false
	for ch in url:
		if ch <= " " or ch in ["\"", "'", "<", ">", "\\", "`", "{", "}", "|", "^"]:
			return false
	var rest := url.substr(8)
	var cut := rest.length()
	for sep in ["/", "?", "#"]:
		var i := rest.find(sep)
		if i >= 0 and i < cut:
			cut = i
	var host := rest.substr(0, cut).to_lower()
	var path := rest.substr(cut)
	if host == "" or host.contains("@") or host.contains(":") or not path.begins_with("/") or path.length() < 2:
		return false
	if not host in IMAGE_HOSTS:
		return false
	return host != "raw.githubusercontent.com" or path.begins_with(GITHUB_PATH)


## Soll dieses Spiel nicht im Status stehen? (Spieloptionen → „Im Discord-Status zeigen“)
static func hidden(g: Dictionary) -> bool:
	return bool(g.get("presence_hidden", false))


## Zweite Zeile: Laden oder System, dazu „Uzai“ („Epic Games · Uzai“, „PlayStation 2 · Uzai“).
static func state_text(g: Dictionary, system_name := "") -> String:
	var where := Library.store_name(g, false, system_name)
	return _line("%s · Uzai" % where) if where != "" else "Uzai"


## Aktivität für den Helfer-Befehl „presence“ ({} = nichts zeigen). start: Unix-Zeit des Starts;
## image wird nur übernommen, wenn image_ok.
static func activity(g: Dictionary, image: String, start: int, system_name := "") -> Dictionary:
	if hidden(g):
		return {}
	var title := _line(str(g.get("title", "")))
	if title == "":
		return {}
	# display 2: Freunde sehen in der Mitgliederliste „Spielt <Titel>“ statt „Spielt Uzai“.
	var a := { "details": title, "state": state_text(g, system_name), "start": maxi(start, 0), "display": DISPLAY_DETAILS }
	if image_ok(image):
		a["image"] = image
		a["large_text"] = title
	return a


## Eine Zeile für Discord: ohne Zeilenumbrüche, höchstens TEXT_MAX Zeichen, mindestens zwei
## (kürzere nimmt Discord nicht – „Q“ wird „„Q““).
static func _line(s: String) -> String:
	var t := s.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if t.length() > TEXT_MAX:
		t = t.left(TEXT_MAX - 1).strip_edges() + "…"
	if t.length() == 1:
		t = "„%s“" % t
	return t
