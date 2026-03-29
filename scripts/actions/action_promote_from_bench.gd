class_name ActionPromoteFromBench
extends GameAction

var player_id: int = -1
var bench_index: int = -1

func _init(actor: int = -1, p_id: int = -1, bench_i: int = -1) -> void:
	actor_id = actor
	player_id = p_id
	bench_index = bench_i

func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN and state.phase != TurnPhase.Phase.START:
		return ActionResult.fail("Promotion not allowed in this phase.")

	if actor_id != player_id:
		return ActionResult.fail("Can only promote cards on your own board.")

	if not state.can_promote_from_bench(player_id, bench_index):
		return ActionResult.fail("Illegal promotion.")

	return ActionResult.success()

func apply(state: GameState) -> void:
	state.promote_from_bench(player_id, bench_index)

func description() -> String:
	return "Promote P%d Bench[%d] to Active" % [player_id, bench_index]
