extends Node2D
## Base scene for overworld maps.
##
## Each map is an inherited scene that paints its own `Terrain` TileMapLayer
## and places spawn `Marker2D`s under `Entities`. On ready, the player is
## moved to the marker named by `GameStateManager.consume_pending_spawn_marker()`,
## or `DefaultSpawn` if no override is set.
##
## Maps may also register `exits`: a mapping of `Vector2i` cell → `{target:
## String, marker: StringName}`. When the player tries to step onto an exit
## cell, the player calls `try_take_exit` instead of moving.

const _DEFAULT_SPAWN: StringName = &"DefaultSpawn"
const _TILE_SIZE: int = 16

var _exits: Dictionary = {}


func register_exit(cell: Vector2i, target_scene: String, spawn_marker: StringName) -> void:
	_exits[cell] = {"target": target_scene, "marker": spawn_marker}

@onready var _entities: Node2D = $Entities
@onready var _player: Node2D = $Entities/Player


func _ready() -> void:
	add_to_group(&"overworld_map")
	var marker_name: StringName = GameStateManager.consume_pending_spawn_marker()
	if marker_name == &"":
		marker_name = _DEFAULT_SPAWN
	var marker: Marker2D = _entities.get_node_or_null(NodePath(String(marker_name))) as Marker2D
	if marker == null:
		marker = _entities.get_node_or_null(NodePath(String(_DEFAULT_SPAWN))) as Marker2D
	if marker != null and _player.has_method(&"place_at_cell"):
		var cell: Vector2i = Vector2i((marker.position / float(_TILE_SIZE)).floor())
		_player.call(&"place_at_cell", cell)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		GameStateManager.return_to_menu()


func try_take_exit(cell: Vector2i) -> bool:
	var exit: Variant = _exits.get(cell)
	if exit == null:
		return false
	GameStateManager.change_overworld_scene(exit["target"], exit["marker"])
	return true
