extends GutTest
## GUT tests for Fossil cards (Claw / Mysterious / Root) — Trainers that play
## as a synthetic Basic Pokémon via ActionPlayFossil.
##
## Verifies: placement, condition immunity, retreat rejection, no-prize KO,
## and that the original Trainer card (not the synthetic Pokémon) is what
## ends up in the discard.

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


## ── Placement and basic shape ───────────────────────────────────────────────

func test_play_fossil_creates_synthetic_basic_pokemon() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Need a basic Pokémon in active so the player has a board.
	b.place_active(0, "DR_49_bagon")
	var fossil: TrainerCardData = _lib.get_card("SS_90_claw_fossil") as TrainerCardData
	mgr.game_position.put_in_hand(0, fossil)

	var result: ActionResult = await mgr.request_action_async(
		ActionPlayFossil.new(0, fossil, "p0_bench1")
	)
	assert_true(result.ok, "ActionPlayFossil should succeed.")

	var inst: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_not_null(inst, "Fossil should occupy the bench slot.")
	assert_true(inst.is_fossil(), "Instance should report is_fossil() == true.")
	assert_eq(inst.source_trainer_card, fossil,
		"source_trainer_card should reference the original Trainer card.")
	assert_eq(inst.max_hp, 40, "Claw Fossil synthetic HP should be 40.")
	assert_eq(int(inst.card.pokemon_type),
		int(PokemonCardData.EnergyType.COLORLESS),
		"Fossil synthetic type should be COLORLESS.")
	assert_eq(inst.card.attacks.size(), 0, "Fossil should have no attacks.")


func test_play_fossil_rejects_active_slot() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var fossil: TrainerCardData = _lib.get_card("SS_91_mysterious_fossil") as TrainerCardData
	mgr.game_position.put_in_hand(0, fossil)

	var result: ActionResult = await mgr.request_action_async(
		ActionPlayFossil.new(0, fossil, "p0_active1")
	)
	assert_false(result.ok, "Fossils may only be played to a bench slot.")


## ── Condition immunity ──────────────────────────────────────────────────────

func test_fossil_ignores_special_conditions() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_49_bagon")
	var fossil: TrainerCardData = _lib.get_card("SS_90_claw_fossil") as TrainerCardData
	mgr.game_position.put_in_hand(0, fossil)
	await mgr.request_action_async(ActionPlayFossil.new(0, fossil, "p0_bench1"))

	var inst: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	inst.add_condition(PokemonInstance.SpecialCondition.ASLEEP)
	inst.add_condition(PokemonInstance.SpecialCondition.POISONED)

	assert_true(inst.special_conditions.is_empty(),
		"Fossils should silently ignore all special conditions.")


## ── Retreat rejection ───────────────────────────────────────────────────────

func test_fossil_cannot_retreat() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Place a real basic on bench to swap to, fossil in active position
	## (artificially — fossils normally only enter bench, but we test the
	## retreat rejection by forcing one into active for the test).
	var fossil: TrainerCardData = _lib.get_card("SS_92_root_fossil") as TrainerCardData
	var synth := ActionPlayFossil._build_synthetic_pokemon(fossil)
	var fossil_inst := PokemonInstance.create(synth, 0)
	fossil_inst.source_trainer_card = fossil
	mgr.board_position.place("p0_active1", fossil_inst)
	b.place_bench(0, "DR_49_bagon")

	var result: ActionResult = await mgr.request_action_async(
		ActionRetreat.new(0, "p0_active1", "p0_bench1")
	)
	assert_false(result.ok, "Fossils should not be retreatable.")


## ── No-prize KO ─────────────────────────────────────────────────────────────

func test_fossil_ko_discards_trainer_card_without_prize() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_49_bagon")
	var fossil: TrainerCardData = _lib.get_card("SS_90_claw_fossil") as TrainerCardData
	mgr.game_position.put_in_hand(0, fossil)
	await mgr.request_action_async(ActionPlayFossil.new(0, fossil, "p0_bench1"))

	## Set p0's prize pile so we'd notice if a prize was taken.
	b.set_prizes(0)
	b.set_prizes(1)
	var p1_prize_count_before: int = mgr.game_position.prizes_remaining(1)

	## KO the fossil.
	var inst: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	inst.current_hp = 0
	mgr.resolve_knockout("p0_bench1", 1)

	## Slot now empty.
	assert_eq(mgr.board_position.get_instance("p0_bench1"), null,
		"Fossil slot should clear after KO.")
	## Original Trainer card should be in p0's discard, not the synthetic.
	assert_true((mgr.game_position.discards[0] as Array).has(fossil),
		"The original Fossil Trainer card should be in p0's discard.")
	## No prize taken.
	assert_eq(mgr.game_position.prizes_remaining(1), p1_prize_count_before,
		"Attacking player should not have taken a prize from a Fossil KO.")
	## And no prize-selection phase opened.
	assert_eq(mgr.prize_selection_phase_for, -1,
		"prize_selection_phase_for should remain unset for Fossil KOs.")


## ── ActionPlayItem rejects fossils ──────────────────────────────────────────

func test_action_play_item_rejects_fossil_card() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_49_bagon")
	var fossil: TrainerCardData = _lib.get_card("SS_90_claw_fossil") as TrainerCardData
	mgr.game_position.put_in_hand(0, fossil)

	var result: ActionResult = await mgr.request_action_async(
		ActionPlayItem.new(0, fossil)
	)
	assert_false(result.ok,
		"ActionPlayItem should refuse Fossils — they must be played via ActionPlayFossil.")
