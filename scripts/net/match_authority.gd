class_name MatchAuthority
extends RefCounted
## Transport-agnostic authority contract used by the scene layer.
##
## Today: LocalMatchAuthority forwards to ManagerSystemSingleton so single
## player and offline development stay exactly as they are.
## Future: an OnlineMatchAuthority can implement the same surface and relay
## requests over the network to a dedicated authoritative server.

signal action_committed(action: GameAction)
signal action_rejected(action: GameAction, reason: String)
signal log_message(text: String)
signal board_slot_changed(slot_id: String, instance: PokemonInstance)
## Emitted whenever an already-placed PokemonInstance mutates in-place
## (HP, conditions, attachments, evolution).  Scene code and future online
## clients use this to refresh HUD or trigger effects without polling.
signal pokemon_state_changed(slot_id: String, instance: PokemonInstance)
signal overflow_escalation(player_id: int, instance: PokemonInstance)
signal hand_changed(player_id: int)
## Fired immediately after a card departs a player's hand (before hand_changed).
signal card_left_hand(player_id: int, card: CardData)
signal deck_changed(player_id: int)
signal discard_changed(player_id: int)
signal prizes_changed(player_id: int)
signal stadium_changed(stadium: TrainerCardData, owner_id: int)
signal supporter_changed(supporter: TrainerCardData, owner_id: int)
signal pokemon_knocked_out(slot_id: String)
signal prize_taken(player_id: int)
signal prize_selection_required(player_id: int)
signal promotion_required(player_id: int)
signal promotion_done(player_id: int, to_slot: String)
signal game_won(player_id: int)
signal turn_started(player_id: int, turn_number: int)
signal turn_ended(player_id: int)
signal phase_changed(phase: int)


func attach_board_anchors(_anchors: Dictionary) -> void:
	push_error("MatchAuthority.attach_board_anchors is not implemented.")


func load_deck(_player_id: int, _cards: Array[CardData]) -> void:
	push_error("MatchAuthority.load_deck is not implemented.")


func draw_starting_hand(_player_id: int, _count: int = 7) -> void:
	push_error("MatchAuthority.draw_starting_hand is not implemented.")


func deal_prizes(_player_id: int, _count: int = 6) -> void:
	push_error("MatchAuthority.deal_prizes is not implemented.")


func has_basic_in_hand(_pid: int) -> bool:
	push_error("MatchAuthority.has_basic_in_hand is not implemented.")
	return false


func return_hand_to_deck(_pid: int) -> void:
	push_error("MatchAuthority.return_hand_to_deck is not implemented.")


func draw_one(_pid: int) -> void:
	push_error("MatchAuthority.draw_one is not implemented.")


func begin_setup_placement(_pid: int) -> void:
	push_error("MatchAuthority.begin_setup_placement is not implemented.")


func end_setup_placement() -> void:
	push_error("MatchAuthority.end_setup_placement is not implemented.")


func begin_game(_starting_player: int = 0) -> void:
	push_error("MatchAuthority.begin_game is not implemented.")


func end_turn() -> void:
	push_error("MatchAuthority.end_turn is not implemented.")


func end_turn_async() -> void:
	push_error("MatchAuthority.end_turn_async is not implemented.")


func request_action(_action: GameAction) -> ActionResult:
	push_error("MatchAuthority.request_action is not implemented.")
	return ActionResult.fail("No authority implementation.")


func request_action_async(_action: GameAction) -> ActionResult:
	push_error("MatchAuthority.request_action_async is not implemented.")
	return ActionResult.fail("No authority implementation.")


func phase_name() -> String:
	push_error("MatchAuthority.phase_name is not implemented.")
	return "?"


func current_player_id() -> int:
	push_error("MatchAuthority.current_player_id is not implemented.")
	return 0


func current_turn_number() -> int:
	push_error("MatchAuthority.current_turn_number is not implemented.")
	return 0
