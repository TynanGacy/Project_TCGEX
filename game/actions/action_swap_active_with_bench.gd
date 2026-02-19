# res://game/actions/action_swap_active_with_bench.gd
class_name ActionSwapActiveWithBench
extends GameAction

var player_id: int = -1
var active_slot: int = -1
var bench_index: int = -1

func _init(actor: int = -1, p_id: int = -1, active_i: int = -1, bench_i: int = -1) -> void:
	actor_id = actor
	player_id = p_id
	active_slot = active_i
	bench_index = bench_i

func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Swapping is only allowed during MAIN phase.")
	
	# Validate that actor is performing action on their own board
	if actor_id != player_id:
		return ActionResult.fail("Can only swap cards on your own board.")
	
	if not state.can_swap_active_with_bench(player_id, active_slot, bench_index):
		return ActionResult.fail("Illegal swap (empty slot / invalid index / etc).")
	
	return ActionResult.success()

func apply(state: GameState) -> void:
	state.swap_active_with_bench(player_id, active_slot, bench_index)

func description() -> String:
	return "Swap P%d Active[%d] with Bench[%d]" % [player_id, active_slot, bench_index]
