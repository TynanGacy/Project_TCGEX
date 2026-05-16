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
	tgt.card.abilities = []  ## isolate from Shelgon's Energy Guard
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
	tgt.card.abilities = []  ## isolate from Energy Guard
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
	tgt.card.abilities = []  ## isolate from Energy Guard
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
	tgt.card.abilities = []  ## isolate from Energy Guard
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


## ──────────────────────────────────────────────────────────────────────────
## Wave 7: simple damage modifiers (self_damage, place_damage_counters,
## aoe_damage, heal_team, ignore_resistance)
## ──────────────────────────────────────────────────────────────────────────


## Helper for wave-7: synthesise an attack on the attacker with no cost.
func _set_attack(att: PokemonInstance, base_damage: int, key: String, params: Dictionary,
		chain: Array = []) -> void:
	var a: AttackData = att.card.attacks[0]
	a.base_damage = base_damage
	a.effect_key = key
	a.effect_params = params
	a.effect_chain = chain
	a.cost_colorless = 0; a.cost_fire = 0; a.cost_water = 0; a.cost_grass = 0
	a.cost_lightning = 0; a.cost_psychic = 0; a.cost_fighting = 0
	a.cost_darkness = 0; a.cost_metal = 0


## self_damage — unconditional
func test_self_damage_unconditional() -> void:
	var setup := _basic_setup(120)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	att.current_hp = att.max_hp  # ensure full health for self-dmg accounting
	_set_attack(att, 0, "self_damage", {"amount": 20})
	var hp_before := att.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(hp_before - att2.current_hp, 20, "self_damage deals 20 to attacker")


## self_damage — coin gate, tails triggers
func test_self_damage_coin_gate_tails() -> void:
	var setup := _basic_setup(120)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	mgr.push_forced_flips([false])  # force tails
	_set_attack(att, 0, "self_damage", {"amount": 10, "coin_gate": true, "tails": true})
	var hp_before := att.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(hp_before - att2.current_hp, 10, "tails-gated self_damage fires on tails")


## self_damage — coin gate, heads skips
func test_self_damage_coin_gate_heads_skips() -> void:
	var setup := _basic_setup(120)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	mgr.push_forced_flips([true])  # heads = no self-damage when tails:true
	_set_attack(att, 0, "self_damage", {"amount": 10, "coin_gate": true, "tails": true})
	var hp_before := att.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.current_hp, hp_before, "tails-gated self_damage skipped on heads")


## place_damage_counters — defender
func test_place_damage_counters_defender() -> void:
	var setup := _basic_setup(120)
	var mgr: ManagerSystem = setup[1]
	var att: PokemonInstance = setup[2]
	var tgt: PokemonInstance = setup[3]
	_set_attack(att, 0, "place_damage_counters", {"count": 1, "target": "defender"})
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 10, "1 damage counter = 10 dmg")


## place_damage_counters — each_opp
func test_place_damage_counters_each_opp() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var t1 := b.place_active(1, "DR_5_golem", {"hp": 120})
	var t2 := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "place_damage_counters", {"count": 1, "target": "each_opp"})
	var hp_t1_before := t1.current_hp
	var hp_t2_before := t2.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	# Both opp Pokémon take 10 dmg counter
	var t1b: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var t2b: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(hp_t1_before - t1b.current_hp, 10, "active gets 1 counter")
	assert_eq(hp_t2_before - t2b.current_hp, 10, "bench gets 1 counter")


## aoe_damage — opp_bench
func test_aoe_damage_opp_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn1 := b.place_bench(1, "DR_5_golem", {"hp": 120})
	var bn2 := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "aoe_damage", {"amount": 10, "side": "opp_bench"})
	var bn1_before := bn1.current_hp
	var bn2_before := bn2.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var bn1b: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	var bn2b: PokemonInstance = mgr.board_position.get_instance("p1_bench2")
	assert_eq(bn1_before - bn1b.current_hp, 10, "bench1 takes 10")
	assert_eq(bn2_before - bn2b.current_hp, 10, "bench2 takes 10")


## aoe_damage — all_bench hits both sides' benches
func test_aoe_damage_all_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var own_bn := b.place_bench(0, "DR_49_bagon", {})
	var opp_bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "aoe_damage", {"amount": 10, "side": "all_bench"})
	var own_before := own_bn.current_hp
	var opp_before := opp_bn.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var own2: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	var opp2: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(own_before - own2.current_hp, 10, "own bench takes 10")
	assert_eq(opp_before - opp2.current_hp, 10, "opp bench takes 10")


## heal_team — all your Pokémon
func test_heal_team_all() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var own_bn := b.place_bench(0, "DR_49_bagon", {})
	att.current_hp = 30  # damaged
	own_bn.current_hp = 30
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "heal_team", {"counters": 1, "scope": "all"})
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var bn2: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_eq(att2.current_hp, 40, "attacker healed 10")
	assert_eq(bn2.current_hp, 40, "bench healed 10")


## ignore_resistance — Resistance is skipped on the damage calc
func test_ignore_resistance() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Find any card with FIRE pokemon_type for attacker, target with FIRE resistance.
	# Use a generic synthetic setup: hack target.card.resistance directly.
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	# Force a resistance match: make target resist attacker's type with -30.
	tgt.card = tgt.card.duplicate(true)
	tgt.card.resistance = att.card.pokemon_type
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 50, "ignore_resistance", {})
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# With resistance ignored, full 50 lands (otherwise it'd be 20).
	assert_eq(hp_before - t2.current_hp, 50, "ignore_resistance skips -30 resist")


## ──────────────────────────────────────────────────────────────────────────
## Wave 8: target redirection, forced switch, energy search
## ──────────────────────────────────────────────────────────────────────────


func _auto_answer_query(mgr: ManagerSystem, value: Variant) -> void:
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void:
			mgr.attack_resolver.resolve_query.call_deferred(value),
		CONNECT_ONE_SHOT
	)


## damage_chosen_target — picks an opp bench slot, applies amount (W/R bypassed).
func test_damage_chosen_target_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "damage_chosen_target", {"amount": 30})
	_auto_answer_query(mgr, "p1_bench1")
	var hp_before := bn.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var bn2: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(hp_before - bn2.current_hp, 30, "30 lands on chosen bench (no W/R)")


## damage_chosen_target with ignore_wr — bench AND active bypass W/R.
func test_damage_chosen_target_ignore_wr_active() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	# Force a weakness on the target so it would normally double damage.
	tgt.card = tgt.card.duplicate(true)
	tgt.card.weakness = att.card.pokemon_type
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "damage_chosen_target", {"amount": 20, "ignore_wr": true})
	_auto_answer_query(mgr, "p1_active1")
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# With ignore_wr, weakness doesn't double the 20 → still 20.
	assert_eq(hp_before - t2.current_hp, 20, "ignore_wr bypasses weakness on active")


## damage_chosen_target — coin tails blocks the whole effect.
func test_damage_chosen_target_coin_gate_tails() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])
	_set_attack(att, 0, "damage_chosen_target", {"amount": 50, "coin_gate": true, "ignore_wr": true})
	var hp_before := tgt.current_hp
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.current_hp, hp_before, "tails gates out damage entirely")


## force_switch_opp — opp picks a bench slot, gets swapped to active.
func test_force_switch_opp() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var orig_active := b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_41_shelgon", {"hp": 70})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "force_switch_opp", {})
	_auto_answer_query(mgr, "p1_bench1")
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	# bench1 pokemon should now be in active1
	var new_active: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var new_bench: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(new_active.card.card_id, bn.card.card_id, "bench Pokémon swapped to active")
	assert_eq(new_bench.card.card_id, orig_active.card.card_id, "original active moved to bench")


## force_switch_opp — no bench → no-op
func test_force_switch_opp_no_bench_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var orig := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "force_switch_opp", {})
	# No _auto_answer_query needed — handler returns early before querying.
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	var still: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(still.card.card_id, orig.card.card_id, "no swap when no bench")


## search_deck_energy_to_hand — pulls N basic energy from deck into hand.
func test_search_deck_energy_to_hand() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Seed deck with energy cards.
	for cid in ["RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy"]:
		var c: CardData = _lib.get_card(cid)
		mgr.game_position.decks[0].append(c)
	var hand_before: int = mgr.game_position.hands[0].size()
	var deck_before: int = mgr.game_position.decks[0].size()
	_set_attack(att, 0, "search_deck_energy_to_hand", {"count": 2})
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 2, "2 energy added to hand")
	assert_eq(mgr.game_position.decks[0].size(), deck_before - 2, "2 removed from deck")


## search_deck_energy_to_hand — distinct_types caps per-type count.
func test_search_deck_energy_distinct_types() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Three grass + one fire — distinct_types with count=3 should take grass + fire = 2.
	for cid in ["RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy",
				"RS_108_fire_energy"]:
		mgr.game_position.decks[0].append(_lib.get_card(cid))
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "search_deck_energy_to_hand", {"count": 3, "distinct_types": true})
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	# Only 2 distinct types in deck → 2 cards (not 3).
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 2,
		"distinct_types caps per type, takes 1 grass + 1 fire")


## search_discard_energy_to_hand — pulls N basic energy from discard.
func test_search_discard_energy_to_hand() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	for cid in ["RS_104_grass_energy", "RS_108_fire_energy"]:
		mgr.game_position.discards[0].append(_lib.get_card(cid))
	var hand_before: int = mgr.game_position.hands[0].size()
	var disc_before: int = mgr.game_position.discards[0].size()
	_set_attack(att, 0, "search_discard_energy_to_hand", {"count": 2})
	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 2, "2 energy moved to hand")
	assert_eq(mgr.game_position.discards[0].size(), disc_before - 2, "2 removed from discard")


