class_name CardAppraiser
extends RefCounted
## Per-card sellback pricing. Each appraisal is a normal-distribution draw
## hard-clamped to a per-rarity [min, max] range — the player should never
## see "15 ± 10" produce a Rare worth 1 or 33. Most tiers derive both their
## stddev and their clamp bounds from `range` (σ = range/2; bounds =
## mean±range), but a tier can override those independently via explicit
## `min` / `max` / `stddev` keys. Rare Secret uses this to keep a tight
## stddev around its mean while occasionally rolling extreme outliers — a
## clamp draws the long tail back into [67, 1000] instead of into a narrow
## ±range band, which makes secret pulls feel volatile and exciting.
## Common's lower bound is additionally floored at MIN_PRICE so the player
## can never be paid negative coins.

const RARITY_PRICING: Dictionary = {
	"Common":       {"mean":   2, "range":   2},
	"Uncommon":     {"mean":   6, "range":   4},
	"Rare":         {"mean":  15, "range":  10},
	"Rare Holo":    {"mean":  20, "range":  10},
	"Rare Holo EX": {"mean":  50, "range":  25},
	"Rare Secret":  {"mean": 200, "range": 100, "min": 67, "max": 1000},
}

## Rarity tier order (low → high). The highest tier on a card wins the price.
const RARITY_ORDER: Array[String] = [
	"Common",
	"Uncommon",
	"Rare",
	"Rare Holo",
	"Rare Holo EX",
	"Rare Secret",
]

const MIN_PRICE: int = 0


static func appraise(card: CardData, rng: RandomNumberGenerator = null) -> int:
	if card == null:
		return MIN_PRICE
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var tier := highest_rarity(card)
	if not RARITY_PRICING.has(tier):
		return MIN_PRICE
	var p: Dictionary = RARITY_PRICING[tier]
	var mean: float = float(p["mean"])
	var range_: float = float(p["range"])
	var sigma: float = float(p.get("stddev", range_ / 2.0))
	var v: float = rng.randfn(mean, sigma)
	## Explicit min/max take precedence over the range-derived bounds so a
	## tier can keep a tight bell curve while still allowing rare outliers
	## (or hard-cap them). Common's lower bound stays floored at MIN_PRICE.
	var lower: int = max(MIN_PRICE, int(p.get("min", mean - range_)))
	var upper: int = int(p.get("max", mean + range_))
	return clampi(roundi(v), lower, upper)


static func highest_rarity(card: CardData) -> String:
	var best: String = ""
	var best_idx: int = -1
	for r in card.rarities:
		var s := str(r)
		var idx := RARITY_ORDER.find(s)
		if idx > best_idx:
			best = s
			best_idx = idx
	return best


static func mean_for(rarity: String) -> int:
	return int((RARITY_PRICING.get(rarity, {}) as Dictionary).get("mean", MIN_PRICE))


static func bounds_for(rarity: String) -> Vector2i:
	## Returns (min, max) integer bounds an appraisal will respect. Honors
	## explicit `min`/`max` overrides if present, otherwise falls back to
	## mean ± range. Useful for tests and tooltips.
	if not RARITY_PRICING.has(rarity):
		return Vector2i(MIN_PRICE, MIN_PRICE)
	var p: Dictionary = RARITY_PRICING[rarity]
	var mean: int = int(p["mean"])
	var range_: int = int(p["range"])
	var lower: int = max(MIN_PRICE, int(p.get("min", mean - range_)))
	var upper: int = int(p.get("max", mean + range_))
	return Vector2i(lower, upper)
