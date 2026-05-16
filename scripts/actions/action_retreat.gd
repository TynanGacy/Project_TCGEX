class_name ActionRetreat
extends GameAction
## Retreats the active Pokémon to the bench.
##
## Cost: discard energy equal to the Pokémon's retreat_cost (any type).
## The first retreat_cost energies in attached_energy are discarded;
## the active and chosen bench Pokémon are swapped.
## All special conditions on the retreating Pokémon are cured.

var player_id: int
var active_slot: String
var bench_slot: String


func _init(pid: int, act_slot: String, bnch_slot: String) -> void:
	player_id   = pid
	active_slot = act_slot
	bench_slot  = bnch_slot


func validate(manager) -> ActionResult:
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if manager.retreat_used_this_turn[player_id]:
		return ActionResult.fail("You have already retreated this turn.")

	if not manager.board_position.has_slot(active_slot):
		return ActionResult.fail("Unknown active slot '%s'." % active_slot)
	if manager.board_position.player_of(active_slot) != player_id:
		return ActionResult.fail("Active slot does not belong to you.")
	if "active" not in active_slot:
		return ActionResult.fail("Can only retreat from an active slot.")
	var active_inst: PokemonInstance = manager.board_position.get_instance(active_slot)
	if active_inst == null:
		return ActionResult.fail("No Pokémon in active slot.")
	if active_inst.card == null:
		return ActionResult.fail("Active Pokémon has no card data.")
	if active_inst.is_fossil():
		return ActionResult.fail("Fossils cannot retreat.")
	## Balloon Berry: free retreat (discard the tool instead of energy).  When
	## present, energy cost is bypassed entirely.
	var free_retreat: TrainerCardData = ToolEffects.free_retreat_tool(active_inst)
	var effective_cost: int = _effective_retreat_cost(active_inst, manager)
	if free_retreat == null \
			and active_inst.attached_energy.size() < effective_cost:
		return ActionResult.fail(
			"Not enough energy to retreat (need %d, have %d)." % [
				effective_cost, active_inst.attached_energy.size(),
			]
		)
	if active_inst.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP):
		return ActionResult.fail("This Pokémon is Asleep and cannot retreat.")
	if active_inst.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED):
		return ActionResult.fail("This Pokémon is Paralyzed and cannot retreat.")
	if active_inst.retreat_locked_until_turn >= manager.turn_number:
		return ActionResult.fail("This Pokémon is retreat-locked until the end of your opponent's next turn.")

	if not manager.board_position.has_slot(bench_slot):
		return ActionResult.fail("Unknown bench slot '%s'." % bench_slot)
	if manager.board_position.player_of(bench_slot) != player_id:
		return ActionResult.fail("Bench slot does not belong to you.")
	if "bench" not in bench_slot:
		return ActionResult.fail("Must retreat to a bench slot.")
	if manager.board_position.get_instance(bench_slot) == null:
		return ActionResult.fail("No Pokémon in that bench slot.")
	return ActionResult.success()


func apply(manager) -> void:
	var active_inst: PokemonInstance = manager.board_position.get_instance(active_slot)

	## Balloon Berry: discard the tool instead of energy and skip the rest of
	## the energy-cost path entirely.
	var free_retreat: TrainerCardData = ToolEffects.free_retreat_tool(active_inst)
	if free_retreat != null:
		active_inst.attached_tools.erase(free_retreat)
		active_inst.tool_attached_turn.erase(free_retreat)
		manager.game_position.put_in_discard(player_id, free_retreat)
		active_inst.special_conditions.clear()
		active_inst.refresh_visual()
		manager.board_position.swap(active_slot, bench_slot)
		manager.retreat_used_this_turn[player_id] = true
		manager.log_message.emit(
			"[Tool] %s — free retreat (tool discarded)." % free_retreat.display_name
		)
		return

	var cost: int = _effective_retreat_cost(active_inst, manager)

	## When there are more energies than the cost, the player must choose which to discard.
	if cost > 0 and active_inst.attached_energy.size() > cost:
		manager.retreat_active_slot = active_slot
		manager.retreat_bench_slot  = bench_slot
		manager.retreat_player_id   = player_id
		manager.retreat_pending     = true
		manager.retreat_energy_choice_required.emit(
			player_id,
			active_inst.attached_energy.duplicate(),
			cost,
			active_slot
		)
		return

	## Auto-discard when there is no meaningful choice (cost == 0 or exactly enough energy).
	for _i in range(cost):
		if active_inst.attached_energy.is_empty():
			break
		var energy_card: CardData = active_inst.attached_energy[0]
		active_inst.attached_energy.remove_at(0)
		manager.game_position.put_in_discard(player_id, energy_card)

	## Retreating cures all special conditions.
	active_inst.special_conditions.clear()
	active_inst.refresh_visual()

	manager.board_position.swap(active_slot, bench_slot)
	manager.retreat_used_this_turn[player_id] = true


## Returns the energy cost to retreat [inst] after applying stadium discount
## and any Poké-Body override (Vibrava "Levitate", Volbeat "Uplifting Glow").
## Body overrides replace the cost outright; stadium discount applies only
## when no body override fires.
static func _effective_retreat_cost(inst: PokemonInstance, manager) -> int:
	if inst == null or inst.card == null:
		return 0
	var override: int = AbilityEffects.retreat_cost_override(inst, manager)
	if override >= 0:
		return override
	return maxi(0, inst.card.retreat_cost \
			- StadiumEffects.retreat_discount_for(inst.card, manager))


func description() -> String:
	return "P%d retreats %s ↔ %s" % [player_id, active_slot, bench_slot]


func affected_slots() -> Array[String]:
	return [active_slot, bench_slot]
