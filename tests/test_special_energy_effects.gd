extends GutTest
## Gameplay tests for the four special energies (Rainbow / Darkness / Metal /
## Multi).  Parsing & classification are covered by test_energy_audit.gd;
## this suite exercises the in-battle hooks added to ActionAttachEnergy,
## AttackResolver, and ActionAttack._check_energy.

var _lib: CardLibrary
var _attack_handlers: Node = null
var _ability_handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_attack_handlers = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_attack_handlers)
	_ability_handlers_node = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers_node)


func after_all() -> void:
	if _attack_handlers != null:
		_attack_handlers.queue_free()
		_attack_handlers = null
	if _ability_handlers_node != null:
		_ability_handlers_node.queue_free()
		_ability_handlers_node = null


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


## --- Rainbow Energy: on-attach damage counter ------------------------------

func test_rainbow_attach_places_one_damage_counter() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Bagon is a vanilla Basic with no on-attach Poké-Body.
	var inst := b.place_active(0, "DR_49_bagon")
	var rainbow := _lib.get_card("RS_95_rainbow_energy") as EnergyCardData
	mgr.game_position.put_in_hand(0, rainbow)
	var pre_hp: int = inst.current_hp

	var result: ActionResult = await mgr.request_action_async(
		ActionAttachEnergy.new(0, rainbow, "p0_active1")
	)
	assert_true(result.ok, "Rainbow attach should succeed.")
	assert_eq(pre_hp - inst.current_hp, 10,
		"Rainbow should place 1 damage counter (10 HP) on attach.")
	assert_eq(inst.attached_energy.size(), 1,
		"Rainbow Energy should be attached after the action.")


## --- Darkness Energy: +10 pre-W/R when attacker qualifies ------------------

func test_darkness_energy_unit_bonus_for_darkness_attacker() -> void:
	## Murkrow (RS) is a Darkness-type Basic — its primary type matches the gate.
	var card := _lib.get_card("SS_47_murkrow") as PokemonCardData
	assert_not_null(card, "SS_47_murkrow should exist in the pool.")
	var inst := PokemonInstance.create(card, 0)
	inst.attached_energy.append(_lib.get_card("RS_93_darkness_energy"))
	assert_eq(
		SpecialEnergyEffects.outgoing_attacker_bonus(inst), 10,
		"1× Darkness Energy on a Darkness Pokémon = +10."
	)
	inst.attached_energy.append(_lib.get_card("RS_93_darkness_energy"))
	assert_eq(
		SpecialEnergyEffects.outgoing_attacker_bonus(inst), 20,
		"Multiple Darkness Energies stack pre-W/R."
	)


func test_darkness_energy_no_bonus_for_non_darkness_attacker() -> void:
	## Bagon is Colorless (Dragon era prints as Colorless in this dataset).
	var card := _lib.get_card("DR_49_bagon") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	inst.attached_energy.append(_lib.get_card("RS_93_darkness_energy"))
	assert_eq(
		SpecialEnergyEffects.outgoing_attacker_bonus(inst), 0,
		"Non-Darkness attacker without 'Dark' in name = no bonus."
	)


## --- Metal Energy: -10 post-W/R when defender is Metal type ----------------

func test_metal_energy_unit_reduction_for_metal_defender() -> void:
	## Aron (RS) is a Metal Basic.
	var card := _lib.get_card("RS_49_aron") as PokemonCardData
	assert_not_null(card, "RS_49_aron should exist in the pool.")
	var inst := PokemonInstance.create(card, 0)
	inst.attached_energy.append(_lib.get_card("RS_94_metal_energy"))
	assert_eq(
		SpecialEnergyEffects.incoming_reduction(inst), 10,
		"1× Metal Energy on a Metal defender = -10."
	)
	inst.attached_energy.append(_lib.get_card("RS_94_metal_energy"))
	assert_eq(
		SpecialEnergyEffects.incoming_reduction(inst), 20,
		"Multiple Metal Energies stack post-W/R."
	)


func test_metal_energy_no_reduction_on_non_metal_defender() -> void:
	var card := _lib.get_card("DR_49_bagon") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	inst.attached_energy.append(_lib.get_card("RS_94_metal_energy"))
	assert_eq(
		SpecialEnergyEffects.incoming_reduction(inst), 0,
		"Non-Metal defender = no reduction."
	)


## --- Multi Energy: conditional type provision ------------------------------

func test_multi_alone_provides_wildcard() -> void:
	var card := _lib.get_card("RS_49_aron") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	var multi := _lib.get_card("SS_93_multi_energy") as EnergyCardData
	inst.attached_energy.append(multi)
	## Empty array == wildcard (matches any single cost slot).
	assert_eq(
		SpecialEnergyEffects.types_for_attached(inst, multi), [] as Array[int],
		"Multi alone should provide wildcard (empty types array)."
	)


