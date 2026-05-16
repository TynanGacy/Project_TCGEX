class_name ActionAttachEnergy
extends GameAction
## Attaches an Energy card from hand to one of the player's in-play Pokemon.
##
## Classic rule: at most one energy attachment per turn.  The Manager owns the
## per-turn energy_attached_this_turn flag; the turn system clears it each
## turn via _reset_turn_flags().

var player_id: int = 0
var card: EnergyCardData = null
var target_slot: String = ""


func _init(pid: int, energy_card: EnergyCardData, slot_id: String) -> void:
	player_id   = pid
	card        = energy_card
	target_slot = slot_id


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No energy card specified.")
	if manager.game_position == null or manager.board_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if not (manager.game_position.hands[player_id] as Array).has(card):
		return ActionResult.fail("Energy is not in your hand.")
	if not manager.board_position.has_slot(target_slot):
		return ActionResult.fail("Unknown slot '%s'." % target_slot)
	if manager.board_position.player_of(target_slot) != player_id:
		return ActionResult.fail("Slot does not belong to you.")
	var inst: PokemonInstance = manager.board_position.get_instance(target_slot)
	if inst == null:
		return ActionResult.fail("No Pokemon in that slot to attach to.")
	if manager.energy_attached_this_turn[player_id]:
		return ActionResult.fail("You have already attached an energy this turn.")
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	var inst: PokemonInstance = manager.board_position.get_instance(target_slot)
	inst.attach_energy(card)
	manager.energy_attached_this_turn[player_id] = true
	## Poké-Body energy-attach triggers (Combusken/Grovyle/Marshtomp "Natural
	## Cure"). Fires only when the just-attached energy matches the body's
	## required_type.
	AbilityEffects.run_on_attached_energy(inst, target_slot, card, manager)
	## Special energy on-attach effects (Rainbow Energy places 1 damage
	## counter on the receiving Pokémon). Runs after Natural Cure so a
	## status clear can't be pre-empted by the self-damage.
	SpecialEnergyEffects.run_on_attach(inst, card, manager)
	## Wave 4 — Ampharos ex "Conductivity": opponent attaching energy places
	## a damage counter on the receiving Pokémon.  Fires after the special-
	## energy trigger so Rainbow's self-damage doesn't compound oddly.
	AbilityEffects.run_on_opponent_energy_attach(inst, target_slot, manager)


func description() -> String:
	var name := card.display_name if card != null else "Energy"
	return "P%d attaches %s to %s" % [player_id, name, target_slot]


func affected_slots() -> Array[String]:
	return [target_slot]
