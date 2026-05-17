extends Node
## Overworld world manager — owns the currently-loaded map and handles
## map-to-map transitions inside the overworld scene.
##
## Sits at the autoload level so `map_exit.gd` can request a transition
## without holding a reference to the root scene. Card-game scripts must
## NOT touch this — see the Isolation Rules section in CLAUDE.md.
##
## Transitions are intra-overworld (swap one map for another inside
## `overworld_root.tscn`). Leaving the overworld entirely is a full scene
## change handled by `GameStateManager`.

signal map_changed(map_id: StringName, spawn_id: StringName)

## Set by `overworld_root.gd` on _ready so this autoload can find the slot
## without a hard scene-path lookup.
var _map_slot: Node3D = null
var _player: Node3D = null

## Pending transition queued during the current frame; consumed by
## overworld_root on the next idle frame.
var _pending_map_path: String = ""
var _pending_spawn_id: StringName = &""


func register_root(map_slot: Node3D, player: Node3D) -> void:
	_map_slot = map_slot
	_player = player


## Called by `map_exit.gd` when the player walks into an exit area.
## Deferred so the trigger Area3D can finish its current signal first.
func request_map_change(map_scene_path: String, spawn_id: StringName) -> void:
	_pending_map_path = map_scene_path
	_pending_spawn_id = spawn_id
	call_deferred("_perform_pending_change")


func _perform_pending_change() -> void:
	if _pending_map_path == "" or _map_slot == null:
		return
	var path: String = _pending_map_path
	var spawn: StringName = _pending_spawn_id
	_pending_map_path = ""
	_pending_spawn_id = &""

	for child in _map_slot.get_children():
		child.queue_free()

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("WorldManager: failed to load map %s" % path)
		return
	var map: Node3D = packed.instantiate()
	_map_slot.add_child(map)

	_place_player_at_spawn(map, spawn)
	var map_id: StringName = StringName(map.name)
	map_changed.emit(map_id, spawn)


func _place_player_at_spawn(map: Node3D, spawn_id: StringName) -> void:
	if _player == null:
		return
	var spawn: Node3D = _find_spawn(map, spawn_id)
	if spawn == null:
		push_warning("WorldManager: spawn '%s' not found, using map origin" % spawn_id)
		_player.global_position = map.global_position
		return
	_player.global_position = spawn.global_position


func _find_spawn(map: Node3D, spawn_id: StringName) -> Node3D:
	for node in map.get_tree().get_nodes_in_group(&"ow_spawn_points"):
		if not (node is Node3D):
			continue
		if not map.is_ancestor_of(node):
			continue
		if StringName(node.name) == spawn_id:
			return node
	return null
