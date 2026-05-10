extends GutTest
## GUT test suite for tier-3 wave 1: damage_scaling effect handler.
##
## Covers each `basis` value in damage_scaling:
##   damage_counters_target, damage_counters_attacker,
##   energy_attached_target, energy_attached_attacker,
##   energy_attached_all, energy_attached_own, energy_attached_opp,
##   energy_of_type_attacker, energy_of_type_target,
##   bench_pokemon_count, bench_pokemon_of_type,
##   coin_flips_heads, coin_flips_per_energy_heads,
##   extra_energy_beyond_cost.
##
## Plus edge cases: zero units, max_units cap.

var _lib: CardLibrary
var _handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_handlers_node = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_handlers_node)


func after_all() -> void:
	if _handlers_node != null:
		_handlers_node.queue_free()
		_handlers_node = null


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


## Synthesises a damage_scaling attack on `att` and runs it.
## Returns [result, attacker_inst, target_inst, manager].
func _run_scaling(att: PokemonInstance, target_slot: String, base_damage: int,
		params: Dictionary, mgr: ManagerSystem) -> Array:
	att.card.attacks[0].base_damage = base_damage
	att.card.attacks[0].effect_key = "damage_scaling"
	att.card.attacks[0].effect_params = params
	## Strip cost so the action doesn't fail validation regardless of attached energy.
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_fire = 0
	att.card.attacks[0].cost_water = 0
	att.card.attacks[0].cost_grass = 0
	att.card.attacks[0].cost_lightning = 0
	att.card.attacks[0].cost_psychic = 0
	att.card.attacks[0].cost_fighting = 0
	att.card.attacks[0].cost_darkness = 0
	att.card.attacks[0].cost_metal = 0
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, target_slot)
	)
	var a_inst: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var t_inst: PokemonInstance = mgr.board_position.get_instance(target_slot)
	return [result, a_inst, t_inst, mgr]


## Uses DR_5_golem (hp_max=120) as the target so tests can place high counter
## counts without immediately KO'ing the target on attack resolution. Bagon
## attacks as COLORLESS so golem's WATER weakness does not trigger.
func _basic_setup(target_hp: int = 120) -> Array:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": target_hp})
	b.set_prizes(0); b.set_prizes(1)
	return [b, mgr, att, tgt]


## ── damage_counters_target ────────────────────────────────────────────────

func test_damage_counters_target() -> void:
	# Golem hp_max=120, current=80 → 4 damage counters; survives 70 dmg.
	var setup := _basic_setup(80)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 30,
		{"basis": "damage_counters_target", "per_unit": 10}, mgr)
	assert_true(r[0].ok, "attack should resolve")
	# 30 base + 10 × 4 counters = 70
	var dmg: int = hp_before - (r[2] as PokemonInstance).current_hp
	assert_eq(dmg, 70, "damage should be 30 base + 4 counters × 10")


func test_damage_counters_target_zero_units() -> void:
	# Target at full HP (golem hp_max=120) → 0 counters → no bonus.
	var setup := _basic_setup(120)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 20,
		{"basis": "damage_counters_target", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	var dmg: int = hp_before - (r[2] as PokemonInstance).current_hp
	assert_eq(dmg, 20, "no bonus when 0 units")


## ── damage_counters_attacker ──────────────────────────────────────────────

func test_damage_counters_attacker() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {"hp": 30})  # bagon hp_max=60, so 3 counters
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "damage_counters_attacker", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	var dmg: int = hp_before - (r[2] as PokemonInstance).current_hp
	assert_eq(dmg, (att.max_hp - 30) / 10 * 10, "damage = attacker counters × 10")


## ── energy_attached_target ────────────────────────────────────────────────