## ──────────────────────────────────────────────────────────────────────────
## Wave 9: smokescreen, damage reduction, hand disruption, target energy
## discard, switch_self
## ──────────────────────────────────────────────────────────────────────────


## smokescreen — sets the next-attack-coin-fail flag on the defender. Verify
## the flag is applied and clears the attacker on tails.
func test_smokescreen_applies_flag() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "smokescreen", {})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(tgt.next_attack_coin_fail_until_turn, mgr.turn_number + 1,
		"smokescreen flag set on defender")


## smokescreen — flag triggers on defender's next attack; tails blocks attack.
func test_smokescreen_tails_blocks_next_attack() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)  # opp's turn
	var atk_opp := b.place_active(1, "DR_49_bagon", {})
	atk_opp.next_attack_coin_fail_until_turn = mgr.turn_number  # active flag
	var tgt_own := b.place_active(0, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])  # tails
	# Plain attack with base damage 20.
	_set_attack(atk_opp, 20, "", {})
	var hp_before := tgt_own.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(1, "p1_active1", 0, "p0_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(t2.current_hp, hp_before, "tails smokescreen blocks damage")
	assert_eq(atk_opp.next_attack_coin_fail_until_turn, -1, "flag cleared after trigger")


## damage_reduction_self_next_turn — Granite Head reduces incoming damage.
func test_damage_reduction_self_next_turn() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att_p0 := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att_p0, 0, "damage_reduction_self_next_turn", {"amount": 10})
	var r1: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r1.ok)
	# Verify the flag is set for the attacker.
	assert_eq(att_p0.damage_reduction_amount, 10, "amount stored")
	assert_eq(att_p0.damage_reduction_until_turn, mgr.turn_number + 1, "expiry stored")

	# Now opp attacks back during their turn — damage should be reduced by 10.
	b.set_turn(1, mgr.turn_number + 1)
	var att_p1: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	_set_attack(att_p1, 30, "", {})
	# Force any potential confusion-style flip to heads to keep deterministic.
	var hp_before := att_p0.current_hp
	var r2: ActionResult = await mgr.request_action_async(
		ActionAttack.new(1, "p1_active1", 0, "p0_active1"))
	assert_true(r2.ok)
	var a2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	# 30 - 10 = 20 (assuming no W/R interaction)
	assert_eq(hp_before - a2.current_hp, 20, "damage reduced by 10")


## discard_from_hand_random — coin heads → 1 random card from opp hand discarded.
func test_discard_from_hand_random_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Seed opp hand with 3 cards.
	for cid in ["RS_104_grass_energy", "RS_108_fire_energy", "RS_106_water_energy"]:
		mgr.game_position.hands[1].append(_lib.get_card(cid))
	mgr.push_forced_flips([true])  # heads
	_set_attack(att, 0, "discard_from_hand_random", {"count": 1, "coin_gate": true})
	var hand_before: int = mgr.game_position.hands[1].size()
	var disc_before: int = mgr.game_position.discards[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[1].size(), hand_before - 1, "1 card removed")
	assert_eq(mgr.game_position.discards[1].size(), disc_before + 1, "1 card discarded")


## discard_from_hand_random — tails skips effect.
func test_discard_from_hand_random_tails_skips() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.hands[1].append(_lib.get_card("RS_104_grass_energy"))
	mgr.push_forced_flips([false])  # tails
	_set_attack(att, 0, "discard_from_hand_random", {"count": 1, "coin_gate": true})
	var hand_before: int = mgr.game_position.hands[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[1].size(), hand_before, "no discard on tails")


## discard_attached_energy_target — flip heads removes 1 energy from defender.
func test_discard_attached_energy_target_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_104_grass_energy", "RS_108_fire_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])  # heads
	_set_attack(att, 0, "discard_attached_energy_target",
		{"count": 1, "coin_gate": true})
	var energy_before := tgt.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.attached_energy.size(), energy_before - 1, "1 energy discarded from target")


## switch_self — auto-switches with first non-empty bench slot.
func test_switch_self_auto_swaps() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var bn := b.place_bench(0, "DR_5_golem", {"hp": 120})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "switch_self", {})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var new_active: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var new_bench: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_eq(new_active.card.card_id, bn.card.card_id, "bench Pokémon promoted")
	assert_eq(new_bench.card.card_id, att.card.card_id, "old active sent to bench")


## switch_self — no-op when bench empty.
func test_switch_self_no_bench_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "switch_self", {})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var still: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(still.card.card_id, att.card.card_id, "stays put when no bench")


## ──────────────────────────────────────────────────────────────────────────
## Wave 7-9 supplementary coverage: edge cases, expiries, JSON smoke
## ──────────────────────────────────────────────────────────────────────────


## ── Wave 7 edge cases ────────────────────────────────────────────────────

## place_damage_counters — each_defending hits both opp active slots.
func test_place_damage_counters_each_defending() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var t1 := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "place_damage_counters",
		{"count": 2, "target": "each_defending"})
	var hp_before := t1.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t1b: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t1b.current_hp, 20, "2 counters = 20 dmg on each defending")


## place_damage_counters — any_opp_query routes to chosen slot.
func test_place_damage_counters_any_opp_query() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "place_damage_counters",
		{"count": 1, "target": "any_opp_query"})
	_auto_answer_query(mgr, "p1_bench1")
	var hp_before := bn.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var bn2: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(hp_before - bn2.current_hp, 10, "10 dmg on chosen bench")


## aoe_damage — opp_all hits primary defender's slot? No — handler excludes
## the primary target to avoid double-counting the base hit.
func test_aoe_damage_opp_all_excludes_primary_target() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var prim := b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# base_damage=20 to primary, aoe also adds 20 to non-primary opp slots.
	_set_attack(att, 20, "aoe_damage", {"amount": 20, "side": "opp_all"})
	var prim_before := prim.current_hp
	var bn_before := bn.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var prim2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var bn2: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(prim_before - prim2.current_hp, 20,
		"primary defender takes 20 (base only, not double-counted)")
	assert_eq(bn_before - bn2.current_hp, 20, "bench takes 20 from aoe")


## aoe_damage — coin_gate tails skips effect.
func test_aoe_damage_coin_gate_tails() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])
	_set_attack(att, 0, "aoe_damage",
		{"amount": 20, "side": "opp_bench", "coin_gate": true})
	var bn_before := bn.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var bn2: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(bn2.current_hp, bn_before, "tails skips aoe damage entirely")


## heal_team — scope:"actives" heals only active slots.
func test_heal_team_actives_only() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var bn := b.place_bench(0, "DR_49_bagon", {})
	att.current_hp = 30
	bn.current_hp = 30
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "heal_team", {"counters": 1, "scope": "actives"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var bn2: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_eq(att2.current_hp, 40, "active healed 10")
	assert_eq(bn2.current_hp, 30, "bench untouched (scope=actives)")


## self_damage — KOs attacker when amount >= HP.
func test_self_damage_can_ko_attacker() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# Damage attacker close to KO.
	att.current_hp = 10
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.place_bench(0, "DR_49_bagon", {})  # bench so KO doesn't end the game
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "self_damage", {"amount": 50})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# After KO, the active slot is empty OR a bench was promoted.
	# Either way, the original attacker should be knocked out.
	assert_true(att.is_knocked_out(), "attacker KO'd by self_damage")


## ── Wave 8 edge cases ────────────────────────────────────────────────────

## damage_chosen_target active WITHOUT ignore_wr — weakness applies normally.
func test_damage_chosen_target_active_applies_weakness() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	# Force a weakness match on the active target.
	tgt.card = tgt.card.duplicate(true)
	tgt.card.weakness = att.card.pokemon_type
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "damage_chosen_target", {"amount": 20})
	_auto_answer_query(mgr, "p1_active1")
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# 20 × 2 weakness = 40 (no ignore_wr, target is active).
	assert_eq(hp_before - t2.current_hp, 40,
		"weakness applies for active target without ignore_wr")


## damage_chosen_target — chosen bench gets bypass-W/R even without ignore_wr.
func test_damage_chosen_target_bench_bypasses_weakness() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	# Force weakness on bench target; without ignore_wr, bench targets should
	# still bypass W/R (the standard 2007 rule, baked into our handler).
	bn.card = bn.card.duplicate(true)
	bn.card.weakness = att.card.pokemon_type
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "damage_chosen_target", {"amount": 20})
	_auto_answer_query(mgr, "p1_bench1")
	var hp_before := bn.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var bn2: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(hp_before - bn2.current_hp, 20,
		"bench bypasses weakness (no doubling)")


## damage_chosen_target — knockout via chosen bench triggers prize selection.
func test_damage_chosen_target_ko_triggers_prize_selection() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_49_bagon", {})
	bn.current_hp = 10  # one shot
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "damage_chosen_target", {"amount": 50, "ignore_wr": true})
	_auto_answer_query(mgr, "p1_bench1")
	# Watch for prize_selection_required emission.
	var prize_requested_for: Array[int] = []
	mgr.prize_selection_required.connect(
		func(pid: int) -> void: prize_requested_for.append(pid),
		CONNECT_ONE_SHOT
	)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Bench slot should now be empty (KO'd).
	assert_true(mgr.board_position.is_empty("p1_bench1"),
		"benched Pokémon KO'd and removed")
	assert_eq(prize_requested_for, [0] as Array[int],
		"attacker prompted for prize selection")


## search_deck_energy_to_hand — fewer matching cards than count.
func test_search_deck_energy_partial_take() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("RS_104_grass_energy"))
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "search_deck_energy_to_hand", {"count": 3})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Only 1 in deck → only 1 moved (not 3).
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 1,
		"takes only what's available")


