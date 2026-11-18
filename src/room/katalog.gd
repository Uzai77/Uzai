extends RefCounted
## Möbelkatalog für „Dein Zimmer“ (Punkt 131): was es gibt, wie groß es ist (in Rasterfeldern zu
## je ZELLE Metern), auf welcher Ebene es steht und was man damit tun kann. Reine Daten – gebaut
## werden die Möbel in moebel.gd, aus eigenen Formen und einigen freien Modellen (CC0 / CC BY 4.0,
## assets/zimmer/LIZENZ.txt).
##
## Ebenen: „boden“ (steht im Weg), „teppich“ (liegt unter allem, man läuft darüber), „klein“ (steht
## auf dem Boden oder auf einer Fläche eines Bodenmöbels), „wand“ (hängt an einer Wand, Rückseite
## zur Wand) und „decke“ (hängt an der Decke). Jede Ebene belegt ihre Felder für sich.
##
## Nutzen (A im Zimmer): spiele (Regal), pokale (Schrank), platten (Plattenregal), musik
## (Plattenspieler), fernseher (Medienwand mit Konsole), sitzen, lampe – sonst nichts.
##
## Anpassen (gestalt.gd): stufen = Größen (Felder, Höhe, Abstellfläche), beine/griffe = Varianten
## wählbar, gestell = Name des zweiten Teils (eigene Farbe und eigenes Material). Eigene Möbel aus
## dem Baukasten (Kennung „e_…“) meldet das Zimmer beim Laden an (eigene_setzen) – sie sind Daten
## aus zimmer.json, geprüft in gestalt.gd.

const ZELLE := 0.5               ## Kantenlänge eines Rasterfelds in Metern

## Möbel nach Zweck (Bau-Menü, bau_inhalt.gd: dort Zeichen und Reihenfolge neben den Raum-Bereichen).
const KATEGORIEN := [
	["sitzen", "Sitzen und Liegen"], ["tische", "Tische"], ["regale", "Regale und Stauraum"],
	["technik", "Technik"], ["licht", "Lampen"], ["pflanzen", "Pflanzen"], ["deko", "Deko"], ["eigene", "Eigene"],
]

const STOFFE := [["salbei", "Salbei"], ["senf", "Senf"], ["terrakotta", "Terrakotta"],
	["nachtblau", "Nachtblau"], ["creme", "Creme"], ["graphit", "Graphit"]]
const HOELZER := [["eiche", "Eiche"], ["walnuss", "Walnuss"], ["weiss", "Weiß lackiert"], ["schwarz", "Schwarz"]]
const FERNSEHER := [["roehre", "Röhre"], ["flach", "Flachbild"], ["beamer", "Beamer"]]
const MOTIVE := [["huegel", "Hügel"], ["sonne", "Sonne"], ["wellen", "Wellen"], ["punkte", "Punkte"]]
const PFLANZEN := [["monstera", "Monstera"], ["olive", "Olivenbaum"], ["kaktus", "Kaktus"]]
const LICHTFARBEN := [["warm", "Warmweiß"], ["gold", "Gold"], ["bunt", "Bunt"]]
const METALLE := [["messing", "Messing"], ["schwarz", "Schwarz"], ["chrom", "Chrom"]]
const TOPFFARBEN := [["weiss", "Weiß"], ["terrakotta", "Terrakotta"], ["schwarz", "Schwarz"]]

## Größenstufen (Felder bei Drehung 0, Höhe, Abstellfläche).
const SOFA_STUFEN := [{ "w": 3, "d": 2, "name": "Zweisitzer" }, { "w": 4, "d": 2, "name": "Dreisitzer" }, { "w": 5, "d": 2, "name": "Viersitzer" }]
const TISCH_STUFEN := [{ "w": 2, "d": 2, "name": "Klein" }, { "w": 3, "d": 2, "name": "Mittel" }, { "w": 4, "d": 2, "name": "Lang" }]
const REGAL_STUFEN := [{ "w": 2, "d": 1, "name": "Niedrig", "h": 1.12, "flaeche": 1.12 }, { "w": 2, "d": 1, "name": "Hoch", "h": 1.92 },
	{ "w": 4, "d": 1, "name": "Breit", "h": 1.92 }, { "w": 4, "d": 1, "name": "Breit und niedrig", "h": 1.12, "flaeche": 1.12 }]
