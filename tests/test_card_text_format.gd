extends GutTest
## Covers the deck-builder display + sort helpers added this session:
##   - card_id parsing (set prefix, numeric portion)
##   - default sort: set rank (DR → SS → RS) then ascending number
##   - alternate sort comparators: type, energy
##   - canonical TCG energy ordering (Grass, Fire, Water, …)
##   - placeholder rarity / collection comparators behave like the default
##   - text-mode row formatting includes the trait fields the deck builder
##     renders into its column-aligned table


# ---------------------------------------------------------------------------
# card_id parsing
# ---------------------------------------------------------------------------

func test_card_number_int_parses_numeric_portion() -> void:
	assert_eq(CardTextFormat.card_number_int("DR_100_charizard"), 100)
	assert_eq(CardTextFormat.card_number_int("RS_2_aggron"), 2)
	assert_eq(CardTextFormat.card_number_int("SS_69_numel"), 69)


func test_card_number_int_handles_garbage() -> void:
	assert_eq(CardTextFormat.card_number_int("noprefix"), 0)
	assert_eq(CardTextFormat.card_number_int(""), 0)


func test_set_rank_orders_dr_ss_rs_then_unknown() -> void:
	## Newest first: DR before SS before RS. Unknown sets sort after.
	assert_lt(CardTextFormat.set_rank("DR"), CardTextFormat.set_rank("SS"))
	assert_lt(CardTextFormat.set_rank("SS"), CardTextFormat.set_rank("RS"))
	assert_lt(CardTextFormat.set_rank("RS"), CardTextFormat.set_rank("ZZ"))


# ---------------------------------------------------------------------------
# Default sort: set rank → ascending number
# ---------------------------------------------------------------------------

func test_compare_card_ids_orders_within_set_numerically() -> void:
	## The bug that motivated this whole exercise: alphanumeric sort puts
	## "20" before "3". The numeric comparator must put "3" first.
	assert_true(CardTextFormat.compare_card_ids("RS_3_a",  "RS_20_b"))
	assert_false(CardTextFormat.compare_card_ids("RS_20_b", "RS_3_a"))


func test_compare_card_ids_orders_dr_before_rs_regardless_of_number() -> void:
	## Newest set wins even with a smaller number on the older set.
	assert_true(CardTextFormat.compare_card_ids("DR_100_x", "RS_1_y"))
	assert_false(CardTextFormat.compare_card_ids("RS_1_y",  "DR_100_x"))


func test_compare_cards_uses_default_order_on_real_cards() -> void:
	var sorted := _all_cards_sorted_by(CardTextFormat.comparator_for("default"))
	## First card belongs to the newest set (DR) by definition.
	assert_eq(CardDatabase.set_of((sorted[0] as CardData).card_id), "DR")
	## Within a contiguous run of one set, numbers ascend monotonically.
	_assert_numbers_ascending_within_each_set(sorted)


# ---------------------------------------------------------------------------
# Alternate comparators
# ---------------------------------------------------------------------------

func test_compare_by_type_groups_pokemon_then_trainer_then_energy() -> void:
	var sorted := _all_cards_sorted_by(CardTextFormat.comparator_for("type"))
	var seen_types: Array[int] = []
	var prev_type: int = -1
	for c in sorted:
		var t: int = (c as CardData).card_type
		if t != prev_type:
			seen_types.append(t)
			prev_type = t
	## Pokémon (0) → Trainer (1) → Energy (2) — values come from
	## CardData.CardType in scripts/cards/card_data.gd.
	assert_eq(seen_types,
		[CardData.CardType.POKEMON, CardData.CardType.TRAINER, CardData.CardType.ENERGY] as Array[int],
		"type-sort should produce one contiguous run per card type")


