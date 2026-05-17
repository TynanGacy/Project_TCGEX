extends CharacterBody3D
## Overworld player — 8-direction grounded movement, no jump.
##
## Camera-relative input: WASD pushes the body along the camera's flattened
## forward / right axes so "up on the stick" is always "away from camera"
## regardless of which way the rig is facing.

@export var walk_speed: float = 4.0
@export var run_speed: float = 7.5
@export var acceleration: float = 18.0
@export var rotation_speed: float = 12.0
@export var gravity: float = 24.0

## Set by `overworld_root.gd` once the camera rig is in the tree so we can
## resolve camera-relative input. Falls back to world axes if unset.
var camera_basis_source: Node3D = null


func _physics_process(delta: float) -> void:
	var input_vec: Vector2 = Vector2(
		Input.get_action_strength(&"ow_move_right") - Input.get_action_strength(&"ow_move_left"),
		Input.get_action_strength(&"ow_move_down") - Input.get_action_strength(&"ow_move_up"),
	)

	var planar: Vector3 = _planar_direction(input_vec)
	var speed: float = run_speed if Input.is_action_pressed(&"ow_run") else walk_speed
	var target_velocity: Vector3 = planar * speed

	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(target_velocity, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = min(velocity.y, 0.0)

	move_and_slide()

	if planar.length_squared() > 0.001:
		var target_yaw: float = atan2(-planar.x, -planar.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)


func _planar_direction(input_vec: Vector2) -> Vector3:
	if input_vec.length_squared() < 0.0001:
		return Vector3.ZERO
	var basis: Basis = Basis.IDENTITY
	if camera_basis_source != null:
		basis = camera_basis_source.global_transform.basis
	var fwd: Vector3 = -basis.z
	var right: Vector3 = basis.x
	fwd.y = 0.0
	right.y = 0.0
	fwd = fwd.normalized()
	right = right.normalized()
	var dir: Vector3 = (fwd * -input_vec.y) + (right * input_vec.x)
	return dir.normalized()
