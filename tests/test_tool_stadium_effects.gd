extends GutTest
## GUT tests for the Day-1 Tool and Stadium aura effects:
##   tool_clear_conditions_on_attach  (Lum Berry)
##   tool_heal_on_damage              (Oran Berry)
##   tool_free_retreat_once           (Balloon Berry)
##   tool_damage_reduction            (Buffer Piece)
##   stadium_passive (hp_bonus aura)  (Low Pressure System)
##
## Each test stages a minimal board via TestBoardBuilder, invokes the relevant
## game-flow hook directly (cleanup, retreat, attack, stadium-change), and
## asserts the resulting state.

var _lib: CardLibrary
var _handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	## Attack-effect handlers are needed by AttackResolver via EffectRegistry.
	## Use plain add_child (registered closures capture this node).
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


## Attaches [tool_card_id] to [inst] as a Tool and records the attach turn so
## ToolEffects.run_between_turn_effects can later evaluate auto-discards.
func _attach_tool(inst: PokemonInstance, tool_card_id: String, mgr: ManagerSystem) -> TrainerCardData:
	var tool: TrainerCardData = _lib.get_card(tool_card_id) as TrainerCardData
	assert_not_null(tool, "Test setup: missing tool '%s'" % tool_card_id)
	inst.attach_tool(tool)
	inst.tool_attached_turn[tool] = mgr.turn_number
	return tool


## ── Lum Berry ───────────────────────────────────────────────────────────────

func test_lum_berry_clears_conditions_and_self_discards() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var inst := b.place_active(0, "DR_49_bagon", {
		"conditions": [PokemonInstance.SpecialCondition.ASLEEP,
					   PokemonInstance.SpecialCondition.POISONED],
	})
	var tool := _attach_tool(inst, "RS_84_lum_berry", mgr)

	ToolEffects.run_between_turn_effects(inst, "p0_active1", mgr)

	assert_true(inst.special_conditions.is_empty(),
		"Lum Berry should clear all special conditions.")
	assert_eq(inst.attached_tools.size(), 0,
		"Lum Berry should self-discard after firing.")
	assert_true((mgr.game_position.discards[0] as Array).has(tool),
		"Lum Berry should be in the owner's discard pile.")


func test_lum_berry_does_nothing_when_no_conditions() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var inst := b.place_active(0, "DR_49_bagon")
	_attach_tool(inst, "RS_84_lum_berry", mgr)

	ToolEffects.run_between_turn_effects(inst, "p0_active1", mgr)

	assert_eq(inst.attached_tools.size(), 1,
		"Lum Berry should remain attached when no conditions are present.")


## ── Oran Berry ──────────────────────────────────────────────────────────────

func test_oran_berry_heals_20_when_damaged() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Bagon: 40 max HP.  Damage to 10 (= 30 missing, ≥ 20 threshold).
	var inst := b.place_active(0, "DR_49_bagon", {"hp": 10})
	var tool := _attach_tool(inst, "RS_85_oran_berry", mgr)

	ToolEffects.run_between_turn_effects(inst, "p0_active1", mgr)

	assert_eq(inst.current_hp, 30, "Oran Berry should heal 20 HP.")
	assert_eq(inst.attached_tools.size(), 0,
		"Oran Berry should self-discard after firing.")
	assert_true((mgr.game_position.discards[0] as Array).has(tool),
		"Oran Berry should be in the owner's discard pile.")


func test_oran_berry_no_trigger_below_20_damage() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Bagon at 30/40 — only 10 missing.
	var inst := b.place_active(0, "DR_49_bagon", {"hp": 30})
	_attach_tool(inst, "RS_85_oran_berry", mgr)

	ToolEffects.run_between_turn_effects(inst, "p0_active1", mgr)

	assert_eq(inst.current_hp, 30, "Oran Berry should not heal when <20 damage.")
	assert_eq(inst.attached_tools.size(), 1, "Oran Berry should remain attached.")


## ── Balloon Berry ───────────────────────────────────────────────────────────

func test_balloon_berry_enables_free_retreat() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Bagon has retreat_cost > 0; without Balloon Berry this would fail.
	var active := b.place_active(0, "DR_49_bagon")
	b.place_bench(0, "DR_41_shelgon")
	var tool := _attach_tool(active, "DR_82_balloon_berry", mgr)
	## Make sure validate sees zero energy attached.
	active.attached_energy.clear()

	var result: ActionResult = await mgr.request_action_async(
		ActionRetreat.new(0, "p0_active1", "p0_bench1")
	)
	assert_true(result.ok, "Balloon Berry should allow retreat with no energy.")
	assert_true((mgr.game_position.discards[0] as Array).has(tool),
		"Balloon Berry should be discarded after free retreat.")
	## After retreat, the active slot should hold the previous bench Pokémon.
	var new_active: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_not_null(new_active, "Bench Pokémon should swap into active.")


