extends Node
## Leistung des Nuvio-Abgleichs mit einem großen Konto (5000 Gesehen, 200 Fortschritt, 1000
## Bibliothek, 400 Serien mit je 200 Folgen). Aufruf: godot --headless --path . res://tests/perf_nuvio.tscn
const NS := preload("res://src/core/nuvio_sync.gd")
const MV := preload("res://src/core/movies.gd")

func _ready() -> void:
	var watched: Array = []
	for i in 5000:
		watched.append(
				{ "content_id": "tt%05d" % (i % 400), "content_type": "series", "title": "x", "season": 1 + i % 5, "episode": i % 40,
				"watched_at": 1700000000000 + i * 1000 })
	var prog: Array = []
	for i in 200:
		prog.append(
				{ "content_id": "tt%05d" % i, "content_type": "series", "video_id": "tt%05d:1:%d" % [i, i % 9], "season": 1, "episode": i % 9, "position": 600000,
				"duration": 2400000, "last_watched": 1800000000000 + i })
	var lib: Array = []
	for i in 1000:
		lib.append(
				NS.library_from_remote({ "content_id": "tt%05d" % i, "content_type": "movie", "name": "T %d" % i, "added_at": 1700000000000 + i, "genres": ["Drama"] }))
	var t := Time.get_ticks_usec()
	var remote := NS.progress_from_remote(prog, watched)
	print("progress_from_remote: %d ms" % ((Time.get_ticks_usec() - t) / 1000))
	t = Time.get_ticks_usec()
	var merged := NS.merge_progress({}, remote, 0, false)
	print("merge_progress: %d ms" % ((Time.get_ticks_usec() - t) / 1000))
	t = Time.get_ticks_usec()
	var a := JSON.stringify(merged)
	var b := JSON.stringify(lib)
	print("stringify (Vergleich): %d ms, %d KB" % [(Time.get_ticks_usec() - t) / 1000, (a.length() + b.length()) / 1024])
	var items := {}
	for i in 400:
		var vids: Array = []
		for s in 5:
			for e in 40:
				vids.append({ "id": "tt%05d:%d:%d" % [i, s + 1, e], "season": s + 1, "episode": e, "title": "", "released": "", "thumbnail": "", "available": true })
		items["tt%05d" % i] = { "id": "tt%05d" % i, "type": "series", "name": "S", "videos": vids }
	t = Time.get_ticks_usec()
	var cw := MV.build_continue({ "progress": merged, "items": items, "hidden": {}, "dismissed": [] }, "2026-10-16")
	print("build_continue: %d ms (%d Einträge)" % [(Time.get_ticks_usec() - t) / 1000, cw.size()])
	t = Time.get_ticks_usec()
	var ev: Array = []
	for i in 50:
		ev.append(
				{ "event_id": i + 1, "operation": "upsert", "content_id": "tt%05d" % i, "content_type": "series", "video_id": "tt%05d:1:1" % i, "season": 1, "episode": 1,
				"position": 1000, "duration": 2000000, "last_watched": 1900000000000 })
	var d := NS.apply_progress_delta(merged, ev, [])
	print("apply_progress_delta (50): %d ms" % ((Time.get_ticks_usec() - t) / 1000))
	get_tree().quit()
