class_name Hand
extends Node3D
## Manages a fan of cards in 3D space.

signal card_played(card: Card)

const CARD_SPACING := 0.7
const MAX_FAN_ANGLE := 5.0  ## Degrees of rotation at edges
const CURVE_HEIGHT := 0.05  ## Vertical curve in the fan
const MAX_HAND_WIDTH := 6.5  ## World-unit cap before spacing compresses
const MIN_CARD_SPACING := 0.2  ## Never overlap cards more than this

var cards: Array[Card] = []


func add_card(card: Card) -> void:
	cards.append(card)
	add_child(card)
	card.card_dropped.connect(_on_card_dropped)
	_layout_cards()


func add_card_animated(card: Card, from_global: Vector3) -> void:
	cards.append(card)
	add_child(card)
	card.card_dropped.connect(_on_card_dropped)
	## Flag as dragging so _layout_cards sets home positions without
	## immediately calling return_to_home on this card.
	card.is_dragging = true
	_layout_cards()
	card.is_dragging = false
	## Place at the deck start position (in Hand local space) then arc to home.
	card.position = to_local(from_global)
	card.animate_draw()


func remove_card(card: Card) -> void:
	cards.erase(card)
	card.card_dropped.disconnect(_on_card_dropped)
	remove_child(card)
	_layout_cards()


func get_card_count() -> int:
	return cards.size()


func _layout_cards() -> void:
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
		## Normalised position: -1 (left) to 1 (right)
		var t := 0.0 if count == 1 else (float(i) / (count - 1)) * 2.0 - 1.0

		## Leftmost card gets the highest Z (closest to camera), ensuring it
		## always renders on top when cards overlap.
		var z_depth := (count - 1 - i) * 0.002

		var home := Vector3(start_x + i * spacing, absf(t) * CURVE_HEIGHT, z_depth)
		card.set_home(home, Vector3(0.0, -t * deg_to_rad(MAX_FAN_ANGLE), 0.0), i)
		if not card.is_dragging:
			card.return_to_home()


func _on_card_dropped(card: Card) -> void:
	card_played.emit(card)
