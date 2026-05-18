class_name OpponentAI
extends RefCounted
## Heuristic CPU opponent.  Decides one main-phase action at a time by
## enumerating candidate actions, filtering to those that pass validate(),
## and picking by priority (active first, then bench, energy, attack).
##
## Phase A scope: priority-ordered heuristics; no trainer/item play, no
## evolution, no ability use, no retreat.  Phase B will add scoring +
## the missing action types.
##
## Every public method returns null on failure (no legal action) rather
## than raising; the driver treats null as "end turn".

const MAX_BENCH_FILL: int = 3


## Returns the next action the CPU should take, or null if it should end the
## turn.  Caller is responsible for actually submitting via request_action.
func decide_action(manager, pid: int) -> GameAction:
	if manager == null:
		return null
	if not manager.is_main_phase_for(pid):
		return null

	## 1. No active Pokémon — must play one.  This is rare mid-game (engine
	##    auto-promotes on KO when there's a unique option) but guard for it.
	var active_action: GameAction = _try_play_basic_to_first_empty_active(manager, pid)
	if active_action != null:
		return active_action

	## 1b. Play a Trainer card if any legal one is in hand.  Trainers (search,
	## draw, switch, etc.) often set up later steps, so they fire before the
	## bench/evolve/attach decisions.  Phase B2 is "play any legal trainer";
	## smart guards (Potion-only-when-damaged, etc.) land with Phase B3 scoring.
	var trainer_action: GameAction = _try_play_trainer(manager, pid)
	if trainer_action != null:
		return trainer_action

	## 2. Fill bench up to MAX_BENCH_FILL with basics from hand.
	var bench_action: GameAction = _try_play_basic_to_bench(manager, pid)
	if bench_action != null:
		return bench_action

	## 2b. Evolve any in-play Pokemon whose evolution is in hand.  ActionEvolve
	## handles the same-turn / first-turn restrictions in its validate(); we
	## just enumerate candidates and submit the first legal one.
	var evolve_action: GameAction = _try_evolve(manager, pid)
	if evolve_action != null:
		return evolve_action

	## 2c. Use an active Poké-Power on any in-play Pokemon.  Sits after evolve
	## so Stage 1/2 powers (Delcatty Energy Draw, Magneton Magnetic Force, …)
	## can fire on the same turn they evolve, before we lock in energy/attack
	## choices.  ActionUseAbility.validate() enforces "active before attack",
	## once-per-turn locks, status suppression (asleep/confused/paralyzed),
	## POKE_POWER-vs-POKE_BODY gating, and per-effect viability via
	## AbilityResolver.validate, so we just submit the first one that passes.
	var ability_action: GameAction = _try_use_ability(manager, pid)
	if ability_action != null:
		return ability_action

	## 3. Attach one energy (once per turn) — prefer the active's needed type.
	if not manager.energy_attached_this_turn[pid]:
		var energy_action: GameAction = _try_attach_energy(manager, pid)
		if energy_action != null:
			return energy_action

	## 4. Attack if any of the active's attacks is fully paid + legal.
	if not manager.attack_used_this_turn[pid]:
		var attack_action: GameAction = _try_attack(manager, pid)
		if attack_action != null:
			return attack_action

	## 5. Nothing useful to do — fall through to end turn.
	return null


## --- 1. Place first basic into the empty active slot -------------------------

func _try_play_basic_to_first_empty_active(manager, pid: int) -> GameAction:
	for i in range(1, manager.active_slot_count + 1):
		var slot := "p%d_active%d" % [pid, i]
		if manager.board_position.get_instance(slot) != null:
			continue
		var basic: PokemonCardData = _first_basic_in_hand(manager, pid)
		if basic == null:
			return null
		var action := ActionPlayPokemon.new(pid, basic, slot)
		if action.validate(manager).ok:
			return action
	return null


