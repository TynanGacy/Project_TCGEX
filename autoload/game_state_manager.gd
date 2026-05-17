extends Node
## Global singleton for scene transitions and persistent player data.
## Wraps get_tree().change_scene_to_file() and holds cross-scene state stubs.

var player_name: String = ""
var play_time: float = 0.0

## Name of the pending placeholder state — set before transitioning to
## placeholder_state.tscn so it can display the correct label.
var _pending_state_name: String = ""


func change_state(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func return_to_menu() -> void:
	change_state("res://scenes/main_menu/main_menu.tscn")


func go_to_placeholder(state_name: String) -> void:
	_pending_state_name = state_name
	change_state("res://scenes/placeholder/placeholder_state.tscn")


func get_pending_state_name() -> String:
	return _pending_state_name


## Routes for the user-progression flow (shop, collection, pack opening).
## change_state() is sufficient on its own; these helpers exist to keep call
## sites readable and centralize the scene paths.

func open_shop() -> void:
	change_state("res://scenes/shop/shop.tscn")


func open_collection() -> void:
	change_state("res://scenes/collection/collection.tscn")


## Pending pack id + batch size consumed by the pack-opening scene on enter.
var _pending_pack_id: String = ""
var _pending_pack_count: int = 1


func open_pack(pack_id: String, count: int = 1) -> void:
	_pending_pack_id = pack_id
	_pending_pack_count = max(1, count)
	change_state("res://scenes/pack_opening/pack_opening.tscn")


func consume_pending_pack_request() -> Dictionary:
	var req := {"pack_id": _pending_pack_id, "count": _pending_pack_count}
	_pending_pack_id = ""
	_pending_pack_count = 1
	return req


func open_sell() -> void:
	change_state("res://scenes/sell/sell.tscn")