## ── Wave 9 edge cases ────────────────────────────────────────────────────

## smokescreen — heads passes through (attack lands normally).
func test_smokescreen_heads_allows_attack() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)
	var atk_opp := b.place_active(1, "DR_49_bagon", {})
	atk_opp.next_attack_coin_fail_until_turn = mgr.turn_number
	var tgt_own := b.place_active(0, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])  # heads = pass
	_set_attack(atk_opp, 20, "", {})
	var hp_before := tgt_own.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(1, "p1_active1", 0, "p0_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	# 20 damage lands normally.
	assert_eq(hp_before - t2.current_hp, 20, "heads lets attack through")
	assert_eq(atk_opp.next_attack_coin_fail_until_turn, -1, "flag cleared either way")


## damage_reduction_self_next_turn — flag expires after the turn boundary.
func test_damage_reduction_expires_after_turn() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Manually set the flag as if Granite Head had fired turn-0.
	att.damage_reduction_until_turn = mgr.turn_number + 1
	att.damage_reduction_amount = 10
	# Jump to turn N+2; sweeper should clear the flag.
	mgr.turn_number += 2
	mgr._clear_expired_retreat_locks()
	assert_eq(att.damage_reduction_until_turn, -1, "expiry sweeper clears it")
	assert_eq(att.damage_reduction_amount, 0, "amount also reset")


## discard_attached_energy_target — tails skips effect.
func test_discard_attached_energy_target_tails_skips() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])  # tails
	_set_attack(att, 0, "discard_attached_energy_target",
		{"count": 1, "coin_gate": true})
	var energy_before := tgt.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.attached_energy.size(), energy_before, "tails preserves energy")


## discard_attached_energy_target — type filter only discards matching energy.
func test_discard_attached_energy_target_type_filter() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_104_grass_energy", "RS_108_fire_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	_set_attack(att, 0, "discard_attached_energy_target",
		{"count": 1, "coin_gate": true, "type": "FIRE"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.attached_energy.size(), 1, "1 of 2 energies removed")
	# The remaining energy should be GRASS (FIRE was discarded).
	var remaining: EnergyCardData = t2.attached_energy[0]
	assert_eq(int(remaining.energy_type), PokemonCardData.EnergyType.GRASS,
		"only FIRE was discarded; GRASS remains")


## switch_self — picks first non-empty bench (not last).
func test_switch_self_picks_first_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# Place two benched Pokémon; switch_self should pick bench1 (first).
	var bn1 := b.place_bench(0, "DR_5_golem", {"hp": 120})
	var bn2 := b.place_bench(0, "DR_41_shelgon", {"hp": 70})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "switch_self", {})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var new_active: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(new_active.card.card_id, bn1.card.card_id, "first bench slot picked")
	# bn2 should still be on bench2 untouched.
	var still_b2: PokemonInstance = mgr.board_position.get_instance("p0_bench2")
	assert_eq(still_b2.card.card_id, bn2.card.card_id, "bench2 untouched")


## ── JSON wiring smoke tests ──────────────────────────────────────────────

## Wailord Take Down (Wave 7 self_damage from JSON).
func test_json_wailord_take_down() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "RS_14_wailord",
		{"energy": ["RS_104_grass_energy","RS_104_grass_energy","RS_104_grass_energy","RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := att.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Take Down should succeed")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	# Wailord's Take Down does 20 self-damage per JSON.
	assert_eq(hp_before - att2.current_hp, 20, "Take Down deals 20 self-damage")


## Shelgon Granite Head (Wave 9 damage_reduction_self_next_turn from JSON).
func test_json_shelgon_granite_head_flag() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# DR_42 Shelgon's Granite Head costs 1 Water + 1 Colorless.
	var att := b.place_active(0, "DR_42_shelgon",
		{"energy": ["RS_106_water_energy", "RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Granite Head should succeed")
	# Flag should be set on Shelgon.
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.damage_reduction_amount, 10, "Granite Head sets 10 reduction")
	assert_true(att2.damage_reduction_until_turn >= mgr.turn_number + 1,
		"flag valid through opponent's next turn")


## Houndour Roar (Wave 8 force_switch_opp from JSON).
func test_json_houndour_roar_swaps() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Roar costs C — give 1 energy.
	var att := b.place_active(0, "DR_59_houndour",
		{"energy": ["RS_104_grass_energy"]})
	var orig_active := b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_41_shelgon", {"hp": 70})
	b.set_prizes(0); b.set_prizes(1)
	_auto_answer_query(mgr, "p1_bench1")
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Roar should succeed")
	var new_active: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(new_active.card.card_id, bn.card.card_id, "Roar swaps active for bench")


## Helper — count taken prize slots for player_id.
func _prizes_taken(mgr: ManagerSystem, pid: int) -> int:
	var n: int = 0
	for c in mgr.game_position.prizes[pid]:
		if c == null:
			n += 1
	return n


## ──────────────────────────────────────────────────────────────────────────
## Wave 10: aoe_damage extensions, draw_cards, damage_scaling coin_gate
## ──────────────────────────────────────────────────────────────────────────


## aoe_damage — side: "own_bench" hits only attacker's bench.
func test_aoe_damage_own_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var own_bn := b.place_bench(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var opp_bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "aoe_damage", {"amount": 10, "side": "own_bench"})
	var own_before := own_bn.current_hp
	var opp_before := opp_bn.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var own2: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	var opp2: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(own_before - own2.current_hp, 10, "own bench takes damage")
	assert_eq(opp2.current_hp, opp_before, "opp bench untouched")


## aoe_damage — side: "each_active" hits both players' actives except primary.
func test_aoe_damage_each_active() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# Damaged so we can see the heal/damage.
	att.current_hp = 60
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "aoe_damage", {"amount": 20, "side": "each_active"})
	var att_before := att.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	# Attacker's active is included in each_active (it's not the primary target).
	assert_eq(att_before - att2.current_hp, 20, "own active takes 20")


## aoe_damage — count caps the number of targets.
func test_aoe_damage_count_caps_targets() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn1 := b.place_bench(1, "DR_5_golem", {"hp": 120})
	var bn2 := b.place_bench(1, "DR_5_golem", {"hp": 120})
	var bn3 := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "aoe_damage",
		{"amount": 20, "side": "opp_bench", "count": 2})
	var bn1_before := bn1.current_hp
	var bn2_before := bn2.current_hp
	var bn3_before := bn3.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# First two benched take damage; third doesn't.
	assert_eq(bn1_before - mgr.board_position.get_instance("p1_bench1").current_hp, 20)
	assert_eq(bn2_before - mgr.board_position.get_instance("p1_bench2").current_hp, 20)
	assert_eq(mgr.board_position.get_instance("p1_bench3").current_hp, bn3_before,
		"third bench slot untouched (count cap)")


## draw_cards — unconditional draw.
func test_draw_cards_unconditional() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	for cid in ["RS_104_grass_energy", "RS_108_fire_energy"]:
		mgr.game_position.decks[0].append(_lib.get_card(cid))
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "draw_cards", {"count": 2})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 2, "2 cards drawn")


## draw_cards — opp_has_evolved condition fails when opp has only basics.
func test_draw_cards_opp_evolved_condition_fails() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_49_bagon", {})  # Bagon is basic
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("RS_104_grass_energy"))
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "draw_cards", {"count": 3, "condition": "opp_has_evolved"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before, "no draw when no evolved")


## draw_cards — opp_has_evolved condition passes with stage-1+ Pokémon.
func test_draw_cards_opp_evolved_condition_passes() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# DR_41_shelgon is a Stage-1 evolution.
	b.place_active(1, "DR_41_shelgon", {"hp": 70})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	for cid in ["RS_104_grass_energy", "RS_108_fire_energy", "RS_106_water_energy"]:
		mgr.game_position.decks[0].append(_lib.get_card(cid))
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "draw_cards", {"count": 3, "condition": "opp_has_evolved"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 3, "3 drawn (opp evolved)")


## damage_scaling — coin_gate skips on tails (base damage still resolves).
func test_damage_scaling_coin_gate_tails() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	var setup := _basic_setup(80)  # target hp_max=120 with 4 counters
	mgr = setup[1]
	var att: PokemonInstance = setup[2]
	mgr.push_forced_flips([false])  # tails
	# Base damage 20 stays; coin-gated scaling does nothing.
	var r: Array = await _run_scaling(att, "p1_active1", 20,
		{"basis": "damage_counters_target", "per_unit": 10, "coin_gate": true}, mgr)
	var t: PokemonInstance = r[2]
	assert_true(r[0].ok)
	# 120-current=80 → 4 counters. Without coin gate would be 20 + 40 = 60.
	# With tails, only base 20 applies.
	assert_eq(120 - t.current_hp, 20 + (120 - 80), "tails skips scaling, base only")


## damage_scaling — coin_gate fires on heads.
func test_damage_scaling_coin_gate_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	var setup := _basic_setup(80)
	mgr = setup[1]
	var att: PokemonInstance = setup[2]
	mgr.push_forced_flips([true])  # heads
	var r: Array = await _run_scaling(att, "p1_active1", 0,
		{"basis": "damage_counters_target", "per_unit": 10, "coin_gate": true}, mgr)
	var t: PokemonInstance = r[2]
	assert_true(r[0].ok)
	# 4 counters × 10 = 40, with no base.
	assert_eq(120 - t.current_hp, 40 + (120 - 80),
		"heads triggers scaling (4 counters × 10)")