## --- 1b. Play a Trainer card if any legal one is in hand --------------------
##
## Iterates the hand left-to-right and returns the first trainer whose
## validate() passes.  Phase B2 has no "is this play worthwhile?" guard —
## the engine validators block obvious illegal cases (supporter-once-per-turn,
## tool-on-already-tooled, etc.), but a card that's *legal but wasteful*
## (e.g. Potion on a full-HP Pokemon) will still fire.  Phase B3 scoring
## will add those nuances.

func _try_play_trainer(manager, pid: int) -> GameAction:
	for card: CardData in manager.game_position.hands[pid] as Array:
		if not (card is TrainerCardData):
			continue
		var tc := card as TrainerCardData

		## Fossils play as Pokemon onto a bench slot.
		if tc.plays_as_pokemon:
			var fossil_action: GameAction = _build_fossil_action(manager, pid, tc)
			if fossil_action != null:
				return fossil_action
			continue

		match tc.trainer_kind:
			TrainerCardData.TrainerKind.ITEM:
				var action := ActionPlayItem.new(pid, tc)
				if action.validate(manager).ok:
					return action
			TrainerCardData.TrainerKind.SUPPORTER:
				var action := ActionPlaySupporter.new(pid, tc)
				if action.validate(manager).ok:
					return action
			TrainerCardData.TrainerKind.STADIUM:
				var action := ActionPlayStadium.new(pid, tc)
				if action.validate(manager).ok:
					return action
			TrainerCardData.TrainerKind.TOOL:
				var tool_action: GameAction = _build_tool_action(manager, pid, tc)
				if tool_action != null:
					return tool_action
	return null