## ── Buffer Piece ────────────────────────────────────────────────────────────

func test_buffer_piece_reduces_attack_damage_by_20() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Bagon's first attack does 10 damage with 1 colorless energy.  We patch
	## it up to 50 so the -20 buffer takes it to 30 (still nonzero).
	var attacker := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})
	var target := b.place_active(1, "DR_41_shelgon")
	attacker.card.attacks[0].base_damage = 50
	attacker.card.attacks[0].effect_key = ""
	_attach_tool(target, "DR_83_buffer_piece", mgr)
	b.set_prizes(0)
	b.set_prizes(1)
	var pre_hp: int = target.current_hp

	var result: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(result.ok, "Attack should resolve")
	## Damage taken should be 50 - 20 = 30.  W/R: Bagon (Colorless) vs Shelgon
	## (Dragon) — no weakness/resistance interaction.
	var damage_taken: int = pre_hp - target.current_hp
	assert_eq(damage_taken, 30,
		"Buffer Piece should reduce 50 damage to 30 (after the -20).")


func test_buffer_piece_auto_discards_after_opponent_turn() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	## Attach on turn 5 as player 0; cleanup runs at end of turn 6 as player 1.
	b.set_turn(0, 5)
	var inst := b.place_active(0, "DR_49_bagon")
	var tool := _attach_tool(inst, "DR_83_buffer_piece", mgr)
	## Simulate that opponent's next turn is the one ending now.
	mgr.turn_number = 6
	mgr.current_player = 1

	ToolEffects.run_between_turn_effects(inst, "p0_active1", mgr)

	assert_eq(inst.attached_tools.size(), 0,
		"Buffer Piece should auto-discard at end of opponent's next turn.")
	assert_true((mgr.game_position.discards[0] as Array).has(tool),
		"Buffer Piece should be in its owner's discard.")


func test_buffer_piece_persists_on_own_turn() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 5)
	var inst := b.place_active(0, "DR_49_bagon")
	_attach_tool(inst, "DR_83_buffer_piece", mgr)
	## Same turn / same player — should not discard.
	mgr.current_player = 0

	ToolEffects.run_between_turn_effects(inst, "p0_active1", mgr)

	assert_eq(inst.attached_tools.size(), 1,
		"Buffer Piece should remain on its owner's turn.")


## ── Low Pressure System (Stadium aura) ──────────────────────────────────────

func test_low_pressure_system_adds_10_hp_to_grass_pokemon() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Treecko is Grass; place it before the stadium drops to test
	## reconcile_all_auras().
	var grass_inst := b.place_active(0, "RS_75_treecko")
	var base_hp := grass_inst.max_hp
	mgr.game_position.put_in_hand(0,
		_lib.get_card("DR_86_low_pressure_system"))

	var result: ActionResult = await mgr.request_action_async(
		ActionPlayStadium.new(0, _lib.get_card("DR_86_low_pressure_system"))
	)
	assert_true(result.ok)
	assert_eq(grass_inst.max_hp, base_hp + 10,
		"Grass Pokémon max_hp should rise by 10 under Low Pressure System.")
	assert_eq(grass_inst.aura_hp_bonus, 10)


func test_low_pressure_system_skips_non_grass_non_lightning() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Bagon is Colorless — should not receive the bonus.
	var bagon := b.place_active(0, "DR_49_bagon")
	var base_hp := bagon.max_hp
	mgr.game_position.put_in_hand(0,
		_lib.get_card("DR_86_low_pressure_system"))

	await mgr.request_action_async(
		ActionPlayStadium.new(0, _lib.get_card("DR_86_low_pressure_system"))
	)
	assert_eq(bagon.max_hp, base_hp, "Colorless Pokémon should not gain HP.")
	assert_eq(bagon.aura_hp_bonus, 0)


func test_low_pressure_system_revoked_on_stadium_replacement() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var grass_inst := b.place_active(0, "RS_75_treecko")
	var base_hp := grass_inst.max_hp
	mgr.game_position.put_in_hand(0,
		_lib.get_card("DR_86_low_pressure_system"))
	mgr.game_position.put_in_hand(0,
		_lib.get_card("DR_85_high_pressure_system"))

	await mgr.request_action_async(
		ActionPlayStadium.new(0, _lib.get_card("DR_86_low_pressure_system"))
	)
	assert_eq(grass_inst.max_hp, base_hp + 10, "Aura active under LPS.")

	## Replace with High Pressure System (which has no hp_bonus).
	await mgr.request_action_async(
		ActionPlayStadium.new(0, _lib.get_card("DR_85_high_pressure_system"))
	)
	assert_eq(grass_inst.max_hp, base_hp,
		"Aura should revoke when the buffing stadium is replaced.")
	assert_eq(grass_inst.aura_hp_bonus, 0)
