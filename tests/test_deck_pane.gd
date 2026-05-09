extends GutTest
## Behavioural tests for the deck builder's right-hand pane.
## Focus: the 4-copy hard cap (added this session) and basic-energy exemption.

const _PANE_SCRIPT := preload("res://scenes/deck_builder/deck_pane.gd")

var _pane: DeckPane = null
var _basic_pkm_id: String = ""
var _basic_energy_id: String = ""
var _special_energy_id: String = ""


func before_all() -> void:
	for c in CardDatabase.all_cards():
		var card: CardData = c
		if _basic_pkm_id == "" and card is PokemonCardData and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			_basic_pkm_id = card.card_id
		if _basic_energy_id == "" and DeckValidator.is_basic_energy(card):
			_basic_energy_id = card.card_id
		if _special_energy_id == "" and card is EnergyCardData and not DeckValidator.is_basic_energy(card):
			_special_energy_id = card.card_id


func before_each() -> void:
	_pane = _PANE_SCRIPT.new()
	## add_child_autofree wires _ready and frees the node after the test.
	add_child_autofree(_pane)


func test_add_card_below_cap_increments_count() -> void:
	_pane.add_card(_basic_pkm_id, 1)
	_pane.add_card(_basic_pkm_id, 1)
	assert_eq(_pane.count_of(_basic_pkm_id), 2)


func test_pokemon_caps_at_four_copies() -> void:
	for i in 6:
		_pane.add_card(_basic_pkm_id, 1)
	assert_eq(_pane.count_of(_basic_pkm_id), 4,
		"non-energy cards should hard-cap at 4 even after extra add_card calls")


func test_special_energy_caps_at_four() -> void:
	## Per the new rule, only the six named basic energies are exempt; every
	## other card — including Rainbow / Multi / Darkness / Metal Energy —
	## stops at 4.
	for i in 8:
		_pane.add_card(_special_energy_id, 1)
	assert_eq(_pane.count_of(_special_energy_id), 4,
		"special energy should respect the 4-copy cap")


func test_basic_energy_is_uncapped() -> void:
	for i in 30:
		_pane.add_card(_basic_energy_id, 1)
	assert_eq(_pane.count_of(_basic_energy_id), 30,
		"basic energy must be exempt from the 4-copy cap")


func test_bulk_add_clamped_to_remaining_allowance() -> void:
	_pane.add_card(_basic_pkm_id, 3)
	_pane.add_card(_basic_pkm_id, 5)  ## should clamp to 1 to stop at 4
	assert_eq(_pane.count_of(_basic_pkm_id), 4)


func test_remove_card_drops_to_zero_then_erases_entry() -> void:
	_pane.add_card(_basic_pkm_id, 2)
	_pane.remove_card(_basic_pkm_id, 2)
	assert_eq(_pane.count_of(_basic_pkm_id), 0)
	assert_false(_pane.get_model().has(_basic_pkm_id),
		"zero-count entries must be erased so saved JSON stays clean")


func test_clear_empties_model() -> void:
	_pane.add_card(_basic_pkm_id, 4)
	_pane.add_card(_basic_energy_id, 30)
	_pane.clear()
	assert_eq(_pane.get_model().size(), 0)