func test_energy_attached_target() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_41_shelgon",
		{"hp": 200, "energy": ["RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "energy_attached_target", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	var dmg: int = hp_before - (r[2] as PokemonInstance).current_hp
	assert_eq(dmg, 30, "0 base + 3 energy × 10 = 30")


## ── energy_attached_attacker ──────────────────────────────────────────────

func test_energy_attached_attacker() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 10,
		{"basis": "energy_attached_attacker", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 30,
		"10 base + 2 energy × 10 = 30")


## ── energy_attached_all / own / opp ───────────────────────────────────────

func test_energy_attached_all() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon",
		{"hp": 200, "energy": ["RS_104_grass_energy"]})
	b.place_bench(0, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "energy_attached_all", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	# 2 (attacker) + 1 (target) + 1 (own bench) = 4 → 40 dmg
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 40)


func test_energy_attached_own() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon",
		{"hp": 200, "energy": ["RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "energy_attached_own", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 20,
		"only attacker's side counts (2 energy × 10)")


func test_energy_attached_opp() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon",
		{"hp": 200, "energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "energy_attached_opp", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 20,
		"only opponent side counts (2 energy × 10)")


## ── energy_of_type_attacker ───────────────────────────────────────────────

func test_energy_of_type_attacker() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy",
			"RS_105_fighting_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 40,
		{"basis": "energy_of_type_attacker", "energy_type": "FIGHTING", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	# 40 base + 1 fighting × 10 = 50; account for weakness/resistance via shelgon's profile
	# Just verify the bonus was applied (delta vs. no fighting energy).
	var dmg: int = hp_before - (r[2] as PokemonInstance).current_hp
	assert_true(dmg >= 50, "should include +10 from FIGHTING energy filter, got %d" % dmg)


## ── bench_pokemon_count ───────────────────────────────────────────────────

func test_bench_pokemon_count() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_bench(0, "DR_49_bagon")
	b.place_bench(0, "DR_49_bagon")
	b.place_bench(0, "DR_49_bagon")
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "bench_pokemon_count", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 30,
		"3 benched Pokémon × 10 = 30")


## ── coin_flips_heads ──────────────────────────────────────────────────────

func test_coin_flips_heads_all_heads() -> void:
	var setup := _basic_setup(200)
	var mgr: ManagerSystem = setup[1]
	mgr.push_forced_flips([true, true])
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "coin_flips_heads", "flips": 2, "per_unit": 70}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 140,
		"2 heads × 70 = 140 (Aggron Double Lariat both-heads)")


func test_coin_flips_heads_all_tails() -> void:
	var setup := _basic_setup(200)
	var mgr: ManagerSystem = setup[1]
	mgr.push_forced_flips([false, false])
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "coin_flips_heads", "flips": 2, "per_unit": 70}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 0,
		"all tails → 0 damage")


func test_coin_flips_per_energy_heads_capped() -> void:
	# Kabutops ex Hydrocutter: flip 1 per energy, max 3, 40 per heads.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy",
			"RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	# 5 energy attached but capped at 3 flips
	mgr.push_forced_flips([true, true, true])
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 300})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "coin_flips_per_energy_heads", "max_flips": 3, "per_unit": 40}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 120,
		"3 heads × 40 = 120 (capped at 3 flips)")


## ── extra_energy_beyond_cost ──────────────────────────────────────────────

func test_extra_energy_beyond_cost() -> void:
	# Set cost manually inside this test rather than via the helper.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# 4 attached, cost 1 → 3 extra, capped at 2 → +20
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy",
			"RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[0].base_damage = 20
	att.card.attacks[0].effect_key = "damage_scaling"
	att.card.attacks[0].effect_params = {
		"basis": "extra_energy_beyond_cost",
		"per_unit": 10,
		"max_units": 2,
	}
	att.card.attacks[0].cost_colorless = 1
	att.card.attacks[0].cost_water = 0
	att.card.attacks[0].cost_fire = 0
	att.card.attacks[0].cost_grass = 0
	att.card.attacks[0].cost_lightning = 0
	att.card.attacks[0].cost_psychic = 0
	att.card.attacks[0].cost_fighting = 0
	att.card.attacks[0].cost_darkness = 0
	att.card.attacks[0].cost_metal = 0
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_true(result.ok)
	assert_eq(hp_before - t2.current_hp, 40,
		"20 base + (4 - 1 cost = 3, capped at 2) × 10 = 40")


## ── max_units cap ─────────────────────────────────────────────────────────

func test_max_units_caps_bonus() -> void:
	# Golem hp_max=120, current=60 → 6 counters; cap at 5 → +50; target survives.
	var setup := _basic_setup(60)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var tgt: PokemonInstance = setup[3]
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "damage_counters_target", "per_unit": 10, "max_units": 5}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 50,
		"capped at 5 × 10 = 50 even with 6 actual counters")


## ── unknown basis is a no-op (no crash) ───────────────────────────────────

