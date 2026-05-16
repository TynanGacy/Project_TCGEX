extends GutTest
## GUT tests for Wave 2 Poké-Bodies.
##
## Covers:
##   - Beautifly "Withering Dust" — global Resistance disabled
##   - Shedinja "Wonder Guard" — source-class total immunity (Evolution/ex)
##   - Wobbuffet "Safeguard" — source-class immunity from ex only
##   - Whiscash "Submerge" — damage immunity while benched
##   - Kecleon "Energy Variation" — type morph from attached energy
##   - Aerodactyl ex "Primal Lock" — opponent Tool play locked
##   - Dustox "Protective Dust" — attack effects prevented (damage still lands)

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
	if _ability_handlers_node != null:
		_ability_handlers_node.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


## --- Beautifly: Withering Dust ---------------------------------------------

func test_withering_dust_baseline_resistance_applies() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Golem ex (Fighting, no abilities) attacking a vanilla Bagon (Colorless).
	## Patch Bagon's resistance to FIGHTING so W/R fires.
	var attacker := b.place_active(0, "DR_91_golem_ex",
		{"energy": ["RS_105_fighting_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	attacker.card.attacks[0].base_damage = 60
	attacker.card.attacks[0].effect_key = ""
	var target := b.place_active(1, "DR_49_bagon")
	## Boost instance HP without mutating the shared card resource — Bagon's
	## 40 HP would otherwise KO on the first 60-damage hit.
	target.max_hp = 200
	target.current_hp = 200
	target.card.resistance = PokemonCardData.EnergyType.FIGHTING
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp
	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	## 60 - 30 (resistance) = 30 damage.
	assert_eq(pre_hp - target.current_hp, 30,
		"Baseline: resistance should reduce 60 → 30.")


func test_withering_dust_disables_resistance_when_in_play() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var attacker := b.place_active(0, "DR_91_golem_ex",
		{"energy": ["RS_105_fighting_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	attacker.card.attacks[0].base_damage = 60
	attacker.card.attacks[0].effect_key = ""
	var target := b.place_active(1, "DR_49_bagon")
	## Boost instance HP without mutating the shared card resource — Bagon's
	## 40 HP would otherwise KO on the first 60-damage hit.
	target.max_hp = 200
	target.current_hp = 200
	target.card.resistance = PokemonCardData.EnergyType.FIGHTING
	## Beautifly on defender's bench → resistance globally disabled.
	b.place_bench(1, "RS_2_beautifly")
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp

	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_eq(pre_hp - target.current_hp, 60,
		"Withering Dust should disable resistance globally → full 60.")


## --- Shedinja: Wonder Guard ------------------------------------------------

func test_wonder_guard_blocks_evolved_attacker() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Attacker: Golem ex (STAGE2 — an Evolution AND a Pokémon-ex, no
	## interfering bodies). Either gate trips Wonder Guard.
	var attacker := b.place_active(0, "DR_91_golem_ex",
		{"energy": ["RS_105_fighting_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	attacker.card.attacks[0].base_damage = 50
	attacker.card.attacks[0].effect_key = ""
	var target := b.place_active(1, "DR_11_shedinja")
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp

	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_eq(target.current_hp, pre_hp,
		"Wonder Guard should block damage from an evolved attacker.")


func test_wonder_guard_allows_basic_non_ex_attacker() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Attacker: Bagon (BASIC, not ex). Should pierce Wonder Guard.
	var attacker := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	attacker.card.attacks[0].base_damage = 20
	attacker.card.attacks[0].effect_key = ""
	var target := b.place_active(1, "DR_11_shedinja")
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp

	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_eq(pre_hp - target.current_hp, 20,
		"Basic non-ex attacker should pierce Wonder Guard.")


## --- Wobbuffet: Safeguard --------------------------------------------------

func test_safeguard_blocks_ex_attacker() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Golem ex (Pokémon-ex, no abilities). Patch attack[0] (Magnitude) to
	## a single-target hit so it lands on Wobbuffet.
	var attacker := b.place_active(0, "DR_91_golem_ex",
		{"energy": ["RS_105_fighting_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	attacker.card.attacks[0].base_damage = 60
	attacker.card.attacks[0].effect_key = ""
	var target := b.place_active(1, "SS_26_wobbuffet")
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp

	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1")
	)
	assert_eq(target.current_hp, pre_hp,
		"Safeguard should block all damage from Pokémon-ex attackers.")


func test_safeguard_allows_non_ex_attacker() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var attacker := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	attacker.card.attacks[0].base_damage = 20
	attacker.card.attacks[0].effect_key = ""
	var target := b.place_active(1, "SS_26_wobbuffet")
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp

	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_eq(pre_hp - target.current_hp, 20,
		"Non-ex attacker should pierce Safeguard.")


## --- Whiscash: Submerge ----------------------------------------------------
##
## Submerge blocks damage to Whiscash while it's on Bench. Without a
## targets-bench-Pokémon attack in this pool, we exercise the helper directly.

func test_submerge_blocks_bench_damage_via_helper() -> void:
	var b   := _make_builder()
	b.set_turn(0)
	var bench: PokemonInstance = b.place_bench(1, "DR_48_whiscash")
	assert_true(AbilityEffects.bench_damage_blocked(bench, "p1_bench1"),
		"Submerge should block damage on a bench slot.")
	## Active slot — Submerge does NOT apply.
	assert_false(AbilityEffects.bench_damage_blocked(bench, "p1_active1"),
		"Submerge only applies while benched.")


## --- Kecleon: Energy Variation --------------------------------------------

func test_energy_variation_morphs_attacker_type_for_weakness() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Kecleon attacks Bagon. Bagon (DR_49) is Colorless with weakness=NONE.
	## Patch Bagon's weakness to FIRE and attach a Fire Energy to Kecleon
	## via Energy Variation; expect ×2 damage.
	var kecleon := b.place_active(0, "SS_18_kecleon",
		{"energy": ["RS_108_fire_energy", "RS_108_fire_energy"]})
	kecleon.card.attacks[0].base_damage = 20
	kecleon.card.attacks[0].effect_key = ""
	var target := b.place_active(1, "DR_49_bagon")
	target.card.weakness = PokemonCardData.EnergyType.FIRE
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp

	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	## Kecleon morphs to FIRE, hits FIRE weakness → 20 × 2 = 40.
	assert_eq(pre_hp - target.current_hp, 40,
		"Energy Variation should set Kecleon's type to FIRE → weakness x2.")


## --- Aerodactyl ex: Primal Lock --------------------------------------------

func test_primal_lock_blocks_opponent_tool_play() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)
	## Player 0 has Aerodactyl ex in active position. P1 is current player.
	b.place_active(0, "SS_94_aerodactyl_ex")
	var receiver := b.place_active(1, "DR_49_bagon")
	## Put a Tool card in P1's hand and try to attach to its own Pokemon.
	var tool: TrainerCardData = _lib.get_card("RS_84_lum_berry") as TrainerCardData
	assert_not_null(tool, "Lum Berry should exist as a TOOL card.")
	mgr.game_position.put_in_hand(1, tool)

	var result: ActionResult = await mgr.request_action_async(
		ActionAttachTool.new(1, tool, "p1_active1")
	)
	assert_false(result.ok, "Primal Lock should block Tool plays.")
	assert_true(receiver.attached_tools.is_empty(),
		"No tool should land on the receiver.")


func test_primal_lock_does_not_block_own_player() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Player 0 (the Primal Lock owner) should still be able to play Tools.
	b.place_active(0, "SS_94_aerodactyl_ex")
	var receiver := b.place_bench(0, "DR_49_bagon")
	var tool: TrainerCardData = _lib.get_card("RS_84_lum_berry") as TrainerCardData
	mgr.game_position.put_in_hand(0, tool)
	var result: ActionResult = await mgr.request_action_async(
		ActionAttachTool.new(0, tool, "p0_bench1")
	)
	assert_true(result.ok, "Primal Lock should NOT block its own player.")
	assert_eq(receiver.attached_tools.size(), 1,
		"Own-side Tool play should land.")


## --- Slaking: Lazy --------------------------------------------------------
##
## Lazy blocks opp Pokémon from using Poké-Powers while Slaking is the
## controller's Active. Test by trying to activate Sceptile's Energy Trans.

func _find_slot(mgr: ManagerSystem, inst: PokemonInstance) -> String:
	for pid in [0, 1]:
		for s in (BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS):
			var sid := "p%d_%s" % [pid, s]
			if mgr.board_position.get_instance(sid) == inst:
				return sid
	return ""


func test_slaking_lazy_blocks_opponent_power_activation() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)  ## P1 is current player.
	## P0 has Slaking active → opponent (P1) Powers are blocked.
	b.place_active(0, "RS_12_slaking")
	## P1 has Sceptile with Energy Trans on its bench, plus a target.
	var sceptile := b.place_active(1, "RS_20_sceptile",
		{"energy": ["RS_104_grass_energy"]})
	b.place_bench(1, "DR_49_bagon")
	var sceptile_slot := _find_slot(mgr, sceptile)
	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(1, sceptile_slot, 0)
	)
	assert_false(r.ok, "Slaking's Lazy should block opp Power activation.")


func test_slaking_lazy_does_not_block_own_player() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## P0 has Slaking active AND Sceptile on bench. Own player's powers
	## are unaffected.
	b.place_active(0, "RS_12_slaking")
	var sceptile := b.place_bench(0, "RS_20_sceptile",
		{"energy": ["RS_104_grass_energy"]})
	b.place_bench(0, "DR_49_bagon")
	var sceptile_slot := _find_slot(mgr, sceptile)
	## Auto-respond to Energy Trans's source/energy/dest prompts.
	## We need the first response (source) to be sceptile_slot, second
	## (energy choice) to be the grass card, third (dest) to be the bagon.
	## Easiest: route to refuse all picks → activation succeeds at VALIDATE
	## even if APPLY ends up doing nothing.
	var queries_sent: int = 0
	mgr.ability_resolver.player_query_requested.connect(
		func(_q: AbilityQuery) -> void:
			queries_sent += 1
			mgr.ability_resolver.resolve_query.call_deferred(null)
	)
	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, sceptile_slot, 0)
	)
	assert_true(r.ok, "Lazy should not block its own player's powers.")


## --- Muk ex: Toxic Gas ----------------------------------------------------

func test_toxic_gas_blocks_power_activation_on_both_sides() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## P1 has Muk ex active → all other powers ignored.
	b.place_active(1, "DR_96_muk_ex")
	## P0 has Sceptile (Energy Trans).
	var sceptile := b.place_active(0, "RS_20_sceptile",
		{"energy": ["RS_104_grass_energy"]})
	b.place_bench(0, "DR_49_bagon")
	var sceptile_slot := _find_slot(mgr, sceptile)
	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, sceptile_slot, 0)
	)
	assert_false(r.ok, "Toxic Gas should block Sceptile's Energy Trans.")


func test_toxic_gas_passive_body_suppression() -> void:
	## Muk ex on P1's Active suppresses every other Pokémon's body via
	## is_body_suppressed. The wider attack-pipeline integration is covered
	## by the wave1 body tests (which still pass because no Muk is present
	## in those scenarios).
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_49_bagon")
	b.place_active(1, "DR_96_muk_ex")
	var foreign := b.place_bench(1, "DR_71_pineco")
	assert_true(AbilityEffects.is_body_suppressed(foreign, mgr),
		"Toxic Gas active should suppress Pineco's body.")
	var muk_inst: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_false(AbilityEffects.is_body_suppressed(muk_inst, mgr),
		"Carrier's own body is exempt — Toxic Gas keeps suppressing.")


## --- Dustox: Protective Dust ----------------------------------------------

## --- Ampharos ex: Conductivity --------------------------------------------

func test_conductivity_places_damage_counter_on_opponent_energy_attach() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)  ## P1 is the attacher.
	## P0 has Ampharos ex in play.  P1 attaches energy to its own Pokémon.
	b.place_active(0, "DR_89_ampharos_ex")
	var receiver := b.place_active(1, "DR_49_bagon")
	var energy: EnergyCardData = _lib.get_card("RS_104_grass_energy") as EnergyCardData
	mgr.game_position.put_in_hand(1, energy)
	var pre_hp: int = receiver.current_hp

	var r: ActionResult = await mgr.request_action_async(
		ActionAttachEnergy.new(1, energy, "p1_active1")
	)
	assert_true(r.ok, "Energy attach should succeed.")
	assert_eq(pre_hp - receiver.current_hp, 10,
		"Conductivity should place 1 damage counter on the receiver.")


func test_conductivity_does_not_fire_on_own_attach() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## P0 owns Ampharos ex AND attaches energy on its own side. Conductivity
	## only fires when OPPONENT attaches.
	b.place_active(0, "DR_89_ampharos_ex")
	var receiver := b.place_bench(0, "DR_49_bagon")
	var energy: EnergyCardData = _lib.get_card("RS_104_grass_energy") as EnergyCardData
	mgr.game_position.put_in_hand(0, energy)
	var pre_hp: int = receiver.current_hp

	var r: ActionResult = await mgr.request_action_async(
		ActionAttachEnergy.new(0, energy, "p0_bench1")
	)
	assert_true(r.ok)
	assert_eq(pre_hp - receiver.current_hp, 0,
		"Conductivity should NOT fire on its own player's attach.")


func test_protective_dust_prevents_status_but_allows_damage() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Attacker: Bagon with patched 20-damage + Poisoned effect.
	var attacker := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	attacker.card.attacks[0].base_damage = 20
	attacker.card.attacks[0].effect_key = "inflict_status"
	attacker.card.attacks[0].effect_params = {"condition": "POISONED"}
	var target := b.place_active(1, "RS_6_dustox")
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp

	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_eq(pre_hp - target.current_hp, 20,
		"Damage should land normally; Protective Dust only blocks effects.")
	assert_false(
		target.special_conditions.has(PokemonInstance.SpecialCondition.POISONED),
		"Protective Dust should prevent the Poisoned application."
	)