const TEPPICH_STUFEN := [{ "w": 4, "d": 3, "name": "Klein" }, { "w": 6, "d": 4, "name": "Mittel" }, { "w": 8, "d": 5, "name": "Groß" }]
const RUND_STUFEN := [{ "w": 3, "d": 3, "name": "Klein" }, { "w": 4, "d": 4, "name": "Mittel" }, { "w": 6, "d": 6, "name": "Groß" }]
const LEISTE_STUFEN := [{ "w": 2, "d": 1, "name": "1 Meter" }, { "w": 4, "d": 1, "name": "2 Meter" }, { "w": 6, "d": 1, "name": "3 Meter" }]
const PFLANZE_STUFEN := [{ "w": 1, "d": 1, "name": "Klein", "h": 0.85 }, { "w": 1, "d": 1, "name": "Mittel", "h": 1.3 },
		{ "w": 2, "d": 2, "name": "Groß", "h": 1.8 }]
const BETT_STUFEN := [{ "w": 2, "d": 5, "name": "Einzelbett" }, { "w": 3, "d": 5, "name": "140 cm breit" }, { "w": 4, "d": 5, "name": "180 cm breit" }]
const WANDREGAL_STUFEN := [{ "w": 2, "d": 1, "name": "1 Meter" }, { "w": 3, "d": 1, "name": "1,5 Meter" }, { "w": 4, "d": 1, "name": "2 Meter" }]

