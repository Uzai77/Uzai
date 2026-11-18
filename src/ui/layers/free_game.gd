extends "res://src/ui/layers/modal.gd"
## Ein Gratis-Spiel von Epic (Punkt 110). Holen geht nur beim Anbieter: mit dem Handy über den
## QR-Code (bei Epic angemeldet, „Holen“ tippen – das Spiel gehört dann dir), im Epic Games
## Launcher oder im Browser am PC. Uzai selbst holt und kauft nichts, und es öffnet etwas nur auf
## Knopfdruck. Ohne Umweg weiter: Gehört das Spiel dir, steht hier gleich „Installieren“ (bzw.
## „Spielen“); mit Epic-Konto in Uzai sieht Uzai, solange die Seite offen ist, alle 20 Sekunden in
## deiner Bibliothek nach und bietet „Installieren“ an, sobald du es geholt hast.

const QrView := preload("res://src/ui/components/qr_view.gd")
const ShopPic := preload("res://src/ui/components/shop_pic.gd")
const ShopCard := preload("res://src/ui/components/shop_card.gd")

var item: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var _watching := false


func build() -> void:
	width = 1300.0
	set_meta("uz_hint_b", "Schließen")
	super()


func fill() -> void:
	var url := str(item.get("url", ""))
	if not url.begins_with("https://store.epicgames.com/"):
		return
	var row := U.hbox(52)
	box.add_child(row)
	var left := U.vbox(12)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
	frame.add_child(QrView.new().setup(url, 300))
	left.add_child(frame)
	var cap := U.label("Mit dem Handy holen", "s", "muted", "medium")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(cap)
	row.add_child(left)
	var col := U.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var wide := str(item.get("header", ""))
	if wide != "":
		var clip := Panel.new()
		clip.custom_minimum_size = Vector2(760, 240)
		clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
		clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var pic := ShopPic.new()
		pic.set("box", Vector2(760, 240))
		U.full_rect(pic)
		clip.add_child(pic)
		col.add_child(clip)
		var wp: WeakRef = weakref(pic)
		Media.url_texture_chain([wide], 960, func(t: Texture2D) -> void:
			var p: Control = wp.get_ref()
			if p and t:
				p.set("texture", t)
		)
	var name_l := U.label(str(item.get("name", "")), "xl", "text", "black", true)
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels: nie übersetzen
	col.add_child(name_l)
	var owned := Store.owned_item(item)
	var g := _owned_game() if owned else {}
	var watch: bool = not owned and not bool(item.get("upcoming", false)) and Library.epic_account != null and Library.epic_account.logged_in()
	col.add_child(U.label(("In deiner Bibliothek" if owned else ShopCard.giveaway_when(item)) + "  ·  Epic Games Store", "m", "ok" if owned else "accent", "bold"))
	if str(item.get("desc", "")) != "":
		col.add_child(_text(str(item.desc)))
	if owned:
		col.add_child(_text("In deiner Bibliothek unter Spiele → Epic."))
	elif watch:
		col.add_child(_text("Code scannen, bei Epic anmelden, „Holen“ tippen."))
	elif bool(item.get("upcoming", false)):
		col.add_child(_text("Gratis ab %s." % ShopCard.day_text(int(item.get("from", 0)))))
	else:
		col.add_child(_text("Code scannen, bei Epic anmelden, „Holen“ tippen."))
	var brow := U.hbox(14)
	col.add_child(brow)
	if not g.is_empty() and main != null:
		var installed := Library.is_installed(g)
		var ib := U.button("Spielen" if installed else "Installieren", "play" if installed else "download", "primary")
		ib.set_meta("uz_default", true)
		# Haupthandlung mit Impuls (Spielen bringt ihn schon mit „launch“).
		if not installed:
			ib.set_meta("uz_haupt", true)
		ib.pressed.connect(func() -> void:
			var m := main
			var gg := Library.get_game(str(g.id))
			close()
			if Library.is_installed(gg):
				m.call("launch", gg)
			else:
				m.call("install_epic", gg))
		brow.add_child(ib)
		var later0 := U.button("Schließen", "close")
		later0.pressed.connect(close)
		brow.add_child(later0)
		return
	var slug := str(item.get("slug", ""))
	if Library.launchers.get("epic", false) and Store.slug_ok(slug):
		var lb := U.button("Im Epic Games Launcher", "games", "primary")
		lb.set_meta("uz_default", true)
		lb.pressed.connect(func() -> void:
			OS.shell_open(Store.EPIC_LAUNCHER % slug)
			Toasts.show_toast("Epic Games Launcher", "„Holen“ wählen.", "games", { "ms": 6000 })
		)
		brow.add_child(lb)
	var pc := U.button("Im Browser am PC", "link", "normal" if brow.get_child_count() > 0 else "primary")
	if brow.get_child_count() == 0:
		pc.set_meta("uz_default", true)
	pc.pressed.connect(func() -> void:
		if Config.kid_stop("browser"):
			return
		OS.shell_open(url)
		Toasts.show_toast("Seite bei Epic im Browser", "Anmelden und „Holen“ wählen. Maus im Guide.", "link",
				{ "ms": 6000 })
	)
	brow.add_child(pc)
	var later := U.button("Schließen", "close")
	later.pressed.connect(close)
	brow.add_child(later)
	if watch:
		_watch_claim()


## Spiel aus der Bibliothek zu diesem Angebot (gleicher Namespace), {} wenn keins.
func _owned_game() -> Dictionary:
	var ns := str(item.get("ns", ""))
	for gg in Library.games:
		if ns != "" and gg.get("epic") is Dictionary and str(gg.epic.get("namespace", "")) == ns:
			return gg
	return {}


## Solange die Seite offen ist (höchstens 10 Minuten): in der Bibliothek des Epic-Kontos nachsehen.
## Gehört das Spiel dann dir, baut sich die Seite mit „Installieren“ neu auf.
func _watch_claim() -> void:
	if _watching:
		return
	_watching = true
	for i in 30:
		await get_tree().create_timer(20.0).timeout
		if not is_inside_tree() or _closing:
			return
		await Library.refresh_epic(true)
		if not is_inside_tree() or _closing:
			return
		if Store.owned_item(item):
			Sfx.play("select")
			for c in box.get_children():
				box.remove_child(c)
				c.queue_free()
			fill()
			await get_tree().process_frame
			var d := Nav.default_in(self)
			if d:
				Nav.focus(d, true)
			return

func _text(text: String) -> Label:
	var t := U.label(text, "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(760, 0)
	return t