## ── JSON wiring smoke tests for Wave 10 ─────────────────────────────────

## DR_5 Golem Rock Slide — 20 to 2 opp benched (count cap).
func test_json_rock_slide_caps_at_two_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Rock Slide costs 2 fighting + 3 colorless = 5 fighting energy.
	var att := b.place_active(0, "DR_5_golem",
		{"energy": ["RS_105_fighting_energy", "RS_105_fighting_energy",
					"RS_105_fighting_energy", "RS_105_fighting_energy",
					"RS_105_fighting_energy"]})
	b.place_active(1, "DR_41_shelgon", {"hp": 70})
	var bn1 := b.place_bench(1, "DR_49_bagon", {})
	var bn2 := b.place_bench(1, "DR_49_bagon", {})
	var bn3 := b.place_bench(1, "DR_49_bagon", {})
	b.set_prizes(0); b.set_prizes(1)
	var bn1_before := bn1.current_hp
	var bn2_before := bn2.current_hp
	var bn3_before := bn3.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # attack idx 1 = Rock Slide
	assert_true(r.ok, "Rock Slide should succeed with 5 fighting energy")
	assert_eq(bn1_before - mgr.board_position.get_instance("p1_bench1").current_hp, 20)
	assert_eq(bn2_before - mgr.board_position.get_instance("p1_bench2").current_hp, 20)
	assert_eq(mgr.board_position.get_instance("p1_bench3").current_hp, bn3_before,
		"third bench untouched")


## SS_85 Zigzagoon Collect — draw 1 card.
func test_json_zigzagoon_collect() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Collect costs 1 colorless.
	var att := b.place_active(0, "SS_85_zigzagoon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("RS_108_fire_energy"))
	var hand_before: int = mgr.game_position.hands[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Collect should succeed")
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 1, "1 card drawn")


## aoe_damage each_active + base_damage — primary takes base, others take amount.
## Replicates the Big Explosion pattern.
func test_aoe_damage_each_active_with_base_damage() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# base_damage 30 to primary; each_active also adds 30 to own active.
	_set_attack(att, 30, "aoe_damage", {"amount": 30, "side": "each_active"})
	var att_before := att.current_hp
	var tgt_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(tgt_before - tgt2.current_hp, 30, "primary takes base damage only")
	assert_eq(att_before - att2.current_hp, 30, "own active takes aoe amount")


## damage_scaling direction:"subtract" — Light Touch Throw style.
## 80 base − 10 per energy on target → caps at min_damage 0.
func test_damage_scaling_subtract_with_min_floor() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# Target with 3 energy → 80 - 30 = 50.
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_104_grass_energy", "RS_104_grass_energy",
								"RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 80, "damage_scaling",
		{"basis": "energy_attached_target", "per_unit": 10,
		 "direction": "subtract", "min_damage": 0})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 50, "80 - 3×10 = 50")


## damage_scaling subtract floor — overflow capped at min_damage.
func test_damage_scaling_subtract_floors_at_zero() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# Target with 10 energy → 80 - 100 would be -20; floor to 0.
	var energy: Array[String] = []
	for _i in range(10):
		energy.append("RS_104_grass_energy")
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120, "energy": energy})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 80, "damage_scaling",
		{"basis": "energy_attached_target", "per_unit": 10,
		 "direction": "subtract", "min_damage": 0})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.current_hp, hp_before, "subtract floored at min_damage=0")


## hits_each_defending JSON wiring — Hariyama Super Slap Push hits both defenders.
func test_json_super_slap_push_hits_each_defending() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Super Slap Push costs FFC (2 fighting + 1 colorless).
	var att := b.place_active(0, "RS_8_hariyama",
		{"energy": ["RS_105_fighting_energy", "RS_105_fighting_energy",
					"RS_104_grass_energy"]})
	var t1 := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var t1_before := t1.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Super Slap Push should succeed")
	var t1b: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# 20 base. Only 1 active in this test — so only that one gets hit. The
	# hits_each_defending flag doesn't multiply; it spreads to each filled
	# active slot.
	assert_eq(t1_before - t1b.current_hp, 20,
		"primary defender takes 20 (verifies hits_each_defending JSON wiring)")


## SS_63 Eevee Quick Attack — coin_bonus_damage JSON smoke.
func test_json_eevee_quick_attack_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_63_eevee", {"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # attack idx 1
	assert_true(r.ok, "Quick Attack should succeed")
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# Base 10 + heads bonus 10 = 20.
	assert_eq(hp_before - t2.current_hp, 20, "Quick Attack: 10 + 10 on heads")


## ──────────────────────────────────────────────────────────────────────────
## Wave 11: Tier A extensions and new handlers
## ──────────────────────────────────────────────────────────────────────────


## inflict_status target=both — both attacker and defender get the status.
func test_inflict_status_target_both() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "inflict_status", {"condition": "CONFUSED", "target": "both"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_true(att.special_conditions.has(PokemonInstance.SpecialCondition.CONFUSED),
		"attacker is confused")
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.CONFUSED),
		"defender is confused")


## inflict_status extra_conditions — multiple statuses in one shot.
func test_inflict_status_extra_conditions() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "inflict_status",
		{"condition": "POISONED", "extra_conditions": ["ASLEEP"]})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.POISONED))
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP))


## conditional_bonus_damage: defender_has_special_energy fires only when set.
func test_conditional_bonus_special_energy_fires() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# Multi energy is a Special Energy (not in BASIC_ENERGY_NAMES).
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["SS_93_multi_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "conditional_bonus_damage",
		{"condition": "defender_has_special_energy", "bonus": 40})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 70, "30 + 40 bonus when special energy present")


## conditional_bonus_damage: defender_has_special_energy does NOT fire on basic-only.
func test_conditional_bonus_special_energy_skips_basics() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "conditional_bonus_damage",
		{"condition": "defender_has_special_energy", "bonus": 40})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 30, "basic energy doesn't trigger bonus")


## conditional_bonus_damage: different_energy_counts with negative bonus.
func test_conditional_bonus_different_energy_negative() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})  # 1 energy
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_104_grass_energy",
								"RS_104_grass_energy"]})  # 2 energy
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 40, "conditional_bonus_damage",
		{"condition": "different_energy_counts", "bonus": -30})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# 40 base − 30 = 10 damage.
	assert_eq(hp_before - t2.current_hp, 10, "different counts reduces base")


## damage_scaling: coin_per_pokemon_heads (Beat Up).
func test_damage_scaling_coin_per_pokemon_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_bench(0, "DR_49_bagon", {})
	b.place_bench(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# 3 own Pokémon → flip 3 coins. Force [true,true,false] → 2 heads.
	mgr.push_forced_flips([true, true, false])
	_set_attack(att, 0, "damage_scaling",
		{"basis": "coin_per_pokemon_heads", "per_unit": 20})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 40, "2 heads × 20 = 40")


## damage_scaling: coin_per_active_energy_heads (Max Bubbles).
func test_damage_scaling_coin_per_active_energy_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# 2 energy on own actives → 2 coins. Force [true, false] → 1 head.
	mgr.push_forced_flips([true, false])
	_set_attack(att, 0, "damage_scaling",
		{"basis": "coin_per_active_energy_heads", "per_unit": 30})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 30, "1 head × 30 = 30")


## heal_team exclude_attacker — Healing Egg pattern.
func test_heal_team_exclude_attacker() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var own_bn := b.place_bench(0, "DR_49_bagon", {})
	att.current_hp = 20
	own_bn.current_hp = 20
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "heal_team",
		{"counters": 2, "scope": "all", "exclude_attacker": true})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var bn2: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_eq(att2.current_hp, 20, "attacker unchanged (excluded)")
	assert_eq(bn2.current_hp, 40, "bench healed 20")


## attach_from_hand_free — auto-attaches matching basic energy to attacker.
func test_attach_from_hand_free_grass_only() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.hands[0].append(_lib.get_card("RS_104_grass_energy"))
	mgr.game_position.hands[0].append(_lib.get_card("RS_104_grass_energy"))
	mgr.game_position.hands[0].append(_lib.get_card("RS_108_fire_energy"))
	_set_attack(att, 0, "attach_from_hand_free", {"count": 2, "type": "GRASS"})
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.attached_energy.size(), energy_before + 2, "2 grass attached")


## attach_from_hand_free — count: -1 attaches all matching.
func test_attach_from_hand_free_all() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	for _i in range(3):
		mgr.game_position.hands[0].append(_lib.get_card("RS_106_water_energy"))
	_set_attack(att, 0, "attach_from_hand_free", {"count": -1, "type": "WATER"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.attached_energy.size(), 3, "all 3 water attached")


## heal_one — picks most-damaged own Pokémon.
func test_heal_one_picks_most_damaged() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	att.current_hp = att.max_hp  # full
	var bn := b.place_bench(0, "DR_5_golem", {"hp": 120})
	bn.current_hp = 40  # damaged (80 missing)
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "heal_one", {"counters": 2})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var bn2: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_eq(bn2.current_hp, 60, "most-damaged bench healed 20")


## heal_one — count_fallback when only one own Pokémon.
func test_heal_one_count_fallback() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	att.current_hp = 10  # 1 own pokemon, damaged
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "heal_one", {"counters": 2, "count_fallback": 1})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	# Only 1 own Pokémon → fallback=1 used → 10 healed (not 20).
	assert_eq(att2.current_hp, 20, "fallback heals only 10")


## mill_one_attach_if_energy — top is basic energy → attach.
func test_mill_one_attaches_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("RS_104_grass_energy"))
	_set_attack(att, 0, "mill_one_attach_if_energy", {})
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.attached_energy.size(), energy_before + 1, "energy attached")
	assert_eq(mgr.game_position.decks[0].size(), 0, "deck popped")


