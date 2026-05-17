extends Node3D
## Top-level overworld scene.
##
## Holds the player, follow camera, world environment, and a `MapSlot` into
## which the current map is instanced. Registers itself with the
## `OverworldWorldManager` autoload so map transitions can swap children of
## `MapSlot` without poking the scene tree directly.

@export var starting_map: PackedScene
@export var starting_spawn: StringName = &"default"

@onready var _player: CharacterBody3D = $Player
@onready var _camera: Node3D = $FollowCamera
@onready var _map_slot: Node3D = $MapSlot


func _ready() -> void:
	OverworldWorldManager.register_root(_map_slot, _player)
	OverworldWorldManager.map_changed.connect(_on_map_changed)

	# Camera-relative input: tell the player where to read its "forward" from.
	_player.camera_basis_source = _camera
	_camera.target = _player

	if starting_map != null:
		var map: Node3D = starting_map.instantiate()
		_map_slot.add_child(map)
		var spawn: Node3D = _find_spawn(map, starting_spawn)
		if spawn != null:
			_player.global_position = spawn.global_position
		else:
			_player.global_position = Vector3.ZERO

	# Snap camera onto player so we don't see it drift in from the origin.
	_camera.global_position = _player.global_position


func _find_spawn(map: Node3D, spawn_id: StringName) -> Node3D:
	for node in get_tree().get_nodes_in_group(&"ow_spawn_points"):
		if not (node is Node3D):
			continue
		if not map.is_ancestor_of(node):
			continue
		if StringName(node.name) == spawn_id:
			return node
	return null


func _on_map_changed(_map_id: StringName, _spawn_id: StringName) -> void:
	# Snap the camera so the rig doesn't visibly lerp from the previous
	# map's coordinates.
	_camera.global_position = _player.global_position


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ow_back"):
		GameStateManager.return_to_menu()
	elif event.is_action_pressed(&"ow_cheat_grant_all"):
		OverworldInventory.grant_all_seen_gates()
