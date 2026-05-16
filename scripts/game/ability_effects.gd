class_name AbilityEffects
## Static helpers that read passive Poké-Body effects from in-play Pokémon and
## apply them at the right game-flow hook.  Parallel to StadiumEffects /
## ToolEffects.
##
## Authoring a new Poké-Body is "register an AbilityEffectDefinition in
## ability_handlers.gd, add a JSON `effect_key` to the relevant card, and
## extend the matching helper here."
##
## All getters accept a manager (ManagerSystem) and read the live game state.
## Helpers that *mutate* state (run_on_damaged_by_attack, run_on_attached_energy,
## run_between_turn_heals) emit pokemon_state_changed / log_message on the
## manager so the UI catches up.

## --- Effect-key constants --------------------------------------------------

const BODY_DAMAGE_REDUCTION                = "body_damage_reduction"
const BODY_DAMAGE_INCREASE_OUTGOING        = "body_damage_increase_outgoing"
const BODY_DAMAGE_TAKEN_AURA_ACTIVE        = "body_damage_taken_aura_active"
const BODY_DAMAGE_REDUCTION_FROM_TYPES     = "body_damage_reduction_from_types"
const BODY_COIN_GATED_REDUCTION            = "body_coin_gated_reduction"
const BODY_STATUS_IMMUNITY                 = "body_status_immunity"
const BODY_RETALIATE_DAMAGE                = "body_retaliate_damage"
const BODY_RETALIATE_STATUS                = "body_retaliate_status"
const BODY_BETWEEN_TURN_HEAL               = "body_between_turn_heal"
const BODY_RETREAT_COST_OVERRIDE           = "body_retreat_cost_override"
const BODY_NATURAL_CURE                    = "body_natural_cure"


## --- Damage modifiers (called from AttackResolver) -------------------------
##
## Pokémon-TCG ability text distinguishes "before applying Weakness and
## Resistance" (Intimidating Fang, Power Pinchers) from "after applying
## Weakness and Resistance" (Exoskeleton, Energy Guard, Glowing Screen).  We
## expose two getters so AttackResolver can apply them at the correct stage.

## Pre-W/R modifier delta applied to [target].  Negative = reduction.  Only
## "aura while active" bodies live here.
static func damage_taken_modifier_before_wr(target: PokemonInstance, manager) -> int:
	if target == null or manager == null:
		return 0
	var total: int = 0
	var pid: int = target.owner_id
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid := "p%d_%s" % [pid, s]
		var active: PokemonInstance = manager.board_position.get_instance(sid)
		if active == null:
			continue
		for abil in _abilities_on(active):
			if abil.effect_key == BODY_DAMAGE_TAKEN_AURA_ACTIVE:
				total -= int(abil.effect_params.get("amount", 0))
	return total


## Post-W/R modifier delta applied to [target] given [attacker]'s type.
## Negative = reduction.  Self bodies and attacker-type-conditional bodies.
static func damage_taken_modifier_after_wr(target: PokemonInstance,
		attacker: PokemonInstance, manager) -> int:
	if target == null or manager == null:
		return 0
	var total: int = 0
	for abil in _abilities_on(target):
		match abil.effect_key:
			BODY_DAMAGE_REDUCTION:
				if _requirement_met(target, abil.effect_params, manager):
					total -= int(abil.effect_params.get("amount", 0))
			BODY_DAMAGE_REDUCTION_FROM_TYPES:
				if attacker != null and attacker.card != null \
						and _attacker_type_matches(attacker, abil.effect_params) \
						and _requirement_met(target, abil.effect_params, manager):
					total -= int(abil.effect_params.get("amount", 0))
	return total


## Pre-W/R modifier added to [attacker]'s outgoing damage by its controller's
## active-position auras (Crawdaunt's Power Pinchers).  Positive = bonus.
static func damage_dealt_modifier_before_wr(attacker: PokemonInstance, manager) -> int:
	if attacker == null or manager == null:
		return 0
	var pid: int = attacker.owner_id
	var total: int = 0
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid := "p%d_%s" % [pid, s]
		var active: PokemonInstance = manager.board_position.get_instance(sid)
		if active == null:
			continue
		for abil in _abilities_on(active):
			if abil.effect_key == BODY_DAMAGE_INCREASE_OUTGOING:
				total += int(abil.effect_params.get("amount", 0))
	return total