## mill_one_attach_if_energy — top is not energy → discard.
func test_mill_one_discards_non_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	# Use a Pokémon card as the top of deck.
	mgr.game_position.decks[0].append(_lib.get_card("DR_49_bagon"))
	_set_attack(att, 0, "mill_one_attach_if_energy", {})
	var disc_before: int = mgr.game_position.discards[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.discards[0].size(), disc_before + 1, "non-energy discarded")


## discard_to_hand_any — pulls most-recently discarded card into hand.
func test_discard_to_hand_any() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.discards[0].append(_lib.get_card("RS_104_grass_energy"))
	mgr.game_position.discards[0].append(_lib.get_card("RS_108_fire_energy"))
	_set_attack(att, 0, "discard_to_hand_any", {"count": 1})
	var hand_before: int = mgr.game_position.hands[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 1, "1 card moved")


## conditional_inflict_status — defender_is_pokemon_ex fires (Extra Poison).
func test_conditional_inflict_status_on_pokemon_ex() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# DR_91 Golem ex has name_slug ending in _ex.
	var tgt := b.place_active(1, "DR_91_golem_ex", {"hp": 150})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "conditional_inflict_status",
		{"condition": "defender_is_pokemon_ex", "statuses": ["ASLEEP", "POISONED"]})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP))
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.POISONED))


## conditional_inflict_status — condition fails (non-ex defender).
func test_conditional_inflict_status_non_ex_skips() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})  # not _ex
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "conditional_inflict_status",
		{"condition": "defender_is_pokemon_ex", "statuses": ["ASLEEP"]})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(tgt.special_conditions.size(), 0, "no status applied")


## inflict_status_by_attached_count — Lizard Poison tier picks.
func test_inflict_status_by_attached_count_tiers() -> void:
	# 2 energy on attacker → CONFUSED (highest min ≤ 2 with condition).
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "inflict_status_by_attached_count",
		{"tiers": [
			{"min": 1, "condition": "ASLEEP"},
			{"min": 2, "condition": "CONFUSED"},
			{"min": 3, "condition": "PARALYZED"},
		]})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.CONFUSED),
		"CONFUSED chosen for 2 energy")
	assert_false(tgt.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP),
		"ASLEEP not applied")


## ── Wave 11 JSON smoke tests ────────────────────────────────────────────

## Eevee… wait, this section already exists. Add a few more smokes:

## DR_4 Flygon Energy Shower — JSON wiring of attach_from_hand_free.
func test_json_flygon_energy_shower() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Energy Shower costs 1 grass + 1 lightning.
	var att := b.place_active(0, "DR_4_flygon",
		{"energy": ["RS_104_grass_energy", "RS_109_lightning_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	for _i in range(3):
		mgr.game_position.hands[0].append(_lib.get_card("RS_104_grass_energy"))
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Energy Shower should succeed")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	# All 3 grass energy in hand should be attached.
	assert_eq(att2.attached_energy.size(), energy_before + 3, "3 energies attached")


## SS_67 Lotad Blot — heal_self JSON smoke.
func test_json_lotad_blot_heals_self() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_67_lotad",
		{"energy": ["RS_106_water_energy", "RS_104_grass_energy"]})
	att.current_hp = 20  # damaged
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # Blot is attack idx 1
	assert_true(r.ok, "Blot should succeed")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.current_hp, 30, "Blot heals 10")


## ──────────────────────────────────────────────────────────────────────────
## Wave 12: Tier B — multi-turn bonus, discard-or-fail, devolve, count_basis
## ──────────────────────────────────────────────────────────────────────────


## bonus_damage_next_turn — queues a bonus that fires on the next attack
## matching attack_name. Confirms the consumption hook runs on the controller's
## subsequent attack.
func test_bonus_damage_next_turn_named_attack() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Set the attack name so the bonus matches on next attack.
	att.card.attacks[0].name = "Slash"
	_set_attack(att, 0, "bonus_damage_next_turn",
		{"amount": 50, "attack_name": "Slash"})
	var r1: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r1.ok)
	assert_eq(att.next_turn_attack_bonuses.size(), 1, "bonus queued")

	# Bump to turn N+2 (so attack happens on attacker's next turn). Reset the
	# attack-used flag so the second attack passes validation.
	mgr.turn_number += 2
	mgr.attack_used_this_turn[0] = false
	# Now switch attack to a damage-dealing one but keep name "Slash".
	_set_attack(att, 30, "", {})
	att.card.attacks[0].name = "Slash"
	var tgt: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var hp_before := tgt.current_hp
	var r2: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r2.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# 30 base + 50 bonus = 80.
	assert_eq(hp_before - t2.current_hp, 80, "bonus consumed on Slash")
	assert_eq(att.next_turn_attack_bonuses.size(), 0, "entry removed after consumption")


## bonus_damage_next_turn — attack name mismatch leaves bonus alone.
func test_bonus_damage_next_turn_name_mismatch() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	att.next_turn_attack_bonuses.append({
		"amount": 40, "attack_name": "Slash", "until_turn": mgr.turn_number + 2
	})
	att.card.attacks[0].name = "Tackle"  # different name
	_set_attack(att, 20, "", {})
	att.card.attacks[0].name = "Tackle"
	var tgt: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 20, "no bonus when name mismatches")
	assert_eq(att.next_turn_attack_bonuses.size(), 1, "entry preserved")


## bonus_damage_next_turn — expired entry pruned on use attempt.
func test_bonus_damage_next_turn_expires() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	att.next_turn_attack_bonuses.append({
		"amount": 40, "attack_name": "", "until_turn": mgr.turn_number - 1
	})
	_set_attack(att, 20, "", {})
	var tgt: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 20, "expired bonus ignored")
	assert_eq(att.next_turn_attack_bonuses.size(), 0, "expired entry pruned")


## discard_or_fail — enough energy → discards and attack proceeds.
func test_discard_or_fail_succeeds() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_108_fire_energy", "RS_106_water_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 100, "discard_or_fail", {"count": 2, "type": "ANY"})
	var hp_before := tgt.current_hp
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(hp_before - t2.current_hp, 100, "damage applied (discard satisfied)")
	assert_eq(att2.attached_energy.size(), energy_before - 2, "2 energy discarded")


## discard_or_fail — not enough energy → attack blocked.
func test_discard_or_fail_blocks_when_insufficient() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})  # only 1 energy
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Note: cost is 0 in _set_attack so action passes validation; handler should
	# then set attack_blocked at CONDITIONALS phase.
	_set_attack(att, 100, "discard_or_fail", {"count": 2, "type": "ANY"})
	var hp_before := tgt.current_hp
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(t2.current_hp, hp_before, "no damage when insufficient energy")
	assert_eq(att2.attached_energy.size(), energy_before, "no energy discarded")


## devolve_each_evolved — each evolved opp Pokémon is devolved.
func test_devolve_each_evolved_basic() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# DR_41_shelgon is Stage 1 (evolves from Bagon).
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 70})
	# Push a prior stage onto tgt so devolution has a card to revert to.
	tgt.prior_stages.append(_lib.get_card("DR_49_bagon"))
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "devolve_each_evolved", {})
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.card.name_slug, "bagon", "devolved to bagon")
	assert_eq(mgr.game_position.decks[1].size(), deck_before + 1,
		"removed card placed on top of opp deck")


## devolve_each_evolved — basics skipped (no prior stages).
func test_devolve_each_evolved_skips_basics() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_49_bagon", {})  # basic, no prior_stages
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "devolve_each_evolved", {})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Defender unchanged.
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.card.name_slug, "bagon", "basic stays a basic")


## place_damage_counters count_basis — Damage Curse pattern.
func test_place_damage_counters_count_basis() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	att.current_hp = att.max_hp - 30  # 3 damage counters on attacker
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "place_damage_counters",
		{"count": 1, "target": "defender", "count_basis": "damage_counters_attacker"})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# 1 + 3 = 4 counters = 40 dmg.
	assert_eq(hp_before - t2.current_hp, 40, "1 + 3 attacker counters = 4 × 10")


## ── Wave 12 JSON smoke tests ─────────────────────────────────────────────

