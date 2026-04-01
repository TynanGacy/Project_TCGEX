class_name Card
extends Node3D
## A 3D draggable card. Picked via raycast on its StaticBody3D.
## The visible face is rendered into a SubViewport and displayed on a PlaneMesh
## that sits just above the card body.

signal drag_started(card: Card)
signal drag_ended(card: Card)
signal card_dropped(card: Card)

@export var card_name: String = "Card"
## Texture shown on the card face mesh when the card is face-down.
## Falls back to BACK_COLOR if not set.
@export var back_texture: Texture2D = null

## Runtime card data binding
var card_instance: CardInstance = null

## Card dimensions (roughly standard playing card proportions)
const CARD_WIDTH := 0.63
const CARD_HEIGHT := 0.88
const CARD_THICKNESS := 0.01

## Visual settings
const HOVER_LIFT := 0.15
const DRAG_LIFT := 0.3
const TWEEN_SPEED := 0.15
const DRAW_SPEED := 0.5

## Colour shown on the face mesh when the card is face-down (back design).
const BACK_COLOR := Color(0.08, 0.12, 0.40)

## State
var is_dragging := false
var is_hovered := false
var face_down: bool = false:
	set(value):
		face_down = value
		_update_visuals()
var home_position := Vector3.ZERO
var home_rotation := Vector3.ZERO
var hand_index := 0

var _tween: Tween = null
var _face_material: StandardMaterial3D = null
## Holds an instance assigned before _ready() runs (nodes not yet available).
var _pending_instance: CardInstance = null

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var static_body: StaticBody3D = $StaticBody3D
@onready var face_viewport: SubViewport = $FaceViewport
@onready var card_face: CardFace = $FaceViewport/CardFace
@onready var face_mesh: MeshInstance3D = $FaceMesh


func _ready() -> void:
	## Build the face material once and keep a reference to swap textures on.
	_face_material = StandardMaterial3D.new()
	_face_material.albedo_color = BACK_COLOR
	## Disable back-face culling so the face is visible from any angle.
	_face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mesh.set_surface_override_material(0, _face_material)
	## Apply any instance that was set before the node was in the tree.
	if _pending_instance != null:
		set_instance(_pending_instance)
		_pending_instance = null
	else:
		_update_visuals()


func set_instance(inst: CardInstance) -> void:
	## If called before _ready(), stash and apply once nodes are available.
	if not is_node_ready():
		_pending_instance = inst
		card_instance = inst
		if inst and inst.data:
			card_name = inst.data.display_name
		return
	card_instance = inst
	if inst and inst.data:
		card_name = inst.data.display_name
		card_face.setup(inst.data)
		## Trigger exactly one render frame from the SubViewport.
		face_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_visuals()


func get_instance() -> CardInstance:
	return card_instance


func _update_visuals() -> void:
	if not _face_material:
		return
	if face_down or card_instance == null:
		## Show back: texture if assigned, otherwise solid colour.
		_face_material.albedo_texture = back_texture
		_face_material.albedo_color = BACK_COLOR if back_texture == null else Color.WHITE
	else:
		## Show face: use viewport texture, white tint so colours are accurate.
		_face_material.albedo_texture = face_viewport.get_texture()
		_face_material.albedo_color = Color.WHITE


func set_hovered(value: bool) -> void:
	if value == is_hovered or is_dragging:
		return
	is_hovered = value
	if value:
		_on_hover_start()
	else:
		_on_hover_end()


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
	tween.tween_property(self, "rotation", Vector3.ZERO, TWEEN_SPEED)
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
	tween.tween_property(self, "position:y", home_position.y + HOVER_LIFT, TWEEN_SPEED)
	tween.tween_property(self, "rotation", Vector3.ZERO, TWEEN_SPEED)


func _on_hover_end() -> void:
	return_to_home()


func return_to_home() -> void:
	var tween := _new_tween()
	tween.tween_property(self, "position", home_position, TWEEN_SPEED)
	tween.tween_property(self, "rotation", home_rotation, TWEEN_SPEED)


func animate_draw() -> void:
	var tween := _new_tween()
	tween.tween_property(self, "position", home_position, DRAW_SPEED) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", home_rotation, DRAW_SPEED) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func snap_to_home() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	position = home_position
	rotation = home_rotation


func set_home(pos: Vector3, rot: Vector3, index: int) -> void:
	home_position = pos
	home_rotation = rot
	hand_index = index
