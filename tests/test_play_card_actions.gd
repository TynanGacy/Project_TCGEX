extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

var state: GameState


func before_each() -> void:
	state = GameState.new(2, 1, 5)
	state.phase = TurnPhase.Phase.MAIN


func _make_pokemon(
	card_id: String,
	stage: PokemonCardData.Stage,
	evolves_from: String = ""
) -> CardInstance:
	var data := PokemonCardData.new()
	data.card_id = card_id
	data.display_name = card_id
	data.stage = stage
	data.evolves_from = evolves_from
	data.hp_max = 60
	return CardInstance.create(data)


func _make_energy() -> CardInstance:
	var data := EnergyCardData.new()
	data.card_id = "fire_energy"
	data.display_name = "Fire Energy"
	data.energy_type = PokemonCardData.EnergyType.FIRE
	return CardInstance.create(data)


func _make_trainer(kind: TrainerCardData.TrainerKind, cid: String = "") -> CardInstance:
	var data := TrainerCardData.new()
	data.card_id = cid if cid != "" else "trainer_%d" % kind
	data.display_name = data.card_id
	data.trainer_kind = kind
	return CardInstance.create(data)


# ===========================================================================
# ActionPlayBasicPokemon
# ===========================================================================

func test_play_basic_to_bench() -> void:
	var card := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(card, "p0_hand")

	var action := ActionPlayBasicPokemon.new(0, card, "bench")
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.find_card_location(card), "p0_bench")
	assert_eq(card.turn_entered_play, state.turn_number)


func test_play_basic_to_active() -> void:
	var card := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(card, "p0_hand")

	var action := ActionPlayBasicPokemon.new(0, card, "active")
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.get_active_card(0, 0), card)


func test_play_basic_to_occupied_active_fails() -> void:
	var occupant := _make_pokemon("squirtle", PokemonCardData.Stage.BASIC)
	state.board.move_card(occupant, "p0_active_0")

	var card := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(card, "p0_hand")

	var action := ActionPlayBasicPokemon.new(0, card, "active")
	var result := action.validate(state)
	assert_false(result.ok)


func test_play_stage1_directly_fails() -> void:
	var card := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	state.board.move_card(card, "p0_hand")

	var action := ActionPlayBasicPokemon.new(0, card, "bench")
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Basic")


func test_play_basic_not_in_hand_fails() -> void:
	var card := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	# Intentionally NOT moved to hand.

	var action := ActionPlayBasicPokemon.new(0, card, "bench")
	var result := action.validate(state)
	assert_false(result.ok)


func test_play_basic_outside_main_phase_fails() -> void:
	state.phase = TurnPhase.Phase.START
	var card := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(card, "p0_hand")

	var action := ActionPlayBasicPokemon.new(0, card, "bench")
	var result := action.validate(state)
	assert_false(result.ok)


func test_play_basic_bench_full_fails() -> void:
	for i in range(5):
		var bench_card := _make_pokemon("mon_%d" % i, PokemonCardData.Stage.BASIC)
		state.board.move_card(bench_card, "p0_bench")

	var card := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(card, "p0_hand")

	var action := ActionPlayBasicPokemon.new(0, card, "bench")
	var result := action.validate(state)
	assert_false(result.ok)


# ===========================================================================
# ActionEvolvePokemon
# ===========================================================================

func test_evolve_on_bench() -> void:
	state.turn_number = 3

	var basic := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = 2
	state.board.move_card(basic, "p0_bench")

	var evolution := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	state.board.move_card(evolution, "p0_hand")

	var action := ActionEvolvePokemon.new(0, evolution, basic)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.find_card_location(evolution), "p0_bench")
	assert_eq(evolution.prior_stage, basic)
	assert_eq(state.board.find_card_location(basic), "")


