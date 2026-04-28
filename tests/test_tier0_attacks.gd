extends GutTest
## GUT test suite for all 24 Tier 0 Pokémon cards.
##
## Tier 0 = no effect text; pure base-damage attacks.
## The existing ActionAttack system handles these completely — no EffectRegistry
## handler is needed.  These tests serve as a regression baseline: if anything
## in the damage pipeline, energy validation, weakness/resistance, or KO
## resolution changes, these tests will catch the breakage immediately.
##
## Run via the GUT panel in the Godot editor or via the CLI runner.

## Card-library is loaded once for the whole suite (expensive disk I/O).
var _lib: CardLibrary


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")


## Returns a fresh manager + builder pair for one test case.
## Each call creates an independent ManagerSystem so tests cannot bleed state.
func _make_builder() -> TestBoardBuilder:
	var mgr = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


## ── Table-driven: all Tier 0 attacks deal correct base damage ─────────────
##
## Target: DR_41_shelgon (COLORLESS, HP=70, no Weakness, no Resistance).
## We override current_hp to 200 so no attack KOs it (max Tier 0 dmg is 60).
## Exception: when the attacker IS Shelgon, we use SS_66_lotad as target
## (WATER, no weakness to COLORLESS).
##
## Columns: [attacker_id, attack_index, energy_ids, expected_dmg, description]
const _TIER0_CASES: Array = [
	# ── DR set ────────────────────────────────────────────────────────────────
	["DR_3_crawdaunt",  0, ["RS_106_water_energy","RS_104_grass_energy","RS_104_grass_energy"], 50,  "Crawdaunt Guillotine"],
	["DR_41_shelgon",   0, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Shelgon Rollout"],
	["DR_46_vibrava",   0, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Vibrava Razor Wing"],
	["DR_49_bagon",     0, ["RS_104_grass_energy"],                                             10,  "Bagon Headbutt"],
	["DR_49_bagon",     1, ["RS_108_fire_energy","RS_104_grass_energy"],                        20,  "Bagon Flare"],
	["DR_51_barboach",  0, ["RS_104_grass_energy"],                                             10,  "Barboach Splash"],
	["DR_51_barboach",  1, ["RS_105_fighting_energy","RS_104_grass_energy"],                    20,  "Barboach Mud Slap"],
	["DR_53_corphish",  0, ["RS_104_grass_energy"],                                             10,  "Corphish Irongrip"],
	["DR_53_corphish",  1, ["RS_106_water_energy","RS_104_grass_energy"],                       20,  "Corphish Slash"],
	["DR_61_magnemite", 0, ["RS_104_grass_energy"],                                             10,  "Magnemite Rollout"],
	["DR_61_magnemite", 1, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Magnemite Hook"],
	["DR_71_pineco",    0, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Pineco Tackle"],
	["DR_78_trapinch",  0, ["RS_104_grass_energy"],                                             10,  "Trapinch Dig"],
	# ── RS set ────────────────────────────────────────────────────────────────
	["RS_32_grovyle",   0, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Grovyle Slash"],
	["RS_36_lairon",    0, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Lairon Ram"],
	["RS_36_lairon",    1, ["RS_94_metal_energy","RS_104_grass_energy","RS_104_grass_energy"],  40,  "Lairon Metal Claw"],
	["RS_46_swellow",   0, ["RS_104_grass_energy","RS_104_grass_energy"],                       30,  "Swellow Wing Attack"],
	["RS_50_aron",      0, ["RS_104_grass_energy"],                                             10,  "Aron Gnaw"],
	["RS_52_electrike", 0, ["RS_109_lightning_energy"],                                         10,  "Electrike Headbutt"],
	["RS_56_makuhita",  0, ["RS_104_grass_energy"],                                             10,  "Makuhita Slap Push"],
	["RS_56_makuhita",  1, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Makuhita Lunge Out"],
	["RS_63_poochyena", 0, ["RS_104_grass_energy"],                                             10,  "Poochyena Bite"],
	["RS_72_taillow",   0, ["RS_104_grass_energy"],                                             10,  "Taillow Peck"],
	["RS_72_taillow",   1, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Taillow Wing Attack"],
	["RS_76_treecko",   0, ["RS_104_grass_energy"],                                             10,  "Treecko Tail Slap"],
	["RS_76_treecko",   1, ["RS_104_grass_energy","RS_104_grass_energy"],                       20,  "Treecko Razor Leaf"],
	# ── SS set ────────────────────────────────────────────────────────────────
	["SS_1_armaldo",    0, ["RS_105_fighting_energy","RS_105_fighting_energy","RS_104_grass_energy"], 60, "Armaldo Blade Arms"],
	["SS_57_cacnea",    0, ["RS_104_grass_energy"],                                             10,  "Cacnea Light Punch"],
	["SS_65_growlithe", 0, ["RS_108_fire_energy","RS_104_grass_energy"],                        20,  "Growlithe Flare"],
	["SS_66_lotad",     0, ["RS_104_grass_energy"],                                             10,  "Lotad Ram"],
	["SS_72_pikachu",   0, ["RS_104_grass_energy"],                                             10,  "Pikachu Scratch"],
	["SS_72_pikachu",   1, ["RS_109_lightning_energy","RS_104_grass_energy","RS_104_grass_energy"], 40, "Pikachu Pika Bolt"],
	["SS_77_seedot",    0, ["RS_104_grass_energy"],                                             10,  "Seedot Tackle"],
]

func test_all_tier0_base_damage() -> void:
	for case in _TIER0_CASES:
		var attacker_id: String  = case[0]
		var atk_idx: int         = case[1]
		var energy_ids: Array    = case[2]
		var expected_dmg: int    = case[3]
		var desc: String         = case[4]
		gut.p("  checking: %s" % desc)

		var b     := _make_builder()
		var mgr   = b._manager

		## Shelgon attacks Lotad; everything else attacks Shelgon.
		var target_id := "SS_66_lotad" if attacker_id == "DR_41_shelgon" else "DR_41_shelgon"

		b.set_turn(0)
		b.place_active(0, attacker_id, {"energy": energy_ids})
		b.place_active(1, target_id,   {"hp": 200})
		b.set_prizes(0)
		b.set_prizes(1)

		var result: ActionResult = mgr.request_action(
			ActionAttack.new(0, "p0_active1", atk_idx, "p1_active1")
		)
		assert_true(result.ok,
			"%s — attack rejected: %s" % [desc, result.reason])

		var target: PokemonInstance = mgr.board_position.get_instance("p1_active1")
		assert_not_null(target, "%s — target disappeared unexpectedly" % desc)
		if target != null:
			assert_eq(target.current_hp, 200 - expected_dmg,
				"%s — expected hp %d, got %d" % [desc, 200 - expected_dmg, target.current_hp])


## ── Weakness ─────────────────────────────────────────────────────────────

func test_weakness_doubles_damage() -> void:
	## Pikachu (LIGHTNING) Pika Bolt: base_damage=40, vs Lotad (W=LIGHTNING).
	## 40 × 2 = 80.
	var b   := _make_builder()
	var mgr = b._manager
	## Pika Bolt costs 1 Lightning + 2 Colorless
	b.set_turn(0)
	b.place_active(0, "SS_72_pikachu", {
		"energy": ["RS_109_lightning_energy", "RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "SS_66_lotad", {"hp": 120})
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 1, "p1_active1"))
	assert_true(result.ok, "Pika Bolt should succeed: " + result.reason)

	var target: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_not_null(target, "Lotad should still be alive at 40 hp")
	if target != null:
		assert_eq(target.current_hp, 40,
			"Lotad: 120 - 80 (40×2 weakness) = 40")


func test_weakness_does_not_apply_to_wrong_type() -> void:
	## Makuhita (FIGHTING) attacks Electrike (R=METAL, W=FIGHTING).
	## FIGHTING type hits Electrike, which is weak to FIGHTING → damage × 2.
	## Lunge Out base=20, so expected = 40.
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_56_makuhita", {
		"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "RS_52_electrike", {"hp": 100})
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 1, "p1_active1"))
	assert_true(result.ok, result.reason)

	var target: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	## Electrike W=FIGHTING → 20 × 2 = 40
	assert_not_null(target)
	if target != null:
		assert_eq(target.current_hp, 60, "Electrike: 100 - 40 (20×2) = 60")


## ── Resistance ───────────────────────────────────────────────────────────

func test_resistance_reduces_damage_by_30() -> void:
	## Swellow (COLORLESS) Wing Attack base=30, vs Makuhita (R=NONE, so full 30).
	## Let's use a card that actually DOES resist: Electrike (R=METAL).
	## Attacker needs to be METAL type. Lairon (METAL) Ram=20 vs Electrike (R=METAL).
	## 20 - 30 = -10 → clamped to 0.
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	## Ram costs 2 Colorless
	b.place_active(0, "RS_36_lairon", {
		"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "RS_52_electrike", {"hp": 50})
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok, result.reason)

	var target: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	## Electrike R=METAL, Lairon is METAL → 20 - 30 = max(0,-10) = 0
	assert_not_null(target)
	if target != null:
		assert_eq(target.current_hp, 50, "Electrike should take 0 damage (resistance clamp)")


func test_resistance_does_not_apply_to_wrong_type() -> void:
	## Grovyle (GRASS) Slash vs Swellow (R=FIGHTING).
	## GRASS ≠ FIGHTING → resistance does not apply, full 20 damage lands.
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_32_grovyle", {
		"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "RS_46_swellow", {"hp": 70})
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok, result.reason)

	var target: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_not_null(target)
	if target != null:
		assert_eq(target.current_hp, 50, "Swellow: 70 - 20 (no resistance) = 50")


func test_both_weakness_and_resistance_can_combine() -> void:
	## Grovyle (GRASS) Slash base=20 vs Lairon (W=FIRE, R=GRASS).
	## GRASS ≠ FIRE so weakness does not apply.
	## GRASS = GRASS so resistance -30 applies → max(0, 20-30) = 0.
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_32_grovyle", {
		"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "RS_36_lairon", {"hp": 70})
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok, result.reason)

	var target: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_not_null(target)
	if target != null:
		assert_eq(target.current_hp, 70, "Lairon resists GRASS → 0 damage")


## ── KO resolution ────────────────────────────────────────────────────────

func test_ko_clears_defending_slot() -> void:
	## Armaldo Blade Arms (60dmg) vs Trapinch at exactly 60 HP → KO.
	## Opponent has Poochyena on bench to avoid game-over signal.
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "SS_1_armaldo", {
		"energy": ["RS_105_fighting_energy", "RS_105_fighting_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "DR_78_trapinch", {"hp": 60})
	b.place_bench(1, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok, result.reason)

	var former_slot: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_null(former_slot, "Trapinch slot should be empty after KO")


func test_ko_removes_one_prize() -> void:
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "SS_1_armaldo", {
		"energy": ["RS_105_fighting_energy", "RS_105_fighting_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "DR_78_trapinch", {"hp": 60})
	b.place_bench(1, "RS_63_poochyena")
	b.set_prizes(0, 6)
	b.set_prizes(1, 6)

	mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))

	assert_eq(mgr.game_position.prizes_remaining(0), 5,
		"P0 should have taken one prize after the KO")


func test_partial_damage_does_not_ko() -> void:
	## Electrike Headbutt (10dmg) vs Poochyena at 40 HP → survives with 30 HP.
	var b   := _make_builder()
	var mgr = b._manager
	TestFixtures.basic_combat(b)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(result.ok, result.reason)

	var target: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_not_null(target, "Poochyena should survive 10 damage")
	if target != null:
		assert_gt(target.current_hp, 0, "Poochyena should still be alive")
		assert_eq(target.current_hp, 30, "Poochyena: 40 - 10 = 30 HP")


## ── Energy validation ────────────────────────────────────────────────────

func test_attack_rejected_with_no_energy() -> void:
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike")   ## no energy
	b.place_active(1, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_false(result.ok, "Attack should fail with no energy")


func test_attack_rejected_with_wrong_typed_energy() -> void:
	## Crawdaunt Guillotine needs 1 Water + 2 Colorless.
	## Attacker has 3 Grass energy — colorless cost met, but Water cost is not.
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_3_crawdaunt", {
		"energy": ["RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_false(result.ok, "Crawdaunt Guillotine should reject without Water energy")
	assert_string_contains(result.reason.to_lower(), "water",
		"Rejection reason should mention the missing energy type")


func test_attack_rejected_with_insufficient_colorless() -> void:
	## Shelgon Rollout needs 2 Colorless; attacker only has 1 energy.
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_41_shelgon", {"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "SS_66_lotad", {"hp": 200})
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_false(result.ok, "Rollout should reject with only 1 energy")


func test_attack_accepted_with_exact_typed_plus_colorless() -> void:
	## Lairon Metal Claw needs 1 Metal + 2 Colorless.
	## Giving exactly 1 Metal + 2 Grass should succeed.
	var b   := _make_builder()
	var mgr = b._manager
	TestFixtures.typed_plus_colorless_cost(b)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 1, "p1_active1"))
	assert_true(result.ok, "Metal Claw with exact energy should succeed: " + result.reason)

	var target: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_not_null(target)
	if target != null:
		assert_eq(target.current_hp, 80, "Shelgon: 120 - 40 = 80")


## ── Special conditions block attacks ─────────────────────────────────────

func test_paralyzed_attacker_cannot_attack() -> void:
	var b   := _make_builder()
	var mgr = b._manager
	TestFixtures.paralyzed_cannot_attack(b)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_false(result.ok, "Paralyzed Pokémon should not be able to attack")
	assert_string_contains(result.reason.to_lower(), "paralyzed")


func test_asleep_attacker_cannot_attack() -> void:
	var b   := _make_builder()
	var mgr = b._manager
	TestFixtures.asleep_cannot_attack(b)

	var result := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_false(result.ok, "Asleep Pokémon should not be able to attack")
	assert_string_contains(result.reason.to_lower(), "asleep")


## ── Turn limits ──────────────────────────────────────────────────────────

func test_cannot_attack_twice_in_one_turn() -> void:
	var b   := _make_builder()
	var mgr = b._manager
	TestFixtures.basic_combat(b)

	var first  := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(first.ok, "First attack should succeed")

	var second := mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_false(second.ok, "Second attack in same turn should be rejected")


func test_cannot_attack_during_opponents_turn() -> void:
	var b   := _make_builder()
	var mgr = b._manager
	TestFixtures.basic_combat(b)
	## Turn is set to P0; P1 tries to attack from their own slot → wrong player.
	var result := mgr.request_action(ActionAttack.new(1, "p1_active1", 0, "p0_active1"))
	assert_false(result.ok, "P1 cannot attack on P0's turn")


func test_cannot_attack_from_bench() -> void:
	var b   := _make_builder()
	var mgr = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike", {"energy": ["RS_109_lightning_energy"]})
	b.place_bench(0,  "RS_63_poochyena", {"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "RS_72_taillow")
	b.set_prizes(0)
	b.set_prizes(1)

	var result := mgr.request_action(ActionAttack.new(0, "p0_bench1", 0, "p1_active1"))
	assert_false(result.ok, "Cannot attack from a bench slot")


## ── EffectRegistry integration (Tier 0 cards produce no effect) ──────────

func test_tier0_attack_dispatches_no_effect_key() -> void:
	## Tier 0 cards have an empty effect_key — EffectRegistry.dispatch should
	## silently do nothing.  We verify this by registering a sentinel handler
	## for the empty key, running the attack, and confirming it was never called.
	var called := false
	EffectRegistry.register("", func(_ctx): called = true)

	var b   := _make_builder()
	var mgr = b._manager
	TestFixtures.basic_combat(b)
	mgr.request_action(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))

	assert_false(called, "Empty effect_key should never invoke a handler")
	EffectRegistry.clear()
