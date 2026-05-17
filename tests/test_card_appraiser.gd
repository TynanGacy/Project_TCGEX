extends GutTest
## Verifies the per-rarity normal-distribution appraisal pricing.


func _seeded_rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


func _make_card(rarities: Array[String]) -> CardData:
	var c := CardData.new()
	c.card_id = "TEST_card"
	c.display_name = "Test"
	c.rarities = rarities
	return c


func test_highest_rarity_wins_when_card_has_multiple() -> void:
	var card := _make_card(["Common", "Rare Holo EX"])
	assert_eq(CardAppraiser.highest_rarity(card), "Rare Holo EX")


func test_appraisal_clamped_to_minimum() -> void:
	## Force draws across many seeds; the clamp must keep the price ≥ 0 for
	## Common (lower bound floored at MIN_PRICE).
	var card := _make_card(["Common"])
	for seed_v in range(100):
		var price := CardAppraiser.appraise(card, _seeded_rng(seed_v))
		assert_true(price >= CardAppraiser.MIN_PRICE,
			"seed %d returned price %d" % [seed_v, price])


func test_appraisal_respects_rarity_bounds() -> void:
	## Every rarity must produce a price inside [mean-range, mean+range] —
	## no exceptions. Per-tier loop catches all tiers in one run.
	var rng := _seeded_rng(31337)
	for tier in CardAppraiser.RARITY_PRICING.keys():
		var card := _make_card([str(tier)])
		var bounds: Vector2i = CardAppraiser.bounds_for(str(tier))
		for _i in 500:
			var price := CardAppraiser.appraise(card, rng)
			assert_true(price >= bounds.x and price <= bounds.y,
				"%s price %d outside [%d, %d]" % [tier, price, bounds.x, bounds.y])


func test_mean_of_many_draws_approximates_configured_mean() -> void:
	## 5000 draws of Rare Holo EX (mean 50, range 25 → bounds [25, 75]).
	## Empirical mean should land within ±3 of 50; clamp bias is symmetric
	## around the mean so the mid-point survives clipping.
	var card := _make_card(["Rare Holo EX"])
	var rng := _seeded_rng(2026)
	var total: int = 0
	var n: int = 5000
	for _i in n:
		total += CardAppraiser.appraise(card, rng)
	var mean := float(total) / float(n)
	assert_between(mean, 47.0, 53.0,
		"empirical mean %.2f should be near 50" % mean)


func test_secret_rare_is_strictly_priciest_on_average() -> void:
	## Sanity check on the rarity → price ordering — a Common's mean appraisal
	## should always be tiny compared to a Secret's.
	var common_card := _make_card(["Common"])
	var secret_card := _make_card(["Rare Secret"])
	var rng := _seeded_rng(7)
	var c_total: int = 0
	var s_total: int = 0
	var n: int = 1000
	for _i in n:
		c_total += CardAppraiser.appraise(common_card, rng)
		s_total += CardAppraiser.appraise(secret_card, rng)
	assert_lt(float(c_total) / float(n), float(s_total) / float(n))
