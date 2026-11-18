extends Node
## Uzais eigener Symbolsatz (Roadmap 98): Linien-Symbole als SVG-Pfade auf einem 24er Raster,
## zur Laufzeit in der passenden Größe gerastert – scharf auf 1080p und 4K. Farbe kommt über modulate.
##
## Regeln für jedes Symbol (Kontaktbogen: tests/probe_klang.gd, Schritt „symbole“):
## - Ein Strich für alle: 2 Einheiten, runde Enden und runde Ecken (STROKE, unten im SVG-Kopf).
##   Kein Symbol setzt eine eigene Strichstärke.
## - Inhalt im Feld 3 … 21, Rahmen mit Ecken 2 (große Flächen) bzw. 1–1,5 (kleine Teile).
## - Punkte: klein als Strich-Punkt („h.01“, Ø 2), groß als gefüllter Kreis r 0,75 (mit Strich Ø 3,5).
## - Gefüllt nur Wiedergabe-Zeichen (Abspielen, Pause, Spulen, Springen), die „_f“-Fassungen und
##   ein Kern (Aufnahme, Bild in Bild) – sonst Linien. Eine „_f“-Fassung hat dieselbe Silhouette wie
##   ihre Linie; Innenteile (Kreuz, Knöpfe, Loch) stanzt eine Maske mit demselben Strich aus.
## - Die Symbole der Leiste oben (Spiele … Einstellungen) haben alle eine „_f“-Fassung; tab_icon()
##   nimmt sie für den gewählten bzw. aktiven Reiter.
## - Keine Logos von Diensten oder Herstellern: „steam“ und „discord“ sind eigene, sachliche Zeichen
##   (aufsteigender Dampf, Sprach-Chat), ebenso die Launcher-Zeichen „store_*“.

const Arbeit := preload("res://src/core/arbeit.gd")