## id → Angaben. w × d: Felder in Breite (x) und Tiefe (z) bei Drehung 0 (Vorderseite nach +z).
## h: Höhe in Metern (für Auswahl und Kamera). flaeche: Höhe der Abstellfläche (0 = keine).
## max: höchstens so viele im Zimmer (0 = beliebig).
const MOEBEL := {
	"sofa": { "name": "Sofa", "kat": "sitzen", "w": 4, "d": 2, "h": 0.86, "ebene": "boden", "varianten": STOFFE, "std": "salbei", "nutzen": "sitzen",
		"stufen": SOFA_STUFEN, "stufe": 1, "beine": true, "gestell": "Beine" },
	"sessel": { "name": "Sessel", "kat": "sitzen", "w": 2, "d": 2, "h": 0.9, "ebene": "boden", "varianten": STOFFE, "std": "senf", "nutzen": "sitzen",
		"beine": true, "gestell": "Beine" },
	"sitzsack": { "name": "Sitzsack", "kat": "sitzen", "w": 2, "d": 2, "h": 0.62, "ebene": "boden", "varianten": STOFFE, "std": "terrakotta", "nutzen": "sitzen" },
	"hocker": { "name": "Hocker", "kat": "sitzen", "w": 1, "d": 1, "h": 0.45, "ebene": "boden", "varianten": STOFFE, "std": "creme", "nutzen": "sitzen",
		"flaeche": 0.45 },
	"couchtisch": { "name": "Couchtisch", "kat": "tische", "w": 3, "d": 2, "h": 0.42, "ebene": "boden", "varianten": HOELZER, "std": "eiche", "flaeche": 0.42,
		"stufen": TISCH_STUFEN, "stufe": 1, "beine": true, "gestell": "Beine" },
	"beistelltisch": { "name": "Beistelltisch", "kat": "tische", "w": 1, "d": 1, "h": 0.55, "ebene": "boden", "varianten": HOELZER, "std": "walnuss",
		"flaeche": 0.55, "gestell": "Fuß" },
	"schreibtisch": { "name": "Schreibtisch", "kat": "tische", "w": 3, "d": 2, "h": 0.76, "ebene": "boden", "varianten": HOELZER, "std": "eiche", "flaeche": 0.76,
		"stufen": TISCH_STUFEN, "stufe": 1, "beine": true, "griffe": true, "gestell": "Beine" },
	"kommode": { "name": "Kommode", "kat": "regale", "w": 2, "d": 1, "h": 0.8, "ebene": "boden", "varianten": HOELZER, "std": "walnuss", "flaeche": 0.8,
		"stufen": [{ "w": 2, "d": 1, "name": "Schmal" }, { "w": 3, "d": 1, "name": "Mittel" }, { "w": 4, "d": 1, "name": "Breit" }], "stufe": 0, "beine": true,
		"griffe": true, "gestell": "Beine" },
	"spieleregal": { "name": "Spieleregal", "kat": "regale", "w": 2, "d": 1, "h": 1.92, "ebene": "boden", "varianten": HOELZER, "std": "eiche", "nutzen": "spiele",
		"stufen": REGAL_STUFEN, "stufe": 1 },
	"trophaeenschrank": { "name": "Trophäenschrank", "kat": "regale", "w": 2, "d": 1, "h": 1.86, "ebene": "boden", "varianten": HOELZER, "std": "walnuss",
		"nutzen": "pokale", "stufen": [{ "w": 2, "d": 1, "name": "Schmal" }, { "w": 4, "d": 1, "name": "Breit" }], "stufe": 0, "griffe": true },
	"plattenregal": { "name": "Plattenregal", "kat": "regale", "w": 2, "d": 1, "h": 0.74, "ebene": "boden", "varianten": HOELZER, "std": "eiche",
		"nutzen": "platten", "flaeche": 0.74,
		"stufen": [{ "w": 2, "d": 1, "name": "2 × 2 Fächer", "flaeche": 0.74 }, { "w": 4, "d": 1, "name": "4 × 2 Fächer", "h": 0.74, "flaeche": 0.74 },
		{ "w": 2, "d": 1, "name": "2 × 4 Fächer", "h": 1.46, "flaeche": 1.46 }], "stufe": 0 },
	"buecherregal": { "name": "Bücherregal", "kat": "regale", "w": 2, "d": 1, "h": 1.6, "ebene": "boden", "varianten": HOELZER, "std": "weiss",
		"stufen": REGAL_STUFEN, "stufe": 1 },
	"medienwand": { "name": "Fernseher", "kat": "technik", "w": 4, "d": 1, "h": 1.25, "ebene": "boden", "varianten": FERNSEHER, "std": "flach",
		"nutzen": "fernseher", "max": 1, "beine": true, "gestell": "Beine" },
	"lautsprecher": { "name": "Lautsprecher", "kat": "technik", "w": 1, "d": 1, "h": 1.0, "ebene": "boden", "varianten": HOELZER, "std": "walnuss",
		"gestell": "Bespannung" },
	"plattenspieler": { "name": "Plattenspieler", "kat": "technik", "w": 1, "d": 1, "h": 0.14, "ebene": "klein", "varianten": HOELZER, "std": "walnuss",
		"nutzen": "musik" },
	"stehlampe": { "name": "Stehlampe", "kat": "licht", "w": 1, "d": 1, "h": 1.62, "ebene": "boden", "varianten": STOFFE, "std": "creme", "nutzen": "lampe",
		"gestell": "Gestell" },
	"tischlampe": { "name": "Tischlampe", "kat": "licht", "w": 1, "d": 1, "h": 0.46, "ebene": "klein", "varianten": STOFFE, "std": "senf", "nutzen": "lampe",
		"gestell": "Fuß" },
	"deckenlampe": { "name": "Deckenlampe", "kat": "licht", "w": 2, "d": 2, "h": 0.5, "ebene": "decke", "varianten": STOFFE, "std": "creme", "nutzen": "lampe" },
	"led_leiste": { "name": "LED-Leiste", "kat": "licht", "w": 4, "d": 1, "h": 0.05, "ebene": "wand",
		"varianten": [["oben", "Unter der Decke"], ["hinten", "Hinter Möbeln"]], "std": "oben", "nutzen": "lampe", "stufen": LEISTE_STUFEN, "stufe": 1,
		"farblicht": true },
	"lichterkette": { "name": "Lichterkette", "kat": "licht", "w": 4, "d": 1, "h": 0.4, "ebene": "wand", "varianten": LICHTFARBEN, "std": "warm",
		"nutzen": "lampe", "stufen": LEISTE_STUFEN, "stufe": 1 },
	"pflanze": { "name": "Pflanze", "kat": "pflanzen", "w": 1, "d": 1, "h": 1.3, "ebene": "boden", "varianten": PFLANZEN, "std": "monstera", "stufen": PFLANZE_STUFEN,
		"stufe": 1, "gestell": "Topf" },
	"topfpflanze": { "name": "Kleine Pflanze", "kat": "pflanzen", "w": 1, "d": 1, "h": 0.3, "ebene": "klein", "varianten": PFLANZEN, "std": "kaktus",
		"gestell": "Topf" },
	"teppich": { "name": "Teppich", "kat": "deko", "w": 6, "d": 4, "h": 0.02, "ebene": "teppich", "varianten": STOFFE, "std": "creme", "stufen": TEPPICH_STUFEN,
		"stufe": 1, "gestell": "Rand" },
	"teppich_rund": { "name": "Runder Teppich", "kat": "deko", "w": 4, "d": 4, "h": 0.02, "ebene": "teppich", "varianten": STOFFE, "std": "senf",
		"stufen": RUND_STUFEN, "stufe": 1, "gestell": "Rand" },
	"bild": { "name": "Bild", "kat": "deko", "w": 2, "d": 1, "h": 0.7, "ebene": "wand", "varianten": MOTIVE, "std": "huegel",
		"stufen": [{ "w": 2, "d": 1, "name": "Klein" }, { "w": 3, "d": 1, "name": "Mittel" }, { "w": 4, "d": 1, "name": "Groß" }], "stufe": 0, "gestell": "Rahmen" },
	"wanduhr": { "name": "Wanduhr", "kat": "deko", "w": 1, "d": 1, "h": 0.4, "ebene": "wand", "varianten": HOELZER, "std": "schwarz" },
	"buecher": { "name": "Bücherstapel", "kat": "deko", "w": 1, "d": 1, "h": 0.16, "ebene": "klein", "varianten": STOFFE, "std": "nachtblau" },
	# Figur und Haustier (src/room/figur/moebel_figur.gd); Lavalampe, Leuchtschild und Körbchen
	# schalten Meilensteine frei (figur/meilensteine.gd). Am Jackenständer wechselst du die Figur.
	"jackenstaender": { "name": "Jackenständer", "kat": "deko", "w": 1, "d": 1, "h": 1.8, "ebene": "boden", "varianten": HOELZER, "std": "eiche",
		"nutzen": "figur" },
	"tierkorb": { "name": "Tierkörbchen", "kat": "deko", "w": 1, "d": 1, "h": 0.15, "ebene": "boden", "varianten": STOFFE, "std": "terrakotta", "nutzen": "tier",
		"max": 1 },
	"lavalampe": { "name": "Lavalampe", "kat": "licht", "w": 1, "d": 1, "h": 0.42, "ebene": "klein",
		"varianten": [["orange", "Orange"], ["lila", "Lila"], ["mint", "Mint"]], "std": "orange", "nutzen": "lampe" },
	"neonschild": { "name": "Leuchtschild", "kat": "licht", "w": 2, "d": 1, "h": 0.42, "ebene": "wand",
		"varianten": [["rosa", "Rosa"], ["blau", "Blau"], ["gold", "Gold"]], "std": "rosa", "nutzen": "lampe" },
	# Echte Möbel aus freien Modellen (CC0 / CC BY 4.0, assets/zimmer/LIZENZ.txt; moebel.gd
	# MODELLE) und weitere eigene: Spielplatz, Deko, Snacks.
	"sofa_samt": { "name": "Samtsofa", "kat": "sitzen", "w": 5, "d": 2, "h": 0.79, "ebene": "boden", "varianten": STOFFE, "std": "nachtblau",
		"nutzen": "sitzen" },
	"sofa_leder": { "name": "Ledersofa", "kat": "sitzen", "w": 6, "d": 2, "h": 1.12, "ebene": "boden", "varianten": [["braun", "Braun"]], "std": "braun",
		"nutzen": "sitzen" },
	"sessel_samt": { "name": "Samtsessel", "kat": "sitzen", "w": 2, "d": 2, "h": 0.69, "ebene": "boden", "varianten": STOFFE, "std": "senf", "nutzen": "sitzen" },
	"sessel_damast": { "name": "Damastsessel", "kat": "sitzen", "w": 2, "d": 2, "h": 0.69, "ebene": "boden", "varianten": [["lila", "Lila und Gold"]],
		"std": "lila", "nutzen": "sitzen" },
	"gamingstuhl": { "name": "Gaming-Stuhl", "kat": "sitzen", "w": 2, "d": 2, "h": 1.28, "ebene": "boden", "varianten": STOFFE, "std": "graphit",
		"nutzen": "sitzen", "gestell": "Gestell" },
	"minikuehlschrank": { "name": "Minikühlschrank", "kat": "technik", "w": 1, "d": 1, "h": 0.86, "ebene": "boden",
		"varianten": [["creme", "Creme"], ["schwarz", "Schwarz"], ["mint", "Mint"]], "std": "creme", "flaeche": 0.86 },
	"monitor": { "name": "Monitor", "kat": "technik", "w": 2, "d": 1, "h": 0.5, "ebene": "klein", "varianten": [["schwarz", "Schwarz"], ["weiss", "Weiß"]],
		"std": "schwarz" },
	"rechner": { "name": "Spiele-PC", "kat": "technik", "w": 1, "d": 1, "h": 0.46, "ebene": "klein", "varianten": [["schwarz", "Schwarz"], ["weiss", "Weiß"]],
		"std": "schwarz" },
	"regallautsprecher": { "name": "Regallautsprecher", "kat": "technik", "w": 1, "d": 1, "h": 0.3, "ebene": "klein", "varianten": HOELZER, "std": "walnuss",
		"gestell": "Front" },
	"radio": { "name": "Radiorekorder", "kat": "technik", "w": 1, "d": 1, "h": 0.38, "ebene": "klein", "varianten": [["grau", "Grau"]], "std": "grau" },
	"stehlampe_dreiarm": { "name": "Dreiarmige Stehlampe", "kat": "licht", "w": 2, "d": 2, "h": 1.86, "ebene": "boden", "varianten": [["weiss", "Weiß"]],
		"std": "weiss", "nutzen": "lampe" },
	"wandlampe": { "name": "Wandlampe", "kat": "licht", "w": 1, "d": 1, "h": 0.32, "ebene": "wand", "varianten": [["schwarz", "Schwarz"]], "std": "schwarz",
		"nutzen": "lampe" },
	"pflanze_busch": { "name": "Blattpflanze", "kat": "pflanzen", "w": 2, "d": 2, "h": 0.97, "ebene": "boden", "varianten": [["gruen", "Grün"]], "std": "gruen" },
	"vase_blumen": { "name": "Blumenvase", "kat": "pflanzen", "w": 1, "d": 1, "h": 0.27, "ebene": "klein", "varianten": [["bunt", "Bunt"]], "std": "bunt" },
	"tasse": { "name": "Teetasse", "kat": "deko", "w": 1, "d": 1, "h": 0.08, "ebene": "klein", "varianten": [["weiss", "Weiß"]], "std": "weiss" },
	"spielzeugauto": { "name": "Spielzeugauto", "kat": "deko", "w": 1, "d": 1, "h": 0.08, "ebene": "klein", "varianten": [["rot", "Rot"]], "std": "rot" },
	"kissen": { "name": "Kissen", "kat": "deko", "w": 1, "d": 1, "h": 0.14, "ebene": "klein", "varianten": STOFFE, "std": "terrakotta" },
	"decke": { "name": "Wolldecke", "kat": "deko", "w": 1, "d": 1, "h": 0.14, "ebene": "klein", "varianten": STOFFE, "std": "graphit" },
	"poster": { "name": "Poster", "kat": "deko", "w": 2, "d": 1, "h": 0.9, "ebene": "wand", "varianten": MOTIVE, "std": "wellen" },
	"snackschale": { "name": "Snackschale", "kat": "deko", "w": 1, "d": 1, "h": 0.1, "ebene": "klein",
		"varianten": [["chips", "Chips"], ["obst", "Obst"], ["suess", "Süßes"]], "std": "chips" },
	"figuren": { "name": "Figurenreihe", "kat": "deko", "w": 1, "d": 1, "h": 0.16, "ebene": "klein",
		"varianten": [["bunt", "Bunt"], ["pastell", "Pastell"], ["gold", "Gold"]], "std": "bunt" },
	# Weitere eigene Möbel (moebel_mehr.gd).
	"ohrensessel": { "name": "Ohrensessel", "kat": "sitzen", "w": 2, "d": 2, "h": 1.12, "ebene": "boden", "varianten": STOFFE, "std": "salbei",
		"nutzen": "sitzen", "beine": true, "gestell": "Beine" },
	"schlafsofa": { "name": "Schlafsofa", "kat": "sitzen", "w": 4, "d": 2, "h": 0.88, "ebene": "boden", "varianten": STOFFE, "std": "creme",
		"nutzen": "sitzen", "beine": true, "gestell": "Rahmen" },
	"bett": { "name": "Bett", "kat": "sitzen", "w": 3, "d": 5, "h": 1.03, "ebene": "boden", "varianten": STOFFE, "std": "salbei", "nutzen": "sitzen",
		"stufen": BETT_STUFEN, "stufe": 1, "beine": true, "gestell": "Bettgestell" },
	"pouf": { "name": "Pouf", "kat": "sitzen", "w": 1, "d": 1, "h": 0.4, "ebene": "boden", "varianten": STOFFE, "std": "senf", "nutzen": "sitzen",
		"flaeche": 0.4 },
	"couchtisch_rund": { "name": "Runder Couchtisch", "kat": "tische", "w": 2, "d": 2, "h": 0.42, "ebene": "boden", "varianten": HOELZER, "std": "walnuss",
		"flaeche": 0.42, "stufen": [{ "w": 2, "d": 2, "name": "Klein" }, { "w": 3, "d": 3, "name": "Groß" }], "stufe": 0, "beine": true, "gestell": "Beine" },
	"satztisch": { "name": "Satztische", "kat": "tische", "w": 1, "d": 1, "h": 0.5, "ebene": "boden", "varianten": HOELZER, "std": "eiche", "flaeche": 0.5,
		"gestell": "Gestell" },
	"gamingtisch": { "name": "Gaming-Schreibtisch", "kat": "tische", "w": 3, "d": 2, "h": 0.77, "ebene": "boden",
		"varianten": [["schwarz", "Schwarz"], ["weiss", "Weiß"], ["nacht", "Nachtblau"]], "std": "schwarz", "flaeche": 0.745,
		"stufen": [{ "w": 3, "d": 2, "name": "1,4 Meter" }, { "w": 4, "d": 2, "name": "1,9 Meter" }], "stufe": 0, "gestell": "Gestell" },
	"sideboard": { "name": "Sideboard", "kat": "regale", "w": 3, "d": 1, "h": 0.745, "ebene": "boden", "varianten": HOELZER, "std": "eiche",
		"flaeche": 0.745, "stufen": [{ "w": 3, "d": 1, "name": "1,5 Meter" }, { "w": 4, "d": 1, "name": "2 Meter" }, { "w": 5, "d": 1, "name": "2,5 Meter" }],
		"stufe": 1, "beine": true, "griffe": true, "gestell": "Beine" },
	"wandregal": { "name": "Wandregal", "kat": "regale", "w": 3, "d": 1, "h": 0.65, "ebene": "wand", "varianten": HOELZER, "std": "eiche",
		"stufen": WANDREGAL_STUFEN, "stufe": 1 },
	"leiterregal": { "name": "Leiterregal", "kat": "regale", "w": 2, "d": 1, "h": 1.8, "ebene": "boden", "varianten": HOELZER, "std": "walnuss" },
	"arcade": { "name": "Arcade-Automat", "kat": "technik", "w": 2, "d": 2, "h": 1.8, "ebene": "boden",
		"varianten": [["nacht", "Nachtblau"], ["kirsch", "Kirschrot"], ["mint", "Mint"], ["holz", "Nussbaum"]], "std": "nacht", "gestell": "Kantenband" },
	"bogenlampe": { "name": "Bogenlampe", "kat": "licht", "w": 2, "d": 2, "h": 2.0, "ebene": "boden", "varianten": METALLE, "std": "messing",
		"nutzen": "lampe", "gestell": "Fuß" },
	"deckenfluter": { "name": "Deckenfluter", "kat": "licht", "w": 1, "d": 1, "h": 1.76, "ebene": "boden", "varianten": STOFFE, "std": "creme",
		"nutzen": "lampe", "gestell": "Gestell" },
	"papierlampe": { "name": "Papierleuchte", "kat": "licht", "w": 1, "d": 1, "h": 1.42, "ebene": "boden", "varianten": STOFFE, "std": "creme",
		"nutzen": "lampe", "gestell": "Beine" },
	"lichtervorhang": { "name": "Lichtervorhang", "kat": "licht", "w": 4, "d": 1, "h": 1.3, "ebene": "wand", "varianten": LICHTFARBEN, "std": "warm",
		"nutzen": "lampe", "stufen": LEISTE_STUFEN, "stufe": 1 },
	"girlande": { "name": "Lichtergirlande", "kat": "licht", "w": 4, "d": 1, "h": 0.3, "ebene": "wand", "varianten": LICHTFARBEN, "std": "warm",
		"nutzen": "lampe", "stufen": LEISTE_STUFEN, "stufe": 1 },
	"bogenhanf": { "name": "Bogenhanf", "kat": "pflanzen", "w": 1, "d": 1, "h": 0.95, "ebene": "boden", "varianten": TOPFFARBEN, "std": "weiss",
		"stufen": [{ "w": 1, "d": 1, "name": "Klein", "h": 0.7 }, { "w": 1, "d": 1, "name": "Mittel", "h": 0.95 }, { "w": 1, "d": 1, "name": "Groß", "h": 1.25 }],
		"stufe": 1, "gestell": "Topf" },
	"haengepflanze": { "name": "Hängepflanze", "kat": "pflanzen", "w": 1, "d": 1, "h": 1.0, "ebene": "decke",
		"varianten": [["creme", "Creme"], ["terrakotta", "Terrakotta"], ["salbei", "Salbei"]], "std": "creme" },
	"kraeuter": { "name": "Kräutertöpfe", "kat": "pflanzen", "w": 1, "d": 1, "h": 0.3, "ebene": "klein",
		"varianten": [["terrakotta", "Terrakotta"], ["weiss", "Weiß"]], "std": "terrakotta", "gestell": "Töpfe" },
	"laeufer": { "name": "Läufer", "kat": "deko", "w": 2, "d": 5, "h": 0.02, "ebene": "teppich", "varianten": STOFFE, "std": "terrakotta",
		"stufen": [{ "w": 2, "d": 4, "name": "2 Meter" }, { "w": 2, "d": 5, "name": "2,5 Meter" }, { "w": 2, "d": 7, "name": "3,5 Meter" }], "stufe": 1,
		"gestell": "Rand" },
	"fell": { "name": "Fell", "kat": "deko", "w": 2, "d": 3, "h": 0.03, "ebene": "teppich",
		"varianten": [["weiss", "Naturweiß"], ["grau", "Grau"], ["braun", "Braun"]], "std": "weiss" },
	"bilderwand": { "name": "Bilderwand", "kat": "deko", "w": 4, "d": 1, "h": 0.8, "ebene": "wand", "varianten": MOTIVE, "std": "sonne", "gestell": "Rahmen" },
	"wanduhr_strahlen": { "name": "Strahlenuhr", "kat": "deko", "w": 2, "d": 1, "h": 0.66, "ebene": "wand",
		"varianten": [["messing", "Messing"], ["holz", "Nussbaum"], ["schwarz", "Schwarz"]], "std": "messing" },
	"vorhang": { "name": "Vorhang", "kat": "deko", "w": 4, "d": 1, "h": 2.45, "ebene": "wand", "varianten": STOFFE, "std": "creme",
		"stufen": LEISTE_STUFEN, "stufe": 1, "gestell": "Stange" },
}

