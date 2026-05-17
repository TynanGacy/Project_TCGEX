class_name PackCatalog
extends RefCounted
## Loads every pack definition under res://data/packs/. Stateless utility —
## not an autoload; callers cache the returned array if they want.

const PACKS_FOLDER: String = "res://data/packs"


static func load_all() -> Array[PackDefinition]:
	var out: Array[PackDefinition] = []
	if not DirAccess.dir_exists_absolute(PACKS_FOLDER):
		push_warning("PackCatalog: folder missing: %s" % PACKS_FOLDER)
		return out
	var files := DirAccess.get_files_at(PACKS_FOLDER)
	var sorted := Array(files)
	sorted.sort()
	for fname in sorted:
		if not String(fname).ends_with(".json"):
			continue
		var pd := PackDefinition.from_path("%s/%s" % [PACKS_FOLDER, fname])
		if pd != null and pd.pack_id != "":
			out.append(pd)
	return out


static func get_by_id(pack_id: String) -> PackDefinition:
	for pd in load_all():
		if pd.pack_id == pack_id:
			return pd
	return null
