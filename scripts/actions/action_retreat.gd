class_name ActionRetreat
extends GameAction
## Retreats one of the actor's Active Pokemon to the bench by paying retreat cost,
## then switches it with a chosen benched Pokemon.

var active_slot: int = 0
var bench_index: int = -1


func _init(pid: int, slot: int = 0, bench_i: int = -1) -> void:
	actor_id = pid
	active_slot = slot
	bench_index = bench_i


func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Can only retreat during MAIN phase.")

	if state.has_attacked_this_turn:
		return ActionResult.fail("Cannot retreat after attacking this turn.")

	if state.has_retreated_this_turn:
		return ActionResult.fail("You have already retreated this turn.")

	var active := state.board.get_active_card(actor_id, active_slot)
	if active == null:
		return ActionResult.fail("No Active Pokemon in slot %d." % active_slot)

	var bench := state.board.get_bench_cards(actor_id)
	if bench.is_empty():
		return ActionResult.fail("No Benched Pokemon available to switch in.")

	var retreat_cost := active.get_effective_retreat_cost(state)
	if active.attached_energy.size() < retreat_cost:
		return ActionResult.fail("Not enough Energy to retreat (need %d)." % retreat_cost)

	if bench_index >= 0 and not state.can_retreat_active(actor_id, active_slot, bench_index):
		return ActionResult.fail("Invalid retreat target at Bench[%d]." % bench_index)

	return ActionResult.success()


func apply(state: GameState) -> void:
	var bench := state.board.get_bench_cards(actor_id)
	if bench.is_empty():
		return

	if bench_index >= 0:
		state.retreat_active_to_bench(actor_id, active_slot, bench_index)
		return

	if bench.size() == 1:
		state.retreat_active_to_bench(actor_id, active_slot, 0)
		return

	var choices: Array = []
	for c in bench:
		choices.append(c)
	TurnControllerSingleton.request_effect_choice(
		"Choose a Benched Pokemon to switch in for retreat.",
		actor_id,
		choices,
		func(chosen: Array) -> void:
			if chosen.is_empty():
				return
			var selected := chosen[0] as CardInstance
			var idx := state.board.get_bench_cards(actor_id).find(selected)
			if idx >= 0:
				state.retreat_active_to_bench(actor_id, active_slot, idx)
	)


func description() -> String:
	return "Retreat Active[%d]" % active_slot
