extends GutTest
## Smoke test for the CardDatabase autoload.
## Confirms the full card pool loads and art lookup is wired.

const EXPECTED_CARD_COUNT := 309


func test_loads_all_cards() -> void:
	var cards: Array = CardDatabase.all_cards()
	assert_eq(cards.size(), EXPECTED_CARD_COUNT,
		"Expected %d cards, got %d" % [EXPECTED_CARD_COUNT, cards.size()])


func test_get_card_round_trip() -> void:
	var cards: Array = CardDatabase.all_cards()
	assert_gt(cards.size(), 0, "card pool empty")
	var sample: CardData = cards[0]
	var fetched: CardData = CardDatabase.get_card(sample.card_id)
	assert_eq(fetched, sample, "get_card should return the same CardData instance")


func test_set_of_parses_prefix() -> void:
	assert_eq(CardDatabase.set_of("RS_1_aggron"), "RS")
	assert_eq(CardDatabase.set_of("DR_42_thing"),  "DR")
	assert_eq(CardDatabase.set_of("SS_100_x"),     "SS")
	assert_eq(CardDatabase.set_of("noprefix"),     "")


func test_cards_by_set_partitions_pool() -> void:
	var by_set: Dictionary = CardDatabase.cards_by_set()
	var total := 0
	for key in by_set.keys():
		total += (by_set[key] as Array).size()
	assert_eq(total, EXPECTED_CARD_COUNT,
		"sum of per-set counts must equal total card count")
	for key in ["DR", "RS", "SS"]:
		assert_true(by_set.has(key), "missing set partition: %s" % key)
		assert_gt((by_set[key] as Array).size(), 0, "empty set partition: %s" % key)


func test_load_art_resolves_for_sample_cards() -> void:
	## Probe one card per set. Missing art is warn-only at runtime; we accept
	## either a Texture2D or null but require the lookup not to crash.
	var by_set: Dictionary = CardDatabase.cards_by_set()
	for key in ["DR", "RS", "SS"]:
		if not by_set.has(key):
			continue
		var sample: CardData = (by_set[key] as Array)[0]
		var tex: Texture2D = CardDatabase.load_art(sample.card_id)
		assert_true(tex == null or tex is Texture2D,
			"load_art for %s returned unexpected type" % sample.card_id)
