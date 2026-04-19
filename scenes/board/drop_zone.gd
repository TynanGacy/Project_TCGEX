class_name DropZone
extends Node3D
## A 3D zone on the table.  In the refactored architecture a DropZone is
## purely a visual anchor: BoardPosition reparents a PokemonInstance to it
## when placing into that slot, and the scene layer raycasts against its
## footprint to figure out which slot the player dragged onto.

@export var zone_name: String = "Zone"
@export var zone_color: Color = Color(0.55, 0.55, 0.60, 0.30)
@export var highlight_color: Color = Color(0.75, 0.78, 0.90, 0.52)

const ZONE_WIDTH           := 0.66
const BOARD_ZONE_HEIGHT    := 0.44
const PORTRAIT_ZONE_HEIGHT := 0.92

var _effective_height: float = PORTRAIT_ZONE_HEIGHT
var _effective_width:  float = ZONE_WIDTH

var is_highlighted := false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var area_3d: Area3D = $Area3D
@onready var label_3d: Label3D = $Label3D
@onready var collision_shape: CollisionShape3D = $Area3D/CollisionShape3D

var _base_material: StandardMaterial3D
var _highlight_material: StandardMaterial3D


func _ready() -> void:
	label_3d.text = zone_name
	_resize_zone(ZONE_WIDTH, _effective_height)

	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = zone_color
	_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = highlight_color
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	mesh_instance.set_surface_override_material(0, _base_material)


func _resize_zone(w: float, h: float) -> void:
	var plane := mesh_instance.mesh.duplicate() as PlaneMesh
	plane.size = Vector2(w, h)
	mesh_instance.mesh = plane

	var box := collision_shape.shape.duplicate() as BoxShape3D
	box.size = Vector3(w, 0.02, h)
	collision_shape.shape = box

	label_3d.position = Vector3(0.0, label_3d.position.y, -(h * 0.35))


func set_zone_size(w: float, h: float) -> void:
	_effective_width  = w
	_effective_height = h
	_resize_zone(w, h)


func set_highlighted(value: bool) -> void:
	is_highlighted = value
	if mesh_instance:
		mesh_instance.set_surface_override_material(
			0, _highlight_material if value else _base_material
		)


func contains_point(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= _effective_width / 2.0 and absf(local.z) <= _effective_height / 2.0