const P := {
	# Leiste oben und alles, was dieselben Begriffe zeigt (eigener Satz, Bogen: tests/probe_leiste.gd):
	# je eine Linien- und eine gefüllte Fassung (_f, Fokus bzw. aktiver Reiter) mit derselben Silhouette.
	"games": '<path d="M8 7.5h8a4.5 4.5 0 0 1 4.35 3.35l.9 3.4a2.6 2.6 0 0 1-4.3 2.55L15.4 15.3H8.6l-1.55 1.5a2.6 2.6 0 0 1-4.3-2.55l.9-3.4A4.5 4.5 0 0 1 8 7.5Z"/><path d="M8 10.3v3.4M6.3 12h3.4M15.6 11.2h.01M17.6 13h.01"/>',
	"games_f": '<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><path d="M8 10.3v3.4M6.3 12h3.4M15.6 11.2h.01M17.6 13h.01" stroke="#000"/></mask><g mask="url(#m)"><path d="M8 7.5h8a4.5 4.5 0 0 1 4.35 3.35l.9 3.4a2.6 2.6 0 0 1-4.3 2.55L15.4 15.3H8.6l-1.55 1.5a2.6 2.6 0 0 1-4.3-2.55l.9-3.4A4.5 4.5 0 0 1 8 7.5Z" fill="#fff"/></g>',
	"shop": '<path d="M5.3 9h13.4l-.8 9.3a2 2 0 0 1-2 1.7H8.1a2 2 0 0 1-2-1.7Z"/><path d="M9 9V7.5a3 3 0 0 1 6 0V9"/>',
	"shop_f": '<path d="M5.3 9h13.4l-.8 9.3a2 2 0 0 1-2 1.7H8.1a2 2 0 0 1-2-1.7Z" fill="#fff"/><path d="M9 9V7.5a3 3 0 0 1 6 0V9"/>',
	"friends": '<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><circle cx="8.8" cy="8.6" r="4.8" fill="#000" stroke="#000"/><path d="M1.8 19.5a7 7 0 0 1 14 0Z" fill="#000" stroke="#000"/></mask><g mask="url(#m)"><circle cx="16.6" cy="9.4" r="2.6"/><path d="M12.6 19.5a4.4 4.4 0 0 1 8.8 0"/></g><circle cx="8.8" cy="8.6" r="3.3"/><path d="M3.3 19.5a5.5 5.5 0 0 1 11 0"/>',
	"friends_f": '<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><circle cx="8.8" cy="8.6" r="4.8" fill="#000" stroke="#000"/><path d="M1.8 19.5a7 7 0 0 1 14 0Z" fill="#000" stroke="#000"/></mask><g mask="url(#m)"><circle cx="16.6" cy="9.4" r="2.6" fill="#fff"/><path d="M12.6 19.5a4.4 4.4 0 0 1 8.8 0Z" fill="#fff"/></g><circle cx="8.8" cy="8.6" r="3.3" fill="#fff"/><path d="M3.3 19.5a5.5 5.5 0 0 1 11 0Z" fill="#fff"/>',
	"user": '<circle cx="12" cy="8.3" r="3.7"/><path d="M5 20a7 7 0 0 1 14 0"/>',
	"user_f": '<circle cx="12" cy="8.3" r="3.7" fill="#fff"/><path d="M5 20a7 7 0 0 1 14 0Z" fill="#fff"/>',
	"music": '<path d="M9 17.5V7.3a1.2 1.2 0 0 1 .95-1.17l8.6-1.85A1.2 1.2 0 0 1 20 5.45V15.5"/><circle cx="6.5" cy="17.5" r="2.5"/><circle cx="17.5" cy="15.5" r="2.5"/>',
	"music_f": '<path d="M9 17.5V7.3a1.2 1.2 0 0 1 .95-1.17l8.6-1.85A1.2 1.2 0 0 1 20 5.45V15.5"/><path d="M9 7.3l11-2.35v3.3L9 10.6Z" fill="#fff"/><circle cx="6.5" cy="17.5" r="2.5" fill="#fff"/><circle cx="17.5" cy="15.5" r="2.5" fill="#fff"/>',
	"video": '<rect x="3" y="5" width="18" height="14" rx="4.5"/><path d="M10.3 9.4v5.2a.6.6 0 0 0 .9.52l4.2-2.6a.6.6 0 0 0 0-1.04l-4.2-2.6a.6.6 0 0 0-.9.52Z" fill="#fff"/>',
	"video_f": '<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><path d="M10.3 9.4v5.2a.6.6 0 0 0 .9.52l4.2-2.6a.6.6 0 0 0 0-1.04l-4.2-2.6a.6.6 0 0 0-.9.52Z" fill="#000" stroke="#000"/></mask><g mask="url(#m)"><rect x="3" y="5" width="18" height="14" rx="4.5" fill="#fff"/></g>',
	"film": '<path d="M4 11h16v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2Z"/><rect x="4" y="6.6" width="16" height="4.4" rx="1.2" transform="rotate(-12 4 11)"/><path d="M9.6 6.8 8 11M14.8 6.8 13.2 11" transform="rotate(-12 4 11)"/>',
	"film_f": '<path d="M4 11h16v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2Z" fill="#fff"/><mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><path d="M9.6 6.4 7.8 11.4M14.8 6.4 13 11.4" transform="rotate(-12 4 11)" stroke="#000"/></mask><g mask="url(#m)"><rect x="4" y="6.6" width="16" height="4.4" rx="1.2" transform="rotate(-12 4 11)" fill="#fff"/></g>',
	"live": '<path d="M8.5 8.5a4.95 4.95 0 0 0 0 7M15.5 8.5a4.95 4.95 0 0 1 0 7M6 6a8.5 8.5 0 0 0 0 12M18 6a8.5 8.5 0 0 1 0 12"/><circle cx="12" cy="12" r="1.2" fill="#fff"/>',
	"live_f": '<path d="M8.5 8.5a4.95 4.95 0 0 0 0 7M15.5 8.5a4.95 4.95 0 0 1 0 7M6 6a8.5 8.5 0 0 0 0 12M18 6a8.5 8.5 0 0 1 0 12"/><circle cx="12" cy="12" r="2" fill="#fff"/>',
	"room": '<path d="M6 12V9a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v3"/><path d="M3 13.5a2 2 0 0 1 4 0V15h10v-1.5a2 2 0 0 1 4 0V18a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18Z"/><path d="M6 19.5v1.3M18 19.5v1.3"/>',
	"room_f": '<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><path d="M1.5 13.5a3.5 3.5 0 0 1 7 0h7a3.5 3.5 0 0 1 7 0V21H1.5Z" fill="#000" stroke="#000"/></mask><g mask="url(#m)"><path d="M6 14V9a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v5Z" fill="#fff"/></g><path d="M3 13.5a2 2 0 0 1 4 0V15h10v-1.5a2 2 0 0 1 4 0V18a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18Z" fill="#fff"/><path d="M6 19.5v1.3M18 19.5v1.3"/>',
	# Browser (Wunschliste 120): eine Kugel mit Meridian und Äquator; gefüllt mit ausgestanzten Linien.
	"browser": '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.4 3.6 5.2 3.6 8.5s-1.2 6.1-3.6 8.5M12 3.5C9.6 5.9 8.4 8.7 8.4 12s1.2 6.1 3.6 8.5"/>',
	"browser_f": '<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><path d="M3.5 12h17M12 3.5c2.4 2.4 3.6 5.2 3.6 8.5s-1.2 6.1-3.6 8.5M12 3.5C9.6 5.9 8.4 8.7 8.4 12s1.2 6.1 3.6 8.5" stroke="#000"/></mask><g mask="url(#m)"><circle cx="12" cy="12" r="8.5" fill="#fff"/></g>',
	"apps": '<rect x="3.75" y="3.75" width="6.5" height="6.5" rx="2"/><rect x="3.75" y="13.75" width="6.5" height="6.5" rx="2"/><rect x="13.75" y="13.75" width="6.5" height="6.5" rx="2"/><circle cx="17" cy="7" r="3.25"/>',
	"apps_f": '<rect x="3.75" y="3.75" width="6.5" height="6.5" rx="2" fill="#fff"/><rect x="3.75" y="13.75" width="6.5" height="6.5" rx="2" fill="#fff"/><rect x="13.75" y="13.75" width="6.5" height="6.5" rx="2" fill="#fff"/><circle cx="17" cy="7" r="3.25" fill="#fff"/>',
	"add": '<rect x="3.5" y="3.5" width="17" height="17" rx="5.5"/><path d="M12 8.5v7M8.5 12h7"/>',
	"add_f": '<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><path d="M12 8.5v7M8.5 12h7" stroke="#000"/></mask><g mask="url(#m)"><rect x="3.5" y="3.5" width="17" height="17" rx="5.5" fill="#fff"/></g>',
	"settings": '<path d="M9.92 5.95L10.13 3.20A9 9 0 0 1 13.87 3.20L14.08 5.95A6.4 6.4 0 0 1 16.20 7.17L18.69 5.98A9 9 0 0 1 20.56 9.22L18.28 10.78A6.4 6.4 0 0 1 18.28 13.22L20.56 14.78A9 9 0 0 1 18.69 18.02L16.20 16.83A6.4 6.4 0 0 1 14.08 18.05L13.87 20.80A9 9 0 0 1 10.13 20.80L9.92 18.05A6.4 6.4 0 0 1 7.80 16.83L5.31 18.02A9 9 0 0 1 3.44 14.78L5.72 13.22A6.4 6.4 0 0 1 5.72 10.78L3.44 9.22A9 9 0 0 1 5.31 5.98L7.80 7.17A6.4 6.4 0 0 1 9.92 5.95Z"/><circle cx="12" cy="12" r="2.6"/>',
	"settings_f": '<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><circle cx="12" cy="12" r="2.6" fill="#000" stroke="none"/></mask><g mask="url(#m)"><path d="M9.92 5.95L10.13 3.20A9 9 0 0 1 13.87 3.20L14.08 5.95A6.4 6.4 0 0 1 16.20 7.17L18.69 5.98A9 9 0 0 1 20.56 9.22L18.28 10.78A6.4 6.4 0 0 1 18.28 13.22L20.56 14.78A9 9 0 0 1 18.69 18.02L16.20 16.83A6.4 6.4 0 0 1 14.08 18.05L13.87 20.80A9 9 0 0 1 10.13 20.80L9.92 18.05A6.4 6.4 0 0 1 7.80 16.83L5.31 18.02A9 9 0 0 1 3.44 14.78L5.72 13.22A6.4 6.4 0 0 1 5.72 10.78L3.44 9.22A9 9 0 0 1 5.31 5.98L7.80 7.17A6.4 6.4 0 0 1 9.92 5.95Z" fill="#fff"/></g>',
	# Weitere Symbole.
	"disc": '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.2"/><path d="M12 6.4a5.6 5.6 0 0 1 5.6 5.6"/>',
	"trophy": '<path d="M8 4h8v5a4 4 0 0 1-8 0V4Z"/><path d="M8 6H5a2.5 2.5 0 0 0 3 4M16 6h3a2.5 2.5 0 0 1-3 4M12 13v3.5M8.5 20h7M9.5 20c0-2 1-3.5 2.5-3.5s2.5 1.5 2.5 3.5"/>',
	"play": '<path d="M8 5.5v13l10.5-6.5L8 5.5Z" fill="#fff"/>',
	"pause": '<rect x="7" y="5.5" width="3" height="13" rx="1" fill="#fff"/><rect x="14" y="5.5" width="3" height="13" rx="1" fill="#fff"/>',
	"prev": '<path d="M18 6.5v11L9.5 12 18 6.5Z" fill="#fff"/><path d="M6.5 6.5v11"/>',
	"next": '<path d="M6 6.5v11l8.5-5.5L6 6.5Z" fill="#fff"/><path d="M17.5 6.5v11"/>',
	"repeat": '<path d="M17 3.5 20 6.5 17 9.5"/><path d="M4 11.5v-1a4 4 0 0 1 4-4h12"/><path d="M7 20.5 4 17.5 7 14.5"/><path d="M20 12.5v1a4 4 0 0 1-4 4H4"/>',
	"shuffle": '<path d="M4 7h3.5c2 0 3 1 4.2 2.6l2.6 4.8C15.5 16 16.5 17 18.5 17H20M4 17h3.5c1.2 0 2-.4 2.7-1.1M14 8.1c.7-.7 1.5-1.1 2.7-1.1H20M18 4.5 20.5 7 18 9.5M18 14.5l2.5 2.5-2.5 2.5"/>',
	"heart": '<path d="M12 19.5s-7-4.3-7-9.4A3.9 3.9 0 0 1 12 8a3.9 3.9 0 0 1 7 2.1c0 5.1-7 9.4-7 9.4Z"/>',
	"heart_f": '<path d="M12 19.5s-7-4.3-7-9.4A3.9 3.9 0 0 1 12 8a3.9 3.9 0 0 1 7 2.1c0 5.1-7 9.4-7 9.4Z" fill="#fff"/>',
	"more": '<circle cx="6" cy="12" r=".75" fill="#fff"/><circle cx="12" cy="12" r=".75" fill="#fff"/><circle cx="18" cy="12" r=".75" fill="#fff"/>',
	"phone": '<path d="M6.5 3.5h3l1.5 4.5-2 1.5a11 11 0 0 0 5.5 5.5l1.5-2 4.5 1.5v3a2 2 0 0 1-2 2A16.5 16.5 0 0 1 4.5 5.5a2 2 0 0 1 2-2z"/>',
	"phone_off": '<path d="M6.5 3.5h3l1.5 4.5-2 1.5a11 11 0 0 0 5.5 5.5l1.5-2 4.5 1.5v3a2 2 0 0 1-2 2A16.5 16.5 0 0 1 4.5 5.5a2 2 0 0 1 2-2z"/><path d="M4 4l16 16"/>',
	"headset": '<path d="M4 14v-2a8 8 0 0 1 16 0v2"/><rect x="3.5" y="13" width="4" height="6.5" rx="1.5"/><rect x="16.5" y="13" width="4" height="6.5" rx="1.5"/>',
	"mic_off": '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5M4 4l16 16"/>',
	"headset_off": '<path d="M4 14v-2a8 8 0 0 1 13.6-5.7M20 12v2"/><rect x="3.5" y="13" width="4" height="6.5" rx="1.5"/><rect x="16.5" y="13" width="4" height="6.5" rx="1.5"/><path d="M3.5 3.5l17 17"/>',
	"leave": '<path d="M14 4h4.5A1.5 1.5 0 0 1 20 5.5v13a1.5 1.5 0 0 1-1.5 1.5H14"/><path d="M10 8l-4 4 4 4M6 12h9"/>',
	"join": '<path d="M10 4H5.5A1.5 1.5 0 0 0 4 5.5v13A1.5 1.5 0 0 0 5.5 20H10"/><path d="M14 8l4 4-4 4M18 12H9"/>',
	"mic": '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
	"tv": '<rect x="3.5" y="4.5" width="17" height="12.5" rx="2"/><path d="M6.5 8.5h11M6.5 11.5h11M6.5 14h7M9 20.5h6"/>',
	"chip": '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3"/>',
	"memory": '<rect x="3.5" y="7" width="17" height="10" rx="2"/><path d="M7.5 10v4M11 10v4M14.5 10v4M6 17v2.5M10 17v2.5M14 17v2.5M18 17v2.5"/>',
	"thermo": '<path d="M10 14.2V5.5a2 2 0 0 1 4 0v8.7a4 4 0 1 1-4 0Z"/><path d="M12 9.5v6.5"/><circle cx="12" cy="17.2" r=".75" fill="#fff"/>',
	"bell": '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 1.5h-15L6 16.5Z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
	"power": '<path d="M12 3.5v8"/><path d="M7 6.3a7.5 7.5 0 1 0 10 0"/>',
	"grid": '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
	"chat": '<path d="M5 6.5A2.5 2.5 0 0 1 7.5 4h9A2.5 2.5 0 0 1 19 6.5v6a2.5 2.5 0 0 1-2.5 2.5H11l-4 4v-4.2A2.5 2.5 0 0 1 5 12.5Z"/>',
	"close": '<path d="M7 7l10 10M17 7 7 17"/>',
	"check": '<path d="M5 12.5 10 17 19 7.5"/>',
	"keyboard": '<rect x="3" y="6.5" width="18" height="11" rx="2"/><path d="M7 10h.01M10.5 10h.01M14 10h.01M17 10h.01M8 14h8"/>',
	"speaker": '<rect x="6" y="3.5" width="12" height="17" rx="2"/><circle cx="12" cy="14" r="3"/><path d="M12 7.5h.01"/>',
	"camera": '<path d="M4 8.5A1.5 1.5 0 0 1 5.5 7h2l1.5-2h6l1.5 2h2A1.5 1.5 0 0 1 20 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5Z"/><circle cx="12" cy="13" r="3.2"/>',
	"home": '<path d="M4 11 12 4.5 20 11v8a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 19Z"/>',
	"star": '<path d="m12 4 2.4 5 5.4.6-4 3.7 1.1 5.4L12 16l-4.9 2.7 1.1-5.4-4-3.7 5.4-.6L12 4Z"/>',
	"star_f": '<path d="m12 4 2.4 5 5.4.6-4 3.7 1.1 5.4L12 16l-4.9 2.7 1.1-5.4-4-3.7 5.4-.6L12 4Z" fill="#fff"/>',
	"send": '<path d="M4 11.5 20 4l-6.5 16-2.6-6.9Z"/><path d="M10.9 13.1 20 4"/>',
	"link": '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
	"folder": '<path d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2h8a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5Z"/>',
	"file": '<path d="M7 3.5h7l4 4V20a.5.5 0 0 1-.5.5h-10A.5.5 0 0 1 7 20Z"/><path d="M14 3.5V8h4"/>',
	"drive": '<rect x="3.5" y="7" width="17" height="10" rx="2"/><path d="M7 13.5h.01M10 13.5h5"/>',
	"search": '<circle cx="10.5" cy="10.5" r="5.5"/><path d="m15 15 5 5"/>',
	"sort": '<path d="M7 5v14M4 16l3 3 3-3M14 7h6M14 12h4M14 17h2"/>',
	"plus": '<path d="M12 5v14M5 12h14"/>',
	"minus": '<path d="M5 12h14"/>',
	"save": '<path d="M5 4.5h11l3 3V19a.5.5 0 0 1-.5.5h-13A.5.5 0 0 1 5 19Z"/><path d="M8 4.5V9h7V4.5M8 19.5v-5h8v5"/>',
	"load": '<path d="M12 15V4M7.5 8.5 12 4l4.5 4.5M5 14.5V19a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-4.5"/>',
	"volume": '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4Z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>',
	"volume_down": '<path d="M5 9.5h3.5L13 5.5v13l-4.5-4H5Z"/><path d="M16.5 9a4 4 0 0 1 0 6"/>',
	"lock": '<rect x="5.5" y="10.5" width="13" height="9.5" rx="2"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
	"undo": '<path d="M9 14 4.5 9.5 9 5"/><path d="M4.5 9.5H14a5.5 5.5 0 0 1 0 11h-3"/>',
	"refresh": '<path d="M19.5 12a7.5 7.5 0 0 1-13 5.1M4.5 12a7.5 7.5 0 0 1 13-5.1M17.5 3.5v3.6h-3.6M6.5 20.5v-3.6h3.6"/>',
	"eye": '<path d="M3 12s3.3-6 9-6 9 6 9 6-3.3 6-9 6-9-6-9-6Z"/><circle cx="12" cy="12" r="2.5"/>',
	"eye_off": '<path d="M3 12s3.3-6 9-6c1.6 0 3 .5 4.2 1.1M21 12s-1.2 2.2-3.6 3.9M12 18c-5.7 0-9-6-9-6M4 4l16 16"/>',
	"image": '<rect x="3.5" y="5" width="17" height="14" rx="2"/><circle cx="9" cy="10" r="1.7"/><path d="m4 17 5-4.5 3.5 3 3-2.5L20 17"/>',
	"palette": '<path d="M12 3.5a8.5 8.5 0 0 0 0 17c1.2 0 1.7-.8 1.4-1.7-.4-1.2.3-2.3 1.6-2.3h1.7a3.8 3.8 0 0 0 3.8-3.8A9 9 0 0 0 12 3.5Z"/><path d="M7.5 12h.01M10 8h.01M14.5 8h.01"/>',
	"controller": '<path d="M7.5 8h9a4.5 4.5 0 0 1 4.3 5.8l-1 3.4a2.4 2.4 0 0 1-4.1.9L14 16h-4l-1.7 2.1a2.4 2.4 0 0 1-4.1-.9l-1-3.4A4.5 4.5 0 0 1 7.5 8Z"/><circle cx="8.5" cy="12" r="1.5"/><path d="M15.5 11h.01M17.5 13h.01"/>',
	"monitor": '<rect x="3.5" y="4.5" width="17" height="11.5" rx="2"/><path d="M9 20h6M12 16v4"/>',
	"clock": '<circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 2"/>',
	"chevron_right": '<path d="m10 6 6 6-6 6"/>',
	"chevron_left": '<path d="m14 6-6 6 6 6"/>',
	"info": '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.5h.01"/>',
	"bulb": '<path d="M9.5 18h5M10.5 21h3"/><path d="M12 3a6 6 0 0 0-3.7 10.7c.8.7 1.2 1.4 1.2 2.3v.5h5V16c0-.9.4-1.6 1.2-2.3A6 6 0 0 0 12 3Z"/>',
	"bluetooth": '<path d="M7 7.5 17 16.5 12 21V3l5 4.5L7 16.5"/>',
	"wifi": '<path d="M2.5 9.2a14 14 0 0 1 19 0M5.6 12.6a9.4 9.4 0 0 1 12.8 0M8.7 16a4.8 4.8 0 0 1 6.6 0"/><circle cx="12" cy="19.3" r="1.1" fill="#fff"/>',
	"pulse": '<path d="M3 12.5h4l2.2-5.5 4.6 11 2.2-5.5H21"/>',
	"warning": '<path d="M12 4 21 19.5H3Z"/><path d="M12 10v4.5M12 17.5h.01"/>',
	"trash": '<path d="M5 7h14M10 7V5h4v2M7 7l1 12.5h8L17 7"/>',
	"edit": '<path d="M5 19l1-4L15.5 5.5a2 2 0 0 1 3 3L9 18Z"/><path d="M14 7l3 3"/>',
	"tag": '<path d="M4 4.5h7.5L20 13l-7 7-8.5-8.5Z"/><circle cx="8.5" cy="8.5" r="1.3"/>',
	"desktop": '<rect x="3.5" y="4.5" width="17" height="11.5" rx="2"/><path d="M9 20h6M12 16v4M9 10.5h6M13 8.5l2 2-2 2"/>',
	"moon": '<path d="M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10Z"/>',
	"restart": '<path d="M5 12a7 7 0 1 0 2-5M5 4.5v4h4"/>',
	"download": '<path d="M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19.5h14"/>',
	"steam": '<path d="M7.5 20.5c-2.4-2.2 2.4-3.8 0-6s2.4-3.8 0-6M12 19c-2.4-2.2 2.4-3.8 0-6s2.4-3.8 0-6M16.5 20.5c-2.4-2.2 2.4-3.8 0-6s2.4-3.8 0-6"/>',
	"discord": '<path d="M4.5 7A2.5 2.5 0 0 1 7 4.5h10A2.5 2.5 0 0 1 19.5 7v6.5A2.5 2.5 0 0 1 17 16h-5l-4.5 3.5V16H7a2.5 2.5 0 0 1-2.5-2.5Z"/><path d="M9 9v3M12 8v5M15 9v3"/>',
	"retro": '<rect x="6" y="3.5" width="12" height="17" rx="2"/><rect x="8.5" y="6" width="7" height="5.5" rx="1"/><path d="M9.5 15.5h2M10.5 14.5v2M14.8 15h.01"/>',
	"qr": '<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><path d="M14 14h2.5v2.5H14zM17.5 17.5H20V20h-2.5zM14 19.5h1M19.5 14v1.5"/>',
	"bookmark": '<path d="M7 4.5h10v15.5l-5-3.6-5 3.6Z"/>',
	"bookmark_f": '<path d="M7 4.5h10v15.5l-5-3.6-5 3.6Z" fill="#fff"/>',
	"history": '<path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3M4.5 4.5v3.5H8"/><path d="M12 8v4.5l3 1.8"/>',
	"list": '<path d="M8.5 7h11M8.5 12h11M8.5 17h11M4.8 7h.01M4.8 12h.01M4.8 17h.01"/>',
	"subtitles": '<rect x="3.5" y="5.5" width="17" height="13" rx="2"/><path d="M10.5 10.3a2 2 0 1 0 0 3.4M17 10.3a2 2 0 1 0 0 3.4"/>',
	"speed": '<path d="M4.5 16a7.5 7.5 0 1 1 15 0"/><path d="M12 16l3.5-5"/><circle cx="12" cy="16" r=".75" fill="#fff"/>',
	"skip": '<path d="M5 6.5v11l7-5.5-7-5.5ZM12.5 6.5v11l7-5.5-7-5.5Z" fill="#fff"/>',
	"record": '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4" fill="#fff"/>',
	"bolt": '<path d="M13.5 3 5.5 13.5h6L10.5 21l8-10.5h-6l1-7.5Z"/>',
	"quality": '<rect x="3.5" y="5.5" width="17" height="13" rx="2"/><path d="M7.5 9.5v5M10.5 9.5v5M7.5 12h3M13.5 9.5v5h1.6a2.5 2.5 0 0 0 0-5Z"/>',
	"channel": '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><circle cx="12" cy="10.5" r="2.5"/><path d="M7.5 19.5a4.5 4.5 0 0 1 9 0"/>',
	"spark": '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>',
	"pip": '<rect x="3" y="4.5" width="18" height="15" rx="2"/><rect x="12" y="12" width="6" height="4.5" rx="1" fill="#fff"/>',
	"fullscreen": '<path d="M4 9V5.5A1.5 1.5 0 0 1 5.5 4H9M15 4h3.5A1.5 1.5 0 0 1 20 5.5V9M20 15v3.5a1.5 1.5 0 0 1-1.5 1.5H15M9 20H5.5A1.5 1.5 0 0 1 4 18.5V15"/>',
	"move": '<path d="M12 3v18M3 12h18M9.5 5.5 12 3l2.5 2.5M9.5 18.5 12 21l2.5-2.5M5.5 9.5 3 12l2.5 2.5M18.5 9.5 21 12l-2.5 2.5"/>',
	"rewind": '<path d="M19 6.5v11l-7-5.5 7-5.5ZM11.5 6.5v11l-7-5.5 7-5.5Z" fill="#fff"/>',
	"forward": '<path d="M5 6.5v11l7-5.5-7-5.5ZM12.5 6.5v11l7-5.5-7-5.5Z" fill="#fff"/>',
	# Weitere Launcher (src/library/stores.gd): eigene, neutrale Zeichen – nie die Logos der Anbieter.
	"store_gog": '<circle cx="12" cy="12" r="5"/><ellipse cx="12" cy="12" rx="10" ry="3.4" transform="rotate(-22 12 12)"/>',
	"store_ubisoft": '<path d="M12 3.5 19.5 7.8v8.4L12 20.5 4.5 16.2V7.8Z"/><circle cx="12" cy="12" r="2.6"/>',
	"store_battlenet": '<path d="M12 3.5 19 6v5.5c0 4.3-3 7.6-7 9-4-1.4-7-4.7-7-9V6Z"/><path d="M9.2 9.2l5.6 5.6M14.8 9.2l-5.6 5.6"/>',
	"store_xbox": '<path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h13A1.5 1.5 0 0 1 20 7.5V10a2 2 0 0 0 0 4v2.5a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 16.5V14a2 2 0 0 0 0-4Z"/><path d="M14.5 8v1.5M14.5 11.25v1.5M14.5 14.5V16"/>',
	"store_amazon": '<path d="M4 8 12 4l8 4v8l-8 4-8-4Z"/><path d="M4 8l8 4 8-4M12 12v8"/>',
	"store_itch": '<rect x="4" y="14" width="16" height="6" rx="2"/><path d="M12 14V9.5"/><circle cx="12" cy="6.5" r="2.7"/>',
	"store_riot": '<circle cx="12" cy="12" r="7"/><path d="M12 2.5v5.5M12 16v5.5M2.5 12H8M16 12h5.5"/><circle cx="12" cy="12" r=".75" fill="#fff"/>',
	# Bau-Menü im Zimmer (src/room/bau_inhalt.gd): je Bereich ein eigenes Zeichen – Raum …
	"wand": '<rect x="3.5" y="5" width="17" height="14" rx="2"/><path d="M3.5 9.7h17M3.5 14.3h17M12 5v4.7M8 9.7v4.6M16 9.7v4.6M12 14.3V19"/>',
	"boden": '<path d="M7.5 6.5h9L20.5 19h-17Z"/><path d="M10.5 6.5 9.2 19M13.5 6.5l1.3 12.5M5.6 12.5h12.8"/>',
	"decke": '<path d="M3.5 20V4.5h17V20"/><path d="M3.5 9a4.5 4.5 0 0 0 4.5-4.5M20.5 9A4.5 4.5 0 0 1 16 4.5M3.5 16.5h4M20.5 16.5h-4"/>',
	"fenster": '<rect x="3.5" y="4.5" width="9.5" height="9.5" rx="1.5"/><path d="M8.25 4.5V14M3.5 9.25H13"/><path d="M15.5 20V6a1.5 1.5 0 0 1 1.5-1.5h2A1.5 1.5 0 0 1 20.5 6v14"/><path d="M17.6 12.5h.01"/>',
	"stimmung": '<path d="M3 17.5h18M7.5 20.5h9M7.5 17.5a4.5 4.5 0 0 1 9 0M12 5.5V8M5.6 8.6l1.8 1.8M18.4 8.6l-1.8 1.8M3.5 13.5h2M18.5 13.5h2"/>',
	"raumgroesse": '<path d="M4 9V5.5A1.5 1.5 0 0 1 5.5 4H9M15 4h3.5A1.5 1.5 0 0 1 20 5.5V9M20 15v3.5a1.5 1.5 0 0 1-1.5 1.5H15M9 20H5.5A1.5 1.5 0 0 1 4 18.5V15"/><path d="M9 15l6-6M11.5 9H15v3.5M9 11.5V15h3.5"/>',
	"vorlage": '<rect x="3.5" y="3.5" width="17" height="17" rx="2"/><path d="M13 3.5v6.5h-2.5"/><rect x="6.5" y="14" width="7.5" height="3" rx="1"/><circle cx="17" cy="15.5" r="1.4"/>',
	# … und Möbel nach Zweck.
	"sitzen": '<path d="M6 4 8.2 13.5H18"/><path d="M8.2 13.5 7 20M17 13.5V20M9.3 9.5H16v4"/>',
	"tisch": '<rect x="3" y="7.5" width="18" height="3.5" rx="1"/><path d="M6.5 11v8.5M17.5 11v8.5M6.5 14.5h11"/>',
	"regal": '<rect x="4.5" y="3.5" width="15" height="17" rx="1.5"/><path d="M4.5 9.2h15M4.5 14.8h15M8 5.7v3.5M10.3 6.4v2.8M13.5 11v3.8M15.7 11.8v3M7.5 17v3.5"/>',
	"technik": '<rect x="3" y="4.5" width="12.5" height="9" rx="1.5"/><path d="M9.25 13.5V17M6.5 17.5H12"/><rect x="17.5" y="7.5" width="3.5" height="12" rx="1"/><path d="M19.25 15.5h.01M19.25 10.5h.01"/>',
	"lampe": '<path d="M8.5 3.5h7l2.5 6.5H6Z"/><path d="M12 10v9.5M8.5 20h7"/>',
	"pflanze": '<path d="M7.5 14.5h9l-1.2 6H8.7Z"/><path d="M12 14.5V9"/><path d="M12 11.5C8.5 11.5 6 9.5 6 6c3.5 0 6 2 6 5.5ZM12 9c0-3 2-5 5.5-5 0 3-2 5-5.5 5Z"/>',
	"deko": '<rect x="4" y="8" width="16" height="12" rx="1.5"/><path d="M8.5 8 12 4l3.5 4"/><path d="M7.5 16.5l3-3 2.3 2 1.7-1.5 2 2.5"/><circle cx="12" cy="4" r=".75" fill="#fff"/>',
	"baukasten": '<rect x="3.5" y="12.5" width="7.5" height="7.5" rx="1.5"/><rect x="13" y="12.5" width="7.5" height="7.5" rx="1.5"/><rect x="8.25" y="4" width="7.5" height="7.5" rx="1.5"/>',
	# Wetter (Licht und Stimmung).
	"sonne": '<circle cx="12" cy="12" r="4"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4 7 17M17 7l1.4-1.4"/>',
	"wolke": '<path d="M7.5 18.5a4 4 0 0 1-.4-7.98 5.5 5.5 0 0 1 10.6-1A4.5 4.5 0 0 1 17 18.5Z"/>',
	"regen": '<path d="M7.5 14.5a3.5 3.5 0 0 1-.35-6.98 4.8 4.8 0 0 1 9.3-.9A4 4 0 0 1 16.5 14.5Z"/><path d="M8.5 17.5l-1 2.5M12.5 17.5l-1 2.5M16.5 17.5l-1 2.5"/>',
	"schnee": '<path d="M7.5 14.5a3.5 3.5 0 0 1-.35-6.98 4.8 4.8 0 0 1 9.3-.9A4 4 0 0 1 16.5 14.5Z"/><path d="M8 18h.01M12 17.5h.01M16 18h.01M10 20.5h.01M14 20.5h.01"/>',
	"nebel": '<path d="M4 8h12M7 12h13M4 16h11M9 20h8"/>',
}

