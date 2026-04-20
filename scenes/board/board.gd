class_name Board
extends Node3D
## The 3D game board — a table surface with DropZone anchors.
##
## In the refactored architecture, DropZones are PURELY visual anchors used
## by BoardPosition to position PokemonInstances.  All logical slot state
## (which Pokemon is in which slot, overflow handling, etc.) lives in
## BoardPosition — the DropZones here just provide world positions.
##
## The named DropZones map 1:1 to BoardPosition slot_ids:
##   "Active"         -> p0_active1        "Opp Active"   -> p1_active1
##   "Active 2"       -> p0_active2        "Opp Active 2" -> p1_active2
##   "Bench N"        -> p0_benchN (1..5)  "Opp Bench N"  -> p1_benchN
##
## Overflow slots (p0_overflow1/2, p1_overflow1/2) are logical only — they
## are not rendered; BoardPosition auto-drains them to empty benches.
## If auto-drain fails it emits overflow_escalation for the Manager.

const PLAYMAT_PATHS: Array[String] = [
	"res://assets/images/playmats/playmat_default.png",
]

var _active_playmat_index: int = 0

const BENCH_CARD_W   := 1.32
const BENCH_CARD_H   := 0.88
const ACTIVE_CARD_W  := 1.98
const ACTIVE_CARD_H  := 1.32

## Maps Board_Position slot_id -> DropZone name in the scene tree.
const SLOT_TO_ZONE_NAME := {
	"p0_active1": "Active",
	"p0_active2": "Active 2",
	"p0_bench1":  "Bench 1",
	"p0_bench2":  "Bench 2",
	"p0_bench3":  "Bench 3",
	"p0_bench4":  "Bench 4",
	"p0_bench5":  "Bench 5",
	"p1_active1": "Opp Active",
	"p1_active2": "Opp Active 2",
	"p1_bench1":  "Opp Bench 1",
	"p1_bench2":  "Opp Bench 2",
	"p1_bench3":  "Opp Bench 3",
	"p1_bench4":  "Opp Bench 4",
	"p1_bench5":  "Opp Bench 5",
}

@onready var _table_surface: MeshInstance3D = $TableSurface


func _ready() -> void:
	_load_playmat()
	_initialise_zones()


func _load_playmat() -> void:
	var mat := _table_surface.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		_table_surface.set_surface_override_material(0, mat)
	var path := PLAYMAT_PATHS[_active_playmat_index]
	if ResourceLoader.exists(path):
		mat.albedo_texture = load(path) as Texture2D
		mat.albedo_color = Color.WHITE
	else:
		mat.albedo_texture = null
		mat.albedo_color = Color(0.22, 0.16, 0.1)


## Size the 2-player × 7-slot visible drop zones appropriately.  Called once
## on _ready.  Prize / deck / discard zones retain their scene transforms.
func _initialise_zones() -> void:
	for sid in SLOT_TO_ZONE_NAME.keys():
		var zone := get_zone_for_slot(sid)
		if zone == null:
			continue
		if "active" in sid:
			zone.set_zone_size(ACTIVE_CARD_W, ACTIVE_CARD_H)
		else:
			zone.set_zone_size(BENCH_CARD_W, BENCH_CARD_H)


## Hides excess Active / Bench DropZones so only the configured count is
## visible.  Active range: 1-2, Bench range: 3-5.  BoardPosition's logical
## slots are untouched — get_slot_zone_at already filters by visibility so
## hidden zones become undroppable.
func configure_slots(active_count: int, bench_count: int) -> void:
	active_count = clampi(active_count, 1, 2)
	bench_count  = clampi(bench_count, 3, 5)
	for pid in range(2):
		for i in range(1, 3):
			var sid := "p%d_active%d" % [pid, i]
			var zone := get_zone_for_slot(sid)
			if zone != null:
				zone.visible = (i <= active_count)
		for i in range(1, 6):
			var sid := "p%d_bench%d" % [pid, i]
			var zone := get_zone_for_slot(sid)
			if zone != null:
				zone.visible = (i <= bench_count)


## Returns the DropZone for a given BoardPosition slot_id, or null.
func get_zone_for_slot(slot_id: String) -> DropZone:
	var zone_name: String = SLOT_TO_ZONE_NAME.get(slot_id, "")
	if zone_name == "":
		return null
	return _find_zone_in_tree(zone_name)


## Builds the { slot_id: DropZone } dictionary BoardPosition uses as its
## anchors for visually placing PokemonInstance nodes.
func collect_slot_anchors() -> Dictionary:
	var anchors: Dictionary = {}
	for sid in SLOT_TO_ZONE_NAME.keys():
		var zone := get_zone_for_slot(sid)
		if zone != null:
			anchors[sid] = zone
	return anchors


## Returns the DropZone at the given world position (used for drag-to-drop).
## Iterates only over the Pokemon-slot zones we care about.
func get_slot_zone_at(world_pos: Vector3) -> DropZone:
	for sid in SLOT_TO_ZONE_NAME.keys():
		var zone := get_zone_for_slot(sid)
		if zone != null and zone.visible and zone.contains_point(world_pos):
			return zone
	return null


## Returns the slot_id for a given DropZone (reverse lookup), or "".
func slot_id_for_zone(zone: DropZone) -> String:
	if zone == null:
		return ""
	for sid in SLOT_TO_ZONE_NAME.keys():
		if get_zone_for_slot(sid) == zone:
			return sid
	return ""


func _find_zone_in_tree(zname: String) -> DropZone:
	for child in get_children():
		if child is DropZone and (child as DropZone).zone_name == zname:
			return child as DropZone
		for grandchild in child.get_children():
			if grandchild is DropZone and (grandchild as DropZone).zone_name == zname:
				return grandchild as DropZone
	return null


func clear_highlights() -> void:
	for sid in SLOT_TO_ZONE_NAME.keys():
		var zone := get_zone_for_slot(sid)
		if zone != null:
			zone.set_highlighted(false)
