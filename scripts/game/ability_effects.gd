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

## Wave 2 patterns.
const BODY_GLOBAL_RESISTANCE_DISABLE       = "body_global_resistance_disable"
const BODY_SOURCE_IMMUNITY                 = "body_source_immunity"
const BODY_BENCH_DAMAGE_IMMUNITY           = "body_bench_damage_immunity"
const BODY_TYPE_MORPH_FROM_ENERGY          = "body_type_morph_from_energy"
const BODY_OPPONENT_PLAY_LOCK              = "body_opponent_play_lock"
const BODY_ATTACK_EFFECT_IMMUNITY_SELF     = "body_attack_effect_immunity_self"

## Wave 3 patterns (ability suppression).
const BODY_SUPPRESS_OPPONENT_POWERS        = "body_suppress_opponent_powers"
const BODY_SUPPRESS_ALL_POWERS_AND_BODIES  = "body_suppress_all_powers_and_bodies"

## Wave 4 patterns (Poké-Power wave 2).
const BODY_DAMAGE_ON_OPPONENT_ENERGY_ATTACH = "body_damage_on_opponent_energy_attach"
const POWER_SEARCH_DECK_PLAY_SPECIFIC_BASIC = "power_search_deck_play_specific_basic"
const POWER_REUSE_LAST_ATTACK              = "power_reuse_last_attack"

## Wave 5 (Baby Evolution).
const POWER_BABY_EVOLUTION                 = "power_baby_evolution"

## Wave 6 (Wave 3A + 3B in the plan — bodies + type-override power).
const BODY_HEAL_ON_MATCHING_ENERGY_ATTACH  = "body_heal_on_matching_energy_attach"
const BODY_OPPONENT_RETREAT_LOCK           = "body_opponent_retreat_lock"
const POWER_TYPE_OVERRIDE_UNTIL_TURN_END   = "power_type_override_until_turn_end"


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
		for abil in _abilities_on(active, manager):
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
	for abil in _abilities_on(target, manager):
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
		for abil in _abilities_on(active, manager):
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
	for abil in _abilities_on(target, manager):
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
	for abil in _abilities_on(target, manager):
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
	for abil in _abilities_on(inst, manager):
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
	for abil in _abilities_on(inst, manager):
		if abil.effect_key != BODY_RETREAT_COST_OVERRIDE:
			continue
		if _requirement_met(inst, abil.effect_params, manager):
			return int(abil.effect_params.get("amount", 0))
	return -1


## --- Energy-attach trigger (Pattern J, Natural Cure) ----------------------

## Called from ActionAttachEnergy.apply() AFTER the energy is attached.  Fires
## any Poké-Body whose trigger matches the just-attached energy.
##
## Recognised bodies:
##   BODY_NATURAL_CURE — clears all special conditions if matching type
##     (params: {required_type})
##   BODY_HEAL_ON_MATCHING_ENERGY_ATTACH — removes N damage counters if
##     matching type (params: {required_type, counters})
static func run_on_attached_energy(inst: PokemonInstance, slot_id: String,
		energy: EnergyCardData, manager) -> void:
	if inst == null or energy == null or manager == null:
		return
	for abil in _abilities_on(inst, manager):
		var want: String = str(abil.effect_params.get("required_type", ""))
		var got: String = PokemonCardData.EnergyType.keys()[int(energy.energy_type)]
		if want != "" and want != got:
			continue
		match abil.effect_key:
			BODY_NATURAL_CURE:
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
			BODY_HEAL_ON_MATCHING_ENERGY_ATTACH:
				var counters: int = int(abil.effect_params.get("counters", 1))
				var heal_hp: int = counters * 10
				var missing: int = inst.max_hp - inst.current_hp
				if missing <= 0:
					continue
				inst.heal(mini(heal_hp, missing))
				manager.pokemon_state_changed.emit(slot_id, inst)
				manager.log_message.emit(
					"[Body] %s — %s healed %d HP." % [
						abil.ability_name, inst.card.display_name,
						mini(heal_hp, missing),
					]
				)


## --- Wave 4: Loose Shell (Ninjask) -----------------------------------------

