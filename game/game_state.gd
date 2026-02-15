# res://game/GameState.gd
class_name GameState
extends RefCounted

## GameState manages the overall turn structure and delegates
## board/zone management to BoardState.

# Assumes 2 players: 0 and 1.
var current_player_id: int = 0
var turn_number: int = 1
var phase: int = TurnPhase.Phase.START

# Board management (separated out)
var board: BoardState

# Player management
var players: Array[Player] = []

# Optional bookkeeping (useful later)
var has_attacked_this_turn: bool = false


func _init(num_players: int = 2, active_slots: int = 1, max_bench: int = 5) -> void:
	board = BoardState.new(num_players, active_slots, max_bench)
	
	# Create player objects
	for i in range(num_players):
		var player := Player.new(i)
		players.append(player)


func get_current_player() -> Player:
	"""Returns the Player object for the current turn."""
	if current_player_id >= 0 and current_player_id < players.size():
		return players[current_player_id]
	return null


func get_player(player_id: int) -> Player:
	"""Returns the Player object for a given ID."""
	if player_id >= 0 and player_id < players.size():
		return players[player_id]
	return null


# ============================================================
#	Turn Flow
# ============================================================
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
			# END should typically roll into next player's START via end_turn().
			pass


func end_turn() -> void:
	turn_number += 1
	current_player_id = 1 - current_player_id
	begin_turn(current_player_id)


# ============================================================
#	Board Delegates (convenience methods)
# ============================================================
func can_swap_active_with_bench(player_id: int, active_slot: int, bench_index: int) -> bool:
	return board.can_swap_active_with_bench(player_id, active_slot, bench_index)


func swap_active_with_bench(player_id: int, active_slot: int, bench_index: int) -> void:
	var active_card := board.get_active_card(player_id, active_slot)
	var bench_cards := board.get_bench_cards(player_id)
	
	if bench_index >= 0 and bench_index < bench_cards.size():
		var bench_card := bench_cards[bench_index]
		board.swap_cards(active_card, bench_card)


func can_promote_from_bench(player_id: int, bench_index: int) -> bool:
	if board.get_first_empty_active_slot(player_id) == -1:
		return false
	
	var bench_cards := board.get_bench_cards(player_id)
	return bench_index >= 0 and bench_index < bench_cards.size()


func promote_from_bench(player_id: int, bench_index: int) -> void:
	var slot_idx := board.get_first_empty_active_slot(player_id)
	if slot_idx == -1:
		return
	
	var bench_cards := board.get_bench_cards(player_id)
	if bench_index >= 0 and bench_index < bench_cards.size():
		var card := bench_cards[bench_index]
		var target_zone := "p%d_active_%d" % [player_id, slot_idx]
		board.move_card(card, target_zone)
