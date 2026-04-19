extends Node3D
## Minimal bare-bones main scene.
##
## Wires the four systems (PokemonInstance / BoardPosition / GamePosition /
## ManagerSystem) together for a single user flow: drag a Basic Pokemon
## card out of the hand onto an Active or Bench slot, and the Manager
## validates + dispatches the ActionPlayPokemon.
##
## Intentionally omitted for the refactor: CPU opponent, turn/phase system,
## attacks, evolution, energy, trainers, retreat, prize taking, win check,
## developer-mode perspective flip.  These will be re-added on top of the
## cleaned-up four-system foundation.

@onready var camera: Camera3D = $Camera3D
@onready var board:  Board    = $Board
@onready var player_hand: Hand = $Board/PlayerHand

@onready var phase_label: Label = $HUD/TopBar/PhaseLabel
@onready var end_turn_button: Button = $HUD/TopBar/EndTurnButton
@onready var game_log: RichTextLabel = $HUD/LogPanel/GameLog

@onready var manager: Node = ManagerSystemSingleton

var card_scene: PackedScene = preload("res://scenes/card/card.tscn")

## CardData -> Card node cache for the hand.
var _hand_cards: Dictionary = {}

## Drag state
var dragged_card: Card = null
const DRAG_PLANE := Plane(Vector3.UP, 0.0)


func _ready() -> void:
	phase_label.text = "Bare-bones refactor: drag a Basic Pokemon to Active/Bench"
	end_turn_button.text = "Reset"
	end_turn_button.pressed.connect(_reset_game)

	manager.action_committed.connect(_on_action_committed)
	manager.action_rejected.connect(_on_action_rejected)
	manager.log_message.connect(_log)
	manager.hand_changed.connect(_on_hand_changed)
	manager.board_slot_changed.connect(_on_board_slot_changed)
	manager.overflow_escalation.connect(_on_overflow_escalation)

	## Wait a frame so Board._ready has run and DropZones are positioned.
	await get_tree().process_frame

	manager.attach_board_anchors(board.collect_slot_anchors())
	_start_game()


func _start_game() -> void:
	var deck: Array[CardData] = DeckLoader.load_deck(0)
	manager.load_deck(0, deck)
	manager.draw_starting_hand(0, 7)
	_rebuild_hand_visual(0)


func _reset_game() -> void:
	## Clear hand visuals.
	for card in _hand_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	_hand_cards.clear()

	## Clear every PokemonInstance from every slot.
	for sid in BoardPosition.all_slot_ids():
		var inst: PokemonInstance = manager.board_position.clear(sid)
		if inst != null:
			inst.queue_free()

	## Reset state by rebuilding the Manager's subsystems.
	manager.game_position  = GamePosition.new()
	manager.board_position.queue_free()
	manager.board_position = BoardPosition.new()
	manager.add_child(manager.board_position)
	manager.board_position.slot_changed.connect(manager._on_slot_changed)
	manager.board_position.overflow_escalation.connect(manager._on_overflow_escalation)
	manager.game_position.deck_changed.connect(func(pid): manager.deck_changed.emit(pid))
	manager.game_position.hand_changed.connect(func(pid): manager.hand_changed.emit(pid))
	manager.game_position.discard_changed.connect(func(pid): manager.discard_changed.emit(pid))
	manager.game_position.prizes_changed.connect(func(pid): manager.prizes_changed.emit(pid))
	manager.attach_board_anchors(board.collect_slot_anchors())

	_start_game()


## ---------------------------------------------------------------------------
## Hand visuals
## ---------------------------------------------------------------------------

func _rebuild_hand_visual(player_id: int) -> void:
	if player_id != 0:
		return  ## Only player 0 hand is rendered in bare-bones mode.

	player_hand.clear_cards()
	for card in _hand_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	_hand_cards.clear()

	var hand: Array = manager.game_position.hands[0]
	for data in hand:
		var card_node := card_scene.instantiate() as Card
		card_node.set_data(data)
		player_hand.add_card(card_node)
		card_node.drag_started.connect(_on_card_drag_started)
		card_node.card_dropped.connect(_on_card_dropped)
		_hand_cards[data] = card_node


func _on_hand_changed(player_id: int) -> void:
	if player_id == 0:
		_rebuild_hand_visual(0)


## ---------------------------------------------------------------------------
## Drag input
## ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_try_pick_card(mb.position)
			else:
				_try_drop_card()
	elif event is InputEventMouseMotion and dragged_card != null:
		var world := _screen_to_table((event as InputEventMouseMotion).position)
		dragged_card.move_to_drag_position(world)


func _try_pick_card(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null:
		return
	if card.data == null or not (card.data is PokemonCardData):
		return  ## Only Basic Pokemon can be played in bare-bones mode.
	if (card.data as PokemonCardData).stage != PokemonCardData.Stage.BASIC:
		return
	dragged_card = card
	card.start_drag()


func _try_drop_card() -> void:
	if dragged_card == null:
		return
	var card := dragged_card
	dragged_card = null

	var zone := board.get_slot_zone_at(card.global_position)
	if zone == null:
		card.end_drag()
		return

	var slot_id := board.slot_id_for_zone(zone)
	if slot_id == "":
		card.end_drag()
		return

	var action := ActionPlayPokemon.new(0, card.data as PokemonCardData, slot_id)
	manager.request_action(action)
	## If the action was committed the Card will be freed in _rebuild_hand_visual
	## via the hand_changed signal; if rejected, it stays in hand.
	card.end_drag()


func _on_card_drag_started(_card: Card) -> void:
	pass


func _on_card_dropped(_card: Card) -> void:
	pass


func _raycast_card(screen_pos: Vector2) -> Card:
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var body := hit.collider as Node
	if body == null:
		return null
	var parent := body.get_parent()
	return parent as Card


func _screen_to_table(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	var hit: Variant = DRAG_PLANE.intersects_ray(from, dir)
	return hit as Vector3 if hit != null else from


## ---------------------------------------------------------------------------
## Manager signal handlers
## ---------------------------------------------------------------------------

func _on_action_committed(action: GameAction) -> void:
	_log("[OK] %s" % action.description())


func _on_action_rejected(action: GameAction, reason: String) -> void:
	if action != null:
		_log("[X] %s — %s" % [action.description(), reason])
	else:
		_log("[X] %s" % reason)


func _on_board_slot_changed(_slot_id: String, _instance) -> void:
	pass  ## BoardPosition places the PokemonInstance visual itself.


func _on_overflow_escalation(player_id: int, _instance) -> void:
	_log("[Overflow] P%d has no empty bench — manual resolution required." % player_id)


func _log(text: String) -> void:
	game_log.append_text(text + "\n")
