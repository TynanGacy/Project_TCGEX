class_name Hand
extends Node3D
## Manages a fan of cards in 3D space.

signal card_played(card: Card)

const CARD_SPACING := 0.7
const MAX_FAN_ANGLE := 5.0  ## Degrees of rotation at edges
const CURVE_HEIGHT := 0.05  ## Vertical curve in the fan

var cards: Array[Card] = []


func add_card(card: Card) -> void:
	cards.append(card)
	add_child(card)
	card.card_dropped.connect(_on_card_dropped)
	card.drag_started.connect(_on_card_drag_started)
	card.drag_ended.connect(_on_card_drag_ended)
	_layout_cards()


func remove_card(card: Card) -> void:
	cards.erase(card)
	card.card_dropped.disconnect(_on_card_dropped)
	card.drag_started.disconnect(_on_card_drag_started)
	card.drag_ended.disconnect(_on_card_drag_ended)
	remove_child(card)
	_layout_cards()


func get_card_count() -> int:
	return cards.size()


func _layout_cards() -> void:
	var count := cards.size()
	if count == 0:
		return

	print("Hand layout: %d cards, global_pos=%s" % [count, str(global_position)])
	var total_width := (count - 1) * CARD_SPACING
	var start_x := -total_width / 2.0

	for i in count:
		var card := cards[i]
		## Normalized position: -1 to 1 from left to right
		var t := 0.0
		if count > 1:
			t = (float(i) / (count - 1)) * 2.0 - 1.0

		var x := start_x + i * CARD_SPACING
		var y := absf(t) * CURVE_HEIGHT
		var z := 0.0
		var rot_y := -t * deg_to_rad(MAX_FAN_ANGLE)

		var home := Vector3(x, y, z)
		card.set_home(home, Vector3(0.0, rot_y, 0.0), i)
		if not card.is_dragging:
			card.return_to_home()
		print("  Card %d home_local=%s global=%s" % [i, str(home), str(card.global_position)])


func _on_card_dropped(card: Card) -> void:
	card_played.emit(card)


func _on_card_drag_started(_card: Card) -> void:
	pass


func _on_card_drag_ended(card: Card) -> void:
	if card in cards:
		card.return_to_home()
