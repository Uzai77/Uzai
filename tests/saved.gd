extends RefCounted
## Für Tests: was in settings.json steht, mit geöffnetem Tresor (src/core/vault.gd).

const Vault := preload("res://src/core/vault.gd")


## Wert unter key_path so, wie Uzai ihn nach einem Neustart läse ("" wenn er fehlt).
static func secret(key_path: String) -> Variant:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.path("settings.json")))
	for part in key_path.split("."):
		if not (d is Dictionary and d.has(part)):
			return ""
		d = d[part]
	var v: Variant = Vault.open(d, Config._keys())
	return v if v != null else ""