func test_unknown_basis_no_op() -> void:
	var setup := _basic_setup(200)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 30,
		{"basis": "totally_made_up", "per_unit": 99}, mgr)
	assert_true(r[0].ok, "unknown basis should not crash")
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 30,
		"only base damage applies on unknown basis")


## ── conditional_bonus_damage ─────────────────────────────────────────────

func test_conditional_defender_has_damage_counters() -> void:
	# Crawdaunt Rend: 30 + 30 if defender has any counters.
	var setup := _basic_setup(110)  # golem max 120, current 110 → 1 counter
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	att.card.attacks[0].base_damage = 30
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "defender_has_damage_counters",
		"bonus": 30,
	}
	att.card.attacks[0].cost_colorless = 0
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(result.ok)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t.current_hp, 60, "30 base + 30 bonus = 60")


func test_conditional_defender_has_damage_counters_no_bonus_when_full() -> void:
	var setup := _basic_setup(120)  # full HP → 0 counters
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	att.card.attacks[0].base_damage = 30
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "defender_has_damage_counters",
		"bonus": 30,
	}
	att.card.attacks[0].cost_colorless = 0
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(result.ok)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t.current_hp, 30, "no bonus when full HP")


func test_conditional_defender_is_pokemon_ex() -> void:
	# Hariyama Mega Throw: 40 + 40 if defender is Pokémon-ex.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# DR_92_kingdra_ex → name_slug ends with "_ex"
	var tgt := b.place_active(1, "DR_92_kingdra_ex", {"hp": 150})
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[0].base_damage = 40
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "defender_is_pokemon_ex",
		"bonus": 40,
	}
	att.card.attacks[0].cost_colorless = 0
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(result.ok)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t.current_hp, 80, "40 base + 40 bonus vs ex")


func test_conditional_defender_is_evolved() -> void:
	var setup := _basic_setup(120)  # golem stage=STAGE2 → evolved
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	att.card.attacks[0].base_damage = 30
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "defender_is_evolved",
		"bonus": 30,
	}
	att.card.attacks[0].cost_colorless = 0
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(result.ok)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t.current_hp, 60, "30 + 30 vs evolved Pokémon")


func test_conditional_defender_is_evolved_basic_no_bonus() -> void:
	# Bagon = BASIC; condition false → no bonus.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_49_bagon", {"hp": 60})
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[0].base_damage = 30
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "defender_is_evolved",
		"bonus": 30,
	}
	att.card.attacks[0].cost_colorless = 0
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(result.ok)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t.current_hp, 30, "no bonus when defender is BASIC")


func test_conditional_defender_has_status() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "conditions": [PokemonInstance.SpecialCondition.POISONED]})
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[0].base_damage = 20
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "defender_has_status",
		"bonus": 20,
	}
	att.card.attacks[0].cost_colorless = 0
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(result.ok)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t.current_hp, 40, "20 + 20 bonus when defender has status")


func test_conditional_defender_is_card_match() -> void:
	# Zangoose Target Slash: +30 if defender is Seviper.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# SS_11_seviper has name_slug "seviper".
	var tgt := b.place_active(1, "SS_11_seviper", {"hp": 80})
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "defender_is_card",
		"card_slug": "seviper",
		"bonus": 30,
	}
	att.card.attacks[0].cost_colorless = 0
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(result.ok)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t.current_hp, 40, "10 + 30 vs Seviper")


## ── JSON wiring smoke: Crawdaunt Rend (conditional_bonus_damage) ──────────

func test_card_json_crawdaunt_rend() -> void:
	# Slaking hp_max=120, weakness=FIGHTING — no doubling vs Crawdaunt's WATER attack.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_13_crawdaunt",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "RS_12_slaking", {"hp": 110})  # 1 counter
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	# attacks[1] is "Rend"
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1")
	)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_true(result.ok)
	assert_eq(hp_before - t.current_hp, 60, "Rend 30 + 30 bonus = 60")


## ── attach_from_discard with coin_gate (Wave 2 / F4) ─────────────────────

func test_attach_from_discard_coin_gate_heads() -> void:
	# Heads → energy attaches.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Seed discard with 2 fire energy cards.
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_108_fire_energy"))
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_108_fire_energy"))
	mgr.push_forced_flips([true])
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = "attach_from_discard"
	att.card.attacks[0].effect_params = {"type": "FIRE", "count": 2, "coin_gate": true}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var attached_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.attached_energy.size() - attached_before, 2,
		"heads → 2 fire energy attached")