func test_evolve_on_active() -> void:
	state.turn_number = 3

	var basic := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = 2
	state.board.move_card(basic, "p0_active_0")

	var evolution := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	state.board.move_card(evolution, "p0_hand")

	var action := ActionEvolvePokemon.new(0, evolution, basic)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.get_active_card(0, 0), evolution)


func test_evolve_transfers_damage() -> void:
	state.turn_number = 3

	var basic := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = 2
	basic.damage = 20
	state.board.move_card(basic, "p0_bench")

	var evolution := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	state.board.move_card(evolution, "p0_hand")

	var action := ActionEvolvePokemon.new(0, evolution, basic)
	action.apply(state)

	assert_eq(evolution.damage, 20)


func test_evolve_on_same_turn_fails() -> void:
	state.turn_number = 3

	var basic := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = 3  # Played this very turn.
	state.board.move_card(basic, "p0_bench")

	var evolution := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	state.board.move_card(evolution, "p0_hand")

	var action := ActionEvolvePokemon.new(0, evolution, basic)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "same turn")


func test_evolve_on_first_turn_fails() -> void:
	state.turn_number = 1  # Player 0's first turn.

	var basic := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = -1
	state.board.move_card(basic, "p0_bench")

	var evolution := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	state.board.move_card(evolution, "p0_hand")

	var action := ActionEvolvePokemon.new(0, evolution, basic)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "first turn")


func test_evolve_player1_first_turn_fails() -> void:
	state.turn_number = 2  # Player 1's first turn.
	state.current_player_id = 1

	var basic := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = -1
	state.board.move_card(basic, "p1_bench")

	var evolution := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	state.board.move_card(evolution, "p1_hand")

	var action := ActionEvolvePokemon.new(1, evolution, basic)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "first turn")


func test_evolve_wrong_target_fails() -> void:
	state.turn_number = 3

	var basic := _make_pokemon("charmander", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = 2
	state.board.move_card(basic, "p0_bench")

	var evolution := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	state.board.move_card(evolution, "p0_hand")

	var action := ActionEvolvePokemon.new(0, evolution, basic)
	var result := action.validate(state)
	assert_false(result.ok)


func test_evolve_stage2_onto_basic_fails() -> void:
	state.turn_number = 3

	var basic := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = 2
	state.board.move_card(basic, "p0_bench")

	# Venusaur is Stage 2 but we point evolves_from at pikachu (wrong).
	var evolution := _make_pokemon("venusaur", PokemonCardData.Stage.STAGE2, "pikachu")
	state.board.move_card(evolution, "p0_hand")

	var action := ActionEvolvePokemon.new(0, evolution, basic)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Stage 2")


func test_evolve_card_not_in_hand_fails() -> void:
	state.turn_number = 3

	var basic := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	basic.turn_entered_play = 2
	state.board.move_card(basic, "p0_bench")

	var evolution := _make_pokemon("raichu", PokemonCardData.Stage.STAGE1, "pikachu")
	# Not placed in hand.

	var action := ActionEvolvePokemon.new(0, evolution, basic)
	var result := action.validate(state)
	assert_false(result.ok)


# ===========================================================================
# ActionAttachEnergy
# ===========================================================================

func test_attach_energy_to_active() -> void:
	var energy := _make_energy()
	state.board.move_card(energy, "p0_hand")

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_active_0")

	var action := ActionAttachEnergy.new(0, energy, pokemon)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_true(pokemon.attached_energy.has(energy))
	assert_eq(state.board.find_card_location(energy), "")
	assert_true(state.get_player(0).has_attached_energy_this_turn)


func test_attach_energy_to_bench() -> void:
	var energy := _make_energy()
	state.board.move_card(energy, "p0_hand")

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_bench")

	var action := ActionAttachEnergy.new(0, energy, pokemon)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)


func test_attach_energy_twice_same_turn_fails() -> void:
	var energy1 := _make_energy()
	state.board.move_card(energy1, "p0_hand")
	var energy2 := _make_energy()
	state.board.move_card(energy2, "p0_hand")

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_active_0")

	var action1 := ActionAttachEnergy.new(0, energy1, pokemon)
	action1.apply(state)

	var action2 := ActionAttachEnergy.new(0, energy2, pokemon)
	var result := action2.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "already")