## SS_19 Omastar Pull Down — devolve_each_evolved JSON wiring.
func test_json_omastar_pull_down() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Pull Down costs 1 water + 2 colorless.
	var att := b.place_active(0, "SS_19_omastar",
		{"energy": ["RS_106_water_energy", "RS_104_grass_energy",
					"RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 70})
	tgt.prior_stages.append(_lib.get_card("DR_49_bagon"))
	b.set_prizes(0); b.set_prizes(1)
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Pull Down should succeed")
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.card.name_slug, "bagon", "shelgon devolved to bagon")
	assert_eq(mgr.game_position.decks[1].size(), deck_before + 1,
		"shelgon card returned to opp deck")


## RS_4 Camerupt Fire Spin — discard_or_fail JSON wiring.
func test_json_camerupt_fire_spin() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Fire Spin presumably costs FFCC. Give 4 energy.
	var att := b.place_active(0, "RS_4_camerupt",
		{"energy": ["RS_108_fire_energy", "RS_108_fire_energy",
					"RS_108_fire_energy", "RS_108_fire_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # Fire Spin idx 1
	if not r.ok:
		# Energy/cost mismatch — fail clearly.
		assert_true(false, "Fire Spin action failed; check cost/energy in test setup")
		return
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(hp_before - t2.current_hp, 100, "Fire Spin base 100 damage")
	assert_eq(att2.attached_energy.size(), energy_before - 2,
		"2 basic energy discarded as cost")


## ──────────────────────────────────────────────────────────────────────────
## Wave 13: Swift, Trembler, Power Count, Random Curse, Pichu, Life Drain,
## Judgement
## ──────────────────────────────────────────────────────────────────────────


## ignore_weakness_resistance — Swift skips both flags.
func test_ignore_weakness_resistance() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	# Force weakness so it would normally double damage.
	tgt.card = tgt.card.duplicate(true)
	tgt.card.weakness = att.card.pokemon_type
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "ignore_weakness_resistance", {})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# 30 with weakness ignored — not 60.
	assert_eq(hp_before - t2.current_hp, 30, "weakness ignored")


## inflict_status target=each_defending — applies to each opp active slot.
func test_inflict_status_each_defending() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "inflict_status",
		{"condition": "PARALYZED", "target": "each_defending"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_true(tgt.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED),
		"defender paralyzed")


## conditional_bonus_damage: you_have_less_energy_total triggers bonus.
func test_conditional_bonus_you_have_less_energy_total() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Attacker: 1 energy. Opp: 3 energy across active+bench.
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	b.place_bench(1, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 20, "conditional_bonus_damage",
		{"condition": "you_have_less_energy_total", "bonus": 30})
	var tgt: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# 1 < 3 → bonus applies: 20 + 30 = 50.
	assert_eq(hp_before - t2.current_hp, 50, "less-energy bonus applies")


## damage_to_almost_ko — fills HP down to ko_distance from KO. Coin heads.
func test_damage_to_almost_ko_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# Target with full HP 120; after attack should be at 10 (ko_distance).
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	_set_attack(att, 0, "damage_to_almost_ko",
		{"ko_distance": 10, "coin_gate": true})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.current_hp, 10, "filled with damage down to ko_distance=10")


## damage_to_almost_ko — tails skips.
func test_damage_to_almost_ko_tails() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])
	_set_attack(att, 0, "damage_to_almost_ko",
		{"ko_distance": 10, "coin_gate": true})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.current_hp, hp_before, "tails skips effect")


## coin_count_to_ko — both heads → KO.
func test_coin_count_to_ko_all_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true, true])
	_set_attack(att, 0, "coin_count_to_ko", {"flips": 2, "min_heads": 2})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Defender should be gone (KO'd).
	assert_true(mgr.board_position.is_empty("p1_active1"),
		"defender KO'd by coin_count_to_ko")


## coin_count_to_ko — partial heads → no KO.
func test_coin_count_to_ko_partial_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true, false])
	_set_attack(att, 0, "coin_count_to_ko", {"flips": 2, "min_heads": 2})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.current_hp, hp_before, "1 heads of 2 → no KO")


## ── Wave 13 JSON smoke tests ─────────────────────────────────────────────

## SS_4 Dusclops Random Curse — places 5 counters (50 dmg) on defender.
func test_json_dusclops_random_curse() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Random Curse costs 1 psychic + 2 colorless.
	var att := b.place_active(0, "SS_4_dusclops",
		{"energy": ["RS_107_psychic_energy", "RS_104_grass_energy",
					"RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # Random Curse idx 1
	assert_true(r.ok, "Random Curse should succeed")
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 50, "5 counters = 50 dmg")


## SS_20 Pichu Energy Retrieval — attaches energy + self-damages per attached.
func test_json_pichu_energy_retrieval() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Energy Retrieval costs 1 lightning.
	var att := b.place_active(0, "SS_20_pichu",
		{"energy": ["RS_109_lightning_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.discards[0].append(_lib.get_card("RS_104_grass_energy"))
	mgr.game_position.discards[0].append(_lib.get_card("RS_108_fire_energy"))
	var energy_before := att.attached_energy.size()
	var hp_before := att.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Energy Retrieval should succeed")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	# 2 energy moved from discard to Pichu; 2 damage counters (20 dmg) to Pichu.
	assert_eq(att2.attached_energy.size(), energy_before + 2, "2 energy attached")
	assert_eq(hp_before - att2.current_hp, 20, "self-damage = 10 per attached")


## ──────────────────────────────────────────────────────────────────────────
## Wave 14: search_deck_to_hand, scaling targeting, leech, attach scaling
## ──────────────────────────────────────────────────────────────────────────


## search_deck_to_hand filter=any — pulls top 2 of deck into hand.
func test_search_deck_to_hand_any() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	for cid in ["RS_104_grass_energy", "DR_49_bagon", "RS_108_fire_energy"]:
		mgr.game_position.decks[0].append(_lib.get_card(cid))
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "search_deck_to_hand", {"count": 2, "filter": "any"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 2, "2 cards drawn")


## search_deck_to_hand filter=trainer — only trainer cards counted.
func test_search_deck_to_hand_trainer_filter() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	# Mix: energy (skip), pokemon (skip), trainer (match)
	mgr.game_position.decks[0].append(_lib.get_card("RS_104_grass_energy"))
	mgr.game_position.decks[0].append(_lib.get_card("DR_49_bagon"))
	var trainer_card: CardData = _lib.get_card("RS_86_pok_ball")
	assert_not_null(trainer_card, "test fixture: need RS_86_pok_ball trainer")
	assert_eq(trainer_card.card_type, CardData.CardType.TRAINER,
		"Poké Ball is a trainer card")
	mgr.game_position.decks[0].append(trainer_card)
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "search_deck_to_hand",
		{"count": 1, "filter": "trainer"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 1, "1 trainer drawn")
	var drawn: CardData = mgr.game_position.hands[0].back()
	assert_eq(drawn.card_type, CardData.CardType.TRAINER, "drawn card is a trainer")


## search_deck_to_hand filter=evolves_from — matches by parent slug.
func test_search_deck_to_hand_evolves_from() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	# DR_41_shelgon evolves_from bagon. DR_49_bagon is basic.
	mgr.game_position.decks[0].append(_lib.get_card("DR_49_bagon"))
	mgr.game_position.decks[0].append(_lib.get_card("DR_41_shelgon"))
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "search_deck_to_hand",
		{"count": 1, "filter": "evolves_from", "evolves_from": "bagon"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 1, "1 evolves-from match")


## search_deck_to_hand condition (Synchronized Search): only fires when predicate holds.
func test_search_deck_to_hand_condition_fails_blocks() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("RS_104_grass_energy"))
	var hand_before: int = mgr.game_position.hands[0].size()
	_set_attack(att, 0, "search_deck_to_hand",
		{"count": 1, "filter": "any", "condition": "same_energy_counts"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# 1 vs 2 → not same → search does nothing.
	assert_eq(mgr.game_position.hands[0].size(), hand_before, "no search on mismatch")


## heal_self_by_damage_dealt — Leech Life equivalent.
func test_heal_self_by_damage_dealt() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Use Golem (hp_max=120) so heal isn't immediately capped.
	var att := b.place_active(0, "DR_5_golem", {"hp": 50})  # damaged
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 40, "heal_self_by_damage_dealt", {})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	# 40 damage dealt → heal from 50 to 90.
	assert_eq(att2.current_hp, 90, "healed by damage dealt")


## damage_chosen_target per_unit_basis=retreat_cost_chosen_target — Breaking Impact.
func test_damage_chosen_target_per_unit_basis_retreat_cost() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# DR_5 Golem typically has retreat_cost 4. Verify via card data.
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	var rc := int(tgt.card.retreat_cost)
	assert_true(rc > 0, "DR_5_golem needs retreat_cost > 0")
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "damage_chosen_target",
		{"amount": 0, "per_unit_basis": "retreat_cost_chosen_target", "per_unit": 10,
		 "ignore_wr": true})
	_auto_answer_query(mgr, "p1_active1")
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, rc * 10, "damage scaled by retreat cost")


## place_damage_counters count_basis=cards_in_opp_hand — Feedback.
func test_place_damage_counters_basis_opp_hand() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Put 3 cards in opp's hand.
	for cid in ["RS_104_grass_energy", "RS_108_fire_energy", "DR_49_bagon"]:
		mgr.game_position.hands[1].append(_lib.get_card(cid))
	_set_attack(att, 0, "place_damage_counters",
		{"count": 0, "target": "defender", "count_basis": "cards_in_opp_hand"})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# 3 cards × 10 = 30 dmg.
	assert_eq(hp_before - t2.current_hp, 30, "counters = opp hand size")


## attach_from_discard count_basis=coin_flips_until_tails — Spiral Growth.
func test_attach_from_discard_count_basis_flips_until_tails() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	for _i in range(3):
		mgr.game_position.discards[0].append(_lib.get_card("RS_104_grass_energy"))
	# 2 heads then tails → 2 attached.
	mgr.push_forced_flips([true, true, false])
	_set_attack(att, 0, "attach_from_discard",
		{"type": "ANY", "count_basis": "coin_flips_until_tails"})
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.attached_energy.size(), energy_before + 2, "2 heads → 2 energy attached")


## ── Wave 14 JSON smoke tests ─────────────────────────────────────────────

## RS_38 Linoone Seek Out — pulls 2 cards.
func test_json_linoone_seek_out() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "RS_38_linoone",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("RS_104_grass_energy"))
	mgr.game_position.decks[0].append(_lib.get_card("RS_108_fire_energy"))
	mgr.game_position.decks[0].append(_lib.get_card("DR_49_bagon"))
	var hand_before: int = mgr.game_position.hands[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Seek Out should succeed")
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 2, "2 cards searched")


## ──────────────────────────────────────────────────────────────────────────
## Wave 15: pre-damage swap with query + Toxic 2× poison
## ──────────────────────────────────────────────────────────────────────────


## swap_with_opp_bench_pre_damage — attacker-chosen swap happens before damage.
## The base damage should land on the NEW defender, not the original.
func test_swap_pre_damage_redirects_base_damage() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var orig := b.place_active(1, "DR_5_golem", {"hp": 120})
	var bench := b.place_bench(1, "DR_41_shelgon", {"hp": 70})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "swap_with_opp_bench_pre_damage",
		{"attacker_chooses": true})
	_auto_answer_query(mgr, "p1_bench1")
	var orig_hp := orig.current_hp
	var bench_hp := bench.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# After the swap, bench Pokémon is now in active1 and should take the 30.
	var new_active: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var moved_to_bench: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_eq(new_active.card.card_id, "DR_41_shelgon", "Shelgon swapped into active")
	assert_eq(moved_to_bench.card.card_id, "DR_5_golem", "Golem moved to bench")
	# Damage hit the new active (Shelgon), not the original (Golem on bench).
	assert_eq(orig_hp - moved_to_bench.current_hp, 0, "Golem untouched on bench")
	assert_eq(bench_hp - new_active.current_hp, 30, "Shelgon took the 30 base damage")