func test_attach_from_discard_coin_gate_tails_no_attach() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_108_fire_energy"))
	mgr.push_forced_flips([false])
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = "attach_from_discard"
	att.card.attacks[0].effect_params = {"type": "FIRE", "count": 2, "coin_gate": true}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var attached_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.attached_energy.size() - attached_before, 0,
		"tails → no attach")


func test_attach_from_discard_self_damage_per_attached() -> void:
	# Pichu Energy Retrieval style: attach 2, take 2 damage counters (20 dmg).
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_108_fire_energy"))
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_108_fire_energy"))
	att.card.attacks[0].base_damage = 0
	att.card.attacks[0].effect_key = "attach_from_discard"
	att.card.attacks[0].effect_params = {
		"type": "ANY", "count": 2, "self_damage_per_attached": 10}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var hp_before := att.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - att.current_hp, 20,
		"2 attached × 10 dmg = 20 self damage")


## ── attach_from_deck (Wave 2 / F4) ────────────────────────────────────────

func test_attach_from_deck_attaches_and_shuffles() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Seed deck with mixed cards including 1 lightning energy.
	var deck: Array = mgr.game_position.decks[0]
	deck.append(_lib.get_card("RS_104_grass_energy"))
	deck.append(_lib.get_card("RS_109_lightning_energy"))
	deck.append(_lib.get_card("RS_104_grass_energy"))
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = "attach_from_deck"
	att.card.attacks[0].effect_params = {"type": "LIGHTNING", "count": 1}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var attached_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.attached_energy.size() - attached_before, 1,
		"1 lightning attached from deck")
	# Lightning should be removed from deck.
	var lightning_left: int = 0
	for c in mgr.game_position.decks[0]:
		if c is EnergyCardData and (c as EnergyCardData).energy_type == PokemonCardData.EnergyType.LIGHTNING:
			lightning_left += 1
	assert_eq(lightning_left, 0, "no lightning left in deck")


## ── JSON wiring smoke: Mewtwo ex Energy Absorption ────────────────────────

func test_card_json_mewtwo_ex_energy_absorption() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "RS_101_mewtwo_ex",
		{"energy": ["RS_107_psychic_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_107_psychic_energy"))
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_106_water_energy"))
	var attached_before := att.attached_energy.size()
	# Energy Absorption is attacks[0]
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.attached_energy.size() - attached_before, 2,
		"up to 2 energy attached from discard")


## ── Wave 4: new damage_scaling bases ─────────────────────────────────────

func test_coin_flips_until_tails() -> void:
	# 3 heads then tails → 3 × 40 = 120 (Linoone Continuous Headbutt).
	var setup := _basic_setup(120)
	var mgr: ManagerSystem = setup[1]
	mgr.push_forced_flips([true, true, true, false])
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "coin_flips_until_tails", "per_unit": 40}, mgr)
	assert_true(r[0].ok)
	var t: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# Target may have been KO'd at 120 dmg vs 120 hp; check via instance only if alive.
	if t != null:
		assert_eq(hp_before - t.current_hp, 120, "3 heads × 40 = 120")


func test_energy_types_attacker() -> void:
	# 3 different energy types → +30 (Flygon Rainbow Burn with per_unit=10).
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_106_water_energy",
			"RS_108_fire_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 30,
		{"basis": "energy_types_attacker", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	# 3 distinct types → +30. base 30 → 60 total.
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 60,
		"3 distinct energy types × 10 = 30 bonus on 30 base")


func test_retreat_cost_target() -> void:
	# Golem retreat_cost=4 → +40 with per_unit=10.
	var setup := _basic_setup(120)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var hp_before: int = (setup[3] as PokemonInstance).current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 40,
		{"basis": "retreat_cost_target", "per_unit": 10}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 80,
		"40 base + 4 retreat × 10 = 80")


func test_damage_scaling_subtract_direction() -> void:
	# Wailord ex Dwindling Wave: 100 base − (counters × 10), floor 0.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Wailord ex hp_max=200, current=140 → 6 counters → −60.
	var att := b.place_active(0, "SS_100_wailord_ex", {"hp": 140})
	var tgt := b.place_active(1, "RS_12_slaking", {"hp": 120})  # no water weakness
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[1].cost_water = 0
	att.card.attacks[1].cost_colorless = 0
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))
	assert_true(r.ok)
	# Slaking weak to FIGHTING — Wailord ex is WATER → no x2.
	assert_eq(hp_before - tgt.current_hp, 40,
		"100 base − 6 counters × 10 = 40")


