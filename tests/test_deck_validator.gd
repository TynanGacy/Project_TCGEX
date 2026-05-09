extends GutTest
## Validator rules:
##   1. Total == 60
##   2. ≤4 copies of any non-basic-Energy card
##   3. ≥1 Basic Pokémon
## Basic Energy is identified by display_name (Grass / Fire / Water /
## Lightning / Psychic / Fighting Energy). Special Energies (Rainbow, Multi,
## Darkness, Metal, …) cap at 4 like any other card.

var _basic_pkm_id: String = ""
var _stage1_pkm_id: String = ""
var _trainer_id: String = ""
var _basic_energy_id: String = ""
var _special_energy_id: String = ""  ## not a basic-energy name


func before_all() -> void:
	## Pick representative real cards from CardDatabase so the tests exercise
	## live data rather than fabricated CardData.
	for c in CardDatabase.all_cards():
		var card: CardData = c
		if _basic_pkm_id == "" and card is PokemonCardData and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			_basic_pkm_id = card.card_id
		if _stage1_pkm_id == "" and card is PokemonCardData and (card as PokemonCardData).stage == PokemonCardData.Stage.STAGE1:
			_stage1_pkm_id = card.card_id
		if _trainer_id == "" and card is TrainerCardData:
			_trainer_id = card.card_id
		if _basic_energy_id == "" and DeckValidator.is_basic_energy(card):
			_basic_energy_id = card.card_id
		if _special_energy_id == "" and card is EnergyCardData and not DeckValidator.is_basic_energy(card):
			_special_energy_id = card.card_id

	assert_ne(_basic_pkm_id, "", "fixture: need at least one Basic Pokémon")
	assert_ne(_basic_energy_id, "", "fixture: need at least one basic Energy")
	assert_ne(_special_energy_id, "", "fixture: need at least one special Energy")


# ---------------------------------------------------------------------------
# Existing rules
# ---------------------------------------------------------------------------

func test_under_60_fails() -> void:
	var model := {_basic_energy_id: 30, _basic_pkm_id: 4}
	var errors := DeckValidator.validate(model)
	assert_true(_has_error(errors, "exactly 60"), "expected size error, got: %s" % str(errors))


func test_over_60_fails() -> void:
	var model := {_basic_energy_id: 70}
	var errors := DeckValidator.validate(model)
	assert_true(_has_error(errors, "exactly 60"))


func test_five_copies_of_non_energy_fails() -> void:
	var model := {_basic_pkm_id: 5, _basic_energy_id: 55}
	var errors := DeckValidator.validate(model)
	assert_true(_has_error(errors, "More than 4"), "expected copy-limit error, got: %s" % str(errors))


func test_thirty_basic_energies_pass_count_rule() -> void:
	## 52 of one basic energy is legal because basic energy is exempt; pad
	## the rest with cards that themselves stay within the cap.
	var model := {_basic_energy_id: 52, _basic_pkm_id: 4, _trainer_id: 4}
	var errors := DeckValidator.validate(model)
	assert_false(_has_error(errors, "More than 4"),
		"30+ basic energies should not trigger the copy-limit rule: %s" % str(errors))


func test_no_basic_pokemon_fails() -> void:
	var model := {_basic_energy_id: 60}
	var errors := DeckValidator.validate(model)
	assert_true(_has_error(errors, "Basic Pokémon"))


func test_valid_deck_passes() -> void:
	var model := {_basic_pkm_id: 4, _basic_energy_id: 52, _trainer_id: 4}
	var errors := DeckValidator.validate(model)
	assert_eq(errors.size(), 0, "expected valid; errors: %s" % str(errors))


# ---------------------------------------------------------------------------
# Basic-energy classification (added this session)
# ---------------------------------------------------------------------------

func test_is_basic_energy_accepts_grass_fire_water_etc() -> void:
	## Cross-check via display_name lookup against the live database.
	var found_count := 0
	for name in DeckValidator.BASIC_ENERGY_NAMES:
		for c in CardDatabase.all_cards():
			if (c as CardData).display_name == name:
				assert_true(DeckValidator.is_basic_energy(c),
					"%s should be a basic energy" % name)
				found_count += 1
				break
	assert_gt(found_count, 0, "expected at least one basic energy in the pool")


func test_is_basic_energy_rejects_special_energy() -> void:
	## Special energies cap at 4 — the new rule's whole point.
	var sp: CardData = CardDatabase.get_card(_special_energy_id)
	assert_false(DeckValidator.is_basic_energy(sp),
		"%s should NOT be classified as basic energy" % sp.display_name)


func test_is_basic_energy_rejects_pokemon_and_trainer() -> void:
	assert_false(DeckValidator.is_basic_energy(CardDatabase.get_card(_basic_pkm_id)))
	assert_false(DeckValidator.is_basic_energy(CardDatabase.get_card(_trainer_id)))


func test_is_basic_energy_handles_null() -> void:
	assert_false(DeckValidator.is_basic_energy(null))


func test_special_energy_capped_at_4() -> void:
	## 5 copies of a Rainbow / Multi / Darkness / Metal Energy must fail
	## the copy limit rule — same as a Pokémon would.
	var model := {_special_energy_id: 5, _basic_pkm_id: 4, _basic_energy_id: 51}
	var errors := DeckValidator.validate(model)
	assert_true(_has_error(errors, "More than 4"),
		"5 copies of a special energy should fail: %s" % str(errors))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func test_total_count_helper() -> void:
	assert_eq(DeckValidator.total_count({_basic_energy_id: 4, _basic_pkm_id: 3}), 7)
	assert_eq(DeckValidator.total_count({}), 0)


func test_basic_pokemon_count_helper() -> void:
	var n := DeckValidator.basic_pokemon_count({_basic_pkm_id: 3, _basic_energy_id: 10})
	assert_eq(n, 3)
	if _stage1_pkm_id != "":
		var n2 := DeckValidator.basic_pokemon_count({_stage1_pkm_id: 3})
		assert_eq(n2, 0, "stage 1 should not count as Basic")


func _has_error(errors: Array, needle: String) -> bool:
	for e in errors:
		if (e as String).contains(needle):
			return true
	return false