## Wo Wandmöbel hängen (Unterkante, Meter über dem Boden).
const WAND_HOEHE := { "bild": 1.25, "wanduhr": 2.02, "lichterkette": 2.25, "led_leiste": 2.6, "neonschild": 1.55, "poster": 1.1,
	"wandlampe": 1.75, "wandregal": 1.2, "lichtervorhang": 2.45, "girlande": 2.25, "bilderwand": 1.1, "wanduhr_strahlen": 1.62, "vorhang": 0.0 }

## Möbel, die es nicht mehr gibt, und was an ihrer Stelle steht (ältere zimmer.json, geteilte Zimmer):
## der Spiegel (eine zweite Ansicht des ganzen Zimmers, pixelig) ist jetzt ein Jackenständer.
const ERSETZT := { "spiegel": "jackenstaender" }

## Eigene Möbel aus dem Baukasten: Kennung → geprüfte Angaben (gestalt.gd, pruefe_eigenes).
static var _eigene := {}


static func has(id: String) -> bool:
	return MOEBEL.has(id) or _eigene.has(id)


static func info(id: String) -> Dictionary:
	if _eigene.has(id):
		return _eigene[id]
	return MOEBEL.get(id, {})


## Eigene Möbel anmelden (aus zimmer.json, schon geprüft): Liste von pruefe_eigenes.
static func eigene_setzen(liste: Array) -> void:
	_eigene.clear()
	for e in liste:
		var d: Dictionary = e
		_eigene[str(d.id)] = { "name": str(d.name), "kat": "eigene", "w": int(d.w), "d": int(d.d), "h": _eigen_hoehe(d.teile),
			"ebene": str(d.ebene), "varianten": [], "std": "", "eigen": d, "nutzen": "lampe" if _eigen_licht(d.teile) else "",
			"flaeche": _eigen_flaeche(d) }