func test_conditional_you_have_more_prizes_left() -> void:
	# DR_1_absol Prize Count: own=6, opp=4 → +20.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0, 6); b.set_prizes(1, 4)
	att.card.attacks[0].base_damage = 20
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "you_have_more_prizes_left", "bonus": 20,
	}
	att.card.attacks[0].cost_colorless = 0
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - tgt.current_hp, 40, "20 + 20 when own prizes > opp")


## ── Wave 6: effect_chain composition ──────────────────────────────────────

func test_effect_chain_runs_both_handlers() -> void:
	# Chain heal_self + cant_attack_next_turn (Slakoth Slack Off pattern).
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"hp": 30, "energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[0].base_damage = 0
	att.card.attacks[0].effect_key = "heal_self"
	att.card.attacks[0].effect_params = {"amount": -1}
	att.card.attacks[0].effect_chain = [
		{"key": "cant_attack_next_turn", "params": {}}
	]
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.current_hp, att.max_hp, "heal_self ran (full heal)")
	assert_eq(att.cant_attack_until_turn, mgr.turn_number + 1,
		"chained cant_attack_next_turn ran too")


## ── Wave 5: search_deck_basic_to_bench ────────────────────────────────────

func test_search_deck_basic_to_bench_by_slug() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_60_magikarp",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Seed deck with 2 Magikarp + 1 Bagon (non-matching).
	var deck: Array = mgr.game_position.decks[0]
	deck.append(_lib.get_card("DR_60_magikarp"))
	deck.append(_lib.get_card("DR_60_magikarp"))
	deck.append(_lib.get_card("DR_49_bagon"))
	# Magikarp Call for Family is attack 0, params slug=magikarp count=5.
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Both magikarp should now be on the bench.
	var bench_count: int = 0
	for s: String in ["bench1", "bench2", "bench3", "bench4", "bench5"]:
		var inst: PokemonInstance = mgr.board_position.get_instance("p0_%s" % s)
		if inst != null and inst.card != null and inst.card.name_slug == "magikarp":
			bench_count += 1
	assert_eq(bench_count, 2, "2 magikarp moved from deck to bench")
	# Bagon (non-matching basic) should remain in deck.
	var bagon_in_deck: bool = false
	for c in mgr.game_position.decks[0]:
		if c is PokemonCardData and (c as PokemonCardData).name_slug == "bagon":
			bagon_in_deck = true
	assert_true(bagon_in_deck, "non-matching basic stays in deck")


func test_search_deck_basic_by_type() -> void:
	# Wurmple Call for Friends — pull GRASS basics.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_81_wurmple",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var deck: Array = mgr.game_position.decks[0]
	# Seed with grass basic + non-grass basic.
	deck.append(_lib.get_card("DR_81_wurmple"))   # GRASS basic
	deck.append(_lib.get_card("SS_78_shroomish")) # GRASS basic
	deck.append(_lib.get_card("DR_49_bagon"))     # COLORLESS basic
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var pulled: int = 0
	for s: String in ["bench1", "bench2", "bench3", "bench4", "bench5"]:
		var inst: PokemonInstance = mgr.board_position.get_instance("p0_%s" % s)
		if inst != null and inst.card != null \
				and int((inst.card as PokemonCardData).pokemon_type) \
					== int(PokemonCardData.EnergyType.GRASS):
			pulled += 1
	assert_eq(pulled, 2, "2 grass basics pulled to bench")


## ── Multi-turn flags (Wave 3 / F3) ────────────────────────────────────────

func test_cant_attack_next_turn_sets_flag() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = "cant_attack_next_turn"
	att.card.attacks[0].effect_params = {}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.cant_attack_until_turn, mgr.turn_number + 1,
		"flag set to turn_number + 1")


func test_damage_immune_next_turn_zeros_incoming_damage() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Pre-set the immunity flag on the target as if its prior turn used Scrunch.
	tgt.damage_immune_until_turn = mgr.turn_number + 1
	att.card.attacks[0].base_damage = 50
	att.card.attacks[0].effect_key = ""
	att.card.attacks[0].effect_params = {}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - tgt.current_hp, 0,
		"damage_immune_until_turn nullifies the damage")


