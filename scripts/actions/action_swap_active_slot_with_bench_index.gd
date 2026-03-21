# res://scripts/actions/action_swap_active_slot_with_bench_index.gd
class_name ActionSwapActiveSlotWithBenchIndex
extends GameAction

var board_player_id: int
var active_slot_index: int
var bench_index: int

func _init(actor: int = -1, board_id: int = -1, active_i: int = -1, bench_i: int = -1) -> void:
	actor_id = actor
	board_player_id = board_id
	active_slot_index = active_i
	bench_index = bench_i

func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Swapping only allowed during MAIN phase.")
	var table_state := state as TableGameState
	if not table_state.can_swap_active_with_bench_3(board_player_id, active_slot_index, bench_index):
		return ActionResult.fail("Illegal swap.")
	return ActionResult.success()

func apply(state: GameState) -> void:
	(state as TableGameState).swap_active_with_bench_3(board_player_id, active_slot_index, bench_index)

func description() -> String:
	return "Swap P%d Active[%d] with Bench[%d]" % [board_player_id, active_slot_index, bench_index]
