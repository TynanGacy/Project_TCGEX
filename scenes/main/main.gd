extends Node3D
## Main scene — camera, lighting, input raycasting, turn engine, and game wiring.

@onready var camera: Camera3D = $Camera3D
@onready var board: Board = $Board
@onready var player_hand: Hand = $Board/PlayerHand

## HUD elements
@onready var phase_label: Label = $HUD/TopBar/PhaseLabel
@onready var end_turn_button: Button = $HUD/TopBar/EndTurnButton
@onready var game_log: RichTextLabel = $HUD/LogPanel/GameLog

var card_scene: PackedScene = preload("res://scenes/card/card.tscn")

## Drag state
var dragged_card: Card = null
var hovered_card: Card = null
var _source_zone: DropZone = null

## Turn engine
@onready var turn_controller: TurnController = TurnControllerSingleton
var game_state: GameState

## The Y height of the table surface for drag plane intersection
const TABLE_Y := 0.0
const DRAG_PLANE := Plane(Vector3.UP, 0.0)

@export var test_hand_size: int = 5

var _pikachu_data: CardData = null


func _ready() -> void:
	player_hand.card_played.connect(_on_card_played)
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	## Try loading test card data
	_pikachu_data = load("res://data/cards/pokemon/pikachu_basic.tres") as CardData

	## Set up game state
	game_state = GameState.new(2, 2, 4)
	turn_controller.set_state(game_state)

	turn_controller.phase_changed.connect(_on_phase_changed)
	turn_controller.action_rejected.connect(_on_action_rejected)
	turn_controller.action_committed.connect(_on_action_committed)
	turn_controller.log_message.connect(_on_turn_log)
	game_state.board.card_moved.connect(_on_board_card_moved)

	_on_phase_changed(game_state.phase)
	_deal_starting_hand(test_hand_size)
	_spawn_deck_visual(0)


func _deal_starting_hand(count: int) -> void:
	print("Dealing %d cards. Hand position: %s" % [count, str(player_hand.global_position)])

	if _pikachu_data:
		# Build a test deck via the game state
		var deck: Array[CardData] = []
		for i in 20:
			deck.append(_pikachu_data)
		game_state.setup_player_deck(0, deck)
		game_state.draw_starting_hand(0, count)

		for inst in game_state.board.get_hand_cards(0):
			var card: Card = card_scene.instantiate()
			card.set_instance(inst)
			card.drag_started.connect(_on_card_drag_started)
			card.drag_ended.connect(_on_card_drag_ended)
			player_hand.add_card(card)
	else:
		# Fallback: spawn placeholder cards when no card data is available
		push_warning("_deal_starting_hand: pikachu_basic.tres failed to load, using placeholders")
		for i in count:
			var card: Card = card_scene.instantiate()
			card.card_name = "Card %d" % (i + 1)
			card.drag_started.connect(_on_card_drag_started)
			card.drag_ended.connect(_on_card_drag_ended)
			player_hand.add_card(card)


func _spawn_deck_visual(pid: int) -> void:
	var deck_zone := board.get_zone_by_name("Deck")
	if deck_zone == null:
		return
	for inst in game_state.board.get_zone("p%d_deck" % pid):
		var card: Card = card_scene.instantiate()
		card.set_instance(inst as CardInstance)
		card.face_down = true
		board.add_child(card)
		deck_zone.receive_card(card)


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
		_source_zone = board.get_zone_containing(card)
		if _source_zone:
			_source_zone.remove_card(card)
		dragged_card = card
		card.start_drag()


func _try_drop_card() -> void:
	if not dragged_card:
		return
	var card := dragged_card
	var from_zone := _source_zone
	dragged_card = null
	_source_zone = null
	card.end_drag()

	if game_state.phase != TurnPhase.Phase.MAIN:
		_log_line("Cards can only be played during the Main Phase.")
		_snap_back(card, from_zone)
		return

	var world_pos := card.global_position
	var target_zone := board.get_zone_at_position(world_pos)
	if target_zone and target_zone.can_accept_card(card):
		if from_zone == null:
			## Coming from hand: reparent to board before zone receives it
			player_hand.remove_card(card)
			board.add_child(card)
			if card.card_instance:
				card.card_instance.zone = CardInstance.Zone.ACTIVE
		target_zone.receive_card(card)
	else:
		_snap_back(card, from_zone)


func _snap_back(card: Card, from_zone: DropZone) -> void:
	if from_zone != null:
		from_zone.receive_card(card)
	else:
		card.snap_to_home()


func _move_dragged_card(screen_pos: Vector2) -> void:
	var world_pos: Variant = _screen_to_table(screen_pos)
	if world_pos != null:
		dragged_card.move_to_drag_position(world_pos as Vector3)


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
	var body: Object = result.collider
	if body is StaticBody3D and body.get_parent() is Card:
		return body.get_parent() as Card
	return null


func _screen_to_table(screen_pos: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit: Variant = DRAG_PLANE.intersects_ray(from, dir)
	return hit


func _on_card_played(_card: Card) -> void:
	pass  ## Placement is handled in _try_drop_card.


func _on_card_drag_started(card: Card) -> void:
	if game_state.phase == TurnPhase.Phase.MAIN:
		board.highlight_valid_zones(card)


func _on_card_drag_ended(_card: Card) -> void:
	board.clear_highlights()


## Turn engine handlers
func _on_end_turn_pressed() -> void:
	var actor := turn_controller.state.current_player_id
	if game_state.phase == TurnPhase.Phase.END:
		turn_controller.end_turn(actor)
	else:
		turn_controller.next_phase(actor)


func _on_phase_changed(phase: int) -> void:
	if phase_label:
		phase_label.text = "Phase: %s" % TurnPhase.phase_to_string(phase)
	## Turn 1 hand is dealt manually in _deal_starting_hand; skip auto-draw.
	if phase == TurnPhase.Phase.START and game_state.turn_number > 1:
		turn_controller.request_action(
			ActionDrawCard.new(game_state.current_player_id, 1)
		)


func _on_board_card_moved(inst: CardInstance, from_zone: String, to_zone: String) -> void:
	if from_zone.ends_with("_deck") and to_zone.ends_with("_hand"):
		_sync_deck_draw_visual(inst)


func _sync_deck_draw_visual(inst: CardInstance) -> void:
	var deck_zone := board.get_zone_by_name("Deck")
	if deck_zone == null:
		return
	var drawn_card: Card = null
	for card in deck_zone.held_cards:
		if card.card_instance == inst:
			drawn_card = card
			break
	if drawn_card == null:
		return
	deck_zone.remove_card(drawn_card)
	board.remove_child(drawn_card)
	drawn_card.face_down = false
	drawn_card.drag_started.connect(_on_card_drag_started)
	drawn_card.drag_ended.connect(_on_card_drag_ended)
	player_hand.add_card(drawn_card)


func _on_action_rejected(action: GameAction, reason: String) -> void:
	_log_line("[REJECT] %s (%s)" % [action.description(), reason])


func _on_action_committed(_action: GameAction) -> void:
	pass


func _on_turn_log(text: String) -> void:
	_log_line(text)


func _log_line(text: String) -> void:
	if game_log:
		game_log.append_text(text + "\n")
