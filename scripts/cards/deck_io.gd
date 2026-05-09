class_name DeckIO
## Read/write deck models in the user's data folder.
##
## Deck model: Dictionary[card_id (String) -> count (int)].
## On-disk JSON format matches data/decks/*.json:
##   { "cards": [ { "card_id": "...", "count": N }, ... ] }

const USER_DECKS_DIR: String = "user://decks"


static func ensure_user_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_DECKS_DIR):
		DirAccess.make_dir_recursive_absolute(USER_DECKS_DIR)


## Loads a deck file (any res:// or user:// path). Returns an empty model on
## error so callers can continue with a fresh deck.
static func load_model(path: String) -> Dictionary:
	var model: Dictionary = {}
	if not FileAccess.file_exists(path):
		push_warning("DeckIO: file does not exist: %s" % path)
		return model
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return model
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("DeckIO: invalid JSON in %s" % path)
		return model
	var entries: Variant = (parsed as Dictionary).get("cards", null)
	if not (entries is Array):
		return model
	for entry in entries as Array:
		if not (entry is Dictionary):
			continue
		var cid: String = str((entry as Dictionary).get("card_id", ""))
		var cnt: int    = int((entry as Dictionary).get("count", 0))
		if cid.is_empty() or cnt <= 0:
			continue
		model[cid] = int(model.get(cid, 0)) + cnt
	return model


static func save_model(model: Dictionary, path: String) -> Error:
	if path.begins_with("user://"):
		ensure_user_dir()
	var entries: Array = []
	var ids: Array = model.keys()
	ids.sort()
	for cid in ids:
		var cnt: int = int(model[cid])
		if cnt <= 0:
			continue
		entries.append({"card_id": cid, "count": cnt})
	var doc: Dictionary = {"cards": entries}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error("DeckIO: could not open %s for write (err %d)" % [path, err])
		return err
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	return OK


## Lists user-saved decks. Returns Array[{"path", "label"}].
static func list_user_decks() -> Array[Dictionary]:
	ensure_user_dir()
	var result: Array[Dictionary] = []
	var files := DirAccess.get_files_at(USER_DECKS_DIR)
	for fname in files:
		if not fname.ends_with(".json"):
			continue
		var path := "%s/%s" % [USER_DECKS_DIR, fname]
		result.append({
			"path": path,
			"label": fname.trim_suffix(".json").replace("_", " "),
		})
	return result


static func slugify(name: String) -> String:
	var s := name.strip_edges().to_lower()
	var out := ""
	for i in s.length():
		var ch := s.substr(i, 1)
		if ch >= "a" and ch <= "z":
			out += ch
		elif ch >= "0" and ch <= "9":
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	return out if out != "" else "deck"


static func user_path_for_slug(slug: String) -> String:
	return "%s/%s.json" % [USER_DECKS_DIR, slug]
