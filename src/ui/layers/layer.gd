extends Control
## Grundlage für alles, was über der Oberfläche liegt: Seitenleisten, Dialoge, Guide.
## B schließt, die Steuerung bleibt innerhalb der Ebene. Bleibt die Oberfläche dahinter zu
## sehen (Seitenleiste, Dialog), rückt sie beim Öffnen eine Spur zurück – Tiefe statt Deckel.
##
## Takt (docs/DESIGN.md › Bewegung): Fläche vor Schrift. Nennt eine Ebene ihre Fläche (flaeche(),
## Seitenleiste und Dialog), blendet nur die Abdunklung; die Fläche kommt deckend und bewegt ihre
## Lage (_enter_motion), die Schrift darauf folgt NACH_FLAECHE später. So liegt nie durchsichtige
## Schrift über der Seite dahinter. Seiten (Spielseite, Shop-Seite, Film) nennen sich
## selbst als Fläche und ihre Schrift über schrift(): Der deckende Grund kommt in T_WEG, die Schrift
## später in T_ORT. Ohne Fläche blendet die ganze Ebene in T_ORT. Schließen: die Schrift geht
## zuerst (T_ANTWORT), die Ebene blendet in T_WEG mit der Kurve „Gehen“ (ease-out) – der größte
## Schritt kommt am Anfang, nie im letzten Bild; verdeckt sie die Oberfläche (Meta "uz_verdeckt",
## die Oberfläche kommt im selben Bild zurück), mit der Kurve „Kreuzen“.

signal closed

const U := preload("res://src/ui/u.gd")
const ListItem := preload("res://src/ui/components/list_item.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const ProgressBarUz := preload("res://src/ui/components/progress_bar.gd")
const Flug := preload("res://src/ui/flug.gd")

## So weit rückt die Oberfläche hinter einer offenen Ebene zurück.
const DEPTH_SCALE := 0.985
## Abdunklung mit Tiefe: zu den Rändern etwas dichter, zur Fläche der Ebene hin etwas lichter – statt
## eines flachen Grautuchs (nur, wenn die Oberfläche dahinter zu sehen bleibt; nie im leichten Modus).
const SCHLEIER := """shader_type canvas_item;
uniform vec2 mitte = vec2(0.5, 0.45);
void fragment() {
	vec2 d = (UV - mitte) * vec2(1.7, 1.0);
	COLOR.a = clamp(COLOR.a * mix(0.8, 1.16, smoothstep(0.1, 1.0, length(d))), 0.0, 1.0);
}
"""
static var _schleier_shader: Shader

var dim := 0.62
var closable := true
var depth := true             ## Oberfläche dahinter rückt zurück (nur wenn sie zu sehen bleibt)
var _scrim: ColorRect
var _closing := false
var _pushed := false

static var _depth_n := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	U.full_rect(self)


func open(host: Control, first: Control = null) -> void:
	# Die Karte, von der die Ebene aufgeht (geteilte Elemente, flug.gd), und bis die Ebene oben
	# liegt, warten Eingaben (nie an die Karte dahinter, nie verloren).
	var quelle := Flug.quelle()
	Nav.hold_for(self)
	host.add_child(self)
	_scrim = ColorRect.new()
	_scrim.color = Color(UzTheme.col("bg"), dim)
	U.full_rect(_scrim)
	_scrim.set_meta("uz_scrim", true)
	_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and closable:
			close()
	)
	add_child(_scrim)
	move_child(_scrim, 0)
	build()
	_schleier()
	_push_back(host)
	if not has_meta("uz_silent"):
		Sfx.play("open")
	modulate.a = 0.0
	# Fliegt ein Bild herein, blendet der Flug die Ebene passend dazu ein.
	if not Flug.auf(self, quelle):
		_auf()
	await get_tree().process_frame
	await _vor_dem_stapel()
	# Schon wieder geschlossen (im selben Augenblick): nicht mehr auf den Stapel legen.
	if _closing or not is_inside_tree():
		Nav.release_hold(self)
		return
	Nav.push_layer(self, first if first else _first_focus())
	Nav.focus_moved.emit(Nav.focused())


func build() -> void:
	pass


## Zum Überschreiben: Worauf die Ebene noch wartet, bevor sie auf den Stapel kommt und die Auswahl nimmt
## (der Guide: bis die Seite dahinter abgelichtet ist).
func _vor_dem_stapel() -> void:
	pass