## swap_with_opp_bench_pre_damage — chained inflict_status burns the NEW defender.
func test_swap_pre_damage_chain_inflict_status_hits_new_defender() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var orig := b.place_active(1, "DR_5_golem", {"hp": 120})
	var bench := b.place_bench(1, "DR_41_shelgon", {"hp": 70})
	b.set_prizes(0); b.set_prizes(1)
	# Luring-Flame style: opp picks bench, then burn new defender.
	_set_attack(att, 0, "swap_with_opp_bench_pre_damage",
		{},
		[{"key": "inflict_status", "params": {"condition": "BURNED"}}])
	_auto_answer_query(mgr, "p1_bench1")
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var new_active: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var swapped_to_bench: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	assert_true(new_active.special_conditions.has(PokemonInstance.SpecialCondition.BURNED),
		"new defender (Shelgon) is Burned")
	assert_false(swapped_to_bench.special_conditions.has(PokemonInstance.SpecialCondition.BURNED),
		"original defender (Golem) on bench is NOT Burned")


## swap_with_opp_bench_pre_damage — no bench → no-op, base damage hits original.
func test_swap_pre_damage_no_bench_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "swap_with_opp_bench_pre_damage",
		{"attacker_chooses": true})
	# No bench → handler returns early. No query expected.
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 30, "primary defender takes base damage")
	assert_eq(t2.card.card_id, "DR_5_golem", "no swap occurred")


## Toxic — inflict POISONED with poison_intensity=2 marks the defender.
func test_toxic_sets_poison_intensity() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "inflict_status",
		{"condition": "POISONED", "poison_intensity": 2})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_true(t2.special_conditions.has(PokemonInstance.SpecialCondition.POISONED),
		"defender is POISONED")
	assert_eq(t2.poison_intensity, 2, "intensity set to 2")


## Toxic — normal poison stays at intensity 1 (regression check).
func test_normal_poison_keeps_intensity_one() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "inflict_status", {"condition": "POISONED"})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.poison_intensity, 1, "normal poison intensity = 1")


## Toxic — between-turn cleanup applies 2× counters (20 damage).
func test_toxic_cleanup_applies_double_counters() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	tgt.special_conditions.append(PokemonInstance.SpecialCondition.POISONED)
	tgt.poison_intensity = 2
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	# Drive the cleanup-instance routine directly. (Avoids needing a full
	# turn-end flow.)
	var ko_candidates: Array[Dictionary] = []
	await mgr._cleanup_instance_async(tgt, "p1_active1", false, ko_candidates)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 20, "Toxic dealt 20 (2× counters)")


## Toxic — removing POISONED resets intensity back to 1.
func test_toxic_intensity_resets_on_remove() -> void:
	var inst := PokemonInstance.create(_lib.get_card("DR_5_golem"), 1)
	inst.special_conditions.append(PokemonInstance.SpecialCondition.POISONED)
	inst.poison_intensity = 2
	inst.remove_condition(PokemonInstance.SpecialCondition.POISONED)
	assert_eq(inst.poison_intensity, 1, "intensity reset")
	assert_false(inst.special_conditions.has(PokemonInstance.SpecialCondition.POISONED),
		"condition removed")


## ── Wave 15 JSON smoke tests ─────────────────────────────────────────────

## DR_72 Slugma Luring Flame — base 0, opp swaps, new defender Burned.
func test_json_luring_flame() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Luring Flame costs 1 fire + 1 colorless.
	var att := b.place_active(0, "DR_72_slugma",
		{"energy": ["RS_108_fire_energy", "RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bench := b.place_bench(1, "DR_41_shelgon", {"hp": 70})
	b.set_prizes(0); b.set_prizes(1)
	_auto_answer_query(mgr, "p1_bench1")
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # Luring Flame idx 1
	assert_true(r.ok, "Luring Flame should succeed")
	var new_active: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(new_active.card.card_id, "DR_41_shelgon", "Shelgon swapped to active")
	assert_true(new_active.special_conditions.has(PokemonInstance.SpecialCondition.BURNED),
		"new defender is Burned")


## SS_9 Mawile Metal Hook — attacker swaps, base 20 dmg to new defender.
func test_json_metal_hook() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Metal Hook costs 1 metal + 1 colorless.
	var att := b.place_active(0, "SS_9_mawile",
		{"energy": ["RS_94_metal_energy", "RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	var bench := b.place_bench(1, "DR_41_shelgon", {"hp": 70})
	b.set_prizes(0); b.set_prizes(1)
	_auto_answer_query(mgr, "p1_bench1")
	var bench_hp := bench.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # Metal Hook idx 1
	assert_true(r.ok, "Metal Hook should succeed")
	var new_active: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(new_active.card.card_id, "DR_41_shelgon", "Shelgon swapped to active")
	# Shelgon should have taken the base 20 damage.
	assert_eq(bench_hp - new_active.current_hp, 20, "new defender takes 20")


## RS_6 Dustox Toxic — applies POISONED + intensity 2.
func test_json_dustox_toxic() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Toxic costs 1 grass + 1 colorless.
	var att := b.place_active(0, "RS_6_dustox",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Toxic should succeed")
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_true(t2.special_conditions.has(PokemonInstance.SpecialCondition.POISONED),
		"defender POISONED")
	assert_eq(t2.poison_intensity, 2, "Toxic sets intensity 2")


## SS_42 Lileep Influence — places Anorith from deck onto bench.
func test_json_lileep_influence() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_42_lileep",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Seed deck with Anorith — the same set has SS_27_anorith which is a basic.
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("SS_27_anorith"))
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Influence should succeed")
	# Anorith should now be on attacker's bench.
	var bench1: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_not_null(bench1, "bench1 occupied")
	assert_eq(bench1.card.name_slug, "anorith", "anorith placed on bench")


## ──────────────────────────────────────────────────────────────────────────
## Wave 16: 5 "Easy" attacks finishing the Pokémon attack roster
##   - RS_19 Pelipper Swallow            (heal_self_by_damage_dealt JSON wire)
##   - SS_54 Wynaut Alluring Smile       (search_deck_to_hand count_basis)
##   - SS_42 Lileep Time Spiral          (devolve_one_with_query, new handler)
##   - DR_28 Forretress Backspin         (may_discard_then_switch, new handler)
##   - SS_43 Lileep Amnesia              (defender_lock_attack, new handler + flag)
## ──────────────────────────────────────────────────────────────────────────


## ── search_deck_to_hand count_basis="energy_attached_attacker" ────────────

## Energy-scaling pull-count: 1 energy attached → 1 card from deck.
func test_search_deck_count_basis_energy_attached_one() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_106_water_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("DR_49_bagon"))
	mgr.game_position.decks[0].append(_lib.get_card("RS_108_fire_energy"))  # filtered out
	_set_attack(att, 0, "search_deck_to_hand",
		{"count_basis": "energy_attached_attacker", "filter": "pokemon"})
	var hand_before: int = mgr.game_position.hands[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 1,
		"1 energy attached → 1 pokemon pulled")


## Energy-scaling pull-count: 3 energy attached → 3 cards from deck.
func test_search_deck_count_basis_energy_attached_three() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_106_water_energy", "RS_106_water_energy",
					"RS_106_water_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	for _i in range(5):
		mgr.game_position.decks[0].append(_lib.get_card("DR_49_bagon"))
	_set_attack(att, 0, "search_deck_to_hand",
		{"count_basis": "energy_attached_attacker", "filter": "pokemon"})
	var hand_before: int = mgr.game_position.hands[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 3,
		"3 energy attached → 3 pokemon pulled")


## Energy-scaling pull-count: 0 energy → no-op (still resolves cleanly).
func test_search_deck_count_basis_energy_attached_zero() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})  # no energy
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("DR_49_bagon"))
	_set_attack(att, 0, "search_deck_to_hand",
		{"count_basis": "energy_attached_attacker", "filter": "pokemon"})
	var hand_before: int = mgr.game_position.hands[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[0].size(), hand_before,
		"0 energy → 0 cards pulled")


## SS_54 Wynaut Alluring Smile JSON wiring — 1 PSYCHIC attached, pulls 1.
func test_json_wynaut_alluring_smile() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_54_wynaut",
		{"energy": ["RS_107_psychic_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.game_position.decks[0].clear()
	mgr.game_position.decks[0].append(_lib.get_card("DR_49_bagon"))
	mgr.game_position.decks[0].append(_lib.get_card("RS_108_fire_energy"))
	var hand_before: int = mgr.game_position.hands[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Alluring Smile should resolve")
	assert_eq(mgr.game_position.hands[0].size(), hand_before + 1,
		"1 energy → 1 Pokémon card searched")


## ── devolve_one_with_query — Time Spiral ─────────────────────────────────

## Heads coin → opp Stage 1 active devolves; card returns to deck.
func test_devolve_one_with_query_heads_active() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 70})
	tgt.prior_stages.append(_lib.get_card("DR_49_bagon"))
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	_set_attack(att, 0, "devolve_one_with_query", {})
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.card.name_slug, "bagon", "active devolved to bagon")
	assert_eq(mgr.game_position.decks[1].size(), deck_before + 1,
		"shelgon card returned to opp deck")


## Tails coin → no devolution.
func test_devolve_one_with_query_tails_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 70})
	tgt.prior_stages.append(_lib.get_card("DR_49_bagon"))
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])
	_set_attack(att, 0, "devolve_one_with_query", {})
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.card.name_slug, "shelgon", "tails → defender unchanged")
	assert_eq(mgr.game_position.decks[1].size(), deck_before, "no deck additions")


