class_name Board
extends Node3D
## The 3D game board — a table surface with drop zones.

var all_zones: Array[DropZone] = []

const BENCH_SPACING := 0.7
const ACTIVE_Z := 0.7
const BENCH_Z := 1.75


func _ready() -> void:
	_collect_zones()


## Rebuild the active zone list, skipping invisible zones so they are never
## treated as valid drop targets.
func _collect_zones() -> void:
	all_zones.clear()
	for child in get_children():
		if child is DropZone and child.visible:
			all_zones.append(child as DropZone)
		for grandchild in child.get_children():
			if grandchild is DropZone and grandchild.visible:
				all_zones.append(grandchild as DropZone)


## Reposition and show/hide active and bench zones to match the configured
## counts. Call once after creating GameState, before dealing cards.
func configure_slots(num_active: int, num_bench: int) -> void:
	for i in range(2):
		var aname := "Active" if i == 0 else "Active 2"
		var zone := _find_zone_in_tree(aname)
		if zone == null:
			continue
		zone.visible = i < num_active
		if i < num_active:
			zone.position = Vector3(_active_x(i, num_active, false), 0.0, ACTIVE_Z)

	for i in range(1, 6):
		var zone := _find_zone_in_tree("Bench %d" % i)
		if zone == null:
			continue
		var si := i - 1
		zone.visible = si < num_bench
		if si < num_bench:
			zone.position = Vector3(_bench_x(si, num_bench, false), 0.0, BENCH_Z)

	for i in range(2):
		var aname := "Opp Active" if i == 0 else "Opp Active 2"
		var zone := _find_zone_in_tree(aname)
		if zone == null:
			continue
		zone.visible = i < num_active
		if i < num_active:
			zone.position = Vector3(_active_x(i, num_active, true), 0.0, -ACTIVE_Z)

	for i in range(1, 6):
		var zone := _find_zone_in_tree("Opp Bench %d" % i)
		if zone == null:
			continue
		var si := i - 1
		zone.visible = si < num_bench
		if si < num_bench:
			zone.position = Vector3(_bench_x(si, num_bench, true), 0.0, -BENCH_Z)

	_collect_zones()


## Searches the full scene tree (visible or not) for a zone by name.
func _find_zone_in_tree(zname: String) -> DropZone:
	for child in get_children():
		if child is DropZone and (child as DropZone).zone_name == zname:
			return child as DropZone
		for grandchild in child.get_children():
			if grandchild is DropZone and (grandchild as DropZone).zone_name == zname:
				return grandchild as DropZone
	return null


func _active_x(slot: int, total: int, mirror: bool) -> float:
	var x := 0.0 if total == 1 else (-0.35 + slot * 0.7)
	return -x if mirror else x


func _bench_x(slot: int, total: int, mirror: bool) -> float:
	var half_span := (total - 1) * BENCH_SPACING * 0.5
	var x := -half_span + slot * BENCH_SPACING
	return -x if mirror else x


func get_zone_by_name(zone_name: String) -> DropZone:
	for zone in all_zones:
		if zone.zone_name == zone_name:
			return zone
	return null


func get_zone_containing(card: Card) -> DropZone:
	for zone in all_zones:
		if card in zone.held_cards:
			return zone
	return null


func get_zone_at_position(world_pos: Vector3) -> DropZone:
	for zone in all_zones:
		if zone.contains_point(world_pos):
			return zone
	return null


func clear_highlights() -> void:
	for zone in all_zones:
		zone.set_highlighted(false)