func test_attach_energy_not_in_hand_fails() -> void:
	var energy := _make_energy()
	# Not placed in hand.

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_active_0")

	var action := ActionAttachEnergy.new(0, energy, pokemon)
	var result := action.validate(state)
	assert_false(result.ok)


func test_attach_energy_to_non_pokemon_fails() -> void:
	var energy := _make_energy()
	state.board.move_card(energy, "p0_hand")

	# Target is also an energy card, not a Pokemon.
	var wrong_target := _make_energy()
	state.board.move_card(wrong_target, "p0_active_0")

	var action := ActionAttachEnergy.new(0, energy, wrong_target)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Pokemon")


func test_attach_energy_outside_main_phase_fails() -> void:
	state.phase = TurnPhase.Phase.ATTACK

	var energy := _make_energy()
	state.board.move_card(energy, "p0_hand")

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_active_0")

	var action := ActionAttachEnergy.new(0, energy, pokemon)
	var result := action.validate(state)
	assert_false(result.ok)


# ===========================================================================
# ActionPlayTrainerItem
# ===========================================================================

func test_play_item_goes_to_discard() -> void:
	var item := _make_trainer(TrainerCardData.TrainerKind.ITEM)
	state.board.move_card(item, "p0_hand")

	var action := ActionPlayTrainerItem.new(0, item)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.find_card_location(item), "p0_discard")


func test_play_item_multiple_times_same_turn_allowed() -> void:
	var item1 := _make_trainer(TrainerCardData.TrainerKind.ITEM)
	state.board.move_card(item1, "p0_hand")
	var item2 := _make_trainer(TrainerCardData.TrainerKind.ITEM)
	state.board.move_card(item2, "p0_hand")

	ActionPlayTrainerItem.new(0, item1).apply(state)

	var action2 := ActionPlayTrainerItem.new(0, item2)
	var result := action2.validate(state)
	assert_true(result.ok, result.reason)


func test_play_supporter_via_item_action_fails() -> void:
	var supporter := _make_trainer(TrainerCardData.TrainerKind.SUPPORTER)
	state.board.move_card(supporter, "p0_hand")

	var action := ActionPlayTrainerItem.new(0, supporter)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Item")


# ===========================================================================
# ActionPlayTrainerSupporter
# ===========================================================================

func test_play_supporter_goes_to_discard() -> void:
	var supporter := _make_trainer(TrainerCardData.TrainerKind.SUPPORTER)
	state.board.move_card(supporter, "p0_hand")

	var action := ActionPlayTrainerSupporter.new(0, supporter)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.find_card_location(supporter), "p0_discard")
	assert_true(state.get_player(0).supporter_played_this_turn)


func test_play_second_supporter_same_turn_fails() -> void:
	var s1 := _make_trainer(TrainerCardData.TrainerKind.SUPPORTER)
	state.board.move_card(s1, "p0_hand")
	var s2 := _make_trainer(TrainerCardData.TrainerKind.SUPPORTER)
	state.board.move_card(s2, "p0_hand")

	ActionPlayTrainerSupporter.new(0, s1).apply(state)

	var action2 := ActionPlayTrainerSupporter.new(0, s2)
	var result := action2.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Supporter")


func test_play_item_via_supporter_action_fails() -> void:
	var item := _make_trainer(TrainerCardData.TrainerKind.ITEM)
	state.board.move_card(item, "p0_hand")

	var action := ActionPlayTrainerSupporter.new(0, item)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Supporter")


# ===========================================================================
# ActionPlayTrainerStadium
# ===========================================================================