## Die angemeldeten eigenen Möbel als Liste (wie eigene_setzen sie bekam) – zum Zurückstellen nach
## einer Prüfung fremder Daten (zimmer_teilen.gd).
static func eigene_liste() -> Array:
	return _eigene.values().map(func(i: Dictionary) -> Dictionary: return i.eigen)


static func eigen(id: String) -> Dictionary:
	return info(id).get("eigen", {})


static func ist_eigen(id: String) -> bool:
	return _eigene.has(id)


static func _eigen_hoehe(teile: Array) -> float:
	var h := 0.02
	for t in teile:
		h = maxf(h, (float(t.y) + float(t.h)) / 100.0)
	return h


static func _eigen_licht(teile: Array) -> bool:
	for t in teile:
		if str(t.a) in ["schirm", "leuchte"]:
			return true
	return false


## Abstellfläche eines eigenen Möbels (Bodenmöbel): Oberkante der größten waagrechten Platte.
static func _eigen_flaeche(d: Dictionary) -> float:
	if str(d.ebene) != "boden":
		return 0.0
	var best := 0.0
	var oben := 0.0
	for t in d.teile:
		if str(t.a) in ["platte", "kasten"] and float(t.b) * float(t.t) > best:
			best = float(t.b) * float(t.t)
			oben = (float(t.y) + float(t.h)) / 100.0
	return oben if best >= 900.0 else 0.0


