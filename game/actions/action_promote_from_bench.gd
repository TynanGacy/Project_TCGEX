# res://game/actions/action_promote_from_bench.gd
class_name ActionPromoteFromBench
extends GameAction

var board_player_id: int = -1
var bench_index: int = -1

func _init(actor: int = -1, board_id: int = -1, bench_i: int = -1) -> void:
	actor_id = actor
	board_player_id = board_id
	bench_index = bench_i

func validate(state: GameState) -> ActionResult:
	# Promotion typically occurs in a special window (after KO).
	# For now, allow during MAIN/START as before.
	if state.phase != TurnPhase.Phase.MAIN and state.phase != TurnPhase.Phase.START:
		return ActionResult.fail("Promotion not allowed in this phase.")

	if board_player_id < 0:
		return ActionResult.fail("No target board player specified.")

	if not state.can_promote_from_bench(actor_id, board_player_id, bench_index):
		return ActionResult.fail("Illegal promotion.")
	return ActionResult.success()

func apply(state: GameState) -> void:
	state.promote_from_bench(actor_id, board_player_id, bench_index)

func description() -> String:
	return "Promote P%d Bench[%d] to Active" % [board_player_id, bench_index]
