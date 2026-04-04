class_name Hand
extends Node3D
## Manages a fan of cards in 3D space.

signal card_played(card: Card)

const CARD_SPACING := 0.5  ## Default overlap spacing (< CARD_WIDTH so cards stack)
const MAX_FAN_ANGLE := 5.0  ## Degrees of rotation at edges
const CURVE_HEIGHT := 0.05  ## Vertical curve in the fan
const MAX_HAND_WIDTH := 4.0  ## World-unit cap before spacing compresses further
const MIN_CARD_SPACING := 0.15  ## Never overlap cards more than this

var cards: Array[Card] = []


func add_card(card: Card) -> void:
	cards.append(card)
	add_child(card)
	card.card_dropped.connect(_on_card_dropped)
	card.drag_started.connect(_on_card_drag_started)
	card.drag_ended.connect(_on_card_drag_ended)
	_layout_cards()


func add_card_animated(card: Card, from_global: Vector3) -> void:
	cards.append(card)
	add_child(card)
	card.card_dropped.connect(_on_card_dropped)
	card.drag_started.connect(_on_card_drag_started)
	card.drag_ended.connect(_on_card_drag_ended)
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

		## Rightmost card gets the highest Z (closest to camera), so it renders
		## on top when cards overlap — matching a physical hand held by a player.
		## Scale z_depth per card based on count so separation stays visible.
		var z_step := 0.01 if count <= 6 else 0.005
		var z_depth := i * z_step

		var home := Vector3(start_x + i * spacing, absf(t) * CURVE_HEIGHT, z_depth)
		card.set_home(home, Vector3(0.0, -t * deg_to_rad(MAX_FAN_ANGLE), 0.0), i)
		## Reorder in the scene tree so later children (rightmost) draw on top.
		move_child(card, i)
		if not card.is_dragging:
			card.return_to_home()


func _on_card_dropped(card: Card) -> void:
	card_played.emit(card)


func _on_card_drag_started(_card: Card) -> void:
	pass


func _on_card_drag_ended(_card: Card) -> void:
	pass
