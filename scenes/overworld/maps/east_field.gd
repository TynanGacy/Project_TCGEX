extends "res://scenes/overworld/maps/map_base.gd"
## Grassy field east of the starting town.
##
## Terrain is hand-painted in the Godot TileMap editor. This script only
## wires the west-edge transition back to `town`. Paint the cells listed
## in `_EXIT_ROWS` on the west border (col 0) as something passable.

const _EXIT_ROWS: Array[int] = [7, 8, 9]


func _ready() -> void:
	for row in _EXIT_ROWS:
		register_exit(Vector2i(0, row), "res://scenes/overworld/maps/town.tscn", &"FromEast")
	super._ready()