## Returns the damage reduction from Pattern-B coin-gated Poké-Bodies (Sand
## Guard, Hard Cocoon).  Resolves the coin flip inline and emits the standard
## coin_flipped signal so the UI animates it.  Returns 0 if the body's
## constraint isn't met (e.g. Hard Cocoon requires the defender's controller
## to NOT be the current player) or the coin came up tails.
static func coin_gated_reduction_for_target(target: PokemonInstance, manager) -> int:
	if target == null or manager == null:
		return 0
	var total: int = 0
	for abil in _abilities_on(target):
		if abil.effect_key != BODY_COIN_GATED_REDUCTION:
			continue
		var params: Dictionary = abil.effect_params
		## Hard Cocoon only fires during opponent's turn (the "during your
		## opponent's turn" clause); Sand Guard fires whenever attacked.
		if bool(params.get("opponent_turn_only", false)) \
				and manager.current_player == target.owner_id:
			continue
		if manager.flip_coin("%s — %s" % [target.card.display_name, abil.ability_name]):
			total += int(params.get("amount", 20))
	return total


## --- Status immunity (called from PokemonInstance.add_condition) -----------

## Returns true if [inst]'s Poké-Bodies prevent it from gaining [condition].
## Pattern D handler. Fossils already short-circuit add_condition() — this
## hook is for non-fossil immunity (Roselia, Zangoose, etc.).
static func blocks_condition(inst: PokemonInstance, condition: int) -> bool:
	if inst == null:
		return false
	for abil in _abilities_on(inst):
		if abil.effect_key != BODY_STATUS_IMMUNITY:
			continue
		var blocked: Array = abil.effect_params.get("conditions", [])
		## "all" sentinel covers Thick Skin-style total immunity.
		if blocked.has("ALL"):
			return true
		var name: String = PokemonInstance.SpecialCondition.keys()[condition]
		if blocked.has(name):
			return true
	return false


## --- Retaliation (called from AttackResolver after damage is applied) ------

## Fires Pattern E retaliation Poké-Bodies on [target] in response to [target]
## taking damage from [attacker]'s attack.  Applies damage counters and/or
## conditions back to the attacker.  Caller passes [target_slot] so we can
## emit pokemon_state_changed for both sides.
static func run_on_damaged_by_attack(target: PokemonInstance, target_slot: String,
		attacker: PokemonInstance, attacker_slot: String, manager) -> void:
	if target == null or attacker == null or manager == null:
		return
	## Retaliation only fires when the target is in active.  ("If X is your
	## Active Pokémon and is damaged by an opponent's attack…")
	if not _is_active_slot(target_slot):
		return
	for abil in _abilities_on(target):
		match abil.effect_key:
			BODY_RETALIATE_DAMAGE:
				var counters: int = int(abil.effect_params.get("counters", 1))
				attacker.apply_damage(counters * 10)
				manager.pokemon_state_changed.emit(attacker_slot, attacker)
				manager.log_message.emit(
					"[Body] %s — %s puts %d damage counter%s on %s." % [
						abil.ability_name, target.card.display_name,
						counters, "" if counters == 1 else "s",
						attacker.card.display_name,
					]
				)
			BODY_RETALIATE_STATUS:
				var cond_name: String = str(abil.effect_params.get("condition", ""))
				var cond := _condition_from_name(cond_name)
				if cond < 0:
					continue
				attacker.add_condition(cond)
				manager.pokemon_state_changed.emit(attacker_slot, attacker)
				manager.log_message.emit(
					"[Body] %s — %s applies %s to %s." % [
						abil.ability_name, target.card.display_name,
						cond_name, attacker.card.display_name,
					]
				)


## --- Between-turn heal (Pattern F) ----------------------------------------

## Heals 10 HP per "remove 1 damage counter" Poké-Body on [inst].  Called from
## ManagerSystem._cleanup_instance_async after condition damage applies.
static func run_between_turn_heals(inst: PokemonInstance, slot_id: String,
		manager) -> void:
	if inst == null or inst.is_knocked_out():
		return
	for abil in _abilities_on(inst):
		if abil.effect_key != BODY_BETWEEN_TURN_HEAL:
			continue
		var counters: int = int(abil.effect_params.get("counters", 1))
		var heal_hp: int = counters * 10
		var missing: int = inst.max_hp - inst.current_hp
		if missing <= 0:
			continue
		inst.heal(mini(heal_hp, missing))
		manager.pokemon_state_changed.emit(slot_id, inst)
		manager.log_message.emit(
			"[Body] %s — %s heals %d HP." % [
				abil.ability_name, inst.card.display_name,
				mini(heal_hp, missing),
			]
		)


