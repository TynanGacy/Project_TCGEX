extends "res://scenes/overworld/maps/map_base.gd"
## Starting town.
##
## Terrain is hand-painted in the Godot TileMap editor — open this scene,
## select the Terrain node, and paint into the dock at the bottom. This
## script only wires up the east-edge transition to `east_field`.
##
## Exit alignment: the cells listed in `_EXIT_ROWS` on the east border
## (col `_MAP_W - 1`) trigger the transition. Paint those cells as
## something passable (e.g. grass or a path tile) so the player can step
## into them.

const _MAP_W: int = 22
const _EXIT_ROWS: Array[int] = [7, 8, 9]


func _ready() -> void:
	for row in _EXIT_ROWS:
		register_exit(Vector2i(_MAP_W - 1, row), "res://scenes/overworld/maps/east_field.tscn", &"FromWest")
	super._ready()
