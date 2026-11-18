extends Node
## Disc-Erkennung ohne Laufwerk: Seriennummern normalisieren, SYSTEM.CNF lesen, echte Abbilder
## (ISO, BIN/CUE Mode 2 und Mode 1, M3U; gebaut mit tests/fixtures/make_discs.py), Cache, Abgleich
## mit der Bibliothek und das Ein- und Auslegen. Aufruf: godot --headless --path . res://tests/logic_disc.tscn

const DiscSerial := preload("res://src/library/disc_serial.gd")
const DiscDb := preload("res://src/library/disc_db.gd")
const DAT := """clrmamepro (
	name "Sony - PlayStation 2"
	version "1"
)

game (
	name "Ico (Europe) (En,Fr,De,Es,It)"
	region "Europe"
	serial "SCES-50760"
	rom ( name "Ico (Europe) (En,Fr,De,Es,It).iso" size 1 crc 0 serial "SCES-50760" )
)
game (
	name "Ico (USA)"
	region "USA"
	serial "SCUS-97113"
	rom ( name "Ico (USA).iso" size 1 crc 0 serial "SCUS-97113" )
)
game (
	name "Legend of Dragoon, The (USA) (Disc 1)"
	serial "SCUS-94491"
	rom ( name "Legend of Dragoon, The (USA) (Disc 1).bin" size 1 )
)
game (
	name "Shadow of the Colossus (Europe)"
	serial "SLES-50330"
	rom ( name "x.iso" size 1 )
)
game (
	name "Ico (Europe) (En,Fr,De,Es,It) (Rev 1)"
	serial "SCES-50760"
	rom ( name "Ico (Europe) (En,Fr,De,Es,It) (Rev 1).iso" size 1 )
)
"""

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	# --- Schreibweisen ---
	check(DiscSerial.normalize("SLES_503.30;1") == "SLES-50330", "SLES_503.30;1 → SLES-50330")
	check(DiscSerial.normalize("sles-50330") == "SLES-50330", "klein und mit Strich")
	check(DiscSerial.normalize("SCUS 942.36") == "SCUS-94236", "mit Leerzeichen")
	check(DiscSerial.normalize("SLUS20312") == "SLUS-20312", "ohne Trenner")
	check(DiscSerial.normalize("PSX.EXE") == "" and DiscSerial.normalize("") == "", "keine Nummer → leer")
	check(DiscSerial.from_name("D:/PS2/SLES-50330 Shadow of the Colossus.cue") == "SLES-50330", "Nummer vorn im Dateinamen")
	check(DiscSerial.from_name("D:/PS2/Ico [SCES_507.60].iso") == "SCES-50760", "Nummer in Klammern im Dateinamen")
	check(DiscSerial.from_name("D:/PS2/Gran Turismo 4 (Year 20051).iso") == "", "Jahreszahl im Titel ist keine Nummer")
	check(DiscSerial.from_name("D:/PS2/SPEED 12345.iso") == "", "Wort mit fünf Buchstaben ist keine Nummer")
	check(DiscSerial.from_name("D:/SLES-50330/Spiel.iso") == "", "nur der Dateiname zählt, nicht der Ordner")

	# --- SYSTEM.CNF ---
	var ps2 := DiscSerial.from_cnf("BOOT2 = cdrom0:\\SLES_503.30;1\r\nVER = 1.00\r\nVMODE = PAL\r\n")
	check(ps2.serial == "SLES-50330" and ps2.system == "ps2", "PS2: BOOT2-Zeile")
	var ps1 := DiscSerial.from_cnf("BOOT = cdrom:\\SCES_008.67;1\r\nTCB = 4\r\n")
	check(ps1.serial == "SCES-00867" and ps1.system == "ps1", "PS1: BOOT-Zeile")
	check(DiscSerial.from_cnf("boot2=cdrom0:\\scus_971.13;1").serial == "SCUS-97113", "klein geschrieben, ohne Leerzeichen")
	check(DiscSerial.from_cnf("BOOT = cdrom:SCUS_942.36;1").serial == "SCUS-94236", "PS1 ohne Backslash")
	check(DiscSerial.from_cnf("BOOT = cdrom:\\PSX.EXE;1").serial == "", "PS1 mit PSX.EXE: keine Nummer")
	check(DiscSerial.from_cnf("").serial == "" and DiscSerial.from_cnf("Unsinn\n=\n").serial == "", "leer oder Unsinn")

	# --- Echte Abbilder ---
	var dir := Config.path("disc_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var zr := ZIPReader.new()
	check(zr.open("res://tests/fixtures/discs.zip") == OK, "Testabbilder geöffnet")
	for f in zr.get_files():
		var out := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		out.store_buffer(zr.read_file(f))
		out.close()
	zr.close()
	var p := func(n: String) -> String: return dir.path_join(n)
	check(DiscSerial.of_file(p.call("Shadow of the Colossus (Europe).iso")) == "SLES-50330", "ISO: SYSTEM.CNF gelesen")
	check(DiscSerial.of_file(p.call("Viele Dateien.iso")) == "SLUS-20312", "ISO: Wurzelverzeichnis über mehrere Sektoren")
	check(DiscSerial.of_file(p.call("Final Fantasy VII (Disc 1).cue")) == "SCES-00867", "CUE → BIN (Mode 2, Daten ab Byte 24)")
	check(DiscSerial.of_file(p.call("Final Fantasy VII (Disc 1).bin")) == "SCES-00867", "BIN direkt")
	check(DiscSerial.of_file(p.call("Mode1.cue")) == "SLPS-01123", "CUE → BIN (Mode 1, Daten ab Byte 16)")
	check(DiscSerial.of_file(p.call("Spiel.m3u")) == "SCES-00867", "M3U → erste Disc")
	check(DiscSerial.of_file(p.call("SLUS-20946 Name im Dateinamen.chd")) == "SLUS-20946", "CHD über den Dateinamen")
	check(DiscSerial.of_file(p.call("Ohne CNF.iso")) == "", "ISO ohne SYSTEM.CNF: keine Nummer")
	check(DiscSerial.of_file(p.call("Ohne Nummer.iso")) == "", "PSX.EXE: keine Nummer")
	check(DiscSerial.of_file(p.call("Kaputt.iso")) == "" and DiscSerial.of_file(p.call("fehlt.iso")) == "", "kaputt oder fehlend: keine Nummer, kein Fehler")

	# --- Cache: nur neue oder geänderte Dateien öffnen ---
	var files := ["Shadow of the Colossus (Europe).iso", "Final Fantasy VII (Disc 1).cue", "Kaputt.iso", "fehlt.iso"].map(func(n): return p.call(n))
	var c1: Dictionary = DiscSerial.index(files, {})[0]
	check(c1.size() == 3 and str(c1[files[0]].serial) == "SLES-50330" and str(c1[files[2]].serial) == "", "Cache: drei Dateien (fehlende fällt weg)")
	# Unverändert: der Eintrag bleibt, die Datei wird nicht neu gelesen (falsche Nummer bleibt stehen).
	var fake := c1.duplicate(true)
	fake[files[0]]["serial"] = "TEST-00001"
	var c2: Dictionary = DiscSerial.index(files, fake)[0]
	check(str(c2[files[0]].serial) == "TEST-00001", "unveränderte Datei wird nicht neu gelesen")
	# Geändert (andere Größe): neu gelesen.
	fake[files[0]]["size"] = 1
	var c3: Dictionary = DiscSerial.index(files, fake)[0]
	check(str(c3[files[0]].serial) == "SLES-50330", "geänderte Datei wird neu gelesen")

	# --- Bibliothek: Abgleich, mehrere Discs, M3U ---
	var g1 := { "id": "ps2:sotc", "title": "Shadow of the Colossus", "system": "ps2", "source": "rom", "path": files[0] }
	var g2 := { "id": "ps1:ff7", "title": "Final Fantasy VII", "system": "ps1", "source": "rom", "path": p.call("Spiel.m3u") }
	var g3 := { "id": "ps1:mode1", "title": "Mode 1", "system": "ps1", "source": "rom", "path": p.call("Mode1.cue"), "hidden": true }
	var g4 := { "id": "ps2:ico", "title": "Ico", "system": "ps2", "source": "rom", "path": "/nirgends/Ico (USA).chd" }
	Library.games = [g1, g2, g3, g4]
	Library._reindex()
	var paths: Array = []
	for g in Library.games:
		paths.append_array(DiscSerial.files_of(g))
	check(paths.has(p.call("Final Fantasy VII (Disc 1).cue")), "M3U: ihre Discs zählen mit")
	Library._disc_cache = DiscSerial.index(paths, {})[0]
	Library._rebuild_serials()
	check(str(Library.game_for_serial("SLES_503.30").get("id", "")) == "ps2:sotc", "Disc SLES_503.30 → Shadow of the Colossus")
	check(str(Library.game_for_serial("SCES-00867").get("id", "")) == "ps1:ff7", "Disc aus einer M3U → das Spiel der M3U")
	check(Library.game_for_serial("SLPS-01123").is_empty(), "ausgeblendetes Spiel wird nicht angeboten")
	check(Library.game_for_serial("SLUS-99999").is_empty(), "unbekannte Nummer: kein Spiel")
	check(Library.has_disc_serials() and Library.has_disc_games(), "Abfrage des Laufwerks lohnt sich")

	# --- Redump-Liste: Namen, Abbilder ohne Nummer, andere Region, eigene Zuordnung ---
	var db := DiscDb.parse_dat(DAT)
	check(str(db.serials["SCES-50760"]) == "Ico (Europe) (En,Fr,De,Es,It)" and str(db.files["ico (usa)"]) == "SCUS-97113",
			"Liste: Nummer → Name, Dateiname → Nummer")
	check(not (db.serials as Dictionary).has("") and (db.serials as Dictionary).size() == 4, "Kopf der Liste zählt nicht als Spiel")
	check(str(db.files.get("legend of dragoon, the (usa)", "")) == "SCUS-94491", "mehrere Discs: Name ohne „(Disc 1)“ zählt auch (M3U)")
	check(DiscDb.title_key("Legend of Dragoon, The (USA) (Disc 1)") == DiscDb.title_key("The Legend of Dragoon"), "Titel ohne Region und Artikel vergleichbar")
	check(DiscDb.serial_for_file(db, "D:/PS2/Ico (USA).chd") == "SCUS-97113", ".chd mit Redump-Namen: Nummer über den Namen")
	var st := DiscDb.new_state()
	var tl := DiscDb.to_tsv(db).split("\n")
	DiscDb.feed_tsv(st, tl, 0, tl.size())
	var back := DiscDb.result(st)
	check(back.serials == db.serials and back.files == db.files, "eigener Cache ergibt dieselbe Liste (Nummern und Dateinamen)")
	check(str(db.serials["SCES-50760"]) == "Ico (Europe) (En,Fr,De,Es,It)" and str(back.files.get("ico (europe) (en,fr,de,es,it) (rev 1)", "")) == "SCES-50760",
			"Cache: Revision mit derselben Nummer bleibt erhalten, erster Name gilt")
	var st3 := DiscDb.new_state()
	DiscDb.feed_tsv(st3, tl, 0, 2)
	DiscDb.feed_tsv(st3, tl, 2, tl.size())
	var back3 := DiscDb.result(st3)
	check(back3.serials == db.serials and back3.files == db.files and DiscDb.to_tsv(back3) == DiscDb.to_tsv(db),
			"Cache stückweise gelesen und neu geschrieben: gleich")
	var st2 := DiscDb.new_state()
	var dl := DAT.split("\n")
	DiscDb.feed_dat(st2, dl, 0, 9)
	DiscDb.feed_dat(st2, dl, 9, dl.size())
	check(DiscDb.result(st2).serials == db.serials and DiscDb.result(st2).files == db.files, "stückweise gelesen: gleiches Ergebnis")
	check(Library.game_for_serial("SCUS-97113").is_empty(), "ohne Liste: .chd ohne Nummer nicht gefunden")
	Library.set_disc_db("ps2", db)
	Library.set_disc_db("ps1", DiscDb.parse_dat(""))
	check(str(Library.game_for_serial("SCUS-97113").get("id", "")) == "ps2:ico", "mit Liste: .chd über den Dateinamen gefunden")
	check(str(Library.game_for_serial("SCES-50760", "ps2").get("id", "")) == "ps2:ico", "Disc aus Europa, Abbild aus den USA: gleicher Titel")
	check(Library.disc_name("SCES-50760") == "Ico (Europe) (En,Fr,De,Es,It)" and Library.disc_name("SLUS-99999") == "", "Name der Disc")
	check(str(Library.disc_candidates("SCES-50760", "ps2")[0].id) == "ps2:ico", "Zuordnen: passendster Titel zuerst")
	Library.link_disc("SLUS-99999", "ps2:sotc")
	check(str(Library.game_for_serial("slus_999.99").get("id", "")) == "ps2:sotc" and Library.disc_links_for("ps2:sotc") == ["SLUS-99999"],
			"selbst zugeordnet: gilt und bleibt")
	Library.link_disc("SLUS-99999", "")
	check(Library.game_for_serial("SLUS-99999").is_empty(), "Zuordnung gelöst")
	check(str(Library.game_for_serial("SLES-50330").get("id", "")) == "ps2:sotc", "Nummer aus dem Abbild bleibt vor der Liste")

	# --- Einlegen und Entfernen ---
	var events: Array = []
	Discs.changed.connect(func(on: bool) -> void: events.append(on))
	Discs.apply_drives([{ "drive": "E:\\", "ready": false, "label": "", "cnf": "" }])
	check(Discs.serial == "" and events.is_empty(), "leeres Laufwerk: nichts")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "SOTC", "cnf": "BOOT2 = cdrom0:\\SLES_503.30;1\r\n" }])
	check(Discs.serial == "SLES-50330" and Discs.system == "ps2" and Discs.game_id == "ps2:sotc" and events == [true], "Disc eingelegt: Spiel erkannt")
	check(Discs.is_disc_game(g1) and not Discs.is_disc_game(g2), "nur dieses Spiel gilt als eingelegt")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "SOTC", "cnf": "BOOT2 = cdrom0:\\SLES_503.30;1\r\n" }])
	check(events.size() == 1, "gleiche Disc: keine zweite Meldung")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "MUSIK", "cnf": "" }])
	check(Discs.serial == "SLES-50330" and events == [true], "bereit ohne Nummer (Disc läuft an): Disc bleibt vorerst")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "MUSIK", "cnf": "" }])
	check(Discs.serial == "" and Discs.game().is_empty() and events == [true, false], "Musik-CD statt PS-Disc: beim zweiten Mal Hervorhebung weg")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "X", "cnf": "BOOT = cdrom:\\SLUS_999.99;1" }])
	check(Discs.serial == "SLUS-99999" and Discs.game_id == "", "fremde Disc: erkannt, aber kein Abbild")
	var e := Discs.entry()
	check(str(e.get("source", "")) == "disc" and str(e.id) == "disc:SLUS-99999" and str(e.title) == "PS1-Disc",
			"ohne Abbild: Eintrag für die Startseite (%s)" % str(e.get("title", "")))
	e["images_auto"] = { "cover": "/x.png" }
	check(Discs.entry().get("images_auto", {}).has("cover"), "derselbe Eintrag bei jedem Aufbau (geladene Bilder bleiben)")
	var n_ev := events.size()
	Discs.apply_drives([{ "drive": "E:\\", "ready": false, "label": "", "cnf": "" }])
	check(Discs.serial == "SLUS-99999" and events.size() == n_ev, "Laufwerk kurz nicht bereit: Disc bleibt")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "X", "cnf": "BOOT = cdrom:\\SLUS_999.99;1" }])
	check(Discs.serial == "SLUS-99999" and events.size() == n_ev, "wieder bereit: keine neue Meldung")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "", "cnf": "" }])
	check(Discs.serial == "SLUS-99999" and events.size() == n_ev, "bereit, aber SYSTEM.CNF noch leer: Disc bleibt")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "X", "cnf": "BOOT = cdrom:\\SLUS_999.99;1" }])
	Discs.apply_drives([{ "drive": "E:\\", "ready": false, "label": "", "cnf": "" }])
	check(Discs.serial == "SLUS-99999" and events.size() == n_ev, "Zähler nach erkannter Disc zurückgesetzt: einmal nicht bereit, Disc bleibt")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "X", "cnf": "BOOT = cdrom:\\SLUS_999.99;1" }])
	var n0 := events.size()
	Discs.link("ps1:ff7")
	check(Discs.game_id == "ps1:ff7" and Discs.entry().is_empty() and events.size() == n0 + 1, "Abbild zugeordnet: Disc startet jetzt dieses Spiel")
	Discs.link("")
	check(Discs.game_id == "" and not Discs.entry().is_empty(), "Zuordnung gelöst: wieder ohne Abbild")
	Discs.apply_drives([{ "drive": "E:\\", "ready": true, "label": "ICO", "cnf": "BOOT2 = cdrom0:\\SCES_507.60;1" }])
	check(Discs.game_id == "ps2:ico" and Discs.title() == "Ico" and Discs.disc_name.begins_with("Ico (Europe)"),
			"Disc mit Namen aus der Liste, Abbild aus anderer Region")
	Discs.apply_drives([])
	check(Discs.serial == "" and events.back() == false, "Disc raus")
	var fd: Array = Discs._folder_drive(dir)
	check(fd.size() == 1 and not bool(fd[0].ready), "Ordner ohne SYSTEM.CNF: Laufwerk leer")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
