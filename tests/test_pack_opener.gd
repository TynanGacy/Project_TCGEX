extends GutTest
## Verifies PackOpener slot counts, set membership, and weight obedience.

const DR_PACK_PATH := "res://data/packs/DR.json"
const RS_PACK_PATH := "res://data/packs/RS.json"


func _seeded_rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


func test_dr_pack_has_nine_cards() -> void:
	var pd := PackDefinition.from_path(DR_PACK_PATH)
	assert_not_null(pd, "pack def loaded")
	assert_eq(pd.total_card_count(), 9, "EX Dragon booster is 9 cards")
	var rolled := PackOpener.roll(pd, _seeded_rng(1))
	assert_eq(rolled.size(), 9, "rolled 9 cards")


func test_all_rolled_cards_belong_to_set() -> void:
	var pd := PackDefinition.from_path(DR_PACK_PATH)
	var rolled := PackOpener.roll(pd, _seeded_rng(42))
	for cid in rolled:
		assert_eq(CardDatabase.set_of(cid), "DR", "card %s is in DR" % cid)


func test_first_eight_slots_are_common_then_uncommon() -> void:
	var pd := PackDefinition.from_path(DR_PACK_PATH)
	var rolled := PackOpener.roll(pd, _seeded_rng(7))
	for i in 5:
		var card: CardData = CardDatabase.get_card(rolled[i])
		assert_true(card.rarities.has("Common"),
			"slot %d should be a Common (got %s)" % [i, str(card.rarities)])
	for i in range(5, 8):
		var card: CardData = CardDatabase.get_card(rolled[i])
		assert_true(card.rarities.has("Uncommon"),
			"slot %d should be an Uncommon (got %s)" % [i, str(card.rarities)])


func test_rarity_weights_approximate_expected_distribution() -> void:
	## With 5000 rolls of the rare slot, the Rare Holo EX rate (~8.33%) should
	## land in [5%, 12%]. Wide bands keep the test stable across RNG seeds.
	var pd := PackDefinition.from_path(DR_PACK_PATH)
	var ex_hits: int = 0
	var secret_hits: int = 0
	var rng := _seeded_rng(2026)
	var trials: int = 5000
	for _i in trials:
		var rolled := PackOpener.roll(pd, rng)
		var rare_card: CardData = CardDatabase.get_card(rolled[8])
		if rare_card.rarities.has("Rare Holo EX"):
			ex_hits += 1
		if rare_card.rarities.has("Rare Secret"):
			secret_hits += 1
	var ex_rate: float = float(ex_hits) / float(trials)
	var secret_rate: float = float(secret_hits) / float(trials)
	assert_between(ex_rate, 0.05, 0.12, "Rare Holo EX rate near 8.33%%")
	assert_between(secret_rate, 0.01, 0.05, "Rare Secret rate near 2.78%%")


func test_pack_never_contains_basic_energy() -> void:
	## RS is the relevant set here — it's the only one with basic energies in
	## the pool. Run many trials to make sure none sneak through.
	var pd := PackDefinition.from_path(RS_PACK_PATH)
	var rng := _seeded_rng(11)
	for _i in 200:
		var rolled := PackOpener.roll(pd, rng)
		for cid in rolled:
			var card: CardData = CardDatabase.get_card(cid)
			assert_false(DeckValidator.is_basic_energy(card),
				"pack rolled a basic energy (%s)" % cid)


func test_pack_has_no_duplicate_card_ids() -> void:
	var pd := PackDefinition.from_path(DR_PACK_PATH)
	var rng := _seeded_rng(13)
	for _i in 200:
		var rolled := PackOpener.roll(pd, rng)
		var seen := {}
		for cid in rolled:
			assert_false(seen.has(cid),
				"duplicate %s in pack: %s" % [cid, str(rolled)])
			seen[cid] = true


func test_pack_caps_trainer_and_energy_separately() -> void:
	## Per design: at most one trainer AND at most one energy per pack.
	## A pack can carry both, just not two of the same type.
	var pd := PackDefinition.from_path(DR_PACK_PATH)
	var rng := _seeded_rng(17)
	for _i in 300:
		var rolled := PackOpener.roll(pd, rng)
		var trainers: int = 0
		var energies: int = 0
		for cid in rolled:
			var card: CardData = CardDatabase.get_card(cid)
			if card.card_type == CardData.CardType.TRAINER:
				trainers += 1
			elif card.card_type == CardData.CardType.ENERGY:
				energies += 1
		assert_true(trainers <= 1,
			"pack had %d trainers: %s" % [trainers, str(rolled)])
		assert_true(energies <= 1,
			"pack had %d energies: %s" % [energies, str(rolled)])


func test_rs_pack_has_no_secrets() -> void:
	var pd := PackDefinition.from_path(RS_PACK_PATH)
	var rolled := PackOpener.roll(pd, _seeded_rng(99))
	for cid in rolled:
		var card: CardData = CardDatabase.get_card(cid)
		assert_false(card.rarities.has("Rare Secret"),
			"RS should never roll a Rare Secret")
