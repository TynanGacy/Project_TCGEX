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

	## 2. Fill bench up to MAX_BENCH_FILL with basics from hand.
	var bench_action: GameAction = _try_play_basic_to_bench(manager, pid)
	if bench_action != null:
		return bench_action

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


## --- 3. Attach one energy (prefer typed match) -------------------------------

func _try_attach_energy(manager, pid: int) -> GameAction:
	var energies: Array[EnergyCardData] = _energies_in_hand(manager, pid)
	if energies.is_empty():
		return null

	## Prefer to attach to the active so it can attack.  Fall back to first
	## bench slot with a Pokémon.
	var targets: Array[String] = []
	for i in range(1, manager.active_slot_count + 1):
		targets.append("p%d_active%d" % [pid, i])
	for i in range(1, manager.bench_slot_count + 1):
		targets.append("p%d_bench%d" % [pid, i])

	for slot: String in targets:
		var inst: PokemonInstance = manager.board_position.get_instance(slot)
		if inst == null:
			continue
		var preferred: EnergyCardData = _pick_best_energy_for(energies, inst)
		if preferred == null:
			preferred = energies[0]
		var action := ActionAttachEnergy.new(pid, preferred, slot)
		if action.validate(manager).ok:
			return action
	return null


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
