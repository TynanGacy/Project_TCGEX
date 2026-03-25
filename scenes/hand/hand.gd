class_name Hand
extends Control
## Manages a fan/spread of cards at the bottom of the screen.

signal card_played(card: Card)

const CARD_SPACING := 120.0
const MAX_FAN_ANGLE := 20.0  ## Degrees of rotation at edges of hand
const CURVE_HEIGHT := 20.0   ## How much cards curve upward in the center

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

	var total_width := (count - 1) * CARD_SPACING + Card.BASE_SIZE.x
	var start_x := (size.x - total_width) / 2.0

	for i in count:
		var card := cards[i]
		## Normalized position: -1 to 1 from left to right
		var t := 0.0
		if count > 1:
			t = (float(i) / (count - 1)) * 2.0 - 1.0

		var x := start_x + i * CARD_SPACING
		var y := size.y - Card.BASE_SIZE.y - 10.0 + abs(t) * CURVE_HEIGHT
		var angle := -t * deg_to_rad(MAX_FAN_ANGLE)

		card.set_home(Vector2(x, y), angle, i)
		if not card.is_dragging:
			card.return_to_home()


func _on_card_dropped(card: Card) -> void:
	card_played.emit(card)


func _on_card_drag_started(_card: Card) -> void:
	pass


func _on_card_drag_ended(card: Card) -> void:
	if card in cards:
		card.return_to_home()


func _on_resized() -> void:
	_layout_cards()


func _ready() -> void:
	resized.connect(_on_resized)