static func name_of(id: String) -> String:
	return str(info(id).get("name", id))


## Alle Möbel einer Kategorie in Katalog-Reihenfolge.
static func in_kategorie(kat: String) -> Array:
	var out: Array = []
	if kat == "eigene":
		return _eigene.keys()
	for id in MOEBEL.keys():
		if str(MOEBEL[id].kat) == kat:
			out.append(id)
	return out


static func varianten(id: String) -> Array:
	return info(id).get("varianten", [])


static func variante_gueltig(id: String, v: String) -> bool:
	if ist_eigen(id):
		return v == ""
	for p in varianten(id):
		if str(p[0]) == v:
			return true
	return false


static func variante_name(id: String, v: String) -> String:
	for p in varianten(id):
		if str(p[0]) == v:
			return str(p[1])
	return ""


static func std_variante(id: String) -> String:
	return str(info(id).get("std", ""))


static func ebene(id: String) -> String:
	return str(info(id).get("ebene", "boden"))


static func nutzen(id: String) -> String:
	return str(info(id).get("nutzen", ""))


static func flaeche(id: String) -> float:
	return float(info(id).get("flaeche", 0.0))


## Felder (Breite, Tiefe) nach Drehung r (0..3): bei 1 und 3 liegt das Möbel quer.
static func groesse(id: String, r: int) -> Vector2i:
	var d := info(id)
	var w := int(d.get("w", 1))
	var t := int(d.get("d", 1))
	return Vector2i(t, w) if r % 2 == 1 else Vector2i(w, t)


