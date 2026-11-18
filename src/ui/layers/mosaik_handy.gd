extends "res://src/ui/layers/modal.gd"
## Bild vom Handy fürs Mosaik: QR-Code zu Uzais kleiner Seite im Heimnetz (Remote.phone_upload_begin,
## dieselbe Seite wie die Handy-Eingabe). Dort sucht man selbst – ein Knopf öffnet auf dem Handy die
## Google-Bildersuche mit dem Namen, Uzai fragt Google nie selbst – und lädt ein Bild hoch.
## Uzai nimmt nur PNG, JPEG oder WebP (nach dem echten Dateikopf) bis 15 MB, dekodiert aus dem
## Puffer und speichert es NEU kodiert im Medienordner (Mosaik.bild_aus_bytes); die Originaldatei,
## ihr Name und Pfad vom Handy werden nie benutzt. Nur im Heimnetz, Einmal-Code, 10 Minuten gültig.

signal fertig(pfad: String)

const QrView := preload("res://src/ui/components/qr_view.gd")
const Mosaik := preload("res://src/library/mosaik.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

var stichwort := ""
var phone_ip := ""          ## nur für Proben: feste Adresse statt der echten im Heimnetz
var _req := ""
var _status: Label


func build() -> void:
	width = 1060.0
	set_meta("uz_hint_b", "Abbrechen")
	super()


## Link für die Bildersuche auf dem Handy (nur ein Link, keine Abfrage durch Uzai).
static func such_link(wort: String) -> String:
	var w := wort.strip_edges().left(120)
	return "https://www.google.com/search?tbm=isch&q=" + w.uri_encode() if w != "" else "https://www.google.com/imghp"


func fill() -> void:
	_req = "mosaik_bild_%d" % Time.get_ticks_msec()
	var url := Remote.phone_upload_begin(_req, "Bild für Uzai", "PNG, JPEG oder WebP, höchstens 15 MB. Gilt 10 Minuten, nur im selben WLAN.",
		such_link(stichwort), "Bilder suchen", "Öffnet die Bildersuche. Bild auf dem Handy speichern, zurück zu diesem Tab, unten wählen.", phone_ip)
	var row := U.hbox(52)
	box.add_child(row)
	if url != "":
		Remote.phone_file.connect(_on_file)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var qr = QrView.new()
		qr.setup(url, 320)
		frame.add_child(qr)
		row.add_child(frame)
	var col := U.vbox(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(U.label("Bild vom Handy", "xl", "text", "black"))
	var t := U.label("Mit der Kamera scannen. Auf dem Handy „Bilder suchen“, ein Bild speichern und hochladen – es erscheint gleich hier." if url != ""
		else "Kein Heimnetz gefunden. Handy und PC müssen im selben WLAN sein.", "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(560, 0)
	col.add_child(t)
	if url != "":
		col.add_child(U.label(url.replace("http://", ""), "m", "accent", "medium"))
	_status = U.label("Wartet auf das Bild …" if url != "" else "", "s", "faint", "regular", true)
	_status.custom_minimum_size = Vector2(560, 0)
	col.add_child(_status)
	var done := U.button("Abbrechen", "close", "flat")
	done.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	done.set_meta("uz_default", true)
	done.set_meta("uz_hint_a", "Schließen")
	done.pressed.connect(close)
	col.add_child(done)


func _on_file(id: String, data: PackedByteArray) -> void:
	if id != _req or not is_inside_tree():
		return
	# Im Hilfsfaden: Ein Foto vom Handy auspacken, prüfen und neu speichern dauert (gemessen 0,16 s bei 12 Megapixel,
	# bei den größten erlaubten Bildern ein Vielfaches) – so lange stünde sonst alles.
	if is_instance_valid(_status):
		_status.text = "Bild wird übernommen …"
	var erg: Variant = await Arbeit.ergebnis(Mosaik.bild_aus_bytes.bind(data, Config.media_dir().path_join("handy")), Arbeit.LANG)
	if id != _req or not is_inside_tree():
		return
	var pfad := str(erg) if erg is String else ""
	if pfad == "":
		if is_instance_valid(_status):
			_status.text = "Wartet auf das Bild …"
		Toasts.show_toast("Bild ließ sich nicht öffnen", "Ein PNG, JPG oder WebP bis 8192 Punkte wählen.", "warning")
		return
	fertig.emit(pfad)
	close()


func _exit_tree() -> void:
	if _req != "":
		Remote.phone_end(_req)
	if Remote.phone_file.is_connected(_on_file):
		Remote.phone_file.disconnect(_on_file)
