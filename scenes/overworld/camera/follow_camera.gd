extends Node3D
## Fixed-angle 3rd-person follow rig — Colosseum/XD style.
##
## The rig is a Node3D positioned in world space; its child Camera3D sits at
## a fixed offset relative to the rig. Each frame the rig smoothly chases
## the target's planar position. No manual orbit, no pitch control.
##
## To couple to a player, set `target` after both nodes are in the tree.

@export var target: Node3D = null
@export var follow_height: float = 6.5
@export var follow_distance: float = 7.5
@export var look_pitch_degrees: float = -38.0
@export var look_yaw_degrees: float = 0.0
## Higher = snappier. ~5–8 feels GameCube-era; 100 = instant.
@export_range(1.0, 100.0) var smoothing: float = 6.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply_camera_offset()
	if target != null:
		global_position = target.global_position


func _process(delta: float) -> void:
	if target == null:
		return
	var t: float = 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(target.global_position, t)


func _apply_camera_offset() -> void:
	if _camera == null:
		return
	# Position the camera at (yaw, height, distance) relative to the rig,
	# then aim it at the rig origin. `look_pitch_degrees` is informational;
	# the actual pitch is whatever look_at produces for the given height +
	# distance.
	var yaw: float = deg_to_rad(look_yaw_degrees)
	var offset: Vector3 = Vector3(
		sin(yaw) * follow_distance,
		follow_height,
		cos(yaw) * follow_distance,
	)
	_camera.position = offset
	_camera.look_at(global_position, Vector3.UP)
	# look_at sets global rotation; convert to local by clearing rig's
	# rotation contribution. Since the rig has no rotation here, that's a
	# no-op, but keep this code path simple and stable.
