extends RefCounted
## Fehlende Launcher (Punkt 115). Findet Uzai Steam, den Epic Games Launcher, die EA app oder einen
## der weiteren Launcher (Punkt 6: GOG Galaxy, Ubisoft Connect, Battle.net, Xbox-App, Amazon Games,
## itch-App, Riot Client – die nur, wenn es Spiele von ihnen gibt) nicht,
## bietet es die offizielle Seite an – und nur die: feste HTTPS-Adressen der Anbieter, nichts
## Mitgeliefertes, kein eigenes Herunterladen oder Ausführen, nie von selbst. Installiert wird auf
## der Seite des Anbieters wie gewohnt; danach liest Uzai die Spiele beim nächsten Einlesen.

const ORDER := ["steam", "epic", "ea", "gog", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot"]
## Nur anbieten, wenn es Spiele dieser Quelle gibt (need): Wer kein Battle.net nutzt, braucht es nicht.
const ON_NEED := ["gog", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot"]
const SITES := {
	"steam": { "name": "Steam", "url": "https://store.steampowered.com/about/", "icon": "steam",
		"what": "Steam-Spiele, der Shop, Erfolge und der Chat" },
	"epic": { "name": "Epic Games Launcher", "url": "https://store.epicgames.com/download", "icon": "games",
		"what": "deine Epic-Spiele – auch die kostenlosen der Woche" },
	"ea": { "name": "EA app", "url": "https://www.ea.com/ea-app", "icon": "games",
		"what": "deine EA-Spiele (früher Origin)" },
	"gog": { "name": "GOG Galaxy", "url": "https://www.gog.com/galaxy", "icon": "store_gog",
		"what": "deine GOG-Spiele, die nur über Galaxy starten" },
	"ubisoft": { "name": "Ubisoft Connect", "url": "https://ubisoftconnect.com/", "icon": "store_ubisoft",
		"what": "deine Ubisoft-Spiele" },
	"battlenet": { "name": "Battle.net", "url": "https://download.battle.net/", "icon": "store_battlenet",
		"what": "deine Blizzard- und Battle.net-Spiele" },
	"xboxpc": { "name": "Xbox-App", "url": "https://www.xbox.com/apps/xbox-app-for-pc", "icon": "store_xbox",
		"what": "deine PC-Game-Pass- und Xbox-Spiele" },
	"amazon": { "name": "Amazon Games", "url": "https://gaming.amazon.com/home", "icon": "store_amazon",
		"what": "deine Spiele aus Amazon Games" },
	"itch": { "name": "itch-App", "url": "https://itch.io/app", "icon": "store_itch",
		"what": "deine itch.io-Spiele, die nur über die App starten" },
	"riot": { "name": "Riot Client", "url": "https://www.riotgames.com/", "icon": "store_riot",
		"what": "League of Legends, VALORANT und die anderen Riot-Spiele" },
}


## Welche fehlen sicher? found: { steam: true/false, … } aus Library.launchers – ein fehlender
## Eintrag heißt „weiß ich nicht“ (anderes System, Helfer antwortete nicht): dann nichts anbieten.
## enabled: welche Quellen eingeschaltet sind (ausgeschaltete bietet Uzai nicht an), need: von
## welchen weiteren Launchern (ON_NEED) es Spiele gibt (Library.launcher_need).
static func missing(found: Dictionary, enabled: Dictionary, need: Dictionary = {}) -> Array:
	var out: Array = []
	for id in ORDER:
		if id in ON_NEED and not bool(need.get(id, false)):
			continue
		if found.has(id) and not bool(found[id]) and bool(enabled.get(id, true)):
			out.append(id)
	return out


static func site(id: String) -> Dictionary:
	return SITES.get(id, {})


## Nur feste https-Adressen aus SITES – nie etwas aus Einstellungen oder dem Netz.
static func url(id: String) -> String:
	var u := str(site(id).get("url", ""))
	return u if u.begins_with("https://") else ""
