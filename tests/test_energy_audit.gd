extends GutTest
## Audit suite for the 10 Energy cards. Verifies that every energy parses with
## the expected energy_type / extra_types / provides values, and that
## CardLibrary's auto-classification (in _finalize_energy) produces the
## documented Rainbow/Multi shape.

const _EXPECTED_ENERGIES: Array = [
	## [card_id, energy_type_name, extra_types_names, provides]
	## Basic six.
	["RS_104_grass_energy",     "GRASS",     [], 1],
	["RS_105_fighting_energy",  "FIGHTING",  [], 1],
	["RS_106_water_energy",     "WATER",     [], 1],
	["RS_107_psychic_energy",   "PSYCHIC",   [], 1],
	["RS_108_fire_energy",      "FIRE",      [], 1],
	["RS_109_lightning_energy", "LIGHTNING", [], 1],
	## Special single-type.
	["RS_93_darkness_energy",   "DARKNESS",  [], 1],
	["RS_94_metal_energy",      "METAL",     [], 1],
	## Multi/Rainbow — both auto-classify to COLORLESS with all 8 std types in
	## extra_types per CardLibrary.gd:157–186.
	["RS_95_rainbow_energy",    "COLORLESS",
		["GRASS","FIRE","WATER","LIGHTNING","PSYCHIC","FIGHTING","DARKNESS","METAL"], 1],
	["SS_93_multi_energy",      "COLORLESS",
		["GRASS","FIRE","WATER","LIGHTNING","PSYCHIC","FIGHTING","DARKNESS","METAL"], 1],
]


func test_all_10_energy_cards_exist() -> void:
	var energies: Array = []
	for c in CardDatabase.all_cards():
		if c is EnergyCardData:
			energies.append(c)
	assert_eq(energies.size(), 10,
		"Expected exactly 10 EnergyCardData entries; found %d." % energies.size())


func test_each_energy_has_expected_provision_shape() -> void:
	var type_keys: Array = PokemonCardData.EnergyType.keys()
	for spec in _EXPECTED_ENERGIES:
		var card_id: String = spec[0]
		var want_type: String = spec[1]
		var want_extras: Array = spec[2]
		var want_provides: int = spec[3]

		var card: EnergyCardData = CardDatabase.get_card(card_id) as EnergyCardData
		assert_not_null(card, "Missing energy card: %s" % card_id)
		if card == null:
			continue

		var got_type: String = type_keys[int(card.energy_type)]
		assert_eq(got_type, want_type,
			"%s: energy_type expected %s, got %s" % [card_id, want_type, got_type])

		var got_extras: Array = []
		for t in card.extra_types:
			got_extras.append(type_keys[int(t)])
		got_extras.sort()
		var want_extras_sorted := (want_extras as Array).duplicate()
		want_extras_sorted.sort()
		assert_eq(got_extras, want_extras_sorted,
			"%s: extra_types mismatch (got %s, want %s)" % [
				card_id, got_extras, want_extras_sorted])

		assert_eq(card.provides, want_provides,
			"%s: provides expected %d, got %d" % [
				card_id, want_provides, card.provides])


func test_rainbow_multi_classify_as_colorless_primary() -> void:
	for cid in ["RS_95_rainbow_energy", "SS_93_multi_energy"]:
		var card: EnergyCardData = CardDatabase.get_card(cid) as EnergyCardData
		assert_not_null(card, "Missing energy card: %s" % cid)
		if card == null:
			continue
		assert_eq(int(card.energy_type),
			int(PokemonCardData.EnergyType.COLORLESS),
			"%s should have COLORLESS as primary type." % cid)
		assert_eq(card.extra_types.size(), 8,
			"%s should declare all 8 standard energy types in extra_types." % cid)
