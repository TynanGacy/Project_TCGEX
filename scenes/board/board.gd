class_name Board
extends Node3D
## The 3D game board — a table surface with drop zones.

signal card_placed(card: Card, zone: DropZone)

var all_zones: Array[DropZone] = []


func _ready() -> void:
	_collect_zones()


func _collect_zones() -> void:
	all_zones.clear()
	for child in get_children():
		if child is DropZone:
			all_zones.append(child)
		for grandchild in child.get_children():
			if grandchild is DropZone:
				all_zones.append(grandchild)


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


func highlight_valid_zones(card: Card) -> void:
	for zone in all_zones:
		zone.set_highlighted(zone.can_accept_card(card))


func clear_highlights() -> void:
	for zone in all_zones:
		zone.set_highlighted(false)


func try_place_card(card: Card, world_pos: Vector3) -> bool:
	var zone := get_zone_at_position(world_pos)
	if zone and zone.can_accept_card(card):
		zone.receive_card(card)
		card_placed.emit(card, zone)
		return true
	return false
