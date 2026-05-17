extends Node
## Overworld inventory — minimal stub.
##
## Holds key items / gate-unlock tokens. Used by `terrain_gate.gd` to decide
## whether to let the player through. Kept deliberately small: the card-game
## side of the project does not look at this, and this script does not look
## at the card-game side.
##
## Items are referenced by `StringName` (e.g. &"surf", &"strength").

signal item_granted(item: StringName)

var _items: Dictionary = {}


func has(item: StringName) -> bool:
	return _items.has(item)


func grant(item: StringName) -> void:
	if _items.has(item):
		return
	_items[item] = true
	item_granted.emit(item)


func revoke(item: StringName) -> void:
	_items.erase(item)


func clear() -> void:
	_items.clear()


## Dev cheat — grants every item ever requested by a gate during this run.
## Iterates the `ow_gates` group and grants their `required_item`.
func grant_all_seen_gates() -> void:
	for node in get_tree().get_nodes_in_group(&"ow_gates"):
		var req: StringName = node.get("required_item")
		if req != &"":
			grant(req)
