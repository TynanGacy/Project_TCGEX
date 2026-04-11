extends Node
## Debug camera-positioning tool.
##
## Press backtick (`) to toggle adjust mode. All controls are intercepted
## so they don't bleed into the game while the overlay is active.
##
## Controls while active:
##   Arrow keys          – pan X / Z (horizontal plane)
##   Shift + Up / Down   – move Y (camera height)
##   Shift + Left/Right  – yaw (rotate around Y)
##   Comma / Period      – pitch (rotate around X)
##   [ / ]               – decrease / increase FOV
##   P                   – print position, rotation_degrees, and full transform
##   Backtick (`)        – exit adjust mode

signal base_transform_changed(new_transform: Transform3D)

const _STEP:     float = 0.05   ## world-units per keypress
const _ROT_STEP: float = 1.0    ## degrees per keypress
const _FOV_STEP: float = 1.0    ## degrees per keypress

var _active: bool  = false
var _camera: Camera3D
var _label:  Label


func _ready() -> void:
	_camera = get_parent().get_node("Camera3D") as Camera3D

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_label.offset_left   =  10.0
	_label.offset_right  = 800.0
	_label.offset_top    = -52.0
	_label.offset_bottom =  -8.0
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	_label.add_theme_font_size_override("font_size", 13)
	_label.visible = false
	get_parent().get_node("HUD").add_child(_label)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key := event as InputEventKey
	if key.echo:
		return

	# Toggle on backtick regardless of active state.
	if key.keycode == KEY_QUOTELEFT:
		_active = not _active
		_label.visible = _active
		if _active:
			_refresh_label()
		get_viewport().set_input_as_handled()
		return

	if not _active:
		return

	# All keys below are consumed when the overlay is active.
	get_viewport().set_input_as_handled()

	var shift := key.shift_pressed
	var pos   := _camera.position
	var rot   := _camera.rotation_degrees
	var fov   := _camera.fov
	var dirty := true

	match key.keycode:
		KEY_RIGHT:
			if shift: rot.y -= _ROT_STEP
			else:      pos.x += _STEP
		KEY_LEFT:
			if shift: rot.y += _ROT_STEP
			else:      pos.x -= _STEP
		KEY_UP:
			if shift: pos.y += _STEP
			else:      pos.z -= _STEP
		KEY_DOWN:
			if shift: pos.y -= _STEP
			else:      pos.z += _STEP
		KEY_COMMA:
			rot.x -= _ROT_STEP
		KEY_PERIOD:
			rot.x += _ROT_STEP
		KEY_BRACKETLEFT:
			fov = maxf(10.0, fov - _FOV_STEP)
		KEY_BRACKETRIGHT:
			fov = minf(120.0, fov + _FOV_STEP)
		KEY_P:
			_print_transform()
			dirty = false
		_:
			dirty = false

	if dirty:
		_camera.position        = pos
		_camera.rotation_degrees = rot
		_camera.fov             = fov
		_refresh_label()
		base_transform_changed.emit(_camera.transform)


func _print_transform() -> void:
	var pos := _camera.position
	var rot := _camera.rotation_degrees
	print("=== Camera Debug ===")
	print("  position:         ", pos)
	print("  rotation_degrees: ", rot)
	print("  fov:              ", _camera.fov)
	print("  transform:        ", _camera.transform)
	print("  (paste into main.tscn Camera3D node)")


func _refresh_label() -> void:
	var pos := _camera.position
	var rot := _camera.rotation_degrees
	_label.text = (
		"[CAM ADJUST]  ` exit  |  Arrows = pan X/Z  |  Shift+↑↓ = height  |  Shift+←→ = yaw  |  , / . = pitch  |  [ / ] = FOV  |  P = print\n"
		+ "pos (%.3f, %.3f, %.3f)   rot (%.1f°, %.1f°, %.1f°)   fov %.1f" % [
			pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, _camera.fov
		]
	)
