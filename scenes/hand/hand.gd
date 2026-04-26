class_name Hand
extends Node3D
## Manages a fan of cards in 3D space.

const CARD_SPACING := 0.7
const MAX_FAN_ANGLE := 5.0  ## Degrees of rotation at edges
## Must stay below CARD_SPACING * tan(HAND_TILT_DEG) ≈ 0.049 so the Y drop
## between any two adjacent cards never exceeds the tilt-induced depth
## separation — if it does, Godot's transparent-object distance sort inverts
## at the overlap and produces clipping.
const CURVE_HEIGHT := 0.04  ## Vertical arc in the fan (V-shape, centre lowest)
const MAX_HAND_WIDTH := 6.5  ## World-unit cap before spacing compresses
const MIN_CARD_SPACING := 0.2  ## Never overlap cards more than this
## Each card tilts so its right side is slightly lower than its left.
## When cards overlap this makes each card appear above the one to its left.
const HAND_TILT_DEG := -4.0

var cards: Array[Card] = []


func add_card(card: Card) -> void:
	cards.append(card)
	add_child(card)
	card._is_in_hand = true
	card.scale = Vector3.ONE * Card.HAND_BASE_SCALE
	_layout_cards()


func remove_card(card: Card) -> void:
	cards.erase(card)
	card._is_in_hand = false
	card.scale = Vector3.ONE
	if card.get_parent() == self:
		remove_child(card)
	_layout_cards()


func clear_cards() -> void:
	for card in cards:
		card._is_in_hand = false
		card.scale = Vector3.ONE
		if card.get_parent() == self:
			remove_child(card)
	cards.clear()


func get_card_count() -> int:
	return cards.size()


func _layout_cards() -> void:
	for i in range(cards.size() - 1, -1, -1):
		if not is_instance_valid(cards[i]):
			cards.remove_at(i)

	var count := cards.size()
	if count == 0:
		return

	## Compress spacing only when the natural spread would overflow.
	var spacing := CARD_SPACING
	if count > 1:
		var natural_width := (count - 1) * CARD_SPACING
		if natural_width > MAX_HAND_WIDTH:
			spacing = maxf(MAX_HAND_WIDTH / (count - 1), MIN_CARD_SPACING)

	var total_width := (count - 1) * spacing
	var start_x := -total_width / 2.0

	for i in count:
		var card := cards[i]
		if not is_instance_valid(card):
			continue
		## Normalised position: -1 (left) to 1 (right)
		var t := 0.0 if count == 1 else (float(i) / (count - 1)) * 2.0 - 1.0

		var home := Vector3(start_x + i * spacing, absf(t) * CURVE_HEIGHT, 0.0)
		## All cards share the same tilt: left side up, right side down.
		## Where cards overlap, each card's left portion rises above its left
		## neighbour's right portion — like a spread physical hand.
		card.set_home(home, Vector3(0.0, -t * deg_to_rad(MAX_FAN_ANGLE), deg_to_rad(HAND_TILT_DEG)), i)
		## Scene-tree order: later children draw on top (rightmost = last).
		move_child(card, i)
		if not card.is_dragging:
			card.return_to_home()


