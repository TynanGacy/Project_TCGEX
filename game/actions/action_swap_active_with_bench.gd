# res://game/actions/ActionSwapActiveWithBench.gd
class_name ActionSwapActiveWithBench
extends GameAction

var bench_index: int

func _init(actor: int = -1, bench_i: int = -1) -> void:
	actor_id = actor
	bench_index = bench_i

func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Swapping is only allowed during MAIN phase.")
	if not state.can_swap_active_with_bench(actor_id, bench_index):
		return ActionResult.fail("Illegal swap (empty slot / invalid index / etc).")
	return ActionResult.success()

func apply(state: GameState) -> void:
	state.swap_active_with_bench(actor_id, bench_index)

func description() -> String:
	return "Swap Active with Bench[%d]" % bench_index
