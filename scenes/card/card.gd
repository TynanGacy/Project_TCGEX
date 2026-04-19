class_name Card
extends Node3D
## A 3D draggable card face.  Picked via raycast on its StaticBody3D.
##
## In the current bare-bones refactor, Card is used ONLY for off-board
## rendering (cards in hand, deck, discard pile).  Any card that is in play
## as a Pokemon is shown by a PokemonInstance instead — PokemonInstance owns
## its own visual including HP / conditions / attachments.

signal drag_started(card: Card)
signal drag_ended(card: Card)
signal card_dropped(card: Card)

@export var card_name: String = "Card"
@export var back_texture: Texture2D = null

## The CardData shown on this card.  The card face only reads display_name
## and art — no dynamic state lives here.
var data: CardData = null

## Card dimensions (portrait; board mode overrides via set_board_mode).
const CARD_WIDTH     := 0.63
const CARD_HEIGHT    := 0.88
const CARD_THICKNESS := 0.01

const HOVER_LIFT := 0.15
const DRAG_LIFT  := 0.30
const TWEEN_SPEED := 0.15
const DRAW_SPEED  := 0.5

const HAND_BASE_SCALE    := 1.50
const HAND_HOVER_SCALE   := 1.95
const HAND_HOVER_Z_DELTA := -0.75
const HAND_HOVER_LIFT    := 0.50

const BACK_COLOR := Color(0.08, 0.12, 0.40)

## Board mode (landscape art) is used by PokemonInstance's internal Card only.
const BOARD_ART_RATIO := 1.52

const FACE_ROUNDED_SHADER := preload("res://scenes/card/card_face_rounded.gdshader")

## State
var is_dragging := false
var is_hovered  := false
var _is_in_hand := false
var _board_mode := false

var face_down: bool = false:
	set(value):
		face_down = value
		_update_visuals()

var home_position := Vector3.ZERO
var home_rotation := Vector3.ZERO
var hand_index := 0

var _display_width: float = CARD_WIDTH
var _card_w: float = CARD_WIDTH
var _card_h: float = CARD_HEIGHT

var _tween: Tween = null
var _face_material: StandardMaterial3D = null
var _body_material: StandardMaterial3D = null
var _face_shader_material: ShaderMaterial = null
var _pending_data: CardData = null

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var static_body: StaticBody3D     = $StaticBody3D
@onready var face_viewport: SubViewport    = $FaceViewport
@onready var card_face: CardFace           = $FaceViewport/CardFace
@onready var face_mesh: MeshInstance3D     = $FaceMesh
@onready var _collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D


func _ready() -> void:
	_face_material = StandardMaterial3D.new()
	_face_material.albedo_color = BACK_COLOR
	_face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mesh.set_surface_override_material(0, _face_material)

	_face_shader_material = ShaderMaterial.new()
	_face_shader_material.shader = FACE_ROUNDED_SHADER
	_face_shader_material.set_shader_parameter("corner_radius", 0.023)
	_face_shader_material.set_shader_parameter("card_size", Vector2(CARD_WIDTH, CARD_HEIGHT))

	var src := mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	_body_material = src.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _body_material)

	## Duplicate meshes so set_board_mode can resize per-instance.
	face_mesh.mesh = face_mesh.mesh.duplicate()
	mesh_instance.mesh = mesh_instance.mesh.duplicate()
	_collision_shape.shape = _collision_shape.shape.duplicate()
	_resize_meshes(_board_mode)

	if _pending_data != null:
		set_data(_pending_data)
		_pending_data = null
	else:
		_update_visuals()


func set_data(card_data: CardData) -> void:
	if not is_node_ready():
		_pending_data = card_data
		data = card_data
		if card_data != null:
			card_name = card_data.display_name
		return
	data = card_data
	if card_data != null:
		card_name = card_data.display_name
		_refresh_face()
	_update_visuals()


func set_board_mode(on: bool) -> void:
	_board_mode = on
	if is_node_ready():
		_resize_meshes(on)
	if data != null:
		_refresh_face()


func set_display_width(w: float) -> void:
	_display_width = w
	if is_node_ready():
		_resize_meshes(_board_mode)


