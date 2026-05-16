extends Node
## Global singleton for scene transitions and persistent player data.
## Wraps get_tree().change_scene_to_file() and holds cross-scene state stubs.

var player_name: String = ""
var play_time: float = 0.0

## Name of the pending placeholder state — set before transitioning to
## placeholder_state.tscn so it can display the correct label.
var _pending_state_name: String = ""

## Spawn marker name for the next overworld scene load. Consumed once by
## the receiving map's _ready, then cleared. Empty means "use DefaultSpawn".
var _pending_spawn_marker: StringName = &""


func change_state(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func return_to_menu() -> void:
	change_state("res://scenes/main_menu/main_menu.tscn")


func go_to_placeholder(state_name: String) -> void:
	_pending_state_name = state_name
	change_state("res://scenes/placeholder/placeholder_state.tscn")


func get_pending_state_name() -> String:
	return _pending_state_name


func change_overworld_scene(scene_path: String, spawn_marker: StringName) -> void:
	_pending_spawn_marker = spawn_marker
	change_state(scene_path)


func consume_pending_spawn_marker() -> StringName:
	var marker: StringName = _pending_spawn_marker
	_pending_spawn_marker = &""
	return marker
