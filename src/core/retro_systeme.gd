extends RefCounted
## Welche Systeme als Retro-System gelten: Emulator-Spiele dieser Systeme tragen ihre Notizen im
## Backlog (Spielseite, „Alles zum Spiel“). Die Switch fehlt mit Absicht – kein Retro-System.

const SYSTEME := ["arcade", "atari2600", "nes", "mastersystem", "pce", "megadrive", "gb", "snes", "gamegear",
	"saturn", "ps1", "n64", "gbc", "dreamcast", "ps2", "gba", "gc", "xbox", "nds", "psp", "xbox360", "ps3",
	"wii", "3ds", "wiiu"]


static func is_retro(sys_id: String) -> bool:
	return sys_id in SYSTEME


## Ist das ein Spiel aus einem Emulator (bzw. von einer Disc) für ein Retro-System?
static func is_retro_game(g: Dictionary) -> bool:
	return str(g.get("source", "")) in ["rom", "disc"] and is_retro(str(g.get("system", "")))
