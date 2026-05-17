extends Area3D
## Map exit trigger — walking into it swaps the current map.
##
## Sits on Layer 6 (`ow_exit_triggers`) and watches for the player's body
## (Layer 2). On overlap, asks `OverworldWorldManager` to deferred-load the
## target map and place the player at the named spawn point.
##
## To avoid an infinite ping-pong if the target map happens to also spawn
## the player inside another exit, exits ignore overlaps for a brief grace
## period after a transition.

@export_file("*.tscn") var target_map: String = ""
@export var target_spawn: StringName = &"default"

const _IGNORE_AFTER_SPAWN_SECONDS: float = 0.5
var _cooldown_until_msec: int = 0


func _ready() -> void:
	add_to_group(&"ow_exits")
	body_entered.connect(_on_body_entered)
	# Grace period covers the case where the player spawns inside an exit
	# from the other side of a paired transition.
	_cooldown_until_msec = Time.get_ticks_msec() + int(_IGNORE_AFTER_SPAWN_SECONDS * 1000.0)


func _on_body_entered(body: Node) -> void:
	if Time.get_ticks_msec() < _cooldown_until_msec:
		return
	if target_map == "":
		push_warning("MapExit at %s has no target_map set" % get_path())
		return
	if not body.is_in_group(&"ow_player"):
		return
	OverworldWorldManager.request_map_change(target_map, target_spawn)