## Called from ActionEvolve.apply() after the evolution swap.  Fires any
## POWER_SEARCH_DECK_PLAY_SPECIFIC_BASIC powers on the new top card.  Params:
##   {"target_slug": "shedinja"}
##
## v1 limitation: auto-accepts the "may" clause and auto-picks the first
## matching basic in the deck.  Sufficient for the only printed user
## (Ninjask), but a future revision should surface a Yes/No + chooser prompt.
static func run_on_evolve(inst: PokemonInstance, slot_id: String, manager) -> void:
	if inst == null or manager == null or inst.card == null:
		return
	for abil in _abilities_on(inst, manager):
		if abil.effect_key != POWER_SEARCH_DECK_PLAY_SPECIFIC_BASIC:
			continue
		var slug: String = str(abil.effect_params.get("target_slug", ""))
		if slug == "":
			continue
		var pid: int = inst.owner_id
		var bench_slot: String = manager.board_position.first_empty_bench(pid)
		if bench_slot == "":
			continue
		var deck: Array = manager.game_position.decks[pid]
		var found: PokemonCardData = null
		for c in deck:
			if c is PokemonCardData and (c as PokemonCardData).name_slug == slug \
					and (c as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
				found = c
				break
		if found == null:
			manager.log_message.emit(
				"[Power] %s — no %s in deck." % [abil.ability_name, slug.capitalize()]
			)
			continue
		manager.game_position.take_from_deck(pid, found)
		var new_inst := PokemonInstance.create(found, pid)
		manager.board_position.place(bench_slot, new_inst)
		manager.game_position.shuffle_deck(pid)
		manager.pokemon_state_changed.emit(bench_slot, new_inst)
		manager.log_message.emit(
			"[Power] %s — placed %s on Bench from deck." % [
				abil.ability_name, found.display_name,
			]
		)


## --- Wave 4: Conductivity (Ampharos ex) ------------------------------------

## Called from ActionAttachEnergy.apply() after the energy is on the target.
## Places 1 damage counter on [target_inst] if [target_inst]'s controller is
## the opponent of any Ampharos ex carrying Conductivity in play.  Per the
## printed rule, only one counter is placed even with multiple Ampharos ex.
static func run_on_opponent_energy_attach(target_inst: PokemonInstance,
		target_slot: String, manager) -> void:
	if target_inst == null or manager == null:
		return
	if target_inst.source_trainer_card != null:
		return  ## Fossils ignore damage triggers.
	var attacher_pid: int = target_inst.owner_id
	var opp := 1 - attacher_pid
	for s in (BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS):
		var sid := "p%d_%s" % [opp, s]
		var inst: PokemonInstance = manager.board_position.get_instance(sid)
		if inst == null:
			continue
		for abil in _abilities_on(inst, manager):
			if abil.effect_key == BODY_DAMAGE_ON_OPPONENT_ENERGY_ATTACH:
				target_inst.apply_damage(10)
				manager.pokemon_state_changed.emit(target_slot, target_inst)
				manager.log_message.emit(
					"[Body] %s — 1 damage counter to %s." % [
						abil.ability_name,
						target_inst.card.display_name if target_inst.card else "target",
					]
				)
				return  ## Only one counter total even with multiple carriers.


## --- Internal helpers ------------------------------------------------------

## Returns the ability list on [inst].  When a [manager] is provided, the
## list is filtered through is_body_suppressed so Muk ex "Toxic Gas" hides
## every other carrier's bodies while it's Active.  Callers without manager
## access (e.g. PokemonInstance.add_condition's blocks_condition gate) get
## the raw list — a known but narrow gap.
static func _abilities_on(inst: PokemonInstance, manager = null) -> Array:
	if inst == null or inst.card == null or inst.card.abilities == null:
		return []
	if manager != null and is_body_suppressed(inst, manager):
		return []
	return inst.card.abilities


## Returns true when activated-power dispatch for [carrier_inst] should be
## blocked by an in-play suppression body (Slaking "Lazy" for opp powers,
## Muk ex "Toxic Gas" for all powers on the board).
static func is_power_suppressed(carrier_inst: PokemonInstance, manager) -> bool:
	if carrier_inst == null or manager == null:
		return false
	## Toxic Gas: any active Muk ex on either side suppresses everyone
	## except its own carrier.
	for pid in [0, 1]:
		for s in BoardPosition.ACTIVE_SLOTS:
			var sid := "p%d_%s" % [pid, s]
			var inst: PokemonInstance = manager.board_position.get_instance(sid)
			if inst == null or inst == carrier_inst:
				continue
			if _has_effect_key(inst, BODY_SUPPRESS_ALL_POWERS_AND_BODIES):
				return true
	## Lazy: opponent's active Slaking suppresses my powers.
	var opp := 1 - carrier_inst.owner_id
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid := "p%d_%s" % [opp, s]
		var inst: PokemonInstance = manager.board_position.get_instance(sid)
		if inst == null:
			continue
		if _has_effect_key(inst, BODY_SUPPRESS_OPPONENT_POWERS):
			return true
	return false


## Returns true when [carrier_inst]'s passive bodies should be ignored due
## to Toxic Gas active on the board.  The carrier itself is exempt so Muk
## ex's own Toxic Gas keeps suppressing while it's the carrier.
static func is_body_suppressed(carrier_inst: PokemonInstance, manager) -> bool:
	if carrier_inst == null or manager == null:
		return false
	for pid in [0, 1]:
		for s in BoardPosition.ACTIVE_SLOTS:
			var sid := "p%d_%s" % [pid, s]
			var inst: PokemonInstance = manager.board_position.get_instance(sid)
			if inst == null or inst == carrier_inst:
				continue
			if _has_effect_key(inst, BODY_SUPPRESS_ALL_POWERS_AND_BODIES):
				return true
	return false


static func _has_effect_key(inst: PokemonInstance, key: String) -> bool:
	if inst == null or inst.card == null or inst.card.abilities == null:
		return false
	for abil in inst.card.abilities:
		if abil != null and abil.effect_key == key:
			return true
	return false


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


## --- Wave 2: Withering Dust (Beautifly) ------------------------------------

## Returns true when any Pokémon with the BODY_GLOBAL_RESISTANCE_DISABLE
## effect_key is currently in play on either side (active or bench).  While
## this is the case, _compute_damage should treat skip_resistance as true.
## Beautifly's Withering Dust reads "as long as Beautifly is in play", so
## we scan every slot, not just actives.
static func global_resistance_disabled(manager) -> bool:
	if manager == null:
		return false
	for pid in [0, 1]:
		for s in (BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS):
			var sid := "p%d_%s" % [pid, s]
			var inst: PokemonInstance = manager.board_position.get_instance(sid)
			if inst == null:
				continue
			for abil in _abilities_on(inst, manager):
				if abil.effect_key == BODY_GLOBAL_RESISTANCE_DISABLE:
					return true
	return false


## --- Wave 2: Wonder Guard / Safeguard --------------------------------------

## Returns true if [target]'s Poké-Body provides total immunity (damage AND
## post-damage effects) from [attacker]'s attack.  Schema:
##   params.from: Array of source-class strings to match. Recognised:
##     "EVOLUTION" — attacker.card.stage != BASIC
##     "POKEMON_EX" — attacker is a Pokémon-ex
##     "BASIC"     — attacker.card.stage == BASIC
## Any match → immunity applies.
static func attack_blocked_by_source_immunity(target: PokemonInstance,
		attacker: PokemonInstance, manager = null) -> bool:
	if target == null or attacker == null or attacker.card == null:
		return false
	for abil in _abilities_on(target, manager):
		if abil.effect_key != BODY_SOURCE_IMMUNITY:
			continue
		var sources: Array = abil.effect_params.get("from", [])
		for s in sources:
			match str(s).to_upper():
				"EVOLUTION":
					if attacker.card.stage != PokemonCardData.Stage.BASIC:
						return true
				"BASIC":
					if attacker.card.stage == PokemonCardData.Stage.BASIC:
						return true
				"POKEMON_EX":
					if is_pokemon_ex(attacker.card):
						return true
	return false


## True if [card]'s card_id has the "_ex" suffix used by Pokémon-ex prints.
## Centralised here so other systems (Phase 3 suppression, Phase 4 Conductivity)
## can reuse it without duplicating the slug rule.
static func is_pokemon_ex(card: PokemonCardData) -> bool:
	if card == null:
		return false
	return String(card.card_id).to_lower().ends_with("_ex")


## --- Wave 2: Submerge ------------------------------------------------------

## Returns true if [target]'s Poké-Body should zero out incoming damage at
## [slot_id] because the carrier is currently benched (Whiscash's "Submerge"
## reads "while it is Benched", which only matters on bench slots).
static func bench_damage_blocked(target: PokemonInstance, slot_id: String,
		manager = null) -> bool:
	if target == null:
		return false
	if "bench" not in slot_id:
		return false
	for abil in _abilities_on(target, manager):
		if abil.effect_key == BODY_BENCH_DAMAGE_IMMUNITY:
			return true
	return false


## --- Wave 2: Protective Dust (Dustox) --------------------------------------

## Returns true if [target] has a Poké-Body that prevents post-damage attack
## effects (status, energy discard, etc.) from landing on it.  Damage still
## applies — the resolver checks this flag between the damage step and the
## effect-execution / post-action steps.
##
## Limitation: this implementation broadly skips the whole effect queue when
## set, which over-blocks edge-case attacks that distribute effects to other
## slots (e.g. bench AoE riders).  None of the printed roster's
## Protective-Dust-relevant attacks in the current pool exercise that case;
## revisit if a future card requires per-effect target awareness.
static func defender_blocks_attack_effects(target: PokemonInstance,
		manager = null) -> bool:
	if target == null:
		return false
	for abil in _abilities_on(target, manager):
		if abil.effect_key == BODY_ATTACK_EFFECT_IMMUNITY_SELF:
			return true
	return false


## --- Wave 2: Energy Variation (type morph) ---------------------------------

## Returns the EnergyType to use for in-battle calculations.  Kecleon's
## "Energy Variation" sets its type to the type of the basic Energy attached
## (or Colorless if none / multiple types are attached).  Other Pokémon
## return their printed pokemon_type unchanged.  Used by AttackResolver's
## W/R compute and the Darkness/Metal energy gates.
static func effective_pokemon_type(inst: PokemonInstance, manager = null) -> int:
	if inst == null or inst.card == null:
		return int(PokemonCardData.EnergyType.NONE)
	## Until-end-of-turn type override (Solrock "Solar Eclipse",
	## Lunatone "Lunar Eclipse").  Resolves before Kecleon's Energy Variation
	## so a Pokémon affected by both falls back to its overridden type.
	if manager != null \
			and inst.type_override_until_turn != -1 \
			and manager.turn_number <= inst.type_override_until_turn:
		return inst.type_override_value
	for abil in _abilities_on(inst, manager):
		if abil.effect_key != BODY_TYPE_MORPH_FROM_ENERGY:
			continue
		## Kecleon: type = the single basic-energy type attached, else Colorless.
		var observed := -1
		for e in inst.attached_energy:
			if not (e is EnergyCardData):
				continue
			if not _is_basic_energy(e as EnergyCardData):
				continue
			var t: int = int((e as EnergyCardData).energy_type)
			if observed == -1:
				observed = t
			elif observed != t:
				return int(PokemonCardData.EnergyType.COLORLESS)
		return observed if observed != -1 else int(PokemonCardData.EnergyType.COLORLESS)
	return int(inst.card.pokemon_type)


## --- Wave 2: Primal Lock (Aerodactyl ex) -----------------------------------

## Returns true when a Pokémon in play carries a BODY_OPPONENT_PLAY_LOCK
## body whose params block [card_kind] for [player_id].
##
## Per-ability schema:
##   block               — Array of card kinds: "POKEMON_TOOL", "SUPPORTER", …
##   scope               — "opponent" (default) blocks only opponent;
##                         "both" blocks every player including the carrier's.
##   carrier_position    — "in_play" (default) carrier active or benched;
##                         "active" carrier must be in active slot to fire.
##
## Cards: Aerodactyl ex "Primal Lock" (default scope, in_play),
##         Armaldo "Primal Veil" (scope=both, carrier_position=active).
static func play_locked_for_player(manager, player_id: int, card_kind: String) -> bool:
	if manager == null:
		return false
	for src_pid in [0, 1]:
		for s in (BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS):
			var sid := "p%d_%s" % [src_pid, s]
			var inst: PokemonInstance = manager.board_position.get_instance(sid)
			if inst == null:
				continue
			for abil in _abilities_on(inst, manager):
				if abil.effect_key != BODY_OPPONENT_PLAY_LOCK:
					continue
				var blocked: Array = abil.effect_params.get("block", [])
				if not blocked.has(card_kind):
					continue
				var scope: String = str(abil.effect_params.get("scope", "opponent"))
				if scope == "opponent" and src_pid == player_id:
					continue
				var carrier_position: String = str(abil.effect_params.get(
					"carrier_position", "in_play"))
				if carrier_position == "active" and "active" not in sid:
					continue
				return true
	return false


## Returns true when an opponent's Active carries a BODY_OPPONENT_RETREAT_LOCK
## body. Cradily's "Super Suction Cups" prevents retreat while it is the
## opponent's Active Pokémon.
static func opp_retreat_locked_for(retreating_inst: PokemonInstance,
		manager) -> bool:
	if retreating_inst == null or manager == null:
		return false
	var opp := 1 - retreating_inst.owner_id
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid := "p%d_%s" % [opp, s]
		var inst: PokemonInstance = manager.board_position.get_instance(sid)
		if inst == null:
			continue
		for abil in _abilities_on(inst, manager):
			if abil.effect_key == BODY_OPPONENT_RETREAT_LOCK:
				return true
	return false
