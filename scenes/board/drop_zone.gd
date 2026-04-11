class_name DropZone
extends Node3D
## A 3D zone on the table where cards can be dropped.

signal card_received(card: Card)

@export var zone_name: String = "Zone"
@export var zone_color: Color = Color(0.2, 0.4, 0.2, 0.5)
@export var highlight_color: Color = Color(0.3, 0.7, 0.3, 0.7)
@export var max_cards: int = 1
## When true, cards placed here switch to board-display mode (landscape art + nameplate).
## Enable only for Active and Bench zones; leave false for Deck, Prize, Discard.
@export var use_board_display: bool = false

## Extra Y rotation (radians) applied to every card placed here.
## Set to PI when the viewer's perspective is flipped 180°.
var perspective_y_rotation: float = 0.0

const ZONE_WIDTH          := 0.66
const BOARD_ZONE_HEIGHT   := 0.44   ## landscape – board-display active/bench slots
const PORTRAIT_ZONE_HEIGHT := 0.92  ## portrait  – deck, prize, discard slots

var _effective_height: float = PORTRAIT_ZONE_HEIGHT
var _effective_width: float = ZONE_WIDTH

var held_cards: Array[Card] = []
var is_highlighted := false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var area_3d: Area3D = $Area3D
@onready var label_3d: Label3D = $Label3D
@onready var collision_shape: CollisionShape3D = $Area3D/CollisionShape3D

var _base_material: StandardMaterial3D
var _highlight_material: StandardMaterial3D


func _ready() -> void:
	label_3d.text = zone_name
	_effective_height = BOARD_ZONE_HEIGHT if use_board_display else PORTRAIT_ZONE_HEIGHT
	_resize_zone(ZONE_WIDTH, _effective_height)

	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = zone_color
	_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = highlight_color
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	mesh_instance.set_surface_override_material(0, _base_material)


## Resizes the visual plane, collision box, and label to the given dimensions.
func _resize_zone(w: float, h: float) -> void:
	var plane := mesh_instance.mesh.duplicate() as PlaneMesh
	plane.size = Vector2(w, h)
	mesh_instance.mesh = plane

	var box := collision_shape.shape.duplicate() as BoxShape3D
	box.size = Vector3(w, 0.02, h)
	collision_shape.shape = box

	## Place the label towards the far edge so it doesn't overlap a card placed
	## in the centre of the zone.
	label_3d.position = Vector3(0.0, label_3d.position.y, -(h * 0.35))


## Public API for board.gd to resize a zone after _ready has run.
func set_zone_size(w: float, h: float) -> void:
	_effective_width = w
	_effective_height = h
	_resize_zone(w, h)


func can_accept_card(_card: Card) -> bool:
	return held_cards.size() < max_cards


func receive_card(card: Card) -> void:
	## Guard against duplicate inserts (e.g. redundant visual-sync calls).
	if held_cards.has(card):
		return
	if not can_accept_card(card):
		return
	held_cards.append(card)
	if use_board_display:
		card.set_board_mode(true)
	card_received.emit(card)
	_layout_held_cards()


func remove_card(card: Card) -> void:
	held_cards.erase(card)
	if use_board_display:
		card.set_board_mode(false)
	_layout_held_cards()


func set_highlighted(value: bool) -> void:
	is_highlighted = value
	if mesh_instance:
		mesh_instance.set_surface_override_material(
			0, _highlight_material if value else _base_material
		)


func contains_point(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= _effective_width / 2.0 and absf(local.z) <= _effective_height / 2.0


func _layout_held_cards() -> void:
	var card_rotation := rotation + Vector3(0, perspective_y_rotation, 0)
	for i in held_cards.size():
		var card := held_cards[i]
		var target := global_position + Vector3(0, 0.02 + i * 0.005, 0)
		card.set_home(target, card_rotation, 0)
		if not card.is_dragging:
			card.return_to_home()


## Re-applies the current perspective_y_rotation to all held cards.
func relayout() -> void:
	_layout_held_cards()