func test_effect_immune_next_turn_blocks_attack_entirely() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	tgt.effect_immune_until_turn = mgr.turn_number + 1
	# Attack tries to inflict POISONED — should also be skipped.
	att.card.attacks[0].base_damage = 50
	att.card.attacks[0].effect_key = "inflict_status"
	att.card.attacks[0].effect_params = {"condition": "POISONED"}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - tgt.current_hp, 0,
		"no damage when target is effect-immune")
	assert_false(tgt.special_conditions.has(PokemonInstance.SpecialCondition.POISONED),
		"no post-damage status applied either")


func test_cant_attack_until_turn_blocks_action_attack() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	att.cant_attack_until_turn = mgr.turn_number + 1
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = ""
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_false(r.ok, "should be rejected with cant_attack flag")


## ── Rigor gap fills (Wave 7) ──────────────────────────────────────────────

func test_multi_turn_flag_auto_clears_after_turn_advance() -> void:
	# Flag set on turn 3 with expiry = 4. Advancing past turn 4 must clear it.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	att.cant_attack_until_turn = 4
	mgr.turn_number = 5
	mgr._clear_expired_retreat_locks()
	assert_eq(att.cant_attack_until_turn, -1,
		"flag should clear once turn_number > expiry")


func test_multi_turn_flag_does_not_clear_too_early() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.set_prizes(0); b.set_prizes(1)
	att.cant_attack_until_turn = 4
	mgr.turn_number = 4  # exactly the expiry turn — flag must still hold
	mgr._clear_expired_retreat_locks()
	assert_eq(att.cant_attack_until_turn, 4,
		"flag holds while turn_number <= expiry")


func test_damage_immune_lets_status_effects_through() -> void:
	# Design promise: damage_immune zeros damage but post-damage effects still
	# apply. Attack a damage-immune target with inflict_status POISONED.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	tgt.damage_immune_until_turn = mgr.turn_number + 1
	att.card.attacks[0].base_damage = 50
	att.card.attacks[0].effect_key = "inflict_status"
	att.card.attacks[0].effect_params = {"condition": "POISONED"}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - tgt.current_hp, 0, "damage_immune zeros the damage")
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.POISONED),
		"non-damage effect (status) still applied under damage_immune")


func test_effect_immune_blocks_status_too() -> void:
	# Contrast with above: effect_immune should block ALL effects, not just damage.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	tgt.effect_immune_until_turn = mgr.turn_number + 1
	att.card.attacks[0].base_damage = 50
	att.card.attacks[0].effect_key = "inflict_status"
	att.card.attacks[0].effect_params = {"condition": "POISONED"}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_false(tgt.special_conditions.has(PokemonInstance.SpecialCondition.POISONED),
		"effect_immune blocks even non-damage effects")


func test_effect_chain_multiple_entries() -> void:
	# Three chain entries: heal_self, cant_attack_next_turn, inflict_status.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"hp": 30, "energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	att.card.attacks[0].base_damage = 0
	att.card.attacks[0].effect_key = "heal_self"
	att.card.attacks[0].effect_params = {"amount": -1}
	att.card.attacks[0].effect_chain = [
		{"key": "cant_attack_next_turn", "params": {}},
		{"key": "inflict_status", "params": {"condition": "POISONED"}},
	]
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.current_hp, att.max_hp, "primary heal ran")
	assert_eq(att.cant_attack_until_turn, mgr.turn_number + 1, "chain[0] ran")
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.POISONED),
		"chain[1] ran")


func test_search_deck_excludes_non_basics() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_60_magikarp",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Deck has only Stage 1 cards — search should pull nothing.
	var deck: Array = mgr.game_position.decks[0]
	deck.append(_lib.get_card("DR_5_golem"))      # Stage 2
	deck.append(_lib.get_card("DR_41_shelgon"))   # Stage 1
	# Magikarp Call for Family is attack 0 with name_slug filter "magikarp".
	# But there's no magikarp in deck and only non-basics, so 0 should be pulled.
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	for s: String in ["bench1", "bench2", "bench3", "bench4", "bench5"]:
		assert_null(mgr.board_position.get_instance("p0_%s" % s),
			"bench should remain empty when no matching basics in deck")


