extends Node
## Single local player profile — coins, collection, and unopened pack inventory.
## Persisted to user://profile.json. Card-game side only; the overworld must not
## reference this autoload (see CLAUDE.md isolation rules).

signal coins_changed(new_value: int)
signal collection_changed(card_id: String, new_count: int)
## Fired for bulk collection mutations (e.g. clear_collection) so listeners can
## perform a single full refresh instead of reacting to N collection_changed
## emissions. Subscribers that already handle collection_changed must ALSO
## handle this signal — collection_changed is NOT emitted for the affected
## cards during a reset to avoid an O(N²) rebuild cascade.
signal collection_reset
signal pack_inventory_changed(pack_id: String, new_count: int)

const SAVE_PATH: String = "user://profile.json"
const SAVE_VERSION: int = 1

var player_name: String = "Player"
var coins: int = 0
var collection: Dictionary = {}       ## card_id -> int copies
var pack_inventory: Dictionary = {}   ## pack_id -> int unopened

var _loaded: bool = false
var _save_queued: bool = false


func _ready() -> void:
	load_profile()


# ---------------------------------------------------------------------------
# Mutators
# ---------------------------------------------------------------------------

func add_coins(n: int) -> void:
	if n == 0:
		return
	coins = max(0, coins + n)
	coins_changed.emit(coins)
	_queue_save()


func spend_coins(n: int) -> bool:
	if n <= 0:
		return true
	if coins < n:
		return false
	coins -= n
	coins_changed.emit(coins)
	_queue_save()
	return true


func add_card(card_id: String, count: int = 1) -> void:
	if card_id.is_empty() or count == 0:
		return
	var current: int = int(collection.get(card_id, 0))
	var next: int = max(0, current + count)
	if next == 0:
		collection.erase(card_id)
	else:
		collection[card_id] = next
	collection_changed.emit(card_id, next)
	_queue_save()


func owned_count(card_id: String) -> int:
	return int(collection.get(card_id, 0))


func grant_pack(pack_id: String, n: int = 1) -> void:
	if pack_id.is_empty() or n == 0:
		return
	var current: int = int(pack_inventory.get(pack_id, 0))
	var next: int = max(0, current + n)
	if next == 0:
		pack_inventory.erase(pack_id)
	else:
		pack_inventory[pack_id] = next
	pack_inventory_changed.emit(pack_id, next)
	_queue_save()


func consume_pack(pack_id: String) -> bool:
	var current: int = int(pack_inventory.get(pack_id, 0))
	if current <= 0:
		return false
	grant_pack(pack_id, -1)
	return true


func pack_count(pack_id: String) -> int:
	return int(pack_inventory.get(pack_id, 0))


func total_unopened_packs() -> int:
	var total: int = 0
	for v in pack_inventory.values():
		total += int(v)
	return total


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func load_profile() -> void:
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	if raw.is_empty():
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("PlayerProfile: corrupt save at %s — starting fresh" % SAVE_PATH)
		return
	var doc: Dictionary = parsed
	player_name = str(doc.get("player_name", player_name))
	coins = int(doc.get("coins", 0))
	collection.clear()
	for k in (doc.get("collection", {}) as Dictionary).keys():
		var v: int = int((doc["collection"] as Dictionary)[k])
		if v > 0:
			collection[str(k)] = v
	pack_inventory.clear()
	for k in (doc.get("pack_inventory", {}) as Dictionary).keys():
		var v: int = int((doc["pack_inventory"] as Dictionary)[k])
		if v > 0:
			pack_inventory[str(k)] = v


func save_profile() -> void:
	var doc: Dictionary = {
		"version": SAVE_VERSION,
		"player_name": player_name,
		"coins": coins,
		"collection": collection,
		"pack_inventory": pack_inventory,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("PlayerProfile: failed to open %s (err %d)" %
			[SAVE_PATH, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()


func clear_collection() -> void:
	## Wipes owned cards (leaves coins and pack inventory intact). Emits the
	## single bulk `collection_reset` signal rather than N collection_changed
	## events — with several hundred owned cards the per-card path triggered
	## an O(N²) UI rebuild cascade that froze the editor.
	if collection.is_empty():
		return
	collection.clear()
	collection_reset.emit()
	_queue_save()


func reset_profile() -> void:
	## Test/debug helper — wipes in-memory state and the save file.
	player_name = "Player"
	coins = 0
	collection.clear()
	pack_inventory.clear()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	coins_changed.emit(coins)


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	call_deferred("_flush_save")


func _flush_save() -> void:
	_save_queued = false
	save_profile()