# --- Größe, Höhe und Fläche je Möbel (mit Stufe) ---------------------------------------------------

static func stufen(id: String) -> Array:
	return info(id).get("stufen", [])


static func std_stufe(id: String) -> int:
	return int(info(id).get("stufe", 0))


## Stufe eines Möbels (aus „s“, sonst Standard), immer gültig.
static func stufe_von(it: Dictionary) -> int:
	var st := stufen(str(it.get("t", "")))
	if st.is_empty():
		return 0
	var s: Variant = it.get("s")
	return clampi(int(s), 0, st.size() - 1) if s is int else std_stufe(str(it.get("t", "")))


static func _stufe_info(it: Dictionary) -> Dictionary:
	var st := stufen(str(it.get("t", "")))
	return st[stufe_von(it)] if not st.is_empty() else {}


## Felder (Breite, Tiefe) eines Möbels samt Stufe und Drehung.
static func groesse_it(it: Dictionary) -> Vector2i:
	var id := str(it.get("t", ""))
	var si := _stufe_info(it)
	var d := info(id)
	var w := int(si.get("w", d.get("w", 1)))
	var t := int(si.get("d", d.get("d", 1)))
	return Vector2i(t, w) if int(it.get("r", 0)) % 2 == 1 else Vector2i(w, t)


static func hoehe_it(it: Dictionary) -> float:
	return float(_stufe_info(it).get("h", info(str(it.get("t", ""))).get("h", 1.0)))


static func flaeche_it(it: Dictionary) -> float:
	var si := _stufe_info(it)
	if si.has("flaeche"):
		return float(si.flaeche)
	if si.has("h") and flaeche(str(it.get("t", ""))) <= 0.0:
		return 0.0
	return flaeche(str(it.get("t", "")))