func _build_fossil_action(manager, pid: int, tc: TrainerCardData) -> GameAction:
	for i in range(1, manager.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [pid, i]
		if not manager.board_position.is_empty(slot):
			continue
		var action := ActionPlayFossil.new(pid, tc, slot)
		if action.validate(manager).ok:
			return action
	return null


func _build_tool_action(manager, pid: int, tc: TrainerCardData) -> GameAction:
	## Iterate own actives + bench; attach to the first slot whose Pokemon has
	## no Tool yet.  Active first so a tool that buffs the attacker lands where
	## it matters.
	for i in range(1, manager.active_slot_count + 1):
		var slot := "p%d_active%d" % [pid, i]
		var action := ActionAttachTool.new(pid, tc, slot)
		if action.validate(manager).ok:
			return action
	for i in range(1, manager.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [pid, i]
		var action := ActionAttachTool.new(pid, tc, slot)
		if action.validate(manager).ok:
			return action
	return null


## --- 2. Fill bench up to MAX_BENCH_FILL --------------------------------------

func _try_play_basic_to_bench(manager, pid: int) -> GameAction:
	var bench_filled: int = 0
	for i in range(1, manager.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [pid, i]
		if manager.board_position.get_instance(slot) != null:
			bench_filled += 1
	if bench_filled >= MAX_BENCH_FILL:
		return null

	var basic: PokemonCardData = _first_basic_in_hand(manager, pid)
	if basic == null:
		return null
	for i in range(1, manager.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [pid, i]
		if manager.board_position.get_instance(slot) != null:
			continue
		var action := ActionPlayPokemon.new(pid, basic, slot)
		if action.validate(manager).ok:
			return action
	return null


## --- 2b. Evolve in-play Pokemon ----------------------------------------------

func _try_evolve(manager, pid: int) -> GameAction:
	var evolutions: Array[PokemonCardData] = []
	for card: CardData in manager.game_position.hands[pid] as Array:
		if card is PokemonCardData \
				and (card as PokemonCardData).stage != PokemonCardData.Stage.BASIC:
			evolutions.append(card)
	if evolutions.is_empty():
		return null

	var slots: Array[String] = []
	for i in range(1, manager.active_slot_count + 1):
		slots.append("p%d_active%d" % [pid, i])
	for i in range(1, manager.bench_slot_count + 1):
		slots.append("p%d_bench%d" % [pid, i])

	for evo: PokemonCardData in evolutions:
		for slot: String in slots:
			var inst: PokemonInstance = manager.board_position.get_instance(slot)
			if inst == null or inst.card == null:
				continue
			if inst.card.name_slug != evo.evolves_from:
				continue
			var action := ActionEvolve.new(pid, evo, slot)
			if action.validate(manager).ok:
				return action
	return null


## --- 2c. Use an active Poké-Power -------------------------------------------
##
## Enumerates every in-play Pokémon owned by [pid] and every ability on each.
## Returns the first ActionUseAbility whose validate() passes — which already
## checks: main-phase, attack-not-used-this-turn, slot ownership, fossil
## guard, ability_index range, once-per-turn lock (`power_used_this_turn`
## vs `ability.repeatable`), special-condition suppression (asleep / confused
## / paralyzed), POKE_POWER kind (skips POKE_BODY), and the effect-specific
## `AbilityResolver.validate` (so e.g. Delcatty's "Energy Draw" only fires
## if there's a discardable energy + the deck is non-empty).
##
## Iteration order: actives first, then bench, in slot-number order, ability
## index in declaration order.  This is deterministic and matches the
## "first valid" pattern used elsewhere in OpponentAI.

func _try_use_ability(manager, pid: int) -> GameAction:
	if manager.attack_used_this_turn[pid]:
		return null  ## Powers are gated to "before your attack" — short-circuit.

	var slots: Array[String] = []
	for i in range(1, manager.active_slot_count + 1):
		slots.append("p%d_active%d" % [pid, i])
	for i in range(1, manager.bench_slot_count + 1):
		slots.append("p%d_bench%d" % [pid, i])

	for slot: String in slots:
		var inst: PokemonInstance = manager.board_position.get_instance(slot)
		if inst == null or inst.card == null:
			continue
		if inst.is_fossil():
			continue
		for abil_idx in inst.card.abilities.size():
			var ability: AbilityData = inst.card.abilities[abil_idx]
			if ability.kind != AbilityData.AbilityKind.POKE_POWER:
				continue  ## Bodies are passive — never activated.
			var action := ActionUseAbility.new(pid, slot, abil_idx)
			if action.validate(manager).ok:
				return action
	return null


## --- 3. Attach one energy (prefer typed match) -------------------------------
##
## Priority:
##   pass 1 — actives that still NEED energy to fund an attack
##   pass 2 — benched Pokemon (build them up while active waits to attack)
##   pass 3 — fallback: any active (last resort if bench is empty and
##            active already covers all its attacks; better than wasting
##            the energy attachment for the turn)

func _try_attach_energy(manager, pid: int) -> GameAction:
	var energies: Array[EnergyCardData] = _energies_in_hand(manager, pid)
	if energies.is_empty():
		return null

	## Pass 1: active slots that still need more energy.
	for i in range(1, manager.active_slot_count + 1):
		var slot := "p%d_active%d" % [pid, i]
		var inst: PokemonInstance = manager.board_position.get_instance(slot)
		if inst == null:
			continue
		if _has_full_attack_coverage(inst, energies):
			continue
		var action: GameAction = _build_attach_action(energies, manager, pid, slot, inst)
		if action != null:
			return action

	## Pass 2: bench Pokemon (build them up so they can step in after a KO).
	for i in range(1, manager.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [pid, i]
		var inst: PokemonInstance = manager.board_position.get_instance(slot)
		if inst == null:
			continue
		var action: GameAction = _build_attach_action(energies, manager, pid, slot, inst)
		if action != null:
			return action

	## Pass 3: fallback — any active even if it already has full coverage,
	## so we don't waste the turn's attachment.
	for i in range(1, manager.active_slot_count + 1):
		var slot := "p%d_active%d" % [pid, i]
		var inst: PokemonInstance = manager.board_position.get_instance(slot)
		if inst == null:
			continue
		var action: GameAction = _build_attach_action(energies, manager, pid, slot, inst)
		if action != null:
			return action
	return null


## Build and validate an ActionAttachEnergy for [slot] with the typed energy
## matching [inst]'s attack costs, or fall back to the first available energy.
func _build_attach_action(energies: Array[EnergyCardData], manager, pid: int,
		slot: String, inst: PokemonInstance) -> GameAction:
	var preferred: EnergyCardData = _pick_best_energy_for(energies, inst)
	if preferred == null:
		preferred = energies[0]
	var action := ActionAttachEnergy.new(pid, preferred, slot)
	if action.validate(manager).ok:
		return action
	return null


## True iff every attack on [inst] is either already payable OR unreachable
## (its typed cost requires an energy type that's neither attached nor in
## hand).  In either case, attaching more energy to [inst] from [hand_energies]
## won't unlock any new attack, so the AI moves on to a different target.
##
## False when the card has no attacks (preserves the prior "still needs
## energy" stance so the AI doesn't refuse to fuel an unevolved Pokemon
## whose evolution adds attacks).
func _has_full_attack_coverage(inst: PokemonInstance,
		hand_energies: Array[EnergyCardData]) -> bool:
	if inst == null or inst.card == null:
		return false
	if inst.card.attacks.is_empty():
		return false
	var available_types: Dictionary = _energy_types_available_for(inst, hand_energies)
	for atk: AttackData in inst.card.attacks:
		if ActionAttack._check_energy(inst, atk).ok:
			continue  ## already payable
		if not _attack_is_reachable(atk, available_types):
			continue  ## unreachable (e.g. requires FIGHTING, none in hand) — skip
		return false  ## still has a growable attack
	return true


## Returns a set (Dictionary used as set) of EnergyType ints reachable from
## the union of [inst]'s currently-attached energies and [hand_energies].
## Special energies that provide multiple types (Rainbow, Multi) contribute
## every type they cover.
func _energy_types_available_for(inst: PokemonInstance,
		hand_energies: Array[EnergyCardData]) -> Dictionary:
	var types: Dictionary = {}
	if inst != null:
		for e in inst.attached_energy:
			if e is EnergyCardData:
				types[int((e as EnergyCardData).energy_type)] = true
				for et in (e as EnergyCardData).extra_types:
					types[int(et)] = true
	for e in hand_energies:
		types[int(e.energy_type)] = true
		for et in e.extra_types:
			types[int(et)] = true
	return types


## True if [atk]'s typed costs can be funded from [available_types].  Colorless
## costs are always reachable (any energy fills colorless), so this only
## checks typed costs.  A typed cost whose type is missing from the set means
## the attack cannot be paid even with infinite future attachments from the
## current pool.
func _attack_is_reachable(atk: AttackData, available_types: Dictionary) -> bool:
	var ET := PokemonCardData.EnergyType
	if atk.cost_fire > 0      and not available_types.has(int(ET.FIRE)):      return false
	if atk.cost_water > 0     and not available_types.has(int(ET.WATER)):     return false
	if atk.cost_grass > 0     and not available_types.has(int(ET.GRASS)):     return false
	if atk.cost_lightning > 0 and not available_types.has(int(ET.LIGHTNING)): return false
	if atk.cost_psychic > 0   and not available_types.has(int(ET.PSYCHIC)):   return false
	if atk.cost_fighting > 0  and not available_types.has(int(ET.FIGHTING)):  return false
	if atk.cost_darkness > 0  and not available_types.has(int(ET.DARKNESS)):  return false
	if atk.cost_metal > 0     and not available_types.has(int(ET.METAL)):     return false
	return true


## --- 4. Attack with the best-tier legal attack -------------------------------
##
## Priority (per user spec):
##   tier 0 — damage > 0 (pick highest damage)
##   tier 1 — damage == 0, inflicts a status NOT already on the target
##   tier 2 — damage == 0, no status effect at all (vanilla effect / search)
##   tier 3 — damage == 0, status the target already has (no-op stacking)
##
## Returns the best legal attack across all of [pid]'s active slots, or null
## if no attack is legal.

const _STATUS_NAMES: Array[String] = [
	"ASLEEP", "BURNED", "CONFUSED", "PARALYZED", "POISONED",
]


func _try_attack(manager, pid: int) -> GameAction:
	var tiers: Array = [[], [], [], []]
	for i in range(1, manager.active_slot_count + 1):
		var atk_slot := "p%d_active%d" % [pid, i]
		var attacker: PokemonInstance = manager.board_position.get_instance(atk_slot)
		if attacker == null or attacker.card == null:
			continue
		var opp_id: int = 1 - pid
		var tgt_slot: String = _first_opponent_active(manager, opp_id)
		if tgt_slot == "":
			continue
		var target: PokemonInstance = manager.board_position.get_instance(tgt_slot)
		for atk_idx in attacker.card.attacks.size():
			var action := ActionAttack.new(pid, atk_slot, atk_idx, tgt_slot)
			if not action.validate(manager).ok:
				continue
			var atk: AttackData = attacker.card.attacks[atk_idx]
			## Skip attacks whose worst-case self-damage would KO the
			## attacker — handing the opponent a free prize is strictly
			## worse than ending the turn.  Conservative check: assumes
			## coin-gated self-damage rolls the bad side.  Phase B3 will
			## use expected-value scoring instead so e.g. a 50%-chance
			## self-damage attack isn't always rejected.
			var self_dmg_max: int = _attack_self_damage_max(atk)
			if self_dmg_max > 0 and attacker.current_hp <= self_dmg_max:
				continue
			var dmg: int = int(atk.base_damage)
			var tier: int = _tier_for_attack(atk, dmg, target)
			tiers[tier].append({"action": action, "damage": dmg})

	for tier in tiers:
		if (tier as Array).is_empty():
			continue
		var best: Dictionary = (tier as Array)[0]
		for entry: Dictionary in tier:
			if int(entry["damage"]) > int(best["damage"]):
				best = entry
		return best["action"] as ActionAttack
	return null


## Returns the worst-case self-damage [atk] could inflict on its own
## attacker.  Used by _try_attack to avoid self-KOs.  Counts known self-
## damage patterns from the effect_key and any effect_chain entries:
##   - "self_damage" with effect_params.amount (Thunder Jolt, Self-
##     Destruct, Volt Tackle, etc.).  Coin-gated variants are counted at
##     their full amount (worst case = tails).
##   - "attach_from_discard" / "attach_from_deck" with
##     self_damage_per_attached × count (Pichu's Energy Retrieval).
## Returns 0 for attacks with no self-damage component.  Phase B3 will
## replace this with an expected-value model and broader pattern coverage.
func _attack_self_damage_max(atk: AttackData) -> int:
	var total: int = _self_damage_amount_for(atk.effect_key, atk.effect_params)
	for raw in atk.effect_chain:
		if raw is Dictionary:
			var key: String    = str((raw as Dictionary).get("key", ""))
			var params: Dictionary = (raw as Dictionary).get("params", {}) as Dictionary
			total += _self_damage_amount_for(key, params)
	return total


func _self_damage_amount_for(key: String, params: Dictionary) -> int:
	match key:
		"self_damage":
			return int(params.get("amount", 0))
		"attach_from_discard", "attach_from_deck":
			var per_attached: int = int(params.get("self_damage_per_attached", 0))
			return per_attached * int(params.get("count", 0))
	return 0


## Returns the priority tier (0 best → 3 worst) for an attack.  See _try_attack
## for the full ordering.
func _tier_for_attack(atk: AttackData, dmg: int, target: PokemonInstance) -> int:
	if dmg > 0:
		return 0
	var status: String = _status_inflicted_by(atk)
	if status.is_empty():
		return 2
	if target != null and _target_has_status(target, status):
		return 3
	return 1


## Returns the SpecialCondition name (e.g. "BURNED") that [atk] would apply to
## its target, or "" if the attack has no status-inflict component.  Covers
## inflict_status, coin_status (probabilistic — counts as inflicts), and the
## inflict_burned_retreat_lock + inflict_status entries in effect_chain.
func _status_inflicted_by(atk: AttackData) -> String:
	var direct_keys: Array[String] = [
		"inflict_status",
		"coin_status",
		"conditional_inflict_status",
		"inflict_status_by_attached_count",
	]
	if atk.effect_key in direct_keys:
		var cond: String = str(atk.effect_params.get("condition", ""))
		if cond in _STATUS_NAMES:
			return cond
	if atk.effect_key == "inflict_burned_retreat_lock":
		return "BURNED"
	for raw in atk.effect_chain:
		if not (raw is Dictionary):
			continue
		var key: String = str((raw as Dictionary).get("key", ""))
		var params: Dictionary = (raw as Dictionary).get("params", {}) as Dictionary
		if key in direct_keys:
			var cond_chain: String = str(params.get("condition", ""))
			if cond_chain in _STATUS_NAMES:
				return cond_chain
		if key == "inflict_burned_retreat_lock":
			return "BURNED"
	return ""


func _target_has_status(target: PokemonInstance, status_name: String) -> bool:
	var idx: int = _STATUS_NAMES.find(status_name)
	if idx < 0:
		return false
	## SpecialCondition enum order matches _STATUS_NAMES:
	## ASLEEP=0, BURNED=1, CONFUSED=2, PARALYZED=3, POISONED=4
	return target.special_conditions.has(idx)


## --- helpers -----------------------------------------------------------------

func _first_basic_in_hand(manager, pid: int) -> PokemonCardData:
	for card: CardData in manager.game_position.hands[pid] as Array:
		if card is PokemonCardData \
				and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			return card
	return null


func _energies_in_hand(manager, pid: int) -> Array[EnergyCardData]:
	var out: Array[EnergyCardData] = []
	for card: CardData in manager.game_position.hands[pid] as Array:
		if card is EnergyCardData:
			out.append(card)
	return out


## Picks an energy whose type matches one of [inst]'s attack costs, otherwise
## returns null so the caller can fall back to the first available energy.
func _pick_best_energy_for(energies: Array[EnergyCardData], inst: PokemonInstance) -> EnergyCardData:
	if inst == null or inst.card == null:
		return null
	var needed_types: Dictionary = {}
	for atk: AttackData in inst.card.attacks:
		if atk.cost_fire > 0:      needed_types[PokemonCardData.EnergyType.FIRE]      = true
		if atk.cost_water > 0:     needed_types[PokemonCardData.EnergyType.WATER]     = true
		if atk.cost_grass > 0:     needed_types[PokemonCardData.EnergyType.GRASS]     = true
		if atk.cost_lightning > 0: needed_types[PokemonCardData.EnergyType.LIGHTNING] = true
		if atk.cost_psychic > 0:   needed_types[PokemonCardData.EnergyType.PSYCHIC]   = true
		if atk.cost_fighting > 0:  needed_types[PokemonCardData.EnergyType.FIGHTING]  = true
		if atk.cost_darkness > 0:  needed_types[PokemonCardData.EnergyType.DARKNESS]  = true
		if atk.cost_metal > 0:     needed_types[PokemonCardData.EnergyType.METAL]     = true
	for e: EnergyCardData in energies:
		if needed_types.has(e.energy_type):
			return e
	return null


func _first_opponent_active(manager, opp_id: int) -> String:
	for i in range(1, manager.active_slot_count + 1):
		var slot := "p%d_active%d" % [opp_id, i]
		if manager.board_position.get_instance(slot) != null:
			return slot
	return ""
