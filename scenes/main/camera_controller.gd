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

const _STEP:     float = 0.05  ## world-units per keypress
const _ROT_STEP: float = 1.0   ## degrees per keypress
const _FOV_STEP: float = 1.0   ## degrees per keypress

@export var camera: Camera3D

var _active: bool = false
var _label:  Label


func _ready() -> void:
	## Own CanvasLayer so the label never depends on an external HUD node.
	var canvas := CanvasLayer.new()
	canvas.layer = 128  ## render on top of everything
	add_child(canvas)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_label.offset_left   =  10.0
	_label.offset_right  = 900.0
	_label.offset_top    = -52.0
	_label.offset_bottom =  -8.0
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	_label.add_theme_font_size_override("font_size", 13)
	_label.visible = false
	canvas.add_child(_label)


func _input(event: InputEvent) -> void:
	## Cast first so we never access .pressed on the base InputEvent type.
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	## Toggle on backtick regardless of active state.
	if key.keycode == KEY_QUOTELEFT:
		_active = not _active
		_label.visible = _active
		if _active:
			_refresh_label()
		get_viewport().set_input_as_handled()
		return

	if not _active:
		return

	## All keys below are consumed while the overlay is active.
	get_viewport().set_input_as_handled()

	if camera == null:
		return

	var shift := key.shift_pressed
	var pos   := camera.position
	var rot   := camera.rotation_degrees
	var fov   := camera.fov
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
		camera.position         = pos
		camera.rotation_degrees = rot
		camera.fov              = fov
		_refresh_label()
		base_transform_changed.emit(camera.transform)


func _print_transform() -> void:
	print("=== Camera Debug ===")
	print("  position:         ", camera.position)
	print("  rotation_degrees: ", camera.rotation_degrees)
	print("  fov:              ", camera.fov)
	print("  transform:        ", camera.transform)
	print("  (paste into main.tscn Camera3D node)")


func _refresh_label() -> void:
	var pos := camera.position
	var rot := camera.rotation_degrees
	_label.text = (
		"[CAM ADJUST]  ` exit  |  Arrows = pan X/Z  |  Shift+↑↓ = height  |  Shift+←→ = yaw  |  , / . = pitch  |  [ / ] = FOV  |  P = print\n"
		+ "pos (%.3f, %.3f, %.3f)   rot (%.1f°, %.1f°, %.1f°)   fov %.1f" % [
			pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, camera.fov
		]
	)