func _resize_meshes(board: bool) -> void:
	if board:
		_card_w = _display_width
		_card_h = _display_width / BOARD_ART_RATIO
	else:
		_card_w = CARD_WIDTH
		_card_h = CARD_HEIGHT
	if face_mesh == null or mesh_instance == null:
		return
	var plane := face_mesh.mesh as PlaneMesh
	plane.size = Vector2(_card_w, _card_h)
	var box := mesh_instance.mesh as BoxMesh
	box.size = Vector3(_card_w, CARD_THICKNESS, _card_h)
	_face_shader_material.set_shader_parameter("card_size", Vector2(_card_w, _card_h))
	if _collision_shape != null:
		var cshape := _collision_shape.shape as BoxShape3D
		cshape.size = Vector3(_card_w, 0.02, _card_h)


func _refresh_face() -> void:
	if data == null or not is_node_ready() or not is_inside_tree():
		return
	if face_down:
		return
	if _board_mode:
		card_face.setup_board(data)
	else:
		card_face.setup(data)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	face_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_update_visuals()


func _update_visuals() -> void:
	if _face_material == null:
		return
	if face_down or data == null:
		face_mesh.set_surface_override_material(0, _face_material)
		if back_texture != null:
			_face_material.albedo_texture = back_texture
			_face_material.albedo_color = Color.WHITE
			_face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			_face_material.alpha_scissor_threshold = 0.5
			if _body_material != null:
				_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_body_material.albedo_color.a = 0.0
		else:
			_face_material.albedo_texture = null
			_face_material.albedo_color = BACK_COLOR
			_face_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			if _body_material != null:
				_body_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				_body_material.albedo_color.a = 1.0
	else:
		_face_shader_material.set_shader_parameter("face_texture", face_viewport.get_texture())
		face_mesh.set_surface_override_material(0, _face_shader_material)
		if _body_material != null:
			_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_body_material.albedo_color.a = 0.0


## --- Drag / hover -----------------------------------------------------------

func set_hovered(value: bool) -> void:
	if value == is_hovered or is_dragging:
		return
	is_hovered = value
	if value:
		_on_hover_start()
	else:
		return_to_home()


func _new_tween() -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	return _tween


func start_drag() -> void:
	is_dragging = true
	is_hovered = false
	var tween := _new_tween()
	tween.tween_property(self, "position:y", home_position.y + DRAG_LIFT, TWEEN_SPEED)
	tween.tween_property(self, "rotation", Vector3(0, home_rotation.y, home_rotation.z), TWEEN_SPEED)
	if scale != Vector3.ONE:
		tween.tween_property(self, "scale", Vector3.ONE, TWEEN_SPEED)
	drag_started.emit(self)


func end_drag() -> void:
	if not is_dragging:
		return
	is_dragging = false
	card_dropped.emit(self)
	drag_ended.emit(self)


func move_to_drag_position(world_pos: Vector3) -> void:
	global_position = Vector3(world_pos.x, home_position.y + DRAG_LIFT, world_pos.z)


func _on_hover_start() -> void:
	var tween := _new_tween()
	if _is_in_hand:
		tween.tween_property(self, "scale",      Vector3.ONE * HAND_HOVER_SCALE,       TWEEN_SPEED)
		tween.tween_property(self, "position:z", home_position.z + HAND_HOVER_Z_DELTA, TWEEN_SPEED)
		tween.tween_property(self, "position:y", home_position.y + HAND_HOVER_LIFT,    TWEEN_SPEED)
	else:
		tween.tween_property(self, "position:y", home_position.y + HOVER_LIFT, TWEEN_SPEED)
		tween.tween_property(self, "rotation",   Vector3(0, home_rotation.y, home_rotation.z), TWEEN_SPEED)


func return_to_home() -> void:
	var tween := _new_tween()
	tween.tween_property(self, "position", home_position, TWEEN_SPEED)
	tween.tween_property(self, "rotation", home_rotation, TWEEN_SPEED)
	var target_scale := Vector3.ONE * HAND_BASE_SCALE if _is_in_hand else Vector3.ONE
	if scale != target_scale:
		tween.tween_property(self, "scale", target_scale, TWEEN_SPEED)


func set_home(pos: Vector3, rot: Vector3, index: int) -> void:
	home_position = pos
	home_rotation = rot
	hand_index = index


func snap_to_home() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	position = home_position
	rotation = home_rotation
	scale = Vector3.ONE * HAND_BASE_SCALE if _is_in_hand else Vector3.ONE
