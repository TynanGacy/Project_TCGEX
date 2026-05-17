class_name PackDefinition
extends RefCounted
## A single booster-pack template, loaded from a JSON file in data/packs/.
## Each slot rolls one card from a rarity pool inside the named set; weights
## let us encode long-tail rates (e.g. ~1/36 Rare Secret) with integer math.

var pack_id: String = ""
var display_name: String = ""
var set_code: String = ""
var price_coins: int = 0
## Array of slot dicts: {count:int, rarity_pool:Array[String], weights:Array[int]?}
var slots: Array = []


static func from_path(path: String) -> PackDefinition:
	if not FileAccess.file_exists(path):
		push_warning("PackDefinition: missing %s" % path)
		return null
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("PackDefinition: invalid JSON in %s" % path)
		return null
	return from_dict(parsed)


static func from_dict(doc: Dictionary) -> PackDefinition:
	var pd := PackDefinition.new()
	pd.pack_id = str(doc.get("pack_id", ""))
	pd.display_name = str(doc.get("display_name", pd.pack_id))
	pd.set_code = str(doc.get("set_code", ""))
	pd.price_coins = int(doc.get("price_coins", 0))
	var raw_slots: Variant = doc.get("slots", [])
	if not (raw_slots is Array):
		return pd
	for s in raw_slots as Array:
		if not (s is Dictionary):
			continue
		var sd: Dictionary = s
		var pool_raw: Variant = sd.get("rarity_pool", [])
		if not (pool_raw is Array) or (pool_raw as Array).is_empty():
			continue
		var pool: Array[String] = []
		for r in pool_raw as Array:
			pool.append(str(r))
		var weights_raw: Variant = sd.get("weights", null)
		var weights: Array[int] = []
		if weights_raw is Array:
			for w in weights_raw as Array:
				weights.append(int(w))
		pd.slots.append({
			"count": max(1, int(sd.get("count", 1))),
			"rarity_pool": pool,
			"weights": weights,
		})
	return pd


func total_card_count() -> int:
	var n: int = 0
	for s in slots:
		n += int((s as Dictionary).get("count", 0))
	return n
