class_name ActionAttack
extends GameAction
## Declares and resolves an attack from one of the current player's active
## Pokemon onto an opposing active Pokemon.
##
## attacker_slot  — 0-based index of the attacking active slot.
## defender       — the CardInstance being attacked (must be opponent's active).
## attack_index   — index into the attacker's PokemonCardData.attacks array.
##
## AttackResolver handles all damage math (energy affordability, weakness,
## resistance).  This action only moves the damage counter onto the defender
## and flips the has_attacked_this_turn flag.

var attacker_slot: int
var defender: CardInstance
var attack_index: int

## Cached during validate() so description() can print meaningful names.
var _attacker: CardInstance = null


func _init(pid: int, slot: int, target: CardInstance, atk_idx: int) -> void:
	actor_id = pid
	attacker_slot = slot
	defender = target
	attack_index = atk_idx


func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN and state.phase != TurnPhase.Phase.ATTACK:
		return ActionResult.fail("Can only attack during MAIN/ATTACK phase.")

	if state.has_attacked_this_turn:
		return ActionResult.fail("Already attacked this turn.")

	var attacker := state.board.get_active_card(actor_id, attacker_slot)
	if attacker == null:
		return ActionResult.fail("No Pokemon in active slot %d." % attacker_slot)

	if not (attacker.data is PokemonCardData):
		return ActionResult.fail("Attacker is not a Pokemon.")

	_attacker = attacker
	var pdata := attacker.data as PokemonCardData

	if attack_index < 0 or attack_index >= pdata.attacks.size():
		return ActionResult.fail("Invalid attack index %d." % attack_index)

	var attack := pdata.attacks[attack_index]

	if not AttackResolver.can_afford(attacker, attack):
		return ActionResult.fail("Not enough energy to use %s." % attack.name)

	## Paralysis and sleep both prevent attacking.
	if attacker.has_condition(CardInstance.SpecialCondition.PARALYZED):
		return ActionResult.fail("%s is Paralyzed and cannot attack." % pdata.display_name)

	if attacker.has_condition(CardInstance.SpecialCondition.ASLEEP):
		return ActionResult.fail("%s is Asleep and cannot attack." % pdata.display_name)

	if defender == null:
		return ActionResult.fail("No defender specified.")

	if not _defender_is_valid(state):
		return ActionResult.fail("Target is not a valid opposing active Pokemon.")

	return ActionResult.success()


func apply(state: GameState) -> void:
	var attacker := state.board.get_active_card(actor_id, attacker_slot)
	if attacker == null:
		return

	var pdata  := attacker.data as PokemonCardData
	var attack := pdata.attacks[attack_index]
	var opp_id := 1 - actor_id

	## Confusion self-hit: tails (50 % chance) deals 30 damage to the attacker
	## instead of the normal attack.
	if attacker.has_condition(CardInstance.SpecialCondition.CONFUSED):
		if randi() % 2 == 0:  # tails
			attacker.apply_damage(30)
			state.has_attacked_this_turn = true
			return

	## Build effect context and run pre-damage hooks (may set damage_bonus /
	## damage_override on the context).
	var ctx := CardEffectContext.for_attack(
		state, actor_id, attacker, defender, attack, attack_index)
	CardEffectRegistry.dispatch_attack_pre(ctx)

	## Determine the effective base damage.
	var effective_base := ctx.damage_override if ctx.damage_override >= 0 \
		else attack.base_damage + ctx.damage_bonus

	## Apply damage using a temporary AttackData copy that carries the modified
	## base so AttackResolver can still apply Weakness / Resistance on top.
	var modified_attack := attack.duplicate() as AttackData
	modified_attack.base_damage = effective_base

	if attack.hits_each_defending:
		## Spread attack — damage every occupied opponent active slot.
		for slot_idx in range(state.board.num_active_slots):
			var opp := state.board.get_active_card(opp_id, slot_idx)
			if opp != null:
				var dmg := AttackResolver.calculate_damage(attacker, opp, modified_attack)
				opp.apply_damage(dmg)
				ctx.damage_dealt += dmg
	else:
		## Single target attack.
		var dmg := AttackResolver.calculate_damage(attacker, defender, modified_attack)
		defender.apply_damage(dmg)
		ctx.damage_dealt = dmg

	## Run post-damage hooks (secondary effects, energy discard, bench damage…).
	CardEffectRegistry.dispatch_attack_post(ctx)

	state.has_attacked_this_turn = true


func description() -> String:
	if _attacker != null and _attacker.data is PokemonCardData:
		var pdata := _attacker.data as PokemonCardData
		var atk_name := "attack %d" % attack_index
		if attack_index < pdata.attacks.size():
			atk_name = pdata.attacks[attack_index].name
		return "%s uses %s" % [pdata.display_name, atk_name]
	return "Active[%d] uses attack %d" % [attacker_slot, attack_index]


func _defender_is_valid(state: GameState) -> bool:
	var opp_id := 1 - actor_id
	var def_zone := state.board.find_card_location(defender)
	for slot_idx in range(state.board.num_active_slots):
		if def_zone == "p%d_active_%d" % [opp_id, slot_idx]:
			return true
	return false
