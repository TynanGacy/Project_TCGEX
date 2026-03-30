class_name Card
extends Node3D
## A 3D draggable card. Picked via raycast on its StaticBody3D.

signal drag_started(card: Card)
signal drag_ended(card: Card)
signal card_dropped(card: Card)

@export var card_name: String = "Card"
@export var card_art: Texture2D

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

## State
var is_dragging := false
var is_hovered := false
var home_position := Vector3.ZERO
var home_rotation := Vector3.ZERO
var hand_index := 0

var _tween: Tween = null

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var static_body: StaticBody3D = $StaticBody3D
@onready var label_3d: Label3D = $Label3D


func _ready() -> void:
	_update_visuals()


func set_instance(inst: CardInstance) -> void:
	card_instance = inst
	if inst and inst.data:
		card_name = inst.data.display_name
		card_art = inst.data.art
	_update_visuals()


func get_instance() -> CardInstance:
	return card_instance


func _update_visuals() -> void:
	if label_3d:
		label_3d.text = card_name
	if mesh_instance and card_art:
		var mat := mesh_instance.get_active_material(0) as StandardMaterial3D
		if mat:
			mat = mat.duplicate()
			mat.albedo_texture = card_art
			mesh_instance.set_surface_override_material(0, mat)


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