## Fassung für den gewählten bzw. aktiven Reiter: gefüllt, wenn es sie gibt.
static func tab_icon(name: String, on: bool) -> String:
	return name + "_f" if on and P.has(name + "_f") else name


## Gemeinsamer Strich aller Symbole.
const STROKE := 2.0

var _cache := {}


## Symbol als Textur für px Bildpunkte (in Oberflächen-Einheiten). Gerastert wird mindestens
## doppelt so fein und so fein, wie das Fenster gerade vergrößert (4K, große Oberfläche): bis 4×.
## Neu gerastert wird im Hintergrund, auf der Spur für Sofortiges (Arbeit.SOFORT): Zurück kommt
## gleich eine leere Textur in der richtigen Größe, das Bild folgt ein, zwei Bilder später. Im
## Aufbau einer Ebene gerastert, kostete der erste Guide gut 12 ms in einem Bild (je Symbol 0,3 ms).
func tex(name: String, px: int = 24) -> Texture2D:
	var scale := clampf(ceilf(_window_scale()), 2.0, 4.0)
	var key := "%s@%d@%d" % [name, px, int(scale)]
	if _cache.has(key):
		return _cache[key]
	var size := float(px) * scale
	var n := maxi(int(size), 1)
	var t := ImageTexture.create_from_image(Image.create(n, n, false, Image.FORMAT_RGBA8))
	_cache[key] = t
	Arbeit.los(_rastern.bind(t, name, size), Arbeit.SOFORT)
	return t


## Im Hintergrund: rastern, das Bild geht im Hauptfaden in die Textur.
func _rastern(t: ImageTexture, name: String, size: float) -> void:
	var img := image(name, size)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_fertig.call_deferred(t, img)


## Gerastertes Symbol in die schon ausgegebene Textur (gleiches Format und Maß: update, sonst neu).
func _fertig(t: ImageTexture, img: Image) -> void:
	if img == null or img.is_empty():
		return
	if img.get_width() == t.get_width() and img.get_height() == t.get_height() and img.get_format() == Image.FORMAT_RGBA8 and not img.has_mipmaps():
		t.update(img)
	else:
		t.set_image(img)


## Das Symbol als Bild mit genau size Bildpunkten Kantenlänge (auch für Proben und Tests).
static func image(name: String, size: float) -> Image:
	var body: String = P.get(name, P["info"])
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [str(STROKE), body]
	var img := Image.new()
	if img.load_svg_from_string(svg, size / 24.0) != OK:
		var n := maxi(int(size), 1)
		img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	return img


func _window_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var s := get_tree().root.get_final_transform().get_scale().x
	return s if s > 0.0 and is_finite(s) else 1.0
