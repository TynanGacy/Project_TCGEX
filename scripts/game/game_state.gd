class_name GameState
extends RefCounted

var current_player_id: int = 0
var turn_number: int = 1
var phase: int = TurnPhase.Phase.START

var board: BoardState

var players: Array[Player] = []

var has_attacked_this_turn: bool = false


func _init(num_players: int = 2, active_slots: int = 1, max_bench: int = 5) -> void:
	board = BoardState.new(num_players, active_slots, max_bench)

	for i in range(num_players):
		var player := Player.new(i)
		players.append(player)


func get_current_player() -> Player:
	if current_player_id >= 0 and current_player_id < players.size():
		return players[current_player_id]
	return null


func get_player(player_id: int) -> Player:
	if player_id >= 0 and player_id < players.size():
		return players[player_id]
	return null


func begin_turn(player_id: int) -> void:
	current_player_id = player_id
	phase = TurnPhase.Phase.START
	has_attacked_this_turn = false

	var player := get_current_player()
	if player:
		player.reset_turn_flags()


func advance_phase() -> void:
	match phase:
		TurnPhase.Phase.START:
			phase = TurnPhase.Phase.MAIN
		TurnPhase.Phase.MAIN:
			phase = TurnPhase.Phase.ATTACK
		TurnPhase.Phase.ATTACK:
			phase = TurnPhase.Phase.END
		TurnPhase.Phase.END:
			pass


func end_turn() -> void:
	turn_number += 1
	# Assumes exactly 2 players (0 and 1). Extend for multiplayer.
	current_player_id = 1 - current_player_id
	begin_turn(current_player_id)


func setup_player_deck(player_id: int, card_data_array: Array[CardData]) -> void:
	var player := get_player(player_id)
	if player == null:
		return
	player.setup_deck(card_data_array)
	player.load_deck_into_board(board)
	player.shuffle_deck_zone(board)


func draw_starting_hand(player_id: int, count: int = 7) -> void:
	var player := get_player(player_id)
	if player == null:
		return
	for i in count:
		player.draw_card(board)


func can_swap_active_with_bench(player_id: int, active_slot: int, bench_index: int) -> bool:
	return board.can_swap_active_with_bench(player_id, active_slot, bench_index)


func swap_active_with_bench(player_id: int, active_slot: int, bench_index: int) -> void:
	var active_card := board.get_active_card(player_id, active_slot)
	var bench_card := board.get_bench_card_at(player_id, bench_index)

	if active_card != null and bench_card != null:
		board.swap_cards(active_card, bench_card)


func can_promote_from_bench(player_id: int, bench_index: int) -> bool:
	if board.get_first_empty_active_slot(player_id) == -1:
		return false

	var bench_card := board.get_bench_card_at(player_id, bench_index)
	return bench_card != null


func promote_from_bench(player_id: int, bench_index: int) -> void:
	var slot_idx := board.get_first_empty_active_slot(player_id)
	if slot_idx == -1:
		return

	var bench_card := board.get_bench_card_at(player_id, bench_index)
	if bench_card != null:
		var target_zone := "p%d_active_%d" % [player_id, slot_idx]
		board.move_card(bench_card, target_zone)
