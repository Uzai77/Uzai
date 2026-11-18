extends Container
## Zeigt sein Kind in voller Größe, solange es Platz hat; sonst so weit verkleinert, dass es
## hineinpasst (Breite und Höhe, oben links ausgerichtet). Für Bildhaftes neben Text, etwa die
## Vorschauen in der Erklärung der Einstellungen: Mit großer Oberfläche bleibt die Schrift groß,
## die Vorschau wird kleiner, statt über den Rand oder auf die Tastenleiste zu laufen. Auch für
## Karten fester Höhe (Freunde rechts), deren Inhalt sonst unten abgeschnitten würde.
## Fordert selbst keinen Platz (Mindestgröße 0) – der Platz kommt vom Elternteil.
## Bliebe nur ein Briefmarken-Bild übrig (kleiner als MIN_K), bleibt der Platz lieber leer.

const MIN_K := 0.4


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for ch in get_children():
			if ch is Control:
				_place(ch as Control)


## Wie stark ein Inhalt der Größe need in die Fläche room verkleinert wird (1 = gar nicht).
static func k_for(need: Vector2, room: Vector2) -> float:
	var k := 1.0
	if need.x > room.x and need.x > 0.0:
		k = minf(k, room.x / need.x)
	if need.y > room.y and need.y > 0.0:
		k = minf(k, room.y / need.y)
	return maxf(k, 0.0)


func _place(c: Control) -> void:
	var need := c.get_combined_minimum_size()
	# Noch ohne Größe (vor dem ersten Ordnen): nichts verkleinern und nichts ausblenden.
	var k := k_for(need, size) if size.x > 0.0 and size.y > 0.0 else 1.0
	# Passt es, bekommt das Kind die ganze Fläche (Füller darin wirken wie gewohnt); verkleinert
	# nur seine Mindesthöhe. Die Breite hängt nicht vom Maßstab ab: Umbrechende Zeilen behalten
	# so ihre Höhe, und der Maßstab pendelt nicht zwischen zwei Werten. fit_child_in_rect setzt
	# den Maßstab zurück: erst einpassen, dann verkleinern.
	fit_child_in_rect(c, Rect2(Vector2.ZERO, Vector2(maxf(size.x, need.x), size.y if k >= 1.0 else need.y)))
	c.scale = Vector2(k, k)
	c.modulate.a = 1.0 if k >= MIN_K else 0.0