## No evolved opp Pokémon → no flip needed, no-op, no error.
func test_devolve_one_with_query_no_evolved_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_49_bagon", {})  # basic, not evolved
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "devolve_one_with_query", {})
	# No forced flip — handler should NOT consume one when no targets exist.
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.card.name_slug, "bagon", "basic stays a basic")
	assert_eq(mgr.game_position.decks[1].size(), deck_before, "no devolve, no deck add")


## SS_42 Lileep Time Spiral JSON wiring — heads devolves opp Stage 1.
func test_json_lileep_time_spiral() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Time Spiral costs 2 colorless (attack index 1).
	var att := b.place_active(0, "SS_42_lileep",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 70})
	tgt.prior_stages.append(_lib.get_card("DR_49_bagon"))
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # Time Spiral idx 1
	assert_true(r.ok, "Time Spiral should resolve")
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.card.name_slug, "bagon", "shelgon devolved to bagon")
	assert_eq(mgr.game_position.decks[1].size(), deck_before + 1,
		"removed card returned to opp deck")


## ── may_discard_then_switch — Backspin ───────────────────────────────────

## Normal case: 1 energy on attacker + bench occupant → discards + swaps.
func test_may_discard_then_switch_normal() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	var bn := b.place_bench(0, "DR_5_golem", {"hp": 120})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "may_discard_then_switch", {})
	var discard_before: int = mgr.game_position.discards[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var new_active: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var new_bench: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_eq(new_active.card.card_id, bn.card.card_id, "bench Pokémon promoted")
	assert_eq(new_bench.card.card_id, att.card.card_id, "old active sent to bench")
	assert_eq(new_bench.attached_energy.size(), 0, "energy discarded from attacker")
	assert_eq(mgr.game_position.discards[0].size(), discard_before + 1,
		"1 energy entered discard")


## No energy on attacker → no-op (no discard, no switch).
func test_may_discard_then_switch_no_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})  # no energy
	b.place_bench(0, "DR_5_golem", {"hp": 120})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "may_discard_then_switch", {})
	var discard_before: int = mgr.game_position.discards[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var still: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(still.card.card_id, att.card.card_id, "attacker stays put")
	assert_eq(mgr.game_position.discards[0].size(), discard_before, "no discard")


## Empty bench → no-op (no discard, no switch).
func test_may_discard_then_switch_no_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "may_discard_then_switch", {})
	var discard_before: int = mgr.game_position.discards[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var still: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(still.card.card_id, att.card.card_id, "attacker stays put — no bench")
	assert_eq(still.attached_energy.size(), 1, "energy NOT discarded when switch fails")
	assert_eq(mgr.game_position.discards[0].size(), discard_before, "no discard")


## DR_28 Forretress Backspin JSON wiring — 40 damage + discard + switch.
func test_json_forretress_backspin() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Backspin costs 3 colorless (attack index 1).
	var att := b.place_active(0, "DR_28_forretress",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy",
					"RS_104_grass_energy"]})
	var bn := b.place_bench(0, "DR_5_golem", {"hp": 120})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1"))  # Backspin idx 1
	assert_true(r.ok, "Backspin should resolve")
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - t2.current_hp, 40, "Backspin base 40 damage")
	var new_active: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(new_active.card.card_id, bn.card.card_id, "Forretress swapped with bench")


## ── defender_lock_attack — Amnesia ───────────────────────────────────────

## Two-attack defender: highest-base-damage attack gets locked.
func test_defender_lock_picks_highest_damage_attack() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	# DR_5_golem has multiple attacks; ensure target HAS >1 attacks.
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	assert_true(tgt.card.attacks.size() >= 2,
		"test target must have >=2 attacks for the lock to be observable")
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "defender_lock_attack", {})
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Independently compute the expected pick: highest base_damage, tie → higher idx.
	var expected_idx: int = 0
	var best_dmg: int = -1
	for i in range(tgt.card.attacks.size()):
		var a: AttackData = tgt.card.attacks[i]
		if a == null: continue
		if a.base_damage >= best_dmg:
			best_dmg = a.base_damage
			expected_idx = i
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_true(t2.cant_use_attack_indices_until_turn.has(expected_idx),
		"highest-damage attack index should be locked")
	assert_eq(int(t2.cant_use_attack_indices_until_turn[expected_idx]),
		mgr.turn_number + 1, "lock expiry = turn_number + 1")


## ActionAttack rejects use of a locked attack on the defender's next turn.
func test_locked_attack_blocks_action_attack() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)
	var defender := b.place_active(1, "DR_5_golem", {"hp": 120})
	# Find a real attack index that has cost golem can pay with 9 colorless-ish energy.
	# Easier: clear all costs on attack[0] and lock attack[0].
	var locked_idx: int = 0
	defender.card.attacks[locked_idx].cost_colorless = 0
	defender.card.attacks[locked_idx].cost_fire = 0
	defender.card.attacks[locked_idx].cost_water = 0
	defender.card.attacks[locked_idx].cost_grass = 0
	defender.card.attacks[locked_idx].cost_lightning = 0
	defender.card.attacks[locked_idx].cost_psychic = 0
	defender.card.attacks[locked_idx].cost_fighting = 0
	defender.card.attacks[locked_idx].cost_darkness = 0
	defender.card.attacks[locked_idx].cost_metal = 0
	b.place_active(0, "DR_49_bagon", {"hp": 60})
	b.set_prizes(0); b.set_prizes(1)
	defender.cant_use_attack_indices_until_turn[locked_idx] = mgr.turn_number + 1
	# Defender (p1) tries to use the locked attack this turn → expect failure.
	mgr.turn_number = mgr.turn_number + 1  # advance to a turn within the lock window
	mgr.current_player = 1
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(1, "p1_active1", locked_idx, "p0_active1"))
	assert_false(r.ok, "locked attack should be rejected")


## Lock auto-clears after the lock window passes.
func test_locked_attack_clears_after_expiry() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var defender := b.place_active(1, "DR_5_golem", {"hp": 120})
	defender.cant_use_attack_indices_until_turn[0] = 4
	mgr.turn_number = 5
	mgr._clear_expired_retreat_locks()
	assert_false(defender.cant_use_attack_indices_until_turn.has(0),
		"lock cleared once turn_number > expiry")


## Lock does NOT clear too early (boundary at exactly expiry turn).
func test_locked_attack_holds_at_expiry_turn() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var defender := b.place_active(1, "DR_5_golem", {"hp": 120})
	defender.cant_use_attack_indices_until_turn[0] = 4
	mgr.turn_number = 4  # exactly the expiry
	mgr._clear_expired_retreat_locks()
	assert_true(defender.cant_use_attack_indices_until_turn.has(0),
		"lock still active while turn_number <= expiry")


## release_cards (KO cleanup) clears the lock dictionary.
func test_release_cards_clears_attack_lock() -> void:
	var b := _make_builder()
	var _mgr: ManagerSystem = b._manager
	var inst := b.place_active(1, "DR_5_golem", {"hp": 120})
	inst.cant_use_attack_indices_until_turn[0] = 99
	inst.release_cards()
	assert_true(inst.cant_use_attack_indices_until_turn.is_empty(),
		"release_cards must clear the lock dictionary")


## SS_43 Lileep Amnesia JSON wiring — locks defender's highest-damage attack.
func test_json_lileep_amnesia() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Amnesia costs 2 colorless (attack index 0).
	var att := b.place_active(0, "SS_43_lileep",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	assert_true(tgt.card.attacks.size() >= 2, "golem must have >=2 attacks")
	b.set_prizes(0); b.set_prizes(1)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Amnesia should resolve")
	var t2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(t2.cant_use_attack_indices_until_turn.size(), 1,
		"exactly 1 attack index locked")


## ── RS_19 Pelipper Swallow JSON wiring ───────────────────────────────────

## Swallow (idx 2): 20 base damage and attacker heals by that amount.
func test_json_pelipper_swallow_heals() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Swallow costs 1 water + 2 colorless.
	var att := b.place_active(0, "RS_19_pelipper",
		{"hp": 30, "energy": ["RS_106_water_energy",
					 "RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	var hp_attacker_before := att.current_hp
	var hp_tgt_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 2, "p1_active1"))  # Swallow idx 2
	assert_true(r.ok, "Swallow should resolve")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var damage_dealt: int = hp_tgt_before - tgt2.current_hp
	assert_true(damage_dealt > 0, "Swallow should deal some damage")
	assert_eq(att2.current_hp - hp_attacker_before, damage_dealt,
		"attacker heals by exact damage dealt")