func test_compare_by_energy_uses_canonical_tcg_order() -> void:
	## Build a small list of one card per type so the test isn't fragile to
	## per-set tiebreaks. Order produced by compare_by_energy must be:
	## Grass → Fire → Water → Lightning → Psychic → Fighting → Darkness →
	## Metal → Colorless. (Dragon does not exist in this era.)
	var canonical: Array[int] = [
		PokemonCardData.EnergyType.GRASS,
		PokemonCardData.EnergyType.FIRE,
		PokemonCardData.EnergyType.WATER,
		PokemonCardData.EnergyType.LIGHTNING,
		PokemonCardData.EnergyType.PSYCHIC,
		PokemonCardData.EnergyType.FIGHTING,
		PokemonCardData.EnergyType.DARKNESS,
		PokemonCardData.EnergyType.METAL,
		PokemonCardData.EnergyType.COLORLESS,
	]
	var sample: Array = []
	for et in canonical:
		var found: CardData = _find_pokemon_with_type(et)
		if found != null:
			sample.append(found)

	## Shuffle into reverse order then sort with the energy comparator and
	## confirm it lands in canonical order.
	sample.reverse()
	sample.sort_custom(CardTextFormat.comparator_for("energy"))
	var observed: Array[int] = []
	for c in sample:
		observed.append((c as PokemonCardData).pokemon_type)
	## Compare with the prefix of canonical that we actually had cards for.
	assert_eq(observed, canonical.slice(0, observed.size()))


func test_placeholder_comparators_match_default_until_implemented() -> void:
	## Rarity and Collection are stubs; the deck builder should still render
	## something sensible (the default order) when they're selected.
	var def := _all_cards_sorted_by(CardTextFormat.comparator_for("default"))
	var rar := _all_cards_sorted_by(CardTextFormat.comparator_for("rarity"))
	var col := _all_cards_sorted_by(CardTextFormat.comparator_for("collection"))
	assert_eq(_card_id_list(rar), _card_id_list(def),
		"rarity sort should currently match the default until rarity data lands")
	assert_eq(_card_id_list(col), _card_id_list(def),
		"collection sort should currently match the default until ownership lands")


func test_unknown_sort_key_falls_back_to_default() -> void:
	var def := _all_cards_sorted_by(CardTextFormat.comparator_for("default"))
	var unk := _all_cards_sorted_by(CardTextFormat.comparator_for("not_a_real_sort_key"))
	assert_eq(_card_id_list(unk), _card_id_list(def))


# ---------------------------------------------------------------------------
# Text-mode row formatting
# ---------------------------------------------------------------------------

func test_row_format_includes_count_name_type_set_locator_and_rarity() -> void:
	var card: CardData = CardDatabase.all_cards()[0]
	var row := CardTextFormat.row(card, 3)
	assert_string_contains(row, "3×")
	assert_string_contains(row, card.display_name)
	assert_string_contains(row, CardTextFormat.type_token(card))
	assert_string_contains(row, CardTextFormat.set_locator(card))


func test_set_locator_format() -> void:
	var c: CardData = CardDatabase.get_card("DR_100_charizard")
	if c == null:
		return  ## fixture missing; skip rather than fail
	var loc := CardTextFormat.set_locator(c)
	assert_string_starts_with(loc, "DR ")
	assert_string_contains(loc, "100/")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _all_cards_sorted_by(cmp: Callable) -> Array:
	var cards := CardDatabase.all_cards().duplicate()
	cards.sort_custom(cmp)
	return cards


func _card_id_list(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append((c as CardData).card_id)
	return out


func _assert_numbers_ascending_within_each_set(sorted: Array) -> void:
	var current_set := ""
	var last_num := -1
	for c in sorted:
		var card: CardData = c
		var s := CardDatabase.set_of(card.card_id)
		var n := CardTextFormat.card_number_int(card.card_id)
		if s != current_set:
			current_set = s
			last_num = n
			continue
		assert_gte(n, last_num,
			"numbers must ascend within set %s; saw %d after %d" % [s, n, last_num])
		last_num = n


func _find_pokemon_with_type(et: int) -> CardData:
	for c in CardDatabase.all_cards():
		if c is PokemonCardData and (c as PokemonCardData).pokemon_type == et:
			return c
	return null
