extends Node2D
## Grid-snapping overworld player.
##
## Moves one tile at a time in cardinal directions. Each step tweens from
## the current tile to the adjacent tile; input is blocked while moving.
## A target tile is rejected when its TileSet custom data declares
## `is_solid = true` OR a non-empty `gating_item`. Inventory lookup that
## could unlock gated tiles is a future phase — for now any gating_item blocks.

const TILE_SIZE: int = 16
const STEP_DURATION: float = 0.18

const _DIRS: Dictionary = {
	&"ui_up": Vector2i(0, -1),
	&"ui_down": Vector2i(0, 1),
	&"ui_left": Vector2i(-1, 0),
	&"ui_right": Vector2i(1, 0),
}

var _terrain: TileMapLayer
var _moving: bool = false
var _facing: Vector2i = Vector2i(0, 1)


func _ready() -> void:
	position = (Vector2(position) / TILE_SIZE).floor() * TILE_SIZE
	_terrain = _find_terrain_layer()
	if _terrain == null:
		push_error("OverworldPlayer: no TileMapLayer found — collision disabled.")


func _find_terrain_layer() -> TileMapLayer:
	# Walk up the tree looking for the first sibling/uncle TileMapLayer.
	# Avoids relying on a scene-file @export NodePath, which silently fails
	# to resolve to a typed Node reference in some scene-load orderings.
	var node: Node = self
	while node != null:
		for child in node.get_children():
			if child is TileMapLayer:
				return child
		node = node.get_parent()
	return null


func _process(_delta: float) -> void:
	if _moving:
		return
	for action in _DIRS:
		if Input.is_action_pressed(action):
			_try_step(_DIRS[action])
			return


func _try_step(dir: Vector2i) -> void:
	_facing = dir
	var current_cell: Vector2i = Vector2i((Vector2(position) / TILE_SIZE).floor())
	var target_cell: Vector2i = current_cell + dir
	var map: Node = get_tree().get_first_node_in_group(&"overworld_map")
	if map != null and map.has_method(&"try_take_exit"):
		if map.call(&"try_take_exit", target_cell):
			return
	if _is_blocked(target_cell):
		return
	_moving = true
	var target_pos: Vector2 = Vector2(target_cell * TILE_SIZE)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", target_pos, STEP_DURATION)
	tween.finished.connect(_on_step_finished)


func _on_step_finished() -> void:
	_moving = false


func _is_blocked(cell: Vector2i) -> bool:
	if _terrain == null:
		return false
	var source_id: int = _terrain.get_cell_source_id(cell)
	if source_id == -1:
		return true
	var data: TileData = _terrain.get_cell_tile_data(cell)
	if data == null:
		return true
	if data.get_custom_data(&"is_solid"):
		return true
	var gating: StringName = data.get_custom_data(&"gating_item")
	if gating != &"":
		# TODO(inventory): unblock when the player holds `gating`.
		return true
	return false


func place_at_cell(cell: Vector2i) -> void:
	position = Vector2(cell * TILE_SIZE)
	_moving = false


func get_facing() -> Vector2i:
	return _facing
