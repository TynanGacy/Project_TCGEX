extends Node3D
## Common base for every overworld map.
##
## A map is a self-contained Node3D subtree dropped into the
## `MapSlot` of `overworld_root.tscn`. By convention each map exposes:
##   - `Terrain/`  — ground meshes + StaticBody3D colliders (collision_layer 3).
##   - `Props/`    — buildings, trees, rocks; instances of reusable scenes.
##   - `Gates/`    — `terrain_gate` instances (Phase 2+, collision_layer 5).
##   - `Exits/`    — `map_exit` instances (Phase 2+, Area3D on layer 6).
##   - Marker3D nodes in the `ow_spawn_points` group, with `name` = spawn id.
##
## The structure is convention, not enforced — the script just exposes
## helpers and a `map_id` so the WorldManager can identify the map.

@export var map_id: StringName = &""


func _ready() -> void:
	if map_id == &"":
		map_id = StringName(name)