## Die Abdunklung bekommt Tiefe (SCHLEIER): lichter dort, wo die Fläche der Ebene steht (Leiste links
## oder rechts, Dialog in der Mitte).
func _schleier() -> void:
	if not is_instance_valid(_scrim) or dim >= 0.9 or dim <= 0.05 or U.Leicht.active:
		return
	if _schleier_shader == null:
		_schleier_shader = Shader.new()
		_schleier_shader.code = SCHLEIER
	var m := ShaderMaterial.new()
	m.shader = _schleier_shader
	var fl := flaeche()
	if fl and is_instance_valid(fl) and fl != self:
		if fl.anchor_left >= 0.99:
			m.set_shader_parameter("mitte", Vector2(0.84, 0.5))
		elif fl.anchor_right <= 0.01:
			m.set_shader_parameter("mitte", Vector2(0.16, 0.5))
	_scrim.material = m


## Ein-Bewegung ohne Flug: Fläche vor Schrift, ohne Fläche blendet die Ebene als Ganzes in T_ORT.
## Ebenen mit eigener Choreografie (Bibliothek) überschreiben das.
func _auf() -> void:
	var fl := flaeche()
	if fl and is_instance_valid(fl):
		_auf_flaeche(fl, U.T_ANTWORT if fl == self else U.NACH_FLAECHE)
	else:
		U.ankommen(self, U.T_ORT, "uz_layer").tween_property(self, "modulate:a", 1.0, U.T_ORT)


## Die deckende Fläche der Ebene (Seitenleiste, Dialog; eine Seite: sie selbst); null: die Ebene
## blendet als Ganzes.
func flaeche() -> Control:
	return null


## Die Schrift auf der Fläche, die nach ihr kommt und vor ihr geht: Standard alles auf der Fläche.
## Seiten (flaeche() == self) nennen hier ihren Inhalt (Bildlauf mit Titel und Knöpfen).
func schrift() -> Array:
	var fl := flaeche()
	if fl == null or not is_instance_valid(fl) or fl == self:
		return []
	return fl.get_children()


## Fläche vor Schrift: Abdunklung blendet ein, die Fläche steht sofort deckend da und bewegt
## sich (_enter_motion der Unterklasse), ihre Schrift kommt verz später in T_ORT. Eine Seite
## (Fläche = die Ebene selbst) kann nicht hereingleiten: Ihr Grund (Bild, Licht) kommt in T_WEG
## (Ankommen), ihr dunkler Boden (die Abdunklung) eine Spur später in T_ORT – so liegt nie halb
## Boden unter halb Bild über der Startseite (übereinander abgedunkelt: ein Loch); die Startseite
## ist schon fast bedeckt, wenn die neue Schrift kommt.
func _auf_flaeche(fl: Control, verz := U.NACH_FLAECHE) -> void:
	var tw := U.ankommen(self, U.T_ORT, "uz_layer").set_parallel(true)
	modulate.a = 1.0
	var seite := fl == self
	var text := schrift()
	if is_instance_valid(_scrim):
		var ziel := _scrim.color
		_scrim.color = Color(ziel, 0.0)
		tw.tween_property(_scrim, "color", ziel, U.T_ORT).set_delay(U.NACH_FLAECHE if seite else 0.0)
	if seite:
		# Der große Titel der Oberfläche darunter weicht zuerst (U.titel_weichen): Er stünde sonst
		# durch den noch halb deckenden Grund unter dem Titel der Seite.
		var sh := _shell_of(get_parent())
		if sh:
			U.titel_weichen(sh)
			set_meta("uz_titel_weg", true)
		for ch in get_children():
			var ci := ch as CanvasItem
			if ci == null or ch == _scrim or ch in text or not ci.visible or ci.modulate.a <= 0.01:
				continue
			var a := ci.modulate.a
			ci.modulate.a = 0.0
			tw.tween_property(ci, "modulate:a", a, U.T_WEG)
	for ch in text:
		if ch is CanvasItem and (ch as CanvasItem).visible:
			(ch as CanvasItem).modulate.a = 0.0
			tw.tween_property(ch, "modulate:a", 1.0, U.T_ORT).set_delay(verz)
	if has_method("_enter_motion"):
		call("_enter_motion", fl)
	# Material „Kernlicht“: die Lichtkante der ankommenden Fläche glänzt einmal auf.
	if not seite:
		U.aufglanz(fl, U.NACH_FLAECHE)


func _first_focus() -> Control:
	return Nav.default_in(self)


