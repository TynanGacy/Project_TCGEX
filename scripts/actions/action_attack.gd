class_name ActionAttack
extends GameAction
## Performs one of the attacking Pokémon's attacks against a defending active.
##
## Validation ensures: attacker is in an active slot and not condition-locked;
## the attack's energy cost is fully covered; the target is the opponent's
## active slot.  After damage is dealt, any resulting KO is forwarded to the
## Manager for prize/discard resolution.

var player_id: int = 0
var attacker_slot: String = ""
var attack_index: int = 0
var target_slot: String = ""


func _init(pid: int, atk_slot: String, atk_idx: int, tgt_slot: String) -> void:
	player_id     = pid
	attacker_slot = atk_slot
	attack_index  = atk_idx
	target_slot   = tgt_slot


func validate(manager) -> ActionResult:
	if manager.game_position == null or manager.board_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if manager.attack_used_this_turn[player_id]:
		return ActionResult.fail("You have already attacked this turn.")

	if not manager.board_position.has_slot(attacker_slot):
		return ActionResult.fail("Unknown attacker slot '%s'." % attacker_slot)
	if manager.board_position.player_of(attacker_slot) != player_id:
		return ActionResult.fail("Attacker slot does not belong to you.")
	if "active" not in attacker_slot:
		return ActionResult.fail("Can only attack from an active slot.")
	var attacker: PokemonInstance = manager.board_position.get_instance(attacker_slot)
	if attacker == null:
		return ActionResult.fail("No Pokémon in attacking slot.")
	if attacker.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP):
		return ActionResult.fail("%s is Asleep and cannot attack." % attacker.card.display_name)
	if attacker.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED):
		return ActionResult.fail("%s is Paralyzed and cannot attack." % attacker.card.display_name)
	if attacker.card == null or attack_index < 0 or attack_index >= attacker.card.attacks.size():
		return ActionResult.fail("Invalid attack index %d." % attack_index)

	var energy_result := _check_energy(attacker, attacker.card.attacks[attack_index])
	if not energy_result.ok:
		return energy_result

	var opp_id := 1 - player_id
	if not manager.board_position.has_slot(target_slot):
		return ActionResult.fail("Unknown target slot '%s'." % target_slot)
	if manager.board_position.player_of(target_slot) != opp_id:
		return ActionResult.fail("Target does not belong to your opponent.")
	if "active" not in target_slot:
		return ActionResult.fail("Can only attack an active Pokémon.")
	var target: PokemonInstance = manager.board_position.get_instance(target_slot)
	if target == null:
		return ActionResult.fail("No Pokémon in target slot.")

	return ActionResult.success()


func apply(manager) -> void:
	var attacker: PokemonInstance = manager.board_position.get_instance(attacker_slot)
	var target: PokemonInstance   = manager.board_position.get_instance(target_slot)
	var attack: AttackData        = attacker.card.attacks[attack_index]

	## Build the context that effect handlers operate on.
	var ctx := AttackContext.new()
	ctx.manager       = manager
	ctx.attacker      = attacker
	ctx.target        = target
	ctx.attack        = attack
	ctx.player_id     = player_id
	ctx.attacker_slot = attacker_slot
	ctx.target_slot   = target_slot
	ctx.base_damage   = attack.base_damage
	ctx.bonus_damage  = 0

	## Pre-damage dispatch: handlers may set ctx.bonus_damage (which will be
	## included in the W/R calculation) and/or queue post-actions.
	EffectRegistry.dispatch(attack.effect_key, ctx)

	## Apply weakness and resistance to (base + bonus), then deal damage.
	ctx.final_damage = _compute_damage(ctx.base_damage + ctx.bonus_damage, attacker, target)
	if ctx.final_damage > 0:
		target.apply_damage(ctx.final_damage)

	manager.attack_used_this_turn[player_id] = true

	if target.is_knocked_out():
		manager.resolve_knockout(target_slot, player_id)

	## Post-damage dispatch: status conditions, bench damage, self-heal, etc.
	ctx.run_post_actions()


func description() -> String:
	return "P%d attacks from %s (attack %d) → %s" % [
		player_id, attacker_slot, attack_index, target_slot
	]


func affected_slots() -> Array[String]:
	return [attacker_slot, target_slot]


## --- Energy helpers -----------------------------------------------------------

## Returns ActionResult.fail if [inst] cannot pay [attack]'s cost.
static func _check_energy(inst: PokemonInstance, attack: AttackData) -> ActionResult:
	var counts: Dictionary = {}
	for e: CardData in inst.attached_energy:
		if e is EnergyCardData:
			var t: int = int((e as EnergyCardData).energy_type)
			counts[t] = counts.get(t, 0) + 1

	var specific := _specific_costs(attack)
	for type_int: int in specific:
		var needed: int = specific[type_int]
		var have: int   = counts.get(type_int, 0)
		if have < needed:
			var type_name: String = PokemonCardData.EnergyType.keys()[type_int]
			return ActionResult.fail(
				"Need %d %s energy, have %d." % [needed, type_name, have]
			)
		counts[type_int] = have - needed

	if attack.cost_colorless > 0:
		var remaining: int = 0
		for cnt: int in counts.values():
			remaining += cnt
		if remaining < attack.cost_colorless:
			return ActionResult.fail(
				"Need %d more energy for Colorless cost." % (attack.cost_colorless - remaining)
			)
	return ActionResult.success()


## Returns {EnergyType int -> count} for the typed (non-Colorless) costs.
static func _specific_costs(attack: AttackData) -> Dictionary:
	var d: Dictionary = {}
	if attack.cost_fire      > 0: d[PokemonCardData.EnergyType.FIRE]      = attack.cost_fire
	if attack.cost_water     > 0: d[PokemonCardData.EnergyType.WATER]     = attack.cost_water
	if attack.cost_grass     > 0: d[PokemonCardData.EnergyType.GRASS]     = attack.cost_grass
	if attack.cost_lightning > 0: d[PokemonCardData.EnergyType.LIGHTNING] = attack.cost_lightning
	if attack.cost_psychic   > 0: d[PokemonCardData.EnergyType.PSYCHIC]   = attack.cost_psychic
	if attack.cost_fighting  > 0: d[PokemonCardData.EnergyType.FIGHTING]  = attack.cost_fighting
	if attack.cost_darkness  > 0: d[PokemonCardData.EnergyType.DARKNESS]  = attack.cost_darkness
	if attack.cost_metal     > 0: d[PokemonCardData.EnergyType.METAL]     = attack.cost_metal
	return d


## Applies weakness (×2) and resistance (−30) to base_damage.
static func _compute_damage(base_damage: int, attacker: PokemonInstance, target: PokemonInstance) -> int:
	if base_damage <= 0:
		return 0
	var dmg := base_damage
	if target.card != null and target.card.weakness != PokemonCardData.EnergyType.NONE:
		if attacker.card != null and attacker.card.pokemon_type == target.card.weakness:
			dmg *= 2
	if target.card != null and target.card.resistance != PokemonCardData.EnergyType.NONE:
		if attacker.card != null and attacker.card.pokemon_type == target.card.resistance:
			dmg = maxi(0, dmg - 30)
	return dmg
