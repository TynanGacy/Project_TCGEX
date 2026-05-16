class_name ActionUseAbility
extends GameAction
## Activates a Poké-Power on an in-play Pokémon.  Routes through
## AbilityResolver in the same way ActionPlayItem routes Trainers through
## TrainerResolver.
##
## Poké-Bodies are passive and never trigger this action; they fire from
## static-helper queries inside other actions.

var player_id: int = 0
var source_slot: String = ""
var ability_index: int = 0


func _init(pid: int, slot_id: String, abil_idx: int = 0) -> void:
	player_id    = pid
	source_slot  = slot_id
	ability_index = abil_idx


func validate(manager) -> ActionResult:
	if manager.game_position == null or manager.board_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	## Poké-Powers say "Once during your turn (before your attack)…"; once the
	## player has attacked, powers are locked for the rest of the turn.
	if manager.attack_used_this_turn[player_id]:
		return ActionResult.fail("Poké-Powers can only be used before your attack.")
	if not manager.board_position.has_slot(source_slot):
		return ActionResult.fail("Unknown slot '%s'." % source_slot)
	if manager.board_position.player_of(source_slot) != player_id:
		return ActionResult.fail("Slot does not belong to you.")
	var inst: PokemonInstance = manager.board_position.get_instance(source_slot)
	if inst == null or inst.card == null:
		return ActionResult.fail("No Pokémon in that slot.")
	if inst.is_fossil():
		return ActionResult.fail("Fossils have no abilities.")
	if ability_index < 0 or ability_index >= inst.card.abilities.size():
		return ActionResult.fail("Invalid ability index %d." % ability_index)
	var ability: AbilityData = inst.card.abilities[ability_index]
	## Non-repeatable powers respect the once-per-turn lock.
	if inst.power_used_this_turn and not ability.repeatable:
		return ActionResult.fail("This Pokémon's Poké-Power has already been used this turn.")
	## Conditions that suppress Poké-Powers (classic ruling).
	if inst.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP):
		return ActionResult.fail("%s is Asleep and cannot use Poké-Powers." % inst.card.display_name)
	if inst.special_conditions.has(PokemonInstance.SpecialCondition.CONFUSED):
		return ActionResult.fail("%s is Confused and cannot use Poké-Powers." % inst.card.display_name)
	if inst.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED):
		return ActionResult.fail("%s is Paralyzed and cannot use Poké-Powers." % inst.card.display_name)
	if ability.kind != AbilityData.AbilityKind.POKE_POWER:
		return ActionResult.fail("That ability is a Poké-Body (passive, not activated).")
	var effect_check := AbilityResolver.validate(ability, source_slot, manager, player_id)
	if not effect_check.ok:
		return effect_check
	return ActionResult.success()


func apply(manager) -> void:
	var inst: PokemonInstance = manager.board_position.get_instance(source_slot)
	if inst == null:
		return
	var ability: AbilityData = inst.card.abilities[ability_index]
	## Repeatable powers ("As often as you like…") never consume the
	## once-per-turn flag.
	if not ability.repeatable:
		inst.power_used_this_turn = true
	if manager.ability_resolver != null:
		manager.ability_resolver.dispatch(ability, source_slot, manager, player_id)


func description() -> String:
	return "P%d activates Poké-Power on %s (idx %d)" % [
		player_id, source_slot, ability_index
	]


func affected_slots() -> Array[String]:
	return [source_slot]