func close() -> void:
	if _closing:
		return
	_closing = true
	_release()
	Nav.release_hold(self)
	Nav.pop_layer(self)
	closed.emit()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Das geteilte Bild fliegt zurück an seine Karte (die Auswahl steht schon wieder dort).
	Flug.zu(self)
	# Schrift zuerst, dann die Fläche: nie bleibt Schrift ohne Fläche stehen. Kurve „Gehen“
	# (ease-out): der größte Schritt am Anfang, am Ende läuft es aus statt zu rucken.
	var text := schrift()
	for ch in text:
		if ch is CanvasItem and is_instance_valid(ch):
			U.weg(ch, "uz_schrift").tween_property(ch, "modulate:a", 0.0, U.T_ANTWORT)
	_titel_zurueck(U.T_ANTWORT)
	var tw := U.weg(self, "uz_layer")
	if flaeche() == self:
		# Seite: umgekehrt wie beim Öffnen – der dunkle Boden geht zuerst („Gehen“), Bild und Licht
		# kreuzen mit der Startseite, die darunter wieder zu sehen ist (kein Loch aus halb Boden
		# unter halb Bild).
		tw.set_parallel(true)
		if is_instance_valid(_scrim):
			tw.tween_property(_scrim, "color", Color(_scrim.color, 0.0), U.T_WEG)
		for ch in get_children():
			if ch is CanvasItem and ch != _scrim and not (ch in text) and (ch as CanvasItem).visible:
				U.kreuz_aus(tw, ch as CanvasItem)
	elif has_meta("uz_verdeckt"):
		U.kreuz_aus(tw, self)
	else:
		tw.tween_property(self, "modulate:a", 0.0, U.T_WEG)
	if has_method("_exit_motion"):
		call("_exit_motion", tw)
	await tw.finished
	queue_free()


func nav_command(cmd: String) -> bool:
	if cmd == "b" and closable:
		Sfx.play("back")
		close()
		return true
	return handle(cmd)


func handle(_cmd: String) -> bool:
	return false


func _notification(what: int) -> void:
	# Ohne close() entfernt (Neuaufbau, Spielstart): die Oberfläche trotzdem zurückholen.
	if what == NOTIFICATION_EXIT_TREE:
		_release()
		_titel_zurueck()
		Nav.release_hold(self)


## Die Titel der Oberfläche, die beim Öffnen gewichen sind, kommen zurück (verz ≥ 0: sanft, nachdem
## die Schrift der Seite gegangen ist).
func _titel_zurueck(verz := -1.0) -> void:
	if not has_meta("uz_titel_weg"):
		return
	remove_meta("uz_titel_weg")
	var sh := _shell_of(get_parent())
	if sh:
		U.titel_zurueck(sh, verz)


# --- Tiefe -------------------------------------------------------------------------------

## Die Oberfläche hinter der Ebene rückt zurück, wenn sie sichtbar bleibt (Abdunklung zwischen
## knapp und fast deckend). Mehrere Ebenen übereinander rücken sie nur einmal zurück.
func _push_back(host: Control) -> void:
	if not depth or _pushed or not is_instance_valid(_scrim):
		return
	var a := _scrim.color.a
	if a <= 0.05 or a >= 0.9:
		return
	var shell := _shell_of(host)
	if shell == null or not shell.visible:
		return
	_pushed = true
	_depth_n += 1
	if _depth_n == 1:
		shell.pivot_offset = shell.size * 0.5
		_tiefe(shell, U.wachsen(DEPTH_SCALE))


func _release() -> void:
	if not _pushed:
		return
	_pushed = false
	_depth_n = maxi(0, _depth_n - 1)
	if _depth_n > 0:
		return
	var shell := _shell_of(get_parent())
	if shell and shell.is_inside_tree():
		# Zurück im Antwort-Takt mit der Kurve „Gehen“: Die letzten Pixel fallen, solange die Ebene
		# noch ausblendet (T_WEG) – jedes Pixel bewegt die ganze Oberfläche, allein am Ende wäre es
		# ein Ruck bzw. ein Nachrucken.
		_tiefe(shell, 1.0, U.T_ANTWORT, true)
	elif shell:
		U.stop(shell, "uz_depth")
		shell.scale = Vector2.ONE


## Tiefe in ganzen Pixeln: Der Rand der Oberfläche wandert (bei 1920 px Breite 14 px) mit dem
## Pixel-Schluss (U.px_schluss) und steht auf einem ganzen Pixel – kein einzelnes spätes Pixel,
## wenn sonst alles steht.
static func _tiefe(shell: Control, ziel: float, dauer := U.T_RAUM, gehen := false) -> void:
	var halb := maxf(shell.size.x * 0.5, 1.0)
	var bis := roundf((1.0 - ziel) * halb)
	var rest := (1.0 - shell.scale.x) * halb - bis
	var tw := U.weg(shell, "uz_depth") if gehen else U.ankommen(shell, dauer, "uz_depth")
	U.px_weg(tw, shell, "uz_px_tiefe", rest, dauer, func(p: float) -> void:
		shell.scale = Vector2.ONE * (1.0 - (bis + p) / halb)
	)


## Die Oberfläche (main.shell) zur Ebenenablage; null, wenn es keine gibt.
static func _shell_of(host: Node) -> Control:
	if host == null or not is_instance_valid(host):
		return null
	var m := host.get_parent()
	if m == null or not ("shell" in m):
		return null
	var s: Variant = m.get("shell")
	if s is Control and is_instance_valid(s):
		return s as Control
	return null
