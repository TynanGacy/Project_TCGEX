# res://game/GameState.gd
class_name GameState
extends RefCounted

# Assumes 2 players: 0 and 1.
var current_player_id: int = 0
var turn_number: int = 1
var phase: int = TurnPhase.Phase.START

# Optional bookkeeping (useful later)
var has_attacked_this_turn: bool = false

# ---- Hooks into your existing zone system ----
# You likely already have these operations implemented in your board model.
# Replace these stubs with calls into your real zone/board code.

func can_swap_active_with_bench(player_id: int, bench_index: int) -> bool:
	# Validate indexes, bench occupancy, etc.
	return true

func swap_active_with_bench(player_id: int, bench_index: int) -> void:
	# Perform swap in model. UI will respond via signals from TurnController.
	pass

func can_promote_from_bench(player_id: int, bench_index: int) -> bool:
	return true

func promote_from_bench(player_id: int, bench_index: int) -> void:
	pass

func begin_turn(player_id: int) -> void:
	current_player_id = player_id
	phase = TurnPhase.Phase.START
	has_attacked_this_turn = false

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