func test_multi_degrades_to_colorless_when_another_special_attached() -> void:
	var card := _lib.get_card("RS_49_aron") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	var multi    := _lib.get_card("SS_93_multi_energy") as EnergyCardData
	var darkness := _lib.get_card("RS_93_darkness_energy") as EnergyCardData
	inst.attached_energy.append(multi)
	inst.attached_energy.append(darkness)
	assert_eq(
		SpecialEnergyEffects.types_for_attached(inst, multi),
		[int(PokemonCardData.EnergyType.COLORLESS)] as Array[int],
		"Multi alongside Darkness should degrade to Colorless-only."
	)


func test_two_multis_both_degrade() -> void:
	var card := _lib.get_card("RS_49_aron") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	var a := _lib.get_card("SS_93_multi_energy") as EnergyCardData
	var b := _lib.get_card("SS_93_multi_energy") as EnergyCardData
	inst.attached_energy.append(a)
	inst.attached_energy.append(b)
	assert_eq(
		SpecialEnergyEffects.types_for_attached(inst, a),
		[int(PokemonCardData.EnergyType.COLORLESS)] as Array[int],
		"Multi sees the other Multi as a special → degrades."
	)
	assert_eq(
		SpecialEnergyEffects.types_for_attached(inst, b),
		[int(PokemonCardData.EnergyType.COLORLESS)] as Array[int],
		"Symmetrically, second Multi also degrades."
	)


func test_rainbow_always_provides_wildcard() -> void:
	var card := _lib.get_card("RS_49_aron") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	var rainbow := _lib.get_card("RS_95_rainbow_energy") as EnergyCardData
	var darkness := _lib.get_card("RS_93_darkness_energy") as EnergyCardData
	inst.attached_energy.append(rainbow)
	inst.attached_energy.append(darkness)
	assert_eq(
		SpecialEnergyEffects.types_for_attached(inst, rainbow), [] as Array[int],
		"Rainbow has no degradation clause; always wildcard."
	)


## --- ActionAttack._check_energy: wildcard cost-paying ----------------------
##
## Build a synthetic attack cost and confirm the bucket accounting in
## _check_energy works for each special-energy combination.

func _make_attack(fire: int, water: int, colorless: int) -> AttackData:
	var a := AttackData.new()
	a.name = "TestAttack"
	a.cost_fire = fire
	a.cost_water = water
	a.cost_colorless = colorless
	return a


func test_rainbow_satisfies_typed_cost() -> void:
	var card := _lib.get_card("DR_49_bagon") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	inst.attached_energy.append(_lib.get_card("RS_95_rainbow_energy"))
	var attack := _make_attack(1, 0, 0)
	var r := ActionAttack._check_energy(inst, attack)
	assert_true(r.ok, "Rainbow should pay 1 Fire cost: %s" % r.reason)


func test_multi_alone_satisfies_two_different_typed_costs() -> void:
	var card := _lib.get_card("DR_49_bagon") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	inst.attached_energy.append(_lib.get_card("SS_93_multi_energy"))
	inst.attached_energy.append(_lib.get_card("SS_93_multi_energy"))
	## Two un-degraded Multi cards present? NO — each Multi sees the other as
	## a special and degrades to Colorless. Verify a Fire/Water cost fails.
	var attack := _make_attack(1, 1, 0)
	var r := ActionAttack._check_energy(inst, attack)
	assert_false(r.ok,
		"Two Multis attached should both degrade; can't pay Fire+Water.")


func test_one_multi_one_basic_pays_mixed_cost() -> void:
	var card := _lib.get_card("DR_49_bagon") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	## Basic energy is NOT a special, so Multi keeps its wildcard status.
	inst.attached_energy.append(_lib.get_card("RS_108_fire_energy"))
	inst.attached_energy.append(_lib.get_card("SS_93_multi_energy"))
	var attack := _make_attack(1, 1, 0)
	var r := ActionAttack._check_energy(inst, attack)
	assert_true(r.ok,
		"Fire (basic) + Multi (wildcard) should pay Fire+Water: %s" % r.reason)


func test_multi_with_darkness_pays_colorless_only() -> void:
	var card := _lib.get_card("DR_49_bagon") as PokemonCardData
	var inst := PokemonInstance.create(card, 0)
	inst.attached_energy.append(_lib.get_card("RS_93_darkness_energy"))
	inst.attached_energy.append(_lib.get_card("SS_93_multi_energy"))
	## Darkness pays Darkness or Colorless; degraded Multi pays Colorless only.
	## A Fire cost cannot be paid.
	var attack := _make_attack(1, 0, 0)
	var r := ActionAttack._check_energy(inst, attack)
	assert_false(r.ok,
		"Multi degraded by Darkness can't pay Fire; Darkness can't pay Fire.")
	## But a 2× Colorless cost is payable.
	var attack2 := _make_attack(0, 0, 2)
	var r2 := ActionAttack._check_energy(inst, attack2)
	assert_true(r2.ok, "Both energies count toward Colorless: %s" % r2.reason)
