class_name LocalMatchAuthority
extends MatchAuthority
## Offline/dev authority adapter.
##
## Wraps the in-process ManagerSystemSingleton behind MatchAuthority so the
## scene layer can target a stable authority API now, then swap to an online
## transport later without rewriting all scene interaction code.

var _manager: Node


func _init(manager: Node) -> void:
	_manager = manager
	_bind_signals()


func _bind_signals() -> void:
	_manager.action_committed.connect(func(action: GameAction) -> void:
		action_committed.emit(action)
	)
	_manager.action_rejected.connect(func(action: GameAction, reason: String) -> void:
		action_rejected.emit(action, reason)
	)
	_manager.log_message.connect(func(text: String) -> void:
		log_message.emit(text)
	)
	_manager.board_slot_changed.connect(func(slot_id: String, instance: PokemonInstance) -> void:
		board_slot_changed.emit(slot_id, instance)
	)
	_manager.pokemon_state_changed.connect(func(slot_id: String, instance: PokemonInstance) -> void:
		pokemon_state_changed.emit(slot_id, instance)
	)
	_manager.overflow_escalation.connect(func(player_id: int, instance: PokemonInstance) -> void:
		overflow_escalation.emit(player_id, instance)
	)
	_manager.hand_changed.connect(func(player_id: int) -> void:
		hand_changed.emit(player_id)
	)
	_manager.card_left_hand.connect(func(player_id: int, card: CardData) -> void:
		card_left_hand.emit(player_id, card)
	)
	_manager.deck_changed.connect(func(player_id: int) -> void:
		deck_changed.emit(player_id)
	)
	_manager.discard_changed.connect(func(player_id: int) -> void:
		discard_changed.emit(player_id)
	)
	_manager.prizes_changed.connect(func(player_id: int) -> void:
		prizes_changed.emit(player_id)
	)
	_manager.stadium_changed.connect(func(stadium: TrainerCardData, owner_id: int) -> void:
		stadium_changed.emit(stadium, owner_id)
	)
	_manager.pokemon_knocked_out.connect(func(slot_id: String) -> void:
		pokemon_knocked_out.emit(slot_id)
	)
	_manager.prize_taken.connect(func(player_id: int) -> void:
		prize_taken.emit(player_id)
	)
	_manager.prize_selection_required.connect(func(player_id: int) -> void:
		prize_selection_required.emit(player_id)
	)
	_manager.promotion_required.connect(func(player_id: int) -> void:
		promotion_required.emit(player_id)
	)
	_manager.promotion_done.connect(func(player_id: int, to_slot: String) -> void:
		promotion_done.emit(player_id, to_slot)
	)
	_manager.game_won.connect(func(player_id: int) -> void:
		game_won.emit(player_id)
	)
	_manager.turn_started.connect(func(player_id: int, turn_number: int) -> void:
		turn_started.emit(player_id, turn_number)
	)
	_manager.turn_ended.connect(func(player_id: int) -> void:
		turn_ended.emit(player_id)
	)
	_manager.phase_changed.connect(func(phase: int) -> void:
		phase_changed.emit(phase)
	)


func attach_board_anchors(anchors: Dictionary) -> void:
	_manager.attach_board_anchors(anchors)


func load_deck(player_id: int, cards: Array[CardData]) -> void:
	_manager.load_deck(player_id, cards)


func draw_starting_hand(player_id: int, count: int = 7) -> void:
	_manager.draw_starting_hand(player_id, count)


func deal_prizes(player_id: int, count: int = 6) -> void:
	_manager.deal_prizes(player_id, count)


func has_basic_in_hand(pid: int) -> bool:
	return _manager.has_basic_in_hand(pid)


func return_hand_to_deck(pid: int) -> void:
	_manager.return_hand_to_deck(pid)


func draw_one(pid: int) -> void:
	_manager.draw_one(pid)


func begin_setup_placement(pid: int) -> void:
	_manager.begin_setup_placement(pid)


func end_setup_placement() -> void:
	_manager.end_setup_placement()


func begin_game(starting_player: int = 0) -> void:
	_manager.begin_game(starting_player)


func end_turn() -> void:
	_manager.end_turn()


func request_action(action: GameAction) -> ActionResult:
	return _manager.request_action(action)


func phase_name() -> String:
	return _manager.phase_name()


func current_player_id() -> int:
	return _manager.current_player


func current_turn_number() -> int:
	return _manager.turn_number
