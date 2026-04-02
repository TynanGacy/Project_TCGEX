class_name DropZone
extends Node3D
## A 3D zone on the table where cards can be dropped.

signal card_received(card: Card)

@export var zone_name: String = "Zone"
@export var zone_color: Color = Color(0.2, 0.4, 0.2, 0.5)
@export var highlight_color: Color = Color(0.3, 0.7, 0.3, 0.7)
@export var max_cards: int = 1

const ZONE_WIDTH := 0.7
const ZONE_HEIGHT := 0.95

var held_cards: Array[Card] = []
var is_highlighted := false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var area_3d: Area3D = $Area3D
@onready var label_3d: Label3D = $Label3D

var _base_material: StandardMaterial3D
var _highlight_material: StandardMaterial3D


func _ready() -> void:
	label_3d.text = zone_name

	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = zone_color
	_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = highlight_color
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	mesh_instance.set_surface_override_material(0, _base_material)


func can_accept_card(_card: Card) -> bool:
	return held_cards.size() < max_cards


func receive_card(card: Card) -> void:
	held_cards.append(card)
	card_received.emit(card)
	_layout_held_cards()


func remove_card(card: Card) -> void:
	held_cards.erase(card)
	_layout_held_cards()


func set_highlighted(value: bool) -> void:
	is_highlighted = value
	if mesh_instance:
		mesh_instance.set_surface_override_material(
			0, _highlight_material if value else _base_material
		)


func contains_point(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= ZONE_WIDTH / 2.0 and absf(local.z) <= ZONE_HEIGHT / 2.0


func _layout_held_cards() -> void:
	for i in held_cards.size():
		var card := held_cards[i]
		var target := global_position + Vector3(0, 0.02 + i * 0.005, 0)
		card.set_home(target, rotation, 0)
		card.return_to_home()
