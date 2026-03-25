extends Node3D
## Main scene — camera, lighting, input raycasting, and game wiring.

@onready var camera: Camera3D = $Camera3D
@onready var board: Board = $Board
@onready var player_hand: Hand = $Board/PlayerHand

var card_scene: PackedScene = preload("res://scenes/card/card.tscn")

## Drag state
var dragged_card: Card = null
var hovered_card: Card = null

## The Y height of the table surface for drag plane intersection
const TABLE_Y := 0.0
const DRAG_PLANE := Plane(Vector3.UP, 0.0)


func _ready() -> void:
	player_hand.card_played.connect(_on_card_played)
	_deal_starting_hand(5)


func _deal_starting_hand(count: int) -> void:
	for i in count:
		var card: Card = card_scene.instantiate()
		card.card_name = "Card %d" % (i + 1)
		card.drag_started.connect(_on_card_drag_started)
		card.drag_ended.connect(_on_card_drag_ended)
		player_hand.add_card(card)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_try_pick_card(mb.position)
			else:
				_try_drop_card()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragged_card:
			_move_dragged_card(mm.position)
		else:
			_update_hover(mm.position)


func _try_pick_card(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card:
		dragged_card = card
		card.start_drag()


func _try_drop_card() -> void:
	if not dragged_card:
		return
	dragged_card.end_drag()
	dragged_card = null


func _move_dragged_card(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_table(screen_pos)
	if world_pos != null:
		dragged_card.move_to_drag_position(world_pos)


func _update_hover(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card != hovered_card:
		if hovered_card:
			hovered_card.set_hovered(false)
		hovered_card = card
		if hovered_card:
			hovered_card.set_hovered(true)


func _raycast_card(screen_pos: Vector2) -> Card:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0, 1)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null
	var body := result.collider
	if body is StaticBody3D and body.get_parent() is Card:
		return body.get_parent() as Card
	return null


func _screen_to_table(screen_pos: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit := DRAG_PLANE.intersects_ray(from, dir)
	return hit


func _on_card_played(card: Card) -> void:
	var world_pos := card.global_position
	if board.try_place_card(card, world_pos):
		player_hand.remove_card(card)
		board.add_child(card)
	else:
		card.return_to_home()


func _on_card_drag_started(card: Card) -> void:
	board.highlight_valid_zones(card)


func _on_card_drag_ended(_card: Card) -> void:
	board.clear_highlights()