## --- Retreat cost override (Pattern G) ------------------------------------

## Returns the override retreat cost imposed by Poké-Bodies on [inst], or -1
## if no body overrides the cost.  Used by ActionRetreat: when this returns
## a non-negative value, that value replaces the card's retreat_cost entirely.
static func retreat_cost_override(inst: PokemonInstance, manager) -> int:
	if inst == null:
		return -1
	for abil in _abilities_on(inst):
		if abil.effect_key != BODY_RETREAT_COST_OVERRIDE:
			continue
		if _requirement_met(inst, abil.effect_params, manager):
			return int(abil.effect_params.get("amount", 0))
	return -1


## --- Energy-attach trigger (Pattern J, Natural Cure) ----------------------

## Called from ActionAttachEnergy.apply() AFTER the energy is attached.  Fires
## any Poké-Body whose trigger matches the just-attached energy.
static func run_on_attached_energy(inst: PokemonInstance, slot_id: String,
		energy: EnergyCardData, manager) -> void:
	if inst == null or energy == null or manager == null:
		return
	for abil in _abilities_on(inst):
		if abil.effect_key != BODY_NATURAL_CURE:
			continue
		var want: String = str(abil.effect_params.get("required_type", ""))
		var got: String = PokemonCardData.EnergyType.keys()[int(energy.energy_type)]
		if want != "" and want != got:
			continue
		if inst.special_conditions.is_empty():
			continue
		inst.special_conditions.clear()
		inst.refresh_visual()
		manager.pokemon_state_changed.emit(slot_id, inst)
		manager.log_message.emit(
			"[Body] %s — %s cleared all conditions." % [
				abil.ability_name, inst.card.display_name,
			]
		)


## --- Internal helpers ------------------------------------------------------

static func _abilities_on(inst: PokemonInstance) -> Array:
	if inst == null or inst.card == null or inst.card.abilities == null:
		return []
	return inst.card.abilities


static func _is_active_slot(slot_id: String) -> bool:
	return "active" in slot_id


## Returns the SpecialCondition enum value for [name] (case-insensitive),
## or -1 if unknown.
static func _condition_from_name(name: String) -> int:
	var keys: Array = PokemonInstance.SpecialCondition.keys()
	var idx: int = keys.find(name.to_upper())
	return idx if idx >= 0 else -1


## Returns true if the body's requirement clause is satisfied.  Schema:
##   params.requires == "has_basic_energy"   → at least 1 basic energy attached
##   params.requires == "partner_in_play"    → params.partner_slug is in play
##                                              on the same side as [inst]
##   missing/empty → always true
static func _requirement_met(inst: PokemonInstance, params: Dictionary,
		manager) -> bool:
	var req: String = str(params.get("requires", ""))
	if req == "":
		return true
	if req == "has_basic_energy":
		for e in inst.attached_energy:
			if e is EnergyCardData and _is_basic_energy(e as EnergyCardData):
				return true
		return false
	if req == "partner_in_play":
		var slug: String = str(params.get("partner_slug", ""))
		if slug == "" or manager == null:
			return false
		for s in BoardPosition.all_slot_ids(inst.owner_id):
			var other: PokemonInstance = manager.board_position.get_instance(s)
			if other != null and other.card != null \
					and other.card.name_slug == slug:
				return true
		return false
	return true


static func _is_basic_energy(e: EnergyCardData) -> bool:
	## Rainbow / Multi are auto-classified to COLORLESS with extra_types
	## populated; treat them as non-basic for the Energy Guard rule.
	var cid := e.card_id.to_lower()
	if cid.contains("rainbow") or cid.contains("multi"):
		return false
	return true


static func _attacker_type_matches(attacker: PokemonInstance, params: Dictionary) -> bool:
	var types: Array = params.get("source_types", [])
	if types.is_empty():
		return true
	var atype: String = PokemonCardData.EnergyType.keys()[int(attacker.card.pokemon_type)]
	for t in types:
		if str(t) == atype:
			return true
	return false