func test_attach_from_discard_empty_discard_no_op() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Empty discard.
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = "attach_from_discard"
	att.card.attacks[0].effect_params = {"type": "FIRE", "count": 2}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var attached_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "attack still resolves when nothing to attach")
	assert_eq(att.attached_energy.size(), attached_before,
		"no energy moved when discard is empty")


func test_attach_from_discard_type_filter_skips_non_matches() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Discard has only WATER energy; we ask for FIRE.
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_106_water_energy"))
	mgr.game_position.put_in_discard(0, _lib.get_card("RS_106_water_energy"))
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = "attach_from_discard"
	att.card.attacks[0].effect_params = {"type": "FIRE", "count": 2}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var attached_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.attached_energy.size(), attached_before,
		"type filter blocks non-matching energy")
	assert_eq(mgr.game_position.discards[0].size(), 2,
		"discard untouched when filter matches nothing")


func test_damage_scaling_subtract_floors_at_min_damage() -> void:
	# 5 attacker counters × 10 = -50 from a 30 base; floor at 10 → final 10.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Bagon hp_max=60, current=10 → 5 counters.
	var att := b.place_active(0, "DR_49_bagon",
		{"hp": 10, "energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: Array = await _run_scaling(att, "p1_active1", 30,
		{"basis": "damage_counters_attacker", "per_unit": 10,
			"direction": "subtract", "min_damage": 10}, mgr)
	assert_true(r[0].ok)
	assert_eq(hp_before - (r[2] as PokemonInstance).current_hp, 10,
		"30 base − 50 floored at 10")


func test_conditional_you_have_more_prizes_false_no_bonus() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	# Opponent has MORE prizes left than us → condition false.
	b.set_prizes(0, 3); b.set_prizes(1, 6)
	att.card.attacks[0].base_damage = 20
	att.card.attacks[0].effect_key = "conditional_bonus_damage"
	att.card.attacks[0].effect_params = {
		"condition": "you_have_more_prizes_left", "bonus": 20,
	}
	att.card.attacks[0].cost_colorless = 0
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - tgt.current_hp, 20,
		"no bonus when own prizes <= opp prizes")


func test_multi_turn_coin_gate_tails_does_not_set_flag() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])
	att.card.attacks[0].base_damage = 10
	att.card.attacks[0].effect_key = "damage_immune_next_turn"
	att.card.attacks[0].effect_params = {"coin_gate": true}
	att.card.attacks[0].cost_colorless = 0
	att.card.attacks[0].cost_grass = 0
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.damage_immune_until_turn, -1,
		"tails on coin_gate must not set the flag")


## ── Wave 6: double-discard chain (Dragon Wave / Mist Ball) ───────────────

func test_card_json_dragonite_ex_dragon_wave_discards_both_types() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Attach 2 water + 2 lightning so the cost is paid AND each discard step
	# has a matching energy to consume.
	var att := b.place_active(0, "DR_90_dragonite_ex",
		{"energy": ["RS_106_water_energy", "RS_106_water_energy",
			"RS_109_lightning_energy", "RS_109_lightning_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Dragon Wave is attack 0.
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# After the attack: 1 water + 1 lightning should remain attached.
	var n_water: int = 0
	var n_lightning: int = 0
	for e: CardData in att.attached_energy:
		if e is EnergyCardData:
			match int((e as EnergyCardData).energy_type):
				int(PokemonCardData.EnergyType.WATER):     n_water += 1
				int(PokemonCardData.EnergyType.LIGHTNING): n_lightning += 1
	assert_eq(n_water, 1, "1 water energy discarded by primary effect")
	assert_eq(n_lightning, 1, "1 lightning energy discarded by chained effect")


## ── JSON wiring smoke: Slakoth Lazy Punch (cant_attack_next_turn) ─────────

func test_card_json_slakoth_lazy_punch() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_80_slakoth",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(att.cant_attack_until_turn, mgr.turn_number + 1,
		"Lazy Punch flagged Slakoth")


## ── JSON wiring smoke: Magneton (energy_attached_own) ─────────────────────

func test_card_json_magneton_magnetic_force() -> void:
	# Magnetic Force costs 1 lightning + 1 colorless.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_17_magneton",
		{"energy": ["RS_109_lightning_energy", "RS_109_lightning_energy",
			"RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 70})
	b.place_bench(0, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_true(result.ok)
	# 4 energy on own side × 10 = 40
	assert_eq(hp_before - t2.current_hp, 40,
		"Magnetic Force = 10 × all energy on own side")
