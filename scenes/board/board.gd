class_name Board
extends Control
## The game board containing drop zones for both players.

signal card_placed(card: Card, zone: DropZone)

@onready var player_zones: HBoxContainer = %PlayerZones
@onready var opponent_zones: HBoxContainer = %OpponentZones

var all_zones: Array[DropZone] = []


func _ready() -> void:
	_collect_zones()


func _collect_zones() -> void:
	all_zones.clear()
	for child in player_zones.get_children():
		if child is DropZone:
			all_zones.append(child)
	for child in opponent_zones.get_children():
		if child is DropZone:
			all_zones.append(child)


func get_zone_at_position(pos: Vector2) -> DropZone:
	for zone in all_zones:
		if zone.get_drop_rect().has_point(pos):
			return zone
	return null


func highlight_valid_zones(card: Card) -> void:
	for zone in all_zones:
		zone.set_highlighted(zone.can_accept_card(card))


func clear_highlights() -> void:
	for zone in all_zones:
		zone.set_highlighted(false)


func try_place_card(card: Card, position: Vector2) -> bool:
	var zone := get_zone_at_position(position)
	if zone and zone.can_accept_card(card):
		zone.receive_card(card)
		card_placed.emit(card, zone)
		return true
	return false