func test_play_stadium_enters_stadium_zone() -> void:
	var stadium := _make_trainer(TrainerCardData.TrainerKind.STADIUM)
	state.board.move_card(stadium, "p0_hand")

	var action := ActionPlayTrainerStadium.new(0, stadium)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.find_card_location(stadium), "stadium")
	assert_true(state.get_player(0).stadium_played_this_turn)


func test_play_stadium_replaces_different_stadium() -> void:
	var old_stadium := _make_trainer(TrainerCardData.TrainerKind.STADIUM, "old_stadium")
	old_stadium.owner_id = 1
	state.board.move_card(old_stadium, "stadium")

	var new_stadium := _make_trainer(TrainerCardData.TrainerKind.STADIUM, "new_stadium")
	state.board.move_card(new_stadium, "p0_hand")

	var action := ActionPlayTrainerStadium.new(0, new_stadium)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.find_card_location(new_stadium), "stadium")
	assert_eq(state.board.find_card_location(old_stadium), "p1_discard")


func test_play_same_stadium_that_is_in_play_fails() -> void:
	var data := TrainerCardData.new()
	data.card_id = "mystic_stadium"
	data.trainer_kind = TrainerCardData.TrainerKind.STADIUM

	var in_play := CardInstance.create(data)
	state.board.move_card(in_play, "stadium")

	var from_hand := CardInstance.create(data)  # Same card_id.
	state.board.move_card(from_hand, "p0_hand")

	var action := ActionPlayTrainerStadium.new(0, from_hand)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "already in play")


func test_play_non_stadium_via_stadium_action_fails() -> void:
	var item := _make_trainer(TrainerCardData.TrainerKind.ITEM)
	state.board.move_card(item, "p0_hand")

	var action := ActionPlayTrainerStadium.new(0, item)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Stadium")


# ===========================================================================
# ActionPlayTrainerTool
# ===========================================================================

func test_play_tool_attaches_to_active_pokemon() -> void:
	var tool := _make_trainer(TrainerCardData.TrainerKind.TOOL)
	state.board.move_card(tool, "p0_hand")

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_active_0")

	var action := ActionPlayTrainerTool.new(0, tool, pokemon)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_true(pokemon.attached_tools.has(tool))
	assert_eq(state.board.find_card_location(tool), "")


func test_play_tool_attaches_to_bench_pokemon() -> void:
	var tool := _make_trainer(TrainerCardData.TrainerKind.TOOL)
	state.board.move_card(tool, "p0_hand")

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_bench")

	var action := ActionPlayTrainerTool.new(0, tool, pokemon)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)


func test_play_second_tool_on_same_pokemon_fails() -> void:
	var tool1 := _make_trainer(TrainerCardData.TrainerKind.TOOL)
	state.board.move_card(tool1, "p0_hand")
	var tool2 := _make_trainer(TrainerCardData.TrainerKind.TOOL)
	state.board.move_card(tool2, "p0_hand")

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_active_0")

	ActionPlayTrainerTool.new(0, tool1, pokemon).apply(state)

	var action2 := ActionPlayTrainerTool.new(0, tool2, pokemon)
	var result := action2.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Tool")


func test_play_tool_to_opponent_pokemon_fails() -> void:
	var tool := _make_trainer(TrainerCardData.TrainerKind.TOOL)
	state.board.move_card(tool, "p0_hand")

	var opponent_pokemon := _make_pokemon("bulbasaur", PokemonCardData.Stage.BASIC)
	state.board.move_card(opponent_pokemon, "p1_active_0")

	var action := ActionPlayTrainerTool.new(0, tool, opponent_pokemon)
	var result := action.validate(state)
	assert_false(result.ok)


func test_play_non_tool_via_tool_action_fails() -> void:
	var item := _make_trainer(TrainerCardData.TrainerKind.ITEM)
	state.board.move_card(item, "p0_hand")

	var pokemon := _make_pokemon("pikachu", PokemonCardData.Stage.BASIC)
	state.board.move_card(pokemon, "p0_active_0")

	var action := ActionPlayTrainerTool.new(0, item, pokemon)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Tool")
